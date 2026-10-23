//
//  AuthenticSyntaxEngine.mm
//  CodeTunner
//
//  Created by Tirawat Nantamas
//  Copyright © 2026 Dotmini Company Limited. All rights reserved.
//

#import "AuthenticSyntaxEngine.h"
#include <string>
#include <vector>
#include <unordered_set>
#include <unordered_map>
#include <iostream>
#include <exception>

// MARK: - AuthenticToken Implementation

@implementation AuthenticToken
+ (instancetype)tokenWithType:(AuthenticTokenType)type range:(NSRange)range content:(NSString *)content {
    AuthenticToken *token = [[AuthenticToken alloc] init];
    token.type = type;
    token.range = range;
    token.content = content;
    return token;
}
@end

// MARK: - C++ Core Lexer (Apple Silicon UMA Zero-Copy UTF-16 Engine)

namespace MicroLexer {

    struct Token {
        AuthenticTokenType type;
        NSUInteger start;
        NSUInteger length;
    };

    static inline bool isASCIIAlpha(unichar c) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    }

    static inline bool isASCIIDigit(unichar c) {
        return (c >= '0' && c <= '9');
    }

    static inline bool isASCIIAlnumOrUnderscore(unichar c) {
        return isASCIIAlpha(c) || isASCIIDigit(c) || c == '_';
    }

    static inline bool isUTF16Space(unichar c) {
        return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
    }

    static inline bool isASCIIPunct(unichar c) {
        return (c >= 33 && c <= 47) || (c >= 58 && c <= 64) ||
               (c >= 91 && c <= 96) || (c >= 123 && c <= 126);
    }

    class Engine {
    public:
        std::unordered_set<std::string> keywords;
        std::unordered_set<std::string> declarationKeywords;

        Engine() = default;

        explicit Engine(const std::string& lang) {
            if (lang == "swift") {
                keywords = {"if", "else", "return", "import", "extension", "guard", "switch", "case", "try", "catch", "throw", "throws", "async", "await", "do", "repeat", "while", "break", "continue", "defer", "init", "deinit", "subscript", "static", "class", "get", "set", "willSet", "didSet", "where", "in", "as", "is", "nil", "true", "false", "self", "Self", "super"};
                declarationKeywords = {"func", "var", "let", "class", "struct", "enum", "protocol", "public", "private", "fileprivate", "internal", "open", "typealias", "associatedtype", "actor", "macro", "nonisolated", "isolated"};
            } else if (lang == "python" || lang == "py") {
                keywords = {"return", "if", "else", "elif", "for", "while", "import", "from", "as", "try", "except", "pass", "None", "True", "False", "lambda", "with", "raise", "finally", "assert", "del", "global", "nonlocal", "yield", "break", "continue", "async", "await", "in", "is", "not", "and", "or"};
                declarationKeywords = {"def", "class"};
            } else if (lang == "r") {
                keywords = {"if", "else", "for", "while", "repeat", "break", "next", "return", "in", "function", "TRUE", "FALSE", "NULL", "NA", "NaN", "Inf", "library", "require", "source", "print", "cat"};
                declarationKeywords = {"function", "library", "require", "data.frame", "matrix", "list", "vector", "factor", "tibble"};
            } else if (lang == "rust" || lang == "rs") {
                keywords = {"if", "else", "return", "match", "loop", "while", "for", "in", "break", "continue", "unsafe", "async", "await", "move", "ref", "mut", "static", "const", "trait", "impl", "type", "crate", "mod", "pub", "use", "extern", "self", "super", "where", "dyn", "true", "false"};
                declarationKeywords = {"fn", "let", "struct", "enum", "union", "const", "static", "type", "trait", "impl"};
            } else if (lang == "go" || lang == "golang") {
                keywords = {"break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var"};
                declarationKeywords = {"func", "var", "const", "type", "package", "import", "struct", "interface"};
            } else if (lang == "javascript" || lang == "js" || lang == "typescript" || lang == "ts" || lang == "jsx" || lang == "tsx") {
                keywords = {"if", "else", "return", "for", "while", "do", "switch", "case", "default", "break", "continue", "try", "catch", "finally", "throw", "new", "this", "super", "import", "export", "from", "as", "await", "async", "yield", "void", "typeof", "instanceof", "delete", "in", "of", "null", "undefined", "true", "false", "NaN", "Infinity"};
                declarationKeywords = {"function", "var", "let", "const", "class", "enum", "interface", "type", "namespace", "module"};
            } else if (lang == "java") {
                keywords = {"if", "else", "return", "for", "while", "do", "switch", "case", "default", "break", "continue", "try", "catch", "finally", "throw", "new", "this", "super", "import", "package", "null", "true", "false", "synchronized", "volatile", "transient", "native", "strictfp"};
                declarationKeywords = {"class", "interface", "enum", "record", "extends", "implements", "public", "private", "protected", "static", "final", "abstract", "void", "int", "boolean", "char", "byte", "short", "long", "float", "double"};
            } else if (lang == "kotlin" || lang == "kt") {
                keywords = {"if", "else", "when", "for", "while", "do", "break", "continue", "return", "throw", "try", "catch", "finally", "package", "import", "this", "super", "null", "true", "false", "is", "in", "as", "fun", "val", "var"};
                declarationKeywords = {"class", "interface", "object", "enum", "annotation", "data", "sealed", "open", "final", "public", "private", "protected", "internal", "override", "abstract", "companion", "init", "constructor", "get", "set", "field", "it"};
            } else if (lang == "objective-c" || lang == "objc" || lang == "m" || lang == "objective-cpp" || lang == "objcpp" || lang == "mm") {
                keywords = {"if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "try", "catch", "throw", "finally", "import", "include", "YES", "NO", "nil", "NULL", "self", "super", "new", "alloc", "init", "copy", "retain", "release", "autorelease", "strong", "weak", "readonly", "readwrite", "nonatomic", "atomic", "assign", "getter", "setter"};
                declarationKeywords = {"@interface", "@implementation", "@end", "@protocol", "@property", "@synthesize", "@dynamic", "@class", "@selector", "@try", "@catch", "@finally", "@throw", "@synchronized", "@autoreleasepool", "int", "float", "double", "char", "void", "bool", "long", "short", "id", "instancetype", "BOOL", "NSInteger", "NSUInteger", "CGFloat", "NSString", "NSArray", "NSDictionary"};
            } else if (lang == "sql") {
                keywords = {"SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER", "TABLE", "INDEX", "VIEW", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "ON", "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT", "AS", "AND", "OR", "NOT", "NULL", "IS", "IN", "BETWEEN", "LIKE", "EXISTS", "CASE", "WHEN", "THEN", "ELSE", "END"};
                declarationKeywords = {"INT", "VARCHAR", "TEXT", "DATE", "DATETIME", "TIMESTAMP", "BOOLEAN", "FLOAT", "DECIMAL", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "DEFAULT", "UNIQUE"};
            } else if (lang == "ruby" || lang == "rb") {
                keywords = {"if", "else", "elsif", "unless", "return", "while", "until", "for", "in", "break", "next", "redo", "retry", "begin", "rescue", "ensure", "end", "case", "when", "then", "def", "class", "module", "self", "super", "yield", "alias", "and", "or", "not", "true", "false", "nil"};
                declarationKeywords = {"def", "class", "module", "attr_reader", "attr_writer", "attr_accessor"};
            } else if (lang == "julia" || lang == "jl") {
                keywords = {"if", "else", "elseif", "for", "while", "return", "break", "continue", "try", "catch", "finally", "throw", "import", "using", "export", "module", "baremodule", "quote", "do", "begin", "end", "true", "false", "nothing", "NaN", "Inf"};
                declarationKeywords = {"function", "macro", "struct", "mutable", "abstract", "primitive", "type", "const", "global", "local"};
            } else {
                keywords = {"return", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "goto", "try", "catch", "throw", "new", "delete", "using", "namespace", "include", "import", "define", "ifdef", "ifndef", "endif", "pragma", "nullptr", "true", "false"};
                declarationKeywords = {"int", "float", "double", "char", "void", "bool", "long", "short", "unsigned", "signed", "class", "struct", "union", "enum", "public", "private", "protected", "virtual", "friend", "static", "const", "mutable", "volatile", "register", "auto", "extern", "template", "typename", "typedef", "operator"};
            }
        }

        static const Engine& sharedEngineForLanguage(const std::string& lang) {
            static const std::unordered_map<std::string, Engine> cache = {
                {"swift", Engine("swift")},
                {"python", Engine("python")},
                {"py", Engine("py")},
                {"r", Engine("r")},
                {"rust", Engine("rust")},
                {"rs", Engine("rs")},
                {"go", Engine("go")},
                {"golang", Engine("golang")},
                {"javascript", Engine("javascript")},
                {"js", Engine("js")},
                {"typescript", Engine("typescript")},
                {"ts", Engine("ts")},
                {"jsx", Engine("jsx")},
                {"tsx", Engine("tsx")},
                {"java", Engine("java")},
                {"kotlin", Engine("kotlin")},
                {"kt", Engine("kt")},
                {"objective-c", Engine("objective-c")},
                {"objc", Engine("objc")},
                {"m", Engine("m")},
                {"objective-cpp", Engine("objective-cpp")},
                {"objcpp", Engine("objcpp")},
                {"mm", Engine("mm")},
                {"sql", Engine("sql")},
                {"ruby", Engine("ruby")},
                {"rb", Engine("rb")},
                {"julia", Engine("julia")},
                {"jl", Engine("jl")},
                {"c", Engine("c")},
                {"cpp", Engine("cpp")}
            };
            auto it = cache.find(lang);
            if (it != cache.end()) {
                return it->second;
            }
            static const Engine defaultEngine("c");
            return defaultEngine;
        }

        std::vector<Token> tokenizeUTF16(const unichar *source, NSUInteger len) const {
            std::vector<Token> tokens;
            tokens.reserve(len / 5);
            NSUInteger i = 0;
            std::string wordBuffer;
            wordBuffer.reserve(64);

            while (i < len) {
                unichar c = source[i];

                // Whitespace
                if (isUTF16Space(c)) {
                    i++;
                    continue;
                }

                // Strings
                if (c == '"' || c == '\'') {
                    NSUInteger start = i;
                    unichar quote = c;
                    i++;
                    while (i < len && source[i] != quote) {
                        if (source[i] == '\\' && i + 1 < len) i++;
                        i++;
                    }
                    if (i < len) i++;
                    tokens.push_back({AuthenticTokenTypeString, start, i - start});
                    continue;
                }

                // Line comments //
                if (c == '/' && i + 1 < len && source[i + 1] == '/') {
                    NSUInteger start = i;
                    i += 2;
                    while (i < len && source[i] != '\n') {
                        i++;
                    }
                    tokens.push_back({AuthenticTokenTypeComment, start, i - start});
                    continue;
                }

                // Block comments /* ... */
                if (c == '/' && i + 1 < len && source[i + 1] == '*') {
                    NSUInteger start = i;
                    i += 2;
                    while (i + 1 < len && !(source[i] == '*' && source[i + 1] == '/')) {
                        i++;
                    }
                    if (i + 1 < len) {
                        i += 2;
                    } else {
                        i = len;
                    }
                    tokens.push_back({AuthenticTokenTypeComment, start, i - start});
                    continue;
                }

                // Line comments #
                if (c == '#') {
                    NSUInteger start = i;
                    while (i < len && source[i] != '\n') {
                        i++;
                    }
                    tokens.push_back({AuthenticTokenTypeComment, start, i - start});
                    continue;
                }

                // Numbers
                if (isASCIIDigit(c)) {
                    NSUInteger start = i;
                    while (i < len && (isASCIIDigit(source[i]) || source[i] == '.' || source[i] == '_' || source[i] == 'x' || source[i] == 'X')) {
                        i++;
                    }
                    tokens.push_back({AuthenticTokenTypeNumber, start, i - start});
                    continue;
                }

                // Identifiers / Keywords (including @attributes in ObjC/Swift)
                if (isASCIIAlpha(c) || c == '_' || (c == '@' && i + 1 < len && isASCIIAlpha(source[i + 1]))) {
                    NSUInteger start = i;
                    wordBuffer.clear();
                    wordBuffer.push_back(static_cast<char>(c));
                    i++;
                    while (i < len && isASCIIAlnumOrUnderscore(source[i])) {
                        if (wordBuffer.size() < 64) {
                            wordBuffer.push_back(static_cast<char>(source[i]));
                        }
                        i++;
                    }

                    if (declarationKeywords.count(wordBuffer)) {
                        tokens.push_back({AuthenticTokenTypeKeywordDeclaration, start, i - start});
                    } else if (keywords.count(wordBuffer)) {
                        tokens.push_back({AuthenticTokenTypeKeyword, start, i - start});
                    } else if (c >= 'A' && c <= 'Z') {
                        tokens.push_back({AuthenticTokenTypeType, start, i - start});
                    } else {
                        NSUInteger nextC = i;
                        while (nextC < len && isUTF16Space(source[nextC])) nextC++;
                        if (nextC < len && source[nextC] == '(') {
                            tokens.push_back({AuthenticTokenTypeFunction, start, i - start});
                        } else {
                            tokens.push_back({AuthenticTokenTypeIdentifier, start, i - start});
                        }
                    }
                    continue;
                }

                // Operators / Punctuation
                if (isASCIIPunct(c)) {
                    tokens.push_back({AuthenticTokenTypePunctuation, i, 1});
                    i++;
                    continue;
                }

                i++;
            }
            return tokens;
        }
    };
}

