import AppKit

let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
sv.documentView = tv
tv.isVerticallyResizable = true
tv.isHorizontallyResizable = true
tv.autoresizingMask = [.width, .height]
tv.textContainer?.widthTracksTextView = false
tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

print(tv.autoresizingMask.rawValue)
