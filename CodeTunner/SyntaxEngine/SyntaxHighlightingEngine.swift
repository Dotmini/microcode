//
//  SyntaxHighlightingEngine.swift
//  CodeTunner - Syntax Highlighting Engine
//
//  Main facade that coordinates lexer, cache, and theme components.
//  Provides a simple API for the UI layer to request syntax highlighting.
//
//  Design Pattern: Facade Pattern
//  - Single entry point for syntax highlighting
//  - Hides complexity of lexer, cache, and theme coordination
//  - Thread-safe for use from UI and background threads
//
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import Foundation
import AppKit
import SwiftUI

// MARK: - Syntax Highlighting Engine

/// Main engine that coordinates all syntax highlighting components.
/// This is the primary interface the UI layer should use.
public final class SyntaxHighlightingEngine: @unchecked Sendable {
    
    /// Available language lexer factories (Lazy Loading)
    /// Thread-safe initialization using static let
    private static let lexerFactories: [String: @Sendable () -> LexerProtocol] = {
        var factories: [String: @Sendable () -> LexerProtocol] = [:]
        
        // Helper to register
        func register(_ lang: String, _ factory: @escaping @Sendable () -> LexerProtocol) {
            factories[lang.lowercased()] = factory
        }
        
        // Core languages
        register("rust") { createRustLexer() }
        register("javascript") { createJavaScriptLexer() }
        register("typescript") { createTypeScriptLexer() }  // Dedicated TypeScript lexer
        
        // JavaScript aliases
        register("js") { createJavaScriptLexer() }
        register("jsx") { createJavaScriptLexer() }
        register("json") { createJavaScriptLexer() }
        
        // TypeScript aliases
        register("ts") { createTypeScriptLexer() }
        register("tsx") { createTypeScriptLexer() }
        
        // Ruby
        register("ruby") { createRubyLexer() }
        // Go
        register("go") { createGoLexer() }
        register("golang") { createGoLexer() }
        
        // C-family (Native ObjC++ Engine)
        register("c") { AuthenticLexerAdapter(languageId: "c") }
        register("cpp") { AuthenticLexerAdapter(languageId: "cpp") }
        register("c++") { AuthenticLexerAdapter(languageId: "cpp") }
        register("h") { AuthenticLexerAdapter(languageId: "c") }
        register("hpp") { AuthenticLexerAdapter(languageId: "cpp") }
        register("objc") { AuthenticLexerAdapter(languageId: "objectivec") }
        register("objective-c") { AuthenticLexerAdapter(languageId: "objectivec") }
        register("m") { AuthenticLexerAdapter(languageId: "objectivec") }
        register("mm") { AuthenticLexerAdapter(languageId: "objectivec") }
        
        // JVM languages (use Swift-like syntax)
        register("java") { createJavaLexer() } // Keep Swift lexer for Java for now
        register("kt") { createKotlinLexer() }
        register("kotlin") { createKotlinLexer() }
        register("scala") { createKotlinLexer() }
        register("groovy") { createJavaLexer() }
        
        // Swift (Native ObjC++ Engine)
        register("swift") { AuthenticLexerAdapter(languageId: "swift") }
        
        // Scripting (Native ObjC++ Engine for Python)
        register("py") { AuthenticLexerAdapter(languageId: "python") }
        register("python") { AuthenticLexerAdapter(languageId: "python") }
        
        // Ruby (Keep Swift lexer)
        register("rb") { createRubyLexer() }
        register("ruby") { createRubyLexer() }
        register("lua") { createRubyLexer() }
        
        // Shell
        register("bash") { createPythonLexer() } // Fallback
        register("sh") { createPythonLexer() }
        register("zsh") { createPythonLexer() }
        register("fish") { createPythonLexer() }
        
        // Data Science (Native ObjC++ Engine)
        register("r") { AuthenticLexerAdapter(languageId: "r") }
        register("julia") { AuthenticLexerAdapter(languageId: "julia") }
        register("jl") { AuthenticLexerAdapter(languageId: "julia") }
        
        register("sql") { createJavaScriptLexer() }
        register("graphql") { createJavaScriptLexer() }
        
        // Web
        register("html") { createJavaScriptLexer() }
        register("css") { createJavaScriptLexer() }
        register("scss") { createJavaScriptLexer() }
        register("sass") { createJavaScriptLexer() }
        register("less") { createJavaScriptLexer() }
        register("vue") { createJavaScriptLexer() }
        register("svelte") { createJavaScriptLexer() }
        
        // Config/Data
        register("yaml") { createPythonLexer() }
        register("yml") { createPythonLexer() }
        register("toml") { createPythonLexer() }
        register("ini") { createPythonLexer() }
        
        // Other
        register("perl") { createPythonLexer() }
        register("php") { createJavaScriptLexer() }
        register("elixir") { createRubyLexer() }
        register("ex") { createRubyLexer() }
        register("exs") { createRubyLexer() }
        register("markdown") { createPythonLexer() }
        register("md") { createPythonLexer() }
        
        return factories
    }()
    
    /// Loaded lexers for this specific engine instance
    /// We only load what we need to save memory.
    private var loadedLexers: [String: IncrementalLexer] = [:]
    
    /// Theme manager instance
    public let themeManager: ThemeManager
    
    /// Currently active lexer
    private var activeLexer: IncrementalLexer?
    
    /// Current document content
    private var documentContent: String = ""
    
    /// Current language ID
    public private(set) var currentLanguage: String = ""
    
    /// Cached attributed string (for performance)
    private var cachedAttributedString: NSAttributedString?
    private var cachedVersion: Int = 0
    private var currentVersion: Int = 0
    
