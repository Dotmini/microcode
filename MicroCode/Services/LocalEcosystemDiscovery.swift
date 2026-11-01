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
    
    private let userDefaultsCacheKey = "microcode_ecosystem_discovered_models_v6"
    private let legacyCacheKeyV5 = "microcode_ecosystem_discovered_models_v5"
    private let launchDate = Date()
    private var loadedFromPersistedCache = false
    
    private init() {
        UserDefaults.standard.removeObject(forKey: legacyCacheKeyV5)
        loadCachedEngines()
        if !loadedFromPersistedCache {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await self.refresh(force: true)
            }
        }
    }
    
    func models(for engineId: String) -> [AIModelDefinition] {
        engines.first(where: { $0.id == engineId })?.models ?? []
    }
    
    var allDiscoveredModels: [AIModelDefinition] {
        engines.flatMap(\.models)
    }
    
    func refresh(force: Bool = false) async {
        guard !isScanning else { return }
        if !force, loadedFromPersistedCache, Date().timeIntervalSince(launchDate) < 3.5, !engines.isEmpty {
            return
        }
        self.isScanning = true
        defer {
            self.isScanning = false
        }
        
        // Discover all installed CLI engines concurrently (only spawn heavy external CLI processes when forced or uncached)
        async let agyTask = discoverAGY(force: force)
        async let openCodeTask = discoverOpenCode(force: force)
        let codexEngine = discoverCodex()
        let zedEngine = discoverZed()
        let geminiCLIEngine = discoverGeminiCLI()
        let cursorEngine = discoverCursorAgent()
        let copilotEngine = discoverCopilot()
        let gooseEngine = discoverGoose()
        let clineEngine = discoverCline()
        let qwenEngine = discoverQwenCode()
        let aiderEngine = discoverAider()
        
        let (agyEngine, openCodeEngine) = await (agyTask, openCodeTask)
        let claudeEngine = await discoverClaude(agyModels: agyEngine.models)
        
        let discovered: [EcosystemEngineInfo] = [
            agyEngine,
            claudeEngine,
            codexEngine,
            geminiCLIEngine,
            openCodeEngine,
            cursorEngine,
            copilotEngine,
            gooseEngine,
            clineEngine,
            qwenEngine,
            aiderEngine,
            zedEngine
        ]
        
        self.engines = discovered
        self.lastScanDate = Date()
        saveCachedEngines(discovered)
        AIModelCatalog.shared.integrateEcosystemEngines(discovered)
    }
    
    // MARK: - 1. Antigravity (AGY) Discovery
    
    private func discoverAGY(force: Bool = false) async -> EcosystemEngineInfo {
        let path = resolveBinaryFast("agy") ?? resolveBinary("agy")
        let isInstalled = path != nil
        var models: [AIModelDefinition] = []
        let cachedModels = (engines.first(where: { $0.id == "agy" })?.models ?? []).filter {
            let lower = $0.id.lowercased()
            return !lower.contains("4-6") && !lower.hasSuffix("-thinking")
        }

        if let path = path, (force || !loadedFromPersistedCache || cachedModels.isEmpty) {
            // Execute `agy models` via CLI only on explicit refresh or cold cache (avoids spawning Electron CLI on every app boot)
            let cliOutput = await runCommand(executable: path, arguments: ["models"], timeoutSeconds: 25.0)
            let parsed = parseAGYModelsOutput(cliOutput)
            if !parsed.isEmpty {
                models = parsed
            }
        }

        // Preserve previously discovered AGY models from cache
        if models.isEmpty, !cachedModels.isEmpty {
            models = cachedModels
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
        AIModelDefinition(id: "gemini-4-argon-high", name: "Gemini 4 Argon (High)", provider: "agy", badge: "FLAGSHIP"),
        AIModelDefinition(id: "gemini-4-argon-medium", name: "Gemini 4 Argon (Medium)", provider: "agy", badge: "FLAGSHIP"),
        AIModelDefinition(id: "gemini-4-argon-low", name: "Gemini 4 Argon (Low)", provider: "agy", badge: "FLAGSHIP"),
        AIModelDefinition(id: "gemini-3.8-flash-high", name: "Gemini 3.8 Flash (High)", provider: "agy", badge: "HIGH REASONING"),
        AIModelDefinition(id: "gemini-3.8-flash-medium", name: "Gemini 3.8 Flash (Medium)", provider: "agy", badge: "FAST"),
        AIModelDefinition(id: "gemini-3.8-flash-low", name: "Gemini 3.8 Flash (Low)", provider: "agy", badge: "FAST"),
        AIModelDefinition(id: "claude-opus-5-5-high", name: "Claude Opus 5.5 (High)", provider: "agy", badge: "HIGH REASONING"),
        AIModelDefinition(id: "claude-opus-5-5-medium", name: "Claude Opus 5.5 (Medium)", provider: "agy", badge: "REASONING"),
        AIModelDefinition(id: "claude-opus-5-5-low", name: "Claude Opus 5.5 (Low)", provider: "agy", badge: "REASONING"),
        AIModelDefinition(id: "claude-sonnet-5-5-high", name: "Claude Sonnet 5.5 (High)", provider: "agy", badge: "HIGH REASONING"),
        AIModelDefinition(id: "claude-sonnet-5-5-medium", name: "Claude Sonnet 5.5 (Medium)", provider: "agy", badge: "PRO"),
        AIModelDefinition(id: "claude-sonnet-5-5-low", name: "Claude Sonnet 5.5 (Low)", provider: "agy", badge: "PRO"),
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
    
    private func discoverOpenCode(force: Bool = false) async -> EcosystemEngineInfo {
        let path = resolveBinaryFast("opencode") ?? resolveBinary("opencode")
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
        let cachedModels = (engines.first(where: { $0.id == "opencode" })?.models ?? []).filter {
            !ACPAgentSession.retiredOpenCodeModels.contains($0.id.lowercased())
        }
        if isInstalled, let path = path, (force || !loadedFromPersistedCache || cachedModels.isEmpty) {
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
                if let modelId = parts.first,
                   modelId.contains("/"),
                   !ACPAgentSession.retiredOpenCodeModels.contains(modelId.lowercased()),
                   !seen.contains(modelId) {
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
        
        if models.isEmpty, !cachedModels.isEmpty {
            models = cachedModels
        }
        if models.isEmpty && isInstalled {
            models = [
                AIModelDefinition(
                    id: ACPAgentSession.fallbackOpenCodeFreeModel,
                    name: "MiMo V2.6 Flash (Free)",
                    provider: "opencode",
                    badge: "FREE"
                )
            ]
        }
        
        // Sort: verified primary free model first, then other free models, then authenticated models
        models.sort { a, b in
            let aPrimary = a.id == ACPAgentSession.fallbackOpenCodeFreeModel
            let bPrimary = b.id == ACPAgentSession.fallbackOpenCodeFreeModel
            if aPrimary != bPrimary { return aPrimary }
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
        
        // 1. Include any live Anthropic API models already fetched in AIModelCatalog (excluding AGY-exclusive slugs)
        if let anthropicProv = AIModelCatalog.shared.provider("anthropic") {
            for m in anthropicProv.models where m.badge != "DEFAULT" {
                let lower = m.id.lowercased()
                guard !lower.contains("5-5"),
                      !lower.hasSuffix("-thinking"),
                      !lower.hasSuffix("-high"),
                      !lower.hasSuffix("-medium"),
                      !lower.hasSuffix("-low") else { continue }
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
        
        // 2. Include standard Anthropic Claude Code concrete models when installed
        for (modelId, label, badge) in Self.defaultClaudeCodeModels {
            if !seen.contains(modelId) {
                seen.insert(modelId)
                models.append(AIModelDefinition(
                    id: modelId,
                    name: label,
                    provider: "claude_code",
                    badge: modelId == activeModel ? "ACTIVE • \(badge)" : badge
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
            ("haiku", "Claude Haiku (Latest Alias)", "HAIKU")
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
    
    static let defaultClaudeCodeModels: [(String, String, String)] = [
        ("claude-opus-4-6", "Claude Opus 4.6", "FLAGSHIP"),
        ("claude-sonnet-4-6", "Claude Sonnet 4.6", "PRO"),
        ("claude-haiku-4-5", "Claude Haiku 4.5", "FAST")
    ]
    
    // MARK: - 5. Zed / ZCode Discovery
    
    private func discoverZed() -> EcosystemEngineInfo {
        let acpBinaryPath = ACPHostService.resolveAgentBinary(for: .zedEngine)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let zedSettings = home.appendingPathComponent(".config/zed/settings.json")
        let isInstalled = acpBinaryPath != nil
        
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
            binaryPath: acpBinaryPath,
            isInstalled: isInstalled,
            isAuthenticated: isInstalled,
            activeModel: defaultModel ?? models.first?.id,
            models: isInstalled ? models : [],
            details: defaultModel != nil
                ? "Zed settings imported from ~/.config/zed/settings.json (Default: \(defaultModel!))"
                : "Zed assistant settings (~/.config/zed/settings.json)"
        )
    }
    
    // MARK: - 6. Additional Major Harnesses (Gemini CLI, Cursor, Copilot, Goose, Cline, Qwen Code, Aider)
    
    private func discoverGeminiCLI() -> EcosystemEngineInfo {
        let path = resolveBinary("gemini") ?? resolveBinaryFast("gemini")
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsFile = home.appendingPathComponent(".gemini/settings.json")
        let isInstalled = path != nil
        var activeModel: String? = "gemini-2.5-pro"
        if let data = try? Data(contentsOf: settingsFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let m = json["model"] as? String, !m.isEmpty {
            activeModel = m
        }
        let models: [AIModelDefinition] = isInstalled ? [
            AIModelDefinition(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro (Gemini CLI)", provider: "gemini_cli", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gemini-3.1-pro-preview", name: "Gemini 3.1 Pro Preview (Gemini CLI)", provider: "gemini_cli", badge: "PRO"),
            AIModelDefinition(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash (Gemini CLI)", provider: "gemini_cli", badge: "FAST"),
            AIModelDefinition(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash (Gemini CLI)", provider: "gemini_cli", badge: "FAST")
        ] : []
        return EcosystemEngineInfo(
            id: "gemini_cli",
            name: "Google Gemini CLI",
            icon: "sparkles",
            binaryPath: path,
            isInstalled: isInstalled,
            isAuthenticated: isInstalled,
            activeModel: activeModel,
            models: models,
            details: isInstalled
                ? "Google Gemini CLI (`@google/gemini-cli`) installed at \(path ?? "")"
                : "Install via `npm install -g @google/gemini-cli`"
        )
    }
    
    private func discoverCursorAgent() -> EcosystemEngineInfo {
        let path = resolveBinary("cursor-agent") ?? resolveBinaryFast("cursor-agent")
        let isInstalled = path != nil
        let models: [AIModelDefinition] = isInstalled ? [
            AIModelDefinition(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6 (Cursor)", provider: "cursor", badge: "CURSOR PRO"),
            AIModelDefinition(id: "gpt-5.4", name: "GPT-5.4 (Cursor)", provider: "cursor", badge: "FLAGSHIP"),
            AIModelDefinition(id: "cursor-fast", name: "Cursor Fast", provider: "cursor", badge: "FAST")
        ] : []
        return EcosystemEngineInfo(
            id: "cursor",
            name: "Cursor Agent CLI",
            icon: "cursorarrow.rays",
            binaryPath: path,
            isInstalled: isInstalled,
            isAuthenticated: isInstalled,
            activeModel: models.first?.id,
            models: models,
            details: isInstalled
                ? "Cursor Agent CLI (`cursor-agent`) ready"
                : "Cursor Agent CLI (`cursor-agent`) not installed"
        )
    }
    
    private func discoverCopilot() -> EcosystemEngineInfo {
        let path = ACPHostService.resolveAgentBinary(for: .githubCopilot)
        let isInstalled = path != nil
        let hasGH = (resolveBinaryFast("gh") ?? resolveBinary("gh")) != nil
        let models: [AIModelDefinition] = isInstalled ? [
            AIModelDefinition(id: "claude-sonnet-4.6", name: "Claude Sonnet 4.6 (Copilot)", provider: "copilot", badge: "COPILOT PRO"),
            AIModelDefinition(id: "gpt-5.4", name: "GPT-5.4 (Copilot)", provider: "copilot", badge: "COPILOT"),
            AIModelDefinition(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro (Copilot)", provider: "copilot", badge: "COPILOT")
        ] : []
        return EcosystemEngineInfo(
            id: "copilot",
            name: "GitHub Copilot CLI",
            icon: "chevron.left.forwardslash.chevron.right",
            binaryPath: path,
            isInstalled: isInstalled,
            isAuthenticated: isInstalled,
            activeModel: models.first?.id,
            models: models,
            details: isInstalled
                ? "GitHub Copilot CLI (`\(path ?? "copilot")`) detected"
                : (hasGH
                    ? "GitHub CLI (`gh`) found — run `gh copilot` once in Terminal to install Copilot CLI"
                    : "Install via `npm install -g @github/copilot` or `gh copilot`")
        )
    }
    
    private func discoverGoose() -> EcosystemEngineInfo {
        let path = resolveBinary("goose") ?? resolveBinaryFast("goose")
        let isInstalled = path != nil
        let models: [AIModelDefinition] = isInstalled ? [
            AIModelDefinition(id: "claude-sonnet-4-6", name: "Goose ACP (Claude Sonnet 4.6)", provider: "goose", badge: "ACP NATIVE"),
            AIModelDefinition(id: "gpt-4.1", name: "Goose ACP (GPT-4.1)", provider: "goose", badge: "ACP NATIVE")
        ] : []
        return EcosystemEngineInfo(
            id: "goose",
            name: "Block Goose (ACP)",
            icon: "bird.fill",
            binaryPath: path,
            isInstalled: isInstalled,
            isAuthenticated: isInstalled,
            activeModel: models.first?.id,
            models: models,
            details: isInstalled
                ? "Block Goose CLI (`goose acp`) native ACP v1 agent"
                : "Install via `brew install block-goose-cli`"
        )
    }
    
    private func discoverCline() -> EcosystemEngineInfo {
        let path = resolveBinary("cline") ?? resolveBinaryFast("cline")
        let isInstalled = path != nil
        let models: [AIModelDefinition] = isInstalled ? [
            AIModelDefinition(id: "claude-sonnet-4-6", name: "Cline (Claude Sonnet 4.6)", provider: "cline", badge: "CLINE"),
            AIModelDefinition(id: "deepseek-r1", name: "Cline (DeepSeek R1)", provider: "cline", badge: "REASONING")
        ] : []
        return EcosystemEngineInfo(
            id: "cline",
            name: "Cline CLI",
            icon: "terminal",
            binaryPath: path,
            isInstalled: isInstalled,
            isAuthenticated: isInstalled,
            activeModel: models.first?.id,
            models: models,
            details: isInstalled
                ? "Cline CLI (`cline`) autonomous coding harness"
                : "Install via `npm install -g cline`"
        )
    }
    
    private func discoverQwenCode() -> EcosystemEngineInfo {
        let path = resolveBinary("qwen") ?? resolveBinaryFast("qwen")
        let isInstalled = path != nil
        let models: [AIModelDefinition] = isInstalled ? [
            AIModelDefinition(id: "qwen3-coder-plus", name: "Qwen3 Coder Plus", provider: "qwen", badge: "CODING"),
            AIModelDefinition(id: "qwen-max", name: "Qwen Max", provider: "qwen", badge: "FLAGSHIP")
        ] : []
        return EcosystemEngineInfo(
            id: "qwen",
            name: "Alibaba Qwen Code",
            icon: "cpu.fill",
            binaryPath: path,
            isInstalled: isInstalled,
            isAuthenticated: isInstalled,
            activeModel: models.first?.id,
            models: models,
            details: isInstalled
                ? "Qwen Code CLI (`@qwen-code/qwen-code`) detected"
                : "Install via `npm install -g @qwen-code/qwen-code`"
        )
    }
    
    private func discoverAider() -> EcosystemEngineInfo {
        let path = resolveBinary("aider") ?? resolveBinaryFast("aider")
        let isInstalled = path != nil
        let models: [AIModelDefinition] = isInstalled ? [
            AIModelDefinition(id: "sonnet", name: "Aider Architect (Claude Sonnet)", provider: "aider", badge: "ARCHITECT"),
            AIModelDefinition(id: "deepseek", name: "Aider Architect (DeepSeek V3)", provider: "aider", badge: "FAST"),
            AIModelDefinition(id: "o3-mini", name: "Aider Architect (o3-mini)", provider: "aider", badge: "REASONING")
        ] : []
        return EcosystemEngineInfo(
            id: "aider",
            name: "Aider Architect",
            icon: "hammer.fill",
            binaryPath: path,
            isInstalled: isInstalled,
            isAuthenticated: isInstalled,
            activeModel: models.first?.id,
            models: models,
            details: isInstalled
                ? "Aider AI Pair Programmer (`aider`) ready"
                : "Install via `pipx install aider-chat` or `brew install aider`"
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
        loadedFromPersistedCache = true
        if let data = try? JSONEncoder().encode(discovered) {
            UserDefaults.standard.set(data, forKey: userDefaultsCacheKey)
        }
    }
    
    private func loadCachedEngines() {
        // 1. Load previously persisted live-discovered engines if available
        if let data = UserDefaults.standard.data(forKey: userDefaultsCacheKey),
           let cached = try? JSONDecoder().decode([EcosystemEngineInfo].self, from: data),
           !cached.isEmpty {
            loadedFromPersistedCache = true
            self.engines = cached.map { eng in
                if eng.id == "codex", let bp = eng.binaryPath, bp.contains(".plugin-appserver/codex-cli"),
                   let healed = resolveBinaryFast("codex") {
                    return EcosystemEngineInfo(
                        id: eng.id, name: eng.name, icon: eng.icon, binaryPath: healed,
                        isInstalled: eng.isInstalled, isAuthenticated: eng.isAuthenticated,
                        activeModel: eng.activeModel, models: eng.models, details: eng.details
                    )
                }
                if eng.id == "agy" {
                    let validModels = eng.models.filter {
                        let lower = $0.id.lowercased()
                        return !lower.contains("4-6") && !lower.hasSuffix("-thinking")
                    }
                    let finalModels = validModels.isEmpty && eng.isInstalled ? Self.defaultAGYModels : validModels
                    return EcosystemEngineInfo(
                        id: eng.id, name: eng.name, icon: eng.icon, binaryPath: eng.binaryPath,
                        isInstalled: eng.isInstalled, isAuthenticated: eng.isInstalled && !finalModels.isEmpty,
                        activeModel: finalModels.first?.id, models: finalModels, details: eng.details
                    )
                }
                if eng.id == "opencode" {
                    let validModels = eng.models.filter {
                        !ACPAgentSession.retiredOpenCodeModels.contains($0.id.lowercased())
                    }
                    return EcosystemEngineInfo(
                        id: eng.id, name: eng.name, icon: eng.icon, binaryPath: eng.binaryPath,
                        isInstalled: eng.isInstalled, isAuthenticated: eng.isAuthenticated,
                        activeModel: validModels.first?.id ?? ACPAgentSession.fallbackOpenCodeFreeModel,
                        models: validModels, details: eng.details
                    )
                }
                if eng.id == "gemini_cli" {
                    return discoverGeminiCLI()
                }
                if eng.id == "copilot" {
                    return discoverCopilot()
                }
                if eng.id == "zed" {
                    return discoverZed()
                }
                return eng
            }
            return
        }
        
        // 2. Otherwise synchronously read fast local disk caches (~/.codex/models_cache.json, ~/.claude/settings.json, ~/.config/zed/settings.json)
        let codex = discoverCodex()
        let zed = discoverZed()
        let agyBin = resolveBinaryFast("agy")
        let claudeBin = resolveBinaryFast("claude")
        let openCodeBin = resolveBinaryFast("opencode")
        let initialClaudeModels: [AIModelDefinition] = claudeBin != nil
            ? Self.defaultClaudeCodeModels.map { AIModelDefinition(id: $0.0, name: $0.1, provider: "claude_code", badge: $0.2) } + [
                AIModelDefinition(id: "opus", name: "Claude Opus (Latest Alias)", provider: "claude_code", badge: "OPUS"),
                AIModelDefinition(id: "sonnet", name: "Claude Sonnet (Latest Alias)", provider: "claude_code", badge: "SONNET"),
                AIModelDefinition(id: "haiku", name: "Claude Haiku (Latest Alias)", provider: "claude_code", badge: "HAIKU")
            ]
            : []
        let initialOpenCodeModels: [AIModelDefinition] = openCodeBin != nil
            ? [AIModelDefinition(id: ACPAgentSession.fallbackOpenCodeFreeModel, name: "MiMo V2.6 Flash (Free)", provider: "opencode", badge: "FREE")]
            : []
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
                id: "claude_code",
                name: "Anthropic Claude Code",
                icon: "command.square.fill",
                binaryPath: claudeBin,
                isInstalled: claudeBin != nil,
                isAuthenticated: claudeBin != nil,
                activeModel: initialClaudeModels.first?.id,
                models: initialClaudeModels,
                details: "Reading ~/.claude/settings.json..."
            ),
            codex,
            discoverGeminiCLI(),
            EcosystemEngineInfo(
                id: "opencode",
                name: "OpenCode",
                icon: "laptopcomputer",
                binaryPath: openCodeBin,
                isInstalled: openCodeBin != nil,
                isAuthenticated: false,
                activeModel: initialOpenCodeModels.first?.id,
                models: initialOpenCodeModels,
                details: "Fetching live models from `opencode models`..."
            ),
            discoverCursorAgent(),
            discoverCopilot(),
            discoverGoose(),
            discoverCline(),
            discoverQwenCode(),
            discoverAider(),
            zed
        ]
    }
}
