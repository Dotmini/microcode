//
//  ThemeManager.swift
//  MicroCode - Syntax Highlighting Engine
//
//  Manages color themes for syntax highlighting.
//  Loads themes from JSON files and maps token types to styles.
//
//  Design Pattern: Singleton + Repository Pattern
//  - Single source of truth for theme data
//  - Themes are loaded lazily and cached
//  - Easy to add custom themes via JSON
//
//  Copyright © 2025 Dotmini Company Limited. All rights reserved.
//

import Foundation
import AppKit

// MARK: - Theme Definition

/// Complete theme definition loaded from JSON.
public struct Theme: Codable, Sendable {
    public let name: String
    public let displayName: String
    public let isDark: Bool
    
    /// Editor colors
    public let editorBackground: String
    public let editorForeground: String
    public let editorSelection: String
    public let editorLineHighlight: String
    public let editorCursor: String
    public let editorGutter: String
    public let editorGutterText: String
    
    /// Syntax colors - maps token type name to style
    public let tokenColors: [String: TokenStyleConfig]
    
    public init(
        name: String,
        displayName: String,
        isDark: Bool,
        editorBackground: String,
        editorForeground: String,
        editorSelection: String,
        editorLineHighlight: String,
        editorCursor: String,
        editorGutter: String,
        editorGutterText: String,
        tokenColors: [String: TokenStyleConfig]
    ) {
        self.name = name
        self.displayName = displayName
        self.isDark = isDark
        self.editorBackground = editorBackground
        self.editorForeground = editorForeground
        self.editorSelection = editorSelection
        self.editorLineHighlight = editorLineHighlight
        self.editorCursor = editorCursor
        self.editorGutter = editorGutter
        self.editorGutterText = editorGutterText
        self.tokenColors = tokenColors
    }
}

/// Style configuration for a token type (from JSON)
public struct TokenStyleConfig: Codable, Sendable {
    public let foreground: String?
    public let background: String?
    public let fontStyle: String?  // "bold", "italic", "bold italic", "underline"
    
    public init(foreground: String? = nil, background: String? = nil, fontStyle: String? = nil) {
        self.foreground = foreground
        self.background = background
        self.fontStyle = fontStyle
    }
    
    /// Convert to TokenStyle
    public func toTokenStyle(defaultForeground: String) -> TokenStyle {
        let isBold = fontStyle?.contains("bold") ?? false
        let isItalic = fontStyle?.contains("italic") ?? false
        let isUnderline = fontStyle?.contains("underline") ?? false
        
        return TokenStyle(
            foregroundColor: foreground ?? defaultForeground,
            backgroundColor: background,
            isBold: isBold,
            isItalic: isItalic,
            isUnderline: isUnderline
        )
    }
}

// MARK: - Theme Manager

/// Manages loading and accessing color themes.
/// Thread-safe. Can be used as singleton (.shared) or per-instance for isolation.
public final class ThemeManager: @unchecked Sendable {
    
    /// Shared instance (for global UI like LineNumberRulerView)
    public static let shared = ThemeManager()
    
    /// Currently active theme
    private var activeTheme: Theme
    
    /// Cache of all loaded themes
    private var themeCache: [String: Theme] = [:]
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    /// Style cache for current theme
    private var styleCache: [SyntaxTokenType: TokenStyle] = [:]
    
    /// Prebuilt immutable dictionary of all built-in themes so every `ThemeManager()` instantiation
    /// is O(1) copy-on-write instead of rebuilding 34 `Theme` structs on `@MainActor`.
    private static let builtInThemes: (defaultDark: Theme, cache: [String: Theme]) = {
        let defaultDark = ThemeManager.createDefaultDarkTheme()
        var cache: [String: Theme] = [
            "default-dark": defaultDark,
            "dark": defaultDark,
            "xcodeDark": defaultDark
        ]
        for themeCase in AppTheme.allCases where themeCase != .system {
            let theme = themeCase.toTheme()
            cache[theme.name] = theme
            if themeCase == .dark || themeCase == .xcodeDark {
                cache["default-dark"] = defaultDark
                cache["dark"] = defaultDark
                cache["xcodeDark"] = defaultDark
            }
            if themeCase == .light {
                cache["default-light"] = theme
            }
        }
        return (defaultDark, cache)
    }()

