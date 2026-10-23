//
//  MultiPlatformRulesEngine.swift
//  MicroCode
//
//  Universal Rules & Context Portability Engine.
//  Discovers, parses, glob-matches, and compiles project rules from:
//  - Cursor: `.cursorrules`, `.cursor/rules/*.mdc`, `.cursorignore`
//  - Windsurf: `.windsurfrules`
//  - Cline / Roo Code: `.clinerules`
//  - GitHub Copilot: `.copilot-instructions.md`, `.github/copilot-instructions.md`
//  - ZCode / Zed: `.zed/settings.json` assistant rules
//  - MicroCode: `.microcode/agent.md`
//

import Foundation
import Combine

public enum RulePlatformSource: String, CaseIterable, Codable, Identifiable {
    case agentsMd = "AGENTS.md (Open Standard)"
    case claudeMd = "Claude Code (CLAUDE.md)"
    case cursorLegacy = "Cursor (.cursorrules)"
    case cursorMdc = "Cursor Modern (.cursor/rules/*.mdc)"
    case windsurf = "Windsurf (.windsurfrules)"
    case cline = "Cline (.clinerules)"
    case copilot = "Copilot (.copilot-instructions.md)"
    case zed = "Zed (.zed/settings.json)"
    case txcode = "TX Code (.txcode-rules)"
    case microcode = "MicroCode (.microcode/agent.md)"

    public var id: String { rawValue }

    public var badge: String {
        switch self {
        case .agentsMd: return "AGENTS.MD"
        case .claudeMd: return "CLAUDE"
        case .cursorLegacy, .cursorMdc: return "CURSOR"
        case .windsurf: return "WINDSURF"
        case .cline: return "CLINE"
        case .copilot: return "COPILOT"
        case .zed: return "ZED"
        case .txcode: return "TXCODE"
        case .microcode: return "MICROCODE"
        }
    }

    public var icon: String {
        switch self {
        case .agentsMd: return "doc.badge.gearshape"
        case .claudeMd: return "sparkles.rectangle.stack"
        case .cursorLegacy, .cursorMdc: return "cursorarrow.rays"
        case .windsurf: return "wind"
        case .cline: return "terminal"
        case .copilot: return "airplane"
        case .zed: return "bolt.fill"
        case .txcode: return "checkmark.rectangle"
        case .microcode: return "sparkles"
        }
    }
}

public enum AgentHookStage: String, Codable, CaseIterable {
    case preTool = "pre_tool"
    case postTool = "post_tool"
    case preFinish = "pre_finish"

    public var badge: String {
        switch self {
        case .preTool: return "PRE_TOOL"
        case .postTool: return "POST_TOOL"
        case .preFinish: return "PRE_FINISH"
        }
    }
}

public struct AgentLifecycleHook: Identifiable, Codable, Hashable {
    public let id: String
    public let stage: AgentHookStage
    public let name: String
    public let matcher: String       // Tool regex/name or file glob (e.g. "file_write|patch_file", "*.ts", "*")
    public let command: String       // Shell command to run
    public let blockOnFailure: Bool  // If true, non-zero exit blocks tool or requires agent fix before finishing
    public let sourceFile: String

    public init(
        id: String = UUID().uuidString,
        stage: AgentHookStage,
        name: String,
        matcher: String = "*",
        command: String,
        blockOnFailure: Bool = true,
        sourceFile: String
    ) {
        self.id = id
        self.stage = stage
        self.name = name
        self.matcher = matcher
        self.command = command
        self.blockOnFailure = blockOnFailure
        self.sourceFile = sourceFile
    }
}

public struct PlatformRule: Identifiable, Codable, Hashable {
    public let id: String
    public let source: RulePlatformSource
    public let fileName: String
    public let relativePath: String
    public let summaryDescription: String
    public let globs: [String]
    public let alwaysApply: Bool
    public let content: String

