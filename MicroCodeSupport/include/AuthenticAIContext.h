#import <Foundation/Foundation.h>

/**
 * AuthenticAIContext
 *
 * Represents the "Semantic Situation" of the user.
 * Passed to AI Agents (Healer, Refactor) to give them deep understanding without hallucination.
 */
@interface AuthenticAIContext : NSObject

/// The code signature of the function/method the cursor is currently inside.
/// Example: "func calculateTotal(items: [Item]) -> Double"
@property (nonatomic, copy) NSString *currentFunctionSignature;

/// List of variables visible in the current scope.
/// Example: ["items: [Item]", "taxRate: Double"]
@property (nonatomic, copy) NSArray<NSString *> *scopeVariables;

/// The class or struct name the cursor is inside.
@property (nonatomic, copy) NSString *enclosingType;

/// Relevant imports/includes that determine available types.
@property (nonatomic, copy) NSArray<NSString *> *imports;

/// A summary string optimized for LLM prompting.
/// Example: "Inside function 'foo', accessing vars [x, y]. Context: Class 'Bar'."
- (NSString *)llmContextDescription;

@end
