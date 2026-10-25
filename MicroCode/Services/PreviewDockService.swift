//
//  PreviewDockService.swift
//  MicroCode
//
//  Universal Multi-Purpose Right-Hand Preview Dock Service
//  Manages multi-tab preview sessions for Web, Simulators, Images, PDFs, Spreadsheets, and arbitrary files.
//
//  Copyright © 2026 Dotmini Company Limited. All rights reserved.
//

import Foundation
import Combine
import SwiftUI
import AppKit
import WebKit

public enum PreviewDockTabKind: Equatable {
    case web
    case ios
    case iOSPhysical
    case androidPhysical
    case android
    case file(URL)
    case diff(id: String, title: String, oldContent: String, newContent: String)
}

public struct PreviewDockTabItem: Identifiable, Equatable {
    public let id: String
    public var title: String
    public var icon: String
    public var kind: PreviewDockTabKind
    public var isClosable: Bool
    public var url: URL?
    public var highlightRange: ClosedRange<Int>?

    public init(
        id: String,
        title: String,
        icon: String,
        kind: PreviewDockTabKind,
        isClosable: Bool,
        url: URL?,
        highlightRange: ClosedRange<Int>? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.kind = kind
        self.isClosable = isClosable
        self.url = url
        self.highlightRange = highlightRange
    }

    public static func == (lhs: PreviewDockTabItem, rhs: PreviewDockTabItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.kind == rhs.kind && lhs.highlightRange == rhs.highlightRange
    }
}

public enum PreviewFileType {
    case image
    case pdf
    case spreadsheet // xlsx, xls, csv, tsv, numbers
    case codeOrText
    case diff
    case quickLook
    
    public static func detect(url: URL) -> PreviewFileType {
        let ext = url.pathExtension.lowercased()
        let fileName = url.lastPathComponent.lowercased()
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tiff", "bmp", "icns", "ico"]
        let pdfExts: Set<String> = ["pdf"]
        let spreadsheetExts: Set<String> = ["xlsx", "xls", "csv", "tsv", "numbers"]
        let diffExts: Set<String> = ["diff", "patch"]
        let codeExts: Set<String> = [
            "json", "jsonc", "jsonl", "md", "markdown", "mdx", "txt", "log",
            "swift", "kt", "kts", "ts", "tsx", "js", "jsx", "mjs", "cjs",
            "svelte", "vue", "astro", "rs", "py", "pyi", "ipynb",
            "html", "htm", "css", "scss", "sass", "less", "yaml", "yml", "xml",
            "sh", "bash", "zsh", "fish", "c", "cpp", "cc", "cxx", "h", "hpp", "m", "mm",
            "go", "mod", "sum", "java", "dart", "sql", "prisma", "toml", "lock",
            "env", "plist", "properties", "gradle", "cmake", "make", "dockerfile",
            "proto", "graphql", "gql", "ar", "zig", "v", "lua", "r", "rmd", "sas",
            "rb", "php", "pl", "ex", "exs", "erl", "hrl", "clj", "scala", "cs", "fs",
            "sol", "metal", "glsl", "wgsl", "hlsl", "tex", "bib", "conf", "ini", "cfg",
            "gitignore", "dockerignore", "editorconfig", "eslintrc", "prettierrc", "babelrc"
        ]
        
        if imageExts.contains(ext) { return .image }
        if pdfExts.contains(ext) { return .pdf }
        if spreadsheetExts.contains(ext) { return .spreadsheet }
        if diffExts.contains(ext) { return .diff }
        if codeExts.contains(ext) { return .codeOrText }
        if fileName.hasPrefix(".") || ["dockerfile", "makefile", "podfile", "gemfile", "procfile", "cargo.lock", "package.resolved"].contains(fileName) {
            return .codeOrText
        }
        // Fallback: if file is small (< 2MB) and valid UTF-8 text, preview as code/text
        if let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = (attr[.size] as? NSNumber)?.intValue,
           size >= 0 && size < 2_000_000,
           let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            let sample = handle.readData(ofLength: min(size, 4096))
            if !sample.contains(0), String(data: sample, encoding: .utf8) != nil {
                return .codeOrText
            }
        }
        return .quickLook
    }
}

@MainActor
public final class PreviewDockService: ObservableObject {
    public static let shared = PreviewDockService()
    
