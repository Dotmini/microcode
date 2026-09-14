//
//  LineNumberRulerView.swift
//  MicroCode
//
//  Professional line number gutter for NSTextView
//  Uses NSRulerView for native macOS integration
//
//  Copyright © 2025 Dotmini Company Limited
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

// MARK: - Safe Overlay Gutter

/// Line-number gutter that overlays the editor instead of participating in
/// `NSScrollView` ruler layout. The old `NSRulerView` implementation changed
/// the clip-view origin and could enter a SwiftUI/AppKit layout cycle.
///
/// This view draws only visible line fragments, owns cancellable notification
/// tokens, and never changes intrinsic content size.
final class EditorLineNumberGutterView: NSView {
    static let preferredWidth: CGFloat = 58

    private weak var textView: NSTextView?
    private weak var clipView: NSClipView?
    private var themeManager: ThemeManager
    private var observers: [NSObjectProtocol] = []
    private var pendingIndexRebuild: DispatchWorkItem?
    private var lineStarts: [Int] = [0]
    private var lineIndexIsComplete = true
    private let maximumIndexedLines = 250_000

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    init(textView: NSTextView, clipView: NSClipView, themeManager: ThemeManager) {
        self.textView = textView
        self.clipView = clipView
        self.themeManager = themeManager
        super.init(frame: .zero)

        autoresizingMask = [.height]
        clipView.postsBoundsChangedNotifications = true
        rebuildLineIndex()

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleIndexRebuild()
        })
        observers.append(center.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        })
        observers.append(center.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        })
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        detach()
    }

    /// Explicit teardown is required because cached editor views can toggle
    /// the gutter repeatedly without being deallocated.
    func detach() {
        pendingIndexRebuild?.cancel()
        pendingIndexRebuild = nil
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    func updateAppearance(themeManager: ThemeManager) {
        self.themeManager = themeManager
        needsDisplay = true
    }

    /// Programmatic `NSTextStorage` replacement does not emit
    /// `NSText.didChangeNotification`. The SwiftUI bridge calls this after it
    /// installs file content so cached editors never keep the initial `[0]`
    /// line index created while the text view was empty.
    func refreshContentIndex() {
        pendingIndexRebuild?.cancel()
        pendingIndexRebuild = nil
        rebuildLineIndex()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Keep the overlay visual-only. Selection and scrolling continue to be
        // handled by the underlying NSTextView/NSScrollView.
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        themeManager.editorGutterColor.setFill()
        bounds.fill()

        NSColor.separatorColor.withAlphaComponent(0.22).setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        separator.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        separator.lineWidth = 0.5
        separator.stroke()

        guard let textView,
              let clipView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = clipView.bounds
        let fontSize = max(9, (textView.font?.pointSize ?? 13) - 2)
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: themeManager.editorGutterTextColor
        ]
        let activeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: themeManager.editorForegroundColor.withAlphaComponent(0.86)
        ]
        let currentLine = lineNumber(for: textView.selectedRange().location)

        if textView.string.isEmpty {
            drawLineNumber(1, y: textView.textContainerOrigin.y - visibleRect.minY,
                           height: defaultLineHeight(for: textView), attributes: activeAttributes)
            return
        }

        // Asking only for the visible glyph range avoids forcing TextKit to
        // lay out the entire document when the user scrolls.
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.location != NSNotFound,
              glyphRange.location < layoutManager.numberOfGlyphs else { return }

        var drawnLines = Set<Int>()
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
            [weak self] _, usedRect, _, fragmentGlyphRange, _ in
            guard let self,
                  fragmentGlyphRange.location < layoutManager.numberOfGlyphs else { return }
            let characterIndex = layoutManager.characterIndexForGlyph(at: fragmentGlyphRange.location)
            guard let number = self.lineNumber(for: characterIndex),
                  drawnLines.insert(number).inserted else { return }
            let y = usedRect.minY + textView.textContainerOrigin.y - visibleRect.minY
            self.drawLineNumber(
                number,
                y: y,
                height: usedRect.height,
                attributes: number == currentLine ? activeAttributes : normalAttributes
            )
        }
    }

    private func scheduleIndexRebuild() {
        pendingIndexRebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rebuildLineIndex()
            self?.needsDisplay = true
        }
        pendingIndexRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func rebuildLineIndex() {
        guard let content = textView?.string else {
            lineStarts = [0]
            lineIndexIsComplete = true
            return
        }

        var starts = [0]
        starts.reserveCapacity(min(maximumIndexedLines, max(16, content.count / 32)))
        var utf16Offset = 0
        var complete = true
        for codeUnit in content.utf16 {
            utf16Offset += 1
            if codeUnit == 10 {
                guard starts.count < maximumIndexedLines else {
                    complete = false
                    break
                }
                starts.append(utf16Offset)
            }
        }
        lineStarts = starts
        lineIndexIsComplete = complete
    }

    /// Binary-search cached UTF-16 line starts. Returning nil beyond the hard
    /// cache limit is safer than allocating unbounded memory for pathological
    /// files containing hundreds of thousands of empty lines.
    private func lineNumber(for characterIndex: Int) -> Int? {
        guard !lineStarts.isEmpty else { return 1 }
        let index = max(0, characterIndex)
        if !lineIndexIsComplete, index > (lineStarts.last ?? 0) { return nil }

        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= index { low = mid + 1 } else { high = mid }
        }
        return max(1, low)
    }

    private func drawLineNumber(
        _ number: Int,
        y: CGFloat,
        height: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard y + height >= bounds.minY, y <= bounds.maxY else { return }
        let string = NSAttributedString(string: "\(number)", attributes: attributes)
        let size = string.size()
        string.draw(at: NSPoint(
            x: bounds.width - size.width - 9,
            y: y + max(0, (height - size.height) / 2)
        ))
    }

    private func defaultLineHeight(for textView: NSTextView) -> CGFloat {
        guard let font = textView.font else { return 16 }
        return textView.layoutManager?.defaultLineHeight(for: font)
            ?? max(16, font.boundingRectForFont.height)
    }
}
