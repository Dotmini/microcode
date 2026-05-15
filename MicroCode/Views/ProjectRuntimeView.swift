//
//  ProjectRuntimeView.swift
//  MicroCode
//
//  Unified Project Runtime Manager
//  Adapts to the detected project type (Node, Python, Rust, etc.)
//

import SwiftUI

struct ProjectRuntimeView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: appState.currentProjectType.icon)
                    .foregroundColor(Color(appState.currentProjectType.color))
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text("Project Runtime")
                        .font(.headline)
                    Text(appState.currentProjectType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Content
            Group {
                switch appState.currentProjectType {
                case .nodejs:
                    NodeProjectManagerView()
                case .python:
                    PythonRuntimeView()
                case .rust:
                    RustRuntimeView()
                case .dotnet:
                    DotnetRuntimeView()
                case .unknown:
                    GenericRuntimeView()
                default:
                    GenericRuntimeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 500)
    }
}

// Placeholder Views for unimplemented runtimes
// MARK: - Python Runtime View
struct PythonRuntimeView: View {
    @ObservedObject var envManager = PythonEnvManager.shared
    @State private var newEnvName: String = ".venv"
    @State private var showingCreateEnv: Bool = false
    @State private var selectedEnv: PythonEnvironment?
    @State private var packagesToInstall: String = ""
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar: Environments
            VStack(alignment: .leading, spacing: 0) {
                Text("Environments")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                List(envManager.environments, selection: $selectedEnv) { env in
                    EnvRow(env: env, isActive: envManager.activeEnvironment?.id == env.id)
                        .tag(env)
                }
                .listStyle(.sidebar)
            }
            .frame(width: 200)
            
            Divider()
            
