import SwiftUI
import AppKit

struct TerminalTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
    var textColor: NSColor = .textColor
    var backgroundColor: NSColor = .textBackgroundColor
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false // Allow transparency from the text view or window
        
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = backgroundColor
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        
        scrollView.documentView = textView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        // Update styling if changed
        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = backgroundColor
        
        // Only update text if it's different and not just a small append
        // For terminal, we usually append. NSTextView is better at this if we use its storage.
        if textView.string != text {
            let previousLength = textView.string.count
            textView.string = text
            
            // Auto-scroll to bottom if it was at the bottom or if it's a significant update
            if text.count > previousLength {
                textView.scrollToEndOfDocument(nil)
            }
        }
    }
}
