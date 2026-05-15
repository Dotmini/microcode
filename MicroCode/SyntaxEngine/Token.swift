//
//  SyntaxToken.swift
//  MicroCode - Syntax Highlighting Engine
//
//  Core token types and structures for syntax highlighting.
//  This module is UI-agnostic and can be used with any rendering backend.
//
//  Design Pattern: Value Types + Protocol-Oriented Programming
//  - SyntaxTokens are value types (structs) for safety and performance
//  - SyntaxTokenType is an enum for exhaustive pattern matching
//  - SyntaxTextRange uses line/column for editor integration
//
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import Foundation

// MARK: - Text Range

/// Represents a range in source code using line and column indices.
/// Line and column are 0-indexed for consistency with most parsing libraries.
public struct SyntaxTextRange: Equatable, Hashable, Sendable {
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int
    
    /// Character offset from the beginning of the document
    public let startOffset: Int
    public let endOffset: Int
    
    public init(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int, startOffset: Int, endOffset: Int) {
        self.startLine = startLine
        self.startColumn = startColumn
        self.endLine = endLine
        self.endColumn = endColumn
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
    
    /// Convenience initializer for single-line tokens
    public init(line: Int, column: Int, length: Int, offset: Int) {
        self.startLine = line
        self.startColumn = column
        self.endLine = line
        self.endColumn = column + length
        self.startOffset = offset
        self.endOffset = offset + length
    }
    
    /// Returns NSRange for use with NSAttributedString
    public var nsRange: NSRange {
        NSRange(location: startOffset, length: endOffset - startOffset)
    }
    
    /// Check if this range contains a specific line
    public func containsLine(_ line: Int) -> Bool {
        line >= startLine && line <= endLine
    }
    
    /// Check if this range overlaps with another range
    public func overlaps(with other: SyntaxTextRange) -> Bool {
        !(endOffset <= other.startOffset || startOffset >= other.endOffset)
    }
}

// MARK: - SyntaxToken Type

/// Categorizes tokens for syntax highlighting.
/// Each category maps to a style in the theme.
public enum SyntaxTokenType: String, CaseIterable, Sendable {
    // Keywords & Control Flow
    case keyword            // if, else, for, while, return, etc.
    case keywordControl     // break, continue, goto
    case keywordOperator    // and, or, not, in, is
    case keywordDeclaration // let, var, const, func, class, struct
    case keywordModifier    // public, private, static, async, await
    
    // Literals
    case string             // "hello", 'world'
    case stringInterpolation // \(expression) inside strings
    case character          // 'a' (single character literals)
    case number             // 42, 3.14, 0xFF
    case boolean            // true, false
    case null               // nil, null, None
    
    // Identifiers
    case identifier         // Generic identifier
    case type               // Type names (usually capitalized)
    case function           // Function/method names when called
    case parameter          // Function parameters
    case property           // Object properties/fields
    case variable           // Variable identifiers
    case constant           // Constant identifiers (ALL_CAPS)
    case enumMember         // Enum case names
    
    // Comments
    case comment            // Single-line comment
    case commentBlock       // Multi-line comment
    case commentDoc         // Documentation comment (///, /** */)
    
    // Operators & Punctuation
    case `operator`         // +, -, *, /, =, ==, etc.
    case punctuation        // ( ) [ ] { } , ; :
    case delimiter          // . ->
    
    // Special
    case preprocessor       // #include, #define, @attribute
    case annotation         // @decorator, @propertyWrapper
    case escape             // \n, \t, \\, etc. in strings
    case regex              // Regular expression literals
    case markup             // Markdown/HTML tags
    
    // Meta
    case unknown            // Unrecognized token
    case whitespace         // Spaces, tabs (usually not styled)
    case newline            // Line breaks
    case error              // Syntax error tokens
}

// MARK: - Lexer State

/// State machine states for the lexer.
/// Used for incremental parsing - knowing what state we're in at end of a line
/// allows us to correctly resume parsing from that line.
public enum SyntaxLexerState: Int, Equatable, Hashable, Sendable {
    case normal = 0                 // Default state
    case inString = 1               // Inside a double-quoted string
    case inStringSingle = 2         // Inside a single-quoted string
    case inStringTemplate = 3       // Inside a template string (backticks)
    case inStringMultiline = 4      // Inside a multi-line string (""" or ''')
    case inComment = 5              // Inside a block comment /* */
    case inDocComment = 6           // Inside a doc comment /** */
    case inRegex = 7                // Inside a regex literal
    case inInterpolation = 8        // Inside string interpolation \(...)
    
