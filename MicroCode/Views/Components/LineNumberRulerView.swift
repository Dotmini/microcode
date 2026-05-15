//
//  LineNumberRulerView.swift
//  MicroCode
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
    private var themeManager: ThemeManager
    
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
        return themeManager.editorGutterTextColor
    }
    
    /// Current line highlight color
    private var currentLineColor: NSColor {
        return themeManager.editorForegroundColor.withAlphaComponent(0.85)
    }
    
    /// Gutter background color
    private var gutterBackgroundColor: NSColor {
        return themeManager.editorGutterColor
    }
    
    /// Separator line color
    private var separatorColor: NSColor {
        return NSColor.separatorColor.withAlphaComponent(0.2)
    }
    
    // MARK: - Init
    
    init(textView: NSTextView, scrollView: NSScrollView, themeManager: ThemeManager) {
        self.textView = textView
        self.themeManager = themeManager
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
        drawBackground(in: rect)

        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let content = textView.string
        let visibleRect = scrollView?.contentView.bounds ?? textView.visibleRect
        let currentLineNumber = lineNumber(for: textView.selectedRange().location, in: content)
        let normalAttributes = lineNumberAttributes(isCurrentLine: false)
        let currentLineAttributes = lineNumberAttributes(isCurrentLine: true)

        if content.isEmpty {
            drawLineNumber(
                1,
                y: textView.textContainerOrigin.y - visibleRect.origin.y,
                lineHeight: defaultLineHeight(for: textView),
                attributes: currentLineNumber == 1 ? currentLineAttributes : normalAttributes
            )
            return
        }

        layoutManager.ensureLayout(for: textContainer)

        let glyphCount = layoutManager.numberOfGlyphs
        guard glyphCount > 0 else {
            drawLineNumber(
                1,
                y: textView.textContainerOrigin.y - visibleRect.origin.y,
                lineHeight: defaultLineHeight(for: textView),
                attributes: currentLineNumber == 1 ? currentLineAttributes : normalAttributes
            )
            return
        }

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.location < glyphCount else { return }

        var drawnLines = Set<Int>()
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
            guard lineGlyphRange.location < glyphCount else { return }

            let charIndex = layoutManager.characterIndexForGlyph(at: lineGlyphRange.location)
            let line = self.lineNumber(for: charIndex, in: content)
            guard drawnLines.insert(line).inserted else { return }

            let yPosition = usedRect.origin.y + textView.textContainerOrigin.y - visibleRect.origin.y
            let attributes = line == currentLineNumber ? currentLineAttributes : normalAttributes
            self.drawLineNumber(line, y: yPosition, lineHeight: usedRect.height, attributes: attributes)
        }

        drawTrailingEmptyLineIfNeeded(
            content: content,
            layoutManager: layoutManager,
            textView: textView,
            visibleRect: visibleRect,
            currentLineNumber: currentLineNumber,
            normalAttributes: normalAttributes,
            currentLineAttributes: currentLineAttributes
        )
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

    private func drawBackground(in rect: NSRect) {
        gutterBackgroundColor.setFill()
        rect.fill()

        separatorColor.setStroke()
        let separatorPath = NSBezierPath()
        separatorPath.move(to: NSPoint(x: bounds.maxX - 0.5, y: rect.minY))
        separatorPath.line(to: NSPoint(x: bounds.maxX - 0.5, y: rect.maxY))
        separatorPath.lineWidth = 0.5
        separatorPath.stroke()
    }

    private func lineNumberAttributes(isCurrentLine: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: isCurrentLine
                ? NSFont.monospacedDigitSystemFont(ofSize: lineNumberFont.pointSize, weight: .medium)
                : lineNumberFont,
            .foregroundColor: isCurrentLine ? currentLineColor : lineNumberColor
        ]
    }

    private func drawLineNumber(_ lineNumber: Int, y: CGFloat, lineHeight: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let attrString = NSAttributedString(string: "\(lineNumber)", attributes: attributes)
        let stringSize = attrString.size()
        let x = gutterWidth - stringSize.width - 10
        let adjustedY = y + (lineHeight - stringSize.height) / 2
        attrString.draw(at: NSPoint(x: x, y: adjustedY))
    }

    private func drawTrailingEmptyLineIfNeeded(
        content: String,
        layoutManager: NSLayoutManager,
        textView: NSTextView,
        visibleRect: NSRect,
        currentLineNumber: Int,
        normalAttributes: [NSAttributedString.Key: Any],
        currentLineAttributes: [NSAttributedString.Key: Any]
    ) {
        guard content.hasSuffix("\n") else { return }

        let line = content.components(separatedBy: "\n").count
        let extraRect = layoutManager.extraLineFragmentRect
        let lineHeight = defaultLineHeight(for: textView)
        let yPosition: CGFloat

        if !extraRect.isEmpty {
            yPosition = extraRect.origin.y + textView.textContainerOrigin.y - visibleRect.origin.y
        } else {
            yPosition = textView.textContainerOrigin.y + CGFloat(line - 1) * lineHeight - visibleRect.origin.y
        }

        guard yPosition + lineHeight >= 0 && yPosition <= visibleRect.height else { return }

        let attributes = line == currentLineNumber ? currentLineAttributes : normalAttributes
        drawLineNumber(line, y: yPosition, lineHeight: lineHeight, attributes: attributes)
    }

    private func defaultLineHeight(for textView: NSTextView) -> CGFloat {
        guard let font = textView.font else { return 16 }
        return textView.layoutManager?.defaultLineHeight(for: font) ?? max(16, font.boundingRectForFont.height)
    }
}
