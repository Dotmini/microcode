//
//  RepoMapService.swift
//  MicroCode
//
//  Feature 1: Repo Map — Codebase structure overview for AI agent context.
//  Scans workspace files and extracts function/class/struct/enum signatures
//  using regex-based pattern matching (no tree-sitter dependency in Swift).
//  Produces a concise map that gives the AI model a bird's-eye view
//  of the entire codebase without reading every file.
//

import Foundation

// MARK: - Repo Map Models

struct RepoSymbol: Codable {
    let name: String
    let kind: String          // function, class, struct, enum, protocol, trait, interface, type, method
    let signature: String     // First line / declaration signature
    let line: Int             // 1-indexed line number
    let filePath: String      // Relative path from workspace root
}

struct RepoFileEntry: Codable {
    let relativePath: String
    let extension_: String
    let sizeBytes: UInt64
    let symbolCount: Int
    let symbols: [RepoSymbol]
}

struct RepoMap: Codable {
    let workspaceRoot: String
    let totalFiles: Int
    let totalSymbols: Int
    let generatedAt: String
    let files: [RepoFileEntry]
    
    /// Compact text representation for AI context injection
    func toCompactText(maxTokenBudget: Int = 8000) -> String {
        var lines: [String] = []
        lines.append("# Repo Map — \(workspaceRoot)")
        lines.append("Files: \(totalFiles) | Symbols: \(totalSymbols)")
        lines.append("")
        
        var charCount = 0
        let charBudget = maxTokenBudget * 4  // ~4 chars per token
        
        for file in files {
            if charCount >= charBudget {
                if let idx = files.firstIndex(where: { $0.relativePath == file.relativePath }) {
                    lines.append("... (truncated — \(totalFiles - idx) files remaining)")
                }
                break
            }
            
            if file.symbols.isEmpty {
                let fileLine = "📄 \(file.relativePath)"
                lines.append(fileLine)
                charCount += fileLine.count
            } else {
                let header = "📄 \(file.relativePath) (\(file.symbolCount) symbols)"
                lines.append(header)
                charCount += header.count
                
                for sym in file.symbols {
                    let symLine = "  \(sym.kind) \(sym.signature)"
                    if charCount + symLine.count > charBudget { break }
                    lines.append(symLine)
                    charCount += symLine.count
                }
            }
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Repo Map Service

@MainActor
class RepoMapService {
    static let shared = RepoMapService()
    
    private var cachedMap: RepoMap?
    private var cachedWorkspace: String?
    private var cacheTimestamp: Date?
    private let cacheTTL: TimeInterval = 120  // 2 minutes
    
    // Directories to always skip
    private let skipDirs: Set<String> = [
        ".git", ".build", ".swiftpm", "node_modules", "target", "build",
        "dist", "Dist", ".build_dist", "Pods", "DerivedData", "__pycache__",
        ".cache", ".next", ".nuxt", "vendor", "venv", ".venv", "env",
        ".tox", ".mypy_cache", ".pytest_cache", "coverage", ".nyc_output",
        "out", "bin", "obj", ".gradle", ".idea", ".vscode", ".cursor"
    ]
    
    // File extensions we care about for symbol extraction
    private let indexableExtensions: Set<String> = [
        "swift", "rs", "py", "js", "jsx", "ts", "tsx", "go", "java", "kt",
        "kts", "rb", "php", "cs", "c", "cc", "cpp", "h", "hpp", "m", "mm",
        "scala", "r", "jl", "lua", "dart", "ex", "exs", "erl", "hs",
        "ml", "mli", "vue", "svelte"
    ]
    
    // Max limits
    private let maxFiles = 500
    private let maxSymbolsPerFile = 100
    private let maxFileSizeBytes: UInt64 = 512 * 1024  // 512KB
    
    /// Generate or return cached repo map
    func getRepoMap(workspace: String, forceRefresh: Bool = false) async -> RepoMap {
        // Return cached if valid
        if !forceRefresh,
           let cached = cachedMap,
           cachedWorkspace == workspace,
           let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) < cacheTTL {
            return cached
        }
        
        let map = await buildRepoMap(workspace: workspace)
        cachedMap = map
        cachedWorkspace = workspace
        cacheTimestamp = Date()
        return map
    }
    
    /// Clear cache (e.g., when files change)
    func invalidateCache() {
        cachedMap = nil
        cacheTimestamp = nil
    }
    
    // MARK: - Build Repo Map
    
    private func buildRepoMap(workspace: String) async -> RepoMap {
        let rootURL = URL(fileURLWithPath: workspace)
        var fileEntries: [RepoFileEntry] = []
        var totalSymbols = 0
        
        // Collect all indexable files
        let files = collectFiles(root: rootURL, current: rootURL, depth: 0, maxDepth: 8)
        
        for fileURL in files.prefix(maxFiles) {
            let relativePath = fileURL.path.replacingOccurrences(of: workspace + "/", with: "")
            let ext = fileURL.pathExtension
            
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let size = attrs[.size] as? UInt64 else { continue }
            
            // Extract symbols from source files
            var symbols: [RepoSymbol] = []
            if indexableExtensions.contains(ext), size <= maxFileSizeBytes {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    symbols = extractSymbols(content: content, ext: ext, relativePath: relativePath)
                }
            }
            
            totalSymbols += symbols.count
            
            fileEntries.append(RepoFileEntry(
                relativePath: relativePath,
                extension_: ext,
                sizeBytes: size,
                symbolCount: symbols.count,
                symbols: symbols
            ))
        }
        
        // Sort: source files with symbols first, then by path
        fileEntries.sort { a, b in
            if a.symbolCount != b.symbolCount { return a.symbolCount > b.symbolCount }
            return a.relativePath < b.relativePath
        }
        
        let formatter = ISO8601DateFormatter()
        return RepoMap(
            workspaceRoot: workspace,
            totalFiles: fileEntries.count,
            totalSymbols: totalSymbols,
            generatedAt: formatter.string(from: Date()),
            files: fileEntries
        )
    }
    
    // MARK: - File Collection
    
    private func collectFiles(root: URL, current: URL, depth: Int, maxDepth: Int) -> [URL] {
        guard depth <= maxDepth else { return [] }
        
        var result: [URL] = []
        let fm = FileManager.default
        
        guard let items = try? fm.contentsOfDirectory(
            at: current,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = item.lastPathComponent
            
            // Skip hidden files and ignored directories
            if name.hasPrefix(".") || skipDirs.contains(name) { continue }
            
            var isDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDir)
            
            if isDir.boolValue {
                result.append(contentsOf: collectFiles(root: root, current: item, depth: depth + 1, maxDepth: maxDepth))
            } else {
                let ext = item.pathExtension.lowercased()
                let configFiles: Set<String> = ["json", "toml", "yaml", "yml", "md", "txt", "html", "css", "scss", "xml", "plist", "sh", "zsh", "fish"]
                let specialNames: Set<String> = ["Package.swift", "Cargo.toml", "Makefile", "Dockerfile", "Gemfile", "Rakefile"]
                if indexableExtensions.contains(ext) || configFiles.contains(ext) || specialNames.contains(name) {
                    result.append(item)
                }
            }
            
            if result.count >= maxFiles { break }
        }
        
        return result
    }
    
