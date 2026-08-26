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
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                Text("Python Environments")
                    .font(.system(size: 14, weight: .semibold))
                
                Spacer()
                
                Button(action: { showingCreateEnv = true }) {
                    Label("New Environment", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            HStack(spacing: 0) {
                // Environment List (Sidebar)
                VStack(alignment: .leading, spacing: 6) {
                    Text("ENVIRONMENTS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                    
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(envManager.environments) { env in
                                Button(action: { selectedEnv = env }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: envManager.activeEnvironment?.id == env.id ? "checkmark.circle.fill" : "cube")
                                            .font(.system(size: 12))
                                            .foregroundColor(envManager.activeEnvironment?.id == env.id ? .secondary : .secondary.opacity(0.6))
                                        
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(env.name)
                                                .font(.system(size: 12, weight: selectedEnv?.id == env.id ? .semibold : .regular))
                                                .foregroundColor(.primary)
                                            Text(env.pythonVersion)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(selectedEnv?.id == env.id ? Color.primary.opacity(0.1) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .frame(width: 190)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                
                Divider()
                
                // Details Panel
                VStack(alignment: .leading, spacing: 14) {
                    if let env = selectedEnv {
                        // Environment Info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Environment Details")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                CompatLabeledContent("Name", value: env.name)
                                CompatLabeledContent("Python", value: env.pythonVersion)
                                CompatLabeledContent("Path", value: env.path.path)
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.primary.opacity(0.04))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                            )
                        }
                        
                        // Actions
                        HStack(spacing: 8) {
                            Button(action: { envManager.activateEnvironment(env) }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle")
                                    Text("Activate")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(envManager.activeEnvironment?.id == env.id)
                            
                            Button(action: { deleteEnv(env) }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                    Text("Delete")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundColor(.secondary)
                        }
                        
                        // ── Auto-detected packages ───────────
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Auto-detected from code", systemImage: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                if envManager.detectedPackages.isEmpty {
                                    Text("No 3rd-party imports detected yet. Write or run Python code to see packages here.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(envManager.detectedPackages.joined(separator: ", "))
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                    
                                    Button {
                                        envManager.installPackages(envManager.detectedPackages, in: env) { _, _ in }
                                    } label: {
                                        Label("Install \(envManager.detectedPackages.count) detected package\(envManager.detectedPackages.count == 1 ? "" : "s")",
                                              systemImage: "arrow.down.circle")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(envManager.isWorking)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.primary.opacity(0.04))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                            )
                        }

                        // ── Manual install ───────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Or install manually")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 8) {
                                TextField("Package names (space separated)", text: $packagesToInstall)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .padding(7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(nsColor: .textBackgroundColor))
                                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                                    )

                                Button("Install") {
                                    installPackages(env)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(packagesToInstall.isEmpty || envManager.isWorking)
                            }

                            Text("Example: numpy pandas matplotlib")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        
                        Spacer()
                    } else {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary.opacity(0.4))
                            Text("Select an environment to view details")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
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