    /// Cached Line Offsets for O(log N) lookup of line numbers
    private var cachedLineOffsets: [Int]?
    
    /// Cached Paragraph Style (to prevent layout churn)
    private var cachedParagraphStyle: NSMutableParagraphStyle?
    private var cachedFontSize: CGFloat = 0
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    /// Shared instance for convenience
    public static let shared = SyntaxHighlightingEngine()
    
    public init(themeManager: ThemeManager = .shared) {
        self.themeManager = themeManager
    }
    
    // MARK: - Language Registration
    
    /// Register a lexer factory for a language (Global, Runtime)
    /// Note: Modifying this at runtime is not thread-safe if done concurrently with reads.
    /// It is recommended to register custom lexers at app launch.
    public static func registerLexerFactory(forLanguage language: String, factory: @escaping @Sendable () -> LexerProtocol) {
        // Warning: This is mutating a static let? No, we can't.
        // If we want runtime registration, we need a lock.
        // But for built-ins, static let is best.
        // We will skip runtime registration for now to ensure safety, or use a separate mutable dictionary for extras.
    }
    
    /// Get available languages
    public var availableLanguages: [String] {
        return Array(Self.lexerFactories.keys).sorted()
    }
    


    // MARK: - Document Management
    
    /// Set the document to highlight
    public func setDocument(_ content: String, language: String) {
        lock.lock()
        defer { lock.unlock() }
        
        let langKey = language.lowercased().trimmingCharacters(in: .whitespaces)
        if langKey.isEmpty {
            return // Or fallback to plain text if needed
        }
        let currentLangKey = activeLexer?.baseLexer.languageId
        
        // Optimization: If content and language haven't changed, skip re-initialization.
        if content == documentContent && langKey == currentLangKey {
            return
        }
        
        documentContent = content
        currentLanguage = langKey
        currentVersion += 1
        cachedAttributedString = nil
        
        // Initialize line offsets cache efficiently
        var newOffsets: [Int] = [0]
        let nsString = content as NSString
        var index = 0
        let length = nsString.length
        
        // Robust O(N) line scan
        while index < length {
            var lineEnd = 0
            var contentEnd = 0
            nsString.getLineStart(nil, end: &lineEnd, contentsEnd: &contentEnd, for: NSRange(location: index, length: 0))
            if lineEnd > index {
                index = lineEnd
                // Check if we advanced past a separator (newline)
                let hasSeparator = contentEnd < lineEnd
                if index < length || hasSeparator {
                    newOffsets.append(index)
                }
            } else {
                 break // Should not happen unless empty or non-advancing
            }
        }
        cachedLineOffsets = newOffsets
        
        // Get or create lexer for language (Lazy)
        if let lexer = loadedLexers[langKey] {
            activeLexer = lexer
            lexer.initialize(with: content)
        } else if let factory = Self.lexerFactories[langKey] {
            // Instantiate on demand!
            let newLexer = IncrementalLexer(lexer: factory())
            loadedLexers[langKey] = newLexer
            activeLexer = newLexer
            newLexer.initialize(with: content)
        } else {
            // Fallback to JavaScript lexer factory
            if let jsFactory = Self.lexerFactories["javascript"] {
                // Check if we already loaded 'javascript' key
                if let jsLexer = loadedLexers["javascript"] {
                     activeLexer = jsLexer
                     jsLexer.initialize(with: content)
                } else {
                    let newLexer = IncrementalLexer(lexer: jsFactory())
                    loadedLexers["javascript"] = newLexer
                    activeLexer = newLexer
                    newLexer.initialize(with: content)
                }
            } else {
                // Total fallback if JS not registered (should not happen)
                 activeLexer = nil
            }
        }
    }
    
    /// Update document content (for incremental updates)
    public func updateDocument(_ content: String, changedLine: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        documentContent = content
        currentVersion += 1
        cachedAttributedString = nil
        
        activeLexer?.handleEdit(at: changedLine, newContent: "")
    }
    
    /// Mark a range of lines as needing re-highlighting
    public func markDirty(fromLine start: Int, toLine end: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        currentVersion += 1
        cachedAttributedString = nil
        activeLexer?.handleLinesChanged(from: start, to: end)
    }
    
