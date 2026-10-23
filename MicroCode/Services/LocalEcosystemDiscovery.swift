//
//  LocalEcosystemDiscovery.swift
//  MicroCode
//
//  Created and Designed by Dotmini Software
//  Founder & CEO: Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//
//  Description:
//  Discovers real, installed AI engines and models dynamically from disk and CLI tools:
//  1. OpenAI Codex: ~/.codex/models_cache.json, ~/.codex/config.toml, ~/.codex/auth.json
//  2. Google Antigravity (AGY): `agy models` CLI and local configuration
//  3. Anthropic Claude Code: ~/.claude/settings.json and CLI binary
//  4. Zed / ZCode Assistant: ~/.config/zed/settings.json
//

import Foundation
import Combine

struct EcosystemEngineInfo: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let icon: String
    let binaryPath: String?
    let isInstalled: Bool
    let isAuthenticated: Bool
    let activeModel: String?
    var models: [AIModelDefinition]
    let details: String
    
    init(
        id: String,
        name: String,
        icon: String,
        binaryPath: String?,
        isInstalled: Bool,
        isAuthenticated: Bool,
        activeModel: String?,
        models: [AIModelDefinition],
        details: String
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.binaryPath = binaryPath
        self.isInstalled = isInstalled
        self.isAuthenticated = isAuthenticated
        self.activeModel = activeModel
        self.models = models
        self.details = details
    }
}

@MainActor
final class LocalEcosystemDiscovery: ObservableObject {
    static let shared = LocalEcosystemDiscovery()
    
    @Published private(set) var engines: [EcosystemEngineInfo] = []
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var lastScanDate: Date?
    
    private let userDefaultsCacheKey = "microcode_ecosystem_discovered_models_v4"
    
    private init() {
        loadCachedEngines()
    }
    
    func models(for engineId: String) -> [AIModelDefinition] {
        engines.first(where: { $0.id == engineId })?.models ?? []
    }
    
    var allDiscoveredModels: [AIModelDefinition] {
        engines.flatMap(\.models)
    }
    
    func refresh() async {
        guard !isScanning else { return }
        self.isScanning = true
        defer {
            self.isScanning = false
        }
        
        // Discover all installed CLI engines concurrently
        async let agyTask = discoverAGY()
        async let openCodeTask = discoverOpenCode()
        let codexEngine = discoverCodex()
        let zedEngine = discoverZed()
        
        let (agyEngine, openCodeEngine) = await (agyTask, openCodeTask)
        let claudeEngine = await discoverClaude(agyModels: agyEngine.models)
        
        let discovered: [EcosystemEngineInfo] = [
            agyEngine,
            openCodeEngine,
            codexEngine,
            claudeEngine,
            zedEngine
        ]
        
        self.engines = discovered
        self.lastScanDate = Date()
        saveCachedEngines(discovered)
        AIModelCatalog.shared.integrateEcosystemEngines(discovered)
    }
    
    // MARK: - 1. Antigravity (AGY) Discovery
    
    private func discoverAGY() async -> EcosystemEngineInfo {
        let path = resolveBinary("agy") ?? resolveBinaryFast("agy")
        let isInstalled = path != nil
        var models: [AIModelDefinition] = []
        
        if let path = path {
            // Execute `agy models` via CLI (allow up to 25s because AGY queries remote live catalog)
            let cliOutput = await runCommand(executable: path, arguments: ["models"], timeoutSeconds: 25.0)
            let parsed = parseAGYModelsOutput(cliOutput)
            if !parsed.isEmpty {
                models = parsed
            }
        }
        
        // If CLI was momentarily unreachable, preserve previously discovered AGY models from cache
        if models.isEmpty, let cached = engines.first(where: { $0.id == "agy" })?.models, !cached.isEmpty {
            models = cached
        }
        if models.isEmpty && isInstalled {
            models = Self.defaultAGYModels
        }
        
        let active = models.first?.id
        
        return EcosystemEngineInfo(
            id: "agy",
            name: "Google Antigravity (AGY)",
            icon: "sparkles",
            binaryPath: path,
            isInstalled: isInstalled,
            isAuthenticated: isInstalled && !models.isEmpty,
            activeModel: active,
            models: models,
            details: models.isEmpty
                ? (isInstalled ? "Run `agy models` or `agy auth login` to fetch live models" : "Antigravity CLI (`agy`) not installed")
                : "Live models fetched via `agy models` (\(models.count) models)"
        )
    }
    
