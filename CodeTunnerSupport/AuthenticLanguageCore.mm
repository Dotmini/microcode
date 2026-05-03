#import "AuthenticLanguageCore.h"
#import "AuthenticAIContext.h"
#import "AuthenticSyntaxEngine.h"

#include <string>
#include <vector>
#include <unordered_map>
#include <iostream>
#include <stack>

// MARK: - MicroParser (C++)
// A lightweight, fault-tolerant parser to extract structure from tokens.

namespace MicroParser {

    struct Symbol {
        std::string name;
        std::string type; // "function", "class", "variable"
        std::string signature;
        NSInteger line;
    };

    struct Scope {
        std::string name; // Function or Class name
        std::string type;
        NSInteger startLine;
        NSInteger endLine;
        std::vector<Symbol> variables;
    };

    class Engine {
    public:
        std::vector<Scope> scopes;
        std::vector<std::string> imports;
        
        Engine() {}
        
        void parse(NSArray<AuthenticToken *> *tokens, NSString *language) {
            scopes.clear();
            imports.clear();
            
            // Basic global scope
            scopes.push_back({"Global", "global", 0, NSIntegerMax, {}});
            
            std::string lang = [language UTF8String];
            bool isSwift = (lang == "swift");
            bool isCpp = (lang == "cpp" || lang == "c" || lang == "objectivec");
            
            std::stack<size_t> scopeStack;
            scopeStack.push(0); // Index of global scope
            
            for (NSInteger i = 0; i < tokens.count; i++) {
                AuthenticToken *t = tokens[i];
                std::string text = [t.content UTF8String];
                
                // 1. Detect Functions (Very naive for now, but fast)
                if (t.type == AuthenticTokenTypeKeywordDeclaration) {
                    if ((isSwift && text == "func") || (isCpp && (text == "void" || text == "int"))) {
                        // Look ahead for name
                        if (i + 1 < tokens.count) {
                            AuthenticToken *nameToken = tokens[i+1];
                            if (nameToken.type == AuthenticTokenTypeIdentifier || nameToken.type == AuthenticTokenTypeFunction) {
                                std::string funcName = [nameToken.content UTF8String];
                                
                                // Create new scope
                                Scope funcScope;
                                funcScope.name = funcName;
                                funcScope.type = "function";
                                funcScope.startLine = t.range.location; // Approximation
                                funcScope.endLine = NSIntegerMax;
                                
                                scopes.push_back(funcScope);
                                // Note: Real parser would push to stack only on '{'
                            }
                        }
                    }
                }
                
                // 2. Detect Variables
                if (t.type == AuthenticTokenTypeKeywordDeclaration) { // var, let, auto
                     if ((isSwift && (text == "var" || text == "let")) || (isCpp && text == "auto")) {
                         if (i + 1 < tokens.count) {
                             AuthenticToken *nameToken = tokens[i+1];
                             if (nameToken.type == AuthenticTokenTypeIdentifier) {
                                  Symbol varSym;
                                  varSym.name = [nameToken.content UTF8String];
                                  varSym.type = "variable";
                                  varSym.line = t.range.location; // line-ish
                                  
                                  // Add to current scope (top of stack)
                                  if (!scopeStack.empty()) {
                                      scopes[scopeStack.top()].variables.push_back(varSym);
                                  }
                             }
                         }
                     }
                }
                
                // 3. Detect Imports
                if (t.type == AuthenticTokenTypeKeyword) {
                    if (text == "import" || text == "#include") {
                        if (i + 1 < tokens.count) {
                             imports.push_back([tokens[i+1].content UTF8String]);
                        }
                    }
                }
                
                // 4. Bracket Scope Management (Crucial for "Am I in function X?")
                if (text == "{") {
                    // In a real parser, we'd link this '{' to the recently declared function
                    // For now, if we just saw a func declaration, we assume this opens it.
                    // This is "heuristic parsing".
                    if (scopes.size() > 1 && scopes.back().startLine < (NSInteger)t.range.location + 50 /* locality */) {
                         // Assume this brace belongs to the last detected symbol scope
                         scopeStack.push(scopes.size() - 1);
                    } else {
                         // Anonymous scope
                         Scope anon;
                         anon.name = "Anonymous";
                         anon.type = "block";
                         anon.startLine = t.range.location;
                         scopes.push_back(anon);
                         scopeStack.push(scopes.size() - 1);
                    }
                } else if (text == "}") {
                    if (scopeStack.size() > 1) { // Don't pop global
                        size_t endingScopeIdx = scopeStack.top();
                        scopes[endingScopeIdx].endLine = t.range.location + t.range.length;
                        scopeStack.pop();
                    }
                }
            }
        }
        
