import AppKit

let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
sv.backgroundColor = .red
sv.drawsBackground = true

let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
tv.string = "short"
tv.isVerticallyResizable = true
tv.isHorizontallyResizable = true
tv.autoresizingMask = [] // EMPTY!
tv.textContainer?.widthTracksTextView = false
tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
tv.backgroundColor = .blue

sv.documentView = tv

// Layout and check frames
sv.layoutSubtreeIfNeeded()
print("tv frame:", tv.frame)
print("clip frame:", sv.contentView.frame)
