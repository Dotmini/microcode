//
//  RefactorProWindow.swift
//  CodeTunner
//
//  AI Refactor Pro - Full-Screen Cross-Language Migration Tool
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import SwiftUI

// MARK: - Refactor Pro Window

struct RefactorProWindow: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    // State
    @State private var selectedMode: RefactorMode = .refactor
    @State private var sourceLanguage: String = "python"
    @State private var targetLanguage: String = "javascript"
    @State private var instructions: String = ""
    @State private var isProcessing: Bool = false
    @State private var originalCode: String = ""
    @State private var refactoredCode: String = ""
    @State private var showReport: Bool = false
    @State private var report: RefactorReport?
    @State private var errorMessage: String = ""
    @State private var selectedTab: Int = 0 // 0: Code, 1: Report, 2: Plan, 3: Logs
    @State private var isUltraMode: Bool = true
    @State private var isStreaming: Bool = false
    @State private var folderFiles: [FileContent] = []
    @State private var totalFilesProcessed: Int = 0
    @State private var streamingBuffer: String = ""
    @State private var animationTask: Task<Void, Never>?
    @State private var currentPlan: ExecutionPlan?
    @State private var agentResults: [AgentToolResult] = []
    
    private let languages = [
        "python", "javascript", "typescript", "swift", "kotlin",
        "java", "c", "cpp", "csharp", "go", "rust", "ruby", "php"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Toolbar
            headerToolbar
            
            Divider()
            
            // Main Content
            CompatHSplitView {
                // Left: Source Code
                sourcePanel
                    .frame(minWidth: 350)
                
                // Right: Refactored Code
                resultPanel
                    .frame(minWidth: 350)
            }
            
            Divider()
            
            // Footer
            footerBar
        }
        .frame(minWidth: 1200, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadCurrentFile()
        }
    }
    
    // MARK: - Header Toolbar
    
    private var headerToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Logo
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.purple.opacity(0.3), .blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 30, height: 30)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("AI Refactor Pro")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    if let file = appState.currentFile {
                        Text(file.name)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider().frame(height: 24)
                
                // Mode pills
                HStack(spacing: 2) {
                    ForEach(RefactorMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedMode = mode }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: mode == .refactor ? "wrench.and.screwdriver.fill" : "arrow.left.arrow.right")
                                    .font(.system(size: 9))
                                Text(mode == .refactor ? "Refactor" : "Migration")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(selectedMode == mode ? .white : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedMode == mode ? Color.accentColor.opacity(0.85) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
                
                if selectedMode == .migration {
                    HStack(spacing: 6) {
                        Picker("", selection: $sourceLanguage) {
                            ForEach(languages, id: \.self) { Text($0.capitalized).tag($0) }
                        }.frame(width: 85).labelsHidden()
                        Image(systemName: "arrow.right").font(.system(size: 10)).foregroundColor(.purple)
                        Picker("", selection: $targetLanguage) {
                            ForEach(languages, id: \.self) { Text($0.capitalized).tag($0) }
                        }.frame(width: 85).labelsHidden()
                    }
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle().fill(isUltraMode ? .green : .secondary.opacity(0.3)).frame(width: 6, height: 6)
                    Text("Ultra").font(.system(size: 10, weight: .medium)).foregroundColor(isUltraMode ? .primary : .secondary)
                    Toggle("", isOn: $isUltraMode).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.04)).cornerRadius(6)
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Rectangle()
                .fill(LinearGradient(colors: [.purple.opacity(0.4), .blue.opacity(0.3), .cyan.opacity(0.2)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
    }
    
    // MARK: - Source Panel
    
    private var sourcePanel: some View {
        VStack(spacing: 0) {
            // Panel Header
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .font(.system(size: 12))
                Text("Source Code")
                    .font(.system(size: 12, weight: .semibold))
                
                Spacer()
                
                if let file = appState.currentFile {
                    Text(file.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            
            if selectedMode == .migration {
                Button(action: selectFolderForMigration) {
                    Label("Select Folder for Bulk Migration", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                
                if !folderFiles.isEmpty {
                    Text("\(folderFiles.count) files selected for migration")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
            }
            
            Divider()
            
            // Code Editor
            TextEditor(text: $originalCode)
                .font(.system(size: 13, design: .monospaced))
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
            
            Divider()
            
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("Instructions")
                    .font(.system(size: 12, weight: .medium))
                
                TextEditor(text: $instructions)
                    .font(.system(size: 12))
                    .frame(height: 80)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if selectedMode == .migration {
                            migrationTemplates
                        } else {
                            refactorTemplates
                        }
                    }
                }
                
                if isUltraMode {
                    HStack(spacing: 6) {
                         Image(systemName: "memory.chip")
                            .foregroundColor(.orange)
                            .font(.system(size: 10))
                         Text("Smart Vector Memory Active")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                         Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        }
    }
    
    // MARK: - Result Panel
    
    private var resultPanel: some View {
        VStack(spacing: 0) {
            // Panel Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .font(.system(size: 12))
                Text(selectedMode == .migration ? "Migrated Code" : "Refactored Code")
                    .font(.system(size: 12, weight: .semibold))
                
                Spacer()
                
                if selectedMode == .migration {
                    Text(".\(targetLanguage)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green.opacity(0.1)).cornerRadius(4)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Tab Bar
            HStack(spacing: 0) {
                TabButton(title: "Code", isSelected: selectedTab == 0) { selectedTab = 0 }
                TabButton(title: "Plan", isSelected: selectedTab == 2) { selectedTab = 2 }
                TabButton(title: "Logs", isSelected: selectedTab == 3) { selectedTab = 3 }
                TabButton(title: "Report", isSelected: selectedTab == 1) { selectedTab = 1 }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            
            Divider()
            
            // Content
            if selectedTab == 0 {
                // Code View
                if refactoredCode.isEmpty {
                    emptyResultView
                } else {
                    TextEditor(text: $refactoredCode)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                }
            } else if selectedTab == 2 {
                // Plan View
                if let plan = currentPlan {
                    ScrollView {
                        PlanPreviewView(plan: plan)
                            .padding(16)
                    }
                } else {
                    VStack {
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No active plan")
                            .foregroundColor(.secondary)
                        Text("The AI will generate a plan for complex tasks")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if selectedTab == 3 {
                // Logs View
                SelfCorrectionLogView(results: agentResults)
            } else {
                // Report View
                if let report = report {
                    reportView(report)
                } else {
                    VStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Generate a refactor to see the report")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
    
    private var emptyResultView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.purple.opacity(0.12), .blue.opacity(0.05), .clear], center: .center, startRadius: 10, endRadius: 60))
                    .frame(width: 100, height: 100)
                Image(systemName: selectedMode == .migration ? "arrow.left.arrow.right" : "wand.and.stars")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            
            VStack(spacing: 6) {
                Text(selectedMode == .migration ? "Ready to Migrate" : "Ready to Refactor")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.8))
                Text("Paste code or load a file, then click Generate")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                ForEach(selectedMode == .migration
                    ? ["Direct Translation", "Idiomatic Style", "Type-Safe Migration"]
                    : ["Clean Code", "Add Error Handling", "Optimize Performance"], id: \.self) { tip in
                    HStack(spacing: 8) {
                        Image(systemName: "sparkle").font(.system(size: 9)).foregroundColor(.purple)
                        Text(tip).font(.system(size: 11)).foregroundColor(.primary.opacity(0.6))
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06)))
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Report View
    
    private func reportView(_ report: RefactorReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Migration Summary")
                                .font(.headline)
                            Spacer()
                            Text(report.timestamp, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ReportStatItem(label: "Source", value: report.sourceLanguage.capitalized, icon: "doc.text")
                            ReportStatItem(label: "Target", value: report.targetLanguage.capitalized, icon: "doc.text.fill")
                            ReportStatItem(label: "Lines Before", value: "\(report.linesBefore)", icon: "text.alignleft")
                            ReportStatItem(label: "Lines After", value: "\(report.linesAfter)", icon: "text.alignleft")
                            ReportStatItem(label: "Complexity Before", value: "\(report.complexityBefore)", icon: "chart.bar")
                            ReportStatItem(label: "Complexity After", value: "\(report.complexityAfter)", icon: "chart.bar.fill")
                        }
                    }
                    .padding(4)
                }
                
                // Changes List
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Changes Made")
                            .font(.headline)
                        
                        ForEach(report.changes, id: \.self) { change in
                            HStack(alignment: .top) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text(change)
                                    .font(.system(size: 12))
                            }
                        }
                    }
                    .padding(4)
                }
                
                // Recommendations
                if !report.recommendations.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recommendations")
                                .font(.headline)
                            
                            ForEach(report.recommendations, id: \.self) { rec in
                                HStack(alignment: .top) {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(.yellow)
                                        .font(.caption)
                                    Text(rec)
                                        .font(.system(size: 12))
                                }
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Footer Bar
    
    private var footerBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(LinearGradient(colors: [.purple.opacity(0.15), .blue.opacity(0.1), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
            
            HStack(spacing: 10) {
                // Error / Status
                if !errorMessage.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.system(size: 10))
                        Text(errorMessage).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                
                if isProcessing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                        Text("AI processing...").font(.system(size: 10)).foregroundColor(.purple)
                    }
                }
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 8) {
                    Menu {
                        Button("Export as PDF") { exportReport(format: .pdf) }
                        Button("Export as Text") { exportReport(format: .text) }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.badge.arrow.up").font(.system(size: 9))
                            Text("Export").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.white.opacity(0.04)).cornerRadius(6)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 80)
                    .disabled(report == nil)
                    
                    Button { copyToClipboard() } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.doc").font(.system(size: 9))
                            Text("Copy").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.white.opacity(0.04)).cornerRadius(6)
                    }
                    .buttonStyle(.plain).disabled(refactoredCode.isEmpty)
                    
                    Button { saveToFile() } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "square.and.arrow.down").font(.system(size: 9))
                            Text("Save As").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.white.opacity(0.06)).cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain).disabled(refactoredCode.isEmpty)
                    
                    if isProcessing {
                        // Stop Button
                        Button { isProcessing = false } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill").font(.system(size: 9))
                                Text("Stop").font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Generate
                        Button { generateRefactor() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles").font(.system(size: 10))
                                Text("Generate").font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(8)
                            .shadow(color: .purple.opacity(0.3), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain).disabled(originalCode.isEmpty)
                    }
                    
                    // Apply
                    Button { applyRefactor() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 10))
                            Text("Apply").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain).disabled(refactoredCode.isEmpty || isProcessing)
                    .opacity(refactoredCode.isEmpty ? 0.4 : 1)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    // MARK: - Templates
    
    private var migrationTemplates: some View {
        Group {
            TemplateChip(title: "🔄 Direct Translation", color: .blue) {
                instructions = "Translate this \(sourceLanguage) code to \(targetLanguage) with exact equivalent functionality. Preserve all logic and structure."
            }
            TemplateChip(title: "📐 Idiomatic Style", color: .purple) {
                instructions = "Convert to idiomatic \(targetLanguage) code. Use language-specific best practices, naming conventions, and patterns."
            }
            TemplateChip(title: "⚡ Optimized", color: .green) {
                instructions = "Migrate and optimize for \(targetLanguage). Use efficient data structures and language features."
            }
            TemplateChip(title: "🔒 Type Safe", color: .orange) {
                instructions = "Migrate with strong type safety. Add all type annotations and handle potential null/nil cases."
            }
        }
    }
    
    private var refactorTemplates: some View {
        Group {
            TemplateChip(title: "🛡️ Error Handling", color: .orange) {
                instructions = "Add comprehensive error handling with try-catch blocks and proper error messages."
            }
            TemplateChip(title: "📝 Documentation", color: .blue) {
                instructions = "Add detailed documentation comments explaining purpose, parameters, and return values."
            }
            TemplateChip(title: "⚡ Performance", color: .green) {
                instructions = "Optimize for better performance: reduce complexity, improve algorithms."
            }
            TemplateChip(title: "🧹 Clean Code", color: .cyan) {
                instructions = "Apply clean code principles: simplify logic, extract methods, reduce nesting."
            }
            TemplateChip(title: "🧪 Add Tests", color: .mint) {
                instructions = "Generate comprehensive unit tests covering edge cases."
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadCurrentFile() {
        if let file = appState.currentFile {
            originalCode = file.content
            sourceLanguage = file.language.lowercased()
        }
    }
    
    private func generateRefactor() {
        isProcessing = true
        errorMessage = ""
        refactoredCode = ""
        selectedTab = 0 // Switch to Code tab
        
        Task {
             // Vector Context Retrieval (Background)
             var vectorContext = ""
             if isUltraMode && !instructions.isEmpty {
                 let query = instructions + " " + String(originalCode.prefix(100))
                 if let response = try? await BackendService.shared.searchVectors(query: query, limit: 3) {
                     if !response.results.isEmpty {
                         vectorContext = "\n\n[Relevant Project Context]:\n" + response.results.map {
                             "File: \($0.file_path)\nSnippet: \($0.snippet)"
                         }.joined(separator: "\n---\n")
                     }
                 }
             }
             
             let enhancedInstructions = instructions + vectorContext
             
             await MainActor.run {
                 performRefactor(with: enhancedInstructions)
             }
        }
    }

    private func performRefactor(with enhancedInstructions: String) {
        if !folderFiles.isEmpty && selectedMode == .migration {
            generateBulkMigration() // Pass instructions TODO: Update Bulk too
            return
        }

        Task {
            do {
                if isUltraMode {
                    isProcessing = true
                    // Use enhanced chat with planning
                    let editorContext = ActiveEditorContext(
                        active_file: appState.currentFile?.path,
                        active_content: originalCode,
                        cursor_line: 0,
                        selected_text: nil,
                        open_files: []
                    )
                    
                    let request = AgentChatRequest(
                        session_id: appState.agentSessionId ?? "default",
                        message: enhancedInstructions, // Use enhanced instructions
                        editor_context: editorContext,
                        provider: appState.aiConfig.provider,
                        model: appState.aiConfig.model,
                        api_key: appState.aiConfig.apiKey,
                        auto_execute: true
                    )
                    
                    let response = try await BackendService.shared.agentEnhancedChat(request: request)
                    
                    await MainActor.run {
                        if let plan = response.plan {
                            self.currentPlan = plan
                            self.selectedTab = 2 // Switch to plan view if a plan was created
                        }
                        self.agentResults = response.tool_results
                        self.refactoredCode = response.content
                        self.isProcessing = false
                        generateReport() // Auto generate report
                    }
                } else {
                    // Standard refactor
                    let result = try await BackendService.shared.refactorCode(
                        code: originalCode,
                        instructions: enhancedInstructions, // Use enhanced instructions
                        provider: appState.aiConfig.provider,
                        model: appState.aiConfig.model,
                        apiKey: appState.aiConfig.apiKey
                    )
                    
                    await MainActor.run {
                        self.refactoredCode = result
                        self.isProcessing = false
                        generateReport()
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func generateBulkMigration() {
        Task {
            do {
                let response = try await BackendService.shared.refactorCodeUltra(
                    files: folderFiles,
                    instructions: instructions,
                    targetLanguage: targetLanguage,
                    provider: appState.aiProvider,
                    model: appState.aiModel,
                    apiKey: appState.apiKeys[appState.aiProvider] ?? ""
                )
                
                await MainActor.run {
                    // Save all files
                    let migratedFolderPath = folderFiles.first?.path ?? ""
                    let parentDir = (migratedFolderPath as NSString).deletingLastPathComponent
                    let newFolder = (parentDir as NSString).appendingPathComponent("migrated_\(targetLanguage)")
                    
                    Task {
                        do {
                            for file in response.refactored_files {
                                let oldName = (file.path as NSString).lastPathComponent
                                let nameWithoutExt = (oldName as NSString).deletingPathExtension
                                let newName = "\(nameWithoutExt).\(targetLanguage)"
                                let newPath = (newFolder as NSString).appendingPathComponent(newName)
                                
                                try await BackendService.shared.writeFile(path: newPath, content: file.content)
                            }
                            // await state.reloadFileTree()
                            await MainActor.run {
                                errorMessage = "Bulk migration complete. Saved to \(newFolder)"
                            }
                        } catch {
                            await MainActor.run {
                                errorMessage = "Failed to save migrated files: \(error.localizedDescription)"
                            }
                        }
                    }
                    
                    if let first = response.refactored_files.first {
                        refactoredCode = "// Bulk Migration Complete\n// Showing: \(first.path)\n\n" + first.content
                    }
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Bulk migration failed: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }

    private func selectFolderForMigration() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            // Scan folder for files (simplified)
            Task {
                do {
                    let fileInfos = try await BackendService.shared.listFiles(path: url.path, recursive: true)
                    var filesToMigrate: [FileContent] = []
                    for info in fileInfos where !info.isDirectory {
                        let content = try await BackendService.shared.readFile(path: info.path)
                        filesToMigrate.append(FileContent(path: info.path, content: content))
                    }
                    await MainActor.run {
                        self.folderFiles = filesToMigrate
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Failed to load folder: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func generateReport() {
        let srcLines = originalCode.components(separatedBy: "\n").count
        let dstLines = refactoredCode.components(separatedBy: "\n").count
        
        report = RefactorReport(
            sourceLanguage: sourceLanguage,
            targetLanguage: selectedMode == .migration ? targetLanguage : sourceLanguage,
            linesBefore: srcLines,
            linesAfter: dstLines,
            complexityBefore: CodeAnalyzer.shared.analyzeComplexity(code: originalCode, language: sourceLanguage).complexity,
            complexityAfter: CodeAnalyzer.shared.analyzeComplexity(code: refactoredCode, language: selectedMode == .migration ? targetLanguage : sourceLanguage).complexity,
            changes: [
                "Converted code structure",
                "Applied language-specific patterns",
                "Updated syntax and keywords",
                "Adjusted type system usage"
            ],
            recommendations: [
                "Review generated code for edge cases",
                "Add unit tests for critical functions",
                "Verify external dependencies are available"
            ],
            timestamp: Date()
        )
    }
    
    private func applyRefactor() {
        guard let file = appState.currentFile else { return }
        
        let cleanedCode = cleanMarkdownCode(refactoredCode)
        
        if selectedMode == .migration {
            // Save as new file with target language extension
            let oldURL = URL(fileURLWithPath: file.path)
            let baseName = oldURL.deletingPathExtension().lastPathComponent
            let newName = "\(baseName)_\(targetLanguage).\(targetLanguage)"
            let newPath = oldURL.deletingLastPathComponent().appendingPathComponent(newName).path
            
            Task {
                do {
                    try await BackendService.shared.writeFile(path: newPath, content: cleanedCode)
                    // await state.reloadFileTree()
                    await MainActor.run {
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Failed to apply migration: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            // Apply to same file AND auto-save
            Task {
                do {
                    try await BackendService.shared.writeFile(path: file.path, content: cleanedCode)
                    await MainActor.run {
                        appState.updateFileContent(cleanedCode, for: file.id)
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Failed to save changes: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func cleanMarkdownCode(_ code: String) -> String {
        var lines = code.components(separatedBy: .newlines)
        // Remove leading backticks if present
        if let first = lines.first, first.contains("```") {
            lines.removeFirst()
        }
        // Remove trailing backticks if present
        if let last = lines.last, last.contains("```") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(refactoredCode, forType: .string)
    }
    
    private func saveToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "refactored.\(selectedMode == .migration ? targetLanguage : sourceLanguage)"
        panel.allowedContentTypes = [.plainText]
        
        if panel.runModal() == .OK, let url = panel.url {
            let cleaned = cleanMarkdownCode(refactoredCode)
            try? cleaned.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    private func exportReport(format: ReportFormat) {
        guard let report = report else { return }
        
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "refactor_report.\(format.extension)"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                if format == .pdf {
                     await MainActor.run {
                         isProcessing = true
                     }
                     
                     let html = generateFormalHTML(report: report)
                     
                     // Use PDFGenerator
                     PDFGenerator.shared.generatePDF(htmlContent: html) { result in
                         Task {
                             await MainActor.run {
                                 isProcessing = false
                                 switch result {
                                 case .success(let data):
                                     do {
                                         try data.write(to: url)
                                         errorMessage = "Report exported to \(url.lastPathComponent)"
                                     } catch {
                                         errorMessage = "Failed to save PDF: \(error.localizedDescription)"
                                     }
                                 case .failure(let error):
                                     errorMessage = "PDF Generation failed: \(error.localizedDescription)"
                                 }
                             }
                         }
                     }
                } else {
                    do {
                        let content = try await generateReportContent(report: report, format: format)
                        try content.write(to: url, atomically: true, encoding: .utf8)
                        await MainActor.run {
                            errorMessage = "Report exported to \(url.lastPathComponent)"
                        }
                    } catch {
                        await MainActor.run {
                            errorMessage = "Export failed: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Official Report Template
    private func generateFormalHTML(report: RefactorReport) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; line-height: 1.6; color: #333; max-width: 800px; margin: 0 auto; padding: 40px; }
                .header { border-bottom: 2px solid #FF6F00; padding-bottom: 20px; margin-bottom: 30px; display: flex; justify-content: space-between; align-items: center; }
                .title { font-size: 28px; font-weight: bold; color: #003366; }
                .subtitle { font-size: 14px; color: #666; text-transform: uppercase; letter-spacing: 1px; }
                .meta-table { width: 100%; border-collapse: collapse; margin-bottom: 30px; }
                .meta-table th { text-align: left; color: #666; font-weight: normal; padding: 8px 0; border-bottom: 1px solid #eee; }
                .meta-table td { text-align: right; font-weight: bold; padding: 8px 0; border-bottom: 1px solid #eee; }
                .section { margin-bottom: 30px; background: #f9f9f9; padding: 20px; border-radius: 8px; border-left: 4px solid #003366; }
                .section-title { font-size: 18px; font-weight: bold; margin-bottom: 15px; color: #003366; }
                .stat-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 20px; }
                .stat-box { background: white; padding: 15px; border-radius: 6px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
                .stat-label { font-size: 12px; color: #666; display: block; margin-bottom: 4px; }
                .stat-value { font-size: 24px; font-weight: bold; color: #FF6F00; }
                ul { padding-left: 20px; margin: 0; }
                li { margin-bottom: 8px; }
                .footer { margin-top: 50px; border-top: 1px solid #eee; padding-top: 20px; font-size: 12px; color: #999; text-align: center; }
                .badge { display: inline-block; padding: 4px 8px; border-radius: 4px; font-size: 11px; font-weight: bold; color: white; background: #003366; }
                code { background: #f0f0f0; padding: 2px 5px; border-radius: 3px; font-family: Menlo, monospace; font-size: 0.9em; }
            </style>
        </head>
        <body>
            <div class="header">
                <div>
                    <div class="title">Code Refactor Report</div>
                    <div class="subtitle">Official Analysis Document</div>
                </div>
                <div class="badge">CONFIDENTIAL</div>
            </div>
            
            <div class="stat-grid">
                 <div class="stat-box">
                    <span class="stat-label">Source Language</span>
                    <span class="stat-value">\(report.sourceLanguage.capitalized)</span>
                 </div>
                 <div class="stat-box">
                    <span class="stat-label">Target Language</span>
                    <span class="stat-value">\(report.targetLanguage.capitalized)</span>
                 </div>
                 <div class="stat-box">
                    <span class="stat-label">Lines Refactored</span>
                    <span class="stat-value">\(report.linesBefore) → \(report.linesAfter)</span>
                 </div>
                 <div class="stat-box">
                    <span class="stat-label">Complexity Reduction</span>
                    <span class="stat-value">\(report.complexityBefore) → \(report.complexityAfter)</span>
                 </div>
            </div>
            
            <div class="section">
                <div class="section-title">Executive Summary</div>
                <p>This report details the automated refactoring process performed by CodeTunner AI. The source code has been analyzed, optimized, and transformed to meet modern standards and specific user requirements.</p>
            </div>
            
            <div class="section">
                <div class="section-title">Key Changes Implemented</div>
                <ul>
                    \(report.changes.map { "<li>\($0)</li>" }.joined(separator: "\n"))
                </ul>
            </div>
            
            \(report.recommendations.isEmpty ? "" : """
            <div class="section" style="border-left-color: #FF6F00;">
                <div class="section-title">AI Recommendations</div>
                <ul>
                    \(report.recommendations.map { "<li>\($0)</li>" }.joined(separator: "\n"))
                </ul>
            </div>
            """)
            
            <div class="footer">
                Generated by CodeTunner AI • \(report.timestamp.formatted(date: .long, time: .shortened))
            </div>
        </body>
        </html>
        """
    }
    
    
    private func generateReportContent(report: RefactorReport, format: ReportFormat) async throws -> String {
        // For now, generate text format. PDF/DOCX will need backend support.
        return """
        ═══════════════════════════════════════════════════════
        AI REFACTOR PRO - MIGRATION REPORT
        ═══════════════════════════════════════════════════════
        
        Generated: \(report.timestamp.formatted())
        
        ───────────────────────────────────────────────────────
        SUMMARY
        ───────────────────────────────────────────────────────
        Source Language:     \(report.sourceLanguage.capitalized)
        Target Language:     \(report.targetLanguage.capitalized)
        Lines Before:        \(report.linesBefore)
        Lines After:         \(report.linesAfter)
        Complexity Before:   \(report.complexityBefore)
        Complexity After:    \(report.complexityAfter)
        
        ───────────────────────────────────────────────────────
        CHANGES MADE
        ───────────────────────────────────────────────────────
        \(report.changes.map { "• \($0)" }.joined(separator: "\n"))
        
        ───────────────────────────────────────────────────────
        RECOMMENDATIONS
        ───────────────────────────────────────────────────────
        \(report.recommendations.map { "💡 \($0)" }.joined(separator: "\n"))
        
        ───────────────────────────────────────────────────────
        ORIGINAL CODE
        ───────────────────────────────────────────────────────
        \(originalCode)
        
        ───────────────────────────────────────────────────────
        REFACTORED CODE
        ───────────────────────────────────────────────────────
        \(refactoredCode)
        
        ═══════════════════════════════════════════════════════
        © 2025 Project IDX | SPU AI CLUB
        ═══════════════════════════════════════════════════════
        """
    }
}

// MARK: - Supporting Types

enum RefactorMode: String, CaseIterable {
    case refactor = "refactor"
    case migration = "migration"
    
    var title: String {
        switch self {
        case .refactor: return "🔧 Refactor"
        case .migration: return "🔄 Migration"
        }
    }
}

enum ReportFormat {
    case pdf, docx, text
    
    var `extension`: String {
        switch self {
        case .pdf: return "pdf"
        case .docx: return "docx"
        case .text: return "txt"
        }
    }
}

struct RefactorReport {
    let sourceLanguage: String
    let targetLanguage: String
    let linesBefore: Int
    let linesAfter: Int
    let complexityBefore: Int
    let complexityAfter: Int
    let changes: [String]
    let recommendations: [String]
    let timestamp: Date
}

// MARK: - Helper Views

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

struct ReportStatItem: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
        }
    }
}

struct TemplateChip: View {
    let title: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovering ? .white : color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isHovering ? color : color.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

struct PlanPreviewView: View {
    let plan: ExecutionPlan
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Execution Plan")
                        .font(.headline)
                    Text(plan.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                StatusBadge(status: plan.status)
            }
            .padding(.bottom, 8)
            
            ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    // Timeline
                    VStack(spacing: 0) {
                        StepIndicator(status: step.status, index: index + 1)
                        
                        if index < plan.steps.count - 1 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 2, height: 24)
                        }
                    }
                    
                    // Content
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.description)
                            .font(.system(size: 13, weight: .medium))
                            .strikethrough(step.status.lowercased() == "completed")
                        
                        HStack {
                            Image(systemName: toolIcon(step.tool))
                            Text(step.tool)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        if let result = step.result {
                            Text(result)
                                .font(.caption2)
                                .padding(6)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                                .foregroundColor(.blue)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.bottom, index < plan.steps.count - 1 ? 0 : 8)
                }
            }
        }
        .padding(20)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func toolIcon(_ tool: String) -> String {
        switch tool {
        case "read_file": return "doc.text.magnifyingglass"
        case "write_file": return "pencil.and.outline"
        case "edit_file": return "doc.text.fill"
        case "search_rag": return "sparkles"
        case "create_plan": return "list.bullet.indent"
        case "execute_command": return "terminal.fill"
        default: return "wrench.and.screwdriver"
        }
    }
}

struct SelfCorrectionLogView: View {
    let results: [AgentToolResult]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Self-Correction Log", systemImage: "clock.arrow.2.circlepath")
                .font(.headline)
                .foregroundColor(.orange)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(results.filter { $0.tool_call_id.contains("execute_command") || !$0.success }, id: \.tool_call_id) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(result.success ? .green : .red)
                                Text(result.success ? "Verification Passed" : "Issue Detected")
                                    .font(.system(size: 12, weight: .bold))
                                Spacer()
                            }
                            
                            Text(result.output)
                                .font(.system(size: 10, design: .monospaced))
                                .padding(8)
                                .background(Color.black.opacity(0.05))
                                .cornerRadius(6)
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
}

struct StepIndicator: View {
    let status: String
    let index: Int
    
    var body: some View {
        ZStack {
            if status.lowercased() == "completed" {
                Circle()
                    .fill(Color.green)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            } else if status.lowercased() == "running" || status.lowercased() == "executing" {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 20, height: 20)
                ProgressView()
                    .controlSize(.mini)
                    .colorInvert()
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 20, height: 20)
                Text("\(index)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct StatusBadge: View {
    let status: String
    
    var body: some View {
        Text(status.uppercased())
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.1))
            .foregroundColor(statusColor)
            .cornerRadius(4)
    }
    
    var statusColor: Color {
        switch status.lowercased() {
        case "completed": return .green
        case "executing", "running", "verifying": return .blue
        case "failed": return .red
        case "queued": return .orange
        case "correcting": return .purple
        default: return .secondary
        }
    }
}
