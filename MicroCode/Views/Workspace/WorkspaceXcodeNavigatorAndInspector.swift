//
//  WorkspaceXcodeNavigatorAndInspector.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2024 Dotmini Company Limited. All rights reserved.
//

import SwiftUI
import AppKit

// MARK: - Xcode-Style Native Editor Navigator Sidebar

enum XcodeNavigatorTab: Int, CaseIterable {
    case project = 0
    case sourceControl = 1
    case search = 2
    case issues = 3

    var icon: String {
        switch self {
        case .project: return "folder"
        case .sourceControl: return "arrow.triangle.branch"
        case .search: return "magnifyingglass"
        case .issues: return "exclamationmark.triangle"
        }
    }

    var title: String {
        switch self {
        case .project: return "Project Navigator"
        case .sourceControl: return "Source Control"
        case .search: return "Search in Workspace"
        case .issues: return "Issue Navigator"
        }
    }
}

struct WorkspaceSearchMatch: Identifiable, Hashable {
    let id: String
    let filePath: String
    let relativePath: String
    let lineNumber: Int
    let columnNumber: Int
    let linePreview: String
}

struct XcodeEditorSidebar: View {
    @EnvironmentObject var appState: AppState
    @Binding var surface: AgenticWorkspaceSurface
    @State private var selectedTab: XcodeNavigatorTab = .project
    @State private var filterText: String = ""
    @State private var showRecentOnly: Bool = false
    @State private var recentProjects: [URL] = []
    @State private var recentFiles: [URL] = []

    // Workspace Ripgrep Search & Replace State
    @State private var workspaceSearchQuery: String = ""
    @State private var workspaceReplaceQuery: String = ""
    @State private var showWorkspaceReplace: Bool = false
    @State private var searchCaseSensitive: Bool = false
    @State private var searchUseRegex: Bool = false
    @State private var isSearchingWorkspace: Bool = false
    @State private var workspaceSearchMatches: [WorkspaceSearchMatch] = []
    @State private var workspaceSearchTask: Task<Void, Never>?
    @State private var workspaceReplaceMessage: String?
    @ObservedObject private var trafficLights = WindowTrafficLightsController.shared