    // MARK: - Symbol Extraction (Regex-based, multi-language)
    
    private func extractSymbols(content: String, ext: String, relativePath: String) -> [RepoSymbol] {
        let lines = content.components(separatedBy: "\n")
        var symbols: [RepoSymbol] = []
        
        for (idx, line) in lines.enumerated() {
            if symbols.count >= maxSymbolsPerFile { break }
            
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") { continue }
            
            if let sym = matchSymbol(line: trimmed, lineNumber: idx + 1, ext: ext, relativePath: relativePath) {
                symbols.append(sym)
            }
        }
        
        return symbols
    }
    
    private func matchSymbol(line: String, lineNumber: Int, ext: String, relativePath: String) -> RepoSymbol? {
        let signature = String(line.prefix(200))  // Cap signature length
        
        switch ext {
        case "swift":
            return matchSwift(line: line, signature: signature, lineNumber: lineNumber, relativePath: relativePath)
        case "rs":
            return matchRust(line: line, signature: signature, lineNumber: lineNumber, relativePath: relativePath)
        case "py":
            return matchPython(line: line, signature: signature, lineNumber: lineNumber, relativePath: relativePath)
        case "js", "jsx", "ts", "tsx":
            return matchJSTS(line: line, signature: signature, lineNumber: lineNumber, relativePath: relativePath)
        case "go":
            return matchGo(line: line, signature: signature, lineNumber: lineNumber, relativePath: relativePath)
        case "java", "kt", "kts":
            return matchJavaKotlin(line: line, signature: signature, lineNumber: lineNumber, relativePath: relativePath)
        case "c", "cc", "cpp", "h", "hpp", "m", "mm":
            return matchCCpp(line: line, signature: signature, lineNumber: lineNumber, relativePath: relativePath)
        case "rb":
            return matchRuby(line: line, signature: signature, lineNumber: lineNumber, relativePath: relativePath)
        case "php":
            return matchPHP(line: line, signature: signature, lineNumber: lineNumber, relativePath: relativePath)
        case "dart":
            return matchDart(line: line, signature: signature, lineNumber: lineNumber, relativePath: relativePath)
        default:
            return nil
        }
    }
    
