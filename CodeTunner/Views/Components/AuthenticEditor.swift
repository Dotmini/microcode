import SwiftUI
import AppKit
import CodeTunnerSupport

struct AuthenticEditor: NSViewRepresentable {
    @Binding var text: String
    var language: String
    var font: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        // Create the text system stack manually for full control
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer(size: CGSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.autoresizingMask = [.width, .height]
        textView.delegate = context.coordinator
        
        // Configure Editor Properties
        textView.isRichText = false // Plain text mode for code
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = font
        textView.backgroundColor = PlaygroundsColors.background
        textView.textColor = PlaygroundsColors.text
        textView.insertionPointColor = .white
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor,
            .foregroundColor: NSColor.white
        ]
        
        // Set initial text
        textView.string = text
        
        // Setup Line Numbers Ruler (Native ObjC++)
        let rulerView = AuthenticLineNumberRuler(scrollView: scrollView, orientation: .verticalRuler)
        scrollView.verticalRulerView = rulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        
        // Initial highlight
        context.coordinator.highlight(textView.textStorage, language: language)
        
        scrollView.documentView = textView
        
        // Update Coordinator with the text storage to observe changes if needed
        // but delegate textDidChange is enough for binding updates.
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        if textView.string != text {
            // Keep selection if possible
            let selectedRanges = textView.selectedRanges
            textView.string = text
            // Highlight again because replacing string clears attributes
            context.coordinator.highlight(textView.textStorage, language: language)
            
            // Restore selection if valid
            if let firstRange = selectedRanges.first?.rangeValue,
               firstRange.upperBound <= text.count {
                textView.selectedRanges = selectedRanges
            }
        }
        
        // Update Helper: Apply Theme to Ruler
        if let ruler = nsView.verticalRulerView as? AuthenticLineNumberRuler {
            let theme = ThemeManager.shared
            ruler.backgroundColor = theme.editorGutterColor
            ruler.textColor = theme.editorGutterTextColor
            ruler.separatorColor = theme.editorForegroundColor.withAlphaComponent(0.1)
            // Force redraw if needed
            ruler.needsDisplay = true
        }
        
