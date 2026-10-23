import Foundation
import Combine
import SwiftUI

enum ContextProviderType: String, CaseIterable, Identifiable {
    case file = "file"
    case folder = "folder"
    case symbol = "symbol"
    case error = "error"
    case terminal = "terminal"
    case git = "git"
    case selection = "selection"
    case web = "web"
    case docs = "docs"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .file: return "Files"
        case .folder: return "Folders"
        case .symbol: return "Symbols"
        case .error: return "Errors"
        case .terminal: return "Terminal Output"
        case .git: return "Git Changes"
        case .selection: return "Selection"
        case .web: return "Web Search"
        case .docs: return "Documentation"
        }
    }
    
    var icon: String {
        switch self {
        case .file: return "doc"
        case .folder: return "folder"
        case .symbol: return "function"
        case .error: return "exclamationmark.triangle"
        case .terminal: return "terminal"
        case .git: return "arrow.triangle.branch"
        case .selection: return "selection.pin.in.out"
        case .web: return "network"
        case .docs: return "book"
        }
    }
    
    var description: String {
        switch self {
        case .file: return "Include file content"
        case .folder: return "Include folder structure"
        case .symbol: return "Search for functions or classes"
        case .error: return "Include current compiler errors"
        case .terminal: return "Include console output"
        case .git: return "Include git status and diff"
        case .selection: return "Include selected code"
        case .web: return "Search the web"
        case .docs: return "Search documentation"
        }
    }
}

struct ContextItem: Identifiable, Equatable {
    let id = UUID()
    let provider: ContextProviderType
    let title: String
    let subtitle: String?
    let content: String
    let tokenEstimate: Int
    
    static func == (lhs: ContextItem, rhs: ContextItem) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class ContextProviderService: ObservableObject {
    static let shared = ContextProviderService()
    
    @Published var suggestions: [ContextProviderType] = []
    @Published var isShowingSuggestions: Bool = false
    @Published var secondLevelItems: [ContextItem] = []
    @Published var isShowingSecondLevel: Bool = false
    @Published var selectedProviderType: ContextProviderType?
    @Published var attachedContexts: [ContextItem] = []
    
    func getSuggestions(for prefix: String) -> [ContextProviderType] {
        let cleanPrefix = prefix.replacingOccurrences(of: "@", with: "").lowercased()
        if cleanPrefix.isEmpty {
            return ContextProviderType.allCases
        } else {
            return ContextProviderType.allCases.filter {
                $0.rawValue.lowercased().hasPrefix(cleanPrefix) ||
                $0.displayName.lowercased().hasPrefix(cleanPrefix)
            }
        }
    }
    
    func loadSecondLevel(for provider: ContextProviderType, query: String, appState: AppState) -> [ContextItem] {
        var items: [ContextItem] = []
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let workspaceRoot = appState.workspaceFolder?.path ?? AgentService.shared.currentWorkspace ?? ""
        
        switch provider {
        case .file:
            var seenPaths = Set<String>()
            // 1. Open files first
            for file in appState.openFiles {
                guard seenPaths.insert(file.path).inserted else { continue }
                if q.isEmpty || file.name.lowercased().contains(q) || file.path.lowercased().contains(q) {
                    let snippet = String(file.content.prefix(24000))
                    items.append(
                        ContextItem(
                            provider: .file,
                            title: file.name,
                            subtitle: file.path,
                            content: "// File: \(file.path)\n\(snippet)",
                            tokenEstimate: max(1, snippet.count / 4)
                        )
                    )
                }
            }
            // 2. Scan real workspace files
            if !workspaceRoot.isEmpty, items.count < 40 {
                let rootURL = URL(fileURLWithPath: workspaceRoot)
                let ignoredDirs: Set<String> = [".git", "node_modules", ".build", "target", "DerivedData", ".next", "dist", "build", "__pycache__", ".venv"]
                if let enumerator = FileManager.default.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    var scanned = 0
                    while let url = enumerator.nextObject() as? URL {
                        let name = url.lastPathComponent
                        if ignoredDirs.contains(name) {
                            enumerator.skipDescendants()
                            continue
                        }
                        scanned += 1
                        if scanned > 1500 || items.count >= 40 { break }
                        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                        let fullPath = url.path
                        guard !seenPaths.contains(fullPath) else { continue }
                        let relPath = fullPath.replacingOccurrences(of: workspaceRoot + "/", with: "")
                        if q.isEmpty || name.lowercased().contains(q) || relPath.lowercased().contains(q) {
                            if let content = try? String(contentsOf: url, encoding: .utf8) {
                                seenPaths.insert(fullPath)
                                let snippet = String(content.prefix(24000))
                                items.append(
                                    ContextItem(
                                        provider: .file,
                                        title: name,
                                        subtitle: relPath,
                                        content: "// File: \(relPath)\n\(snippet)",
                                        tokenEstimate: max(1, snippet.count / 4)
                                    )
                                )
                            }
                        }
                    }
                }
            }
            
        case .folder:
            if !workspaceRoot.isEmpty {
                let rootURL = URL(fileURLWithPath: workspaceRoot)
                let ignoredDirs: Set<String> = [".git", "node_modules", ".build", "target", "DerivedData", ".next", "dist", "build", "__pycache__", ".venv"]
                var dirs: [URL] = [rootURL]
                if let enumerator = FileManager.default.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    while let url = enumerator.nextObject() as? URL {
                        if ignoredDirs.contains(url.lastPathComponent) {
                            enumerator.skipDescendants()
                            continue
                        }
                        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                            dirs.append(url)
                            if dirs.count >= 50 { break }
                        }
                    }
                }
                for dirURL in dirs {
                    let rel = dirURL.path == workspaceRoot ? rootURL.lastPathComponent : dirURL.path.replacingOccurrences(of: workspaceRoot + "/", with: "")
                    guard q.isEmpty || rel.lowercased().contains(q) else { continue }
                    let entries = (try? FileManager.default.contentsOfDirectory(atPath: dirURL.path))?
                        .filter { !$0.hasPrefix(".") }
                        .sorted()
                        .prefix(80)
                        .joined(separator: "\n- ") ?? ""
                    let treeContent = "Directory: \(rel)\n- \(entries)"
                    items.append(
                        ContextItem(
                            provider: .folder,
                            title: dirURL.lastPathComponent,
                            subtitle: rel,
                            content: treeContent,
                            tokenEstimate: max(10, treeContent.count / 4)
                        )
                    )
                }
            }
            
