//
//  ContainerView.swift
//  CodeTunner
//
//  Apple Container Management UI
//
//  SPU AI CLUB - Dotmini Software
//

import SwiftUI

struct ContainerView: View {
    @StateObject private var containerService = ContainerService.shared
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    @State private var showNewContainer = false
    @State private var showBuildImage = false
    @State private var showDeploySheet = false
    @State private var commandInput = ""
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // System Status Banner
            if !containerService.isSystemReady {
                systemStatusBanner
            }
            
            Divider()
            
            // Tabs
            HStack(spacing: 0) {
                ContainerTabButton(title: "Containers", isSelected: selectedTab == 0) { selectedTab = 0 }
                ContainerTabButton(title: "Images", isSelected: selectedTab == 1) { selectedTab = 1 }
                ContainerTabButton(title: "Deploy", isSelected: selectedTab == 3) { selectedTab = 3 }
                ContainerTabButton(title: "Terminal", isSelected: selectedTab == 2) { selectedTab = 2 }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Content
            if selectedTab == 0 {
                containersListView
            } else if selectedTab == 1 {
                imagesListView
            } else if selectedTab == 3 {
                deploymentView
            } else {
                containerTerminalView
            }
        }
        .frame(width: 750, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            Task {
                await containerService.checkSystemStatus()
                if containerService.isSystemReady {
                    try? await containerService.listContainers()
                    try? await containerService.listImages()
                }
            }
        }
        .sheet(isPresented: $showNewContainer) {
            NewContainerSheet()
        }
        .sheet(isPresented: $showBuildImage) {
            BuildImageSheet()
        }
        .sheet(isPresented: $showDeploySheet) {
            DeploymentProfileSheet()
        }
    }
    
    // MARK: - System Status Banner
    
    private var systemStatusBanner: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
            
            Text(containerService.systemStatus.displayMessage)
                .font(.subheadline)
            
            Spacer()
            
            if case .pluginsUnavailable = containerService.systemStatus {
                Button("Start System") {
                    Task {
                        try? await containerService.initializeSystem()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else if case .needsStart = containerService.systemStatus {
                Button("Initialize") {
                    Task {
                        try? await containerService.initializeSystem()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(statusColor.opacity(0.1))
    }
    
    private var statusIcon: String {
        switch containerService.systemStatus {
        case .ready: return "checkmark.circle.fill"
        case .checking: return "arrow.triangle.2.circlepath"
        case .notInstalled: return "xmark.circle.fill"
        case .pluginsUnavailable, .needsStart: return "exclamationmark.triangle.fill"
        case .error, .unknown: return "questionmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch containerService.systemStatus {
        case .ready: return .green
        case .checking: return .blue
        case .notInstalled, .error: return .red
        case .pluginsUnavailable, .needsStart: return .orange
        case .unknown: return .secondary
        }
    }
    
    // MARK: - Deployment View
    
    private var deploymentView: some View {
        VStack(spacing: 0) {
            // Deployment Profiles
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Production Deployment Profiles")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(containerService.deploymentProfiles) { profile in
                            DeploymentProfileCard(profile: profile) {
                                deployProfile(profile)
                            }
                        }
                        
                        // Add New Profile
                        Button {
                            showDeploySheet = true
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "plus.circle.dashed")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("Custom Profile")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    
                    Divider()
                        .padding(.vertical)
                    
                    Text("Quick Deploy")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    HStack(spacing: 12) {
                        QuickDeployButton(icon: "globe", title: "Web App", subtitle: "Port 3000") {
                            quickDeploy(.webApp(port: 3000))
                        }
                        QuickDeployButton(icon: "network", title: "Python API", subtitle: "Port 8000") {
                            quickDeploy(.pythonAPI(port: 8000))
                        }
                        QuickDeployButton(icon: "doc.richtext", title: "Static Site", subtitle: "Port 8080") {
                            quickDeploy(.staticSite(port: 8080))
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
    }
    
    private func deployProfile(_ profile: ContainerService.DeploymentProfile) {
        guard let filePath = appState.currentFile?.path else { return }
        let projectPath = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        
        Task {
            do {
                _ = try await containerService.deployWithProfile(profile, projectPath: projectPath)
                selectedTab = 0 // Switch to containers tab
            } catch {
                containerService.terminalOutput += "❌ Deploy failed: \(error.localizedDescription)\n"
            }
        }
    }
    
    private func quickDeploy(_ type: ContainerService.QuickDeployType) {
        guard let filePath = appState.currentFile?.path else { return }
        let projectPath = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        
        Task {
            do {
                _ = try await containerService.quickDeploy(type: type, projectPath: projectPath)
                selectedTab = 0
            } catch {
                containerService.terminalOutput += "❌ Quick deploy failed: \(error.localizedDescription)\n"
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "shippingbox.fill")
                .foregroundColor(.orange)
            Text("Apple Containers")
                .font(.headline)
            
            Spacer()
            
            // Actions
            Button {
                Task { try? await containerService.listContainers() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Button {
                showNewContainer = true
            } label: {
                Image(systemName: "plus")
                Text("New Container")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    private var containersListView: some View {
        VStack(spacing: 0) {
            if containerService.containers.isEmpty {
                emptyContainersView
            } else {
                List {
                    ForEach(containerService.containers) { container in
                        ContainerRow(container: container)
                    }
                }
            }
            
            // Quick Actions
            HStack {
                Button("Run Project in Container") {
                    runCurrentProject()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Build in Container") {
                    buildCurrentProject()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if containerService.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    private var emptyContainersView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "shippingbox")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("No containers running")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Create a new container or run your project in a container")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    private var imagesListView: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Available Images")
                    .font(.subheadline.bold())
                Spacer()
                
                Button {
                    showBuildImage = true
                } label: {
                    Image(systemName: "hammer")
                    Text("Build Image")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            
            Divider()
            
            if containerService.images.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Text("No local images")
                        .foregroundColor(.secondary)
                    Button("Pull ubuntu:22.04") {
                        Task { try? await containerService.pullImage("ubuntu:22.04") }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            } else {
                List {
                    ForEach(containerService.images) { image in
                        ImageRow(image: image)
                    }
                }
            }
        }
    }
    
    private var containerTerminalView: some View {
        VStack(spacing: 0) {
            // Terminal output
            ScrollViewReader { proxy in
                ScrollView {
                    Text(containerService.terminalOutput.isEmpty ? "# Container Terminal Ready\n# Run projects or execute commands in containers" : containerService.terminalOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(nsColor: appState.appTheme.editorText))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("bottom")
                }
                .onChange(of: containerService.terminalOutput) { _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .background(Color(nsColor: appState.appTheme.editorBackground))
            
            Divider()
            
            // Command input
            HStack(spacing: 8) {
                Text("container")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                
                TextField("Enter container command...", text: $commandInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { runCommand() }
                
                Button {
                    runCommand()
                } label: {
                    Image(systemName: "return")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button {
                    containerService.clearTerminal()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    private func runCommand() {
        guard !commandInput.isEmpty else { return }
        let cmd = commandInput
        commandInput = ""
        
        Task {
            do {
                let args = cmd.split(separator: " ").map(String.init)
                containerService.terminalOutput += "$ container \(cmd)\n"
                // Direct command execution through Process
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/local/bin/container")
                process.arguments = args
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                containerService.terminalOutput += output + "\n"
                
                try? await containerService.listContainers()
            } catch {
                containerService.terminalOutput += "Error: \(error.localizedDescription)\n"
            }
        }
    }
    
    private func runCurrentProject() {
        guard let filePath = appState.currentFile?.path else { return }
        let projectPath = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        
        Task {
            try? await containerService.runProjectInContainer(
                projectPath: projectPath,
                language: appState.selectedLanguage
            )
        }
    }
    
    private func buildCurrentProject() {
        guard let filePath = appState.currentFile?.path else { return }
        let projectPath = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        
        Task {
            _ = try? await containerService.buildProjectInContainer(
                projectPath: projectPath,
                language: appState.selectedLanguage
            )
        }
    }
}

// MARK: - Container Row

struct ContainerRow: View {
    let container: Container
    @StateObject private var containerService = ContainerService.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(container.name)
                    .font(.headline)
                
                HStack {
                    Text(container.image)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(container.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(statusColor)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 4) {
                if container.status == .running {
                    Button {
                        Task { try? await containerService.stopContainer(container.id) }
                    } label: {
                        Image(systemName: "stop.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button {
                        Task { try? await containerService.startContainer(container.id) }
                    } label: {
                        Image(systemName: "play.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Button {
                    Task { try? await containerService.deleteContainer(container.id) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch container.status {
        case .running: return .green
        case .stopped, .exited: return .red
        case .created: return .yellow
        case .unknown: return .gray
        }
    }
}

// MARK: - Image Row

struct ImageRow: View {
    let image: ContainerImage
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(image.name):\(image.tag)")
                    .font(.headline)
                
                if let size = image.size {
                    Text(size)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button("Run") {
                Task {
                    try? await ContainerService.shared.runContainer(image: "\(image.name):\(image.tag)")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tab Button

struct ContainerTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - New Container Sheet

struct NewContainerSheet: View {
    @StateObject private var containerService = ContainerService.shared
    @State private var name = ""
    @State private var image = "ubuntu:22.04"
    @State private var hostPort = ""
    @State private var containerPort = ""
    @State private var volumeHost = ""
    @State private var volumeContainer = ""
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create Container")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("my-container", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Image")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("ubuntu:22.04", text: $image)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Host Port")
                            .font(.caption).foregroundColor(.secondary)
                        TextField("8080", text: $hostPort)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Text("→")
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Container Port")
                            .font(.caption).foregroundColor(.secondary)
                        TextField("80", text: $containerPort)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                
                Button("Create") {
                    Task {
                        var ports: [Container.PortMapping] = []
                        if let hp = Int(hostPort), let cp = Int(containerPort) {
                            ports.append(Container.PortMapping(hostPort: hp, containerPort: cp, protocol_: "tcp"))
                        }
                        
                        _ = try? await containerService.createContainer(
                            name: name.isEmpty ? "container-\(UUID().uuidString.prefix(8))" : name,
                            image: image,
                            ports: ports
                        )
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(image.isEmpty)
            }
        }
        .padding(32)
        .frame(width: 400)
    }
}

// MARK: - Build Image Sheet

struct BuildImageSheet: View {
    @StateObject private var containerService = ContainerService.shared
    @State private var tag = ""
    @State private var dockerfile = "Dockerfile"
    @State private var context = "."
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Build Image")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tag")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("my-app:latest", text: $tag)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dockerfile")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("Dockerfile", text: $dockerfile)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Context")
                        .font(.caption).foregroundColor(.secondary)
                    TextField(".", text: $context)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                
                Button("Build") {
                    Task {
                        try? await containerService.buildImage(
                            dockerfile: dockerfile,
                            tag: tag,
                            context: context
                        )
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(tag.isEmpty)
            }
        }
        .padding(32)
        .frame(width: 400)
    }
}

// MARK: - Deployment Profile Card

struct DeploymentProfileCard: View {
    let profile: ContainerService.DeploymentProfile
    let onDeploy: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconForProfile)
                    .foregroundColor(.blue)
                Text(profile.name)
                    .font(.headline)
                Spacer()
            }
            
            Text(profile.baseImage)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !profile.ports.isEmpty {
                Text("Ports: \(profile.ports.map { "\($0.hostPort):\($0.containerPort)" }.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Deploy") {
                onDeploy()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .frame(height: 130)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var iconForProfile: String {
        if profile.name.lowercased().contains("web") { return "globe" }
        if profile.name.lowercased().contains("api") { return "network" }
        if profile.name.lowercased().contains("database") { return "cylinder" }
        return "shippingbox"
    }
}

// MARK: - Quick Deploy Button

struct QuickDeployButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.caption.bold())
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Deployment Profile Sheet

struct DeploymentProfileSheet: View {
    @StateObject private var containerService = ContainerService.shared
    @State private var name = ""
    @State private var baseImage = "node:20-slim"
    @State private var hostPort = "3000"
    @State private var containerPort = "3000"
    @State private var envKey = ""
    @State private var envValue = ""
    @State private var environment: [String: String] = [:]
    @State private var command = ""
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create Deployment Profile")
                .font(.title2.bold())
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Profile Name")
                            .font(.caption).foregroundColor(.secondary)
                        TextField("My Web App", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Base Image")
                            .font(.caption).foregroundColor(.secondary)
                        TextField("node:20-slim", text: $baseImage)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Host Port")
                                .font(.caption).foregroundColor(.secondary)
                            TextField("3000", text: $hostPort)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Text("→")
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Container Port")
                                .font(.caption).foregroundColor(.secondary)
                            TextField("3000", text: $containerPort)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Command (optional)")
                            .font(.caption).foregroundColor(.secondary)
                        TextField("npm start", text: $command)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Environment Variables
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Environment Variables")
                            .font(.caption).foregroundColor(.secondary)
                        
                        ForEach(Array(environment.keys), id: \.self) { key in
                            HStack {
                                Text("\(key)=\(environment[key] ?? "")")
                                    .font(.caption)
                                Spacer()
                                Button {
                                    environment.removeValue(forKey: key)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(6)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                        }
                        
                        HStack {
                            TextField("KEY", text: $envKey)
                                .textFieldStyle(.roundedBorder)
                            TextField("value", text: $envValue)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                if !envKey.isEmpty {
                                    environment[envKey] = envValue
                                    envKey = ""
                                    envValue = ""
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .disabled(envKey.isEmpty)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                
                Button("Save Profile") {
                    var ports: [Container.PortMapping] = []
                    if let hp = Int(hostPort), let cp = Int(containerPort) {
                        ports.append(Container.PortMapping(hostPort: hp, containerPort: cp, protocol_: "tcp"))
                    }
                    
                    let profile = ContainerService.DeploymentProfile(
                        name: name.isEmpty ? "Custom" : name,
                        baseImage: baseImage,
                        ports: ports,
                        volumes: [],
                        environment: environment,
                        command: command.isEmpty ? nil : command
                    )
                    
                    containerService.deploymentProfiles.append(profile)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || baseImage.isEmpty)
            }
        }
        .padding(32)
        .frame(width: 450)
    }
}
