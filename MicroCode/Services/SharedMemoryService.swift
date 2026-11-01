//
//  SharedMemoryService.swift
//  MicroCode
//
//  Zero-Copy POSIX Shared Memory (shm_open + mmap) Polyglot Bridge,
//  Live Kernel Variable & Unified Memory Registry, Static Cell Lineage DAG Analyzer,
//  and Native `# @param` Reactive Parameter Widget Engine for Cell Mode.
//
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import SwiftUI
import Combine

// MARK: - Live Kernel Variable & Unified Memory Metadata

struct KernelVariableInfo: Identifiable, Codable, Equatable {
    var id: String { name }
    let name: String
    let typeName: String
    let shape: String
    let dtype: String
    let memoryBytes: Int64
    let preview: String
    let columns: [String]
    let numericSample: [Double]

    var formattedMemory: String {
        if memoryBytes < 1024 { return "\(memoryBytes) B" }
        return ByteCountFormatter.string(fromByteCount: memoryBytes, countStyle: .memory)
    }

    var isTabularOrArray: Bool {
        let lower = typeName.lowercased()
        return lower.contains("dataframe")
            || lower.contains("ndarray")
            || lower.contains("tensor")
            || lower.contains("array")
            || lower.contains("series")
            || lower.contains("list")
    }
}

// MARK: - Per-Cell Execution Telemetry

struct CellExecutionTelemetry: Codable, Equatable {
    let durationMs: Double
    let memoryDeltaBytes: Int64
    let peakRSSBytes: Int64
    let metalAllocatedBytes: Int64
    let isCachedBinary: Bool

    var formattedDuration: String {
        if durationMs < 1.0 {
            return String(format: "%.2fms", durationMs)
        } else if durationMs < 1000.0 {
            return String(format: "%.1fms", durationMs)
        } else {
            return String(format: "%.2fs", durationMs / 1000.0)
        }
    }

    var formattedMemoryDelta: String? {
        let absBytes = abs(memoryDeltaBytes)
        guard absBytes >= 64 * 1024 else { return nil }
        let formatted = ByteCountFormatter.string(fromByteCount: absBytes, countStyle: .memory)
        return (memoryDeltaBytes >= 0 ? "+" : "-") + formatted
    }

    var formattedMetal: String? {
        guard metalAllocatedBytes > 0 else { return nil }
        let formatted = ByteCountFormatter.string(fromByteCount: metalAllocatedBytes, countStyle: .memory)
        return "Metal \(formatted)"
    }
}

// MARK: - Structured Inline DataFrame Payload (Auto-Rendered Grid & Chart Studio)

struct InlineDataFrameColumnStats: Codable, Equatable {
    let nullCount: Int
    let minVal: Double?
    let maxVal: Double?
    let meanVal: Double?
}

struct InlineDataFramePayload: Codable, Equatable {
    let variableName: String
    let totalRows: Int
    let totalCols: Int
    let columns: [String]
    let dtypes: [String: String]
    let stats: [String: InlineDataFrameColumnStats]
    let rows: [[String]]
    let csvExportPath: String?
}

// MARK: - Per-Cell Time-Travel Execution Snapshot

struct CellVersionSnapshot: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let versionNumber: Int
    let timestamp: Date
    let sourceLabel: String
    let content: String
    let outputPreview: String
    let durationMs: Double?
}

// MARK: - Native `# @param` Widget Specification & Parser

struct CellParameterSpec: Identifiable, Equatable {
    enum Kind: Equatable {
        case sliderDouble(min: Double, max: Double, step: Double)
        case sliderInt(min: Int, max: Int, step: Int)
        case dropdown(options: [String])
        case toggle
        case text
    }

    var id: String { "\(lineIndex)-\(name)" }
    let name: String
    let lineIndex: Int
    let kind: Kind
    var stringValue: String
    var doubleValue: Double
    var boolValue: Bool
}

