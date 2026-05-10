//
//  LineNumberRulerView.swift
//  CodeTunner
//
//  Professional line number gutter for NSTextView
//  Uses NSRulerView for native macOS integration
//
//  Copyright © 2025 SPU AI CLUB — Dotmini Software
//

import AppKit

// MARK: - Line Number Ruler View

final class LineNumberRulerView: NSRulerView {
    
    // MARK: - Properties
    
    private weak var textView: NSTextView?
    
    /// Gutter width (auto-calculated based on line count digits)
    private var gutterWidth: CGFloat = 40
    
    /// Cached line count for efficient gutter width calculation
    private var cachedLineCount: Int = 0
    
    /// Line number font
    private var lineNumberFont: NSFont {
        let size = max(9, (textView?.font?.pointSize ?? 13) - 2)
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }
    
    /// Line number text color
    private var lineNumberColor: NSColor {
        return NSColor.secondaryLabelColor
    }
    
    /// Current line highlight color
    private var currentLineColor: NSColor {
        return NSColor.labelColor.withAlphaComponent(0.85)
    }
    
    /// Gutter background color
    private var gutterBackgroundColor: NSColor {
        if let bgColor = textView?.backgroundColor {
            // Slightly different shade than editor background
            return bgColor.blended(withFraction: 0.06, of: NSColor.labelColor) ?? bgColor
        }
        return NSColor.controlBackgroundColor
    }
    
    /// Separator line color
    private var separatorColor: NSColor {
        return NSColor.separatorColor.withAlphaComponent(0.2)
    }
    
    // MARK: - Init
    
    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        
        self.clientView = textView
        self.ruleThickness = gutterWidth
        
        // Observe text changes to update line numbers
        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification, object: textView
        )
        
        // Observe selection changes to highlight current line
        NotificationCenter.default.addObserver(
            self, selector: #selector(selectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification, object: textView
        )
        
        // Observe bounds changes for scroll sync
        if let contentView = scrollView.contentView as? NSClipView {
            contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification, object: contentView
            )
        }
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Notifications
    
    @objc private func textDidChange(_ notification: Notification) {
        updateGutterWidth()
        needsDisplay = true
    }
    
    @objc private func selectionDidChange(_ notification: Notification) {
        needsDisplay = true
    }
    
    @objc private func boundsDidChange(_ notification: Notification) {
        needsDisplay = true
    }
    
    // MARK: - Gutter Width
    
    private func updateGutterWidth() {
        guard let textView = textView else { return }
        let lineCount = max(1, textView.string.components(separatedBy: "\n").count)
        
        // Only recalculate if digit count changed
        if lineCount != cachedLineCount {
            cachedLineCount = lineCount
            let digits = max(3, String(lineCount).count + 1)
            let sampleString = String(repeating: "8", count: digits)
            let size = (sampleString as NSString).size(withAttributes: [.font: lineNumberFont])
            let newWidth = ceil(size.width) + 20 // padding
            
            if abs(newWidth - gutterWidth) > 1 {
                gutterWidth = newWidth
                ruleThickness = gutterWidth
            }
        }
    }
    
    // MARK: - Drawing
    
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        
        let content = textView.string
        let visibleRect = scrollView?.contentView.bounds ?? textView.visibleRect
        
        // Draw gutter background
        gutterBackgroundColor.setFill()
        rect.fill()
        
        // Draw separator line
        separatorColor.setStroke()
        let separatorPath = NSBezierPath()
        separatorPath.move(to: NSPoint(x: bounds.maxX - 0.5, y: rect.minY))
        separatorPath.line(to: NSPoint(x: bounds.maxX - 0.5, y: rect.maxY))
        separatorPath.lineWidth = 0.5
        separatorPath.stroke()
        
        // Calculate visible line range
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        
        // Get current line number (for highlighting)
        let selectedRange = textView.selectedRange()
        let currentLineNumber = lineNumber(for: selectedRange.location, in: content)
        
        // Attributes for line numbers
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: lineNumberColor
        ]
        
        let currentLineAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: lineNumberFont.pointSize, weight: .medium),
            .foregroundColor: currentLineColor
        ]
        
        // Iterate through visible lines
        let nsString = content as NSString
        var lineIndex = lineNumber(for: charRange.location, in: content)
        
        var index = charRange.location
        while index <= min(charRange.location + charRange.length, nsString.length) {
            // Find the line range for this index
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            
            // Get the glyph range for this line
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            
            // Get the bounding rect for the first glyph in this line
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: lineGlyphRange.location, effectiveRange: nil)
            
            // Adjust for text container inset
            lineRect.origin.y += textView.textContainerInset.height
            
            // Convert to ruler coordinates
            let yPosition = lineRect.origin.y - visibleRect.origin.y
            
            // Draw line number
            let lineNumberString = "\(lineIndex)"
            let isCurrentLine = lineIndex == currentLineNumber
            let attributes = isCurrentLine ? currentLineAttributes : normalAttributes
            
            let attrString = NSAttributedString(string: lineNumberString, attributes: attributes)
            let stringSize = attrString.size()
            
            // Right-align with padding
            let x = gutterWidth - stringSize.width - 10
            let y = yPosition + (lineRect.height - stringSize.height) / 2
            
            attrString.draw(at: NSPoint(x: x, y: y))
            
            // Move to next line
            lineIndex += 1
            
            // Safety: prevent infinite loop (NSString.lineRange can return the range of the last line when index is at the end of the string)
            let nextIndex = NSMaxRange(lineRange)
            if index == nextIndex { break }
            index = nextIndex
        }
    }
    
    // MARK: - Helpers
    
    /// Calculate the 1-based line number for a character index
    private func lineNumber(for charIndex: Int, in string: String) -> Int {
        let nsString = string as NSString
        let clampedIndex = max(0, min(charIndex, nsString.length))
        
        // Fast line counting
        var count = 1
        let utf16 = string.utf16
        if clampedIndex <= utf16.count {
            let prefix = utf16.prefix(clampedIndex)
            for codeUnit in prefix {
                // 10 is the utf16 code unit for \n
                if codeUnit == 10 {
                    count += 1
                }
            }
        }
        return count
    }
}
