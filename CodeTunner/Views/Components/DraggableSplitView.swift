import SwiftUI

struct DraggableSplitView<Left: View, Right: View>: View {
    let left: Left
    let right: Right
    
    @State private var leftProportion: CGFloat
    @State private var dragStartProportion: CGFloat = 0.5
    @State private var isDragging: Bool = false
    @State private var hoverDivider: Bool = false
    
    init(initialProportion: CGFloat = 0.5, @ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self._leftProportion = State(initialValue: initialProportion)
        self.left = left()
        self.right = right()
    }
    
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                left
                    .frame(width: max(0, geo.size.width * leftProportion))
                    .clipped()
                
                // Divider
                ZStack {
                    Rectangle()
                        .fill(hoverDivider || isDragging ? Color.accentColor.opacity(0.3) : Color.clear)
                        .frame(width: 12)
                    
                    Capsule()
                        .fill(hoverDivider || isDragging ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 4, height: 32)
                }
                .frame(width: 1) // logical width
                .contentShape(Rectangle().inset(by: -6))
                .onHover { hovering in
                    hoverDivider = hovering
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                dragStartProportion = leftProportion
                            }
                            let delta = value.translation.width / geo.size.width
                            leftProportion = max(0.1, min(0.9, dragStartProportion + delta))
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
                .zIndex(1)
                
                right
                    .frame(width: max(0, geo.size.width * (1 - leftProportion)))
                    .clipped()
            }
        }
    }
}