        case .symbol:
            let symbolPattern = #"(?:func|struct|class|enum|protocol|actor|def|fn|interface|type)\s+([A-Za-z0-9_]+)"#
            let regex = try? NSRegularExpression(pattern: symbolPattern)
            for file in appState.openFiles {
                let lines = file.content.components(separatedBy: .newlines)
                for (idx, line) in lines.enumerated() {
                    guard let regex = regex,
                          let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                          match.numberOfRanges > 1,
                          let r = Range(match.range(at: 1), in: line) else { continue }
                    let symName = String(line[r])
                    if q.isEmpty || symName.lowercased().contains(q) {
                        let start = max(0, idx - 2)
                        let end = min(lines.count - 1, idx + 28)
                        let snippet = lines[start...end].joined(separator: "\n")
                        items.append(
                            ContextItem(
                                provider: .symbol,
                                title: symName,
                                subtitle: "\(file.name):\(idx + 1)",
                                content: "// Symbol \(symName) in \(file.path):\(idx + 1)\n\(snippet)",
                                tokenEstimate: max(10, snippet.count / 4)
                            )
                        )
                    }
                    if items.count >= 30 { break }
                }
            }
            if items.isEmpty {
                items.append(
                    ContextItem(
                        provider: .symbol,
                        title: query.isEmpty ? "Workspace Symbols" : "Symbol '\(query)'",
                        subtitle: "Open a source file or type symbol name",
                        content: "Search workspace symbols for: \(query)",
                        tokenEstimate: 25
                    )
                )
            }
            
        case .error:
            var diagLines: [String] = []
            for (uri, diags) in LSPManager.shared.fileDiagnostics where !diags.isEmpty {
                let cleanPath = URL(string: uri)?.path ?? uri
                let fileName = URL(fileURLWithPath: cleanPath).lastPathComponent
                for d in diags {
                    diagLines.append("\(fileName):\(d.range.start.line + 1):\(d.range.start.character + 1): \(d.message)")
                }
            }
            let errorReport = diagLines.isEmpty
                ? (appState.consoleOutput.isEmpty ? "No active LSP or compiler errors detected." : String(appState.consoleOutput.suffix(4000)))
                : diagLines.joined(separator: "\n")
            items.append(
                ContextItem(
                    provider: .error,
                    title: diagLines.isEmpty ? "Console & Build Diagnostics" : "\(diagLines.count) Active Compiler/LSP Diagnostics",
                    subtitle: "Active workspace diagnostics & build logs",
                    content: errorReport,
                    tokenEstimate: max(15, errorReport.count / 4)
                )
            )
            
