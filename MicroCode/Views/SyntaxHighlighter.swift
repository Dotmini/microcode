//
//  SyntaxHighlighter.swift
//  MicroCode
//
//  Swift Playgrounds-style syntax highlighting
//  Copyright © 2025 Dotmini Company Limited. All rights reserved.
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
        keywords: [
            "fn", "var", "let", "mut", "struct", "class", "enum", "import", "extern", "async", "await",
            "export", "test", "interrupt", "@owned", "@State", "@External", "@export", "@test",
            "if", "else", "elif", "loop", "while", "for", "return", "break", "continue", "match",
            "true", "false", "nil", "null", "GLOBAL", "RESET", "ERR",
            "alloc", "free", "peek", "poke", "print", "println", "printf"
        ],
        types: [
            "int", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64",
            "float", "f32", "f64", "string", "bool", "void",
            "i8_ptr", "i32_ptr", "i64_ptr", "ptr", "Vector2", "Array", "Map", "Any",
            "VStack", "HStack", "ZStack", "Text", "Title", "Headline", "Button", "TextField", "Image", "Spacer", "Live", "DebugUI"
        ],
        stringDelimiters: ["\"\"\"", "\""],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )

    static let c = LanguageRules(
        keywords: ["if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "goto", "struct", "union", "enum", "typedef", "sizeof", "static", "extern", "const", "volatile", "inline", "true", "false", "NULL"],
        types: ["int", "char", "float", "double", "void", "short", "long", "signed", "unsigned", "bool", "size_t", "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "uintptr_t"],
        stringDelimiters: ["\"", "'"],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )

    static let cpp = LanguageRules(
        keywords: ["if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "goto", "class", "struct", "union", "enum", "typedef", "namespace", "using", "template", "typename", "concept", "requires", "public", "private", "protected", "virtual", "override", "final", "constexpr", "consteval", "noexcept", "inline", "static", "extern", "mutable", "explicit", "friend", "const", "new", "delete", "this", "nullptr", "sizeof", "try", "catch", "throw", "co_await", "co_return", "co_yield", "true", "false"],
        types: ["int", "char", "float", "double", "void", "bool", "auto", "size_t", "string", "string_view", "vector", "map", "set", "unordered_map", "unordered_set", "array", "deque", "list", "pair", "tuple", "unique_ptr", "shared_ptr", "weak_ptr", "optional", "variant", "any", "span", "thread", "mutex", "atomic"],
        stringDelimiters: ["\"", "'"],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )

    static let objc = LanguageRules(
        keywords: ["@interface", "@implementation", "@protocol", "@end", "@property", "@synthesize", "@dynamic", "@class", "@import", "@selector", "@encode", "@synchronized", "@autoreleasepool", "@try", "@catch", "@finally", "@throw", "nonatomic", "atomic", "strong", "weak", "assign", "copy", "readonly", "readwrite", "nullable", "nonnull", "self", "super", "if", "else", "for", "while", "return", "YES", "NO", "nil", "Nil", "NULL"],
        types: ["id", "instancetype", "Class", "SEL", "BOOL", "NSInteger", "NSUInteger", "CGFloat", "NSString", "NSArray", "NSDictionary", "NSSet", "NSNumber", "NSData", "NSURL", "NSError", "NSObject", "UIView", "UIViewController", "NSView", "int", "float", "double", "char", "void"],
        stringDelimiters: ["\"", "'"],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )

    static let csharp = LanguageRules(
        keywords: ["class", "struct", "record", "interface", "enum", "delegate", "namespace", "using", "public", "private", "protected", "internal", "static", "readonly", "volatile", "virtual", "override", "abstract", "sealed", "async", "await", "unsafe", "partial", "required", "if", "else", "switch", "case", "default", "for", "foreach", "in", "while", "do", "break", "continue", "return", "goto", "yield", "throw", "try", "catch", "finally", "from", "where", "select", "new", "this", "base", "null", "true", "false", "is", "as", "typeof", "get", "set", "init"],
        types: ["void", "bool", "byte", "char", "decimal", "double", "float", "int", "uint", "long", "ulong", "short", "ushort", "object", "string", "dynamic", "var", "Task", "List", "Dictionary", "IEnumerable", "Span"],
        stringDelimiters: ["\"", "'"],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )

    static let dart = LanguageRules(
        keywords: ["class", "enum", "mixin", "extension", "typedef", "import", "export", "part", "library", "as", "show", "hide", "abstract", "const", "final", "late", "static", "factory", "required", "async", "await", "sync", "yield", "if", "else", "switch", "case", "default", "for", "while", "do", "break", "continue", "return", "throw", "try", "catch", "finally", "rethrow", "assert", "extends", "with", "implements", "super", "this", "new", "is", "true", "false", "null"],
        types: ["var", "dynamic", "void", "int", "double", "num", "bool", "String", "List", "Map", "Set", "Future", "Stream", "Widget", "StatelessWidget", "StatefulWidget", "State", "BuildContext", "Color", "Container", "Text", "Row", "Column", "Stack", "Scaffold", "AppBar", "MaterialApp"],
        stringDelimiters: ["\"\"\"", "'''", "\"", "'"],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )

    static let java = LanguageRules(
        keywords: ["class", "interface", "enum", "extends", "implements", "public", "private", "protected", "static", "final", "abstract", "synchronized", "volatile", "transient", "native", "strictfp", "import", "package", "if", "else", "switch", "case", "default", "for", "while", "do", "break", "continue", "return", "throw", "throws", "try", "catch", "finally", "new", "this", "super", "instanceof", "assert", "record", "sealed", "permits", "true", "false", "null"],
        types: ["void", "boolean", "byte", "char", "short", "int", "long", "float", "double", "String", "Object", "List", "ArrayList", "Map", "HashMap", "Set", "HashSet", "Optional", "CompletableFuture"],
        stringDelimiters: ["\"\"\"", "\""],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )

    static let kotlin = LanguageRules(
        keywords: ["class", "interface", "object", "fun", "val", "var", "constructor", "init", "this", "super", "package", "import", "public", "private", "protected", "internal", "abstract", "final", "open", "override", "lateinit", "companion", "data", "sealed", "enum", "annotation", "suspend", "inline", "tailrec", "if", "else", "when", "for", "while", "do", "return", "break", "continue", "throw", "try", "catch", "finally", "is", "in", "as", "true", "false", "null"],
        types: ["Any", "Unit", "Nothing", "Int", "Long", "Short", "Byte", "Float", "Double", "Boolean", "Char", "String", "Array", "List", "Map", "Set", "MutableList", "MutableMap"],
        stringDelimiters: ["\"\"\"", "\""],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )

    static let php = LanguageRules(
        keywords: ["function", "fn", "class", "interface", "trait", "enum", "extends", "implements", "public", "private", "protected", "static", "final", "readonly", "abstract", "const", "var", "global", "if", "else", "elseif", "switch", "case", "default", "match", "for", "foreach", "as", "while", "do", "break", "continue", "return", "goto", "try", "catch", "finally", "throw", "echo", "print", "isset", "empty", "unset", "include", "require", "namespace", "use", "new", "clone", "instanceof", "yield", "true", "false", "null", "self", "parent"],
        types: ["string", "int", "float", "bool", "array", "object", "callable", "iterable", "void", "never", "mixed"],
        stringDelimiters: ["\"", "'"],
        commentPatterns: [("//", nil), ("#", nil), ("/*", "*/")]
    )

    static let ruby = LanguageRules(
        keywords: ["def", "class", "module", "end", "if", "elsif", "else", "unless", "while", "until", "for", "in", "do", "begin", "rescue", "ensure", "raise", "return", "break", "next", "redo", "retry", "yield", "super", "self", "alias", "and", "or", "not", "then", "when", "case", "true", "false", "nil", "attr_accessor", "attr_reader", "attr_writer", "require", "include"],
        types: ["String", "Integer", "Float", "Array", "Hash", "Symbol", "Regexp", "Range", "NilClass", "TrueClass", "FalseClass"],
        stringDelimiters: ["\"", "'"],
        commentPatterns: [("#", nil)]
    )

    static let shell = LanguageRules(
        keywords: ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until", "case", "esac", "select", "function", "time", "export", "source", "alias", "local", "declare", "readonly", "return", "exit", "set", "unset", "eval", "exec", "trap", "read", "echo", "printf", "test", "cd", "pwd", "true", "false"],
        types: ["PATH", "HOME", "USER", "SHELL", "TERM"],
        stringDelimiters: ["\"", "'", "`"],
        commentPatterns: [("#", nil)]
    )

    static let sql = LanguageRules(
        keywords: ["select", "from", "where", "insert", "into", "values", "update", "set", "delete", "join", "inner", "left", "right", "full", "outer", "cross", "on", "using", "group", "by", "having", "order", "asc", "desc", "limit", "offset", "union", "all", "intersect", "except", "distinct", "create", "alter", "drop", "truncate", "table", "view", "index", "schema", "database", "column", "constraint", "primary", "key", "foreign", "references", "check", "unique", "default", "and", "or", "not", "in", "is", "null", "like", "ilike", "between", "exists", "case", "when", "then", "else", "end", "cast", "as", "over", "partition"],
        types: ["int", "integer", "bigint", "smallint", "varchar", "char", "text", "boolean", "bool", "date", "timestamp", "float", "double", "numeric", "decimal", "json", "jsonb", "uuid", "blob"],
        stringDelimiters: ["'", "\""],
        commentPatterns: [("--", nil), ("/*", "*/")]
    )

    static let html = LanguageRules(
        keywords: ["html", "head", "body", "div", "span", "p", "a", "img", "button", "input", "form", "label", "select", "option", "textarea", "table", "thead", "tbody", "tr", "th", "td", "ul", "ol", "li", "nav", "header", "footer", "main", "section", "article", "aside", "h1", "h2", "h3", "h4", "h5", "h6", "script", "style", "link", "meta", "title", "svg", "path", "circle", "rect", "iframe"],
        types: ["class", "id", "name", "value", "type", "src", "href", "rel", "target", "alt", "style", "width", "height", "placeholder", "disabled", "required", "readonly", "data", "aria", "role"],
        stringDelimiters: ["\"", "'"],
        commentPatterns: [("<!--", "-->")]
    )

    static let css = LanguageRules(
        keywords: ["color", "background", "margin", "padding", "border", "font", "display", "position", "top", "bottom", "left", "right", "width", "height", "flex", "grid", "justify-content", "align-items", "gap", "overflow", "z-index", "opacity", "transform", "transition", "animation", "box-shadow", "border-radius", "cursor", "@media", "@keyframes", "@import", "@font-face", "important"],
        types: ["none", "block", "inline", "inline-block", "relative", "absolute", "fixed", "sticky", "inherit", "auto"],
        stringDelimiters: ["\"", "'"],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )

    static let json = LanguageRules(
        keywords: ["true", "false", "null"],
        types: ["String", "Number", "Boolean", "Array", "Object"],
        stringDelimiters: ["\""],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )

    static let yaml = LanguageRules(
        keywords: ["true", "false", "yes", "no", "on", "off", "null", "~", "True", "False", "None"],
        types: ["string", "int", "float", "bool", "list", "map"],
        stringDelimiters: ["\"", "'"],
        commentPatterns: [("#", nil)]
    )

    static let markdown = LanguageRules(
        keywords: ["TODO", "FIXME", "NOTE", "WARNING", "IMPORTANT", "TIP"],
        types: ["Heading", "List", "Code", "Link", "Quote"],
        stringDelimiters: ["`", "\""],
        commentPatterns: [("<!--", "-->")]
    )

    static let lua = LanguageRules(
        keywords: ["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"],
        types: ["string", "number", "table", "boolean", "nil", "function", "userdata", "thread"],
        stringDelimiters: ["\"", "'", "`"],
        commentPatterns: [("--", nil), ("/*", "*/")]
    )

    static let zig = LanguageRules(
        keywords: ["const", "var", "fn", "pub", "usingnamespace", "struct", "enum", "union", "error", "test", "comptime", "inline", "extern", "export", "defer", "errdefer", "unreachable", "return", "break", "continue", "if", "else", "switch", "while", "for", "try", "catch", "async", "await", "suspend", "resume", "null", "undefined", "true", "false"],
        types: ["void", "bool", "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "isize", "usize", "f32", "f64", "anytype", "anyerror"],
        stringDelimiters: ["\"", "'"],
        commentPatterns: [("//", nil)]
    )

    static let r = LanguageRules(
        keywords: ["if", "else", "repeat", "while", "function", "for", "in", "next", "break", "TRUE", "FALSE", "NULL", "Inf", "NaN", "NA", "library", "require"],
        types: ["data.frame", "vector", "matrix", "list", "factor", "numeric", "character", "logical"],
        stringDelimiters: ["\"", "'"],
        commentPatterns: [("#", nil)]
    )

    static let julia = LanguageRules(
        keywords: ["function", "macro", "quote", "let", "local", "global", "const", "do", "struct", "module", "using", "import", "export", "return", "break", "continue", "if", "elseif", "else", "for", "while", "try", "catch", "finally", "throw", "true", "false", "nothing"],
        types: ["Int", "Int64", "Float64", "Bool", "String", "Char", "Array", "Vector", "Matrix", "Dict", "Set"],
        stringDelimiters: ["\"\"\"", "\""],
        commentPatterns: [("#", nil)]
    )

    static let elixir = LanguageRules(
        keywords: ["def", "defp", "defmodule", "defmacro", "defprotocol", "defimpl", "do", "end", "if", "unless", "case", "cond", "with", "for", "try", "rescue", "catch", "after", "receive", "send", "import", "require", "use", "alias", "fn", "true", "false", "nil"],
        types: ["Integer", "Float", "Boolean", "Atom", "String", "List", "Map", "Tuple"],
        stringDelimiters: ["\"\"\"", "\""],
        commentPatterns: [("#", nil)]
    )

    static let solidity = LanguageRules(
        keywords: ["contract", "interface", "library", "is", "pragma", "solidity", "import", "function", "modifier", "event", "error", "struct", "enum", "mapping", "public", "private", "internal", "external", "view", "pure", "payable", "memory", "storage", "calldata", "virtual", "override", "returns", "return", "emit", "revert", "require", "assert", "if", "else", "for", "while", "true", "false"],
        types: ["address", "bool", "string", "bytes", "int", "uint", "uint8", "uint256"],
        stringDelimiters: ["\"", "'"],
        commentPatterns: [("//", nil), ("/*", "*/")]
    )
    
    static func forLanguage(_ language: String) -> LanguageRules {
        switch language.lowercased() {
        case "python", "py": return .python
        case "swift": return .swift
        case "rust", "rs": return .rust
        case "javascript", "js", "jsx", "mjs", "cjs": return .javascript
        case "typescript", "ts", "tsx", "mts", "cts": return .javascript
        case "go", "golang": return .go
        case "ardium", "ar": return .ardium
        case "c", "h": return .c
        case "cpp", "c++", "cc", "cxx", "hpp", "hxx", "hh", "arduino", "ino": return .cpp
        case "objc", "objective-c", "m", "objcpp", "objective-cpp", "mm": return .objc
        case "csharp", "cs", "c#": return .csharp
        case "dart": return .dart
        case "java": return .java
        case "kotlin", "kt", "kts": return .kotlin
        case "php", "phtml", "php8": return .php
        case "ruby", "rb": return .ruby
        case "shell", "sh", "bash", "zsh", "fish": return .shell
        case "sql", "pgsql", "mysql", "sqlite", "plsql": return .sql
        case "html", "htm", "xml", "svg", "xhtml", "vue", "svelte": return .html
        case "css", "scss", "sass", "less": return .css
        case "json", "jsonc": return .json
        case "yaml", "yml", "toml", "ini", "conf", "config", "env": return .yaml
        case "markdown", "md", "mdown", "mkd": return .markdown
        case "lua": return .lua
        case "zig": return .zig
        case "r": return .r
        case "julia", "jl": return .julia
        case "elixir", "ex", "exs": return .elixir
        case "solidity", "sol": return .solidity
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
