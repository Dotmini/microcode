//
//  RemoteXView.swift
//  CodeTunner
//
//  Remote Explorer - SSH, SFTP, FTP Connection Manager
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import SwiftUI

// MARK: - Remote Connection Configuration

struct RemoteConnectionConfig: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var host: String
    var port: UInt16 = 22
    var username: String
    var authType: AuthType = .password
    var password: String = ""
    var keyPath: String = ""
    var connectionType: ConnectionType = .ssh
    var lastConnected: Date?
    
    enum AuthType: String, Codable, CaseIterable {
        case password = "password"
        case key = "key"
        
        var displayName: String {
            switch self {
            case .password: return "Password"
            case .key: return "SSH Key"
            }
        }
        
        var icon: String {
            switch self {
            case .password: return "key.fill"
            case .key: return "key.horizontal.fill"
            }
        }
    }
    
    enum ConnectionType: String, Codable, CaseIterable {
        case ssh = "ssh"
        case sftp = "sftp"
        case ftp = "ftp"
        case ftps = "ftps"
        
        var displayName: String {
            switch self {
            case .ssh: return "SSH"
            case .sftp: return "SFTP"
            case .ftp: return "FTP"
            case .ftps: return "FTPS"
            }
        }
        
        var icon: String {
            switch self {
            case .ssh: return "terminal.fill"
            case .sftp: return "externaldrive.connected.to.line.below.fill"
            case .ftp: return "folder.badge.gearshape"
            case .ftps: return "lock.icloud.fill"
            }
        }
        
        var defaultPort: UInt16 {
            switch self {
            case .ssh, .sftp: return 22
            case .ftp, .ftps: return 21
            }
        }
    }
    
    var isSecure: Bool {
        connectionType == .ftps || connectionType == .sftp || connectionType == .ssh
    }
    
    enum CloudProvider: String, Codable, CaseIterable {
        case none = "none"
        case aws = "aws"
        case gcp = "gcp"
        case alibaba = "alibaba"
        case digitalocean = "digitalocean"
        
        var displayName: String {
            switch self {
            case .none: return "Custom"
            case .aws: return "AWS"
            case .gcp: return "GCP"
            case .alibaba: return "Alibaba"
            case .digitalocean: return "DigitalOcean"
            }
        }
        
        var icon: String {
            switch self {
            case .none: return "server.rack"
            case .aws: return "cloud.fill"
            case .gcp: return "cloud.rainbow.half"
            case .alibaba: return "cart.fill"
            case .digitalocean: return "drop.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .none: return .secondary
            case .aws: return .orange
            case .gcp: return .blue
            case .alibaba: return .orange
            case .digitalocean: return .blue
            }
        }
        
        var defaultUser: String {
            switch self {
            case .none: return ""
            case .aws: return "ec2-user"
            case .gcp: return "google_compute_engine"
            case .alibaba: return "root"
            case .digitalocean: return "root"
            }
        }
    }
    
    var provider: CloudProvider = .none
    
    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, authType, password, keyPath, connectionType, lastConnected, provider
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? 22
        username = try container.decode(String.self, forKey: .username)
        authType = try container.decodeIfPresent(AuthType.self, forKey: .authType) ?? .password
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        keyPath = try container.decodeIfPresent(String.self, forKey: .keyPath) ?? ""
        connectionType = try container.decodeIfPresent(ConnectionType.self, forKey: .connectionType) ?? .ssh
        lastConnected = try container.decodeIfPresent(Date.self, forKey: .lastConnected)
        provider = try container.decodeIfPresent(CloudProvider.self, forKey: .provider) ?? .none
    }
    
    // Memberwise init
    init(id: UUID = UUID(), name: String, host: String, port: UInt16 = 22, username: String, authType: AuthType = .password, password: String = "", keyPath: String = "", connectionType: ConnectionType = .ssh, provider: CloudProvider = .none) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authType = authType
        self.password = password
        self.keyPath = keyPath
        self.connectionType = connectionType
        self.provider = provider
    }
}

// MARK: - Remote Connection Manager

class RemoteConnectionManager: ObservableObject {
    static let shared = RemoteConnectionManager()
    
    @Published var servers: [RemoteConnectionConfig] = []
    @Published var currentConnection: RemoteConnectionConfig?
    @Published var isConnected: Bool = false
    @Published var connectionStatus: String = "Disconnected"
    @Published var terminalOutput: String = ""
    @Published var remoteFiles: [FileInfo] = []
    @Published var currentPath: String = "/"
    
    private let storageKey = "remote_servers"
    private let recentKeysKey = "remote_recent_keys"
    private var webSocketTask: URLSessionWebSocketTask?
    
    init() {
        loadServers()
        loadRecentKeys()
    }
    
    // MARK: - Recent Keys
    
    @Published var recentKeys: [String] = []
    
    func loadRecentKeys() {
        if let data = UserDefaults.standard.object(forKey: recentKeysKey) as? [String] {
            recentKeys = data
        }
    }
    
    func addRecentKey(_ path: String) {
        guard !path.isEmpty else { return }
        if !recentKeys.contains(path) {
            recentKeys.insert(path, at: 0)
            if recentKeys.count > 5 { recentKeys.removeLast() }
            UserDefaults.standard.set(recentKeys, forKey: recentKeysKey)
        }
    }
    
    func importSSHConfig() {
        let entries = SSHConfigParser.shared.parseDefaultConfig()
        var count = 0
        for entry in entries {
             // Check duplicate
             if !servers.contains(where: { $0.host == entry.hostName || $0.name == entry.host }) {
                 let config = RemoteConnectionConfig(
                    name: entry.host,
                    host: entry.hostName,
                    port: entry.port ?? 22,
                    username: entry.user ?? "root",
                    authType: entry.identityFile != nil ? .key : .password,
                    password: "",
                    keyPath: entry.identityFile ?? "",
                    connectionType: .ssh,
                    provider: .none
                 )
                 addServer(config)
                 count += 1
             }
        }
        // Could notify user "Imported \(count) servers"
    }
    
