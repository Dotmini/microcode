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
    case android
    case file(URL)
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
    case quickLook
    
    public static func detect(url: URL) -> PreviewFileType {
        let ext = url.pathExtension.lowercased()
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tiff", "bmp", "icns"]
        let pdfExts: Set<String> = ["pdf"]
        let spreadsheetExts: Set<String> = ["xlsx", "xls", "csv", "tsv", "numbers"]
        let codeExts: Set<String> = ["json", "md", "markdown", "txt", "swift", "kt", "ts", "js", "rs", "py", "html", "css", "yaml", "yml", "xml", "sh"]
        
        if imageExts.contains(ext) { return .image }
        if pdfExts.contains(ext) { return .pdf }
        if spreadsheetExts.contains(ext) { return .spreadsheet }
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
            PreviewDockTabItem(id: "web", title: "Web", icon: "globe", kind: .web, isClosable: false, url: nil),
            PreviewDockTabItem(id: "ios", title: "iOS", icon: "iphone", kind: .ios, isClosable: false, url: nil),
            PreviewDockTabItem(id: "android", title: "Android", icon: "apps.iphone", kind: .android, isClosable: false, url: nil)
        ]
        activeTabId = "web"
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
        case .codeOrText: icon = "doc.plaintext"
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
        case .android:
            DeviceRuntimeService.shared.embeddedDockMode = .android
            DeviceRuntimeService.shared.showingEmbeddedAppleDock = false
        case .file:
            break
        }
    }
}
