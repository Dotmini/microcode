//
//  SyntaxHighlighter.swift
//  CodeTunner
//
//  Swift Playgrounds-style syntax highlighting
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import SwiftUI
import AppKit

// MARK: - Swift Playgrounds Color Scheme

struct PlaygroundsColors {
    // Keywords (if, else, func, class, struct, let, var, etc.)
    static let keyword = NSColor(red: 0.8, green: 0.2, blue: 0.6, alpha: 1.0)  // Pink
    
    // Strings
    static let string = NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0)  // Red
    
    // Comments
    static let comment = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)  // Gray
    
    // Types (Int, String, Bool, etc.)
    static let type = NSColor(red: 0.5, green: 0.3, blue: 0.8, alpha: 1.0)  // Purple
    
    // Functions
    static let function = NSColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1.0)  // Blue
    
    // Numbers
    static let number = NSColor(red: 0.8, green: 0.5, blue: 0.2, alpha: 1.0)  // Orange
    
    // Properties/Variables
    static let property = NSColor(red: 0.3, green: 0.7, blue: 0.6, alpha: 1.0)  // Teal
    
    // Operators
    static let `operator` = NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)  // Light gray
    
    // Default text
    static let text = NSColor.textColor
    
    // Background
    static let background = NSColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1.0)
    
    // Line numbers
    static let lineNumber = NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
}

// MARK: - Token Types

enum TokenType {
    case keyword
    case string
    case comment
    case type
    case function
    case number
    case property
    case `operator`
    case text
    
    var color: NSColor {
        switch self {
        case .keyword: return PlaygroundsColors.keyword
        case .string: return PlaygroundsColors.string
        case .comment: return PlaygroundsColors.comment
        case .type: return PlaygroundsColors.type
        case .function: return PlaygroundsColors.function
        case .number: return PlaygroundsColors.number
        case .property: return PlaygroundsColors.property
        case .operator: return PlaygroundsColors.operator
        case .text: return PlaygroundsColors.text
        }
    }
}

// MARK: - Language Rules

struct LanguageRules {
    let keywords: Set<String>
    let types: Set<String>
    let stringDelimiters: [String]
    let commentPatterns: [(start: String, end: String?)]
    
    static let python = LanguageRules(
        keywords: ["def", "class", "if", "else", "elif", "for", "while", "return", "import", "from", "as", "try", "except", "finally", "with", "lambda", "yield", "raise", "pass", "break", "continue", "and", "or", "not", "in", "is", "True", "False", "None", "async", "await", "global", "nonlocal"],
        types: ["int", "str", "float", "bool", "list", "dict", "tuple", "set", "bytes", "object", "type", "range", "enumerate", "zip", "map", "filter"],
        stringDelimiters: ["\"\"\"", "'''", "\"", "'"],
        commentPatterns: [("#", nil)]
    )
    
    static let swift = LanguageRules(
        keywords: ["func", "class", "struct", "enum", "protocol", "extension", "if", "else", "guard", "switch", "case", "default", "for", "while", "repeat", "return", "break", "continue", "throw", "throws", "try", "catch", "do", "let", "var", "where", "import", "typealias", "associatedtype", "init", "deinit", "subscript", "static", "private", "fileprivate", "internal", "public", "open", "override", "final", "mutating", "nonmutating", "lazy", "weak", "unowned", "inout", "some", "any", "async", "await", "actor", "@State", "@Binding", "@Published", "@ObservedObject", "@EnvironmentObject", "@Environment", "@MainActor", "self", "Self", "super", "nil", "true", "false"],
        types: ["Int", "String", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional", "Result", "Void", "Any", "AnyObject", "Error", "Never", "View", "Text", "Image", "Button", "VStack", "HStack", "ZStack", "List", "ScrollView", "NavigationView", "NavigationStack", "Color", "Font", "CGFloat", "CGPoint", "CGSize", "CGRect", "URL", "Date", "Data"],
        stringDelimiters: ["\"\"\"", "\""],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )
    
    static let rust = LanguageRules(
        keywords: ["fn", "let", "mut", "const", "static", "if", "else", "match", "loop", "while", "for", "in", "break", "continue", "return", "struct", "enum", "impl", "trait", "type", "where", "use", "mod", "pub", "crate", "self", "super", "as", "ref", "move", "async", "await", "dyn", "unsafe", "extern"],
        types: ["i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize", "f32", "f64", "bool", "char", "str", "String", "Vec", "Option", "Result", "Box", "Rc", "Arc", "Cell", "RefCell", "HashMap", "HashSet", "BTreeMap", "BTreeSet"],
        stringDelimiters: ["\""],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )
    
    static let javascript = LanguageRules(
        keywords: ["function", "const", "let", "var", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "throw", "try", "catch", "finally", "new", "delete", "typeof", "instanceof", "void", "this", "super", "class", "extends", "static", "get", "set", "async", "await", "yield", "import", "export", "from", "as", "default", "true", "false", "null", "undefined", "NaN", "Infinity"],
        types: ["Array", "Object", "String", "Number", "Boolean", "Function", "Symbol", "BigInt", "Map", "Set", "WeakMap", "WeakSet", "Promise", "Date", "RegExp", "Error", "JSON", "Math", "console"],
        stringDelimiters: ["`", "\"", "'"],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )
    
    static let go = LanguageRules(
        keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var", "true", "false", "nil", "iota"],
        types: ["bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr"],
        stringDelimiters: ["`", "\""],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )

    static let ardium = LanguageRules(
        keywords: ["fn", "let", "mut", "if", "else", "while", "return", "import", "void"],
        types: ["int", "string", "bool"],
        stringDelimiters: ["\""],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )
    
    static func forLanguage(_ language: String) -> LanguageRules {
        switch language.lowercased() {
        case "python": return .python
        case "swift": return .swift
        case "rust": return .rust
        case "javascript", "js": return .javascript
        case "typescript", "ts": return .javascript  // Similar to JS
        case "go", "golang": return .go
        case "ardium", "ar": return .ardium
        default: return .python
        }
    }
}

// MARK: - Metal-Accelerated Text Layer

/// GPU-accelerated text layer using Core Animation.
/// Set `drawsAsynchronously = true` to offload drawing to GPU.
class MetalTextLayer: CATextLayer {
    override init() {
        super.init()
        configure()
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
        configure()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }
    
