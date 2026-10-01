//
//  HierarchicalContextCompiler.swift
//  MicroCode
//
//  Multi-Tier Hierarchical Codebase Context Compiler.
//  Builds compact repository structural maps, syntax skeletons, and surgical
//  file windows to maximize LLM prompt efficiency and eliminate context pollution.
//  Tirawat Nantamas Founder and CEO of Dotmini Software.
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation

/// Builds hierarchical context for the AI agent.
/// Level 0: System prompt + tool definitions (CACHED)
/// Level 1: Repository structural map (symbols + type signatures)
/// Level 2: File skeletons (signatures + docstrings, no method bodies)
/// Level 3: Full target files (files being modified)
@MainActor
public class HierarchicalContextCompiler: ObservableObject {
    public static let shared = HierarchicalContextCompiler()
    
    // MARK: - Level 1: Repository Map
    
    /// Generate a compact repo map showing exported symbols and their type signatures.
    /// Budget: ~2,000-6,000 tokens
    public func buildRepoMap(workspaceRoot: String, tokenBudget: Int = 4000) async -> String {
        let fm = FileManager.default
        // Enumerator check handled below
        
        var files: [String] = []
        if let enumerator = fm.enumerator(atPath: workspaceRoot) {
            while let path = enumerator.nextObject() as? String {
                if path.hasPrefix(".") || path.contains(".git/") || path.contains("build/") || path.contains("node_modules/") { continue }
                if path.hasSuffix(".swift") || path.hasSuffix(".rs") || path.hasSuffix(".ts") || path.hasSuffix(".py") {
                    files.append(path)
                }
            }
        }
        
        // Prioritize by common names
        files.sort { a, b in
            let aName = (a as NSString).lastPathComponent
            let bName = (b as NSString).lastPathComponent
            let important = ["main", "app", "index", "mod", "lib"]
            let aImportant = important.contains { aName.lowercased().contains($0) }
            let bImportant = important.contains { bName.lowercased().contains($0) }
            if aImportant && !bImportant { return true }
            if !aImportant && bImportant { return false }
            return a < b
        }
        
        var repoMap = ""
        var currentTokens = 0
        
        for file in files {
            let fullPath = (workspaceRoot as NSString).appendingPathComponent(file)
            let symbols = extractSymbols(from: fullPath)
            if symbols.isEmpty { continue }
            
            var fileMap = "\(file):\n"
            for sym in symbols {
                fileMap += "  \(sym.signature)\n"
            }
            fileMap += "\n"
            
            let tokens = estimateTokens(fileMap)
            if currentTokens + tokens > tokenBudget { break }
            
            repoMap += fileMap
            currentTokens += tokens
        }
        
        return repoMap
    }
    
    // MARK: - Level 2: File Skeletons
    
    /// Generate skeleton view of specific files (signatures + docstrings, no bodies)
    /// Budget: ~3,000-10,000 tokens
    public func buildFileSkeletons(files: [String], tokenBudget: Int = 6000) async -> String {
        var skeletons = ""
        var currentTokens = 0
        
        for file in files {
            let symbols = extractSymbols(from: file)
            if symbols.isEmpty { continue }
            
            var fileSkeleton = "File: \(file)\n"
            for sym in symbols {
                if let doc = sym.docComment, !doc.isEmpty {
                    fileSkeleton += "  \(doc)\n"
                }
                fileSkeleton += "  \(sym.signature) { ... }\n"
            }
            fileSkeleton += "\n"
            
            let tokens = estimateTokens(fileSkeleton)
            if currentTokens + tokens > tokenBudget { break }
            
            skeletons += fileSkeleton
            currentTokens += tokens
        }
        
        return skeletons
    }
    
    // MARK: - Level 3: Surgical Files
    
    /// Get full content of files being actively modified
    /// Budget: remaining context window
    public func buildSurgicalContext(activeFiles: [String], diagnosticFiles: [String]) async -> String {
        var allFiles = Set(activeFiles)
        allFiles.formUnion(diagnosticFiles)
        
        var content = ""
        for file in allFiles {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            content += "/// FILE: \(file) ///\n"
            content += text
            content += "\n\n"
        }
        return content
    }
    
    // MARK: - Unified Context Builder
    
