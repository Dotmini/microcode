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
//  Copyright © 2025 Dotmini Company Limited. All rights reserved.
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
        
        // Core & Systems
        register("rust") { createRustLexer() }
        register("rs") { createRustLexer() }
        register("ardium") { createArdiumLexer() }
        register("ar") { createArdiumLexer() }
        register("swift") { createSwiftLexer() }
        register("c") { createCLexer() }
        register("h") { createCLexer() }
        register("cpp") { createCppLexer() }
        register("c++") { createCppLexer() }
        register("cc") { createCppLexer() }
        register("cxx") { createCppLexer() }
        register("hpp") { createCppLexer() }
        register("hxx") { createCppLexer() }
        register("hh") { createCppLexer() }
        register("arduino") { createCppLexer() }
        register("ino") { createCppLexer() }
        register("objc") { createObjCLexer() }
        register("objective-c") { createObjCLexer() }
        register("m") { createObjCLexer() }
        register("objcpp") { createObjCLexer() }
        register("objective-cpp") { createObjCLexer() }
        register("mm") { createObjCLexer() }
        register("zig") { createZigLexer() }
        register("go") { createGoLexer() }
        register("golang") { createGoLexer() }
        register("solidity") { createSolidityLexer() }
        register("sol") { createSolidityLexer() }

        // Mobile & Managed
        register("java") { createJavaLexer() }
        register("kotlin") { createKotlinLexer() }
        register("kt") { createKotlinLexer() }
        register("kts") { createKotlinLexer() }
        register("scala") { createKotlinLexer() }
        register("groovy") { createJavaLexer() }
        register("csharp") { createCSharpLexer() }
        register("cs") { createCSharpLexer() }
        register("c#") { createCSharpLexer() }
        register("dart") { createDartLexer() }

        // Web & Frontend
        register("javascript") { createJavaScriptLexer() }
        register("js") { createJavaScriptLexer() }
        register("jsx") { createJavaScriptLexer() }
        register("mjs") { createJavaScriptLexer() }
        register("cjs") { createJavaScriptLexer() }
        register("typescript") { createTypeScriptLexer() }
        register("ts") { createTypeScriptLexer() }
        register("tsx") { createTypeScriptLexer() }
        register("mts") { createTypeScriptLexer() }
        register("cts") { createTypeScriptLexer() }
        register("html") { createHtmlLexer() }
        register("htm") { createHtmlLexer() }
        register("xhtml") { createHtmlLexer() }
        register("xml") { createHtmlLexer() }
        register("svg") { createHtmlLexer() }
        register("vue") { createHtmlLexer() }
        register("svelte") { createHtmlLexer() }
        register("css") { createCssLexer() }
        register("scss") { createCssLexer() }
        register("sass") { createCssLexer() }
        register("less") { createCssLexer() }
        register("php") { createPhpLexer() }
        register("phtml") { createPhpLexer() }
        register("php8") { createPhpLexer() }

        // Scripting & Shell
        register("python") { createPythonLexer() }
        register("py") { createPythonLexer() }
        register("ruby") { createRubyLexer() }
        register("rb") { createRubyLexer() }
        register("lua") { createLuaLexer() }
        register("shell") { createShellLexer() }
        register("sh") { createShellLexer() }
        register("bash") { createShellLexer() }
        register("zsh") { createShellLexer() }
        register("fish") { createShellLexer() }
        register("perl") { createPythonLexer() }
        register("pl") { createPythonLexer() }
        register("pm") { createPythonLexer() }

        // Data, Query, & Config
        register("sql") { createSqlLexer() }
        register("pgsql") { createSqlLexer() }
        register("mysql") { createSqlLexer() }
        register("sqlite") { createSqlLexer() }
        register("plsql") { createSqlLexer() }
        register("json") { createJsonLexer() }
        register("jsonc") { createJsonLexer() }
        register("yaml") { createYamlLexer() }
        register("yml") { createYamlLexer() }
        register("toml") { createYamlLexer() }
        register("ini") { createYamlLexer() }
        register("conf") { createYamlLexer() }
        register("config") { createYamlLexer() }
        register("env") { createYamlLexer() }
        register("markdown") { createMarkdownLexer() }
        register("md") { createMarkdownLexer() }
        register("mdown") { createMarkdownLexer() }
        register("mkd") { createMarkdownLexer() }
        register("graphql") { createJavaScriptLexer() }
        register("gql") { createJavaScriptLexer() }

        // Functional & Scientific
        register("r") { createRLexer() }
        register("julia") { createJuliaLexer() }
        register("jl") { createJuliaLexer() }
        register("elixir") { createElixirLexer() }
        register("ex") { createElixirLexer() }
        register("exs") { createElixirLexer() }
        
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
    
    /// Purges idle and inactive lexer and line caches to save memory
    public func purgeInactiveCaches() {
        lock.lock()
        defer { lock.unlock() }
        for (lang, lexer) in loadedLexers where lang != currentLanguage {
            lexer.cache.purgeMemory()
        }
        cachedAttributedString = nil
        cachedLineOffsets = nil
    }
    
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
    
    /// Fast O(log N) lookup of 0-indexed (line, character) from a UTF-16 offset using `cachedLineOffsets`.
    public func lineAndColumn(for utf16Offset: Int) -> (line: Int, character: Int) {
        lock.lock()
        let offsets = cachedLineOffsets
        let content = documentContent
        lock.unlock()
        
        if let offsets = offsets, !offsets.isEmpty {
            var low = 0
            var high = offsets.count
            while low < high {
                let mid = low + (high - low) / 2
                if offsets[mid] <= utf16Offset {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            let line = max(0, low - 1)
            let lineStart = offsets[line]
            return (line, max(0, utf16Offset - lineStart))
        }
        
        let nsText = content as NSString
        let safeLoc = max(0, min(utf16Offset, nsText.length))
        let prefix = nsText.substring(to: safeLoc)
        let lines = prefix.components(separatedBy: "\n")
        return (max(0, lines.count - 1), lines.last?.utf16.count ?? 0)
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
    /// Currently running chunked attribute-application task on MainActor
    private var currentApplyTask: Task<Void, Never>?
    
    /// Cancel any in-flight highlighting task
    public func cancelHighlighting() {
        currentHighlightTask?.cancel()
        currentHighlightTask = nil
        currentApplyTask?.cancel()
        currentApplyTask = nil
    }
    
    /// Releases cached document string, attributed string, and lexer line cache from RAM.
    public func clearCache() {
        lock.lock()
        documentContent = ""
        cachedAttributedString = nil
        activeLexer = nil
        lock.unlock()
    }
    
    /// Asynchronously apply highlighting to an existing NSTextStorage.
    /// Uses true dirty-line incremental application so typing on a single line only updates that line's tokens.
    @MainActor
    public func applyHighlightingAsync(to textStorage: NSTextStorage, fontSize: CGFloat, font: NSFont? = nil, completion: (@MainActor @Sendable () -> Void)? = nil) {
        // Cancel previous tasks to prevent "task explosion" and race conditions
        currentHighlightTask?.cancel()
        currentApplyTask?.cancel()
        
        lock.lock()
        let content = documentContent
        let lexer = activeLexer
        let version = currentVersion
        let cachedLines = cachedLineOffsets?.count ?? 200
        lock.unlock()
        
        guard let lexer = lexer else {
            completion?()
            return
        }
        
        if cachedLines < 150 && content.utf16.count < 6000 {
            // SYNC PATH (Zero Flash) — small files only
            let update = lexer.retokenizeDirtyRegionsIncremental(in: content)
            self.applyIncrementalUpdate(update, to: textStorage, fontSize: fontSize, font: font, expectedVersion: version)
            completion?()
            return
        }
        
        // ASYNC PATH (Large Docs)
        currentHighlightTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                await MainActor.run { completion?() }
                return
            }
            
            if Task.isCancelled {
                await MainActor.run { completion?() }
                return
            }
            
            // 1. Re-lex dirty regions incrementally
            let update = lexer.retokenizeDirtyRegionsIncremental(in: content)
            
            if Task.isCancelled {
                await MainActor.run { completion?() }
                return
            }
            
            // 2. Apply attributes on the main thread (only dirty lines for edits!)
            await MainActor.run {
                defer { completion?() }
                if Task.isCancelled { return }
                
                self.lock.lock()
                let isStillValid = (self.currentVersion == version && self.documentContent.utf16.count == textStorage.length)
                self.lock.unlock()
                
                if isStillValid {
                    self.applyIncrementalUpdate(update, to: textStorage, fontSize: fontSize, font: font, expectedVersion: version)
                }
            }
        }
    }
    
    @MainActor
    private func applyIncrementalUpdate(
        _ update: IncrementalLexer.IncrementalHighlightUpdate,
        to textStorage: NSTextStorage,
        fontSize: CGFloat,
        font: NSFont?,
        expectedVersion: Int? = nil
    ) {
        if update.isFullDocument {
            applyTokens(update.tokens, to: textStorage, fontSize: fontSize, font: font, expectedVersion: expectedVersion)
            return
        }
        guard let dirtyRange = update.dirtyCharRange, dirtyRange.length > 0 else { return }
        let storageLength = textStorage.length
        guard dirtyRange.location >= 0, dirtyRange.location < storageLength else { return }
        let clampedLength = min(dirtyRange.length, storageLength - dirtyRange.location)
        guard clampedLength > 0 else { return }
        let safeRange = NSRange(location: dirtyRange.location, length: clampedLength)
        
        let defaultFont = font ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let defaultColor = themeManager.editorForegroundColor
        
        textStorage.beginEditing()
        // Reset the edited line(s) to default foreground/font first so removed keywords lose stale colors immediately
        textStorage.addAttributes([
            .foregroundColor: defaultColor,
            .font: defaultFont,
            .ligature: 0
        ], range: safeRange)
        textStorage.removeAttribute(.underlineStyle, range: safeRange)
        applyTokensBatch(update.tokens, to: textStorage, defaultFont: defaultFont, fontSize: fontSize)
        textStorage.endEditing()
    }
    
    /// Internal helper to apply attributes for specific tokens.
    /// CRITICAL: Must be called on the main thread.
    /// Uses chunking to prevent Main Thread blocking on large updates.
    @MainActor
    private func applyTokens(_ tokens: [SyntaxToken], to textStorage: NSTextStorage, fontSize: CGFloat, font: NSFont?, expectedVersion: Int? = nil) {
        assert(Thread.isMainThread, "applyTokens must be called on the main thread")
        currentApplyTask?.cancel()
        
        let defaultFont = font ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        
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
        currentApplyTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            var startIndex = 0
            while startIndex < tokens.count {
                if Task.isCancelled { return }
                if let expectedVersion = expectedVersion {
                    self.lock.lock()
                    let valid = (self.currentVersion == expectedVersion && self.documentContent.utf16.count == textStorage.length)
                    self.lock.unlock()
                    if !valid { return }
                }
                
                let endIndex = min(startIndex + chunkSize, tokens.count)
                let chunk = Array(tokens[startIndex..<endIndex])
                
                textStorage.beginEditing()
                self.applyTokensBatch(chunk, to: textStorage, defaultFont: defaultFont, fontSize: fontSize)
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
         let boldFont = NSFont(descriptor: defaultFont.fontDescriptor.withSymbolicTraits(.bold), size: fontSize) ?? defaultFont
         let italicFont = NSFont(descriptor: defaultFont.fontDescriptor.withSymbolicTraits(.italic), size: fontSize) ?? defaultFont
         let boldItalicFont = NSFont(descriptor: defaultFont.fontDescriptor.withSymbolicTraits([.bold, .italic]), size: fontSize) ?? defaultFont
         let storageLength = textStorage.length
         let forceUpdateSmall = storageLength < 500
         
         for token in tokens {
             let nsRange = token.range.nsRange
             
             // Ensure range is within bounds
             if nsRange.location >= 0 && nsRange.length > 0 && nsRange.location + nsRange.length <= storageLength {
                 let targetColor = themeManager.color(for: token.type)
                 var attributes: [NSAttributedString.Key: Any] = [
                     .foregroundColor: targetColor,
                     .ligature: 0
                 ]
                 
                 let style = themeManager.style(for: token.type)
                 if style.isBold && style.isItalic {
                     attributes[.font] = boldItalicFont
                 } else if style.isBold {
                     attributes[.font] = boldFont
                 } else if style.isItalic {
                     attributes[.font] = italicFont
                 }
                 
                 if style.isUnderline {
                     attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                 }
                 
                 // Optimization: Skip update if color matches (Prevent Flicker)
                 if forceUpdateSmall {
                     textStorage.addAttributes(attributes, range: nsRange)
                 } else {
                     let currentAttrs = textStorage.attributes(at: nsRange.location, effectiveRange: nil)
                     let currentColor = currentAttrs[.foregroundColor] as? NSColor
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
            DispatchQueue.main.async {
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
    
    private static let quickHighlightLock = NSLock()
    private static let sharedQuickEngine = SyntaxHighlightingEngine()
    private static var swiftUIAttributedCache: [Int: AttributedString] = [:]
    
    /// Quick highlight for a single string (non-incremental), reusing a shared engine instance.
    public static func highlight(
        _ code: String,
        language: String,
        fontSize: CGFloat,
        isDark: Bool = true
    ) -> NSAttributedString {
        quickHighlightLock.lock()
        defer { quickHighlightLock.unlock() }
        
        sharedQuickEngine.themeManager.setActiveTheme(isDark ? "dark" : "light")
        sharedQuickEngine.setDocument(code, language: language)
        return sharedQuickEngine.highlightedAttributedString(fontSize: fontSize)
    }
    
    /// Cached SwiftUI AttributedString for read-only code blocks (e.g. AI Chat NativeCodeBlockView).
    public static func cachedSwiftUIAttributedString(
        _ code: String,
        language: String,
        fontSize: CGFloat,
        isDark: Bool = true
    ) -> AttributedString {
        var hasher = Hasher()
        hasher.combine(code)
        hasher.combine(language.lowercased())
        hasher.combine(Int(fontSize * 10))
        hasher.combine(isDark)
        let key = hasher.finalize()
        
        quickHighlightLock.lock()
        if let cached = swiftUIAttributedCache[key] {
            quickHighlightLock.unlock()
            return cached
        }
        
        sharedQuickEngine.themeManager.setActiveTheme(isDark ? "dark" : "light")
        sharedQuickEngine.setDocument(code, language: language)
        let nsAttr = sharedQuickEngine.highlightedAttributedString(fontSize: fontSize)
        sharedQuickEngine.clearCache()
        let swiftAttr = (try? AttributedString(nsAttr, including: \.appKit)) ?? AttributedString(code)
        if swiftUIAttributedCache.count > 256 {
            swiftUIAttributedCache.removeAll(keepingCapacity: true)
        }
        swiftUIAttributedCache[key] = swiftAttr
        quickHighlightLock.unlock()
        return swiftAttr
    }
    
    public static func purgeQuickHighlightCache() {
        quickHighlightLock.lock()
        swiftUIAttributedCache.removeAll(keepingCapacity: false)
        sharedQuickEngine.clearCache()
        quickHighlightLock.unlock()
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

/// Interactive NSTextView supporting Cmd+Click (Go to Definition), Option+Click (Quick Help Hover), and F12.
final class IDEInteractiveTextView: NSTextView {
    var onGoToDefinitionAtCharIndex: ((Int) -> Void)?
    var onQuickHelpAtCharIndex: ((Int, NSPoint) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) && !flags.contains(.shift) {
            let point = convert(event.locationInWindow, from: nil)
            let charIdx = characterIndexForInsertion(at: point)
            onGoToDefinitionAtCharIndex?(charIdx)
            return
        }
        if flags.contains(.option) && !flags.contains(.command) {
            let point = convert(event.locationInWindow, from: nil)
            let charIdx = characterIndexForInsertion(at: point)
            onQuickHelpAtCharIndex?(charIdx, point)
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // F12 -> Go to Definition
        if event.keyCode == 111 {
            onGoToDefinitionAtCharIndex?(selectedRange().location)
            return
        }
        super.keyDown(with: event)
    }
}

// Custom NSScrollView to prevent SwiftUI from attempting to size the scroll view
// based on the length of the code inside the NSTextView. This definitively breaks
// the AppKit layout recursion loop (_FlexFrameLayout) that causes EXC_BREAKPOINT.
class NoIntrinsicScrollView: NSScrollView {
    private(set) var lineNumberGutter: EditorLineNumberGutterView?

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
        if let gutter = lineNumberGutter {
            gutter.frame = NSRect(
                x: 0,
                y: 0,
                width: EditorLineNumberGutterView.preferredWidth,
                height: bounds.height
            )
        }
        guard let tv = documentView as? NSTextView else { return }
        let w = contentSize.width
        let h = contentSize.height
        guard w > 1 else { return }
        var didResize = false
        if abs(tv.frame.width - w) > 0.5 {
            tv.setFrameSize(NSSize(width: w, height: max(tv.frame.height, h)))
            didResize = true
        } else if tv.frame.height < h {
            tv.setFrameSize(NSSize(width: tv.frame.width, height: h))
            didResize = true
        }
        if let tc = tv.textContainer {
            let insetW = tv.textContainerInset.width * 2
            let targetContainerWidth = max(1, w - insetW)
            if abs(tc.containerSize.width - targetContainerWidth) > 1.0 {
                tc.containerSize = NSSize(width: targetContainerWidth, height: .greatestFiniteMagnitude)
                didResize = true
            }
            if didResize {
                tv.layoutManager?.ensureLayout(forBoundingRect: contentView.bounds, in: tc)
                tv.needsDisplay = true
                contentView.needsDisplay = true
                lineNumberGutter?.needsDisplay = true
            }
        }
    }

    func configureLineNumbers(
        visible: Bool,
        textView: NSTextView,
        themeManager: ThemeManager,
        fileURL: URL? = nil
    ) {
        if visible {
            if let gutter = lineNumberGutter {
                gutter.updateAppearance(themeManager: themeManager, fileURL: fileURL)
            } else {
                let gutter = EditorLineNumberGutterView(
                    textView: textView,
                    clipView: contentView,
                    themeManager: themeManager,
                    fileURL: fileURL
                )
                addSubview(gutter, positioned: .above, relativeTo: contentView)
                lineNumberGutter = gutter
            }
            textView.textContainerInset = NSSize(
                width: EditorLineNumberGutterView.preferredWidth + 5,
                height: 8
            )
        } else {
            lineNumberGutter?.detach()
            lineNumberGutter?.removeFromSuperview()
            lineNumberGutter = nil
            textView.textContainerInset = NSSize(width: 5, height: 8)
        }
        needsLayout = true
    }
}

public struct SyntaxHighlightedCodeView: NSViewRepresentable {
    @EnvironmentObject var appState: AppState
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
    public let isEditable: Bool
    public let enableHighlighting: Bool
    public let showLineNumbers: Bool
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

    /// Purges cached NSScrollViews that are no longer mounted in any active window,
    /// freeing tens of megabytes of TextKit glyph and layout backing memory.
    @MainActor
    public static func purgeNonVisibleViewCache() {
        let keys = Array(viewCache.keys)
        for key in keys {
            if let sv = viewCache[key], sv.window == nil {
                if let tv = sv.documentView as? NSTextView {
                    tv.string = ""
                }
                viewCache.removeValue(forKey: key)
            }
        }
    }

    public init(text: Binding<String>, language: String, fontSize: CGFloat = 13, isDark: Bool = true, themeName: String? = nil, fontName: String = "Menlo", fontWeight: Int = 2, fileURL: URL? = nil, isScrollEnabled: Bool = true, isTransparent: Bool = false, isEditable: Bool = true, enableHighlighting: Bool = true, showLineNumbers: Bool = false, editorID: String? = nil) {
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
        self.isEditable = isEditable
        self.enableHighlighting = enableHighlighting
        self.showLineNumbers = showLineNumbers
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

        // REUSE: Only reuse a cached scroll view if it is NOT currently mounted
        // in an active superview/window. Handing the same NSView instance to
        // two live AppKitPlatformViewHosts simultaneously corrupts AppKit's view
        // hierarchy and causes two Coordinators to fight over the same textView.
        if let id = editorID, let cached = Self.viewCache[id],
           cached.superview == nil, cached.window == nil,
           let tv = cached.documentView as? NSTextView {
            let engine = SyntaxHighlightingEngine()
            context.coordinator.engine = engine
            context.coordinator.textView = tv
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
        let textView = IDEInteractiveTextView(usingTextLayoutManager: false)
        textView.layoutManager?.allowsNonContiguousLayout = true
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
        context.coordinator.textView = textView
        let coord = context.coordinator
        textView.onGoToDefinitionAtCharIndex = { [weak coord, weak textView] charIdx in
            guard let coord, let tv = textView else { return }
            coord.handleGoToDefinition(at: charIdx, in: tv)
        }
        textView.onQuickHelpAtCharIndex = { [weak coord, weak textView] charIdx, point in
            guard let coord, let tv = textView else { return }
            coord.handleQuickHelp(at: charIdx, point: point, in: tv)
        }

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
            tv.isEditable = isEditable
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

            // Never attach an NSRulerView here. It shifts the clip-view origin
            // and previously caused blank editors/layout recursion. The safe
            // gutter is a visual overlay managed by NoIntrinsicScrollView.
            scrollView.verticalRulerView = nil
            scrollView.hasVerticalRuler  = false
            scrollView.rulersVisible     = false
            scrollView.configureLineNumbers(
                visible: coordinator.parent.showLineNumbers,
                textView: tv,
                themeManager: engine.themeManager,
                fileURL: coordinator.parent.fileURL
            )
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

            // AppState owns document-open notifications and applies file-size
            // limits. Sending a second notification here duplicated large
            // strings and could wake the LSP twice for every opened file.
        }

        // Push initial content + highlighting NOW (synchronous) so the editor
        // is never blank waiting on an async tick. SwiftUI also calls
        // updateNSView right after this, which is a cheap no-op if unchanged.
        context.coordinator.applyContent(self, to: textView, scrollView: scrollView, force: true)

        // Cache so subsequent SwiftUI identity churn reuses THIS view.
        if let id = editorID {
            Self.viewCache[id] = scrollView
            // Keep at most 2 cached editor scrollViews (primary + split); immediately release unmounted TextKit buffers.
            if Self.viewCache.count > 2 {
                for key in Self.viewCache.keys where key != id {
                    if let evicted = Self.viewCache[key], evicted.window == nil {
                        if let tv = evicted.documentView as? NSTextView {
                            tv.string = ""
                        }
                        Self.viewCache.removeValue(forKey: key)
                    }
                    if Self.viewCache.count <= 2 { break }
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
        var lspChangeTask: Task<Void, Never>?
        var autocompleteTask: Task<Void, Never>?
        var bindingSyncTask: Task<Void, Never>?
        var isUpdating = false
        var isInsertingCompletion = false
        var isInvalidated = false // Prevents async callbacks after teardown
        
        // Weak reference to the text view to insert completions
        weak var textView: NSTextView?
        
        // Engine is now owned by the Coordinator (PERSISTENT)
        var engine: SyntaxHighlightingEngine? // Changed to var and optional
        
        // Cache for change detection
        var lastText: String = ""
        var lastLanguage: String = ""
        var lastThemeName: String?
        var lastFontSize: CGFloat = 0
        var lastIsDark: Bool = false
        var lastIsTransparent: Bool = false  // FIX: track transparent mode
        var lastIsEditable: Bool = true
        var lastEnableHighlighting: Bool = true
        var lastShowLineNumbers: Bool = false
        var lastFileURL: URL? = nil // Added fileURL to cache
        var didRenderSelfTest = false
        var lastAutocompleteCursorLoc: Int = -1

        init(_ parent: SyntaxHighlightedCodeView) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInsertCompletionNotification(_:)),
                name: Notification.Name("InsertLSPCompletionItem"),
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleJumpToLineNotification(_:)),
                name: Notification.Name("JumpToLineNotification"),
                object: nil
            )
        }
        
        @objc private func handleInsertCompletionNotification(_ notification: Notification) {
            guard let fileURL = parent.fileURL,
                  parent.appState.currentFile?.path == fileURL.path,
                  let userInfo = notification.userInfo,
                  let item = userInfo["item"] as? CompletionItem,
                  let tv = textView else {
                return
            }
            
            self.insertCompletion(item, into: tv)
        }
        
        @objc private func handleJumpToLineNotification(_ notification: Notification) {
            guard let fileURL = parent.fileURL,
                  parent.appState.currentFile?.path == fileURL.path,
                  let userInfo = notification.userInfo,
                  let line = userInfo["line"] as? Int,
                  let tv = textView else {
                return
            }
            
            let text = tv.string
            let nsText = text as NSString
            let lines = text.components(separatedBy: "\n")
            
            // line is 1-indexed in xcodebuild
            let targetLine = max(0, line - 1)
            guard targetLine < lines.count else { return }
            
            var charIndex = 0
            for i in 0..<targetLine {
                charIndex += lines[i].count + 1 // +1 for the newline character
            }
            
            if let col = userInfo["column"] as? Int {
                charIndex += max(0, col - 1)
            }
            
            let finalIndex = min(nsText.length, charIndex)
            tv.setSelectedRange(NSRange(location: finalIndex, length: 0))
            tv.scrollRangeToVisible(NSRange(location: finalIndex, length: 0))
        }

        /// Single, synchronous code path that configures geometry/theme/font
        /// and pushes the (highlighted) text into the view. Shared by
        /// makeNSView (force=true) and updateNSView (force=false).
        func applyContent(_ p: SyntaxHighlightedCodeView,
                          to textView: NSTextView,
                          scrollView: NSScrollView,
                          force: Bool) {
            guard let engine = engine else { return }
            self.parent = p

            let langChanged = lastLanguage != p.language
            let themeNameChanged = lastThemeName != p.themeName
            let fontChanged = lastFontSize != p.fontSize
            let darkChanged = lastIsDark != p.isDark
            let transparentChanged = lastIsTransparent != p.isTransparent
            let editableChanged = lastIsEditable != p.isEditable
            let highlightingChanged = lastEnableHighlighting != p.enableHighlighting
            let lineNumbersChanged = lastShowLineNumbers != p.showLineNumbers
            let visualConfigChanged = langChanged || themeNameChanged || fontChanged
                || darkChanged || transparentChanged || editableChanged
                || highlightingChanged || lineNumbersChanged

            // ULTRA-FAST NO-OP PATH DURING LIVE TYPING:
            // When the user types in `textView`, `lastText` and `textView.string` already contain
            // the latest characters. Returning here avoids full-file string normalization,
            // `engine.setDocument` cache resets, redundant full-file re-lexing, and synchronous
            // `ensureLayout` stalls on every keystroke.
            if !force && !visualConfigChanged && (lastText == p.text || textView.string == p.text) {
                return
            }

            configureTextGeometry(for: textView, in: scrollView)

            let normalizedText = p.text.contains("\r") ? p.text.replacingOccurrences(of: "\r\n", with: "\n") : p.text
            let textChanged = lastText != normalizedText && textView.string != normalizedText

            if !force && !textChanged && !visualConfigChanged {
                lastText = normalizedText
                return
            }

            lastText = normalizedText
            lastLanguage = p.language
            lastThemeName = p.themeName
            lastFontSize = p.fontSize
            lastIsDark = p.isDark
            lastIsTransparent = p.isTransparent
            lastIsEditable = p.isEditable
            lastEnableHighlighting = p.enableHighlighting
            lastShowLineNumbers = p.showLineNumbers

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
            textView.isEditable = p.isEditable

            if force || lineNumbersChanged || themeNameChanged || darkChanged || fontChanged || lastFileURL != p.fileURL,
               let editorScrollView = scrollView as? NoIntrinsicScrollView {
                lastFileURL = p.fileURL
                editorScrollView.configureLineNumbers(
                    visible: p.showLineNumbers,
                    textView: textView,
                    themeManager: engine.themeManager,
                    fileURL: p.fileURL
                )
            }

            // Content replacement (only when external binding differs from NSTextView buffer)
            let didReplaceBuffer = (textView.string != normalizedText)
            if didReplaceBuffer {
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
                (scrollView as? NoIntrinsicScrollView)?.lineNumberGutter?.refreshContentIndex()
            }

            if force || didReplaceBuffer || langChanged || themeNameChanged || darkChanged || fontChanged || highlightingChanged {
                if p.enableHighlighting {
                    engine.setDocument(textView.string, language: p.language)
                } else {
                    engine.cancelHighlighting()
                }
                if p.enableHighlighting, let ts = textView.textStorage, ts.length > 0 {
                    engine.applyHighlightingAsync(to: ts, fontSize: p.fontSize, font: textView.font) { [weak textView, weak scrollView] in
                        if let tv = textView, let tc = tv.textContainer, let sv = scrollView {
                            tv.layoutManager?.ensureLayout(forBoundingRect: sv.contentView.bounds, in: tc)
                            tv.needsDisplay = true
                        }
                        scrollView?.contentView.needsDisplay = true
                        (scrollView as? NoIntrinsicScrollView)?.lineNumberGutter?.needsDisplay = true
                    }
                }
            }

            if let tc = textView.textContainer {
                textView.layoutManager?.ensureLayout(forBoundingRect: scrollView.contentView.bounds, in: tc)
            }
            textView.needsDisplay = true
            scrollView.contentView.needsDisplay = true
            (scrollView as? NoIntrinsicScrollView)?.lineNumberGutter?.needsDisplay = true
        }

        func configureTextGeometry(for textView: NSTextView, in scrollView: NSScrollView) {
            let contentSize = scrollView.contentSize
            let targetWidth = max(1, contentSize.width)
            let targetHeight = max(1, contentSize.height)

            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.minSize = NSSize(width: 0, height: targetHeight)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                      height: CGFloat.greatestFiniteMagnitude)

            let newWidth = targetWidth
            let newHeight = max(textView.frame.height, targetHeight)
            if abs(textView.frame.width - newWidth) > 0.5 ||
                abs(textView.frame.height - newHeight) > 0.5 {
                textView.setFrameSize(NSSize(width: newWidth, height: newHeight))
            }

            if let container = textView.textContainer {
                let insetW = textView.textContainerInset.width * 2
                let containerWidth = max(1, targetWidth - insetW)
                container.widthTracksTextView = true
                if abs(container.containerSize.width - containerWidth) > 0.5 {
                    container.containerSize = NSSize(width: containerWidth,
                                                     height: CGFloat.greatestFiniteMagnitude)
                }
            }
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
            isInvalidated = true
            highlightTimer?.invalidate()
            lspChangeTask?.cancel()
            autocompleteTask?.cancel()
            bindingSyncTask?.cancel()
            engine?.cancelHighlighting()
            engine = nil
        }
        
        // MARK: - NSTextStorageDelegate (Incremental Updates)
        
        public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range: NSRange, changeInLength: Int) {
            guard !isUpdating else { return }
            
            // IME-FIRST: Skip processing if IME composition is in progress
            if let layoutManager = textStorage.layoutManagers.first,
               let textContainer = layoutManager.textContainers.first,
               let textView = textContainer.textView,
               textView.hasMarkedText() {
                return
            }
            
            if editedMask.contains(.editedCharacters) {
                let fullString = textStorage.string
                self.lastText = fullString
                
                if parent.enableHighlighting {
                    engine?.processEdit(range: range, changeInLength: changeInLength, newContent: fullString)
                }
                
                // Debounce background LSP didChange when not immediately requesting completion
                if let url = parent.fileURL {
                    let language = parent.language
                    lspChangeTask?.cancel()
                    lspChangeTask = Task {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard !Task.isCancelled else { return }
                        await LSPManager.shared.documentChanged(uri: url.absoluteString, language: language, content: fullString)
                    }
                }
                
                // Trigger Official Autocomplete when user is actively typing or editing in the focused editor
                if !isInsertingCompletion,
                   let layoutManager = textStorage.layoutManagers.first,
                   let textContainer = layoutManager.textContainers.first,
                   let textView = textContainer.textView,
                   textView.window?.firstResponder === textView {
                    
                    let nsString = fullString as NSString
                    let isSingleCharInsert = (changeInLength == 1 && range.length == 1 && range.location + 1 <= nsString.length)
                    let isSingleCharBackspace = (changeInLength == -1 && range.length == 0 && parent.appState.showingCompletions)
                    
                    if isSingleCharInsert || isSingleCharBackspace {
                        let cursorLoc = min(nsString.length, range.location + range.length)
                        let ctx = Self.extractCompletionContext(at: cursorLoc, in: nsString)
                        
                        if ctx.shouldTrigger {
                            self.lastAutocompleteCursorLoc = cursorLoc
                            triggerAutocompleteRequest(
                                at: cursorLoc,
                                context: ctx,
                                content: fullString,
                                layoutManager: layoutManager,
                                textContainer: textContainer,
                                textView: textView
                            )
                        } else {
                            autocompleteTask?.cancel()
                            if parent.appState.showingCompletions {
                                parent.appState.dismissCompletions()
                            }
                        }
                    } else {
                        autocompleteTask?.cancel()
                        if parent.appState.showingCompletions {
                            parent.appState.dismissCompletions()
                        }
                    }
                }
                
                // Inherit typingAttributes from edited token for zero-flash typing
                if let layoutManager = textStorage.layoutManagers.first,
                   let textContainer = layoutManager.textContainers.first,
                   let textView = textContainer.textView {
                    let endLocation = range.location + range.length
                    let checkLocation = max(0, endLocation - 1)
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
                }
            }
        }
        
        private struct CursorCompletionContext {
            let wordPrefix: String
            let wordStart: Int
            let triggerCharacter: String?
            let isMemberAccess: Bool
            var shouldTrigger: Bool {
                isMemberAccess || !wordPrefix.isEmpty
            }
        }
        
        private static func extractCompletionContext(at cursorLoc: Int, in nsText: NSString) -> CursorCompletionContext {
            guard cursorLoc > 0, cursorLoc <= nsText.length else {
                return CursorCompletionContext(wordPrefix: "", wordStart: cursorLoc, triggerCharacter: nil, isMemberAccess: false)
            }
            
            // Scan backwards for identifier characters (`[A-Za-z0-9_@]`)
            var wordStart = cursorLoc
            while wordStart > 0 {
                let ch = nsText.character(at: wordStart - 1)
                if let scalar = UnicodeScalar(ch),
                   (CharacterSet.alphanumerics.contains(scalar) || ch == 95 /* _ */ || ch == 64 /* @ */) {
                    wordStart -= 1
                } else {
                    break
                }
            }
            
            let wordPrefix = nsText.substring(with: NSRange(location: wordStart, length: cursorLoc - wordStart))
            
            // Check character immediately before `wordStart` for member access (`.`, `:`, `>`)
            var isMemberAccess = false
            var triggerChar: String? = nil
            if wordStart > 0 {
                let prevUnichar = nsText.character(at: wordStart - 1)
                if prevUnichar == 46 /* . */ {
                    isMemberAccess = true
                    if wordPrefix.isEmpty { triggerChar = "." }
                } else if prevUnichar == 58 /* : */ {
                    // Check `::` or CSS/Swift `:`
                    isMemberAccess = true
                    if wordPrefix.isEmpty { triggerChar = ":" }
                } else if prevUnichar == 62 /* > */ && wordStart >= 2 && nsText.character(at: wordStart - 2) == 45 /* -> */ {
                    isMemberAccess = true
                    if wordPrefix.isEmpty { triggerChar = ">" }
                }
            }
            
            return CursorCompletionContext(
                wordPrefix: wordPrefix,
                wordStart: wordStart,
                triggerCharacter: triggerChar,
                isMemberAccess: isMemberAccess
            )
        }
        
        private func triggerAutocompleteRequest(
            at cursorLoc: Int,
            context: CursorCompletionContext,
            content: String,
            layoutManager: NSLayoutManager,
            textContainer: NSTextContainer,
            textView: NSTextView
        ) {
            let (line, charIndex) = engine?.lineAndColumn(for: cursorLoc) ?? getLSPPosition(for: cursorLoc, in: content)
            
            // Compute cursor rect in NSScrollView top-left coordinates
            let targetCharIdx = max(0, cursorLoc - 1)
            let charRange = NSRange(location: targetCharIdx, length: min(1, (content as NSString).length - targetCharIdx))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            layoutManager.ensureLayout(forGlyphRange: glyphRange)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            if rect.height <= 0, glyphRange.location < layoutManager.numberOfGlyphs {
                rect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            }
            let containerOrigin = textView.textContainerOrigin
            let cursorRect = rect.offsetBy(dx: containerOrigin.x, dy: containerOrigin.y)
            let scrollView = textView.enclosingScrollView
            let rectInScrollView = textView.convert(cursorRect, to: scrollView)
            
            let isFlipped = scrollView?.isFlipped ?? true
            let scrollHeight = scrollView?.bounds.height ?? 600
            let scrollWidth = scrollView?.bounds.width ?? 800
            let rawTopY = isFlipped ? rectInScrollView.origin.y : (scrollHeight - rectInScrollView.maxY)
            let lineHeight = max(18, rectInScrollView.height)
            let popupWidth: CGFloat = 420
            let clampedX = max(48, min(rectInScrollView.origin.x, max(48, scrollWidth - popupWidth - 16)))
            
            let popupEstimatedHeight: CGFloat = 240
            let finalY: CGFloat
            if rawTopY + lineHeight + popupEstimatedHeight > scrollHeight && rawTopY > popupEstimatedHeight {
                finalY = max(6, rawTopY - popupEstimatedHeight - 4)
            } else {
                finalY = max(6, rawTopY + lineHeight + 3)
            }
            let swiftuiRect = CGRect(x: clampedX, y: finalY, width: rectInScrollView.width, height: lineHeight)
            
            autocompleteTask?.cancel()
            lspChangeTask?.cancel() // `requestCompletions` will sync `documentChanged` directly
            autocompleteTask = Task { @MainActor [weak self] in
                // Brief 25ms coalesce so rapid typing cancels stale keystrokes before hitting LSP
                try? await Task.sleep(nanoseconds: 25_000_000)
                guard let self = self, !Task.isCancelled, !self.isInvalidated else { return }
                await self.parent.appState.requestCompletions(
                    line: line,
                    character: charIndex,
                    cursorRect: swiftuiRect,
                    content: content,
                    wordPrefix: context.wordPrefix,
                    triggerCharacter: context.triggerCharacter,
                    isMemberAccess: context.isMemberAccess
                )
            }
        }
        
        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !textView.hasMarkedText() else { return }
            guard !isUpdating else { return }
            
            let newText = textView.string
            // Keep `lastText` synced immediately so SwiftUI's `updateNSView` knows `textView`
            // already has this exact text and skips redundant full-document re-application.
            self.lastText = newText
            
            // Debounce SwiftUI `@Binding var text` propagation (90ms) so typing at 60-120 WPM
            // doesn't force SwiftUI to re-evaluate the parent view hierarchy on every single keystroke.
            bindingSyncTask?.cancel()
            bindingSyncTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 90_000_000)
                guard let self = self, !Task.isCancelled, !self.isInvalidated else { return }
                if self.parent.text != newText {
                    self.parent.text = newText
                }
            }

            // Trigger fast incremental highlight (50ms debounce)
            triggerDebouncedHighlight(for: textView)
        }
        
        public func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            bindingSyncTask?.cancel()
            let finalString = textView.string
            self.lastText = finalString
            if parent.text != finalString {
                parent.text = finalString
            }
        }
        
        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let range = textView.selectedRanges.first?.rangeValue,
                  range.length == 0 else {
                if parent.appState.showingCompletions {
                    parent.appState.dismissCompletions()
                }
                return
            }
            
            if parent.appState.showingCompletions && abs(range.location - lastAutocompleteCursorLoc) > 1 {
                parent.appState.dismissCompletions()
            }
            
            guard let textStorage = textView.textStorage,
                  textStorage.length > 0 else { return }
            
            let location = range.location
            let checkLocation = max(0, location - 1)
            
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
        }

        func triggerDebouncedHighlight(for textView: NSTextView?) {
            guard parent.enableHighlighting else { return }
            highlightTimer?.invalidate()
            highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, !self.isInvalidated else { return }
                    if let tv = textView {
                        self.applyHighlighting(to: tv)
                    }
                }
            }
        }
        
        // MARK: - Keyboard Navigation & Auto Indentation
        
        public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Manual completion trigger (Opt+Esc / F5 / complete:)
            if commandSelector == #selector(NSResponder.complete(_:)),
               let textStorage = textView.textStorage,
               let layoutManager = textStorage.layoutManagers.first,
               let textContainer = layoutManager.textContainers.first {
                let cursorLoc = textView.selectedRange().location
                let nsString = textStorage.string as NSString
                let ctx = Self.extractCompletionContext(at: cursorLoc, in: nsString)
                self.lastAutocompleteCursorLoc = cursorLoc
                triggerAutocompleteRequest(
                    at: cursorLoc,
                    context: CursorCompletionContext(
                        wordPrefix: ctx.wordPrefix,
                        wordStart: ctx.wordStart,
                        triggerCharacter: ctx.triggerCharacter,
                        isMemberAccess: ctx.isMemberAccess || ctx.wordPrefix.isEmpty
                    ),
                    content: textStorage.string,
                    layoutManager: layoutManager,
                    textContainer: textContainer,
                    textView: textView
                )
                return true
            }
            
            if parent.appState.showingCompletions {
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    parent.appState.selectNextCompletion()
                    return true
                } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    parent.appState.selectPreviousCompletion()
                    return true
                } else if commandSelector == #selector(NSResponder.insertNewline(_:)) || commandSelector == #selector(NSResponder.insertTab(_:)) {
                    if let selected = parent.appState.selectedCompletionItem {
                        insertCompletion(selected, into: textView)
                        return true
                    }
                } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    parent.appState.dismissCompletions()
                    return true
                }
            }
            
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                handleNewline(in: textView)
                return true
            }
            return false
        }
        
        private func insertCompletion(_ item: CompletionItem, into textView: NSTextView) {
            guard let range = textView.selectedRanges.first?.rangeValue else { return }
            let text = textView.string as NSString
            let cursorLocation = range.location
            
            let (resolvedText, cursorOffsetFromEnd) = item.resolvedInsertion()
            var insertText = resolvedText
            
            // Find prefix word start (including `@` for Swift attributes like `@State`)
            var wordStart = cursorLocation
            while wordStart > 0 {
                let ch = text.character(at: wordStart - 1)
                if let scalar = UnicodeScalar(ch),
                   (CharacterSet.alphanumerics.contains(scalar) || ch == 95 /* _ */ || ch == 64 /* @ */) {
                    wordStart -= 1
                } else {
                    break
                }
            }
            
            // Prevent double dot (`..frame`) when inserting a dot-prefixed completion after `.`
            if wordStart > 0 && text.character(at: wordStart - 1) == 46 /* . */ && insertText.hasPrefix(".") {
                insertText = String(insertText.dropFirst())
            }
            
            let wordRange = NSRange(location: wordStart, length: cursorLocation - wordStart)
            
            autocompleteTask?.cancel()
            parent.appState.dismissCompletions()
            
            isInsertingCompletion = true
            defer { isInsertingCompletion = false }
            
            if textView.shouldChangeText(in: wordRange, replacementString: insertText) {
                textView.replaceCharacters(in: wordRange, with: insertText)
                textView.didChangeText()
                
                let newCursorPos = max(0, wordStart + insertText.utf16.count - cursorOffsetFromEnd)
                textView.setSelectedRange(NSRange(location: newCursorPos, length: 0))
                
                let newText = textView.string
                self.lastText = newText
                bindingSyncTask?.cancel()
                if self.parent.text != newText {
                    self.parent.text = newText
                }
            }
        }
        
        private func getLSPPosition(for cursorLocation: Int, in text: String) -> (line: Int, character: Int) {
            if let engine = engine {
                return engine.lineAndColumn(for: cursorLocation)
            }
            var line = 0
            var character = 0
            let textNSString = text as NSString
            if cursorLocation <= textNSString.length {
                let prefix = textNSString.substring(to: cursorLocation)
                let lines = prefix.components(separatedBy: "\n")
                line = max(0, lines.count - 1)
                character = lines.last?.utf16.count ?? 0
            }
            return (line, character)
        }
        
        private func handleNewline(in textView: NSTextView) {
            guard let range = textView.selectedRanges.first?.rangeValue else { return }
            let text = textView.string
            let cursorLocation = range.location
            
            let prefix = (text as NSString).substring(to: cursorLocation)
            var currentLine = ""
            if let lastNewline = prefix.range(of: "\n", options: .backwards) {
                currentLine = String(prefix[lastNewline.upperBound...])
            } else {
                currentLine = prefix
            }
            
            var indentation = ""
            for char in currentLine {
                if char.isWhitespace {
                    indentation.append(char)
                } else {
                    break
                }
            }
            
            let trimmedLine = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let openers: [Character] = ["{", "(", "[", ":"]
            
            var shouldIndent = false
            if let lastChar = trimmedLine.last, openers.contains(lastChar) {
                shouldIndent = true
            }
            
            var insertString = "\n" + indentation
            if shouldIndent {
                insertString += "    "
            }
            
            if textView.shouldChangeText(in: range, replacementString: insertString) {
                textView.replaceCharacters(in: range, with: insertString)
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }
        
        private func applyHighlighting(to textView: NSTextView) {
            guard parent.enableHighlighting else { return }
            guard let textStorage = textView.textStorage,
                  let engine = engine else { return }
            guard !textView.hasMarkedText() else { return }
            
            isUpdating = true
            engine.applyHighlightingAsync(to: textStorage, fontSize: parent.fontSize, font: textView.font) { [weak self] in
                self?.isUpdating = false
            }
        }
        
        // MARK: - Cmd+Click / F12 Go-to-Definition & Option+Click Quick Help
        
        private static func extractIdentifierToken(at charIdx: Int, in nsText: NSString) -> String {
            guard nsText.length > 0 else { return "" }
            let clamped = max(0, min(charIdx, nsText.length - 1))
            var start = clamped
            while start > 0 {
                let c = nsText.character(at: start - 1)
                if let s = UnicodeScalar(c), (CharacterSet.alphanumerics.contains(s) || c == 95) {
                    start -= 1
                } else {
                    break
                }
            }
            var end = clamped
            while end < nsText.length {
                let c = nsText.character(at: end)
                if let s = UnicodeScalar(c), (CharacterSet.alphanumerics.contains(s) || c == 95) {
                    end += 1
                } else {
                    break
                }
            }
            guard end > start else { return "" }
            return nsText.substring(with: NSRange(location: start, length: end - start))
        }
        
        func handleGoToDefinition(at charIdx: Int, in textView: NSTextView) {
            guard let fileURL = parent.fileURL else { return }
            let content = textView.string
            let nsText = content as NSString
            let symbol = Self.extractIdentifierToken(at: charIdx, in: nsText)
            let (line, character) = getLSPPosition(for: charIdx, in: content)
            let uri = fileURL.standardizedFileURL.absoluteString
            let lang = parent.language
            let wsPath = parent.appState.workspaceFolder?.path
            
            Task { @MainActor in
                let locations = await LSPManager.shared.getDefinition(
                    uri: uri,
                    language: lang,
                    line: line,
                    character: character,
                    symbolHint: symbol,
                    workspacePath: wsPath
                )
                guard let loc = locations.first else { return }
                let targetURL: URL
                if let parsed = URL(string: loc.uri), parsed.isFileURL {
                    targetURL = parsed
                } else {
                    let cleanPath = loc.uri.replacingOccurrences(of: "file://", with: "")
                    targetURL = URL(fileURLWithPath: cleanPath)
                }
                let targetLine = loc.range.start.line + 1
                let targetCol = loc.range.start.character + 1
                
                if targetURL.standardizedFileURL.path != fileURL.standardizedFileURL.path {
                    await self.parent.appState.loadFile(url: targetURL)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(
                        name: Notification.Name("JumpToLineNotification"),
                        object: nil,
                        userInfo: ["line": targetLine, "column": targetCol]
                    )
                }
            }
        }
        
        func handleQuickHelp(at charIdx: Int, point: NSPoint, in textView: NSTextView) {
            guard let fileURL = parent.fileURL else { return }
            let content = textView.string
            let nsText = content as NSString
            let symbol = Self.extractIdentifierToken(at: charIdx, in: nsText)
            let (line, character) = getLSPPosition(for: charIdx, in: content)
            let uri = fileURL.standardizedFileURL.absoluteString
            let lang = parent.language
            
            Task { @MainActor in
                let hoverText = await LSPManager.shared.getHover(
                    uri: uri,
                    language: lang,
                    line: line,
                    character: character
                )
                let display = (hoverText?.isEmpty == false)
                    ? hoverText!
                    : (symbol.isEmpty ? nil : "Symbol: `\(symbol)` (\(lang.capitalized))\nTip: ⌘+Click or press F12 to jump to definition.")
                guard let display else { return }
                
                let popover = NSPopover()
                popover.behavior = .transient
                let controller = NSHostingController(
                    rootView: VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                            Text(symbol.isEmpty ? "Quick Help" : symbol)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Spacer()
                            Text(LSPManager.shared.activeSourceBadge)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        Divider()
                        ScrollView {
                            Text(display)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 180)
                    }
                    .padding(10)
                    .frame(width: 380)
                )
                popover.contentViewController = controller
                let anchorRect = NSRect(x: point.x, y: point.y, width: 2, height: 14)
                popover.show(relativeTo: anchorRect, of: textView, preferredEdge: .maxY)
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
