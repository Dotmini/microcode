//
//  AgentContextProtocolBridge.swift
//  MicroCode
//
//  Universal Context Protocol & Editor Interop Bridge.
//  Provides seamless compatibility with Cursor, OpenCode, Zed, and BigModel:
//  - Context Mention Expansion: `@file`, `@git`, `@diff`, `@diagnostics`, `@symbol`, `@rules`
//  - Unified Multi-File Diff Applicator (Zed & Cursor search/replace blocks)
//  - Deep editor context streaming
//
//  Copyright © 2025 Dotmini Company Limited
//

import Foundation
import Combine
import AppKit

public struct ExpandedMentionContext {
    public let originalPrompt: String
    public let expandedPrompt: String
    public let resolvedMentions: [String]
    public let attachedSnippetsCount: Int
}

@MainActor
public final class AgentContextProtocolBridge: ObservableObject {
    public static let shared = AgentContextProtocolBridge()

    @Published public private(set) var totalMentionsExpanded: Int = 0
    @Published public private(set) var totalDiffsApplied: Int = 0
    @Published public private(set) var lastExpansionSummary: String = ""

    private init() {}

    // MARK: - Mention Expansion (@file, @git, @diagnostics, @symbol, @rules)

    /// Expands Zed / Cursor style mentions in the prompt, appending extracted workspace context
    public func expandMentions(prompt: String, workspaceRoot: String?) async -> ExpandedMentionContext {
        guard let root = workspaceRoot, !root.isEmpty else {
            return ExpandedMentionContext(
                originalPrompt: prompt,
                expandedPrompt: prompt,
                resolvedMentions: [],
                attachedSnippetsCount: 0
            )
        }

        var resolvedMentions: [String] = []
        var contextBlocks: [String] = []

        let rootURL = URL(fileURLWithPath: root)

        // 1. Check for @git or @git:diff or @diff
        if prompt.localizedCaseInsensitiveContains("@git") || prompt.localizedCaseInsensitiveContains("@diff") {
            let gitDiff = await fetchGitContext(rootURL: rootURL)
            if !gitDiff.isEmpty {
                contextBlocks.append("""
                [Attached Context from @git]
                \(gitDiff)
                [/Attached Context from @git]
                """)
                resolvedMentions.append("@git")
            }
        }

        // 2. Check for @diagnostics or @problems
        if prompt.localizedCaseInsensitiveContains("@diagnostics") || prompt.localizedCaseInsensitiveContains("@problems") {
            let diagnostics = await fetchDiagnosticsContext()
            if !diagnostics.isEmpty {
                contextBlocks.append("""
                [Attached Context from @diagnostics]
                \(diagnostics)
                [/Attached Context from @diagnostics]
                """)
                resolvedMentions.append("@diagnostics")
            }
        }

        // 3. Check for @rules
        if prompt.localizedCaseInsensitiveContains("@rules") {
            let activeRulesPrompt = MultiPlatformRulesEngine.shared.formatPromptSection()
            if !activeRulesPrompt.isEmpty {
                contextBlocks.append("""
                [Attached Context from @rules]
                \(activeRulesPrompt)
                [/Attached Context from @rules]
                """)
                resolvedMentions.append("@rules")
            }
        }

        // 4. Check for @file:<path> or @<path_with_extension>
        let fileMentions = extractFileMentions(from: prompt, rootURL: rootURL)
        for (mentionKey, fileURL) in fileMentions {
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                let relPath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
                let capped = content.count > 16_000 ? String(content.prefix(16_000)) + "\n... [truncated for context limit]" : content
                let ext = fileURL.pathExtension.lowercased()
                contextBlocks.append("""
                [Attached Context from \(mentionKey): \(relPath)]
                ```\(ext)
                \(capped)
                ```
                [/Attached Context]
                """)
                resolvedMentions.append(mentionKey)
            }
        }

