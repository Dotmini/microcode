//
//  PythonEnvSheet.swift
//  MicroCode
//
//  UI for Python Environment Management
//

import SwiftUI

struct PythonEnvSheet: View {
    @ObservedObject var envManager = PythonEnvManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var newEnvName: String = ""
    @State private var showingCreateEnv: Bool = false
    @State private var selectedEnv: PythonEnvironment?
    @State private var packagesToInstall: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.green)
                Text("Python Environments")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showingCreateEnv = true }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Create New Environment")
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            HStack(spacing: 0) {
                // Environment List
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
                
                // Details Panel
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
                        
                        // ── Auto-detected packages (primary path) ───────────
                        GroupBox(label: Label("Auto-detected from your code", systemImage: "wand.and.stars")) {
                            VStack(alignment: .leading, spacing: 8) {
                                if envManager.detectedPackages.isEmpty {
                                    Text("No 3rd-party imports detected yet. Run a cell or write `import …` and they'll appear here automatically.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(envManager.detectedPackages.joined(separator: ", "))
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)

                                    Button {
                                        envManager.installPackages(envManager.detectedPackages, in: env) { _, _ in }
                                    } label: {
                                        Label("Install \(envManager.detectedPackages.count) detected package\(envManager.detectedPackages.count == 1 ? "" : "s")",
                                              systemImage: "arrow.down.circle.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(envManager.isWorking)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }

                        // ── Manual install (fallback) ───────────────────────
                        GroupBox(label: Text("Or install manually")) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("Package names (space separated)", text: $packagesToInstall)
                                        .textFieldStyle(.roundedBorder)

                                    Button("Install") {
                                        installPackages(env)
                                    }
                                    .buttonStyle(.bordered)
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
                        VStack {
                            Spacer()
                            Image(systemName: "folder.badge.gearshape")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("Select an environment")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            
            Divider()
            
            // Output Log
            if !envManager.output.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Output")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Clear") {
                            envManager.output = ""
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    
                    ScrollView {
                        Text(envManager.output)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(4)
                }
                .padding()
            }
        }
        .frame(width: 700, height: 550)
        .sheet(isPresented: $showingCreateEnv) {
            CreateEnvSheet()
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

struct EnvRow: View {
    let env: PythonEnvironment
    let isActive: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isActive ? "checkmark.circle.fill" : "folder")
                .foregroundColor(isActive ? .green : .secondary)
            
            VStack(alignment: .leading) {
                Text(env.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                Text(env.pythonVersion)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CreateEnvSheet: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var envManager = PythonEnvManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var envName: String = ""
    @State private var selectedPythonPath: String = "python3"
    @State private var availableVersions: [PythonVersionInfo] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create Virtual Environment")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                // Environment Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Environment Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("my-env", text: $envName)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Python Version Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Python Version")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $selectedPythonPath) {
                        if availableVersions.isEmpty {
                            Text("python3 (default)")
                                .tag("python3")
                        } else {
                            ForEach(availableVersions) { version in
                                HStack {
                                    Image(systemName: "p.circle.fill")
                                        .foregroundColor(.blue)
                                    Text(version.displayName)
                                }
                                .tag(version.path)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 280)
            
            Text("A new Python virtual environment will be created using the selected Python version.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 280)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Create") {
                    createEnv()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(envName.isEmpty || envManager.isWorking)
            }
            
            if envManager.isWorking {
                ProgressView("Creating environment...")
            }
        }
        .padding(30)
        .frame(width: 380)
        .onAppear {
            detectPythonVersions()
        }
    }
    
    private func detectPythonVersions() {
        var versions: [PythonVersionInfo] = []
        
        // Common Python paths to check
        let pythonPaths = [
            "/opt/homebrew/bin/python3",
            "/opt/homebrew/bin/python3.13",
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/bin/python3.11",
            "/opt/homebrew/bin/python3.10",
            "/opt/homebrew/bin/python3.9",
            "/usr/local/bin/python3",
            "/usr/local/bin/python3.12",
            "/usr/local/bin/python3.11",
            "/usr/local/bin/python3.10",
            "/usr/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.10/bin/python3",
        ]
        
        let fileManager = FileManager.default
        
        for path in pythonPaths {
            if fileManager.fileExists(atPath: path) {
                // Get version
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["--version"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        let version = output.replacingOccurrences(of: "Python ", with: "")
                        let displayName = "Python \(version)"
                        
                        // Avoid duplicates
                        if !versions.contains(where: { $0.version == version }) {
                            versions.append(PythonVersionInfo(path: path, version: version, displayName: displayName))
                        }
                    }
                } catch {
                    // Ignore errors
                }
            }
        }
        
        availableVersions = versions.sorted { $0.version > $1.version }
        if let first = availableVersions.first {
            selectedPythonPath = first.path
        }
    }
    
    private func createEnv() {
        envManager.createEnvironment(name: envName, pythonPath: selectedPythonPath) { success, _ in
            if success {
                dismiss()
            }
        }
    }
}