    private var displayedFileTree: Binding<[FileNode]> {
        if filterText.isEmpty && !showRecentOnly {
            return $appState.fileTree
        }
        let filtered = filterFileNodes(appState.fileTree, query: filterText, recentOnly: showRecentOnly)
        return Binding(
            get: { filtered },
            set: { _ in }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            navigatorTabBar

            projectHeaderBar

            Group {
                switch selectedTab {
                case .project:
                    projectNavigatorContent
                case .sourceControl:
                    GitPanelView()
                case .search:
                    searchNavigatorContent
                case .issues:
                    issuesNavigatorContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomFilterBar
        }
        .background(Color.clear)
        .onAppear {
            refreshRecents()
            if appState.fileTree.isEmpty && appState.workspaceFolder != nil {
                Task { @MainActor in await appState.refreshFileTree() }
            }
        }
        .onChange(of: appState.workspaceFolder) { _ in
            refreshRecents()
            workspaceSearchMatches = []
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MicroCodeOpenWorkspaceSearch"))) { notif in
            withAnimation(.easeInOut(duration: 0.12)) {
                selectedTab = .search
                if let showReplace = notif.userInfo?["replace"] as? Bool {
                    showWorkspaceReplace = showReplace
                }
            }
        }
    }

    // MARK: - Navigator Tab Bar (Xcode Icon Strip)

    private var navigatorTabBar: some View {
        HStack(spacing: 2) {
            Spacer().frame(width: trafficLights.interactiveLeadingInset(windowed: 70, fullScreen: 4))
            ForEach(XcodeNavigatorTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        selectedTab = tab
                    }
                } label: {
                    Image(systemName: selectedTab == tab ? "\(tab.icon).fill" : tab.icon)
                        .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                        .frame(width: 24, height: 22)
                        .background(selectedTab == tab ? Color.primary.opacity(0.10) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
            Spacer()
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .frame(height: 36)
    }

    // MARK: - Project Header Bar

    private var projectHeaderBar: some View {
        HStack(spacing: 6) {
            Image(systemName: appState.workspaceFolder != nil ? "folder.fill" : "folder")
                .foregroundColor(appState.workspaceFolder != nil ? .accentColor : .secondary)
                .font(.system(size: 11))

            Text(appState.workspaceFolder?.lastPathComponent ?? "No Project")
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(.primary)

            Spacer()

            Menu {
                Button {
                    appState.openFolder()
                } label: {
                    Label("Open Project or Folder…", systemImage: "folder.badge.plus")
                }

                Button {
                    appState.openFile()
                } label: {
                    Label("Open File…", systemImage: "doc.badge.plus")
                }

                if !recentProjects.isEmpty {
                    Divider()
                    Menu("Recent Projects") {
                        ForEach(recentProjects.prefix(8), id: \.self) { url in
                            Button(url.lastPathComponent) {
                                Task { @MainActor in await appState.openWorkspace(url: url) }
                            }
                        }
                    }
                }

                if !recentFiles.isEmpty {
                    Menu("Recent Files") {
                        ForEach(recentFiles.prefix(10), id: \.self) { url in
                            Button(url.lastPathComponent) {
                                Task { @MainActor in await appState.loadFile(url: url) }
                            }
                        }
                    }
                }

                Divider()

                Button {
                    appState.newFile()
                } label: {
                    Label("New File", systemImage: "doc.badge.plus")
                }

                Button {
                    Task { @MainActor in await appState.refreshFileTree() }
                } label: {
                    Label("Refresh File Tree", systemImage: "arrow.clockwise")
                }

                if appState.workspaceFolder != nil {
                    Divider()
                    Button("Close Project", role: .destructive) {
                        appState.closeWorkspace()
                    }
                }

                Divider()
                Button {
                    surface = .agent
                } label: {
                    Label("Switch to AI Agent Mode", systemImage: "brain")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Project Options")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }

    // MARK: - Project Navigator Content

    @ViewBuilder
    private var projectNavigatorContent: some View {
        if appState.workspaceFolder != nil {
            VStack(spacing: 0) {
                AuthenticFileTree(
                    fileTree: displayedFileTree,
                    revision: appState.fileTreeRevision,
                    backgroundColor: (appState.appTheme.isGlass || appState.appTheme.usesDarkGlassSidebar) ? .clear : appState.appTheme.panelBackground,
                    onAction: { action in
                        handleAction(action)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let warning = appState.fileTreeLimitWarning {
                    Text(warning)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.035))
                }
            }
        } else {
            emptyProjectStateView
        }
    }

    // MARK: - Empty Project Navigator (Xcode Style)

    private var emptyProjectStateView: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 34))
                        .foregroundColor(.accentColor.opacity(0.85))
                        .padding(.top, 24)

                    Text("Xcode Project Navigator")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Open a folder or file to explore and edit your code.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    HStack(spacing: 10) {
                        Button(action: { appState.openFolder() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "folder.badge.plus")
                                Text("Open Folder…")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: { appState.openFile() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "doc")
                                Text("Open File…")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.primary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }

                if !recentProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("RECENT PROJECTS")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)

                        VStack(spacing: 2) {
                            ForEach(recentProjects.prefix(6), id: \.self) { url in
                                Button {
                                    Task { @MainActor in await appState.openWorkspace(url: url) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "folder.fill")
                                            .foregroundColor(.accentColor)
                                            .font(.system(size: 12))
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(url.lastPathComponent)
                                                .font(.system(size: 11.5, weight: .medium))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            Text(url.path)
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.03))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                }

                if !recentFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("RECENT FILES")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)

                        VStack(spacing: 2) {
                            ForEach(recentFiles.prefix(6), id: \.self) { url in
                                Button {
                                    Task { @MainActor in await appState.loadFile(url: url) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "doc.text.fill")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 12))
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(url.lastPathComponent)
                                                .font(.system(size: 11.5, weight: .medium))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            Text(url.path)
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.03))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Search Navigator Content (Ripgrep + Multi-File Replace)

    private var searchNavigatorContent: some View {
        VStack(spacing: 6) {
            VStack(spacing: 5) {
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            showWorkspaceReplace.toggle()
                        }
                    } label: {
                        Image(systemName: showWorkspaceReplace ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 14, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Replace in Workspace (⇧⌘H)")

                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10.5))
                        TextField("Find in Workspace (⇧⌘F)…", text: $workspaceSearchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5))
                            .onSubmit {
                                triggerWorkspaceRipgrepSearch()
                            }
                            .onChange(of: workspaceSearchQuery) { _ in
                                scheduleWorkspaceRipgrepSearch()
                            }

                        if !workspaceSearchQuery.isEmpty {
                            Button(action: {
                                workspaceSearchQuery = ""
                                workspaceSearchMatches = []
                                workspaceReplaceMessage = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            searchCaseSensitive.toggle()
                            triggerWorkspaceRipgrepSearch()
                        } label: {
                            Text("Aa")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(searchCaseSensitive ? Color.accentColor.opacity(0.22) : Color.clear)
                                .foregroundColor(searchCaseSensitive ? .accentColor : .secondary)
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                        .help("Match Case")

                        Button {
                            searchUseRegex.toggle()
                            triggerWorkspaceRipgrepSearch()
                        } label: {
                            Text(".*")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(searchUseRegex ? Color.accentColor.opacity(0.22) : Color.clear)
                                .foregroundColor(searchUseRegex ? .accentColor : .secondary)
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                        .help("Use Regular Expression")
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                }

                if showWorkspaceReplace {
                    HStack(spacing: 4) {
                        Spacer().frame(width: 14)
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.left.arrow.right")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                            TextField("Replace with…", text: $workspaceReplaceQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11.5))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)

                        Button {
                            performWorkspaceReplaceAll()
                        } label: {
                            Text("All")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(workspaceSearchMatches.isEmpty ? Color.secondary.opacity(0.1) : Color.accentColor.opacity(0.18))
                                .foregroundColor(workspaceSearchMatches.isEmpty ? .secondary : .accentColor)
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .disabled(workspaceSearchMatches.isEmpty || workspaceSearchQuery.isEmpty)
                        .help("Replace All Across Workspace")
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            if let msg = workspaceReplaceMessage {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 10))
                    Text(msg)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
            }

            if appState.workspaceFolder == nil {
                VStack(spacing: 6) {
                    Text("No Workspace Open")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    if isSearchingWorkspace {
                        ProgressView().scaleEffect(0.5)
                        Text("Searching workspace…")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else if !workspaceSearchQuery.isEmpty {
                        let fileCount = Set(workspaceSearchMatches.map(\.filePath)).count
                        Text("\(workspaceSearchMatches.count) results in \(fileCount) files")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        // File name matches
                        if !workspaceSearchQuery.isEmpty {
                            let fileMatches = matchingFileNodes(in: appState.fileTree, query: workspaceSearchQuery).prefix(12)
                            if !fileMatches.isEmpty {
                                Text("FILES")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.top, 2)
                                ForEach(Array(fileMatches), id: \.id) { node in
                                    Button {
                                        Task { @MainActor in
                                            await appState.loadFile(url: URL(fileURLWithPath: node.path))
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: node.isDirectory ? "folder.fill" : "doc.text.fill")
                                                .foregroundColor(node.isDirectory ? .accentColor : .secondary)
                                                .font(.system(size: 10.5))
                                            Text(node.name)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.primary.opacity(0.03))
                                        .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Ripgrep Content Matches
                        if !workspaceSearchMatches.isEmpty {
                            Text("TEXT MATCHES")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.top, 6)

                            ForEach(workspaceSearchMatches) { match in
                                Button {
                                    let url = URL(fileURLWithPath: match.filePath)
                                    Task { @MainActor in
                                        await appState.loadFile(url: url)
                                        try? await Task.sleep(nanoseconds: 40_000_000)
                                        NotificationCenter.default.post(
                                            name: Notification.Name("JumpToLineNotification"),
                                            object: nil,
                                            userInfo: ["line": match.lineNumber]
                                        )
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.text")
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.accentColor)
                                            Text(match.relativePath)
                                                .font(.system(size: 10.5, weight: .semibold))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            Text(":\(match.lineNumber)")
                                                .font(.system(size: 9.5, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                        Text(match.linePreview)
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.035))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    private func scheduleWorkspaceRipgrepSearch() {
        workspaceSearchTask?.cancel()
        workspaceReplaceMessage = nil
        let query = workspaceSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            workspaceSearchMatches = []
            isSearchingWorkspace = false
            return
        }
        workspaceSearchTask = Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { triggerWorkspaceRipgrepSearch() }
        }
    }

    private func triggerWorkspaceRipgrepSearch() {
        guard let rootURL = appState.workspaceFolder else { return }
        let query = workspaceSearchQuery
        guard !query.isEmpty else {
            workspaceSearchMatches = []
            isSearchingWorkspace = false
            return
        }
        let caseSensitive = searchCaseSensitive
        let useRegex = searchUseRegex
        let rootPath = rootURL.path
        isSearchingWorkspace = true

        Task.detached(priority: .userInitiated) {
            let rgCandidates = [
                "/opt/homebrew/bin/rg",
                "/usr/local/bin/rg",
                "/usr/bin/rg"
            ]
            let rgBin = rgCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })

            let proc = Process()
            let pipe = Pipe()
            proc.currentDirectoryURL = rootURL
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice

            if let rg = rgBin {
                proc.executableURL = URL(fileURLWithPath: rg)
                var args = [
                    "--vimgrep",
                    "--max-count", "40",
                    "--max-filesize", "2M",
                    "--glob", "!.git",
                    "--glob", "!node_modules",
                    "--glob", "!target",
                    "--glob", "!.build",
                    "--glob", "!DerivedData"
                ]
                if !caseSensitive { args.append("-i") }
                if !useRegex { args.append("-F") }
                args.append("--")
                args.append(query)
                args.append(".")
                proc.arguments = args
            } else {
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
                var args = [
                    "-rnI",
                    "--exclude-dir=.git",
                    "--exclude-dir=node_modules",
                    "--exclude-dir=target",
                    "--exclude-dir=.build",
                    "--exclude-dir=DerivedData"
                ]
                if !caseSensitive { args.append("-i") }
                if !useRegex { args.append("-F") } else { args.append("-E") }
                args.append("--")
                args.append(query)
                args.append(".")
                proc.arguments = args
            }

            var matches: [WorkspaceSearchMatch] = []
            do {
                try proc.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                if let output = String(data: data, encoding: .utf8) {
                    var count = 0
                    output.enumerateLines { line, stop in
                        guard count < 400 else { stop = true; return }
                        // Format: ./path/to/file:line:col:preview or ./path/to/file:line:preview
                        let parts = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
                        guard parts.count >= 3,
                              let lineNum = Int(parts[1]) else { return }
                        var rawRel = String(parts[0])
                        if rawRel.hasPrefix("./") {
                            rawRel.removeFirst(2)
                        }
                        let colNum: Int
                        let preview: String
                        if parts.count == 4, let c = Int(parts[2]) {
                            colNum = c
                            preview = String(parts[3]).trimmingCharacters(in: .whitespaces)
                        } else {
                            colNum = 1
                            preview = parts.dropFirst(2).joined(separator: ":").trimmingCharacters(in: .whitespaces)
                        }
                        let fullPath = (rootPath as NSString).appendingPathComponent(rawRel)
                        matches.append(
                            WorkspaceSearchMatch(
                                id: "\(fullPath):\(lineNum):\(colNum):\(count)",
                                filePath: fullPath,
                                relativePath: rawRel,
                                lineNumber: lineNum,
                                columnNumber: colNum,
                                linePreview: preview
                            )
                        )
                        count += 1
                    }
                }
            } catch {}

            let finalMatches = matches
            await MainActor.run {
                self.workspaceSearchMatches = finalMatches
                self.isSearchingWorkspace = false
            }
        }
    }

    private func performWorkspaceReplaceAll() {
        let query = workspaceSearchQuery
        let replacement = workspaceReplaceQuery
        guard !query.isEmpty, !workspaceSearchMatches.isEmpty else { return }

        let targetFiles = Array(Set(workspaceSearchMatches.map(\.filePath)))
        let caseSensitive = searchCaseSensitive
        let useRegex = searchUseRegex

        var modifiedFilesCount = 0
        for path in targetFiles {
            let url = URL(fileURLWithPath: path)
            guard let original = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var options: String.CompareOptions = []
            if !caseSensitive { options.insert(.caseInsensitive) }
            if useRegex { options.insert(.regularExpression) }

            let updated = original.replacingOccurrences(of: query, with: replacement, options: options)
            if updated != original {
                do {
                    try updated.write(to: url, atomically: true, encoding: .utf8)
                    modifiedFilesCount += 1
                    if let openFile = appState.openFiles.first(where: { $0.path == path }) {
                        appState.updateFileContent(updated, for: openFile.id)
                    }
                } catch {}
            }
        }

        workspaceReplaceMessage = "Replaced in \(modifiedFilesCount) file(s)"
        triggerWorkspaceRipgrepSearch()
    }

    // MARK: - Issues Navigator Content

    private var issuesNavigatorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("ISSUES & DIAGNOSTICS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                if let warning = appState.fileTreeLimitWarning {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 11))
                        Text(warning)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.08))
                    .cornerRadius(6)
                    .padding(.horizontal, 8)
                }

                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green.opacity(0.8))
                    Text("No build or analysis errors detected")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
        }
    }

    // MARK: - Recent Navigator Content

    private var recentNavigatorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !recentProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("RECENT PROJECTS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(recentProjects.count)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                        ForEach(recentProjects, id: \.self) { url in
                            Button {
                                Task { @MainActor in await appState.openWorkspace(url: url) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.accentColor)
                                        .font(.system(size: 12))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(url.path)
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.03))
                                .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                    }
                }

                if !recentFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "doc")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("RECENT FILES")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(recentFiles.count)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)

                        ForEach(recentFiles, id: \.self) { url in
                            Button {
                                Task { @MainActor in await appState.loadFile(url: url) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 12))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(url.path)
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.03))
                                .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                    }
                }