    /// Build complete hierarchical context within a total token budget
    public func buildContext(
        workspaceRoot: String,
        activeFiles: [String],
        diagnosticFiles: [String],
        referencedFiles: [String],
        totalBudget: Int = 30000
    ) async -> HierarchicalContext {
        // Allocate budget: 15% repo map, 25% skeletons, 60% surgical
        let repoMapBudget = Int(Double(totalBudget) * 0.15)
        let skeletonBudget = Int(Double(totalBudget) * 0.25)
        // surgicalBudget implicitly takes the rest, though buildSurgicalContext doesn't truncate in this simple model yet.
        
        let repoMap = await buildRepoMap(workspaceRoot: workspaceRoot, tokenBudget: repoMapBudget)
        let skeletons = await buildFileSkeletons(files: referencedFiles, tokenBudget: skeletonBudget)
        let surgical = await buildSurgicalContext(activeFiles: activeFiles, diagnosticFiles: diagnosticFiles)
        
        return HierarchicalContext(
            repoMap: repoMap,
            fileSkeletons: skeletons,
            surgicalFiles: surgical,
            totalEstimatedTokens: estimateTokens(repoMap) + estimateTokens(skeletons) + estimateTokens(surgical)
        )
    }
    
    // MARK: - Symbol Extraction
    
    /// Extract symbols from a Swift/Rust/TypeScript/Python file using regex patterns
    private func extractSymbols(from filePath: String) -> [CodeSymbol] {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return [] }
        
        var symbols: [CodeSymbol] = []
        let lines = content.components(separatedBy: .newlines)
        
        var currentDocComment: [String] = []
        
        // Multi-language regex patterns
        let patterns = [
            // Swift
            "^\\s*(?:public\\s+|private\\s+|fileprivate\\s+|internal\\s+)?(?:class|struct|enum|protocol)\\s+([A-Za-z0-9_]+)",
            "^\\s*(?:public\\s+|private\\s+|fileprivate\\s+|internal\\s+)?(?:func)\\s+([A-Za-z0-9_]+)",
            "^\\s*(?:public\\s+|private\\s+|fileprivate\\s+|internal\\s+)?(?:var|let)\\s+([A-Za-z0-9_]+)",
            // Rust
            "^\\s*(?:pub\\s+)?(?:fn|struct|enum|trait)\\s+([A-Za-z0-9_]+)",
            "^\\s*impl(?:\\s+<[^>]+>)?\\s+([A-Za-z0-9_]+)",
            // TypeScript / JS
            "^\\s*(?:export\\s+)?(?:class|function|interface|type)\\s+([A-Za-z0-9_]+)",
            "^\\s*(?:export\\s+)?(?:const|let|var)\\s+([A-Za-z0-9_]+)\\s*=",
            // Python
            "^\\s*(?:class|def)\\s+([A-Za-z0-9_]+)"
        ]
        
        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        
        for (i, line) in lines.enumerated() {
            let tline = line.trimmingCharacters(in: .whitespaces)
            if tline.hasPrefix("///") || tline.hasPrefix("//") || tline.hasPrefix("/**") || tline.hasPrefix("*") {
                currentDocComment.append(tline)
                continue
            }
            
            if tline.hasPrefix("@") {
                continue // Skip decorators/attributes for symbol matching
            }
            
            var matched = false
            for regex in regexes {
                let range = NSRange(location: 0, length: line.utf16.count)
                if let match = regex.firstMatch(in: line, options: [], range: range) {
                    let doc = currentDocComment.isEmpty ? nil : currentDocComment.joined(separator: "\n")
                    let nameRange = match.range(at: 1)
                    let name = (nameRange.location != NSNotFound) ? (line as NSString).substring(with: nameRange) : "Unknown"
                    
                    let kind: CodeSymbol.SymbolKind = line.contains("func ") || line.contains("fn ") || line.contains("def ") || line.contains("function ") ? .function : .type
                    
                    symbols.append(CodeSymbol(
                        name: name,
                        kind: kind,
                        signature: tline,
                        filePath: filePath,
                        lineNumber: i + 1,
                        docComment: doc
                    ))
                    matched = true
                    break
                }
            }
            
            if !matched && !tline.isEmpty {
                currentDocComment.removeAll()
            } else if matched {
                currentDocComment.removeAll()
            }
        }
        
        return symbols
    }
    
    private func estimateTokens(_ text: String) -> Int {
        // ~4 chars per token approximation
        return text.count / 4
    }
}

// MARK: - Models

public struct HierarchicalContext {
    public let repoMap: String
    public let fileSkeletons: String
    public let surgicalFiles: String
    public let totalEstimatedTokens: Int
    
    public var combined: String {
        var parts: [String] = []
        if !repoMap.isEmpty {
            parts.append("## Repository Structure Map\n\(repoMap)")
        }
        if !fileSkeletons.isEmpty {
            parts.append("## Referenced File Skeletons\n\(fileSkeletons)")
        }
        if !surgicalFiles.isEmpty {
            parts.append("## Active Files (Full Content)\n\(surgicalFiles)")
        }
        return parts.joined(separator: "\n\n---\n\n")
    }
}

public struct CodeSymbol {
    public let name: String
    public let kind: SymbolKind
    public let signature: String
    public let filePath: String
    public let lineNumber: Int
    public let docComment: String?
    
    public enum SymbolKind: String {
        case function, method, property, type, variable, constant, module
    }
}
