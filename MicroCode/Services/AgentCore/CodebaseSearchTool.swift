//
//  CodebaseSearchTool.swift
//  MicroCode
//
//  Hybrid BM25 + Symbol Graph Codebase Search Engine for Autonomous AI Agents.
//  Combines incremental RepoMap symbol definition ranking, CamelCase/snake_case
//  sub-token tokenization, file-path relevance, and multi-core BM25 code chunk
//  scoring with enclosing-symbol attribution.
//

import Foundation

final class HybridCodebaseSearchEngine: @unchecked Sendable {
    static let shared = HybridCodebaseSearchEngine()

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "where", "what",
        "when", "which", "how", "does", "are", "was", "were", "into", "onto",
        "about", "all", "any", "can", "use", "used", "using", "find", "show",
        "get", "set", "code", "file", "files", "function", "method", "class"
    ]

    struct RankedSymbolHit {
        let symbol: RepoSymbol
        let score: Double
        let isExact: Bool
    }

    struct RankedChunkHit {
        let relativePath: String
        let startLine: Int
        let endLine: Int
        let enclosingSymbol: String?
        let score: Double
        let snippet: String
    }

    /// Splits identifiers and natural-language queries into normalized sub-tokens
    /// (e.g., `reconcileCoreSimulatorStorage` -> `["reconcile", "core", "simulator", "storage"]`).
    static func tokenize(_ raw: String, dropStopWords: Bool = true) -> [String] {
        var expanded = ""
        expanded.reserveCapacity(raw.count + 16)
        let scalars = Array(raw.unicodeScalars)
        for i in scalars.indices {
            let cur = scalars[i]
            if i > 0 {
                let prev = scalars[i - 1]
                let prevIsLower = CharacterSet.lowercaseLetters.contains(prev)
                let curIsUpper = CharacterSet.uppercaseLetters.contains(cur)
                let prevIsUpper = CharacterSet.uppercaseLetters.contains(prev)
                let nextIsLower: Bool = (i + 1 < scalars.count) && CharacterSet.lowercaseLetters.contains(scalars[i + 1])
                if (prevIsLower && curIsUpper) || (prevIsUpper && curIsUpper && nextIsLower) {
                    expanded.append(" ")
                }
            }
            if CharacterSet.alphanumerics.contains(cur) || cur.value > 127 {
                expanded.unicodeScalars.append(cur)
            } else {
                expanded.append(" ")
            }
        }

        var seen = Set<String>()
        var result: [String] = []
        for part in expanded.lowercased().split(separator: " ") {
            let token = String(part)
            guard token.count >= 2 else { continue }
            if dropStopWords && stopWords.contains(token) { continue }
            if seen.insert(token).inserted {
                result.append(token)
            }
        }
        if result.isEmpty {
            // Fallback without stop-word filtering if query consisted only of short/common terms
            for part in expanded.lowercased().split(separator: " ") {
                let token = String(part)
                if !token.isEmpty && seen.insert(token).inserted {
                    result.append(token)
                }
            }
        }
        return result
    }

    /// Hybrid BM25 + Symbol Graph search across a workspace
    func searchCodebase(
        query: String,
        workspace: String,
        maxResults: Int = 8,
        fileFilter: String? = nil
    ) async -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return "Empty search query." }

        let canonicalWorkspace = URL(fileURLWithPath: workspace).standardizedFileURL.path
        let repoMap = await RepoMapService.shared.getRepoMap(workspace: canonicalWorkspace)
        let queryTokens = Self.tokenize(trimmedQuery, dropStopWords: true)
        let rawQueryLower = trimmedQuery.lowercased()
        let compactIdentifierQuery = trimmedQuery
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .lowercased()

        let allowedExtensions: Set<String>? = {
            guard let f = fileFilter?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty else { return nil }
            return Set(f.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ".", with: "").lowercased() }.filter { !$0.isEmpty })
        }()

        let candidateFiles = repoMap.files.filter { entry in
            if let exts = allowedExtensions {
                return exts.contains(entry.extension_.lowercased())
            }
            return true
        }

        // 1. Score Symbol Graph Definitions
        var symbolHits: [RankedSymbolHit] = []
        for file in candidateFiles {
            let pathLower = file.relativePath.lowercased()
            for sym in file.symbols {
                let symLower = sym.name.lowercased()
                let sigLower = sym.signature.lowercased()
                var score: Double = 0
                var isExact = false

                if symLower == rawQueryLower || symLower == compactIdentifierQuery {
                    score += 65.0
                    isExact = true
                } else if symLower.hasPrefix(compactIdentifierQuery) && compactIdentifierQuery.count >= 3 {
                    score += 38.0
                } else if symLower.contains(compactIdentifierQuery) && compactIdentifierQuery.count >= 3 {
                    score += 26.0
                }

                let symTokens = Set(Self.tokenize(sym.name, dropStopWords: false))
                var matchedTokens = 0
                for qt in queryTokens {
                    if symTokens.contains(qt) {
                        score += 14.0
                        matchedTokens += 1
                    } else if symLower.contains(qt) {
                        score += 8.0
                        matchedTokens += 1
                    } else if sigLower.contains(qt) {
                        score += 4.0
                        matchedTokens += 1
                    } else if pathLower.contains(qt) {
                        score += 3.0
                    }
                }
                if queryTokens.count >= 2 && matchedTokens == queryTokens.count {
                    score += 18.0
                }
                if score >= 12.0 {
                    symbolHits.append(RankedSymbolHit(symbol: sym, score: score, isExact: isExact))
                }
            }
        }
        symbolHits.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.symbol.filePath < $1.symbol.filePath
        }
        let topSymbols = Array(symbolHits.prefix(min(10, maxResults + 2)))

        // 2. Parallel BM25 Window Scoring across candidate source files
        let chunkHits: [RankedChunkHit] = await PerformanceManager.shared.runOnECore {
            guard !queryTokens.isEmpty else { return [] }

            struct FileScanResult {
                let entry: RepoFileEntry
                let lines: [String]
                let termLineHits: [String: [Int]]
                let termFreq: [String: Int]
            }

            let maxScanBytes: UInt64 = 512 * 1024
            let scanned: [FileScanResult] = PerformanceManager.parallelMap(candidateFiles, minItemsPerCore: 6) { entry in
                guard entry.sizeBytes > 0 && entry.sizeBytes <= maxScanBytes else { return nil }
                let fullPath = (canonicalWorkspace as NSString).appendingPathComponent(entry.relativePath)
                guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { return nil }
                let contentLower = content.lowercased()
                let pathLower = entry.relativePath.lowercased()

                var hasAnyMatch = rawQueryLower.count >= 3 && (contentLower.contains(rawQueryLower) || pathLower.contains(rawQueryLower))
                if !hasAnyMatch {
                    for qt in queryTokens where contentLower.contains(qt) || pathLower.contains(qt) {
                        hasAnyMatch = true
                        break
                    }
                }
                guard hasAnyMatch else { return nil }

                let lines = content.components(separatedBy: "\n")
                var termLineHits: [String: [Int]] = [:]
                var termFreq: [String: Int] = [:]

                for (idx, line) in lines.enumerated() {
                    let ll = line.lowercased()
                    for qt in queryTokens where ll.contains(qt) {
                        termLineHits[qt, default: []].append(idx)
                        termFreq[qt, default: 0] += 1
                    }
                }
                if termFreq.isEmpty && !pathLower.isEmpty {
                    // Matched only path name: expose header window
                    return FileScanResult(entry: entry, lines: lines, termLineHits: [:], termFreq: [:])
                }
                return FileScanResult(entry: entry, lines: lines, termLineHits: termLineHits, termFreq: termFreq)
            }.compactMap { $0 }

            guard !scanned.isEmpty else { return [] }

            // Compute IDF across workspace corpus
            let totalDocs = Double(max(candidateFiles.count, scanned.count))
            var idf: [String: Double] = [:]
            for qt in queryTokens {
                let df = Double(scanned.filter { ($0.termFreq[qt] ?? 0) > 0 }.count)
                idf[qt] = log(1.0 + (totalDocs - df + 0.5) / (df + 0.5))
            }

            let avgLines = max(40.0, Double(scanned.reduce(0) { $0 + $1.lines.count }) / Double(scanned.count))
            let k1 = 1.5
            let b = 0.75
            let windowRadius = 12

            var allChunks: [RankedChunkHit] = []
            for doc in scanned {
                let lineCount = doc.lines.count
                guard lineCount > 0 else { continue }
                let pathLower = doc.entry.relativePath.lowercased()
                var pathBonus: Double = 0
                for qt in queryTokens where pathLower.contains(qt) {
                    pathBonus += 4.5 * (idf[qt] ?? 1.0)
                }

                // Collect candidate anchor lines
                var anchorLines = Set<Int>()
                for (_, idxs) in doc.termLineHits {
                    for i in idxs.prefix(40) { anchorLines.insert(i) }
                }
                if anchorLines.isEmpty && pathBonus > 0 {
                    anchorLines.insert(0)
                }

                let sortedAnchors = anchorLines.sorted()
                var fileWindows: [RankedChunkHit] = []
                var lastEnd = -100

                for anchor in sortedAnchors {
                    if anchor <= lastEnd - 6 { continue }
                    let wStart = max(0, anchor - 6)
                    let wEnd = min(lineCount - 1, anchor + windowRadius + 6)
                    let winLen = Double(wEnd - wStart + 1)

                    var windowTermCounts: [String: Int] = [:]
                    var exactPhraseHits = 0
                    for li in wStart...wEnd {
                        let ll = doc.lines[li].lowercased()
                        if rawQueryLower.count >= 4 && ll.contains(rawQueryLower) {
                            exactPhraseHits += 1
                        }
                        for qt in queryTokens where ll.contains(qt) {
                            windowTermCounts[qt, default: 0] += 1
                        }
                    }

                    var bm25: Double = pathBonus + Double(exactPhraseHits) * 14.0
                    for (qt, tfCount) in windowTermCounts {
                        let tf = Double(tfCount)
                        let termIDF = idf[qt] ?? 1.0
                        let norm = tf * (k1 + 1.0) / (tf + k1 * (1.0 - b + b * (winLen / min(avgLines, 60.0))))
                        bm25 += termIDF * norm * 3.0
                    }

                    // Multi-term co-occurrence proximity bonus
                    if queryTokens.count >= 2 && windowTermCounts.count >= 2 {
                        let coverage = Double(windowTermCounts.count) / Double(queryTokens.count)
                        bm25 += coverage * 16.0
                    }

                    // Enclosing symbol lookup & bonus
                    let midLine1Indexed = anchor + 1
                    let enclosing = doc.entry.symbols
                        .filter { $0.line <= midLine1Indexed + 3 }
                        .max(by: { $0.line < $1.line })
                    if let enc = enclosing {
                        let encLower = enc.name.lowercased()
                        for qt in queryTokens where encLower.contains(qt) {
                            bm25 += 5.5
                        }
                    }

                    guard bm25 >= 5.0 else { continue }
                    lastEnd = wEnd

                    var snippetLines: [String] = []
                    snippetLines.reserveCapacity(wEnd - wStart + 1)
                    for li in wStart...wEnd {
                        let rawLine = doc.lines[li]
                        let clipped = rawLine.count > 220 ? String(rawLine.prefix(220)) + "…" : rawLine
                        snippetLines.append("\(li + 1): \(clipped)")
                    }

                    fileWindows.append(
                        RankedChunkHit(
                            relativePath: doc.entry.relativePath,
                            startLine: wStart + 1,
                            endLine: wEnd + 1,
                            enclosingSymbol: enclosing.map { "\($0.kind) \($0.name)" },
                            score: bm25,
                            snippet: snippetLines.joined(separator: "\n")
                        )
                    )
                }

                // Keep top 2 windows per file so a single huge file doesn't crowd out other modules
                fileWindows.sort { $0.score > $1.score }
                allChunks.append(contentsOf: fileWindows.prefix(2))
            }

            allChunks.sort {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.relativePath < $1.relativePath
            }
            return Array(allChunks.prefix(maxResults))
        }

        if topSymbols.isEmpty && chunkHits.isEmpty {
            return "No codebase matches found for '\(trimmedQuery)' in \(canonicalWorkspace)."
        }

        var out: [String] = []
        out.append("# Hybrid Codebase Search: \"\(trimmedQuery)\"")
        out.append("Workspace: \(canonicalWorkspace) | Indexed Files: \(repoMap.totalFiles) | Indexed Symbols: \(repoMap.totalSymbols)")

        if !topSymbols.isEmpty {
            out.append("\n## [SYMBOL DEFINITIONS]")
            for hit in topSymbols {
                let s = hit.symbol
                let tag = hit.isExact ? "EXACT" : String(format: "%.1f", hit.score)
                out.append("- [\(tag)] `\(s.filePath):\(s.line)` (\(s.kind)) — `\(s.signature)`")
            }
        }

        if !chunkHits.isEmpty {
            out.append("\n## [RANKED CODE CHUNKS (BM25 + Proximity)]")
            for (idx, chunk) in chunkHits.enumerated() {
                let symHeader = chunk.enclosingSymbol.map { " | in `\($0)`" } ?? ""
                out.append("\n### \(idx + 1). `\(chunk.relativePath):\(chunk.startLine)-\(chunk.endLine)`\(symHeader) (score: \(String(format: "%.1f", chunk.score)))")
                out.append("```")
                out.append(chunk.snippet)
                out.append("```")
            }
        }

        return out.joined(separator: "\n")
    }

    /// Ranked Symbol Definition + Reference lookup for `find_symbol`
    func searchSymbolDefinitionsAndReferences(
        symbol: String,
        symbolType: String,
        directory: String
    ) async -> String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Symbol name is required." }

        let canonicalDir = URL(fileURLWithPath: directory).standardizedFileURL.path
        let repoMap = await RepoMapService.shared.getRepoMap(workspace: canonicalDir)
        let symLower = trimmed.lowercased()
        let normalizedKindFilter: Set<String>? = {
            let t = symbolType.lowercased()
            switch t {
            case "function", "func", "method": return ["function", "method"]
            case "class": return ["class", "actor", "interface", "protocol", "trait"]
            case "struct": return ["struct"]
            case "enum": return ["enum"]
            default: return nil
            }
        }()

        var exactDefs: [RepoSymbol] = []
        var partialDefs: [RepoSymbol] = []

        for file in repoMap.files {
            for s in file.symbols {
                if let allowedKinds = normalizedKindFilter, !allowedKinds.contains(s.kind.lowercased()) {
                    continue
                }
                let candidateLower = s.name.lowercased()
                if candidateLower == symLower {
                    exactDefs.append(s)
                } else if candidateLower.contains(symLower) {
                    partialDefs.append(s)
                }
            }
        }

        // Fast bounded reference scan via grep (skipping heavy build dirs)
        let escaped = NSRegularExpression.escapedPattern(for: trimmed)
        let pattern = "\\b\(escaped)\\b"
        let grepProcess = Process()
        grepProcess.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        var args = ["-rn", "--color=never", "-I", "-E"]
        for dir in GrepSearchTool.excludedDirs {
            args.append("--exclude-dir=\(dir)")
        }
        args.append(contentsOf: ["-m", "15", "-e", pattern, canonicalDir])
        grepProcess.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        grepProcess.standardInput = FileHandle.nullDevice
        grepProcess.standardOutput = outPipe
        grepProcess.standardError = errPipe

        var referenceLines: [String] = []
        if (try? grepProcess.run()) != nil {
            async let stdoutData = Task.detached { outPipe.fileHandleForReading.readDataToEndOfFile() }.value
            async let stderrData = Task.detached { errPipe.fileHandleForReading.readDataToEndOfFile() }.value
            let data = await stdoutData
            _ = await stderrData
            while grepProcess.isRunning {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            let rawOut = String(data: data, encoding: .utf8) ?? ""
            let defKeys = Set((exactDefs + partialDefs).map { "\($0.filePath):\($0.line)" })
            let prefix = canonicalDir.hasSuffix("/") ? canonicalDir : canonicalDir + "/"
            for rawLine in rawOut.split(separator: "\n").prefix(60) {
                var lineStr = String(rawLine)
                if lineStr.hasPrefix(prefix) {
                    lineStr = String(lineStr.dropFirst(prefix.count))
                }
                // Check if this line is already listed in definitions
                let parts = lineStr.split(separator: ":", maxSplits: 2)
                if parts.count >= 2 {
                    let key = "\(parts[0]):\(parts[1])"
                    if defKeys.contains(key) { continue }
                }
                referenceLines.append(lineStr.count > 220 ? String(lineStr.prefix(220)) + "…" : lineStr)
                if referenceLines.count >= 30 { break }
            }
        }

        if exactDefs.isEmpty && partialDefs.isEmpty && referenceLines.isEmpty {
            return "No symbols or references matching '\(trimmed)' found in \(canonicalDir)"
        }

        var report: [String] = []
        if !exactDefs.isEmpty {
            report.append("## [DEFINITIONS — Exact Match (\(exactDefs.count))]")
            for d in exactDefs.prefix(25) {
                report.append("- `\(d.filePath):\(d.line)` [\(d.kind)] `\(d.signature)`")
            }
        }
        if !partialDefs.isEmpty {
            report.append("\n## [DEFINITIONS — Related Symbols (\(min(partialDefs.count, 15)))]")
            for d in partialDefs.prefix(15) {
                report.append("- `\(d.filePath):\(d.line)` [\(d.kind)] `\(d.signature)`")
            }
        }
        if !referenceLines.isEmpty {
            report.append("\n## [REFERENCES & CALL SITES (showing \(referenceLines.count))]")
            report.append(contentsOf: referenceLines)
        }
        return report.joined(separator: "\n")
    }
}