    private func configure() {
        // GPU-accelerated asynchronous drawing
        self.drawsAsynchronously = true
        
        // Match screen resolution
        self.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        // Smooth text rendering
        self.allowsFontSubpixelQuantization = true
        
        // Optimize for frequently updated content
        self.isWrapped = true
        self.truncationMode = .none
    }
    
    /// Update text content with attributed string.
    func setHighlightedText(_ attributedString: NSAttributedString) {
        self.string = attributedString
    }
}

// MARK: - Playgrounds Syntax Highlighter

struct PlaygroundsSyntaxHighlighter {
    let language: String
    private let rules: LanguageRules
    
    init(language: String) {
        self.language = language
        self.rules = LanguageRules.forLanguage(language)
    }
    
    func highlight(_ code: String) -> AttributedString {
        var result = AttributedString()
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
        
        for (index, line) in lines.enumerated() {
            let highlightedLine = highlightLine(String(line))
            result.append(highlightedLine)
            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        
        return result
    }
    
    /// Async version running on E-Core for large files.
    /// Use this to avoid blocking UI during highlighting.
    func highlightAsync(_ code: String) async -> AttributedString {
        await PerformanceManager.shared.runOnECore { [self] in
            highlight(code)
        }
    }
    
    private func highlightLine(_ line: String) -> AttributedString {
        var result = AttributedString()
        var index = line.startIndex
        
        while index < line.endIndex {
            // Check for comments first
            if let (token, endIndex) = tryMatchComment(line, from: index) {
                var attr = AttributedString(token)
                attr.foregroundColor = Color(PlaygroundsColors.comment)
                result.append(attr)
                index = endIndex
                continue
            }
            
            // Check for strings
            if let (token, endIndex) = tryMatchString(line, from: index) {
                var attr = AttributedString(token)
                attr.foregroundColor = Color(PlaygroundsColors.string)
                result.append(attr)
                index = endIndex
                continue
            }
            
            // Check for numbers
            if let (token, endIndex) = tryMatchNumber(line, from: index) {
                var attr = AttributedString(token)
                attr.foregroundColor = Color(PlaygroundsColors.number)
                result.append(attr)
                index = endIndex
                continue
            }
            
            // Check for words (keywords, types, identifiers)
            if let (token, endIndex) = tryMatchWord(line, from: index) {
                var attr = AttributedString(token)
                
                if rules.keywords.contains(token) {
                    attr.foregroundColor = Color(PlaygroundsColors.keyword)
                } else if rules.types.contains(token) {
                    attr.foregroundColor = Color(PlaygroundsColors.type)
                } else if token.first?.isUppercase == true {
                    attr.foregroundColor = Color(PlaygroundsColors.type)
                } else {
                    attr.foregroundColor = Color(PlaygroundsColors.text)
                }
                
                result.append(attr)
                index = endIndex
                continue
            }
            
            // Default: single character
            var attr = AttributedString(String(line[index]))
            attr.foregroundColor = Color(PlaygroundsColors.text)
            result.append(attr)
            index = line.index(after: index)
        }
        
        return result
    }
    
    private func tryMatchComment(_ line: String, from start: String.Index) -> (String, String.Index)? {
        for (commentStart, commentEnd) in rules.commentPatterns {
            if line[start...].hasPrefix(commentStart) {
                if let end = commentEnd {
                    // Multi-line style - find end
                    if let endRange = line[start...].range(of: end) {
                        let token = String(line[start..<endRange.upperBound])
                        return (token, endRange.upperBound)
                    }
                    // No end found, take rest of line
                    return (String(line[start...]), line.endIndex)
                } else {
                    // Single line comment - rest of line
                    return (String(line[start...]), line.endIndex)
                }
            }
        }
        return nil
    }
    
    private func tryMatchString(_ line: String, from start: String.Index) -> (String, String.Index)? {
        for delimiter in rules.stringDelimiters {
            if line[start...].hasPrefix(delimiter) {
                let afterDelimiter = line.index(start, offsetBy: delimiter.count)
                if afterDelimiter >= line.endIndex {
                    return (delimiter, line.endIndex)
                }
                
                // Find closing delimiter
                var current = afterDelimiter
                while current < line.endIndex {
                    if line[current...].hasPrefix(delimiter) {
                        let end = line.index(current, offsetBy: delimiter.count)
                        return (String(line[start..<end]), end)
                    }
                    // Skip escaped characters
                    if line[current] == "\\" && line.index(after: current) < line.endIndex {
                        current = line.index(current, offsetBy: 2)
                    } else {
                        current = line.index(after: current)
                    }
                }
                // No closing found
                return (String(line[start...]), line.endIndex)
            }
        }
        return nil
    }
    
    private func tryMatchNumber(_ line: String, from start: String.Index) -> (String, String.Index)? {
        let nextIndex = line.index(after: start)
        guard line[start].isNumber || (line[start] == "." && nextIndex < line.endIndex && line[nextIndex].isNumber) else {
            return nil
        }
        
        var end = start
        var hasDot = false
        
        while end < line.endIndex {
            let char = line[end]
            if char.isNumber {
                end = line.index(after: end)
            } else if char == "." && !hasDot {
                hasDot = true
                end = line.index(after: end)
            } else if char == "x" || char == "X" || char == "b" || char == "B" || char == "o" || char == "O" {
                // Hex, binary, octal
                end = line.index(after: end)
            } else if char.isHexDigit || char == "_" {
                end = line.index(after: end)
            } else {
                break
            }
        }
        
        if end > start {
            return (String(line[start..<end]), end)
        }
        return nil
    }
    
    private func tryMatchWord(_ line: String, from start: String.Index) -> (String, String.Index)? {
        guard line[start].isLetter || line[start] == "_" || line[start] == "@" else {
            return nil
        }
        
        var end = start
        while end < line.endIndex && (line[end].isLetter || line[end].isNumber || line[end] == "_") {
            end = line.index(after: end)
        }
        
        if end > start {
            return (String(line[start..<end]), end)
        }
        return nil
    }
}

// MARK: - Syntax Highlighted Text View

struct SyntaxHighlightedText: View {
    let code: String
    let language: String
    
