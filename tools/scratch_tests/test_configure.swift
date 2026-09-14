import AppKit

let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
sv.hasVerticalScroller = true
sv.hasHorizontalScroller = true

let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
tv.minSize = NSSize(width: 0, height: 0)
tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
tv.isVerticallyResizable = true
tv.isHorizontallyResizable = true
tv.autoresizingMask = [.width, .height] // Let's see if this conflicts
tv.textContainer?.widthTracksTextView = false
tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

sv.documentView = tv
print("Configured.")
