//
//  AuthenticLexerAdapter.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2026 AIPRENEUR. All rights reserved.
//

import Foundation
import MicroCodeSupport

/// Adapts the Objective-C++ AuthenticSyntaxEngine to the Swift LexerProtocol
public final class AuthenticLexerAdapter: LexerProtocol, @unchecked Sendable {
    public let languageId: String
    
    public init(languageId: String) {
        self.languageId = languageId
    }
    
    public func tokenize(_ source: String) -> SyntaxTokenStream {
        // Call into Objective-C++ engine
        let rawTokens = AuthenticSyntaxEngine.tokenizeSource(source, language: languageId)
        
        var syntaxTokens: [SyntaxToken] = []
        
        // Convert authentic tokens to Swift tokens
        for rawToken in rawTokens {
            guard let token = rawToken as? AuthenticToken else { continue }
            
            let type = mapTokenType(token.type)
            
            // Map range
            // Note: AuthenticToken range is NSRange (flat). SyntaxToken needs Line/Column.
            // Calculating line/column for every token here is expensive.
            // Ideally AuthenticSyntaxEngine returns a structure with line info or we calculate it efficiently.
            // For now, we perform a calculation based on the source string.
            // OPTIMIZATION: This should be done in C++ side in the future.
            
            // TODO: Optimize range calculation. Currently calculating on the fly which is slow for large docs.
            let range = calculateRange(for: token.range, in: source)
            
            let syntaxToken = SyntaxToken(
                type: type,
                text: token.content,
                range: range,
                endState: .normal // ObjC++ engine manages state internally for full document
            )
            syntaxTokens.append(syntaxToken)
        }
        
        return SyntaxTokenStream(tokens: syntaxTokens)
    }
    
    public func tokenizeLine(_ line: String, lineNumber: Int, startState: SyntaxLexerState, startOffset: Int) -> (tokens: [SyntaxToken], endState: SyntaxLexerState) {
        // Call into Objective-C++ engine for single line
        // State mapping: generic integer state
        let objcStartState = 0 // Map startState to int if needed
        var objcEndState: Int = 0
        
        let rawTokens = AuthenticSyntaxEngine.tokenizeLine(line, language: languageId, startState: objcStartState, endState: &objcEndState)
        
        var syntaxTokens: [SyntaxToken] = []
        for rawToken in rawTokens {
            guard let token = rawToken as? AuthenticToken else { continue }
            
            let type = mapTokenType(token.type)
            // Local range within the line
            let startCol = token.range.location
            let endCol = token.range.location + token.range.length
            
            let range = SyntaxTextRange(
                startLine: lineNumber,
                startColumn: startCol,
                endLine: lineNumber,
                endColumn: endCol,
                startOffset: startOffset + startCol,
                endOffset: startOffset + endCol
            )
            
            let syntaxToken = SyntaxToken(
                type: type,
                text: token.content,
                range: range,
                endState: .normal 
            )
            syntaxTokens.append(syntaxToken)
        }
        
        return (syntaxTokens, .normal) // TODO: Map objcEndState back to SyntaxLexerState enum
    }
    
    private func mapTokenType(_ type: AuthenticTokenType) -> SyntaxTokenType {
        switch type {
        case .keyword: return .keyword
        case .string: return .string
        case .number: return .number
        case .comment: return .comment
        case .type: return .type
        case .function: return .function
        case .operator: return .operator
        case .punctuation: return .punctuation
        case .preprocessor: return .preprocessor
        default: return .identifier // Unknown or just text
        }
    }
    
    private func calculateRange(for nsRange: NSRange, in source: String) -> SyntaxTextRange {
        // Slow fallback for full document tokenization
        // In reality, line/column should be provided by the lexer.
        // For MVP, we assume flat highlighting or simplified 
        return SyntaxTextRange(startLine: 0, startColumn: 0, endLine: 0, endColumn: 0, startOffset: nsRange.location, endOffset: nsRange.location + nsRange.length)
    }
}
