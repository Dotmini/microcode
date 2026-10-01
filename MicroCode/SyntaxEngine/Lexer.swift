//
//  Lexer.swift
//  MicroCode - Syntax Highlighting Engine
//
//  State machine-based lexer for robust tokenization.
//  This design is more reliable than regex-only approaches because:
//  1. It properly handles context (e.g., keywords inside strings aren't highlighted)
//  2. It tracks state across lines (for multi-line comments/strings)
//  3. It's easier to extend for new languages
//
//  Design Pattern: Strategy Pattern + State Machine
//  - LexerProtocol defines the interface
//  - Each language has its own Lexer implementation
//  - State machine handles context-aware tokenization
//
//  Copyright © 2025 Dotmini Company Limited. All rights reserved.
//

import Foundation

// MARK: - Lexer Protocol

/// Protocol for language-specific lexers.
/// Each language (Python, Swift, Rust, etc.) implements this protocol.
public protocol LexerProtocol: Sendable {
    /// The language identifier (e.g., "python", "swift")
    var languageId: String { get }
    
    /// SyntaxTokenize a single line of code.
    /// - Parameters:
    ///   - line: The source code line to tokenize
    ///   - lineNumber: The 0-indexed line number
    ///   - startState: The lexer state at the beginning of this line
    ///   - startOffset: Character offset from document start
    /// - Returns: Array of tokens and the ending state for next line
    func tokenizeLine(_ line: String, lineNumber: Int, startState: SyntaxLexerState, startOffset: Int) -> (tokens: [SyntaxToken], endState: SyntaxLexerState)
    
    /// SyntaxTokenize an entire document.
    /// - Parameter source: Complete source code
    /// - Returns: SyntaxTokenStream with all tokens
    func tokenize(_ source: String) -> SyntaxTokenStream
}

// MARK: - State Machine Lexer

/// A robust state machine-based lexer.
/// Handles common programming language constructs with proper context tracking.
public class StateMachineLexer: LexerProtocol, @unchecked Sendable {
    public let languageId: String
    
    /// Language-specific keywords mapped to their token types
    private let keywords: [String: SyntaxTokenType]
    
    /// Single-line comment prefix (e.g., "//", "#")
    private let lineCommentPrefix: String?
    private let additionalLineCommentPrefixes: [String]
    
    /// Block comment markers (e.g., ("/*", "*/"))
    private let blockCommentMarkers: (start: String, end: String)?
    
    /// Doc comment prefix (e.g., "///", "/**")
    private let docCommentPrefix: String?
    
    /// String delimiters (e.g., ["\"", "'", "`"])
    private let stringDelimiters: [Character]
    
    /// Multi-line string delimiter (e.g., "\"\"\"" for Python)
    private let multilineStringDelimiter: String?
    
    /// String interpolation start (e.g., "\\(" for Swift, "${" for JS)
    private let interpolationStart: String?
    
    public init(
        languageId: String,
        keywords: [String: SyntaxTokenType],
        lineCommentPrefix: String? = "//",
        additionalLineCommentPrefixes: [String] = [],
        blockCommentMarkers: (String, String)? = ("/*", "*/"),
        docCommentPrefix: String? = "///",
        stringDelimiters: [Character] = ["\"", "'"],
        multilineStringDelimiter: String? = nil,
        interpolationStart: String? = nil
    ) {
        self.languageId = languageId
        self.keywords = keywords
        self.lineCommentPrefix = lineCommentPrefix
        self.additionalLineCommentPrefixes = additionalLineCommentPrefixes
        self.blockCommentMarkers = blockCommentMarkers
        self.docCommentPrefix = docCommentPrefix
        self.stringDelimiters = stringDelimiters
        self.multilineStringDelimiter = multilineStringDelimiter
        self.interpolationStart = interpolationStart
    }
    
    // MARK: - Main SyntaxTokenization
    
    public func tokenize(_ source: String) -> SyntaxTokenStream {
        var allSyntaxTokens: [SyntaxToken] = []
        var currentState: SyntaxLexerState = .normal
        var currentOffset = 0
        
        let lines = source.components(separatedBy: "\n")
        
        for (lineNumber, line) in lines.enumerated() {
            let (tokens, endState) = tokenizeLine(line, lineNumber: lineNumber, startState: currentState, startOffset: currentOffset)
            allSyntaxTokens.append(contentsOf: tokens)
            currentState = endState
            currentOffset += line.utf16.count + 1 // +1 for newline (+1 is safe here as \n is 1 byte/unit)
        }
        
        return SyntaxTokenStream(tokens: allSyntaxTokens)
    }
    
    public func tokenizeLine(_ line: String, lineNumber: Int, startState: SyntaxLexerState, startOffset: Int) -> (tokens: [SyntaxToken], endState: SyntaxLexerState) {
        var tokens: [SyntaxToken] = []
        var state = startState
        var index = line.startIndex
        var column = 0
        var offset = startOffset
        
        while index < line.endIndex {
            let remaining = line[index...] // Substring (no allocation)
            
            // Handle based on current state
            switch state {
            case .normal:
                let (token, newState, consumed) = tokenizeNormal(remaining, line: lineNumber, column: column, offset: offset)
                if let token = token {
                    tokens.append(token)
                }
                state = newState
                let consumedUTF16 = remaining.prefix(consumed).utf16.count
                index = line.index(index, offsetBy: consumed)
                column += consumedUTF16
                offset += consumedUTF16
                
            case .inComment, .inDocComment:
                let (token, newState, consumed) = tokenizeBlockComment(remaining, line: lineNumber, column: column, offset: offset, isDoc: state == .inDocComment)
                if let token = token {
                    tokens.append(token)
                }
                state = newState
                let consumedUTF16 = remaining.prefix(consumed).utf16.count
                index = line.index(index, offsetBy: consumed)
                column += consumedUTF16
                offset += consumedUTF16
                
            case .inString, .inStringSingle, .inStringTemplate:
                let delimiter: Character = state == .inString ? "\"" : (state == .inStringSingle ? "'" : "`")
                let (token, newState, consumed) = tokenizeString(remaining, line: lineNumber, column: column, offset: offset, delimiter: delimiter)
                if let token = token {
                    tokens.append(token)
                }
                state = newState
                let consumedUTF16 = remaining.prefix(consumed).utf16.count
                index = line.index(index, offsetBy: consumed)
                column += consumedUTF16
                offset += consumedUTF16
                
            case .inStringMultiline:
                let (token, newState, consumed) = tokenizeMultilineString(remaining, line: lineNumber, column: column, offset: offset)
                if let token = token {
                    tokens.append(token)
                }
                state = newState
                let consumedUTF16 = remaining.prefix(consumed).utf16.count
                index = line.index(index, offsetBy: consumed)
                column += consumedUTF16
                offset += consumedUTF16
                
            default:
                // Handle other states - fallback to normal
                let (token, newState, consumed) = tokenizeNormal(remaining, line: lineNumber, column: column, offset: offset)
                if let token = token {
                    tokens.append(token)
                }
                state = newState
                let consumedUTF16 = remaining.prefix(consumed).utf16.count
                index = line.index(index, offsetBy: consumed)
                column += consumedUTF16
                offset += consumedUTF16
            }
        }
        
        return (tokens, state)
    }
    
    // MARK: - State-Specific SyntaxTokenizers
    
    /// SyntaxTokenize in normal state (not inside string or comment)
    private func tokenizeNormal(_ text: Substring, line: Int, column: Int, offset: Int) -> (SyntaxToken?, SyntaxLexerState, Int) {
        guard !text.isEmpty else { return (nil, .normal, 0) }
        
        guard let first = text.first else { return (nil, .normal, 0) }
        
        // Whitespace
        if first.isWhitespace {
            let count = text.prefix(while: { $0.isWhitespace && $0 != "\n" }).count
            return (nil, .normal, count) // Skip whitespace, don't create token
        }
        
        // Doc comment check (before regular comment)
        if let docPrefix = docCommentPrefix, text.hasPrefix(docPrefix) {
            let comment = String(text.prefix(while: { $0 != "\n" }))
            let range = SyntaxTextRange(line: line, column: column, length: comment.utf16.count, offset: offset)
            let token = SyntaxToken(type: .commentDoc, text: comment, range: range, endState: .normal)
            return (token, .normal, comment.count)
        }
        
        // Single-line comment
        let allLinePrefixes = ([lineCommentPrefix].compactMap { $0 } + additionalLineCommentPrefixes)
        for prefix in allLinePrefixes {
            if text.hasPrefix(prefix) {
                let comment = String(text.prefix(while: { $0 != "\n" }))
                let range = SyntaxTextRange(line: line, column: column, length: comment.utf16.count, offset: offset)
                let token = SyntaxToken(type: .comment, text: comment, range: range, endState: .normal)
                return (token, .normal, comment.count)
            }
        }
        
        // Block comment start
        if let markers = blockCommentMarkers, text.hasPrefix(markers.start) {
            if let endRange = text.range(of: markers.end, range: text.index(text.startIndex, offsetBy: markers.start.count)..<text.endIndex) {
                // Complete block comment on this line
                let endIndex = text.index(endRange.upperBound, offsetBy: 0)
                let comment = String(text[..<endIndex])
                let range = SyntaxTextRange(line: line, column: column, length: comment.utf16.count, offset: offset)
                let token = SyntaxToken(type: .commentBlock, text: comment, range: range, endState: .normal)
                return (token, .normal, comment.count)
            } else {
                // Block comment continues to next line
                let comment = text
                let range = SyntaxTextRange(line: line, column: column, length: comment.utf16.count, offset: offset)
                let token = SyntaxToken(type: .commentBlock, text: String(comment), range: range, endState: .inComment)
                return (token, .inComment, comment.count)
            }
        }
        
        // String literals
        for delimiter in stringDelimiters {
            if first == delimiter {
                // Check for multi-line string
                if let multiDelim = multilineStringDelimiter, text.hasPrefix(multiDelim) {
                    return tokenizeMultilineStringStart(text, line: line, column: column, offset: offset)
                }
                
                // Regular string
                let (stringSyntaxToken, endState, consumed) = tokenizeString(text, line: line, column: column, offset: offset, delimiter: delimiter, isStart: true)
                return (stringSyntaxToken, endState, consumed)
            }
        }
        
        // Numbers
        if first.isNumber || (first == "." && text.dropFirst().first?.isNumber == true) {
            return tokenizeNumber(text, line: line, column: column, offset: offset)
        }
        
        // Identifiers and keywords
        if first.isLetter || first == "_" || first == "@" || first == "#" {
            return tokenizeIdentifier(text, line: line, column: column, offset: offset)
        }
        
        // Operators and punctuation
        return tokenizeOperator(text, line: line, column: column, offset: offset)
    }
    