                if recentProjects.isEmpty && recentFiles.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No Recent Items")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Bottom Filter Bar (Xcode Style)

    private var bottomFilterBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    appState.newFile()
                } label: {
                    Label("New File…", systemImage: "doc.badge.plus")
                }

                Button {
                    if let ws = appState.workspaceFolder {
                        Task { @MainActor in
                            await appState.createFolder(at: ws.path, name: "New Folder")
                        }
                    } else {
                        appState.openFolder()
                    }
                } label: {
                    Label("New Folder…", systemImage: "folder.badge.plus")
                }

                Divider()

                Button {
                    appState.openFile()
                } label: {
                    Label("Open File…", systemImage: "doc")
                }

                Button {
                    appState.openFolder()
                } label: {
                    Label("Open Folder…", systemImage: "folder")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Add file or folder")

            // Filter
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))
                TextField("Filter", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !filterText.isEmpty {
                    Button(action: { filterText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(4)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showRecentOnly.toggle()
                }
            }) {
                Image(systemName: showRecentOnly ? "clock.fill" : "clock")
                    .font(.system(size: 11))
                    .foregroundColor(showRecentOnly ? .accentColor : .secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Show only recently opened files")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Actions & Helpers

    private func refreshRecents() {
        recentProjects = AppState.getRecentWorkspaces()
        recentFiles = AppState.getRecentFiles()
    }

    private func handleAction(_ action: FileTreeAction) {
        switch action {
        case .openFile(let node):
            Task { @MainActor in
                await appState.loadFile(url: URL(fileURLWithPath: node.path))
            }
        case .loadChildren(let node):
            Task { @MainActor in await appState.loadChildren(for: node.id) }
        case .createFolder(let node, let name):
            Task { @MainActor in await appState.createFolder(at: node.path, name: name) }
        case .rename(let node, let newName):
            Task { @MainActor in await appState.renameFile(at: node.path, to: newName) }
        case .delete(let node):
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: node.path), resultingItemURL: nil)
            Task { @MainActor in await appState.refreshFileTree() }
        }
    }

    private func matchingFileNodes(in nodes: [FileNode], query: String) -> [FileNode] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var matches: [FileNode] = []
        func traverse(_ list: [FileNode]) {
            for item in list {
                if item.name.localizedCaseInsensitiveContains(query) {
                    matches.append(item)
                }
                traverse(item.children)
            }
        }
        traverse(nodes)
        return Array(matches.prefix(50))
    }

    private func filterFileNodes(_ nodes: [FileNode], query: String, recentOnly: Bool) -> [FileNode] {
        var result: [FileNode] = []
        let cleanQuery = query.trimmingCharacters(in: .whitespaces)
        let recentPaths = Set(recentFiles.map { $0.path } + appState.openFiles.map { $0.path })

        for node in nodes {
            if node.isDirectory {
                let filteredChildren = filterFileNodes(node.children, query: query, recentOnly: recentOnly)
                if !filteredChildren.isEmpty {
                    var copy = node
                    copy.children = filteredChildren
                    result.append(copy)
                }
            } else {
                let matchesQuery = cleanQuery.isEmpty || node.name.localizedCaseInsensitiveContains(cleanQuery)
                let matchesRecent = !recentOnly || recentPaths.contains(node.path)
                if matchesQuery && matchesRecent {
                    result.append(node)
                }
            }
        }
        return result
    }
}