// MARK: - AuthenticSyntaxEngine Implementation

@implementation AuthenticSyntaxEngine

+ (NSArray<AuthenticToken *> *)tokenizeSource:(NSString *)source language:(NSString *)language {
    if (!source) return @[];
    NSUInteger sourceLength = source.length;
    if (sourceLength == 0) return @[];

    const char *utf8Lang = language ? [language UTF8String] : nullptr;
    std::string cppLang = utf8Lang ? std::string(utf8Lang) : "c";

    try {
        const MicroLexer::Engine& engine = MicroLexer::Engine::sharedEngineForLanguage(cppLang);

        // Zero-Copy UMA fast path: read directly from CFString's internal UTF-16 buffer when contiguous
        const unichar *directChars = CFStringGetCharactersPtr((__bridge CFStringRef)source);
        std::vector<unichar> fallbackBuffer;
        const unichar *charsPtr = directChars;
        if (!charsPtr) {
            fallbackBuffer.resize(sourceLength);
            [source getCharacters:fallbackBuffer.data() range:NSMakeRange(0, sourceLength)];
            charsPtr = fallbackBuffer.data();
        }

        std::vector<MicroLexer::Token> cppTokens = engine.tokenizeUTF16(charsPtr, sourceLength);
        NSMutableArray<AuthenticToken *> *result = [NSMutableArray arrayWithCapacity:cppTokens.size()];

        for (const auto& t : cppTokens) {
            if (t.start >= sourceLength || t.length == 0) continue;
            NSUInteger len = (t.start + t.length <= sourceLength) ? t.length : (sourceLength - t.start);
            [result addObject:[AuthenticToken tokenWithType:t.type range:NSMakeRange(t.start, len) content:@""]];
        }

        return result;
    } catch (const std::exception& e) {
        NSLog(@"[AuthenticSyntaxEngine] C++ Exception: %s", e.what());
        return @[];
    } catch (...) {
        NSLog(@"[AuthenticSyntaxEngine] Unknown C++ Exception");
        return @[];
    }
}

+ (NSArray<AuthenticToken *> *)tokenizeLine:(NSString *)line language:(NSString *)language startState:(NSInteger)startState endState:(NSInteger *)endState {
    // TODO: Implement state-aware line tokenization for scroll perf
    return [self tokenizeSource:line language:language];
}

@end
