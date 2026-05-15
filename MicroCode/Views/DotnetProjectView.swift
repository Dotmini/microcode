//
//  DotnetProjectView.swift
//  MicroCode
//
//  Xcode-style .NET Project Creation with Build/Run/Preview
//

import SwiftUI
import WebKit

// MARK: - .NET Project View

struct DotnetProjectView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    
    // Wizard State
    @State private var currentStep: Int = 0
    @State private var selectedTemplate: DotnetTemplate = .console
    @State private var projectName: String = "MyApp"
    @State private var projectPath: String = ""
    @State private var organizationName: String = "com.company"
    @State private var useGit: Bool = true
    @State private var isCreating: Bool = false
    @State private var error: String?
    @State private var createdProjectPath: String?
    
    // Build/Run State
    @State private var isBuilding: Bool = false
    @State private var isRunning: Bool = false
    @State private var buildOutput: String = ""
    @State private var showPreview: Bool = false
    @State private var previewURL: String = "http://localhost:5000"
    
    private let steps = ["Template", "Options", "Location", "Summary"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            if createdProjectPath != nil {
                // Project Management View
                projectManagementView
            } else {
                // Wizard View
                HStack(spacing: 0) {
                    stepsSidebar
                        .frame(width: 180)
                    
                    Divider()
                    
                    VStack(spacing: 0) {
                        stepContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        Divider()
                        
                        bottomButtons
                    }
                }
            }
        }
        .frame(width: 850, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if projectPath.isEmpty {
                projectPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects").path
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "cube.box.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(createdProjectPath != nil ? projectName : "New .NET Project")
                    .font(.title3.weight(.semibold))
                Text(createdProjectPath != nil ? "Build, Run & Preview" : "Create a new .NET application")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Steps Sidebar
    
    private var stepsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(index == currentStep ? Color.accentColor : (index < currentStep ? Color.green : Color.gray.opacity(0.3)))
                            .frame(width: 26, height: 26)
                        
                        if index < currentStep {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(index == currentStep ? .white : .secondary)
                        }
                    }
                    
                    Text(step)
                        .font(.system(size: 12, weight: index == currentStep ? .semibold : .regular))
                        .foregroundColor(index == currentStep ? .primary : .secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(index == currentStep ? Color.accentColor.opacity(0.1) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    if index <= currentStep {
                        currentStep = index
                    }
                }
            }
            
            Spacer()
            
            // .NET Info
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text(".NET 8.0")
                        .font(.caption)
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Step Content
    
    @ViewBuilder
    private var stepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch currentStep {
                case 0:
                    templateView
                case 1:
                    optionsView
                case 2:
                    locationView
                case 3:
                    summaryView
                default:
                    EmptyView()
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Template View
    
    private var templateView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a template")
                .font(.title3.weight(.semibold))
            
            Text("Select the type of .NET application you want to create.")
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(DotnetTemplate.allCases, id: \.self) { template in
                    TemplateCard(
                        template: template,
                        isSelected: selectedTemplate == template
                    ) {
                        selectedTemplate = template
                    }
                }
            }
        }
    }
    
    // MARK: - Options View
    
    private var optionsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Configure your project")
                .font(.title3.weight(.semibold))
            
            // Project Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Product Name")
                    .font(.subheadline.weight(.medium))
                
                TextField("MyApp", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                
                Text("The name of your application")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Organization
            VStack(alignment: .leading, spacing: 6) {
                Text("Organization Identifier")
                    .font(.subheadline.weight(.medium))
                
                TextField("com.company", text: $organizationName)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Bundle ID Preview
            GroupBox {
                HStack {
                    Text("Bundle Identifier:")
                        .foregroundColor(.secondary)
                    Text("\(organizationName).\(projectName.lowercased().replacingOccurrences(of: " ", with: ""))")
                        .font(.system(.body, design: .monospaced))
                }
            }
            
            Divider()
            
            Toggle("Initialize Git repository", isOn: $useGit)
        }
    }
    
    // MARK: - Location View
    
    private var locationView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose a location")
                .font(.title3.weight(.semibold))
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Save project in:")
                    .font(.subheadline.weight(.medium))
                
                HStack {
                    TextField("Location", text: $projectPath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                    
                    Button("Browse...") {
                        selectLocation()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Full path:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(fullProjectPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.blue)
                }
            }
        }
    }
    
    // MARK: - Summary View
    
    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Review your settings")
                .font(.title3.weight(.semibold))
            
            GroupBox {
                VStack(spacing: 12) {
                    SummaryRow(icon: selectedTemplate.icon, label: "Template", value: selectedTemplate.name)
                    Divider()
                    SummaryRow(icon: "textformat", label: "Name", value: projectName)
                    Divider()
                    SummaryRow(icon: "building.2", label: "Organization", value: organizationName)
                    Divider()
                    SummaryRow(icon: "folder", label: "Location", value: fullProjectPath)
                    Divider()
                    SummaryRow(icon: "arrow.triangle.branch", label: "Git", value: useGit ? "Yes" : "No")
                }
                .padding(.vertical, 4)
            }
            
            if let error = error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Bottom Buttons
    
    private var bottomButtons: some View {
        HStack {
            Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            if currentStep > 0 {
                Button("Previous") {
                    withAnimation { currentStep -= 1 }
                }
                .buttonStyle(.bordered)
            }
            
            if currentStep < steps.count - 1 {
                Button("Next") {
                    withAnimation { currentStep += 1 }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed)
            } else {
                Button(action: createProject) {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 60)
                    } else {
                        Text("Create")
                            .frame(width: 60)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating)
            }
        }
        .padding()
    }
    
    // MARK: - Project Management View (After Creation)
    
    private var projectManagementView: some View {
        CompatHSplitView {
            // Left: Build/Run Controls
            VStack(alignment: .leading, spacing: 16) {
                // Project Info
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(projectName, systemImage: "folder.fill")
                            .font(.headline)
                        
                        HStack {
                            Image(systemName: selectedTemplate.icon)
                                .foregroundColor(selectedTemplate.color)
                            Text(selectedTemplate.name)
                                .font(.caption)
                        }
                        
                        Text(createdProjectPath ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                // Actions
                GroupBox {
                    VStack(spacing: 10) {
                        Button(action: buildProject) {
                            HStack {
                                Image(systemName: "hammer.fill")
                                Text("Build")
                                Spacer()
                                if isBuilding {
                                    ProgressView().scaleEffect(0.7)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBuilding || isRunning)
                        
                        Button(action: runProject) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Run")
                                Spacer()
                                if isRunning {
                                    ProgressView().scaleEffect(0.7)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isBuilding || isRunning)
                        
                        if selectedTemplate.isWebProject {
                            Divider()
                            
                            Button(action: { showPreview.toggle() }) {
                                HStack {
                                    Image(systemName: showPreview ? "eye.slash" : "eye")
                                    Text(showPreview ? "Hide Preview" : "Show Preview")
                                    Spacer()
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: openInBrowser) {
                                HStack {
                                    Image(systemName: "safari")
                                    Text("Open in Browser")
                                    Spacer()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Divider()
                        
                        Button(action: openInMicroCode) {
                            HStack {
                                Image(systemName: "doc.text")
                                Text("Open in Editor")
                                Spacer()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // Build Output
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Output")
                            .font(.caption.weight(.semibold))
                        
                        ScrollView {
                            Text(buildOutput.isEmpty ? "Ready to build..." : buildOutput)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 150)
                    }
                }
                
                Spacer()
            }
            .padding()
            .frame(minWidth: 280, maxWidth: 320)
            
            Divider()
            
            // Right: Preview (for web projects)
            if selectedTemplate.isWebProject && showPreview {
                WebPreviewView(url: previewURL)
            } else {
                // Welcome/placeholder
                VStack {
                    Image(systemName: selectedTemplate.icon)
                        .font(.system(size: 64))
                        .foregroundColor(selectedTemplate.color.opacity(0.5))
                    
                    Text("Project Created Successfully!")
                        .font(.title2)
                        .padding(.top)
                    
                    Text("Use the controls on the left to build and run your project.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    if selectedTemplate.isWebProject {
                        Text("Click 'Run' then 'Show Preview' to see your web app.")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            }
        }
    }
    
    // MARK: - Helpers
    
    private var fullProjectPath: String {
        (projectPath as NSString).appendingPathComponent(projectName)
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case 0: return true
        case 1: return !projectName.isEmpty
        case 2: return !projectPath.isEmpty
        default: return true
        }
    }
    
    private func selectLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            projectPath = url.path
        }
    }
    
    private func createProject() {
        isCreating = true
        error = nil
        
        Task {
            do {
                let fm = FileManager.default
                let projectURL = URL(fileURLWithPath: fullProjectPath)
                
                try fm.createDirectory(at: projectURL, withIntermediateDirectories: true)
                
                // Run dotnet new
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/dotnet")
                process.arguments = ["new", selectedTemplate.cliName, "-n", projectName, "-o", "."]
                process.currentDirectoryURL = projectURL
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    if useGit {
                        let gitProcess = Process()
                        gitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                        gitProcess.arguments = ["init"]
                        gitProcess.currentDirectoryURL = projectURL
                        try? gitProcess.run()
                        gitProcess.waitUntilExit()
                    }
                    
                    await MainActor.run {
                        createdProjectPath = fullProjectPath
                        buildOutput = "✅ Project created at \(fullProjectPath)"
                        isCreating = false
                    }
                } else {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                    
                    await MainActor.run {
                        error = output
                        isCreating = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isCreating = false
                }
            }
        }
    }
    
    private func buildProject() {
        guard let path = createdProjectPath else { return }
        
        isBuilding = true
        buildOutput = "🔨 Building...\n"
        
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/dotnet")
            process.arguments = ["build"]
            process.currentDirectoryURL = URL(fileURLWithPath: path)
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                await MainActor.run {
                    buildOutput += output
                    buildOutput += process.terminationStatus == 0 ? "\n✅ Build succeeded!" : "\n❌ Build failed!"
                    isBuilding = false
                }
            } catch {
                await MainActor.run {
                    buildOutput += "❌ Error: \(error.localizedDescription)"
                    isBuilding = false
                }
            }
        }
    }
    
    private func runProject() {
        guard let path = createdProjectPath else { return }
        
        isRunning = true
        buildOutput = "🚀 Running...\n"
        
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/dotnet")
            process.arguments = ["run"]
            process.currentDirectoryURL = URL(fileURLWithPath: path)
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                
                // For web projects, show preview after a delay
                if selectedTemplate.isWebProject {
                    await MainActor.run {
                        buildOutput += "🌐 Starting web server...\n"
                    }
                    
                    try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                    
                    await MainActor.run {
                        showPreview = true
                        buildOutput += "✅ Server running at \(previewURL)\n"
                    }
                }
                
                // Wait for process (non-blocking for web apps)
                if !selectedTemplate.isWebProject {
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    await MainActor.run {
                        buildOutput += output
                        isRunning = false
                    }
                } else {
                    await MainActor.run {
                        isRunning = false
                    }
                }
            } catch {
                await MainActor.run {
                    buildOutput += "❌ Error: \(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }
    
    private func openInBrowser() {
        if let url = URL(string: previewURL) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openInMicroCode() {
        guard let path = createdProjectPath else { return }
        appState.openProjectFolder(url: URL(fileURLWithPath: path))
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Template Card

struct TemplateCard: View {
    let template: DotnetTemplate
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(template.color.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: template.icon)
                        .font(.system(size: 24))
                        .foregroundColor(template.color)
                }
                
                Text(template.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                
                Text(template.description)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 24)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Summary Row

struct SummaryRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(label)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
    }
}

// MARK: - Web Preview View

struct WebPreviewView: View {
    let url: String
    
    var body: some View {
        VStack(spacing: 0) {
            // URL Bar
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.green)
                Text(url)
                    .font(.system(size: 12, design: .monospaced))
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // WebView
            WebViewWrapper(url: url)
        }
    }
}

// MARK: - WebView Wrapper

struct WebViewWrapper: NSViewRepresentable {
    let url: String
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        if let url = URL(string: url) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        if let url = URL(string: url) {
            nsView.load(URLRequest(url: url))
        }
    }
}

// MARK: - Dotnet Template

enum DotnetTemplate: String, CaseIterable {
    case console
    case classlib
    case webapi
    case mvc
    case blazorserver
    case blazorwasm
    case maui
    case worker
    
    var name: String {
        switch self {
        case .console: return "Console App"
        case .classlib: return "Class Library"
        case .webapi: return "Web API"
        case .mvc: return "MVC Web App"
        case .blazorserver: return "Blazor Server"
        case .blazorwasm: return "Blazor WASM"
        case .maui: return "MAUI App"
        case .worker: return "Worker Service"
        }
    }
    
    var cliName: String {
        switch self {
        case .maui: return "maui"
        default: return rawValue
        }
    }
    
    var icon: String {
        switch self {
        case .console: return "terminal"
        case .classlib: return "building.2"
        case .webapi: return "network"
        case .mvc: return "safari"
        case .blazorserver: return "bolt.fill"
        case .blazorwasm: return "bolt"
        case .maui: return "macwindow"
        case .worker: return "gearshape.2"
        }
    }
    
    var description: String {
        switch self {
        case .console: return "Command-line app"
        case .classlib: return "Reusable library"
        case .webapi: return "RESTful HTTP API"
        case .mvc: return "MVC web app"
        case .blazorserver: return "Server-side Blazor"
        case .blazorwasm: return "WebAssembly Blazor"
        case .maui: return "Cross-platform UI"
        case .worker: return "Background service"
        }
    }
    
    var color: Color {
        switch self {
        case .console: return .green
        case .classlib: return .blue
        case .webapi: return .orange
        case .mvc: return .purple
        case .blazorserver: return .pink
        case .blazorwasm: return .cyan
        case .maui: return .indigo
        case .worker: return .gray
        }
    }
    
    var isWebProject: Bool {
        switch self {
        case .webapi, .mvc, .blazorserver, .blazorwasm:
            return true
        default:
            return false
        }
    }
}