struct AgenticContextInspector: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var agent = AgentService.shared
    @ObservedObject private var deviceRuntime = DeviceRuntimeService.shared
    @Binding var surface: AgenticWorkspaceSurface
    private var selectedTab: AgenticInspectorTab {
        get { appState.selectedInspectorTab }
        nonmutating set { appState.selectedInspectorTab = newValue }
    }
    @State private var taskMarkdownContent: String = ""
    @State private var walkthroughMarkdownContent: String = ""
    @State private var taskSubTab: Int = 0 // 0 = Task, 1 = Walkthrough
    @ObservedObject private var previewDock = PreviewDockService.shared
    @AppStorage("agenticInspectorWidth") private var inspectorWidth: Double = 380

    private var maxAllowedInspectorWidth: CGFloat {
        let winW = NSApp.keyWindow?.frame.width ?? 1200
        let sidebarW: CGFloat = appState.sidebarVisible ? 240 : 0
        let minCenterColumnW: CGFloat = 380
        let dynamicMax = max(260, winW - sidebarW - minCenterColumnW)
        let cap: CGFloat = appState.sidebarVisible ? (selectedTab == .preview ? 760 : 640) : 880
        return min(cap, dynamicMax)
    }

    private var effectiveInspectorWidth: CGFloat {
        let base = max(220, min(maxAllowedInspectorWidth, CGFloat(inspectorWidth)))
        if previewDock.isExpandedWidth && selectedTab == .preview {
            return min(maxAllowedInspectorWidth, max(base + 160, 620))
        }
        return base
    }

    var body: some View {
        HStack(spacing: 0) {
            // Native AppKit Draggable Resize Splitter on leading edge
            NativePaneResizeSplitter(
                edge: .trailingPane,
                width: $inspectorWidth,
                currentEffectiveWidth: Double(effectiveInspectorWidth),
                minWidth: 220,
                maxWidth: Double(maxAllowedInspectorWidth),
                visualWidth: 6,
                showsGripPill: true,
                collapseThreshold: 120,
                onDragStarted: {
                    if previewDock.isExpandedWidth {
                        inspectorWidth = Double(effectiveInspectorWidth)
                        previewDock.isExpandedWidth = false
                    }
                },
                onCollapse: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        appState.hidePreviewInspector()
                    }
                },
                onDoubleClick: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if selectedTab == .preview {
                            previewDock.isExpandedWidth.toggle()
                        } else {
                            inspectorWidth = 380
                        }
                    }
                }
            )
            .frame(width: 6)
            .zIndex(30)

            VStack(spacing: 0) {
                // Header Bar with Tab Switcher
                HStack(spacing: 6) {
                    ForEach(AgenticInspectorTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selectedTab = tab
                                if tab == .preview && !deviceRuntime.showingEmbeddedDeviceDock {
                                    deviceRuntime.showingEmbeddedDeviceDock = true
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                switch tab {
                                case .context:
                                    Image(systemName: "sidebar.right")
                                        .font(.system(size: 9))
                                case .preview:
                                    Image(systemName: deviceRuntime.embeddedDockMode == .web ? "globe" : (deviceRuntime.showingEmbeddedAppleDock ? "iphone" : "candybarphone"))
                                        .font(.system(size: 9))
                                case .plan:
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.system(size: 9))
                                case .tasks:
                                    Image(systemName: "checklist")
                                        .font(.system(size: 9))
                                }
                                Text(tab.rawValue)
                                    .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)
                            .background(selectedTab == tab ? Color.primary.opacity(0.1) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if selectedTab == .preview {
                        Menu {
                            Section("Preview Target") {
                                Button("WebApp Preview") {
                                    PreviewDockService.shared.selectTab(id: "web")
                                    deviceRuntime.embeddedDockMode = .web
                                    deviceRuntime.showingEmbeddedDeviceDock = true
                                }
                                Button("iOS Simulator") {
                                    PreviewDockService.shared.selectTab(id: "ios")
                                    deviceRuntime.embeddedDockMode = .ios
                                    deviceRuntime.showingEmbeddedDeviceDock = true
                                    deviceRuntime.showingEmbeddedAppleDock = true
                                }
                                Button("Android Emulator") {
                                    PreviewDockService.shared.selectTab(id: "android")
                                    deviceRuntime.embeddedDockMode = .android
                                    deviceRuntime.showingEmbeddedDeviceDock = true
                                    deviceRuntime.showingEmbeddedAppleDock = false
                                }
                            }

                            Divider()

                            Button("Choose Device & Run…") {
                                deviceRuntime.showingDeviceRuntimeSheet = true
                            }
                            let appleDevices = deviceRuntime.devices.filter(\.isAppleSimulator)
                            let androidDevices = deviceRuntime.devices.filter { $0.platform == .android }
                            if !appleDevices.isEmpty {
                                Section("iOS Simulators") {
                                    ForEach(appleDevices.prefix(6)) { device in
                                        Button(device.name) {
                                            Task {
                                                deviceRuntime.selectedDeviceID = device.id
                                                deviceRuntime.stopEmbeddedAndroid()
                                                deviceRuntime.showingEmbeddedDeviceDock = true
                                                deviceRuntime.showingEmbeddedAppleDock = true
                                                await deviceRuntime.startEmbeddedAppleSimulator()
                                            }
                                        }
                                    }
                                }
                            }
                            if !androidDevices.isEmpty {
                                Section("Android Emulators") {
                                    ForEach(androidDevices.prefix(6)) { device in
                                        Button(device.name) {
                                            Task {
                                                deviceRuntime.selectedDeviceID = device.id
                                                deviceRuntime.showingEmbeddedDeviceDock = true
                                                deviceRuntime.showingEmbeddedAppleDock = false
                                                await deviceRuntime.startEmbeddedAndroid()
                                            }
                                        }
                                    }
                                }
                            }
                            Divider()
                            Button("Refresh Devices") {
                                Task { await deviceRuntime.refresh(workspace: appState.workspaceFolder) }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 18)
                    } else {
                        Text(agent.isLoading ? "Working" : "Ready")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }

                    // Standard macOS HIG Close button [✕] at top-right
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            appState.hidePreviewInspector()
                            PreviewDockService.shared.hideDock()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Close Inspector (⌘I)")
                    .layoutPriority(10)
                }
                .padding(.horizontal, 10)
                .frame(height: 36)

                Divider()

                // Tab Content
                switch selectedTab {
                case .context:
                    contextTabView
                case .preview:
                    previewTabView
                case .plan:
                    implementationPlanTabView
                case .tasks:
                    tasksAndWalkthroughTabView
                }
            }
            .frame(width: effectiveInspectorWidth)
            .clipped()
            .background(
                appState.appTheme.isGlass ? Color.clear : Color(nsColor: selectedTab == .preview ? appState.appTheme.editorBackground : appState.appTheme.panelBackground)
            )
        }
        .onAppear {
            reloadTaskAndWalkthrough()
        }
        .onChange(of: deviceRuntime.showingEmbeddedDeviceDock) { showing in
            if !showing && appState.selectedInspectorTab == .preview {
                withAnimation(.easeInOut(duration: 0.16)) {
                    appState.selectedInspectorTab = .context
                }
            }
        }
    }

    // MARK: - Context Tab View
    private var contextTabView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                inspectorSection("CURRENT FILE") {
                    if let file = appState.currentFile {
                        contextFileRow(path: file.path, status: file.isUnsaved ? "Modified" : file.language)
                    } else {
                        emptyLabel("No file selected")
                    }
                }

                inspectorSection("FILES CHANGED \(changedFiles.count)") {
                    if changedFiles.isEmpty {
                        emptyLabel("No changes in this task")
                    } else {
                        ForEach(changedFiles.prefix(12), id: \.self) { path in
                            contextFileRow(path: path, status: "Changed")
                        }
                    }
                }

                inspectorSection("OPEN FILES \(appState.openFiles.count)") {
                    if appState.openFiles.isEmpty {
                        emptyLabel("No open files")
                    } else {
                        ForEach(appState.openFiles.prefix(10)) { file in
                            contextFileRow(path: file.path, status: file.isUnsaved ? "Unsaved" : nil)
                        }
                    }
                }

                inspectorSection("AGENT ACTIVITY") {
                    if agent.activityLog.isEmpty {
                        emptyLabel("Activity will appear here")
                    } else {
                        ForEach(agent.activityLog.suffix(8).reversed()) { activity in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.message)
                                    .font(.system(size: 10))
                                    .lineLimit(2)
                                if let detail = activity.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Live Preview Tab View
    private var previewTabView: some View {
        VStack(spacing: 0) {
            EmbeddedDeviceDockView(showsCloseButton: false)
                .environmentObject(appState)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Implementation Plan Tab View
    @ObservedObject private var planManager = ImplementationPlanManager.shared
    
    private var implementationPlanTabView: some View {
        VStack(spacing: 0) {
            if let plan = planManager.currentPlan {
                // Scrollable content
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Plan Title & Summary
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                            
                            if !plan.summary.isEmpty {
                                Text(plan.summary)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                            
                            // Progress indicator
                            if plan.totalSteps > 0 {
                                HStack(spacing: 6) {
                                    GeometryReader { geometry in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color.primary.opacity(0.08))
                                                .frame(height: 3)
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color.primary.opacity(0.4))
                                                .frame(width: geometry.size.width * plan.progress, height: 3)
                                        }
                                    }
                                    .frame(height: 3)
                                    
                                    Text("\(plan.completedSteps)/\(plan.totalSteps)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        
                        // Open Questions
                        if !plan.openQuestions.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 4) {
                                    Image(systemName: "questionmark.circle")
                                        .font(.system(size: 10))
                                    Text("OPEN QUESTIONS")
                                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                }
                                .foregroundColor(.secondary)
                                
                                ForEach(Array(plan.openQuestions.enumerated()), id: \.offset) { idx, question in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("\(idx + 1).")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: 16, alignment: .trailing)
                                        Text(question)
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.primary.opacity(0.8))
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                        
                        // Proposed Changes (Sections)
                        if !plan.sections.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: "list.bullet.indent")
                                        .font(.system(size: 10))
                                    Text("PROPOSED CHANGES")
                                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 14)
                                
                                ForEach(plan.sections) { section in
                                    PlanSectionRow(section: section)
                                }
                            }
                        }
                        
                        // Verification Plan
                        if !plan.verificationSteps.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.shield")
                                        .font(.system(size: 10))
                                    Text("VERIFICATION PLAN")
                                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                }
                                .foregroundColor(.secondary)
                                
                                ForEach(plan.verificationSteps, id: \.self) { step in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "circle")
                                            .font(.system(size: 6))
                                            .foregroundColor(.secondary)
                                            .padding(.top, 4)
                                        Text(step)
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.primary.opacity(0.8))
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                        
                        Spacer(minLength: 60)
                    }
                }
                
                // Sticky bottom bar with Proceed/Reject
                if plan.approvalState == .pending {
                    Divider().opacity(0.3)
                    
                    HStack(spacing: 8) {
                        Button(action: { planManager.reject() }) {
                            Text("Reject")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary.opacity(0.5))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button(action: { planManager.approve() }) {
                            HStack(spacing: 5) {
                                Text("Proceed")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("⌘↵")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.primary.opacity(0.5))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.12))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                } else if plan.approvalState == .approved {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.primary.opacity(0.5))
                        Text("Plan Approved")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.04))
                }
            } else {
                // No plan state
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("No Implementation Plan")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("When the agent proposes a plan, it will appear here for review.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 220)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private struct PlanSectionRow: View {
        let section: PlanSection
        @State private var isExpanded: Bool = true
        
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: {
                    withAnimation(.snappy(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                        
                        Text(section.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(Color.primary.opacity(0.02))
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(section.steps) { step in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: step.status.statusIcon)
                                    .font(.system(size: 10))
                                    .foregroundColor(step.status.statusColor)
                                    .frame(width: 14)
                                    .padding(.top, 2)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(alignment: .top, spacing: 6) {
                                        if let action = step.action {
                                            Text("[\(action)]")
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .foregroundColor(actionColor(for: action))
                                                .padding(.top, 1)
                                        }
                                        
                                        Text(step.description)
                                            .font(.system(size: 11))
                                            .foregroundColor(.primary.opacity(0.9))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    
                                    if let fileLink = step.fileLink {
                                        Text(fileLink)
                                            .font(.system(size: 9.5, design: .monospaced))
                                            .foregroundColor(.secondary.opacity(0.8))
                                    }
                                    
                                    if let detail = step.detail {
                                        Text(detail)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .padding(.top, 1)
                                    }
                                }
                            }
                            .padding(.leading, 32)
                            .padding(.trailing, 14)
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.bottom, 4)
                }
            }
            .background(Color.primary.opacity(0.01))
            .cornerRadius(6)
            .padding(.horizontal, 10)
        }
        
        private func actionColor(for action: String) -> Color {
            switch action.uppercased() {
            case "NEW":
                return .primary.opacity(0.8)
            case "MODIFY":
                return .primary.opacity(0.6)
            case "DELETE":
                return .primary.opacity(0.4)
            default:
                return .primary.opacity(0.5)
            }
        }
    }

    // MARK: - Tasks & Walkthrough Tab View
    private var tasksAndWalkthroughTabView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    withAnimation { taskSubTab = 0 }
                } label: {
                    Text("task.md")
                        .font(.system(size: 10, weight: taskSubTab == 0 ? .semibold : .regular, design: .monospaced))
                        .foregroundColor(taskSubTab == 0 ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(taskSubTab == 0 ? Color.primary.opacity(0.08) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation { taskSubTab = 1 }
                } label: {
                    Text("walkthrough.md")
                        .font(.system(size: 10, weight: taskSubTab == 1 ? .semibold : .regular, design: .monospaced))
                        .foregroundColor(taskSubTab == 1 ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(taskSubTab == 1 ? Color.primary.opacity(0.08) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    reloadTaskAndWalkthrough()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reload Task & Walkthrough")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.03))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if taskSubTab == 0 {
                        renderTaskChecklist()
                    } else {
                        renderWalkthrough()
                    }
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private func renderTaskChecklist() -> some View {
        let lines = taskMarkdownContent.components(separatedBy: .newlines)
        let checklistItems = lines.compactMap { line -> (isCompleted: Bool, text: String)? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("* [ ] ") {
                return (false, String(trimmed.dropFirst(6)))
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") || trimmed.hasPrefix("* [x] ") || trimmed.hasPrefix("* [X] ") {
                return (true, String(trimmed.dropFirst(6)))
            }
            return nil
        }

        if checklistItems.isEmpty {
            if !taskMarkdownContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                RenderedMarkdownDocumentView(markdown: taskMarkdownContent)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No task steps found")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("No .microcode/task.md file")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
            }
        } else {
            let completedCount = checklistItems.filter { $0.isCompleted }.count
            let totalCount = checklistItems.count

            HStack {
                Text("\(completedCount)/\(totalCount) Tasks Done")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(Int((Double(completedCount) / Double(max(1, totalCount))) * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            ProgressView(value: Double(completedCount), total: Double(totalCount))
                .progressViewStyle(.linear)

            Divider().padding(.vertical, 4)

            ForEach(Array(checklistItems.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundColor(item.isCompleted ? .accentColor : .secondary.opacity(0.6))
                        .padding(.top, 1)

                    MarkdownTextView(text: item.text)
                        .opacity(item.isCompleted ? 0.65 : 1.0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 3)
            }
            
            Divider().padding(.vertical, 6)
            RenderedMarkdownDocumentView(markdown: taskMarkdownContent)
        }
    }

    @ViewBuilder
    private func renderWalkthrough() -> some View {
        if walkthroughMarkdownContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No walkthrough recorded yet")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("AI Walkthroughs and verification summaries will be displayed here as the task progresses.")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 11))
                    Text("Execution Walkthrough")
                        .font(.system(size: 11, weight: .bold))
                    Spacer()
                }

                Divider().opacity(0.5)

                RenderedMarkdownDocumentView(markdown: walkthroughMarkdownContent)
            }
        }
    }

    private func reloadTaskAndWalkthrough() {
        guard let workspace = appState.workspaceFolder?.path ?? AgentService.shared.currentWorkspace else { return }
        let taskURL = WorkspaceStoragePaths.readableWorkspaceOrStateFile(named: "task.md", workspacePath: workspace)
        let walkthroughURL = WorkspaceStoragePaths.readableWorkspaceOrStateFile(named: "walkthrough.md", workspacePath: workspace)

        taskMarkdownContent = (try? String(contentsOf: taskURL, encoding: .utf8)) ?? ""
        walkthroughMarkdownContent = (try? String(contentsOf: walkthroughURL, encoding: .utf8)) ?? ""
    }

    private var changedFiles: [String] {
        var values = agent.filesModified
        values.append(contentsOf: appState.gitStatus?.files.map(\.path) ?? [])
        return Array(NSOrderedSet(array: values)).compactMap { $0 as? String }
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(.secondary.opacity(0.75))
    }

    private func contextFileRow(path: String, status: String?) -> some View {
        Button {
            let url = resolvedURL(for: path)
            Task { @MainActor in
                await appState.loadFile(url: url)
                surface = .editor
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(relativePath(path))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if let status {
                        Text(status)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    private func resolvedURL(for path: String) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return appState.workspaceFolder?.appendingPathComponent(path) ?? URL(fileURLWithPath: path)
    }

    private func relativePath(_ path: String) -> String {
        guard let root = appState.workspaceFolder?.path, path.hasPrefix(root) else { return path }
        return String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

struct LegacyInlineAgentPanel: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var modelCatalog = AIModelCatalog.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("AI Agent")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(appState.aiModel.isEmpty ? "Ready" : AIModelCatalog.formatFullDisplayName(provider: appState.aiProvider, modelId: appState.aiModel))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()

                Menu {
                    ForEach(modelCatalog.providers) { provider in
                        Menu(provider.name) {
                            ForEach(provider.models) { model in
                                Button(model.name) {
                                    appState.aiProvider = provider.id
                                    appState.aiModel = model.id
                                    appState.saveSettings()
                                }
                            }
                        }
                    }
                } label: {
                    Text("Model")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .frame(height: 20)
                }
                .menuStyle(.borderlessButton)

                Button {
                    _ = AgentService.shared.createNewChat(projectPath: appState.workspaceFolder?.path)
                } label: {
                    Text("New").font(.system(size: 10)).foregroundColor(.secondary).frame(height: 20)
                }
                .buttonStyle(.plain)

                Button {
                    appState.aiChatVisible = false
                    appState.toggleEditorMode(.aiAgent)
                } label: {
                    Text("Expand").font(.system(size: 10)).foregroundColor(.secondary).frame(height: 20)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { appState.aiChatVisible = false }
                } label: {
                    Text("Close").font(.system(size: 10)).foregroundColor(.secondary).frame(height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            AIAgentView().environmentObject(appState)
        }
    }
}

