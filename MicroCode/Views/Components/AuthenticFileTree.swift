//
//  AuthenticFileTree.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2026 Dotmini Company Limited. All rights reserved.
//

import SwiftUI
import AppKit

// MARK: - Node Wrapper (Bridge Class for NSOutlineView)

class FileNodeWrapper: NSObject {
    var node: FileNode
    let id: String
    
    // Cache children wrappers to maintain object identity across updates
    var childrenWrappers: [FileNodeWrapper]? = nil
    
    init(_ node: FileNode) {
        self.node = node
        self.id = node.id
    }
}

// MARK: - Authentic File Tree (NSOutlineView)

struct AuthenticFileTree: NSViewRepresentable {
    @Binding var fileTree: [FileNode]
    let revision: UInt64
    var backgroundColor: NSColor = .clear
    var onAction: (FileTreeAction) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        
        let outlineView = NSOutlineView()
        scrollView.drawsBackground = backgroundColor.alphaComponent > 0
        scrollView.backgroundColor = backgroundColor
        outlineView.backgroundColor = backgroundColor
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.headerView = nil // No header
        outlineView.rowHeight = 24
        
        // Single Column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MainColumn"))
        column.width = 200
        column.minWidth = 100
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        
        // Selection Style
        // Source-list style applies an AppKit vibrancy material that stays
        // gray even when the selected app theme is opaque. Plain style keeps
        // the native behavior while respecting our explicit theme background.
        outlineView.style = .plain
        outlineView.allowsMultipleSelection = true
        
        // Click and Double-click actions
        outlineView.target = context.coordinator
        outlineView.action = #selector(Coordinator.onClick)
        outlineView.doubleAction = #selector(Coordinator.onDoubleClick)
        
        context.coordinator.outlineView = outlineView
        scrollView.documentView = outlineView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let outlineView = nsView.documentView as? NSOutlineView else { return }
        context.coordinator.parent = self
        nsView.drawsBackground = backgroundColor.alphaComponent > 0
        nsView.backgroundColor = backgroundColor
        outlineView.backgroundColor = backgroundColor
        
        if context.coordinator.needsReload(revision: revision, currentTreeCount: fileTree.count) {
            context.coordinator.syncTree(fileTree: fileTree, in: outlineView, scrollView: nsView)
        }
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: AuthenticFileTree
        var rootItems: [FileNodeWrapper] = []
        var lastRevision: UInt64?
        weak var outlineView: NSOutlineView?
        
        // Expansion and scroll stability tracking
        var targetFolderId: String?
        var expandedItemIds = Set<String>()
        var isRestoringExpansion = false
        
