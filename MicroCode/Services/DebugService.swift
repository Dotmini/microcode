// Copyright © 2025 Dotmini Software. All rights reserved.

import Foundation
import SwiftUI
import Combine

enum ErrorStatus: String, Codable, Equatable {
    case new
    case analyzing
    case explained
    case fixed
    case dismissed
}

struct StackFrame: Identifiable, Equatable {
    let id = UUID()
    let functionName: String
    let filePath: String?
    let lineNumber: Int?
    let columnNumber: Int?
    let isUserCode: Bool
    
    static func == (lhs: StackFrame, rhs: StackFrame) -> Bool {
        lhs.id == rhs.id
    }
}

struct SuggestedFix: Equatable {
    let description: String
    let filePath: String
    let oldCode: String
    let newCode: String
    let confidence: Double
}

struct RuntimeError: Identifiable, Equatable {
    let id: UUID
    let language: String
    let errorType: String
    let message: String
    let stackTrace: [StackFrame]
    let rawOutput: String
    let timestamp: Date
    var aiExplanation: String?
    var suggestedFix: SuggestedFix?
    var status: ErrorStatus
    
    init(id: UUID = UUID(), language: String, errorType: String, message: String, stackTrace: [StackFrame], rawOutput: String, timestamp: Date = Date(), aiExplanation: String? = nil, suggestedFix: SuggestedFix? = nil, status: ErrorStatus = .new) {
        self.id = id
        self.language = language
        self.errorType = errorType
        self.message = message
        self.stackTrace = stackTrace
        self.rawOutput = rawOutput
        self.timestamp = timestamp
        self.aiExplanation = aiExplanation
        self.suggestedFix = suggestedFix
        self.status = status
    }
    
    static func == (lhs: RuntimeError, rhs: RuntimeError) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
    }
}

@MainActor
class DebugService: ObservableObject {
    static let shared = DebugService()
    
    @Published var errors: [RuntimeError] = []
    @Published var currentError: RuntimeError?
    @Published var isAnalyzing: Bool = false
    
    private init() {}
    
    func parseErrorOutput(_ output: String, language: String) -> RuntimeError? {
        let lines = output.components(separatedBy: .newlines)
        
        switch language.lowercased() {
        case "python":
            return parsePythonError(output, lines: lines)
        case "javascript", "typescript", "node":
            return parseNodeError(output, lines: lines)
        case "rust":
            return parseRustError(output, lines: lines)
        case "swift":
            return parseSwiftError(output, lines: lines)
        case "go":
            return parseGoError(output, lines: lines)
        case "java":
            return parseJavaError(output, lines: lines)
        default:
            return parseGenericError(output, lines: lines, language: language)
        }
    }
    
    func analyzeError(_ error: RuntimeError) async {
        guard let index = errors.firstIndex(where: { $0.id == error.id }) else { return }
        
        isAnalyzing = true
        errors[index].status = .analyzing
        if currentError?.id == error.id {
            currentError?.status = .analyzing
        }
        
        let prompt = """
        Analyze this \(error.language) runtime error.
        
        Error Type: \(error.errorType)
        Message: \(error.message)
        
        Stack Trace:
        \(error.stackTrace.map { "\($0.functionName) at \($0.filePath ?? "unknown"):\($0.lineNumber ?? 0)" }.joined(separator: "\n"))
        
        Raw Output:
        \(error.rawOutput)
        
        Provide a plain-English explanation, identify the root cause, and return a JSON object with a 'fix' containing 'description', 'oldCode', 'newCode', 'filePath', and 'confidence' (0.0 to 1.0).
        """
        
        do {
            // Simplified for now assuming AIClient returns something like this
            let response = try await AIClient.shared.generateText(prompt: prompt)
            
            // Basic extraction (in a real scenario we'd use a better JSON parser out of the LLM response)
            let explanation = response
            
            errors[index].aiExplanation = explanation
            errors[index].status = .explained
            if currentError?.id == error.id {
                currentError?.aiExplanation = explanation
                currentError?.status = .explained
            }
        } catch let catchError {
            print("Error analyzing: \(catchError)")
            errors[index].status = .new
            if currentError?.id == error.id {
                currentError?.status = .new
            }
        }
        
        isAnalyzing = false
    }
    
    func applyFix(_ fix: SuggestedFix) async {
        // Implement applying the fix, possibly via AgentToolBox or PendingChangeModel
        print("Applying fix to \(fix.filePath)")
    }
    
    func dismissError(_ error: RuntimeError) {
        if let index = errors.firstIndex(where: { $0.id == error.id }) {
            errors[index].status = .dismissed
            if currentError?.id == error.id {
                currentError = nil
            }
        }
    }
    
    func clearAll() {
        errors.removeAll()
        currentError = nil
        isAnalyzing = false
    }
    
    // MARK: - Language Parsers
    