        // 5. Check for @symbol:<name>
        let symbolMentions = extractSymbolMentions(from: prompt)
        for symbol in symbolMentions {
            let symbolResults = await searchSymbolInWorkspace(symbol: symbol, rootURL: rootURL)
            if !symbolResults.isEmpty {
                contextBlocks.append("""
                [Attached Context from @symbol:\(symbol)]
                \(symbolResults)
                [/Attached Context]
                """)
                resolvedMentions.append("@symbol:\(symbol)")
            }
        }

        if !contextBlocks.isEmpty {
            totalMentionsExpanded += resolvedMentions.count
            lastExpansionSummary = "Expanded \(resolvedMentions.count) mention(s): \(resolvedMentions.joined(separator: ", "))"
            let finalPrompt = prompt + "\n\n" + contextBlocks.joined(separator: "\n\n")
            return ExpandedMentionContext(
                originalPrompt: prompt,
                expandedPrompt: finalPrompt,
                resolvedMentions: resolvedMentions,
                attachedSnippetsCount: contextBlocks.count
            )
        }

        return ExpandedMentionContext(
            originalPrompt: prompt,
            expandedPrompt: prompt,
            resolvedMentions: [],
            attachedSnippetsCount: 0
        )
    }

    // MARK: - Git Context

    private func fetchGitContext(rootURL: URL) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["status", "--short"]
        process.currentDirectoryURL = rootURL

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let statusData = pipe.fileHandleForReading.readDataToEndOfFile()
            let statusStr = String(data: statusData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Also get brief diff
            let diffProcess = Process()
            diffProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            diffProcess.arguments = ["diff", "--stat", "HEAD"]
            diffProcess.currentDirectoryURL = rootURL
            let diffPipe = Pipe()
            diffProcess.standardOutput = diffPipe
            diffProcess.standardError = Pipe()
            try diffProcess.run()
            diffProcess.waitUntilExit()
            let diffData = diffPipe.fileHandleForReading.readDataToEndOfFile()
            let diffStr = String(data: diffData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            var result = ""
            if !statusStr.isEmpty {
                result += "Git Status:\n\(statusStr)\n"
            }
            if !diffStr.isEmpty {
                result += "\nGit Diff Summary:\n\(diffStr)\n"
            }
            return result.isEmpty ? "Working tree clean (no uncommitted changes)." : result
        } catch {
            return "Unable to run git: \(error.localizedDescription)"
        }
    }

    // MARK: - Diagnostics Context

    private func fetchDiagnosticsContext() async -> String {
        var diagnosticsSummary: [String] = []
        for (uri, diags) in LSPManager.shared.fileDiagnostics {
            guard !diags.isEmpty else { continue }
            let fileName = URL(string: uri)?.lastPathComponent ?? uri
            for d in diags.prefix(5) {
                let severityStr = d.severity == 1 ? "ERROR" : (d.severity == 2 ? "WARN" : "INFO")
                let line = d.range.start.line + 1
                diagnosticsSummary.append("[\(severityStr)] \(fileName):\(line) - \(d.message)")
            }
        }
        if diagnosticsSummary.isEmpty {
            return "No active compiler or linter errors found in workspace."
        }
        return diagnosticsSummary.joined(separator: "\n")
    }

    // MARK: - File Mentions Parser

    private func extractFileMentions(from prompt: String, rootURL: URL) -> [(String, URL)] {
        var results: [(String, URL)] = []
        let pattern = #"@file:([^\s,;]+)|@([a-zA-Z0-9_\-/\\]+\.[a-zA-Z0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return results }

        let nsString = prompt as NSString
        let matches = regex.matches(in: prompt, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            var mentionText = ""
            var filePath = ""

            if match.range(at: 1).location != NSNotFound {
                filePath = nsString.substring(with: match.range(at: 1))
                mentionText = "@file:\(filePath)"
            } else if match.range(at: 2).location != NSNotFound {
                filePath = nsString.substring(with: match.range(at: 2))
                mentionText = "@\(filePath)"
            }

            guard !filePath.isEmpty else { continue }

            // Check if absolute or relative
            var targetURL: URL
            if filePath.hasPrefix("/") {
                targetURL = URL(fileURLWithPath: filePath)
            } else {
                targetURL = rootURL.appendingPathComponent(filePath)
            }

            // Fallback: search for file by name if relative path didn't exist directly
            if !FileManager.default.fileExists(atPath: targetURL.path) {
                let fileName = URL(fileURLWithPath: filePath).lastPathComponent
                if let found = findFileByName(fileName, in: rootURL) {
                    targetURL = found
                }
            }

            if FileManager.default.fileExists(atPath: targetURL.path) {
                results.append((mentionText, targetURL))
            }
        }

        return results
    }

    private func findFileByName(_ name: String, in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == name {
                return fileURL
            }
        }
        return nil
    }

    // MARK: - Symbol Mentions Parser

    private func extractSymbolMentions(from prompt: String) -> [String] {
        var symbols: [String] = []
        let pattern = #"@symbol:([a-zA-Z0-9_]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return symbols }

        let nsString = prompt as NSString
        let matches = regex.matches(in: prompt, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            if match.range(at: 1).location != NSNotFound {
                let sym = nsString.substring(with: match.range(at: 1))
                symbols.append(sym)
            }
        }
        return symbols
    }

    private func searchSymbolInWorkspace(symbol: String, rootURL: URL) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        process.arguments = ["-rn", "--max-count=5", "--exclude-dir=.git", "--exclude-dir=build", symbol, rootURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let rawOutput = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if rawOutput.isEmpty {
                return "Symbol `\(symbol)` not found."
            }
            return rawOutput.replacingOccurrences(of: rootURL.path + "/", with: "")
        } catch {
            return "Symbol search error: \(error.localizedDescription)"
        }
    }

    // MARK: - Unified Multi-File Diff Applicator (Zed & Cursor SEARCH/REPLACE & Diff)

    /// Applies multi-file search/replace or unified diffs produced by reasoning models or external tools
    public func applyMultiFileDiffs(diffContent: String, workspaceRoot: String) async -> (applied: [String], errors: [String]) {
        var appliedFiles: [String] = []
        var errors: [String] = []

        // Detect Cursor / Zed search & replace blocks
        let searchReplacePattern = #"(?:File:\s*`?([^\r\n`]+)`?[\r\n]+)?<<<<<<< SEARCH[\r\n]+([\s\S]*?)=======[\r\n]+([\s\S]*?)>>>>>>>"#
        if let regex = try? NSRegularExpression(pattern: searchReplacePattern, options: []) {
            let nsText = diffContent as NSString
            let matches = regex.matches(in: diffContent, options: [], range: NSRange(location: 0, length: nsText.length))

            for match in matches {
                var targetFilePath = ""
                if match.range(at: 1).location != NSNotFound {
                    targetFilePath = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let oldText = nsText.substring(with: match.range(at: 2))
                let newText = nsText.substring(with: match.range(at: 3))

                guard !targetFilePath.isEmpty else { continue }

                let fullURL = targetFilePath.hasPrefix("/")
                    ? URL(fileURLWithPath: targetFilePath)
                    : URL(fileURLWithPath: workspaceRoot).appendingPathComponent(targetFilePath)

                do {
                    guard FileManager.default.fileExists(atPath: fullURL.path) else {
                        errors.append("File not found: \(targetFilePath)")
                        continue
                    }
                    let existing = try String(contentsOf: fullURL, encoding: .utf8)
                    if existing.contains(oldText) {
                        let updated = existing.replacingOccurrences(of: oldText, with: newText)
                        try updated.write(to: fullURL, atomically: true, encoding: .utf8)
                        appliedFiles.append(targetFilePath)
                        totalDiffsApplied += 1
                    } else {
                        errors.append("Search block did not match in \(targetFilePath)")
                    }
                } catch {
                    errors.append("Failed to edit \(targetFilePath): \(error.localizedDescription)")
                }
            }
        }

        return (appliedFiles, errors)
    }
}