        // Update language if changed (re-highlight)
        if context.coordinator.currentLanguage != language {
            context.coordinator.currentLanguage = language
            context.coordinator.highlight(textView.textStorage, language: language)
        }
    }
    
    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AuthenticEditor
        var currentLanguage: String
        
        // The Brain (Native ObjC++)
        var languageCore: AuthenticLanguageCore?
        
        // Performance: Debounce timer + dirty tracking
        private var highlightWorkItem: DispatchWorkItem?
        private var lastHighlightedText: String = ""
        private var isHighlighting = false
        
        init(_ parent: AuthenticEditor) {
            self.parent = parent
            self.currentLanguage = parent.language
            super.init()
            
            // Initialize Core
            self.languageCore = AuthenticLanguageCore(language: currentLanguage)
        }
        
        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            // 1. Update Binding (always immediate)
            parent.text = textView.string
            
            // 2. Invalidate ruler (cheap)
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
            
            // 3. Debounced highlight — 150ms after last keystroke
            highlightWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.performHighlight(textView)
            }
            highlightWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }
        
        private func performHighlight(_ textView: NSTextView) {
            guard !isHighlighting else { return }
            isHighlighting = true
            defer { isHighlighting = false }
            
            let text = textView.string
            
            // Skip if nothing changed
            guard text != lastHighlightedText else { return }
            lastHighlightedText = text
            
            highlight(textView.textStorage, language: currentLanguage, textView: textView)
        }
        
        func highlight(_ textStorage: NSTextStorage?, language: String, textView: NSTextView? = nil) {
            guard let textStorage = textStorage else { return }
            
            // Re-init core if language changed
            if language != currentLanguage || languageCore == nil {
                currentLanguage = language
                languageCore = AuthenticLanguageCore(language: language)
                languageCore?.updateSource(textStorage.string)
            }
            
            guard let core = languageCore else { return }
            
            // Ensure core is up to date
            core.updateSource(textStorage.string)
            
            // Get Native Tokens
            let tokens = core.tokens() ?? []
            
            // Calculate visible range for partial highlighting
            let highlightRange: NSRange
            if let tv = textView,
               let clipView = tv.enclosingScrollView?.contentView {
                let visibleRect = clipView.documentVisibleRect
                // Add generous padding (2x visible height) for smooth scrolling
                let paddedRect = visibleRect.insetBy(dx: 0, dy: -visibleRect.height)
                let glyphRange = tv.layoutManager?.glyphRange(forBoundingRect: paddedRect, in: tv.textContainer!) ?? NSRange(location: 0, length: textStorage.length)
                let charRange = tv.layoutManager?.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil) ?? NSRange(location: 0, length: textStorage.length)
                highlightRange = charRange
            } else {
                highlightRange = NSRange(location: 0, length: textStorage.length)
            }
            
            // Apply attributes only in visible range
            textStorage.beginEditing()
            
            // Reset base for visible range only
            textStorage.removeAttribute(.foregroundColor, range: highlightRange)
            textStorage.addAttributes([
                .foregroundColor: PlaygroundsColors.text,
                .font: parent.font
            ], range: highlightRange)
            
            // Apply token colors (only those in visible range)
            applyNativeTokens(tokens, to: textStorage, visibleRange: highlightRange)
            
            // Apply Hex Colors only in visible range + only for small files (< 50KB)
            if textStorage.length < 50000 {
                applyHexColorHighlighting(to: textStorage, inRange: highlightRange)
            }
            
            textStorage.endEditing()
        }
        
        private func applyNativeTokens(_ tokens: [AuthenticToken], to storage: NSTextStorage, visibleRange: NSRange) {
            let strLen = storage.length
            let visEnd = visibleRange.location + visibleRange.length
            
            for token in tokens {
                let range = token.range
                // Skip tokens outside visible range
                if range.location + range.length < visibleRange.location { continue }
                if range.location > visEnd { break } // tokens are ordered, can stop early
                
                if range.location + range.length <= strLen {
                    let color = colorForTokenType(token.type)
                    storage.addAttribute(.foregroundColor, value: color, range: range)
                }
            }
        }
        
        private func applyHexColorHighlighting(to textStorage: NSTextStorage, inRange range: NSRange) {
            let string = textStorage.string
            let hexPattern = "#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\\b"
            
            // Clamp range to valid bounds
            let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
            guard safeRange.length > 0 else { return }
            
            if let regex = try? NSRegularExpression(pattern: hexPattern, options: []) {
                regex.enumerateMatches(in: string, options: [], range: safeRange) { match, _, _ in
                    guard let matchRange = match?.range else { return }
                    let nsString = string as NSString
                    let hexString = nsString.substring(with: matchRange)
                    
                    guard let color = NSColor(hexString: hexString) else { return }
                    textStorage.addAttribute(.backgroundColor, value: color, range: matchRange)
                    
                    guard let rgb = color.usingColorSpace(.genericRGB) else { return }
                    let r: CGFloat = rgb.redComponent
                    let g: CGFloat = rgb.greenComponent
                    let b: CGFloat = rgb.blueComponent
                    let brightness: CGFloat = ((r * 299) + (g * 587) + (b * 114)) / 1000
                    let textColor: NSColor = (brightness > 0.5) ? NSColor.black : NSColor.white
                    textStorage.addAttribute(.foregroundColor, value: textColor, range: matchRange)
                }
            }
        }
        
        private func colorForTokenType(_ type: AuthenticTokenType) -> NSColor {
            switch type {
            case .keyword, .keywordControl, .keywordModifier: return PlaygroundsColors.keyword
            case .keywordDeclaration: return PlaygroundsColors.keyword
            case .string: return PlaygroundsColors.string
            case .number: return PlaygroundsColors.number
            case .comment: return PlaygroundsColors.comment
            case .type: return PlaygroundsColors.type
            case .function: return PlaygroundsColors.function
            case .identifier: return PlaygroundsColors.text
            case .operator: return PlaygroundsColors.text
            case .punctuation: return PlaygroundsColors.text
            case .preprocessor: return PlaygroundsColors.keyword 
            case .URL: return PlaygroundsColors.string
            case .unknown: return PlaygroundsColors.text
            @unknown default: return PlaygroundsColors.text
            }
        }
    }
}

// Helper for Color Parsing
extension NSColor {
    convenience init?(hexString: String) {
        var cString: String = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if (cString.hasPrefix("#")) {
            cString.remove(at: cString.startIndex)
        }
        
        if ((cString.count) != 6 && (cString.count) != 3) {
            return nil
        }
        
        // Expansion of 3-digit hex
        if cString.count == 3 {
            let r = cString[cString.startIndex]
            let g = cString[cString.index(cString.startIndex, offsetBy: 1)]
            let b = cString[cString.index(cString.startIndex, offsetBy: 2)]
            cString = "\(r)\(r)\(g)\(g)\(b)\(b)"
        }
        
        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)
        
        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: CGFloat(1.0)
        )
    }
}