    public init(
        id: String = UUID().uuidString,
        source: RulePlatformSource,
        fileName: String,
        relativePath: String,
        summaryDescription: String,
        globs: [String],
        alwaysApply: Bool,
        content: String
    ) {
        self.id = id
        self.source = source
        self.fileName = fileName
        self.relativePath = relativePath
        self.summaryDescription = summaryDescription
        self.globs = globs
        self.alwaysApply = alwaysApply
        self.content = content
    }
}

public struct DiscoveredMCPServer: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let sourcePlatform: String
    public let command: String
    public let args: [String]
    public let env: [String: String]
    public let url: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        sourcePlatform: String,
        command: String,
        args: [String],
        env: [String: String] = [:],
        url: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sourcePlatform = sourcePlatform
        self.command = command
        self.args = args
        self.env = env
        self.url = url
    }
}

public final class MultiPlatformRulesEngine: ObservableObject {
    public static let shared = MultiPlatformRulesEngine()

    @Published public private(set) var discoveredRules: [PlatformRule] = []
    @Published public private(set) var discoveredHooks: [AgentLifecycleHook] = []
    @Published public private(set) var discoveredMCPServers: [DiscoveredMCPServer] = []
    @Published public private(set) var ignoredPatterns: [String] = []
    @Published public private(set) var lastScanDate: Date? = nil
    @Published public private(set) var currentWorkspace: String? = nil

    private let fileManager = FileManager.default
    private let scanQueue = DispatchQueue(label: "com.microcode.rulesengine", qos: .userInitiated)

    private init() {}

    // MARK: - Workspace Scanning

