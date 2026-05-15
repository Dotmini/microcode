//
//  CodeAnalyzer.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import Foundation

struct CodeMetrics: Codable {
    let complexity: Int
    let linesOfCode: Int
    let functions: Int
    let classes: Int
    let codeSmells: [CodeSmell]
}

struct CodeSmell: Codable, Identifiable {
    let id = UUID()
    let type: String
    let line: Int
    let message: String
    let severity: String
    
    enum CodingKeys: String, CodingKey {
        case type, line, message, severity
    }
}

class CodeAnalyzer {
    static let shared = CodeAnalyzer()
    
    private init() {}
    
    // MARK: - Complexity Analysis
    
    func analyzeComplexity(code: String, language: String) -> CodeMetrics {
        let lines = code.components(separatedBy: .newlines)
        let linesOfCode = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        
        // Simple metrics - in production, use proper AST parsing
        let complexity = calculateCyclomaticComplexity(code: code, language: language)
        let functions = countFunctions(code: code, language: language)
        let classes = countClasses(code: code, language: language)
        let codeSmells = detectCodeSmells(code: code, language: language)
        
        return CodeMetrics(
            complexity: complexity,
            linesOfCode: linesOfCode,
            functions: functions,
            classes: classes,
            codeSmells: codeSmells
        )
    }
    
    /// Async version running on E-Core to avoid blocking UI.
    /// Use this for large files or real-time analysis.
    func analyzeComplexityAsync(code: String, language: String) async -> CodeMetrics {
        await PerformanceManager.shared.runOnECore { [self] in
            analyzeComplexity(code: code, language: language)
        }
    }
    
    private func calculateCyclomaticComplexity(code: String, language: String) -> Int {
        var complexity = 1 // Base complexity
        
        let controlFlowKeywords: [String]
        
        switch language.lowercased() {
        case "swift", "objc":
            controlFlowKeywords = ["if", "else", "for", "while", "case", "catch", "guard", "??"]
        case "python":
            controlFlowKeywords = ["if", "elif", "else", "for", "while", "except", "and", "or"]
        case "javascript", "typescript":
            controlFlowKeywords = ["if", "else", "for", "while", "case", "catch", "&&", "||", "?"]
        default:
            controlFlowKeywords = ["if", "else", "for", "while", "case", "catch"]
        }
        
        let lines = code.components(separatedBy: .newlines)
        for line in lines {
            for keyword in controlFlowKeywords {
                if line.contains(keyword) {
                    complexity += 1
                }
            }
        }
        
        return complexity
    }
    
    private func countFunctions(code: String, language: String) -> Int {
        var count = 0
        let lines = code.components(separatedBy: .newlines)
        
        for line in lines {
            switch language.lowercased() {
            case "swift":
                if line.contains("func ") {
                    count += 1
                }
            case "python":
                if line.contains("def ") {
                    count += 1
                }
            case "javascript", "typescript":
                if line.contains("function ") || line.contains("const ") && line.contains("=>") {
                    count += 1
                }
            default:
                if line.contains("function") || line.contains("def") || line.contains("func") {
                    count += 1
                }
            }
        }
        
        return count
    }
    
    private func countClasses(code: String, language: String) -> Int {
        var count = 0
        let lines = code.components(separatedBy: .newlines)
        
        for line in lines {
            if line.contains("class ") || line.contains("struct ") {
                count += 1
            }
        }
        
        return count
    }
    
    private func detectCodeSmells(code: String, language: String) -> [CodeSmell] {
        var smells: [CodeSmell] = []
        let lines = code.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Long line
            if line.count > 120 {
                smells.append(CodeSmell(
                    type: "Long Line",
                    line: lineNumber,
                    message: "Line exceeds 120 characters",
                    severity: "warning"
                ))
            }
            
            // TODO comments
            if trimmed.contains("TODO") || trimmed.contains("FIXME") {
                smells.append(CodeSmell(
                    type: "TODO/FIXME",
                    line: lineNumber,
                    message: "Unresolved TODO or FIXME comment",
                    severity: "info"
                ))
            }
            
            // Magic numbers
            let magicNumberRegex = try? NSRegularExpression(pattern: "\\b\\d{3,}\\b")
            if let matches = magicNumberRegex?.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               !matches.isEmpty {
                smells.append(CodeSmell(
                    type: "Magic Number",
                    line: lineNumber,
                    message: "Consider extracting magic number to constant",
                    severity: "warning"
                ))
            }
            
            // Deep nesting (4+ levels)
            let indentLevel = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            if indentLevel > 16 {
                smells.append(CodeSmell(
                    type: "Deep Nesting",
                    line: lineNumber,
                    message: "Deep nesting detected - consider refactoring",
                    severity: "warning"
                ))
            }
        }
        
        return smells
    }
}