    @Published public var openTabs: [PreviewDockTabItem] = []
    @Published public var activeTabId: String = "web"
    @Published public var isDockVisible: Bool = false
    @Published public var isExpandedWidth: Bool = false
    
    // Quick comment dispatched from Image region selection into Agent Chat
    @Published public var pendingRegionComment: String? = nil
    private init() {
        // Default standard runtime tabs - Web preview first, followed by iOS and Android
        openTabs = [
            PreviewDockTabItem(id: "web", title: "WebApp Preview", icon: "globe", kind: .web, isClosable: true, url: nil),
            PreviewDockTabItem(id: "ios", title: "iOS Sim", icon: "iphone", kind: .ios, isClosable: true, url: nil),
            PreviewDockTabItem(id: "android", title: "Android Emu", icon: "candybarphone", kind: .android, isClosable: true, url: nil)
        ]
        activeTabId = "web"
    }
    
    public var activeTab: PreviewDockTabItem? {
        openTabs.first(where: { $0.id == activeTabId }) ?? openTabs.first
    }
    
    public func activateTabWithoutSideEffects(id: String) {
        ensureStandardTabExists(id: id)
        guard openTabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
        isDockVisible = true
        DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
        AppState.shared?.agenticContextVisible = false
    }

    private func ensureStandardTabExists(id: String) {
        guard !openTabs.contains(where: { $0.id == id }) else { return }
        switch id {
        case "android":
            openTabs.append(PreviewDockTabItem(id: "android", title: "Android Emu", icon: "candybarphone", kind: .android, isClosable: true, url: nil))
        case "ios":
            openTabs.append(PreviewDockTabItem(id: "ios", title: "iOS Sim", icon: "iphone", kind: .ios, isClosable: true, url: nil))
        case "web":
            openTabs.append(PreviewDockTabItem(id: "web", title: "WebApp Preview", icon: "globe", kind: .web, isClosable: true, url: nil))
        case "ios-physical":
            openTabs.append(PreviewDockTabItem(id: "ios-physical", title: "iPhone (USB)", icon: "iphone", kind: .iOSPhysical, isClosable: true, url: nil))
        case "android-physical":
            openTabs.append(PreviewDockTabItem(id: "android-physical", title: "Android (USB)", icon: "candybarphone", kind: .androidPhysical, isClosable: true, url: nil))
        default:
            break
        }
    }

    public func selectTab(id: String) {
        ensureStandardTabExists(id: id)
        guard openTabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
        isDockVisible = true
        DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
        AppState.shared?.agenticContextVisible = false
        syncWithDeviceRuntime()
    }
    
    public func openFile(url: URL, startLine: Int? = nil, endLine: Int? = nil, makeActive: Bool = true) {
        // Parse any #L10-L20 fragment or suffix in the URL string if startLine was not explicitly passed
        var effectiveStart = startLine
        var effectiveEnd = endLine
        var cleanPath = url.path
        if let frag = url.fragment, effectiveStart == nil {
            let parsed = Self.parseLineFragment(frag)
            effectiveStart = parsed?.start
            effectiveEnd = parsed?.end
        }
        if cleanPath.contains("#L"), let hashIdx = cleanPath.range(of: "#L") {
            let frag = String(cleanPath[hashIdx.lowerBound...]).dropFirst()
            if effectiveStart == nil, let parsed = Self.parseLineFragment(String(frag)) {
                effectiveStart = parsed.start
                effectiveEnd = parsed.end
            }
            cleanPath = String(cleanPath[..<hashIdx.lowerBound])
        }

        let normalizedURL = URL(fileURLWithPath: cleanPath).standardizedFileURL
        let tabId = "file:\(normalizedURL.path)"
        let range: ClosedRange<Int>? = {
            guard let s = effectiveStart, s > 0 else { return nil }
            let e = max(s, effectiveEnd ?? s)
            return s...e
        }()
        
        if let existingIdx = openTabs.firstIndex(where: { $0.id == tabId }) {
            if let range {
                openTabs[existingIdx].highlightRange = range
            }
            if makeActive {
                activeTabId = openTabs[existingIdx].id
                isDockVisible = true
                DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
                AppState.shared?.agenticContextVisible = false
                syncWithDeviceRuntime()
            }
            TelemetryService.shared.recordFeature("Code Preview (\(normalizedURL.lastPathComponent))")
            return
        }
        
        let type = PreviewFileType.detect(url: normalizedURL)
        let icon: String
        switch type {
        case .image: icon = "photo"
        case .pdf: icon = "doc.text.fill"
        case .spreadsheet: icon = "tablecells"
        case .codeOrText: icon = "chevron.left.forwardslash.chevron.right"
        case .diff: icon = "arrow.left.and.right.square"
        case .quickLook: icon = "doc"
        }
        
        let newTab = PreviewDockTabItem(
            id: tabId,
            title: normalizedURL.lastPathComponent,
            icon: icon,
            kind: .file(normalizedURL),
            isClosable: true,
            url: normalizedURL,
            highlightRange: range
        )
        
        openTabs.append(newTab)
        if makeActive {
            activeTabId = newTab.id
            isDockVisible = true
            DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
            AppState.shared?.agenticContextVisible = false
            syncWithDeviceRuntime()
        }
        TelemetryService.shared.recordFeature("Code Preview (\(normalizedURL.lastPathComponent))")
    }

