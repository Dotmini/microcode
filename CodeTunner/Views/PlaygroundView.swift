//
//  PlaygroundView.swift
//  CodeTunner
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
    
    // Cell Mode Support
    @State private var isCellMode: Bool = false
    @State private var cells: [PlaygroundCellModel] = [PlaygroundCellModel(code: "print('Hello from Cell 1')", colorTheme: .none)]
    @State private var executionTask: Task<Void, Never>?
    
    // Catalogue Support
    @State private var showCatalogue: Bool = false
    
    // All languages supported by backend runner
    let supportedLanguages = [
        "python", "r", "julia", "ruby",            // Scripting
        "swift", "objective-c", "objective-c++",   // Apple
        "rust", "go", "c", "c++", "d",             // Systems
        "javascript", "typescript",                 // Web
        "java", "kotlin",                          // JVM
        "lua", "perl", "php",                      // Other Scripting
        "sql", "shell", "bash",                    // Data/DevOps
        "ardium"                                   // Custom
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
            // Main Content
            HSplitView {
                if showCatalogue {
                    CatalogueSidebar(onSelectItem: handleCatalogueItem)
                        .transition(.move(edge: .leading))
                    Divider()
                }
                
                // Left Pane: Editor & Data
                VStack(spacing: 0) {
                    if showDataFiles {
                        dataFilesPanel
                            .frame(minHeight: 150, maxHeight: 300)
                        Divider()
                    }
                    
                    if isCellMode {
                        cellEditorPanel
                    } else {
                        codeEditorPanel
                    }
                }
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                
                // Right Pane: Output & Preview
                if (showOutput || showGUIPreview) && !isCellMode {
                    VStack(spacing: 0) {
                        if showGUIPreview {
                            guiPreviewPanel
                                .frame(minHeight: 200, maxHeight: .infinity)
                        }
                        
                        if showGUIPreview && showOutput {
                            Divider()
                        }
                        
                        if showOutput {
                            outputPanel
                                .frame(minHeight: 100, maxHeight: showGUIPreview ? 300 : .infinity)
                        }
                    }
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            print("🚀 PlaygroundView: onAppear triggered")
            if code == "print('Hello, Playground!')" {
                updateDefaultCode(for: language)
            }
            
            // Ensure directory exists asynchronously
            Task {
                try? FileManager.default.createDirectory(at: playgroundDirectory, withIntermediateDirectories: true)
                print("🚀 PlaygroundView: Verified directory at \(playgroundDirectory.path)")
            }
        }
        .sheet(isPresented: $showingEnvManager) {
            PythonEnvSheet()
        }
    }
    
    // MARK: - Toolbar
    
    private var playgroundToolbar: some View {
        HStack {
            // Language Selector
            Menu {
                ForEach(supportedLanguages, id: \.self) { lang in
                    Button(lang.capitalized) {
                        language = lang
                        updateDefaultCode(for: lang)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: languageIcon(language))
                        .foregroundColor(.pink)
                    Text(language.capitalized)
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(controlBackground)
                .cornerRadius(6)
            }
            
            // Settings Button
            Button(action: { showingSettings.toggle() }) {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showingSettings) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Playground Settings")
                        .font(.headline)
                    
                    Divider()
                    
                    // Font Size
                    VStack(alignment: .leading) {
                        Text("Font Size: \(Int(appState.playgroundFontSize))")
                            .font(.caption)
                        Slider(value: $appState.playgroundFontSize, in: 10...24, step: 1)
                    }
                    
                    // Font Family
                    VStack(alignment: .leading) {
                        Text("Font Family")
                            .font(.caption)
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
                    VStack(alignment: .leading) {
                        Text("Theme")
                            .font(.caption)
                        Picker("", selection: $appState.appTheme) {
                            ForEach(AppTheme.allCases, id: \.self) { theme in
                                Text(theme.displayName).tag(theme)
                            }
                        }
                        .labelsHidden()
                    }
                }
                .padding()
                .frame(width: 250)
            }
            
            // Python Environment Selector
            if language == "python" {
                pythonEnvMenu
            }
            
            if ["javascript", "typescript"].contains(language.lowercased()) {
                NodeVersionPicker()
            }
            
            Divider()
                .frame(height: 20)
            
            // Catalogue Toggle
            Toggle(isOn: $showCatalogue) {
                HStack(spacing: 4) {
                    Image(systemName: "book.fill")
                    Text("Catalogue")
                }
                .font(.system(size: 12))
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .tint(showCatalogue ? .blue : .secondary)
            
            Spacer()
            
            // Data Files Toggle
            Toggle(isOn: $showDataFiles) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text("Data")
                }
                .font(.system(size: 12))
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .tint(showDataFiles ? .orange : .secondary)
            
            // Output Toggle
            Toggle(isOn: $showOutput) {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                    Text("Output")
                }
                .font(.system(size: 12))
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .tint(showOutput ? .green : .secondary)
            
            // GUI Preview Toggle
            Toggle(isOn: $showGUIPreview) {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                    Text("Preview")
                }
                .font(.system(size: 12))
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .tint(showGUIPreview ? .pink : .secondary)
            .disabled(isCellMode)
            
            Divider()
                .frame(height: 20)
            
            // Cell Mode Toggle
            Toggle(isOn: $isCellMode) {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.2x2")
                    Text("Cell Mode")
                }
                .font(.system(size: 12, weight: .bold))
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .tint(isCellMode ? .purple : .secondary)
            
            if isCellMode {
                // Run By Color Menu
                Menu {
                    ForEach(getUsedColors()) { theme in
                        Button(action: { runCellsByColor(theme) }) {
                            Label("Run \(theme.rawValue)", systemImage: "play.fill")
                                .foregroundColor(theme.iconColor)
                        }
                    }
                    
                    Divider()
                    
                    Button(action: { runAllCells() }) {
                        Label("Run All Cells", systemImage: "play.circle.fill")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Run By Color")
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)
                
                Button(action: addCell) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
                .frame(height: 20)
            
            // Auto-run toggle
            Toggle("Auto-run", isOn: $autoRunEnabled)
                .font(.system(size: 12))
                .toggleStyle(.switch)
            
            // Live Preview (Hot Reload) toggle
            Toggle(isOn: Binding(
                get: { HotReloadService.shared.isEnabled },
                set: { _ in HotReloadService.shared.toggle() }
            )) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                    Text("Hot Reload")
                }
                .font(.system(size: 12))
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .tint(HotReloadService.shared.isEnabled ? .yellow : .secondary)
            
            // Execution stats
            if executionTime > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    Text("\(String(format: "%.2f", executionTime))s")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
            }
            
            // Run button
            // Run/Stop button
            Button(action: {
                if isExecuting {
                    executionTask?.cancel()
                    autoRunTask?.cancel()
                    isExecuting = false
                    
                    // Also stop cells if in cell mode
                    if isCellMode {
                        for cell in cells { cell.isExecuting = false }
                    }
                } else {
                    if isCellMode {
                        runAllCells()
                    } else {
                        executionTask = Task {
                            await runCode()
                        }
                    }
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isExecuting ? "stop.circle.fill" : "play.circle.fill")
                    Text(isExecuting ? "Stop" : "Run")
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(isExecuting ? .red : .pink)
            .keyboardShortcut("r", modifiers: [.command])
            
            // Clear output
            Button(action: {
                output = ""
                executionTime = 0
            }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Clear Output")
        }
        .padding()
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
        appState.appTheme == .transparent ? Color.white.opacity(0.05) : Color(nsColor: .windowBackgroundColor)
    }
    
    private var controlBackground: Color {
        appState.appTheme == .transparent ? Color.white.opacity(0.08) : Color(nsColor: .controlBackgroundColor)
    }
    
    private var codeEditorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            codeEditorHeader
            Divider()
            codeEditorContent
        }
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
                .foregroundColor(.green)
            Text(framework)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.green.opacity(0.1))
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
            fontWeight: appState.playgroundFontWeight
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: code) { newValue in
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
            // Header
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(.green)
                Text("Output")
                    .font(.system(size: 11, weight: .semibold))
                
                if isExecuting || pythonEnvManager.isWorking {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.leading, 4)
                }
                
                Spacer()
                
                if exitCode != 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Exit \(exitCode)")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(panelBackground)
            
            Divider()
            
            ScrollView {
                Text(output.isEmpty ? "Output will appear here..." : output)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(output.isEmpty ? .secondary : Color(nsColor: appState.appTheme.editorText))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .background(editorBackground)
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
            // Header
            HStack {
                Image(systemName: "macwindow")
                    .foregroundColor(.purple)
                Text("SwiftUI Preview")
                    .font(.system(size: 11, weight: .semibold))
                
                Spacer()
                
                if isPreviewLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
                
                Button("⟳ Refresh") {
                    renderSwiftUIPreview()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(panelBackground)
            
            Divider()
            
            // Preview Content
            if language == "swift" && detectedGUIFramework == "SwiftUI" {
                // Real SwiftUI Preview in iPhone Frame
                ScrollView {
                    iPhoneFrameView(
                        content: {
                            if let image = swiftPreviewImage {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else if isPreviewLoading {
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text("Compiling...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(panelBackground)
                            } else {
                                VStack(spacing: 16) {
                                    Image(systemName: "swift")
                                        .font(.system(size: 48))
                                        .foregroundColor(.orange)
                                    
                                    Text("SwiftUI Preview")
                                        .font(.headline)
                                    
                                    Text("Click Refresh to compile")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Button("▶ Compile & Preview") {
                                        renderSwiftUIPreview()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(panelBackground)
                            }
                        },
                        deviceType: .iPhone15Pro,
                        colorScheme: appState.appTheme.isDark ? .dark : .light
                    )
                    .padding(20)
                }
            } else if detectedGUIFramework != nil {
                // Python/Other GUI - show HTML preview
                GUIPreviewWebView(htmlContent: guiPreviewHTML)
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
                        Text("Import a GUI framework to see preview")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(panelBackground)
            }
        }
    }
    
    /// Compile and render actual SwiftUI code
    private func renderSwiftUIPreview() {
        isPreviewLoading = true
        swiftPreviewImage = nil
        output = "🔨 Compiling SwiftUI code...\n"
        
        Task {
            do {
                let image = try await compileAndRenderSwiftUI(code: code)
                await MainActor.run {
                    swiftPreviewImage = image
                    isPreviewLoading = false
                    output += "✅ Preview rendered successfully\n"
                }
            } catch {
                await MainActor.run {
                    isPreviewLoading = false
                    output += "❌ Error: \(error.localizedDescription)\n"
                }
            }
        }
    }
    
    /// Compile SwiftUI code and render to image
    private func compileAndRenderSwiftUI(code: String) async throws -> NSImage {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftUIPreview_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create a wrapper that renders the user's view to an image
        let wrapperCode = generatePreviewWrapper(userCode: code)
        let sourceFile = tempDir.appendingPathComponent("Preview.swift")
        let outputPath = tempDir.appendingPathComponent("preview_output.png")
        let executablePath = tempDir.appendingPathComponent("PreviewApp")
        
        try wrapperCode.write(to: sourceFile, atomically: true, encoding: .utf8)
        
        // Compile with swiftc
        let compileResult = try await runProcess(
            executable: "/usr/bin/swiftc",
            arguments: [
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
        
        // Run the executable to generate image
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
        
        // Load the generated image
        guard let image = NSImage(contentsOf: outputPath) else {
            throw NSError(domain: "SwiftUIPreview", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Failed to load rendered image"
            ])
        }
        
        return image
    }
    
    /// Generate wrapper code that renders user's SwiftUI view to image
    private func generatePreviewWrapper(userCode: String) -> String {
        // Extract the struct name if present (find first View struct, not App)
        let structPattern = #"struct\s+(\w+)\s*:\s*View\s*\{"#
        var viewName = "ContentView"
        if let regex = try? NSRegularExpression(pattern: structPattern, options: []),
           let match = regex.firstMatch(in: userCode, range: NSRange(userCode.startIndex..., in: userCode)),
           let range = Range(match.range(at: 1), in: userCode) {
            viewName = String(userCode[range])
        }
        
        // Clean user code for macOS compilation
        var cleanedCode = userCode
        
        // Remove @main attribute (we add our own)
        cleanedCode = cleanedCode.replacingOccurrences(of: "@main\n", with: "// @main (disabled for preview)\n")
        cleanedCode = cleanedCode.replacingOccurrences(of: "@main ", with: "// @main (disabled) ")
        
        // Replace iOS-only UIColor references with macOS NSColor
        cleanedCode = cleanedCode.replacingOccurrences(of: ".systemGroupedBackground", with: ".windowBackgroundColor")
        cleanedCode = cleanedCode.replacingOccurrences(of: ".systemBackground", with: ".windowBackgroundColor")
        cleanedCode = cleanedCode.replacingOccurrences(of: ".systemGray5", with: ".controlBackgroundColor")
        cleanedCode = cleanedCode.replacingOccurrences(of: ".systemGray4", with: ".controlBackgroundColor")
        cleanedCode = cleanedCode.replacingOccurrences(of: ".systemGray3", with: ".separatorColor")
        cleanedCode = cleanedCode.replacingOccurrences(of: ".systemGray2", with: ".secondaryLabelColor")
        cleanedCode = cleanedCode.replacingOccurrences(of: ".systemGray", with: ".labelColor")
        cleanedCode = cleanedCode.replacingOccurrences(of: ".label", with: ".labelColor")
        cleanedCode = cleanedCode.replacingOccurrences(of: ".secondaryLabel", with: ".secondaryLabelColor")
        cleanedCode = cleanedCode.replacingOccurrences(of: ".tertiaryLabel", with: ".tertiaryLabelColor")
        
        // Replace iOS-only toolbar placements with macOS equivalents
        cleanedCode = cleanedCode.replacingOccurrences(of: ".topBarTrailing", with: ".automatic")
        cleanedCode = cleanedCode.replacingOccurrences(of: ".topBarLeading", with: ".automatic")
        cleanedCode = cleanedCode.replacingOccurrences(of: ".navigationBarTrailing", with: ".automatic")
        cleanedCode = cleanedCode.replacingOccurrences(of: ".navigationBarLeading", with: ".automatic")
        cleanedCode = cleanedCode.replacingOccurrences(of: ".bottomBar", with: ".automatic")
        
        return """
        import SwiftUI
        import AppKit
        
        // User's SwiftUI Code (adapted for macOS)
        \(cleanedCode)
        
        // Preview Renderer
        @main
        struct PreviewRenderer {
            static func main() {
                guard CommandLine.arguments.count > 1 else {
                    print("Usage: PreviewApp <output_path>")
                    exit(1)
                }
                let outputPath = CommandLine.arguments[1]
                
                let view = \(viewName)()
                    .frame(width: 375, height: 812)
                    .background(panelBackground)
                
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2.0
                
                if let cgImage = renderer.cgImage {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 375, height: 812))
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
        Menu {
            // System Python Versions
            Text("System Python")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if appState.availablePythonVersions.isEmpty {
                Button("python3 (default)") {
                    appState.selectedPythonVersion = "python3"
                    pythonEnvManager.activeEnvironment = nil
                }
            } else {
                ForEach(appState.availablePythonVersions) { version in
                    Button {
                        appState.selectedPythonVersion = version.path
                        pythonEnvManager.activeEnvironment = nil
                    } label: {
                        HStack {
                            Text(version.displayName)
                            if appState.selectedPythonVersion == version.path {
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
                appState.detectPythonVersions()
            }
            
            Button("Manage Environments...") {
                showingEnvManager = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "terminal")
                    .foregroundColor(.green)
                Text(currentPythonDisplay)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(controlBackground)
            .cornerRadius(4)
        }
        .onAppear {
            appState.detectPythonVersions()
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
    
    // MARK: - Analysis Logc
    
    private nonisolated func analyzeCode(code: String, language: String) -> (String?, [String]?) {
        // 1. Detect GUI Framework
        var detectedFramework: String? = nil
        let lowercased = code.lowercased()
        
        if language == "python" {
            if lowercased.contains("import tkinter") || lowercased.contains("from tkinter") {
                detectedFramework = "tkinter"
            } else if lowercased.contains("import pyqt") || lowercased.contains("from pyqt") {
                detectedFramework = "PyQt5"
            } else if lowercased.contains("import customtkinter") || lowercased.contains("from customtkinter") {
                detectedFramework = "customtkinter"
            } else if lowercased.contains("import kivy") {
                detectedFramework = "Kivy"
            }
        } else if language == "swift" {
            if lowercased.contains("import swiftui") || lowercased.contains("@main") {
                detectedFramework = "SwiftUI"
            }
        } else if language == "rust" {
            if lowercased.contains("egui") || lowercased.contains("eframe") {
                detectedFramework = "egui"
            } else if lowercased.contains("gtk") {
                detectedFramework = "GTK"
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
            // 1. Single Debounce for EVERYTHING (Wait 0.6s)
            // This prevents race conditions where execution starts before analysis finishes
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            
            // 2. Perform Analysis (Background)
            // strictly before any execution logic
            let codeToAnalyze = code
            let currentLang = language
            
            let analysisResult = await Task.detached(priority: .userInitiated) {
                return self.analyzeCode(code: codeToAnalyze, language: currentLang)
            }.value
            
            guard !Task.isCancelled else { return }
            
            // 3. Update State (Main Actor)
            await MainActor.run {
                // Update Framework
                self.detectedGUIFramework = analysisResult.0
                if self.detectedGUIFramework != nil {
                    // Auto-open Disabled by user request
                    // if !self.showGUIPreview { self.showGUIPreview = true }
                    self.refreshGUIPreview()
                }
                
                // Update Python Imports
                if let packages = analysisResult.1 {
                    self.pythonEnvManager.detectedPackages = packages
                }
            }
            
            // 4. Execution Dispatch
            // Only now do we allow Hot Reload or Auto Run
            
            // A. Trigger Hot Reload (Preview Pane)
            if ["swift", "rust", "c", "cpp"].contains(currentLang) {
                HotReloadService.shared.requestReload(
                    sourceCode: codeToAnalyze,
                    language: currentLang
                )
            }
            
            // B. Auto Run (Console Output)
            if autoRunEnabled {
                // Cancel previous execution task if still running
                executionTask?.cancel()
                await runCode()
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
                        <span>⚡ 100%</span>
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
        
        // Backend Service Execution (Async)
        do {
            // Backend Service Execution (Streaming)
            var buffer = ""
            var lastUpdate = Date()
            
            for try await event in BackendService.shared.streamExecuteCode(
                code: code,
                language: language
            ) {
                 if let stdout = event.Output {
                     buffer += stdout
                 }
                 if let stderr = event.Error {
                     // Clean NSLog for Obj-C
                     if language == "objective-c" || language == "objective-cpp" {
                         buffer += cleanNSLog(stderr)
                     } else {
                         buffer += stderr
                     }
                 }
                 
                 // Throttled UI Update (Max 10fps)
                 if -lastUpdate.timeIntervalSinceNow > 0.1 {
                     let chunk = buffer
                     buffer = ""
                     lastUpdate = Date()
                     await MainActor.run {
                         output += chunk
                     }
                 }
                 
                 if let code = event.Exit {
                     // Flush before setting exit code
                     if !buffer.isEmpty {
                        let chunk = buffer
                        buffer = ""
                        await MainActor.run { output += chunk }
                     }
                     exitCode = code
                 }
            }
            
            // Final Flush
            if !buffer.isEmpty {
                let chunk = buffer
                await MainActor.run { output += chunk }
            }
            
            // Execution Finished
            executionTime = Date().timeIntervalSince(startTime)
            isExecuting = false
        } catch {
            await MainActor.run {
                if Task.isCancelled {
                   // Ignore error if cancelled
                } else {
                   output = "Error: \(error.localizedDescription)"
                }
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
            // Ardium Playground
            fn main() {
                print("Hello, Ardium!")
                
                let x = 10
                let y = 20
                print("Sum:", x + y)
            }
            """
            
        default:
            code = "print('Hello, World!')"
        }
    }

    // MARK: - Cell Mode & Catalogue Logic
    
    private var cellEditorPanel: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(cells) { cell in
                    PlaygroundCellView(
                        cell: cell,
                        language: language,
                        onRun: { runCell(cell: cell) },
                        onDelete: { deleteCell(cell: cell) }
                    )
                    .environmentObject(appState)
                    .environmentObject(cell)
                }
                
                Button(action: addCell) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add New Cell")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 20)
            }
            .padding(.top, 12)
        }
    }
    
    func getUsedColors() -> [CellColorTheme] {
        let colors = Set(cells.map { $0.colorTheme })
        return Array(colors).sorted { $0.rawValue < $1.rawValue }
    }
    
    func runCell(cell: PlaygroundCellModel) {
        Task {
            cell.isExecuting = true
            cell.output = ""
            let startTime = Date()
            
            do {
                let result = try await BackendService.shared.executeCode(code: cell.code, language: language)
                await MainActor.run {
                    cell.output = result.stdout + result.stderr
                    cell.executionTime = Date().timeIntervalSince(startTime)
                    cell.isExecuting = false
                }
            } catch {
                await MainActor.run {
                    cell.output = "Error: \(error.localizedDescription)"
                    cell.isExecuting = false
                }
            }
        }
    }
    
    func runCellsByColor(_ theme: CellColorTheme) {
        for cell in cells where cell.colorTheme == theme {
            runCell(cell: cell)
        }
    }
    
    func runAllCells() {
        for cell in cells {
            runCell(cell: cell)
        }
    }
    
    func addCell() {
        cells.append(PlaygroundCellModel(code: "", colorTheme: .none))
    }
    
    func deleteCell(cell: PlaygroundCellModel) {
        cells.removeAll { $0.id == cell.id }
        if cells.isEmpty {
            addCell()
        }
    }
    
    func handleCatalogueItem(code: String) {
        if isCellMode {
            cells.append(PlaygroundCellModel(code: code, colorTheme: .none))
        } else {
            self.code += "\n" + code
        }
    }

    /// Strips NSLog metadata (timestamps, process IDs, etc) from stderr
    private func cleanNSLog(_ input: String) -> String {
        // Pattern: 2025-12-25 23:19:09.013 bin[6248:6488860] Hello, World!
        let pattern = #"^\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}\.\d{3}\s.*?\[\d+:\d+\]\s(.*)$"#
        
        var cleaned = ""
        let lines = input.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
                let stripped = regex.stringByReplacingMatches(in: line, options: [], range: nsRange, withTemplate: "$1")
                cleaned += stripped
            } else {
                cleaned += line
            }
            if index < lines.count - 1 {
                cleaned += "\n"
            }
        }
        
        return cleaned
    }
}

// MARK: - GUI Preview WebView

struct GUIPreviewWebView: NSViewRepresentable {
    let htmlContent: String
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.configuration.preferences.javaScriptEnabled = true
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }
}

// MARK: - iPhone Frame View

/// Photorealistic iPhone 15 Pro frame for SwiftUI preview
struct iPhoneFrameView<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var deviceType: iPhoneDevice = .iPhone15Pro
    var colorScheme: ColorScheme = .dark
    
    var body: some View {
        content()
            .cornerRadius(12)
            .shadow(radius: 5)
            .padding(10)
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

#Preview {
    PlaygroundView()
        .environmentObject(AppState())
        .frame(width: 1200, height: 700)
}