    /// Returns true if this state spans across line boundaries
    public var isMultiLine: Bool {
        switch self {
        case .inComment, .inDocComment, .inStringMultiline:
            return true
        default:
            return false
        }
    }
}

// MARK: - SyntaxToken

/// A lexical token representing a unit of source code.
/// Immutable value type for thread safety.
public struct SyntaxToken: Equatable, Hashable, Sendable {
    /// The category of this token
    public let type: SyntaxTokenType
    
    /// The source text of the token
    public let text: String
    
    /// Location in the source document
    public let range: SyntaxTextRange
    
    /// Lexer state at the end of this token (for incremental parsing)
    public let endState: SyntaxLexerState
    
    public init(type: SyntaxTokenType, text: String, range: SyntaxTextRange, endState: SyntaxLexerState = .normal) {
        self.type = type
        self.text = text
        self.range = range
        self.endState = endState
    }
    
    /// Convenience check if token spans multiple lines
    public var isMultiLine: Bool {
        range.startLine != range.endLine
    }
}

// MARK: - SyntaxToken Stream

/// A collection of tokens for a document or portion of document.
/// Optimized for line-based access.
public struct SyntaxTokenStream: Sendable {
    /// All tokens in document order
    public private(set) var tokens: [SyntaxToken]
    
    /// Index of first token on each line (for fast line-based lookup)
    private var lineIndex: [Int: Int]
    
    public init(tokens: [SyntaxToken] = []) {
        self.tokens = tokens
        self.lineIndex = [:]
        rebuildLineIndex()
    }
    
    /// Rebuild the line index after tokens change
    private mutating func rebuildLineIndex() {
        lineIndex.removeAll()
        for (index, token) in tokens.enumerated() {
            let line = token.range.startLine
            if lineIndex[line] == nil {
                lineIndex[line] = index
            }
        }
    }
    
    /// Get all tokens that touch a specific line
    public func tokens(forLine line: Int) -> [SyntaxToken] {
        tokens.filter { $0.range.containsLine(line) }
    }
    
    /// Get tokens in a range of lines (inclusive)
    public func tokens(fromLine start: Int, toLine end: Int) -> [SyntaxToken] {
        tokens.filter { token in
            token.range.endLine >= start && token.range.startLine <= end
        }
    }
    
    /// Replace tokens in a line range (for incremental updates)
    public mutating func replaceSyntaxTokens(fromLine start: Int, toLine end: Int, with newSyntaxTokens: [SyntaxToken]) {
        // Remove old tokens in the range
        tokens.removeAll { $0.range.startLine >= start && $0.range.endLine <= end }
        
        // Find insertion point
        let insertIndex = tokens.firstIndex { $0.range.startLine > end } ?? tokens.count
        
        // Insert new tokens
        tokens.insert(contentsOf: newSyntaxTokens, at: insertIndex)
        
        // Rebuild index
        rebuildLineIndex()
    }
}

// MARK: - Styled SyntaxToken

/// A token with its visual styling applied.
/// This is the output that the UI layer consumes.
public struct StyledToken: Sendable {
    public let token: SyntaxToken
    public let style: TokenStyle
    
    public init(token: SyntaxToken, style: TokenStyle) {
        self.token = token
        self.style = style
    }
}

// MARK: - SyntaxToken Style

/// Visual styling for a token type.
public struct TokenStyle: Equatable, Sendable {
    public let foregroundColor: String  // Hex color like "#FF5733"
    public let backgroundColor: String?
    public let isBold: Bool
    public let isItalic: Bool
    public let isUnderline: Bool
    public let fontFamily: String?
    
    public init(
        foregroundColor: String,
        backgroundColor: String? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        fontFamily: String? = nil
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.fontFamily = fontFamily
    }
    
    /// Default style (white text, no special formatting)
    public static let `default` = TokenStyle(foregroundColor: "#FFFFFF")
}