    private func parsePythonError(_ output: String, lines: [String]) -> RuntimeError? {
        guard output.contains("Traceback (most recent call last):") else { return nil }
        
        var stackTrace: [StackFrame] = []
        var errorType = "PythonError"
        var message = ""
        
        let fileRegex = try? NSRegularExpression(pattern: #"File "(.+)", line (\d+), in (.+)"#)
        
        for (i, line) in lines.enumerated() {
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = fileRegex?.firstMatch(in: line, range: nsRange) {
                if let fileRange = Range(match.range(at: 1), in: line),
                   let lineRange = Range(match.range(at: 2), in: line),
                   let funcRange = Range(match.range(at: 3), in: line) {
                    let file = String(line[fileRange])
                    let lineNum = Int(line[lineRange])
                    let funcName = String(line[funcRange])
                    
                    let isUserCode = !file.contains("/lib/python") && !file.contains("/site-packages/")
                    
                    stackTrace.append(StackFrame(functionName: funcName, filePath: file, lineNumber: lineNum, columnNumber: nil, isUserCode: isUserCode))
                }
            } else if !line.hasPrefix(" ") && i > 0 && line.contains(":") {
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    errorType = parts[0].trimmingCharacters(in: .whitespaces)
                    message = parts[1].trimmingCharacters(in: .whitespaces)
                } else {
                    message = line
                }
            }
        }
        
        return RuntimeError(language: "Python", errorType: errorType, message: message.isEmpty ? "Unknown python error" : message, stackTrace: stackTrace.reversed(), rawOutput: output)
    }
    
    private func parseNodeError(_ output: String, lines: [String]) -> RuntimeError? {
        guard output.contains("Error:") || output.contains("Exception:") || output.contains("TypeError:") || output.contains("ReferenceError:") else { return nil }
        
        var stackTrace: [StackFrame] = []
        var errorType = "NodeError"
        var message = ""
        
        let stackRegex = try? NSRegularExpression(pattern: #"at (.+) \((.+):(\d+):(\d+)\)"#)
        let stackRegexAlt = try? NSRegularExpression(pattern: #"at (.+):(\d+):(\d+)"#)
        
        var firstErrorFound = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !firstErrorFound && (trimmed.contains("Error:") || trimmed.hasSuffix("Error")) {
                let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    errorType = parts[0].trimmingCharacters(in: .whitespaces)
                    message = parts[1].trimmingCharacters(in: .whitespaces)
                } else {
                    message = trimmed
                }
                firstErrorFound = true
                continue
            }
            
            if trimmed.hasPrefix("at ") {
                let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
                if let match = stackRegex?.firstMatch(in: line, range: nsRange) {
                    if let funcRange = Range(match.range(at: 1), in: line),
                       let fileRange = Range(match.range(at: 2), in: line),
                       let lineRange = Range(match.range(at: 3), in: line),
                       let colRange = Range(match.range(at: 4), in: line) {
                        
                        let funcName = String(line[funcRange])
                        let file = String(line[fileRange])
                        let lineNum = Int(line[lineRange])
                        let colNum = Int(line[colRange])
                        let isUserCode = !file.contains("node_modules") && !file.contains("internal/")
                        
                        stackTrace.append(StackFrame(functionName: funcName, filePath: file, lineNumber: lineNum, columnNumber: colNum, isUserCode: isUserCode))
                    }
                } else if let match = stackRegexAlt?.firstMatch(in: line, range: nsRange) {
                    if let fileRange = Range(match.range(at: 1), in: line),
                       let lineRange = Range(match.range(at: 2), in: line),
                       let colRange = Range(match.range(at: 3), in: line) {
                        
                        let file = String(line[fileRange])
                        let lineNum = Int(line[lineRange])
                        let colNum = Int(line[colRange])
                        let isUserCode = !file.contains("node_modules") && !file.contains("internal/")
                        
                        stackTrace.append(StackFrame(functionName: "<anonymous>", filePath: file, lineNumber: lineNum, columnNumber: colNum, isUserCode: isUserCode))
                    }
                }
            }
        }
        
        return RuntimeError(language: "JavaScript/TypeScript", errorType: errorType, message: message, stackTrace: stackTrace, rawOutput: output)
    }
    
