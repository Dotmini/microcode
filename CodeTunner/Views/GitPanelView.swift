import SwiftUI

// ==========================================
// Git Manager Panel — Production Grade
// Branch, Stage, Diff, Stash, CI/CD
// ==========================================

struct GitPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var showGitSettings = false
    @State private var showCommitSheet = false
    @State private var commitMessage = ""
    @State private var selectedTab = 0 // 0=Changes, 1=Branches, 2=History, 3=Stash, 4=CI/CD
    @State private var expandStaged = true
    @State private var expandUnstaged = true
    @State private var expandUntracked = true
    @State private var newBranchName = ""
    @State private var showNewBranch = false
    @State private var stashMessage = ""
    @State private var showDiffFor: String?
    @State private var diffContent = ""
    @State private var showConfirmDiscard = false
    @State private var discardTarget = ""
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            
            if let status = appState.gitStatus {
                branchBar(status: status)
                Divider()
                tabBar
                Divider()
                
                switch selectedTab {
                case 0: changesTab(status: status)
                case 1: branchesTab
                case 2: historyTab
                case 3: stashTab
                case 4: cicdTab
                default: changesTab(status: status)
                }
                
                Divider()
                actionsBar(status: status)
            } else {
                notRepoState
            }
        }
        .sheet(isPresented: $showGitSettings) { GitSettingsView().environmentObject(appState) }
        .sheet(isPresented: $showCommitSheet) { commitSheet }
        .alert("Discard Changes?", isPresented: $showConfirmDiscard) {
            Button("Discard", role: .destructive) { appState.gitDiscardFile(discardTarget) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will discard all changes to \(discardTarget)")
        }
    }
    
    // MARK: - Header
    private var header: some View {
        HStack {
            Image(systemName: "arrow.triangle.branch").foregroundColor(.orange)
            Text("Source Control").font(.system(size: 11, weight: .semibold))
            Spacer()
            Button { appState.gitRefresh() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 10))
            }.buttonStyle(.borderless).help("Refresh")
            Button { showGitSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 10))
            }.buttonStyle(.borderless).help("Settings")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Branch Bar
    private func branchBar(status: GitStatus) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(appState.gitBranches.filter { !$0.contains("remotes/") }, id: \.self) { b in
                    Button(b) { appState.gitSwitchBranch(b) }
                }
                if !appState.gitBranches.filter({ $0.contains("remotes/") }).isEmpty {
                    Divider()
                    Menu("Remote Branches") {
                        ForEach(appState.gitBranches.filter { $0.contains("remotes/") }, id: \.self) { b in
                            let short = b.replacingOccurrences(of: "remotes/origin/", with: "")
                            Button(short) { appState.gitSwitchBranch(short) }
                        }
                    }
                }
                Divider()
                Button { showNewBranch = true } label: { Label("New Branch...", systemImage: "plus") }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
                    Text(status.branch).font(.system(size: 11, weight: .medium, design: .monospaced))
                    Image(systemName: "chevron.down").font(.system(size: 7))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1)).cornerRadius(4)
            }.buttonStyle(.plain)
            
            Spacer()
            
            if status.ahead > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up").font(.system(size: 8))
                    Text("\(status.ahead)").font(.system(size: 10))
                }.foregroundColor(.green)
            }
            if status.behind > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down").font(.system(size: 8))
                    Text("\(status.behind)").font(.system(size: 10))
                }.foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .popover(isPresented: $showNewBranch) {
            VStack(spacing: 12) {
                Text("New Branch").font(.headline)
                TextField("branch-name", text: $newBranchName).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { showNewBranch = false }.buttonStyle(.bordered)
                    Spacer()
                    Button("Create & Switch") {
                        if !newBranchName.isEmpty {
                            appState.gitCreateBranch(newBranchName)
                            newBranchName = ""
                            showNewBranch = false
                        }
                    }.buttonStyle(.borderedProminent)
                }
            }.padding().frame(width: 280)
        }
    }
    
    // MARK: - Tab Bar
    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("Changes", icon: "doc.badge.plus", tag: 0)
            tabButton("Branches", icon: "arrow.triangle.branch", tag: 1)
            tabButton("History", icon: "clock.arrow.circlepath", tag: 2)
            tabButton("Stash", icon: "tray.and.arrow.down", tag: 3)
            tabButton("CI/CD", icon: "gearshape.2", tag: 4)
        }
        .padding(.horizontal, 4).padding(.vertical, 4)
    }
    
    private func tabButton(_ title: String, icon: String, tag: Int) -> some View {
        Button {
            selectedTab = tag
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 10))
                Text(title).font(.system(size: 8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(selectedTab == tag ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .foregroundColor(selectedTab == tag ? .accentColor : .secondary)
    }
    
    // MARK: - Tab 0: Changes
    private func changesTab(status: GitStatus) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                let staged = status.files.filter { $0.status == "added" || $0.status == "modified" || $0.status == "deleted" || $0.status == "renamed" }
                let untracked = status.files.filter { $0.status == "untracked" }
                
                if !staged.isEmpty {
                    fileSection(title: "Changes", files: staged, icon: "checkmark.circle.fill", color: .green,
                                expanded: $expandStaged, isStaged: true)
                }
                if !untracked.isEmpty {
                    fileSection(title: "Untracked", files: untracked, icon: "plus.circle.fill", color: .orange,
                                expanded: $expandUntracked, isStaged: false)
                }
                if status.files.isEmpty { emptyState }
            }.padding(.vertical, 4)
        }
    }
    
    private func fileSection(title: String, files: [GitFileStatus], icon: String, color: Color,
                             expanded: Binding<Bool>, isStaged: Bool) -> some View {
        VStack(spacing: 0) {
            Button { withAnimation { expanded.wrappedValue.toggle() } } label: {
                HStack {
                    Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9)).foregroundColor(.secondary).frame(width: 12)
                    Image(systemName: icon).font(.system(size: 10)).foregroundColor(color)
                    Text(title).font(.system(size: 11, weight: .medium))
                    Spacer()
                    // Stage/Unstage all
                    if isStaged {
                        Button { appState.gitStageAll() } label: {
                            Image(systemName: "plus.circle").font(.system(size: 10))
                        }.buttonStyle(.borderless).help("Stage All")
                    }
                    Text("\(files.count)").font(.system(size: 10)).foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1)).cornerRadius(4)
                }.padding(.horizontal, 12).padding(.vertical, 6)
            }.buttonStyle(.plain)
            
            if expanded.wrappedValue {
                ForEach(files, id: \.path) { file in
                    fileRow(file: file, isStaged: isStaged)
                }
            }
        }
    }
    
    private func fileRow(file: GitFileStatus, isStaged: Bool) -> some View {
        HStack(spacing: 6) {
            statusBadge(file.status)
            Text(file.path.components(separatedBy: "/").last ?? file.path)
                .font(.system(size: 11)).lineLimit(1)
            Spacer()
            if file.path.contains("/") {
                Text(file.path.components(separatedBy: "/").dropLast().joined(separator: "/"))
                    .font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
            }
            // Action buttons
            Button { appState.gitShowDiff(for: file.path); showDiffFor = file.path } label: {
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 9))
            }.buttonStyle(.borderless).help("View Diff")
            
            if isStaged {
                Button { appState.gitUnstageFile(file.path) } label: {
                    Image(systemName: "minus.circle").font(.system(size: 9)).foregroundColor(.orange)
                }.buttonStyle(.borderless).help("Unstage")
            } else {
                Button { appState.gitStageFile(file.path) } label: {
                    Image(systemName: "plus.circle").font(.system(size: 9)).foregroundColor(.green)
                }.buttonStyle(.borderless).help("Stage")
            }
            
            Button { discardTarget = file.path; showConfirmDiscard = true } label: {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 9)).foregroundColor(.red)
            }.buttonStyle(.borderless).help("Discard")
        }
        .padding(.horizontal, 12).padding(.leading, 24).padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if let folder = appState.workspaceFolder {
                Task { await appState.loadFile(url: folder.appendingPathComponent(file.path)) }
            }
        }
        .popover(isPresented: Binding(get: { showDiffFor == file.path }, set: { if !$0 { showDiffFor = nil } })) {
            diffPopover(path: file.path)
        }
    }
    
    private func diffPopover(path: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass").foregroundColor(.blue)
                Text(path).font(.system(size: 11, weight: .medium, design: .monospaced))
                Spacer()
                Button { showDiffFor = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }.padding(8)
            Divider()
            ScrollView {
                Text(appState.gitDiff.isEmpty ? "(no diff)" : appState.gitDiff)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }.frame(width: 500, height: 300)
    }
    
    private func statusBadge(_ status: String) -> some View {
        let (letter, color): (String, Color) = {
            switch status {
            case "added": return ("A", .green)
            case "modified": return ("M", .orange)
            case "deleted": return ("D", .red)
            case "renamed": return ("R", .blue)
            case "untracked": return ("U", .secondary)
            default: return ("?", .secondary)
            }
        }()
        return Text(letter)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .frame(width: 16)
    }
    
    // MARK: - Tab 1: Branches
    private var branchesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                let currentBranch = appState.gitStatus?.branch ?? ""
                let local = appState.gitBranches.filter { !$0.contains("remotes/") }
                let remote = appState.gitBranches.filter { $0.contains("remotes/") }
                
                if !local.isEmpty {
                    sectionHeader("Local Branches", icon: "arrow.triangle.branch", color: .blue)
                    ForEach(local, id: \.self) { b in
                        branchRow(b, isCurrent: b == currentBranch, isRemote: false)
                    }
                }
                if !remote.isEmpty {
                    sectionHeader("Remote Branches", icon: "globe", color: .purple)
                    ForEach(remote, id: \.self) { b in
                        let short = b.replacingOccurrences(of: "remotes/origin/", with: "")
                        branchRow(short, isCurrent: false, isRemote: true)
                    }
                }
            }.padding(.vertical, 4)
        }
    }
    
    private func branchRow(_ name: String, isCurrent: Bool, isRemote: Bool) -> some View {
        HStack(spacing: 8) {
            if isCurrent {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundColor(.green)
            } else {
                Image(systemName: isRemote ? "globe" : "arrow.triangle.branch")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            Text(name).font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
            Spacer()
            if !isCurrent {
                Button { appState.gitSwitchBranch(name) } label: {
                    Text("Switch").font(.system(size: 9))
                }.buttonStyle(.bordered).controlSize(.mini)
                
                if !isRemote {
                    Menu {
                        Button("Merge into current") { appState.gitMergeBranch(name) }
                        Divider()
                        Button("Delete", role: .destructive) { appState.gitDeleteBranch(name) }
                        Button("Force Delete", role: .destructive) { appState.gitDeleteBranch(name, force: true) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 10))
                    }.menuStyle(.borderlessButton).frame(width: 20)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(isCurrent ? Color.accentColor.opacity(0.06) : Color.clear)
    }
    
    // MARK: - Tab 2: History
    private var historyTab: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(appState.gitCommits) { commit in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(commit.message).font(.system(size: 11)).lineLimit(2)
                        HStack(spacing: 8) {
                            Text(String(commit.hash.prefix(7)))
                                .font(.system(size: 9, design: .monospaced)).foregroundColor(.blue)
                            Text(commit.author).font(.system(size: 9)).foregroundColor(.secondary)
                            Spacer()
                            Text(commit.timestamp).font(.system(size: 9)).foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    Divider().padding(.leading, 12)
                }
            }
        }
    }
    
    // MARK: - Tab 3: Stash
    private var stashTab: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Stash message (optional)", text: $stashMessage)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11))
                Button { appState.gitStash(message: stashMessage.isEmpty ? nil : stashMessage); stashMessage = "" } label: {
                    Label("Stash", systemImage: "tray.and.arrow.down")
                }.buttonStyle(.borderedProminent).controlSize(.small)
            }.padding(10)
            Divider()
            
            if appState.gitStashList.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray").font(.system(size: 28)).foregroundColor(.secondary)
                    Text("No stashes").font(.system(size: 12)).foregroundColor(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    ForEach(Array(appState.gitStashList.enumerated()), id: \.offset) { idx, entry in
                        HStack {
                            Image(systemName: "tray.fill").font(.system(size: 10)).foregroundColor(.blue)
                            Text(entry).font(.system(size: 10)).lineLimit(1)
                            Spacer()
                            Button("Pop") { appState.gitStashPop(index: idx) }
                                .buttonStyle(.bordered).controlSize(.mini)
                            Button { appState.gitStashDrop(index: idx) } label: {
                                Image(systemName: "trash").font(.system(size: 9)).foregroundColor(.red)
                            }.buttonStyle(.borderless)
                        }.padding(.horizontal, 12).padding(.vertical, 4)
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
    }
    
    // MARK: - Tab 4: CI/CD
    private var cicdTab: some View {
        VStack(spacing: 0) {
            HStack {
                Text("GitHub Actions").font(.system(size: 11, weight: .medium))
                Spacer()
                if appState.cicdLoading {
                    ProgressView().scaleEffect(0.5).frame(width: 14, height: 14)
                }
                Button { appState.gitLoadCICDStatus() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }.buttonStyle(.borderless)
            }.padding(10)
            Divider()
            
            if appState.cicdRuns.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "gearshape.2").font(.system(size: 28)).foregroundColor(.secondary)
                    Text("No CI/CD runs").font(.system(size: 12)).foregroundColor(.secondary)
                    Text("Configure GitHub Actions to see runs here")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    ForEach(appState.cicdRuns) { run in
                        HStack(spacing: 8) {
                            cicdIcon(run.conclusion)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.display_title).font(.system(size: 11)).lineLimit(1)
                                Text("#\(run.run_number) · \(run.status)")
                                    .font(.system(size: 9)).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func cicdIcon(_ conclusion: String?) -> some View {
        switch conclusion {
        case "success":
            Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundColor(.green)
        case "failure":
            Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundColor(.red)
        default:
            Image(systemName: "circle").font(.system(size: 12)).foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helpers
    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(color)
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
            Spacer()
        }.padding(.horizontal, 12).padding(.vertical, 6).background(Color.primary.opacity(0.02))
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle").font(.system(size: 32)).foregroundColor(.green)
            Text("No changes").font(.system(size: 12, weight: .medium))
            Text("Working tree is clean").font(.system(size: 10)).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }
    
    private var notRepoState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 40)).foregroundColor(.secondary)
            Text("Not a Git Repository").font(.headline)
            Text("Initialize a repository to track changes").font(.caption).foregroundColor(.secondary)
            Button("Initialize Repository") { initRepo() }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
    
    // MARK: - Actions Bar
    private func actionsBar(status: GitStatus) -> some View {
        HStack(spacing: 8) {
            Button { showCommitSheet = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle"); Text("Commit")
                }.font(.system(size: 11))
            }.buttonStyle(.borderedProminent).disabled(status.files.isEmpty)
            
            Button { appState.gitPush() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                    if status.ahead > 0 { Text("\(status.ahead)") }
                }.font(.system(size: 11))
            }.buttonStyle(.bordered).disabled(status.ahead == 0)
            
            Button { appState.gitPull() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                    if status.behind > 0 { Text("\(status.behind)") }
                }.font(.system(size: 11))
            }.buttonStyle(.bordered)
            
            Spacer()
            
            Menu {
                Button("Fetch All") { appState.gitFetch() }
                Divider()
                Button("Stage All") { appState.gitStageAll() }
                Divider()
                Button("Discard All", role: .destructive) { discardAll() }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 14))
            }.menuStyle(.borderlessButton).frame(width: 24)
        }.padding(12)
    }
    
    // MARK: - Commit Sheet
    private var commitSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Commit Changes").font(.headline)
                Spacer()
                Button { showCommitSheet = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Commit Message").font(.subheadline)
                TextEditor(text: $commitMessage)
                    .font(.system(size: 12, design: .monospaced)).frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }
            HStack {
                Text("Quick:").font(.caption).foregroundColor(.secondary)
                ForEach(["fix:", "feat:", "docs:", "refactor:", "chore:"], id: \.self) { p in
                    Button(p) { commitMessage = p + " " }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            HStack {
                Toggle("Stage all", isOn: .constant(true)).controlSize(.small)
                Spacer()
                Button("Cancel") { showCommitSheet = false }.buttonStyle(.bordered)
                Button("Commit & Push") { doCommitAndPush() }
                    .buttonStyle(.borderedProminent)
                    .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Commit") { doCommit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 450)
    }
    
    // MARK: - Actions
    private func initRepo() {
        guard let folder = appState.workspaceFolder else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["init"]
        p.currentDirectoryURL = folder
        try? p.run(); p.waitUntilExit()
        appState.gitRefresh()
    }
    
    private func doCommit() {
        guard !commitMessage.isEmpty else { return }
        Task {
            appState.gitStageAll()
            try? await Task.sleep(nanoseconds: 300_000_000)
            await appState.commitChanges(message: commitMessage)
            await MainActor.run { commitMessage = ""; showCommitSheet = false; appState.gitRefresh() }
        }
    }
    
    private func doCommitAndPush() {
        guard !commitMessage.isEmpty else { return }
        Task {
            appState.gitStageAll()
            try? await Task.sleep(nanoseconds: 300_000_000)
            await appState.commitChanges(message: commitMessage)
            appState.gitPush()
            await MainActor.run { commitMessage = ""; showCommitSheet = false }
        }
    }
    
    private func discardAll() {
        guard let folder = appState.workspaceFolder else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["checkout", "--", "."]
        p.currentDirectoryURL = folder
        try? p.run(); p.waitUntilExit()
        appState.gitRefresh()
    }
}
