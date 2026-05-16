//
//  SyntaxHighlightingEngine.swift
//  MicroCode - Syntax Highlighting Engine
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
        
        // C-family
        register("c") { createSwiftLexer() } // Fallback
        register("cpp") { createSwiftLexer() }
        register("c++") { createSwiftLexer() }
        register("h") { createSwiftLexer() }
        register("hpp") { createSwiftLexer() }
        register("objc") { createSwiftLexer() }
        register("objective-c") { createSwiftLexer() }
        register("m") { createSwiftLexer() }
        register("mm") { createSwiftLexer() }
        
        // JVM languages (use Swift-like syntax)
        register("java") { createJavaLexer() } // Keep Swift lexer for Java for now
        register("kt") { createKotlinLexer() }
        register("kotlin") { createKotlinLexer() }
        register("scala") { createKotlinLexer() }
        register("groovy") { createJavaLexer() }
        
        // Swift
        register("swift") { createSwiftLexer() }
        
        // Scripting (Native ObjC++ Engine disabled for now due to pipeline/token issues, using Swift Lexer)
        register("py") { createPythonLexer() }
        register("python") { createPythonLexer() }
        
        // Ruby (Keep Swift lexer)
        register("rb") { createRubyLexer() }
        register("ruby") { createRubyLexer() }
        register("lua") { createRubyLexer() }
        
        // Shell
        register("bash") { createPythonLexer() } // Fallback
        register("sh") { createPythonLexer() }
        register("zsh") { createPythonLexer() }
        register("fish") { createPythonLexer() }
        
        // Data Science (Fallback to Python/Swift)
        register("r") { createPythonLexer() }
        register("julia") { createPythonLexer() }
        register("jl") { createPythonLexer() }
        
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
    
    /// Whether the initial view setup has completed
    /// (set to true after the makeNSView async block fires)
    internal var isViewReady: Bool = false
    
    /// Shared instance for convenience
    public static let shared = SyntaxHighlightingEngine()
    
    public init(themeManager: ThemeManager? = nil) {
        // CRITICAL FIX: Each engine gets its own ThemeManager instance by default.
        // This prevents the singleton race condition where multiple views overwrite
        // each others active theme, causing invisible text.
        self.themeManager = themeManager ?? ThemeManager()
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
        
        let nsNew = newContent as NSString
        let safeAddedLocation = max(0, min(range.location, nsNew.length))
        let safeAddedLength = max(0, min(range.length, nsNew.length - safeAddedLocation))
        let addedText = nsNew.substring(with: NSRange(location: safeAddedLocation, length: safeAddedLength))
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
            let currentAddedOffset = range.location
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
            let shiftAmount = changeInLength 
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
            charDelta: changeInLength
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
    
    /// Cancel any in-flight highlighting task
    public func cancelHighlighting() {
        currentHighlightTask?.cancel()
        currentHighlightTask = nil
    }
    
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
        
        // HYBRID APPROACH: only highlight synchronously for genuinely small
        // documents. 500 lines was far too high — a few hundred lines of dense
        // code (or long minified lines) tokenized on the main thread, twice
        // per change, across many SwiftUI update passes, froze the editor on
        // open ("loading นานค้าง"). Gate by BOTH line count and char count and
        // keep the budget tight; anything bigger is lexed off-thread (the
        // plain text is already on screen, so colours just arrive a beat late).
        let lineCount = content.filter({ $0 == "\n" }).count
        if lineCount < 150 && content.utf16.count < 6000 {
            // SYNC PATH (Zero Flash) — small files only
            CrashReporter.shared.breadcrumb("Engine.applyHighlightingAsync sync: retokenize lang=\(currentLanguage) lines=\(lineCount)")
            let tokens = lexer.retokenizeDirtyRegions(in: content)
            CrashReporter.shared.breadcrumb("Engine.applyHighlightingAsync sync: applyTokens count=\(tokens.count)")
             self.applyTokens(tokens, to: textStorage, fontSize: fontSize, font: font)
            CrashReporter.shared.breadcrumb("Engine.applyHighlightingAsync sync: done")
             completion?()
             return
        }
        
        // ASYNC PATH (Large Docs)
        // Use a detached task for background work, but keep reference for cancellation
        currentHighlightTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                await MainActor.run { completion?() }
                return
            }
            
            // Check cancellation before heavy work
            if Task.isCancelled {
                await MainActor.run { completion?() }
                return
            }
            
            // 1. Re-lex dirty regions (this is the expensive part)
            let tokens = lexer.retokenizeDirtyRegions(in: content)
            
            // Check cancellation mid-work
            if Task.isCancelled {
                await MainActor.run { completion?() }
                return
            }
            
            // 2. Apply attributes on the main thread
            await MainActor.run {
                // ALWAYS call completion when we exit this closure to prevent isUpdating deadlocks
                defer { completion?() }
                
                // Check cancellation right before applying
                if Task.isCancelled { return }
                
                // Verify text still matches to prevent crashes or misaligned highlighting
                self.lock.lock()
                let isStillValid = (self.currentVersion == version && self.documentContent.utf16.count == textStorage.length)
                self.lock.unlock()
                
                if isStillValid {
                    self.applyTokens(tokens, to: textStorage, fontSize: fontSize, font: font)
                }
            }
        }
    }
    
    /// Internal helper to apply attributes for specific tokens.
    /// CRITICAL: Must be called on the main thread.
    /// Uses chunking to prevent Main Thread blocking on large updates.
    @MainActor
    private func applyTokens(_ tokens: [SyntaxToken], to textStorage: NSTextStorage, fontSize: CGFloat, font: NSFont?) {
        assert(Thread.isMainThread, "applyTokens must be called on the main thread")
        
        let fgColor = themeManager.editorForegroundColor
        let defaultFont = font ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        
        let fullRange = NSRange(location: 0, length: textStorage.length)
        if fullRange.length > 0 {
            textStorage.beginEditing()
            textStorage.addAttributes([
                .foregroundColor: fgColor,
                .font: defaultFont,
                .ligature: 0
            ], range: fullRange)
            textStorage.endEditing()
        }
        
        // CHUNK SIZE: Apply 2000 tokens at a time to keep frame rate high
        // 2000 tokens ~ 200 lines of code roughly.
        let chunkSize = 2000
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
         // NOTE: Callers (applyTokens / applyHighlighting) are responsible for wrapping in beginEditing/endEditing.
         // Do NOT call beginEditing/endEditing here to avoid double-nesting which triggers NSTextStorage assertions.
         
         for token in tokens {
             let nsRange = token.range.nsRange
             
             // Ensure range is within bounds
             if nsRange.location + nsRange.length <= textStorage.length {
                 var attributes: [NSAttributedString.Key: Any] = [
                     .foregroundColor: themeManager.color(for: token.type),
                     .ligature: 0
                 ]
                 
                 let style = themeManager.style(for: token.type)
                 if style.isBold || style.isItalic {
                     var traits: NSFontDescriptor.SymbolicTraits = []
                     if style.isBold { traits.insert(.bold) }
                     if style.isItalic { traits.insert(.italic) }
                     
                     let descriptor = defaultFont.fontDescriptor.withSymbolicTraits(traits)
                     let styledFont = NSFont(descriptor: descriptor, size: fontSize) ?? defaultFont
                     attributes[.font] = styledFont
                 }
                 
                 if style.isUnderline {
                     attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                 }
                 
                 // Optimization: Skip update if color matches (Prevent Flicker)
                 // BUT: For small files (New Files), we force update to ensure consistency and prevent "White Flash" if defaults are wrong.
                 if textStorage.length < 500 {
                     textStorage.addAttributes(attributes, range: nsRange)
                 } else {
                     let currentAttrs = textStorage.attributes(at: nsRange.location, effectiveRange: nil)
                     let currentColor = currentAttrs[.foregroundColor] as? NSColor
                     let targetColor = attributes[.foregroundColor] as? NSColor
                     
                     if currentColor != targetColor {
                         textStorage.addAttributes(attributes, range: nsRange)
                     }
                 }
             }
         }
    }

    /// Synchronous version (use with caution on small snippets or background threads)
    nonisolated public func applyHighlighting(to textStorage: NSTextStorage, fontSize: CGFloat, font: NSFont? = nil) {
        lock.lock()
        let content = documentContent
        let lexer = activeLexer
        lock.unlock()
        
        guard let lexer = lexer else { return }
        let tokens = lexer.retokenizeDirtyRegions(in: content)
        
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.applyTokens(tokens, to: textStorage, fontSize: fontSize, font: font)
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    self.applyTokens(tokens, to: textStorage, fontSize: fontSize, font: font)
                }
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