    public init() {
        self.activeTheme = Self.builtInThemes.defaultDark
        self.themeCache = Self.builtInThemes.cache
        rebuildStyleCache()
    }
    
    // MARK: - Public API
    
    /// Get the current active theme
    public var currentTheme: Theme {
        lock.lock()
        defer { lock.unlock() }
        return activeTheme
    }
    
    /// Set the active theme by name.
    /// "system" is resolved to "dark" or "light" based on the current macOS appearance.
    /// If the theme is not in the cache a safe fallback is used so text is always visible.
    public func setActiveTheme(_ themeName: String) {
        lock.lock()
        defer { lock.unlock() }
        
        // Resolve "system" pseudo-theme to an actual theme id
        let resolvedName: String
        if themeName.lowercased() == "system" {
            // Check effective appearance outside the lock — NSApp is main-thread safe
            let isDarkMode = (NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            resolvedName = isDarkMode ? "dark" : "light"
        } else {
            resolvedName = themeName
        }
        
        if let theme = themeCache[resolvedName] {
            activeTheme = theme
            rebuildStyleCache()
        } else if let fallback = themeCache["dark"] ?? themeCache["default-dark"] ?? themeCache.values.first {
            // Safety fallback: always apply SOME theme — prevents invisible text when
            // an unrecognised theme id is passed (e.g. a custom or future theme).
            activeTheme = fallback
            rebuildStyleCache()
        }
        // If even the fallback is missing the default-dark set in init() stays active,
        // which always has a valid light foreground on dark background.
    }
    
    /// Load a theme from JSON data
    public func loadTheme(from jsonData: Data) throws -> Theme {
        let decoder = JSONDecoder()
        let theme = try decoder.decode(Theme.self, from: jsonData)
        
        lock.lock()
        themeCache[theme.name] = theme
        lock.unlock()
        
        return theme
    }
    
    /// Load a theme from a file URL
    public func loadTheme(from url: URL) throws -> Theme {
        let data = try Data(contentsOf: url)
        return try loadTheme(from: data)
    }
    
    /// Import a standard VS Code color theme (`colors` + `tokenColors` TextMate scopes) and register it
    /// under `name` (defaults to the file name). Returns the registered theme.
    @discardableResult
    public func loadVSCodeTheme(from url: URL, name: String? = nil) throws -> Theme {
        var text = try String(contentsOf: url, encoding: .utf8)
        // VS Code themes are JSONC: strip full-line // comments and trailing commas.
        text = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        text = text.replacingOccurrences(of: ",(\\s*[}\\]])", with: "$1", options: .regularExpression)
        guard let data = text.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ThemeManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid VS Code theme JSON"])
        }
        func hex(_ v: Any?) -> String? {
            guard let s = v as? String, s.hasPrefix("#"), s.count >= 7 else { return nil }
            return String(s.prefix(7))
        }
        let colors = root["colors"] as? [String: Any] ?? [:]
        let isDark = (root["type"] as? String ?? "dark").lowercased() != "light"
        let themeName = name ?? url.deletingPathExtension().lastPathComponent
        let bg = hex(colors["editor.background"]) ?? (isDark ? "#1E1E1E" : "#FFFFFF")
        let fg = hex(colors["editor.foreground"]) ?? (isDark ? "#D4D4D4" : "#000000")

        // TextMate scope prefix -> our token keys (later/more-specific rules override earlier ones)
        let scopeMap: [(String, [String])] = [
            ("keyword", ["keyword", "keywordControl", "keywordDeclaration", "keywordModifier", "keywordOperator"]),
            ("storage", ["keywordDeclaration", "keywordModifier"]),
            ("keyword.operator", ["operator", "keywordOperator"]),
            ("string", ["string"]),
            ("string.regexp", ["regex"]),
            ("constant.character.escape", ["escape"]),
            ("constant.numeric", ["number"]),
            ("constant", ["constant", "enumMember"]),
            ("constant.language", ["boolean", "null"]),
            ("comment", ["comment", "commentDoc", "commentBlock"]),
            ("entity.name.function", ["function"]),
            ("support.function", ["function"]),
            ("entity.name.type", ["type"]),
            ("entity.name.class", ["type"]),
            ("support.class", ["type"]),
            ("support.type", ["type"]),
            ("variable", ["variable", "identifier"]),
            ("variable.parameter", ["parameter"]),
            ("variable.other.property", ["property"]),
            ("variable.other.object.property", ["property"]),
            ("support.variable.property", ["property"]),
            ("punctuation", ["punctuation", "delimiter"]),
            ("meta.preprocessor", ["preprocessor"]),
            ("keyword.control.directive", ["preprocessor"]),
            ("entity.name.tag", ["markup"]),
            ("meta.decorator", ["annotation"]),
            ("entity.name.function.decorator", ["annotation"]),
            ("punctuation.definition.template-expression", ["stringInterpolation"])
        ].sorted { $0.0.count < $1.0.count }

        var tokenColors: [String: TokenStyleConfig] = [:]
        for rule in (root["tokenColors"] as? [[String: Any]] ?? []) {
            guard let settings = rule["settings"] as? [String: Any], let color = hex(settings["foreground"]) else { continue }
            let fontStyle = settings["fontStyle"] as? String
            var scopes: [String] = []
            if let s = rule["scope"] as? String {
                scopes = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else if let a = rule["scope"] as? [String] {
                scopes = a
            }
            for scope in scopes {
                for (key, targets) in scopeMap where scope == key || scope.hasPrefix(key + ".") {
                    for t in targets { tokenColors[t] = TokenStyleConfig(foreground: color, fontStyle: fontStyle) }
                }
            }
        }
        // Semantic token colors (e.g. "variable.readonly") refine constant/parameter/property when present.
        if let sem = root["semanticTokenColors"] as? [String: Any] {
            func semColor(_ v: Any?) -> String? { hex(v) ?? hex((v as? [String: Any])?["foreground"]) }
            if let c = semColor(sem["variable.readonly"]) ?? semColor(sem["variable"]) { tokenColors["constant"] = TokenStyleConfig(foreground: c) }
            if let c = semColor(sem["parameter"]) { tokenColors["parameter"] = TokenStyleConfig(foreground: c) }
            if let c = semColor(sem["property"]) { tokenColors["property"] = TokenStyleConfig(foreground: c) }
        }
        tokenColors["identifier"] = tokenColors["identifier"] ?? TokenStyleConfig(foreground: fg)

        let theme = Theme(
            name: themeName,
            displayName: themeName,
            isDark: isDark,
            editorBackground: bg,
            editorForeground: fg,
            editorSelection: hex(colors["editor.selectionBackground"]) ?? (isDark ? "#264F78" : "#ADD6FF"),
            editorLineHighlight: hex(colors["editor.lineHighlightBackground"]) ?? (isDark ? "#2A2D2E" : "#F0F0F0"),
            editorCursor: hex(colors["editorCursor.foreground"]) ?? fg,
            editorGutter: bg,
            editorGutterText: hex(colors["editorLineNumber.foreground"]) ?? (isDark ? "#858585" : "#237893"),
            tokenColors: tokenColors
        )
        lock.lock()
        themeCache[theme.name] = theme
        lock.unlock()
        return theme
    }
    
    /// Get all available theme names
    public var availableThemes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(themeCache.keys).sorted()
    }
    
