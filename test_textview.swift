import AppKit

let sv = NSTextView.scrollableTextView()
let tv = sv.documentView as! NSTextView
tv.string = "This is a long string that will wrap"
sv.frame = NSRect(x: 0, y: 0, width: 0, height: 100) // Width 0
sv.layoutSubtreeIfNeeded()
print("Did not crash")
