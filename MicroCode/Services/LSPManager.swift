//
//  LSPManager.swift
//  MicroCode - LSP Manager & Official Completion Intelligence Engine
//
//  Orchestrates multiple LSP client instances for different languages,
//  guarantees synchronized didOpen/didChange ordering before completion queries,
//  and provides official prefix/fuzzy ranking + SDK & live AST symbol completions.
//  Tirawat Nantamas Founder and CEO of Dotmini Software.
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation
import SwiftUI

/// Manages LSP clients for different languages
@MainActor
class LSPManager: ObservableObject {
    
    static let shared = LSPManager()
    
    /// Active LSP clients by server type
    @Published var activeClients: [LanguageServer: LSPClientService] = [:]
    
    /// Latest diagnostics by file URI
    @Published var fileDiagnostics: [String: [LSPDiagnostic]] = [:]
    
    /// Human-readable badge for the last completion query (e.g. "sourcekit-lsp", "rust-analyzer", "Swift SDK")
    @Published var activeSourceBadge: String = "LSP"
    
    /// Current root URI for workspace
    private var rootUri: String?
    
    /// In-flight server startup tasks to prevent spawning duplicate language server processes
    private var startingClients: [LanguageServer: Task<LSPClientService?, Never>] = [:]
    
    /// Document versions for tracking changes
    private var documentVersions: [String: Int] = [:]
    
    /// URIs that have actually sent `textDocument/didOpen` to their active client
    private var openedDocumentURIs: Set<String> = []
    
    /// Last synced document content hash per URI to avoid redundant JSON-RPC payloads
    private var documentContentHashes: [String: Int] = [:]
    
    /// Latest in-memory content per URI for fast local symbol extraction
    private var documentContents: [String: String] = [:]
    
    private init() {}
    
    // MARK: - API
    
    /// Set the workspace root
    func setWorkspace(_ url: URL) {
        self.rootUri = url.standardizedFileURL.absoluteString
    }
    
