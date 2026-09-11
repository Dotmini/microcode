//
//  PlaygroundView.swift
//  MicroCode
//
//  Swift Playgrounds-style code playground with syntax highlighting
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//
//  Tirawat Nantamas | Dotmini Software | SPU AI CLUB
//

import SwiftUI
import WebKit
import UniformTypeIdentifiers

// MARK: - Data File Model

struct PlaygroundDataFile: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    var variableName: String {
        name.replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
}

struct PlaygroundView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var pythonEnvManager = PythonEnvManager.shared
    @ObservedObject private var runtimeManager = RuntimeManager.shared
    
    @State private var code: String = "print('Hello, Playground!')"
    @State private var language: String = "python"
    @State private var output: String = ""
    @State private var isExecuting: Bool = false
    @State private var autoRunEnabled: Bool = true
    @State private var autoRunTask: Task<Void, Never>?
    @State private var executionTime: Double = 0.0
    @State private var exitCode: Int = 0
    @State private var showingEnvManager: Bool = false
    @State private var showGUIPreview: Bool = false
    @State private var showOutput: Bool = true
    @State private var showDataFiles: Bool = false
    @State private var guiPreviewHTML: String = ""
    @State private var detectedGUIFramework: String?
    @State private var dataFiles: [PlaygroundDataFile] = []
    @State private var isDropTargeted: Bool = false
    @State private var swiftPreviewImage: NSImage?
    @State private var isPreviewLoading: Bool = false
    @State private var showingSettings: Bool = false
    
    // Live GUI & Dynamic SwiftUI Preview Support
    enum SwiftUIPreviewMode: String, CaseIterable {
        case interactive = "Interactive"
        case snapshot = "Snapshot"
    }
    @State private var swiftPreviewMode: SwiftUIPreviewMode = .interactive
    @State private var selectedPreviewDevice: PreviewDeviceType = .iPhone
    @State private var swiftPreviewDylibPath: String? = nil
    @State private var swiftPreviewTrigger: UUID = UUID()
    @State private var swiftPreviewError: String? = nil
    @State private var swiftPreviewZoom: CGFloat = 0.55
    @State private var isManualZoom: Bool = false
    @State private var responsiveScale: CGFloat = 0.55
    @State private var dylibCoordinator = SwiftUIPreviewCoordinator()
    
    // External GUI Process Control (Python Tkinter/PyQt, Rust egui, Go Gio, etc.)
    @State private var activeGUIProcess: Process? = nil
    @State private var isGUIRunning: Bool = false
    @State private var guiProcessPID: Int32? = nil
    @State private var guiProcessOutput: String = ""
    
    // Cell Mode Support
    @State private var isCellMode: Bool = false
    @State private var cells: [PlaygroundCellModel] = [PlaygroundCellModel(code: "print('Hello from Cell 1')", colorTheme: .none)]
    @State private var executionTask: Task<Void, Never>?
    @State private var currentMicroplayURL: URL? = nil
    
    // Document Mode Support
    @State private var showDocumentMode: Bool = false
    @State private var documentURL: URL?
    @State private var isDocumentPiP: Bool = false
    
    // All languages supported by backend runner
    let supportedLanguages = [
        "python", "r", "julia", "ruby",            // Scripting
        "swift", "objective-c", "objective-c++",   // Apple
        "rust", "go", "c", "c++", "d",             // Systems
        "javascript", "typescript",                 // Web
        "java", "kotlin",                          // JVM
        "lua", "perl", "php",                      // Other Scripting
        "sql", "shell", "bash",                    // Data/DevOps
        "ardium",                                   // Custom
        "latex", "markdown"                        // Document (with preview)
    ]
    
    // Playground data directory
    private var playgroundDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PlaygroundData")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            playgroundToolbar
            
            Divider()
            
            // Main Content
            if showDocumentMode && !isDocumentPiP {
                DraggableSplitView(initialProportion: 0.3) {
                    DocumentViewer(documentURL: $documentURL, isPiPActive: $isDocumentPiP)
                        .frame(minWidth: 200)
                } right: {
                    mainAndRightPane
                }
            } else {
                mainAndRightPane
            }
        }
        .onAppear {
            CrashReporter.shared.breadcrumb("PlaygroundView.onAppear lang=\(language) cellMode=\(isCellMode)")
            print("🚀 PlaygroundView: onAppear triggered")
            
            // Check if code was exported from AI Agent
            if let exportedCode = appState.aiExportedCode, !exportedCode.isEmpty {
                code = exportedCode
                appState.aiExportedCode = nil // Clear after consuming
                print("🚀 PlaygroundView: Loaded code from AI Agent")
            } else if let saved = UserDefaults.standard.string(forKey: "microcode_playground_code_\(language)"),
                      !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Restore the user's last Playground work (autosave) so it is
                // never lost between launches.
                code = saved
            } else if code == "print('Hello, Playground!')" {
                updateDefaultCode(for: language)
            }
            
            // Sync language from AppState
            if !appState.selectedLanguage.isEmpty && appState.selectedLanguage != language {
                language = appState.selectedLanguage
            }

            if language == "swift" && (code.contains("import SwiftUI") || code.contains("struct ContentView: View") || code.contains(": View")) {
                showGUIPreview = true
                showOutput = false
            }
            
            // Ensure directory exists asynchronously
            Task {
                try? FileManager.default.createDirectory(at: playgroundDirectory, withIntermediateDirectories: true)
                print("🚀 PlaygroundView: Verified directory at \(playgroundDirectory.path)")
            }
            runtimeManager.detectAll()
        }
        .onChange(of: isDocumentPiP) { newValue in
            if newValue && showDocumentMode {
                PiPWindowManager.shared.show(documentURL: documentURL, onClose: {
                    isDocumentPiP = false
                })
            } else {
                PiPWindowManager.shared.close()
            }
        }
        .sheet(isPresented: $showingEnvManager) {
            PythonEnvSheet()
        }
    }
    
    @ViewBuilder
    private var mainAndRightPane: some View {
        if showOutput || showGUIPreview {
            DraggableSplitView(initialProportion: 0.55) {
                centerPane
            } right: {
                rightPane
            }
        } else {
            centerPane
        }
    }
    
    private var centerPane: some View {
        VStack(spacing: 0) {
            if showDataFiles {
                dataFilesPanel
                    .frame(minHeight: 150, maxHeight: 300)
                Divider()
            }
            
            codeEditorPanel
        }
        .frame(maxWidth: .infinity)
    }
    
    private var rightPane: some View {
        VStack(spacing: 0) {
            if showGUIPreview {
                guiPreviewPanel
                    .frame(minHeight: 200)
            }
            
            if showGUIPreview && showOutput {
                Divider()
            }
            
            if showOutput {
                outputPanel
                    .frame(minHeight: 100, maxHeight: showGUIPreview ? .infinity : .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Toolbar
    
    private var playgroundToolbar: some View {
        HStack(spacing: 8) {
            // Language Selector
            Menu {
                ForEach(supportedLanguages, id: \.self) { lang in
                    Button(lang.capitalized) {
                        language = lang
                        updateDefaultCode(for: lang)
                        // Auto-show preview for latex, markdown, or swift
                        if lang == "latex" || lang == "markdown" || lang == "swift" {
                            showGUIPreview = true
                            showOutput = false
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: languageIcon(language))
                        .foregroundColor(.accentColor)
                    Text(language.capitalized)
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(controlBackground)
                )
            }
            .buttonStyle(.plain)
            
            // Settings Button
            Button(action: { showingSettings.toggle() }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(controlBackground)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingSettings) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Playground Settings")
                        .font(.headline)
                    
                    Divider()
                    
                    // Font Size
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Font Size: \(Int(appState.playgroundFontSize))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $appState.playgroundFontSize, in: 10...24, step: 1)
                    }
                    
                    // Font Family
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Font Family")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: $appState.playgroundFontName) {
                            Text("Menlo").tag("Menlo")
                            Text("Monaco").tag("Monaco")
                            Text("Courier New").tag("Courier New")
                            Text("SF Mono").tag("SF Mono")
                            Text("JetBrains Mono").tag("JetBrains Mono")
                            Text("Fira Code").tag("Fira Code")
                        }
                        .labelsHidden()
                    }
                    
                    // Theme
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Theme")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: $appState.appTheme) {
                            ForEach(AppTheme.allCases, id: \.self) { theme in
                                Text(theme.displayName).tag(theme)
                            }
                        }
                        .labelsHidden()
                    }
                }
                .padding(14)
                .frame(width: 250)
            }
            
            // Python Environment Selector
            if language == "python" {
                pythonEnvMenu
            }

            if let runtime = playgroundRuntime(for: language) {
                runtimeEnvironmentMenu(for: runtime)
            }
            
            if ["javascript", "typescript"].contains(language.lowercased()) {
                NodeVersionPicker()
            }
            
            Divider()
                .frame(height: 16)
            
            // Playground Mode Switcher (Single Code vs Cell Mode)
            Picker("", selection: $isCellMode) {
                Text("Editor").tag(false)
                Text("Cell Mode").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            
            // Open .microplay
            Button(action: { openMicroplayFile() }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.badge.gearshape")
                    Text("Open")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(controlBackground)
                )
            }
            .buttonStyle(.plain)
            .help("Open .microplay file")
            
            // Save .microplay
            Button(action: { saveMicroplayFile() }) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(controlBackground)
                )
            }
            .buttonStyle(.plain)
            .help("Save as .microplay file")
            
            // Document Mode Toggle Button
            Button(action: { showDocumentMode.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.fill")
                    Text("Document")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(showDocumentMode ? .white : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(showDocumentMode ? Color.white.opacity(0.16) : controlBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(showDocumentMode ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Data Files Toggle
            Button(action: { showDataFiles.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text("Data")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(showDataFiles ? .white : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(showDataFiles ? Color.white.opacity(0.16) : controlBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(showDataFiles ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            
            // Output Toggle
            Button(action: { showOutput.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                    Text("Output")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(showOutput ? .white : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(showOutput ? Color.white.opacity(0.16) : controlBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(showOutput ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            
            // GUI Preview Toggle
            Button(action: { showGUIPreview.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                    Text("Preview")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(showGUIPreview ? .white : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(showGUIPreview ? Color.white.opacity(0.16) : controlBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(showGUIPreview ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            
            Divider()
                .frame(height: 16)
            
            // Auto-run toggle
            Toggle("Auto-run", isOn: $autoRunEnabled)
                .font(.system(size: 11))
                .toggleStyle(.switch)
                .controlSize(.small)
            
            // Live Preview (Hot Reload) toggle
            Button(action: { HotReloadService.shared.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                    Text("Hot Reload")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(HotReloadService.shared.isEnabled ? .white : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(HotReloadService.shared.isEnabled ? Color.white.opacity(0.16) : controlBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(HotReloadService.shared.isEnabled ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            
            // Execution stats
            if executionTime > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                        .font(.system(size: 10))
                    Text("\(String(format: "%.2f", executionTime))s")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(controlBackground)
                )
            }
            
            // Run/Stop button (Sleek Dark Monochrome Action Button)
            Button(action: {
                if isExecuting {
                    executionTask?.cancel()
                    autoRunTask?.cancel()
                    isExecuting = false
                } else {
                    executionTask = Task {
                        await runCode()
                    }
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: isExecuting ? "stop.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(isExecuting ? "Stop" : "Run")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(isExecuting ? Color(red: 1.0, green: 0.45, blue: 0.45) : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isExecuting ? Color(red: 0.35, green: 0.1, blue: 0.1) : Color(white: 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(isExecuting ? Color.red.opacity(0.4) : Color.white.opacity(0.22), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: [.command])
            
            // Clear output
            Button(action: {
                output = ""
                executionTime = 0
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(controlBackground)
                    )
            }
            .buttonStyle(.plain)
            .help("Clear Output")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(panelBackground)
    }
    
    // MARK: - Code Editor Panel
    
    private var editorBackground: Color {
        appState.appTheme == .transparent ? .clear : Color(nsColor: appState.appTheme.editorBackground)
    }
    
    private var editorText: Color {
        Color(nsColor: appState.appTheme.editorText)
    }
    
    private var lineNumberColor: Color {
        Color(nsColor: appState.appTheme.commentColor)
    }
    
    private var panelBackground: Color {
        if appState.appTheme == .transparent {
            return Color.white.opacity(0.05)
        }
        return Color(nsColor: appState.appTheme.workspaceBackground)
    }
    
    private var controlBackground: Color {
        if appState.appTheme == .transparent {
            return Color.white.opacity(0.08)
        }
        return Color(nsColor: appState.appTheme.editorBackground).opacity(0.85)
    }
    
    private var codeEditorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isCellMode {
                cellModeContent
            } else {
                codeEditorContent
            }
        }
    }
    
    private var cellModeContent: some View {
        VStack(spacing: 0) {
            // Cell Mode Action Header
            HStack {
                Text("Cell Mode (\(cells.count) cells)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { runAllCells() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Run All")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(white: 0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    let newCell = PlaygroundCellModel(code: "# New Cell\n", colorTheme: .none)
                    cells.append(newCell)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Cell")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(controlBackground)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(panelBackground)
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(cells) { cell in
                        PlaygroundCellView(
                            cell: cell,
                            language: language,
                            onRun: { runCell(cell) },
                            onDelete: {
                                if cells.count > 1 {
                                    cells.removeAll { $0.id == cell.id }
                                }
                            }
                        )
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var codeEditorHeader: some View {
        HStack {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .foregroundColor(.accentColor)
            Text("Code")
                .font(.system(size: 11, weight: .semibold))
            
            Spacer()
            
            if let framework = detectedGUIFramework {
                frameworkBadge(framework)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(panelBackground)
    }
    
    private func frameworkBadge(_ framework: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "macwindow")
                .foregroundColor(.secondary)
            Text(framework)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.08))
        .cornerRadius(4)
    }
    
    private var codeEditorContent: some View {
        // Code editor with syntax highlighting
        SyntaxHighlightedCodeView(
            text: $code,
            language: language,
            fontSize: appState.playgroundFontSize,
            isDark: appState.appTheme.isDark,
            themeName: appState.appTheme.rawValue,
            fontName: appState.playgroundFontName,
            fontWeight: appState.playgroundFontWeight,
            showLineNumbers: appState.showLineNumbers,
            editorID: "playground-main"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: code) { newValue in
            // Realtime autosave so Playground work is never lost.
            UserDefaults.standard.set(newValue, forKey: "microcode_playground_code_\(language)")

            // Immediate Clear on Empty
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                coordinatorTask?.cancel()
                executionTask?.cancel()
                output = ""
                isExecuting = false
                detectedGUIFramework = nil
                pythonEnvManager.detectedPackages = []
                return
            }

            handleCodeChange()
        }
    }
    
    
    // MARK: - Output Panel
    
    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with title, clear, and close buttons
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "terminal")
                        .foregroundColor(.secondary)
                        .font(.system(size: 10))
                    Text("Output")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !output.isEmpty {
                    Button(action: { output = "" }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear Output")
                }

                Button(action: { showOutput = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close Output")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(panelBackground)

            Divider()

            PlaygroundTerminalView(
                text: $output,
                fontSize: $appState.playgroundFontSize,
                theme: appState.appTheme
            )
            .padding(4)
            .background(editorBackground)
            .clipped()
        }
    }
    
    // MARK: - Data Files Panel
    
    private var dataFilesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.orange)
                Text("Data Files")
                    .font(.system(size: 11, weight: .semibold))
                
                Spacer()
                
                // Clear all button
                if !dataFiles.isEmpty {
                    Button(action: clearDataFiles) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Clear all data files")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(panelBackground)
            
            Divider()
            
            // Drop Zone
            VStack(spacing: 12) {
                if dataFiles.isEmpty {
                    // Drop hint
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 36))
                            .foregroundColor(isDropTargeted ? .orange : .secondary)
                        
                        Text("Drop Files Here")
                            .font(.headline)
                            .foregroundColor(isDropTargeted ? .orange : .secondary)
                        
                        Text("CSV, JSON, TXT, Images...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .foregroundColor(isDropTargeted ? .orange : .secondary.opacity(0.5))
                    )
                    .padding(12)
                } else {
                    // File list
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(dataFiles) { file in
                                dataFileRow(file)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(editorBackground)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleFileDrop(providers)
            }
        }
    }
    
    private func dataFileRow(_ file: PlaygroundDataFile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: fileIcon(for: file.name))
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                Text(file.variableName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Insert path button
            Button(action: { insertFilePath(file) }) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.green)
            }
            .buttonStyle(.borderless)
            .help("Insert file path in code")
            
            // Remove button
            Button(action: { removeDataFile(file) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove file")
        }
        .padding(8)
        .background(controlBackground)
        .cornerRadius(6)
    }
    
    private func fileIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "csv": return "tablecells"
        case "json": return "curlybraces"
        case "txt", "text": return "doc.text"
        case "png", "jpg", "jpeg", "gif", "heic": return "photo"
        case "pdf": return "doc.richtext"
        case "xlsx", "xls": return "tablecells.fill"
        case "py": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
    
    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let sourceURL = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
                DispatchQueue.main.async {
                    copyFileToPlayground(sourceURL)
                }
            }
        }
        return true
    }
    
    private func copyFileToPlayground(_ sourceURL: URL) {
        let filename = sourceURL.lastPathComponent
        let destURL = playgroundDirectory.appendingPathComponent(filename)
        
        do {
            // Remove existing file if exists
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            
            // Copy file
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            
            // Add to data files
            let file = PlaygroundDataFile(name: filename, url: destURL)
            dataFiles.append(file)
            
            // Auto-insert path in code
            insertFilePath(file)
            
            output += "📁 Added: \(filename)\n"
        } catch {
            output += "❌ Failed to copy \(filename): \(error.localizedDescription)\n"
        }
    }
    
    private func insertFilePath(_ file: PlaygroundDataFile) {
        let pathCode: String
        
        switch language {
        case "python":
            pathCode = "\(file.variableName) = r'\(file.url.path)'\n"
        case "javascript", "typescript":
            pathCode = "const \(file.variableName) = '\(file.url.path)';\n"
        case "swift":
            pathCode = "let \(file.variableName) = URL(fileURLWithPath: \"\(file.url.path)\")\n"
        case "rust":
            pathCode = "let \(file.variableName) = std::path::Path::new(\"\(file.url.path)\");\n"
        case "go":
            pathCode = "\(file.variableName) := \"\(file.url.path)\"\n"
        case "d":
            pathCode = "string \(file.variableName) = \"\(file.url.path)\";\n"
        default:
            pathCode = "// \(file.variableName) = \"\(file.url.path)\"\n"
        }
        
        // Insert at beginning or after existing path declarations
        if let range = code.range(of: "# Files") {
            code.insert(contentsOf: pathCode, at: range.upperBound)
        } else {
            // Add header and path at beginning
            code = "# Files\n\(pathCode)\n\(code)"
        }
    }
    
    private func removeDataFile(_ file: PlaygroundDataFile) {
        dataFiles.removeAll { $0.id == file.id }
        try? FileManager.default.removeItem(at: file.url)
    }
    
    private func clearDataFiles() {
        for file in dataFiles {
            try? FileManager.default.removeItem(at: file.url)
        }
        dataFiles.removeAll()
    }
    
    // MARK: - GUI Preview Panel
    
    private var guiPreviewPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — only for SwiftUI preview (needs Refresh) or GUI frameworks.
            if language != "latex" && language != "markdown" {
                HStack(spacing: 8) {
                    if language == "swift" && detectedGUIFramework == "SwiftUI" {
                        HStack(spacing: 6) {
                            Image(systemName: "swift")
                                .foregroundColor(.orange)
                            Text("Preview")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()

                            Picker("", selection: $swiftPreviewMode) {
                                Text("Live").tag(SwiftUIPreviewMode.interactive)
                                Text("Snapshot").tag(SwiftUIPreviewMode.snapshot)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                            .fixedSize()

                            Picker("", selection: $selectedPreviewDevice) {
                                ForEach(PreviewDeviceType.allCases) { dev in
                                    Text(dev.shortName).tag(dev)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 130)
                            .fixedSize()
                            .onChange(of: selectedPreviewDevice) { _ in
                                isManualZoom = false
                                renderSwiftUIPreview()
                            }

                            HStack(spacing: 2) {
                                Button {
                                    isManualZoom = true
                                    swiftPreviewZoom = max(0.25, (isManualZoom ? swiftPreviewZoom : responsiveScale) - 0.05)
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .buttonStyle(.plain)

                                Text("\(Int(round((isManualZoom ? swiftPreviewZoom : responsiveScale) * 100)))%")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 32)
                                    .lineLimit(1)

                                Button {
                                    isManualZoom = true
                                    swiftPreviewZoom = min(1.2, (isManualZoom ? swiftPreviewZoom : responsiveScale) + 0.05)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .buttonStyle(.plain)

                                Button("Fit") {
                                    withAnimation(.spring(response: 0.25)) {
                                        isManualZoom = false
                                    }
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 9, weight: isManualZoom ? .regular : .bold))
                                .foregroundColor(isManualZoom ? .secondary : .accentColor)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(5)
                            .fixedSize()
                        }
                    } else if let framework = detectedGUIFramework {
                        Image(systemName: frameworkIcon(for: framework))
                            .foregroundColor(frameworkColor(for: framework))
                        Text("\(framework) Preview")
                            .font(.system(size: 11, weight: .semibold))

                        if isGUIRunning {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text("Running (PID: \(guiProcessPID ?? 0))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(4)
                        }
                    } else {
                        Image(systemName: "macwindow")
                            .foregroundColor(.secondary)
                        Text("GUI Preview")
                            .font(.system(size: 11, weight: .semibold))
                    }

                    Spacer(minLength: 4)

                    if isPreviewLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    }

                    if language == "swift" && detectedGUIFramework == "SwiftUI" {
                        Button {
                            renderSwiftUIPreview()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh Preview")

                        Button {
                            showGUIPreview = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Close Preview")
                    } else if detectedGUIFramework != nil {
                        if isGUIRunning {
                            Button(action: stopGUIApp) {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .controlSize(.small)
                            .font(.system(size: 10))

                            Button(action: launchGUIApp) {
                                Label("Rerun", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .font(.system(size: 10))
                        } else {
                            Button(action: launchGUIApp) {
                                Label("Launch GUI", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .font(.system(size: 10))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(panelBackground)

                Divider()
            }

            // LaTeX Real-time Preview
            if language == "latex" {
                LaTeXPreviewWebView(latexCode: code)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Markdown Real-time Preview
            else if language == "markdown" {
                MarkdownPreviewWebView(markdown: code)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Preview Content
            else if language == "swift" && detectedGUIFramework == "SwiftUI" {
                // Real SwiftUI Preview in Centered, Fully-Responsive Canvas
                GeometryReader { proxy in
                    let availableWidth = proxy.size.width
                    let availableHeight = proxy.size.height
                    let targetFrameWidth = selectedPreviewDevice.frameWidth
                    let targetFrameHeight = selectedPreviewDevice.frameHeight
                    let autoScale = max(0.20, min(0.85, min((availableWidth - 24) / targetFrameWidth, (availableHeight - 48) / targetFrameHeight)))
                    let currentScale = isManualZoom ? swiftPreviewZoom : autoScale
                    let hasPreview = (swiftPreviewMode == .interactive && swiftPreviewDylibPath != nil) || swiftPreviewImage != nil

                    ZStack {
                        GridBackground()

                        VStack(spacing: 8) {
                            Group {
                                if selectedPreviewDevice == .iPhone {
                                    iPhoneFrameView(
                                        content: {
                                            previewInnerContent(hasPreview: hasPreview)
                                        },
                                        deviceType: .iPhone15Pro,
                                        colorScheme: appState.appTheme.isDark ? .dark : .light
                                    )
                                } else {
                                    iPadFrameView(
                                        content: {
                                            previewInnerContent(hasPreview: hasPreview)
                                        },
                                        colorScheme: appState.appTheme.isDark ? .dark : .light
                                    )
                                }
                            }
                            .scaleEffect(currentScale)
                            .frame(width: targetFrameWidth * currentScale, height: targetFrameHeight * currentScale)

                            Text("\(selectedPreviewDevice.displayName) (\(Int(round(currentScale * 100)))%)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: availableWidth, height: availableHeight)
                    .clipped()
                    .onAppear {
                        responsiveScale = autoScale
                    }
                    .onChange(of: autoScale) { newScale in
                        responsiveScale = newScale
                    }
                }
            } else if let framework = detectedGUIFramework {
                VStack(spacing: 0) {
                    // GUI Control Deck
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(frameworkColor(for: framework).opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: frameworkIcon(for: framework))
                                    .font(.system(size: 20))
                                    .foregroundColor(frameworkColor(for: framework))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(framework) Desktop Application")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(isGUIRunning ? "Process active on macOS display" : "Click 'Launch GUI' to run window")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if isGUIRunning {
                                Button(action: stopGUIApp) {
                                    Label("Stop", systemImage: "stop.fill")
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)

                                Button(action: launchGUIApp) {
                                    Label("Rerun", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button(action: launchGUIApp) {
                                    Label("Launch GUI", systemImage: "play.fill")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                    .padding(12)

                    Divider()

                    // Live GUI Output Console
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("GUI PROCESS LOGS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            if !guiProcessOutput.isEmpty {
                                Button("Clear") {
                                    guiProcessOutput = ""
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                        ScrollView {
                            Text(guiProcessOutput.isEmpty ? "No logs yet. Launch GUI to see stdout/stderr." : guiProcessOutput)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(guiProcessOutput.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(6)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(panelBackground)
            } else {
                // No GUI detected
                VStack(spacing: 12) {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Text("No GUI Detected")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    if language == "swift" {
                        Text("Add 'import SwiftUI' to enable preview")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Import a GUI framework (Tkinter, PyQt, egui, Fyne, etc.) to see preview")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(panelBackground)
            }
        }
    }

    @ViewBuilder
    private func previewInnerContent(hasPreview: Bool) -> some View {
        let targetWidth = selectedPreviewDevice.screenWidth
        let targetHeight = selectedPreviewDevice.screenHeight

        ZStack {
            Color.black
                .ignoresSafeArea()

            if swiftPreviewMode == .interactive && swiftPreviewDylibPath != nil {
                DynamicSwiftUIView(
                    dylibPath: swiftPreviewDylibPath,
                    trigger: swiftPreviewTrigger,
                    coordinator: dylibCoordinator,
                    onError: { err in
                        swiftPreviewError = err
                    }
                )
                .frame(width: targetWidth, height: targetHeight)
            } else if let image = swiftPreviewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: targetWidth, height: targetHeight)
            } else if !isPreviewLoading && swiftPreviewError == nil {
                VStack(spacing: 16) {
                    Image(systemName: "swift")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("SwiftUI Live Preview")
                        .font(.headline)

                    Text(swiftPreviewMode == .interactive ? "Sub-second Dynamic Loading" : "High-res Image Snapshot")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(swiftPreviewMode == .interactive ? "▶ Compile & Run Live" : "▶ Render Snapshot") {
                        renderSwiftUIPreview()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }

            // Zero-flicker loading overlay (Only full screen progress if no preview has ever been loaded)
            if isPreviewLoading {
                if hasPreview {
                    // Discreet bottom-right compilation pill; existing preview stays rock-solid
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Updating...")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .padding(.bottom, selectedPreviewDevice.bottomInset + 8)
                    }
                    .transition(.opacity)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(swiftPreviewMode == .interactive ? "Compiling dynamic library..." : "Rendering snapshot...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }
            }

            // Non-destructive error banner (if preview exists, show soft banner; else show full error screen)
            if let errorMsg = swiftPreviewError {
                if hasPreview {
                    VStack {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.yellow)
                            Text(errorMsg.components(separatedBy: "\n").first ?? "Compilation warning")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            Spacer()
                            Button("Retry") {
                                renderSwiftUIPreview()
                            }
                            .font(.system(size: 9))
                            .buttonStyle(.bordered)
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(.horizontal, 12)
                        .padding(.top, selectedPreviewDevice.topInset + 4)

                        Spacer()
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.yellow)
                        Text("Preview Compilation Error")
                            .font(.headline)
                        ScrollView {
                            Text(errorMsg)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.red)
                                .padding(8)
                        }
                        .frame(maxHeight: 140)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)

                        HStack {
                            Button("Retry") {
                                renderSwiftUIPreview()
                            }
                            .buttonStyle(.borderedProminent)

                            if swiftPreviewMode == .interactive {
                                Button("Switch to Snapshot") {
                                    swiftPreviewMode = .snapshot
                                    renderSwiftUIPreview()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }
            }
        }
        .frame(width: targetWidth, height: targetHeight)
    }

    /// Compile and render SwiftUI code (Live Dylib or Snapshot)
    private func renderSwiftUIPreview() {
        isPreviewLoading = true
        swiftPreviewError = nil
        output = "🔨 Compiling SwiftUI code...\n"

        Task {
            if swiftPreviewMode == .interactive {
                do {
                    let dylibPath = try await compileSwiftUIDylib(code: code)
                    await MainActor.run {
                        self.swiftPreviewDylibPath = dylibPath
                        self.swiftPreviewTrigger = UUID()
                        self.isPreviewLoading = false
                        self.output += "✅ Live interactive preview loaded successfully\n"
                    }
                } catch {
                    await MainActor.run {
                        self.swiftPreviewError = error.localizedDescription
                        self.isPreviewLoading = false
                        self.output += "❌ Interactive compilation error: \(error.localizedDescription)\n"
                    }
                }
            } else {
                do {
                    let image = try await compileAndRenderSwiftUI(code: code)
                    await MainActor.run {
                        self.swiftPreviewImage = image
                        self.isPreviewLoading = false
                        self.output += "✅ Snapshot preview rendered successfully\n"
                    }
                } catch {
                    await MainActor.run {
                        self.swiftPreviewError = error.localizedDescription
                        self.isPreviewLoading = false
                        self.output += "❌ Snapshot error: \(error.localizedDescription)\n"
                    }
                }
            }
        }
    }

    /// Compile SwiftUI code to dynamic library for in-memory live rendering
    private func compileSwiftUIDylib(code: String) async throws -> String {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftUIDylib_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let wrapperCode = generateDynamicWrapper(userCode: code)
        let sourceFile = tempDir.appendingPathComponent("PreviewDynamic.swift")
        let dylibFile = tempDir.appendingPathComponent("libpreview_\(UUID().uuidString.prefix(8)).dylib")

        try wrapperCode.write(to: sourceFile, atomically: true, encoding: .utf8)

        let compileResult = try await runProcess(
            executable: "/usr/bin/env",
            arguments: [
                "swiftc",
                "-emit-library",
                "-o", dylibFile.path,
                "-framework", "SwiftUI",
                "-framework", "AppKit",
                sourceFile.path
            ],
            currentDirectory: tempDir
        )

        if !compileResult.success {
            throw NSError(domain: "SwiftUIPreview", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Compilation failed:\n\(compileResult.stderr)"
            ])
        }

        guard FileManager.default.fileExists(atPath: dylibFile.path) else {
            throw NSError(domain: "SwiftUIPreview", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Dynamic library was not generated"
            ])
        }

        return dylibFile.path
    }

    /// Detect the primary root View struct to render
    private func detectMainViewName(in code: String) -> String {
        // 1. If #Preview { SomeView(...) } exists, extract SomeView
        let previewMacroPattern = #"#Preview\s*(?:\([^)]*\))?\s*\{\s*([A-Za-z0-9_]+)\s*\("#
        if let regex = try? NSRegularExpression(pattern: previewMacroPattern, options: []),
           let match = regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)),
           let range = Range(match.range(at: 1), in: code) {
            return String(code[range])
        }

        // 2. Find all structs conforming to View
        let structPattern = #"struct\s+(\w+)\s*:\s*(?:[^{]*\b)?View\b"#
        guard let regex = try? NSRegularExpression(pattern: structPattern, options: []) else {
            return "ContentView"
        }

        let matches = regex.matches(in: code, range: NSRange(code.startIndex..., in: code))
        let names = matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: code) else { return nil }
            return String(code[range])
        }

        if names.isEmpty { return "ContentView" }
        if names.contains("ContentView") { return "ContentView" }
        if names.contains("MainView") { return "MainView" }
        if names.contains("RootView") { return "RootView" }

        // Filter out typical subview/row/cell names that need bindings or parameters
        let mainCandidates = names.filter { name in
            !name.hasSuffix("RowView") &&
            !name.hasSuffix("Row") &&
            !name.hasSuffix("Cell") &&
            !name.hasSuffix("ItemView") &&
            !name.hasSuffix("Badge") &&
            !name.hasSuffix("Card")
        }

        return mainCandidates.first ?? names.first ?? "ContentView"
    }

    /// Provide iOS UIKit/SwiftUI compatibility shims and sanitize code for macOS compilation
    private func sanitizeSwiftUICodeForMacOS(_ userCode: String) -> (cleanedCode: String, shims: String) {
        let shims = """
        typealias UIColor = NSColor
        extension NSColor {
            static var secondarySystemBackground: NSColor { NSColor(white: 0.11, alpha: 1.0) }
            static var systemBackground: NSColor { .black }
            static var tertiarySystemBackground: NSColor { NSColor(white: 0.16, alpha: 1.0) }
            static var systemGroupedBackground: NSColor { .black }
            static var secondarySystemGroupedBackground: NSColor { NSColor(white: 0.11, alpha: 1.0) }
            static var tertiarySystemGroupedBackground: NSColor { NSColor(white: 0.16, alpha: 1.0) }
            static var systemGray: NSColor { labelColor }
            static var systemGray2: NSColor { secondaryLabelColor }
            static var systemGray3: NSColor { separatorColor }
            static var systemGray4: NSColor { NSColor(white: 0.22, alpha: 1.0) }
            static var systemGray5: NSColor { NSColor(white: 0.18, alpha: 1.0) }
            static var systemGray6: NSColor { NSColor(white: 0.12, alpha: 1.0) }
            static var placeholderText: NSColor { placeholderTextColor }
        }

        extension Color {
            init(_ uiColor: NSColor) { self.init(nsColor: uiColor) }
            static var secondarySystemBackground: Color { Color(white: 0.11) }
            static var systemBackground: Color { Color.black }
            static var tertiarySystemBackground: Color { Color(white: 0.16) }
            static var systemGroupedBackground: Color { Color.black }
            static var secondarySystemGroupedBackground: Color { Color(white: 0.11) }
            static var tertiarySystemGroupedBackground: Color { Color(white: 0.16) }
            static var systemGray: Color { Color(NSColor.labelColor) }
            static var systemGray2: Color { Color(NSColor.secondaryLabelColor) }
            static var systemGray3: Color { Color(NSColor.separatorColor) }
            static var systemGray4: Color { Color(white: 0.22) }
            static var systemGray5: Color { Color(white: 0.18) }
            static var systemGray6: Color { Color(white: 0.12) }
        }
        """

        var cleaned = userCode
        cleaned = cleaned.replacingOccurrences(of: "@main\n", with: "// @main (disabled)\n")
        cleaned = cleaned.replacingOccurrences(of: "@main ", with: "// @main (disabled) ")
        cleaned = cleaned.replacingOccurrences(of: ".listStyle(.insetGrouped)", with: ".listStyle(.inset)")
        cleaned = cleaned.replacingOccurrences(of: ".listStyle(.grouped)", with: ".listStyle(.inset)")
        cleaned = cleaned.replacingOccurrences(of: "EditButton()", with: "Button(\"Edit\") {}")
        cleaned = cleaned.replacingOccurrences(of: ".navigationBarTitleDisplayMode(.inline)", with: "")
        cleaned = cleaned.replacingOccurrences(of: ".navigationBarTitleDisplayMode(.large)", with: "")
        cleaned = cleaned.replacingOccurrences(of: ".navigationBarTitleDisplayMode(.automatic)", with: "")
        cleaned = cleaned.replacingOccurrences(of: ".navigationBarBackButtonHidden(true)", with: "")
        cleaned = cleaned.replacingOccurrences(of: ".navigationBarBackButtonHidden(false)", with: "")
        cleaned = cleaned.replacingOccurrences(of: ".navigationBarHidden(true)", with: "")
        cleaned = cleaned.replacingOccurrences(of: ".navigationBarHidden(false)", with: "")
        cleaned = cleaned.replacingOccurrences(of: ".topBarTrailing", with: ".automatic")
        cleaned = cleaned.replacingOccurrences(of: ".topBarLeading", with: ".automatic")
        cleaned = cleaned.replacingOccurrences(of: ".navigationBarTrailing", with: ".automatic")
        cleaned = cleaned.replacingOccurrences(of: ".navigationBarLeading", with: ".automatic")
        cleaned = cleaned.replacingOccurrences(of: ".bottomBar", with: ".automatic")

        return (cleaned, shims)
    }

    /// Generate dynamic library wrapper with C-ABI entry point
    private func generateDynamicWrapper(userCode: String) -> String {
        let viewName = detectMainViewName(in: userCode)
        let (cleanedCode, shims) = sanitizeSwiftUICodeForMacOS(userCode)
        let topInset = selectedPreviewDevice.topInset
        let bottomInset = selectedPreviewDevice.bottomInset

        return """
        import SwiftUI
        import AppKit

        // iOS UIKit & SwiftUI Compatibility Shims for macOS
        \(shims)

        // User's SwiftUI Code
        \(cleanedCode)

        // Dynamic C-ABI Bridge
        @_cdecl("microcode_create_preview")
        public func microcode_create_preview() -> UnsafeMutableRawPointer {
            let view = \(viewName)()
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: \(topInset))
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: \(bottomInset))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            let hostingView = NSHostingView(rootView: AnyView(view))
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.black.cgColor
            return Unmanaged.passRetained(hostingView).toOpaque()
        }
        """
    }

    /// Launch external GUI application process (Python Tkinter/PyQt, Rust egui, Go Gio, etc.)
    private func launchGUIApp() {
        stopGUIApp()
        let framework = detectedGUIFramework ?? "GUI"
        guiProcessOutput = "🚀 Launching \(framework) Application...\n"
        isGUIRunning = true

        Task {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MicroCode_GUI_\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let ext = appState.fileExtension(for: language)
            let scriptPath = tempDir.appendingPathComponent("main.\(ext)")
            try? code.write(to: scriptPath, atomically: true, encoding: .utf8)

            let process = Process()
            var executable = "/usr/bin/env"
            var arguments: [String] = []

            switch language {
            case "python":
                let pyPath = pythonEnvManager.activeEnvironment?.pythonPath ?? appState.selectedPythonVersion
                executable = pythonEnvManager.resolveExecutablePath(pyPath)
                arguments = [scriptPath.path]
            case "rust":
                let binPath = tempDir.appendingPathComponent("gui_bin")
                await MainActor.run {
                    self.guiProcessOutput += "🔨 Compiling Rust binary with rustc...\n"
                }
                let compileResult = try? await runProcess(
                    executable: "/usr/bin/env",
                    arguments: ["rustc", scriptPath.path, "-o", binPath.path],
                    currentDirectory: tempDir
                )
                if compileResult?.success != true {
                    await MainActor.run {
                        self.guiProcessOutput += "❌ Rust compilation failed:\n\(compileResult?.stderr ?? "")\n"
                        self.isGUIRunning = false
                    }
                    return
                }
                executable = binPath.path
                arguments = []
            case "go":
                executable = "/usr/bin/env"
                arguments = ["go", "run", scriptPath.path]
            default:
                executable = "/usr/bin/env"
                arguments = [language, scriptPath.path]
            }

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = tempDir

            var env = ProcessInfo.processInfo.environment
            let home = NSHomeDirectory()
            let extraPaths = [
                "/opt/homebrew/bin",
                "/opt/homebrew/sbin",
                "/usr/local/bin",
                "\(home)/.cargo/bin",
                "\(home)/.swiftly/bin",
                "/opt/homebrew/opt/openjdk@21/bin",
                "/opt/homebrew/opt/openjdk/bin",
                "/Applications/Xcode.app/Contents/Developer/usr/bin",
                "/Applications/Xcode-beta.app/Contents/Developer/usr/bin",
                "/Volumes/MAC/Xcode-beta 2.app/Contents/Developer/usr/bin"
            ]
            let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.guiProcessOutput += text
                    }
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.guiProcessOutput += text
                    }
                }
            }

            do {
                try process.run()
                await MainActor.run {
                    self.activeGUIProcess = process
                    self.guiProcessPID = process.processIdentifier
                    self.guiProcessOutput += "✅ Process started with PID: \(process.processIdentifier)\n"
                }

                process.waitUntilExit()

                await MainActor.run {
                    self.isGUIRunning = false
                    self.activeGUIProcess = nil
                    self.guiProcessPID = nil
                    self.guiProcessOutput += "\n🏁 GUI Process exited with code: \(process.terminationStatus)\n"
                }
            } catch {
                await MainActor.run {
                    self.isGUIRunning = false
                    self.activeGUIProcess = nil
                    self.guiProcessPID = nil
                    self.guiProcessOutput += "❌ Failed to start GUI process: \(error.localizedDescription)\n"
                }
            }
        }
    }

    /// Terminate active external GUI process
    private func stopGUIApp() {
        if let proc = activeGUIProcess, proc.isRunning {
            proc.terminate()
            activeGUIProcess = nil
            isGUIRunning = false
            guiProcessPID = nil
            guiProcessOutput += "🛑 GUI Process stopped by user.\n"
        }
    }

    private func frameworkIcon(for framework: String) -> String {
        switch framework {
        case "SwiftUI", "UIKit", "AppKit": return "swift"
        case "Tkinter", "CustomTkinter", "PyQt", "PySide", "Python GUI": return "macwindow"
        case "egui (Rust)", "Slint (Rust)", "Iced (Rust)": return "gearshape.2"
        case "Fyne (Go)", "Gio (Go)": return "network"
        case "Flutter": return "bolt.fill"
        default: return "macwindow"
        }
    }

    private func frameworkColor(for framework: String) -> Color {
        switch framework {
        case "SwiftUI": return .orange
        case "Tkinter", "CustomTkinter": return .blue
        case "PyQt", "PySide", "Python GUI": return .green
        case "egui (Rust)", "Slint (Rust)", "Iced (Rust)": return .red
        case "Fyne (Go)", "Gio (Go)": return .cyan
        case "Flutter": return .blue
        default: return .purple
        }
    }

    /// Compile SwiftUI code and render to image
    private func compileAndRenderSwiftUI(code: String) async throws -> NSImage {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftUIPreview_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let wrapperCode = generatePreviewWrapper(userCode: code)
        let sourceFile = tempDir.appendingPathComponent("Preview.swift")
        let outputPath = tempDir.appendingPathComponent("preview_output.png")
        let executablePath = tempDir.appendingPathComponent("PreviewApp")

        try wrapperCode.write(to: sourceFile, atomically: true, encoding: .utf8)

        let compileResult = try await runProcess(
            executable: "/usr/bin/env",
            arguments: [
                "swiftc",
                "-parse-as-library",
                "-o", executablePath.path,
                "-framework", "SwiftUI",
                "-framework", "AppKit",
                sourceFile.path
            ],
            currentDirectory: tempDir
        )

        if !compileResult.success {
            throw NSError(domain: "SwiftUIPreview", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Compilation failed:\n\(compileResult.stderr)"
            ])
        }

        let runResult = try await runProcess(
            executable: executablePath.path,
            arguments: [outputPath.path],
            currentDirectory: tempDir
        )

        if !runResult.success {
            throw NSError(domain: "SwiftUIPreview", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Execution failed:\n\(runResult.stderr)"
            ])
        }

        guard let image = NSImage(contentsOf: outputPath) else {
            throw NSError(domain: "SwiftUIPreview", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Failed to load rendered image"
            ])
        }

        return image
    }

    /// Generate wrapper code that renders user's SwiftUI view to image
    private func generatePreviewWrapper(userCode: String) -> String {
        let viewName = detectMainViewName(in: userCode)
        let (cleanedCode, shims) = sanitizeSwiftUICodeForMacOS(userCode)
        let targetWidth = Int(selectedPreviewDevice.screenWidth)
        let targetHeight = Int(selectedPreviewDevice.screenHeight)
        let topInset = Int(selectedPreviewDevice.topInset)
        let bottomInset = Int(selectedPreviewDevice.bottomInset)

        return """
        import SwiftUI
        import AppKit

        // iOS UIKit & SwiftUI Compatibility Shims for macOS
        \(shims)

        // User's SwiftUI Code (adapted for macOS)
        \(cleanedCode)

        // Preview Renderer
        @main
        struct PreviewRenderer {
            @MainActor
            static func main() {
                guard CommandLine.arguments.count > 1 else {
                    print("Usage: PreviewApp <output_path>")
                    exit(1)
                }
                let outputPath = CommandLine.arguments[1]

                let view = \(viewName)()
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Color.clear.frame(height: \(topInset))
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Color.clear.frame(height: \(bottomInset))
                    }
                    .frame(width: \(targetWidth), height: \(targetHeight))
                    .background(Color.black)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 2.0

                if let cgImage = renderer.cgImage {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: \(targetWidth), height: \(targetHeight)))
                    if let tiffData = nsImage.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        try? pngData.write(to: URL(fileURLWithPath: outputPath))
                        print("Image saved to \\(outputPath)")
                        exit(0)
                    }
                }
                print("Failed to render image")
                exit(1)
            }
        }
        """
    }

    
    /// Run a process and capture output
    private func runProcess(executable: String, arguments: [String], currentDirectory: URL) async throws -> (success: Bool, stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.currentDirectoryURL = currentDirectory
                
                var env = ProcessInfo.processInfo.environment
                let home = NSHomeDirectory()
                let extraPaths = [
                    "/opt/homebrew/bin",
                    "/usr/local/bin",
                    "\(home)/.cargo/bin",
                    "\(home)/.swiftly/bin",
                    "/Applications/Xcode.app/Contents/Developer/usr/bin",
                    "/Applications/Xcode-beta.app/Contents/Developer/usr/bin",
                    "/Volumes/MAC/Xcode-beta 2.app/Contents/Developer/usr/bin"
                ]
                let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
                env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
                process.environment = env
                
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                    
                    continuation.resume(returning: (
                        success: process.terminationStatus == 0,
                        stdout: stdout,
                        stderr: stderr
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Python Environment Menu
    
    private var pythonEnvMenu: some View {
        let state = appState
        return Menu {
            // System Python Versions
            Text("System Python")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if state.availablePythonVersions.isEmpty {
                Button("python3 (default)") {
                    state.selectedPythonVersion = "python3"
                    pythonEnvManager.activeEnvironment = nil
                }
            } else {
                ForEach(state.availablePythonVersions) { version in
                    Button {
                        state.selectedPythonVersion = version.path
                        pythonEnvManager.activeEnvironment = nil
                    } label: {
                        HStack {
                            Text(version.displayName)
                            if state.selectedPythonVersion == version.path {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            // Virtual Environments
            if !pythonEnvManager.environments.isEmpty {
                Divider()
                
                Text("Virtual Environments")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(pythonEnvManager.environments) { env in
                    Button {
                        pythonEnvManager.activateEnvironment(env)
                    } label: {
                        HStack {
                            Text(env.name)
                            if pythonEnvManager.activeEnvironment?.id == env.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            Button("Refresh Versions") {
                state.detectPythonVersions()
            }
            
            Button("Manage Environments...") {
                showingEnvManager = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 0.12, green: 0.72, blue: 0.42))
                Text(currentPythonDisplay)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(controlBackground)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            state.detectPythonVersions()
        }
    }
    
    private var currentPythonDisplay: String {
        if let env = pythonEnvManager.activeEnvironment {
            return "venv: \(env.name)"
        }
        if let version = appState.availablePythonVersions.first(where: { $0.path == appState.selectedPythonVersion }) {
            return version.displayName
        }
        return "Python"
    }

    private func playgroundRuntime(for language: String) -> RuntimeType? {
        switch language.lowercased() {
        case "r": return .r
        case "julia", "jl": return .julia
        default: return nil
        }
    }

    private func runtimeEnvironmentMenu(for runtime: RuntimeType) -> some View {
        let paths = runtimeManager.availablePaths(for: runtime)
        let activePath = runtimeManager.selectedExecutable(for: runtime)
        return Menu {
            Text("\(runtime.rawValue) Environment")
                .font(.caption)
                .foregroundColor(.secondary)

            if paths.isEmpty {
                Text("No \(runtime.rawValue) runtime detected")
                    .foregroundColor(.secondary)
            } else {
                ForEach(paths, id: \.self) { path in
                    Button {
                        runtimeManager.activateRuntime(path, for: runtime)
                    } label: {
                        HStack {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                            if activePath == path { Image(systemName: "checkmark") }
                        }
                    }
                }
            }

            Divider()
            Button("Refresh Runtimes") { runtimeManager.detectAll() }
            Button("Manage Environments…") { showingEnvManager = true }
        } label: {
            HStack(spacing: 6) {
                Text(runtime.icon)
                Text(activePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? runtime.rawValue)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(controlBackground))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Analysis Logc
    
    private nonisolated func analyzeCode(code: String, language: String) -> (String?, [String]?) {
        // 1. Detect GUI Framework
        var detectedFramework: String? = nil
        let lowercased = code.lowercased()
        
        if language == "python" {
            if lowercased.contains("customtkinter") {
                detectedFramework = "CustomTkinter"
            } else if lowercased.contains("tkinter") {
                detectedFramework = "Tkinter"
            } else if lowercased.contains("pyqt6") || lowercased.contains("pyqt5") || lowercased.contains("pyqt") {
                detectedFramework = "PyQt"
            } else if lowercased.contains("pyside6") || lowercased.contains("pyside2") || lowercased.contains("pyside") {
                detectedFramework = "PySide"
            } else if lowercased.contains("import flet") || lowercased.contains("from flet") {
                detectedFramework = "Flet"
            } else if lowercased.contains("import kivy") || lowercased.contains("from kivy") {
                detectedFramework = "Kivy"
            } else if lowercased.contains("import pygame") {
                detectedFramework = "Pygame"
            } else if lowercased.contains("import wx") {
                detectedFramework = "wxPython"
            }
        } else if language == "swift" {
            if lowercased.contains("import swiftui") || lowercased.contains("struct contentview: view") || lowercased.contains("@main") {
                detectedFramework = "SwiftUI"
            } else if lowercased.contains("import uikit") {
                detectedFramework = "UIKit"
            } else if lowercased.contains("import appkit") {
                detectedFramework = "AppKit"
            }
        } else if language == "rust" {
            if lowercased.contains("egui") || lowercased.contains("eframe") {
                detectedFramework = "egui (Rust)"
            } else if lowercased.contains("slint") {
                detectedFramework = "Slint (Rust)"
            } else if lowercased.contains("iced") {
                detectedFramework = "Iced (Rust)"
            } else if lowercased.contains("gtk") {
                detectedFramework = "GTK (Rust)"
            }
        } else if language == "go" {
            if lowercased.contains("fyne.io") || lowercased.contains("fyne") {
                detectedFramework = "Fyne (Go)"
            } else if lowercased.contains("gioui.org") || lowercased.contains("gio") {
                detectedFramework = "Gio (Go)"
            }
        } else if language == "dart" {
            if lowercased.contains("package:flutter") {
                detectedFramework = "Flutter"
            }
        } else if language == "kotlin" {
            if lowercased.contains("androidx.compose") {
                detectedFramework = "Compose Desktop"
            }
        }
        
        // 2. Detect Python Imports
        var imports: [String]? = nil
        if language == "python" {
            imports = PythonEnvManager.analyzeImports(code)
        }
        
        return (detectedFramework, imports)
    }
    
    // MARK: - Helpers
    
    private func languageIcon(_ lang: String) -> String {
        switch lang {
        case "python": return "p.square"
        case "swift": return "swift"
        case "rust": return "gearshape.2"
        case "javascript", "typescript": return "j.square"
        case "go": return "g.square"
        case "r": return "r.square"
        case "julia": return "j.circle"
        default: return "doc.text"
        }
    }
    
    // Unified Coordinator Task to serialize Analysis -> Execution
    @State private var coordinatorTask: Task<Void, Never>?
    
    private func handleCodeChange() {
        coordinatorTask?.cancel()
        coordinatorTask = Task {
            // 1. Debounce for Instant Realtime Execution:
            // 650ms for Swift/SwiftUI preview compilation to avoid background compiler thrashing/flicker
            // 120ms for lightweight scripts and hot reload
            let isSwiftUI = language == "swift" && (detectedGUIFramework == "SwiftUI" || code.contains("import SwiftUI") || code.contains(": View"))
            let debounceNanos: UInt64 = isSwiftUI ? 650_000_000 : 120_000_000
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            
            let codeToAnalyze = code
            let currentLang = language
            
            // 2. Immediate Execution Dispatch (Zero Latency)
            // Auto Run without waiting for heavy AST/package analysis
            if autoRunEnabled {
                executionTask?.cancel()
                executionTask = Task {
                    await runCode()
                }
            }
            
            // Trigger Hot Reload (Preview Pane)
            if ["swift", "rust", "c", "cpp"].contains(currentLang) {
                HotReloadService.shared.requestReload(
                    sourceCode: codeToAnalyze,
                    language: currentLang
                )
            }
            
            // 3. Asynchronous Analysis (GUI & Python Imports) decoupled from execution
            let analysisResult = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let result = self.analyzeCode(code: codeToAnalyze, language: currentLang)
                    continuation.resume(returning: result)
                }
            }
            
            guard !Task.isCancelled else { return }
            
            // 4. Update UI State for GUI & Imports
            await MainActor.run {
                self.detectedGUIFramework = analysisResult.0
                if self.detectedGUIFramework != nil {
                    self.refreshGUIPreview()
                }
                
                if let packages = analysisResult.1 {
                    self.pythonEnvManager.detectedPackages = packages
                }
            }
        }
    }
    
    // Logic moved to background task inside handleCodeChange
    // private func detectGUIFramework() { ... }
    
    private func refreshGUIPreview() {
        guard let framework = detectedGUIFramework else { return }
        
        if framework == "SwiftUI" {
            // Use real SwiftUI ImageRenderer preview
            renderSwiftUIPreview()
        } else {
            // Python/other frameworks - use HTML placeholder
            guiPreviewHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <style>
                    body { 
                        font-family: -apple-system, BlinkMacSystemFont, sans-serif; 
                        background: #1e1e1e; 
                        color: white;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                        height: 100vh;
                        margin: 0;
                    }
                    .preview-container {
                        text-align: center;
                        padding: 20px;
                    }
                    .preview-icon { font-size: 48px; margin-bottom: 16px; }
                    .preview-title { font-size: 18px; font-weight: bold; margin-bottom: 8px; }
                    .preview-subtitle { font-size: 14px; color: #999; }
                </style>
            </head>
            <body>
                <div class="preview-container">
                    <div class="preview-icon">🐍</div>
                    <div class="preview-title">\(framework) Preview</div>
                    <div class="preview-subtitle">Run code to see GUI</div>
                </div>
            </body>
            </html>
            """
        }
    }
    
    /// Generate a visual preview for SwiftUI code by parsing the view hierarchy
    private func generateSwiftUIPreview() -> String {
        let lowercased = code.lowercased()
        
        // Detect SwiftUI components in the code
        var components: [(icon: String, name: String, color: String)] = []
        
        // Layout containers
        if code.contains("VStack") { components.append(("↕️", "VStack", "#7C3AED")) }
        if code.contains("HStack") { components.append(("↔️", "HStack", "#3B82F6")) }
        if code.contains("ZStack") { components.append(("📚", "ZStack", "#10B981")) }
        if code.contains("List") { components.append(("📋", "List", "#F59E0B")) }
        if code.contains("ScrollView") { components.append(("📜", "ScrollView", "#EC4899")) }
        if code.contains("NavigationView") || code.contains("NavigationStack") { 
            components.append(("🧭", "NavigationView", "#06B6D4")) 
        }
        if code.contains("TabView") { components.append(("📑", "TabView", "#8B5CF6")) }
        if code.contains("Form") { components.append(("📝", "Form", "#6366F1")) }
        if code.contains("GeometryReader") { components.append(("📐", "GeometryReader", "#EF4444")) }
        
        // UI Elements
        if code.contains("Text(") { components.append(("📝", "Text", "#94A3B8")) }
        if code.contains("Button(") { components.append(("🔘", "Button", "#2563EB")) }
        if code.contains("Image(") { components.append(("🖼️", "Image", "#22C55E")) }
        if code.contains("TextField") { components.append(("⌨️", "TextField", "#A855F7")) }
        if code.contains("Toggle") { components.append(("🔀", "Toggle", "#14B8A6")) }
        if code.contains("Slider") { components.append(("📊", "Slider", "#F97316")) }
        if code.contains("Picker") { components.append(("🎯", "Picker", "#0EA5E9")) }
        if code.contains("DatePicker") { components.append(("📅", "DatePicker", "#D946EF")) }
        if code.contains("ProgressView") { components.append(("⏳", "ProgressView", "#84CC16")) }
        if code.contains("Spacer") { components.append(("⬜", "Spacer", "#64748B")) }
        if code.contains("Divider") { components.append(("➖", "Divider", "#475569")) }
        
        // Extract Text content
        var textContents: [String] = []
        let textPattern = #"Text\("([^"]+)"\)"#
        if let regex = try? NSRegularExpression(pattern: textPattern, options: []) {
            let range = NSRange(code.startIndex..., in: code)
            let matches = regex.matches(in: code, options: [], range: range)
            for match in matches.prefix(5) {
                if let textRange = Range(match.range(at: 1), in: code) {
                    textContents.append(String(code[textRange]))
                }
            }
        }
        
        // Build HTML preview
        let componentsHTML = components.isEmpty ? 
            "<div style='color: #666; font-style: italic;'>No SwiftUI views detected</div>" :
            components.map { comp in
                "<div class='component' style='border-left: 3px solid \(comp.color);'><span class='icon'>\(comp.icon)</span> \(comp.name)</div>"
            }.joined(separator: "\n")
        
        let textPreviewHTML = textContents.isEmpty ? "" :
            """
            <div class="section">
                <div class="section-header">📝 Text Content</div>
                \(textContents.map { text in "<div class='text-item'>\"\(text)\"</div>" }.joined(separator: "\n"))
            </div>
            """
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                * { box-sizing: border-box; }
                body { 
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif; 
                    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%); 
                    color: white;
                    margin: 0;
                    padding: 16px;
                    min-height: 100vh;
                }
                .device-frame {
                    background: #0f0f15;
                    border-radius: 24px;
                    padding: 12px;
                    max-width: 320px;
                    margin: 0 auto;
                    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
                    border: 1px solid #333;
                }
                .device-screen {
                    background: linear-gradient(180deg, #1f1f28 0%, #2a2a38 100%);
                    border-radius: 16px;
                    min-height: 400px;
                    padding: 16px;
                    overflow: hidden;
                }
                .status-bar {
                    display: flex;
                    justify-content: space-between;
                    font-size: 12px;
                    font-weight: 600;
                    margin-bottom: 16px;
                    color: #888;
                }
                .header {
                    text-align: center;
                    margin-bottom: 20px;
                }
                .header h1 {
                    font-size: 16px;
                    font-weight: 600;
                    margin: 0;
                    color: #0A84FF;
                }
                .header p {
                    font-size: 11px;
                    color: #666;
                    margin: 4px 0 0 0;
                }
                .section {
                    background: rgba(255,255,255,0.05);
                    border-radius: 12px;
                    padding: 12px;
                    margin-bottom: 12px;
                }
                .section-header {
                    font-size: 11px;
                    font-weight: 600;
                    color: #888;
                    margin-bottom: 8px;
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                }
                .component {
                    display: flex;
                    align-items: center;
                    gap: 8px;
                    font-size: 13px;
                    padding: 8px 10px;
                    background: rgba(255,255,255,0.03);
                    border-radius: 8px;
                    margin-bottom: 6px;
                }
                .component:last-child { margin-bottom: 0; }
                .icon { font-size: 14px; }
                .text-item {
                    font-size: 12px;
                    color: #22C55E;
                    font-family: 'SF Mono', Menlo, monospace;
                    padding: 6px 8px;
                    background: rgba(34, 197, 94, 0.1);
                    border-radius: 6px;
                    margin-bottom: 4px;
                }
                .footer {
                    text-align: center;
                    font-size: 10px;
                    color: #444;
                    margin-top: 16px;
                }
            </style>
        </head>
        <body>
            <div class="device-frame">
                <div class="device-screen">
                    <div class="status-bar">
                        <span>9:41</span>
                        <span>100%</span>
                    </div>
                    <div class="header">
                        <h1>SwiftUI Preview</h1>
                        <p>Detected \(components.count) components</p>
                    </div>
                    <div class="section">
                        <div class="section-header">🧱 View Hierarchy</div>
                        \(componentsHTML)
                    </div>
                    \(textPreviewHTML)
                    <div class="footer">
                        Live Preview • Run to execute
                    </div>
                </div>
            </div>
        </body>
        </html>
        """
    }
    
    @MainActor
    private func runCode() async {
        // Document languages are previewed live, never executed by the backend
        // runner (which would report "Language 'markdown' not supported yet").
        if language == "markdown" || language == "latex" {
            await MainActor.run {
                isExecuting = false
                output = ""
                exitCode = 0
                showGUIPreview = true
            }
            return
        }

        if language == "swift" && (detectedGUIFramework == "SwiftUI" || code.contains("import SwiftUI") || code.contains(": View")) {
            await MainActor.run {
                isExecuting = false
                showGUIPreview = true
                showOutput = false
                renderSwiftUIPreview()
            }
            return
        }

        isExecuting = true
        output = ""
        exitCode = 0

        let startTime = Date()
        
        if language == "python" {
            // Note: Python implementation logic mixed with async/completion needs care. 
            // For now, we wrap the legacy completion-based call if needed, or better, 
            // since we are refactoring, we should make pythonEnvManager.executeCode async too?
            // For this quick fix, I will focus on the backend calls which are the main issue.
             
            // If GUI framework detected, run in external window
            if detectedGUIFramework != nil {
                output = "🖼️ Launching GUI app in external window...\n"
                
                // Sanitize code: replace curly quotes with straight quotes
                let sanitizedCode = code
                    .replacingOccurrences(of: "\u{2018}", with: "'")  // Left single quote
                    .replacingOccurrences(of: "\u{2019}", with: "'")  // Right single quote
                    .replacingOccurrences(of: "\u{201C}", with: "\"") // Left double quote
                    .replacingOccurrences(of: "\u{201D}", with: "\"") // Right double quote
                
                // Save code to temp file and run externally
                let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("playground_gui_\(UUID().uuidString).py")
                do {
                    try sanitizedCode.write(to: tempFile, atomically: true, encoding: .utf8)
                    
                    let pythonPath = pythonEnvManager.activeEnvironment?.pythonPath ?? appState.selectedPythonVersion
                    
                    // Run in background detached process
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: pythonPath)
                    process.arguments = [tempFile.path]
                    process.currentDirectoryURL = FileManager.default.temporaryDirectory
                    
                    try process.run()
                    
                    output += "✅ GUI app started (PID: \(process.processIdentifier))\n"
                    output += "📍 File: \(tempFile.path)\n"
                    executionTime = Date().timeIntervalSince(startTime)
                    isExecuting = false
                } catch {
                    output = "❌ Failed to launch GUI: \(error.localizedDescription)"
                    isExecuting = false
                }
                return
            }
            
            // Standard Python now falls through to Backend Streaming below
            // This ensures infinite loops and long running scripts stream output correctly
        }
        
        // Local Execution (Fastest & Supports 20+ Languages)
        // We use the new non-blocking async execution from AppState
        do {
            let (stdout, stderr, code) = await appState.executeScript(code: code, language: language)
            
            await MainActor.run {
                output = stdout
                if !stderr.isEmpty {
                    output += "\n" + stderr
                }
                output += "\n\nExited with code \(code) in \(String(format: "%.2f", Date().timeIntervalSince(startTime)))s\n"
                exitCode = Int(code)
                isExecuting = false
            }
        }
    }
    
    private func detectGUIFramework() {
        if code.contains("import SwiftUI") || code.contains("struct ContentView: View") {
            detectedGUIFramework = "SwiftUI"
        } else if code.contains("import UIKit") {
            detectedGUIFramework = "UIKit"
        } else if code.contains("import AppKit") {
            detectedGUIFramework = "AppKit"
        } else if language == "python" && (code.contains("tkinter") || code.contains("PyQt") || code.contains("wx")) {
            detectedGUIFramework = "Python GUI"
        } else {
            detectedGUIFramework = nil
        }
    }
    
    private func updateDefaultCode(for lang: String) {
        switch lang {
        case "python":
            code = """
            # Python Playground
            print("Hello from Python!")
            
            # Simple List Comprehension
            squares = [x**2 for x in range(10)]
            print(f"Squares: {squares}")
            """
        case "swift":
            code = """
            // Swift Playground
            import SwiftUI

            struct ContentView: View {
                @State private var count = 0
                
                var body: some View {
                    VStack(spacing: 20) {
                        Text("Hello, Swift!")
                            .font(.largeTitle)
                            .foregroundColor(.pink)
                        
                        Text("Count: \\(count)")
                            .font(.title2)
                        
                        Button("Increment") {
                            count += 1
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            """
        case "rust":
            code = """
            fn main() {
                println!("Hello from Rust!");
            }
            """
        case "javascript":
            code = """
            // JavaScript Playground
            console.log('Hello, JavaScript!');

            const numbers = [1, 2, 3, 4, 5];
            const sum = numbers.reduce((a, b) => a + b, 0);
            console.log('Sum:', sum);

            // DOM example (for web)
            // document.body.innerHTML = '<h1>Hello World</h1>';
            """
        case "typescript":
            code = """
            // TypeScript Playground
            interface User {
                name: string;
                age: number;
            }

            const user: User = {
                name: "John",
                age: 30
            };

            console.log('Hello, TypeScript!');
            console.log(`User: ${user.name}, Age: ${user.age}`);
            """
        case "go":
            code = """
            // Go Playground
            package main

            import "fmt"

            func main() {
                fmt.Println("Hello, Go!")
                
                x := 2 + 2
                fmt.Printf("2 + 2 = %d\\n", x)
            }
            """

        case "r":
            code = """
            # R Playground
            # Tidyverse is supported if installed
            
            print("Hello, R!")
            
            # Basic data frame
            df <- data.frame(
                name = c("Alice", "Bob", "Charlie"),
                age = c(25, 30, 35),
                score = c(85, 92, 78)
            )
            
            print(df)
            
            # Summary statistics
            print(summary(df))
            
            # Mean of age
            print(paste("Mean age:", mean(df["age"][[1]])))
            """

        case "julia":
            code = """
            # Julia Playground
            println("Hello, Julia!")
            
            # Simple math and plotting (mock)
            x = 1:10
            y = x .^ 2
            println("Squares: ", y)
            
            # Struct example
            struct User
                name::String
                age::Int
            end
            
            user = User("John", 30)
            println("User: ", user.name, " (", user.age, ")")
            """

        case "d":
            code = """
            // D Playground
            import std.stdio;

            void main() {
                writeln("Hello, D!");
                
                int[] numbers = [1, 2, 3, 4, 5];
                foreach (n; numbers) {
                    writef("%d ", n * n);
                }
                writeln();
            }
            """

        case "c++", "cpp":
            code = """
            // C++ Playground
            #include <iostream>
            #include <vector>
            #include <numeric>

            int main() {
                std::cout << "Hello, C++!" << std::endl;
                
                std::vector<int> numbers = {1, 2, 3, 4, 5};
                int sum = std::accumulate(numbers.begin(), numbers.end(), 0);
                std::cout << "Sum: " << sum << std::endl;
                
                return 0;
            }
            """
        case "objective-c", "objc":
            code = """
            // Objective-C Playground
            #import <Foundation/Foundation.h>

            int main(int argc, const char * argv[]) {
                @autoreleasepool {
                    NSLog(@"Hello, Objective-C!");
                    
                    NSArray *numbers = @[@1, @2, @3, @4, @5];
                    NSInteger sum = 0;
                    for (NSNumber *num in numbers) {
                        sum += [num integerValue];
                    }
                    NSLog(@"Sum: %ld", (long)sum);
                }
                return 0;
            }
            """
            
        case "objective-c++", "objcpp":
            code = """
            // Objective-C++ Playground
            #import <Foundation/Foundation.h>
            #include <vector>
            #include <iostream>

            int main(int argc, const char * argv[]) {
                @autoreleasepool {
                    NSLog(@"Hello, Objective-C++!");
                    
                    // Mix C++ STL with Objective-C
                    std::vector<int> numbers = {1, 2, 3, 4, 5};
                    int sum = 0;
                    for (int n : numbers) {
                        sum += n;
                    }
                    std::cout << "C++ Sum: " << sum << std::endl;
                    
                    // Objective-C Foundation
                    NSArray *nsNumbers = @[@10, @20, @30];
                    NSLog(@"ObjC Array: %@", nsNumbers);
                }
                return 0;
            }
            """
            
        case "ruby", "rb":
            code = """
            # Ruby Playground
            puts "Hello, Ruby!"
            
            # Array operations
            numbers = [1, 2, 3, 4, 5]
            squares = numbers.map { |n| n ** 2 }
            puts squares.inspect
            """
            
        case "c":
            code = """
            // C Playground
            #include <stdio.h>

            int main() {
                printf("Hello, C!\\n");
                
                int sum = 0;
                for (int i = 1; i <= 10; i++) {
                    sum += i;
                }
                printf("Sum 1-10: %d\\n", sum);
                
                return 0;
            }
            """
            
        case "java":
            code = """
            // Java Playground
            public class Main {
                public static void main(String[] args) {
                    System.out.println("Hello, Java!");
                    
                    int[] numbers = {1, 2, 3, 4, 5};
                    int sum = 0;
                    for (int n : numbers) {
                        sum += n;
                    }
                    System.out.println("Sum: " + sum);
                }
            }
            """
            
        case "kotlin", "kt":
            code = """
            // Kotlin Script Playground
            println("Hello, Kotlin!")
            
            val numbers = listOf(1, 2, 3, 4, 5)
            val sum = numbers.sum()
            println("Sum: " + sum)
            
            // Lambda
            val squares = numbers.map { it * it }
            println("Squares: " + squares)
            """
            
        case "lua":
            code = """
            -- Lua Playground
            print("Hello, Lua!")
            
            -- Table (array)
            local numbers = {1, 2, 3, 4, 5}
            local sum = 0
            for _, v in ipairs(numbers) do
                sum = sum + v
            end
            print("Sum: " .. sum)
            """
            
        case "perl", "pl":
            code = """
            #!/usr/bin/perl
            # Perl Playground
            use strict;
            use warnings;
            
            print "Hello, Perl!\\n";
            
            my @numbers = (1, 2, 3, 4, 5);
            my $sum = 0;
            foreach my $n (@numbers) { $sum += $n; }
            print "Sum: ", $sum, "\\n";
            """
            
        case "php":
            code = """
            <?php
            // PHP Playground
            echo "Hello, PHP!\\n";
            
            $numbers = [1, 2, 3, 4, 5];
            $sum = array_sum($numbers);
            echo "Sum: " . $sum . "\\n";
            
            $squares = array_map(function($n) { return $n * $n; }, $numbers);
            echo "Squares: " . implode(", ", $squares) . "\\n";
            ?>
            """
            
        case "shell", "bash", "sh":
            code = """
            #!/bin/bash
            # Shell Playground
            echo "Hello, Bash!"
            
            # Variables
            NAME="MicroCode"
            echo "Welcome to MicroCode"
            
            # Loop
            for i in 1 2 3 4 5; do
                echo "Number: $i"
            done
            """
            
        case "sql":
            code = """
            -- SQL Playground (SQLite)
            CREATE TABLE users (
                id INTEGER PRIMARY KEY,
                name TEXT,
                age INTEGER
            );
            
            INSERT INTO users (name, age) VALUES ('Alice', 25);
            INSERT INTO users (name, age) VALUES ('Bob', 30);
            INSERT INTO users (name, age) VALUES ('Charlie', 35);
            
            SELECT * FROM users;
            SELECT name, age FROM users WHERE age > 25;
            """
            
        case "ardium", "ar":
            code = """
            // ==========================================
            // Ardium 2.3 Playground
            // ==========================================

            let language = "Ardium";
            let version = "v2.3";
            let sum = 0;
            let i = 1;

            fn calculate_magic() {
                return 42;
            }

            fn main() {
                println("🚀 Welcome to Ardium Playground in MicroCode!");
                
                print("Language: ");
                println(language);
                print("Version:  ");
                println(version);
                
                while (i < 11) {
                    sum = sum + (i * i);
                    i = i + 1;
                }
                print("Sum of squares (1..10) = ");
                println(sum);
                
                print("calculate_magic() returned: ");
                println(calculate_magic());
                println("=========================================");
            }
            """
        
        case "latex":
            code = """
            # LaTeX Playground
            
            Welcome to the **LaTeX Playground**! Write math equations with real-time preview.
            
            ## Inline Math
            
            The quadratic formula is $x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$.
            
            ## Block Math
            
            $$
            \\int_{-\\infty}^{\\infty} e^{-x^2} dx = \\sqrt{\\pi}
            $$
            
            ## More Examples
            
            - Einstein's famous equation: $E = mc^2$
            - Euler's identity: $e^{i\\pi} + 1 = 0$
            - Sum: $\\sum_{k=1}^{n} k = \\frac{n(n+1)}{2}$
            
            ---
            
            ### Matrix Example
            
            $$
            \\begin{pmatrix}
            a & b \\\\
            c & d
            \\end{pmatrix}
            $$
            """
        
        case "markdown":
            code = """
            # Markdown Playground
            
            This is **bold** and this is *italic*.
            
            ## Features
            
            - Lists work
            - Math is supported: $\\alpha + \\beta = \\gamma$
            - Code blocks too:
            
            ```python
            print("Hello World!")
            ```
            
            ## Equation
            
            $$
            f(x) = \\int_{-\\infty}^{x} e^{-t^2} dt
            $$
            """
            
        default:
            code = "print('Hello, World!')"
        }
    }

    // MARK: - Catalogue Logic
    
    func handleCatalogueItem(code: String) {
        self.code += "\n" + code
    }

    /// Strips ANSI escape sequences from text
    private func cleanANSI(_ text: String) -> String {
        let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    /// Strips NSLog metadata (timestamps, process IDs, etc) from stderr
    private func cleanNSLog(_ input: String) -> String {
        // Pattern: 2025-12-25 23:19:09.013 bin[6248:6488860] Hello, World!
        let pattern = #"^\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}\.\d{3}\s.*?\[\d+:\d+\]\s(.*)$"#
        
        var cleaned = ""
        let lines = input.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            var processedLine = line
            
            // Clean ANSI first
            processedLine = cleanANSI(processedLine)
            
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsRange = NSRange(processedLine.startIndex..<processedLine.endIndex, in: processedLine)
                let stripped = regex.stringByReplacingMatches(in: processedLine, options: [], range: nsRange, withTemplate: "$1")
                cleaned += stripped
            } else {
                cleaned += processedLine
            }
            if index < lines.count - 1 {
                cleaned += "\n"
            }
        }
        
        return cleaned
    }

    // MARK: - .microplay File Handling & Cell Mode Operations

    func openMicroplayFile() {
        let panel = NSOpenPanel()
        panel.title = "Open Playground Document"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "microplay") ?? .json,
            UTType.json
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let selectedURL = panel.url {
            loadMicroplay(from: selectedURL)
        }
    }

    func loadMicroplay(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let doc = try decoder.decode(MicroplayDocument.self, from: data)
            
            self.currentMicroplayURL = url
            
            if !doc.cells.isEmpty {
                // Switch to Cell Mode
                self.isCellMode = true
                self.cells = doc.cells.map { cellData in
                    var theme: CellColorTheme = .none
                    if let themeStr = cellData.colorTheme,
                       let matchedTheme = CellColorTheme(rawValue: themeStr) {
                        theme = matchedTheme
                    }
                    let cell = PlaygroundCellModel(
                        id: UUID(uuidString: cellData.id) ?? UUID(),
                        code: cellData.content,
                        output: cellData.output ?? "",
                        colorTheme: theme
                    )
                    return cell
                }
                if let firstCellLang = doc.cells.first?.language, !firstCellLang.isEmpty {
                    self.language = firstCellLang
                }
                self.output = "📖 Loaded \(doc.cells.count) cell(s) from \(url.lastPathComponent)\n"
            } else {
                self.output = "📖 Loaded \(url.lastPathComponent)\n"
            }
        } catch {
            self.output = "❌ Failed to open .microplay: \(error.localizedDescription)\n"
        }
    }

    func saveMicroplayFile() {
        let panel = NSSavePanel()
        panel.title = "Save Playground Document"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "microplay") ?? .json
        ]
        panel.nameFieldStringValue = currentMicroplayURL?.lastPathComponent ?? "Playground.microplay"
        
        if panel.runModal() == .OK, let targetURL = panel.url {
            saveMicroplay(to: targetURL)
        }
    }

    func saveMicroplay(to url: URL) {
        let microplayCells: [MicroplayCellData]
        if isCellMode {
            microplayCells = cells.map { cell in
                MicroplayCellData(
                    id: cell.id.uuidString,
                    type: "code",
                    language: self.language,
                    content: cell.code,
                    output: cell.output,
                    colorTheme: cell.colorTheme.rawValue,
                    isCollapsed: false,
                    generatedCode: ""
                )
            }
        } else {
            microplayCells = [
                MicroplayCellData(
                    id: UUID().uuidString,
                    type: "code",
                    language: self.language,
                    content: self.code,
                    output: self.output,
                    colorTheme: CellColorTheme.none.rawValue,
                    isCollapsed: false,
                    generatedCode: ""
                )
            ]
        }
        
        let doc = MicroplayDocument(
            name: url.lastPathComponent,
            mode: "playground",
            cells: microplayCells
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(doc)
            try data.write(to: url, options: .atomic)
            self.currentMicroplayURL = url
            self.output = "💾 Successfully saved to \(url.lastPathComponent)\n"
        } catch {
            self.output = "❌ Failed to save .microplay: \(error.localizedDescription)\n"
        }
    }

    func runCell(_ cell: PlaygroundCellModel) {
        cell.isExecuting = true
        cell.output = ""
        let startTime = Date()
        
        Task {
            let (stdout, stderr, code) = await appState.executeScript(code: cell.code, language: language)
            await MainActor.run {
                cell.output = stdout
                if !stderr.isEmpty {
                    cell.output += (cell.output.isEmpty ? "" : "\n") + stderr
                }
                cell.executionTime = Date().timeIntervalSince(startTime)
                cell.isExecuting = false
            }
        }
    }

    func runAllCells() {
        Task {
            for cell in cells {
                await MainActor.run {
                    cell.isExecuting = true
                    cell.output = ""
                }
                let startTime = Date()
                let (stdout, stderr, _) = await appState.executeScript(code: cell.code, language: language)
                await MainActor.run {
                    cell.output = stdout
                    if !stderr.isEmpty {
                        cell.output += (cell.output.isEmpty ? "" : "\n") + stderr
                    }
                    cell.executionTime = Date().timeIntervalSince(startTime)
                    cell.isExecuting = false
                }
            }
        }
    }
}

// MARK: - GUI Preview WebView

struct GUIPreviewWebView: NSViewRepresentable {
    let htmlContent: String
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        let pagePrefs = WKWebpagePreferences()
        pagePrefs.allowsContentJavaScript = true
        webView.configuration.defaultWebpagePreferences = pagePrefs
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }
}

// MARK: - LaTeX Preview with KaTeX (Fast Rendering)

/// Real-time LaTeX preview using KaTeX (10x faster than MathJax)
struct LaTeXPreviewWebView: NSViewRepresentable {
    let latexCode: String
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let pagePrefs = WKWebpagePreferences()
        pagePrefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pagePrefs
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Escape content for safe JavaScript injection
        let escapedLatex = latexCode
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        
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
                * { box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
                    margin: 0;
                    padding: 24px;
                    background: #1a1a1a;
                    color: #f0f0f0;
                    line-height: 1.8;
                    font-size: 16px;
                }
                .katex { font-size: 1.2em; color: #f0f0f0; }
                .katex-display { margin: 1.5em 0; overflow-x: auto; }
                .katex-display > .katex { text-align: left; }
                pre, code {
                    background: #2a2a2a;
                    padding: 2px 6px;
                    border-radius: 4px;
                    font-family: 'SF Mono', 'Fira Code', monospace;
                    font-size: 14px;
                }
                pre {
                    padding: 12px;
                    overflow-x: auto;
                }
                h1, h2, h3, h4 {
                    color: #FF6F00;
                    margin-top: 1.5em;
                    margin-bottom: 0.5em;
                }
                h1 { font-size: 2em; border-bottom: 2px solid #FF6F00; padding-bottom: 0.3em; }
                h2 { font-size: 1.5em; }
                h3 { font-size: 1.2em; }
                hr { border: 0; height: 1px; background: #444; margin: 2em 0; }
                .error { color: #ff6b6b; background: #3a2020; padding: 8px 12px; border-radius: 6px; }
                #content { max-width: 800px; margin: 0 auto; }
                /* Scrollbar styling */
                ::-webkit-scrollbar { width: 8px; height: 8px; }
                ::-webkit-scrollbar-track { background: #1a1a1a; }
                ::-webkit-scrollbar-thumb { background: #444; border-radius: 4px; }
                ::-webkit-scrollbar-thumb:hover { background: #555; }
            </style>
        </head>
        <body>
            <div id="content"></div>
            <script>
                document.addEventListener('DOMContentLoaded', function() {
                    const raw = `\(escapedLatex)`;
                    const content = document.getElementById('content');
                    
                    try {
                        // Process the content - handle display math, inline math, and regular text
                        let processed = raw;
                        
                        // First, protect code blocks
                        const codeBlocks = [];
                        processed = processed.replace(/```([\\s\\S]*?)```/g, (match, code) => {
                            codeBlocks.push('<pre><code>' + code.replace(/</g, '&lt;').replace(/>/g, '&gt;') + '</code></pre>');
                            return '%%CODEBLOCK' + (codeBlocks.length - 1) + '%%';
                        });
                        
                        // Convert headers
                        processed = processed.replace(/^#### (.*$)/gm, '<h4>$1</h4>');
                        processed = processed.replace(/^### (.*$)/gm, '<h3>$1</h3>');
                        processed = processed.replace(/^## (.*$)/gm, '<h2>$1</h2>');
                        processed = processed.replace(/^# (.*$)/gm, '<h1>$1</h1>');
                        
                        // Convert horizontal rules
                        processed = processed.replace(/^---$/gm, '<hr>');
                        
                        // Convert line breaks to paragraphs
                        processed = processed.split(/\\n\\n+/).map(para => {
                            if (para.startsWith('<h') || para.startsWith('<hr') || para.includes('%%CODEBLOCK')) return para;
                            return '<p>' + para.replace(/\\n/g, '<br>') + '</p>';
                        }).join('');
                        
                        // Restore code blocks
                        codeBlocks.forEach((block, i) => {
                            processed = processed.replace('%%CODEBLOCK' + i + '%%', block);
                        });
                        
                        content.innerHTML = processed;
                        
                        // Render LaTeX with KaTeX auto-render
                        renderMathInElement(content, {
                            delimiters: [
                                {left: '$$', right: '$$', display: true},
                                {left: '$', right: '$', display: false},
                                {left: '\\\\[', right: '\\\\]', display: true},
                                {left: '\\\\(', right: '\\\\)', display: false}
                            ],
                            throwOnError: false,
                            errorColor: '#ff6b6b'
                        });
                    } catch (e) {
                        content.innerHTML = '<div class="error">⚠️ LaTeX Error: ' + e.message + '</div><pre>' + raw + '</pre>';
                    }
                });
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - Markdown Live Preview (marked.js + highlight.js + KaTeX)

/// Real-time Markdown preview. The HTML shell + renderer load ONCE; each
/// keystroke just calls a JS render function (no full page reload → no flicker).
struct MarkdownPreviewWebView: NSViewRepresentable {
    let markdown: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var ready = false
        var pending: String?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            if let p = pending { render(webView, p); pending = nil }
        }
        func render(_ webView: WKWebView, _ md: String) {
            guard ready else { pending = md; return }
            let data = (try? JSONSerialization.data(withJSONObject: [md])) ?? Data("[\"\"]".utf8)
            let json = String(data: data, encoding: .utf8) ?? "[\"\"]"
            webView.evaluateJavaScript("window.__render(\(json)[0]);", completionHandler: nil)
        }
    }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        cfg.defaultWebpagePreferences = prefs
        let webView = WKWebView(frame: .zero, configuration: cfg)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.shellHTML, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(webView, markdown)
    }

    private static let shellHTML = """
    <!DOCTYPE html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/styles/github-dark.min.css">
    <script src="https://cdn.jsdelivr.net/npm/marked@12.0.0/marked.min.js"></script>
    <script src="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/highlight.min.js"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js"></script>
    <style>
      *{box-sizing:border-box}
      body{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',sans-serif;
        margin:0;padding:24px 28px;background:#1e1e1e;color:#e8e8e8;line-height:1.7;font-size:15px}
      h1,h2,h3,h4{line-height:1.3;margin:1.2em 0 .5em;font-weight:600}
      h1{border-bottom:1px solid #333;padding-bottom:.3em}
      h2{border-bottom:1px solid #2a2a2a;padding-bottom:.25em}
      a{color:#4ea1ff}
      code{background:#2a2a2a;padding:2px 6px;border-radius:4px;
        font-family:'SF Mono','Fira Code',monospace;font-size:.88em}
      pre{background:#161616;padding:14px 16px;border-radius:8px;overflow-x:auto;border:1px solid #2a2a2a}
      pre code{background:none;padding:0;font-size:.85em}
      blockquote{border-left:3px solid #4ea1ff;margin:1em 0;padding:.2em 1em;color:#b8b8b8;background:#242424}
      table{border-collapse:collapse;margin:1em 0;width:100%}
      th,td{border:1px solid #333;padding:6px 12px}
      th{background:#262626}
      img{max-width:100%}
      hr{border:none;border-top:1px solid #333;margin:1.5em 0}
      .katex{font-size:1.05em}
    </style></head>
    <body><div id="c"></div>
    <script>
      function ready(fn){ if(window.marked&&window.hljs){fn()} else {setTimeout(function(){ready(fn)},30)} }
      window.__render = function(md){
        ready(function(){
          marked.setOptions({ breaks:true, gfm:true,
            highlight:function(code,lang){
              try{ return (lang&&hljs.getLanguage(lang))?hljs.highlight(code,{language:lang}).value:hljs.highlightAuto(code).value }catch(e){return code}
            }});
          var el=document.getElementById('c');
          el.innerHTML = marked.parse(md||'');
          if(window.renderMathInElement){
            renderMathInElement(el,{delimiters:[
              {left:'$$',right:'$$',display:true},
              {left:'$',right:'$',display:false},
              {left:'\\\\[',right:'\\\\]',display:true},
              {left:'\\\\(',right:'\\\\)',display:false}],throwOnError:false});
          }
        });
      };
    </script></body></html>
    """
}

// MARK: - Preview Device Type & iPad Frame View

enum PreviewDeviceType: String, CaseIterable, Identifiable {
    case iPhone = "iPhone"
    case iPad = "iPad"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .iPhone: return "iPhone 15 Pro"
        case .iPad: return "iPad Pro M5"
        }
    }
    
    var shortName: String {
        switch self {
        case .iPhone: return "iPhone"
        case .iPad: return "iPad"
        }
    }
    
    var screenWidth: CGFloat {
        switch self {
        case .iPhone: return 393
        case .iPad: return 938
        }
    }
    
    var screenHeight: CGFloat {
        switch self {
        case .iPhone: return 852
        case .iPad: return 646
        }
    }
    
    var frameWidth: CGFloat {
        switch self {
        case .iPhone: return 413
        case .iPad: return 1024
        }
    }
    
    var frameHeight: CGFloat {
        switch self {
        case .iPhone: return 872
        case .iPad: return 729
        }
    }
    
    var topInset: CGFloat {
        switch self {
        case .iPhone: return 59
        case .iPad: return 24
        }
    }
    
    var bottomInset: CGFloat {
        switch self {
        case .iPhone: return 34
        case .iPad: return 20
        }
    }
}

/// Photorealistic iPad Pro M5 Landscape frame with official hardware bezel
struct iPadFrameView<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var colorScheme: ColorScheme = .dark
    
    // Official Bezel specs: 1024x729 total, screen 938x646 (43px border left/right, 41.5px top/bottom), corner radius 28
    private let screenWidth: CGFloat = 938
    private let screenHeight: CGFloat = 646
    private let frameWidth: CGFloat = 1024
    private let frameHeight: CGFloat = 729
    private let screenCornerRadius: CGFloat = 28
    
    var body: some View {
        let isDark = colorScheme == .dark
        
        ZStack {
            // 1. Fallback hardware chassis (Solid matte black with soft rounded edges)
            RoundedRectangle(cornerRadius: 38)
                .fill(Color.black)
                .frame(width: frameWidth, height: frameHeight)
                .shadow(color: .black.opacity(0.6), radius: 24, x: 0, y: 12)
            
            // 2. Screen Area (Nested in transparent cutout)
            ZStack {
                // Display background
                RoundedRectangle(cornerRadius: screenCornerRadius)
                    .fill(Color.black)
                
                // Screen content
                content()
                    .frame(width: screenWidth, height: screenHeight)
                    .background(Color.black)
                
                // iPad Status Bar (Top)
                VStack {
                    HStack {
                        Text("9:41 AM")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isDark ? .white : .black)
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Image(systemName: "wifi")
                            Image(systemName: "battery.100")
                        }
                        .font(.system(size: 12))
                        .foregroundColor(isDark ? .white : .black)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    
                    Spacer()
                }
                .allowsHitTesting(false)
                
                // iPad Home Indicator (Bottom)
                VStack {
                    Spacer()
                    Capsule()
                        .fill((isDark ? Color.white : Color.black).opacity(0.45))
                        .frame(width: 280, height: 5)
                        .padding(.bottom, 6)
                }
                .allowsHitTesting(false)
            }
            .frame(width: screenWidth, height: screenHeight)
            .clipShape(RoundedRectangle(cornerRadius: screenCornerRadius))
            
            // 3. Official Bezel PNG Overlay with Center Cutout
            if let bezelImage = DeviceFrameAssets.loadIPadProBezel() {
                Image(nsImage: bezelImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: frameWidth, height: frameHeight)
                    .allowsHitTesting(false)
            }
            
            // 4. Front Facing Camera & TrueDepth Sensor (Centered at top border)
            VStack {
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color.black.opacity(0.95))
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color(white: 0.2), lineWidth: 0.5)
                        )
                    Spacer()
                }
                .padding(.top, 16)
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .frame(width: frameWidth, height: frameHeight)
    }
}

// MARK: - iPhone Frame View

/// Photorealistic iPhone frame for SwiftUI live preview matching Editor Preview Canvas
struct iPhoneFrameView<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var deviceType: iPhoneDevice = .iPhone15Pro
    var colorScheme: ColorScheme = .dark
    
    var body: some View {
        let (width, height, cornerRadius, hasDynamicIsland) = deviceType.config
        let isDark = colorScheme == .dark
        
        ZStack {
            // Device Body (Titanium / Aluminum frame)
            RoundedRectangle(cornerRadius: cornerRadius + 8)
                .fill(
                    LinearGradient(
                        colors: deviceType.titaniumColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: width + 20, height: height + 20)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
            
            // Inner bezel (black)
            RoundedRectangle(cornerRadius: cornerRadius + 4)
                .fill(Color.black)
                .frame(width: width + 10, height: height + 10)
            
            // Screen area
            ZStack {
                // Screen background
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isDark ? Color.black : Color(white: 0.95))
                
                // Content View (Live or snapshot)
                content()
                    .frame(width: width, height: height)
                    .background(isDark ? Color.black : Color(white: 0.95))
                
                // Dynamic Island / Notch
                if hasDynamicIsland {
                    VStack {
                        Capsule()
                            .fill(Color.black)
                            .frame(width: 126, height: 36)
                            .padding(.top, 11)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
                
                // Status Bar (9:41, icons)
                VStack {
                    HStack {
                        Text("9:41")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isDark ? .white : .black)
                        
                        Spacer()
                        
                        HStack(spacing: 5) {
                            Image(systemName: "cellularbars")
                            Image(systemName: "wifi")
                            Image(systemName: "battery.100")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(isDark ? .white : .black)
                    }
                    .padding(.horizontal, hasDynamicIsland ? 32 : 20)
                    .padding(.top, hasDynamicIsland ? 14 : 10)
                    
                    Spacer()
                }
                .allowsHitTesting(false)
                
                // Home Indicator
                if deviceType != .iPhoneSE {
                    VStack {
                        Spacer()
                        Capsule()
                            .fill((isDark ? Color.white : Color.black).opacity(0.5))
                            .frame(width: 134, height: 5)
                            .padding(.bottom, 8)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            
        }
        .frame(width: width + 20, height: height + 20)
    }
}

// MARK: - iPhone Device Configuration

enum iPhoneDevice {
    case iPhone15Pro
    case iPhone15ProMax
    case iPhone15
    case iPhoneSE
    
    var config: (screenWidth: CGFloat, screenHeight: CGFloat, cornerRadius: CGFloat, hasDynamicIsland: Bool) {
        switch self {
        case .iPhone15Pro:
            return (393, 852, 55, true)
        case .iPhone15ProMax:
            return (430, 932, 55, true)
        case .iPhone15:
            return (393, 852, 50, true)
        case .iPhoneSE:
            return (375, 667, 0, false)
        }
    }
    
    var titaniumColors: [Color] {
        switch self {
        case .iPhone15Pro, .iPhone15ProMax:
            // Natural Titanium
            return [
                Color(red: 0.65, green: 0.63, blue: 0.60),
                Color(red: 0.55, green: 0.53, blue: 0.50),
                Color(red: 0.60, green: 0.58, blue: 0.55),
                Color(red: 0.50, green: 0.48, blue: 0.45)
            ]
        case .iPhone15:
            // Aluminum
            return [
                Color(red: 0.75, green: 0.75, blue: 0.78),
                Color(red: 0.65, green: 0.65, blue: 0.68)
            ]
        case .iPhoneSE:
            // Black
            return [Color(white: 0.2), Color(white: 0.15)]
        }
    }
    
    var buttonColor: Color {
        switch self {
        case .iPhone15Pro, .iPhone15ProMax:
            return Color(red: 0.45, green: 0.43, blue: 0.40)
        default:
            return Color(white: 0.3)
        }
    }
}

// MARK: - Battery Icon

struct BatteryIcon: View {
    var body: some View {
        ZStack(alignment: .leading) {
            // Battery outline
            RoundedRectangle(cornerRadius: 2)
                .stroke(lineWidth: 0.8)
                .frame(width: 18, height: 8)
            
            // Battery fill
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.green)
                .frame(width: 14, height: 5)
                .offset(x: 1.5)
            
            // Battery cap
            Rectangle()
                .fill(.primary)
                .frame(width: 1.5, height: 4)
                .offset(x: 18)
        }
    }
}

// MARK: - SwiftUI Dynamic Live Preview

final class SwiftUIPreviewCoordinator {
    var currentHandle: UnsafeMutableRawPointer?
    
    deinit {
        closeCurrent()
    }
    
    func closeCurrent() {
        if let handle = currentHandle {
            dlclose(handle)
            currentHandle = nil
        }
    }
}

struct DynamicSwiftUIView: NSViewRepresentable {
    let dylibPath: String?
    let trigger: UUID
    let coordinator: SwiftUIPreviewCoordinator
    let onError: (String) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        loadDylib(into: container)
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.wantsLayer = true
        nsView.layer?.backgroundColor = NSColor.black.cgColor
        loadDylib(into: nsView)
    }
    
    private func loadDylib(into container: NSView) {
        guard let path = dylibPath, FileManager.default.fileExists(atPath: path) else {
            return
        }
        
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            let err = dlerror().map { String(cString: $0) } ?? "dlopen error"
            DispatchQueue.main.async {
                onError("Failed to load dylib: \(err)")
            }
            return
        }
        
        guard let sym = dlsym(handle, "microcode_create_preview") else {
            dlclose(handle)
            let err = dlerror().map { String(cString: $0) } ?? "Symbol microcode_create_preview not found"
            DispatchQueue.main.async {
                onError("Missing symbol: \(err)")
            }
            return
        }
        
        coordinator.closeCurrent()
        coordinator.currentHandle = handle
        
        typealias MakePreviewFn = @convention(c) () -> UnsafeMutableRawPointer
        let makeFn = unsafeBitCast(sym, to: MakePreviewFn.self)
        let rawPtr = makeFn()
        let hostedView = Unmanaged<NSView>.fromOpaque(rawPtr).takeRetainedValue()
        hostedView.wantsLayer = true
        hostedView.layer?.backgroundColor = NSColor.black.cgColor
        
        container.subviews.forEach { $0.removeFromSuperview() }
        container.addSubview(hostedView)
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: container.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostedView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }
}