        init(_ parent: AuthenticFileTree) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(onIconThemeChanged), name: NSNotification.Name("MicroCodeIconThemeChanged"), object: nil)
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func onIconThemeChanged() {
            DispatchQueue.main.async { [weak self] in
                self?.outlineView?.reloadData()
            }
        }
        
        func updateRootItems(_ items: [FileNodeWrapper]) {
            self.rootItems = items
        }
        
        func needsReload(revision: UInt64, currentTreeCount: Int) -> Bool {
            if lastRevision != revision || rootItems.count != currentTreeCount {
                lastRevision = revision
                return true
            }
            return false
        }
        
        // MARK: - Lookup Helpers
        
        func findWrapper(byId id: String, in items: [FileNodeWrapper]? = nil) -> FileNodeWrapper? {
            let list = items ?? rootItems
            for item in list {
                if item.id == id { return item }
                if let children = item.childrenWrappers {
                    if let found = findWrapper(byId: id, in: children) {
                        return found
                    }
                }
            }
            return nil
        }
        
        func findNode(byId id: String, in nodes: [FileNode]) -> FileNode? {
            for node in nodes {
                if node.id == id { return node }
                if let found = findNode(byId: id, in: node.children) {
                    return found
                }
            }
            return nil
        }
        
        // Reconcile wrappers so existing objects maintain identity and memory state
        func reconcileWrappers(existing: [FileNodeWrapper], newNodes: [FileNode]) -> [FileNodeWrapper] {
            var existingMap: [String: FileNodeWrapper] = [:]
            for item in existing {
                existingMap[item.id] = item
            }
            return newNodes.map { node in
                if let existingWrapper = existingMap[node.id] {
                    existingWrapper.node = node
                    if let existingChildren = existingWrapper.childrenWrappers, !node.children.isEmpty {
                        existingWrapper.childrenWrappers = reconcileWrappers(existing: existingChildren, newNodes: node.children)
                    } else if node.hasLoadedChildren {
                        existingWrapper.childrenWrappers = node.children.map { FileNodeWrapper($0) }
                    }
                    return existingWrapper
                } else {
                    let newWrapper = FileNodeWrapper(node)
                    if node.hasLoadedChildren && !node.children.isEmpty {
                        newWrapper.childrenWrappers = node.children.map { FileNodeWrapper($0) }
                    }
                    return newWrapper
                }
            }
        }
        
        // MARK: - Tree Sync (Preserving Scroll and Preventing Jump-to-Top)
        
        func syncTree(fileTree: [FileNode], in outlineView: NSOutlineView, scrollView: NSScrollView) {
            // 1. FAST PATH: A specific target folder just loaded its children asynchronously
            if let targetId = targetFolderId,
               let targetWrapper = findWrapper(byId: targetId, in: rootItems),
               let updatedNode = findNode(byId: targetId, in: fileTree),
               updatedNode.hasLoadedChildren && !targetWrapper.node.hasLoadedChildren {
                
                targetWrapper.node = updatedNode
                targetWrapper.childrenWrappers = updatedNode.children.map { FileNodeWrapper($0) }
                
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0.05
                outlineView.reloadItem(targetWrapper, reloadChildren: true)
                outlineView.expandItem(targetWrapper)
                NSAnimationContext.endGrouping()
                
                // Immediately scroll to keep the expanded folder and its newly loaded children visible
                scrollItemIntoView(targetWrapper, in: outlineView)
                
                DispatchQueue.main.async { [weak self, weak outlineView] in
                    guard let self = self, let ov = outlineView,
                          let wrapper = self.findWrapper(byId: targetId, in: self.rootItems) else { return }
                    self.scrollItemIntoView(wrapper, in: ov)
                }
                return
            }
            
            // 2. FULL SYNC PATH: Root count changed, workspace loaded, or structural update
            let savedScrollY = scrollView.contentView.bounds.origin.y
            let visibleRect = outlineView.visibleRect
            let visibleRows = outlineView.rows(in: visibleRect)
            let topRow = visibleRows.location != NSNotFound && visibleRows.length > 0 ? visibleRows.location : -1
            let topItemId: String? = (topRow >= 0 && topRow < outlineView.numberOfRows)
                ? (outlineView.item(atRow: topRow) as? FileNodeWrapper)?.id
                : nil
            let selectedRow = outlineView.selectedRow
            let selectedItemId: String? = (selectedRow >= 0 && selectedRow < outlineView.numberOfRows)
                ? (outlineView.item(atRow: selectedRow) as? FileNodeWrapper)?.id
                : nil
            
            var idsToRestore = expandedItemIds
            if let targetId = targetFolderId {
                idsToRestore.insert(targetId)
            }
            
            let newItems = reconcileWrappers(existing: rootItems, newNodes: fileTree)
            updateRootItems(newItems)
            
            outlineView.reloadData()
            
            if idsToRestore.isEmpty {
                for item in newItems where item.node.isDirectory {
                    outlineView.expandItem(item)
                }
            } else {
                restoreExpansion(outlineView, ids: idsToRestore)
            }
            
            outlineView.layoutSubtreeIfNeeded()
            
            // Restore scroll: Prioritize target folder, then selected item, then top item, then saved Y
            let priorityTargetId = targetFolderId ?? selectedItemId
            if let targetId = priorityTargetId,
               let wrapper = findWrapper(byId: targetId, in: rootItems),
               outlineView.row(forItem: wrapper) >= 0 {
                scrollItemIntoView(wrapper, in: outlineView)
            } else if let topId = topItemId,
                      let topWrapper = findWrapper(byId: topId, in: rootItems),
                      outlineView.row(forItem: topWrapper) >= 0 {
                let row = outlineView.row(forItem: topWrapper)
                outlineView.scrollRowToVisible(row)
            } else {
                let maxScrollY = max(0, outlineView.frame.height - scrollView.contentView.bounds.height)
                let clampedY = max(0, min(savedScrollY, maxScrollY))
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            
            DispatchQueue.main.async { [weak self, weak outlineView] in
                guard let self = self, let ov = outlineView else { return }
                if let targetId = self.targetFolderId,
                   let wrapper = self.findWrapper(byId: targetId, in: self.rootItems) {
                    self.scrollItemIntoView(wrapper, in: ov)
                }
            }
        }
        
        // Helper to smoothly scroll an item and its children into comfortable view
        func scrollItemIntoView(_ wrapper: FileNodeWrapper, in outlineView: NSOutlineView) {
            let row = outlineView.row(forItem: wrapper)
            guard row >= 0 else { return }
            outlineView.scrollRowToVisible(row)
            let childCount = outlineView.numberOfChildren(ofItem: wrapper)
            if childCount > 0 {
                let maxChildRow = min(row + min(childCount, 4), outlineView.numberOfRows - 1)
                if maxChildRow > row {
                    outlineView.scrollRowToVisible(maxChildRow)
                }
            }
            outlineView.scrollRowToVisible(row)
        }
        
        // MARK: - State Persistence
        
        func getExpandedIds(_ outlineView: NSOutlineView) -> Set<String> {
            var expanded = expandedItemIds
            let rowCount = outlineView.numberOfRows
            if rowCount > 0 {
                for i in 0..<rowCount {
                    if let item = outlineView.item(atRow: i) as? FileNodeWrapper, outlineView.isItemExpanded(item) {
                        expanded.insert(item.id)
                    }
                }
            }
            return expanded
        }
        
        func restoreExpansion(_ outlineView: NSOutlineView, ids: Set<String>) {
            isRestoringExpansion = true
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            
            func expand(_ item: FileNodeWrapper) {
                if ids.contains(item.id) {
                    if item.childrenWrappers == nil {
                        item.childrenWrappers = item.node.children.map { FileNodeWrapper($0) }
                    }
                    outlineView.expandItem(item)
                    if let children = item.childrenWrappers {
                        children.forEach { expand($0) }
                    }
                }
            }
            
            rootItems.forEach { expand($0) }
            
            NSAnimationContext.endGrouping()
            isRestoringExpansion = false
        }
        
        // MARK: - Folder Interaction & Expansion
        
        func expandFolder(_ item: FileNodeWrapper, in outlineView: NSOutlineView) {
            targetFolderId = item.id
            expandedItemIds.insert(item.id)
            if item.childrenWrappers == nil && !item.node.children.isEmpty {
                item.childrenWrappers = item.node.children.map { FileNodeWrapper($0) }
            }
            outlineView.expandItem(item)
            scrollItemIntoView(item, in: outlineView)
            
            if !item.node.hasLoadedChildren {
                parent.onAction(.loadChildren(item.node))
            }
        }
        
        @objc func onClick(_ sender: NSOutlineView) {
            let row = sender.clickedRow
            guard row >= 0, let item = sender.item(atRow: row) as? FileNodeWrapper else { return }
            
            // Check if the click was directly on the disclosure triangle
            if let event = NSApp.currentEvent {
                let point = sender.convert(event.locationInWindow, from: nil)
                let outlineCellFrame = sender.frameOfOutlineCell(atRow: row)
                if outlineCellFrame.contains(point) {
                    // Disclosure triangle click is handled natively by NSOutlineView
                    return
                }
            }
            
            if item.node.isDirectory {
                targetFolderId = item.id
                if sender.isItemExpanded(item) {
                    sender.collapseItem(item)
                } else {
                    expandFolder(item, in: sender)
                }
            }
        }
        
        @objc func onDoubleClick(_ sender: NSOutlineView) {
            let row = sender.clickedRow
            guard row >= 0, let item = sender.item(atRow: row) as? FileNodeWrapper else { return }
            
            if item.node.isDirectory {
                targetFolderId = item.id
                if sender.isItemExpanded(item) {
                    sender.collapseItem(item)
                } else {
                    expandFolder(item, in: sender)
                }
            } else {
                parent.onAction(.openFile(item.node))
            }
        }

        // MARK: - DataSource
        
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                return rootItems.count
            }
            guard let wrapper = item as? FileNodeWrapper else { return 0 }
            return wrapper.node.children.count
        }
        
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil {
                guard index >= 0 && index < rootItems.count else { return NSObject() }
                return rootItems[index]
            }
            guard let wrapper = item as? FileNodeWrapper else { return NSObject() }
            
            if wrapper.childrenWrappers == nil {
                wrapper.childrenWrappers = wrapper.node.children.map { FileNodeWrapper($0) }
            }
            
            guard let children = wrapper.childrenWrappers, index >= 0 && index < children.count else {
                return NSObject()
            }
            return children[index]
        }
        
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let wrapper = item as? FileNodeWrapper else { return false }
            return wrapper.node.isDirectory
        }
        
        // MARK: - Delegate (View)
        
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let wrapper = item as? FileNodeWrapper else { return nil }
            
            let cellIdentifier = NSUserInterfaceItemIdentifier("FileCell")
            var view = outlineView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
            
            if view == nil {
                view = NSTableCellView()
                view?.identifier = cellIdentifier
                
                // Icon
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.imageScaling = .scaleProportionallyDown
                view?.addSubview(imageView)
                view?.imageView = imageView
                
                // Text
                let textField = NSTextField()
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.isBordered = false
                textField.drawsBackground = false
                textField.lineBreakMode = .byTruncatingTail
                view?.addSubview(textField)
                view?.textField = textField
                
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: view!.leadingAnchor, constant: 2),
                    imageView.centerYAnchor.constraint(equalTo: view!.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: view!.trailingAnchor, constant: -2),
                    textField.centerYAnchor.constraint(equalTo: view!.centerYAnchor)
                ])
            }
            
            // Configure
            let isExpanded = outlineView.isItemExpanded(item)
            if let extIcon = ExtensionManager.shared.iconImage(for: wrapper.node.name, isDirectory: wrapper.node.isDirectory, isExpanded: isExpanded) {
                view?.imageView?.image = extIcon
                view?.imageView?.contentTintColor = nil
            } else {
                let iconName = fileIconName(for: wrapper.node.name, isDirectory: wrapper.node.isDirectory)
                view?.imageView?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
                view?.imageView?.contentTintColor = iconColor(for: wrapper.node.name, isDirectory: wrapper.node.isDirectory)
            }
            view?.textField?.stringValue = wrapper.node.name
            
            return view
        }
        
        // MARK: - Selection Events
        
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            let row = outlineView.selectedRow
            guard row >= 0, let item = outlineView.item(atRow: row) as? FileNodeWrapper else { return }
            if !item.node.isDirectory {
                parent.onAction(.openFile(item.node))
            }
        }
        
        // MARK: - Expansion Events
        
        func outlineViewItemDidExpand(_ notification: Notification) {
            guard let item = notification.userInfo?["NSObject"] as? FileNodeWrapper else { return }
            expandedItemIds.insert(item.id)
            
            if !isRestoringExpansion {
                targetFolderId = item.id
                if let ov = outlineView {
                    scrollItemIntoView(item, in: ov)
                }
            }
            
            if !item.node.hasLoadedChildren {
                parent.onAction(.loadChildren(item.node))
            }
        }
        
        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard let item = notification.userInfo?["NSObject"] as? FileNodeWrapper else { return }
            expandedItemIds.remove(item.id)
            
            if !isRestoringExpansion {
                targetFolderId = item.id
                if let ov = outlineView {
                    let row = ov.row(forItem: item)
                    if row >= 0 {
                        ov.scrollRowToVisible(row)
                    }
                }
            }
        }
        
        private func fileIconName(for name: String, isDirectory: Bool) -> String {
            if isDirectory { return "folder.fill" }
            let ext = (name as NSString).pathExtension.lowercased()
            switch ext {
            case "swift": return "swift"
            case "py": return "curlybraces.square"
            case "js", "ts": return "curlybraces"
            case "rs": return "gearshape.2"
            case "json": return "curlybraces.square"
            case "md": return "doc.richtext"
            case "plist": return "list.bullet.rectangle"
            case "storyboard", "xib": return "square.grid.2x2"
            case "entitlements": return "lock.doc"
            default: return "doc.text"
            }
        }
        
        private func iconColor(for name: String, isDirectory: Bool) -> NSColor {
            if isDirectory {
                return NSColor(red: 0.96, green: 0.75, blue: 0.30, alpha: 1.0) // Xcode yellow folder
            }
            let ext = (name as NSString).pathExtension.lowercased()
            switch ext {
            case "swift": return .systemOrange
            case "py": return .systemGreen
            case "js": return .systemYellow
            case "ts": return .systemBlue
            case "rs": return .systemOrange
            case "json": return .systemPurple
            case "md": return .systemCyan
            case "plist", "entitlements": return .systemGray
            default: return .secondaryLabelColor
            }
        }
    }
}