    /// Get style for a token type
    public func style(for tokenType: SyntaxTokenType) -> TokenStyle {
        lock.lock()
        defer { lock.unlock() }
        return styleCache[tokenType] ?? TokenStyle.default
    }
    
    /// Apply styling to tokens
    public func applyStyles(to tokens: [SyntaxToken]) -> [StyledToken] {
        tokens.map { token in
            StyledToken(token: token, style: style(for: token.type))
        }
    }
    
    // MARK: - NSColor Conversion
    
    /// Get NSColor for a token type
    public func color(for tokenType: SyntaxTokenType) -> NSColor {
        let style = self.style(for: tokenType)
        return NSColor(hex: style.foregroundColor) ?? .textColor
    }
    
    /// Get editor background color
    public var editorBackgroundColor: NSColor {
        NSColor(hex: currentTheme.editorBackground) ?? .textBackgroundColor
    }
    
    /// Get editor foreground color
    public var editorForegroundColor: NSColor {
        NSColor(hex: currentTheme.editorForeground) ?? .textColor
    }
    
    public var selectionColor: NSColor {
        NSColor(hex: currentTheme.editorSelection) ?? .selectedTextBackgroundColor
    }
    
    public var caretColor: NSColor {
        NSColor(hex: currentTheme.editorCursor) ?? .textColor
    }
    