    /// SyntaxTokenize a string literal
    private func tokenizeString(_ text: Substring, line: Int, column: Int, offset: Int, delimiter: Character, isStart: Bool = false) -> (SyntaxToken?, SyntaxLexerState, Int) {
        var index = text.startIndex
        
        // Skip opening delimiter if this is the start
        if isStart && !text.isEmpty && text.first == delimiter {
            index = text.index(after: index)
        }
        
        var content = isStart ? String(delimiter) : ""
        
        while index < text.endIndex {
            let char = text[index]
            
            if char == "\\" && text.index(after: index) < text.endIndex {
                // Escape sequence
                content.append(char)
                index = text.index(after: index)
                content.append(text[index])
                index = text.index(after: index)
            } else if char == delimiter {
                // End of string
                content.append(char)
                let range = SyntaxTextRange(line: line, column: column, length: content.utf16.count, offset: offset)
                let token = SyntaxToken(type: .string, text: content, range: range, endState: .normal)
                return (token, .normal, content.count)
            } else {
                content.append(char)
                index = text.index(after: index)
            }
        }
        
        // String continues to next line (unterminated on this line)
        let range = SyntaxTextRange(line: line, column: column, length: content.utf16.count, offset: offset)
        let endState: SyntaxLexerState = delimiter == "\"" ? .inString : (delimiter == "'" ? .inStringSingle : .inStringTemplate)
        let token = SyntaxToken(type: .string, text: content, range: range, endState: endState)
        return (token, endState, content.count)
    }
    
    /// SyntaxTokenize block comment
    private func tokenizeBlockComment(_ text: Substring, line: Int, column: Int, offset: Int, isDoc: Bool) -> (SyntaxToken?, SyntaxLexerState, Int) {
        guard let markers = blockCommentMarkers else {
            return (nil, .normal, text.count)
        }
        
        if let endRange = text.range(of: markers.end) {
            let endIndex = text.index(endRange.upperBound, offsetBy: 0)
            let comment = String(text[..<endIndex])
            let range = SyntaxTextRange(line: line, column: column, length: comment.utf16.count, offset: offset)
            let token = SyntaxToken(type: isDoc ? .commentDoc : .commentBlock, text: comment, range: range, endState: .normal)
            return (token, .normal, comment.count)
        } else {
            // Comment continues
            let range = SyntaxTextRange(line: line, column: column, length: text.utf16.count, offset: offset)
            let token = SyntaxToken(type: isDoc ? .commentDoc : .commentBlock, text: String(text), range: range, endState: isDoc ? .inDocComment : .inComment)
            return (token, isDoc ? .inDocComment : .inComment, text.count)
        }
    }
    
    /// SyntaxTokenize multi-line string start
    private func tokenizeMultilineStringStart(_ text: Substring, line: Int, column: Int, offset: Int) -> (SyntaxToken?, SyntaxLexerState, Int) {
        guard let multiDelim = multilineStringDelimiter else {
            return (nil, .normal, 0)
        }
        
        // Check if string ends on this line
        let afterDelim = String(text.dropFirst(multiDelim.count))
        if let endRange = afterDelim.range(of: multiDelim) {
            let totalLength = multiDelim.count + afterDelim.distance(from: afterDelim.startIndex, to: endRange.upperBound)
            let content = String(text.prefix(totalLength))
            let range = SyntaxTextRange(line: line, column: column, length: content.utf16.count, offset: offset)
            let token = SyntaxToken(type: .string, text: content, range: range, endState: .normal)
            return (token, .normal, content.count)
        } else {
            // Continues to next line
            let range = SyntaxTextRange(line: line, column: column, length: text.utf16.count, offset: offset)
            let token = SyntaxToken(type: .string, text: String(text), range: range, endState: .inStringMultiline)
            return (token, .inStringMultiline, text.count)
        }
    }
    
    /// SyntaxTokenize inside multi-line string
    private func tokenizeMultilineString(_ text: Substring, line: Int, column: Int, offset: Int) -> (SyntaxToken?, SyntaxLexerState, Int) {
        guard let multiDelim = multilineStringDelimiter else {
            return (nil, .normal, 0)
        }
        
        if let endRange = text.range(of: multiDelim) {
            let endIndex = text.index(endRange.upperBound, offsetBy: 0)
            let content = String(text[..<endIndex])
            let range = SyntaxTextRange(line: line, column: column, length: content.utf16.count, offset: offset)
            let token = SyntaxToken(type: .string, text: content, range: range, endState: .normal)
            return (token, .normal, content.count)
        } else {
            let range = SyntaxTextRange(line: line, column: column, length: text.utf16.count, offset: offset)
            let token = SyntaxToken(type: .string, text: String(text), range: range, endState: .inStringMultiline)
            return (token, .inStringMultiline, text.count)
        }
    }
    
    /// SyntaxTokenize a number literal
    private func tokenizeNumber(_ text: Substring, line: Int, column: Int, offset: Int) -> (SyntaxToken?, SyntaxLexerState, Int) {
        var index = text.startIndex
        var isFloat = false
        var isHex = false
        
        // Check for hex
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            isHex = true
            index = text.index(index, offsetBy: 2)
        }
        
        while index < text.endIndex {
            let char = text[index]
            
            if isHex {
                if char.isHexDigit {
                    index = text.index(after: index)
                } else {
                    break
                }
            } else if char.isNumber {
                index = text.index(after: index)
            } else if char == "." && !isFloat {
                let nextIdx = text.index(after: index)
                if nextIdx < text.endIndex && text[nextIdx].isNumber {
                    isFloat = true
                    index = text.index(after: index)
                } else {
                    break
                }
            } else if (char == "e" || char == "E") && !isHex {
                index = text.index(after: index)
                if index < text.endIndex && (text[index] == "+" || text[index] == "-") {
                    index = text.index(after: index)
                }
            } else if char == "_" {
                // Numeric separator
                index = text.index(after: index)
            } else {
                break
            }
        }
        
        let numberText = String(text[text.startIndex..<index])
        let range = SyntaxTextRange(line: line, column: column, length: numberText.utf16.count, offset: offset)
        let token = SyntaxToken(type: .number, text: numberText, range: range, endState: .normal)
        return (token, .normal, numberText.count)
    }
    
    /// SyntaxTokenize an identifier or keyword
    private func tokenizeIdentifier(_ text: Substring, line: Int, column: Int, offset: Int) -> (SyntaxToken?, SyntaxLexerState, Int) {
        var index = text.startIndex
        guard let first = text.first else { return (nil, .normal, 0) }
        
        // Handle @ and # prefixed identifiers (decorators, preprocessor)
        var isDecorator = false
        var isPreprocessor = false
        
        if first == "@" {
            isDecorator = true
            index = text.index(after: index)
        } else if first == "#" {
            isPreprocessor = true
            index = text.index(after: index)
        }
        
        // Consume identifier characters
        while index < text.endIndex {
            let char = text[index]
            if char.isLetter || char.isNumber || char == "_" {
                index = text.index(after: index)
            } else {
                break
            }
        }
        
        let identText = String(text[text.startIndex..<index])
        let range = SyntaxTextRange(line: line, column: column, length: identText.utf16.count, offset: offset)
        
        // Determine token type
        let tokenType: SyntaxTokenType
        if isDecorator {
            tokenType = .annotation
        } else if isPreprocessor {
            tokenType = .preprocessor
        } else if let kwType = keywords[identText] ?? keywords[identText.lowercased()] {
            tokenType = kwType
        } else if identText == "true" || identText == "false" || identText == "TRUE" || identText == "FALSE" {
            tokenType = .boolean
        } else if identText == "nil" || identText == "null" || identText == "None" || identText == "NULL" {
            tokenType = .null
        } else if identText.first?.isUppercase == true {
            tokenType = .type
        } else {
            tokenType = .identifier
        }
        
        let token = SyntaxToken(type: tokenType, text: identText, range: range, endState: .normal)
        return (token, .normal, identText.count)
    }
    
    /// SyntaxTokenize an operator or punctuation
    private func tokenizeOperator(_ text: Substring, line: Int, column: Int, offset: Int) -> (SyntaxToken?, SyntaxLexerState, Int) {
        guard let first = text.first else { return (nil, .normal, 0) }
        
        // Multi-character operators (check longest first)
        let multiOps = ["===", "!==", "...", "..<", "->", "=>", "<=", ">=", "==", "!=", "&&", "||", "<<", ">>", "+=", "-=", "*=", "/=", "??", "++", "--"]
        for op in multiOps {
            if text.hasPrefix(op) {
                let range = SyntaxTextRange(line: line, column: column, length: op.utf16.count, offset: offset)
                let token = SyntaxToken(type: .operator, text: op, range: range, endState: .normal)
                return (token, .normal, op.count)
            }
        }
        
        // Single-character operators
        let operators: Set<Character> = ["+", "-", "*", "/", "%", "=", "<", ">", "!", "&", "|", "^", "~", "?"]
        let punctuation: Set<Character> = ["(", ")", "[", "]", "{", "}", ",", ";", ":"]
        let delimiters: Set<Character> = ["."]
        
        let tokenType: SyntaxTokenType
        if operators.contains(first) {
            tokenType = .operator
        } else if punctuation.contains(first) {
            tokenType = .punctuation
        } else if delimiters.contains(first) {
            tokenType = .delimiter
        } else {
            tokenType = .unknown
        }
        
        let range = SyntaxTextRange(line: line, column: column, length: String(first).utf16.count, offset: offset)
        let token = SyntaxToken(type: tokenType, text: String(first), range: range, endState: .normal)
        return (token, .normal, 1)
    }
}