    /// Automatically find package root (Package.swift, Cargo.toml, tsconfig.json, pyproject.toml, .git)
    private func resolveRootURI(for fileURI: String?) -> String? {
        if let fileURI = fileURI, let fileURL = URL(string: fileURI), fileURL.isFileURL {
            let fm = FileManager.default
            var dir = fileURL.deletingLastPathComponent()
            let markers = ["Package.swift", "Cargo.toml", "tsconfig.json", "pyproject.toml", "go.mod", "pubspec.yaml", ".git"]
            for _ in 0..<6 {
                for marker in markers {
                    if fm.fileExists(atPath: dir.appendingPathComponent(marker).path) {
                        return dir.standardizedFileURL.absoluteString
                    }
                }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
            if rootUri == nil {
                return fileURL.deletingLastPathComponent().standardizedFileURL.absoluteString
            }
        }
        return rootUri
    }
    
    /// Get or start LSP client for a language (deduplicating concurrent startup requests)
    func clientFor(language: String, fileURI: String? = nil) async throws -> LSPClientService? {
        guard let serverType = LanguageServer.serverFor(language: language) else {
            return nil
        }
        
        // Return existing client if already running
        if let existing = activeClients[serverType], existing.isRunning {
            return existing
        }
        
        // Join in-flight initialization if already starting
        if let existingTask = startingClients[serverType] {
            return await existingTask.value
        }
        
        let effectiveRoot = resolveRootURI(for: fileURI)
        guard let targetRoot = effectiveRoot else {
            return nil
        }
        if self.rootUri == nil {
            self.rootUri = targetRoot
        }
        
        let startupTask = Task<LSPClientService?, Never> { @MainActor in
            defer { self.startingClients.removeValue(forKey: serverType) }
            guard let _ = await LSPClientService.resolveBinaryAsync(serverType.rawValue, searchPaths: serverType.searchPaths) else {
                return nil
            }
            let client = LSPClientService(serverType: serverType)
            do {
                try await client.start(rootUri: targetRoot)
                self.activeClients[serverType] = client
                return client
            } catch {
                print("❌ [LSPManager] Failed to start \(serverType.rawValue): \(error.localizedDescription)")
                return nil
            }
        }
        
        startingClients[serverType] = startupTask
        return await startupTask.value
    }
    
    /// Notify that a document was opened
    func documentOpened(uri: String, language: String, content: String) async {
        documentContents[uri] = content
        guard let serverType = LanguageServer.serverFor(language: language) else { return }
        guard let _ = await LSPClientService.resolveBinaryAsync(serverType.rawValue, searchPaths: serverType.searchPaths) else { return }
        
        let contentHash = content.hashValue
        if openedDocumentURIs.contains(uri), documentContentHashes[uri] == contentHash {
            return
        }
        
        guard let client = try? await clientFor(language: language, fileURI: uri) else { return }
        
        do {
            if openedDocumentURIs.contains(uri) {
                let version = (documentVersions[uri] ?? 1) + 1
                documentVersions[uri] = version
                documentContentHashes[uri] = contentHash
                try await client.didChange(uri: uri, version: version, text: content)
            } else {
                documentVersions[uri] = 1
                documentContentHashes[uri] = contentHash
                try await client.didOpen(uri: uri, languageId: language, version: 1, text: content)
                openedDocumentURIs.insert(uri)
            }
        } catch {
            print("❌ [LSPManager] didOpen failed: \(error)")
        }
    }
    
    /// Notify that a document was changed (automatically calls didOpen first if never opened)
    func documentChanged(uri: String, language: String, content: String) async {
        documentContents[uri] = content
        guard let serverType = LanguageServer.serverFor(language: language) else { return }
        guard let _ = await LSPClientService.resolveBinaryAsync(serverType.rawValue, searchPaths: serverType.searchPaths) else { return }
        
        if !openedDocumentURIs.contains(uri) {
            await documentOpened(uri: uri, language: language, content: content)
            return
        }
        
        let contentHash = content.hashValue
        if documentContentHashes[uri] == contentHash {
            return
        }
        documentContentHashes[uri] = contentHash
        
        let version = (documentVersions[uri] ?? 1) + 1
        documentVersions[uri] = version
        
        guard let client = try? await clientFor(language: language, fileURI: uri) else { return }
        
        do {
            try await client.didChange(uri: uri, version: version, text: content)
        } catch {
            print("❌ [LSPManager] didChange failed: \(error)")
        }
    }
    
    /// Get completions at a position with full document sync, context awareness, official SDK & live AST symbols, and fuzzy/prefix ranking.
    func getCompletions(
        uri: String,
        language: String,
        line: Int,
        character: Int,
        content: String? = nil,
        wordPrefix: String = "",
        triggerCharacter: String? = nil,
        isMemberAccess: Bool = false
    ) async -> [CompletionItem] {
        if let content = content {
            documentContents[uri] = content
        }
        let activeContent = content ?? documentContents[uri] ?? ""
        
        var lspItems: [CompletionItem] = []
        var usedLiveLSP = false
        
        if let serverType = LanguageServer.serverFor(language: language),
           let _ = await LSPClientService.resolveBinaryAsync(serverType.rawValue, searchPaths: serverType.searchPaths) {
            // CRITICAL FIX: Sync the latest buffer to the Language Server BEFORE requesting completion
            if !activeContent.isEmpty {
                await documentChanged(uri: uri, language: language, content: activeContent)
            }
            if !Task.isCancelled, let client = try? await clientFor(language: language, fileURI: uri) {
                do {
                    lspItems = try await client.completion(
                        uri: uri,
                        line: line,
                        character: character,
                        triggerCharacter: triggerCharacter
                    )
                    if !lspItems.isEmpty {
                        usedLiveLSP = true
                        activeSourceBadge = serverType.rawValue
                    }
                } catch {
                    // Fall through to official SDK + workspace symbol engine
                }
            }
        }
        
        guard !Task.isCancelled else { return [] }
        
        // Gather official SDK completions + live symbols from the active document
        let fallbackItems = Self.officialLanguageAndDocumentCompletions(
            language: language,
            documentContent: activeContent,
            currentWordPrefix: wordPrefix,
            isMemberAccess: isMemberAccess
        )
        
        if !usedLiveLSP {
            let langLabel = language.isEmpty ? "Code" : language.capitalized
            activeSourceBadge = "\(langLabel) Official"
        }
        
        // Combine and rank with Official IDE Relevance Scorer
        let merged = Self.rankAndFilterCompletions(
            lspItems: lspItems,
            fallbackItems: fallbackItems,
            wordPrefix: wordPrefix,
            isMemberAccess: isMemberAccess,
            language: language
        )
        
        return merged
    }
    
    /// Get hover info at a position
    func getHover(uri: String, language: String, line: Int, character: Int) async -> String? {
        if let client = try? await clientFor(language: language, fileURI: uri),
           let result = try? await client.hover(uri: uri, line: line, character: character),
           !result.contents.displayText.isEmpty {
            return result.contents.displayText
        }
        return nil
    }
    
    /// Get definition locations (with instant local/workspace AST symbol fallback when LSP is indexing or unavailable)
    func getDefinition(uri: String, language: String, line: Int, character: Int, symbolHint: String? = nil, workspacePath: String? = nil) async -> [LSPLocation] {
        if let client = try? await clientFor(language: language, fileURI: uri),
           let locs = try? await client.definition(uri: uri, line: line, character: character),
           !locs.isEmpty {
            return locs
        }
        
        // Instant fallback: search current document & workspace for symbol declaration
        guard let sym = symbolHint, !sym.isEmpty else { return [] }
        let escaped = NSRegularExpression.escapedPattern(for: sym)
        let declPattern = "(?:func|struct|class|enum|protocol|actor|typealias|let|var|def|fn|interface|type|const)\\s+\(escaped)\\b"
        
        // 1. Check current document first
        if let content = documentContents[uri],
           let regex = try? NSRegularExpression(pattern: declPattern) {
            let lines = content.components(separatedBy: "\n")
            for (idx, textLine) in lines.enumerated() {
                let nsRange = NSRange(textLine.startIndex..<textLine.endIndex, in: textLine)
                if let match = regex.firstMatch(in: textLine, range: nsRange) {
                    let col = match.range.location
                    let pos = LSPPosition(line: idx, character: col)
                    return [LSPLocation(uri: uri, range: LSPRange(start: pos, end: pos))]
                }
            }
        }
        
        // 2. Check workspace via fast ripgrep / grep
        if let ws = workspacePath, !ws.isEmpty {
            let found: LSPLocation? = await Task.detached(priority: .userInitiated) {
                let p = Process()
                let outPipe = Pipe()
                let rgPath = ["/opt/homebrew/bin/rg", "/usr/local/bin/rg"].first(where: { FileManager.default.isExecutableFile(atPath: $0) })
                if let rg = rgPath {
                    p.executableURL = URL(fileURLWithPath: rg)
                    p.arguments = ["--vimgrep", "--max-count", "1", "-e", declPattern, ws]
                } else {
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
                    p.arguments = ["-rnIE", "--exclude-dir=.git", "--exclude-dir=node_modules", "--exclude-dir=target", "--exclude-dir=.build", declPattern, ws]
                }
                p.standardOutput = outPipe
                p.standardError = Pipe()
                try? p.run()
                p.waitUntilExit()
                guard let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
                      let firstLine = out.components(separatedBy: "\n").first(where: { !$0.isEmpty }) else {
                    return nil
                }
                let parts = firstLine.components(separatedBy: ":")
                guard parts.count >= 2,
                      let lineNum = Int(parts[1]) else { return nil }
                let filePath = parts[0]
                let colNum = parts.count >= 3 ? (Int(parts[2]) ?? 1) : 1
                let fileURI = URL(fileURLWithPath: filePath).standardizedFileURL.absoluteString
                let pos = LSPPosition(line: max(0, lineNum - 1), character: max(0, colNum - 1))
                return LSPLocation(uri: fileURI, range: LSPRange(start: pos, end: pos))
            }.value
            if let found {
                return [found]
            }
        }
        return []
    }
    
    /// Stop all LSP clients
    func stopAll() {
        for (_, task) in startingClients {
            task.cancel()
        }
        startingClients.removeAll()
        for (_, client) in activeClients {
            client.stop()
        }
        activeClients.removeAll()
        documentVersions.removeAll()
        openedDocumentURIs.removeAll()
        documentContentHashes.removeAll()
    }
    
    /// Stop client for a specific language
    func stop(language: String) {
        guard let serverType = LanguageServer.serverFor(language: language) else { return }
        startingClients[serverType]?.cancel()
        startingClients.removeValue(forKey: serverType)
        activeClients[serverType]?.stop()
        activeClients.removeValue(forKey: serverType)
    }
    
    // MARK: - Status
    
    func isAvailable(for language: String) -> Bool {
        guard let serverType = LanguageServer.serverFor(language: language) else { return false }
        if let client = activeClients[serverType] { return client.isRunning }
        return LSPClientService.resolveBinary(serverType.rawValue, searchPaths: serverType.searchPaths) != nil
    }

    private var detectedServersCache: [LanguageServer]?

    func detectInstalledServers(refresh: Bool = false) -> [LanguageServer] {
        if !refresh, let c = detectedServersCache { return c }
        let found = LanguageServer.allCases.filter {
            LSPClientService.resolveBinary($0.rawValue, searchPaths: $0.searchPaths) != nil
        }
        detectedServersCache = found
        return found
    }

    func detectedLanguages(refresh: Bool = false) -> [String] {
        Array(Set(detectInstalledServers(refresh: refresh).flatMap { $0.languageIds })).sorted()
    }
    
    func capabilities(for language: String) -> ServerCapabilities? {
        guard let serverType = LanguageServer.serverFor(language: language),
              let client = activeClients[serverType] else { return nil }
        return client.serverCapabilities
    }
    
    // MARK: - Official IDE Ranking, Filtering & SDK Intelligence Engine
    
    /// Top-level declaration keywords that should NEVER appear right after `.` member access
    private static let nonMemberTopLevelKeywords: Set<String> = [
        "associatedtype", "typealias", "precedencegroup", "import", "operator",
        "infix", "prefix", "postfix", "struct", "class", "protocol", "extension",
        "actor", "deinit", "subscript", "fileprivate", "internal", "public",
        "private", "open", "inout", "borrowing", "consuming", "nonisolated",
        "package", "macro", "where", "fallthrough", "continue", "break"
    ]
    
    nonisolated static func rankAndFilterCompletions(
        lspItems: [CompletionItem],
        fallbackItems: [CompletionItem],
        wordPrefix: String,
        isMemberAccess: Bool,
        language: String
    ) -> [CompletionItem] {
        let cleanPrefix = wordPrefix.trimmingCharacters(in: CharacterSet(charactersIn: ".:>"))
        let lowerPrefix = cleanPrefix.lowercased()
        
        // Require either a member trigger (`.`, `:`, `>`) or at least 1 identifier char
        if !isMemberAccess && cleanPrefix.isEmpty {
            return []
        }
        
        struct ScoredCandidate {
            let item: CompletionItem
            let score: Int
            let sortKey: String
        }
        
        var seenKeys = Set<String>()
        var scored: [ScoredCandidate] = []
        scored.reserveCapacity(min(256, lspItems.count + fallbackItems.count))
        
        func evaluate(_ item: CompletionItem, isFromLiveLSP: Bool) {
            let primary = item.primarySymbolName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !primary.isEmpty else { return }
            
            // Do not suggest the exact bare identifier the user just typed if it has no signature/detail
            if primary == cleanPrefix && item.parameterSignature == nil && item.detail == nil && !isFromLiveLSP {
                return
            }
            
            // When in member access (`.`), filter out top-level keywords like `associatedtype`
            if isMemberAccess {
                if nonMemberTopLevelKeywords.contains(primary.lowercased()) {
                    return
                }
                if item.kind == 14 && primary.lowercased() != "self" && primary.lowercased() != "init" && primary.lowercased() != "type" && primary.lowercased() != "await" {
                    return
                }
            }
            
            let matchTarget = (item.filterText ?? primary).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let lowerTarget = matchTarget.lowercased()
            
            var score = 0
            if cleanPrefix.isEmpty {
                // Triggered by `.` / `:` with empty prefix
                score = 500
            } else if matchTarget.hasPrefix(cleanPrefix) || primary.hasPrefix(cleanPrefix) {
                // Tier 1: Exact case-sensitive prefix match
                score = 1400 - min(60, matchTarget.count - cleanPrefix.count)
                if primary == cleanPrefix { score += 100 }
            } else if lowerTarget.hasPrefix(lowerPrefix) || primary.lowercased().hasPrefix(lowerPrefix) {
                // Tier 2: Case-insensitive prefix match
                score = 1100 - min(60, matchTarget.count - cleanPrefix.count)
            } else if isSubsequenceOrCamelMatch(query: cleanPrefix, target: primary) {
                // Tier 3: CamelCase / subsequence match (e.g. `VSt` -> `VStack`, `mW` -> `minWidth`)
                score = 800 - min(60, primary.count)
            } else if lowerTarget.contains(lowerPrefix) {
                // Tier 4: Substring match
                score = 600 - min(60, matchTarget.count)
            } else {
                // Does not match user's typed prefix — exclude!
                return
            }
            
            // Source & Kind prioritization
            if isFromLiveLSP {
                score += 180
            }
            if isMemberAccess {
                switch item.kind {
                case 2, 3: score += 140 // Method / Function (e.g. .frame, .padding)
                case 5, 10: score += 130 // Field / Property
                case 20: score += 110 // EnumMember
                default: break
                }
            } else {
                switch item.kind {
                case 6, 5, 10: score += 90  // Local Variable / Property
                case 2, 3, 4: score += 80   // Function / Method / Constructor
                case 7, 22, 8, 13: score += 75 // Class / Struct / Interface / Enum
                case 14, 15: score += 60    // Keyword / Snippet
                default: break
                }
            }
            
            let dedupKey = "\(primary)|\(item.parameterSignature ?? "")"
            guard seenKeys.insert(dedupKey).inserted else { return }
            
            scored.append(ScoredCandidate(
                item: item,
                score: score,
                sortKey: item.sortText ?? item.label
            ))
        }
        
        // Evaluate live LSP items first so they win deduplication
        for item in lspItems {
            evaluate(item, isFromLiveLSP: true)
        }
        for item in fallbackItems {
            evaluate(item, isFromLiveLSP: false)
        }
        
        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.sortKey != b.sortKey { return a.sortKey < b.sortKey }
            return a.item.label < b.item.label
        }
        
        // Cap to top 60 items so popup rendering is instantaneous (120fps)
        return Array(scored.prefix(60).map(\.item))
    }
    