        // Query
        Scope* findScopeAt(NSInteger line) {
            // Find the most specific scope (deepest) that contains this line
            Scope* bestMatch = &scopes[0]; // Global
            
            for (size_t i = 1; i < scopes.size(); i++) {
                // Determine 'line' from range location (very rough approx, needs real line mapping)
                // Assuming range.location is character index. We need line index.
                // TODO: Fix line mapping. For now, we assume simple character index check if possible, or we need line map.
                // Wait, the Tokenizer gives us Ranges (char indices).
                // The input 'line' is a line number.
                // We need to know which char indices correspond to 'line'.
                // AuthenticLanguageCore should manage Line <-> Char Index map.
            }
            return bestMatch; 
        }
    };
}


@interface AuthenticLanguageCore ()
@property (nonatomic, strong) NSString *currentLanguage;
@property (nonatomic, strong) NSArray<AuthenticToken *> *currentTokens;
@property (nonatomic, strong) NSString *sourceCode;
@property (nonatomic, assign) MicroParser::Engine *parser;
@end

@implementation AuthenticLanguageCore

+ (instancetype)shared {
    static AuthenticLanguageCore *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[AuthenticLanguageCore alloc] initWithLanguage:@"swift"];
    });
    return sharedInstance;
}

- (AuthenticAIContext *)aiContext {
    if (!_sourceCode || _sourceCode.length == 0) {
        return [[AuthenticAIContext alloc] init];
    }
    return [self contextForLine:0 column:0];
}

- (instancetype)initWithLanguage:(NSString *)language {
    self = [super init];
    if (self) {
        _currentLanguage = [language copy];
        _currentTokens = @[];
        _parser = new MicroParser::Engine();
    }
    return self;
}

- (void)dealloc {
    delete _parser;
}

- (void)updateSource:(NSString *)source {
    _sourceCode = [source copy];
    
    // 1. Tokenize (Syntax)
    _currentTokens = [AuthenticSyntaxEngine tokenizeSource:source language:_currentLanguage];
    
    // 2. Parse (Semantics)
    // Note: This runs on the calling thread. For large files, should use GCD.
    _parser->parse(_currentTokens, _currentLanguage);
}

- (NSArray<AuthenticToken *> *)tokens {
    return _currentTokens;
}

- (AuthenticAIContext *)contextForLine:(NSInteger)line column:(NSInteger)column {
    AuthenticAIContext *ctx = [[AuthenticAIContext alloc] init];
    
    // Convert Line/Col to Char Index (Need a helper for this)
    NSRange lineRange = [self rangeForLine:line];
    if (lineRange.location == NSNotFound) {
        return ctx;
    }
    NSUInteger charIndex = lineRange.location + column;
    
    // 1. Find Scope
    // Iterate parsed scopes to find the deepest one wrapping charIndex
    if (_parser->scopes.empty()) {
        return ctx;
    }
    MicroParser::Scope *foundScope = &_parser->scopes[0]; // Global
    
    // Heuristic: Find last declared scope started BEFORE this charIndex and NOT ended
    for (const auto& scope : _parser->scopes) {
        if (scope.type == "function" || scope.type == "class") {
            // Check start (approx via startLine which is actually char index in my parser)
             if ((NSUInteger)scope.startLine <= charIndex && (NSUInteger)scope.endLine >= charIndex) {
                 foundScope = (MicroParser::Scope*)&scope;
             }
        }
    }
    
    if (foundScope->name != "Global") {
        ctx.currentFunctionSignature = [NSString stringWithUTF8String:foundScope->name.c_str()];
        ctx.enclosingType = [NSString stringWithUTF8String:foundScope->type.c_str()]; // e.g. "function"
    }
    
    // 2. Variables
    NSMutableArray *vars = [NSMutableArray array];
    for (const auto& v : foundScope->variables) {
        [vars addObject:[NSString stringWithUTF8String:v.name.c_str()]];
    }
    ctx.scopeVariables = [vars copy];
    
    // 3. Imports
    NSMutableArray *imps = [NSMutableArray array];
    for (const auto& imp : _parser->imports) {
        [imps addObject:[NSString stringWithUTF8String:imp.c_str()]];
    }
    ctx.imports = [imps copy];
    
    return ctx;
}

- (NSArray<NSString *> *)symbols {
    NSMutableArray *syms = [NSMutableArray array];
    for (const auto& scope : _parser->scopes) {
        if (scope.name != "Global" && scope.name != "Anonymous") {
             [syms addObject:[NSString stringWithUTF8String:scope.name.c_str()]];
        }
    }
    return syms;
}

- (NSArray<NSDictionary *> *)diagnostics {
    return @[]; // TODO: Integrate LSP diagnostics
}

// Helper: Naive O(N) line finder. In production, cache this.
- (NSRange)rangeForLine:(NSInteger)line {
    if (!_sourceCode || _sourceCode.length == 0) {
        return NSMakeRange(NSNotFound, 0);
    }
    NSUInteger numberOfLines, index, stringLength = [_sourceCode length];
    for (index = 0, numberOfLines = 0; index < stringLength; numberOfLines++) {
        NSRange range = [_sourceCode lineRangeForRange:NSMakeRange(index, 0)];
        if (numberOfLines == line) {
            return range;
        }
        index = NSMaxRange(range);
    }
    return NSMakeRange(NSNotFound, 0);
}

@end
