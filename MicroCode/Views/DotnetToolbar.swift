//
//  DotnetToolbar.swift
//  MicroCode
//
//  .NET Project Build/Run/Debug toolbar bar
//

import SwiftUI
import WebKit

// MARK: - .NET Toolbar

struct DotnetToolbar: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var dotnetManager = DotnetToolbarManager()
    
    var body: some View {
        if dotnetManager.isDotnetProject {
            HStack(spacing: 8) {
                // Project indicator
                HStack(spacing: 4) {
                    Image(systemName: "cube.box.fill")
                        .foregroundColor(.purple)
                    Text(dotnetManager.projectName)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(4)
                
                Divider().frame(height: 16)
                
                // Configuration picker
                Picker("", selection: $dotnetManager.configuration) {
                    Text("Debug").tag("Debug")
                    Text("Release").tag("Release")
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                
                Divider().frame(height: 16)
                
                // Build button
                Button(action: { dotnetManager.build() }) {
                    HStack(spacing: 4) {
                        if dotnetManager.isBuilding {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "hammer.fill")
                        }
                        Text("Build")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .disabled(dotnetManager.isBuilding || dotnetManager.isRunning)
                
                // Run button
                Button(action: { dotnetManager.run() }) {
                    HStack(spacing: 4) {
                        if dotnetManager.isRunning {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text("Run")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(dotnetManager.isBuilding || dotnetManager.isRunning)
                
                // Stop button
                if dotnetManager.isRunning {
                    Button(action: { dotnetManager.stop() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                
                // Hot Reload (for web projects)
                if dotnetManager.isWebProject {
                    Divider().frame(height: 16)
                    
                    Toggle(isOn: $dotnetManager.hotReloadEnabled) {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(dotnetManager.hotReloadEnabled ? .orange : .secondary)
                            Text("Hot Reload")
                                .font(.system(size: 11))
                        }
                    }
                    .toggleStyle(.button)
                    
                    Button(action: { dotnetManager.showPreview.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: dotnetManager.showPreview ? "eye.slash" : "eye")
                            Text("Preview")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { dotnetManager.openInBrowser() }) {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.bordered)
                    .help("Open in Browser")
                }
                
                Spacer()
                
                // Status
                if !dotnetManager.statusMessage.isEmpty {
                    Text(dotnetManager.statusMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                // Output toggle
                Button(action: { dotnetManager.showOutput.toggle() }) {
                    Image(systemName: "terminal")
                        .foregroundColor(dotnetManager.showOutput ? .accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Toggle Output")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Output panel
            if dotnetManager.showOutput && !dotnetManager.buildOutput.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                    
                    ScrollView {
                        Text(dotnetManager.buildOutput)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(height: 120)
                    .background(Color.black.opacity(0.3))
                }
            }
            
            Divider()
        }
    }
}

// MARK: - .NET Toolbar Manager

@MainActor
final class DotnetToolbarManager: ObservableObject {
    @Published var isDotnetProject: Bool = false
    @Published var projectName: String = ""
    @Published var projectPath: String = ""
    @Published var configuration: String = "Debug"
    @Published var isBuilding: Bool = false
    @Published var isRunning: Bool = false
    @Published var buildOutput: String = ""
    @Published var statusMessage: String = ""
    @Published var showOutput: Bool = false
    @Published var showPreview: Bool = false
    @Published var hotReloadEnabled: Bool = true
    @Published var isWebProject: Bool = false
    @Published var previewURL: String = "http://localhost:5000"
    
    private var runProcess: Process?
    
    init() {
        // Listen for project folder changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(projectFolderChanged),
            name: NSNotification.Name("ProjectFolderChanged"),
            object: nil
        )
        
        // Check current folder
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkForDotnetProject()
        }
    }
    
    @objc private func projectFolderChanged() {
        checkForDotnetProject()
    }
    
    func checkForDotnetProject() {
        // Get current project folder from AppState
        guard let projectURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            isDotnetProject = false
            return
        }
        
        // For now, check common locations
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        
        // Find .csproj or .sln files
        if let contents = try? fm.contentsOfDirectory(atPath: cwd) {
            for file in contents {
                if file.hasSuffix(".csproj") || file.hasSuffix(".sln") {
                    isDotnetProject = true
                    projectPath = cwd
                    projectName = (file as NSString).deletingPathExtension
                    
                    // Check if web project
                    if let projContents = try? String(contentsOfFile: "\(cwd)/\(file)", encoding: .utf8) {
                        isWebProject = projContents.contains("Microsoft.NET.Sdk.Web") ||
                                      projContents.contains("Microsoft.NET.Sdk.BlazorWebAssembly")
                    }
                    
                    return
                }
            }
        }
        
        isDotnetProject = false
    }
    
    // MARK: - Actions
    
    func build() {
        isBuilding = true
        statusMessage = "Building..."
        buildOutput = "🔨 Building \(projectName)...\n"
        
        Task {
            await executeDotnetCommand(["build", "-c", configuration])
            
            await MainActor.run {
                isBuilding = false
                statusMessage = buildOutput.contains("error") ? "Build failed" : "Build succeeded"
            }
        }
    }
    
    func run() {
        isRunning = true
        statusMessage = "Running..."
        buildOutput = "🚀 Running \(projectName)...\n"
        
        Task {
            let args = hotReloadEnabled && isWebProject 
                ? ["watch", "run", "-c", configuration]
                : ["run", "-c", configuration]
            
            await executeDotnetCommand(args, waitForExit: !isWebProject)
            
            if isWebProject {
                // Wait for server to start
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    statusMessage = "Running on \(previewURL)"
                    if showPreview {
                        // Preview will auto-update via binding
                    }
                }
            }
        }
    }
    
    func stop() {
        runProcess?.terminate()
        runProcess = nil
        isRunning = false
        statusMessage = "Stopped"
        buildOutput += "\n⏹️ Process stopped"
    }
    
    func openInBrowser() {
        if let url = URL(string: previewURL) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func executeDotnetCommand(_ args: [String], waitForExit: Bool = true) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: findDotnetPath())
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        if !waitForExit {
            runProcess = process
        }
        
        // Read output
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                DispatchQueue.main.async {
                    self?.buildOutput += text
                }
            }
        }
        
        do {
            try process.run()
            
            if waitForExit {
                process.waitUntilExit()
                
                await MainActor.run {
                    if process.terminationStatus == 0 {
                        buildOutput += "\n✅ Success"
                    } else {
                        buildOutput += "\n❌ Failed with exit code \(process.terminationStatus)"
                    }
                    isRunning = false
                }
            }
        } catch {
            await MainActor.run {
                buildOutput += "\n❌ Error: \(error.localizedDescription)"
                isRunning = false
                isBuilding = false
            }
        }
    }
    
    private func findDotnetPath() -> String {
        let paths = [
            "/opt/homebrew/bin/dotnet",
            "/usr/local/bin/dotnet",
            "/usr/bin/dotnet"
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return "dotnet"
    }
}

// MARK: - Preview Panel (for Web projects)

struct DotnetPreviewPanel: View {
    let url: String
    @Binding var isVisible: Bool
    
    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                // URL bar
                HStack {
                    Image(systemName: "globe")
                        .foregroundColor(.green)
                    Text(url)
                        .font(.system(size: 11, design: .monospaced))
                    Spacer()
                    
                    Button(action: {}) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    
                    Button(action: { isVisible = false }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()
                
                // WebView
                DotnetWebView(url: url)
            }
        }
    }
}

struct DotnetWebView: NSViewRepresentable {
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
