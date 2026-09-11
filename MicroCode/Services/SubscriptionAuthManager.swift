//
//  SubscriptionAuthManager.swift
//  MicroCode
//
//  Manages web subscription connections (ChatGPT Plus/Team/Pro, Claude Pro, Gemini Advanced, DeepSeek, Copilot, Zhipu GLM)
//  without requiring per-token pay-as-you-go API keys.
//

import Foundation
import Combine
import AppKit

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
        case .claude: return "claude-3-7-sonnet"
        case .gemini: return "gemini-2.5-flash"
        case .deepseek: return "deepseek-chat"
        case .copilot: return "gpt-4o"
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
    
    public var modelInfos: [SubscriptionModelInfo] {
        switch self {
        case .chatgpt:
            return [
                SubscriptionModelInfo(modelID: "o3-mini", name: "o3-mini", provider: .chatgpt, badge: "REASONING", description: "High-speed STEM, deep code and logic reasoning", aiProviderID: "openai"),
                SubscriptionModelInfo(modelID: "o1", name: "o1 Pro", provider: .chatgpt, badge: "PRO", description: "Deep architectural planning and math reasoning", aiProviderID: "openai"),
                SubscriptionModelInfo(modelID: "gpt-4o", name: "GPT-4o Omni", provider: .chatgpt, badge: "PLUS / PRO", description: "Omni multimodal intelligence, unlimited flat-rate", aiProviderID: "openai"),
                SubscriptionModelInfo(modelID: "chatgpt-4o-latest", name: "ChatGPT-4o Latest", provider: .chatgpt, badge: "WEB", description: "Dynamic chatgpt.com web version", aiProviderID: "openai"),
                SubscriptionModelInfo(modelID: "gpt-4o-mini", name: "GPT-4o mini", provider: .chatgpt, badge: "FAST", description: "Fast lightweight multimodal model", aiProviderID: "openai")
            ]
        case .claude:
            return [
                SubscriptionModelInfo(modelID: "claude-3-7-sonnet", name: "Claude 3.7 Sonnet", provider: .claude, badge: "HYBRID", description: "Flagship hybrid thinking & standard code execution via Claude Pro", aiProviderID: "anthropic"),
                SubscriptionModelInfo(modelID: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", provider: .claude, badge: "PRO", description: "Industry standard coding & tool use", aiProviderID: "anthropic"),
                SubscriptionModelInfo(modelID: "claude-3-5-haiku", name: "Claude 3.5 Haiku", provider: .claude, badge: "FAST", description: "High-speed lightweight agent assistant", aiProviderID: "anthropic")
            ]
        case .gemini:
            return [
                SubscriptionModelInfo(modelID: "gemini-2.5-flash", name: "Gemini 2.5 Flash", provider: .gemini, badge: "FAST", description: "Real-time multimodal speed & live awareness", aiProviderID: "gemini"),
                SubscriptionModelInfo(modelID: "gemini-2.5-pro", name: "Gemini 2.5 Pro", provider: .gemini, badge: "ADVANCED", description: "Google One AI flagship deep problem solving", aiProviderID: "gemini"),
                SubscriptionModelInfo(modelID: "gemini-2.0-flash", name: "Gemini 2.0 Flash", provider: .gemini, badge: "STABLE", description: "Next-gen multimodal workhorse model", aiProviderID: "gemini")
            ]
        case .deepseek:
            return [
                SubscriptionModelInfo(modelID: "deepseek-chat", name: "DeepSeek V3", provider: .deepseek, badge: "CHAT", description: "Flagship general coding and chat", aiProviderID: "deepseek"),
                SubscriptionModelInfo(modelID: "deepseek-reasoner", name: "DeepSeek R1", provider: .deepseek, badge: "REASONING", description: "Deep R1 mathematical reasoning", aiProviderID: "deepseek")
            ]
        case .copilot:
            return [
                SubscriptionModelInfo(modelID: "gpt-4o", name: "GPT-4o", provider: .copilot, badge: "COPILOT", description: "OpenAI GPT-4o via GitHub Copilot subscription", aiProviderID: "copilot"),
                SubscriptionModelInfo(modelID: "claude-3-7-sonnet", name: "Claude 3.7 Sonnet", provider: .copilot, badge: "COPILOT", description: "Anthropic Claude 3.7 via GitHub Copilot subscription", aiProviderID: "copilot"),
                SubscriptionModelInfo(modelID: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", provider: .copilot, badge: "COPILOT", description: "Anthropic Claude 3.5 via GitHub Copilot subscription", aiProviderID: "copilot"),
                SubscriptionModelInfo(modelID: "o3-mini", name: "o3-mini", provider: .copilot, badge: "COPILOT", description: "o3-mini reasoning via GitHub Copilot subscription", aiProviderID: "copilot"),
                SubscriptionModelInfo(modelID: "o1", name: "o1", provider: .copilot, badge: "COPILOT", description: "o1 reasoning via GitHub Copilot subscription", aiProviderID: "copilot")
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
        return acc.isValid && !acc.sessionToken.isEmpty
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
        accounts[provider] = account
        persistAccounts()
    }
    
    public func disconnect(provider: SubscriptionProviderType) {
        accounts.removeValue(forKey: provider)
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
                    var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.timeoutInterval = 5
                    if let (_, resp) = try? await URLSession.shared.data(for: req),
                       let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                        DispatchQueue.main.async {
                            self.saveAccount(provider: .chatgpt, emailOrUser: email, sessionToken: token, source: "Manual")
                        }
                        detected += 1
                    }
                }
            }
        }
        
        // 2. Check for Claude CLI session (~/.claude/config.json or keychain)
        let claudeConfig = home.appendingPathComponent(".claude/config.json")
        var claudeToken: String?
        if FileManager.default.fileExists(atPath: claudeConfig.path) {
            if let data = try? Data(contentsOf: claudeConfig),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = (json["sessionKey"] ?? json["oauthToken"] ?? json["apiKey"]) as? String,
               !token.isEmpty {
                claudeToken = token
            }
        }
        if claudeToken == nil {
            claudeToken = fetchFromKeychain(service: "Claude Code")
        }
        
        if let token = claudeToken, !token.isEmpty {
            if token.hasPrefix("sk-ant-") {
                // Claude CLI stored an API key, NOT a web session. Route directly to BYOK!
                UserDefaults.standard.set(token, forKey: "anthropic_api_key")
            } else {
                var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
                req.setValue(token, forHTTPHeaderField: "x-api-key")
                req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                req.timeoutInterval = 5
                if let (_, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    DispatchQueue.main.async {
                        self.saveAccount(provider: .claude, emailOrUser: "Claude Authenticated", sessionToken: token, source: "Manual")
                    }
                    detected += 1
                }
            }
        }
        
        // 3. Check for GitHub Copilot CLI session
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
            ghToken = fetchInternetPasswordFromKeychain(server: "github.com")
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
        
        let finalDetected = detected
        DispatchQueue.main.async {
            self.detectedSessionCount = finalDetected
            if finalDetected > 0 {
                self.lastDetectionMessage = "Verified and connected \(finalDetected) active subscription session(s)."
            } else {
                self.lastDetectionMessage = "No verified subscriptions found. Please connect in settings or use Direct API Key."
            }
        }
    }
    
    private func fetchFromKeychain(service: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                return output
            }
        } catch {}
        return nil
    }
    
    private func fetchInternetPasswordFromKeychain(server: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-internet-password", "-s", server, "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                return output
            }
        } catch {}
        return nil
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
    private var copilotTokenExpiresAt: Date?
    private let copilotLock = NSLock()
    
    public func getCopilotSessionToken(githubToken: String) async throws -> String {
        copilotLock.lock()
        if let cached = cachedCopilotSessionToken,
           let expires = copilotTokenExpiresAt,
           expires > Date().addingTimeInterval(120) {
            copilotLock.unlock()
            return cached
        }
        copilotLock.unlock()
        
        let cleanToken = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else {
            throw NSError(domain: "Copilot", code: 401, userInfo: [NSLocalizedDescriptionKey: "GitHub token is empty."])
        }
        
        var req = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/v2/token")!)
        req.setValue("token \(cleanToken)", forHTTPHeaderField: "Authorization")
        req.setValue("vscode/1.95.0", forHTTPHeaderField: "Editor-Version")
        req.setValue("copilot-chat/0.22.4", forHTTPHeaderField: "Editor-Plugin-Version")
        req.setValue("GitHubCopilot/1.155.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Copilot", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response from GitHub Copilot auth."])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "Copilot", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub Copilot token exchange failed (HTTP \(http.statusCode)). Ensure your GitHub account has an active Copilot subscription."])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionToken = json["token"] as? String, !sessionToken.isEmpty else {
            throw NSError(domain: "Copilot", code: 502, userInfo: [NSLocalizedDescriptionKey: "Could not parse Copilot session token from GitHub."])
        }
        
        let exp = (json["expires_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            ?? Date().addingTimeInterval(1800)
            
        copilotLock.lock()
        cachedCopilotSessionToken = sessionToken
        copilotTokenExpiresAt = exp
        copilotLock.unlock()
        
        return sessionToken
    }
    
    public func clearAllAccounts() {
        accounts.removeAll()
        copilotLock.lock()
        cachedCopilotSessionToken = nil
        copilotTokenExpiresAt = nil
        copilotLock.unlock()
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    private func persistAccounts() {
        if let encoded = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    private func loadSavedAccounts() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([SubscriptionProviderType: SubscriptionAccount].self, from: data) {
            var validAccounts: [SubscriptionProviderType: SubscriptionAccount] = [:]
            var didRedirectAPIKey = false
            for (prov, acc) in decoded {
                let tok = acc.sessionToken.trimmingCharacters(in: .whitespacesAndNewlines)
                // Redirect raw API keys to BYOK storage (not subscription accounts)
                if tok.hasPrefix("sk-ant-") {
                    UserDefaults.standard.set(tok, forKey: "anthropic_api_key")
                    didRedirectAPIKey = true
                    continue
                } else if tok.hasPrefix("AIzaSy") {
                    UserDefaults.standard.set(tok, forKey: "gemini_api_key")
                    didRedirectAPIKey = true
                    continue
                }
                // Accept any valid account regardless of source
                // (sources: "Manual", "Web Sign-In (1-Click)", "Manual Input")
                if acc.isValid && !tok.isEmpty {
                    validAccounts[prov] = acc
                }
            }
            self.accounts = validAccounts
            // Only persist if we actually redirected API keys (removed entries)
            if didRedirectAPIKey {
                persistAccounts()
            }
        }
    }
}