// MARK: - Language-Specific Lexers

/// Creates a pre-configured lexer for Swift
public func createSwiftLexer() -> StateMachineLexer {
    let swiftKeywords: [String: SyntaxTokenType] = [
        // Declarations
        "class": .keywordDeclaration, "struct": .keywordDeclaration, "enum": .keywordDeclaration,
        "protocol": .keywordDeclaration, "extension": .keywordDeclaration, "func": .keywordDeclaration,
        "var": .keywordDeclaration, "let": .keywordDeclaration, "typealias": .keywordDeclaration,
        "init": .keywordDeclaration, "deinit": .keywordDeclaration, "subscript": .keywordDeclaration,
        "actor": .keywordDeclaration, "associatedtype": .keywordDeclaration,
        
        // Modifiers
        "public": .keywordModifier, "private": .keywordModifier, "fileprivate": .keywordModifier,
        "internal": .keywordModifier, "open": .keywordModifier, "static": .keywordModifier,
        "override": .keywordModifier, "final": .keywordModifier, "mutating": .keywordModifier,
        "lazy": .keywordModifier, "weak": .keywordModifier, "unowned": .keywordModifier,
        "async": .keywordModifier, "await": .keywordModifier, "nonisolated": .keywordModifier,
        
        // Property Wrappers & Annotations
        "@State": .annotation, "@Binding": .annotation, "@Environment": .annotation,
        "@EnvironmentObject": .annotation, "@ObservedObject": .annotation, "@StateObject": .annotation,
        "@Published": .annotation, "@MainActor": .annotation, "@ViewBuilder": .annotation,
        "@discardableResult": .annotation, "@objc": .annotation, "@available": .annotation,
        "@frozen": .annotation, "@inlinable": .annotation, "@AppStorage": .annotation,
        "@SceneStorage": .annotation, "@FocusState": .annotation,
        
        // Control flow
        "if": .keyword, "else": .keyword, "switch": .keyword, "case": .keyword,
        "default": .keyword, "for": .keyword, "while": .keyword, "repeat": .keyword,
        "do": .keyword, "guard": .keyword, "where": .keyword, "in": .keywordOperator,
        "return": .keywordControl, "break": .keywordControl, "continue": .keywordControl,
        "fallthrough": .keywordControl, "throw": .keywordControl,
        
        // Error handling
        "try": .keyword, "catch": .keyword, "throws": .keyword, "rethrows": .keyword,
        
        // Literals & Constants
        "true": .boolean, "false": .boolean, "nil": .null,
        
        // Core Swift & SwiftUI Types
        "String": .type, "Int": .type, "Double": .type, "Float": .type, "Bool": .type,
        "Character": .type, "Substring": .type, "Data": .type, "Date": .type, "URL": .type,
        "UUID": .type, "Array": .type, "Dictionary": .type, "Set": .type, "Optional": .type,
        "Result": .type, "Error": .type, "Task": .type, "MainActor": .type,
        "Identifiable": .type, "Hashable": .type, "Equatable": .type, "Comparable": .type,
        "Codable": .type, "Sendable": .type, "CaseIterable": .type,
        
        // SwiftUI Components & Primitives
        "View": .type, "App": .type, "Scene": .type, "WindowGroup": .type,
        "VStack": .type, "HStack": .type, "ZStack": .type, "LazyVStack": .type, "LazyHStack": .type,
        "LazyVGrid": .type, "LazyHGrid": .type, "Grid": .type, "GridRow": .type,
        "Text": .type, "Button": .type, "Image": .type, "Label": .type,
        "TextField": .type, "SecureField": .type, "TextEditor": .type,
        "Toggle": .type, "Picker": .type, "Slider": .type, "Stepper": .type, "ProgressView": .type,
        "Spacer": .type, "Divider": .type, "List": .type, "Section": .type, "ForEach": .type,
        "ScrollView": .type, "NavigationStack": .type, "NavigationView": .type, "NavigationLink": .type,
        "Color": .type, "Font": .type, "Shape": .type, "Capsule": .type, "Circle": .type,
        "Rectangle": .type, "RoundedRectangle": .type, "Ellipse": .type,
        
        // Other
        "import": .keyword, "self": .keyword, "Self": .keyword, "super": .keyword,
        "Any": .type, "some": .keyword, "any": .keyword, "is": .keywordOperator, "as": .keywordOperator,
    ]
    
    return StateMachineLexer(
        languageId: "swift",
        keywords: swiftKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: "///",
        stringDelimiters: ["\""],
        multilineStringDelimiter: "\"\"\"",
        interpolationStart: "\\("
    )
}