// MARK: - Agent Tool: codebase_search

struct CodebaseSearchTool: AgentTool {
    let name = "codebase_search"
    let description = """
        Hybrid semantic + BM25 + symbol-graph codebase search. Finds relevant symbol definitions, \
        functions, types, and ranked source code chunks across the workspace from natural-language \
        concepts or partial identifiers (e.g. 'simulator storage fallback', 'token compression boundary'). \
        Use this first when exploring unfamiliar code or locating feature implementations.
        """
    let parameters = [
        ToolParameter(name: "query", type: "string", description: "Natural-language concept, feature description, or symbol keywords to search for", required: true),
        ToolParameter(name: "directory", type: "string", description: "Directory to search in (optional, defaults to active workspace root)", required: false),
        ToolParameter(name: "max_results", type: "integer", description: "Maximum ranked code chunks to return (default: 8, max: 20)", required: false),
        ToolParameter(name: "filter", type: "string", description: "Optional comma-separated file extension filter (e.g. 'swift' or 'rs,ts')", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        let queryOpt = (params["query"] as? String)
            ?? (params["pattern"] as? String)
            ?? (params["symbol"] as? String)
        let defaultRoot = await MainActor.run { AgentToolBox.shared.effectiveWorkspaceRoot }
        let directoryOpt = (params["directory"] as? String)
            ?? (params["path"] as? String)
            ?? defaultRoot

        guard let query = queryOpt?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            throw ToolBoxError.invalidParams("query is required")
        }
        guard let directory = directoryOpt, !directory.isEmpty else {
            throw ToolBoxError.invalidParams("directory is required")
        }

        let requestedMax = (params["max_results"] as? Int) ?? 8
        let boundedMax = max(1, min(20, requestedMax))
        let filter = params["filter"] as? String

        return await HybridCodebaseSearchEngine.shared.searchCodebase(
            query: query,
            workspace: directory,
            maxResults: boundedMax,
            fileFilter: filter
        )
    }
}