    public var editorGutterColor: NSColor {
        NSColor(hex: currentTheme.editorGutter) ?? .textBackgroundColor
    }
    
    public var editorGutterTextColor: NSColor {
        NSColor(hex: currentTheme.editorGutterText) ?? .secondaryLabelColor
    }
    
    // MARK: - Private Helpers
    
    /// Rebuild the style cache from current theme
    private func rebuildStyleCache() {
        styleCache.removeAll()
        
        let defaultForeground = activeTheme.editorForeground
        
        // Map each token type to its style
        for tokenType in SyntaxTokenType.allCases {
            let typeName = tokenType.rawValue
            
            if let config = activeTheme.tokenColors[typeName] {
                styleCache[tokenType] = config.toTokenStyle(defaultForeground: defaultForeground)
            } else {
                // Fallback to related type or default
                let fallbackStyle = findFallbackStyle(for: tokenType, defaultForeground: defaultForeground)
                styleCache[tokenType] = fallbackStyle
            }
        }
    }
    
    /// Find a fallback style for token types not explicitly defined
    private func findFallbackStyle(for tokenType: SyntaxTokenType, defaultForeground: String) -> TokenStyle {
        // Fallback mappings for related types
        let fallbacks: [SyntaxTokenType: [String]] = [
            .keywordControl: ["keyword"],
            .keywordOperator: ["keyword"],
            .keywordDeclaration: ["keyword"],
            .keywordModifier: ["keyword"],
            .stringInterpolation: ["string"],
            .character: ["string"],
            .commentDoc: ["comment"],
            .commentBlock: ["comment"],
            .variable: ["identifier"],
            .property: ["identifier"],
            .parameter: ["identifier"],
            .constant: ["identifier"],
            .enumMember: ["type"],
            .preprocessor: ["annotation", "keyword"],
            .punctuation: ["delimiter"],
            .delimiter: ["punctuation"],
        ]
        
        // Try fallback keys
        if let keys = fallbacks[tokenType] {
            for key in keys {
                if let config = activeTheme.tokenColors[key] {
                    return config.toTokenStyle(defaultForeground: defaultForeground)
                }
            }
        }
        
        // Ultimate fallback: default foreground
        return TokenStyle(foregroundColor: defaultForeground)
    }
    
    // MARK: - Built-in Themes
    
