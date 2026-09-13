//
//  PreviewDockService.swift
//  MicroCode
//
//  Universal Multi-Purpose Right-Hand Preview Dock Service
//  Manages multi-tab preview sessions for Web, Simulators, Images, PDFs, Spreadsheets, and arbitrary files.
//
//  Copyright © 2026 AIPRENEUR. All rights reserved.
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

    public static func == (lhs: PreviewDockTabItem, rhs: PreviewDockTabItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.kind == rhs.kind
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
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tiff", "bmp", "icns"]
        let pdfExts: Set<String> = ["pdf"]
        let spreadsheetExts: Set<String> = ["xlsx", "xls", "csv", "tsv", "numbers"]
        let diffExts: Set<String> = ["diff", "patch"]
        let codeExts: Set<String> = [
            "json", "md", "markdown", "txt", "swift", "kt", "ts", "js", "tsx", "jsx",
            "rs", "py", "html", "css", "scss", "sass", "less", "yaml", "yml", "xml",
            "sh", "bash", "zsh", "c", "cpp", "cc", "cxx", "h", "hpp", "go", "java",
            "dart", "sql", "toml", "lock", "env", "plist", "properties", "gradle",
            "cmake", "make", "dockerfile", "proto", "graphql", "ar", "zig", "v", "lua", "r", "sas"
        ]
        
        if imageExts.contains(ext) { return .image }
        if pdfExts.contains(ext) { return .pdf }
        if spreadsheetExts.contains(ext) { return .spreadsheet }
        if diffExts.contains(ext) { return .diff }
        if codeExts.contains(ext) { return .codeOrText }
        return .quickLook
    }
}

@MainActor
public final class PreviewDockService: ObservableObject {
    public static let shared = PreviewDockService()
    
    @Published public var openTabs: [PreviewDockTabItem] = []
    @Published public var activeTabId: String = "web"
    @Published public var isDockVisible: Bool = false
    
    // Quick comment dispatched from Image region selection into Agent Chat
    @Published public var pendingRegionComment: String? = nil
    
    private init() {
        // Default standard runtime tabs
        openTabs = [
            PreviewDockTabItem(id: "android", title: "Android Emu", icon: "candybarphone", kind: .android, isClosable: false, url: nil),
            PreviewDockTabItem(id: "android-physical", title: "Android USB", icon: "cable.connector", kind: .androidPhysical, isClosable: false, url: nil),
            PreviewDockTabItem(id: "ios", title: "iOS Sim", icon: "iphone", kind: .ios, isClosable: false, url: nil),
            PreviewDockTabItem(id: "ios-physical", title: "iPhone USB", icon: "cable.connector", kind: .iOSPhysical, isClosable: false, url: nil),
            PreviewDockTabItem(id: "web", title: "Web", icon: "globe", kind: .web, isClosable: false, url: nil)
        ]
        activeTabId = "android"
    }
    
    public var activeTab: PreviewDockTabItem? {
        openTabs.first(where: { $0.id == activeTabId }) ?? openTabs.first
    }
    
    public func selectTab(id: String) {
        if openTabs.contains(where: { $0.id == id }) {
            activeTabId = id
            isDockVisible = true
            DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
            syncWithDeviceRuntime()
        }
    }
    
    public func openFile(url: URL, makeActive: Bool = true) {
        let normalizedURL = url.standardizedFileURL
        let tabId = "file:\(normalizedURL.path)"
        
        if let existing = openTabs.first(where: { $0.id == tabId }) {
            if makeActive {
                activeTabId = existing.id
                isDockVisible = true
                DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
            }
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
            url: normalizedURL
        )
        
        openTabs.append(newTab)
        if makeActive {
            activeTabId = newTab.id
            isDockVisible = true
            DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
        }
    }

    public func openDiff(id: String? = nil, title: String, oldContent: String, newContent: String, makeActive: Bool = true) {
        let tabId = id ?? "diff:\(title)"
        if let existing = openTabs.first(where: { $0.id == tabId }) {
            if makeActive {
                activeTabId = existing.id
                isDockVisible = true
                DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
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
    
    public func closeTab(id: String) {
        guard let index = openTabs.firstIndex(where: { $0.id == id }) else { return }
        guard openTabs[index].isClosable else { return }
        
        let wasActive = (activeTabId == id)
        openTabs.remove(at: index)
        
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
        panel.title = "Preview File in Right Dock"
        panel.prompt = "Preview"
        panel.message = "Choose an image, PDF, Excel sheet, or document to preview"
        
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
            DeviceRuntimeService.shared.showingEmbeddedAppleDock = false
        case .ios:
            DeviceRuntimeService.shared.embeddedDockMode = .ios
            DeviceRuntimeService.shared.showingEmbeddedAppleDock = true
        case .iOSPhysical:
            DeviceRuntimeService.shared.embeddedDockMode = .ios
            DeviceRuntimeService.shared.showingEmbeddedAppleDock = false
        case .android, .androidPhysical:
            DeviceRuntimeService.shared.embeddedDockMode = .android
            DeviceRuntimeService.shared.showingEmbeddedAppleDock = false
        case .file, .diff:
            break
        }
    }
}