    static let defaultAGYModels: [AIModelDefinition] = [
        AIModelDefinition(id: "gemini-3.8-flash-low", name: "Gemini 3 Flash (Low)", provider: "agy", badge: "FAST"),
        AIModelDefinition(id: "gemini-3.8-flash-medium", name: "Gemini 3 Flash (Medium)", provider: "agy", badge: "FAST"),
        AIModelDefinition(id: "gemini-3.8-flash-high", name: "Gemini 3 Flash (High)", provider: "agy", badge: "HIGH REASONING"),
        AIModelDefinition(id: "gemini-4-argon-low", name: "Gemini 3.1 Pro (Low)", provider: "agy", badge: "FLAGSHIP"),
        AIModelDefinition(id: "gemini-4-argon-medium", name: "Gemini 3.1 Pro (Medium)", provider: "agy", badge: "FLAGSHIP"),
        AIModelDefinition(id: "gemini-4-argon-high", name: "Gemini 3.1 Pro (High)", provider: "agy", badge: "FLAGSHIP"),
        AIModelDefinition(id: "claude-sonnet-5-5-low", name: "Claude Sonnet 4.6 (Low)", provider: "agy", badge: "PRO"),
        AIModelDefinition(id: "claude-sonnet-5-5-medium", name: "Claude Sonnet 4.6 (Medium)", provider: "agy", badge: "PRO"),
        AIModelDefinition(id: "claude-sonnet-5-5-high", name: "Claude Sonnet 4.6 (High)", provider: "agy", badge: "HIGH REASONING"),
        AIModelDefinition(id: "claude-opus-5-5-low", name: "Claude Opus 4.6 (Low)", provider: "agy", badge: "REASONING"),
        AIModelDefinition(id: "claude-opus-5-5-medium", name: "Claude Opus 4.6 (Medium)", provider: "agy", badge: "REASONING"),
        AIModelDefinition(id: "claude-opus-5-5-high", name: "Claude Opus 4.6 (High)", provider: "agy", badge: "HIGH REASONING"),
        AIModelDefinition(id: "gpt-oss-120b-medium", name: "GPT-OSS 120B (Medium)", provider: "agy", badge: "AGY LIVE")
    ]
    