/// Creates a pre-configured lexer for Python
public func createPythonLexer() -> StateMachineLexer {
    let pythonKeywords: [String: SyntaxTokenType] = [
        // Definitions
        "def": .keywordDeclaration, "class": .keywordDeclaration, "lambda": .keywordDeclaration,
        
        // Control flow
        "if": .keyword, "elif": .keyword, "else": .keyword, "for": .keyword,
        "while": .keyword, "try": .keyword, "except": .keyword, "finally": .keyword,
        "with": .keyword, "match": .keyword, "case": .keyword,  // Python 3.10+
        "return": .keywordControl, "break": .keywordControl, "continue": .keywordControl,
        "pass": .keywordControl, "raise": .keywordControl, "yield": .keywordControl,
        
        // Operators
        "and": .keywordOperator, "or": .keywordOperator, "not": .keywordOperator,
        "in": .keywordOperator, "is": .keywordOperator,
        
        // Imports
        "import": .keyword, "from": .keyword, "as": .keyword,
        
        // Variables
        "global": .keyword, "nonlocal": .keyword,
        
        // Async
        "async": .keywordModifier, "await": .keywordModifier,
        
        // Other
        "assert": .keyword, "del": .keyword,
        
        // Built-in Constants
        "True": .number, "False": .number, "None": .number,
        
        // Type Hints (Python 3.5+)
        "int": .type, "str": .type, "float": .type, "bool": .type, "list": .type,
        "dict": .type, "tuple": .type, "set": .type, "bytes": .type, "type": .type,
        "Any": .type, "Optional": .type, "Union": .type, "List": .type, "Dict": .type,
        "Tuple": .type, "Set": .type, "Callable": .type, "Awaitable": .type,
        
        // Built-in Functions (common)
        // NOTE: int/str/float/bool/list/dict/tuple/set/type are intentionally
        // NOT repeated here — they are already mapped to .type above. A Swift
        // dictionary *literal* with duplicate keys is a fatal runtime trap
        // (`Dictionary literal contains duplicate keys` → brk #1 / SIGTRAP),
        // which is exactly what crashed Python files in Cell/Playground.
        "print": .function, "len": .function, "range": .function, "open": .function,
        "input": .function,
        "isinstance": .function, "issubclass": .function, "hasattr": .function,
        "getattr": .function, "setattr": .function, "delattr": .function,
        "super": .function, "property": .function, "staticmethod": .function,
        "classmethod": .function, "enumerate": .function, "zip": .function,
        "map": .function, "filter": .function, "sorted": .function, "reversed": .function,
    ]
    
    return StateMachineLexer(
        languageId: "python",
        keywords: pythonKeywords,
        lineCommentPrefix: "#",
        blockCommentMarkers: nil,  // Python uses """ for multiline, not /* */
        docCommentPrefix: nil,
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: "\"\"\"",
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for Rust
public func createRustLexer() -> StateMachineLexer {
    let rustKeywords: [String: SyntaxTokenType] = [
        // Declarations
        "fn": .keywordDeclaration, "struct": .keywordDeclaration, "enum": .keywordDeclaration,
        "trait": .keywordDeclaration, "impl": .keywordDeclaration, "type": .keywordDeclaration,
        "let": .keywordDeclaration, "const": .keywordDeclaration, "static": .keywordDeclaration,
        "mod": .keywordDeclaration, "use": .keywordDeclaration, "macro_rules": .keywordDeclaration,
        
        // Modifiers
        "pub": .keywordModifier, "mut": .keywordModifier, "ref": .keywordModifier,
        "async": .keywordModifier, "await": .keywordModifier, "unsafe": .keywordModifier,
        "extern": .keywordModifier, "dyn": .keywordModifier, "box": .keywordModifier,
        
        // Control flow
        "if": .keyword, "else": .keyword, "match": .keyword,
        "for": .keyword, "while": .keyword, "loop": .keyword,
        "return": .keywordControl, "break": .keywordControl, "continue": .keywordControl,
        
        // Primitive Types
        "i8": .type, "i16": .type, "i32": .type, "i64": .type, "i128": .type, "isize": .type,
        "u8": .type, "u16": .type, "u32": .type, "u64": .type, "u128": .type, "usize": .type,
        "f32": .type, "f64": .type, "bool": .type, "char": .type, "str": .type,
        
        // Common Types
        "String": .type, "Vec": .type, "Option": .type, "Result": .type, "Box": .type,
        "Rc": .type, "Arc": .type, "Cell": .type, "RefCell": .type, "Mutex": .type,
        "HashMap": .type, "HashSet": .type, "BTreeMap": .type, "BTreeSet": .type,
        "Some": .type, "None": .type, "Ok": .type, "Err": .type,
        
        // Other Keywords
        "self": .keyword, "Self": .type, "super": .keyword, "crate": .keyword,
        "where": .keyword, "as": .keywordOperator, "in": .keywordOperator,
        "move": .keyword, "true": .number, "false": .number,
        
        // Common Macros (highlighted as functions)
        "println": .function, "print": .function, "format": .function,
        "vec": .function, "panic": .function, "assert": .function,
        "assert_eq": .function, "assert_ne": .function, "debug_assert": .function,
        "todo": .function, "unimplemented": .function, "unreachable": .function,
        "cfg": .function, "derive": .function, "include": .function,
    ]
    
    return StateMachineLexer(
        languageId: "rust",
        keywords: rustKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: "///",
        stringDelimiters: ["\""],
        multilineStringDelimiter: nil,
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for Ardium
public func createArdiumLexer() -> StateMachineLexer {
    let ardiumKeywords: [String: SyntaxTokenType] = [
        // Declarations
        "fn": .keywordDeclaration, "var": .keywordDeclaration, "let": .keywordDeclaration,
        "mut": .keywordModifier, "struct": .keywordDeclaration, "class": .keywordDeclaration,
        "enum": .keywordDeclaration, "import": .keywordDeclaration, "extern": .keywordDeclaration,
        "async": .keywordModifier, "await": .keywordModifier,
        "export": .keywordDeclaration, "test": .keywordDeclaration, "interrupt": .keywordDeclaration,
        
        // Memory & RAII keywords
        "@owned": .keywordModifier, "@State": .keywordModifier, "@External": .keywordModifier,
        "@export": .keywordModifier, "@test": .keywordModifier,
        "alloc": .function, "free": .function, "peek": .function, "poke": .function,
        
        // Control flow
        "if": .keyword, "else": .keyword, "elif": .keyword,
        "loop": .keyword, "while": .keyword, "for": .keyword,
        "return": .keywordControl, "break": .keywordControl, "continue": .keywordControl,
        "match": .keyword,
        
        // Constants & Special
        "true": .number, "false": .number, "nil": .number, "null": .number,
        "GLOBAL": .keyword, "RESET": .keyword, "ERR": .keyword,
        
        // Primitive & Pointer Types
        "int": .type, "i8": .type, "i16": .type, "i32": .type, "i64": .type,
        "u8": .type, "u16": .type, "u32": .type, "u64": .type,
        "float": .type, "f32": .type, "f64": .type,
        "string": .type, "bool": .type, "void": .type,
        "i8_ptr": .type, "i32_ptr": .type, "i64_ptr": .type, "ptr": .type,
        
        // Composite & stdlib types
        "Vector2": .type, "Array": .type, "Map": .type, "Any": .type,
        
        // Builtins & CoreUI Framework
        "print": .function, "println": .function, "printf": .function,
        "VStack": .function, "HStack": .function, "ZStack": .function,
        "Text": .function, "Title": .function, "Headline": .function,
        "Button": .function, "TextField": .function, "Image": .function, "Spacer": .function,
        "Live": .function, "DebugUI": .function,
        "init": .function, "createWindow": .function, "run": .function
    ]
    
    return StateMachineLexer(
        languageId: "ardium",
        keywords: ardiumKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: "///",
        stringDelimiters: ["\""],
        multilineStringDelimiter: "\"\"\"",
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for JavaScript/TypeScript
public func createJavaScriptLexer() -> StateMachineLexer {
    let jsKeywords: [String: SyntaxTokenType] = [
        // Declarations
        "function": .keywordDeclaration, "class": .keywordDeclaration,
        "var": .keywordDeclaration, "let": .keywordDeclaration, "const": .keywordDeclaration,
        
        // Control flow
        "if": .keyword, "else": .keyword, "switch": .keyword, "case": .keyword,
        "default": .keyword, "for": .keyword, "while": .keyword, "do": .keyword,
        "return": .keywordControl, "break": .keywordControl, "continue": .keywordControl,
        "throw": .keywordControl,
        
        // Error handling
        "try": .keyword, "catch": .keyword, "finally": .keyword,
        
        // Other
        "import": .keyword, "export": .keyword, "from": .keyword,
        "this": .keyword, "super": .keyword, "new": .keyword, "delete": .keyword,
        "typeof": .keywordOperator, "instanceof": .keywordOperator, "in": .keywordOperator,
        "async": .keywordModifier, "await": .keywordModifier,
        "extends": .keyword, "implements": .keyword,
        "interface": .keywordDeclaration, "type": .keywordDeclaration,  // TypeScript
        "readonly": .keywordModifier, "private": .keywordModifier, "public": .keywordModifier,  // TypeScript
    ]
    
    return StateMachineLexer(
        languageId: "javascript",
        keywords: jsKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: "/**",
        stringDelimiters: ["\"", "'", "`"],  // Template literals with backtick
        multilineStringDelimiter: nil,
        interpolationStart: "${"
    )
}

/// Creates a pre-configured lexer for TypeScript
public func createTypeScriptLexer() -> StateMachineLexer {
    let tsKeywords: [String: SyntaxTokenType] = [
        // Declarations (TypeScript specific)
        "interface": .keywordDeclaration, "type": .keywordDeclaration, "enum": .keywordDeclaration,
        "namespace": .keywordDeclaration, "module": .keywordDeclaration, "declare": .keywordDeclaration,
        "abstract": .keywordDeclaration, "function": .keywordDeclaration, "class": .keywordDeclaration,
        "var": .keywordDeclaration, "let": .keywordDeclaration, "const": .keywordDeclaration,
        
        // Modifiers
        "public": .keywordModifier, "private": .keywordModifier, "protected": .keywordModifier,
        "readonly": .keywordModifier, "static": .keywordModifier, "override": .keywordModifier,
        "async": .keywordModifier, "await": .keywordModifier,
        
        // Control flow
        "if": .keyword, "else": .keyword, "switch": .keyword, "case": .keyword,
        "default": .keyword, "for": .keyword, "while": .keyword, "do": .keyword,
        "return": .keywordControl, "break": .keywordControl, "continue": .keywordControl,
        "throw": .keywordControl, "yield": .keywordControl,
        
        // Error handling
        "try": .keyword, "catch": .keyword, "finally": .keyword,
        
        // Imports/Exports
        "import": .keyword, "export": .keyword, "from": .keyword, "as": .keyword,
        
        // TypeScript Types
        "string": .type, "number": .type, "boolean": .type, "void": .type,
        "null": .type, "undefined": .type, "never": .type, "unknown": .type,
        "any": .type, "object": .type, "symbol": .type, "bigint": .type,
        "Array": .type, "Record": .type, "Partial": .type, "Required": .type,
        "Pick": .type, "Omit": .type, "Exclude": .type, "Extract": .type,
        "Promise": .type, "Map": .type, "Set": .type, "WeakMap": .type, "WeakSet": .type,
        
        // Type Keywords
        "keyof": .keywordOperator, "typeof": .keywordOperator, "instanceof": .keywordOperator,
        "in": .keywordOperator, "is": .keywordOperator, "infer": .keyword,
        "extends": .keyword, "implements": .keyword, "satisfies": .keyword,
        
        // Other
        "this": .keyword, "super": .keyword, "new": .keyword, "delete": .keyword,
        "true": .number, "false": .number,
        
        // Common globals
        // NOTE: "module" is intentionally omitted here — it is already mapped
        // to .keywordDeclaration above. Duplicate keys in a Swift dictionary
        // literal are a fatal runtime trap (brk #1 / SIGTRAP).
        "console": .type, "document": .type, "window": .type, "process": .type,
        "require": .function, "exports": .type,
    ]
    
    return StateMachineLexer(
        languageId: "typescript",
        keywords: tsKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: "/**",
        stringDelimiters: ["\"", "'", "`"],
        multilineStringDelimiter: nil,
        interpolationStart: "${"
    )
}

/// Creates a pre-configured lexer for Ruby
public func createRubyLexer() -> StateMachineLexer {
    let rubyKeywords: [String: SyntaxTokenType] = [
        // Definitions
        "def": .keywordDeclaration, "class": .keywordDeclaration, "module": .keywordDeclaration,
        "attr_reader": .keywordDeclaration, "attr_writer": .keywordDeclaration, "attr_accessor": .keywordDeclaration,
        
        // Control flow
        "if": .keyword, "elsif": .keyword, "else": .keyword, "unless": .keyword,
        "case": .keyword, "when": .keyword, "for": .keyword, "while": .keyword,
        "until": .keyword, "do": .keyword, "begin": .keyword, "rescue": .keyword,
        "ensure": .keyword, "end": .keyword, "then": .keyword,
        "return": .keywordControl, "break": .keywordControl, "next": .keywordControl,
        "redo": .keywordControl, "retry": .keywordControl, "raise": .keywordControl,
        
        // Operators
        "and": .keywordOperator, "or": .keywordOperator, "not": .keywordOperator,
        "in": .keywordOperator,
        
        // Other
        "require": .keyword, "include": .keyword, "extend": .keyword,
        "self": .keyword, "super": .keyword, "yield": .keyword,
        "alias": .keyword, "defined?": .keyword,
        "private": .keywordModifier, "protected": .keywordModifier, "public": .keywordModifier,
    ]
    
    return StateMachineLexer(
        languageId: "ruby",
        keywords: rubyKeywords,
        lineCommentPrefix: "#",
        blockCommentMarkers: ("=begin", "=end"),
        docCommentPrefix: nil,
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: nil,
        interpolationStart: "#{"
    )
}

/// Creates a pre-configured lexer for Go
public func createGoLexer() -> StateMachineLexer {
    let goKeywords: [String: SyntaxTokenType] = [
        // Declarations
        "func": .keywordDeclaration, "var": .keywordDeclaration, "const": .keywordDeclaration,
        "type": .keywordDeclaration, "struct": .keywordDeclaration, "interface": .keywordDeclaration,
        "package": .keywordDeclaration, "import": .keyword,
        
        // Control flow
        "if": .keyword, "else": .keyword, "switch": .keyword, "case": .keyword,
        "default": .keyword, "for": .keyword, "range": .keyword, "select": .keyword,
        "return": .keywordControl, "break": .keywordControl, "continue": .keywordControl,
        "goto": .keywordControl, "fallthrough": .keywordControl,
        
        // Concurrency
        "go": .keywordModifier, "chan": .keywordModifier, "defer": .keywordModifier,
        
        // Other
        "map": .keyword, "make": .keyword, "new": .keyword, "len": .keyword,
        "cap": .keyword, "append": .keyword, "copy": .keyword, "delete": .keyword,
    ]
    
    return StateMachineLexer(
        languageId: "go",
        keywords: goKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: nil,
        stringDelimiters: ["\"", "'", "`"],  // Backtick for raw strings
        multilineStringDelimiter: nil,
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for C/C++
public func createCLexer() -> StateMachineLexer {
    let cKeywords: [String: SyntaxTokenType] = [
        // Primitive Types
        "int": .type, "char": .type, "float": .type, "double": .type,
        "void": .type, "long": .type, "short": .type, "unsigned": .type,
        "signed": .type, "bool": .type, "size_t": .type, "wchar_t": .type,
        "int8_t": .type, "int16_t": .type, "int32_t": .type, "int64_t": .type,
        "uint8_t": .type, "uint16_t": .type, "uint32_t": .type, "uint64_t": .type,
        
        // STL Types
        "string": .type, "vector": .type, "map": .type, "set": .type,
        "unordered_map": .type, "unordered_set": .type, "array": .type,
        "list": .type, "deque": .type, "queue": .type, "stack": .type,
        "pair": .type, "tuple": .type, "optional": .type, "variant": .type,
        "any": .type, "span": .type, "string_view": .type,
        "shared_ptr": .type, "unique_ptr": .type, "weak_ptr": .type,
        "function": .type, "thread": .type, "mutex": .type, "atomic": .type,
        
        // Declarations
        "struct": .keywordDeclaration, "union": .keywordDeclaration, "enum": .keywordDeclaration,
        "typedef": .keywordDeclaration, "class": .keywordDeclaration, "namespace": .keywordDeclaration,
        "template": .keywordDeclaration, "typename": .keywordDeclaration, "concept": .keywordDeclaration,
        
        // Modifiers
        "static": .keywordModifier, "extern": .keywordModifier, "const": .keywordModifier,
        "volatile": .keywordModifier, "inline": .keywordModifier, "virtual": .keywordModifier,
        "explicit": .keywordModifier, "mutable": .keywordModifier, "friend": .keywordModifier,
        "public": .keywordModifier, "private": .keywordModifier, "protected": .keywordModifier,
        "constexpr": .keywordModifier, "consteval": .keywordModifier, "constinit": .keywordModifier,
        "noexcept": .keywordModifier, "override": .keywordModifier, "final": .keywordModifier,
        "thread_local": .keywordModifier,
        
        // Control flow
        "if": .keyword, "else": .keyword, "switch": .keyword, "case": .keyword,
        "default": .keyword, "for": .keyword, "while": .keyword, "do": .keyword,
        "return": .keywordControl, "break": .keywordControl, "continue": .keywordControl,
        "goto": .keywordControl,
        
        // C++11+ Keywords
        "auto": .keyword, "decltype": .keyword, "nullptr": .number,
        "static_assert": .keyword, "alignas": .keyword, "alignof": .keyword,
        "requires": .keyword, "co_await": .keyword, "co_return": .keyword, "co_yield": .keyword,
        
        // Other
        "sizeof": .keyword, "new": .keyword, "delete": .keyword, "this": .keyword,
        "using": .keyword, "try": .keyword, "catch": .keyword, "throw": .keyword,
        "register": .keyword, "typeid": .keyword, "dynamic_cast": .keyword,
        "static_cast": .keyword, "reinterpret_cast": .keyword, "const_cast": .keyword,
        
        // Preprocessor (highlighted as keywords)
        "include": .keyword, "define": .keyword, "ifdef": .keyword, "ifndef": .keyword,
        "endif": .keyword, "pragma": .keyword,
        
        // Boolean
        "true": .number, "false": .number,
    ]
    
    return StateMachineLexer(
        languageId: "c",
        keywords: cKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: "/**",
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: nil,
        interpolationStart: nil
    )
}

// MARK: - Java & Kotlin Support

/// Creates a pre-configured lexer for Java
public func createJavaLexer() -> StateMachineLexer {
    let javaKeywords: [String: SyntaxTokenType] = [
        // Declarations
        "class": .keywordDeclaration, "interface": .keywordDeclaration, "enum": .keywordDeclaration,
        "abstract": .keywordDeclaration, "final": .keywordDeclaration, "static": .keywordDeclaration,
        "public": .keywordModifier, "private": .keywordModifier, "protected": .keywordModifier,
        "void": .type, "boolean": .type, "int": .type, "long": .type, "float": .type, "double": .type,
        "byte": .type, "short": .type, "char": .type,
        
        // Control flow
        "if": .keyword, "else": .keyword, "switch": .keyword, "case": .keyword, "default": .keyword,
        "for": .keyword, "while": .keyword, "do": .keyword, "break": .keywordControl,
        "continue": .keywordControl, "return": .keywordControl, "throw": .keywordControl,
        "try": .keyword, "catch": .keyword, "finally": .keyword,
        
        // Other
        "import": .keyword, "package": .keyword, "new": .keyword, "extends": .keyword,
        "implements": .keyword, "super": .keyword, "this": .keyword, "instanceof": .keywordOperator,
        "true": .number, "false": .number, "null": .null, "var": .keywordDeclaration
    ]
    
    return StateMachineLexer(
        languageId: "java",
        keywords: javaKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: "/**",
        stringDelimiters: ["\""],
        multilineStringDelimiter: nil,
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for Kotlin
public func createKotlinLexer() -> StateMachineLexer {
    let kotlinKeywords: [String: SyntaxTokenType] = [
        // Declarations
        "class": .keywordDeclaration, "interface": .keywordDeclaration, "object": .keywordDeclaration,
        "fun": .keywordDeclaration, "val": .keywordDeclaration, "var": .keywordDeclaration,
        "constructor": .keywordDeclaration, "init": .keywordDeclaration, "this": .keyword,
        "super": .keyword, "package": .keywordDeclaration, "import": .keyword,
        
        // Modifiers
        "public": .keywordModifier, "private": .keywordModifier, "protected": .keywordModifier,
        "internal": .keywordModifier, "abstract": .keywordModifier, "final": .keywordModifier,
        "open": .keywordModifier, "override": .keywordModifier, "lateinit": .keywordModifier,
        "companion": .keywordModifier, "data": .keywordModifier, "sealed": .keywordModifier,
        "enum": .keywordDeclaration, "annotation": .keywordDeclaration,
        
        // Control flow
        "if": .keyword, "else": .keyword, "when": .keyword, "for": .keyword, "while": .keyword,
        "do": .keyword, "return": .keywordControl, "break": .keywordControl, "continue": .keywordControl,
        "throw": .keywordControl, "try": .keyword, "catch": .keyword, "finally": .keyword,
        
        // Operators/Types
        "is": .keywordOperator, "in": .keywordOperator, "as": .keywordOperator,
        "true": .number, "false": .number, "null": .null,
        "Type": .type, "Int": .type, "String": .type, "Boolean": .type,
        
        // Coroutines
        "suspend": .keywordModifier
    ]
    
    return StateMachineLexer(
        languageId: "kotlin",
        keywords: kotlinKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: "/**",
        stringDelimiters: ["\""],
        multilineStringDelimiter: "\"\"\"",
        interpolationStart: "$"
    )
}

// MARK: - Extended Multi-Language Lexers

/// Creates a pre-configured lexer for C++
public func createCppLexer() -> StateMachineLexer {
    var cppKeywords = [
        // Types
        "int": SyntaxTokenType.type, "char": .type, "float": .type, "double": .type, "void": .type,
        "long": .type, "short": .type, "unsigned": .type, "signed": .type, "bool": .type, "size_t": .type,
        "uint8_t": .type, "uint16_t": .type, "uint32_t": .type, "uint64_t": .type,
        "int8_t": .type, "int16_t": .type, "int32_t": .type, "int64_t": .type, "uintptr_t": .type, "ptrdiff_t": .type,
        "string": .type, "string_view": .type, "vector": .type, "map": .type, "set": .type,
        "unordered_map": .type, "unordered_set": .type, "array": .type, "deque": .type, "list": .type,
        "queue": .type, "stack": .type, "pair": .type, "tuple": .type, "unique_ptr": .type, "shared_ptr": .type,
        "weak_ptr": .type, "optional": .type, "variant": .type, "any": .type, "span": .type,
        "thread": .type, "mutex": .type, "atomic": .type, "auto": .keyword, "decltype": .keyword,

        // Declarations & Modifiers
        "class": .keywordDeclaration, "struct": .keywordDeclaration, "union": .keywordDeclaration,
        "enum": .keywordDeclaration, "typedef": .keywordDeclaration, "namespace": .keywordDeclaration,
        "template": .keywordDeclaration, "typename": .keywordDeclaration, "concept": .keywordDeclaration,
        "requires": .keywordDeclaration, "public": .keywordModifier, "private": .keywordModifier,
        "protected": .keywordModifier, "virtual": .keywordModifier, "override": .keywordModifier,
        "final": .keywordModifier, "constexpr": .keywordModifier, "consteval": .keywordModifier,
        "constinit": .keywordModifier, "noexcept": .keywordModifier, "inline": .keywordModifier,
        "static": .keywordModifier, "extern": .keywordModifier, "mutable": .keywordModifier,
        "explicit": .keywordModifier, "friend": .keywordModifier, "volatile": .keywordModifier, "const": .keywordModifier,

        // Control flow & statements
        "if": .keyword, "else": .keyword, "switch": .keyword, "case": .keyword, "default": .keyword,
        "for": .keyword, "while": .keyword, "do": .keyword, "break": .keywordControl,
        "continue": .keywordControl, "return": .keywordControl, "goto": .keywordControl,
        "try": .keyword, "catch": .keyword, "throw": .keywordControl, "co_await": .keyword,
        "co_return": .keywordControl, "co_yield": .keyword, "static_assert": .keyword, "nullptr": .number,
        "new": .keyword, "delete": .keyword, "sizeof": .keyword, "this": .keyword, "using": .keyword,

        // Preprocessor
        "include": .preprocessor, "define": .preprocessor, "ifdef": .preprocessor, "ifndef": .preprocessor,
        "endif": .preprocessor, "pragma": .preprocessor, "true": .number, "false": .number
    ]
    return StateMachineLexer(
        languageId: "cpp",
        keywords: cppKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: "/**",
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: nil,
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for Objective-C / Objective-C++
public func createObjCLexer() -> StateMachineLexer {
    let objcKeywords: [String: SyntaxTokenType] = [
        "@interface": .keywordDeclaration, "@implementation": .keywordDeclaration, "@protocol": .keywordDeclaration,
        "@end": .keywordDeclaration, "@property": .keywordDeclaration, "@synthesize": .keywordDeclaration,
        "@dynamic": .keywordDeclaration, "@class": .keywordDeclaration, "@import": .keyword,
        "@selector": .keyword, "@encode": .keyword, "@synchronized": .keyword, "@autoreleasepool": .keyword,
        "@try": .keyword, "@catch": .keyword, "@finally": .keyword, "@throw": .keywordControl,
        "id": .type, "instancetype": .type, "Class": .type, "SEL": .type, "BOOL": .type,
        "NSInteger": .type, "NSUInteger": .type, "CGFloat": .type, "NSString": .type, "NSArray": .type,
        "NSDictionary": .type, "NSSet": .type, "NSNumber": .type, "NSData": .type, "NSURL": .type,
        "NSError": .type, "NSObject": .type, "UIView": .type, "UIViewController": .type, "NSView": .type,
        "nonatomic": .keywordModifier, "atomic": .keywordModifier, "strong": .keywordModifier,
        "weak": .keywordModifier, "assign": .keywordModifier, "copy": .keywordModifier, "readonly": .keywordModifier,
        "readwrite": .keywordModifier, "nullable": .keywordModifier, "nonnull": .keywordModifier,
        "_Nullable": .keywordModifier, "_Nonnull": .keywordModifier, "YES": .number, "NO": .number,
        "nil": .null, "Nil": .null, "NULL": .null, "self": .keyword, "super": .keyword,
        "if": .keyword, "else": .keyword, "switch": .keyword, "case": .keyword, "default": .keyword,
        "for": .keyword, "while": .keyword, "do": .keyword, "return": .keywordControl, "break": .keywordControl,
        "int": .type, "float": .type, "double": .type, "char": .type, "void": .type, "static": .keywordModifier
    ]
    return StateMachineLexer(
        languageId: "objective-c",
        keywords: objcKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: "/**",
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: nil,
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for C#
public func createCSharpLexer() -> StateMachineLexer {
    let csKeywords: [String: SyntaxTokenType] = [
        "class": .keywordDeclaration, "struct": .keywordDeclaration, "record": .keywordDeclaration,
        "interface": .keywordDeclaration, "enum": .keywordDeclaration, "delegate": .keywordDeclaration,
        "namespace": .keywordDeclaration, "using": .keyword, "event": .keywordDeclaration,
        "public": .keywordModifier, "private": .keywordModifier, "protected": .keywordModifier,
        "internal": .keywordModifier, "static": .keywordModifier, "readonly": .keywordModifier,
        "volatile": .keywordModifier, "virtual": .keywordModifier, "override": .keywordModifier,
        "abstract": .keywordModifier, "sealed": .keywordModifier, "async": .keywordModifier,
        "await": .keywordModifier, "unsafe": .keywordModifier, "partial": .keywordModifier,
        "required": .keywordModifier, "void": .type, "bool": .type, "byte": .type, "char": .type,
        "decimal": .type, "double": .type, "float": .type, "int": .type, "uint": .type, "long": .type,
        "ulong": .type, "short": .type, "ushort": .type, "object": .type, "string": .type, "dynamic": .type,
        "var": .keywordDeclaration, "Task": .type, "List": .type, "Dictionary": .type, "IEnumerable": .type,
        "if": .keyword, "else": .keyword, "switch": .keyword, "case": .keyword, "default": .keyword,
        "for": .keyword, "foreach": .keyword, "in": .keywordOperator, "while": .keyword, "do": .keyword,
        "break": .keywordControl, "continue": .keywordControl, "return": .keywordControl, "goto": .keywordControl,
        "yield": .keywordControl, "throw": .keywordControl, "try": .keyword, "catch": .keyword, "finally": .keyword,
        "from": .keyword, "where": .keyword, "select": .keyword, "group": .keyword, "into": .keyword,
        "orderby": .keyword, "join": .keyword, "let": .keyword, "on": .keyword, "equals": .keyword,
        "new": .keyword, "this": .keyword, "base": .keyword, "null": .null, "true": .number, "false": .number,
        "is": .keywordOperator, "as": .keywordOperator, "typeof": .keyword, "sizeof": .keyword, "nameof": .keyword,
        "get": .keyword, "set": .keyword, "init": .keyword, "value": .keyword
    ]
    return StateMachineLexer(
        languageId: "csharp",
        keywords: csKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: "///",
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: "\"\"\"",
        interpolationStart: "{"
    )
}

/// Creates a pre-configured lexer for Dart & Flutter
public func createDartLexer() -> StateMachineLexer {
    let dartKeywords: [String: SyntaxTokenType] = [
        "class": .keywordDeclaration, "enum": .keywordDeclaration, "mixin": .keywordDeclaration,
        "extension": .keywordDeclaration, "typedef": .keywordDeclaration, "import": .keyword,
        "export": .keyword, "part": .keyword, "library": .keyword, "as": .keywordOperator,
        "show": .keyword, "hide": .keyword, "abstract": .keywordModifier, "const": .keywordModifier,
        "final": .keywordModifier, "late": .keywordModifier, "static": .keywordModifier,
        "factory": .keywordModifier, "external": .keywordModifier, "required": .keywordModifier,
        "async": .keywordModifier, "await": .keywordModifier, "sync": .keywordModifier,
        "yield": .keywordControl, "if": .keyword, "else": .keyword, "switch": .keyword, "case": .keyword,
        "default": .keyword, "for": .keyword, "while": .keyword, "do": .keyword, "break": .keywordControl,
        "continue": .keywordControl, "return": .keywordControl, "throw": .keywordControl, "try": .keyword,
        "catch": .keyword, "finally": .keyword, "rethrow": .keywordControl, "assert": .keyword,
        "extends": .keyword, "with": .keyword, "implements": .keyword, "super": .keyword, "this": .keyword,
        "new": .keyword, "is": .keywordOperator, "var": .keywordDeclaration, "dynamic": .type,
        "void": .type, "int": .type, "double": .type, "num": .type, "bool": .type, "String": .type,
        "List": .type, "Map": .type, "Set": .type, "Future": .type, "Stream": .type,
        "Widget": .type, "StatelessWidget": .type, "StatefulWidget": .type, "State": .type,
        "BuildContext": .type, "Color": .type, "Container": .type, "Text": .type, "Row": .type,
        "Column": .type, "Stack": .type, "Scaffold": .type, "AppBar": .type, "MaterialApp": .type,
        "true": .number, "false": .number, "null": .null
    ]
    return StateMachineLexer(
        languageId: "dart",
        keywords: dartKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: "///",
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: "\"\"\"",
        interpolationStart: "$"
    )
}

/// Creates a pre-configured lexer for PHP
public func createPhpLexer() -> StateMachineLexer {
    let phpKeywords: [String: SyntaxTokenType] = [
        "function": .keywordDeclaration, "fn": .keywordDeclaration, "class": .keywordDeclaration,
        "interface": .keywordDeclaration, "trait": .keywordDeclaration, "enum": .keywordDeclaration,
        "extends": .keyword, "implements": .keyword, "public": .keywordModifier, "private": .keywordModifier,
        "protected": .keywordModifier, "static": .keywordModifier, "final": .keywordModifier,
        "readonly": .keywordModifier, "abstract": .keywordModifier, "const": .keywordModifier,
        "var": .keywordDeclaration, "global": .keywordModifier, "if": .keyword, "else": .keyword,
        "elseif": .keyword, "switch": .keyword, "case": .keyword, "default": .keyword, "match": .keyword,
        "for": .keyword, "foreach": .keyword, "as": .keyword, "while": .keyword, "do": .keyword,
        "break": .keywordControl, "continue": .keywordControl, "return": .keywordControl, "goto": .keywordControl,
        "try": .keyword, "catch": .keyword, "finally": .keyword, "throw": .keywordControl,
        "echo": .keyword, "print": .keyword, "die": .keyword, "exit": .keyword, "isset": .keyword,
        "empty": .keyword, "unset": .keyword, "include": .keyword, "include_once": .keyword,
        "require": .keyword, "require_once": .keyword, "namespace": .keywordDeclaration, "use": .keyword,
        "new": .keyword, "clone": .keyword, "instanceof": .keywordOperator, "yield": .keywordControl,
        "true": .number, "false": .number, "null": .null, "self": .keyword, "parent": .keyword
    ]
    return StateMachineLexer(
        languageId: "php",
        keywords: phpKeywords,
        lineCommentPrefix: "//",
        additionalLineCommentPrefixes: ["#"],
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: "/**",
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: nil,
        interpolationStart: "$"
    )
}

/// Creates a pre-configured lexer for Shell (Bash / Zsh / POSIX)
public func createShellLexer() -> StateMachineLexer {
    let shellKeywords: [String: SyntaxTokenType] = [
        "if": .keyword, "then": .keyword, "else": .keyword, "elif": .keyword, "fi": .keyword,
        "for": .keyword, "in": .keyword, "do": .keyword, "done": .keyword, "while": .keyword,
        "until": .keyword, "case": .keyword, "esac": .keyword, "select": .keyword, "function": .keywordDeclaration,
        "time": .keyword, "export": .keywordModifier, "source": .keyword, "alias": .keyword,
        "unalias": .keyword, "local": .keywordDeclaration, "declare": .keywordDeclaration,
        "typeset": .keywordDeclaration, "readonly": .keywordModifier, "return": .keywordControl,
        "exit": .keywordControl, "set": .keyword, "unset": .keyword, "eval": .keyword, "exec": .keyword,
        "trap": .keyword, "shift": .keyword, "read": .keyword, "echo": .keyword, "printf": .keyword,
        "test": .keyword, "true": .number, "false": .number, "cd": .keyword, "pwd": .keyword
    ]
    return StateMachineLexer(
        languageId: "shell",
        keywords: shellKeywords,
        lineCommentPrefix: "#",
        blockCommentMarkers: nil,
        docCommentPrefix: nil,
        stringDelimiters: ["\"", "'", "`"],
        multilineStringDelimiter: nil,
        interpolationStart: "$"
    )
}

/// Creates a pre-configured lexer for SQL (ANSI, PostgreSQL, MySQL, BigQuery, SQLite)
public func createSqlLexer() -> StateMachineLexer {
    let sqlKeywords: [String: SyntaxTokenType] = [
        "select": .keyword, "from": .keyword, "where": .keyword, "insert": .keyword, "into": .keyword,
        "values": .keyword, "update": .keyword, "set": .keyword, "delete": .keyword, "join": .keyword,
        "inner": .keyword, "left": .keyword, "right": .keyword, "full": .keyword, "outer": .keyword,
        "cross": .keyword, "natural": .keyword, "on": .keyword, "using": .keyword, "group": .keyword,
        "by": .keyword, "having": .keyword, "order": .keyword, "asc": .keyword, "desc": .keyword,
        "limit": .keyword, "offset": .keyword, "union": .keyword, "all": .keyword, "intersect": .keyword,
        "except": .keyword, "distinct": .keyword, "create": .keywordDeclaration, "alter": .keywordDeclaration,
        "drop": .keywordDeclaration, "truncate": .keywordDeclaration, "table": .keywordDeclaration,
        "view": .keywordDeclaration, "index": .keywordDeclaration, "schema": .keywordDeclaration,
        "database": .keywordDeclaration, "column": .keywordDeclaration, "constraint": .keywordDeclaration,
        "primary": .keywordModifier, "key": .keywordModifier, "foreign": .keywordModifier,
        "references": .keywordModifier, "check": .keywordModifier, "unique": .keywordModifier,
        "default": .keywordModifier, "cascade": .keywordModifier, "and": .keywordOperator,
        "or": .keywordOperator, "not": .keywordOperator, "in": .keywordOperator, "is": .keywordOperator,
        "null": .null, "like": .keywordOperator, "ilike": .keywordOperator, "between": .keywordOperator,
        "exists": .keywordOperator, "case": .keyword, "when": .keyword, "then": .keyword,
        "else": .keyword, "end": .keyword, "cast": .keyword, "as": .keyword, "over": .keyword,
        "partition": .keyword, "count": .function, "sum": .function, "avg": .function, "min": .function,
        "max": .function, "coalesce": .function, "int": .type, "integer": .type, "bigint": .type,
        "varchar": .type, "char": .type, "text": .type, "boolean": .type, "bool": .type,
        "date": .type, "timestamp": .type, "float": .type, "double": .type, "numeric": .type,
        "decimal": .type, "json": .type, "jsonb": .type, "true": .number, "false": .number
    ]
    return StateMachineLexer(
        languageId: "sql",
        keywords: sqlKeywords,
        lineCommentPrefix: "--",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: nil,
        stringDelimiters: ["'", "\""],
        multilineStringDelimiter: nil,
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for HTML, XML, and SVG
public func createHtmlLexer() -> StateMachineLexer {
    let htmlKeywords: [String: SyntaxTokenType] = [
        "html": .keyword, "head": .keyword, "body": .keyword, "div": .keyword, "span": .keyword,
        "p": .keyword, "a": .keyword, "img": .keyword, "button": .keyword, "input": .keyword,
        "form": .keyword, "label": .keyword, "select": .keyword, "option": .keyword, "textarea": .keyword,
        "table": .keyword, "thead": .keyword, "tbody": .keyword, "tr": .keyword, "th": .keyword,
        "td": .keyword, "ul": .keyword, "ol": .keyword, "li": .keyword, "nav": .keyword,
        "header": .keyword, "footer": .keyword, "main": .keyword, "section": .keyword,
        "article": .keyword, "aside": .keyword, "h1": .keyword, "h2": .keyword, "h3": .keyword,
        "h4": .keyword, "h5": .keyword, "h6": .keyword, "script": .keyword, "style": .keyword,
        "link": .keyword, "meta": .keyword, "title": .keyword, "svg": .keyword, "path": .keyword,
        "circle": .keyword, "rect": .keyword, "line": .keyword, "g": .keyword, "iframe": .keyword,
        "class": .property, "id": .property, "name": .property, "value": .property, "type": .property,
        "src": .property, "href": .property, "rel": .property, "target": .property, "alt": .property,
        "width": .property, "height": .property, "placeholder": .property,
        "disabled": .property, "required": .property, "readonly": .property, "data": .property,
        "doctype": .preprocessor
    ]
    return StateMachineLexer(
        languageId: "html",
        keywords: htmlKeywords,
        lineCommentPrefix: nil,
        blockCommentMarkers: ("<!--", "-->"),
        docCommentPrefix: nil,
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: nil,
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for CSS, SCSS, and Less
public func createCssLexer() -> StateMachineLexer {
    let cssKeywords: [String: SyntaxTokenType] = [
        "color": .property, "background": .property, "margin": .property, "padding": .property,
        "border": .property, "font": .property, "display": .property, "position": .property,
        "top": .property, "bottom": .property, "left": .property, "right": .property,
        "width": .property, "height": .property, "flex": .property, "grid": .property,
        "justify-content": .property, "align-items": .property, "gap": .property, "overflow": .property,
        "z-index": .property, "opacity": .property, "transform": .property, "transition": .property,
        "animation": .property, "box-shadow": .property, "border-radius": .property, "cursor": .property,
        "@media": .keyword, "@keyframes": .keyword, "@import": .keyword, "@font-face": .keyword,
        "@supports": .keyword, "important": .keywordModifier, "none": .type, "block": .type,
        "inline": .type, "inline-block": .type, "relative": .type, "absolute": .type, "fixed": .type,
        "sticky": .type, "inherit": .type, "initial": .type, "auto": .type
    ]
    return StateMachineLexer(
        languageId: "css",
        keywords: cssKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: nil,
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: nil,
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for JSON
public func createJsonLexer() -> StateMachineLexer {
    let jsonKeywords: [String: SyntaxTokenType] = [
        "true": .number, "false": .number, "null": .null
    ]
    return StateMachineLexer(
        languageId: "json",
        keywords: jsonKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: nil,
        stringDelimiters: ["\""],
        multilineStringDelimiter: nil,
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for YAML / TOML
public func createYamlLexer() -> StateMachineLexer {
    let yamlKeywords: [String: SyntaxTokenType] = [
        "true": .number, "false": .number, "yes": .number, "no": .number,
        "on": .number, "off": .number, "null": .null, "~": .null,
        "True": .number, "False": .number, "None": .null
    ]
    return StateMachineLexer(
        languageId: "yaml",
        keywords: yamlKeywords,
        lineCommentPrefix: "#",
        blockCommentMarkers: nil,
        docCommentPrefix: nil,
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: nil,
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for Markdown
public func createMarkdownLexer() -> StateMachineLexer {
    return StateMachineLexer(
        languageId: "markdown",
        keywords: ["TODO": .keyword, "FIXME": .keywordControl, "NOTE": .type, "WARNING": .keywordControl],
        lineCommentPrefix: nil,
        blockCommentMarkers: ("<!--", "-->"),
        docCommentPrefix: nil,
        stringDelimiters: ["`", "\""],
        multilineStringDelimiter: "```",
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for Lua
public func createLuaLexer() -> StateMachineLexer {
    let luaKeywords: [String: SyntaxTokenType] = [
        "and": .keywordOperator, "break": .keywordControl, "do": .keyword, "else": .keyword,
        "elseif": .keyword, "end": .keyword, "false": .number, "for": .keyword,
        "function": .keywordDeclaration, "goto": .keywordControl, "if": .keyword, "in": .keywordOperator,
        "local": .keywordDeclaration, "nil": .null, "not": .keywordOperator, "or": .keywordOperator,
        "repeat": .keyword, "return": .keywordControl, "then": .keyword, "true": .number,
        "until": .keyword, "while": .keyword, "print": .function, "require": .keyword,
        "type": .function, "tostring": .function, "tonumber": .function, "pairs": .function, "ipairs": .function
    ]
    return StateMachineLexer(
        languageId: "lua",
        keywords: luaKeywords,
        lineCommentPrefix: "--",
        blockCommentMarkers: ("--[[", "]]"),
        docCommentPrefix: nil,
        stringDelimiters: ["\"", "'", "`"],
        multilineStringDelimiter: nil,
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for Zig
public func createZigLexer() -> StateMachineLexer {
    let zigKeywords: [String: SyntaxTokenType] = [
        "const": .keywordDeclaration, "var": .keywordDeclaration, "fn": .keywordDeclaration,
        "pub": .keywordModifier, "usingnamespace": .keyword, "struct": .keywordDeclaration,
        "enum": .keywordDeclaration, "union": .keywordDeclaration, "error": .keywordDeclaration,
        "test": .keywordDeclaration, "comptime": .keywordModifier, "inline": .keywordModifier,
        "extern": .keywordModifier, "export": .keywordModifier, "threadlocal": .keywordModifier,
        "align": .keywordModifier, "volatile": .keywordModifier, "asm": .keyword,
        "defer": .keywordControl, "errdefer": .keywordControl, "unreachable": .keywordControl,
        "return": .keywordControl, "break": .keywordControl, "continue": .keywordControl,
        "if": .keyword, "else": .keyword, "switch": .keyword, "while": .keyword, "for": .keyword,
        "try": .keyword, "catch": .keyword, "async": .keywordModifier, "await": .keywordModifier,
        "suspend": .keywordModifier, "resume": .keywordModifier, "anytype": .type, "anyerror": .type,
        "void": .type, "bool": .type, "i8": .type, "u8": .type, "i16": .type, "u16": .type,
        "i32": .type, "u32": .type, "i64": .type, "u64": .type, "isize": .type, "usize": .type,
        "f32": .type, "f64": .type, "null": .null, "undefined": .null, "true": .number, "false": .number
    ]
    return StateMachineLexer(
        languageId: "zig",
        keywords: zigKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: nil,
        docCommentPrefix: "///",
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: nil,
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for R
public func createRLexer() -> StateMachineLexer {
    let rKeywords: [String: SyntaxTokenType] = [
        "if": .keyword, "else": .keyword, "repeat": .keyword, "while": .keyword,
        "function": .keywordDeclaration, "for": .keyword, "in": .keywordOperator,
        "next": .keywordControl, "break": .keywordControl, "TRUE": .number, "FALSE": .number,
        "NULL": .null, "Inf": .number, "NaN": .number, "NA": .null, "library": .keyword, "require": .keyword
    ]
    return StateMachineLexer(
        languageId: "r",
        keywords: rKeywords,
        lineCommentPrefix: "#",
        blockCommentMarkers: nil,
        docCommentPrefix: nil,
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: nil,
        interpolationStart: nil
    )
}

/// Creates a pre-configured lexer for Julia
public func createJuliaLexer() -> StateMachineLexer {
    let juliaKeywords: [String: SyntaxTokenType] = [
        "function": .keywordDeclaration, "macro": .keywordDeclaration, "quote": .keyword,
        "let": .keywordDeclaration, "local": .keywordModifier, "global": .keywordModifier,
        "const": .keywordModifier, "do": .keyword, "struct": .keywordDeclaration,
        "module": .keywordDeclaration, "using": .keyword, "import": .keyword, "export": .keyword,
        "type": .keywordDeclaration, "abstract": .keywordModifier, "mutable": .keywordModifier,
        "return": .keywordControl, "break": .keywordControl, "continue": .keywordControl,
        "if": .keyword, "elseif": .keyword, "else": .keyword, "for": .keyword, "while": .keyword,
        "try": .keyword, "catch": .keyword, "finally": .keyword, "throw": .keywordControl,
        "true": .number, "false": .number, "nothing": .null, "missing": .null
    ]
    return StateMachineLexer(
        languageId: "julia",
        keywords: juliaKeywords,
        lineCommentPrefix: "#",
        blockCommentMarkers: ("#=", "=#"),
        docCommentPrefix: nil,
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: "\"\"\"",
        interpolationStart: "$"
    )
}

/// Creates a pre-configured lexer for Elixir
public func createElixirLexer() -> StateMachineLexer {
    let elixirKeywords: [String: SyntaxTokenType] = [
        "def": .keywordDeclaration, "defp": .keywordDeclaration, "defmodule": .keywordDeclaration,
        "defmacro": .keywordDeclaration, "defprotocol": .keywordDeclaration, "defimpl": .keywordDeclaration,
        "do": .keyword, "end": .keyword, "if": .keyword, "unless": .keyword, "case": .keyword,
        "cond": .keyword, "with": .keyword, "for": .keyword, "try": .keyword, "rescue": .keyword,
        "catch": .keyword, "after": .keyword, "receive": .keyword, "send": .keyword,
        "import": .keyword, "require": .keyword, "use": .keyword, "alias": .keyword,
        "fn": .keywordDeclaration, "true": .number, "false": .number, "nil": .null
    ]
    return StateMachineLexer(
        languageId: "elixir",
        keywords: elixirKeywords,
        lineCommentPrefix: "#",
        blockCommentMarkers: nil,
        docCommentPrefix: "@doc",
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: "\"\"\"",
        interpolationStart: "#{"
    )
}

/// Creates a pre-configured lexer for Solidity
public func createSolidityLexer() -> StateMachineLexer {
    let solidityKeywords: [String: SyntaxTokenType] = [
        "contract": .keywordDeclaration, "interface": .keywordDeclaration, "library": .keywordDeclaration,
        "is": .keyword, "pragma": .preprocessor, "solidity": .keyword, "import": .keyword,
        "function": .keywordDeclaration, "modifier": .keywordDeclaration, "event": .keywordDeclaration,
        "error": .keywordDeclaration, "struct": .keywordDeclaration, "enum": .keywordDeclaration,
        "mapping": .keywordDeclaration, "address": .type, "bool": .type, "string": .type,
        "bytes": .type, "int": .type, "uint": .type, "uint256": .type, "public": .keywordModifier,
        "private": .keywordModifier, "internal": .keywordModifier, "external": .keywordModifier,
        "view": .keywordModifier, "pure": .keywordModifier, "payable": .keywordModifier,
        "memory": .keywordModifier, "storage": .keywordModifier, "calldata": .keywordModifier,
        "virtual": .keywordModifier, "override": .keywordModifier, "returns": .keyword,
        "return": .keywordControl, "emit": .keyword, "revert": .keywordControl, "require": .keyword,
        "assert": .keyword, "if": .keyword, "else": .keyword, "for": .keyword, "while": .keyword,
        "do": .keyword, "break": .keywordControl, "continue": .keywordControl, "try": .keyword,
        "catch": .keyword, "assembly": .keyword, "constructor": .keywordDeclaration, "msg": .keyword,
        "tx": .keyword, "block": .keyword, "this": .keyword, "true": .number, "false": .number
    ]
    return StateMachineLexer(
        languageId: "solidity",
        keywords: solidityKeywords,
        lineCommentPrefix: "//",
        blockCommentMarkers: ("/*", "*/"),
        docCommentPrefix: "///",
        stringDelimiters: ["\"", "'"],
        multilineStringDelimiter: nil,
        interpolationStart: nil
    )
}