    private var highlighter: PlaygroundsSyntaxHighlighter {
        PlaygroundsSyntaxHighlighter(language: language)
    }
    
    var body: some View {
        Text(highlighter.highlight(code))
            .font(.system(size: 14, design: .monospaced))
            .textSelection(.enabled)
    }
}

// MARK: - Syntax Highlighted Editor

struct SyntaxHighlightedEditor: View {
    @Binding var code: String
    let language: String
    let showLineNumbers: Bool
    
    @State private var textViewHeight: CGFloat = 300
    
    init(code: Binding<String>, language: String, showLineNumbers: Bool = true) {
        self._code = code
        self.language = language
        self.showLineNumbers = showLineNumbers
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView([.vertical, .horizontal]) {
                HStack(alignment: .top, spacing: 0) {
                    // Line numbers
                    if showLineNumbers {
                        lineNumbersView
                    }
                    
                    // Code with highlighting overlay
                    ZStack(alignment: .topLeading) {
                        // Invisible TextEditor for editing
                        TextEditor(text: $code)
                            .font(.system(size: 14, design: .monospaced))
                            .compatScrollContentBackground(.hidden)
                            .background(.clear)
                            .foregroundColor(.clear)
                            .opacity(0.01)  // Nearly invisible but still editable
                        
                        // Highlighted code overlay
                        SyntaxHighlightedText(code: code, language: language)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)  // Let clicks through to TextEditor
                    }
                    .frame(minWidth: geometry.size.width - (showLineNumbers ? 50 : 0))
                }
            }
            .background(Color(PlaygroundsColors.background))
        }
    }
    
    private var lineNumbersView: some View {
        let lines = code.components(separatedBy: "\n")
        
        return VStack(alignment: .trailing, spacing: 0) {
            ForEach(0..<lines.count, id: \.self) { index in
                Text("\(index + 1)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(PlaygroundsColors.lineNumber))
                    .frame(height: 20)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(PlaygroundsColors.background).opacity(0.5))
    }
}