        case .terminal:
            let output = appState.consoleOutput.isEmpty ? "(Console output is empty)" : String(appState.consoleOutput.suffix(8000))
            items.append(
                ContextItem(
                    provider: .terminal,
                    title: "Terminal Output",
                    subtitle: "Recent console & build logs",
                    content: output,
                    tokenEstimate: max(10, output.count / 4)
                )
            )
            
        case .git:
            let gitSummary = Self.runGitContextSnapshot(in: workspaceRoot)
            items.append(
                ContextItem(
                    provider: .git,
                    title: "Git Working Tree & Diff",
                    subtitle: workspaceRoot.isEmpty ? "Current repository" : URL(fileURLWithPath: workspaceRoot).lastPathComponent,
                    content: gitSummary,
                    tokenEstimate: max(20, gitSummary.count / 4)
                )
            )
            
        case .selection:
            if let current = appState.currentFile {
                let snippet = String(current.content.prefix(16000))
                items.append(
                    ContextItem(
                        provider: .selection,
                        title: "Active File: \(current.name)",
                        subtitle: current.path,
                        content: "// Active Editor Context (\(current.path)):\n\(snippet)",
                        tokenEstimate: max(15, snippet.count / 4)
                    )
                )
            } else {
                items.append(
                    ContextItem(
                        provider: .selection,
                        title: "Active Editor Context",
                        subtitle: "No file currently open",
                        content: "No active file open in the editor.",
                        tokenEstimate: 10
                    )
                )
            }
            
        case .web, .docs:
            let targetQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "project documentation" : query
            items.append(
                ContextItem(
                    provider: provider,
                    title: provider == .web ? "Live Web Search: '\(targetQuery)'" : "Documentation Lookup: '\(targetQuery)'",
                    subtitle: provider == .web ? "Instructs Agent to ground response with web search" : "Instructs Agent to inspect project & SDK docs",
                    content: provider == .web
                        ? "[Web Research Directive] Search and ground your response with up-to-date web references for: \(targetQuery)"
                        : "[Documentation Directive] Search workspace documentation, README, and SDK references for: \(targetQuery)",
                    tokenEstimate: 40
                )
            )
        }
        
        return items
    }
    
    private static func runGitContextSnapshot(in workspaceRoot: String) -> String {
        guard !workspaceRoot.isEmpty else { return "No workspace folder open." }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["sh", "-c", "git status --short && echo '--- DIFF STAT ---' && git diff --stat && echo '--- DIFF ---' && git diff --unified=3 | head -c 12000"]
        proc.currentDirectoryURL = URL(fileURLWithPath: workspaceRoot)
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return output.isEmpty ? "Working tree clean (no uncommitted git changes)." : output
        } catch {
            return "Unable to read git status: \(error.localizedDescription)"
        }
    }
    
    func resolveContext(provider: ContextProviderType, query: String, appState: AppState) -> ContextItem? {
        let items = loadSecondLevel(for: provider, query: query, appState: appState)
        return items.first
    }
    
    func buildContextPrompt() -> String {
        guard !attachedContexts.isEmpty else { return "" }
        
        var prompt = "Here is the provided context:\n\n"
        for item in attachedContexts {
            prompt += "--- \(item.title) (\(item.provider.displayName)) ---\n"
            prompt += item.content
            prompt += "\n\n"
        }
        return prompt
    }
    
    func selectProvider(_ provider: ContextProviderType) {
        selectedProviderType = provider
        isShowingSuggestions = false
        isShowingSecondLevel = true
    }
    
    func removeContext(_ item: ContextItem) {
        attachedContexts.removeAll { $0.id == item.id }
    }
    
    func clearAll() {
        attachedContexts.removeAll()
        suggestions.removeAll()
        secondLevelItems.removeAll()
        isShowingSuggestions = false
        isShowingSecondLevel = false
        selectedProviderType = nil
    }
}