    private func parseRustError(_ output: String, lines: [String]) -> RuntimeError? {
        guard output.contains("error[E") || output.contains("error:") || output.contains("panicked at") else { return nil }
        
        var stackTrace: [StackFrame] = []
        var errorType = "RustError"
        var message = ""
        
        if output.contains("panicked at") {
            errorType = "Panic"
            if let panicRange = output.range(of: "panicked at") {
                let afterPanic = output[panicRange.upperBound...]
                let msgLine = afterPanic.split(separator: "\n").first ?? ""
                message = String(msgLine).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        let fileRegex = try? NSRegularExpression(pattern: #"--> (.+):(\d+):(\d+)"#)
        
        for line in lines {
            if line.starts(with: "error[") {
                let parts = line.split(separator: "]", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    errorType = parts[0].replacingOccurrences(of: "error[", with: "").trimmingCharacters(in: .whitespaces)
                    message = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if line.starts(with: "error:") {
                message = line.replacingOccurrences(of: "error:", with: "").trimmingCharacters(in: .whitespaces)
            }
            
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = fileRegex?.firstMatch(in: line, range: nsRange) {
                if let fileRange = Range(match.range(at: 1), in: line),
                   let lineRange = Range(match.range(at: 2), in: line),
                   let colRange = Range(match.range(at: 3), in: line) {
                    
                    let file = String(line[fileRange])
                    let lineNum = Int(line[lineRange])
                    let colNum = Int(line[colRange])
                    
                    stackTrace.append(StackFrame(functionName: "unknown", filePath: file, lineNumber: lineNum, columnNumber: colNum, isUserCode: true))
                }
            }
        }
        
        if errorType == "RustError" && message.isEmpty {
            return nil
        }
        
        return RuntimeError(language: "Rust", errorType: errorType, message: message, stackTrace: stackTrace, rawOutput: output)
    }
    
    private func parseSwiftError(_ output: String, lines: [String]) -> RuntimeError? {
        guard output.contains("Fatal error:") || output.contains("Precondition failed:") else { return nil }
        
        var errorType = "Swift Fatal Error"
        var message = ""
        
        for line in lines {
            if line.contains("Fatal error:") {
                message = line.components(separatedBy: "Fatal error:").last?.trimmingCharacters(in: .whitespaces) ?? ""
            } else if line.contains("Precondition failed:") {
                errorType = "Precondition Failed"
                message = line.components(separatedBy: "Precondition failed:").last?.trimmingCharacters(in: .whitespaces) ?? ""
            }
        }
        
        return RuntimeError(language: "Swift", errorType: errorType, message: message, stackTrace: [], rawOutput: output)
    }
    
    private func parseGoError(_ output: String, lines: [String]) -> RuntimeError? {
        guard output.contains("panic:") else { return nil }
        
        var stackTrace: [StackFrame] = []
        var errorType = "Go Panic"
        var message = ""
        
        var inStack = false
        var currentFunc = ""
        
        for line in lines {
            if line.hasPrefix("panic:") {
                message = line.replacingOccurrences(of: "panic:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("goroutine") {
                inStack = true
            } else if inStack {
                if line.hasPrefix("\t") {
                    // file and line
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let parts = trimmed.split(separator: " ")
                    if let fileLine = parts.first {
                        let fileParts = fileLine.split(separator: ":")
                        if fileParts.count == 2 {
                            let file = String(fileParts[0])
                            let lineNum = Int(fileParts[1])
                            let isUserCode = !file.contains("/go/src/") && !file.contains("pkg/mod")
                            stackTrace.append(StackFrame(functionName: currentFunc, filePath: file, lineNumber: lineNum, columnNumber: nil, isUserCode: isUserCode))
                        }
                    }
                } else {
                    currentFunc = line.components(separatedBy: "(").first ?? line
                }
            }
        }
        
        return RuntimeError(language: "Go", errorType: errorType, message: message, stackTrace: stackTrace, rawOutput: output)
    }
    
    private func parseJavaError(_ output: String, lines: [String]) -> RuntimeError? {
        guard output.contains("Exception in thread") else { return nil }
        
        var stackTrace: [StackFrame] = []
        var errorType = "JavaException"
        var message = ""
        
        let stackRegex = try? NSRegularExpression(pattern: #"at (.+)\((.+):(\d+)\)"#)
        
        for line in lines {
            if line.starts(with: "Exception in thread") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    errorType = parts[1].trimmingCharacters(in: .whitespaces)
                    if parts.count >= 3 {
                        message = parts[2...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
                    }
                }
            } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("at ") {
                let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
                if let match = stackRegex?.firstMatch(in: line, range: nsRange) {
                    if let funcRange = Range(match.range(at: 1), in: line),
                       let fileRange = Range(match.range(at: 2), in: line),
                       let lineRange = Range(match.range(at: 3), in: line) {
                        
                        let funcName = String(line[funcRange])
                        let file = String(line[fileRange])
                        let lineNum = Int(line[lineRange])
                        
                        let isUserCode = !funcName.starts(with: "java.") && !funcName.starts(with: "sun.")
                        
                        stackTrace.append(StackFrame(functionName: funcName, filePath: file, lineNumber: lineNum, columnNumber: nil, isUserCode: isUserCode))
                    }
                }
            }
        }
        
        return RuntimeError(language: "Java", errorType: errorType, message: message, stackTrace: stackTrace, rawOutput: output)
    }
    
    private func parseGenericError(_ output: String, lines: [String], language: String) -> RuntimeError? {
        let lower = output.lowercased()
        if lower.contains("error:") || lower.contains("fatal:") || lower.contains("exception") {
            let firstErrorLine = lines.first(where: { $0.lowercased().contains("error:") || $0.lowercased().contains("exception") }) ?? "Unknown error"
            return RuntimeError(language: language, errorType: "GenericError", message: firstErrorLine, stackTrace: [], rawOutput: output)
        }
        return nil
    }
}
