import SwiftUI

struct DesignCanvasView: View {
    @EnvironmentObject var designStore: DesignStore
    
    // Grid Configuration
    private let gridSize: CGFloat = 20
    private let dotSize: CGFloat = 2
    
    @State private var dragStart: CGPoint? = nil
    @State private var draggingElementID: UUID? = nil
    
    // State for Drawing
    @State private var drawingElement: DesignElement? = nil
    @State private var dragStartPoint: CGPoint? = nil
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                gridLayer
                contentLayer
                
                // Drawing Preview Layer
                if let element = drawingElement {
                    DesignElementView(element: element, isSelected: true)
                        .position(
                            x: (element.x + element.width/2) * designStore.zoomLevel,
                            y: (element.y + element.height/2) * designStore.zoomLevel
                        )
                        .opacity(0.7)
                }
            }
            .background(Color.white)
            .contentShape(Rectangle()) // Fix window dragging
            .offset(x: designStore.panOffset.width, y: designStore.panOffset.height)
            .gesture(backgroundGesture)
            .focusable() // Allow focus for keyboard events
            // Delete Shortcut
            .overlay(
                Button(action: { designStore.deleteSelection() }) {
                    EmptyView()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .opacity(0)
            )
        }
    }
    
    private var gridLayer: some View {
        MetalGridView(
            zoom: designStore.zoomLevel,
            offset: designStore.panOffset,
            gridSize: gridSize
        )
        .onTapGesture { designStore.selection = [] }
    }
    
    private var contentLayer: some View {
        Group {
            if let pageIndex = designStore.project.pages.firstIndex(where: { $0.id == designStore.activePageId }) {
                ForEach(designStore.project.pages[pageIndex].elements) { element in
                    ZStack {
                        DesignElementView(element: element, isSelected: designStore.selection.contains(element.id))
                            .equatable()
                            .position(
                                x: (element.x + element.width/2) * designStore.zoomLevel,
                                y: (element.y + element.height/2) * designStore.zoomLevel
                            )
                            .onTapGesture { designStore.selection = [element.id] }
                            .gesture(
                                DragGesture()
                                    .onChanged { value in handleDragChange(value, element: element) }
                                    .onEnded { _ in handleDragEnd() }
                            )
                        
                        if designStore.selection.contains(element.id) {
                            DesignInteractionOverlay(element: binding(for: element), zoomLevel: designStore.zoomLevel)
                                .position(
                                    x: (element.x + element.width/2) * designStore.zoomLevel,
                                    y: (element.y + element.height/2) * designStore.zoomLevel
                                )
                        }
                    }
                }
            }
        }
    }
    
    private var backgroundGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let zoom = designStore.zoomLevel
                
                if designStore.currentTool == .hand {
                    // Panning
                    designStore.panOffset.width += value.translation.width * 0.1
                    designStore.panOffset.height += value.translation.height * 0.1
                } else if designStore.currentTool == .select {
                    // Selection Marquee (Future)
                    designStore.selection = []
                } else {
                    // Drawing Shape
                    if dragStartPoint == nil {
                        dragStartPoint = value.startLocation
                    }
                    
                    let startX = value.startLocation.x / zoom
                    let startY = value.startLocation.y / zoom
                    let currentX = value.location.x / zoom
                    let currentY = value.location.y / zoom
                    
                    let x = min(startX, currentX)
                    let y = min(startY, currentY)
                    let w = abs(currentX - startX)
                    let h = abs(currentY - startY)
                    
                    // Update Preview
                    let type = toolToType(designStore.currentTool)
                    if drawingElement == nil {
                         drawingElement = DesignElement.create(type: type, x: x, y: y)
                    }
                    drawingElement?.x = x
                    drawingElement?.y = y
                    drawingElement?.width = max(w, 10) // Min size
                    drawingElement?.height = max(h, 10)
                }
            }
            .onEnded { value in
                if let element = drawingElement {
                    designStore.addElement(element)
                    DispatchQueue.main.async { // Avoid state update loop
                         designStore.currentTool = .select
                    }
                    drawingElement = nil
                }
                dragStartPoint = nil
            }
    }
    
    private func toolToType(_ tool: DesignStore.DesignTool) -> DesignElementType {
        switch tool {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .line: return .line
        case .text: return .text
        case .button: return .button
        case .card: return .card
        case .frame: return .frame
        default: return .rectangle
        }
    }
    
    // Helpers
    private func binding(for element: DesignElement) -> Binding<DesignElement> {
        Binding(
            get: {
                if let pageIndex = designStore.project.pages.firstIndex(where: { $0.id == designStore.activePageId }) {
                    return designStore.project.pages[pageIndex].elements.first(where: { $0.id == element.id }) ?? element
                }
                return element
            },
            set: { newValue in
                if let pageIndex = designStore.project.pages.firstIndex(where: { $0.id == designStore.activePageId }) {
                    if let elIndex = designStore.project.pages[pageIndex].elements.firstIndex(where: { $0.id == element.id }) {
                        designStore.project.pages[pageIndex].elements[elIndex] = newValue
                    }
                }
            }
        )
    }
    
    private func handleDragChange(_ value: DragGesture.Value, element: DesignElement) {
        if !designStore.selection.contains(element.id) {
            designStore.selection = [element.id]
        }
        
        if draggingElementID != element.id {
             draggingElementID = element.id
             dragStart = CGPoint(x: element.x, y: element.y)
        }
        
        if let start = dragStart {
            let dx = value.translation.width / designStore.zoomLevel
            let dy = value.translation.height / designStore.zoomLevel
            
            // Apply Update
            designStore.updateElement(element.copyWith(x: start.x + dx, y: start.y + dy))
        }
    }
    
    private func handleDragEnd() {
        draggingElementID = nil
        dragStart = nil
    }
}