    public func refresh(workspaceRoot: String?) {
        guard let root = workspaceRoot, !root.isEmpty else {
            DispatchQueue.main.async {
                self.discoveredRules = []
                self.discoveredHooks = []
                self.discoveredMCPServers = []
                self.ignoredPatterns = []
                self.currentWorkspace = nil
            }
            return
        }

        scanQueue.async { [weak self] in
            guard let self = self else { return }
            var rules: [PlatformRule] = []
            var hooks: [AgentLifecycleHook] = []
            var ignores: [String] = []

            let rootURL = URL(fileURLWithPath: root)

            // 0A. Scan Open Standard AGENTS.md (root + nested directories up to depth 3)
            self.scanAgentsMdFiles(rootURL: rootURL, into: &rules)

            // 0B. Scan Claude Code CLAUDE.md and .claude/CLAUDE.md (with @path import expansion)
            for claudeRel in ["CLAUDE.md", ".claude/CLAUDE.md"] {
                let claudeURL = rootURL.appendingPathComponent(claudeRel)
                if let rawContent = try? String(contentsOf: claudeURL, encoding: .utf8),
                   !rawContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let expanded = self.expandAtFileImports(in: rawContent, baseURL: claudeURL.deletingLastPathComponent(), rootURL: rootURL)
                    rules.append(PlatformRule(
                        source: .claudeMd,
                        fileName: URL(fileURLWithPath: claudeRel).lastPathComponent,
                        relativePath: claudeRel,
                        summaryDescription: "Claude Code Project Memory & Guidelines",
                        globs: ["*"],
                        alwaysApply: true,
                        content: expanded
                    ))
                }
            }

            // 0C. Scan TX Code .txcode-rules and .txcode/rules/*.{md,mdc}
            for txRel in [".txcode-rules", ".txcoderules"] {
                let txURL = rootURL.appendingPathComponent(txRel)
                if let content = try? String(contentsOf: txURL, encoding: .utf8),
                   !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    rules.append(PlatformRule(
                        source: .txcode,
                        fileName: txRel,
                        relativePath: txRel,
                        summaryDescription: "TX Code Project Rules",
                        globs: ["*"],
                        alwaysApply: true,
                        content: content
                    ))
                }
            }
            let txRulesDir = rootURL.appendingPathComponent(".txcode/rules")
            if let enumerator = self.fileManager.enumerator(at: txRulesDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    let ext = fileURL.pathExtension.lowercased()
                    if ext == "mdc" || ext == "md" {
                        if let parsed = self.parseMdcRule(fileURL: fileURL, rootURL: rootURL, sourceOverride: .txcode) {
                            rules.append(parsed)
                        }
                    }
                }
            }

            // 1. Scan Cursor Legacy .cursorrules
            let cursorRulesURL = rootURL.appendingPathComponent(".cursorrules")
            if let content = try? String(contentsOf: cursorRulesURL, encoding: .utf8), !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rules.append(PlatformRule(
                    source: .cursorLegacy,
                    fileName: ".cursorrules",
                    relativePath: ".cursorrules",
                    summaryDescription: "Cursor Project Rules",
                    globs: ["*"],
                    alwaysApply: true,
                    content: content
                ))
            }

            // 2. Scan Cursor .cursorignore
            let cursorIgnoreURL = rootURL.appendingPathComponent(".cursorignore")
            if let ignoreText = try? String(contentsOf: cursorIgnoreURL, encoding: .utf8) {
                let lines = ignoreText.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                ignores.append(contentsOf: lines)
            }

            // 3. Scan Cursor Modern .cursor/rules/*.mdc
            let cursorRulesDir = rootURL.appendingPathComponent(".cursor/rules")
            if let enumerator = self.fileManager.enumerator(at: cursorRulesDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension.lowercased() == "mdc" || fileURL.pathExtension.lowercased() == "md" {
                        if let rule = self.parseMdcRule(fileURL: fileURL, rootURL: rootURL) {
                            rules.append(rule)
                        }
                    }
                }
            }

            // 4. Scan Windsurf .windsurfrules
            let windsurfURL = rootURL.appendingPathComponent(".windsurfrules")
            if let content = try? String(contentsOf: windsurfURL, encoding: .utf8), !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rules.append(PlatformRule(
                    source: .windsurf,
                    fileName: ".windsurfrules",
                    relativePath: ".windsurfrules",
                    summaryDescription: "Windsurf Cascade Rules",
                    globs: ["*"],
                    alwaysApply: true,
                    content: content
                ))
            }

            // 5. Scan Cline .clinerules
            let clineURL = rootURL.appendingPathComponent(".clinerules")
            if let content = try? String(contentsOf: clineURL, encoding: .utf8), !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rules.append(PlatformRule(
                    source: .cline,
                    fileName: ".clinerules",
                    relativePath: ".clinerules",
                    summaryDescription: "Cline / Roo Code Rules",
                    globs: ["*"],
                    alwaysApply: true,
                    content: content
                ))
            }

            // 6. Scan GitHub Copilot instructions
            let copilotPaths = [".github/copilot-instructions.md", ".copilot-instructions.md"]
            for relPath in copilotPaths {
                let copilotURL = rootURL.appendingPathComponent(relPath)
                if let content = try? String(contentsOf: copilotURL, encoding: .utf8), !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    rules.append(PlatformRule(
                        source: .copilot,
                        fileName: URL(fileURLWithPath: relPath).lastPathComponent,
                        relativePath: relPath,
                        summaryDescription: "GitHub Copilot Instructions",
                        globs: ["*"],
                        alwaysApply: true,
                        content: content
                    ))
                    break
                }
            }

            // 7. Scan Zed .zed/settings.json
            let zedURL = rootURL.appendingPathComponent(".zed/settings.json")
            if let data = try? Data(contentsOf: zedURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let assistant = json["assistant"] as? [String: Any] {
                    if let prompt = assistant["system_prompt"] as? String, !prompt.isEmpty {
                        rules.append(PlatformRule(
                            source: .zed,
                            fileName: "settings.json",
                            relativePath: ".zed/settings.json",
                            summaryDescription: "Zed Assistant System Prompt",
                            globs: ["*"],
                            alwaysApply: true,
                            content: prompt
                        ))
                    }
                }
            }

            // 8. Scan MicroCode .microcode/agent.md and .microcode/rules/*.{md,mdc}
            let microcodeURL = rootURL.appendingPathComponent(".microcode/agent.md")
            if let content = try? String(contentsOf: microcodeURL, encoding: .utf8), !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rules.append(PlatformRule(
                    source: .microcode,
                    fileName: "agent.md",
                    relativePath: ".microcode/agent.md",
                    summaryDescription: "MicroCode Native Agent Instructions",
                    globs: ["*"],
                    alwaysApply: true,
                    content: content
                ))
            }
            let mcRulesDir = rootURL.appendingPathComponent(".microcode/rules")
            if let enumerator = self.fileManager.enumerator(at: mcRulesDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    let ext = fileURL.pathExtension.lowercased()
                    if ext == "mdc" || ext == "md" {
                        if let parsed = self.parseMdcRule(fileURL: fileURL, rootURL: rootURL, sourceOverride: .microcode) {
                            rules.append(parsed)
                        }
                    }
                }
            }

            // 8B. Scan Lifecycle Hooks (pre_tool, post_tool, pre_finish)
            self.scanLifecycleHooks(rootURL: rootURL, into: &hooks)

            // 9. Scan Universal MCP servers across MicroCode, Antigravity, Claude, Cursor, Windsurf, VS Code, and Codex
            var mcpServers: [DiscoveredMCPServer] = []
            let homeURL = self.fileManager.homeDirectoryForCurrentUser
            let mcpCandidates: [(URL, String)] = [
                (rootURL.appendingPathComponent(".microcode/mcp.json"), "MicroCode Workspace (.microcode/mcp.json)"),
                (rootURL.appendingPathComponent(".mcp.json"), "MCP Standard (.mcp.json)"),
                (rootURL.appendingPathComponent(".cursor/mcp.json"), "Cursor (.cursor/mcp.json)"),
                (rootURL.appendingPathComponent(".vscode/mcp.json"), "VS Code (.vscode/mcp.json)"),
                (homeURL.appendingPathComponent(".microcode/mcp.json"), "MicroCode Global (~/.microcode/mcp.json)"),
                (homeURL.appendingPathComponent(".cursor/mcp.json"), "Cursor User (~/.cursor/mcp.json)"),
                (homeURL.appendingPathComponent(".codeium/windsurf/mcp_config.json"), "Windsurf (~/.codeium/windsurf/mcp_config.json)"),
                (homeURL.appendingPathComponent(".codex/mcp.json"), "Codex (~/.codex/mcp.json)"),
                (homeURL.appendingPathComponent(".gemini/antigravity/mcp_config.json"), "Antigravity (~/.gemini/antigravity/mcp_config.json)"),
                (homeURL.appendingPathComponent(".gemini/settings.json"), "Antigravity (~/.gemini/settings.json)"),
                (homeURL.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json"), "Claude Desktop")
            ]
            for (fileURL, label) in mcpCandidates {
                if let data = try? Data(contentsOf: fileURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let serversDict = (json["mcpServers"] as? [String: [String: Any]]) ?? (json["servers"] as? [String: [String: Any]])
                    if let servers = serversDict {
                        for (serverName, spec) in servers {
                            if serverName == "microcode" { continue } // Already handled natively by MCPClient.shared (mcp__local__*)
                            if let disabled = spec["disabled"] as? Bool, disabled { continue }
                            if let enabled = spec["enabled"] as? Bool, !enabled { continue }
                            let cmd = spec["command"] as? String ?? ""
                            let args = spec["args"] as? [String] ?? []
                            let env = spec["env"] as? [String: String] ?? [:]
                            let remoteUrl = (spec["url"] as? String) ?? (spec["serverUrl"] as? String)
                            // Skip servers with unconfigured placeholder credentials (e.g. YOUR_SLACK_BOT_TOKEN)
                            if env.values.contains(where: { $0.hasPrefix("YOUR_") }) { continue }
                            if (!cmd.isEmpty || (remoteUrl != nil && !(remoteUrl?.isEmpty ?? true))) && !mcpServers.contains(where: { $0.name == serverName }) {
                                mcpServers.append(DiscoveredMCPServer(
                                    name: serverName,
                                    sourcePlatform: label,
                                    command: cmd.isEmpty ? (remoteUrl ?? "") : cmd,
                                    args: args,
                                    env: env,
                                    url: remoteUrl
                                ))
                            }
                        }
                    }
                }
            }

            let finalRules = rules
            let finalHooks = hooks
            let finalMCPServers = mcpServers
            let finalIgnores = ignores
            DispatchQueue.main.async {
                self.discoveredRules = finalRules
                self.discoveredHooks = finalHooks
                self.discoveredMCPServers = finalMCPServers
                self.ignoredPatterns = finalIgnores
                self.lastScanDate = Date()
                self.currentWorkspace = root
                ExternalMCPManager.shared.syncWithDiscoveredServers(finalMCPServers)
            }
        }
    }

    // MARK: - AGENTS.md (Root + Nested Subdirectory Discovery) & CLAUDE.md @import Expansion

    private func scanAgentsMdFiles(rootURL: URL, into rules: inout [PlatformRule]) {
        // 1. Root AGENTS.md
        let rootAgentsURL = rootURL.appendingPathComponent("AGENTS.md")
        if let content = try? String(contentsOf: rootAgentsURL, encoding: .utf8),
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = expandAtFileImports(in: content, baseURL: rootURL, rootURL: rootURL)
            rules.append(PlatformRule(
                source: .agentsMd,
                fileName: "AGENTS.md",
                relativePath: "AGENTS.md",
                summaryDescription: "Workspace Root AGENTS.md Instructions",
                globs: ["*"],
                alwaysApply: true,
                content: expanded
            ))
        }

        // 2. Nested AGENTS.md in immediate subdirectories (up to depth 2) with automatic directory glob scoping
        let skipDirs: Set<String> = [".git", "node_modules", ".build", "target", "dist", "build", ".codetuner-build", "Pods", ".next", "venv", ".venv"]
        guard let topChildren = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return
        }
        for childURL in topChildren {
            guard (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let dirName = childURL.lastPathComponent
            if skipDirs.contains(dirName) { continue }

            let nestedAgents = childURL.appendingPathComponent("AGENTS.md")
            if let content = try? String(contentsOf: nestedAgents, encoding: .utf8),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let relPath = "\(dirName)/AGENTS.md"
                rules.append(PlatformRule(
                    source: .agentsMd,
                    fileName: relPath,
                    relativePath: relPath,
                    summaryDescription: "Scoped AGENTS.md for \(dirName)/",
                    globs: ["\(dirName)/*", "\(dirName)/**/*"],
                    alwaysApply: false,
                    content: content
                ))
            }
        }
    }

    private func expandAtFileImports(in text: String, baseURL: URL, rootURL: URL) -> String {
        let lines = text.components(separatedBy: .newlines)
        var outLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Support `@path/to/file.md` standalone import syntax (used by CLAUDE.md and AGENTS.md)
            if trimmed.hasPrefix("@"),
               !trimmed.contains(" "),
               trimmed.count > 2,
               (trimmed.hasSuffix(".md") || trimmed.hasSuffix(".mdc") || trimmed.hasSuffix(".txt")) {
                let importRel = String(trimmed.dropFirst())
                let candidateURL = importRel.hasPrefix("/")
                    ? URL(fileURLWithPath: importRel)
                    : baseURL.appendingPathComponent(importRel).standardizedFileURL
                if candidateURL.path.hasPrefix(rootURL.path),
                   let imported = try? String(contentsOf: candidateURL, encoding: .utf8),
                   !imported.isEmpty {
                    outLines.append("<!-- Imported from \(importRel) -->")
                    outLines.append(imported)
                    continue
                }
            }
            outLines.append(line)
        }
        return outLines.joined(separator: "\n")
    }

    // MARK: - Lifecycle Hooks Discovery & Execution (pre_tool, post_tool, pre_finish)

    private func scanLifecycleHooks(rootURL: URL, into hooks: inout [AgentLifecycleHook]) {
        let hookCandidates: [(URL, String)] = [
            (rootURL.appendingPathComponent(".microcode/hooks.json"), ".microcode/hooks.json"),
            (rootURL.appendingPathComponent(".txcode/hooks.json"), ".txcode/hooks.json"),
            (rootURL.appendingPathComponent(".cursor/hooks.json"), ".cursor/hooks.json"),
            (rootURL.appendingPathComponent(".claude/settings.json"), ".claude/settings.json"),
            (rootURL.appendingPathComponent(".claude/settings.local.json"), ".claude/settings.local.json")
        ]

        for (fileURL, sourceLabel) in hookCandidates {
            guard let data = try? Data(contentsOf: fileURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let hooksRoot = (json["hooks"] as? [String: Any]) ?? json

            let stageMappings: [(keys: [String], stage: AgentHookStage)] = [
                (["pre_tool", "preTool", "PreToolUse"], .preTool),
                (["post_tool", "postTool", "PostToolUse"], .postTool),
                (["pre_finish", "preFinish", "Stop"], .preFinish)
            ]

            for mapping in stageMappings {
                for key in mapping.keys {
                    if let entries = hooksRoot[key] as? [[String: Any]] {
                        for entry in entries {
                            let matcher = (entry["matcher"] as? String) ?? (entry["glob"] as? String) ?? (entry["tool"] as? String) ?? "*"
                            let blockOnFailure = (entry["blockOnFailure"] as? Bool) ?? (entry["block_on_failure"] as? Bool) ?? true
                            if let cmd = entry["command"] as? String, !cmd.isEmpty {
                                let name = (entry["name"] as? String) ?? "\(mapping.stage.rawValue): \(cmd.prefix(36))"
                                hooks.append(AgentLifecycleHook(
                                    stage: mapping.stage,
                                    name: name,
                                    matcher: matcher,
                                    command: cmd,
                                    blockOnFailure: blockOnFailure,
                                    sourceFile: sourceLabel
                                ))
                            } else if let innerHooks = entry["hooks"] as? [[String: Any]] {
                                // Claude Code nested hooks array format
                                for inner in innerHooks {
                                    if let cmd = inner["command"] as? String, !cmd.isEmpty {
                                        let name = (inner["name"] as? String) ?? "\(mapping.stage.rawValue) (\(matcher))"
                                        hooks.append(AgentLifecycleHook(
                                            stage: mapping.stage,
                                            name: name,
                                            matcher: matcher,
                                            command: cmd,
                                            blockOnFailure: blockOnFailure,
                                            sourceFile: sourceLabel
                                        ))
                                    }
                                }
                            }
                        }
                    } else if let singleCmd = hooksRoot[key] as? String, !singleCmd.isEmpty {
                        hooks.append(AgentLifecycleHook(
                            stage: mapping.stage,
                            name: "\(mapping.stage.rawValue) hook",
                            matcher: "*",
                            command: singleCmd,
                            blockOnFailure: true,
                            sourceFile: sourceLabel
                        ))
                    }
                }
            }
        }
    }

    /// Executes matching lifecycle hooks for `pre_tool`, `post_tool`, or `pre_finish`.
    public func executeHooks(
        stage: AgentHookStage,
        toolName: String? = nil,
        filePath: String? = nil,
        workspaceRoot: String
    ) async -> (allowed: Bool, feedback: String) {
        let stageHooks = discoveredHooks.filter { $0.stage == stage }
        guard !stageHooks.isEmpty, !workspaceRoot.isEmpty else {
            return (true, "")
        }

        let matchingHooks = stageHooks.filter { hook in
            let m = hook.matcher.trimmingCharacters(in: .whitespacesAndNewlines)
            if m.isEmpty || m == "*" || m == "**/*" { return true }
            if let tool = toolName {
                let parts = m.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.contains(where: { $0.caseInsensitiveCompare(tool) == .orderedSame }) {
                    return true
                }
            }
            if let file = filePath {
                let relFile = file.replacingOccurrences(of: workspaceRoot + "/", with: "")
                if matchGlob(pattern: m, string: relFile) {
                    return true
                }
            }
            return false
        }

        guard !matchingHooks.isEmpty else { return (true, "") }

        var feedbackParts: [String] = []
        for hook in matchingHooks {
            let result = await runHookShellCommand(
                hook.command,
                stage: stage,
                toolName: toolName,
                filePath: filePath,
                workspaceRoot: workspaceRoot
            )
            if result.exitCode != 0 {
                let snippet = String(result.output.suffix(1200)).trimmingCharacters(in: .whitespacesAndNewlines)
                let msg = "⚠️ [Hook \(stage.badge) Failed — \(hook.name) (`\(hook.command)` exited with \(result.exitCode))]:\n\(snippet.isEmpty ? "(no output)" : snippet)"
                feedbackParts.append(msg)
                if hook.blockOnFailure {
                    return (false, feedbackParts.joined(separator: "\n\n"))
                }
            } else if !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && stage != .preTool {
                let snippet = String(result.output.suffix(600)).trimmingCharacters(in: .whitespacesAndNewlines)
                feedbackParts.append("ℹ️ [Hook \(stage.badge) — \(hook.name)]: \(snippet)")
            }
        }

        return (true, feedbackParts.joined(separator: "\n\n"))
    }

    private func runHookShellCommand(
        _ command: String,
        stage: AgentHookStage,
        toolName: String?,
        filePath: String?,
        workspaceRoot: String
    ) async -> (exitCode: Int32, output: String) {
        await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-c", command]
            proc.currentDirectoryURL = URL(fileURLWithPath: workspaceRoot)
            var env = ProcessInfo.processInfo.environment
            env["MICROCODE_HOOK_STAGE"] = stage.rawValue
            env["MICROCODE_WORKSPACE"] = workspaceRoot
            if let toolName { env["MICROCODE_TOOL"] = toolName }
            if let filePath {
                env["MICROCODE_FILE"] = filePath
                env["FILE"] = filePath
            }
            proc.environment = env

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            do {
                try proc.run()
                let deadline = Date().addingTimeInterval(15.0)
                while proc.isRunning && Date() < deadline {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                if proc.isRunning {
                    proc.terminate()
                    return (-1, "Hook timed out after 15s")
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                return (proc.terminationStatus, output)
            } catch {
                return (-1, error.localizedDescription)
            }
        }.value
    }

    // MARK: - MDC Parsing (.cursor/rules/*.mdc & .txcode/rules/*.md)

    private func parseMdcRule(fileURL: URL, rootURL: URL, sourceOverride: RulePlatformSource? = nil) -> PlatformRule? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8), !text.isEmpty else { return nil }

        var description = ""
        var globs: [String] = []
        var alwaysApply = false
        var markdownContent = text

        // Check YAML frontmatter: delimited by ---
        if text.hasPrefix("---") {
            let parts = text.components(separatedBy: "---")
            if parts.count >= 3 {
                let yaml = parts[1]
                markdownContent = parts.dropFirst(2).joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)

                for line in yaml.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("description:") {
                        description = trimmed.replacingOccurrences(of: "description:", with: "")
                            .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                    } else if trimmed.hasPrefix("globs:") {
                        let globVal = trimmed.replacingOccurrences(of: "globs:", with: "")
                            .trimmingCharacters(in: CharacterSet(charactersIn: " \"'[]"))
                        globs = globVal.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                    } else if trimmed.hasPrefix("alwaysApply:") {
                        let boolVal = trimmed.replacingOccurrences(of: "alwaysApply:", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        alwaysApply = (boolVal == "true" || boolVal == "1")
                    }
                }
            }
        }

        let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        let fallbackDesc = fileURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        return PlatformRule(
            source: sourceOverride ?? .cursorMdc,
            fileName: fileURL.lastPathComponent,
            relativePath: relativePath,
            summaryDescription: description.isEmpty ? fallbackDesc : description,
            globs: globs.isEmpty ? ["*"] : globs,
            alwaysApply: alwaysApply,
            content: markdownContent
        )
    }

    // MARK: - Glob Matching & Prompt Assembly

    /// Determines which rules match the currently open or active files
    public func activeRules(forFiles relativePaths: [String] = []) -> [PlatformRule] {
        if relativePaths.isEmpty {
            // Return all rules that are either alwaysApply or generic wildcard
            return discoveredRules.filter { $0.alwaysApply || $0.globs.contains("*") }
        }

        return discoveredRules.filter { rule in
            if rule.alwaysApply { return true }
            for glob in rule.globs {
                if glob == "*" || glob == "**/*" { return true }
                for file in relativePaths {
                    if matchGlob(pattern: glob, string: file) {
                        return true
                    }
                }
            }
            return false
        }
    }

    /// Generates a structured, token-conscious prompt section containing all active platform rules
    public func formatPromptSection(forFiles relativeFiles: [String] = [], maxTokens: Int = 1200) -> String {
        let matching = activeRules(forFiles: relativeFiles)
        guard !matching.isEmpty else { return "" }

        var output = "\n\n## Multi-Platform Rules & Guidelines (Cursor, Zed, Copilot)\n"
        output += "The following rules are dynamically imported and active for this project:\n\n"

        var currentTokenEst = 0

        for rule in matching {
            let header = "### [\(rule.source.badge)] \(rule.fileName) (\(rule.summaryDescription))\n"
            let globsStr = rule.globs.joined(separator: ", ")
            let meta = "> Scope: `\(globsStr)` | Always Apply: `\(rule.alwaysApply)`\n\n"
            
            // Limit each rule content if needed
            let trimmedContent = rule.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let ruleText = "\(header)\(meta)```markdown\n\(trimmedContent.prefix(2000))\n```\n\n"
            
            let estTokens = ruleText.count / 4
            if currentTokenEst + estTokens > maxTokens && currentTokenEst > 200 {
                output += "> ... [\(matching.count - 1) more rules omitted for token budget]\n"
                break
            }
            output += ruleText
            currentTokenEst += estTokens
        }

        return output
    }

    // MARK: - Helper Glob Matcher

    private func matchGlob(pattern: String, string: String) -> Bool {
        // Fast exact or extension match
        if pattern == string { return true }
        if pattern.hasPrefix("*.") {
            let ext = String(pattern.dropFirst(2))
            return string.hasSuffix("." + ext)
        }
        if pattern.hasPrefix("**/*.") {
            let ext = String(pattern.dropFirst(5))
            return string.hasSuffix("." + ext)
        }

        // Posix fnmatch fallback for standard globs
        let fnmatchResult = fnmatch(pattern, string, FNM_PATHNAME | FNM_PERIOD)
        if fnmatchResult == 0 { return true }

        // Relaxed path match: check if pattern suffix matches
        let cleanPattern = pattern.replacingOccurrences(of: "**/", with: "")
        if fnmatch(cleanPattern, (string as NSString).lastPathComponent, 0) == 0 {
            return true
        }

        return false
    }
}