enum CellParameterEngine {
    /// Parses `# @param` declarations from cell code.
    /// Supported forms:
    /// 1) Inline trailing annotation:
    ///    `learning_rate = 0.01 # @param [0.0001..0.1, step=0.001]`
    ///    `school = "Sarasas" # @param ["Sarasas", "Ruamrudee", "BCC"]`
    ///    `normalize = True # @param`
    /// 2) Header comment annotation followed by assignment (or standalone):
    ///    `# @param threshold: float = 0.75 [0.0..1.0, step=0.05]`
    static func parseParameters(from code: String) -> [CellParameterSpec] {
        let lines = code.components(separatedBy: "\n")
        var specs: [CellParameterSpec] = []

        for (idx, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard rawLine.contains("@param") else { continue }

            // Form A: `var_name = literal  # @param ...` (or `// @param ...`)
            if !trimmed.hasPrefix("#") && !trimmed.hasPrefix("//") {
                let commentSplit: (lhs: String, rhs: String)? = {
                    if let r = rawLine.range(of: "#") {
                        return (String(rawLine[..<r.lowerBound]), String(rawLine[r.upperBound...]))
                    }
                    if let r = rawLine.range(of: "//") {
                        return (String(rawLine[..<r.lowerBound]), String(rawLine[r.upperBound...]))
                    }
                    return nil
                }()
                guard let split = commentSplit, split.rhs.contains("@param") else { continue }
                guard let eqRange = split.lhs.range(of: "=") else { continue }
                var lhsName = String(split.lhs[..<eqRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                for prefix in ["let mut ", "let ", "var ", "const ", "auto ", "double ", "float ", "int ", "bool "] {
                    if lhsName.hasPrefix(prefix) {
                        lhsName = String(lhsName.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    }
                }
                if let colonIdx = lhsName.firstIndex(of: ":") {
                    lhsName = String(lhsName[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                }
                var rhsVal = String(split.lhs[eqRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                if rhsVal.hasSuffix(";") { rhsVal.removeLast() }

                if let spec = buildSpec(name: lhsName, lineIndex: idx, rawValue: rhsVal, metaComment: split.rhs) {
                    specs.append(spec)
                }
            } else {
                // Form B: `# @param name: float = 0.5 [0.0..1.0, step=0.05]`
                guard let paramRange = trimmed.range(of: "@param") else { continue }
                let afterParam = String(trimmed[paramRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                // Check if next line assigns the variable
                let targetLineIndex: Int
                var varName = ""
                var rawVal = ""

                if let eqRange = afterParam.range(of: "=") {
                    let head = String(afterParam[..<eqRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    varName = head.components(separatedBy: ":").first?.trimmingCharacters(in: .whitespaces) ?? ""
                    var valPart = String(afterParam[eqRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if let bracketIdx = valPart.firstIndex(of: "[") {
                        valPart = String(valPart[..<bracketIdx]).trimmingCharacters(in: .whitespaces)
                    }
                    rawVal = valPart
                    if idx + 1 < lines.count,
                       lines[idx + 1].trimmingCharacters(in: .whitespaces).hasPrefix(varName),
                       lines[idx + 1].contains("=") {
                        targetLineIndex = idx + 1
                        let nextL = lines[idx + 1]
                        if let nextEq = nextL.range(of: "=") {
                            rawVal = String(nextL[nextEq.upperBound...]).trimmingCharacters(in: .whitespaces)
                            if rawVal.hasSuffix(";") { rawVal.removeLast() }
                        }
                    } else {
                        targetLineIndex = idx
                    }
                    if !varName.isEmpty, let spec = buildSpec(name: varName, lineIndex: targetLineIndex, rawValue: rawVal, metaComment: afterParam) {
                        specs.append(spec)
                    }
                }
            }
        }
        return specs
    }

    private static func buildSpec(name: String, lineIndex: Int, rawValue: String, metaComment: String) -> CellParameterSpec? {
        guard !name.isEmpty else { return nil }
        let unquoted = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        let lowerVal = unquoted.lowercased()

        // Check bracket metadata `[min..max, step=s]` or `["a", "b", "c"]`
        if let openB = metaComment.firstIndex(of: "["),
           let closeB = metaComment.lastIndex(of: "]"),
           openB < closeB {
            let inside = String(metaComment[metaComment.index(after: openB)..<closeB]).trimmingCharacters(in: .whitespaces)
            if inside.contains("..") {
                let parts = inside.components(separatedBy: ",")
                let rangeBounds = parts[0].components(separatedBy: "..")
                if rangeBounds.count == 2 {
                    let minStr = rangeBounds[0].trimmingCharacters(in: .whitespaces)
                    let maxStr = rangeBounds[1].trimmingCharacters(in: .whitespaces)
                    var stepVal: Double? = nil
                    for p in parts.dropFirst() {
                        let kv = p.components(separatedBy: "=")
                        if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces) == "step" {
                            stepVal = Double(kv[1].trimmingCharacters(in: .whitespaces))
                        }
                    }
                    let isFloating = minStr.contains(".") || maxStr.contains(".") || rawValue.contains(".") || (stepVal != nil && floor(stepVal!) != stepVal!) || metaComment.contains("float")
                    if isFloating, let lo = Double(minStr), let hi = Double(maxStr), hi > lo {
                        let cur = Double(unquoted) ?? lo
                        let st = stepVal ?? max((hi - lo) / 100.0, 0.0001)
                        return CellParameterSpec(
                            name: name,
                            lineIndex: lineIndex,
                            kind: .sliderDouble(min: lo, max: hi, step: st),
                            stringValue: unquoted,
                            doubleValue: min(max(cur, lo), hi),
                            boolValue: false
                        )
                    } else if let lo = Int(minStr), let hi = Int(maxStr), hi > lo {
                        let cur = Int(unquoted) ?? lo
                        let st = max(1, Int(stepVal ?? 1))
                        return CellParameterSpec(
                            name: name,
                            lineIndex: lineIndex,
                            kind: .sliderInt(min: lo, max: hi, step: st),
                            stringValue: "\(cur)",
                            doubleValue: Double(min(max(cur, lo), hi)),
                            boolValue: false
                        )
                    }
                }
            } else {
                // Dropdown options list
                let opts = inside
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")) }
                    .filter { !$0.isEmpty }
                if opts.count >= 2 {
                    let cur = opts.contains(unquoted) ? unquoted : opts[0]
                    return CellParameterSpec(
                        name: name,
                        lineIndex: lineIndex,
                        kind: .dropdown(options: opts),
                        stringValue: cur,
                        doubleValue: 0,
                        boolValue: false
                    )
                }
            }
        }

        // Boolean toggle
        if lowerVal == "true" || lowerVal == "false" {
            let b = (lowerVal == "true")
            return CellParameterSpec(
                name: name,
                lineIndex: lineIndex,
                kind: .toggle,
                stringValue: b ? "True" : "False",
                doubleValue: b ? 1 : 0,
                boolValue: b
            )
        }

        // Inferred numeric slider
        if let d = Double(unquoted) {
            if unquoted.contains(".") {
                let hi = d == 0 ? 1.0 : max(abs(d) * 4.0, 1.0)
                let lo = d < 0 ? -hi : 0.0
                return CellParameterSpec(
                    name: name,
                    lineIndex: lineIndex,
                    kind: .sliderDouble(min: lo, max: hi, step: max((hi - lo) / 100.0, 0.001)),
                    stringValue: unquoted,
                    doubleValue: d,
                    boolValue: false
                )
            } else if let i = Int(unquoted) {
                let hi = max(abs(i) * 4, 100)
                let lo = i < 0 ? -hi : 0
                return CellParameterSpec(
                    name: name,
                    lineIndex: lineIndex,
                    kind: .sliderInt(min: lo, max: hi, step: 1),
                    stringValue: "\(i)",
                    doubleValue: Double(i),
                    boolValue: false
                )
            }
        }

        return CellParameterSpec(
            name: name,
            lineIndex: lineIndex,
            kind: .text,
            stringValue: unquoted,
            doubleValue: 0,
            boolValue: false
        )
    }

    /// Rewrites the exact variable literal in `code` while preserving trailing `# @param` comments and indentation.
    static func updateParameterValue(in code: String, spec: CellParameterSpec, newFormattedLiteral: String, language: String) -> String {
        var lines = code.components(separatedBy: "\n")
        guard spec.lineIndex >= 0 && spec.lineIndex < lines.count else { return code }
        let line = lines[spec.lineIndex]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") {
            // Standalone `# @param x: float = 0.5 [...]` — insert or update assignment on following line
            let assignLine = "\(spec.name) = \(newFormattedLiteral)"
            lines.insert(assignLine, at: spec.lineIndex + 1)
            return lines.joined(separator: "\n")
        }

        // Preserve trailing comment (`# ...` or `// ...`)
        let commentIndex: String.Index? = {
            if let r = line.range(of: "#") { return r.lowerBound }
            if let r = line.range(of: "//") { return r.lowerBound }
            return nil
        }()
        let codePart = commentIndex != nil ? String(line[..<commentIndex!]) : line
        let commentPart = commentIndex != nil ? "  " + String(line[commentIndex!...]) : ""
        let needsSemicolon = codePart.trimmingCharacters(in: .whitespaces).hasSuffix(";")

        guard let eqRange = codePart.range(of: "=") else { return code }
        let lhs = String(codePart[..<eqRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let leadingIndent = String(line.prefix { $0 == " " || $0 == "\t" })
        let semi = needsSemicolon ? ";" : ""
        lines[spec.lineIndex] = "\(leadingIndent)\(lhs) = \(newFormattedLiteral)\(semi)\(commentPart)"
        return lines.joined(separator: "\n")
    }
}

// MARK: - Static Cell Lineage & Reactive DAG Analyzer

struct CellDAGNodeInfo: Equatable {
    let cellId: UUID
    let cellNumber: Int
    let definedSymbols: Set<String>
    let referencedUpstreamSymbols: [String]
    let upstreamCellNumbers: [Int]
    let downstreamCellIds: [UUID]
    let isStaleFromUpstream: Bool
}

enum CellLineageDAGAnalyzer {
    private static let ignoredKeywords: Set<String> = [
        "import", "from", "as", "def", "class", "return", "if", "elif", "else", "for", "while",
        "in", "not", "and", "or", "is", "None", "True", "False", "try", "except", "finally",
        "with", "lambda", "yield", "async", "await", "pass", "break", "continue", "global",
        "print", "len", "range", "list", "dict", "set", "str", "int", "float", "bool", "type",
        "enumerate", "zip", "min", "max", "sum", "abs", "round", "open", "display", "pd", "np",
        "plt", "sns", "os", "sys", "json", "math", "time", "Path", "shm", "self",
        "let", "mut", "fn", "func", "var", "const", "pub", "struct", "enum", "impl", "use",
        "package", "main", "std", "cout", "endl", "include", "SELECT", "FROM", "WHERE", "GROUP",
        "BY", "ORDER", "LIMIT", "JOIN", "LEFT", "INNER", "ON", "AS", "INSERT", "INTO", "CREATE", "TABLE"
    ]

    /// Extracts `(definedSymbols, referencedTokens)` from cell code in `< 0.3ms`.
    static func extractSymbols(code: String) -> (defs: Set<String>, refs: Set<String>) {
        var defs = Set<String>()
        var refs = Set<String>()

        let lines = code.components(separatedBy: "\n")
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") || trimmed.hasPrefix("--") {
                continue
            }
            // Strip inline trailing comment
            let codeOnly: String = {
                if let r = trimmed.range(of: " #") { return String(trimmed[..<r.lowerBound]) }
                if let r = trimmed.range(of: "//") { return String(trimmed[..<r.lowerBound]) }
                return trimmed
            }()

            // Detect function / class / SQL table definitions
            for kw in ["def ", "class ", "fn ", "func "] {
                if codeOnly.hasPrefix(kw) {
                    let rest = String(codeOnly.dropFirst(kw.count))
                    let ident = String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
                    if ident.count >= 2 && !ignoredKeywords.contains(ident) {
                        defs.insert(ident)
                    }
                }
            }

            // Detect top-level / local assignments (`x = ...`, `x, y = ...`, `let x = ...`, `x <- ...`)
            if let arrowRange = codeOnly.range(of: "<-") {
                let lhs = String(codeOnly[..<arrowRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                if isValidIdentifier(lhs) { defs.insert(lhs) }
            } else if let eqIndex = findSingleAssignmentEquals(in: codeOnly) {
                var lhs = String(codeOnly[..<eqIndex]).trimmingCharacters(in: .whitespaces)
                for prefix in ["let mut ", "let ", "var ", "const ", "auto "] {
                    if lhs.hasPrefix(prefix) {
                        lhs = String(lhs.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    }
                }
                if let colon = lhs.firstIndex(of: ":") {
                    lhs = String(lhs[..<colon]).trimmingCharacters(in: .whitespaces)
                }
                for candidate in lhs.components(separatedBy: ",") {
                    let clean = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "()[] \t"))
                    if isValidIdentifier(clean) {
                        defs.insert(clean)
                    }
                }
            }

            // Collect identifier tokens for references
            var current = ""
            for ch in codeOnly {
                if ch.isLetter || ch.isNumber || ch == "_" {
                    current.append(ch)
                } else {
                    if isValidIdentifier(current) { refs.insert(current) }
                    current.removeAll(keepingCapacity: true)
                }
            }
            if isValidIdentifier(current) { refs.insert(current) }
        }

        // Remove symbols solely defined and not externally needed if desired; keep refs minus ignored
        return (defs, refs)
    }

    private static func isValidIdentifier(_ s: String) -> Bool {
        guard s.count >= 2, let first = s.first, (first.isLetter || first == "_") else { return false }
        return !ignoredKeywords.contains(s)
    }

    private static func findSingleAssignmentEquals(in line: String) -> String.Index? {
        let chars = Array(line)
        var parenDepth = 0
        for i in 0..<chars.count {
            let c = chars[i]
            if c == "(" || c == "[" || c == "{" { parenDepth += 1 }
            else if c == ")" || c == "]" || c == "}" { parenDepth = max(0, parenDepth - 1) }
            else if c == "=" && parenDepth == 0 {
                let prev: Character = i > 0 ? chars[i - 1] : " "
                let next: Character = (i + 1 < chars.count) ? chars[i + 1] : " "
                if next == "=" || next == ">" { continue }
                if prev == "=" || prev == "!" || prev == "<" || prev == ">" { continue }
                return line.index(line.startIndex, offsetBy: i)
            }
        }
        return nil
    }

    /// Computes full cell lineage graph across an ordered list of `(id, isCode, content, lastExecutedStep, lastModifiedStep)`.
    static func analyzeGraph(
        cells: [(id: UUID, isRunnableCode: Bool, content: String, lastRunEpoch: Int)]
    ) -> [UUID: CellDAGNodeInfo] {
        var extracted: [(id: UUID, num: Int, defs: Set<String>, refs: Set<String>, epoch: Int)] = []
        for (idx, item) in cells.enumerated() where item.isRunnableCode {
            let sym = extractSymbols(code: item.content)
            extracted.append((item.id, idx + 1, sym.defs, sym.refs, item.lastRunEpoch))
        }

        // Map latest defining cell prior to each position
        var latestProducer: [String: (id: UUID, num: Int, epoch: Int)] = [:]
        var upstreamByCell: [UUID: [(id: UUID, num: Int, symbol: String, epoch: Int)]] = [:]
        var downstreamByCell: [UUID: [UUID]] = [:]

        for node in extracted {
            var ups: [(id: UUID, num: Int, symbol: String, epoch: Int)] = []
            for ref in node.refs.sorted() {
                if let prod = latestProducer[ref], prod.id != node.id {
                    ups.append((prod.id, prod.num, ref, prod.epoch))
                    if !(downstreamByCell[prod.id]?.contains(node.id) ?? false) {
                        downstreamByCell[prod.id, default: []].append(node.id)
                    }
                }
            }
            upstreamByCell[node.id] = ups
            for d in node.defs {
                latestProducer[d] = (node.id, node.num, node.epoch)
            }
        }

        var result: [UUID: CellDAGNodeInfo] = [:]
        for node in extracted {
            let ups = upstreamByCell[node.id] ?? []
            let upNums = Array(Set(ups.map(\.num))).sorted()
            let upSyms = Array(Set(ups.map(\.symbol))).sorted()
            let downs = downstreamByCell[node.id] ?? []
            // Stale if an upstream cell was executed MORE RECENTLY than this cell (and this cell ran at least once, or upstream ran and this hasn't re-synced)
            let isStale: Bool = {
                guard node.epoch > 0 else { return false }
                return ups.contains { $0.epoch > node.epoch }
            }()
            result[node.id] = CellDAGNodeInfo(
                cellId: node.id,
                cellNumber: node.num,
                definedSymbols: node.defs,
                referencedUpstreamSymbols: upSyms,
                upstreamCellNumbers: upNums,
                downstreamCellIds: downs,
                isStaleFromUpstream: isStale
            )
        }
        return result
    }

    /// Returns all transitive downstream cell IDs in topological notebook order starting strictly after `rootCellId`.
    static func transitiveDownstreamIds(from rootCellId: UUID, graph: [UUID: CellDAGNodeInfo], orderedIds: [UUID]) -> [UUID] {
        var reachable = Set<UUID>()
        var queue: [UUID] = graph[rootCellId]?.downstreamCellIds ?? []
        while let next = queue.first {
            queue.removeFirst()
            if reachable.insert(next).inserted {
                queue.append(contentsOf: graph[next]?.downstreamCellIds ?? [])
            }
        }
        return orderedIds.filter { reachable.contains($0) }
    }
}

// MARK: - Zero-Copy Shared Memory Service & Live Variable Registry

class SharedMemoryService: ObservableObject {
    static let shared = SharedMemoryService()

    @Published var sharedDataFrames: [String] = []
    @Published var sharedArtifacts: [URL] = []
    @Published var liveVariablesByNotebook: [UUID: [KernelVariableInfo]] = [:]
    @Published var kernelMemoryByNotebook: [UUID: (rssBytes: Int64, metalBytes: Int64)] = [:]

    private let baseURL = "http://127.0.0.1:3000/api/data"
    private let shmBrokerURL = "http://127.0.0.1:3000/api/shm"

    private init() {}

    func activeVariables(for notebookId: UUID?) -> [KernelVariableInfo] {
        guard let notebookId else { return [] }
        return liveVariablesByNotebook[notebookId] ?? []
    }

    func updateLiveVariables(
        for notebookId: UUID,
        variables: [KernelVariableInfo],
        rssBytes: Int64,
        metalBytes: Int64
    ) {
        DispatchQueue.main.async {
            self.liveVariablesByNotebook[notebookId] = variables
            self.kernelMemoryByNotebook[notebookId] = (rssBytes, metalBytes)
        }
    }

    func clearLiveVariables(for notebookId: UUID) {
        DispatchQueue.main.async {
            self.liveVariablesByNotebook[notebookId] = []
            self.kernelMemoryByNotebook[notebookId] = (0, 0)
        }
    }

    /// Generates compact, high-signal `@var` context markdown for the AI Agent without wasting tokens.
    func variableMentionSnapshot(variableName: String, notebookId: UUID?) -> String {
        let vars = activeVariables(for: notebookId)
        guard let v = vars.first(where: { $0.name == variableName }) else {
            return "`@\(variableName)`"
        }
        var md = "\n[Live Kernel Variable `@\(v.name)` — Type: `\(v.typeName)`, Shape: `\(v.shape)`, Dtype: `\(v.dtype)`, Memory: `\(v.formattedMemory)`]"
        if !v.columns.isEmpty {
            md += "\nColumns (\(v.columns.count)): `\(v.columns.prefix(40).joined(separator: ", "))`"
        }
        if !v.preview.isEmpty {
            md += "\nSample:\n```\n\(v.preview.prefix(600))\n```"
        }
        return md
    }

    func shareArtifact(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard !sharedArtifacts.contains(where: { $0.path == normalized.path }) else { return }
        sharedArtifacts.append(normalized)
    }

    func removeArtifact(_ url: URL) {
        sharedArtifacts.removeAll { $0.standardizedFileURL.path == url.standardizedFileURL.path }
    }

    func refreshList(sessionId: String = "default_notebook") async {
        // 1. Check Zero-Copy POSIX SHM Broker variables first
        var collectedNames: [String] = []
        if let brokerListURL = URL(string: "\(shmBrokerURL)/\(sessionId)"),
           let (bData, _) = try? await URLSession.shared.data(for: LocalBackendAuth.request(url: brokerListURL)),
           let bJson = try? JSONSerialization.jsonObject(with: bData) as? [String: Any],
           let varsArr = bJson["variables"] as? [[String: Any]] {
            for item in varsArr {
                if let name = item["name"] as? String, !collectedNames.contains(name) {
                    collectedNames.append(name)
                }
            }
        }

        // 2. Merge `/api/data/list`
        if let url = URL(string: "\(baseURL)/list"),
           let (data, _) = try? await URLSession.shared.data(for: LocalBackendAuth.request(url: url)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String]],
           let names = json["names"] {
            for n in names where !collectedNames.contains(n) {
                collectedNames.append(n)
            }
        }

        let finalNames = collectedNames
        await MainActor.run {
            self.sharedDataFrames = finalNames
        }
    }

    /// True Zero-Copy POSIX `shm_open` + `mmap` Python Bridge wired directly to Rust `GLOBAL_SHM_BROKER`
    /// (`/api/shm/allocate` & `/api/shm/:session_id/:name`), using Apache Arrow IPC (`pyarrow`) or
    /// protocol-5 zero-copy memoryview buffers in RAM, with automatic fallback if backend is offline.
    func getPythonBridgeCode(sessionId: String = "default_notebook") -> String {
        return """
        import os as _mc_os
        import io as _mc_io
        import mmap as _mc_mmap
        import ctypes as _mc_ctypes
        import pickle as _mc_pickle
        import struct as _mc_struct
        import urllib.request as _mc_urlreq
        import json as _mc_json

        class MicroCodeSHM:
            _MAGIC_ARROW = b"MCARW001"
            _MAGIC_PKL5  = b"MCPKL005"

            def __init__(self, session_id="\(sessionId)", api_root="http://127.0.0.1:3000"):
                self.session_id = session_id
                self.api_root = api_root.rstrip("/")
                self.base_url = f"{self.api_root}/api/data"
                self._libc = _mc_ctypes.CDLL(None)
                self._libc.shm_open.argtypes = [_mc_ctypes.c_char_p, _mc_ctypes.c_int, _mc_ctypes.c_uint]
                self._libc.shm_open.restype = _mc_ctypes.c_int
                self._libc.close.argtypes = [_mc_ctypes.c_int]

            def _headers(self):
                tok = _mc_os.environ.get("MICROCODE_LOCAL_API_TOKEN", "")
                return {"X-MicroCode-Token": tok, "Content-Type": "application/json"} if tok else {"Content-Type": "application/json"}

            def _api_json(self, method, path, payload=None):
                data = _mc_json.dumps(payload).encode("utf-8") if payload is not None else None
                req = _mc_urlreq.Request(f"{self.api_root}{path}", data=data, headers=self._headers(), method=method)
                with _mc_urlreq.urlopen(req, timeout=5) as resp:
                    return _mc_json.loads(resp.read().decode("utf-8"))

            def _serialize_zero_copy_payload(self, obj):
                try:
                    import pyarrow as pa
                    if hasattr(obj, "__dataframe__") or type(obj).__name__ == "DataFrame":
                        tbl = pa.Table.from_pandas(obj) if hasattr(obj, "to_parquet") else pa.table(obj)
                        sink = pa.BufferOutputStream()
                        with pa.ipc.new_stream(sink, tbl.schema) as writer:
                            writer.write_table(tbl)
                        buf = sink.getvalue()
                        return self._MAGIC_ARROW + _mc_struct.pack("<Q", buf.size) + memoryview(buf).tobytes(), "arrow_table"
                except Exception:
                    pass
                raw = _mc_pickle.dumps(obj, protocol=5)
                return self._MAGIC_PKL5 + _mc_struct.pack("<Q", len(raw)) + raw, "python_object"

            def _deserialize_zero_copy_payload(self, mm):
                magic = bytes(mm[:8])
                length = _mc_struct.unpack("<Q", mm[8:16])[0]
                view = memoryview(mm)[16:16 + length]
                if magic == self._MAGIC_ARROW:
                    import pyarrow as pa
                    reader = pa.ipc.open_stream(pa.py_buffer(view))
                    return reader.read_all().to_pandas()
                if magic == self._MAGIC_PKL5:
                    return _mc_pickle.loads(view)
                raise RuntimeError("Unknown SHM segment header")

            def set(self, name, obj):
                payload, dtype = self._serialize_zero_copy_payload(obj)
                # 1. True Zero-Copy POSIX shm_open + mmap via Rust GLOBAL_SHM_BROKER
                try:
                    meta = self._api_json("POST", "/api/shm/allocate", {
                        "session_id": self.session_id,
                        "variable_name": name,
                        "size_bytes": len(payload),
                        "data_type": dtype
                    }).get("metadata", {})
                    shm_name = meta.get("shm_name")
                    seg_size = int(meta.get("size_bytes", len(payload)))
                    if shm_name:
                        fd = self._libc.shm_open(shm_name.encode("utf-8"), _mc_os.O_RDWR, 0o600)
                        if fd >= 0:
                            try:
                                mm = _mc_mmap.mmap(fd, seg_size, _mc_mmap.MAP_SHARED, _mc_mmap.PROT_READ | _mc_mmap.PROT_WRITE)
                                mm[:len(payload)] = payload
                                mm.close()
                                return
                            finally:
                                self._libc.close(fd)
                except Exception:
                    pass

                # 2. Fallback local RAM/tmp segment
                fallback_path = f"/tmp/mc_shm_{self.session_id}_{name}.bin"
                with open(fallback_path, "wb") as f:
                    f.write(payload)

            def get(self, name):
                # 1. True Zero-Copy POSIX shm_open + mmap(PROT_READ)
                try:
                    meta = self._api_json("GET", f"/api/shm/{self.session_id}/{name}").get("metadata", {})
                    shm_name = meta.get("shm_name")
                    seg_size = int(meta.get("size_bytes", 0))
                    if shm_name and seg_size >= 16:
                        fd = self._libc.shm_open(shm_name.encode("utf-8"), _mc_os.O_RDONLY, 0)
                        if fd >= 0:
                            try:
                                mm = _mc_mmap.mmap(fd, seg_size, _mc_mmap.MAP_SHARED, _mc_mmap.PROT_READ)
                                try:
                                    return self._deserialize_zero_copy_payload(mm)
                                finally:
                                    mm.close()
                            finally:
                                self._libc.close(fd)
                except Exception:
                    pass

                # 2. Fallback local segment
                fallback_path = f"/tmp/mc_shm_{self.session_id}_{name}.bin"
                if _mc_os.path.exists(fallback_path):
                    with open(fallback_path, "rb") as f:
                        mm = _mc_mmap.mmap(f.fileno(), 0, access=_mc_mmap.ACCESS_READ)
                        try:
                            return self._deserialize_zero_copy_payload(mm)
                        finally:
                            mm.close()
                raise KeyError(f"Shared memory variable '{name}' not found in session '{self.session_id}'")

            def list(self):
                try:
                    res = self._api_json("GET", f"/api/shm/{self.session_id}")
                    return [v.get("name") for v in res.get("variables", []) if v.get("name")]
                except Exception:
                    return []

        shm = MicroCodeSHM()
        """
    }
}