    // MARK: - Language-specific matchers
    
    private func matchSwift(line: String, signature: String, lineNumber: Int, relativePath: String) -> RepoSymbol? {
        let typePatterns: [(String, String)] = [
            ("class ", "class"), ("struct ", "struct"), ("enum ", "enum"),
            ("protocol ", "protocol"), ("actor ", "actor"), ("extension ", "extension")
        ]
        for (prefix, kind) in typePatterns {
            if let name = extractName(line: line, keyword: prefix) {
                return RepoSymbol(name: name, kind: kind, signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        
        if line.contains("func ") {
            if let name = extractFuncName(line: line, keyword: "func ") {
                let kind = line.contains("static ") ? "static_method" : "function"
                return RepoSymbol(name: name, kind: kind, signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        
        if line.contains("typealias ") {
            if let name = extractName(line: line, keyword: "typealias ") {
                return RepoSymbol(name: name, kind: "type", signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        
        return nil
    }
    
    private func matchRust(line: String, signature: String, lineNumber: Int, relativePath: String) -> RepoSymbol? {
        if line.contains("fn ") && !line.contains("//") {
            if let name = extractFuncName(line: line, keyword: "fn ") {
                return RepoSymbol(name: name, kind: "function", signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        
        let typePatterns: [(String, String)] = [
            ("struct ", "struct"), ("enum ", "enum"), ("trait ", "trait"),
            ("impl ", "impl"), ("mod ", "module"), ("type ", "type")
        ]
        for (prefix, kind) in typePatterns {
            if let name = extractName(line: line, keyword: prefix) {
                if kind == "impl" {
                    let clean = line.replacingOccurrences(of: "impl ", with: "")
                        .components(separatedBy: " {").first?
                        .trimmingCharacters(in: .whitespaces) ?? name
                    return RepoSymbol(name: clean, kind: kind, signature: signature, line: lineNumber, filePath: relativePath)
                }
                return RepoSymbol(name: name, kind: kind, signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        
        return nil
    }
    
    private func matchPython(line: String, signature: String, lineNumber: Int, relativePath: String) -> RepoSymbol? {
        if line.hasPrefix("def ") || line.hasPrefix("async def ") {
            let keyword = line.hasPrefix("async def ") ? "async def " : "def "
            if let name = extractFuncName(line: line, keyword: keyword) {
                return RepoSymbol(name: name, kind: "function", signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        if line.hasPrefix("class ") {
            if let name = extractName(line: line, keyword: "class ") {
                return RepoSymbol(name: name, kind: "class", signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        // Indented methods (note: matchSymbol already trims, so this won't match indented)
        return nil
    }
    
    private func matchJSTS(line: String, signature: String, lineNumber: Int, relativePath: String) -> RepoSymbol? {
        if line.contains("function ") && !line.contains("//") {
            if let name = extractFuncName(line: line, keyword: "function ") {
                return RepoSymbol(name: name, kind: "function", signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        
        if (line.contains("const ") || line.contains("let ") || line.contains("var ")) && line.contains("=>") {
            let keyword = line.contains("const ") ? "const " : (line.contains("let ") ? "let " : "var ")
            if let name = extractName(line: line, keyword: keyword) {
                return RepoSymbol(name: name, kind: "function", signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        
        let typePatterns: [(String, String)] = [
            ("class ", "class"), ("interface ", "interface"),
            ("type ", "type"), ("enum ", "enum")
        ]
        for (prefix, kind) in typePatterns {
            if line.contains(prefix) {
                if let name = extractName(line: line, keyword: prefix) {
                    return RepoSymbol(name: name, kind: kind, signature: signature, line: lineNumber, filePath: relativePath)
                }
            }
        }
        
        if line.contains("export ") && line.contains("function ") {
            if let name = extractFuncName(line: line, keyword: "function ") {
                return RepoSymbol(name: name, kind: "function", signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        
        return nil
    }
    
    private func matchGo(line: String, signature: String, lineNumber: Int, relativePath: String) -> RepoSymbol? {
        if line.hasPrefix("func ") {
            if line.contains(") ") && line.first == "f" {
                // Could be method: func (r *Receiver) Name(
                let parts = line.components(separatedBy: ") ")
                if parts.count >= 2 {
                    if let name = extractFuncName(line: parts[1], keyword: "") {
                        return RepoSymbol(name: name, kind: "method", signature: signature, line: lineNumber, filePath: relativePath)
                    }
                }
            }
            if let name = extractFuncName(line: line, keyword: "func ") {
                return RepoSymbol(name: name, kind: "function", signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        if line.hasPrefix("type ") {
            if let name = extractName(line: line, keyword: "type ") {
                let kind = line.contains("struct") ? "struct" : (line.contains("interface") ? "interface" : "type")
                return RepoSymbol(name: name, kind: kind, signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        return nil
    }
    
    private func matchJavaKotlin(line: String, signature: String, lineNumber: Int, relativePath: String) -> RepoSymbol? {
        let typePatterns: [(String, String)] = [
            ("class ", "class"), ("interface ", "interface"),
            ("enum ", "enum"), ("object ", "object"),
            ("data class ", "class"), ("sealed class ", "class"),
            ("abstract class ", "class"), ("annotation class ", "class")
        ]
        for (prefix, kind) in typePatterns {
            if line.contains(prefix) {
                if let name = extractName(line: line, keyword: prefix) {
                    return RepoSymbol(name: name, kind: kind, signature: signature, line: lineNumber, filePath: relativePath)
                }
            }
        }
        
        if line.contains("fun ") {
            if let name = extractFuncName(line: line, keyword: "fun ") {
                return RepoSymbol(name: name, kind: "function", signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        
        return nil
    }
    
    private func matchCCpp(line: String, signature: String, lineNumber: Int, relativePath: String) -> RepoSymbol? {
        let typePatterns: [(String, String)] = [
            ("class ", "class"), ("struct ", "struct"), ("enum ", "enum"),
            ("typedef ", "type"), ("namespace ", "namespace")
        ]
        for (prefix, kind) in typePatterns {
            if line.hasPrefix(prefix) || line.contains(" \(prefix)") {
                if let name = extractName(line: line, keyword: prefix) {
                    return RepoSymbol(name: name, kind: kind, signature: signature, line: lineNumber, filePath: relativePath)
                }
            }
        }
        
        if line.hasPrefix("@interface ") {
            if let name = extractName(line: line, keyword: "@interface ") {
                return RepoSymbol(name: name, kind: "interface", signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        if line.hasPrefix("@implementation ") {
            if let name = extractName(line: line, keyword: "@implementation ") {
                return RepoSymbol(name: name, kind: "class", signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        
        return nil
    }
    
    private func matchRuby(line: String, signature: String, lineNumber: Int, relativePath: String) -> RepoSymbol? {
        if line.hasPrefix("def ") {
            if let name = extractFuncName(line: line, keyword: "def ") {
                return RepoSymbol(name: name, kind: "function", signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        if line.hasPrefix("class ") {
            if let name = extractName(line: line, keyword: "class ") {
                return RepoSymbol(name: name, kind: "class", signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        if line.hasPrefix("module ") {
            if let name = extractName(line: line, keyword: "module ") {
                return RepoSymbol(name: name, kind: "module", signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        return nil
    }
    
    private func matchPHP(line: String, signature: String, lineNumber: Int, relativePath: String) -> RepoSymbol? {
        if line.contains("function ") {
            if let name = extractFuncName(line: line, keyword: "function ") {
                return RepoSymbol(name: name, kind: "function", signature: signature, line: lineNumber, filePath: relativePath)
            }
        }
        let typePatterns: [(String, String)] = [
            ("class ", "class"), ("interface ", "interface"), ("trait ", "trait"), ("enum ", "enum")
        ]
        for (prefix, kind) in typePatterns {
            if line.contains(prefix) {
                if let name = extractName(line: line, keyword: prefix) {
                    return RepoSymbol(name: name, kind: kind, signature: signature, line: lineNumber, filePath: relativePath)
                }
            }
        }
        return nil
    }
    
    private func matchDart(line: String, signature: String, lineNumber: Int, relativePath: String) -> RepoSymbol? {
        let typePatterns: [(String, String)] = [
            ("class ", "class"), ("mixin ", "mixin"), ("enum ", "enum"),
            ("extension ", "extension"), ("typedef ", "type")
        ]
        for (prefix, kind) in typePatterns {
            if line.contains(prefix) {
                if let name = extractName(line: line, keyword: prefix) {
                    return RepoSymbol(name: name, kind: kind, signature: signature, line: lineNumber, filePath: relativePath)
                }
            }
        }
        return nil
    }
    
    // MARK: - Helpers
    
    /// Extract identifier name after a keyword: "class Foo" -> "Foo"
    private func extractName(line: String, keyword: String) -> String? {
        guard let range = line.range(of: keyword) else { return nil }
        let after = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        
        let endChars = CharacterSet(charactersIn: " <({:;,=\n\r")
        let name = after.components(separatedBy: endChars).first ?? ""
        return name.isEmpty ? nil : name
    }
    
    /// Extract function name: "func doSomething(" -> "doSomething"
    private func extractFuncName(line: String, keyword: String) -> String? {
        guard let range = line.range(of: keyword) else { return nil }
        let after = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        
        let endChars = CharacterSet(charactersIn: " <({:;,=\n\r")
        let name = after.components(separatedBy: endChars).first ?? ""
        
        guard let first = name.first, first.isLetter || first == "_" else { return nil }
        return name.isEmpty ? nil : name
    }
}

// MARK: - Agent Tool: repo_map

struct RepoMapTool: AgentTool {
    let name = "repo_map"
    let description = """
        Generate a concise overview map of the entire codebase structure. \
        Shows all files and their key symbols (functions, classes, structs, enums, protocols) \
        with signatures. Use this to understand project architecture before diving into specific files. \
        Much more efficient than reading files one by one.
        """
    let parameters = [
        ToolParameter(name: "directory", type: "string", description: "Workspace root directory to map", required: true),
        ToolParameter(name: "max_tokens", type: "integer", description: "Max token budget for output (default: 8000)", required: false),
        ToolParameter(name: "filter", type: "string", description: "Optional file extension filter (e.g. 'swift' or 'rs,py')", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let directory = params["directory"] as? String else {
            throw ToolBoxError.invalidParams("directory is required")
        }
        
        let maxTokens = params["max_tokens"] as? Int ?? 8000
        let filter = params["filter"] as? String
        
        var map = await RepoMapService.shared.getRepoMap(workspace: directory)
        
        // Apply extension filter if provided
        if let filter = filter, !filter.isEmpty {
            let exts = Set(filter.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
            let filteredFiles = map.files.filter { exts.contains($0.extension_.lowercased()) }
            map = RepoMap(
                workspaceRoot: map.workspaceRoot,
                totalFiles: filteredFiles.count,
                totalSymbols: filteredFiles.reduce(0) { $0 + $1.symbolCount },
                generatedAt: map.generatedAt,
                files: filteredFiles
            )
        }
        
        return map.toCompactText(maxTokenBudget: maxTokens)
    }
}
