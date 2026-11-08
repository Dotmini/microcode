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
    /// Merged UTF-16 intervals already colored in the active NSTextStorage (enables O(visible) lazy scroll highlighting)
    private var appliedHighlightRanges: [NSRange] = []
    private var initialLexCompletedVersion: Int = -1
    
    // MARK: Rainbow bracket pair colorization (VS Code parity)
    /// Last LSP semantic overlay, keyed by UTF-16 start location. Re-applied whenever the lexer repaints a
    /// region (e.g. lazy scroll highlighting) so colors never flip between lexical and semantic.
    private var semanticByLocation: [Int: (length: Int, type: SyntaxTokenType)] = [:]
    private var semanticStorageLength: Int = -1
    
    private var bracketCacheVersion: Int = -1
    private var bracketCacheLang: String = ""
    private var bracketCacheLength: Int = -1
    private var bracketLocations: [Int32] = []
    private var bracketLevels: [UInt8] = []
    
    /// Toggle with `defaults write ... rainbowBracketsEnabled -bool NO`. Default ON.
    public static var rainbowBracketsEnabled: Bool {
        (UserDefaults.standard.object(forKey: "rainbowBracketsEnabled") as? Bool) ?? true
    }
    
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
    

    // MARK: - Off-MainActor Document Pre-Builder

    public struct PrebuiltEditorDocument: @unchecked Sendable {
        public let path: String
        public let language: String
        public let normalizedText: String
        public let attributedString: NSAttributedString
        public let lineStarts: [Int]
        public let precoloredUTF16End: Int
        public let fontSize: CGFloat
        public let activeThemeID: String
        public let fontName: String
        public let fontWeight: Int
        public let enableHighlighting: Bool
    }

    private static let prebuildLock = NSLock()
    private static var prebuiltDocuments: [PrebuiltEditorDocument] = []
    private static let maxPrebuiltDocuments = 1

    public static func clearPrebuiltDocuments() {
        prebuildLock.lock()
        prebuiltDocuments.removeAll()
        prebuildLock.unlock()
    }

    /// Contiguous UTF-8 raw-pointer scan computing UTF-16 line-start offsets in <0.5ms even in `-Onone`,
    /// handling `\n`, `\r\n`, lone `\r`, and UTF-16 surrogate-pair widths accurately.
    nonisolated public static func computeUTF16LineStartsFast(_ content: String) -> [Int] {
        var offsets: [Int] = [0]
        offsets.reserveCapacity(max(16, content.utf8.count / 36))
        let usedContiguous: Void? = content.utf8.withContiguousStorageIfAvailable { buf in
            guard let base = buf.baseAddress else { return }
            let n = buf.count
            var utf16Index = 0
            var prevCR = false
            var i = 0
            while i < n {
                let b = base[i]
                if b < 0x80 {
                    utf16Index &+= 1
                    if b == 0x0A {
                        if prevCR {
                            offsets[offsets.count - 1] = utf16Index
                            prevCR = false
                        } else {
                            offsets.append(utf16Index)
                        }
                    } else if b == 0x0D {
                        offsets.append(utf16Index)
                        prevCR = true
                    } else {
                        prevCR = false
                    }
                } else {
                    prevCR = false
                    if (b & 0xC0) != 0x80 {
                        utf16Index &+= (b >= 0xF0 ? 2 : 1)
                    }
                }
                i &+= 1
            }
        }
        if usedContiguous == nil {
            var utf16Index = 0
            var prevCR = false
            for unit in content.utf16 {
                utf16Index += 1
                if unit == 0x0A {
                    if prevCR {
                        offsets[offsets.count - 1] = utf16Index
                        prevCR = false
                    } else {
                        offsets.append(utf16Index)
                    }
                } else if unit == 0x0D {
                    offsets.append(utf16Index)
                    prevCR = true
                } else {
                    prevCR = false
                }
            }
        }
        return offsets
    }

    /// Prebuilds a detached `NSAttributedString`, UTF-16 line-start table, and Frame-0 viewport syntax colors
    /// entirely on a background thread during `AppState.loadFile`, cutting `@MainActor` mount work to a single
    /// `textStorage.setAttributedString` assignment.
    nonisolated public static func prebuildDocumentOffMainActor(
        path: String,
        rawContent: String,
        language: String,
        fontSize: CGFloat,
        themeName: String?,
        isDark: Bool,
        fontName: String = "Menlo",
        fontWeight: Int = 2,
        enableHighlighting: Bool
    ) -> String {
        let normalizedText = rawContent.utf8.contains(0x0D)
            ? rawContent.replacingOccurrences(of: "\r\n", with: "\n")
            : rawContent
        let lineStarts = computeUTF16LineStartsFast(normalizedText)

        let lowerTheme = themeName?.lowercased() ?? ""
        let activeThemeID: String
        if !lowerTheme.isEmpty && lowerTheme != "system", let tn = themeName {
            activeThemeID = tn
        } else {
            activeThemeID = isDark ? "dark" : "light"
        }

        let themeMgr = ThemeManager()
        themeMgr.setActiveTheme(activeThemeID)
        let fgColor = themeMgr.editorForegroundColor

        let weight: NSFont.Weight
        switch fontWeight {
        case 0: weight = .ultraLight
        case 1: weight = .light
        case 2: weight = .regular
        case 3: weight = .medium
        case 4: weight = .semibold
        case 5: weight = .bold
        default: weight = .regular
        }
        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        let customFont = NSFont(name: fontName, size: fontSize) ?? baseFont

        let mutableAttr = NSMutableAttributedString(
            string: normalizedText,
            attributes: [.foregroundColor: fgColor, .font: customFont, .ligature: 0]
        )

        var precoloredEnd = 0
        let docLen = mutableAttr.length
        let langKey = language.lowercased().trimmingCharacters(in: .whitespaces)
        if enableHighlighting && docLen > 0 && !langKey.isEmpty,
           let factory = lexerFactories[langKey] ?? lexerFactories["javascript"] {
            let lexer = factory()
            let ns = normalizedText as NSString
            let maxLines = min(lineStarts.count, 260)
            var state: SyntaxLexerState = .normal
            var preTokens: [SyntaxToken] = []
            preTokens.reserveCapacity(min(2_000, maxLines * 8))

            for lineIdx in 0..<maxLines {
                let startOffset = lineStarts[lineIdx]
                let rawEnd = (lineIdx + 1 < lineStarts.count) ? lineStarts[lineIdx + 1] : docLen
                var lineEnd = rawEnd
                if lineEnd > startOffset {
                    let c = ns.character(at: lineEnd - 1)
                    if c == 0x0A || c == 0x0D {
                        lineEnd -= 1
                        if c == 0x0A && lineEnd > startOffset && ns.character(at: lineEnd - 1) == 0x0D {
                            lineEnd -= 1
                        }
                    }
                }
                let lineStr = lineEnd > startOffset
                    ? ns.substring(with: NSRange(location: startOffset, length: lineEnd - startOffset))
                    : ""
                let (tokens, nextState) = lexer.tokenizeLine(
                    lineStr,
                    lineNumber: lineIdx,
                    startState: state,
                    startOffset: startOffset
                )
                preTokens.append(contentsOf: tokens)
                state = nextState
            }

            if !preTokens.isEmpty {
                let boldFont = NSFont(descriptor: customFont.fontDescriptor.withSymbolicTraits(.bold), size: fontSize) ?? customFont
                let italicFont = NSFont(descriptor: customFont.fontDescriptor.withSymbolicTraits(.italic), size: fontSize) ?? customFont
                let boldItalicFont = NSFont(descriptor: customFont.fontDescriptor.withSymbolicTraits([.bold, .italic]), size: fontSize) ?? customFont
                var styleCache: [SyntaxTokenType: (attrs: [NSAttributedString.Key: Any], isPlain: Bool)] = [:]
                styleCache.reserveCapacity(24)

                mutableAttr.beginEditing()
                for token in preTokens {
                    let r = token.range.nsRange
                    guard r.location >= 0 && r.length > 0 && r.location + r.length <= docLen else { continue }
                    let styleEntry: (attrs: [NSAttributedString.Key: Any], isPlain: Bool)
                    if let hit = styleCache[token.type] {
                        styleEntry = hit
                    } else {
                        let targetColor = themeMgr.color(for: token.type)
                        let style = themeMgr.style(for: token.type)
                        var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: targetColor, .ligature: 0]
                        if style.isBold && style.isItalic {
                            attrs[.font] = boldItalicFont
                        } else if style.isBold {
                            attrs[.font] = boldFont
                        } else if style.isItalic {
                            attrs[.font] = italicFont
                        }
                        if style.isUnderline {
                            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                        }
                        let isPlain = (targetColor == fgColor && !style.isBold && !style.isItalic && !style.isUnderline)
                        let built = (attrs: attrs, isPlain: isPlain)
                        styleCache[token.type] = built
                        styleEntry = built
                    }
                    if !styleEntry.isPlain {
                        mutableAttr.addAttributes(styleEntry.attrs, range: r)
                    }
                }
                mutableAttr.endEditing()
            }
            precoloredEnd = (maxLines < lineStarts.count) ? lineStarts[maxLines] : docLen
        }

        let entry = PrebuiltEditorDocument(
            path: path,
            language: langKey,
            normalizedText: normalizedText,
            attributedString: mutableAttr,
            lineStarts: lineStarts,
            precoloredUTF16End: precoloredEnd,
            fontSize: fontSize,
            activeThemeID: activeThemeID,
            fontName: fontName,
            fontWeight: fontWeight,
            enableHighlighting: enableHighlighting
        )

        prebuildLock.lock()
        prebuiltDocuments.removeAll { $0.path == path }
        prebuiltDocuments.append(entry)
        if prebuiltDocuments.count > maxPrebuiltDocuments {
            prebuiltDocuments.removeFirst(prebuiltDocuments.count - maxPrebuiltDocuments)
        }
        prebuildLock.unlock()

        return normalizedText
    }

    @MainActor
    public static func consumePrebuiltDocument(
        path: String?,
        normalizedText: String,
        language: String,
        fontSize: CGFloat,
        activeThemeID: String,
        fontName: String,
        fontWeight: Int,
        enableHighlighting: Bool
    ) -> PrebuiltEditorDocument? {
        prebuildLock.lock()
        defer { prebuildLock.unlock() }
        let langKey = language.lowercased().trimmingCharacters(in: .whitespaces)
        if let idx = prebuiltDocuments.lastIndex(where: { doc in
            (path == nil || doc.path == path)
                && doc.language == langKey
                && doc.fontSize == fontSize
                && doc.activeThemeID == activeThemeID
                && doc.fontName == fontName
                && doc.fontWeight == fontWeight
                && doc.enableHighlighting == enableHighlighting
                && doc.normalizedText.utf8.count == normalizedText.utf8.count
                && doc.normalizedText == normalizedText
        }) {
            return prebuiltDocuments.remove(at: idx)
        }
        return nil
    }

    // MARK: - Document Management

    public var currentLineOffsets: [Int]? {
        lock.lock()
        defer { lock.unlock() }
        return cachedLineOffsets
    }
    
    /// Set the document to highlight
    public func setDocument(_ content: String, language: String, precomputedLineStarts: [Int]? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if content != documentContent { semanticByLocation.removeAll(); semanticStorageLength = -1 }
        
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
        appliedHighlightRanges.removeAll(keepingCapacity: true)
        initialLexCompletedVersion = -1
        
        let newOffsets: [Int]
        if let precomputed = precomputedLineStarts, !precomputed.isEmpty {
            newOffsets = precomputed
        } else {
            newOffsets = Self.computeUTF16LineStartsFast(content)
        }
        cachedLineOffsets = newOffsets
        let lineCount = newOffsets.count
        
        // Get or create lexer for language (Lazy) — reuse `lineCount` directly to avoid a second full-file byte scan!
        if let lexer = loadedLexers[langKey] {
            activeLexer = lexer
            lexer.initialize(withLineCount: lineCount)
        } else if let factory = Self.lexerFactories[langKey] {
            let newLexer = IncrementalLexer(lexer: factory())
            loadedLexers[langKey] = newLexer
            activeLexer = newLexer
            newLexer.initialize(withLineCount: lineCount)
        } else {
            if let jsFactory = Self.lexerFactories["javascript"] {
                if let jsLexer = loadedLexers["javascript"] {
                    activeLexer = jsLexer
                    jsLexer.initialize(withLineCount: lineCount)
                } else {
                    let newLexer = IncrementalLexer(lexer: jsFactory())
                    loadedLexers["javascript"] = newLexer
                    activeLexer = newLexer
                    newLexer.initialize(withLineCount: lineCount)
                }
            } else {
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
        semanticByLocation.removeAll()
        semanticStorageLength = -1
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
        if initialLexCompletedVersion == currentVersion {
            initialLexCompletedVersion = currentVersion + 1
        }
        documentContent = newContent
        currentVersion += 1
        cachedAttributedString = nil
        appliedHighlightRanges = appliedHighlightRanges.compactMap { r in
            guard r.location < range.location else { return nil }
            let clippedLen = min(r.length, range.location - r.location)
            return clippedLen > 0 ? NSRange(location: r.location, length: clippedLen) : nil
        }
        
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
        let lineStarts = cachedLineOffsets
        
        lock.unlock()
        
        // SyntaxTokenize
        let tokens: [SyntaxToken]
        if let lexer = lexer {
            tokens = lexer.retokenizeDirtyRegions(in: content, lineStarts: lineStarts)
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
    /// Cooperative cancellation flag shared with `DispatchQueue.concurrentPerform` workers
    private var currentCancelToken: LexerCancelToken?
    /// Currently running chunked attribute-application task on MainActor
    private var currentApplyTask: Task<Void, Never>?
    
    /// Cancel any in-flight highlighting task
    public func cancelHighlighting() {
        currentCancelToken?.cancel()
        currentCancelToken = nil
        currentHighlightTask?.cancel()
        currentHighlightTask = nil
        currentApplyTask?.cancel()
        currentApplyTask = nil
    }
    
    /// Releases cached document string, attributed string, and lexer line cache from RAM.
    public func clearCache() {
        currentCancelToken?.cancel()
        currentCancelToken = nil
        lock.lock()
        documentContent = ""
        cachedAttributedString = nil
        appliedHighlightRanges.removeAll(keepingCapacity: false)
        initialLexCompletedVersion = -1
        activeLexer = nil
        lock.unlock()
    }

    public func recordPrebuiltHighlightedRange(_ range: NSRange) {
        recordHighlightedRange(range)
    }

    private func recordHighlightedRange(_ range: NSRange) {
        guard range.length > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        appliedHighlightRanges.append(range)
        appliedHighlightRanges.sort { $0.location < $1.location }
        var merged: [NSRange] = []
        merged.reserveCapacity(appliedHighlightRanges.count)
        for r in appliedHighlightRanges {
            if let last = merged.last, r.location <= NSMaxRange(last) + 64 {
                let end = max(NSMaxRange(last), NSMaxRange(r))
                merged[merged.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else {
                merged.append(r)
            }
        }
        appliedHighlightRanges = merged
    }

    private func isRangeFullyHighlighted(_ range: NSRange) -> Bool {
        guard range.length > 0 else { return true }
        lock.lock()
        defer { lock.unlock() }
        for r in appliedHighlightRanges {
            if r.location <= range.location && NSMaxRange(r) >= NSMaxRange(range) {
                return true
            }
        }
        return false
    }

    /// Lazily applies cached syntax tokens to newly scrolled viewport regions in O(visible lines) (<1.5ms),
    /// eliminating upfront full-document NSTextStorage attribute storms on multi-thousand-line files.
    @MainActor
    public func highlightViewportOnScroll(
        visibleCharRange: NSRange,
        to textStorage: NSTextStorage,
        fontSize: CGFloat,
        font: NSFont?
    ) {
        let storageLen = textStorage.length
        guard storageLen > 0, visibleCharRange.length > 0 else { return }
        let safeStart = max(0, min(visibleCharRange.location, storageLen))
        let safeEnd = max(safeStart, min(NSMaxRange(visibleCharRange), storageLen))
        let clampedVis = NSRange(location: safeStart, length: safeEnd - safeStart)
        guard clampedVis.length > 0, !isRangeFullyHighlighted(clampedVis) else { return }

        lock.lock()
        let isLexReady = (initialLexCompletedVersion == currentVersion && documentContent.utf16.count == storageLen)
        let offsets = cachedLineOffsets
        lock.unlock()
        guard isLexReady, let offsets, !offsets.isEmpty else { return }

        let windowStart = max(0, safeStart - 14_000)
        let windowEnd = min(storageLen, safeEnd + 14_000)
        let windowRange = NSRange(location: windowStart, length: windowEnd - windowStart)

        func lineIndex(for utf16Offset: Int) -> Int {
            var low = 0
            var high = offsets.count
            while low < high {
                let mid = (low + high) / 2
                if offsets[mid] <= utf16Offset { low = mid + 1 } else { high = mid }
            }
            return max(0, low - 1)
        }

        let startLine = lineIndex(for: windowStart)
        let endLine = min(offsets.count, lineIndex(for: windowEnd) + 1)
        guard startLine < endLine else { return }

        let sliceTokens = tokens(forLines: startLine..<endLine)
        if !sliceTokens.isEmpty {
            let defaultFont = font ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            textStorage.beginEditing()
            applyTokensBatch(sliceTokens, to: textStorage, defaultFont: defaultFont, fontSize: fontSize)
            textStorage.endEditing()
        }
        recordHighlightedRange(windowRange)
    }
    
    /// Asynchronously apply highlighting to an existing NSTextStorage.
    /// Uses true dirty-line incremental application so typing or AI patching only updates changed lines,
    /// and prioritizes `visibleCharRange` synchronously on Frame 0 when opening large files.
    @MainActor
    public func applyHighlightingAsync(
        to textStorage: NSTextStorage,
        fontSize: CGFloat,
        font: NSFont? = nil,
        visibleCharRange: NSRange? = nil,
        skipMainActorApplyIfFullDocument: Bool = false,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        // Cancel previous tasks + concurrentPerform workers to prevent "task explosion" and race conditions
        currentCancelToken?.cancel()
        currentHighlightTask?.cancel()
        currentApplyTask?.cancel()
        
        lock.lock()
        let content = documentContent
        let lexer = activeLexer
        let version = currentVersion
        let lineStarts = cachedLineOffsets
        let cachedLines = lineStarts?.count ?? 200
        lock.unlock()
        
        guard let lexer = lexer else {
            completion?()
            return
        }
        
        if cachedLines < 150 && content.utf8.count < 6000 {
            // SYNC PATH (Zero Flash) — small files only
            let update = lexer.retokenizeDirtyRegionsIncremental(in: content, lineStarts: lineStarts)
            lock.lock()
            initialLexCompletedVersion = version
            lock.unlock()
            if !(skipMainActorApplyIfFullDocument && update.isFullDocument) {
                self.applyIncrementalUpdate(update, to: textStorage, fontSize: fontSize, font: font, expectedVersion: version, visibleCharRange: visibleCharRange)
            }
            completion?()
            return
        }
        
        let cancelToken = LexerCancelToken()
        currentCancelToken = cancelToken
        let initialMaxLine: Int? = skipMainActorApplyIfFullDocument ? -1 : 420
        
        // ASYNC PATH (Large Docs)
        currentHighlightTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                await MainActor.run { completion?() }
                return
            }
            
            // During 0ms multi-tab bursts on large (>800-line) files, yield briefly so rapidly superseded
            // intermediate tabs cancel BEFORE splitting 10k+ lines or entering `DispatchQueue.concurrentPerform`.
            if cachedLines > 800 {
                try? await Task.sleep(nanoseconds: 18_000_000)
            }
            
            if Task.isCancelled || cancelToken.isCancelled {
                await MainActor.run { completion?() }
                return
            }
            
            // 1. Re-lex dirty regions incrementally (with cooperative cancelToken + bounded token unpacking)
            let update = lexer.retokenizeDirtyRegionsIncremental(
                in: content,
                lineStarts: lineStarts,
                cancelToken: cancelToken,
                initialMaxLine: initialMaxLine
            )
            
            if Task.isCancelled || cancelToken.isCancelled {
                await MainActor.run { completion?() }
                return
            }
            
            // 2. Apply attributes on the main thread (0ms no-op when Frame-0 viewport was already pre-colored off-MainActor!)
            await MainActor.run {
                defer { completion?() }
                if Task.isCancelled || cancelToken.isCancelled { return }
                
                self.lock.lock()
                let isStillValid = (self.currentVersion == version && self.documentContent.utf16.count == textStorage.length)
                if isStillValid {
                    self.initialLexCompletedVersion = version
                }
                self.lock.unlock()
                
                if isStillValid && !(skipMainActorApplyIfFullDocument && update.isFullDocument) {
                    self.applyIncrementalUpdate(update, to: textStorage, fontSize: fontSize, font: font, expectedVersion: version, visibleCharRange: visibleCharRange)
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
        expectedVersion: Int? = nil,
        visibleCharRange: NSRange? = nil
    ) {
        if update.isFullDocument {
            applyTokens(update.tokens, to: textStorage, fontSize: fontSize, font: font, expectedVersion: expectedVersion, visibleCharRange: visibleCharRange)
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
        recordHighlightedRange(safeRange)
    }
    
    /// Internal helper to apply attributes for specific tokens.
    /// CRITICAL: Must be called on the main thread.
    /// Uses chunking + viewport-bounded lookahead to prevent TextKit 1 contiguous glyph layout stalls on MainActor.
    @MainActor
    private func applyTokens(
        _ tokens: [SyntaxToken],
        to textStorage: NSTextStorage,
        fontSize: CGFloat,
        font: NSFont?,
        expectedVersion: Int? = nil,
        visibleCharRange: NSRange? = nil
    ) {
        assert(Thread.isMainThread, "applyTokens must be called on the main thread")
        currentApplyTask?.cancel()
        
        let defaultFont = font ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let storageLen = textStorage.length
        
        // CHUNK SIZE: Apply 1200 tokens at a time and yield back to CFRunLoop between chunks
        let chunkSize = 1200
        // If small enough, apply synchronously (fast path)
        if tokens.count <= chunkSize {
            textStorage.beginEditing()
            applyTokensBatch(tokens, to: textStorage, defaultFont: defaultFont, fontSize: fontSize)
            textStorage.endEditing()
            recordHighlightedRange(NSRange(location: 0, length: storageLen))
            return
        }

        // VIEWPORT-FIRST PRIORITY PASS: Immediately color tokens inside/around the visible viewport
        // synchronously so Frame 0 never renders unhighlighted text, while bounding offscreen TextKit 1
        // attribute runs on >2,000-token files (scroll events lazily color further down via highlightViewportOnScroll).
        var remainingTokens = tokens
        let centerAnchor = visibleCharRange?.location ?? 0
        let visLength = max(visibleCharRange?.length ?? 2500, 2500)
        var targetWindowRange = NSRange(location: 0, length: storageLen)
        if let vis = visibleCharRange, vis.length > 0 {
            let priorityStart = max(0, vis.location - 3500)
            let priorityEnd = min(storageLen, vis.location + vis.length + 3500)
            var viewportTokens: [SyntaxToken] = []
            var deferredTokens: [SyntaxToken] = []
            viewportTokens.reserveCapacity(min(tokens.count, 1200))
            deferredTokens.reserveCapacity(min(tokens.count, 3000))

            // Tight smooth-scroll lookahead (±9,000 UTF-16 units ~ ±220 lines) for any medium/large file (>2,000 tokens);
            // deeper scrolling triggers O(visible) `highlightViewportOnScroll` from cached IncrementalLexer tokens.
            let maxOffscreenRadius = tokens.count > 2_000 ? 9_000 : Int.max / 2
            let windowMin = max(0, centerAnchor - maxOffscreenRadius)
            let windowMax = min(storageLen, centerAnchor + visLength + maxOffscreenRadius)
            targetWindowRange = NSRange(location: windowMin, length: max(0, windowMax - windowMin))

            for tok in tokens {
                let r = tok.range.nsRange
                let tokEnd = r.location + r.length
                if tokEnd >= priorityStart && r.location <= priorityEnd {
                    viewportTokens.append(tok)
                } else if tokEnd >= windowMin && r.location <= windowMax {
                    deferredTokens.append(tok)
                }
            }

            if !viewportTokens.isEmpty {
                textStorage.beginEditing()
                applyTokensBatch(viewportTokens, to: textStorage, defaultFont: defaultFont, fontSize: fontSize)
                textStorage.endEditing()
            }
            recordHighlightedRange(NSRange(location: priorityStart, length: max(0, priorityEnd - priorityStart)))
            remainingTokens = deferredTokens
        } else if tokens.count > 2_000 {
            let capEnd = min(storageLen, 10_000)
            remainingTokens = tokens.filter { $0.range.nsRange.location <= capEnd }
            targetWindowRange = NSRange(location: 0, length: capEnd)
        }
        
        guard !remainingTokens.isEmpty else {
            recordHighlightedRange(targetWindowRange)
            return
        }

        let capturedWindowRange = targetWindowRange
        // Bounded lookahead remainder: Chunk asynchronously and yield to AppKit CFRunLoop
        currentApplyTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            var startIndex = 0
            while startIndex < remainingTokens.count {
                if Task.isCancelled { return }
                if let expectedVersion = expectedVersion {
                    self.lock.lock()
                    let valid = (self.currentVersion == expectedVersion && self.documentContent.utf16.count == textStorage.length)
                    self.lock.unlock()
                    if !valid { return }
                }
                
                let endIndex = min(startIndex + chunkSize, remainingTokens.count)
                let chunk = Array(remainingTokens[startIndex..<endIndex])
                
                textStorage.beginEditing()
                self.applyTokensBatch(chunk, to: textStorage, defaultFont: defaultFont, fontSize: fontSize)
                textStorage.endEditing()
                
                startIndex += chunkSize
                
                // Sleep 6ms to genuinely yield to AppKit CFRunLoop (Task.yield() alone stays in MainActor turn)
                try? await Task.sleep(nanoseconds: 6_000_000)
            }
            self.recordHighlightedRange(capturedWindowRange)
        }
    }
    
    // MARK: - LSP Semantic Token Overlay (compiler-accurate colors on top of the instant lexical pass)

    nonisolated static func syntaxType(forSemantic type: String, modifiers: Set<String>) -> SyntaxTokenType? {
        switch type {
        case "namespace", "type", "class", "struct", "enum", "interface", "typeParameter", "typeAlias":
            return .type
        case "parameter":
            return .parameter
        case "variable":
            return modifiers.contains("readonly") ? .constant : .variable
        case "property":
            return modifiers.contains("readonly") ? .constant : .property
        case "enumMember":
            return .enumMember
        case "function", "method":
            return .function
        case "macro":
            return .preprocessor
        case "decorator":
            return .annotation
        default:
            return nil
        }
    }

    /// Overlays LSP semantic token colors on `textStorage`. `text` must be the exact string the tokens were
    /// computed against; aborts (no-op) if the storage has since changed. Applied in cooperative chunks.
    @MainActor
    func applySemanticTokens(_ tokens: [LSPSemanticToken], to textStorage: NSTextStorage, text: String) async {
        let expectedLength = textStorage.length
        guard !tokens.isEmpty, text.utf16.count == expectedLength else { return }

        // UTF-16 line starts
        var lineStarts: [Int] = [0]
        var pos = 0
        for u in text.utf16 {
            pos += 1
            if u == 0x0A { lineStarts.append(pos) }
        }

        var map: [Int: (length: Int, type: SyntaxTokenType)] = [:]
        map.reserveCapacity(tokens.count)
        for t in tokens {
            guard t.line < lineStarts.count, let st = Self.syntaxType(forSemantic: t.type, modifiers: t.modifiers) else { continue }
            let loc = lineStarts[t.line] + t.character
            if loc >= 0, loc + t.length <= expectedLength { map[loc] = (t.length, st) }
        }
        semanticByLocation = map
        semanticStorageLength = expectedLength

        var colorCache: [SyntaxTokenType: NSColor] = [:]
        let chunk = 1500
        var idx = 0
        while idx < tokens.count {
            if Task.isCancelled || textStorage.length != expectedLength { return }
            let end = min(idx + chunk, tokens.count)
            textStorage.beginEditing()
            for t in tokens[idx..<end] {
                guard t.line < lineStarts.count,
                      let st = Self.syntaxType(forSemantic: t.type, modifiers: t.modifiers) else { continue }
                let loc = lineStarts[t.line] + t.character
                guard loc >= 0, loc + t.length <= expectedLength else { continue }
                let color: NSColor
                if let c = colorCache[st] { color = c } else {
                    color = themeManager.color(for: st)
                    colorCache[st] = color
                }
                textStorage.addAttribute(.foregroundColor, value: color, range: NSRange(location: loc, length: t.length))
            }
            textStorage.endEditing()
            idx = end
            try? await Task.sleep(nanoseconds: 4_000_000)
        }
    }

    // MARK: - Rainbow Brackets

    /// Builds (once per document version) a sorted map of bracket UTF-16 location -> nesting level (0...2),
    /// skipping brackets inside comments and strings. Disabled for very large files to protect latency.
    private func ensureBracketMap(storageLength: Int) -> Bool {
        lock.lock()
        let content = documentContent
        let ver = currentVersion
        let lang = currentLanguage.lowercased()
        lock.unlock()
        
        if bracketCacheVersion == ver && bracketCacheLang == lang && bracketCacheLength == storageLength {
            return !bracketLocations.isEmpty
        }
        bracketLocations.removeAll(keepingCapacity: true)
        bracketLevels.removeAll(keepingCapacity: true)
        bracketCacheVersion = ver
        bracketCacheLang = lang
        bracketCacheLength = storageLength
        
        let unsupported: Set<String> = ["markdown", "plaintext", "text", "txt", "html", "xml", "log"]
        guard !unsupported.contains(lang), content.utf8.count <= 600_000 else { return false }
        
        let hashComment: Set<String> = ["python", "shell", "ruby", "yaml", "toml", "r", "julia", "elixir"]
        let singleQuoteStrings: Set<String> = ["python", "javascript", "typescript", "php", "ruby", "shell", "dart", "yaml", "toml", "lua", "sql", "julia", "css", "elixir", "r", "json"]
        let tripleQuote: Set<String> = ["python", "swift", "kotlin", "julia", "elixir"]
        let backtickStrings: Set<String> = ["javascript", "typescript", "go", "shell"]
        let useHash = hashComment.contains(lang)
        let useDash = (lang == "sql" || lang == "lua")
        let useSlash = !useHash && !useDash && lang != "json"
        let useBlock = useSlash || lang == "css"
        let useSingle = singleQuoteStrings.contains(lang)
        let useTriple = tripleQuote.contains(lang)
        let useBacktick = backtickStrings.contains(lang)
        
        var c = content
        var locs: [Int32] = []
        var levels: [UInt8] = []
        var totalUTF16 = 0
        
        c.withUTF8 { buf in
            let n = buf.count
            var i = 0
            var pos = 0
            var depth = 0
            
            @inline(__always) func advance() {
                let b = buf[i]
                if b < 0x80 { pos += 1 }
                else if b >= 0xF0 { pos += 2 }
                else if b >= 0xC0 { pos += 1 }
                i += 1
            }
            @inline(__always) func skipToLineEnd() {
                while i < n, buf[i] != 0x0A { advance() }
            }
            
            while i < n {
                let b = buf[i]
                switch b {
                case 0x2F where useSlash && i + 1 < n && buf[i + 1] == 0x2F:      // //
                    skipToLineEnd()
                case 0x2F where useBlock && i + 1 < n && buf[i + 1] == 0x2A:      // /* */
                    advance(); advance()
                    while i < n, !(buf[i] == 0x2A && i + 1 < n && buf[i + 1] == 0x2F) { advance() }
                    if i < n { advance(); if i < n { advance() } }
                case 0x23 where useHash:                                           // #
                    skipToLineEnd()
                case 0x2D where useDash && i + 1 < n && buf[i + 1] == 0x2D:       // --
                    skipToLineEnd()
                case 0x22:                                                         // "
                    if useTriple, i + 2 < n, buf[i + 1] == 0x22, buf[i + 2] == 0x22 {
                        advance(); advance(); advance()
                        while i < n, !(buf[i] == 0x22 && i + 2 < n && buf[i + 1] == 0x22 && buf[i + 2] == 0x22) { advance() }
                        for _ in 0..<3 where i < n { advance() }
                    } else {
                        advance()
                        while i < n, buf[i] != 0x22, buf[i] != 0x0A {
                            if buf[i] == 0x5C, i + 1 < n, buf[i + 1] != 0x0A { advance() }
                            advance()
                        }
                        if i < n, buf[i] == 0x22 { advance() }
                    }
                case 0x27:                                                         // '
                    if useSingle {
                        advance()
                        while i < n, buf[i] != 0x27, buf[i] != 0x0A {
                            if buf[i] == 0x5C, i + 1 < n, buf[i + 1] != 0x0A { advance() }
                            advance()
                        }
                        if i < n, buf[i] == 0x27 { advance() }
                    } else if i + 2 < n, buf[i + 2] == 0x27 {                      // 'x'
                        advance(); advance(); advance()
                    } else if i + 3 < n, buf[i + 1] == 0x5C, buf[i + 3] == 0x27 {  // '\n'
                        advance(); advance(); advance(); advance()
                    } else {
                        advance()
                    }
                case 0x60 where useBacktick:                                       // `
                    advance()
                    while i < n, buf[i] != 0x60 {
                        if buf[i] == 0x5C, i + 1 < n { advance() }
                        advance()
                    }
                    if i < n { advance() }
                case 0x28, 0x5B, 0x7B:                                             // ( [ {
                    locs.append(Int32(truncatingIfNeeded: pos))
                    levels.append(UInt8(depth % 3))
                    depth += 1
                    advance()
                case 0x29, 0x5D, 0x7D:                                             // ) ] }
                    depth = max(0, depth - 1)
                    locs.append(Int32(truncatingIfNeeded: pos))
                    levels.append(UInt8(depth % 3))
                    advance()
                default:
                    advance()
                }
            }
            totalUTF16 = pos
        }
        
        guard totalUTF16 == storageLength else { return false }
        bracketLocations = locs
        bracketLevels = levels
        return !locs.isEmpty
    }
    
    private func bracketLevel(at location: Int) -> Int? {
        var low = 0
        var high = bracketLocations.count
        let target = Int32(truncatingIfNeeded: location)
        while low < high {
            let mid = (low + high) / 2
            if bracketLocations[mid] < target { low = mid + 1 } else { high = mid }
        }
        if low < bracketLocations.count, bracketLocations[low] == target { return Int(bracketLevels[low]) }
        return nil
    }
    
    private func rainbowColors(isDark: Bool) -> [NSColor] {
        if isDark {
            return [NSColor(srgbRed: 1.0, green: 0.843, blue: 0.0, alpha: 1),        // #FFD700
                    NSColor(srgbRed: 0.855, green: 0.439, blue: 0.839, alpha: 1),    // #DA70D6
                    NSColor(srgbRed: 0.090, green: 0.624, blue: 1.0, alpha: 1)]      // #179FFF
        }
        return [NSColor(srgbRed: 0.016, green: 0.192, blue: 0.980, alpha: 1),        // #0431FA
                NSColor(srgbRed: 0.192, green: 0.576, blue: 0.192, alpha: 1),        // #319331
                NSColor(srgbRed: 0.482, green: 0.220, blue: 0.078, alpha: 1)]        // #7B3814
    }
    
    private func applyTokensBatch(_ tokens: [SyntaxToken], to textStorage: NSTextStorage, defaultFont: NSFont, fontSize: CGFloat) {
         // NOTE: Callers (applyTokens / applyHighlighting) are responsible for wrapping in beginEditing/endEditing.
         let boldFont = NSFont(descriptor: defaultFont.fontDescriptor.withSymbolicTraits(.bold), size: fontSize) ?? defaultFont
         let italicFont = NSFont(descriptor: defaultFont.fontDescriptor.withSymbolicTraits(.italic), size: fontSize) ?? defaultFont
         let boldItalicFont = NSFont(descriptor: defaultFont.fontDescriptor.withSymbolicTraits([.bold, .italic]), size: fontSize) ?? defaultFont
         let defaultColor = themeManager.editorForegroundColor
         let storageLength = textStorage.length
         let forceUpdateSmall = storageLength < 500

         // Pre-build attribute dictionaries per SyntaxTokenType (<= ~20 entries instead of allocating 35,000 dicts)
         var styleCache: [SyntaxTokenType: (color: NSColor, attrs: [NSAttributedString.Key: Any], isDefaultPlain: Bool)] = [:]
         styleCache.reserveCapacity(24)

         let rainbowOn = Self.rainbowBracketsEnabled && ensureBracketMap(storageLength: storageLength)
         let rainbowPalette = rainbowOn ? rainbowColors(isDark: themeManager.currentTheme.isDark) : []

         for token in tokens {
             let nsRange = token.range.nsRange
             guard nsRange.location >= 0 && nsRange.length > 0 && nsRange.location + nsRange.length <= storageLength else {
                 continue
             }
             
             if rainbowOn, token.type == .punctuation, nsRange.length == 1,
                let level = bracketLevel(at: nsRange.location) {
                 textStorage.addAttribute(.foregroundColor, value: rainbowPalette[level], range: nsRange)
                 continue
             }

             let cached: (color: NSColor, attrs: [NSAttributedString.Key: Any], isDefaultPlain: Bool)
             if let hit = styleCache[token.type] {
                 cached = hit
             } else {
                 let targetColor = themeManager.color(for: token.type)
                 let style = themeManager.style(for: token.type)
                 var attributes: [NSAttributedString.Key: Any] = [
                     .foregroundColor: targetColor,
                     .ligature: 0
                 ]
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
                 let isPlain = (targetColor == defaultColor && !style.isBold && !style.isItalic && !style.isUnderline)
                 let built = (color: targetColor, attrs: attributes, isDefaultPlain: isPlain)
                 styleCache[token.type] = built
                 cached = built
             }

             if forceUpdateSmall {
                 textStorage.addAttributes(cached.attrs, range: nsRange)
             } else {
                 // Query single .foregroundColor attribute instead of bridging full NSDictionary per token
                 let currentColor = textStorage.attribute(.foregroundColor, at: nsRange.location, effectiveRange: nil) as? NSColor
                 if cached.isDefaultPlain && currentColor == defaultColor {
                     continue
                 }
                 if currentColor != cached.color || !cached.isDefaultPlain {
                     if currentColor != cached.color || cached.attrs.count > 2 {
                         textStorage.addAttributes(cached.attrs, range: nsRange)
                     }
                 }
             }
         }

         // Re-assert LSP semantic colors over freshly painted lexical colors (prevents color flips on scroll).
         if semanticStorageLength == storageLength, !semanticByLocation.isEmpty {
             var semColors: [SyntaxTokenType: NSColor] = [:]
             for token in tokens {
                 let loc = token.range.startOffset
                 guard let sem = semanticByLocation[loc], loc + sem.length <= storageLength else { continue }
                 let color: NSColor
                 if let c = semColors[sem.type] { color = c } else {
                     color = themeManager.color(for: sem.type)
                     semColors[sem.type] = color
                 }
                 textStorage.addAttribute(.foregroundColor, value: color, range: NSRange(location: loc, length: sem.length))
             }
         }
    }

    /// Synchronous version (use with caution on small snippets or background threads)
    nonisolated public func applyHighlighting(to textStorage: NSTextStorage, fontSize: CGFloat, font: NSFont? = nil) {
        lock.lock()
        let content = documentContent
        let lexer = activeLexer
        let lineStarts = cachedLineOffsets
        lock.unlock()
        
        guard let lexer = lexer else { return }
        let tokens = lexer.retokenizeDirtyRegions(in: content, lineStarts: lineStarts)
        
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
        
        guard let lexer = activeLexer, let lineStarts = cachedLineOffsets, !range.isEmpty else { return [] }
        
        return lexer.cache.tokens(fromLine: range.lowerBound, toLine: range.upperBound - 1, lineStarts: lineStarts)
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
        isDark: Bool = true,
        themeName: String? = nil
    ) -> AttributedString {
        var hasher = Hasher()
        hasher.combine(code)
        hasher.combine(language.lowercased())
        hasher.combine(Int(fontSize * 10))
        hasher.combine(isDark)
        hasher.combine(themeName ?? "")
        let key = hasher.finalize()
        
        quickHighlightLock.lock()
        if let cached = swiftUIAttributedCache[key] {
            quickHighlightLock.unlock()
            return cached
        }
        
        if let themeName, !themeName.isEmpty, themeName.lowercased() != "system" {
            sharedQuickEngine.themeManager.setActiveTheme(themeName)
        } else {
            sharedQuickEngine.themeManager.setActiveTheme(isDark ? "dark" : "light")
        }
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

/// Interactive NSTextView supporting Cmd+Click (Go to Definition), Option+Click (Quick Help Hover), F12,
/// and hardware-accelerated multiplayer remote carets + selection highlights.
final class IDEInteractiveTextView: NSTextView {
    var onGoToDefinitionAtCharIndex: ((Int) -> Void)?
    var onQuickHelpAtCharIndex: ((Int, NSPoint) -> Void)?
    var collaborationFileURL: URL?
    private var isObservingCollabPresence = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            if !isObservingCollabPresence {
                isObservingCollabPresence = true
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleRemoteCollabPresenceChanged(_:)),
                    name: CollaborationService.remotePresenceDidChangeNotification,
                    object: nil
                )
            }
            needsDisplay = true
        } else if isObservingCollabPresence {
            isObservingCollabPresence = false
            NotificationCenter.default.removeObserver(
                self,
                name: CollaborationService.remotePresenceDidChangeNotification,
                object: nil
            )
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleRemoteCollabPresenceChanged(_ notification: Notification) {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawRemoteCollaboratorCarets(in: dirtyRect)
    }

    private func drawRemoteCollaboratorCarets(in dirtyRect: NSRect) {
        guard let fileURL = collaborationFileURL else { return }
        let peers = CollaborationService.shared.remoteCollaborators(inFilePath: fileURL.path)
        guard !peers.isEmpty,
              let lm = layoutManager,
              let tc = textContainer else { return }

        let nsText = self.string as NSString
        let totalLen = nsText.length
        let origin = textContainerOrigin

        // Build 0-based line start UTF-16 offsets once per draw pass when collaborators are present
        var lineStarts: [Int] = [0]
        if totalLen > 0 {
            var searchIdx = 0
            while searchIdx < totalLen {
                let nlRange = nsText.range(
                    of: "\n",
                    options: .literal,
                    range: NSRange(location: searchIdx, length: totalLen - searchIdx)
                )
                if nlRange.location == NSNotFound { break }
                lineStarts.append(nlRange.location + 1)
                searchIdx = nlRange.location + 1
            }
        }

        func utf16Offset(line: Int, column: Int) -> Int {
            guard !lineStarts.isEmpty else { return 0 }
            let clampedLineIdx = max(0, min(lineStarts.count - 1, line - 1))
            let lineStart = lineStarts[clampedLineIdx]
            let lineEnd: Int
            if clampedLineIdx + 1 < lineStarts.count {
                lineEnd = max(lineStart, lineStarts[clampedLineIdx + 1] - 1)
            } else {
                lineEnd = totalLen
            }
            return max(lineStart, min(lineEnd, lineStart + max(0, column - 1)))
        }

        let defaultLineHeight: CGFloat = max(16, (self.font?.pointSize ?? 13) * 1.4)
        var usedFlagSlotsOnLine: [Int: Int] = [:]

        for peer in peers {
            guard let cursor = peer.cursorPosition else { continue }
            let peerColor = CollaborationColorHelper.nsColor(fromHex: peer.color)
            let startIdx = utf16Offset(line: cursor.line, column: cursor.column)

            // 1. Draw translucent selection range if teammate selected code
            if let endL = cursor.endLine, let endC = cursor.endColumn {
                let endIdx = utf16Offset(line: endL, column: endC)
                let lo = min(startIdx, endIdx)
                let hi = max(startIdx, endIdx)
                if hi > lo, lo < totalLen {
                    let safeRange = NSRange(location: lo, length: min(hi - lo, totalLen - lo))
                    let glyphRange = lm.glyphRange(forCharacterRange: safeRange, actualCharacterRange: nil)
                    if glyphRange.length > 0 {
                        peerColor.withAlphaComponent(0.22).setFill()
                        peerColor.withAlphaComponent(0.45).setStroke()
                        lm.enumerateEnclosingRects(
                            forGlyphRange: glyphRange,
                            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                            in: tc
                        ) { rect, _ in
                            let r = rect.offsetBy(dx: origin.x, dy: origin.y)
                            if r.intersects(dirtyRect) {
                                let path = NSBezierPath(roundedRect: r, xRadius: 2.5, yRadius: 2.5)
                                path.fill()
                                path.lineWidth = 0.8
                                path.stroke()
                            }
                        }
                    }
                }
            }

            // 2. Compute exact caret rectangle
            let caretRect: NSRect
            if totalLen == 0 || lm.numberOfGlyphs == 0 {
                caretRect = NSRect(x: origin.x, y: origin.y, width: 2.2, height: defaultLineHeight)
            } else if startIdx < totalLen {
                let glyphIdx = min(lm.glyphIndexForCharacter(at: startIdx), max(0, lm.numberOfGlyphs - 1))
                let frag = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil, withoutAdditionalLayout: true)
                let loc = lm.location(forGlyphAt: glyphIdx)
                let h = frag.height > 1 ? frag.height : defaultLineHeight
                caretRect = NSRect(x: origin.x + frag.minX + loc.x, y: origin.y + frag.minY, width: 2.2, height: h)
            } else {
                let lastCharIdx = totalLen - 1
                let lastGlyphIdx = min(lm.glyphIndexForCharacter(at: lastCharIdx), max(0, lm.numberOfGlyphs - 1))
                let frag = lm.lineFragmentRect(forGlyphAt: lastGlyphIdx, effectiveRange: nil, withoutAdditionalLayout: true)
                let h = frag.height > 1 ? frag.height : defaultLineHeight
                if nsText.character(at: lastCharIdx) == 10 {
                    caretRect = NSRect(x: origin.x, y: origin.y + frag.maxY, width: 2.2, height: h)
                } else {
                    let endRect = lm.boundingRect(forGlyphRange: NSRange(location: lastGlyphIdx, length: 1), in: tc)
                    caretRect = NSRect(x: origin.x + endRect.maxX, y: origin.y + frag.minY, width: 2.2, height: h)
                }
            }

            let isAITeammate = peer.userId == CollaborationService.aiTeammateUserId || peer.role == "AI Agent"

            // Active typing / AI teammate subtle line highlight strip
            if cursor.isTyping == true || isAITeammate {
                let lineStrip = NSRect(x: 0, y: caretRect.minY, width: bounds.width, height: caretRect.height)
                if lineStrip.intersects(dirtyRect) {
                    peerColor.withAlphaComponent(isAITeammate ? 0.13 : 0.08).setFill()
                    lineStrip.fill()
                }
            }

            // Draw crisp 2.2pt colored caret bar
            let caretPath = NSBezierPath(roundedRect: caretRect, xRadius: 1.1, yRadius: 1.1)
            peerColor.setFill()
            caretPath.fill()

            // 3. Draw floating collaborator name flag right above/below caret
            let slot = usedFlagSlotsOnLine[cursor.line, default: 0]
            usedFlagSlotsOnLine[cursor.line] = slot + 1
            let labelText: String
            if isAITeammate {
                if peer.isAIActive, let status = peer.aiStatusText, !status.isEmpty {
                    let shortStatus = status.count > 34 ? String(status.prefix(34)) + "…" : status
                    labelText = "✦ \(peer.displayName) · \(shortStatus)"
                } else if cursor.isTyping == true {
                    labelText = "✦ \(peer.displayName) · กำลังแก้ Ln \(cursor.line)"
                } else {
                    labelText = "✦ \(peer.displayName) · Ln \(cursor.line)"
                }
            } else {
                labelText = cursor.isTyping == true
                    ? "\(peer.displayName) · กำลังแก้"
                    : peer.displayName
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let textSize = (labelText as NSString).size(withAttributes: attrs)
            let pillW = ceil(textSize.width) + 10
            let pillH: CGFloat = 15
            let rawX = caretRect.minX + CGFloat(slot) * (pillW + 4)
            let clampedX = max(2, min(max(2, bounds.width - pillW - 4), rawX))
            let flagY = caretRect.minY >= (pillH + 2)
                ? (caretRect.minY - pillH + 1)
                : (caretRect.maxY - 1)
            let pillRect = NSRect(x: clampedX, y: flagY, width: pillW, height: pillH)
            if pillRect.insetBy(dx: -4, dy: -4).intersects(dirtyRect) {
                let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4)
                peerColor.withAlphaComponent(0.95).setFill()
                pillPath.fill()
                (labelText as NSString).draw(
                    at: NSPoint(x: pillRect.minX + 5, y: pillRect.minY + (pillH - textSize.height) * 0.5),
                    withAttributes: attrs
                )
            }
        }
    }

    private var isHandlingMouseDown = false

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
        isHandlingMouseDown = true
        defer { isHandlingMouseDown = false }
        super.mouseDown(with: event)
        if let noIntrinsic = enclosingScrollView as? NoIntrinsicScrollView,
           noIntrinsic.forwardsScrollToEnclosingView,
           noIntrinsic.contentView.bounds.origin != .zero {
            noIntrinsic.contentView.scroll(to: .zero)
            noIntrinsic.reflectScrolledClipView(noIntrinsic.contentView)
        }
    }

    override func autoscroll(with event: NSEvent) -> Bool {
        if let noIntrinsic = enclosingScrollView as? NoIntrinsicScrollView,
           noIntrinsic.forwardsScrollToEnclosingView {
            if noIntrinsic.contentView.bounds.origin != .zero {
                noIntrinsic.contentView.scroll(to: .zero)
                noIntrinsic.reflectScrolledClipView(noIntrinsic.contentView)
            }
            return noIntrinsic.superview?.autoscroll(with: event) ?? false
        }
        return super.autoscroll(with: event)
    }

    override func scrollToVisible(_ rect: NSRect) -> Bool {
        if let noIntrinsic = enclosingScrollView as? NoIntrinsicScrollView,
           noIntrinsic.forwardsScrollToEnclosingView {
            if noIntrinsic.contentView.bounds.origin != .zero {
                noIntrinsic.contentView.scroll(to: .zero)
                noIntrinsic.reflectScrolledClipView(noIntrinsic.contentView)
            }
            // Clicking a cell that is already under the user's cursor must NEVER jump any scroll view
            if isHandlingMouseDown {
                return false
            }
            // For keyboard navigation / typing near viewport edges, forward only the compact caret rect
            // to the enclosing Notebook ScrollView instead of scrolling inside the cell.
            if let outerHost = noIntrinsic.superview {
                let paddedCaret = rect.insetBy(dx: 0, dy: -6)
                let rectInOuter = convert(paddedCaret, to: outerHost)
                return outerHost.scrollToVisible(rectInOuter)
            }
            return false
        }
        return super.scrollToVisible(rect)
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
    /// When true (`isScrollEnabled == false` in Notebook / Playground cells), all wheel and pinch
    /// events pass straight through to the outer Notebook `ScrollView` and internal clip origin stays locked at `.zero`.
    var forwardsScrollToEnclosingView: Bool = false

    // Returning noIntrinsicMetric prevents the scroll view from bubbling the
    // text view's content size up to SwiftUI, which is what triggered the
    // _FlexFrameLayout recursion crash. sizeThatFits returning the proposal
    // also stops SwiftUI from ever querying intrinsic size, so this never
    // recurses back into SwiftUI layout.
    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func scrollWheel(with event: NSEvent) {
        if forwardsScrollToEnclosingView {
            if contentView.bounds.origin != .zero {
                contentView.scroll(to: .zero)
                reflectScrolledClipView(contentView)
            }
            nextResponder?.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        if forwardsScrollToEnclosingView {
            nextResponder?.magnify(with: event)
            return
        }
        super.magnify(with: event)
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
        if forwardsScrollToEnclosingView && contentView.bounds.origin != .zero {
            contentView.scroll(to: .zero)
            reflectScrolledClipView(contentView)
        }
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
    @MainActor private static var viewCacheOrder: [String] = []
    private static let maxCachedEditorViews = 2
    /// Dedicated warm pool for lightweight Notebook / Playground cell editors (`cell-*`, `pgcell-*`)
    /// so hovering or clicking across multi-cell sheets never evicts or recreates `NSScrollView`s.
    @MainActor private static var cellViewCache: [String: NSScrollView] = [:]
    @MainActor private static var cellViewCacheOrder: [String] = []
    private static let maxCachedCellViews = 36

    private static func isCellEditorID(_ id: String) -> Bool {
        id.hasPrefix("cell-") || id.hasPrefix("pgcell-")
    }

    /// Enforces a strict LRU cap on cached NSScrollViews, releasing unmounted TextKit & IOSurface buffers.
    @MainActor
    private static func trimViewCache(keeping protectedID: String? = nil) {
        viewCacheOrder.removeAll { viewCache[$0] == nil }
        if viewCache.count > maxCachedEditorViews {
            for key in viewCacheOrder where key != protectedID {
                guard let sv = viewCache[key] else { continue }
                if sv.window == nil && sv.superview == nil {
                    if let tv = sv.documentView as? NSTextView {
                        tv.delegate = nil
                        tv.textStorage?.delegate = nil
                        tv.string = ""
                    }
                    viewCache.removeValue(forKey: key)
                }
                if viewCache.count <= maxCachedEditorViews { break }
            }
            viewCacheOrder.removeAll { viewCache[$0] == nil }
        }

        cellViewCacheOrder.removeAll { cellViewCache[$0] == nil }
        if cellViewCache.count > maxCachedCellViews {
            for key in cellViewCacheOrder where key != protectedID {
                guard let sv = cellViewCache[key] else { continue }
                if sv.window == nil && sv.superview == nil {
                    if let tv = sv.documentView as? NSTextView {
                        tv.delegate = nil
                        tv.textStorage?.delegate = nil
                        tv.string = ""
                    }
                    cellViewCache.removeValue(forKey: key)
                }
                if cellViewCache.count <= maxCachedCellViews { break }
            }
            cellViewCacheOrder.removeAll { cellViewCache[$0] == nil }
        }
    }

    /// Purges cached NSScrollViews that are no longer mounted in any active window,
    /// freeing tens of megabytes of TextKit glyph and layout backing memory.
    @MainActor
    public static func purgeNonVisibleViewCache() {
        SyntaxHighlightingEngine.clearPrebuiltDocuments()
        for key in Array(viewCache.keys) {
            if let sv = viewCache[key], sv.window == nil {
                if let tv = sv.documentView as? NSTextView {
                    tv.delegate = nil
                    tv.textStorage?.delegate = nil
                    tv.string = ""
                }
                viewCache.removeValue(forKey: key)
            }
        }
        viewCacheOrder.removeAll { viewCache[$0] == nil }
        for key in Array(cellViewCache.keys) {
            if let sv = cellViewCache[key], sv.window == nil {
                if let tv = sv.documentView as? NSTextView {
                    tv.delegate = nil
                    tv.textStorage?.delegate = nil
                    tv.string = ""
                }
                cellViewCache.removeValue(forKey: key)
            }
        }
        cellViewCacheOrder.removeAll { cellViewCache[$0] == nil }
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
        if let id = editorID,
           let cached = (Self.isCellEditorID(id) ? Self.cellViewCache[id] : Self.viewCache[id]),
           cached.superview == nil, cached.window == nil,
           let tv = cached.documentView as? NSTextView {
            (cached as? NoIntrinsicScrollView)?.forwardsScrollToEnclosingView = !self.isScrollEnabled
            cached.hasVerticalScroller = self.isScrollEnabled
            cached.hasHorizontalScroller = self.isScrollEnabled
            (tv as? IDEInteractiveTextView)?.collaborationFileURL = self.fileURL
            let engine = SyntaxHighlightingEngine()
            context.coordinator.engine = engine
            context.coordinator.textView = tv
            tv.delegate = context.coordinator
            tv.textStorage?.delegate = context.coordinator
            CrashReporter.shared.breadcrumb("SHCV.makeNSView REUSE id=\(id) tsLen=\(tv.textStorage?.length ?? -1)")
            context.coordinator.applyContent(self, to: tv, scrollView: cached, force: true)
            context.coordinator.scheduleSemanticOverlay(afterNanoseconds: 1_200_000_000, retriesLeft: 3)
            return cached
        }

        // Custom ScrollView to prevent intrinsic size bubbling.
        // Give a realistic initial 960x680 viewport for scrollable file editors (or compact 640x96 for non-scrolling cells)
        // so TextKit 1 NEVER initializes `NSTextContainer` at width=1pt.
        let initialSeedHeight: CGFloat = isScrollEnabled ? 680 : 96
        let scrollView = NoIntrinsicScrollView(frame: NSRect(x: 0, y: 0, width: isScrollEnabled ? 960 : 640, height: initialSeedHeight))
        scrollView.forwardsScrollToEnclosingView = !isScrollEnabled
        scrollView.hasVerticalScroller = isScrollEnabled
        scrollView.hasHorizontalScroller = isScrollEnabled
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        let contentSize = scrollView.contentSize
        let initialWidth = max(isScrollEnabled ? 640 : 320, contentSize.width)
        let initialHeight = max(isScrollEnabled ? 480 : 64, contentSize.height)

        // Use AppKit's OWN construction (explicit TextKit 1) instead of a
        // hand-assembled NSTextStorage/NSLayoutManager/NSTextContainer.
        // On macOS 26 the manual stack assigned via `documentView` laid glyphs
        // out (the gutter ruler drew correctly) but the text view itself drew
        // NOTHING — the v2.5.5 diagnostic proved frame/window/glyphs were all
        // correct, so the blank editor was a TextKit-stack/rendering quirk, not
        // geometry or colour. `NSTextView(usingTextLayoutManager: false)` builds
        // a fully-wired, render-correct TextKit 1 view (macOS 13+).
        let textView = IDEInteractiveTextView(usingTextLayoutManager: false)
        textView.collaborationFileURL = self.fileURL
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
        context.coordinator.scheduleSemanticOverlay(afterNanoseconds: 1_200_000_000, retriesLeft: 3)

        // Cache so subsequent SwiftUI identity churn reuses THIS view (only for small/medium files <= 96 KB
        // so multi-hundred-KB files like 11k-line kernel sources release their TextKit & IOSurface memory on tab switch).
        if let id = editorID, self.text.utf8.count <= 96 * 1024 {
            if Self.isCellEditorID(id) {
                Self.cellViewCache[id] = scrollView
                Self.cellViewCacheOrder.removeAll { $0 == id }
                Self.cellViewCacheOrder.append(id)
            } else {
                Self.viewCache[id] = scrollView
                Self.viewCacheOrder.removeAll { $0 == id }
                Self.viewCacheOrder.append(id)
            }
            Self.trimViewCache(keeping: id)
        }

        return scrollView
    }

    public static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.isInvalidated = true
        coordinator.highlightTimer?.invalidate()
        coordinator.highlightTimer = nil
        coordinator.lspChangeTask?.cancel()
        coordinator.lspChangeTask = nil
        coordinator.semanticTask?.cancel()
        coordinator.semanticTask = nil
        coordinator.autocompleteTask?.cancel()
        coordinator.autocompleteTask = nil
        coordinator.bindingSyncTask?.cancel()
        coordinator.bindingSyncTask = nil
        coordinator.collabEditSyncTask?.cancel()
        coordinator.collabEditSyncTask = nil
        coordinator.scrollHighlightWork?.cancel()
        coordinator.scrollHighlightWork = nil
        coordinator.engine?.cancelHighlighting()
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.observedClipView = nil
        coordinator.lastText = ""

        // Enforce strict LRU max=2 AFTER SwiftUI unmounts dismantled views so rapid 8-tab bursts
        // never retain 8 NSScrollViews + IOSurface tile backing buffers simultaneously.
        Self.trimViewCache()

        let isCached = Self.viewCache.values.contains(where: { $0 === nsView })
            || Self.cellViewCache.values.contains(where: { $0 === nsView })
        if !isCached {
            coordinator.engine?.clearCache()
            coordinator.engine = nil
            if let tv = nsView.documentView as? NSTextView {
                tv.delegate = nil
                tv.textStorage?.delegate = nil
                tv.string = ""
            }
        }
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
        var semanticTask: Task<Void, Never>?
        var autocompleteTask: Task<Void, Never>?
        var bindingSyncTask: Task<Void, Never>?
        var collabEditSyncTask: Task<Void, Never>?
        var scrollHighlightWork: DispatchWorkItem?
        weak var observedClipView: NSClipView?
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
                  let userInfo = notification.userInfo,
                  let line = userInfo["line"] as? Int,
                  let tv = textView else {
                return
            }
            let editorStdPath = fileURL.standardizedFileURL.path
            let currentStdPath = parent.appState.currentFile.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path }
            let targetStdPath = (userInfo["fileURL"] as? URL)?.standardizedFileURL.path
            guard currentStdPath == editorStdPath || targetStdPath == editorStdPath else {
                return
            }
            
            let text = tv.string
            let nsText = text as NSString
            let lines = text.components(separatedBy: "\n")
            guard !lines.isEmpty else { return }
            
            // line is 1-indexed
            let targetLine = max(0, min(lines.count - 1, line - 1))
            
            var charIndex = 0
            for i in 0..<targetLine {
                charIndex += (lines[i] as NSString).length + 1 // +1 for the newline character
            }
            
            if let col = userInfo["column"] as? Int {
                let lineLen = (lines[targetLine] as NSString).length
                charIndex += max(0, min(lineLen, col - 1))
            }
            
            let finalIndex = min(nsText.length, charIndex)
            let scrollOnly = (userInfo["scrollOnly"] as? Bool) == true
            if !scrollOnly {
                tv.setSelectedRange(NSRange(location: finalIndex, length: 0))
            }
            tv.scrollRangeToVisible(NSRange(location: finalIndex, length: 0))
            tv.needsDisplay = true
        }

        func attachScrollHighlightObserverIfNeeded(_ scrollView: NSScrollView) {
            let clip = scrollView.contentView
            guard observedClipView !== clip else { return }
            if let old = observedClipView {
                NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: old)
            }
            clip.postsBoundsChangedNotifications = true
            observedClipView = clip
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleClipBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clip
            )
        }

        @objc private func handleClipBoundsDidChange(_ notification: Notification) {
            guard !isInvalidated, parent.enableHighlighting else { return }
            scrollHighlightWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.isInvalidated, self.parent.enableHighlighting,
                          let engine = self.engine,
                          let tv = self.textView,
                          let ts = tv.textStorage, ts.length > 0,
                          let lm = tv.layoutManager,
                          let tc = tv.textContainer,
                          let clip = self.observedClipView else { return }
                    let visRect = clip.bounds
                    guard visRect.height > 0 else { return }
                    let glyphRange = lm.glyphRange(forBoundingRectWithoutAdditionalLayout: visRect, in: tc)
                    guard glyphRange.length > 0 else { return }
                    let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                    engine.highlightViewportOnScroll(
                        visibleCharRange: charRange,
                        to: ts,
                        fontSize: self.parent.fontSize,
                        font: tv.font
                    )
                }
            }
            scrollHighlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.008, execute: work)
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
            if let noIntrinsic = scrollView as? NoIntrinsicScrollView {
                let shouldForward = !p.isScrollEnabled
                if noIntrinsic.forwardsScrollToEnclosingView != shouldForward {
                    noIntrinsic.forwardsScrollToEnclosingView = shouldForward
                    scrollView.hasVerticalScroller = p.isScrollEnabled
                    scrollView.hasHorizontalScroller = p.isScrollEnabled
                    if shouldForward && scrollView.contentView.bounds.origin != .zero {
                        scrollView.contentView.scroll(to: .zero)
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                    }
                }
            }
            if let ideTV = textView as? IDEInteractiveTextView, ideTV.collaborationFileURL != p.fileURL {
                ideTV.collaborationFileURL = p.fileURL
                ideTV.needsDisplay = true
            }
            attachScrollHighlightObserverIfNeeded(scrollView)

            let langChanged = lastLanguage != p.language
            let themeNameChanged = lastThemeName != p.themeName
            let fontChanged = lastFontSize != p.fontSize
            let darkChanged = lastIsDark != p.isDark
            let transparentChanged = lastIsTransparent != p.isTransparent
            let editableChanged = lastIsEditable != p.isEditable
            let highlightingChanged = lastEnableHighlighting != p.enableHighlighting
            let lineNumbersChanged = lastShowLineNumbers != p.showLineNumbers
            let fileURLChanged = lastFileURL != p.fileURL
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

            // Raw UTF-8 byte scan (`0x0D`) avoids O(N) Extended Grapheme Cluster breaking in `-Onone`.
            let normalizedText = p.text.utf8.contains(0x0D) ? p.text.replacingOccurrences(of: "\r\n", with: "\n") : p.text
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

            let lowerTheme = p.themeName?.lowercased() ?? ""
            let activeThemeID: String
            if !lowerTheme.isEmpty && lowerTheme != "system", let tn = p.themeName {
                activeThemeID = tn
            } else {
                activeThemeID = p.isDark ? "dark" : "light"
            }

            // Theme + colours
            if force || themeNameChanged || darkChanged || transparentChanged {
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
            var appliedIncrementalPatch = false
            var consumedPrebuilt: SyntaxHighlightingEngine.PrebuiltEditorDocument? = nil
            if didReplaceBuffer {
                let existingNS = textView.string as NSString
                let newNS = normalizedText as NSString
                let oldLen = existingNS.length
                let newLen = newNS.length

                // INCREMENTAL UTF-16 DIFF PATCHING:
                // When AI (`replace_in_file`), Cmd+K, or Collaboration updates part of an already-loaded
                // document (same file & visual config), patch only the changed UTF-16 window instead of
                // destroying the entire NSTextStorage, preserving scroll offset, cursor selection, and
                // unchanged TextKit glyph layout + IncrementalLexer line caches.
                let sameLogicalFile = !fileURLChanged
                if !force && !visualConfigChanged && sameLogicalFile && oldLen > 0 && newLen > 0,
                   let ts = textView.textStorage,
                   let patch = Self.computeUTF16DiffPatch(old: existingNS, new: newNS),
                   (patch.oldRange.length + patch.newRange.length) < max(oldLen, newLen) {
                    let oldSelection = textView.selectedRange()
                    let savedOrigin = scrollView.contentView.bounds.origin

                    isUpdating = true
                    ts.beginEditing()
                    ts.replaceCharacters(in: patch.oldRange, with: patch.replacement)
                    if patch.newRange.length > 0 {
                        ts.addAttributes([.foregroundColor: fgColor, .font: customFont, .ligature: 0], range: patch.newRange)
                    }
                    ts.endEditing()
                    isUpdating = false

                    let delta = patch.newRange.length - patch.oldRange.length
                    let oldEnd = patch.oldRange.location + patch.oldRange.length
                    let newSelLoc: Int
                    if oldSelection.location >= oldEnd {
                        newSelLoc = max(0, min(newLen, oldSelection.location + delta))
                    } else if oldSelection.location > patch.oldRange.location {
                        newSelLoc = min(newLen, patch.newRange.location + patch.newRange.length)
                    } else {
                        newSelLoc = min(newLen, oldSelection.location)
                    }
                    textView.setSelectedRange(NSRange(location: newSelLoc, length: 0))
                    scrollView.contentView.scroll(to: savedOrigin)
                    scrollView.reflectScrolledClipView(scrollView.contentView)

                    if p.enableHighlighting {
                        engine.processEdit(range: patch.newRange, changeInLength: delta, newContent: normalizedText)
                    }
                    appliedIncrementalPatch = true
                    (scrollView as? NoIntrinsicScrollView)?.lineNumberGutter?.refreshContentIndex()
                } else {
                    isUpdating = true
                    let r = NSRange(location: 0, length: newLen)
                    if r.length > 0 {
                        if let prebuilt = SyntaxHighlightingEngine.consumePrebuiltDocument(
                            path: p.fileURL?.standardizedFileURL.path,
                            normalizedText: normalizedText,
                            language: p.language,
                            fontSize: p.fontSize,
                            activeThemeID: activeThemeID,
                            fontName: p.fontName,
                            fontWeight: p.fontWeight,
                            enableHighlighting: p.enableHighlighting
                        ) {
                            consumedPrebuilt = prebuilt
                            textView.textStorage?.setAttributedString(prebuilt.attributedString)
                        } else {
                            let attr = NSAttributedString(
                                string: normalizedText,
                                attributes: [.foregroundColor: fgColor, .font: customFont, .ligature: 0]
                            )
                            textView.textStorage?.setAttributedString(attr)
                        }
                    } else {
                        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
                    }
                    isUpdating = false

                    if let starts = consumedPrebuilt?.lineStarts {
                        (scrollView as? NoIntrinsicScrollView)?.lineNumberGutter?.adoptPrecomputedLineStarts(starts)
                    } else if !p.enableHighlighting {
                        let starts = SyntaxHighlightingEngine.computeUTF16LineStartsFast(normalizedText)
                        (scrollView as? NoIntrinsicScrollView)?.lineNumberGutter?.adoptPrecomputedLineStarts(starts)
                    }
                }
            }

            if force || didReplaceBuffer || langChanged || themeNameChanged || darkChanged || fontChanged || highlightingChanged {
                if p.enableHighlighting {
                    if !appliedIncrementalPatch {
                        engine.setDocument(
                            normalizedText,
                            language: p.language,
                            precomputedLineStarts: consumedPrebuilt?.lineStarts
                        )
                        if consumedPrebuilt == nil, didReplaceBuffer, let starts = engine.currentLineOffsets {
                            (scrollView as? NoIntrinsicScrollView)?.lineNumberGutter?.adoptPrecomputedLineStarts(starts)
                        }
                        if let precoloredEnd = consumedPrebuilt?.precoloredUTF16End, precoloredEnd > 0 {
                            engine.recordPrebuiltHighlightedRange(NSRange(location: 0, length: precoloredEnd))
                        }
                    }
                } else {
                    engine.cancelHighlighting()
                }
                if p.enableHighlighting, let ts = textView.textStorage, ts.length > 0 {
                    let visCharRange: NSRange? = {
                        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return nil }
                        let visRect = scrollView.contentView.bounds
                        guard visRect.height > 0 else {
                            return NSRange(location: 0, length: min(ts.length, 8000))
                        }
                        let glyphRange = lm.glyphRange(forBoundingRectWithoutAdditionalLayout: visRect, in: tc)
                        if glyphRange.length == 0 {
                            return NSRange(location: 0, length: min(ts.length, 8000))
                        }
                        return lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                    }()

                    let skipInitialApply = (consumedPrebuilt?.precoloredUTF16End ?? 0) > 0 && !appliedIncrementalPatch
                    engine.applyHighlightingAsync(
                        to: ts,
                        fontSize: p.fontSize,
                        font: textView.font,
                        visibleCharRange: visCharRange,
                        skipMainActorApplyIfFullDocument: skipInitialApply
                    ) { [weak textView, weak scrollView] in
                        if !skipInitialApply, let tv = textView, let tc = tv.textContainer, let sv = scrollView {
                            let bounds = sv.contentView.bounds
                            if sv.window != nil && bounds.width >= 32 && bounds.height >= 16 {
                                tv.layoutManager?.ensureLayout(forBoundingRect: bounds, in: tc)
                            }
                            tv.needsDisplay = true
                        }
                        scrollView?.contentView.needsDisplay = true
                        (scrollView as? NoIntrinsicScrollView)?.lineNumberGutter?.needsDisplay = true
                    }
                }
            }

            if let tc = textView.textContainer,
               scrollView.window != nil,
               scrollView.contentView.bounds.width >= 32,
               scrollView.contentView.bounds.height >= 16 {
                textView.layoutManager?.ensureLayout(forBoundingRect: scrollView.contentView.bounds, in: tc)
            }
            textView.needsDisplay = true
            scrollView.contentView.needsDisplay = true
            (scrollView as? NoIntrinsicScrollView)?.lineNumberGutter?.needsDisplay = true
        }

        func configureTextGeometry(for textView: NSTextView, in scrollView: NSScrollView) {
            let contentSize = scrollView.contentSize
            // Never collapse an unmounted or transient 0-width NSScrollView down to width=1pt!
            // Wrapping 380k characters at width=1pt creates 380k 1-char CoreText line fragments on MainActor.
            let fallbackWidth: CGFloat = parent.isScrollEnabled ? 960 : 640
            let fallbackHeight: CGFloat = parent.isScrollEnabled ? 680 : 64
            let targetWidth = contentSize.width >= 64 ? contentSize.width : max(textView.frame.width, fallbackWidth)
            let targetHeight = contentSize.height >= 24 ? contentSize.height : max(textView.frame.height, fallbackHeight)

            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.minSize = NSSize(width: 0, height: parent.isScrollEnabled ? targetHeight : 24)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                      height: CGFloat.greatestFiniteMagnitude)

            let newWidth = targetWidth
            let newHeight = parent.isScrollEnabled ? max(textView.frame.height, targetHeight) : targetHeight
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
        
        nonisolated static func computeUTF16DiffPatch(
            old oldNS: NSString,
            new newNS: NSString
        ) -> (oldRange: NSRange, newRange: NSRange, replacement: String)? {
            let oldLen = oldNS.length
            let newLen = newNS.length
            let minLen = min(oldLen, newLen)

            var prefix = 0
            while prefix < minLen && oldNS.character(at: prefix) == newNS.character(at: prefix) {
                prefix += 1
            }
            // Do not split a UTF-16 surrogate pair at the prefix boundary
            if prefix > 0 && prefix < minLen {
                let nextOld = oldNS.character(at: prefix)
                let nextNew = newNS.character(at: prefix)
                if (0xDC00...0xDFFF).contains(nextOld) || (0xDC00...0xDFFF).contains(nextNew) {
                    prefix -= 1
                }
            }

            if prefix == oldLen && prefix == newLen {
                return nil
            }

            var suffix = 0
            let maxSuffix = minLen - prefix
            while suffix < maxSuffix && oldNS.character(at: oldLen - 1 - suffix) == newNS.character(at: newLen - 1 - suffix) {
                suffix += 1
            }
            // Do not split a UTF-16 surrogate pair at the suffix boundary
            if suffix > 0 {
                let firstOldSuffix = oldNS.character(at: oldLen - suffix)
                let firstNewSuffix = newNS.character(at: newLen - suffix)
                if (0xDC00...0xDFFF).contains(firstOldSuffix) || (0xDC00...0xDFFF).contains(firstNewSuffix) {
                    suffix -= 1
                }
            }

            let oldRange = NSRange(location: prefix, length: oldLen - prefix - suffix)
            let newRange = NSRange(location: prefix, length: newLen - prefix - suffix)
            let replacement = newNS.substring(with: newRange)
            return (oldRange: oldRange, newRange: newRange, replacement: replacement)
        }

        /// Requests LSP semantic tokens (debounced) and overlays them on the lexical colors, like VS Code.
        func scheduleSemanticOverlay(afterNanoseconds delay: UInt64, retriesLeft: Int = 0) {
            guard parent.enableHighlighting, parent.fileURL != nil,
                  (UserDefaults.standard.object(forKey: "semanticHighlightingEnabled") as? Bool) ?? true,
                  LanguageServer.serverFor(language: parent.language) != nil else { return }
            semanticTask?.cancel()
            semanticTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled, let self, !self.isInvalidated,
                      let url = self.parent.fileURL,
                      let tv = self.textView, let ts = tv.textStorage,
                      ts.length > 0, ts.length < 400_000, !tv.hasMarkedText(),
                      let engine = self.engine else { return }
                let language = self.parent.language
                let uri = url.standardizedFileURL.absoluteString
                let text = ts.string
                await LSPManager.shared.documentChanged(uri: uri, language: language, content: text)
                let fetched = await LSPManager.shared.getSemanticTokens(uri: uri, language: language)
                guard !Task.isCancelled, !self.isInvalidated else { return }
                guard let tokens = fetched else {
                    // Server may still be starting/indexing — retry a couple of times.
                    if retriesLeft > 0 {
                        self.scheduleSemanticOverlay(afterNanoseconds: 4_000_000_000, retriesLeft: retriesLeft - 1)
                    }
                    return
                }
                guard ts.string == text else { return }
                await engine.applySemanticTokens(tokens, to: ts, text: text)
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            isInvalidated = true
            highlightTimer?.invalidate()
            lspChangeTask?.cancel()
            autocompleteTask?.cancel()
            bindingSyncTask?.cancel()
            semanticTask?.cancel()
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
                        await LSPManager.shared.documentChanged(uri: url.standardizedFileURL.absoluteString, language: language, content: fullString)
                        await MainActor.run { [weak self] in
                            self?.scheduleSemanticOverlay(afterNanoseconds: 350_000_000)
                        }
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
        
        private static func computeOneBasedLineAndColumn(utf16Offset: Int, in nsText: NSString) -> (line: Int, column: Int) {
            let safeOffset = max(0, min(utf16Offset, nsText.length))
            guard safeOffset > 0 else { return (1, 1) }
            var line = 1
            var lastLineStart = 0
            var searchIdx = 0
            while searchIdx < safeOffset {
                let nl = nsText.range(
                    of: "\n",
                    options: .literal,
                    range: NSRange(location: searchIdx, length: safeOffset - searchIdx)
                )
                if nl.location == NSNotFound { break }
                line += 1
                lastLineStart = nl.location + 1
                searchIdx = nl.location + 1
            }
            return (line, max(1, safeOffset - lastLineStart + 1))
        }

        private func syncCollaborationSelection(in textView: NSTextView, isTyping: Bool) {
            guard CollaborationService.shared.currentSession != nil,
                  let fileURL = parent.fileURL else { return }
            let sel = textView.selectedRange()
            let nsText = textView.string as NSString
            let startPos = Self.computeOneBasedLineAndColumn(utf16Offset: sel.location, in: nsText)
            var endLine: Int? = nil
            var endCol: Int? = nil
            if sel.length > 0 {
                let endPos = Self.computeOneBasedLineAndColumn(utf16Offset: sel.location + sel.length, in: nsText)
                endLine = endPos.line
                endCol = endPos.column
            }
            CollaborationService.shared.updateLocalEditorSelection(
                filePath: fileURL.path,
                line: startPos.line,
                column: startPos.column,
                endLine: endLine,
                endColumn: endCol,
                isTyping: isTyping
            )
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !textView.hasMarkedText() else { return }
            guard !isUpdating else { return }
            
            let newText = textView.string
            // Keep `lastText` synced immediately so SwiftUI's `updateNSView` knows `textView`
            // already has this exact text and skips redundant full-document re-application.
            self.lastText = newText
            
            // Stream live multiplayer caret + typing buffer over WebSocket (110ms debounce for buffer)
            if CollaborationService.shared.currentSession != nil, let fileURL = parent.fileURL {
                syncCollaborationSelection(in: textView, isTyping: true)
                let path = fileURL.path
                collabEditSyncTask?.cancel()
                collabEditSyncTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 110_000_000)
                    guard let self = self, !Task.isCancelled, !self.isInvalidated else { return }
                    CollaborationService.shared.notifyLocalFileEdited(path: path, content: newText)
                }
            }

            // Debounce SwiftUI `@Binding var text` propagation (90ms normal, 320ms on multi-MB plain-text files)
            // so typing at 60-120 WPM doesn't force SwiftUI to re-evaluate the parent view hierarchy on every keystroke.
            let isLargePlainDoc = !parent.enableHighlighting || (textView.textStorage?.length ?? 0) > 512_000
            let syncDelayNs: UInt64 = isLargePlainDoc ? 320_000_000 : 90_000_000
            bindingSyncTask?.cancel()
            bindingSyncTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: syncDelayNs)
                guard let self = self, !Task.isCancelled, !self.isInvalidated else { return }
                if self.parent.text != newText {
                    self.parent.text = newText
                }
            }

            // Trigger fast incremental highlight (50ms debounce) when syntax highlighting is enabled
            if parent.enableHighlighting {
                triggerDebouncedHighlight(for: textView)
            }
        }
        
        public func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            bindingSyncTask?.cancel()
            collabEditSyncTask?.cancel()
            let finalString = textView.string
            self.lastText = finalString
            if parent.text != finalString {
                parent.text = finalString
            }
            if CollaborationService.shared.currentSession != nil, let fileURL = parent.fileURL {
                CollaborationService.shared.notifyLocalFileEdited(path: fileURL.path, content: finalString)
                syncCollaborationSelection(in: textView, isTyping: false)
            }
        }
        
        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if CollaborationService.shared.currentSession != nil, !isUpdating {
                syncCollaborationSelection(in: textView, isTyping: false)
            }
            guard let range = textView.selectedRanges.first?.rangeValue,
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
