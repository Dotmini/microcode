import SwiftUI

struct DesignInteractionOverlay: View {
    @Binding var element: DesignElement
    let zoomLevel: CGFloat
    
    // State to track resize start
    @State private var initialFrame: CGRect?
    
    // Appearance
    // Appearance
    private var handleSize: CGFloat { 10 / zoomLevel }
    private let handleColor: Color = .white
    private let handleBorder: Color = .blue
    
    var body: some View {
        ZStack {
            // Selection Border
            Rectangle()
                .strokeBorder(Color.blue, lineWidth: 2)
                .allowsHitTesting(false)
            
            // Handles
            Group {
                // Cornerstone handles
                handle(alignment: .topLeading) { dx, dy in resize(dx: dx, dy: dy, lock: .bottomTrailing) }
                handle(alignment: .topTrailing) { dx, dy in resize(dx: dx, dy: dy, lock: .bottomLeading) }
                handle(alignment: .bottomLeading) { dx, dy in resize(dx: dx, dy: dy, lock: .topTrailing) }
                handle(alignment: .bottomTrailing) { dx, dy in resize(dx: dx, dy: dy, lock: .topLeading) }
                
                // Edge handles
                handle(alignment: .top) { dx, dy in resize(dx: 0, dy: dy, lock: .bottom) }
                handle(alignment: .bottom) { dx, dy in resize(dx: 0, dy: dy, lock: .top) }
                handle(alignment: .leading) { dx, dy in resize(dx: dx, dy: 0, lock: .trailing) }
                handle(alignment: .trailing) { dx, dy in resize(dx: dx, dy: 0, lock: .leading) }
            }
        }
        .frame(width: element.width, height: element.height)
    }
    
    // MARK: - Handle Logic
    
    private func handle(alignment: Alignment, action: @escaping (CGFloat, CGFloat) -> Void) -> some View {
        Circle()
            .fill(handleColor)
            .overlay(Circle().stroke(handleBorder, lineWidth: 1.5 / zoomLevel))
            .frame(width: handleSize, height: handleSize)
            .shadow(radius: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            // Offset handle to be centered on the border
            .offset(x: offset(for: alignment).x, y: offset(for: alignment).y)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if initialFrame == nil { initialFrame = element.frame }
                        // Calculate delta relative to zoom
                        let dx = value.translation.width / zoomLevel
                        let dy = value.translation.height / zoomLevel
                        action(dx, dy)
                    }
                    .onEnded { _ in
                        initialFrame = nil
                    }
            )
    }
    
    // Helper to offset handles 50% out
    private func offset(for alignment: Alignment) -> CGPoint {
        switch alignment {
        case .topLeading: return CGPoint(x: -handleSize/2, y: -handleSize/2)
        case .top: return CGPoint(x: 0, y: -handleSize/2)
        case .topTrailing: return CGPoint(x: handleSize/2, y: -handleSize/2)
        case .leading: return CGPoint(x: -handleSize/2, y: 0)
        case .trailing: return CGPoint(x: handleSize/2, y: 0)
        case .bottomLeading: return CGPoint(x: -handleSize/2, y: handleSize/2)
        case .bottom: return CGPoint(x: 0, y: handleSize/2)
        case .bottomTrailing: return CGPoint(x: handleSize/2, y: handleSize/2)
        default: return .zero
        }
    }
    
    // Resizing Logic using "Lock Point" anchor
    // We calculate new frame by expanding/contracting from the opposite corner
    private enum LockPoint {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
        case top, bottom, leading, trailing
    }
    
    private func resize(dx: CGFloat, dy: CGFloat, lock: LockPoint) {
        guard let initial = initialFrame else { return }
        
        // This is a simplified "Directional" Resize
        // Real impl usually calculates min/max
        
        var newX = initial.origin.x
        var newY = initial.origin.y
        var newW = initial.width
        var newH = initial.height
        
        // Horizontal
        if lock == .trailing || lock == .topTrailing || lock == .bottomTrailing {
            // Locking Right edge -> Resize from Left
            newX += dx
            newW -= dx
        } else if lock == .leading || lock == .topLeading || lock == .bottomLeading {
             // Locking Left edge -> Resize from Right
            newW += dx
        }
        
        // Vertical
        if lock == .bottom || lock == .bottomLeading || lock == .bottomTrailing {
            // Locking Bottom -> Resize from Top
            newY += dy
            newH -= dy
        } else if lock == .top || lock == .topLeading || lock == .topTrailing {
            // Locking Top -> Resize from Bottom
            newH += dy
        }
        
        // Min size
        if newW < 10 { newW = 10; newX = element.x } // Prevent flipping for now
        if newH < 10 { newH = 10; newY = element.y }
        
        element.x = newX
        element.y = newY
        element.width = newW
        element.height = newH
    }
}
