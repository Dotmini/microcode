import AppKit

let sv = NSTextView.scrollableTextView()
let tv = sv.documentView as! NSTextView

print("isHorizontallyResizable:", tv.isHorizontallyResizable)
print("autoresizingMask:", tv.autoresizingMask.rawValue)
print("widthTracksTextView:", tv.textContainer?.widthTracksTextView ?? false)