    /// Creates the default dark theme (MicroCode Apple Pro / Xcode Dark Aesthetic)
    public static func createDefaultDarkTheme() -> Theme {
        Theme(
            name: "default-dark",
            displayName: "MicroCode Pro Dark",
            isDark: true,
            editorBackground: "#000000",
            editorForeground: "#FFFFFF",
            editorSelection: "#263342",
            editorLineHighlight: "#111114",
            editorCursor: "#FFFFFF",
            editorGutter: "#000000",
            editorGutterText: "#4A4A50",
            tokenColors: [
                "keyword": TokenStyleConfig(foreground: "#FC5FA3"),
                "keywordControl": TokenStyleConfig(foreground: "#FC5FA3"),
                "keywordDeclaration": TokenStyleConfig(foreground: "#FC5FA3"),
                "keywordModifier": TokenStyleConfig(foreground: "#FC5FA3"),
                "keywordOperator": TokenStyleConfig(foreground: "#FC5FA3"),
                "string": TokenStyleConfig(foreground: "#FC6A5D"),
                "number": TokenStyleConfig(foreground: "#D0BF69"),
                "boolean": TokenStyleConfig(foreground: "#FC5FA3"),
                "null": TokenStyleConfig(foreground: "#FC5FA3"),
                "comment": TokenStyleConfig(foreground: "#6C7986", fontStyle: "italic"),
                "commentDoc": TokenStyleConfig(foreground: "#6C7986", fontStyle: "italic"),
                "commentBlock": TokenStyleConfig(foreground: "#6C7986", fontStyle: "italic"),
                "type": TokenStyleConfig(foreground: "#5DD8CE"),
                "function": TokenStyleConfig(foreground: "#41A7FC"),
                "identifier": TokenStyleConfig(foreground: "#FFFFFF"),
                "variable": TokenStyleConfig(foreground: "#FFFFFF"),
                "property": TokenStyleConfig(foreground: "#5DD8CE"),
                "parameter": TokenStyleConfig(foreground: "#FFFFFF"),
                "operator": TokenStyleConfig(foreground: "#FFFFFF"),
                "punctuation": TokenStyleConfig(foreground: "#D1D1D6"),
                "delimiter": TokenStyleConfig(foreground: "#E5E5EA"),
                "annotation": TokenStyleConfig(foreground: "#FD8F3F"),
                "preprocessor": TokenStyleConfig(foreground: "#FD8F3F"),
                "escape": TokenStyleConfig(foreground: "#D7BA7D"),
            ]
        )
    }
    
    /// Creates the default light theme
    public static func createDefaultLightTheme() -> Theme {
        Theme(
            name: "default-light",
            displayName: "Light+ (Default)",
            isDark: false,
            editorBackground: "#FFFFFF",
            editorForeground: "#000000",
            editorSelection: "#ADD6FF",
            editorLineHighlight: "#FFFBDD",
            editorCursor: "#000000",
            editorGutter: "#FFFFFF",
            editorGutterText: "#237893",
            tokenColors: [
                "keyword": TokenStyleConfig(foreground: "#0000FF"),
                "keywordControl": TokenStyleConfig(foreground: "#AF00DB"),
                "keywordDeclaration": TokenStyleConfig(foreground: "#0000FF"),
                "keywordModifier": TokenStyleConfig(foreground: "#0000FF"),
                "keywordOperator": TokenStyleConfig(foreground: "#0000FF"),
                "string": TokenStyleConfig(foreground: "#A31515"),
                "number": TokenStyleConfig(foreground: "#098658"),
                "boolean": TokenStyleConfig(foreground: "#0000FF"),
                "null": TokenStyleConfig(foreground: "#0000FF"),
                "comment": TokenStyleConfig(foreground: "#008000", fontStyle: "italic"),
                "commentDoc": TokenStyleConfig(foreground: "#008000", fontStyle: "italic"),
                "commentBlock": TokenStyleConfig(foreground: "#008000", fontStyle: "italic"),
                "type": TokenStyleConfig(foreground: "#267F99"),
                "function": TokenStyleConfig(foreground: "#795E26"),
                "identifier": TokenStyleConfig(foreground: "#001080"),
                "variable": TokenStyleConfig(foreground: "#001080"),
                "property": TokenStyleConfig(foreground: "#001080"),
                "parameter": TokenStyleConfig(foreground: "#001080"),
                "operator": TokenStyleConfig(foreground: "#000000"),
                "punctuation": TokenStyleConfig(foreground: "#000000"),
                "delimiter": TokenStyleConfig(foreground: "#000000"),
                "annotation": TokenStyleConfig(foreground: "#795E26"),
                "preprocessor": TokenStyleConfig(foreground: "#AF00DB"),
                "escape": TokenStyleConfig(foreground: "#EE0000"),
            ]
        )
    }
    
    // MARK: - Legacy Methods Removed
    // createHappyNewYearTheme, createExtraClearTheme, etc. are now handled via AppTheme.toTheme() in AppState.swift

}

