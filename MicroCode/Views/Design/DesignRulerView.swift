import SwiftUI

struct DesignRulerView: View {
    let orientation: Orientation
    let zoom: CGFloat
    let offset: CGFloat
    
    enum Orientation {
        case horizontal
        case vertical
    }
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let effectiveSpacing = 100 * zoom
                // Optimization: Don't render if too small
                if effectiveSpacing < 20 { return }
                
                let start = offset
                let length = (orientation == .horizontal) ? size.width : size.height
                
                // Calculate visible range based on offset
                // visibleScreenX = 0...length
                // canvasX = (screenX - pan) / zoom
                // We want to draw marks at regular canvas intervals (e.g. 0, 100, 200...)
                
                // Start drawing from nearest 100
                // let firstMark = floor((0 - offset) / zoom / 100) * 100
                
                // Wait, logic is screen-based drawing of canvas coordinate values.
                // We iterate screen pixels? No, easier to iterate canvas units and project them.
                
                let visibleStartCanvas = -offset / zoom
                let visibleEndCanvas = (length - offset) / zoom
                
                // Round to nearest 100 (major ticks)
                let startTick = floor(visibleStartCanvas / 100) * 100
                
                var path = Path()
                
                for i in stride(from: startTick, to: visibleEndCanvas + 100, by: 100) {
                    let screenPos = i * zoom + offset
                    if screenPos < -50 || screenPos > length + 50 { continue }
                    
                    if orientation == .horizontal {
                        // Major tick
                        path.move(to: CGPoint(x: screenPos, y: 0))
                        path.addLine(to: CGPoint(x: screenPos, y: 20))
                        
                        // Text
                        let text = Text("\(Int(i))").font(.system(size: 8))
                        context.draw(text, at: CGPoint(x: screenPos + 12, y: 10))
                        
                        // Minor ticks (every 10 units = 10 ticks per 100?) Too dense. 
                        // Maybe 50?
                        let mid = screenPos + (50 * zoom)
                        path.move(to: CGPoint(x: mid, y: 15))
                        path.addLine(to: CGPoint(x: mid, y: 20))
                        
                    } else {
                        path.move(to: CGPoint(x: 0, y: screenPos))
                        path.addLine(to: CGPoint(x: 20, y: screenPos))
                        
                        // Vertical text is tricky, context.draw doesn't rotate easily in SwiftUI Canvas < macOS 13?
                        // Actually it does `context.rotate`. But let's just draw standard horizontal text near the tick.
                        let text = Text("\(Int(i))").font(.system(size: 8))
                        context.draw(text, at: CGPoint(x: 10, y: screenPos + 10))
                        
                         let mid = screenPos + (50 * zoom)
                        path.move(to: CGPoint(x: 15, y: mid))
                        path.addLine(to: CGPoint(x: 20, y: mid))
                    }
                }
                
                context.stroke(path, with: .color(.gray), lineWidth: 0.5)
            }
        }
        .frame(width: orientation == .vertical ? 20 : nil, height: orientation == .horizontal ? 20 : nil)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipped()
    }
}