    private func parseAGYModelsOutput(_ output: String) -> [AIModelDefinition] {
        var results: [AIModelDefinition] = []
        var seenIds = Set<String>()
        
        // Strip ANSI escape sequences
        let ansiPattern = #"\u{001B}\[[0-9;]*[a-zA-Z]"#
        let cleanOutput = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
        
        // Split by both \r and \n because `agy models` uses \r for its braille progress spinner
        // right before printing the first model line.
        let spinnerChars = CharacterSet(charactersIn: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
        let rawSegments = cleanOutput.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
        
        for segment in rawSegments {
            var trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            trimmed = trimmed.trimmingCharacters(in: spinnerChars).trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !trimmed.isEmpty else { continue }
            let lowerLine = trimmed.lowercased()
            if lowerLine.contains("fetching available models") ||
               lowerLine.hasPrefix("fetching") ||
               lowerLine.hasPrefix("usage") ||
               lowerLine.hasPrefix("error") ||
               lowerLine.hasPrefix("warn") {
                continue
            }
            
            var id = ""
            var displayName = ""
            
            if trimmed.contains("\t") {
                let parts = trimmed.split(separator: "\t", maxSplits: 1).map(String.init)
                id = parts[0].trimmingCharacters(in: .whitespaces)
                displayName = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : id
            } else {
                let parts = trimmed.components(separatedBy: CharacterSet.whitespaces).filter { !$0.isEmpty }
                guard let first = parts.first else { continue }
                id = first
                displayName = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : id
            }
            
            // Valid model IDs have no spaces and contain letters/hyphens
            guard !id.isEmpty,
                  !id.contains(" "),
                  id.range(of: #"^[a-zA-Z0-9._/-]+$"#, options: .regularExpression) != nil,
                  !seenIds.contains(id) else { continue }
            seenIds.insert(id)
            
            let lower = id.lowercased()
            let badge: String
            if lower.contains("argon") { badge = "FLAGSHIP" }
            else if lower.contains("high") { badge = "HIGH REASONING" }
            else if lower.contains("opus") { badge = "REASONING" }
            else if lower.contains("sonnet") || lower.contains("pro") { badge = "PRO" }
            else if lower.contains("thinking") { badge = "THINKING" }
            else if lower.contains("flash") || lower.contains("low") { badge = "FAST" }
            else { badge = "AGY LIVE" }
            
            results.append(AIModelDefinition(
                id: id,
                name: displayName.isEmpty ? AIModelCatalog.formatModelName(id) : displayName,
                provider: "agy",
                badge: badge
            ))
        }
        return results
    }
    
    // MARK: - 2. OpenCode Discovery
    
    private func discoverOpenCode() async -> EcosystemEngineInfo {
        let path = resolveBinary("opencode") ?? resolveBinaryFast("opencode")
        let isInstalled = path != nil
        
        let authPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/auth.json")
        var isAuthenticated = false
        if let authData = try? Data(contentsOf: authPath),
           let json = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
           !json.isEmpty {
            isAuthenticated = true
        }
        
        var models: [AIModelDefinition] = []
        if isInstalled, let path = path {
            let cliOutput = await runCommand(executable: path, arguments: ["models"], timeoutSeconds: 15.0)
            let ansiPattern = #"\u{001B}\[[0-9;]*[a-zA-Z]"#
            let cleanOutput = cliOutput.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
            let lines = cleanOutput.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            var seen = Set<String>()
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      !trimmed.contains("┌"), !trimmed.contains("└"), !trimmed.contains("│"),
                      !trimmed.lowercased().contains("error"),
                      !trimmed.lowercased().contains("usage") else { continue }
                
                let parts = trimmed.split(separator: " ").map(String.init)
                if let modelId = parts.first, modelId.contains("/"), !seen.contains(modelId) {
                    seen.insert(modelId)
                    let displayName = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : AIModelCatalog.formatModelName(modelId)
                    let isFree = modelId.lowercased().contains("free")
                    let badge = isFree ? "FREE" : (isAuthenticated ? "LIVE" : "NEEDS AUTH")
                    models.append(AIModelDefinition(
                        id: modelId,
                        name: displayName,
                        provider: "opencode",
                        badge: badge
                    ))
                }
            }
        }
        
        if models.isEmpty, let cached = engines.first(where: { $0.id == "opencode" })?.models, !cached.isEmpty {
            models = cached
        }
        
        // Sort: Free models first
        models.sort { a, b in
            let aFree = a.id.lowercased().contains("free")
            let bFree = b.id.lowercased().contains("free")
            if aFree && !bFree { return true }
            if !aFree && bFree { return false }
            return a.id < b.id
        }
        
        let defaultModel = models.first?.id
        
        return EcosystemEngineInfo(
            id: "opencode",
            name: "OpenCode",
            icon: "laptopcomputer",
            binaryPath: path,
            isInstalled: isInstalled,
            isAuthenticated: isAuthenticated,
            activeModel: defaultModel,
            models: models,
            details: isInstalled
                ? "Live models fetched via `opencode models` (\(models.count) models)"
                : "OpenCode CLI not installed"
        )
    }
    
    // MARK: - 3. OpenAI Codex Discovery
    
    private func discoverCodex() -> EcosystemEngineInfo {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexDir = home.appendingPathComponent(".codex")
        let cacheFile = codexDir.appendingPathComponent("models_cache.json")
        let configFile = codexDir.appendingPathComponent("config.toml")
        let authFile = codexDir.appendingPathComponent("auth.json")
        
        let binaryPath = resolveBinary("codex") ?? resolveBinaryFast("codex")
        let isInstalled = binaryPath != nil || FileManager.default.fileExists(atPath: cacheFile.path)
        let isAuthenticated = FileManager.default.fileExists(atPath: authFile.path)
        
        var activeModel: String? = nil
        if let configData = try? String(contentsOf: configFile, encoding: .utf8) {
            for line in configData.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("model =") || trimmed.hasPrefix("model=") {
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    if parts.count > 1 {
                        activeModel = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                    }
                }
            }
        }
        
        var models: [AIModelDefinition] = []
        if let data = try? Data(contentsOf: cacheFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let modelList = json["models"] as? [[String: Any]] {
            for item in modelList {
                guard let slug = item["slug"] as? String else { continue }
                let vis = (item["visibility"] as? String) ?? "list"
                if vis == "hide" && slug != activeModel { continue }
                
                let displayName = (item["display_name"] as? String) ?? AIModelCatalog.formatModelName(slug)
                let lower = slug.lowercased()
                let badge: String
                if slug == activeModel {
                    badge = "ACTIVE • CODEX"
                } else if lower.contains("astra") || lower.contains("6") {
                    badge = "FLAGSHIP"
                } else if lower.contains("sol") || lower.contains("pro") {
                    badge = "HIGH PERF"
                } else if lower.contains("luna") {
                    badge = "FAST"
                } else {
                    badge = "CODEX LIVE"
                }
                
                models.append(AIModelDefinition(
                    id: slug,
                    name: displayName,
                    provider: "codex",
                    badge: badge
                ))
            }
        }
        
        if models.isEmpty, let cached = engines.first(where: { $0.id == "codex" })?.models, !cached.isEmpty {
            models = cached
        }
        
        return EcosystemEngineInfo(
            id: "codex",
            name: "OpenAI Codex",
            icon: "terminal.fill",
            binaryPath: binaryPath,
            isInstalled: isInstalled,
            isAuthenticated: isAuthenticated,
            activeModel: activeModel ?? models.first?.id,
            models: models,
            details: !models.isEmpty
                ? "Live models from ~/.codex/models_cache.json (\(models.count) models)"
                : (isInstalled ? "OpenAI Codex CLI installed" : "Codex CLI not installed")
        )
    }
    
    // MARK: - 4. Claude Code Discovery
    
    private func discoverClaude(agyModels: [AIModelDefinition] = []) async -> EcosystemEngineInfo {
        let path = resolveBinary("claude") ?? resolveBinaryFast("claude")
        let isInstalled = path != nil
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsFile = home.appendingPathComponent(".claude/settings.json")
        
        var activeModel: String? = nil
        if let data = try? Data(contentsOf: settingsFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let m = json["model"] as? String, !m.isEmpty {
            activeModel = m
        }
        
        var models: [AIModelDefinition] = []
        var seen = Set<String>()
        
        // 1. Include any live Anthropic API models already fetched in AIModelCatalog
        if let anthropicProv = AIModelCatalog.shared.provider("anthropic") {
            for m in anthropicProv.models where m.badge != "DEFAULT" {
                if !seen.contains(m.id) {
                    seen.insert(m.id)
                    models.append(AIModelDefinition(
                        id: m.id,
                        name: m.name,
                        provider: "claude_code",
                        badge: m.id == activeModel ? "ACTIVE • \(m.badge)" : m.badge
                    ))
                }
            }
        }
        
        // 2. Include live Claude models discovered from AGY CLI (e.g. claude-opus-5-5-high, claude-sonnet-5-5-high)
        for m in agyModels where m.id.lowercased().contains("claude") {
            if !seen.contains(m.id) {
                seen.insert(m.id)
                models.append(AIModelDefinition(
                    id: m.id,
                    name: m.name,
                    provider: "claude_code",
                    badge: m.id == activeModel ? "ACTIVE • \(m.badge)" : m.badge
                ))
            }
        }
        
        models.sort { a, b in
            let sa = AIModelCatalog.claudeModelSortScore(a.id)
            let sb = AIModelCatalog.claudeModelSortScore(b.id)
            if sa != sb { return sa > sb }
            return a.id.localizedStandardCompare(b.id) == .orderedDescending
        }
        
        // 3. Append standard Claude Code CLI aliases after the concrete live models
        for (alias, label, badge) in [
            ("opus", "Claude Opus (Latest Alias)", "OPUS"),
            ("sonnet", "Claude Sonnet (Latest Alias)", "SONNET"),
            ("haiku", "Claude Haiku (Latest Alias)", "HAIKU"),
            ("auto", "Claude Code Auto", "DYNAMIC")
        ] {
            if !seen.contains(alias) {
                seen.insert(alias)
                models.append(AIModelDefinition(
                    id: alias,
                    name: label,
                    provider: "claude_code",
                    badge: alias == activeModel ? "ACTIVE • \(badge)" : badge
                ))
            }
        }
        
        if let active = activeModel, !seen.contains(active) {
            seen.insert(active)
            models.append(AIModelDefinition(
                id: active,
                name: "Claude (\(active))",
                provider: "claude_code",
                badge: "ACTIVE"
            ))
        }
        
        return EcosystemEngineInfo(
            id: "claude_code",
            name: "Anthropic Claude Code",
            icon: "command.square.fill",
            binaryPath: path,
            isInstalled: isInstalled,
            isAuthenticated: isInstalled,
            activeModel: models.first?.id ?? activeModel,
            models: models,
            details: isInstalled
                ? "Claude Code CLI with \(models.count) live models (active: '\(models.first?.id ?? activeModel ?? "default")')"
                : "Claude Code CLI not installed"
        )
    }
    
    // MARK: - 5. Zed / ZCode Discovery
    
    private func discoverZed() -> EcosystemEngineInfo {
        let path = resolveBinary("zed") ?? resolveBinaryFast("zed")
        let home = FileManager.default.homeDirectoryForCurrentUser
        let zedSettings = home.appendingPathComponent(".config/zed/settings.json")
        let isInstalled = path != nil || FileManager.default.fileExists(atPath: zedSettings.path)
        
        var models: [AIModelDefinition] = []
        var seen = Set<String>()
        var defaultModel: String? = nil
        
        if let rawText = try? String(contentsOf: zedSettings, encoding: .utf8) {
            let stripped = stripJSONCComments(rawText)
            if let data = stripped.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let agent = json["agent"] as? [String: Any] {
                    if let def = agent["default_model"] as? [String: Any], let m = def["model"] as? String, !m.isEmpty {
                        defaultModel = m
                        seen.insert(m)
                        models.append(AIModelDefinition(
                            id: m,
                            name: AIModelCatalog.formatModelName(m),
                            provider: "zed",
                            badge: "ZED DEFAULT"
                        ))
                    }
                    if let inl = agent["inline_assistant_model"] as? [String: Any], let m = inl["model"] as? String, !m.isEmpty, !seen.contains(m) {
                        seen.insert(m)
                        models.append(AIModelDefinition(
                            id: m,
                            name: AIModelCatalog.formatModelName(m),
                            provider: "zed",
                            badge: "ZED INLINE"
                        ))
                    }
                }
                if let assistant = json["assistant"] as? [String: Any],
                   let def = assistant["default_model"] as? [String: Any],
                   let m = def["model"] as? String, !m.isEmpty, !seen.contains(m) {
                    if defaultModel == nil { defaultModel = m }
                    seen.insert(m)
                    models.append(AIModelDefinition(
                        id: m,
                        name: AIModelCatalog.formatModelName(m),
                        provider: "zed",
                        badge: "ZED DEFAULT"
                    ))
                }
            }
        }
        
        return EcosystemEngineInfo(
            id: "zed",
            name: "Zed / ZCode Assistant",
            icon: "chevron.left.forwardslash.chevron.right",
            binaryPath: path,
            isInstalled: isInstalled,
            isAuthenticated: isInstalled,
            activeModel: defaultModel ?? models.first?.id,
            models: models,
            details: defaultModel != nil
                ? "Zed settings from ~/.config/zed/settings.json (Default: \(defaultModel!))"
                : "Zed assistant settings (~/.config/zed/settings.json)"
        )
    }
    
    // MARK: - Helpers
    
    private func resolveBinary(_ name: String) -> String? {
        return ACPHostService.resolveExecutablePath(name)
    }
    
    private func runCommand(executable: String, arguments: [String], timeoutSeconds: Double = 25.0) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = Pipe()
                
                var env = ProcessInfo.processInfo.environment
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let extraPaths = [
                    "\(home)/.local/bin",
                    "\(home)/.opencode/bin",
                    "/opt/homebrew/bin",
                    "/usr/local/bin",
                    "\(home)/.cargo/bin",
                    "\(home)/.bun/bin",
                    "\(home)/.npm-global/bin",
                    "/usr/bin",
                    "/bin"
                ].joined(separator: ":")
                if let existingPath = env["PATH"], !existingPath.isEmpty {
                    env["PATH"] = "\(extraPaths):\(existingPath)"
                } else {
                    env["PATH"] = extraPaths
                }
                env["NO_COLOR"] = "1"
                env.removeValue(forKey: "MICROCODE_LOCAL_API_TOKEN")
                process.environment = env
                
                do {
                    try process.run()
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                        if process.isRunning {
                            process.terminate()
                        }
                    }
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
    
    private func stripJSONCComments(_ input: String) -> String {
        var output = ""
        let lines = input.components(separatedBy: .newlines)
        var insideBlockComment = false
        
        for line in lines {
            var curr = line
            if insideBlockComment {
                if let endRange = curr.range(of: "*/") {
                    curr = String(curr[endRange.upperBound...])
                    insideBlockComment = false
                } else {
                    continue
                }
            }
            
            while let startRange = curr.range(of: "/*") {
                if let endRange = curr.range(of: "*/", range: startRange.upperBound..<curr.endIndex) {
                    curr.removeSubrange(startRange.lowerBound..<endRange.upperBound)
                } else {
                    curr = String(curr[..<startRange.lowerBound])
                    insideBlockComment = true
                    break
                }
            }
            
            if let singleLineRange = curr.range(of: "//") {
                curr = String(curr[..<singleLineRange.lowerBound])
            }
            
            output += curr + "\n"
        }
        return output
    }
    
    private func resolveBinaryFast(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let checkPaths = [
            "\(home)/.local/bin/\(name)",
            "\(home)/.opencode/bin/\(name)",
            "\(home)/.codex/plugins/.plugin-appserver/codex-cli/bin/\(name)",
            "\(home)/.codex/plugins/.plugin-appserver/codex-cli/CodexCLI.app/Contents/MacOS/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.cargo/bin/\(name)",
            "\(home)/.bun/bin/\(name)",
            "\(home)/.npm-global/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        return checkPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }
    
    private func saveCachedEngines(_ discovered: [EcosystemEngineInfo]) {
        if let data = try? JSONEncoder().encode(discovered) {
            UserDefaults.standard.set(data, forKey: userDefaultsCacheKey)
        }
    }
    
    private func loadCachedEngines() {
        // 1. Load previously persisted live-discovered engines if available
        if let data = UserDefaults.standard.data(forKey: userDefaultsCacheKey),
           let cached = try? JSONDecoder().decode([EcosystemEngineInfo].self, from: data),
           !cached.isEmpty {
            self.engines = cached.map { eng in
                if eng.id == "codex", let bp = eng.binaryPath, bp.contains(".plugin-appserver/codex-cli"),
                   let healed = resolveBinaryFast("codex") {
                    return EcosystemEngineInfo(
                        id: eng.id, name: eng.name, icon: eng.icon, binaryPath: healed,
                        isInstalled: eng.isInstalled, isAuthenticated: eng.isAuthenticated,
                        activeModel: eng.activeModel, models: eng.models, details: eng.details
                    )
                }
                if eng.id == "agy" && eng.models.isEmpty && eng.isInstalled {
                    return EcosystemEngineInfo(
                        id: eng.id, name: eng.name, icon: eng.icon, binaryPath: eng.binaryPath,
                        isInstalled: eng.isInstalled, isAuthenticated: true,
                        activeModel: Self.defaultAGYModels.first?.id, models: Self.defaultAGYModels, details: eng.details
                    )
                }
                return eng
            }
            return
        }
        
        // 2. Otherwise synchronously read fast local disk caches (~/.codex/models_cache.json, ~/.claude/settings.json, ~/.config/zed/settings.json)
        let codex = discoverCodex()
        let zed = discoverZed()
        let agyBin = resolveBinaryFast("agy")
        self.engines = [
            EcosystemEngineInfo(
                id: "agy",
                name: "Google Antigravity (AGY)",
                icon: "sparkles",
                binaryPath: agyBin,
                isInstalled: agyBin != nil,
                isAuthenticated: agyBin != nil,
                activeModel: agyBin != nil ? Self.defaultAGYModels.first?.id : nil,
                models: agyBin != nil ? Self.defaultAGYModels : [],
                details: "Live models from `agy models`"
            ),
            EcosystemEngineInfo(
                id: "opencode",
                name: "OpenCode",
                icon: "laptopcomputer",
                binaryPath: resolveBinaryFast("opencode"),
                isInstalled: resolveBinaryFast("opencode") != nil,
                isAuthenticated: false,
                activeModel: nil,
                models: [],
                details: "Fetching live models from `opencode models`..."
            ),
            codex,
            EcosystemEngineInfo(
                id: "claude_code",
                name: "Anthropic Claude Code",
                icon: "command.square.fill",
                binaryPath: resolveBinaryFast("claude"),
                isInstalled: resolveBinaryFast("claude") != nil,
                isAuthenticated: resolveBinaryFast("claude") != nil,
                activeModel: nil,
                models: [],
                details: "Reading ~/.claude/settings.json..."
            ),
            zed
        ]
    }
}