    func loadServers() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([RemoteConnectionConfig].self, from: data) {
            servers = decoded
        }
    }
    
    func saveServers() {
        if let encoded = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    func addServer(_ server: RemoteConnectionConfig) {
        servers.append(server)
        saveServers()
    }
    
    func updateServer(_ server: RemoteConnectionConfig) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            saveServers()
        }
    }
    
    func deleteServer(_ server: RemoteConnectionConfig) {
        servers.removeAll { $0.id == server.id }
        saveServers()
    }
    
    func connect(to server: RemoteConnectionConfig) async -> Bool {
        await MainActor.run {
            connectionStatus = "Connecting..."
            currentConnection = server
            terminalOutput = "Connecting to \(server.host)...\n"
        }
        
        do {
            let response = try await BackendService.shared.connectRemote(config: server)
            
            if response.success {
                await MainActor.run {
                    isConnected = true
                    connectionStatus = "Connected"
                    
                    // Update last connected
                    var updated = server
                    updated.lastConnected = Date()
                    updateServer(updated)
                }
                // Start WebSocket Shell ONLY for SSH
                if server.connectionType == .ssh {
                    startShellWebSocket(id: server.id.uuidString)
                }
            } else {
                 await MainActor.run {
                    connectionStatus = "Connection Failed"
                    isConnected = false
                    lastError = response.message
                    showError = true
                 }
            }
            return response.success
        } catch {
            await MainActor.run {
                connectionStatus = "Error: \(error.localizedDescription)"
                isConnected = false
                lastError = error.localizedDescription
                showError = true
            }
            return false
        }
    }
    
    private func startShellWebSocket(id: String) {
        guard let url = BackendService.shared.remoteShellWebSocketURL(id: id) else {
            print("❌ Invalid WebSocket URL for id: \(id)")
            return
        }
        let request = URLRequest(url: url)
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        
        receiveMessage()
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
             case .failure(let error):
                 DispatchQueue.main.async {
                     self.terminalOutput += "\n[Shell Disconnected: \(error.localizedDescription)]\n"
                     // DO NOT set isConnected = false here, as it kills the file browser
                 }
            case .success(let message):
                switch message {
                case .string(let text):
                    DispatchQueue.main.async {
                        self.terminalOutput += text
                    }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.terminalOutput += text
                        }
                    }
                @unknown default:
                    break
                }
                
                // Continue receiving
                if self.isConnected {
                    self.receiveMessage()
                }
            }
        }
    }
    
    func sendCommand(_ command: String) {
        // Send command + newline
        let message = URLSessionWebSocketTask.Message.string(command + "\n")
        webSocketTask?.send(message) { error in
            if let error = error {
                print("WebSocket sending error: \(error)")
            }
        }
    }
    
    
    // Add error callback or published property for UI alerts
    // Add error callback or published property for UI alerts
    @Published var lastError: String?
    @Published var showError: Bool = false
    @Published var isLoadingFiles: Bool = false
    
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        
        isConnected = false
        currentConnection = nil
        connectionStatus = "Disconnected"
        terminalOutput += "\n[Disconnected]\n"
        remoteFiles = []
        currentPath = "/"
    }
    
    func uploadFile(localPath: URL, remotePath: String) async {
        guard let server = currentConnection, isConnected else { return }
        
        // Optimistic Update
        let filename = localPath.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: localPath.path)[.size] as? UInt64) ?? 0
        let newFile = FileInfo(name: filename, path: remotePath.hasSuffix("/") ? remotePath + filename : remotePath + "/" + filename, isDirectory: false, size: fileSize, modified: nil, extension: localPath.pathExtension)
        
        await MainActor.run {
            if !remoteFiles.contains(where: { $0.name == filename }) {
                remoteFiles.append(newFile)
                remoteFiles.sort { $0.isDirectory && !$1.isDirectory }
            }
        }
        
        do {
            let data = try Data(contentsOf: localPath)
            let targetPath = remotePath.hasSuffix("/") ? remotePath + filename : remotePath + "/" + filename
            
            try await BackendService.shared.uploadRemoteFile(id: server.id.uuidString, path: targetPath, content: data)
            // Refresh purely to sync metadata
            await listFiles(at: currentPath)
        } catch {
            print("Upload error: \(error)")
            // Revert if failed
            await listFiles(at: currentPath)
        }
    }
    
    func downloadFile(remotePath: String, localDir: URL) async -> URL? {
         guard let server = currentConnection, isConnected else { return nil }
         do {
             let data = try await BackendService.shared.downloadRemoteFile(id: server.id.uuidString, path: remotePath)
             let filename = URL(fileURLWithPath: remotePath).lastPathComponent
             let targetURL = localDir.appendingPathComponent(filename)
             
             try data.write(to: targetURL)
             return targetURL
         } catch {
             print("Download error: \(error)")
             return nil
         }
    }
    
    func listFiles(at path: String) async {
        guard let server = currentConnection, isConnected else { return }
        
        await MainActor.run { isLoadingFiles = true }
        
        do {
            let files = try await BackendService.shared.listRemoteFiles(id: server.id.uuidString, path: path)
            await MainActor.run {
                self.remoteFiles = files.sorted { $0.isDirectory && !$1.isDirectory }
                self.currentPath = path
                self.isLoadingFiles = false
            }
        } catch {
            await MainActor.run {
                self.remoteFiles = []
                self.lastError = "Failed to list files: \(error.localizedDescription)"
                self.showError = true
                self.isLoadingFiles = false
            }
        }
    }

    func mkdir(path: String) async {
        guard let server = currentConnection, isConnected else { return }
        
        // Optimistic
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        let newFolder = FileInfo(name: folderName, path: path, isDirectory: true, size: 0, modified: nil, extension: nil)
        
        await MainActor.run {
            remoteFiles.append(newFolder)
            remoteFiles.sort { $0.isDirectory && !$1.isDirectory }
        }
        
        do {
            try await BackendService.shared.remoteMkdir(id: server.id.uuidString, path: path)
            // No need to refresh immediately if consistent
        } catch {
            print("Mkdir error: \(error)")
            await listFiles(at: currentPath) // Revert
        }
    }
    
    func remove(path: String, isDirectory: Bool) async {
        guard let server = currentConnection, isConnected else { return }
        
        await MainActor.run {
            remoteFiles.removeAll { $0.path == path }
        }
        
        do {
            try await BackendService.shared.remoteRemove(id: server.id.uuidString, path: path, isDirectory: isDirectory)
        } catch {
            print("Remove error: \(error)")
            await listFiles(at: currentPath) // Revert
        }
    }
    
    func rename(source: String, destination: String) async {
        guard let server = currentConnection, isConnected else { return }
        
        await MainActor.run {
             if let index = remoteFiles.firstIndex(where: { $0.path == source }) {
                 let oldItem = remoteFiles[index]
                 let newName = URL(fileURLWithPath: destination).lastPathComponent
                 let newItem = FileInfo(name: newName, path: destination, isDirectory: oldItem.isDirectory, size: oldItem.size, modified: oldItem.modified, extension: URL(fileURLWithPath: destination).pathExtension)
                 remoteFiles[index] = newItem
             }
        }
        
        do {
            try await BackendService.shared.remoteRename(id: server.id.uuidString, source: source, destination: destination)
        } catch {
            print("Rename error: \(error)")
            await listFiles(at: currentPath)
        }
    }
    
    // Legacy single command execution (optional use)
    func executeSingleCommand(_ command: String) async -> String {
        guard let server = currentConnection else { return "Not connected" }
        do {
            return try await BackendService.shared.executeRemoteCommand(id: server.id.uuidString, command: command)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Remote Explorer View

struct RemoteXView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var manager = RemoteConnectionManager.shared
    @State private var selectedServer: RemoteConnectionConfig?
    @State private var showingConfigSheet = false
    @State private var currentConfigMode: ServerConfigSheet.Mode = .add
    @State private var connectionTask: Task<Void, Never>?
    @State private var selectedTab: Int = 0 // 0: Terminal, 1: Files, 2: Info
    @State private var sidebarVisible: Bool = true
    
    var body: some View {
        Group {
            if sidebarVisible {
                DraggableSplitView(initialProportion: 0.3) {
                    serverListPanel
                        .frame(minWidth: 250)
                } right: {
                    mainConnectionContent
                }
            } else {
                mainConnectionContent
            }
        }
        .sheet(isPresented: $showingConfigSheet) {
            ServerConfigSheet(mode: currentConfigMode) { server in
                if case .edit = currentConfigMode {
                    manager.updateServer(server)
                } else {
                    manager.addServer(server)
                }
            }
        }
        .alert("Connection Error", isPresented: $manager.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(manager.lastError ?? "Unknown error occurred.")
        }
    }
    
    @ViewBuilder
    private var mainConnectionContent: some View {
        if manager.isConnected, let connectedServer = manager.currentConnection {
            connectionPanel(server: connectedServer)
        } else if let server = selectedServer {
            connectionPanel(server: server)
        } else {
            emptyStateView
        }
    }
    
    // MARK: - Server List Panel
    
    private var serverListPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Remote Servers", systemImage: "server.rack")
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                Button(action: {
                    currentConfigMode = .add
                    showingConfigSheet = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Add Server")
            }
            .padding(12)
            .background(Color.compat(nsColor: .windowBackgroundColor))
            
            // Sub-header: Import
            HStack {
                Button(action: { manager.importSSHConfig() }) {
                    Label("Import SSH Config", systemImage: "arrow.down.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                Spacer()
            }
            
            Divider()
            
            if manager.servers.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("No Servers")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Add a remote server to get started")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                    
                    Button("Add Server") {
                        currentConfigMode = .add
                        showingConfigSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedServer) {
                    ForEach(manager.servers) { server in
                        ServerRowView(server: server, isSelected: selectedServer?.id == server.id)
                            .tag(server)
                            .onTapGesture {
                                selectedServer = server
                            }
                            .contextMenu {
                                Button("Edit") {
                                    currentConfigMode = .edit(server)
                                    showingConfigSheet = true
                                }
                                Button("Duplicate") {
                                    var copy = server
                                    copy.id = UUID()
                                    copy.name = "\(server.name) Copy"
                                    manager.addServer(copy)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    manager.deleteServer(server)
                                    if selectedServer?.id == server.id {
                                        selectedServer = nil
                                    }
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
                .onAppear {
                    // Auto-select first server if none selected
                    if selectedServer == nil, let first = manager.servers.first {
                        selectedServer = first
                    }
                }
            }
        }
        .background(Color.compat(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Connection Panel
    
    private func connectionPanel(server: RemoteConnectionConfig) -> some View {
        VStack(spacing: 0) {
            // Connection Header
            HStack(spacing: 12) {
                // 1. Sidebar Toggle (Always Visible)
                Button(action: {
                    withAnimation { sidebarVisible.toggle() }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.borderless)
                .padding(6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
                .help(sidebarVisible ? "Hide Server List" : "Show Server List")

                // 2. Server Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: server.connectionType.icon)
                            .foregroundColor(.accentColor)
                        Text(server.name)
                            .font(.headline)
                    }
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(manager.isConnected && manager.currentConnection?.id == server.id ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        
                        // Only show status from manager if ID matches
                        if manager.currentConnection?.id == server.id {
                             Text(manager.isConnected ? "Connected" : manager.connectionStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Disconnected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Text("\(server.username)@\(server.host):\(server.port)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.compat(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)
                
                Button(action: {
                    currentConfigMode = .edit(server)
                    showingConfigSheet = true
                }) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)
                .help("Edit Server")
                
                if manager.isConnected && manager.currentConnection?.id == server.id {
                    // Open in Main Editor (If Workspace Active)
                    if appState.isRemoteProject {
                        Button(action: {
                            // Switch to Main Code View
                            let state: AppState = appState
                            state.editorMode = EditorMode.code
                        }) {
                            Label("Open in Editor", systemImage: "macwindow.on.rectangle")
                        }
                        .buttonStyle(.borderedProminent)
                        .help("Switch to Main Editor View")
                    }
                    
                    Button("Disconnect") {
                        manager.disconnect()
                    }
                    .buttonStyle(.bordered)
                } else if manager.connectionStatus == "Connecting..." && manager.currentConnection?.id == server.id {
                    Button("Cancel") {
                        connectionTask?.cancel()
                        manager.disconnect()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Connect") {
                        // Set selected server before connecting
                        selectedServer = server
                        connectionTask = Task {
                            let success = await manager.connect(to: server)
                            if success {
                                // If FTP/SFTP/FTPS, switch to Files tab automatically
                                if server.connectionType == .ftp || server.connectionType == .sftp || server.connectionType == .ftps {
                                    await MainActor.run {
                                        selectedTab = 1 // Files
                                    }
                                    // Trigger file list
                                    await manager.listFiles(at: manager.currentPath)
                                } else {
                                    await MainActor.run {
                                        selectedTab = 0 // Terminal
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .background(Color.compat(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content Area - Show when connected
            if manager.isConnected, let connectedServer = manager.currentConnection {
                TabView(selection: $selectedTab) {
                    // Only show terminal for SSH
                    if connectedServer.connectionType == .ssh {
                        RemoteTerminalTab(manager: manager)
                            .tabItem {
                                Label("Terminal", systemImage: "terminal.fill")
                            }
                            .tag(0)
                    }
                    
                    RemoteFilesTab(manager: manager, appState: appState)
                        .tabItem {
                            Label("Files", systemImage: "folder.fill")
                        }
                        .tag(1)
                    
                    ServerInfoTab(server: connectedServer)
                        .tabItem {
                            Label("Info", systemImage: "info.circle.fill")
                        }
                        .tag(2)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("Not Connected")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("Click Connect to establish connection")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                    
                    Button("Connect Now") {
                        Task {
                            await manager.connect(to: server)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.4))
            
            Text("Remote Explorer")
                .font(.title)
                .foregroundColor(.secondary)
            
            Text("Select a server or add a new one to get started")
                .font(.body)
                .foregroundColor(.secondary.opacity(0.7))
            
            HStack(spacing: 16) {
                Button {
                    currentConfigMode = .add
                    showingConfigSheet = true
                } label: {
                    Label("Add SSH Server", systemImage: "terminal.fill")
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    var server = RemoteConnectionConfig(name: "New SFTP", host: "", username: "")
                    server.connectionType = .sftp
                    currentConfigMode = .edit(server) // Use edit mode to pass pre-filled object
                    showingConfigSheet = true
                } label: {
                    Label("Add SFTP Server", systemImage: "externaldrive.connected.to.line.below.fill")
                }
                .buttonStyle(.bordered)
            }
            
            // Cloud Presets
            VStack(spacing: 8) {
                Text("Quick Add Cloud Server")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                HStack(spacing: 12) {
                    CloudPresetButton(provider: .aws) {
                        configurePreset(.aws)
                    }
                    CloudPresetButton(provider: .gcp) {
                        configurePreset(.gcp)
                    }
                    CloudPresetButton(provider: .alibaba) {
                        configurePreset(.alibaba)
                    }
                     CloudPresetButton(provider: .digitalocean) {
                        configurePreset(.digitalocean)
                    }
                }
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.compat(nsColor: .textBackgroundColor))
    }
    
    private func configurePreset(_ provider: RemoteConnectionConfig.CloudProvider) {
        var server = RemoteConnectionConfig(name: "New \(provider.displayName)", host: "", username: provider.defaultUser)
        server.provider = provider
        server.connectionType = .ssh
        
        // Provider specific defaults
        if provider == .gcp {
            server.authType = .key
            server.keyPath = "~/.ssh/google_compute_engine"
        } else if provider == .aws {
             server.authType = .key
             // AWS often requires user to pick key, but we can hint
        }
        
        currentConfigMode = .edit(server) // Use edit mode to pre-fill
        showingConfigSheet = true
    }
}

struct CloudPresetButton: View {
    let provider: RemoteConnectionConfig.CloudProvider
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: provider.icon)
                    .font(.system(size: 20))
                    .foregroundColor(provider.color)
                Text(provider.displayName)
                    .font(.system(size: 10))
            }
            .frame(width: 60, height: 50)
            .background(Color.compat(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Server Row View

struct ServerRowView: View {
    let server: RemoteConnectionConfig
    let isSelected: Bool
    @ObservedObject var manager = RemoteConnectionManager.shared
    
    @State private var pulseScale: CGFloat = 1.0
    
    var isConnecting: Bool {
        manager.connectionStatus == "Connecting..." && manager.currentConnection?.id == server.id
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(server.connectionType == .ssh ? Color.green.opacity(0.1) :
                          server.connectionType == .sftp ? Color.blue.opacity(0.1) :
                          Color.orange.opacity(0.1))
                    .frame(width: 36, height: 36)
                
                if isConnecting {
                    Circle()
                        .stroke(Color.green, lineWidth: 2)
                        .frame(width: 44, height: 44)
                        .scaleEffect(pulseScale)
                        .opacity(2.0 - Double(pulseScale))
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                                pulseScale = 2.0
                            }
                        }
                }
                
                Image(systemName: server.provider != .none ? server.provider.icon : server.connectionType.icon)
                    .font(.system(size: 16))
                    .foregroundColor(server.provider != .none ? server.provider.color :
                                    (server.connectionType == .ssh ? .green :
                                    server.connectionType == .sftp ? .blue : .orange))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.system(size: 13, weight: .medium))
                
                Text("\(server.username)@\(server.host)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(server.connectionType.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Server Configuration Sheet

struct ServerConfigSheet: View {
    enum Mode {
        case add
        case edit(RemoteConnectionConfig)
    }
    
    let mode: Mode
    let onSave: (RemoteConnectionConfig) -> Void
    
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "22"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var keyPath: String = ""
    @State private var connectionType: RemoteConnectionConfig.ConnectionType = .ssh
    @State private var provider: RemoteConnectionConfig.CloudProvider = .none
    @State private var authType: RemoteConnectionConfig.AuthType = .password
    @State private var showingKeyPicker = false
    @State private var magicPaste: String = "" // Magic SSH Parser input
    @State private var lastPastedValue: String = ""
    
    @State private var reachabilityStatus: ReachabilityStatus = .unknown
    enum ReachabilityStatus {
        case unknown, checking, reachable, unreachable
    }
    
    var isValid: Bool {
        !name.isEmpty && !host.isEmpty && !username.isEmpty && (authType == .key ? !keyPath.isEmpty : !password.isEmpty)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(mode.isAdd ? "Add Server" : "Edit Server")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.compat(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Magic Paste Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "wand.and.stars")
                                .foregroundColor(.purple)
                            Text("Magic SSH Import")
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                        }
                        
                        TextField("Paste SSH command here (e.g. ssh -i key.pem user@host)", text: $magicPaste)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: magicPaste) { newValue in
                                parseMagicSSH(newValue)
                            }
                        
                        Text("Supports: ssh command, or user@host format")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.1), lineWidth: 1))
                    
                    // Cloud Provider Wizard
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Cloud Provider Wizard")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            ProviderTile(provider: .aws, current: $provider, action: selectProvider)
                            ProviderTile(provider: .gcp, current: $provider, action: selectProvider)
                            ProviderTile(provider: .alibaba, current: $provider, action: selectProvider)
                            ProviderTile(provider: .digitalocean, current: $provider, action: selectProvider)
                            ProviderTile(provider: .none, current: $provider, action: selectProvider)
                        }
                    }
                    // Connection Type
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connection Type")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: $connectionType) {
                            ForEach(RemoteConnectionConfig.ConnectionType.allCases, id: \.self) { type in
                                Label(type.displayName, systemImage: type.icon).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: connectionType) { newValue in
                            port = String(newValue.defaultPort)
                        }
                    }
                    
                    Divider()
                    
                    // Server Details
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Server Details")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Name")
                                .frame(width: 80, alignment: .trailing)
                            TextField("My Server", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            Text("Host")
                                .frame(width: 80, alignment: .trailing)
                            TextField("example.com or IP", text: $host)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: host) { _ in debouncePing() }
                            
                            // Reachability Indicator
                            ZStack {
                                Circle()
                                    .fill(reachabilityStatus == .reachable ? Color.green : 
                                          reachabilityStatus == .unreachable ? Color.red : 
                                          Color.gray.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                
                                if reachabilityStatus == .checking {
                                    Circle()
                                        .stroke(Color.blue, lineWidth: 1)
                                        .frame(width: 14, height: 14)
                                        .scaleEffect(1.5)
                                        .opacity(0)
                                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: false), value: reachabilityStatus)
                                }
                            }
                            .frame(width: 20)
                            .help(reachabilityStatus == .reachable ? "Host is reachable" : 
                                  reachabilityStatus == .unreachable ? "Host is unreachable" : 
                                  "Checking reachability...")
                        }
                        
                        HStack {
                            Text("Port")
                                .frame(width: 80, alignment: .trailing)
                            TextField("22", text: $port)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }
                    
                    Divider()
                    
                    // Authentication
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Authentication")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Username")
                                .frame(width: 80, alignment: .trailing)
                            TextField("root", text: $username)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            Text("Auth Type")
                                .frame(width: 80, alignment: .trailing)
                            Picker("", selection: $authType) {
                                ForEach(RemoteConnectionConfig.AuthType.allCases, id: \.self) { type in
                                    Label(type.displayName, systemImage: type.icon).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        if authType == .password {
                            HStack {
                                Text("Password")
                                    .frame(width: 80, alignment: .trailing)
                                SecureField("Password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                            }
                        } else {
                            HStack {
                                Text("Key Path")
                                    .frame(width: 80, alignment: .trailing)
                                TextField("~/.ssh/id_rsa", text: $keyPath)
                                    .textFieldStyle(.roundedBorder)
                                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                                        if let provider = providers.first {
                                            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                                                if let url = url {
                                                    DispatchQueue.main.async {
                                                        self.keyPath = url.path
                                                        self.authType = .key
                                                    }
                                                }
                                            }
                                            return true
                                        }
                                        return false
                                    }
                                
                                Button("Browse...") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    panel.allowsMultipleSelection = false
                                    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
                                    
                                    if panel.runModal() == .OK, let url = panel.url {
                                        keyPath = url.path
                                        // Save to recent
                                        RemoteConnectionManager.shared.addRecentKey(keyPath)
                                    }
                                }
                            }
                            
                            // Recent Keys Menu
                            if !RemoteConnectionManager.shared.recentKeys.isEmpty {
                                Menu("Recent Keys") {
                                    ForEach(RemoteConnectionManager.shared.recentKeys, id: \.self) { key in
                                        Button(key) {
                                            keyPath = key
                                        }
                                    }
                                }
                                .font(.caption)
                                .padding(.leading, 80) // Align to text field start roughly
                            }
                        }
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer
            VStack {
                 if let result = testResult {
                     Text(result)
                         .foregroundColor(testSuccess ? .green : .red)
                         .font(.caption)
                 }
                 
                 HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    if testingConnection {
                        ProgressView().scaleEffect(0.5)
                    }
                    
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(!isValid || testingConnection)
                    
                    Button(mode.isAdd ? "Add" : "Save") {
                        saveServer()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
                }
            }
            .padding(16)
            .background(Color.compat(nsColor: .windowBackgroundColor))
        }
        .frame(width: 520, height: 600)
        .onAppear {
            if case .edit(let server) = mode {
                name = server.name
                host = server.host
                port = String(server.port)
                username = server.username
                password = server.password
                keyPath = server.keyPath
                connectionType = server.connectionType
                provider = server.provider
                authType = server.authType
                
                // Trigger reachability check
                debouncePing()
            }
        }
    }
    
    @State private var testingConnection = false
    @State private var testResult: String?
    @State private var testSuccess = false
    
    private func selectProvider(_ provider: RemoteConnectionConfig.CloudProvider) {
        self.provider = provider
        if username.isEmpty || username == RemoteConnectionConfig.CloudProvider.none.defaultUser || username == "root" {
            username = provider.defaultUser
        }
        if name.isEmpty {
            name = "My \(provider.displayName) Server"
        }
        if provider == .gcp {
            authType = .key
            keyPath = "~/.ssh/google_compute_engine"
        }
    }
    
    private func parseMagicSSH(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Simple regex-based parsing
        // Target formats:
        // 1. ssh -i path user@host -p port
        // 2. user@host
        
        var parsedUser = ""
        var parsedHost = ""
        var parsedPort = "22"
        var parsedKey = ""
        
        if trimmed.hasPrefix("ssh ") {
            let parts = trimmed.components(separatedBy: .whitespaces)
            var i = 1
            while i < parts.count {
                let part = parts[i]
                if part == "-i" && i + 1 < parts.count {
                    parsedKey = parts[i+1]
                    i += 2
                } else if part == "-p" && i + 1 < parts.count {
                    parsedPort = parts[i+1]
                    i += 2
                } else if !part.hasPrefix("-") && part.contains("@") {
                    let subParts = part.components(separatedBy: "@")
                    parsedUser = subParts[0]
                    parsedHost = subParts[1]
                    i += 1
                } else if !part.hasPrefix("-") && parsedHost.isEmpty {
                    parsedHost = part
                    i += 1
                } else {
                    i += 1
                }
            }
        } else if trimmed.contains("@") {
            let subParts = trimmed.components(separatedBy: "@")
            parsedUser = subParts[0]
            parsedHost = subParts[1]
        }
        
        // Apply if found
        if !parsedUser.isEmpty { username = parsedUser }
        if !parsedHost.isEmpty { host = parsedHost }
        if !parsedPort.isEmpty { port = parsedPort }
        if !parsedKey.isEmpty { 
            keyPath = parsedKey
            authType = .key
        }
        
        if name.isEmpty && !parsedHost.isEmpty {
            name = parsedHost
        }
    }
    
    private func debouncePing() {
        reachabilityStatus = .checking
        // Simple manual debounce for MVP
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            await checkReachability()
        }
    }
    
    private func checkReachability() async {
        guard !host.isEmpty else { 
            reachabilityStatus = .unknown
            return 
        }
        
        do {
            let p = UInt16(port) ?? 22
            let success = try await BackendService.shared.pingRemote(host: host, port: p)
            await MainActor.run {
                reachabilityStatus = success ? .reachable : .unreachable
            }
        } catch {
            await MainActor.run {
                reachabilityStatus = .unreachable
            }
        }
    }
    
    private func testConnection() {
        testingConnection = true
        testResult = nil
        
        let config = RemoteConnectionConfig(
            id: UUID(), // temp id
            name: name,
            host: host,
            port: UInt16(port) ?? 22,
            username: username,
            authType: authType,
            password: password,
            keyPath: keyPath,
            connectionType: connectionType,
            provider: provider
        )
        
        Task {
            do {
                let response = try await BackendService.shared.connectRemote(config: config)
                await MainActor.run {
                    testingConnection = false
                    testSuccess = response.success
                    testResult = response.success ? "Connection Successful!" : "Connection Failed: \(response.message)"
                }
            } catch {
                await MainActor.run {
                    testingConnection = false
                    testSuccess = false
                    testResult = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func saveServer() {
        var server: RemoteConnectionConfig
        
        if case .edit(let existing) = mode {
            server = existing
        } else {
            server = RemoteConnectionConfig(name: name, host: host, username: username)
        }
        
        server.name = name
        server.host = host
        server.port = UInt16(port) ?? 22
        server.username = username
        server.password = password
        server.keyPath = keyPath
        server.connectionType = connectionType
        server.provider = provider
        server.authType = authType
        
        onSave(server)
        dismiss()
    }
}

extension ServerConfigSheet.Mode {
    var isAdd: Bool {
        if case .add = self { return true }
        return false
    }
}

// MARK: - Remote Terminal Tab

struct RemoteTerminalTab: View {
    @ObservedObject var manager: RemoteConnectionManager
    @EnvironmentObject var appState: AppState
    @State private var externalCommand: String?
    
    var body: some View {
        ZStack {
            // Background Blur Effect
            VisualEffectView(material: NSVisualEffectView.Material.underWindowBackground, blendingMode: NSVisualEffectView.BlendingMode.behindWindow)
                .ignoresSafeArea()
            
            // Tint Overlay for "Semi-Transparent" feel
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            if let serverId = manager.currentConnection?.id.uuidString,
               let url = BackendService.shared.remoteShellWebSocketURL(id: serverId) {
                
                TransparentTerminalView(
                    url: url,
                    theme: appState.appTheme,
                    fontSize: Int(appState.fontSize),
                    fontFamily: appState.fontFamily,
                    externalCommand: $externalCommand
                )
                .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                .padding(4) // Small padding from edges
            } else {
                VStack {
                    ProgressView()
                    Text("Initializing Terminal Session...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}



// MARK: - Remote Files Tab

struct RemoteFilesTab: View {
    @ObservedObject var manager: RemoteConnectionManager
    @State private var remotePathInput: String = "/"
    
    // UI State
    @State private var showingNewFolderAlert = false
    @State private var showingNewFileAlert = false
    @State private var showingRenameAlert = false
    @State private var showingDeleteConfirm = false
    @State private var showingOpenWorkspaceAlert = false
    @State private var showingNewProjectAlert = false
    @State private var autoRefreshEnabled = true
    @State private var newNameInput = ""
    @State private var itemToRename: String?
    @State private var itemToDelete: FileInfo?
    
    @ObservedObject var appState: AppState
    
    // Local State
    @State private var localPath: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var localFiles: [LocalFile] = []
    
    struct LocalFile: Identifiable {
        let id = UUID()
        let name: String
        let url: URL
        let isDirectory: Bool
        let size: Int64
    }
    
    var body: some View {
        DraggableSplitView(initialProportion: 0.5) {
            // LEFT: Local
            localPane
        } right: {
            // RIGHT: Remote
            remotePane
        }
    }
    
    // MARK: - Local Pane
    
    private var localPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "macmini")
                Text("Local")
                    .font(.headline)
                Spacer()
                Button(action: headerUpLocal) { Image(systemName: "arrow.up") }
            }
            .padding(8)
            .background(Color.compat(nsColor: .controlBackgroundColor))
            
            // Path
            Text(localPath.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            
            Divider()
            
            // List
            List {
                ForEach(localFiles) { file in
                    localFileRow(file)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                for provider in providers {
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
                        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                            Task { await manager.uploadFile(localPath: url, remotePath: manager.currentPath) }
                        }
                    }
                }
                return true
            }
        }
    }
    
    private func localFileRow(_ file: LocalFile) -> some View {
        HStack {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                .foregroundColor(file.isDirectory ? .blue : .secondary)
            Text(file.name)
            Spacer()
            if !file.isDirectory {
                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if file.isDirectory {
                navigateLocal(to: file.url)
            } else {
                NSWorkspace.shared.open(file.url)
            }
        }
        .contextMenu {
            Button("Upload to Remote") {
                Task { await manager.uploadFile(localPath: file.url, remotePath: manager.currentPath) }
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
        }
    }
    // MARK: - Remote Pane
    
    private var remotePane: some View {
        VStack(spacing: 0) {
            remoteHeader
            remotePathEntry
            Divider()
            remoteFileList
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
                     if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                         Task { await manager.uploadFile(localPath: url, remotePath: manager.currentPath) }
                     }
                }
            }
            return true
        }
        .frame(minWidth: 200)
        .alert("New Folder", isPresented: $showingNewFolderAlert) {
            TextField("Folder Name", text: $newNameInput)
            Button("Create") {
                let path = manager.currentPath.hasSuffix("/") ? manager.currentPath + newNameInput : manager.currentPath + "/" + newNameInput
                Task { await manager.mkdir(path: path) }
                newNameInput = ""
            }
            Button("Cancel", role: .cancel) { newNameInput = "" }
        }
        .alert("New File", isPresented: $showingNewFileAlert) {
            TextField("File Name", text: $newNameInput)
            Button("Create") {
                let path = manager.currentPath.hasSuffix("/") ? manager.currentPath + newNameInput : manager.currentPath + "/" + newNameInput
                Task { await manager.uploadFile(localPath: URL(fileURLWithPath: "/dev/null"), remotePath: manager.currentPath)
                       let serverId = manager.currentConnection?.id.uuidString ?? ""
                       try? await BackendService.shared.uploadRemoteFile(id: serverId, path: path, content: Data())
                       await manager.listFiles(at: manager.currentPath)
                }
                newNameInput = ""
            }
            Button("Cancel", role: .cancel) { newNameInput = "" }
        }
        .alert("New Project", isPresented: $showingNewProjectAlert) {
            TextField("Project Name", text: $newNameInput)
            Button("Create & Open") {
                let path = manager.currentPath.hasSuffix("/") ? manager.currentPath + newNameInput : manager.currentPath + "/" + newNameInput
                Task {
                    await manager.mkdir(path: path)
                    await openRemoteWorkspace(path: path)
                }
                newNameInput = ""
            }
            Button("Cancel", role: .cancel) { newNameInput = "" }
        }
        .alert("Rename Item", isPresented: $showingRenameAlert) {
            TextField("New Name", text: $newNameInput)
            Button("Rename") {
                if let oldName = itemToRename {
                    let source = manager.currentPath.hasSuffix("/") ? manager.currentPath + oldName : manager.currentPath + "/" + oldName
                    let dest = manager.currentPath.hasSuffix("/") ? manager.currentPath + newNameInput : manager.currentPath + "/" + newNameInput
                    Task { await manager.rename(source: source, destination: dest) }
                }
                newNameInput = ""
                itemToRename = nil
            }
            Button("Cancel", role: .cancel) { 
                newNameInput = ""
                itemToRename = nil
            }
        }
        .alert("Delete Item", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let file = itemToDelete {
                    Task { await manager.remove(path: file.path, isDirectory: file.isDirectory) }
                }
                itemToDelete = nil
            }
            Button("Cancel", role: .cancel) { itemToDelete = nil }
        } message: {
            Text("Are you sure you want to delete '\(itemToDelete?.name ?? "")'?")
        }
        .alert("Open as Workspace", isPresented: $showingOpenWorkspaceAlert) {
            Button("Open") {
                Task { await openRemoteWorkspace(path: manager.currentPath) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Open '\(manager.currentPath)' as a workspace?\n\nFiles will be downloaded and cached locally. Changes will sync automatically.")
        }
    }
    
    private var remoteHeader: some View {
        HStack {
            Image(systemName: "server.rack")
            Text("Remote")
                .font(.headline)
            Spacer()
            Button(action: { showingOpenWorkspaceAlert = true }) { 
                Image(systemName: "folder.badge.gearshape")
                Text("Workspace")
            }
            .help("Open current directory as workspace")
            
            Button(action: { showingNewProjectAlert = true }) {
                Image(systemName: "plus.app.fill")
                Text("New Project")
            }
            .help("Create new project folder and open")
            Button(action: { showingNewFolderAlert = true }) { Image(systemName: "folder.badge.plus") }
            Button(action: { showingNewFileAlert = true }) { Image(systemName: "doc.badge.plus") }
            
            Button(action: { autoRefreshEnabled.toggle() }) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(autoRefreshEnabled ? .accentColor : .secondary)
            }
            .help(autoRefreshEnabled ? "Auto-refresh on (5s)" : "Auto-refresh off")
            
            Button(action: headerUpRemote) { Image(systemName: "arrow.up") }
            Button(action: { refreshRemote() }) { Image(systemName: "arrow.clockwise") }
        }
        .padding(8)
        .background(Color.compat(nsColor: .controlBackgroundColor))
    }
    
    private var remotePathEntry: some View {
        TextField("Remote Path", text: $remotePathInput)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                Task { await manager.listFiles(at: remotePathInput) }
            }
            .padding(4)
    }
    
    private var remoteFileList: some View {
        Group {
            if manager.isLoadingFiles {
                VStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if manager.remoteFiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Empty Directory")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(manager.lastError ?? "No files found at this path")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Refresh") {
                        refreshRemote()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.remoteFiles, id: \.name) { file in
                        remoteFileRow(file)
                    }
                }
            }
        }
    }
    
    // MARK: - Remote File Row
    
    private func remoteFileRow(_ file: FileInfo) -> some View {
        HStack {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                .foregroundColor(file.isDirectory ? .blue : .secondary)
            Text(file.name)
            Spacer()
            Text(file.isDirectory ? "Dir" : ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if file.isDirectory {
                let newPath = manager.currentPath.hasSuffix("/") ? manager.currentPath + file.name : manager.currentPath + "/" + file.name
                Task { await manager.listFiles(at: newPath) }
            } else {
                // Open Remote File
                Task {
                    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CodeTunnerRemote/\(manager.currentConnection?.id.uuidString ?? "unknown")")
                    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    
                    if let localURL = await manager.downloadFile(remotePath: file.path, localDir: tempDir) {
                        let codeExts = ["swift", "py", "rs", "js", "ts", "c", "cpp", "h", "java", "kt", "html", "css", "json", "md", "txt", "sh", "yml", "xml", "go", "php", "rb", "sql"]
                        if codeExts.contains(localURL.pathExtension.lowercased()) {
                            if let serverId = manager.currentConnection?.id {
                                appState.remoteWorkspaceManager.registerTempFile(localURL: localURL, remotePath: file.path, serverId: serverId)
                            }
                            await appState.loadFile(url: localURL)
                            await MainActor.run { 
                                let state: AppState = appState
                                state.editorMode = EditorMode.code 
                            }
                        } else {
                            NSWorkspace.shared.open(localURL)
                        }
                    }
                }
            }
        }
        .contextMenu {
            if file.isDirectory {
                Button("Open as Workspace") {
                    Task { await openRemoteWorkspace(path: file.path) }
                }
                Divider()
            }
            Button("Download to Local") {
                Task {
                    _ = await manager.downloadFile(remotePath: file.path, localDir: localPath)
                    loadLocalFiles() // Refresh local
                }
            }
            Button("Rename") {
                itemToRename = file.name
                newNameInput = file.name
                showingRenameAlert = true
            }
            Button("Delete", role: .destructive) {
                itemToDelete = file
                showingDeleteConfirm = true
            }
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }
        }
    }
    
    // MARK: - Auto Refresh Effect
    
    private var autoRefreshEffect: some View {
        EmptyView()
            .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
                if autoRefreshEnabled && !manager.isLoadingFiles {
                    refreshRemote()
                }
            }
    }
    
    // MARK: - Local Helpers
    
    private func loadLocalFiles() {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: localPath, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])
            
            localFiles = try urls.map { url in
                let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                return LocalFile(
                    name: url.lastPathComponent,
                    url: url,
                    isDirectory: resourceValues.isDirectory ?? false,
                    size: Int64(resourceValues.fileSize ?? 0)
                )
            }.sorted { $0.isDirectory && !$1.isDirectory }
        } catch {
            print("Error loading local files: \(error)")
            localFiles = []
        }
    }
    
    private func navigateLocal(to url: URL) {
        localPath = url
        loadLocalFiles()
    }
    
    private func headerUpLocal() {
        let parent = localPath.deletingLastPathComponent()
        localPath = parent
        loadLocalFiles()
    }
    
    // MARK: - Remote Helpers
    
    private func refreshRemote() {
        Task {
            await manager.listFiles(at: manager.currentPath)
        }
    }
    
    private func openRemoteWorkspace(path: String) async {
        guard let server = manager.currentConnection else { return }
        
        // Capture appState reference before async
        let appStateRef = appState
        
        do {
            try await appStateRef.remoteWorkspaceManager.openRemoteProject(server: server, remotePath: path)
            
            // Update AppState workspace folder to the cached location
            await MainActor.run {
                if let workspace = appStateRef.remoteWorkspaceManager.currentWorkspace {
                    appStateRef.workspaceFolder = workspace.localCachePath
                    // File tree will auto-update via AppState
                }
            }
        } catch {
            print("Failed to open remote workspace: \\(error)")
        }
    }
    
    private func headerUpRemote() {
        let current = manager.currentPath
        let components = current.split(separator: "/")
        if !components.isEmpty {
            let parent = "/" + components.dropLast().joined(separator: "/")
            Task { await manager.listFiles(at: parent) }
        } else if current != "/" {
             Task { await manager.listFiles(at: "/") }
        }
    }
}
// MARK: - Server Info Tab

struct ServerInfoTab: View {
    let server: RemoteConnectionConfig
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Connection Details") {
                    VStack(alignment: .leading, spacing: 12) {
                        RemoteInfoRow(label: "Name", value: server.name)
                        RemoteInfoRow(label: "Type", value: server.connectionType.displayName)
                        RemoteInfoRow(label: "Host", value: server.host)
                        RemoteInfoRow(label: "Port", value: String(server.port))
                        RemoteInfoRow(label: "Username", value: server.username)
                        if server.provider != .none {
                            RemoteInfoRow(label: "Cloud Provider", value: server.provider.displayName)
                        }
                        
                        if let lastConnected = server.lastConnected {
                            RemoteInfoRow(label: "Last Connected", value: lastConnected.formatted())
                        }
                    }
                    .padding(8)
                }
                
                GroupBox("Sync Options") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: bindingForSync(server)) {
                            Label("Sync with Project", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .toggleStyle(.switch)
                        
                        Text("When enabled, saving a file in your project will automatically upload it to this server.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
    }
    
    @EnvironmentObject var appState: AppState
    
    private func bindingForSync(_ server: RemoteConnectionConfig) -> Binding<Bool> {
        Binding(
            get: {
                appState.remoteSyncEnabled && appState.activeRemoteSync?.id == server.id
            },
            set: { newValue in
                if newValue {
                    appState.activeRemoteSync = server
                    appState.remoteSyncEnabled = true
                } else {
                    if appState.activeRemoteSync?.id == server.id {
                        appState.remoteSyncEnabled = false
                    }
                }
            }
        )
    }
}

struct RemoteInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .trailing)
            Text(value)
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
    }
}

// MARK: - Ultra UI Components

struct ProviderTile: View {
    let provider: RemoteConnectionConfig.CloudProvider
    @Binding var current: RemoteConnectionConfig.CloudProvider
    let action: (RemoteConnectionConfig.CloudProvider) -> Void
    
    var isSelected: Bool { current == provider }
    
    var body: some View {
        Button(action: { action(provider) }) {
            VStack(spacing: 8) {
                Image(systemName: provider.icon)
                    .font(.system(size: 20))
                Text(provider.displayName)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(width: 85, height: 70)
            .background(isSelected ? provider.brandColor.opacity(0.15) : Color.secondary.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? provider.brandColor : Color.clear, lineWidth: 2)
            )
            .foregroundColor(isSelected ? provider.brandColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

extension RemoteConnectionConfig.CloudProvider {
    var brandColor: Color {
        switch self {
        case .aws: return .orange
        case .gcp: return .blue
        case .alibaba: return .orange
        case .digitalocean: return .cyan
        case .none: return .gray
        }
    }
}
