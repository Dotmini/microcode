//
//  AuthenticFileTree.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2026 AIPRENEUR. All rights reserved.
//

import SwiftUI
import AppKit

// MARK: - Node Wrapper (Bridge Class for NSOutlineView)

class FileNodeWrapper: NSObject {
    let node: FileNode
    let id: String
    
    // Cache children wrappers to maintain object identity
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
        
        // Double click action
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(Coordinator.onDoubleClick)
        
        scrollView.documentView = outlineView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let outlineView = nsView.documentView as? NSOutlineView else { return }
        context.coordinator.parent = self
        nsView.drawsBackground = backgroundColor.alphaComponent > 0
        nsView.backgroundColor = backgroundColor
        outlineView.backgroundColor = backgroundColor
        
        // Efficient Update: Reload only if data changed
        // For simplicity in this step, we reload mostly.
        // Ideally we diff, but `fileTree` replacement is usually a full refresh event in AppState.
        
        // Naive update: check count diff or deep logic.
        // For now, we update the coordinator's root cache and reload.
        // To preserve expansion state, we would need to save/restore persistent IDs.
        
        if context.coordinator.needsReload(revision: revision, currentTreeCount: fileTree.count) {
             // Save expansion state BEFORE updating rootItems
             let expandedIds = context.coordinator.getExpandedIds(outlineView)
             
             let newItems = fileTree.map { FileNodeWrapper($0) }
             context.coordinator.updateRootItems(newItems)
             
             outlineView.reloadData()
             
             // Restore expansion state
             context.coordinator.restoreExpansion(outlineView, ids: expandedIds)
        }
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: AuthenticFileTree
        var rootItems: [FileNodeWrapper] = []
        var lastRevision: UInt64?
        
        init(_ parent: AuthenticFileTree) {
            self.parent = parent
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
        
        // MARK: - State Persistence
        
        func getExpandedIds(_ outlineView: NSOutlineView) -> Set<String> {
            var expanded = Set<String>()
            let rowCount = outlineView.numberOfRows
            guard rowCount > 0 else { return expanded }
            for i in 0..<rowCount {
                if let item = outlineView.item(atRow: i) as? FileNodeWrapper, outlineView.isItemExpanded(item) {
                     expanded.insert(item.id)
                }
            }
            return expanded
        }
        
        func restoreExpansion(_ outlineView: NSOutlineView, ids: Set<String>) {
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
            let iconName = fileIconName(for: wrapper.node.name, isDirectory: wrapper.node.isDirectory)
            view?.imageView?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            view?.imageView?.contentTintColor = iconColor(for: wrapper.node.name, isDirectory: wrapper.node.isDirectory)
            view?.textField?.stringValue = wrapper.node.name
            
            return view
        }
        
        @objc func onDoubleClick(_ sender: NSOutlineView) {
            let row = sender.clickedRow
            guard row >= 0, let item = sender.item(atRow: row) as? FileNodeWrapper else { return }
            
            if item.node.isDirectory {
                if sender.isItemExpanded(item) {
                     sender.collapseItem(item)
                } else {
                     sender.expandItem(item)
                     // Trigger load children if needed
                     if !item.node.hasLoadedChildren {
                         parent.onAction(.loadChildren(item.node))
                     }
                }
            } else {
                parent.onAction(.openFile(item.node))
            }
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
            if !item.node.hasLoadedChildren {
                parent.onAction(.loadChildren(item.node))
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
