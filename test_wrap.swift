import AppKit

let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 0, height: 100))
sv.hasVerticalScroller = true

let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 0, height: 100))
tv.string = String(repeating: "hello world ", count: 1000)
tv.isVerticallyResizable = true
tv.isHorizontallyResizable = false
tv.autoresizingMask = [.width]
tv.textContainer?.widthTracksTextView = true

// DANGEROUS LINE:
tv.textContainer?.containerSize = NSSize(width: sv.contentSize.width, height: CGFloat.greatestFiniteMagnitude)

sv.documentView = tv
sv.layoutSubtreeIfNeeded()
print("Did not crash!")