    nonisolated private static func isSubsequenceOrCamelMatch(query: String, target: String) -> Bool {
        guard query.count >= 2, query.count <= target.count else { return false }
        var qIdx = query.startIndex
        var tIdx = target.startIndex
        while qIdx < query.endIndex && tIdx < target.endIndex {
            if query[qIdx].lowercased() == target[tIdx].lowercased() {
                qIdx = query.index(after: qIdx)
            }
            tIdx = target.index(after: tIdx)
        }
        return qIdx == query.endIndex
    }
    
    // MARK: - Live Document Symbol Extractor & Official SDK Catalog
    
    nonisolated static func officialLanguageAndDocumentCompletions(
        language: String,
        documentContent: String,
        currentWordPrefix: String,
        isMemberAccess: Bool
    ) -> [CompletionItem] {
        let lang = language.lowercased()
        var results: [CompletionItem] = []
        
        // 1. Official Language / Framework SDK Signatures
        switch lang {
        case "swift":
            if isMemberAccess {
                results.append(contentsOf: swiftUIMemberCompletions)
            } else {
                results.append(contentsOf: swiftTopLevelCompletions)
            }
        case "rust", "rs":
            results.append(contentsOf: isMemberAccess ? rustMemberCompletions : rustTopLevelCompletions)
        case "python", "py":
            results.append(contentsOf: isMemberAccess ? pythonMemberCompletions : pythonTopLevelCompletions)
        case "typescript", "javascript", "ts", "js", "tsx", "jsx":
            results.append(contentsOf: isMemberAccess ? tsMemberCompletions : tsTopLevelCompletions)
        case "html", "htm", "vue", "svelte":
            results.append(contentsOf: htmlCompletions)
        case "css", "scss", "less":
            results.append(contentsOf: cssCompletions)
        case "go", "golang":
            results.append(contentsOf: goCompletions)
        case "c", "cpp", "c++", "h", "hpp", "objc", "objective-c", "mm":
            results.append(contentsOf: cppCompletions)
        case "ardium", "ar":
            results.append(contentsOf: ardiumCompletions)
        default:
            break
        }
        
        // 2. Live Document Symbol Extraction (functions, structs, classes, variables in current file)
        if !documentContent.isEmpty && documentContent.utf16.count < 120_000 {
            let docSymbols = extractLiveDocumentSymbols(from: documentContent, excluding: currentWordPrefix)
            results.append(contentsOf: docSymbols)
        }
        
        return results
    }
    
    nonisolated private static func extractLiveDocumentSymbols(from content: String, excluding currentPrefix: String) -> [CompletionItem] {
        var items: [CompletionItem] = []
        var seen = Set<String>()
        
        let lines = content.components(separatedBy: "\n")
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") || line.hasPrefix("#") || line.hasPrefix("/*") {
                continue
            }
            
