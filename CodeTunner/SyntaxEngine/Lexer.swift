//
//  Lexer.swift
//  CodeTunner - Syntax Highlighting Engine
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
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
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
        blockCommentMarkers: (String, String)? = ("/*", "*/"),
        docCommentPrefix: String? = "///",
        stringDelimiters: [Character] = ["\"", "'"],
        multilineStringDelimiter: String? = nil,
        interpolationStart: String? = nil
    ) {
        self.languageId = languageId
        self.keywords = keywords
        self.lineCommentPrefix = lineCommentPrefix
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
        if let prefix = lineCommentPrefix, text.hasPrefix(prefix) {
            let comment = String(text.prefix(while: { $0 != "\n" }))
            let range = SyntaxTextRange(line: line, column: column, length: comment.utf16.count, offset: offset)
            let token = SyntaxToken(type: .comment, text: comment, range: range, endState: .normal)
            return (token, .normal, comment.count)
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
            } else if char == "." && !isFloat && index < text.index(before: text.endIndex) && text[text.index(after: index)].isNumber {
                isFloat = true
                index = text.index(after: index)
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
        } else if let kwType = keywords[identText] {
            tokenType = kwType
        } else if identText == "true" || identText == "false" {
            tokenType = .boolean
        } else if identText == "nil" || identText == "null" || identText == "None" {
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
        "async": .keywordModifier, "await": .keywordModifier, "@MainActor": .keywordModifier,
        
        // Control flow
        "if": .keyword, "else": .keyword, "switch": .keyword, "case": .keyword,
        "default": .keyword, "for": .keyword, "while": .keyword, "repeat": .keyword,
        "do": .keyword, "guard": .keyword, "where": .keyword, "in": .keywordOperator,
        "return": .keywordControl, "break": .keywordControl, "continue": .keywordControl,
        "fallthrough": .keywordControl, "throw": .keywordControl,
        
        // Error handling
        "try": .keyword, "catch": .keyword, "throws": .keyword, "rethrows": .keyword,
        
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
        "print": .function, "len": .function, "range": .function, "open": .function,
        "input": .function, "int": .function, "str": .function, "list": .function,
        "dict": .function, "set": .function, "tuple": .function, "type": .function,
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
        "console": .type, "document": .type, "window": .type, "process": .type,
        "require": .function, "module": .type, "exports": .type,
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

