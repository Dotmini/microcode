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
    case cursorLegacy = "Cursor (.cursorrules)"
    case cursorMdc = "Cursor Modern (.cursor/rules/*.mdc)"
    case windsurf = "Windsurf (.windsurfrules)"
    case cline = "Cline (.clinerules)"
    case copilot = "Copilot (.copilot-instructions.md)"
    case zed = "Zed (.zed/settings.json)"
    case microcode = "MicroCode (.microcode/agent.md)"

    public var id: String { rawValue }

    public var badge: String {
        switch self {
        case .cursorLegacy, .cursorMdc: return "CURSOR"
        case .windsurf: return "WINDSURF"
        case .cline: return "CLINE"
        case .copilot: return "COPILOT"
        case .zed: return "ZED"
        case .microcode: return "MICROCODE"
        }
    }

    public var icon: String {
        switch self {
        case .cursorLegacy, .cursorMdc: return "cursorarrow.rays"
        case .windsurf: return "wind"
        case .cline: return "terminal"
        case .copilot: return "airplane"
        case .zed: return "bolt.fill"
        case .microcode: return "sparkles"
        }
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

    public init(
        id: String = UUID().uuidString,
        name: String,
        sourcePlatform: String,
        command: String,
        args: [String],
        env: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.sourcePlatform = sourcePlatform
        self.command = command
        self.args = args
        self.env = env
    }
}

public final class MultiPlatformRulesEngine: ObservableObject {
    public static let shared = MultiPlatformRulesEngine()

    @Published public private(set) var discoveredRules: [PlatformRule] = []
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
                self.discoveredMCPServers = []
                self.ignoredPatterns = []
                self.currentWorkspace = nil
            }
            return
        }

        scanQueue.async { [weak self] in
            guard let self = self else { return }
            var rules: [PlatformRule] = []
            var ignores: [String] = []

            let rootURL = URL(fileURLWithPath: root)

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

            // 8. Scan MicroCode .microcode/agent.md
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

            // 9. Scan Cursor MCP servers (.cursor/mcp.json or .mcp.json)
            var mcpServers: [DiscoveredMCPServer] = []
            let mcpCandidates: [(URL, String)] = [
                (rootURL.appendingPathComponent(".cursor/mcp.json"), "Cursor (.cursor/mcp.json)"),
                (rootURL.appendingPathComponent(".mcp.json"), "MCP Standard (.mcp.json)"),
                (self.fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".cursor/mcp.json"), "Cursor User (~/.cursor/mcp.json)")
            ]
            for (fileURL, label) in mcpCandidates {
                if let data = try? Data(contentsOf: fileURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let servers = json["mcpServers"] as? [String: [String: Any]] {
                    for (serverName, spec) in servers {
                        let cmd = spec["command"] as? String ?? ""
                        let args = spec["args"] as? [String] ?? []
                        let env = spec["env"] as? [String: String] ?? [:]
                        if !cmd.isEmpty && !mcpServers.contains(where: { $0.name == serverName }) {
                            mcpServers.append(DiscoveredMCPServer(
                                name: serverName,
                                sourcePlatform: label,
                                command: cmd,
                                args: args,
                                env: env
                            ))
                        }
                    }
                }
            }

            let finalRules = rules
            let finalMCPServers = mcpServers
            let finalIgnores = ignores
            DispatchQueue.main.async {
                self.discoveredRules = finalRules
                self.discoveredMCPServers = finalMCPServers
                self.ignoredPatterns = finalIgnores
                self.lastScanDate = Date()
                self.currentWorkspace = root
            }
        }
    }

    // MARK: - MDC Parsing (.cursor/rules/*.mdc)

    private func parseMdcRule(fileURL: URL, rootURL: URL) -> PlatformRule? {
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
            source: .cursorMdc,
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
