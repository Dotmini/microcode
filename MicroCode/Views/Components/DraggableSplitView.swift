import SwiftUI
import AppKit

// MARK: - Native AppKit Pane Resize Splitter (120Hz Screen-Coordinate Tracking)

/// High-precision AppKit splitter view that overrides `mouseDownCanMoveWindow = false`
/// and tracks hardware screen coordinates (`NSEvent.mouseLocation.x`) directly via
/// `NSWindow.trackEvents`. Eliminates window-drag hijacking, stuck cursors, and
/// SwiftUI geometry feedback lag on both Left and Right split panes.
struct NativePaneResizeSplitter: NSViewRepresentable {
    enum ResizeEdge {
        /// Splitter sits on the trailing edge of a left-hand pane (`+deltaX` widens pane).
        case leadingPane
        /// Splitter sits on the leading edge of a right-hand pane (`-deltaX` widens pane).
        case trailingPane
    }

    let edge: ResizeEdge
    let currentWidth: Double
    let minWidth: Double
    let maxWidth: Double
    var visualWidth: CGFloat = 6
    var showsGripPill: Bool = true
    var collapseThreshold: Double? = nil
    var onWidthChange: (Double) -> Void
    var onDragStarted: (() -> Void)? = nil
    var onCollapse: (() -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil

    init(
        edge: ResizeEdge,
        width: Binding<Double>,
        currentEffectiveWidth: Double? = nil,
        minWidth: Double,
        maxWidth: Double,
        visualWidth: CGFloat = 6,
        showsGripPill: Bool = true,
        collapseThreshold: Double? = nil,
        onDragStarted: (() -> Void)? = nil,
        onCollapse: (() -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil
    ) {
        self.edge = edge
        self.currentWidth = currentEffectiveWidth ?? width.wrappedValue
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.visualWidth = visualWidth
        self.showsGripPill = showsGripPill
        self.collapseThreshold = collapseThreshold
        self.onWidthChange = { newVal in
            width.wrappedValue = newVal
        }
        self.onDragStarted = onDragStarted
        self.onCollapse = onCollapse
        self.onDoubleClick = onDoubleClick
    }

    init(
        edge: ResizeEdge,
        currentWidth: Double,
        minWidth: Double,
        maxWidth: Double,
        visualWidth: CGFloat = 6,
        showsGripPill: Bool = true,
        collapseThreshold: Double? = nil,
        onWidthChange: @escaping (Double) -> Void,
        onDragStarted: (() -> Void)? = nil,
        onCollapse: (() -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil
    ) {
        self.edge = edge
        self.currentWidth = currentWidth
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.visualWidth = visualWidth
        self.showsGripPill = showsGripPill
        self.collapseThreshold = collapseThreshold
        self.onWidthChange = onWidthChange
        self.onDragStarted = onDragStarted
        self.onCollapse = onCollapse
        self.onDoubleClick = onDoubleClick
    }

    func makeNSView(context: Context) -> PaneResizeSplitterNSView {
        let view = PaneResizeSplitterNSView()
        applyProperties(to: view)
        return view
    }

    func updateNSView(_ nsView: PaneResizeSplitterNSView, context: Context) {
        applyProperties(to: nsView)
    }

    private func applyProperties(to view: PaneResizeSplitterNSView) {
        view.edge = edge
        if !view.isDragging {
            view.currentWidth = currentWidth
        }
        view.minWidth = minWidth
        view.maxWidth = maxWidth
        view.showsGripPill = showsGripPill
        view.collapseThreshold = collapseThreshold
        view.onWidthChange = onWidthChange
        view.onDragStarted = onDragStarted
        view.onCollapse = onCollapse
        view.onDoubleClick = onDoubleClick
    }
}

final class PaneResizeSplitterNSView: NSView {
    var edge: NativePaneResizeSplitter.ResizeEdge = .leadingPane
    var currentWidth: Double = 270
    var minWidth: Double = 160
    var maxWidth: Double = 600
    var showsGripPill: Bool = true {
        didSet { if oldValue != showsGripPill { needsDisplay = true } }
    }
    var collapseThreshold: Double? = nil
    var onWidthChange: ((Double) -> Void)?
    var onDragStarted: (() -> Void)?
    var onCollapse: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    private(set) var isDragging: Bool = false
    private var isHovered: Bool = false
    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Convert point from superview coordinates to local bounds and allow generous ±4pt grab margin
        let localPoint = convert(point, from: superview)
        let expandedBounds = bounds.insetBy(dx: -4, dy: 0)
        return expandedBounds.contains(localPoint) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds.insetBy(dx: -4, dy: 0),
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds.insetBy(dx: -4, dy: 0), cursor: .resizeLeftRight)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
        NSCursor.resizeLeftRight.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if !isDragging {
            needsDisplay = true
            NSCursor.arrow.set()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let active = isHovered || isDragging
        let midX = bounds.midX
        let midY = bounds.midY

        if active {
            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
            bounds.fill()
        }

        let lineWidth: CGFloat = active ? 2.0 : 1.0
        let lineRect = NSRect(
            x: midX - lineWidth * 0.5,
            y: bounds.minY,
            width: lineWidth,
            height: bounds.height
        )
        let lineColor = active
            ? NSColor.controlAccentColor
            : NSColor.labelColor.withAlphaComponent(0.11)
        lineColor.setFill()
        lineRect.fill()

        if showsGripPill || active {
            let pillW: CGFloat = 3.0
            let pillH: CGFloat = active ? 36.0 : 26.0
            let pillRect = NSRect(
                x: midX - pillW * 0.5,
                y: midY - pillH * 0.5,
                width: pillW,
                height: pillH
            )
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 1.5, yRadius: 1.5)
            let pillColor = active
                ? NSColor.controlAccentColor
                : NSColor.secondaryLabelColor.withAlphaComponent(0.36)
            pillColor.setFill()
            pillPath.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let onDoubleClick {
            onDoubleClick()
            return
        }

        guard let win = self.window else { return }

        isDragging = true
        needsDisplay = true
        NSCursor.resizeLeftRight.set()
        onDragStarted?()

        let startScreenX = NSEvent.mouseLocation.x
        let startWidth = currentWidth
        var didTriggerCollapse = false

        win.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { [weak self] trackedEvent, stop in
            guard let self, let trackedEvent else {
                stop.pointee = true
                return
            }
            switch trackedEvent.type {
            case .leftMouseDragged:
                NSCursor.resizeLeftRight.set()
                let deltaX = Double(NSEvent.mouseLocation.x - startScreenX)
                let rawProposed = (self.edge == .leadingPane)
                    ? (startWidth + deltaX)
                    : (startWidth - deltaX)

                if let threshold = self.collapseThreshold,
                   rawProposed < threshold,
                   let onCollapse = self.onCollapse {
                    didTriggerCollapse = true
                    stop.pointee = true
                    DispatchQueue.main.async {
                        onCollapse()
                    }
                    return
                }

                let safeMax = max(self.minWidth, self.maxWidth)
                let clamped = max(self.minWidth, min(safeMax, rawProposed))
                self.currentWidth = clamped
                self.onWidthChange?(clamped)

            case .leftMouseUp:
                stop.pointee = true

            default:
                break
            }
        }

        isDragging = false
        let mouseInWindow = win.mouseLocationOutsideOfEventStream
        let localMouse = convert(mouseInWindow, from: nil)
        isHovered = bounds.insetBy(dx: -4, dy: 0).contains(localMouse)
        needsDisplay = true
        if !didTriggerCollapse && !isHovered {
            NSCursor.arrow.set()
        }
    }
}

// MARK: - Window Drag Spacer for Custom Titlebar Empty Space

/// Lightweight AppKit spacer for custom header bars so dragging empty header space
/// moves the macOS window while `window.isMovableByWindowBackground` stays `false`
/// (preventing accidental window drags on splitters, editors, and canvases).
struct WindowDragSpacerView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragHandleNSView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowDragHandleNSView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

// MARK: - Proportional Draggable Split View

struct DraggableSplitView<Left: View, Right: View>: View {
    let left: Left
    let right: Right
    var minLeftWidth: CGFloat = 200
    var minRightWidth: CGFloat = 200
    
    @State private var leftProportion: CGFloat
    
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
            let dividerWidth: CGFloat = 6
            let safeWidth = max(100, totalWidth - dividerWidth)
            
            let minProp = min(0.48, max(0.05, minLeftWidth / safeWidth))
            let maxProp = max(0.52, min(0.95, 1.0 - (minRightWidth / safeWidth)))
            let clampedProportion = max(minProp, min(maxProp, leftProportion))
            
            let leftWidth = max(0, safeWidth * clampedProportion)
            let rightWidth = max(0, safeWidth - leftWidth)
            
            HStack(spacing: 0) {
                left
                    .frame(width: leftWidth)
                    .clipped()
                
                NativePaneResizeSplitter(
                    edge: .leadingPane,
                    currentWidth: Double(leftWidth),
                    minWidth: Double(safeWidth * minProp),
                    maxWidth: Double(safeWidth * maxProp),
                    visualWidth: dividerWidth,
                    onWidthChange: { newLeftW in
                        leftProportion = max(minProp, min(maxProp, CGFloat(newLeftW) / safeWidth))
                    },
                    onDoubleClick: {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            leftProportion = 0.5
                        }
                    }
                )
                .frame(width: dividerWidth)
                .zIndex(50)
                
                right
                    .frame(width: rightWidth)
                    .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
