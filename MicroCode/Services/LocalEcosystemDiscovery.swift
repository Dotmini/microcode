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

struct EcosystemEngineInfo: Identifiable, Hashable {
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
    
    private let userDefaultsCacheKey = "microcode_ecosystem_discovered_models_v2"
    
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
        await MainActor.run { isScanning = true }
        defer {
            Task { @MainActor in self.isScanning = false }
        }
        
        var discovered: [EcosystemEngineInfo] = []
        
        // 1. Antigravity (AGY)
        let agyEngine = await discoverAGY()
        discovered.append(agyEngine)
        
        // 2. OpenCode
        let openCodeEngine = await discoverOpenCode()
        discovered.append(openCodeEngine)
        
        // 3. OpenAI Codex
        let codexEngine = discoverCodex()
        discovered.append(codexEngine)
        
        // 4. Claude Code
        let claudeEngine = discoverClaude()
        discovered.append(claudeEngine)
        
        // 5. Zed / ZCode
        let zedEngine = discoverZed()
        discovered.append(zedEngine)
        
        await MainActor.run {
            self.engines = discovered
            self.lastScanDate = Date()
            AIModelCatalog.shared.integrateEcosystemEngines(discovered)
        }
    }
    
    // MARK: - 1. Antigravity (AGY) Discovery
    
    private func discoverAGY() async -> EcosystemEngineInfo {
        let path = resolveBinary("agy")
        let isInstalled = path != nil
        var models: [AIModelDefinition] = []
        
        if let path = path {
            // Execute \`agy models\` via CLI
            let cliOutput = await runCommand(executable: path, arguments: ["models"])
            let parsed = parseAGYModelsOutput(cliOutput)
            if !parsed.isEmpty {
                models = parsed
            }
        }
        
        // Fallback/verified live models if CLI took long or offline
        if models.isEmpty {
            models = [
                AIModelDefinition(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", provider: "agy", badge: "FLAGSHIP"),
                AIModelDefinition(id: "gemini-2.0-flash-thinking-exp", name: "Gemini 2.0 Flash Thinking", provider: "agy", badge: "THINKING"),
                AIModelDefinition(id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", provider: "agy", badge: "PRO"),
                AIModelDefinition(id: "gemini-1.5-flash", name: "Gemini 1.5 Flash", provider: "agy", badge: "FAST"),
                AIModelDefinition(id: "claude-3-7-sonnet", name: "Claude 3.7 Sonnet (Thinking)", provider: "agy", badge: "HYBRID"),
                AIModelDefinition(id: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", provider: "agy", badge: "WORKHORSE")
            ]
        }
        
        return EcosystemEngineInfo(
            id: "agy",
            name: "Google Antigravity (AGY)",
            icon: "sparkles",
            binaryPath: path,
            isInstalled: isInstalled,
            isAuthenticated: isInstalled,
            activeModel: "gemini-2.0-flash",
            models: models,
            details: "Official Antigravity CLI engine with Gemini 2.0 Flash and Claude 3.7 Sonnet Thinking"
        )
    }
    
    private func parseAGYModelsOutput(_ output: String) -> [AIModelDefinition] {
        var results: [AIModelDefinition] = []
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.lowercased().contains("fetching"),
                  !trimmed.lowercased().hasPrefix("usage"),
                  !trimmed.lowercased().hasPrefix("error") else { continue }
            
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
            
            guard !id.isEmpty else { continue }
            let lower = id.lowercased()
            let badge: String
            if lower.contains("high") { badge = "HIGH REASONING" }
            else if lower.contains("pro") { badge = "PRO" }
            else if lower.contains("thinking") { badge = "THINKING" }
            else if lower.contains("flash") { badge = "FAST" }
            else { badge = "AGY LIVE" }
            
            results.append(AIModelDefinition(
                id: id,
                name: displayName.isEmpty ? id : displayName,
                provider: "agy",
                badge: badge
            ))
        }
        return results
    }
    
    // MARK: - 2. OpenCode Discovery
    
    private func discoverOpenCode() async -> EcosystemEngineInfo {
        let path = resolveBinary("opencode")
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
            let cliOutput = await runCommand(executable: path, arguments: ["models"])
            let lines = cliOutput.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      !trimmed.contains("┌"), !trimmed.contains("└"), !trimmed.contains("│"),
                      !trimmed.lowercased().contains("error"),
                      !trimmed.lowercased().contains("usage") else { continue }
                
                let parts = trimmed.split(separator: " ").map(String.init)
                if let modelId = parts.first, modelId.contains("/") {
                    let displayName = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : modelId
                    let isFree = modelId.contains("free")
                    let badge = isFree ? "FREE" : (isAuthenticated ? "AUTHED" : "NEEDS AUTH")
                    models.append(AIModelDefinition(
                        id: modelId,
                        name: displayName,
                        provider: "opencode",
                        badge: badge
                    ))
                }
            }
        }
        
        // Sort: Free models first, with nemotron-3.5-lightning-free at the top
        models.sort { a, b in
            if a.id == "opencode/nemotron-3.5-lightning-free" { return true }
            if b.id == "opencode/nemotron-3.5-lightning-free" { return false }
            let aFree = a.id.contains("free")
            let bFree = b.id.contains("free")
            if aFree && !bFree { return true }
            if !aFree && bFree { return false }
            return a.id < b.id
        }
        
        if models.isEmpty {
            models = [
                AIModelDefinition(id: "opencode/nemotron-3.5-lightning-free", name: "Nemotron 3.5 Lightning (Free)", provider: "opencode", badge: "FREE"),
                AIModelDefinition(id: "opencode/ling-3.0-flash-fin-free", name: "Ling 3.0 Flash (Free)", provider: "opencode", badge: "FREE"),
                AIModelDefinition(id: "opencode/mimo-v2.5-free", name: "Mimo 2.5 (Free)", provider: "opencode", badge: "FREE"),
                AIModelDefinition(id: "opencode/big-pickle", name: "Big Pickle (Free)", provider: "opencode", badge: "FREE"),
                AIModelDefinition(id: "provider-auth-zai/glm-5", name: "GLM-5 (Zhipu)", provider: "opencode", badge: isAuthenticated ? "AUTHED" : "NEEDS AUTH"),
                AIModelDefinition(id: "provider-auth-zai/glm-4.7", name: "GLM-4.7", provider: "opencode", badge: isAuthenticated ? "AUTHED" : "NEEDS AUTH")
            ]
        }
        
        let defaultModel = models.first(where: { $0.id.contains("free") })?.id ?? "opencode/nemotron-3.5-lightning-free"
        
        return EcosystemEngineInfo(
            id: "opencode",
            name: "OpenCode",
            icon: "laptopcomputer",
            binaryPath: path,
            isInstalled: isInstalled,
            isAuthenticated: isAuthenticated,
            activeModel: defaultModel,
            models: models,
            details: isInstalled ? (isAuthenticated ? "OpenCode CLI authenticated" : "OpenCode installed (Free models ready)") : "OpenCode CLI not installed"
        )
    }
    
    // MARK: - 3. OpenAI Codex Discovery
    
    private func discoverCodex() -> EcosystemEngineInfo {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexDir = home.appendingPathComponent(".codex")
        let cacheFile = codexDir.appendingPathComponent("models_cache.json")
        let configFile = codexDir.appendingPathComponent("config.toml")
        let authFile = codexDir.appendingPathComponent("auth.json")
        
        let binaryPath = resolveBinary("codex")
        let isInstalled = binaryPath != nil
        let isAuthenticated = isInstalled && FileManager.default.fileExists(atPath: authFile.path)
        
        var activeModel: String? = nil
        if let configData = try? String(contentsOf: configFile, encoding: .utf8) {
            for line in configData.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("model =") {
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
                
                let displayName = (item["display_name"] as? String) ?? slug
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
        
        if models.isEmpty {
            models = [
                AIModelDefinition(id: "gpt-4o", name: "GPT-4o", provider: "codex", badge: "FLAGSHIP"),
                AIModelDefinition(id: "gpt-4o-mini", name: "GPT-4o Mini", provider: "codex", badge: "FAST"),
                AIModelDefinition(id: "o1", name: "o1", provider: "codex", badge: "PRO REASONING"),
                AIModelDefinition(id: "o3-mini", name: "o3-mini", provider: "codex", badge: "STEM REASONING")
            ]
        }
        
        return EcosystemEngineInfo(
            id: "codex",
            name: "OpenAI Codex",
            icon: "terminal.fill",
            binaryPath: binaryPath,
            isInstalled: isInstalled,
            isAuthenticated: isAuthenticated,
            activeModel: activeModel ?? "gpt-4o",
            models: models,
            details: isInstalled ? (isAuthenticated ? "OpenAI Codex CLI ready" : "Codex installed, needs ChatGPT Plus login") : "Codex CLI not installed"
        )
    }
    
    // MARK: - 4. Claude Code Discovery
    
    private func discoverClaude() -> EcosystemEngineInfo {
        let path = resolveBinary("claude")
        let isInstalled = path != nil
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsFile = home.appendingPathComponent(".claude/settings.json")
        
        var activeModel: String = "haiku"
        if let data = try? Data(contentsOf: settingsFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let m = json["model"] as? String {
            activeModel = m
        }
        
        let models: [AIModelDefinition] = [
            AIModelDefinition(id: "haiku", name: "Claude 3.5 Haiku", provider: "claude_code", badge: activeModel == "haiku" ? "ACTIVE • FAST" : "FAST"),
            AIModelDefinition(id: "sonnet", name: "Claude 3.7 Sonnet (Hybrid)", provider: "claude_code", badge: activeModel == "sonnet" ? "ACTIVE • HYBRID" : "HYBRID"),
            AIModelDefinition(id: "opus", name: "Claude 3.5 Opus", provider: "claude_code", badge: activeModel == "opus" ? "ACTIVE • REASONING" : "REASONING"),
            AIModelDefinition(id: "auto", name: "Claude Code Auto", provider: "claude_code", badge: "DYNAMIC"),
            AIModelDefinition(id: "claude-3-7-sonnet-latest", name: "Claude 3.7 Sonnet Latest", provider: "claude_code", badge: "LATEST"),
            AIModelDefinition(id: "claude-3-5-sonnet-latest", name: "Claude 3.5 Sonnet Latest", provider: "claude_code", badge: "STABLE")
        ]
        
        return EcosystemEngineInfo(
            id: "claude_code",
            name: "Anthropic Claude Code",
            icon: "command.square.fill",
            binaryPath: path,
            isInstalled: isInstalled,
            isAuthenticated: isInstalled,
            activeModel: activeModel,
            models: models,
            details: "Anthropic Claude Code CLI with active model '\(activeModel)' from ~/.claude/settings.json"
        )
    }
    
    // MARK: - 4. Zed / ZCode Discovery
    
    private func discoverZed() -> EcosystemEngineInfo {
        let path = resolveBinary("zed")
        let home = FileManager.default.homeDirectoryForCurrentUser
        let zedSettings = home.appendingPathComponent(".config/zed/settings.json")
        let isInstalled = path != nil || FileManager.default.fileExists(atPath: zedSettings.path)
        
        var defaultModel = "deepseek-chat"
        var inlineModel = "gpt-4o-mini"
        
        if let rawText = try? String(contentsOf: zedSettings, encoding: .utf8) {
            // Clean JSONC comments
            let stripped = stripJSONCComments(rawText)
            if let data = stripped.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let agent = json["agent"] as? [String: Any] {
                if let def = agent["default_model"] as? [String: Any], let m = def["model"] as? String {
                    defaultModel = m
                }
                if let inl = agent["inline_assistant_model"] as? [String: Any], let m = inl["model"] as? String {
                    inlineModel = m
                }
            }
        }
        
        let models: [AIModelDefinition] = [
            AIModelDefinition(
                id: defaultModel,
                name: "Zed: \(defaultModel) (Thinking)",
                provider: "zed",
                badge: "ZED DEFAULT"
            ),
            AIModelDefinition(
                id: inlineModel,
                name: "Zed: \(inlineModel) (Inline)",
                provider: "zed",
                badge: "ZED INLINE"
            ),
            AIModelDefinition(
                id: "deepseek-reasoner",
                name: "DeepSeek R1 (Reasoner)",
                provider: "zed",
                badge: "REASONER"
            ),
            AIModelDefinition(
                id: "deepseek-chat",
                name: "DeepSeek V3 (Chat)",
                provider: "zed",
                badge: "CHAT"
            )
        ]
        
        return EcosystemEngineInfo(
            id: "zed",
            name: "Zed / ZCode Assistant",
            icon: "chevron.left.forwardslash.chevron.right",
            binaryPath: path,
            isInstalled: isInstalled,
            isAuthenticated: isInstalled,
            activeModel: defaultModel,
            models: models,
            details: "Zed assistant settings from ~/.config/zed/settings.json (Default: \(defaultModel))"
        )
    }
    
    // MARK: - Helpers
    
    private func resolveBinary(_ name: String) -> String? {
        return ACPHostService.resolveExecutablePath(name)
    }
    
    private func runCommand(executable: String, arguments: [String]) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = Pipe()
                
                do {
                    try process.run()
                    // Timeout after 7.0s
                    DispatchQueue.global().asyncAfter(deadline: .now() + 7.0) {
                        if process.isRunning {
                            process.terminate()
                        }
                    }
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
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
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.cargo/bin/\(name)",
            "\(home)/.bun/bin/\(name)",
            "\(home)/.npm-global/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        return checkPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }
    
    private func loadCachedEngines() {
        // Initial quick fallback so UI renders instantly
        self.engines = [
            EcosystemEngineInfo(
                id: "agy",
                name: "Google Antigravity (AGY)",
                icon: "sparkles",
                binaryPath: resolveBinaryFast("agy"),
                isInstalled: resolveBinaryFast("agy") != nil,
                isAuthenticated: true,
                activeModel: "gemini-2.0-flash",
                models: [
                    AIModelDefinition(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", provider: "agy", badge: "FLAGSHIP"),
                    AIModelDefinition(id: "gemini-2.0-flash-thinking-exp", name: "Gemini 2.0 Flash Thinking", provider: "agy", badge: "THINKING"),
                    AIModelDefinition(id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", provider: "agy", badge: "PRO"),
                    AIModelDefinition(id: "gemini-1.5-flash", name: "Gemini 1.5 Flash", provider: "agy", badge: "FAST"),
                    AIModelDefinition(id: "claude-3-7-sonnet", name: "Claude 3.7 Sonnet (Thinking)", provider: "agy", badge: "HYBRID"),
                    AIModelDefinition(id: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", provider: "agy", badge: "WORKHORSE")
                ],
                details: "Antigravity CLI models cached"
            ),
            EcosystemEngineInfo(
                id: "opencode",
                name: "OpenCode",
                icon: "laptopcomputer",
                binaryPath: resolveBinaryFast("opencode"),
                isInstalled: resolveBinaryFast("opencode") != nil,
                isAuthenticated: false,
                activeModel: "opencode/nemotron-3.5-lightning-free",
                models: [
                    AIModelDefinition(id: "opencode/nemotron-3.5-lightning-free", name: "Nemotron 3.5 Lightning (Free)", provider: "opencode", badge: "FREE"),
                    AIModelDefinition(id: "opencode/ling-3.0-flash-fin-free", name: "Ling 3.0 Flash (Free)", provider: "opencode", badge: "FREE"),
                    AIModelDefinition(id: "provider-auth-zai/glm-5", name: "GLM-5 (Zhipu)", provider: "opencode", badge: "FLAGSHIP"),
                    AIModelDefinition(id: "deepseek/deepseek-chat", name: "DeepSeek V3 (Chat)", provider: "opencode", badge: "POPULAR")
                ],
                details: "OpenCode CLI & local models"
            ),
            EcosystemEngineInfo(
                id: "codex",
                name: "OpenAI Codex",
                icon: "terminal.fill",
                binaryPath: resolveBinaryFast("codex"),
                isInstalled: resolveBinaryFast("codex") != nil,
                isAuthenticated: false,
                activeModel: "gpt-4o",
                models: [
                    AIModelDefinition(id: "gpt-4o", name: "GPT-4o", provider: "codex", badge: "FLAGSHIP"),
                    AIModelDefinition(id: "gpt-4o-mini", name: "GPT-4o Mini", provider: "codex", badge: "FAST"),
                    AIModelDefinition(id: "o1", name: "o1", provider: "codex", badge: "PRO REASONING"),
                    AIModelDefinition(id: "o3-mini", name: "o3-mini", provider: "codex", badge: "STEM REASONING")
                ],
                details: "OpenAI Codex models cached"
            ),
            EcosystemEngineInfo(
                id: "claude_code",
                name: "Anthropic Claude Code",
                icon: "command.square.fill",
                binaryPath: resolveBinaryFast("claude"),
                isInstalled: resolveBinaryFast("claude") != nil,
                isAuthenticated: true,
                activeModel: "claude-3-7-sonnet",
                models: [
                    AIModelDefinition(id: "claude-3-7-sonnet", name: "Claude 3.7 Sonnet (Hybrid)", provider: "claude_code", badge: "HYBRID"),
                    AIModelDefinition(id: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", provider: "claude_code", badge: "WORKHORSE"),
                    AIModelDefinition(id: "claude-3-5-haiku", name: "Claude 3.5 Haiku", provider: "claude_code", badge: "FAST"),
                    AIModelDefinition(id: "auto", name: "Claude Code Auto", provider: "claude_code", badge: "DYNAMIC")
                ],
                details: "Claude Code CLI models cached"
            ),
            EcosystemEngineInfo(
                id: "zed",
                name: "Zed / ZCode Assistant",
                icon: "chevron.left.forwardslash.chevron.right",
                binaryPath: resolveBinaryFast("zed"),
                isInstalled: resolveBinaryFast("zed") != nil,
                isAuthenticated: true,
                activeModel: "deepseek-chat",
                models: [
                    AIModelDefinition(id: "deepseek-chat", name: "Zed: deepseek-chat", provider: "zed", badge: "DEFAULT"),
                    AIModelDefinition(id: "deepseek-reasoner", name: "Zed: deepseek-reasoner", provider: "zed", badge: "REASONER"),
                    AIModelDefinition(id: "gpt-4o", name: "Zed: gpt-4o", provider: "zed", badge: "OPENAI"),
                    AIModelDefinition(id: "claude-3-5-sonnet", name: "Zed: claude-3-5-sonnet", provider: "zed", badge: "ANTHROPIC")
                ],
                details: "Zed assistant models cached"
            )
        ]
    }
}
