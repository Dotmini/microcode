//
//  XcodeBuildParser.swift
//  MicroCode
//
//  Created by Antigravity on 2026.
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import Foundation

struct XcodeBuildIssue: Identifiable, Codable, Equatable {
    let id: UUID
    let filePath: String
    let line: Int
    let column: Int
    let isError: Bool
    let message: String
    
    init(filePath: String, line: Int, column: Int, isError: Bool, message: String) {
        self.id = UUID()
        self.filePath = filePath
        self.line = line
        self.column = column
        self.isError = isError
        self.message = message
    }
    
    var fileName: String {
        return URL(fileURLWithPath: filePath).lastPathComponent
    }
}

class XcodeBuildParser: ObservableObject {
    @Published var issues: [XcodeBuildIssue] = []
    @Published var currentTarget: String = ""
    @Published var currentFileCompiling: String = ""
    @Published var totalWarningsCount = 0
    @Published var totalErrorsCount = 0
    
    // Regex matches:
    // 1. /path/to/file.swift:10:15: error: message
    // 2. /path/to/file.m:10:15: warning: message
    // 3. /path/to/file.cpp:10:15: fatal error: message
    private let issueRegex = try? NSRegularExpression(
        pattern: "^(/[^:]+):(\\d+):(\\d+):\\s+(error|warning|fatal error):\\s+(.+)$",
        options: []
    )
    
    // Matches: === BUILD TARGET MyTarget OF PROJECT MyProject WITH CONFIGURATION Debug ===
    private let targetRegex = try? NSRegularExpression(
        pattern: "===\\s+BUILD TARGET\\s+([\\w\\-]+)",
        options: []
    )
    
    // Matches: CompileSwiftNormal /path/to/file.swift
    // or CompileC /path/to/file.m
    private let compileRegex = try? NSRegularExpression(
        pattern: "(CompileSwift|CompileSwiftNormal|CompileC|CompileC++)\\s+[^\\s]+\\s+([^\\s]+)",
        options: []
    )
    
    func clear() {
        issues = []
        currentTarget = ""
        currentFileCompiling = ""
        totalWarningsCount = 0
        totalErrorsCount = 0
    }
    
    func parseLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        
        // 1. Check for Issues (Warnings/Errors)
        if let match = issueRegex?.firstMatch(in: trimmed, options: [], range: range) {
            let nsTrimmed = trimmed as NSString
            let filePath = nsTrimmed.substring(with: match.range(at: 1))
            let lineStr = nsTrimmed.substring(with: match.range(at: 2))
            let colStr = nsTrimmed.substring(with: match.range(at: 3))
            let typeStr = nsTrimmed.substring(with: match.range(at: 4))
            let message = nsTrimmed.substring(with: match.range(at: 5))
            
            let lineNum = Int(lineStr) ?? 0
            let colNum = Int(colStr) ?? 0
            let isError = typeStr.contains("error")
            
            let issue = XcodeBuildIssue(
                filePath: filePath,
                line: lineNum,
                column: colNum,
                isError: isError,
                message: message
            )
            
            DispatchQueue.main.async {
                // Prevent duplicate issue additions
                if !self.issues.contains(where: { $0.filePath == issue.filePath && $0.line == issue.line && $0.message == issue.message }) {
                    self.issues.append(issue)
                    if isError {
                        self.totalErrorsCount += 1
                    } else {
                        self.totalWarningsCount += 1
                    }
                }
            }
            return
        }
        
        // 2. Check for Build Target Changes
        if let match = targetRegex?.firstMatch(in: trimmed, options: [], range: range) {
            let nsTrimmed = trimmed as NSString
            let targetName = nsTrimmed.substring(with: match.range(at: 1))
            DispatchQueue.main.async {
                self.currentTarget = targetName
            }
            return
        }
        
        // 3. Check for File Compilation Progress
        if let match = compileRegex?.firstMatch(in: trimmed, options: [], range: range) {
            let nsTrimmed = trimmed as NSString
            let filePath = nsTrimmed.substring(with: match.range(at: 2))
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            DispatchQueue.main.async {
                self.currentFileCompiling = fileName
            }
            return
        }
    }
}
