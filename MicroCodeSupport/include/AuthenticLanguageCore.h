#import <Foundation/Foundation.h>
#import "AuthenticSyntaxEngine.h"

@class AuthenticAIContext;

/**
 * AuthenticLanguageCore
 *
 * The Central Nervous System for the CodeTunner IDE.
 *
 * Philosophy: "Smart by Design"
 * - The Engine is the single source of truth.
 * - The Editor is just a renderer of the Engine's state.
 * - The AI is a client/plugin of the Engine, querying it for semantic context.
 *
 * Capabilities:
 * - High-speed Tokenization (Syntax Highlighting)
 * - Lightweight Semantic Parsing (Symbol Graph)
 * - Diagnostic Management (LSP + Compiler Wrapper)
 * - AI Code Context Provider
 */
@interface AuthenticLanguageCore : NSObject

/// Shared singleton for global context (if applicable)
+ (instancetype)shared;

/// Initialize with a specific language (e.g., "swift", "cpp", "python")
- (instancetype)initWithLanguage:(NSString *)language;

/// Update the engine with new source code.
/// This triggers incremental re-tokenization and semantic parsing.
- (void)updateSource:(NSString *)source;

// MARK: - Syntax Layer (The Eyes)

/// Get current syntax tokens for highlighting
- (NSArray<AuthenticToken *> *)tokens;

// MARK: - Semantic Layer (The Brain)

/// Returns the "AI Context" for a specific cursor position.
/// This includes the current function, variable scope, and relevant type definitions.
/// Used by HealerAgent, Copilot, and RefactorPro.
- (AuthenticAIContext *)contextForLine:(NSInteger)line column:(NSInteger)column;

/// Convenience accessor for current context (defaults to last cursor or top)
- (AuthenticAIContext *)aiContext;

/// Get a list of all symbols (classes, functions, variables) in the file.
- (NSArray<NSString *> *)symbols;

// MARK: - Diagnostics Layer (The Immune System)

/// Current diagnostics (errors, warnings) derived from LSP or local checks.
@property (nonatomic, readonly) NSArray<NSDictionary *> *diagnostics;

@end
