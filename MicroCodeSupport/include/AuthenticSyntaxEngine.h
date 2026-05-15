//
//  AuthenticSyntaxEngine.h
//  CodeTunner
//
//  Created by SPU AI CLUB
//  Copyright © 2026 AIPRENEUR. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Token Type Enum
typedef NS_ENUM(NSInteger, AuthenticTokenType) {
    AuthenticTokenTypeUnknown = 0,
    AuthenticTokenTypeKeyword,
    AuthenticTokenTypeKeywordDeclaration,
    AuthenticTokenTypeIdentifier,
    AuthenticTokenTypeString,
    AuthenticTokenTypeNumber,
    AuthenticTokenTypeComment,
    AuthenticTokenTypeType,
    AuthenticTokenTypeFunction,
    AuthenticTokenTypeOperator,
    AuthenticTokenTypePunctuation,
    AuthenticTokenTypePreprocessor,
    AuthenticTokenTypeURL,
    AuthenticTokenTypeKeywordControl,
    AuthenticTokenTypeKeywordModifier
};

// Lightweight Token Object
@interface AuthenticToken : NSObject

@property (nonatomic, assign) AuthenticTokenType type;
@property (nonatomic, assign) NSRange range;
@property (nonatomic, copy) NSString *content;

+ (instancetype)tokenWithType:(AuthenticTokenType)type range:(NSRange)range content:(NSString *)content;

@end

// Syntax Engine Class
@interface AuthenticSyntaxEngine : NSObject

/// Tokenize the entire source code for a specific language
+ (NSArray<AuthenticToken *> *)tokenizeSource:(NSString *)source language:(NSString *)language;

/// Tokenize a single line (optimized for editor updates)
+ (NSArray<AuthenticToken *> *)tokenizeLine:(NSString *)line language:(NSString *)language startState:(NSInteger)startState endState:(NSInteger *)endState;

@end

NS_ASSUME_NONNULL_END