            // Detail / Actions
            VStack(alignment: .leading, spacing: 16) {
                if let env = selectedEnv {
                    // Environment Info
                    GroupBox(label: Text("Environment Details")) {
                        VStack(alignment: .leading, spacing: 8) {
                            CompatLabeledContent("Name", value: env.name)
                            CompatLabeledContent("Python", value: env.pythonVersion)
                            CompatLabeledContent("Path", value: env.path.path)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Actions
                    HStack {
                        Button(action: { envManager.activateEnvironment(env) }) {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                Text("Activate")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(envManager.activeEnvironment?.id == env.id)
                        
                        Button(action: { deleteEnv(env) }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete")
                            }
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    }
                    
                    // Install Packages
                    GroupBox(label: Text("Install Packages")) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Package names (space separated)", text: $packagesToInstall)
                                    .textFieldStyle(.roundedBorder)
                                
                                Button("Install") {
                                    installPackages(env)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(packagesToInstall.isEmpty || envManager.isWorking)
                            }
                            
                            Text("Example: numpy pandas matplotlib")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Spacer()
                } else {
                    // Empty State or Create New
                    VStack {
                        Spacer()
                        Image(systemName: "terminal")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Environment Selected")
                            .foregroundColor(.secondary)
                            .padding(.bottom)
                        
                        Button("Create New Virtual Environment") {
                            showingCreateEnv = true
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingCreateEnv) {
            CreateEnvSheet()
        }
        .onAppear {
            // Auto select active or first
            if let active = envManager.activeEnvironment {
                selectedEnv = active
            } else {
                selectedEnv = envManager.environments.first
            }
        }
    }
    
    private func installPackages(_ env: PythonEnvironment) {
        let packages = packagesToInstall.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        envManager.installPackages(packages, in: env) { success, _ in
            if success {
                packagesToInstall = ""
            }
        }
    }
    
    private func deleteEnv(_ env: PythonEnvironment) {
        envManager.deleteEnvironment(env) { _ in
            selectedEnv = nil
        }
    }
}

// MARK: - Rust Runtime View
struct RustRuntimeView: View {
    @EnvironmentObject var appState: AppState
    @State private var envVariables: [EnvVariable] = []
    @State private var statusMessage: String = ""
    @State private var cargoInfo: String = "Loading..."
    
    var body: some View {
        VStack(spacing: 20) {
            // Cargo Info
            GroupBox(label: Text("Cargo Project Info")) {
                HStack {
                    Image(systemName: "gearshape.2.fill")
                        .font(.title)
                        .foregroundColor(.orange)
                    
                    Text(cargoInfo)
                        .font(.system(.body, design: .monospaced))
                    
                    Spacer()
                    
                    Button("Run Cargo Check") {
                        // TODO: Implement check
                    }
                }
                .padding()
            }
            
            // ENV Editor
            EnvEditorView(
                envVariables: $envVariables,
                statusMessage: $statusMessage,
                onSave: saveEnv,
                onReload: loadEnv
            )
        }
        .padding()
        .onAppear {
            loadEnv()
            loadCargoInfo()
        }
    }
    
    // Logic extraction (can be moved to a ViewModifier or Utility)
    private func loadEnv() {
        guard let folder = appState.workspaceFolder else { return }
        let envPath = folder.appendingPathComponent(".env")
        do {
            let content = try String(contentsOf: envPath, encoding: .utf8)
            envVariables = EnvUtils.parseEnv(content)
            statusMessage = "Loaded .env"
        } catch {
            statusMessage = "No .env found (new)"
        }
    }
    
    private func saveEnv() {
        guard let folder = appState.workspaceFolder else { return }
        let envPath = folder.appendingPathComponent(".env")
        let content = EnvUtils.serializeEnv(envVariables)
        try? content.write(to: envPath, atomically: true, encoding: .utf8)
        statusMessage = "Saved .env"
    }
    
    private func loadCargoInfo() {
        // Simple mock for now
        cargoInfo = "Unknown Crate"
        guard let folder = appState.workspaceFolder else { return }
        let cargoPath = folder.appendingPathComponent("Cargo.toml")
        
        if let content = try? String(contentsOf: cargoPath, encoding: .utf8) {
             let lines = content.components(separatedBy: .newlines)
             for line in lines {
                 if line.starts(with: "name =") {
                     cargoInfo = line.replacingOccurrences(of: "\"", with: "")
                 }
             }
        }
    }
}

// MARK: - .NET Runtime View
struct DotnetRuntimeView: View {
    @EnvironmentObject var appState: AppState
    @State private var envVariables: [EnvVariable] = []
    @State private var statusMessage: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            GroupBox(label: Text(".NET Project")) {
                HStack {
                    Image(systemName: "square.3.layers.3d.down.right")
                        .foregroundColor(.purple)
                    Text("Solution / Project detected")
                    Spacer()
                }
                .padding()
            }
            
            EnvEditorView(
                envVariables: $envVariables,
                statusMessage: $statusMessage,
                onSave: saveEnv,
                onReload: loadEnv
            )
        }
        .padding()
        .onAppear { loadEnv() }
    }
    
    private func loadEnv() {
        // Reuse logic (duplicated for speed, should be shared)
        guard let folder = appState.workspaceFolder else { return }
        let envPath = folder.appendingPathComponent(".env")
        do {
            let content = try String(contentsOf: envPath, encoding: .utf8)
            envVariables = EnvUtils.parseEnv(content)
            statusMessage = "Loaded .env"
        } catch {
            statusMessage = "No .env found"
        }
    }
    
    private func saveEnv() {
        guard let folder = appState.workspaceFolder else { return }
        let envPath = folder.appendingPathComponent(".env")
        let content = EnvUtils.serializeEnv(envVariables)
        try? content.write(to: envPath, atomically: true, encoding: .utf8)
        statusMessage = "Saved .env"
    }
}

// MARK: - Generic Runtime View
struct GenericRuntimeView: View {
    @EnvironmentObject var appState: AppState
    @State private var envVariables: [EnvVariable] = []
    @State private var statusMessage: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("General Project Settings")
                .font(.headline)
            
            EnvEditorView(
                envVariables: $envVariables,
                statusMessage: $statusMessage,
                onSave: saveEnv,
                onReload: loadEnv
            )
        }
        .padding()
        .onAppear { loadEnv() }
    }
    
    private func loadEnv() {
        guard let folder = appState.workspaceFolder else { return }
        let envPath = folder.appendingPathComponent(".env")
        do {
            let content = try String(contentsOf: envPath, encoding: .utf8)
            envVariables = EnvUtils.parseEnv(content)
            statusMessage = "Loaded .env"
        } catch {
            statusMessage = "No .env found"
        }
    }
    
    private func saveEnv() {
        guard let folder = appState.workspaceFolder else { return }
        let envPath = folder.appendingPathComponent(".env")
        let content = EnvUtils.serializeEnv(envVariables)
        try? content.write(to: envPath, atomically: true, encoding: .utf8)
        statusMessage = "Saved .env"
    }
}

// Helper for parsing
struct EnvUtils {
    static func parseEnv(_ content: String) -> [EnvVariable] {
        var vars: [EnvVariable] = []
        content.enumerateLines { line, _ in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count >= 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty && !key.starts(with: "#") {
                    vars.append(EnvVariable(key: key, value: value))
                }
            }
        }
        return vars
    }
    
    static func serializeEnv(_ vars: [EnvVariable]) -> String {
        vars.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }
}