    /// Resolves a file reference string (such as `file:///path/file.swift#L10-L20`, `+page.svelte #L1-256`, or relative workspace path)
    /// and opens it in the Right-Hand Code Preview Split Pane. Returns `true` if the file was found and opened.
    @discardableResult
    public func openFileFromReference(_ rawReference: String, workspacePath: String? = nil, defaultStartLine: Int? = nil, defaultEndLine: Int? = nil) -> Bool {
        var working = rawReference.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "`'\"<>()")))
        guard !working.isEmpty else { return false }

        var startLine = defaultStartLine
        var endLine = defaultEndLine

        if working.hasPrefix("file://") {
            working = String(working.dropFirst("file://".count))
            working = working.removingPercentEncoding ?? working
        } else if working.hasPrefix("microcode-file://") {
            working = String(working.dropFirst("microcode-file://".count))
            working = working.removingPercentEncoding ?? working
        }

        // Extract #L10-L20 or #L10-20
        if let rangeMatch = working.range(of: #"\s*#L(\d+)(?:-L?(\d+))?$"#, options: .regularExpression) {
            let frag = String(working[rangeMatch]).trimmingCharacters(in: .whitespaces).dropFirst() // drop '#'
            if let parsed = Self.parseLineFragment(String(frag)) {
                startLine = parsed.start
                endLine = parsed.end
            }
            working = String(working[..<rangeMatch.lowerBound]).trimmingCharacters(in: .whitespaces)
        } else if let colonMatch = working.range(of: #":(\d+)(?::(\d+))?$"#, options: .regularExpression) {
            let nums = String(working[colonMatch]).split(separator: ":").compactMap { Int($0) }
            if let first = nums.first {
                startLine = first
                endLine = nums.count > 1 ? nums[1] : first
            }
            working = String(working[..<colonMatch.lowerBound])
        }

        // Strip trailing " (+N more)" if from multi_file_read
        if let moreRange = working.range(of: #"\s*\(\+\d+\s+more\)$"#, options: .regularExpression) {
            working = String(working[..<moreRange.lowerBound])
        }

        let wsRoot = workspacePath
            ?? AgentService.shared.currentWorkspace
            ?? AgentToolBox.shared.workspaceRoot
            ?? AppState.shared?.workspaceFolder?.path

        if let resolvedURL = Self.resolveFileURL(pathOrName: working, workspaceRoot: wsRoot) {
            openFile(url: resolvedURL, startLine: startLine, endLine: endLine, makeActive: true)
            return true
        }
        return false
    }

    public static func parseLineFragment(_ fragment: String) -> (start: Int, end: Int)? {
        let cleaned = fragment.trimmingCharacters(in: CharacterSet(charactersIn: "# \t"))
        guard cleaned.uppercased().hasPrefix("L") else { return nil }
        let parts = cleaned.dropFirst().components(separatedBy: CharacterSet(charactersIn: "-:"))
        let nums = parts.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "Ll ")) }.compactMap { Int($0) }
        guard let first = nums.first, first > 0 else { return nil }
        let second = nums.count > 1 ? max(first, nums[1]) : first
        return (first, second)
    }

    public static func resolveFileURL(pathOrName: String, workspaceRoot: String?) -> URL? {
        let fm = FileManager.default
        let expanded = (pathOrName as NSString).expandingTildeInPath
        var isDir: ObjCBool = false

        if expanded.hasPrefix("/") {
            if fm.fileExists(atPath: expanded, isDirectory: &isDir), !isDir.boolValue {
                return URL(fileURLWithPath: expanded)
            }
        }

        if let ws = workspaceRoot, !ws.isEmpty {
            let candidate = (ws as NSString).appendingPathComponent(pathOrName)
            if fm.fileExists(atPath: candidate, isDirectory: &isDir), !isDir.boolValue {
                return URL(fileURLWithPath: candidate)
            }

            // If pathOrName is a filename or partial relative path (e.g. "+page.svelte" or "AIUsageTracker.swift"),
            // search inside workspaceRoot (skipping heavy build/vendor directories).
            let targetLast = (pathOrName as NSString).lastPathComponent
            if !targetLast.isEmpty {
                let wsURL = URL(fileURLWithPath: ws)
                let skipDirs: Set<String> = [".git", "node_modules", ".build", "build", "target", "DerivedData", ".next", ".svelte-kit", "dist", "Pods", ".venv", "venv"]
                if let enumerator = fm.enumerator(
                    at: wsURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    var bestMatch: URL? = nil
                    var scanned = 0
                    while let itemURL = enumerator.nextObject() as? URL {
                        scanned += 1
                        if scanned > 6000 { break }
                        let name = itemURL.lastPathComponent
                        if skipDirs.contains(name) {
                            enumerator.skipDescendants()
                            continue
                        }
                        if name == targetLast {
                            if itemURL.path.hasSuffix(pathOrName) {
                                return itemURL
                            }
                            if bestMatch == nil {
                                bestMatch = itemURL
                            }
                        }
                    }
                    if let bestMatch {
                        return bestMatch
                    }
                }
            }
        }
        return nil
    }

    public func openDiff(id: String? = nil, title: String, oldContent: String, newContent: String, makeActive: Bool = true) {
        let tabId = id ?? "diff:\(title)"
        if let existing = openTabs.first(where: { $0.id == tabId }) {
            if makeActive {
                activeTabId = existing.id
                isDockVisible = true
                DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
                AppState.shared?.agenticContextVisible = false
            }
            return
        }
        
        let newTab = PreviewDockTabItem(
            id: tabId,
            title: title,
            icon: "arrow.left.and.right.square",
            kind: .diff(id: tabId, title: title, oldContent: oldContent, newContent: newContent),
            isClosable: true,
            url: nil
        )
        
        openTabs.append(newTab)
        if makeActive {
            activeTabId = newTab.id
            isDockVisible = true
            DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
            AppState.shared?.agenticContextVisible = false
        }
    }
    
    public func openGitDiff(for path: String, workspaceFolder: URL? = nil, makeActive: Bool = true) {
        let fileURL = URL(fileURLWithPath: path)
        let resolvedFolder = workspaceFolder ?? findGitRoot(from: fileURL) ?? fileURL.deletingLastPathComponent()
        let fileName = (path as NSString).lastPathComponent
        let relPath: String
        if path.hasPrefix(resolvedFolder.path) {
            relPath = String(path.dropFirst(resolvedFolder.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            relPath = path
        }
        
        Task.detached(priority: .userInitiated) {
            let showProcess = Process()
            let showPipe = Pipe()
            showProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            showProcess.arguments = ["show", "HEAD:\(relPath)"]
            showProcess.currentDirectoryURL = resolvedFolder
            showProcess.standardOutput = showPipe
            showProcess.standardError = Pipe()
            try? showProcess.run()
            showProcess.waitUntilExit()
            let oldData = showPipe.fileHandleForReading.readDataToEndOfFile()
            let oldContent = String(data: oldData, encoding: .utf8) ?? ""
            
            let newContent = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            
            await MainActor.run {
                PreviewDockService.shared.openDiff(
                    id: "gitdiff:\(path)",
                    title: "Diff: \(fileName)",
                    oldContent: oldContent,
                    newContent: newContent,
                    makeActive: makeActive
                )
            }
        }
    }
    
    private func findGitRoot(from url: URL) -> URL? {
        var current = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        while current.path != "/" && current.path.count > 1 {
            let gitDir = current.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitDir.path) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }
    
    public func hideDock() {
        isDockVisible = false
        DeviceRuntimeService.shared.showingEmbeddedDeviceDock = false
        DeviceRuntimeService.shared.stopEmbeddedAndroid()
        DeviceRuntimeService.shared.stopEmbeddedAppleSimulator()
        IOSDeviceCaptureService.shared.stopCapture()
        IOSDeviceCaptureService.shared.stopMonitoring()
        AndroidStreamService.shared.stopStreaming()
    }

    public func closeTab(id: String) {
        guard let index = openTabs.firstIndex(where: { $0.id == id }) else { return }
        guard openTabs[index].isClosable else { return }
        
        let wasActive = (activeTabId == id)
        openTabs.remove(at: index)
        
        if id == "android" {
            DeviceRuntimeService.shared.stopEmbeddedAndroid()
        } else if id == "ios" {
            DeviceRuntimeService.shared.stopEmbeddedAppleSimulator()
        } else if id == "ios-physical" {
            IOSDeviceCaptureService.shared.stopCapture()
            IOSDeviceCaptureService.shared.stopMonitoring()
        } else if id == "android-physical" {
            AndroidStreamService.shared.stopStreaming()
        }

        if openTabs.isEmpty {
            hideDock()
            return
        }
        
        if wasActive {
            if index < openTabs.count {
                activeTabId = openTabs[index].id
            } else if let last = openTabs.last {
                activeTabId = last.id
            }
            syncWithDeviceRuntime()
        }
    }
    
    public func pickAndOpenFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = AppState.shared?.workspaceFolder
        panel.title = "Preview File in Right Split Pane"
        panel.prompt = "Preview"
        panel.message = "Choose a code file, image, PDF, spreadsheet, or document to preview"
        
        if panel.runModal() == .OK, let url = panel.url {
            openFile(url: url, makeActive: true)
        }
    }
    
    public func sendRegionCommentToAgent(comment: String) {
        pendingRegionComment = comment
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCode.PreviewDock.RegionComment"),
            object: comment
        )
    }
    
    private func syncWithDeviceRuntime() {
        guard let active = activeTab else { return }
        switch active.kind {
        case .web:
            DeviceRuntimeService.shared.embeddedDockMode = .web
            DeviceRuntimeService.shared.stopEmbeddedAndroid()
            DeviceRuntimeService.shared.stopEmbeddedAppleSimulator()
            IOSDeviceCaptureService.shared.stopCapture()
        case .ios:
            DeviceRuntimeService.shared.embeddedDockMode = .ios
            DeviceRuntimeService.shared.showingEmbeddedAppleDock = true
            DeviceRuntimeService.shared.stopEmbeddedAndroid()
            IOSDeviceCaptureService.shared.stopCapture()
            DeviceRuntimeService.shared.selectDefaultAppleSimulatorIfNeeded()
        case .iOSPhysical:
            DeviceRuntimeService.shared.embeddedDockMode = .ios
            DeviceRuntimeService.shared.stopEmbeddedAndroid()
            DeviceRuntimeService.shared.stopEmbeddedAppleSimulator()
        case .android:
            DeviceRuntimeService.shared.embeddedDockMode = .android
            DeviceRuntimeService.shared.stopEmbeddedAppleSimulator()
            IOSDeviceCaptureService.shared.stopCapture()
        case .androidPhysical:
            DeviceRuntimeService.shared.embeddedDockMode = .android
            DeviceRuntimeService.shared.stopEmbeddedAndroid()
            DeviceRuntimeService.shared.stopEmbeddedAppleSimulator()
            IOSDeviceCaptureService.shared.stopCapture()
        case .file, .diff:
            DeviceRuntimeService.shared.stopEmbeddedAndroid()
            DeviceRuntimeService.shared.stopEmbeddedAppleSimulator()
            IOSDeviceCaptureService.shared.stopCapture()
        }
    }

    public var isVisible: Bool {
        isDockVisible || DeviceRuntimeService.shared.showingEmbeddedDeviceDock
    }

    public var selectedTab: PreviewDockTabKind? {
        activeTab?.kind
    }

    public func reloadWeb() {
        DeviceRuntimeService.shared.webRefreshTrigger.toggle()
    }
}

