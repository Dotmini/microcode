//
//  GitSettingsView.swift
//  CodeTunner
//
//  Git configuration and settings management
//

import SwiftUI

// MARK: - Git Settings View

struct GitSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    // User Config
    @State private var userName: String = ""
    @State private var userEmail: String = ""
    
    // Repository Config
    @State private var defaultBranch: String = "main"
    @State private var remoteURL: String = ""
    @State private var remoteName: String = "origin"
    
    // Preferences
    @State private var autoFetch: Bool = true
    @State private var autoStage: Bool = false
    @State private var signCommits: Bool = false
    @State private var pushTags: Bool = true
    
    // Authentication
    @State private var authMethod: GitAuthMethod = .https
    @State private var sshKeyPath: String = ""
    @State private var personalAccessToken: String = ""
    @State private var showToken: Bool = false
    
    // Branch Management
    @State private var branches: [String] = []
    @State private var currentBranch: String = ""
    @State private var newBranchName: String = ""
    @State private var showNewBranchSheet: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var branchToDelete: String = ""
    
    // State
    @State private var isLoading: Bool = false
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""
    @State private var selectedTab: GitSettingsTab = .config
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Tabs
            tabBar
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .config:
                        configSection
                    case .repository:
                        repositorySection
                    case .auth:
                        authSection
                    case .branches:
                        branchesSection
                    case .preferences:
                        preferencesSection
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer
            footer
        }
        .frame(width: 600, height: 550)
        .onAppear {
            loadGitConfig()
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.title2)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Git Settings")
                    .font(.headline)
                Text("Configure Git for your project")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Tab Bar
    
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(GitSettingsTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation { selectedTab = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                        Text(tab.rawValue)
                    }
                    .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    
    // MARK: - Config Section
    
    private var configSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("User Identity")
                .font(.headline)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Name")
                            .frame(width: 80, alignment: .leading)
                        TextField("Your Name", text: $userName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Email")
                            .frame(width: 80, alignment: .leading)
                        TextField("you@example.com", text: $userEmail)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Text("These settings will be used for Git commits.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            Text("Default Settings")
                .font(.headline)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Default Branch")
                            .frame(width: 120, alignment: .leading)
                        Picker("", selection: $defaultBranch) {
                            Text("main").tag("main")
                            Text("master").tag("master")
                            Text("develop").tag("develop")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    // MARK: - Repository Section
    
    private var repositorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Remote Configuration")
                .font(.headline)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Remote Name")
                            .frame(width: 100, alignment: .leading)
                        TextField("origin", text: $remoteName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Remote URL")
                            .frame(width: 100, alignment: .leading)
                        TextField("https://github.com/user/repo.git", text: $remoteURL)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.vertical, 4)
            }
            
            HStack {
                Button("Fetch") { fetchRemote() }
                    .buttonStyle(.bordered)
                
                Button("Set Remote") { setRemote() }
                    .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            Text("Repository Info")
                .font(.headline)
            
            if let folder = appState.workspaceFolder {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Path", value: folder.path)
                        InfoRow(label: "Branch", value: currentBranch)
                        if let status = appState.gitStatus {
                            InfoRow(label: "Changes", value: "\(status.files.count) files")
                            InfoRow(label: "Ahead", value: "\(status.ahead)")
                            InfoRow(label: "Behind", value: "\(status.behind)")
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("No repository open")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Auth Section
    
    private var authSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Authentication Method")
                .font(.headline)
            
            Picker("Method", selection: $authMethod) {
                ForEach(GitAuthMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.segmented)
            
            GroupBox {
                switch authMethod {
                case .https:
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Personal Access Token")
                            .font(.subheadline.bold())
                        
                        HStack {
                            if showToken {
                                TextField("ghp_xxxx...", text: $personalAccessToken)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("ghp_xxxx...", text: $personalAccessToken)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            Button {
                                showToken.toggle()
                            } label: {
                                Image(systemName: showToken ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }
                        
                        Link("Generate token on GitHub", destination: URL(string: "https://github.com/settings/tokens")!)
                            .font(.caption)
                    }
                    
                case .ssh:
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SSH Key")
                            .font(.subheadline.bold())
                        
                        HStack {
                            TextField("~/.ssh/id_ed25519", text: $sshKeyPath)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("Browse") {
                                selectSSHKey()
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Button("Generate New SSH Key") {
                            generateSSHKey()
                        }
                        .buttonStyle(.bordered)
                        
                        Text("Make sure your public key is added to your Git provider")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                case .credential:
                    VStack(alignment: .leading, spacing: 12) {
                        Text("macOS Keychain")
                            .font(.subheadline.bold())
                        
                        Text("Credentials stored in macOS Keychain will be used automatically.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button("Open Keychain Access") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keychain-Access")!)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            Button("Save Authentication") {
                saveAuth()
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Branches Section
    
    private var branchesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Branches")
                    .font(.headline)
                
                Spacer()
                
                Button { loadBranches() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                
                Button { showNewBranchSheet = true } label: {
                    Label("New Branch", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            
            if branches.isEmpty {
                GroupBox {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No branches found")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            } else {
                List {
                    ForEach(branches, id: \.self) { branch in
                        HStack {
                            Image(systemName: branch == currentBranch ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(branch == currentBranch ? .green : .secondary)
                            
                            Text(branch)
                                .font(.system(.body, design: .monospaced))
                            
                            if branch == currentBranch {
                                Text("current")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green)
                                    .cornerRadius(4)
                            }
                            
                            Spacer()
                            
                            if branch != currentBranch {
                                Button("Checkout") {
                                    checkoutBranch(branch)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button {
                                    branchToDelete = branch
                                    showDeleteConfirm = true
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
                .frame(height: 200)
            }
        }
        .sheet(isPresented: $showNewBranchSheet) {
            newBranchSheet
        }
        .alert("Delete Branch", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteBranch(branchToDelete)
            }
        } message: {
            Text("Are you sure you want to delete '\(branchToDelete)'?")
        }
    }
    
    private var newBranchSheet: some View {
        VStack(spacing: 16) {
            Text("Create New Branch")
                .font(.headline)
            
            TextField("Branch name", text: $newBranchName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
            
            HStack {
                Button("Cancel") { showNewBranchSheet = false }
                    .buttonStyle(.bordered)
                
                Button("Create") {
                    createBranch(newBranchName)
                    showNewBranchSheet = false
                    newBranchName = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newBranchName.isEmpty)
            }
        }
        .padding(20)
    }
    
    // MARK: - Preferences Section
    
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Git Preferences")
                .font(.headline)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-fetch on project open", isOn: $autoFetch)
                    Toggle("Auto-stage changes before commit", isOn: $autoStage)
                    Toggle("Sign commits with GPG", isOn: $signCommits)
                    Toggle("Push tags with commits", isOn: $pushTags)
                }
                .padding(.vertical, 4)
            }
            
            Divider()
            
            Text("Commit Settings")
                .font(.headline)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show commit message suggestions", isOn: .constant(true))
                    Toggle("Require commit message", isOn: .constant(true))
                    Toggle("Auto-add Co-authored-by", isOn: .constant(false))
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            if !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            if !successMessage.isEmpty {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
            Spacer()
            
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
            
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
            
            Button("Save") { saveConfig() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func loadGitConfig() {
        // Load from git config
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["config", "--global", "--list"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.split(separator: "\n") {
                    let parts = line.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        let key = String(parts[0])
                        let value = String(parts[1])
                        
                        switch key {
                        case "user.name": userName = value
                        case "user.email": userEmail = value
                        case "init.defaultbranch": defaultBranch = value
                        default: break
                        }
                    }
                }
            }
        } catch {
            errorMessage = "Failed to load git config"
        }
        
        loadBranches()
        
        if let status = appState.gitStatus {
            currentBranch = status.branch
        }
    }
    
    private func loadBranches() {
        guard let folder = appState.workspaceFolder else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["branch", "--list"]
        process.currentDirectoryURL = folder
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                branches = output.split(separator: "\n").map { line in
                    var name = String(line).trimmingCharacters(in: .whitespaces)
                    if name.hasPrefix("* ") {
                        name = String(name.dropFirst(2))
                        currentBranch = name
                    }
                    return name
                }
            }
        } catch {
            errorMessage = "Failed to load branches"
        }
    }
    
    private func saveConfig() {
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                // Save user config
                try runGitCommand(["config", "--global", "user.name", userName])
                try runGitCommand(["config", "--global", "user.email", userEmail])
                try runGitCommand(["config", "--global", "init.defaultBranch", defaultBranch])
                
                // Save preferences to UserDefaults
                UserDefaults.standard.set(autoFetch, forKey: "git.autoFetch")
                UserDefaults.standard.set(autoStage, forKey: "git.autoStage")
                UserDefaults.standard.set(signCommits, forKey: "git.signCommits")
                UserDefaults.standard.set(pushTags, forKey: "git.pushTags")
                
                await MainActor.run {
                    successMessage = "Settings saved"
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func runGitCommand(_ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        try process.run()
        process.waitUntilExit()
    }
    
    private func fetchRemote() {
        guard let folder = appState.workspaceFolder else { return }
        
        isLoading = true
        Task {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["fetch", remoteName]
                process.currentDirectoryURL = folder
                try process.run()
                process.waitUntilExit()
                
                await MainActor.run {
                    successMessage = "Fetched from \(remoteName)"
                    isLoading = false
                    appState.gitRefresh()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Fetch failed"
                    isLoading = false
                }
            }
        }
    }
    
    private func setRemote() {
        guard let folder = appState.workspaceFolder, !remoteURL.isEmpty else { return }
        
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["remote", "set-url", remoteName, remoteURL]
            process.currentDirectoryURL = folder
            
            do {
                try process.run()
                process.waitUntilExit()
                successMessage = "Remote updated"
            } catch {
                // Try adding if not exists
                let addProcess = Process()
                addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                addProcess.arguments = ["remote", "add", remoteName, remoteURL]
                addProcess.currentDirectoryURL = folder
                try? addProcess.run()
                addProcess.waitUntilExit()
                successMessage = "Remote added"
            }
        }
    }
    
    private func selectSSHKey() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        
        if panel.runModal() == .OK, let url = panel.url {
            sshKeyPath = url.path
        }
    }
    
    private func generateSSHKey() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-t", "ed25519", "-C", userEmail, "-f", "\(NSHomeDirectory())/.ssh/id_ed25519_codetunner", "-N", ""]
        
        do {
            try process.run()
            process.waitUntilExit()
            sshKeyPath = "\(NSHomeDirectory())/.ssh/id_ed25519_codetunner"
            successMessage = "SSH key generated"
        } catch {
            errorMessage = "Failed to generate SSH key"
        }
    }
    
    private func saveAuth() {
        switch authMethod {
        case .https:
            // Store token in keychain
            if !personalAccessToken.isEmpty {
                UserDefaults.standard.set(personalAccessToken, forKey: "git.personalAccessToken")
                successMessage = "Token saved"
            }
        case .ssh:
            UserDefaults.standard.set(sshKeyPath, forKey: "git.sshKeyPath")
            successMessage = "SSH key path saved"
        case .credential:
            successMessage = "Using macOS Keychain"
        }
    }
    
    private func createBranch(_ name: String) {
        guard let folder = appState.workspaceFolder, !name.isEmpty else { return }
        
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["checkout", "-b", name]
            process.currentDirectoryURL = folder
            
            do {
                try process.run()
                process.waitUntilExit()
                await MainActor.run {
                    loadBranches()
                    appState.gitRefresh()
                    successMessage = "Branch '\(name)' created"
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to create branch"
                }
            }
        }
    }
    
    private func checkoutBranch(_ name: String) {
        guard let folder = appState.workspaceFolder else { return }
        
        isLoading = true
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["checkout", name]
            process.currentDirectoryURL = folder
            
            do {
                try process.run()
                process.waitUntilExit()
                await MainActor.run {
                    currentBranch = name
                    loadBranches()
                    appState.gitRefresh()
                    successMessage = "Switched to '\(name)'"
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to checkout"
                    isLoading = false
                }
            }
        }
    }
    
    private func deleteBranch(_ name: String) {
        guard let folder = appState.workspaceFolder else { return }
        
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["branch", "-d", name]
            process.currentDirectoryURL = folder
            
            do {
                try process.run()
                process.waitUntilExit()
                await MainActor.run {
                    loadBranches()
                    successMessage = "Branch '\(name)' deleted"
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to delete branch"
                }
            }
        }
    }
}

// MARK: - Supporting Types

enum GitSettingsTab: String, CaseIterable {
    case config = "Config"
    case repository = "Repository"
    case auth = "Auth"
    case branches = "Branches"
    case preferences = "Preferences"
    
    var icon: String {
        switch self {
        case .config: return "person.fill"
        case .repository: return "externaldrive.fill"
        case .auth: return "key.fill"
        case .branches: return "arrow.triangle.branch"
        case .preferences: return "gearshape.fill"
        }
    }
}

enum GitAuthMethod: String, CaseIterable {
    case https = "HTTPS Token"
    case ssh = "SSH Key"
    case credential = "Keychain"
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
        }
    }
}
