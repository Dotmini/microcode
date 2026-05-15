#import "AuthenticAIContext.h"

@implementation AuthenticAIContext

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentFunctionSignature = @"";
        _scopeVariables = @[];
        _enclosingType = @"";
        _imports = @[];
    }
    return self;
}

- (NSString *)llmContextDescription {
    NSMutableString *desc = [NSMutableString string];
    
    if (self.currentFunctionSignature.length > 0) {
        [desc appendFormat:@"User is editing inside function:\n`%@`\n\n", self.currentFunctionSignature];
    } else {
        [desc appendString:@"User is at global scope.\n\n"];
    }
    
    if (self.enclosingType.length > 0) {
        [desc appendFormat:@"Enclosing Type: %@\n", self.enclosingType];
    }
    
    if (self.scopeVariables.count > 0) {
        [desc appendString:@"Visible Variables:\n"];
        for (NSString *var in self.scopeVariables) {
            [desc appendFormat:@"- %@\n", var];
        }
        [desc appendString:@"\n"];
    }
    
    if (self.imports.count > 0) {
        [desc appendFormat:@"Imports: %@\n", [self.imports componentsJoinedByString:@", "]];
    }
    
    return [desc copy];
}

@end
