import SwiftUI

struct DraggableSplitView<Left: View, Right: View>: View {
    let left: Left
    let right: Right
    var minLeftWidth: CGFloat = 200
    var minRightWidth: CGFloat = 200
    
    @State private var leftProportion: CGFloat
    @State private var dragStartProportion: CGFloat = 0.5
    @State private var isDragging: Bool = false
    @State private var hoverDivider: Bool = false
    
    init(
        initialProportion: CGFloat = 0.5,
        minLeftWidth: CGFloat = 200,
        minRightWidth: CGFloat = 200,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) {
        self._leftProportion = State(initialValue: initialProportion)
        self.minLeftWidth = minLeftWidth
        self.minRightWidth = minRightWidth
        self.left = left()
        self.right = right()
    }
    
    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let safeWidth = max(100, totalWidth)
            
            // Dynamic bounds preventing either pane from violating minimum width
            let minProp = min(0.48, max(0.05, minLeftWidth / safeWidth))
            let maxProp = max(0.52, min(0.95, 1.0 - (minRightWidth / safeWidth)))
            let clampedProportion = max(minProp, min(maxProp, leftProportion))
            
            let leftWidth = max(0, safeWidth * clampedProportion)
            let rightWidth = max(0, safeWidth * (1.0 - clampedProportion))
            
            HStack(spacing: 0) {
                left
                    .frame(width: leftWidth)
                    .clipped()
                
                // Divider with generous hit target
                ZStack {
                    // Invisible hit target
                    Color.clear
                        .frame(width: 20)
                        .contentShape(Rectangle())
                    
                    // Highlight bar on hover or drag
                    Rectangle()
                        .fill(hoverDivider || isDragging ? Color.accentColor.opacity(0.35) : Color.clear)
                        .frame(width: 8)
                    
                    // Center pill handle
                    Capsule()
                        .fill(hoverDivider || isDragging ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 4, height: 36)
                }
                .frame(width: 1) // logical width in HStack
                .zIndex(999)
                .onHover { hovering in
                    hoverDivider = hovering
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else if !isDragging {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                dragStartProportion = clampedProportion
                            }
                            let delta = value.translation.width / safeWidth
                            let target = dragStartProportion + delta
                            leftProportion = max(minProp, min(maxProp, target))
                        }
                        .onEnded { _ in
                            isDragging = false
                            if !hoverDivider {
                                NSCursor.pop()
                            }
                        }
                )
                
                right
                    .frame(width: rightWidth)
                    .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