// Custom NSScrollView to prevent SwiftUI from attempting to size the scroll view
// based on the length of the code inside the NSTextView. This definitively breaks
// the AppKit layout recursion loop (_FlexFrameLayout) that causes EXC_BREAKPOINT.
class NoIntrinsicScrollView: NSScrollView {
    // Returning noIntrinsicMetric prevents the scroll view from bubbling the
    // text view's content size up to SwiftUI, which is what triggered the
    // _FlexFrameLayout recursion crash. sizeThatFits returning the proposal
    // also stops SwiftUI from ever querying intrinsic size, so this never
    // recurses back into SwiftUI layout.
    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    // The deferred configureTextGeometry() can run before SwiftUI has given
    // this scroll view its real frame (contentSize ≈ 0 → text view 1pt wide →
    // every glyph wraps off-screen → "nothing shows"). Once the scroll view
    // gets a real size, AppKit calls layout(); here we keep the document
    // NSTextView's width synced to the content width. This is the canonical
    // maintenance for a *wrapping* (isHorizontallyResizable = false,
    // widthTracksTextView = true) text view and does NOT fight the layout
    // manager — unlike the old override that also forced an infinite-width
    // container while horizontally resizable.
    override func layout() {
        super.layout()
        guard let tv = documentView as? NSTextView else { return }
        let w = contentSize.width
        let h = contentSize.height
        guard w > 1 else { return }
        if abs(tv.frame.width - w) > 0.5 {
            tv.setFrameSize(NSSize(width: w, height: max(tv.frame.height, h)))
        } else if tv.frame.height < h {
            tv.setFrameSize(NSSize(width: tv.frame.width, height: h))
        }
    }
}

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
    public let isTransparent: Bool
    /// Stable identity for this logical editor (file id / "playground" / cell
    /// id). SwiftUI churns this representable's identity (it recreates the
    /// NSView via makeNSView repeatedly), and the freshly-created EMPTY view
    /// kept replacing the one that had content → permanently blank editor.
    /// When an editorID is supplied we cache & REUSE the NSScrollView so churn
    /// always returns the same, content-bearing, mounted view.
    public let editorID: String?

    /// Per-editor reused scroll views, keyed by editorID. Main-actor only
    /// (SyntaxHighlightedCodeView is always used from SwiftUI/main).
    @MainActor private static var viewCache: [String: NSScrollView] = [:]

    public init(text: Binding<String>, language: String, fontSize: CGFloat = 13, isDark: Bool = true, themeName: String? = nil, fontName: String = "Menlo", fontWeight: Int = 2, fileURL: URL? = nil, isScrollEnabled: Bool = true, isTransparent: Bool = false, editorID: String? = nil) {
        self._text = text
        self.language = language
        self.fontSize = fontSize
        self.isDark = isDark
        self.themeName = themeName
        self.fontName = fontName
        self.fontWeight = fontWeight
        self.fileURL = fileURL
        self.isScrollEnabled = isScrollEnabled
        self.isTransparent = isTransparent
        self.editorID = editorID
    }

    @available(macOS 13.0, *)
    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        // CRITICAL FIX: By explicitly returning the proposed size, we PREVENT SwiftUI 
        // from ever querying the intrinsicContentSize of the NSScrollView.
        // This definitively kills the _FlexFrameLayout recursion crash.
        return proposal.replacingUnspecifiedDimensions()
    }

    public func makeNSView(context: Context) -> NSScrollView {
        // ─────────────────────────────────────────────────────────────────
        // CRITICAL: makeNSView is called INSIDE a SwiftUI/AppKit layout pass.
        // ─────────────────────────────────────────────────────────────────
        CrashReporter.shared.breadcrumb("SHCV.makeNSView lang=\(language) start id=\(editorID ?? "nil")")

        // REUSE: SwiftUI keeps recreating this representable's NSView (identity
        // churn). Return the SAME cached scroll view (it already holds the
        // content + ruler) so a fresh empty view never replaces it on screen.
        if let id = editorID, let cached = Self.viewCache[id],
           let tv = cached.documentView as? NSTextView {
            let engine = SyntaxHighlightingEngine()
            context.coordinator.engine = engine
            tv.delegate = context.coordinator
            tv.textStorage?.delegate = context.coordinator
            CrashReporter.shared.breadcrumb("SHCV.makeNSView REUSE id=\(id) tsLen=\(tv.textStorage?.length ?? -1)")
            context.coordinator.applyContent(self, to: tv, scrollView: cached, force: true)
            return cached
        }

        // Custom ScrollView to prevent intrinsic size bubbling
        let scrollView = NoIntrinsicScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        let contentSize = scrollView.contentSize
        let initialWidth = max(1, contentSize.width)
        let initialHeight = max(1, contentSize.height)

        // Use AppKit's OWN construction (explicit TextKit 1) instead of a
        // hand-assembled NSTextStorage/NSLayoutManager/NSTextContainer.
        // On macOS 26 the manual stack assigned via `documentView` laid glyphs
        // out (the gutter ruler drew correctly) but the text view itself drew
        // NOTHING — the v2.5.5 diagnostic proved frame/window/glyphs were all
        // correct, so the blank editor was a TextKit-stack/rendering quirk, not
        // geometry or colour. `NSTextView(usingTextLayoutManager: false)` builds
        // a fully-wired, render-correct TextKit 1 view (macOS 13+).
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.frame = NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: initialWidth, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView

        // Only set the delegate here — this does NOT trigger layout.
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator

        // Initialize engine and assign to coordinator NOW.
        let engine = SyntaxHighlightingEngine()
        context.coordinator.engine = engine

        // Configure the view fully & SYNCHRONOUSLY. The real crash was a lexer
        // duplicate-dictionary-key trap (fixed) — NOT layout re-entrancy — so
        // the old deferred double-async dance was unnecessary and caused a
        // render race: the deferred config ran before the scroll view had a
        // real frame and nothing re-synced → permanently blank editor.
        // Synchronous configuration is the standard, reliable pattern;
        // NoIntrinsicScrollView + sizeThatFits already stop SwiftUI from
        // querying intrinsic size, so there is no recursion.
        do {
            let coordinator = context.coordinator
            let tv = textView
            CrashReporter.shared.breadcrumb("SHCV.makeNSView config (sync) start")

            // ── Text view behaviour ──────────────────────────────────────
            tv.isRichText = true
            tv.isEditable = true
            tv.isSelectable = true
            tv.allowsUndo = true
            tv.usesFindBar = true
            tv.importsGraphics = false
            tv.usesFontPanel = false
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
            tv.isAutomaticSpellingCorrectionEnabled = false
            tv.isAutomaticLinkDetectionEnabled = false
            tv.baseWritingDirection = .natural
            tv.allowsDocumentBackgroundColorChange = false

            // ── Theme ────────────────────────────────────────────────────
            let lowerTheme = coordinator.parent.themeName?.lowercased() ?? ""
            let activeThemeID: String
            if !lowerTheme.isEmpty && lowerTheme != "system", let tn = coordinator.parent.themeName {
                activeThemeID = tn
            } else {
                activeThemeID = coordinator.parent.isDark ? "dark" : "light"
            }
            engine.themeManager.setActiveTheme(activeThemeID)

            // ── Font ─────────────────────────────────────────────────────
            let fw = coordinator.parent.fontWeight
            let fontWeightValue: NSFont.Weight
            switch fw {
            case 0: fontWeightValue = .ultraLight
            case 1: fontWeightValue = .light
            case 2: fontWeightValue = .regular
            case 3: fontWeightValue = .medium
            case 4: fontWeightValue = .semibold
            case 5: fontWeightValue = .bold
            default: fontWeightValue = .regular
            }
            let baseFont = NSFont.monospacedSystemFont(ofSize: coordinator.parent.fontSize, weight: fontWeightValue)
            let customFont = NSFont(name: coordinator.parent.fontName, size: coordinator.parent.fontSize) ?? baseFont
            tv.font = customFont
            tv.typingAttributes[.font] = customFont
            tv.typingAttributes[.ligature] = 0
            tv.typingAttributes[.foregroundColor] = engine.themeManager.editorForegroundColor

            // ── Colors ───────────────────────────────────────────────────
            let tn = coordinator.parent.themeName
            let effectiveTransparent = coordinator.parent.isTransparent
                || tn == "transparent" || tn == "extraClear"
                || tn == "crystalClear" || tn == "obsidianGlass"
            let fgColor = engine.themeManager.editorForegroundColor
            let bgColor = engine.themeManager.editorBackgroundColor
            tv.backgroundColor      = effectiveTransparent ? .clear : bgColor
            tv.drawsBackground      = !effectiveTransparent
            tv.insertionPointColor  = fgColor
            tv.textContainerInset   = NSSize(width: 5, height: 8)
            tv.textColor            = fgColor
            scrollView.drawsBackground  = !effectiveTransparent
            scrollView.backgroundColor  = effectiveTransparent ? .clear : bgColor

            // ── Layout ───────────────────────────────────────────────────
            coordinator.configureTextGeometry(for: tv, in: scrollView)

            // ── Line Numbers (safe to add after view is in hierarchy) ─────
            let rulerView = LineNumberRulerView(textView: tv, scrollView: scrollView,
                                               themeManager: engine.themeManager)
            scrollView.verticalRulerView = rulerView
            scrollView.hasVerticalRuler  = true
            scrollView.rulersVisible     = true
            scrollView.hasVerticalScroller   = coordinator.parent.isScrollEnabled
            scrollView.hasHorizontalScroller = coordinator.parent.isScrollEnabled
            scrollView.autohidesScrollers    = true
            scrollView.scrollerStyle         = .overlay // FIX: Prevent layout loops when scrollers hide/show

            // CRITICAL FIX: Prevent SwiftUI _FlexFrameLayout infinite recursion loop.
            // By setting these priorities to .defaultLow, we force NSScrollView to ALWAYS
            // accept the size SwiftUI proposes, rather than fighting SwiftUI by reporting
            // an intrinsic content size based on the text length.
            scrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
            scrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            scrollView.needsLayout = true


            coordinator.engine?.isViewReady = true
            _ = fgColor; _ = customFont
            CrashReporter.shared.breadcrumb("SHCV.makeNSView config (sync) done")

            // ── LSP notification ─────────────────────────────────────────
            let lang = coordinator.parent.language
            if let url = coordinator.parent.fileURL {
                let content = tv.textStorage?.string ?? ""
                Task.detached(priority: .utility) {
                    await LSPManager.shared.documentOpened(uri: url.absoluteString,
                                                          language: lang,
                                                          content: content)
                }
            }
        }

        // Push initial content + highlighting NOW (synchronous) so the editor
        // is never blank waiting on an async tick. SwiftUI also calls
        // updateNSView right after this, which is a cheap no-op if unchanged.
        context.coordinator.applyContent(self, to: textView, scrollView: scrollView, force: true)

        // Cache so subsequent SwiftUI identity churn reuses THIS view.
        if let id = editorID {
            Self.viewCache[id] = scrollView
            // Bound the cache so long sessions with many files don't grow
            // without limit.
            if Self.viewCache.count > 24 {
                for key in Self.viewCache.keys where key != id {
                    if (Self.viewCache[key]?.window) == nil {
                        Self.viewCache.removeValue(forKey: key)
                    }
                    if Self.viewCache.count <= 24 { break }
                }
            }
        }

        return scrollView
    }


    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.textStorage != nil else { return }
        guard context.coordinator.engine != nil else { return }
        context.coordinator.parent = self
        // Synchronous, single code path shared with makeNSView. No async
        // deferral (that race left the editor permanently blank). Cheap no-op
        // when nothing changed.
        context.coordinator.applyContent(self, to: textView, scrollView: scrollView, force: false)
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    @MainActor
    public class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
        var parent: SyntaxHighlightedCodeView
        var highlightTimer: Timer?
        var isUpdating = false
        var isInvalidated = false // Prevents async callbacks after teardown
        
        // Engine is now owned by the Coordinator (PERSISTENT)
        var engine: SyntaxHighlightingEngine? // Changed to var and optional
        
        // Cache for change detection
        var lastText: String = ""
        var lastLanguage: String = ""
        var lastThemeName: String?
        var lastFontSize: CGFloat = 0
        var lastIsDark: Bool = false
        var lastIsTransparent: Bool = false  // FIX: track transparent mode
        var lastFileURL: URL? = nil // Added fileURL to cache
        var didRenderSelfTest = false

        init(_ parent: SyntaxHighlightedCodeView) {
            self.parent = parent
        }

        /// One-shot render self-test. Runs ~0.7s after content is applied and
        /// the view is in a window, when AppKit has actually drawn. Captures
        /// the concrete reason glyphs are invisible: occluding sibling views,
        /// layer/alpha/mask, clip bounds vs glyph used-rect, container metrics.
        func scheduleRenderSelfTest(_ textView: NSTextView, _ scrollView: NSScrollView) {
            guard !didRenderSelfTest else { return }
            didRenderSelfTest = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self, weak textView, weak scrollView] in
                guard let self = self, !self.isInvalidated,
                      let tv = textView, let sv = scrollView else { return }
                func r(_ rc: NSRect) -> String { "\(Int(rc.origin.x)),\(Int(rc.origin.y)) \(Int(rc.width))x\(Int(rc.height))" }

                var lines: [String] = ["=== RENDER SELF-TEST id=\(self.parent.editorID ?? "nil") ==="]
                lines.append("win=\(tv.window != nil) winVisible=\(tv.window?.isVisible ?? false) occ=\(tv.window?.occlusionState.contains(.visible) ?? false)")
                lines.append("tv.frame=\(r(tv.frame)) bounds=\(r(tv.bounds)) flipped=\(tv.isFlipped) hidden=\(tv.isHidden) alpha=\(tv.alphaValue) opaque=\(tv.isOpaque)")
                lines.append("tv.wantsLayer=\(tv.wantsLayer) layer=\(tv.layer != nil) layerOpacity=\(tv.layer?.opacity ?? -1) layerHidden=\(tv.layer?.isHidden ?? false) layerMask=\(tv.layer?.mask != nil) layerBounds=\(tv.layer.map { r($0.bounds) } ?? "nil")")
                lines.append("tv.string.count=\(tv.string.count) prefix=\(tv.string.prefix(24).replacingOccurrences(of: "\n", with: "\\n"))")
                if let lm = tv.layoutManager, let tc = tv.textContainer {
                    let glyphs = lm.numberOfGlyphs
                    let used = lm.usedRect(for: tc)
                    let gr = lm.glyphRange(for: tc)
                    lm.ensureLayout(for: tc)
                    let firstFrag = glyphs > 0 ? lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil) : .zero
                    lines.append("glyphs=\(glyphs) usedRect=\(r(used)) glyphRange=\(gr) firstFrag=\(r(firstFrag)) inset=\(tv.textContainerInset) origin=\(tv.textContainerOrigin) container=\(tc.size) pad=\(tc.lineFragmentPadding) widthTracks=\(tc.widthTracksTextView)")
                }
                if let clip = sv.contentView as NSClipView? {
                    lines.append("clip=\(type(of: clip)) bounds=\(r(clip.bounds)) docVisible=\(r(sv.documentVisibleRect)) clipDraws=\(clip.drawsBackground) svDraws=\(sv.drawsBackground) doc==tv:\(sv.documentView === tv)")
                }
                // Ancestor chain — detect a covering/opaque/zero-alpha parent.
                var v: NSView? = tv
                var depth = 0
                while let cur = v, depth < 12 {
                    lines.append("  ANC[\(depth)] \(type(of: cur)) frame=\(r(cur.frame)) hidden=\(cur.isHidden) alpha=\(cur.alphaValue) layerOpacity=\(cur.layer?.opacity ?? -1) subviews=\(cur.superview?.subviews.count ?? 0)")
                    v = cur.superview; depth += 1
                }
                // Occlusion: siblings drawn AFTER our branch overlapping the tv.
                if let win = tv.window, let content = win.contentView {
                    let tvInWin = tv.convert(tv.bounds, to: content)
                    var occluders: [String] = []
                    func scan(_ view: NSView, _ path: String) {
                        for (i, sub) in view.subviews.enumerated() {
                            // Skip tv itself, ancestors of tv, and views inside tv.
                            let isAncestorOfTV = tv.isDescendant(of: sub)
                            let isInsideTV = sub.isDescendant(of: tv)
                            let f = sub.convert(sub.bounds, to: content)
                            if sub !== tv, !isAncestorOfTV, !isInsideTV,
                               !sub.isHidden, sub.alphaValue > 0.01,
                               f.intersects(tvInWin), f.width > 50, f.height > 50 {
                                let hasBG = sub.layer?.backgroundColor != nil
                                occluders.append("\(path)[\(i)] \(type(of: sub)) f=\(r(f)) opaque=\(sub.isOpaque) bg=\(hasBG) a=\(sub.alphaValue)")
                            }
                            if !isInsideTV { scan(sub, "\(path)[\(i)]") }
                        }
                    }
                    scan(content, "win")
                    lines.append("tvInWin=\(r(tvInWin)) possibleOccluders(\(occluders.count)): \(occluders.prefix(8).joined(separator: " | "))")
                }
                CrashReporter.shared.breadcrumb(lines.joined(separator: "\n"))
                tv.needsDisplay = true
            }
        }

        /// Single, synchronous code path that configures geometry/theme/font
        /// and pushes the (highlighted) text into the view. Shared by
        /// makeNSView (force=true) and updateNSView (force=false). No async
        /// deferral — that previously raced and left the editor blank.
        func applyContent(_ p: SyntaxHighlightedCodeView,
                          to textView: NSTextView,
                          scrollView: NSScrollView,
                          force: Bool) {
            guard let engine = engine else { return }
            self.parent = p

            // Always keep geometry synced (cheap, idempotent) — this is what
            // makes the text visible once the scroll view finally gets a real
            // frame, even on no-content-change update passes.
            configureTextGeometry(for: textView, in: scrollView)

            let normalizedText = p.text.replacingOccurrences(of: "\r\n", with: "\n")
            let textChanged = lastText != normalizedText
            let langChanged = lastLanguage != p.language
            let themeNameChanged = lastThemeName != p.themeName
            let fontChanged = lastFontSize != p.fontSize
            let darkChanged = lastIsDark != p.isDark
            let transparentChanged = lastIsTransparent != p.isTransparent

            if !force && !textChanged && !langChanged && !themeNameChanged
                && !fontChanged && !darkChanged && !transparentChanged {
                return
            }

            lastText = normalizedText
            lastLanguage = p.language
            lastThemeName = p.themeName
            lastFontSize = p.fontSize
            lastIsDark = p.isDark
            lastIsTransparent = p.isTransparent

            // Theme + colours
            if force || themeNameChanged || darkChanged || transparentChanged {
                let lowerTheme = p.themeName?.lowercased() ?? ""
                let activeThemeID: String
                if !lowerTheme.isEmpty && lowerTheme != "system", let tn = p.themeName {
                    activeThemeID = tn
                } else {
                    activeThemeID = p.isDark ? "dark" : "light"
                }
                engine.themeManager.setActiveTheme(activeThemeID)

                let effectiveTransparent = p.isTransparent
                    || p.themeName == "transparent" || p.themeName == "extraClear"
                    || p.themeName == "crystalClear" || p.themeName == "obsidianGlass"
                let bg: NSColor = effectiveTransparent ? .clear : engine.themeManager.editorBackgroundColor
                let draws = !effectiveTransparent
                textView.backgroundColor = bg
                textView.drawsBackground = draws
                scrollView.backgroundColor = bg
                scrollView.drawsBackground = draws
                let fg = engine.themeManager.editorForegroundColor
                textView.insertionPointColor = fg
                textView.textColor = fg
                textView.typingAttributes[.foregroundColor] = fg
                textView.selectedTextAttributes = [.backgroundColor: engine.themeManager.selectionColor]
            }

            let fgColor = engine.themeManager.editorForegroundColor

            // Font
            let customFont: NSFont
            if force || fontChanged {
                let weight: NSFont.Weight
                switch p.fontWeight {
                case 0: weight = .ultraLight
                case 1: weight = .light
                case 2: weight = .regular
                case 3: weight = .medium
                case 4: weight = .semibold
                case 5: weight = .bold
                default: weight = .regular
                }
                let base = NSFont.monospacedSystemFont(ofSize: p.fontSize, weight: weight)
                customFont = NSFont(name: p.fontName, size: p.fontSize) ?? base
                textView.font = customFont
                textView.typingAttributes[.font] = customFont
            } else {
                customFont = textView.font ?? NSFont.monospacedSystemFont(ofSize: p.fontSize, weight: .regular)
            }
            textView.typingAttributes[.ligature] = 0

            // Content
            if textView.string != normalizedText {
                isUpdating = true
                let r = NSRange(location: 0, length: (normalizedText as NSString).length)
                if r.length > 0 {
                    let attr = NSMutableAttributedString(string: normalizedText)
                    attr.addAttributes([.foregroundColor: fgColor, .font: customFont, .ligature: 0], range: r)
                    textView.textStorage?.setAttributedString(attr)
                } else {
                    textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
                }
                isUpdating = false
            }

            engine.setDocument(textView.string, language: p.language)
            if let ts = textView.textStorage, ts.length > 0 {
                // Single highlight pass. The debounced pass is ONLY for live
                // typing (Coordinator.textDidChange); doing both here doubled
                // every retokenization and compounded the open-file freeze.
                engine.applyHighlightingAsync(to: ts, fontSize: p.fontSize, font: textView.font)
            }

            let glyphs = textView.layoutManager?.numberOfGlyphs ?? -1
            CrashReporter.shared.breadcrumb("SHCV.applyContent force=\(force) lang=\(p.language) tvFrame=\(Int(textView.frame.width))x\(Int(textView.frame.height)) content=\(Int(scrollView.contentSize.width))x\(Int(scrollView.contentSize.height)) glyphs=\(glyphs) tsLen=\(textView.textStorage?.length ?? -1) draws=\(textView.drawsBackground) hidden=\(textView.isHidden) win=\(textView.window != nil)")

            scheduleRenderSelfTest(textView, scrollView)
        }

        func configureTextGeometry(for textView: NSTextView, in scrollView: NSScrollView) {
            // Canonical, stable "wrapping" NSTextView-in-NSScrollView setup.
            // We always wrap to the scroll view's width instead of toggling
            // isHorizontallyResizable. Mixing isHorizontallyResizable = true
            // with autoresizingMask = [.width] and an infinite-width container
            // (the previous non-wrap path) made the text view's drawable area
            // collapse — glyphs were laid out but never drawn (black screen),
            // and fed size oscillation into SwiftUI's _FlexFrameLayout
            // (immediate crash inside Playground/Notebook).
            let contentSize = scrollView.contentSize
            let targetWidth = max(1, contentSize.width)
            let targetHeight = max(1, contentSize.height)

            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.minSize = NSSize(width: 0, height: targetHeight)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                      height: CGFloat.greatestFiniteMagnitude)

            if let container = textView.textContainer {
                container.widthTracksTextView = true
                container.containerSize = NSSize(width: targetWidth,
                                                 height: CGFloat.greatestFiniteMagnitude)
            }

            // Make the document view fill the scroll view's width so text is
            // immediately visible. Height only ever grows (the layout manager
            // owns the real height once glyphs are laid out).
            let newWidth = targetWidth
            let newHeight = max(textView.frame.height, targetHeight)
            if abs(textView.frame.width - newWidth) > 0.5 ||
                abs(textView.frame.height - newHeight) > 0.5 {
                textView.setFrameSize(NSSize(width: newWidth, height: newHeight))
            }
            let fg = textView.textColor?.description ?? "nil"
            let bg = textView.backgroundColor.description
            CrashReporter.shared.breadcrumb("SHCV.configureTextGeometry content=\(Int(contentSize.width))x\(Int(contentSize.height)) tvFrame=\(Int(textView.frame.width))x\(Int(textView.frame.height)) tsLen=\(textView.textStorage?.length ?? -1) draws=\(textView.drawsBackground) fg=\(fg) bg=\(bg)")
        }
        
        deinit {
            // Mark as invalidated FIRST so async callbacks bail out
            isInvalidated = true
            // Cancel any in-flight highlighting task on deallocation
            highlightTimer?.invalidate()
            engine?.cancelHighlighting()
            
            // Break possible retain cycles
            engine = nil
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
                    
                    // CRASH FIX: Validate bounds before accessing attributes
                    if textStorage.length > 0 && checkLocation < textStorage.length {
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
                    
                    // NOTE: ensureLayout removed — it was forcing synchronous layout of entire
                    // document on every keystroke, causing multi-second freezes on large files.
                    // The layout manager handles incremental layout automatically.
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
                guard let self = self, !self.isInvalidated else { return }
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
            
            // CRASH FIX: Early return if text storage is empty
            guard let textStorage = textView.textStorage,
                  textStorage.length > 0 else { return }
            
            // Context-Aware Typing Attributes (Zero-Flash Typing)
            // When cursor moves, checking the token at the cursor allows us to pre-set the color
            // So if I click inside a green string, I type green immediately.
            
            let location = range.location
            // Check character BEFORE cursor (to inherit)
            let checkLocation = max(0, location - 1)
            
            // CRASH FIX: Double-check bounds
            if checkLocation < textStorage.length {
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
            highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, !self.isInvalidated else { return }
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
