import SwiftUI
import Combine

@MainActor
class DesignStore: ObservableObject {
    @Published var project: DesignProject
    @Published var activePageId: UUID
    @Published var selection: Set<UUID> = []
    
    // Canvas State
    @Published var zoomLevel: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero
    
    // Tool
    @Published var currentTool: DesignTool = .select
    
    enum DesignTool {
        case select, hand, frame
        // Shapes
        case rectangle, ellipse, roundedRect, star, polygon, line, arrow
        // GUI Tools
        case button, label, textfield, checkbox, switchToggle, slider, progress
        case text, image
        // Advanced
        case card, list, navigationBar, tabBar
        // New
        case avatar, badge, radioButton, tooltip, menu, modal, divider
    }
    
    init() {
        let page1 = DesignPage(name: "Page 1", elements: [])
        self.project = DesignProject(name: "New Design", pages: [page1], activePageId: page1.id)
        self.activePageId = page1.id
    }
    
    // MARK: - Element Management
    
    func addElement(_ element: DesignElement) {
        if let index = project.pages.firstIndex(where: { $0.id == activePageId }) {
            project.pages[index].elements.append(element)
            selection = [element.id]
        }
    }
    
    func updateElement(_ element: DesignElement) {
        if let pageIndex = project.pages.firstIndex(where: { $0.id == activePageId }) {
            if let elIndex = project.pages[pageIndex].elements.firstIndex(where: { $0.id == element.id }) {
                project.pages[pageIndex].elements[elIndex] = element
            }
        }
    }
    
    func deleteSelection() {
        guard let pageIndex = project.pages.firstIndex(where: { $0.id == activePageId }) else { return }
        // Clear selection first to avoid UI trying to render deleted items
        let itemsToDelete = selection
        selection = []
        
        project.pages[pageIndex].elements.removeAll(where: { itemsToDelete.contains($0.id) })
    }
    
    // MARK: - Helpers
    
    var activePage: DesignPage? {
        project.pages.first(where: { $0.id == activePageId })
    }
    
    func selectedElement() -> DesignElement? {
        guard let id = selection.first else { return nil }
        return activePage?.elements.first(where: { $0.id == id })
    }
    
    func selectedElements() -> [DesignElement] {
        guard let page = activePage else { return [] }
        return page.elements.filter { selection.contains($0.id) }
    }
    
    // MARK: - Duplicate
    
    func duplicateSelection() {
        guard let pageIndex = project.pages.firstIndex(where: { $0.id == activePageId }) else { return }
        let selected = selectedElements()
        var newIds: Set<UUID> = []
        for element in selected {
            var copy = element
            copy.id = UUID()
            copy.name = "\(element.name) Copy"
            copy.x += 20
            copy.y += 20
            project.pages[pageIndex].elements.append(copy)
            newIds.insert(copy.id)
        }
        selection = newIds
    }
    
    // MARK: - Alignment (Figma-style)
    
    func alignSelection(_ alignment: AlignmentAction) {
        guard let pageIndex = project.pages.firstIndex(where: { $0.id == activePageId }) else { return }
        let selected = selectedElements()
        guard selected.count > 1 else { return }
        
        let minX = selected.map { $0.x }.min() ?? 0
        let maxX = selected.map { $0.x + $0.width }.max() ?? 0
        let minY = selected.map { $0.y }.min() ?? 0
        let maxY = selected.map { $0.y + $0.height }.max() ?? 0
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        
        for id in selection {
            guard let idx = project.pages[pageIndex].elements.firstIndex(where: { $0.id == id }) else { continue }
            var el = project.pages[pageIndex].elements[idx]
            
            switch alignment {
            case .left: el.x = minX
            case .right: el.x = maxX - el.width
            case .top: el.y = minY
            case .bottom: el.y = maxY - el.height
            case .centerH: el.x = centerX - el.width / 2
            case .centerV: el.y = centerY - el.height / 2
            case .distributeH:
                break // Handled separately
            case .distributeV:
                break
            }
            project.pages[pageIndex].elements[idx] = el
        }
        
        // Handle distribute
        if alignment == .distributeH && selected.count > 2 {
            let sorted = selected.sorted { $0.x < $1.x }
            let totalSpace = (sorted.last!.x + sorted.last!.width) - sorted.first!.x
            let totalWidth = sorted.reduce(0) { $0 + $1.width }
            let gap = (totalSpace - totalWidth) / CGFloat(sorted.count - 1)
            var currentX = sorted.first!.x
            for item in sorted {
                if let idx = project.pages[pageIndex].elements.firstIndex(where: { $0.id == item.id }) {
                    project.pages[pageIndex].elements[idx].x = currentX
                    currentX += item.width + gap
                }
            }
        }
        
        if alignment == .distributeV && selected.count > 2 {
            let sorted = selected.sorted { $0.y < $1.y }
            let totalSpace = (sorted.last!.y + sorted.last!.height) - sorted.first!.y
            let totalHeight = sorted.reduce(0) { $0 + $1.height }
            let gap = (totalSpace - totalHeight) / CGFloat(sorted.count - 1)
            var currentY = sorted.first!.y
            for item in sorted {
                if let idx = project.pages[pageIndex].elements.firstIndex(where: { $0.id == item.id }) {
                    project.pages[pageIndex].elements[idx].y = currentY
                    currentY += item.height + gap
                }
            }
        }
    }
    
    // MARK: - Save / Export
    
    func saveProject() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(project) else { return }
        
        let fm = FileManager.default
        let dir = (AgentToolBox.shared.workspaceRoot ?? NSHomeDirectory()) + "/.microcode/designs"
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/\(project.name.replacingOccurrences(of: " ", with: "_")).json"
        try? data.write(to: URL(fileURLWithPath: path))
    }
    
    func loadProject(from path: String) {
        guard let data = FileManager.default.contents(atPath: path),
              let proj = try? JSONDecoder().decode(DesignProject.self, from: data) else { return }
        self.project = proj
        self.activePageId = proj.pages.first?.id ?? UUID()
    }
    
    // MARK: - Bring Forward / Send Back
    
    func bringToFront() {
        guard let pageIndex = project.pages.firstIndex(where: { $0.id == activePageId }),
              let id = selection.first,
              let idx = project.pages[pageIndex].elements.firstIndex(where: { $0.id == id }) else { return }
        let element = project.pages[pageIndex].elements.remove(at: idx)
        project.pages[pageIndex].elements.append(element)
    }
    
    func sendToBack() {
        guard let pageIndex = project.pages.firstIndex(where: { $0.id == activePageId }),
              let id = selection.first,
              let idx = project.pages[pageIndex].elements.firstIndex(where: { $0.id == id }) else { return }
        let element = project.pages[pageIndex].elements.remove(at: idx)
        project.pages[pageIndex].elements.insert(element, at: 0)
    }
    
    // MARK: - Page Management
    
    func addPage(name: String) {
        let page = DesignPage(name: name)
        project.pages.append(page)
        activePageId = page.id
    }
    
    func deletePage(_ id: UUID) {
        project.pages.removeAll { $0.id == id }
        if activePageId == id {
            activePageId = project.pages.first?.id ?? UUID()
        }
    }
}

// MARK: - Alignment Actions

enum AlignmentAction {
    case left, right, top, bottom, centerH, centerV, distributeH, distributeV
}
