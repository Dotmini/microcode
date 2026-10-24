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
}