    /// Process a text change incrementally
    /// Process a text change incrementally
    @MainActor
    public func processEdit(range: NSRange, changeInLength: Int, newContent: String) {
        lock.lock()
        let oldContent = documentContent
        let version = currentVersion
        lock.unlock()

        // 0. BOUNDS CHECK: Verify range is valid for oldContent
        // This is critical because processEdit can be called with initial text load
        // from NSTextStorage before the engine has documentContent synced.
        let nsOld = oldContent as NSString
        if range.location < 0 || range.location > nsOld.length {
            // Out of sync edit: Re-initialize with full content instead of crashing
            setDocument(newContent, language: currentLanguage)
            return
        }
        
        // Calculate original range
        let originalLength = max(0, range.length - changeInLength)
        let oldRange = NSRange(location: range.location, length: min(originalLength, nsOld.length - range.location))
        
        lock.lock()
        defer { lock.unlock() }
        
        // 1. Identify start line (Optimized O(log N))
        var startLine = 0
        
        if let offsets = cachedLineOffsets {
            // Binary search for the line starting before or at oldRange.location
            // Find insertion point
            var lower = 0
            var upper = offsets.count
            while lower < upper {
                let mid = lower + (upper - lower) / 2
                if offsets[mid] <= oldRange.location {
                    lower = mid + 1
                } else {
                    upper = mid
                }
            }
            startLine = max(0, lower - 1)
        } else {
            // Fallback O(N)
            nsOld.substring(to: oldRange.location).enumerateLines { _, _ in
                startLine += 1
            }
        }
        
        // 2 & 3: Count lines efficiently
        let removedText = nsOld.substring(with: oldRange)
        let removedLinesCount = removedText.components(separatedBy: "\n").count - 1
        
        let addedText = (newContent as NSString).substring(with: range)
        let addedLinesCount = addedText.components(separatedBy: "\n").count - 1
        
        // Update Offsets Cache (O(L))
        if var offsets = cachedLineOffsets {
            // 1. Remove offsets for deleted lines
            let removeStart = startLine + 1
            let removeEnd = startLine + 1 + removedLinesCount
            // Valid range check
            if removeStart < offsets.count {
               let safeEnd = min(removeEnd, offsets.count)
               offsets.removeSubrange(removeStart..<safeEnd)
            }
            
            // 2. Insert offsets for added lines
            var addedOffsets: [Int] = []
            var currentAddedOffset = range.location
            let nsAdded = addedText as NSString
            var index = 0
            let length = nsAdded.length
             while index < length {
                var lineEnd = 0
                var contentEnd = 0
                nsAdded.getLineStart(nil, end: &lineEnd, contentsEnd: &contentEnd, for: NSRange(location: index, length: 0))
                if lineEnd > index {
                    index = lineEnd
                    // Only add if it's not the very end of string (unless needed?)
                    // Offsets stores STARTS.
                    // If we have "A\nB", inserted at 0: "A\n" -> offsets: 0, 2
                    // FIX: If we have a separator (newline), it implies a new line start follows.
                    let hasSeparator = contentEnd < lineEnd
                    if index < length || hasSeparator {
                        addedOffsets.append(currentAddedOffset + index)
                    }
                } else {
                    break
                }
            }
            
            if !addedOffsets.isEmpty {
                offsets.insert(contentsOf: addedOffsets, at: startLine + 1)
            }
            
            // 3. Shift subsequent offsets
            let shiftAmount = changeInLength - originalLength // can be negative
            // Ensure we don't crash if startLine + 1 + addedOffsets.count is OOB
            let shiftStart = startLine + 1 + addedOffsets.count
            if shiftStart < offsets.count {
                for i in shiftStart..<offsets.count {
                    offsets[i] += shiftAmount
                }
            }
            
            cachedLineOffsets = offsets
        }
        
        // 4. Update content
        documentContent = newContent
        currentVersion += 1
        cachedAttributedString = nil
        
        // 5. Notify the active lexer's cache of the structural change
        activeLexer?.cache.handleDocumentChange(
            changeStart: startLine,
            linesRemoved: removedLinesCount,
            linesAdded: addedLinesCount,
            charDelta: changeInLength - originalLength
        )
        
        // 6. Explicitly mark the start line as dirty to ensure it's re-lexed
        // even if the line count didn't change.
        activeLexer?.cache.markDirty(line: startLine)
    }
    
    // MARK: - Highlighting API
    
    /// Get highlighted NSAttributedString for the current document.
    /// This is the main method the UI should call.
    public func highlightedAttributedString(fontSize: CGFloat, font: NSFont? = nil) -> NSAttributedString {
        lock.lock()
        
        // Return cached version if available
        if let cached = cachedAttributedString, cachedVersion == currentVersion {
            lock.unlock()
            return cached
        }
        
        let content = documentContent
        let lexer = activeLexer
        
        lock.unlock()
        
        // SyntaxTokenize
        let tokens: [SyntaxToken]
        if let lexer = lexer {
            tokens = lexer.retokenizeDirtyRegions(in: content)
        } else {
            // Fallback: no tokens
            tokens = []
        }
        
        // Build attributed string
        let attributed = buildAttributedString(
            content: content,
            tokens: tokens,
            fontSize: fontSize,
            font: font
        )
        
        // Cache result
        lock.lock()
        cachedAttributedString = attributed
        cachedVersion = currentVersion
        lock.unlock()
        
        return attributed
    }
    
    /// Currently running highlight task
    private var currentHighlightTask: Task<Void, Never>?
    