// MARK: - Universal Preview Hot Reload Engine (Playground-Style Instant Live Reload)

@MainActor
public final class PreviewHotReloadEngine: ObservableObject {
    public static let shared = PreviewHotReloadEngine()

    private static let autoReloadKey = "microcode.preview.autoHotReload"
    private static let liveTypingKey = "microcode.preview.liveTyping"

    /// Automatically hot-reload WebApp, App Runtime (iOS/Android/Flutter/RN), and File Previews on Save or AI Agent edit.
    @Published public var isAutoHotReloadEnabled: Bool {
        didSet { UserDefaults.standard.set(isAutoHotReloadEnabled, forKey: Self.autoReloadKey) }
    }

    /// Playground-style instant live buffer preview as the user types in the Code Editor (before pressing ⌘S).
    @Published public var isLiveTypingEnabled: Bool {
        didSet { UserDefaults.standard.set(isLiveTypingEnabled, forKey: Self.liveTypingKey) }
    }

    @Published public var isReloading: Bool = false
    @Published public var reloadCount: Int = 0
    @Published public var lastReloadDurationMs: Int = 0
    @Published public var lastModifiedFileName: String = ""
    @Published public var lastModifiedFilePath: String = ""
    @Published public var lastReloadSource: String = ""
    @Published public var lastReloadTimestamp: Date = .distantPast
    @Published public var liveBufferOverrides: [String: String] = [:]

