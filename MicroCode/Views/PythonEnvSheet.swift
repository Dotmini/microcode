//
//  PythonEnvSheet.swift
//  MicroCode
//
//  UI for Python Environment Management
//

import SwiftUI

struct PythonEnvSheet: View {
    @ObservedObject var envManager = PythonEnvManager.shared
    @ObservedObject private var runtimeManager = RuntimeManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var showingCreateEnv: Bool = false
    @State private var selectedEnv: PythonEnvironment?
    @State private var packagesToInstall: String = ""
    @State private var isOutputExpanded = false
    @State private var selectedRuntime: RuntimeType = .python
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.65)

            HStack(spacing: 0) {
                environmentNavigator
                Divider().opacity(0.65)

                Group {
                    if selectedRuntime == .python, let env = selectedEnv {
                        environmentDetails(env)
                    } else if selectedRuntime != .python {
                        runtimeDetails
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                            Text("No environment selected")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Create a virtual environment or select one from the sidebar.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            }
            .frame(maxHeight: .infinity)

            if !envManager.output.isEmpty {
                Divider().opacity(0.65)
                outputConsole
            }
        }
        .frame(width: 820, height: 610)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            selectedEnv = envManager.activeEnvironment ?? envManager.environments.first
            runtimeManager.detectAll()
        }
        .onChange(of: envManager.environments) { environments in
            guard let selectedEnv else {
                self.selectedEnv = envManager.activeEnvironment ?? environments.first
                return
            }
            if !environments.contains(where: { $0.id == selectedEnv.id }) {
                self.selectedEnv = envManager.activeEnvironment ?? environments.first
            }
        }
        .onChange(of: envManager.output) { output in
            if !output.isEmpty && envManager.isWorking {
                isOutputExpanded = true
            }
        }
        .sheet(isPresented: $showingCreateEnv) {
            CreateEnvSheet()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Manage Environments")
                    .font(.system(size: 15, weight: .semibold))
                Text("Select the runtime and interpreter used by this notebook and editor.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if envManager.isWorking {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Working")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Button {
                showingCreateEnv = true
            } label: {
                Label(selectedRuntime == .python ? "New Python Environment" : "Runtime settings", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(selectedRuntime != .python)

            Button(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(Color.primary.opacity(0.055), in: Circle())
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
    }

    private var environmentNavigator: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ENVIRONMENTS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                Spacer()
                Text("\(envManager.environments.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 15)

            Picker("Runtime", selection: $selectedRuntime) {
                ForEach(RuntimeType.allCases) { runtime in
                    Text("\(runtime.icon)  \(runtime.rawValue)").tag(runtime)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .padding(.horizontal, 14)

            if selectedRuntime != .python {
                Text("INTERPRETERS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                runtimeNavigator
            } else {

            if envManager.environments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.dashed")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("No virtual environments")
                        .font(.system(size: 11, weight: .medium))
                    Button("Create one") { showingCreateEnv = true }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(envManager.environments) { env in
                            environmentRow(env)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.bottom, 12)
                }
            }
            }
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.32))
    }

    private var runtimeNavigator: some View {
        let status = runtimeManager.runtimes.first(where: { $0.type == selectedRuntime })
        return VStack(alignment: .leading, spacing: 4) {
            if let status, status.isInstalled {
                ForEach(runtimeManager.availablePaths(for: selectedRuntime), id: \.self) { path in
                    runtimeRow(path: path, activePath: status.path)
                }
            } else {
                Text("Not detected on this Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(14)
            }
            Button { runtimeManager.detectAll() } label: { Label("Refresh runtimes", systemImage: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 9)
        .padding(.bottom, 12)
    }

    private func runtimeRow(path: String, activePath: String?) -> some View {
        let isActive = activePath == path
        let executableName = URL(fileURLWithPath: path).lastPathComponent
        return Button {
            runtimeManager.activateRuntime(path, for: selectedRuntime)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "terminal")
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                Text(isActive ? "Active interpreter" : executableName)
                        .font(.system(size: 11, weight: .semibold))
                    Text(path).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(isActive ? Color.accentColor.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var runtimeDetails: some View {
        let status = runtimeManager.runtimes.first(where: { $0.type == selectedRuntime })
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Text(selectedRuntime.icon).font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(selectedRuntime.rawValue) Environment").font(.system(size: 18, weight: .semibold))
                        Text(status?.isInstalled == true ? (status?.version ?? "Detected") : "Runtime not detected")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                detailCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Interpreter").font(.system(size: 12, weight: .semibold))
                        detailLine(selectedRuntime.rawValue, status?.path ?? "Not installed", monospaced: true)
                        Text("Choose another detected version in the sidebar. Node versions from nvm/asdf are detected automatically.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                detailCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Package manager").font(.system(size: 12, weight: .semibold))
                        Text(packageCommand(for: selectedRuntime))
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
        }
    }

    private func packageCommand(for runtime: RuntimeType) -> String {
        switch runtime {
        case .nodejs: return "npm install <package>  •  pnpm add <package>"
        case .bun: return "bun add <package>"
        case .deno: return "deno add jsr:<package>"
        case .r: return "install.packages(\"package\")"
        case .julia: return "import Pkg; Pkg.add(\"Package\")"
        case .rust: return "cargo add <crate>"
        case .dotnet: return "dotnet add package <package>"
        case .java, .kotlin: return "Add dependency in build.gradle.kts / pom.xml"
        default: return "Uses the selected interpreter from the sidebar."
        }
    }

    private func environmentRow(_ env: PythonEnvironment) -> some View {
        let isSelected = selectedEnv?.id == env.id
        let isActive = envManager.activeEnvironment?.id == env.id
        return Button {
            selectedEnv = env
            packagesToInstall = ""
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "terminal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(env.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(env.pythonVersion)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
                if isActive {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func environmentDetails(_ env: PythonEnvironment) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 42, height: 42)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(env.name)
                                .font(.system(size: 18, weight: .semibold))
                            if envManager.activeEnvironment?.id == env.id {
                                Text("ACTIVE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.13), in: Capsule())
                            }
                        }
                        Text("Python \(env.pythonVersion)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                detailCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Interpreter")
                            .font(.system(size: 12, weight: .semibold))
                        detailLine("Python", env.pythonPath, monospaced: true)
                        detailLine("Environment", env.path.path, monospaced: true)
                    }
                }

                HStack(spacing: 9) {
                    Button {
                        envManager.activateEnvironment(env)
                    } label: {
                        Label(envManager.activeEnvironment?.id == env.id ? "Active Environment" : "Use This Environment",
                              systemImage: envManager.activeEnvironment?.id == env.id ? "checkmark" : "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(envManager.activeEnvironment?.id == env.id || envManager.isWorking)

                    Button(role: .destructive) {
                        deleteEnv(env)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(envManager.isWorking)
                }

                packageSuggestions(for: env)
                manualInstall(for: env)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
        }
    }

    private func packageSuggestions(for env: PythonEnvironment) -> some View {
        detailCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentColor)
                    Text("Detected packages")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("FROM NOTEBOOK")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                if envManager.detectedPackages.isEmpty {
                    Text("No third-party imports detected. Packages imported by a cell will appear here.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                } else {
                    Text(envManager.detectedPackages.joined(separator: "  ·  "))
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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
        }
    }

    private func manualInstall(for env: PythonEnvironment) -> some View {
        detailCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Install a package")
                    .font(.system(size: 12, weight: .semibold))
                HStack(spacing: 9) {
                    TextField("numpy pandas matplotlib", text: $packagesToInstall)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.09), lineWidth: 1))

                    Button("Install") { installPackages(env) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(packagesToInstall.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || envManager.isWorking)
                }
                Text("Separate multiple package names with spaces.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var outputConsole: some View {
        DisclosureGroup(isExpanded: $isOutputExpanded) {
            ScrollView {
                Text(envManager.output)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.88))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(height: 132)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                Text("Activity output")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                if envManager.isWorking {
                    ProgressView().controlSize(.mini)
                }
                Button("Clear") { envManager.output = "" }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.52), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private func detailLine(_ label: String, _ value: String, monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 11, design: monospaced ? .monospaced : .default))
                .textSelection(.enabled)
                .lineLimit(2)
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
            guard DeveloperToolsGuard.isSafeToExecute(path) else { continue }
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