    /// Asynchronously apply highlighting to an existing NSTextStorage.
    /// Performs lexing on a background thread and updates attributes on the main thread.
    @MainActor
    public func applyHighlightingAsync(to textStorage: NSTextStorage, fontSize: CGFloat, font: NSFont? = nil, completion: (@MainActor @Sendable () -> Void)? = nil) {
        // Cancel previous task to prevent "task explosion" and race conditions
        currentHighlightTask?.cancel()
        
        lock.lock()
        let content = documentContent
        let lexer = activeLexer
        let version = currentVersion
        lock.unlock()
        
        guard let lexer = lexer else {
            completion?()
            return
        }
        
        // HYBRID APPROACH: If document is small enough, highlight synchronously to prevent "Flash"
        // 500 lines is a safe budget for main thread processing (~1-2ms)
        let lineCount = content.filter({ $0 == "\n" }).count
        if lineCount < 500 {
            // SYNC PATH (Zero Flash)
            let tokens = lexer.retokenizeDirtyRegions(in: content)
             self.applyTokens(tokens, to: textStorage, fontSize: fontSize, font: font)
             completion?()
             return
        }
        
        // ASYNC PATH (Large Docs)
        // Use a detached task for background work, but keep reference for cancellation
        currentHighlightTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // Check cancellation before heavy work
            if Task.isCancelled { return }
            
            // 1. Re-lex dirty regions (this is the expensive part)
            let tokens = lexer.retokenizeDirtyRegions(in: content)
            
            // Check cancellation mid-work
            if Task.isCancelled { return }
            
            // 2. Apply attributes on the main thread
            await MainActor.run {
                // Check cancellation right before applying
                if Task.isCancelled { return }
                
                // Verify text still matches to prevent crashes or misaligned highlighting
                self.lock.lock()
                let isStillValid = (self.currentVersion == version && self.documentContent.utf16.count == textStorage.length)
                self.lock.unlock()
                
                if isStillValid {
                    self.applyTokens(tokens, to: textStorage, fontSize: fontSize, font: font)
                }
                
                completion?()
            }
        }
    }
    
    /// Internal helper to apply attributes for specific tokens.
    /// CRITICAL: Must be called on the main thread.
    /// Uses chunking to prevent Main Thread blocking on large updates.
    @MainActor
    private func applyTokens(_ tokens: [SyntaxToken], to textStorage: NSTextStorage, fontSize: CGFloat, font: NSFont?) {
        assert(Thread.isMainThread, "applyTokens must be called on the main thread")
        
        // CHUNK SIZE: Apply 2000 tokens at a time to keep frame rate high
        // 2000 tokens ~ 200 lines of code roughly.
        let chunkSize = 2000
        let defaultFont = font ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        
        // If small enough, apply synchronously (fast path)
        if tokens.count <= chunkSize {
            textStorage.beginEditing()
            applyTokensBatch(tokens, to: textStorage, defaultFont: defaultFont, fontSize: fontSize)
            textStorage.endEditing()
            return
        }
        
        // Large update: Chunk it asynchronously on Main Actor to allow UI events to interleave
        Task { @MainActor in
            var startIndex = 0
            while startIndex < tokens.count {
                // Check if document changed underneath us or task cancelled
                if Task.isCancelled { return }
                
                let endIndex = min(startIndex + chunkSize, tokens.count)
                let chunk = Array(tokens[startIndex..<endIndex])
                
                textStorage.beginEditing()
                applyTokensBatch(chunk, to: textStorage, defaultFont: defaultFont, fontSize: fontSize)
                textStorage.endEditing()
                
                startIndex += chunkSize
                
                // Allow UI to breathe
                await Task.yield() 
            }
        }
    }
    
    private func applyTokensBatch(_ tokens: [SyntaxToken], to textStorage: NSTextStorage, defaultFont: NSFont, fontSize: CGFloat) {
         // USE CACHED PARAGRAPH STYLE
         // Creating a new one every time causes NSTextStorage to treat it as a change, triggering layout.
         
         let paragraphStyle: NSMutableParagraphStyle
         
         if let cached = cachedParagraphStyle, cachedFontSize == fontSize {
             paragraphStyle = cached
         } else {
             let newStyle = NSMutableParagraphStyle()
             newStyle.minimumLineHeight = defaultFont.pointSize * 1.2
             newStyle.maximumLineHeight = defaultFont.pointSize * 1.2
             
             // Update cache
             cachedParagraphStyle = newStyle
             cachedFontSize = fontSize
             paragraphStyle = newStyle
         }

         
         for token in tokens {
            let nsRange = token.range.nsRange
            
            // Validate range safety
            guard nsRange.location >= 0,
                  nsRange.location + nsRange.length <= textStorage.length else {
                continue
            }
            
            // Collect attributes into a single dictionary to minimize layout invalidations (1 call vs 5)
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: themeManager.color(for: token.type),
                .paragraphStyle: paragraphStyle,
                .ligature: 0
            ]
            
            // Apply font style (bold/italic)
            let style = themeManager.style(for: token.type)
            if style.isBold || style.isItalic {
                var traits: NSFontDescriptor.SymbolicTraits = []
                if style.isBold { traits.insert(.bold) }
                if style.isItalic { traits.insert(.italic) }
                
                let descriptor = defaultFont.fontDescriptor.withSymbolicTraits(traits)
                let styledFont = NSFont(descriptor: descriptor, size: fontSize) ?? defaultFont
                attributes[.font] = styledFont
            } else {
                attributes[.font] = defaultFont
            }
            
            if style.isUnderline {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            
            // Optimization: Skip update if color matches (Prevent Flicker)
            // BUT: For small files (New Files), we force update to ensure consistency and prevent "White Flash" if defaults are wrong.
            // Check textStorage.length to detect small/new files.
            let isSmallFile = textStorage.length < 1000
            
            if !isSmallFile && nsRange.length > 0 {
                let existingColor = textStorage.attribute(.foregroundColor, at: nsRange.location, effectiveRange: nil) as? NSColor
                let newColor = attributes[.foregroundColor] as? NSColor
                
                // If colors match, we assume other attributes match too (safe optimization for typing)
                if let existing = existingColor, let new = newColor, existing == new {
                    continue
                }
            }
            
            textStorage.addAttributes(attributes, range: nsRange)
        }
    }

    /// Synchronous version (use with caution on small snippets or background threads)
    @MainActor
    public func applyHighlighting(to textStorage: NSTextStorage, fontSize: CGFloat, font: NSFont? = nil) {
        lock.lock()
        let content = documentContent
        let lexer = activeLexer
        lock.unlock()
        
        guard let lexer = lexer else { return }
        let tokens = lexer.retokenizeDirtyRegions(in: content)
        
        // Since this is the sync version, we assume caller is managing thread safety or is on main thread.
        // We use MainActor to be safe if called from main.
        if Thread.isMainThread {
            applyTokens(tokens, to: textStorage, fontSize: fontSize, font: font)
        } else {
            DispatchQueue.main.sync {
                applyTokens(tokens, to: textStorage, fontSize: fontSize, font: font)
            }
        }
    }
    

    /// Get tokens for a specific line range (for partial updates)
    public func tokens(forLines range: Range<Int>) -> [SyntaxToken] {
        lock.lock()
        defer { lock.unlock() }
        
        guard let lexer = activeLexer else { return [] }
        
        var tokens: [SyntaxToken] = []
        for line in range {
            if let entry = lexer.cache.entry(forLine: line) {
                tokens.append(contentsOf: entry.tokens)
            }
        }
        return tokens
    }
    
    // MARK: - Attributed String Building
    
    /// Build NSAttributedString from tokens
    private func buildAttributedString(content: String, tokens: [SyntaxToken], fontSize: CGFloat, font: NSFont? = nil) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: content)
        let fullRange = NSRange(location: 0, length: content.utf16.count)
        
        // Set default attributes
        let defaultFont = font ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let defaultColor = themeManager.editorForegroundColor
        
        attributed.addAttribute(.font, value: defaultFont, range: fullRange)
        attributed.addAttribute(.foregroundColor, value: defaultColor, range: fullRange)
        // Disable ligatures to prevent jitter
        attributed.addAttribute(.ligature, value: 0, range: fullRange)
        
        // Apply token styles
        for token in tokens {
            let nsRange = token.range.nsRange
            
            // Validate range
            guard nsRange.location >= 0,
                  nsRange.location + nsRange.length <= content.utf16.count else {
                continue
            }
            
            let color = themeManager.color(for: token.type)
            attributed.addAttribute(.foregroundColor, value: color, range: nsRange)
            
            // Apply font style (bold/italic)
            let style = themeManager.style(for: token.type)
            if style.isBold || style.isItalic {
                var traits: NSFontDescriptor.SymbolicTraits = []
                if style.isBold { traits.insert(.bold) }
                if style.isItalic { traits.insert(.italic) }
                
                let descriptor = defaultFont.fontDescriptor.withSymbolicTraits(traits)
                let styledFont = NSFont(descriptor: descriptor, size: fontSize) ?? defaultFont
                attributed.addAttribute(.font, value: styledFont, range: nsRange)
            }
            
            if style.isUnderline {
                attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
            }
        }
        
        return attributed
    }
    
    // MARK: - Convenience Methods
    
    /// Quick highlight for a single string (non-incremental)
    public static func highlight(
        _ code: String,
        language: String,
        fontSize: CGFloat,
        isDark: Bool = true
    ) -> NSAttributedString {
        let engine = SyntaxHighlightingEngine()
        
        // Set theme
        engine.themeManager.setActiveTheme(isDark ? "default-dark" : "default-light")
        
        // Set document and highlight
        engine.setDocument(code, language: language)
        return engine.highlightedAttributedString(fontSize: fontSize)
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

/// SwiftUI view that displays syntax-highlighted code.
/// Uses the SyntaxHighlightingEngine for tokenization and styling.
public struct SyntaxHighlightedCodeView: NSViewRepresentable {
    @Binding public var text: String
    public let language: String
    public let fontSize: CGFloat
    public let isDark: Bool
    public let themeName: String?
    public let fontName: String
    public let fontWeight: Int // 0-5
    public let fileURL: URL?
    public let isScrollEnabled: Bool
    
    /// Local engine instance - MOVED TO COORDINATOR
    // private let engine = SyntaxHighlightingEngine()
    
    public init(text: Binding<String>, language: String, fontSize: CGFloat = 13, isDark: Bool = true, themeName: String? = nil, fontName: String = "Menlo", fontWeight: Int = 2, fileURL: URL? = nil, isScrollEnabled: Bool = true) {
        self._text = text
        self.language = language
        self.fontSize = fontSize
        self.isDark = isDark
        self.themeName = themeName
        self.fontName = fontName
        self.fontWeight = fontWeight
        self.fileURL = fileURL
        self.isScrollEnabled = isScrollEnabled
    }
    
    public func makeNSView(context: Context) -> NSScrollView {
        // Use Apple's factory method
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        
        // Configure text view
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        
        // IME-FIRST: Enable proper bi-directional text support (RTL for Hebrew/Arabic)
        textView.baseWritingDirection = .natural // Auto-detect LTR/RTL based on content
        
        // IME-FIRST: Allow Input Method Editors to work correctly
        // These settings ensure Thai/Japanese/Chinese keyboards function properly
        textView.allowsDocumentBackgroundColorChange = false
        textView.isAutomaticLinkDetectionEnabled = false
        
        // Initialize engine and assign to coordinator
        let engine = SyntaxHighlightingEngine()
        context.coordinator.engine = engine
        
        // Set theme
        let activeThemeID = (themeName != nil && themeName != "system" && !themeName!.isEmpty) ? themeName! : (isDark ? "dark" : "light")
        engine.themeManager.setActiveTheme(activeThemeID)
        
        // ... (lines 791-860 unchanged in intent, but need to be careful with replace)
        // I will target the specific block to avoid replacing too much.
        
    // (I must use separate chunks or a larger block. I'll use a large block or multiple calls?
    // replace_file_content supports single chunk. I will do makeNSView first)

        
        // Set Font
        let fontWeightValue: NSFont.Weight
        switch fontWeight {
        case 0: fontWeightValue = .ultraLight
        case 1: fontWeightValue = .light
        case 2: fontWeightValue = .regular
        case 3: fontWeightValue = .medium
        case 4: fontWeightValue = .semibold
        case 5: fontWeightValue = .bold
        default: fontWeightValue = .regular
        }
        
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: fontWeightValue)
        let customFont = NSFont(name: fontName, size: fontSize) ?? font
        textView.font = customFont
        textView.typingAttributes[.font] = customFont
        textView.typingAttributes[.font] = customFont
        textView.typingAttributes[.ligature] = 0 // Disable ligatures
        textView.typingAttributes[.foregroundColor] = engine.themeManager.editorForegroundColor // FIX: Default to Theme Color (White)
        
        // Set colors
        let isTransparent = themeName == "transparent" || themeName == "extraClear"
        textView.backgroundColor = isTransparent ? .clear : engine.themeManager.editorBackgroundColor
        textView.drawsBackground = !isTransparent
        textView.insertionPointColor = engine.themeManager.editorForegroundColor
        textView.textContainerInset = NSSize(width: 5, height: 8)
        
        // Ensure default text color is set immediately in makeNSView
        textView.textColor = engine.themeManager.editorForegroundColor
        
        // Disable Line Numbers to restore text visibility immediately
        // let rulerView = LineNumberRulerView(textView: textView, scrollView: scrollView)
        // scrollView.verticalRulerView = rulerView
        // scrollView.hasVerticalRuler = true
        // scrollView.rulersVisible = true
        
        scrollView.hasVerticalScroller = isScrollEnabled
        scrollView.hasHorizontalScroller = isScrollEnabled
        scrollView.autohidesScrollers = true
        
        if !isScrollEnabled {
            scrollView.scrollsDynamically = false
            // Disable elastic bounce if possible (not exposed directly on NSScrollView easily without subclass)
            // But removing scrollers usually helps.
        }
        
        // FIX BLINK: Disable [.width] mask which fights with 'No Wrap' mode.
        // Use [.height] to fill vertically.
        textView.autoresizingMask = [.height]
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        
        // FIX INVISIBLE TEXT: Ensure initial width is large enough so it doesn't collapse to 0
        let initialWidth = max(scrollView.frame.width, 800)
        let initialHeight = max(scrollView.frame.height, 600)
        textView.minSize = NSSize(width: initialWidth, height: initialHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        // Ensure Transparency is strictly enforced
        scrollView.drawsBackground = !isTransparent
        scrollView.backgroundColor = isTransparent ? .clear : engine.themeManager.editorBackgroundColor
        scrollView.backgroundColor = isTransparent ? .clear : engine.themeManager.editorBackgroundColor
        
        // Initialize and apply highlighting
        engine.setDocument(text, language: language)
        
        // Notify LSP file opened
        if let url = context.coordinator.parent.fileURL {
            Task {
                await LSPManager.shared.documentOpened(uri: url.absoluteString, language: language, content: text)
            }
        }
        
        // Use asynchronous highlighting to prevent main-thread freeze during cell initialization
        // We set the cached text first (fast) then apply attributes later
        textView.string = text
        if let textStorage = textView.textStorage {
            engine.applyHighlightingAsync(to: textStorage, fontSize: fontSize, font: textView.font)
        }
        
        return scrollView
    }
    
    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Log to detect layout loops
        ReportLogManager.shared.log("updateNSView called", type: .debug)

        guard let textView = scrollView.documentView as? NSTextView,
              let textStorage = textView.textStorage else { return }
        
        guard let engine = context.coordinator.engine else { return }
        
        // Critical: Update coordinator's parent to ensure Binding is fresh
        context.coordinator.parent = self
        
        // LOOP PROTECTION: Check if anything actually changed
        // This prevents infinite layout loops where updateNSView triggers a layout, which calls updateNSView again.
        if context.coordinator.lastText == text &&
           context.coordinator.lastLanguage == language &&
           context.coordinator.lastThemeName == themeName &&
           context.coordinator.lastFontSize == fontSize &&
           context.coordinator.lastIsDark == isDark {
            return
        }
        
        // Update Cache
        context.coordinator.lastText = text
        context.coordinator.lastLanguage = language
        context.coordinator.lastThemeName = themeName
        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastIsDark = isDark
        
        // Update theme
        let activeThemeID = (themeName != nil && themeName != "system" && !themeName!.isEmpty) ? themeName! : (isDark ? "dark" : "light")
        engine.themeManager.setActiveTheme(activeThemeID)
        
        let isTransparent = themeName == "transparent" || themeName == "extraClear"
        textView.backgroundColor = isTransparent ? .clear : engine.themeManager.editorBackgroundColor
        textView.drawsBackground = !isTransparent
        scrollView.backgroundColor = isTransparent ? .clear : engine.themeManager.editorBackgroundColor
        scrollView.drawsBackground = !isTransparent
        
        // Ensure explicit text color (fixes invisible text if highlighting lags)
        // Ensure explicit text color (fixes invisible text if highlighting lags)
        // Guard updates to prevent typingAttributes reset
        // REMOVED: textColor assignment here can reset typingAttributes.
        // It is already set in makeNSView.
        // let fgColor = engine.themeManager.editorForegroundColor
        // if textView.textColor != fgColor {
        //    textView.textColor = fgColor
        // }
        // textView.insertionPointColor = engine.themeManager.caretColor
        
        let selectionColor = engine.themeManager.selectionColor
        // Equality check for attributes dictionary is hard, we assume if theme changed, we update.
        // We rely on 'loop protection' above for theme checks, but being explicit helps.
        // If we really want to check:
        // let currentSel = textView.selectedTextAttributes[.backgroundColor] as? NSColor
        // if currentSel != selectionColor { ... }
        // For now, let's trust the logic, but re-assignment might be benign if identical?
        // Let's guard it anyway for safety.
        let currentSelColor = textView.selectedTextAttributes[.backgroundColor] as? NSColor
        if currentSelColor != selectionColor {
            var attributes: [NSAttributedString.Key: Any] = [
                .backgroundColor: selectionColor
            ]
            // Only force white text if selection color is very dark, otherwise keep original syntax/theme color
            // Actually, for "transparent beautiful", we usually just want the background selection 
            // and keep the syntax highlighting visible underneath if possible, 
            // OR use the system default which does that automatically if we don't override foreground.
            // But if we override background, we might need to be careful.
            
            // Fix: Don't force foreground color to white. Let syntax highlighting shine through or use system default behavior.
            textView.selectedTextAttributes = attributes
        }
        
        // Update Font
        let fontWeightValue: NSFont.Weight
        switch fontWeight {
        case 0: fontWeightValue = .ultraLight
        case 1: fontWeightValue = .light
        case 2: fontWeightValue = .regular
        case 3: fontWeightValue = .medium
        case 4: fontWeightValue = .semibold
        case 5: fontWeightValue = .bold
        default: fontWeightValue = .regular
        }
        
        // Optimize Update: Check if font actually changed before setting
        // This prevents the layout manager from invalidating layout unnecessarily
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: fontWeightValue)
        let customFont = NSFont(name: fontName, size: fontSize) ?? font
        
        if textView.font != customFont {
            textView.font = customFont
            textView.typingAttributes[.font] = customFont
            textView.typingAttributes[.font] = customFont
            textView.typingAttributes[.ligature] = 0 // Disable ligatures
            textView.typingAttributes[.foregroundColor] = engine.themeManager.editorForegroundColor
        }
        
        // Ensure specific attributes are present without full reset
        if textView.typingAttributes[.ligature] == nil {
             textView.typingAttributes[.ligature] = 0
        }
        if textView.typingAttributes[.foregroundColor] == nil {
             textView.typingAttributes[.foregroundColor] = engine.themeManager.editorForegroundColor
        }
        
        // Check if text or language changed
        // Critical Fix: Also check if language changed, otherwise switching file types (e.g. .txt -> .swift) wouldn't update highlighting
        // We store the current language in the engine to compare
        let languageChanged = engine.currentLanguage != language
        
        if textView.string != text || languageChanged {
            // Update the actual text view content if it changed
            if textView.string != text {
                // Critical Fix: Disable Coordinator updates during full replacement
                // We SKIP manipulating undoManager to avoid crashes, but we keep the isUpdating flag
                // to prevent the O(N) diffing/deadlock in processEdit().
                context.coordinator.isUpdating = true
                textView.string = text
                context.coordinator.isUpdating = false
            }
            
            // Update document content in engine
            engine.setDocument(text, language: language)
            
            // Apply highlighting via Debounce to prevent Main Thread congestion (e.g. Notebook open)
            context.coordinator.triggerDebouncedHighlight(for: textView)
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    @MainActor
    public class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: SyntaxHighlightedCodeView
        var highlightTimer: Timer?
        var isUpdating = false
        
        // Engine is now owned by the Coordinator (PERSISTENT)
        var engine: SyntaxHighlightingEngine? // Changed to var and optional
        
        // Cache for change detection
        var lastText: String = ""
        var lastLanguage: String = ""
        var lastThemeName: String?
        var lastFontSize: CGFloat = 0
        var lastIsDark: Bool = false
        var lastFileURL: URL? = nil // Added fileURL to cache
        
        init(_ parent: SyntaxHighlightedCodeView) {
            self.parent = parent
        }
        
        // MARK: - NSTextStorageDelegate (Incremental Updates)
        
        public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range: NSRange, changeInLength: Int) {
            // Avoid processing our own highlighting updates
            guard !isUpdating else { return }
            
            // IME-FIRST: Skip processing if IME composition is in progress
            // This prevents corruption of marked text (e.g., Thai, Japanese, Chinese input)
            if let layoutManager = textStorage.layoutManagers.first,
               let textContainer = layoutManager.textContainers.first,
               let textView = textContainer.textView,
               textView.hasMarkedText() {
                return // IME is composing, don't interfere
            }
            
            // Only process character changes (typing, pasting), not attribute changes
            if editedMask.contains(.editedCharacters) {
                // Synchronously update the engine's model to keep it in sync
                engine?.processEdit(range: range, changeInLength: changeInLength, newContent: textStorage.string)
                
                // Notify LSP of change
                if let url = parent.fileURL {
                    let content = textStorage.string
                    let language = parent.language
                    Task {
                        await LSPManager.shared.documentChanged(uri: url.absoluteString, language: language, content: content)
                    }
                }
                
                // POST-EDIT FIX: Update typingAttributes to match the just-typed content
                // This ensures continuous typing inherits the NEW color (e.g. typing "import " -> import is pink, space should be pink/white)
                // We access the TextView via the LayoutManager
                if let layoutManager = textStorage.layoutManagers.first,
                   let textContainer = layoutManager.textContainers.first,
                   let textView = textContainer.textView {
                    
                    let endLocation = range.location + range.length
                    let checkLocation = max(0, endLocation - 1)
                    
                    if checkLocation < textStorage.length {
                        let attributes = textStorage.attributes(at: checkLocation, effectiveRange: nil)
                        if let color = attributes[.foregroundColor] as? NSColor {
                            var newAttributes = textView.typingAttributes
                            newAttributes[.foregroundColor] = color
                            if let font = attributes[.font] as? NSFont {
                                newAttributes[.font] = font
                            }
                            textView.typingAttributes = newAttributes
                        }
                    }
                    
                    // Force layout to ensure visual update immediately (Nuclear option for New File Blink)
                    layoutManager.ensureLayout(for: textContainer)
                }
            }
        }
        
        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            // IME-FIRST: Skip binding update during IME composition
            // Prevents corruption of Thai/Japanese/Chinese input while composing
            guard !textView.hasMarkedText() else { return }
            
            // Loop Protection: If content matches binding, ignore
            if parent.text == textView.string { return }
            guard !isUpdating else { return }
            
            // ASYNC Binding Update: Breaks the Layout Recursion Loop
            let newText = textView.string
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Double check before updating to prevent race conditions
                if self.parent.text != newText {
                    self.parent.text = newText
                }
            }

            // Trigger highlight
            triggerDebouncedHighlight(for: textView)
        }
        
        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let range = textView.selectedRanges.first?.rangeValue,
                  range.length == 0 else { return } // Only for insertion point
            
            // Context-Aware Typing Attributes (Zero-Flash Typing)
            // When cursor moves, checking the token at the cursor allows us to pre-set the color
            // So if I click inside a green string, I type green immediately.
            
            let location = range.location
            // Check character BEFORE cursor (to inherit)
            let checkLocation = max(0, location - 1)
            
            if let textStorage = textView.textStorage, checkLocation < textStorage.length {
                // Get attributes at check location
                let attributes = textStorage.attributes(at: checkLocation, effectiveRange: nil)
                if let color = attributes[.foregroundColor] as? NSColor {
                    var newAttributes = textView.typingAttributes
                    newAttributes[.foregroundColor] = color
                    // Sync font as well
                    if let font = attributes[.font] as? NSFont {
                        newAttributes[.font] = font
                    }
                    textView.typingAttributes = newAttributes
                }
            }
        }

        func triggerDebouncedHighlight(for textView: NSTextView?) {
            highlightTimer?.invalidate()
            highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    if let tv = textView {
                        self.applyHighlighting(to: tv)
                    }
                }
            }
        }
        
        // MARK: - Auto Indentation
        
        public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                handleNewline(in: textView)
                return true
            }
            return false
        }
        
        private func handleNewline(in textView: NSTextView) {
            guard let range = textView.selectedRanges.first?.rangeValue else { return }
            let text = textView.string
            let cursorLocation = range.location
            
            // Get current line content up to cursor
            let prefix = (text as NSString).substring(to: cursorLocation)
            var currentLine = ""
            if let lastNewline = prefix.range(of: "\n", options: .backwards) {
                currentLine = String(prefix[lastNewline.upperBound...])
            } else {
                currentLine = prefix
            }
            
            // 1. Calculate base indentation (spaces/tabs from current line)
            var indentation = ""
            for char in currentLine {
                if char.isWhitespace {
                    indentation.append(char)
                } else {
                    break
                }
            }
            
            // 2. Check if we should increase indentation
            // Rules: Ends with {, (, [, or : (Python)
            let trimmedLine = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let openers: [Character] = ["{", "(", "[", ":"]
            
            var shouldIndent = false
            if let lastChar = trimmedLine.last {
                if openers.contains(lastChar) {
                    shouldIndent = true
                }
            }
            
            // 3. Construct new line content
            // Assuming 4 spaces for indentation (can be configurable later)
            var insertString = "\n" + indentation
            if shouldIndent {
                insertString += "    "
            }
            
            // Check for closing brace autocompletion scenarios
            // e.g. "{" -> "\n    \n}"
            // This is a more advanced feature, keeping it simple for now as requested "Auto indent"
            
            // 4. Insert text
            if textView.shouldChangeText(in: range, replacementString: insertString) {
                // IMPORTANT: Update engine BEFORE applying change to textStorage if using direct storage manipulation,
                // but here replaceCharacters will trigger textStorage delegate which calls processEdit.
                textView.replaceCharacters(in: range, with: insertString)
                // textView.didChangeText() // CAUTION: Redundant call causing double updates/freezes
                
                // Auto-scroll to cursor
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }
        
        private func applyHighlighting(to textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let engine = engine else { return }
            
            // IME-FIRST: Skip highlighting during IME composition
            // This preserves the marked text underline and prevents visual corruption
            guard !textView.hasMarkedText() else { return }
            
            // Only set isUpdating if we are actually editing characters
            // Here we use it to prevent the delegate from reacting to the attribute changes we are about to make
            isUpdating = true
            
            // Use asynchronous application to keep UI responsive
            engine.applyHighlightingAsync(to: textStorage, fontSize: parent.fontSize, font: textView.font) { [weak self] in
                self?.isUpdating = false
            }
        }
    }
}