            // Detect declarations (struct, class, enum, protocol, func, fn, def, var, let, const)
            if let decl = parseDeclaration(from: line), decl.name != currentPrefix, seen.insert(decl.name).inserted {
                items.append(CompletionItem(
                    label: decl.signature ?? decl.name,
                    kind: decl.kind,
                    detail: decl.detail,
                    documentation: "Defined in current document",
                    insertText: decl.insertText ?? decl.name,
                    filterText: decl.name
                ))
            }
        }
        
        // Also extract identifier tokens (length >= 3) for fast local variable/type completion
        var currentIdent = ""
        for ch in content {
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "@" {
                currentIdent.append(ch)
            } else {
                if currentIdent.count >= 3,
                   currentIdent != currentPrefix,
                   !currentIdent.first!.isNumber,
                   seen.insert(currentIdent).inserted {
                    items.append(CompletionItem(
                        label: currentIdent,
                        kind: 6, // Variable / Identifier
                        detail: "Document Symbol",
                        insertText: currentIdent,
                        filterText: currentIdent
                    ))
                }
                currentIdent.removeAll(keepingCapacity: true)
            }
        }
        return items
    }
    
    nonisolated private static func parseDeclaration(from line: String) -> (name: String, signature: String?, insertText: String?, kind: Int, detail: String)? {
        let tokens = line.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count >= 2 else { return nil }
        
        for i in 0..<(tokens.count - 1) {
            let kw = String(tokens[i])
            let rawNext = String(tokens[i + 1])
            let cleanName = rawNext.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
            guard cleanName.count >= 2 else { continue }
            let name = String(cleanName)
            
            switch kw {
            case "struct":
                return (name, name, name, 22, "struct \(name)")
            case "class", "actor":
                return (name, name, name, 7, "\(kw) \(name)")
            case "enum":
                return (name, name, name, 13, "enum \(name)")
            case "protocol", "trait", "interface":
                return (name, name, name, 8, "\(kw) \(name)")
            case "func", "fn", "def":
                if let parenStart = line.range(of: name + "(") {
                    let fromName = String(line[parenStart.lowerBound...])
                    if let closeParen = fromName.firstIndex(of: ")") {
                        let sig = String(fromName[...closeParen])
                        return (name, sig, "\(name)($0)", 3, "\(kw) \(sig)")
                    }
                }
                return (name, "\(name)()", "\(name)($0)", 3, "\(kw) \(name)()")
            case "var", "let", "const", "@State", "@Binding", "@Published", "@ObservedObject", "@StateObject", "@EnvironmentObject":
                if kw.hasPrefix("@") { continue }
                let cleanVar = name.replacingOccurrences(of: ":", with: "")
                return (cleanVar, cleanVar, cleanVar, 6, "\(kw) \(cleanVar)")
            default:
                continue
            }
        }
        return nil
    }
    
    // MARK: - Official Language SDK Signatures
    
    nonisolated private static let swiftUIMemberCompletions: [CompletionItem] = [
        CompletionItem(label: "frame(width:height:alignment:)", kind: 2, detail: "-> some View", documentation: "Positions this view within an invisible frame with the specified size.", insertText: "frame(width: ${1:100}, height: ${2:100})", filterText: "frame"),
        CompletionItem(label: "frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)", kind: 2, detail: "-> some View", documentation: "Positions this view within an invisible frame having the specified size constraints.", insertText: "frame(minWidth: ${1:0}, maxWidth: ${2:.infinity}, minHeight: ${3:0}, maxHeight: ${4:.infinity})", filterText: "frame"),
        CompletionItem(label: "frame(maxWidth:maxHeight:alignment:)", kind: 2, detail: "-> some View", documentation: "Flexible frame constraint for responsive SwiftUI layouts.", insertText: "frame(maxWidth: ${1:.infinity}, maxHeight: ${2:.infinity})", filterText: "frame"),
        CompletionItem(label: "padding(_:_:)", kind: 2, detail: "-> some View", documentation: "Adds an equal padding amount to specific edges of this view.", insertText: "padding(${1:.all}, ${2:12})", filterText: "padding"),
        CompletionItem(label: "padding(_:)", kind: 2, detail: "-> some View", documentation: "Adds a specific padding amount to each edge of this view.", insertText: "padding(${1:12})", filterText: "padding"),
        CompletionItem(label: "background(_:)", kind: 2, detail: "-> some View", documentation: "Layers the given style or view behind this view.", insertText: "background(${1:Color.clear})", filterText: "background"),
        CompletionItem(label: "foregroundStyle(_:)", kind: 2, detail: "-> some View", documentation: "Sets a view's foreground elements to use a given style.", insertText: "foregroundStyle(${1:.primary})", filterText: "foregroundStyle"),
        CompletionItem(label: "foregroundColor(_:)", kind: 2, detail: "-> some View", documentation: "Sets the color of the foreground elements displayed by this view.", insertText: "foregroundColor(${1:.primary})", filterText: "foregroundColor"),
        CompletionItem(label: "font(_:)", kind: 2, detail: "-> some View", documentation: "Sets the default font for text in this view.", insertText: "font(.system(size: ${1:13}, weight: ${2:.regular}))", filterText: "font"),
        CompletionItem(label: "fontWeight(_:)", kind: 2, detail: "-> some View", documentation: "Sets the font weight of the text in this view.", insertText: "fontWeight(.${1:semibold})", filterText: "fontWeight"),
        CompletionItem(label: "cornerRadius(_:)", kind: 2, detail: "-> some View", documentation: "Clips this view to its bounding frame, with the specified corner radius.", insertText: "cornerRadius(${1:8})", filterText: "cornerRadius"),
        CompletionItem(label: "clipShape(_:)", kind: 2, detail: "-> some View", documentation: "Sets a clipping shape for this view.", insertText: "clipShape(RoundedRectangle(cornerRadius: ${1:8}))", filterText: "clipShape"),
        CompletionItem(label: "overlay(_:)", kind: 2, detail: "-> some View", documentation: "Layers a secondary view or shape in front of this view.", insertText: "overlay(\n    ${1:RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1)}\n)", filterText: "overlay"),
        CompletionItem(label: "shadow(color:radius:x:y:)", kind: 2, detail: "-> some View", documentation: "Adds a shadow to this view.", insertText: "shadow(color: .black.opacity(0.2), radius: ${1:8}, x: 0, y: ${2:4})", filterText: "shadow"),
        CompletionItem(label: "onAppear(perform:)", kind: 2, detail: "-> some View", documentation: "Adds an action to perform before this view appears.", insertText: "onAppear {\n    $0\n}", filterText: "onAppear"),
        CompletionItem(label: "onDisappear(perform:)", kind: 2, detail: "-> some View", documentation: "Adds an action to perform after this view disappears.", insertText: "onDisappear {\n    $0\n}", filterText: "onDisappear"),
        CompletionItem(label: "onChange(of:perform:)", kind: 2, detail: "-> some View", documentation: "Adds an action to perform when the specified value changes.", insertText: "onChange(of: ${1:value}) { newValue in\n    $0\n}", filterText: "onChange"),
        CompletionItem(label: "task(priority:_:)", kind: 2, detail: "-> some View", documentation: "Adds an asynchronous task to perform before this view appears.", insertText: "task {\n    $0\n}", filterText: "task"),
        CompletionItem(label: "sheet(isPresented:content:)", kind: 2, detail: "-> some View", documentation: "Presents a sheet when a binding to a Boolean value that you provide is true.", insertText: "sheet(isPresented: $${1:isPresented}) {\n    $0\n}", filterText: "sheet"),
        CompletionItem(label: "alert(_:isPresented:actions:)", kind: 2, detail: "-> some View", documentation: "Presents an alert when a given condition is true.", insertText: "alert(\"${1:Title}\", isPresented: $${2:showAlert}) {\n    Button(\"OK\", role: .cancel) {}\n}", filterText: "alert"),
        CompletionItem(label: "buttonStyle(_:)", kind: 2, detail: "-> some View", documentation: "Sets the style for buttons within this view.", insertText: "buttonStyle(.${1:plain})", filterText: "buttonStyle"),
        CompletionItem(label: "textFieldStyle(_:)", kind: 2, detail: "-> some View", documentation: "Sets the style for text fields within this view.", insertText: "textFieldStyle(.${1:plain})", filterText: "textFieldStyle"),
        CompletionItem(label: "lineLimit(_:)", kind: 2, detail: "-> some View", documentation: "Sets the maximum number of lines that text can occupy in this view.", insertText: "lineLimit(${1:1})", filterText: "lineLimit"),
        CompletionItem(label: "opacity(_:)", kind: 2, detail: "-> some View", documentation: "Sets the transparency of this view.", insertText: "opacity(${1:0.8})", filterText: "opacity"),
        CompletionItem(label: "disabled(_:)", kind: 2, detail: "-> some View", documentation: "Adds a condition that controls whether users can interact with this view.", insertText: "disabled(${1:false})", filterText: "disabled"),
        CompletionItem(label: "environmentObject(_:)", kind: 2, detail: "-> some View", documentation: "Supplies an ObservableObject to a view subhierarchy.", insertText: "environmentObject(${1:model})", filterText: "environmentObject"),
        CompletionItem(label: "animation(_:value:)", kind: 2, detail: "-> some View", documentation: "Applies the given animation to this view when the specified value changes.", insertText: "animation(.easeInOut(duration: 0.2), value: ${1:state})", filterText: "animation"),
        CompletionItem(label: "onTapGesture(perform:)", kind: 2, detail: "-> some View", documentation: "Adds an action to perform when this view recognizes a tap gesture.", insertText: "onTapGesture {\n    $0\n}", filterText: "onTapGesture"),
        CompletionItem(label: "onHover(perform:)", kind: 2, detail: "-> some View", documentation: "Adds an action to perform when the user moves the pointer over or away from the view's frame.", insertText: "onHover { hovering in\n    $0\n}", filterText: "onHover"),
        CompletionItem(label: "help(_:)", kind: 2, detail: "-> some View", documentation: "Adds help text (tooltip) to a view on macOS.", insertText: "help(\"${1:Tooltip}\")", filterText: "help"),
        CompletionItem(label: "toolbar(content:)", kind: 2, detail: "-> some View", documentation: "Populates the toolbar or navigation bar with the specified items.", insertText: "toolbar {\n    $0\n}", filterText: "toolbar"),
        CompletionItem(label: "navigationTitle(_:)", kind: 2, detail: "-> some View", documentation: "Configures the view's title for purposes of navigation.", insertText: "navigationTitle(\"${1:Title}\")", filterText: "navigationTitle"),
        CompletionItem(label: "ignoresSafeArea(_:edges:)", kind: 2, detail: "-> some View", documentation: "Expands the view out of its safe area.", insertText: "ignoresSafeArea()", filterText: "ignoresSafeArea"),
        CompletionItem(label: "contentShape(_:)", kind: 2, detail: "-> some View", documentation: "Defines the content shape for hit testing.", insertText: "contentShape(Rectangle())", filterText: "contentShape"),
        CompletionItem(label: "offset(x:y:)", kind: 2, detail: "-> some View", documentation: "Offset this view by the horizontal and vertical amount specified.", insertText: "offset(x: ${1:0}, y: ${2:0})", filterText: "offset"),
        CompletionItem(label: "zIndex(_:)", kind: 2, detail: "-> some View", documentation: "Controls the display order of overlapping views.", insertText: "zIndex(${1:1})", filterText: "zIndex"),
        CompletionItem(label: "infinity", kind: 20, detail: "CGFloat", documentation: "Positive infinity, commonly used in .frame(maxWidth: .infinity).", insertText: "infinity", filterText: "infinity"),
        CompletionItem(label: "leading", kind: 20, detail: "Alignment", documentation: "Leading edge alignment.", insertText: "leading", filterText: "leading"),
        CompletionItem(label: "trailing", kind: 20, detail: "Alignment", documentation: "Trailing edge alignment.", insertText: "trailing", filterText: "trailing"),
        CompletionItem(label: "center", kind: 20, detail: "Alignment", documentation: "Center alignment.", insertText: "center", filterText: "center"),
        CompletionItem(label: "horizontal", kind: 20, detail: "Edge.Set", documentation: "Horizontal edges (leading and trailing).", insertText: "horizontal", filterText: "horizontal"),
        CompletionItem(label: "vertical", kind: 20, detail: "Edge.Set", documentation: "Vertical edges (top and bottom).", insertText: "vertical", filterText: "vertical"),
        CompletionItem(label: "primary", kind: 10, detail: "Color", documentation: "The color to use for primary content.", insertText: "primary", filterText: "primary"),
        CompletionItem(label: "secondary", kind: 10, detail: "Color", documentation: "The color to use for secondary content.", insertText: "secondary", filterText: "secondary"),
        CompletionItem(label: "accentColor", kind: 10, detail: "Color", documentation: "The application's accent color.", insertText: "accentColor", filterText: "accentColor"),
        CompletionItem(label: "windowBackgroundColor", kind: 10, detail: "NSColor", documentation: "The color to use for the window background.", insertText: "windowBackgroundColor", filterText: "windowBackgroundColor"),
        CompletionItem(label: "map(_:)", kind: 2, detail: "([T]) -> [U]", documentation: "Returns an array containing the results of mapping the given closure over the sequence's elements.", insertText: "map { $0 }", filterText: "map"),
        CompletionItem(label: "filter(_:)", kind: 2, detail: "([T]) -> [T]", documentation: "Returns an array containing, in order, the elements of the sequence that satisfy the given predicate.", insertText: "filter { $0 }", filterText: "filter"),
        CompletionItem(label: "compactMap(_:)", kind: 2, detail: "([T]) -> [U]", documentation: "Returns an array containing the non-nil results of calling the given transformation.", insertText: "compactMap { $0 }", filterText: "compactMap"),
        CompletionItem(label: "first(where:)", kind: 2, detail: "Element?", documentation: "Returns the first element of the sequence that satisfies the given predicate.", insertText: "first(where: { $0 })", filterText: "first"),
        CompletionItem(label: "contains(_:)", kind: 2, detail: "Bool", documentation: "Returns a Boolean value indicating whether the sequence contains the given element.", insertText: "contains(${1:element})", filterText: "contains"),
        CompletionItem(label: "append(_:)", kind: 2, detail: "Void", documentation: "Adds a new element at the end of the array.", insertText: "append(${1:newElement})", filterText: "append"),
        CompletionItem(label: "trimmingCharacters(in:)", kind: 2, detail: "String", documentation: "Returns a new string made by removing from both ends characters contained in a given character set.", insertText: "trimmingCharacters(in: .whitespacesAndNewlines)", filterText: "trimmingCharacters"),
        CompletionItem(label: "lowercased()", kind: 2, detail: "String", documentation: "Returns a lowercase version of the string.", insertText: "lowercased()", filterText: "lowercased"),
        CompletionItem(label: "uppercased()", kind: 2, detail: "String", documentation: "Returns an uppercase version of the string.", insertText: "uppercased()", filterText: "uppercased"),
        CompletionItem(label: "isEmpty", kind: 10, detail: "Bool", documentation: "A Boolean value indicating whether the collection is empty.", insertText: "isEmpty", filterText: "isEmpty"),
        CompletionItem(label: "count", kind: 10, detail: "Int", documentation: "The number of elements in the collection.", insertText: "count", filterText: "count")
    ]
    
    nonisolated private static let swiftTopLevelCompletions: [CompletionItem] = [
        CompletionItem(label: "VStack", kind: 22, detail: "SwiftUI View", documentation: "A view that arranges its subviews in a vertical line.", insertText: "VStack(alignment: .leading, spacing: ${1:8}) {\n    $0\n}", filterText: "VStack"),
        CompletionItem(label: "HStack", kind: 22, detail: "SwiftUI View", documentation: "A view that arranges its subviews in a horizontal line.", insertText: "HStack(spacing: ${1:8}) {\n    $0\n}", filterText: "HStack"),
        CompletionItem(label: "ZStack", kind: 22, detail: "SwiftUI View", documentation: "A view that overlays its subviews, aligning them in both axes.", insertText: "ZStack {\n    $0\n}", filterText: "ZStack"),
        CompletionItem(label: "LazyVStack", kind: 22, detail: "SwiftUI View", documentation: "A view that arranges its children in a line that grows vertically, creating items only as needed.", insertText: "LazyVStack(alignment: .leading, spacing: ${1:8}) {\n    $0\n}", filterText: "LazyVStack"),
        CompletionItem(label: "LazyHStack", kind: 22, detail: "SwiftUI View", documentation: "A view that arranges its children in a line that grows horizontally, creating items only as needed.", insertText: "LazyHStack(spacing: ${1:8}) {\n    $0\n}", filterText: "LazyHStack"),
        CompletionItem(label: "ScrollView", kind: 22, detail: "SwiftUI View", documentation: "A scrollable view.", insertText: "ScrollView {\n    $0\n}", filterText: "ScrollView"),
        CompletionItem(label: "List", kind: 22, detail: "SwiftUI View", documentation: "A container that presents rows of data arranged in a single column.", insertText: "List {\n    $0\n}", filterText: "List"),
        CompletionItem(label: "ForEach", kind: 22, detail: "SwiftUI View", documentation: "A structure that computes views on demand from an underlying collection of identified data.", insertText: "ForEach(${1:items}) { item in\n    $0\n}", filterText: "ForEach"),
        CompletionItem(label: "Button", kind: 22, detail: "SwiftUI View", documentation: "A control that initiates an action.", insertText: "Button(action: {\n    $0\n}) {\n    Text(\"${1:Label}\")\n}", filterText: "Button"),
        CompletionItem(label: "Text", kind: 22, detail: "SwiftUI View", documentation: "A view that displays one or more lines of read-only text.", insertText: "Text(\"${1:text}\")", filterText: "Text"),
        CompletionItem(label: "TextField", kind: 22, detail: "SwiftUI View", documentation: "A control that displays an editable text interface.", insertText: "TextField(\"${1:Placeholder}\", text: $${2:text})", filterText: "TextField"),
        CompletionItem(label: "Image(systemName:)", kind: 22, detail: "SwiftUI View", documentation: "Creates a system symbol image (SF Symbols).", insertText: "Image(systemName: \"${1:star.fill}\")", filterText: "Image"),
        CompletionItem(label: "Spacer", kind: 22, detail: "SwiftUI View", documentation: "A flexible space that expands along the major axis of its containing stack layout.", insertText: "Spacer()", filterText: "Spacer"),
        CompletionItem(label: "Divider", kind: 22, detail: "SwiftUI View", documentation: "A visual element that can be used to separate other content.", insertText: "Divider()", filterText: "Divider"),
        CompletionItem(label: "NavigationSplitView", kind: 22, detail: "SwiftUI View", documentation: "A view that presents views in two or three columns.", insertText: "NavigationSplitView {\n    $0\n} detail: {\n    \n}", filterText: "NavigationSplitView"),
        CompletionItem(label: "HSplitView", kind: 22, detail: "SwiftUI View", documentation: "A layout container that arranges its children horizontally with draggable dividers.", insertText: "HSplitView {\n    $0\n}", filterText: "HSplitView"),
        CompletionItem(label: "VSplitView", kind: 22, detail: "SwiftUI View", documentation: "A layout container that arranges its children vertically with draggable dividers.", insertText: "VSplitView {\n    $0\n}", filterText: "VSplitView"),
        CompletionItem(label: "WindowGroup", kind: 22, detail: "SwiftUI Scene", documentation: "A scene that presents a group of identically structured windows.", insertText: "WindowGroup {\n    $0\n}", filterText: "WindowGroup"),
        CompletionItem(label: "RoundedRectangle(cornerRadius:)", kind: 22, detail: "Shape", documentation: "A rectangular shape with rounded corners.", insertText: "RoundedRectangle(cornerRadius: ${1:8})", filterText: "RoundedRectangle"),
        CompletionItem(label: "Color", kind: 22, detail: "SwiftUI Color", documentation: "A representation of a color that adapts to a given context.", insertText: "Color", filterText: "Color"),
        CompletionItem(label: "@State", kind: 14, detail: "Property Wrapper", documentation: "A property wrapper type that can read and write a value managed by SwiftUI.", insertText: "@State private var ${1:name}: ${2:Bool} = ${3:false}", filterText: "@State"),
        CompletionItem(label: "@Binding", kind: 14, detail: "Property Wrapper", documentation: "A property wrapper type that can read and write a value owned by a source of truth.", insertText: "@Binding var ${1:name}: ${2:String}", filterText: "@Binding"),
        CompletionItem(label: "@Published", kind: 14, detail: "Combine Wrapper", documentation: "A type that publishes a property marked with an attribute.", insertText: "@Published var ${1:name}: ${2:String} = ${3:\"\"}", filterText: "@Published"),
        CompletionItem(label: "@StateObject", kind: 14, detail: "Property Wrapper", documentation: "A property wrapper type that instantiates an observable object.", insertText: "@StateObject private var ${1:viewModel} = ${2:ViewModel}()", filterText: "@StateObject"),
        CompletionItem(label: "@ObservedObject", kind: 14, detail: "Property Wrapper", documentation: "A property wrapper type that subscribes to an observable object.", insertText: "@ObservedObject var ${1:viewModel}: ${2:ViewModel}", filterText: "@ObservedObject"),
        CompletionItem(label: "@EnvironmentObject", kind: 14, detail: "Property Wrapper", documentation: "A property wrapper type for an observable object supplied by a parent or ancestor view.", insertText: "@EnvironmentObject var ${1:appState}: ${2:AppState}", filterText: "@EnvironmentObject"),
        CompletionItem(label: "@Environment", kind: 14, detail: "Property Wrapper", documentation: "A property wrapper that reads a value from a view's environment.", insertText: "@Environment(\\.${1:dismiss}) private var ${1:dismiss}", filterText: "@Environment"),
        CompletionItem(label: "@MainActor", kind: 14, detail: "Global Actor", documentation: "A singleton actor whose executor is equivalent to the main dispatch queue.", insertText: "@MainActor", filterText: "@MainActor"),
        CompletionItem(label: "struct", kind: 14, detail: "Declaration", documentation: "Declares a value-type structure.", insertText: "struct ${1:Name} {\n    $0\n}", filterText: "struct"),
        CompletionItem(label: "class", kind: 14, detail: "Declaration", documentation: "Declares a reference-type class.", insertText: "class ${1:Name} {\n    $0\n}", filterText: "class"),
        CompletionItem(label: "enum", kind: 14, detail: "Declaration", documentation: "Declares an enumeration.", insertText: "enum ${1:Name} {\n    case $0\n}", filterText: "enum"),
        CompletionItem(label: "protocol", kind: 14, detail: "Declaration", documentation: "Declares a protocol interface.", insertText: "protocol ${1:Name} {\n    $0\n}", filterText: "protocol"),
        CompletionItem(label: "extension", kind: 14, detail: "Declaration", documentation: "Adds new functionality to an existing type.", insertText: "extension ${1:Type} {\n    $0\n}", filterText: "extension"),
        CompletionItem(label: "func", kind: 14, detail: "Function", documentation: "Declares a function or method.", insertText: "func ${1:name}(${2}) {\n    $0\n}", filterText: "func"),
        CompletionItem(label: "guard", kind: 14, detail: "Control Flow", documentation: "Early exit statement if condition is not met.", insertText: "guard ${1:let value = optional} else { return }", filterText: "guard"),
        CompletionItem(label: "Task", kind: 22, detail: "Concurrency", documentation: "A unit of asynchronous work.", insertText: "Task {\n    $0\n}", filterText: "Task"),
        CompletionItem(label: "DispatchQueue.main.async", kind: 3, detail: "Grand Central Dispatch", documentation: "Schedules a block for asynchronous execution on the main queue.", insertText: "DispatchQueue.main.async {\n    $0\n}", filterText: "DispatchQueue"),
        CompletionItem(label: "URLSession.shared.data(for:)", kind: 3, detail: "async throws -> (Data, URLResponse)", documentation: "Downloads the contents of a URL based on the specified URL request.", insertText: "URLSession.shared.data(for: ${1:request})", filterText: "URLSession"),
        CompletionItem(label: "print(_:)", kind: 3, detail: "Swift.print", documentation: "Writes the textual representations of the given items into the standard output.", insertText: "print(${1:value})", filterText: "print"),
        CompletionItem(label: "String", kind: 22, detail: "Swift.String", documentation: "A Unicode string value that is a collection of characters.", insertText: "String", filterText: "String"),
        CompletionItem(label: "Int", kind: 22, detail: "Swift.Int", documentation: "A signed integer value type.", insertText: "Int", filterText: "Int"),
        CompletionItem(label: "Double", kind: 22, detail: "Swift.Double", documentation: "A double-precision, floating-point value type.", insertText: "Double", filterText: "Double"),
        CompletionItem(label: "Bool", kind: 22, detail: "Swift.Bool", documentation: "A value type whose instances are either true or false.", insertText: "Bool", filterText: "Bool"),
        CompletionItem(label: "CGFloat", kind: 22, detail: "CoreFoundation", documentation: "The basic type for floating-point scalar values in Core Graphics.", insertText: "CGFloat", filterText: "CGFloat"),
        CompletionItem(label: "UUID", kind: 22, detail: "Foundation", documentation: "A universally unique value that can be used to identify types, interfaces, and other items.", insertText: "UUID()", filterText: "UUID")
    ]
    
    nonisolated private static let rustTopLevelCompletions: [CompletionItem] = [
        CompletionItem(label: "fn", kind: 14, detail: "fn name() {}", documentation: "Declares a Rust function.", insertText: "fn ${1:name}(${2}) {\n    $0\n}", filterText: "fn"),
        CompletionItem(label: "pub fn", kind: 14, detail: "pub fn name() {}", documentation: "Declares a public Rust function.", insertText: "pub fn ${1:name}(${2}) {\n    $0\n}", filterText: "pub"),
        CompletionItem(label: "struct", kind: 22, detail: "struct Name {}", documentation: "Declares a Rust struct.", insertText: "struct ${1:Name} {\n    $0\n}", filterText: "struct"),
        CompletionItem(label: "enum", kind: 13, detail: "enum Name {}", documentation: "Declares a Rust enum.", insertText: "enum ${1:Name} {\n    $0\n}", filterText: "enum"),
        CompletionItem(label: "impl", kind: 14, detail: "impl Type {}", documentation: "Implements methods or traits for a type.", insertText: "impl ${1:Type} {\n    $0\n}", filterText: "impl"),
        CompletionItem(label: "match", kind: 14, detail: "Pattern Matching", documentation: "Exhaustive pattern matching control flow.", insertText: "match ${1:expr} {\n    $0\n}", filterText: "match"),
        CompletionItem(label: "println!", kind: 3, detail: "Macro", documentation: "Prints to the standard output, with a newline.", insertText: "println!(\"${1:{}}\", ${2:val});", filterText: "println"),
        CompletionItem(label: "format!", kind: 3, detail: "Macro -> String", documentation: "Creates a String using interpolation of runtime expressions.", insertText: "format!(\"${1:{}}\", ${2:val})", filterText: "format"),
        CompletionItem(label: "vec!", kind: 3, detail: "Macro -> Vec<T>", documentation: "Creates a Vec containing the arguments.", insertText: "vec![$0]", filterText: "vec"),
        CompletionItem(label: "Result", kind: 13, detail: "Result<T, E>", documentation: "Error handling with the Result type.", insertText: "Result<${1:T}, ${2:Error}>", filterText: "Result"),
        CompletionItem(label: "Option", kind: 13, detail: "Option<T>", documentation: "Optional value: Some(T) or None.", insertText: "Option<${1:T}>", filterText: "Option"),
        CompletionItem(label: "String", kind: 22, detail: "std::string::String", documentation: "A UTF-8–encoded, growable string.", insertText: "String", filterText: "String"),
        CompletionItem(label: "Vec", kind: 22, detail: "std::vec::Vec<T>", documentation: "A contiguous growable array type.", insertText: "Vec<${1:T}>", filterText: "Vec"),
        CompletionItem(label: "HashMap", kind: 22, detail: "std::collections::HashMap", documentation: "A hash map implemented with quadratic probing and SIMD lookup.", insertText: "HashMap<${1:K}, ${2:V}>", filterText: "HashMap"),
        CompletionItem(label: "Arc", kind: 22, detail: "std::sync::Arc<T>", documentation: "A thread-safe reference-counting pointer.", insertText: "Arc::new(${1:val})", filterText: "Arc"),
        CompletionItem(label: "tokio::spawn", kind: 3, detail: "JoinHandle<T>", documentation: "Spawns a new asynchronous task on the Tokio runtime.", insertText: "tokio::spawn(async move {\n    $0\n});", filterText: "tokio")
    ]
    
    nonisolated private static let rustMemberCompletions: [CompletionItem] = [
        CompletionItem(label: "unwrap()", kind: 2, detail: "-> T", documentation: "Returns the contained Some or Ok value, panicking if None or Err.", insertText: "unwrap()", filterText: "unwrap"),
        CompletionItem(label: "expect(msg)", kind: 2, detail: "-> T", documentation: "Returns the contained value or panics with a custom message.", insertText: "expect(\"${1:failed}\")", filterText: "expect"),
        CompletionItem(label: "unwrap_or_default()", kind: 2, detail: "-> T", documentation: "Returns the contained value or the default for that type.", insertText: "unwrap_or_default()", filterText: "unwrap_or_default"),
        CompletionItem(label: "map(f)", kind: 2, detail: "Iterator / Option / Result", documentation: "Maps a value or iterator by applying a function.", insertText: "map(|${1:x}| $0)", filterText: "map"),
        CompletionItem(label: "and_then(f)", kind: 2, detail: "Option / Result", documentation: "Calls op if the value is Some/Ok, otherwise returns None/Err.", insertText: "and_then(|${1:x}| $0)", filterText: "and_then"),
        CompletionItem(label: "collect()", kind: 2, detail: "-> B", documentation: "Transforms an iterator into a collection.", insertText: "collect::<Vec<_>>()", filterText: "collect"),
        CompletionItem(label: "iter()", kind: 2, detail: "-> Iter<'_, T>", documentation: "Returns an iterator over the slice.", insertText: "iter()", filterText: "iter"),
        CompletionItem(label: "clone()", kind: 2, detail: "-> Self", documentation: "Returns a copy of the value.", insertText: "clone()", filterText: "clone"),
        CompletionItem(label: "to_string()", kind: 2, detail: "-> String", documentation: "Converts the given value to a String.", insertText: "to_string()", filterText: "to_string"),
        CompletionItem(label: "as_str()", kind: 2, detail: "-> &str", documentation: "Extracts a string slice containing the entire String.", insertText: "as_str()", filterText: "as_str"),
        CompletionItem(label: "is_empty()", kind: 2, detail: "-> bool", documentation: "Returns true if the collection contains no elements.", insertText: "is_empty()", filterText: "is_empty"),
        CompletionItem(label: "len()", kind: 2, detail: "-> usize", documentation: "Returns the number of elements.", insertText: "len()", filterText: "len"),
        CompletionItem(label: "push(value)", kind: 2, detail: "-> ()", documentation: "Appends an element to the back of a collection.", insertText: "push(${1:val})", filterText: "push"),
        CompletionItem(label: "await", kind: 14, detail: "Future.await", documentation: "Suspends execution until the result of a Future is ready.", insertText: "await", filterText: "await")
    ]
    
    nonisolated private static let tsTopLevelCompletions: [CompletionItem] = [
        CompletionItem(label: "function", kind: 14, detail: "function name() {}", documentation: "Declares a JavaScript/TypeScript function.", insertText: "function ${1:name}(${2}) {\n    $0\n}", filterText: "function"),
        CompletionItem(label: "async function", kind: 14, detail: "async function name() {}", documentation: "Declares an asynchronous function.", insertText: "async function ${1:name}(${2}) {\n    $0\n}", filterText: "async"),
        CompletionItem(label: "const", kind: 14, detail: "const name = value", documentation: "Declares a block-scoped constant.", insertText: "const ${1:name} = ${2:value};", filterText: "const"),
        CompletionItem(label: "let", kind: 14, detail: "let name = value", documentation: "Declares a block-scoped mutable variable.", insertText: "let ${1:name} = ${2:value};", filterText: "let"),
        CompletionItem(label: "interface", kind: 8, detail: "TypeScript Interface", documentation: "Declares a TypeScript interface.", insertText: "interface ${1:Name} {\n    $0\n}", filterText: "interface"),
        CompletionItem(label: "type", kind: 8, detail: "TypeScript Type Alias", documentation: "Declares a TypeScript type alias.", insertText: "type ${1:Name} = ${2:string};", filterText: "type"),
        CompletionItem(label: "console.log", kind: 3, detail: "(...data: any[]) => void", documentation: "Prints to stdout with newline.", insertText: "console.log(${1:value});", filterText: "console"),
        CompletionItem(label: "document.querySelector", kind: 3, detail: "(selector: string) => Element | null", documentation: "Returns the first Element within the document that matches the specified selector.", insertText: "document.querySelector('${1:selector}')", filterText: "document"),
        CompletionItem(label: "document.getElementById", kind: 3, detail: "(id: string) => HTMLElement | null", documentation: "Returns a reference to the first object with the specified value of the ID attribute.", insertText: "document.getElementById('${1:id}')", filterText: "document"),
        CompletionItem(label: "fetch", kind: 3, detail: "(input: RequestInfo) => Promise<Response>", documentation: "Starts the process of fetching a resource from the network.", insertText: "fetch('${1:/api}')", filterText: "fetch"),
        CompletionItem(label: "Promise", kind: 7, detail: "Promise<T>", documentation: "Represents the completion or failure of an asynchronous operation.", insertText: "new Promise((resolve, reject) => {\n    $0\n})", filterText: "Promise"),
        CompletionItem(label: "useState", kind: 3, detail: "React Hook", documentation: "Returns a stateful value, and a function to update it.", insertText: "const [${1:state}, set${1:State}] = useState(${2:initialValue});", filterText: "useState"),
        CompletionItem(label: "useEffect", kind: 3, detail: "React Hook", documentation: "Accepts a function that contains imperative, possibly effectful code.", insertText: "useEffect(() => {\n    $0\n}, []);", filterText: "useEffect"),
        CompletionItem(label: "JSON.stringify", kind: 3, detail: "(value: any) => string", documentation: "Converts a JavaScript value to a JavaScript Object Notation (JSON) string.", insertText: "JSON.stringify(${1:value})", filterText: "JSON"),
        CompletionItem(label: "JSON.parse", kind: 3, detail: "(text: string) => any", documentation: "Converts a JSON string into an object.", insertText: "JSON.parse(${1:text})", filterText: "JSON")
    ]
    
    nonisolated private static let tsMemberCompletions: [CompletionItem] = [
        CompletionItem(label: "log(...data)", kind: 2, detail: "console.log", documentation: "Outputs a message to the console.", insertText: "log(${1:value})", filterText: "log"),
        CompletionItem(label: "error(...data)", kind: 2, detail: "console.error", documentation: "Outputs an error message to the console.", insertText: "error(${1:err})", filterText: "error"),
        CompletionItem(label: "querySelector(selector)", kind: 2, detail: "-> Element | null", documentation: "Returns the first matching Element node within the node's subtree.", insertText: "querySelector('${1:.class}')", filterText: "querySelector"),
        CompletionItem(label: "getElementById(id)", kind: 2, detail: "-> HTMLElement | null", documentation: "Returns a reference to the element by its ID.", insertText: "getElementById('${1:id}')", filterText: "getElementById"),
        CompletionItem(label: "addEventListener(type, listener)", kind: 2, detail: "EventTarget", documentation: "Appends an event listener for events whose type attribute value is type.", insertText: "addEventListener('${1:click}', (event) => {\n    $0\n})", filterText: "addEventListener"),
        CompletionItem(label: "map(callback)", kind: 2, detail: "Array<U>", documentation: "Calls a defined callback function on each element of an array, and returns an array that contains the results.", insertText: "map((${1:item}) => $0)", filterText: "map"),
        CompletionItem(label: "filter(predicate)", kind: 2, detail: "Array<T>", documentation: "Returns the elements of an array that meet the condition specified in a callback function.", insertText: "filter((${1:item}) => $0)", filterText: "filter"),
        CompletionItem(label: "forEach(callback)", kind: 2, detail: "void", documentation: "Performs the specified action for each element in an array.", insertText: "forEach((${1:item}) => {\n    $0\n})", filterText: "forEach"),
        CompletionItem(label: "reduce(callback, initialValue)", kind: 2, detail: "U", documentation: "Calls the specified callback function for all the elements in an array.", insertText: "reduce((acc, ${1:item}) => $0, ${2:0})", filterText: "reduce"),
        CompletionItem(label: "find(predicate)", kind: 2, detail: "T | undefined", documentation: "Returns the value of the first element in the array where predicate is true.", insertText: "find((${1:item}) => $0)", filterText: "find"),
        CompletionItem(label: "includes(searchElement)", kind: 2, detail: "boolean", documentation: "Determines whether an array/string includes a certain element.", insertText: "includes(${1:value})", filterText: "includes"),
        CompletionItem(label: "push(...items)", kind: 2, detail: "number", documentation: "Appends new elements to the end of an array.", insertText: "push(${1:item})", filterText: "push"),
        CompletionItem(label: "then(onfulfilled)", kind: 2, detail: "Promise", documentation: "Attaches callbacks for the resolution and/or rejection of the Promise.", insertText: "then((${1:res}) => $0)", filterText: "then"),
        CompletionItem(label: "catch(onrejected)", kind: 2, detail: "Promise", documentation: "Attaches a callback for only the rejection of the Promise.", insertText: "catch((${1:err}) => $0)", filterText: "catch"),
        CompletionItem(label: "json()", kind: 2, detail: "Promise<any>", documentation: "Reads a Response stream to completion and parses as JSON.", insertText: "json()", filterText: "json"),
        CompletionItem(label: "length", kind: 10, detail: "number", documentation: "Gets or sets the length of the array or string.", insertText: "length", filterText: "length"),
        CompletionItem(label: "textContent", kind: 10, detail: "string | null", documentation: "Represents the text content of the node and its descendants.", insertText: "textContent", filterText: "textContent"),
        CompletionItem(label: "innerHTML", kind: 10, detail: "string", documentation: "Gets or sets the HTML markup contained within the element.", insertText: "innerHTML", filterText: "innerHTML"),
        CompletionItem(label: "classList", kind: 10, detail: "DOMTokenList", documentation: "Returns the class attribute of the element as a DOMTokenList.", insertText: "classList", filterText: "classList")
    ]
    
    nonisolated private static let pythonTopLevelCompletions: [CompletionItem] = [
        CompletionItem(label: "def", kind: 14, detail: "def func():", documentation: "Defines a Python function.", insertText: "def ${1:name}(${2}):\n    $0", filterText: "def"),
        CompletionItem(label: "async def", kind: 14, detail: "async def func():", documentation: "Defines an asynchronous coroutine function.", insertText: "async def ${1:name}(${2}):\n    $0", filterText: "async"),
        CompletionItem(label: "class", kind: 7, detail: "class Name:", documentation: "Defines a Python class.", insertText: "class ${1:Name}:\n    def __init__(self${2}):\n        $0", filterText: "class"),
        CompletionItem(label: "import", kind: 14, detail: "Module Import", documentation: "Imports a Python module.", insertText: "import ${1:os}", filterText: "import"),
        CompletionItem(label: "from ... import", kind: 14, detail: "Symbol Import", documentation: "Imports specific symbols from a module.", insertText: "from ${1:typing} import ${2:List, Dict, Optional}", filterText: "from"),
        CompletionItem(label: "print(value)", kind: 3, detail: "Built-in Function", documentation: "Prints the values to a stream, or to sys.stdout by default.", insertText: "print(${1:value})", filterText: "print"),
        CompletionItem(label: "len(obj)", kind: 3, detail: "-> int", documentation: "Return the number of items in a container.", insertText: "len(${1:obj})", filterText: "len"),
        CompletionItem(label: "enumerate(iterable)", kind: 3, detail: "-> enumerate", documentation: "Return an enumerate object yielding (index, value) pairs.", insertText: "enumerate(${1:items})", filterText: "enumerate"),
        CompletionItem(label: "range(stop)", kind: 3, detail: "-> range", documentation: "Return an immutable sequence of numbers.", insertText: "range(${1:10})", filterText: "range"),
        CompletionItem(label: "isinstance(obj, classinfo)", kind: 3, detail: "-> bool", documentation: "Return whether an object is an instance of a class or of a subclass thereof.", insertText: "isinstance(${1:obj}, ${2:type})", filterText: "isinstance"),
        CompletionItem(label: "open(file, mode)", kind: 3, detail: "-> TextIOWrapper", documentation: "Open file and return a stream.", insertText: "open(${1:\"file.txt\"}, \"${2:r}\", encoding=\"utf-8\")", filterText: "open")
    ]
    
    nonisolated private static let pythonMemberCompletions: [CompletionItem] = [
        CompletionItem(label: "append(object)", kind: 2, detail: "list.append -> None", documentation: "Append object to the end of the list.", insertText: "append(${1:item})", filterText: "append"),
        CompletionItem(label: "extend(iterable)", kind: 2, detail: "list.extend -> None", documentation: "Extend list by appending elements from the iterable.", insertText: "extend(${1:items})", filterText: "extend"),
        CompletionItem(label: "get(key, default)", kind: 2, detail: "dict.get -> Any", documentation: "Return the value for key if key is in the dictionary, else default.", insertText: "get(${1:key}, ${2:None})", filterText: "get"),
        CompletionItem(label: "items()", kind: 2, detail: "dict.items", documentation: "Return a set-like object providing a view on D's items.", insertText: "items()", filterText: "items"),
        CompletionItem(label: "keys()", kind: 2, detail: "dict.keys", documentation: "Return a set-like object providing a view on D's keys.", insertText: "keys()", filterText: "keys"),
        CompletionItem(label: "values()", kind: 2, detail: "dict.values", documentation: "Return an object providing a view on D's values.", insertText: "values()", filterText: "values"),
        CompletionItem(label: "split(sep)", kind: 2, detail: "str.split -> list[str]", documentation: "Return a list of the substrings in the string, using sep as the separator string.", insertText: "split(${1})", filterText: "split"),
        CompletionItem(label: "join(iterable)", kind: 2, detail: "str.join -> str", documentation: "Concatenate any number of strings.", insertText: "join(${1:items})", filterText: "join"),
        CompletionItem(label: "strip()", kind: 2, detail: "str.strip -> str", documentation: "Return a copy of the string with leading and trailing whitespace removed.", insertText: "strip()", filterText: "strip"),
        CompletionItem(label: "replace(old, new)", kind: 2, detail: "str.replace -> str", documentation: "Return a copy with all occurrences of substring old replaced by new.", insertText: "replace(${1:old}, ${2:new})", filterText: "replace"),
        CompletionItem(label: "startswith(prefix)", kind: 2, detail: "str.startswith -> bool", documentation: "Return True if S starts with the specified prefix.", insertText: "startswith(${1:prefix})", filterText: "startswith"),
        CompletionItem(label: "endswith(suffix)", kind: 2, detail: "str.endswith -> bool", documentation: "Return True if S ends with the specified suffix.", insertText: "endswith(${1:suffix})", filterText: "endswith")
    ]
    
    nonisolated private static let htmlCompletions: [CompletionItem] = [
        CompletionItem(label: "div", kind: 15, detail: "<div>...</div>", documentation: "Generic flow container element.", insertText: "<div class=\"${1:container}\">\n    $0\n</div>", filterText: "div"),
        CompletionItem(label: "button", kind: 15, detail: "<button>...</button>", documentation: "Interactive button element.", insertText: "<button type=\"button\" id=\"${1:btn}\">${2:Click}</button>", filterText: "button"),
        CompletionItem(label: "input", kind: 15, detail: "<input />", documentation: "Interactive form input control.", insertText: "<input type=\"${1:text}\" placeholder=\"${2:Enter...}\" />", filterText: "input"),
        CompletionItem(label: "section", kind: 15, detail: "<section>...</section>", documentation: "Standalone document section.", insertText: "<section class=\"${1:section}\">\n    $0\n</section>", filterText: "section"),
        CompletionItem(label: "script", kind: 15, detail: "<script>...</script>", documentation: "Embeds executable JavaScript.", insertText: "<script src=\"${1:app.js}\"></script>", filterText: "script"),
        CompletionItem(label: "link", kind: 15, detail: "<link rel=\"stylesheet\" />", documentation: "External resource link element.", insertText: "<link rel=\"stylesheet\" href=\"${1:styles.css}\" />", filterText: "link")
    ]
    
    nonisolated private static let cssCompletions: [CompletionItem] = [
        CompletionItem(label: "display: flex", kind: 10, detail: "CSS Flexbox", documentation: "Enables flex container layout.", insertText: "display: flex;", filterText: "display"),
        CompletionItem(label: "display: grid", kind: 10, detail: "CSS Grid", documentation: "Enables grid container layout.", insertText: "display: grid;", filterText: "display"),
        CompletionItem(label: "justify-content", kind: 10, detail: "CSS Alignment", documentation: "Defines alignment along the main axis.", insertText: "justify-content: ${1:space-between};", filterText: "justify-content"),
        CompletionItem(label: "align-items", kind: 10, detail: "CSS Alignment", documentation: "Defines alignment along the cross axis.", insertText: "align-items: ${1:center};", filterText: "align-items"),
        CompletionItem(label: "background", kind: 10, detail: "CSS Background", documentation: "Shorthand background property.", insertText: "background: ${1:#111827};", filterText: "background"),
        CompletionItem(label: "border-radius", kind: 10, detail: "CSS Corners", documentation: "Rounds the corners of an element's outer border edge.", insertText: "border-radius: ${1:12px};", filterText: "border-radius"),
        CompletionItem(label: "padding", kind: 10, detail: "CSS Box Model", documentation: "Sets the padding area on all four sides of an element.", insertText: "padding: ${1:12px 16px};", filterText: "padding"),
        CompletionItem(label: "gap", kind: 10, detail: "CSS Grid/Flex Gap", documentation: "Sets the gaps (gutters) between rows and columns.", insertText: "gap: ${1:12px};", filterText: "gap"),
        CompletionItem(label: "color", kind: 10, detail: "CSS Text Color", documentation: "Sets the foreground color value of an element's text.", insertText: "color: ${1:#f9fafb};", filterText: "color"),
        CompletionItem(label: "font-size", kind: 10, detail: "CSS Typography", documentation: "Sets the size of the font.", insertText: "font-size: ${1:14px};", filterText: "font-size"),
        CompletionItem(label: "box-shadow", kind: 10, detail: "CSS Elevation", documentation: "Adds shadow effects around an element's frame.", insertText: "box-shadow: 0 10px 25px rgba(0, 0, 0, 0.25);", filterText: "box-shadow"),
        CompletionItem(label: "transition", kind: 10, detail: "CSS Animation", documentation: "Transitions between two states of an element.", insertText: "transition: all 0.2s ease;", filterText: "transition")
    ]
    
    nonisolated private static let goCompletions: [CompletionItem] = [
        CompletionItem(label: "func", kind: 14, detail: "func name() {}", documentation: "Declares a Go function.", insertText: "func ${1:name}(${2}) {\n\t$0\n}", filterText: "func"),
        CompletionItem(label: "fmt.Println", kind: 3, detail: "(a ...any) (n int, err error)", documentation: "Formats using the default formats for its operands and writes to standard output.", insertText: "fmt.Println(${1:val})", filterText: "Println"),
        CompletionItem(label: "fmt.Sprintf", kind: 3, detail: "(format string, a ...any) string", documentation: "Formats according to a format specifier and returns the resulting string.", insertText: "fmt.Sprintf(\"${1:%v}\", ${2:val})", filterText: "Sprintf"),
        CompletionItem(label: "type ... struct", kind: 22, detail: "Go Struct", documentation: "Declares a Go struct type.", insertText: "type ${1:Name} struct {\n\t$0\n}", filterText: "type")
    ]
    
    nonisolated private static let cppCompletions: [CompletionItem] = [
        CompletionItem(label: "std::vector", kind: 7, detail: "<vector>", documentation: "Sequence container that encapsulates dynamic size arrays.", insertText: "std::vector<${1:int}>", filterText: "vector"),
        CompletionItem(label: "std::string", kind: 7, detail: "<string>", documentation: "Standard C++ string class.", insertText: "std::string", filterText: "string"),
        CompletionItem(label: "std::cout", kind: 6, detail: "<iostream>", documentation: "Standard output stream.", insertText: "std::cout << ${1:val} << std::endl;", filterText: "cout"),
        CompletionItem(label: "std::make_unique", kind: 3, detail: "<memory>", documentation: "Constructs an object and wraps it in a std::unique_ptr.", insertText: "std::make_unique<${1:Type}>(${2})", filterText: "make_unique")
    ]
    
    nonisolated private static let ardiumCompletions: [CompletionItem] = [
        CompletionItem(label: "fn", kind: 14, detail: "Ardium Function", documentation: "Declares an Ardium function.", insertText: "fn ${1:name}(${2}) {\n    $0\n}", filterText: "fn"),
        CompletionItem(label: "struct", kind: 22, detail: "Ardium Struct", documentation: "Declares an Ardium struct.", insertText: "struct ${1:Name} {\n    $0\n}", filterText: "struct"),
        CompletionItem(label: "print", kind: 3, detail: "fn print(value)", documentation: "Prints a value to standard output in Ardium.", insertText: "print(${1:\"Hello\"});", filterText: "print"),
        CompletionItem(label: "@owned", kind: 14, detail: "RAII Ownership", documentation: "Ardium RAII ownership attribute.", insertText: "@owned", filterText: "@owned")
    ]
}

// MARK: - SwiftUI Integration

/// View modifier to enable LSP features
struct LSPEnabledModifier: ViewModifier {
    @StateObject private var lspManager = LSPManager.shared
    
    func body(content: Content) -> some View {
        content
            .environmentObject(lspManager)
    }
}

extension View {
    func lspEnabled() -> some View {
        modifier(LSPEnabledModifier())
    }
}
