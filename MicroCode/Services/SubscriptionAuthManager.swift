//
//  SubscriptionAuthManager.swift
//  MicroCode
//
//  Created and Designed by Dotmini Software
//  Founder & CEO: Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//
//  Description:
//  Manages web subscription connections (ChatGPT Plus/Team/Pro, Claude Pro, Gemini Advanced, DeepSeek, Copilot, Zhipu GLM)
//  without requiring per-token pay-as-you-go API keys.
//

import Foundation
import Combine
import AppKit
import Security

public struct SubscriptionModelInfo: Identifiable, Hashable, Codable {
    public var id: String { "\(provider.rawValue):\(modelID)" }
    public let modelID: String
    public let name: String
    public let provider: SubscriptionProviderType
    public let badge: String
    public let description: String
    public let aiProviderID: String // "openai", "anthropic", "gemini", "deepseek", "glm"
    
    public init(modelID: String, name: String, provider: SubscriptionProviderType, badge: String, description: String, aiProviderID: String) {
        self.modelID = modelID
        self.name = name
        self.provider = provider
        self.badge = badge
        self.description = description
        self.aiProviderID = aiProviderID
    }
}

public enum SubscriptionProviderType: String, CaseIterable, Identifiable, Codable {
    case chatgpt = "chatgpt"
    case claude = "claude"
    case gemini = "gemini"
    case deepseek = "deepseek"
    case copilot = "copilot"
    case glm = "glm"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .chatgpt: return "ChatGPT Plus / Team / Pro"
        case .claude: return "Claude Pro / Team"
        case .gemini: return "Gemini Advanced (Google One)"
        case .deepseek: return "DeepSeek Web (Unlimited)"
        case .copilot: return "GitHub Copilot (CLI / Web)"
        case .glm: return "Zhipu GLM (BigModel)"
        }
    }
    
    public var providerIcon: String {
        switch self {
        case .chatgpt: return "openai"
        case .claude: return "anthropic"
        case .gemini: return "gemini"
        case .deepseek: return "deepseek"
        case .copilot: return "github"
        case .glm: return "glm"
        }
    }
    
    public var defaultModel: String {
        switch self {
        case .chatgpt: return "gpt-4o"
        case .claude: return "claude-3-7-sonnet-20250219"
        case .gemini: return "gemini-2.0-flash"
        case .deepseek: return "deepseek-chat"
        case .copilot: return "auto"
        case .glm: return "glm-4-plus"
        }
    }
    
    public var shortLabel: String {
        switch self {
        case .chatgpt: return "ChatGPT Plus"
        case .claude: return "Claude Pro"
        case .gemini: return "Gemini Adv"
        case .deepseek: return "DeepSeek Web"
        case .copilot: return "Copilot"
        case .glm: return "GLM Member"
        }
    }
    
    // MARK: - Live Model Store
    private static var liveModelInfos: [SubscriptionProviderType: [SubscriptionModelInfo]] = [:]

    public static func setLiveModels(for provider: SubscriptionProviderType, models: [SubscriptionModelInfo]) {
        liveModelInfos[provider] = models
    }

    public static func registerCustomSubscriptionModel(provider: SubscriptionProviderType, modelId: String) {
        let cleanId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return }
        
        let customKey = "microcode_sub_custom_models_\(provider.rawValue)"
        var saved = UserDefaults.standard.stringArray(forKey: customKey) ?? []
        if !saved.contains(cleanId) {
            saved.append(cleanId)
            UserDefaults.standard.set(saved, forKey: customKey)
        }
        
        let newInfo = SubscriptionModelInfo(
            modelID: cleanId,
            name: AIModelCatalog.formatModelName(cleanId),
            provider: provider,
            badge: "CUSTOM",
            description: "User registered custom model for \(provider.displayName)",
            aiProviderID: provider.aiProviderID
        )
        
        var current = liveModelInfos[provider] ?? provider.defaultModelInfos
        if !current.contains(where: { $0.modelID == cleanId }) {
            current.insert(newInfo, at: 0)
            liveModelInfos[provider] = current
        }
    }

    public var aiProviderID: String {
        switch self {
        case .chatgpt: return "openai"
        case .claude: return "anthropic"
        case .gemini: return "gemini"
        case .deepseek: return "deepseek"
        case .copilot: return "copilot"
        case .glm: return "glm"
        }
    }

    public var modelInfos: [SubscriptionModelInfo] {
        if let live = Self.liveModelInfos[self], !live.isEmpty {
            return live
        }
        let customKey = "microcode_sub_custom_models_\(rawValue)"
        let customs = UserDefaults.standard.stringArray(forKey: customKey) ?? []
        var res = defaultModelInfos
        for cid in customs.reversed() {
            if !res.contains(where: { $0.modelID == cid }) {
                res.insert(SubscriptionModelInfo(
                    modelID: cid,
                    name: AIModelCatalog.formatModelName(cid),
                    provider: self,
                    badge: "CUSTOM",
                    description: "Custom model",
                    aiProviderID: self.aiProviderID
                ), at: 0)
            }
        }
        return res
    }

    public var defaultModelInfos: [SubscriptionModelInfo] {
        switch self {
        case .chatgpt:
            return [
                SubscriptionModelInfo(modelID: "gpt-4o", name: "GPT-4o", provider: .chatgpt, badge: "FLAGSHIP", description: "OpenAI flagship multimodal reasoning & code generation", aiProviderID: "openai"),
                SubscriptionModelInfo(modelID: "gpt-4o-mini", name: "GPT-4o Mini", provider: .chatgpt, badge: "FAST", description: "Affordable and fast multimodal intelligence", aiProviderID: "openai"),
                SubscriptionModelInfo(modelID: "o1", name: "o1", provider: .chatgpt, badge: "REASONING", description: "Deep architectural reasoning and STEM intelligence", aiProviderID: "openai"),
                SubscriptionModelInfo(modelID: "o3-mini", name: "o3-mini", provider: .chatgpt, badge: "FAST REASONING", description: "High-speed logic, STEM, and code reasoning", aiProviderID: "openai")
            ]
        case .claude:
            return [
                SubscriptionModelInfo(modelID: "claude-3-7-sonnet-20250219", name: "Claude 3.7 Sonnet", provider: .claude, badge: "HYBRID", description: "Hybrid thinking and coding frontier via Claude Pro", aiProviderID: "anthropic"),
                SubscriptionModelInfo(modelID: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", provider: .claude, badge: "FLAGSHIP", description: "Industry standard agentic coding & tool use", aiProviderID: "anthropic"),
                SubscriptionModelInfo(modelID: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", provider: .claude, badge: "FAST", description: "High-speed coding and lightweight processing", aiProviderID: "anthropic")
            ]
        case .gemini:
            return [
                SubscriptionModelInfo(modelID: "gemini-2.0-flash", name: "Gemini 2.0 Flash", provider: .gemini, badge: "FLAGSHIP", description: "Next-gen multimodal speed, coding, and real-time awareness", aiProviderID: "gemini"),
                SubscriptionModelInfo(modelID: "gemini-1.5-pro", name: "Gemini 1.5 Pro", provider: .gemini, badge: "LONG CONTEXT", description: "2M token context window for complex codebase analysis", aiProviderID: "gemini"),
                SubscriptionModelInfo(modelID: "gemini-1.5-flash", name: "Gemini 1.5 Flash", provider: .gemini, badge: "FAST", description: "Fast, versatile multimodal performance", aiProviderID: "gemini")
            ]
        case .deepseek:
            return [
                SubscriptionModelInfo(modelID: "deepseek-chat", name: "DeepSeek V3 (Chat)", provider: .deepseek, badge: "CHAT", description: "Flagship general coding and chat intelligence", aiProviderID: "deepseek"),
                SubscriptionModelInfo(modelID: "deepseek-reasoner", name: "DeepSeek R1 (Reasoner)", provider: .deepseek, badge: "REASONER", description: "Open reasoning model with chain-of-thought", aiProviderID: "deepseek")
            ]
        case .copilot:
            return [
                SubscriptionModelInfo(modelID: "auto", name: "Copilot Auto", provider: .copilot, badge: "AUTO", description: "GitHub Copilot dynamic model routing", aiProviderID: "copilot"),
                SubscriptionModelInfo(modelID: "claude-3-7-sonnet", name: "Claude 3.7 Sonnet", provider: .copilot, badge: "HYBRID", description: "Anthropic Claude 3.7 via Copilot", aiProviderID: "copilot"),
                SubscriptionModelInfo(modelID: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", provider: .copilot, badge: "FLAGSHIP", description: "Anthropic Claude 3.5 via Copilot", aiProviderID: "copilot"),
                SubscriptionModelInfo(modelID: "gpt-4o", name: "GPT-4o", provider: .copilot, badge: "FLAGSHIP", description: "OpenAI GPT-4o via Copilot", aiProviderID: "copilot"),
                SubscriptionModelInfo(modelID: "o3-mini", name: "o3-mini", provider: .copilot, badge: "REASONING", description: "OpenAI o3-mini via Copilot", aiProviderID: "copilot")
            ]
        case .glm:
            return [
                SubscriptionModelInfo(modelID: "glm-4-plus", name: "GLM-4 Plus", provider: .glm, badge: "MEMBER", description: "Zhipu BigModel flagship membership", aiProviderID: "glm"),
                SubscriptionModelInfo(modelID: "glm-4-flash", name: "GLM-4 Flash", provider: .glm, badge: "FREE", description: "High-speed zero-latency response", aiProviderID: "glm")
            ]
        }
    }

    public var availableModels: [String] {
        return modelInfos.map(\.modelID)
    }
    
    public var webLoginURL: URL {
        switch self {
        case .chatgpt: return URL(string: "https://chatgpt.com")!
        case .claude: return URL(string: "https://claude.ai/login")!
        case .gemini: return URL(string: "https://gemini.google.com")!
        case .deepseek: return URL(string: "https://chat.deepseek.com")!
        case .copilot: return URL(string: "https://github.com/login/device")!
        case .glm: return URL(string: "https://bigmodel.cn/login")!
        }
    }
    
    public var tokenHelpTitle: String {
        switch self {
        case .chatgpt: return "How to get ChatGPT Token"
        case .claude: return "How to get Claude Token"
        case .gemini: return "How to get Gemini Cookie"
        case .deepseek: return "How to get DeepSeek Token"
        case .copilot: return "How to get Copilot Token"
        case .glm: return "How to get GLM Token"
        }
    }
    
    public var tokenGuideSteps: [String] {
        switch self {
        case .chatgpt:
            return [
                "1. Click 'Open Web Portal' to sign in to chatgpt.com",
                "2. Press ⌥⌘I (DevTools) → Application → Cookies (chatgpt.com)",
                "3. Copy value of '__Secure-next-auth.session-token' or run `codex login` in Terminal and click 'Auto-detect CLI Auth'."
            ]
        case .claude:
            return [
                "1. Log in to claude.ai in browser or install Claude Code (`npm i -g @anthropic-ai/claude-code`)",
                "2. If using Claude Code, run `claude login` in Terminal then click 'Auto-detect CLI Auth'.",
                "3. Or in browser DevTools → Application → Cookies → copy 'sessionKey'."
            ]
        case .gemini:
            return [
                "1. Go to gemini.google.com with active Google One AI Premium subscription.",
                "2. Open DevTools (⌥⌘I) → Application → Cookies (gemini.google.com).",
                "3. Copy '__Secure-1PSID' cookie value and paste below."
            ]
        case .deepseek:
            return [
                "1. Go to chat.deepseek.com and sign in with your phone or email.",
                "2. Open DevTools (⌥⌘I) → Application → Local Storage (chat.deepseek.com).",
                "3. Copy 'userToken' value and paste below."
            ]
        case .copilot:
            return [
                "1. Open Terminal and run `gh auth login` with GitHub Copilot access.",
                "2. Click 'Auto-detect CLI Auth' above to import automatically.",
                "3. Or paste your personal access token (PAT) with copilot scopes."
            ]
        case .glm:
            return [
                "1. Go to bigmodel.cn/usercenter/proj-mgmt/apikeys",
                "2. Sign in with your subscription account.",
                "3. Copy your User/Authorization Token and paste below."
            ]
        }
    }
    
    public var consoleExtractionSnippet: String {
        switch self {
        case .chatgpt:
            return "(() => { const c = document.cookie.split('; '); const d = c.find(r => r.startsWith('__Secure-next-auth.session-token='))?.split('=')[1]; if (d) return d; const chunks = c.filter(r => r.trim().startsWith('__Secure-next-auth.session-token.')).sort().map(r => r.split('=')[1]).join(''); return chunks || localStorage.getItem('accessToken') || ''; })()"
        case .claude:
            return "document.cookie.split('; ').find(r => r.startsWith('sessionKey='))?.split('=')[1] || ''"
        case .gemini:
            return "document.cookie.split('; ').find(r => r.startsWith('__Secure-1PSID='))?.split('=')[1] || ''"
        case .deepseek:
            return "JSON.parse(localStorage.getItem('userToken') || '{}')?.value || localStorage.getItem('userToken') || ''"
        case .copilot:
            return "gh auth token"
        case .glm:
            return "localStorage.getItem('token') || ''"
        }
    }
    
    public var helpInstruction: String {
        switch self {
        case .chatgpt:
            return "Uses your ChatGPT Plus/Pro session or Codex CLI token. Zero API per-token charges."
        case .claude:
            return "Uses Claude Code CLI auth (~/.claude) or session token from claude.ai."
        case .gemini:
            return "Uses Gemini Advanced (Google One AI Premium) session cookie."
        case .deepseek:
            return "Uses DeepSeek Web chat session (DeepSeek V3 & R1 reasoning free/unlimited)."
        case .copilot:
            return "Uses GitHub Copilot CLI session (~/.config/gh) or token."
        case .glm:
            return "Uses Zhipu BigModel GLM-4 Plus membership token."
        }
    }
}

public struct SubscriptionAccount: Identifiable, Codable {
    public var id: String
    public var provider: SubscriptionProviderType
    public var emailOrUser: String
    public var sessionToken: String
    public var isValid: Bool
    public var source: String
    public var expiresAt: Date?
    public var lastVerified: Date
    
    public init(id: String = UUID().uuidString,
                provider: SubscriptionProviderType,
                emailOrUser: String,
                sessionToken: String,
                isValid: Bool = true,
                source: String = "Manual",
                expiresAt: Date? = nil,
                lastVerified: Date = Date()) {
        self.id = id
        self.provider = provider
        self.emailOrUser = emailOrUser
        self.sessionToken = sessionToken
        self.isValid = isValid
        self.source = source
        self.expiresAt = expiresAt
        self.lastVerified = lastVerified
    }
}

public class SubscriptionAuthManager: ObservableObject {
    public static let shared = SubscriptionAuthManager()
    
    @Published public var activeProvider: SubscriptionProviderType = .chatgpt
    @Published public var accounts: [SubscriptionProviderType: SubscriptionAccount] = [:]
    @Published public var isVerifying: Bool = false
    @Published public var detectedSessionCount: Int = 0
    @Published public var lastDetectionMessage: String = ""
    
    private let userDefaultsKey = "microcode_subscription_accounts_v1"
    
    private init() {
        loadSavedAccounts()
    }
    
    public func isConnected(_ provider: SubscriptionProviderType) -> Bool {
        guard let acc = accounts[provider] else { return false }
        return acc.isValid && !acc.sessionToken.isEmpty && (acc.expiresAt.map { $0 > Date() } ?? true)
    }
    
    public var hasAnyConnected: Bool {
        return SubscriptionProviderType.allCases.contains { isConnected($0) }
    }
    
    public func connectedProviders() -> [SubscriptionProviderType] {
        return SubscriptionProviderType.allCases.filter { isConnected($0) }
    }
    
    public func connectedModelInfos() -> [SubscriptionModelInfo] {
        return connectedProviders().flatMap { $0.modelInfos }
    }
    
    public func allModelInfos() -> [SubscriptionModelInfo] {
        return SubscriptionProviderType.allCases.flatMap { $0.modelInfos }
    }
    
    public func findModel(id: String, provider: SubscriptionProviderType? = nil) -> SubscriptionModelInfo? {
        if let provider = provider {
            return provider.modelInfos.first(where: { $0.modelID == id })
        }
        if let active = connectedModelInfos().first(where: { $0.modelID == id && $0.provider == activeProvider }) {
            return active
        }
        return connectedModelInfos().first(where: { $0.modelID == id }) ?? allModelInfos().first(where: { $0.modelID == id })
    }
    
    public func getAccount(_ provider: SubscriptionProviderType) -> SubscriptionAccount? {
        return accounts[provider]
    }
    
    public func token(for provider: SubscriptionProviderType) -> String? {
        return accounts[provider]?.sessionToken
    }
    
    public static func setLiveModels(for provider: SubscriptionProviderType, models: [SubscriptionModelInfo]) {
        SubscriptionProviderType.setLiveModels(for: provider, models: models)
    }

    public static func registerCustomSubscriptionModel(provider: SubscriptionProviderType, modelId: String) {
        SubscriptionProviderType.registerCustomSubscriptionModel(provider: provider, modelId: modelId)
    }

    // MARK: - Live Model Fetching & Sync
    @MainActor
    public func fetchLiveModels(for provider: SubscriptionProviderType) async {
        if provider == .copilot {
            await AIModelCatalog.shared.fetchLiveCopilotModels()
        } else {
            await AIModelCatalog.shared.fetchLiveModelsForProvider(provider.aiProviderID)
            syncLiveModelsFromCatalog(for: provider)
        }
    }

    @MainActor
    public func syncLiveModelsFromCatalog(for provider: SubscriptionProviderType) {
        let catalogProviderId = provider.aiProviderID
        if let catalogProv = AIModelCatalog.shared.provider(catalogProviderId) {
            var subModels: [SubscriptionModelInfo] = []
            for m in catalogProv.models {
                subModels.append(SubscriptionModelInfo(
                    modelID: m.id,
                    name: m.name,
                    provider: provider,
                    badge: m.badge,
                    description: "\(provider.displayName) live model: \(m.id)",
                    aiProviderID: provider.aiProviderID
                ))
            }
            if !subModels.isEmpty {
                Self.setLiveModels(for: provider, models: subModels)
            }
        }
    }
    
    public func saveAccount(provider: SubscriptionProviderType, emailOrUser: String, sessionToken: String, source: String = "Manual") {
        let trimmedToken = sessionToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return }
        
        // Strict separation: API keys belong to BYOK Direct API, never Web Subscription
        if trimmedToken.hasPrefix("sk-ant-") {
            UserDefaults.standard.set(trimmedToken, forKey: "anthropic_api_key")
            return
        } else if trimmedToken.hasPrefix("AIzaSy") {
            UserDefaults.standard.set(trimmedToken, forKey: "gemini_api_key")
            return
        }
        
        let account = SubscriptionAccount(
            provider: provider,
            emailOrUser: emailOrUser.isEmpty ? "Active Subscriber" : emailOrUser,
            sessionToken: trimmedToken,
            isValid: true,
            source: source,
            lastVerified: Date()
        )
        guard saveTokenToKeychain(provider: provider.rawValue, token: trimmedToken) else {
            lastDetectionMessage = "Could not save the credential to Keychain. Please reconnect."
            return
        }
        accounts[provider] = account
        persistAccounts()
    }
    
    public func disconnect(provider: SubscriptionProviderType) {
        if provider == .copilot {
            copilotLock.lock()
            cachedCopilotSessionToken = nil
            cachedCopilotSourceToken = nil
            copilotTokenExpiresAt = nil
            copilotLock.unlock()
        }
        accounts.removeValue(forKey: provider)
        deleteTokenFromKeychain(provider: provider.rawValue)
        persistAccounts()
    }
    
    /// Scans local CLI tools and verifies authentication with provider before registering
    public func detectLocalCLISessions() async {
        var detected = 0
        let home = FileManager.default.homeDirectoryForCurrentUser
        
        // 1. Check for Codex / OpenAI CLI auth (~/.codex/auth.json)
        let codexAuth = home.appendingPathComponent(".codex/auth.json")
        if FileManager.default.fileExists(atPath: codexAuth.path) {
            if let data = try? Data(contentsOf: codexAuth),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var email = "Codex Subscriber"
                var token = ""
                
                if let tokens = json["tokens"] as? [String: Any] {
                    if let access = tokens["access_token"] as? String, !access.isEmpty {
                        token = access
                    }
                }
                if token.isEmpty, let directToken = (json["access_token"] ?? json["token"]) as? String {
                    token = directToken
                }
                
                // Read email from id_token if available
                if let tokens = json["tokens"] as? [String: Any],
                   let idToken = tokens["id_token"] as? String {
                    let parts = idToken.components(separatedBy: ".")
                    if parts.count > 1, let payloadData = Data(base64Encoded: base64Padded(parts[1])),
                       let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                       let mail = payload["email"] as? String {
                        email = mail
                    }
                }
                
                // Verify token before saving
                if !token.isEmpty {
                    // If it looks like a real API key, verify it
                    if token.hasPrefix("sk-") {
                        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
                        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        req.timeoutInterval = 5
                        if let (_, resp) = try? await URLSession.shared.data(for: req),
                           let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                            DispatchQueue.main.async {
                                self.saveAccount(provider: .chatgpt, emailOrUser: email, sessionToken: token, source: "Codex CLI")
                            }
                            detected += 1
                        }
                    } else {
                        // OAuth token from CLI - trust the file existence as proof of auth
                        DispatchQueue.main.async {
                            self.saveAccount(provider: .chatgpt, emailOrUser: email.isEmpty ? "Codex CLI User" : email, sessionToken: token, source: "Codex CLI")
                        }
                        detected += 1
                    }
                }
            }
        }
        
        // 2. Check for Claude CLI session (~/.claude.json, ~/.claude/config.json, or environment)
        let claudeHomeJson = home.appendingPathComponent(".claude.json")
        let claudeConfig = home.appendingPathComponent(".claude/config.json")
        var claudeToken: String?
        if FileManager.default.fileExists(atPath: claudeHomeJson.path),
           let data = try? Data(contentsOf: claudeHomeJson),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = (json["sessionKey"] ?? json["oauthToken"] ?? json["apiKey"]) as? String,
           !token.isEmpty {
            claudeToken = token
        }
        if claudeToken == nil, FileManager.default.fileExists(atPath: claudeConfig.path) {
            if let data = try? Data(contentsOf: claudeConfig),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = (json["sessionKey"] ?? json["oauthToken"] ?? json["apiKey"]) as? String,
               !token.isEmpty {
                claudeToken = token
            }
        }
        if claudeToken == nil {
            claudeToken = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ProcessInfo.processInfo.environment["CLAUDE_API_KEY"]
        }
        
        if let token = claudeToken, !token.isEmpty {
            if token.hasPrefix("sk-ant-") {
                // Real API key - verify and save as direct key
                var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
                req.setValue(token, forHTTPHeaderField: "x-api-key")
                req.setValue("2024-10-22", forHTTPHeaderField: "anthropic-version")
                req.timeoutInterval = 5
                if let (_, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    UserDefaults.standard.set(token, forKey: "anthropic_api_key")
                    DispatchQueue.main.async {
                        self.saveAccount(provider: .claude, emailOrUser: "Claude API", sessionToken: token, source: "Claude CLI")
                    }
                    detected += 1
                }
            } else {
                // Session/OAuth token from Claude CLI - trust file existence
                DispatchQueue.main.async {
                    self.saveAccount(provider: .claude, emailOrUser: "Claude CLI User", sessionToken: token, source: "Claude CLI")
                }
                detected += 1
            }
        }
        
        // 3. Check for GitHub Copilot CLI session (~/.config/gh/hosts.yml or environment)
        let ghHosts = home.appendingPathComponent(".config/gh/hosts.yml")
        var ghToken: String?
        if FileManager.default.fileExists(atPath: ghHosts.path),
           let content = try? String(contentsOf: ghHosts, encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.starts(with: "oauth_token:") {
                    let parts = trimmed.split(separator: ":", maxSplits: 1)
                    if parts.count > 1 {
                        let tok = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        if !tok.isEmpty {
                            ghToken = tok
                            break
                        }
                    }
                }
            }
        }
        if ghToken == nil {
            ghToken = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? ProcessInfo.processInfo.environment["GH_TOKEN"] ?? ProcessInfo.processInfo.environment["COPILOT_TOKEN"]
        }
        
        if let token = ghToken, !token.isEmpty {
            // Verify if account has active Copilot access
            var req = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/v2/token")!)
            req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("vscode/1.95.0", forHTTPHeaderField: "Editor-Version")
            req.setValue("GitHubCopilot/1.155.0", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 5
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                DispatchQueue.main.async {
                    self.saveAccount(provider: .copilot, emailOrUser: "GitHub Copilot Active", sessionToken: token, source: "Manual")
                }
                detected += 1
            }
        }
        
        // Also check GEMINI_API_KEY env var
        if let geminiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !geminiKey.isEmpty {
            DispatchQueue.main.async {
                self.saveAccount(provider: .gemini, emailOrUser: "Gemini API", sessionToken: geminiKey, source: "Environment")
            }
            detected += 1
        }
        
        // 5. Check for DeepSeek
        if let dsKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !dsKey.isEmpty {
            DispatchQueue.main.async {
                self.saveAccount(provider: .deepseek, emailOrUser: "DeepSeek API", sessionToken: dsKey, source: "Environment")
            }
            detected += 1
        }
        
        let finalDetected = detected
        DispatchQueue.main.async {
            self.detectedSessionCount = finalDetected
            if finalDetected > 0 {
                self.lastDetectionMessage = "Detected \(finalDetected) active subscription session(s)."
            } else {
                self.lastDetectionMessage = "No verified subscriptions found. Please connect in settings or use Direct API Key."
            }
        }
    }
    
    private func fetchFromKeychainAsync(service: String) async -> String? {
        // Disabled: Spawning /usr/bin/security without user interaction triggers repeated
        // macOS system password dialogs ("MicroCode wants to access key in your keychain").
        return nil
    }
    
    private func fetchInternetPasswordFromKeychainAsync(server: String) async -> String? {
        // Disabled: Spawning /usr/bin/security without user interaction triggers repeated
        // macOS system password dialogs ("MicroCode wants to access key in your keychain").
        return nil
    }
    
    @discardableResult
    private func saveTokenToKeychain(provider: String, token: String) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.dotmini.microcode.subscription",
            kSecAttrAccount as String: provider
        ]
        let value = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func loadTokenFromKeychain(provider: String) -> String? {
        let service = "com.dotmini.microcode.subscription"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteTokenFromKeychain(provider: String) {
        let service = "com.dotmini.microcode.subscription"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    private func base64Padded(_ str: String) -> String {
        var base64 = str.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        return base64
    }
    
    // MARK: - Copilot Token Exchange
    private var cachedCopilotSessionToken: String?
    private var cachedCopilotSourceToken: String?
    private var copilotTokenExpiresAt: Date?
    private let copilotLock = NSLock()
    
    public func getCopilotSessionToken(githubToken: String) async throws -> String {
        copilotLock.lock()
        if cachedCopilotSourceToken == githubToken, let cached = cachedCopilotSessionToken,
           let expires = copilotTokenExpiresAt,
           expires > Date().addingTimeInterval(120) {
            copilotLock.unlock()
            return cached
        }
        copilotLock.unlock()
        
        let cleanToken = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else {
            throw NSError(domain: "Copilot", code: 401, userInfo: [NSLocalizedDescriptionKey: "GitHub token is empty. Connect your GitHub Copilot subscription in Settings."])
        }
        
        // If the token is already a Copilot session token, return directly
        if cleanToken.contains(";") || cleanToken.contains("tid=") || cleanToken.contains("exp=") {
            return cleanToken.replacingOccurrences(of: "Bearer ", with: "")
        }
        
        var req = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/v2/token")!)
        let authPrefix = cleanToken.hasPrefix("gh") ? "token " : "Bearer "
        req.setValue("\(authPrefix)\(cleanToken)", forHTTPHeaderField: "Authorization")
        req.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        req.setValue("copilot-chat/0.24.0", forHTTPHeaderField: "Editor-Plugin-Version")
        req.setValue("GitHubCopilot/1.250.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Copilot", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response from GitHub Copilot auth."])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "Copilot", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub Copilot token exchange failed (HTTP \(http.statusCode)). Please verify that your GitHub account has an active Copilot subscription (Copilot Pro/Business/Enterprise)."])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionToken = json["token"] as? String, !sessionToken.isEmpty else {
            throw NSError(domain: "Copilot", code: 502, userInfo: [NSLocalizedDescriptionKey: "Could not parse Copilot session token from GitHub."])
        }
        
        let exp = (json["expires_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            ?? Date().addingTimeInterval(1800)
            
        copilotLock.lock()
        cachedCopilotSourceToken = githubToken
        cachedCopilotSessionToken = sessionToken
        copilotTokenExpiresAt = exp
        copilotLock.unlock()
        
        return sessionToken
    }
    
    // MARK: - Copilot Device Flow (Official VS Code Copilot OAuth)
    public func startCopilotDeviceFlow(
        onUserCode: @escaping (String, URL) -> Void,
        onSuccess: @escaping (SubscriptionAccount) -> Void,
        onError: @escaping (String) -> Void
    ) {
        Task {
            do {
                let clientId = "01ab8ac9400c4e429b23" // Official GitHub Copilot Client ID
                var req = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                let body = "client_id=\(clientId)&scope=read:user"
                req.httpBody = body.data(using: .utf8)
                
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let deviceCode = json["device_code"] as? String,
                      let userCode = json["user_code"] as? String,
                      let verifyUrlStr = json["verification_uri"] as? String,
                      let verifyUrl = URL(string: verifyUrlStr) else {
                    await MainActor.run { onError("Failed to request device authorization code from GitHub.") }
                    return
                }
                
                let interval = (json["interval"] as? Double) ?? 5.0
                let expiresIn = (json["expires_in"] as? Double) ?? 900.0
                
                // Copy user code to clipboard automatically
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(userCode, forType: .string)
                    onUserCode(userCode, verifyUrl)
                }
                
                // Poll for completion
                let startTime = Date()
                while Date().timeIntervalSince(startTime) < expiresIn {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    
                    var pollReq = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
                    pollReq.httpMethod = "POST"
                    pollReq.setValue("application/json", forHTTPHeaderField: "Accept")
                    pollReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    let pollBody = "client_id=\(clientId)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
                    pollReq.httpBody = pollBody.data(using: .utf8)
                    
                    if let (pollData, pollResp) = try? await URLSession.shared.data(for: pollReq),
                       let pollHttp = pollResp as? HTTPURLResponse, pollHttp.statusCode == 200,
                       let pollJson = try? JSONSerialization.jsonObject(with: pollData) as? [String: Any] {
                        
                        if let error = pollJson["error"] as? String {
                            if error == "authorization_pending" {
                                continue
                            } else if error == "slow_down" {
                                try? await Task.sleep(nanoseconds: 5_000_000_000)
                                continue
                            } else {
                                await MainActor.run { onError("GitHub authorization error: \(error)") }
                                return
                            }
                        }
                        
                        if let accessToken = pollJson["access_token"] as? String, !accessToken.isEmpty {
                            _ = try await self.getCopilotSessionToken(githubToken: accessToken)
                            let account = SubscriptionAccount(
                                provider: .copilot,
                                emailOrUser: "GitHub Copilot Active",
                                sessionToken: accessToken,
                                isValid: true,
                                source: "GitHub Device Auth"
                            )
                            await MainActor.run {
                                guard self.saveTokenToKeychain(provider: SubscriptionProviderType.copilot.rawValue, token: accessToken) else {
                                    onError("Could not save the Copilot credential to Keychain.")
                                    return
                                }
                                self.accounts[.copilot] = account
                                self.persistAccounts()
                                onSuccess(account)
                            }
                            return
                        }
                    }
                }
                
                await MainActor.run { onError("GitHub authorization timed out. Please try again.") }
            } catch {
                await MainActor.run { onError(error.localizedDescription) }
            }
        }
    }
    
    public func clearAllAccounts() {
        for provider in accounts.keys {
            deleteTokenFromKeychain(provider: provider.rawValue)
        }
        accounts.removeAll()
        copilotLock.lock()
        cachedCopilotSessionToken = nil
        cachedCopilotSourceToken = nil
        copilotTokenExpiresAt = nil
        copilotLock.unlock()
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    private func persistAccounts() {
        // Only metadata leaves Keychain. Migrate older copies on every load.
        let metadata = accounts.mapValues { account in
            var copy = account
            copy.sessionToken = ""
            return copy
        }
        if let encoded = try? JSONEncoder().encode(metadata) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    private func loadSavedAccounts() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([SubscriptionProviderType: SubscriptionAccount].self, from: data) {
            var validAccounts: [SubscriptionProviderType: SubscriptionAccount] = [:]
            for (prov, acc) in decoded {
                var loadedToken = acc.sessionToken
                if let keychainToken = loadTokenFromKeychain(provider: prov.rawValue) {
                    loadedToken = keychainToken
                } else if !loadedToken.isEmpty {
                    guard saveTokenToKeychain(provider: prov.rawValue, token: loadedToken) else { continue }
                }
                let tok = loadedToken.trimmingCharacters(in: .whitespacesAndNewlines)
                // Redirect raw API keys to BYOK storage (not subscription accounts)
                if tok.hasPrefix("sk-ant-") {
                    UserDefaults.standard.set(tok, forKey: "anthropic_api_key")
                    continue
                } else if tok.hasPrefix("AIzaSy") {
                    UserDefaults.standard.set(tok, forKey: "gemini_api_key")
                    continue
                }
                // Accept any valid account regardless of source
                // (sources: "Manual", "Web Sign-In (1-Click)", "Manual Input")
                if acc.isValid && !tok.isEmpty {
                    var updatedAcc = acc
                    updatedAcc.sessionToken = tok
                    validAccounts[prov] = updatedAcc
                }
            }
            self.accounts = validAccounts
            // Only persist if we actually redirected API keys (removed entries)
            persistAccounts()
        }
    }
}