// MARK: - Usage Example

/*
 USAGE EXAMPLE:
 
 1. Basic usage with the shared engine:
 
    let highlighted = SyntaxHighlightingEngine.highlight(
        code,
        language: "swift",
        fontSize: 13,
        isDark: true
    )
    textView.textStorage?.setAttributedString(highlighted)
 
 2. Incremental updates (for editors):
 
    let engine = SyntaxHighlightingEngine.shared
    
    // Initial load
    engine.setDocument(code, language: "swift")
    let attributed = engine.highlightedAttributedString(fontSize: 13)
    
    // On text change
    engine.markDirty(fromLine: editedLine, toLine: editedLine)
    let updated = engine.highlightedAttributedString(fontSize: 13)
 
 3. SwiftUI integration:
 
    struct EditorView: View {
        @State private var code = "func hello() { print(\"Hello\") }"
        
        var body: some View {
            SyntaxHighlightedCodeView(
                text: $code,
                language: "swift",
                fontSize: 13,
                isDark: true,
                themeName: "default-dark"
            )
        }
    }
 
 4. Custom theme loading:
 
    let themeData = try Data(contentsOf: themeURL)
    let theme = try ThemeManager.shared.loadTheme(from: themeData)
    ThemeManager.shared.setActiveTheme(theme.name)
 
 HANDLING OVERLAPPING TOKENS:
 
 The state machine lexer handles overlapping patterns correctly because:
 1. It processes the source sequentially
 2. Context-aware tokenization (keywords in strings aren't highlighted)
 3. Priority ordering (comments processed before keywords)
 
 When applying styles to NSAttributedString:
 - SyntaxTokens are applied in order they appear in the source
 - Later tokens overwrite earlier ones for the same range
 - This naturally handles cases like "if" inside a comment
 
 */
