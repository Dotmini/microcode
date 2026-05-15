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
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
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
    
    /// Public initializer — creates an independent instance with all themes pre-registered.
    /// Use this when you need isolated theme state (e.g., per-editor instances).
    public init() {
        // Initialize with default dark theme
        self.activeTheme = ThemeManager.createDefaultDarkTheme()
        
        // Register all AppThemes (Single Source of Truth)
        for themeCase in AppTheme.allCases {
            // Skip system as it maps to current mode, but register actual themes
            if themeCase != .system {
                let theme = themeCase.toTheme()
                self.themeCache[theme.name] = theme
                
                // Keep default aliases for compatibility
                if themeCase == .dark { self.themeCache["default-dark"] = theme }
                if themeCase == .light { self.themeCache["default-light"] = theme }
            }
        }
        
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
    
    /// Creates the default dark theme (similar to VS Code Dark+)
    public static func createDefaultDarkTheme() -> Theme {
        Theme(
            name: "default-dark",
            displayName: "Dark+ (Default)",
            isDark: true,
            editorBackground: "#1E1E1E",
            editorForeground: "#D4D4D4",
            editorSelection: "#264F78",
            editorLineHighlight: "#2D2D2D",
            editorCursor: "#AEAFAD",
            editorGutter: "#1E1E1E",
            editorGutterText: "#858585",
            tokenColors: [
                "keyword": TokenStyleConfig(foreground: "#569CD6"),
                "keywordControl": TokenStyleConfig(foreground: "#C586C0"),
                "keywordDeclaration": TokenStyleConfig(foreground: "#569CD6"),
                "keywordModifier": TokenStyleConfig(foreground: "#569CD6"),
                "keywordOperator": TokenStyleConfig(foreground: "#569CD6"),
                "string": TokenStyleConfig(foreground: "#CE9178"),
                "number": TokenStyleConfig(foreground: "#B5CEA8"),
                "boolean": TokenStyleConfig(foreground: "#569CD6"),
                "null": TokenStyleConfig(foreground: "#569CD6"),
                "comment": TokenStyleConfig(foreground: "#6A9955", fontStyle: "italic"),
                "commentDoc": TokenStyleConfig(foreground: "#6A9955", fontStyle: "italic"),
                "commentBlock": TokenStyleConfig(foreground: "#6A9955", fontStyle: "italic"),
                "type": TokenStyleConfig(foreground: "#4EC9B0"),
                "function": TokenStyleConfig(foreground: "#DCDCAA"),
                "identifier": TokenStyleConfig(foreground: "#9CDCFE"),
                "variable": TokenStyleConfig(foreground: "#9CDCFE"),
                "property": TokenStyleConfig(foreground: "#9CDCFE"),
                "parameter": TokenStyleConfig(foreground: "#9CDCFE"),
                "operator": TokenStyleConfig(foreground: "#D4D4D4"),
                "punctuation": TokenStyleConfig(foreground: "#D4D4D4"),
                "delimiter": TokenStyleConfig(foreground: "#D4D4D4"),
                "annotation": TokenStyleConfig(foreground: "#DCDCAA"),
                "preprocessor": TokenStyleConfig(foreground: "#C586C0"),
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