    private var liveTypingDebounceTask: Task<Void, Never>?
    private var workspaceWatcherTimer: Timer?
    private var watchedFileModDates: [String: Date] = [:]
    private var lastScannedWorkspacePath: String = ""

    private init() {
        if UserDefaults.standard.object(forKey: Self.autoReloadKey) == nil {
            self.isAutoHotReloadEnabled = true
        } else {
            self.isAutoHotReloadEnabled = UserDefaults.standard.bool(forKey: Self.autoReloadKey)
        }
        if UserDefaults.standard.object(forKey: Self.liveTypingKey) == nil {
            self.isLiveTypingEnabled = true
        } else {
            self.isLiveTypingEnabled = UserDefaults.standard.bool(forKey: Self.liveTypingKey)
        }
        setupObservers()
        startLightweightWorkspaceWatcher()
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MicroCodeAgentTerminalCommand"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let phase = note.userInfo?["phase"] as? String, phase == "completed" else { return }
            Task { @MainActor [weak self] in
                self?.scanWorkspaceForRecentChanges(source: "Terminal")
            }
        }
    }

    /// Called when a file is saved in the Code Editor (`⌘S`) or modified on disk by an AI Agent tool.
    public func notifyFileSaved(path: String, content: String? = nil, source: String = "Editor") {
        let start = CFAbsoluteTimeGetCurrent()
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let fileName = (standardized as NSString).lastPathComponent
        let ext = (standardized as NSString).pathExtension.lowercased()

        if let content {
            liveBufferOverrides[standardized] = content
        } else {
            liveBufferOverrides.removeValue(forKey: standardized)
        }

        if let attr = try? FileManager.default.attributesOfItem(atPath: standardized),
           let modDate = attr[.modificationDate] as? Date {
            watchedFileModDates[standardized] = modDate
        }

        lastModifiedFilePath = standardized
        lastModifiedFileName = fileName
        lastReloadSource = source
        lastReloadTimestamp = Date()
        reloadCount += 1

        var userInfo: [String: Any] = [
            "path": standardized,
            "fileName": fileName,
            "ext": ext,
            "source": source
        ]
        if let content {
            userInfo["content"] = content
        }

        // 1. Broadcast standard notifications so WebApp Preview, File Previews, and Diff views update immediately
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCodeFileSaved"),
            object: standardized,
            userInfo: userInfo
        )
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCodeWorkspaceFileDidChange"),
            object: standardized,
            userInfo: userInfo
        )
        NotificationCenter.default.post(
            name: NSNotification.Name("FileUpdatedExternally"),
            object: nil,
            userInfo: userInfo
        )

        // 2. If a CSS file was modified, inject CSS directly into the active WKWebView without full page flash
        if ["css", "scss", "less"].contains(ext) {
            let cssText = content ?? (try? String(contentsOfFile: standardized, encoding: .utf8)) ?? ""
            injectLiveCSSIntoWebView(fileName: fileName, cssContent: cssText)
        }

        // 3. Trigger App Runtime Auto Hot Reload (iOS Simulator / Android Emulator / Flutter / React Native / macOS)
        if isAutoHotReloadEnabled {
            let appSourceExts: Set<String> = [
                "swift", "m", "mm", "h", "c", "cpp", "storyboard", "xib", "plist",
                "kt", "kts", "java", "xml", " darts", "dart",
                "js", "jsx", "ts", "tsx", "json"
            ]
            if appSourceExts.contains(ext) && !standardized.contains("/.microcode/") {
                DeviceRuntimeService.shared.scheduleAutoHotReload(changedFilePath: standardized, source: source)
            }
        }

        let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
        lastReloadDurationMs = elapsedMs
    }

    /// Called as the user types in the Code Editor for Playground-style zero-save live preview.
    public func notifyLiveBufferEdited(path: String, content: String, language: String) {
        guard !path.isEmpty else { return }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        liveBufferOverrides[standardized] = content

        guard isLiveTypingEnabled && isAutoHotReloadEnabled else { return }

        let ext = (standardized as NSString).pathExtension.lowercased()
        let fileName = (standardized as NSString).lastPathComponent
        let isSwift = ext == "swift" || language.lowercased() == "swift"
        let debounceNs: UInt64 = isSwift ? 650_000_000 : 160_000_000

        liveTypingDebounceTask?.cancel()
        liveTypingDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled, let self else { return }

            let start = CFAbsoluteTimeGetCurrent()
            self.lastModifiedFilePath = standardized
            self.lastModifiedFileName = fileName
            self.lastReloadSource = "Live Typing"
            self.lastReloadTimestamp = Date()
            self.reloadCount += 1

            let userInfo: [String: Any] = [
                "path": standardized,
                "fileName": fileName,
                "ext": ext,
                "content": content,
                "language": language,
                "source": "Live Typing"
            ]

            // Instant CSS hot-injection into active Web Preview
            if ext == "css" {
                self.injectLiveCSSIntoWebView(fileName: fileName, cssContent: content)
            } else if ext == "html" || ext == "htm" || ext == "svg" {
                self.injectLiveHTMLIntoWebViewIfMatching(filePath: standardized, htmlContent: content)
            }

            // Notify active File Preview & SwiftUI Live Preview tabs
            NotificationCenter.default.post(
                name: NSNotification.Name("MicroCodeLiveBufferUpdated"),
                object: standardized,
                userInfo: userInfo
            )

            // Also forward to backend HotReloadService if enabled for compiled languages
            if ["swift", "rust", "rs", "c", "cpp"].contains(ext) && HotReloadService.shared.isEnabled {
                HotReloadService.shared.requestReload(
                    sourceCode: content,
                    language: ext,
                    filePath: standardized
                )
            }

            self.lastReloadDurationMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
        }
    }

    /// Injects updated CSS directly into the active Preview WKWebView without reloading the page or losing JS state/scroll.
    public func injectLiveCSSIntoWebView(fileName: String, cssContent: String) {
        guard let webView = IDEBrowserAutomationService.shared.activePreviewWebView else { return }
        let escapedFileName = fileName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let base64CSS = Data(cssContent.utf8).base64EncodedString()

        let script = """
        (() => {
            try {
                const cssText = new TextDecoder().decode(Uint8Array.from(atob('\(base64CSS)'), c => c.charCodeAt(0)));
                const targetName = '\(escapedFileName)';
                let styleEl = document.querySelector(`style[data-mc-hot="${targetName}"]`);
                if (!styleEl) {
                    styleEl = document.createElement('style');
                    styleEl.setAttribute('data-mc-hot', targetName);
                    document.head.appendChild(styleEl);
                }
                styleEl.textContent = cssText;
                // Also bust cache on matching <link rel="stylesheet">
                document.querySelectorAll('link[rel="stylesheet"]').forEach(link => {
                    const href = link.getAttribute('href') || '';
                    if (href.includes(targetName)) {
                        const clean = href.split('?')[0];
                        link.setAttribute('href', clean + '?mc_hot=' + Date.now());
                    }
                });
                return true;
            } catch (e) {
                return false;
            }
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Updates local HTML/SVG preview live in the active WKWebView while preserving scroll position.
    public func injectLiveHTMLIntoWebViewIfMatching(filePath: String, htmlContent: String) {
        guard let webView = IDEBrowserAutomationService.shared.activePreviewWebView else { return }
        let currentURL = webView.url ?? DeviceRuntimeService.shared.targetWebURL
        guard let currentURL, currentURL.isFileURL else { return }
        let currentPath = currentURL.standardizedFileURL.path
        guard currentPath == filePath else { return }

        let base64HTML = Data(htmlContent.utf8).base64EncodedString()
        let script = """
        (() => {
            try {
                const sx = window.scrollX || 0;
                const sy = window.scrollY || 0;
                const html = new TextDecoder().decode(Uint8Array.from(atob('\(base64HTML)'), c => c.charCodeAt(0)));
                const parser = new DOMParser();
                const doc = parser.parseFromString(html, 'text/html');
                if (doc && doc.body && document.body) {
                    if (doc.head && document.head) {
                        document.head.innerHTML = doc.head.innerHTML;
                    }
                    document.body.innerHTML = doc.body.innerHTML;
                    document.body.className = doc.body.className;
                    document.body.setAttribute('style', doc.body.getAttribute('style') || '');
                    window.scrollTo(sx, sy);
                    return true;
                }
            } catch (e) {}
            return false;
        })();
        """
        webView.evaluateJavaScript(script) { result, _ in
            if (result as? Bool) != true {
                let baseDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
                webView.loadHTMLString(htmlContent, baseURL: baseDir)
            }
        }
    }

    /// Performs a scroll-preserving reload on a WKWebView.
    public func reloadWebViewPreservingScroll(_ webView: WKWebView) {
        webView.evaluateJavaScript("[window.scrollX || 0, window.scrollY || 0]") { result, _ in
            var scrollX: Double = 0
            var scrollY: Double = 0
            if let arr = result as? [Double], arr.count == 2 {
                scrollX = arr[0]
                scrollY = arr[1]
            } else if let arr = result as? [NSNumber], arr.count == 2 {
                scrollX = arr[0].doubleValue
                scrollY = arr[1].doubleValue
            }
            if webView.url?.isFileURL == true, let fileURL = webView.url {
                webView.loadFileURL(fileURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
            } else {
                webView.reloadFromOrigin()
            }
            if scrollX > 0 || scrollY > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    webView.evaluateJavaScript("window.scrollTo(\(scrollX), \(scrollY));", completionHandler: nil)
                }
            }
        }
    }

    // MARK: - Lightweight Workspace File Modification Watcher

    private func startLightweightWorkspaceWatcher() {
        workspaceWatcherTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isAutoHotReloadEnabled else { return }
                guard PreviewDockService.shared.isDockVisible || DeviceRuntimeService.shared.showingEmbeddedDeviceDock else { return }
                self.scanWorkspaceForRecentChanges(source: "Disk")
            }
        }
    }

    public func scanWorkspaceForRecentChanges(source: String = "Disk") {
        guard let wsPath = AgentService.shared.currentWorkspace ?? AppState.shared?.workspaceFolder?.path,
              !wsPath.isEmpty else { return }

        if lastScannedWorkspacePath != wsPath {
            lastScannedWorkspacePath = wsPath
            watchedFileModDates.removeAll()
            seedWorkspaceDates(rootPath: wsPath)
            return
        }

        let rootURL = URL(fileURLWithPath: wsPath)
        let CandidateDirs = ["", "src", "app", "lib", "public", "components", "pages", "views", "styles", "assets"]
        let watchedExts: Set<String> = [
            "html", "htm", "css", "scss", "js", "jsx", "ts", "tsx", "vue", "svelte",
            "swift", "kt", "java", "dart", "py", "md", "svg", "json"
        ]
        let fm = FileManager.default

        for sub in CandidateDirs {
            let dirURL = sub.isEmpty ? rootURL : rootURL.appendingPathComponent(sub)
            guard let items = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in items {
                let ext = item.pathExtension.lowercased()
                guard watchedExts.contains(ext) else { continue }
                guard let vals = try? item.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      vals.isRegularFile == true,
                      let modDate = vals.contentModificationDate else { continue }

                let itemPath = item.standardizedFileURL.path
                if let prevDate = watchedFileModDates[itemPath] {
                    if modDate.timeIntervalSince(prevDate) > 0.05 {
                        watchedFileModDates[itemPath] = modDate
                        notifyFileSaved(path: itemPath, content: nil, source: source)
                        return
                    }
                } else {
                    watchedFileModDates[itemPath] = modDate
                }
            }
        }
    }

    private func seedWorkspaceDates(rootPath: String) {
        let rootURL = URL(fileURLWithPath: rootPath)
        let candidateDirs = ["", "src", "app", "lib", "public", "components", "pages", "views", "styles", "assets"]
        let fm = FileManager.default
        for sub in candidateDirs {
            let dirURL = sub.isEmpty ? rootURL : rootURL.appendingPathComponent(sub)
            guard let items = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for item in items {
                if let vals = try? item.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                   vals.isRegularFile == true,
                   let modDate = vals.contentModificationDate {
                    watchedFileModDates[item.standardizedFileURL.path] = modDate
                }
            }
        }
    }
}

