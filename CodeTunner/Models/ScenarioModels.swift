//
//  ScenarioModels.swift
//  CodeTunner
//
//  Automation Scenario Models - like make.com / n8n
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import SwiftUI
import Foundation

// MARK: - Scenario Model

class ScenarioModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    @Published var nodes: [ScenarioNode] = []
    @Published var connections: [ScenarioConnection] = []
    @Published var isRunning: Bool = false
    @Published var lastRunDate: Date?
    @Published var runCount: Int = 0
    
    init(name: String) {
        self.name = name
    }
}

// MARK: - Node Types

enum ScenarioNodeType: String, CaseIterable, Identifiable, Codable {
    // Triggers
    case trigger = "Trigger"
    case schedule = "Schedule"
    case webhook = "Webhook"
    
    // Communication
    case email = "Email"
    case line = "LINE"
    case telegram = "Telegram"
    case slack = "Slack"
    case discord = "Discord"
    case sms = "SMS"
    case whatsapp = "WhatsApp"
    
    // HTTP & Data
    case http = "HTTP"
    case transform = "Transform"
    case code = "Code"
    case broadcast = "Broadcast"
    case database = "Database"
    case filter = "Filter"
    case delay = "Delay"
    
    // AI Providers (6 providers)
    case openai = "ChatGPT"
    case gemini = "Gemini"
    case claude = "Claude"
    case deepseek = "DeepSeek"
    case glm = "GLM-4"
    case perplexity = "Perplexity"
    
    // Integrations
    case notion = "Notion"
    case googleSheets = "Google Sheets"
    case awsS3 = "AWS S3"
    case firebase = "Firebase"
    case airtable = "Airtable"
    case stripe = "Stripe"
    case container = "Container"
    
    // Flow Control
    case ifCondition = "IF"
    case loop = "Loop"
    case merge = "Merge"
    case variable = "Variable"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .trigger: return "play.circle.fill"
        case .schedule: return "clock.fill"
        case .webhook: return "antenna.radiowaves.left.and.right"
        case .email: return "envelope.fill"
        case .line: return "message.fill"
        case .http: return "globe"
        case .transform: return "gearshape.2.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .broadcast: return "megaphone.fill"
        case .database: return "cylinder.fill"
        case .filter: return "slider.horizontal.3"
        case .delay: return "timer"
        case .slack: return "number.square.fill"
        case .discord: return "bubble.left.and.bubble.right.fill"
        case .sms: return "phone.fill"
        case .whatsapp: return "phone.circle.fill"
        case .telegram: return "paperplane.fill"
        
        // AI
        case .openai, .gemini, .claude, .deepseek, .glm, .perplexity: return "brain.head.profile"
            
        // Integrations
        case .notion: return "doc.text.fill"
        case .googleSheets: return "tablecells.fill"
        case .awsS3: return "server.rack"
        case .firebase: return "flame.fill"
        case .airtable: return "square.stack.3d.up.fill"
        case .stripe: return "creditcard.fill"
        case .container: return "shippingbox.fill"
            
        // Flow
        case .ifCondition: return "arrow.triangle.branch"
        case .loop: return "repeat"
        case .merge: return "arrow.triangle.merge"
        case .variable: return "x.squareroot"
        }
    }
    
    var color: Color {
        switch self {
        case .trigger, .schedule, .webhook: return .green
        case .email: return .blue
        case .line, .whatsapp: return .green
        case .telegram: return .blue
        case .slack: return .purple
        case .discord: return .indigo
        case .sms: return .teal
            
        case .http: return .orange
        case .transform, .filter, .variable: return .purple
        case .code: return .pink
        case .broadcast: return .red
        
        // AI
        case .openai: return .green
        case .gemini: return .blue
        case .claude: return .orange
        case .deepseek: return .blue
        case .glm: return .purple
        case .perplexity: return .teal
            
        // Integrations
        case .database, .awsS3, .firebase: return .cyan
        case .notion: return .primary
        case .googleSheets: return .green
        case .airtable: return .yellow
        case .stripe: return .indigo
        case .container: return .orange
            
        case .delay, .ifCondition, .loop, .merge: return .gray
        }
    }
    
    var category: NodeCategory {
        switch self {
        case .trigger, .schedule, .webhook: return .triggers
        case .email, .line, .slack, .discord, .broadcast, .sms, .whatsapp, .telegram: return .messaging
        case .http, .notion, .googleSheets, .awsS3, .firebase, .airtable, .stripe, .container: return .integrations
        case .openai, .gemini, .claude, .deepseek, .glm, .perplexity: return .integrations
        case .transform, .filter, .code, .variable: return .logic
        case .database: return .data
        case .delay, .ifCondition, .loop, .merge: return .flow
        }
    }
    
    static var byCategory: [NodeCategory: [ScenarioNodeType]] {
        Dictionary(grouping: allCases, by: { $0.category })
    }
}

enum NodeCategory: String, CaseIterable {
    case triggers = "Triggers"
    case messaging = "Messaging"
    case integrations = "Integrations"
    case logic = "Logic"
    case data = "Data"
    case flow = "Flow Control"
    
    var icon: String {
        switch self {
        case .triggers: return "bolt.fill"
        case .messaging: return "bubble.left.and.bubble.right.fill"
        case .integrations: return "link"
        case .logic: return "gearshape.fill"
        case .data: return "cylinder.fill"
        case .flow: return "arrow.triangle.branch"
        }
    }
}

// MARK: - Scenario Node

class ScenarioNode: ObservableObject, Identifiable {
    let id = UUID()
    @Published var type: ScenarioNodeType
    @Published var name: String
    @Published var position: CGPoint
    @Published var config: NodeConfig
    @Published var isSelected: Bool = false
    @Published var lastOutput: String = ""
    @Published var hasError: Bool = false
    
    init(type: ScenarioNodeType, position: CGPoint) {
        self.type = type
        self.name = type.rawValue
        self.position = position
        self.config = NodeConfig(type: type)
    }
}

// MARK: - Node Config

    struct NodeExecutionResult: Decodable {
        let nodeId: String
        let success: Bool
        // let output: AnyCodable? // difficult to decode arbitrary JSON in Swift perfectly without wrapper
    }


// MARK: - Node Config

struct NodeConfig: Codable {
    var type: ScenarioNodeType
    
    // Common
    var enabled: Bool = true
    
    // Email (Gmail, Outlook, Custom SMTP)
    var emailTo: String = ""
    var emailSubject: String = ""
    var emailBody: String = ""
    var emailAttachmentPath: String = ""
    var smtpHost: String = ""
    var smtpPort: Int = 587
    var smtpUser: String = ""
    var smtpPassword: String = ""
    var emailUseSSL: Bool = true
    
    // LINE Messaging API
    var lineMessageType: String = "push"
    var lineChannelToken: String = ""
    var lineNotifyToken: String = ""
    var lineUserId: String = ""
    var lineGroupId: String = ""
    var lineMessage: String = ""
    var lineImageUrl: String = ""
    var lineStickerPackageId: String = ""
    var lineStickerId: String = ""
    
    // Telegram Bot API
    var telegramBotToken: String = ""
    var telegramChatId: String = ""
    var telegramMessage: String = ""
    var telegramImageUrl: String = ""
    var telegramParseMode: String = "HTML"
    
    // HTTP
    var httpUrl: String = ""
    var httpMethod: String = "GET"
    var httpHeaders: [String: String] = [:]
    var httpBody: String = ""
    var httpTimeout: Int = 30
    
    // Code
    var codeLanguage: String = "python"
    var codeContent: String = ""
    
    // Schedule
    var scheduleInterval: Int = 60
    var scheduleCron: String = ""
    
    // Webhook
    var webhookPath: String = "/webhook"
    
    // Transform
    var transformExpression: String = ""
    
    // Filter
    var filterCondition: String = ""
    
    // Delay
    var delaySeconds: Int = 5
    
    // Database
    var dbType: String = "sqlite"
    var dbConnection: String = ""
    var dbQuery: String = ""
    
    // Broadcast
    var broadcastMessage: String = ""
    
    // AI
    var aiProvider: String = "chatgpt"
    var aiApiKey: String = ""
    var aiModel: String = "gpt-4"
    var aiPrompt: String = ""
    var aiSystemPrompt: String = ""
    var aiTemperature: Double = 0.7
    var aiMaxTokens: Int = 1024
    
    // Provider Specific Keys
    var geminiApiKey: String = ""
    var openaiApiKey: String = ""
    var deepseekApiKey: String = ""
    var glmApiKey: String = ""
    var perplexityApiKey: String = ""
    var claudeApiKey: String = ""
    
    // Google Sheets
    var sheetsSpreadsheetId: String = ""
    var sheetsRange: String = ""
    var sheetsAction: String = "read"
    var sheetsServiceAccountJson: String = ""
    
    init(type: ScenarioNodeType) {
        self.type = type
        
        // Set defaults
        switch type {
        case .code:
            codeContent = "# Your code here\nprint('Hello from Scenario!')"
        case .http:
            httpUrl = "https://api.example.com"
        case .email:
            emailSubject = "Notification"
            emailBody = "This is an automated message."
        case .line:
            lineMessage = "Hello from CodeTunner!"
        default:
            break
        }
    }
}


// MARK: - Scenario Connection

struct ScenarioConnection: Identifiable {
    let id = UUID()
    let sourceNodeId: UUID
    let targetNodeId: UUID
    var label: String = ""
}

// MARK: - Scenario Manager

@MainActor
class ScenarioManager: ObservableObject {
    static let shared = ScenarioManager()
    
    @Published var scenarios: [ScenarioModel] = []
    @Published var activeScenario: ScenarioModel?
    @Published var isRunning: Bool = false
    @Published var logs: [ScenarioLog] = []
    @Published var scheduleTimer: Timer?
    @Published var isScheduled: Bool = false
    @Published var scheduleIntervalSeconds: Int = 300
    
    private var scenarioDir: String {
        let workspace = AgentToolBox.shared.workspaceRoot ?? NSHomeDirectory()
        return (workspace as NSString).appendingPathComponent(".microcode/scenarios")
    }
    
    private init() {
        loadScenarios()
        if scenarios.isEmpty {
            let defaultScenario = ScenarioModel(name: "My First Scenario")
            scenarios.append(defaultScenario)
            activeScenario = defaultScenario
        } else {
            activeScenario = scenarios.first
        }
    }
    
    func createScenario(name: String) -> ScenarioModel {
        let scenario = ScenarioModel(name: name)
        scenarios.append(scenario)
        return scenario
    }
    
    func deleteScenario(_ scenario: ScenarioModel) {
        scenarios.removeAll { $0.id == scenario.id }
        if activeScenario?.id == scenario.id {
            activeScenario = scenarios.first
        }
    }
    
    func addNode(type: ScenarioNodeType, at position: CGPoint) {
        guard let scenario = activeScenario else { return }
        let node = ScenarioNode(type: type, position: position)
        scenario.nodes.append(node)
    }
    
    func removeNode(_ node: ScenarioNode) {
        guard let scenario = activeScenario else { return }
        scenario.nodes.removeAll { $0.id == node.id }
        scenario.connections.removeAll { $0.sourceNodeId == node.id || $0.targetNodeId == node.id }
    }
    
    func connect(from source: ScenarioNode, to target: ScenarioNode) {
        guard let scenario = activeScenario else { return }
        let connection = ScenarioConnection(sourceNodeId: source.id, targetNodeId: target.id)
        scenario.connections.append(connection)
    }
    
    func disconnect(_ connection: ScenarioConnection) {
        guard let scenario = activeScenario else { return }
        scenario.connections.removeAll { $0.id == connection.id }
    }
    
    // MARK: - Save / Load
    
    func saveScenario(_ scenario: ScenarioModel? = nil) {
        let target = scenario ?? activeScenario
        guard let s = target else { return }
        
        let fm = FileManager.default
        try? fm.createDirectory(atPath: scenarioDir, withIntermediateDirectories: true)
        
        let data: [String: Any] = [
            "id": s.id.uuidString,
            "name": s.name,
            "runCount": s.runCount,
            "nodes": s.nodes.map { node -> [String: Any] in
                let encoder = JSONEncoder()
                let configData = (try? encoder.encode(node.config)) ?? Data()
                let configDict = (try? JSONSerialization.jsonObject(with: configData)) as? [String: Any] ?? [:]
                return [
                    "id": node.id.uuidString,
                    "type": node.type.rawValue,
                    "name": node.name,
                    "x": node.position.x,
                    "y": node.position.y,
                    "config": configDict
                ]
            },
            "connections": s.connections.map { ["source": $0.sourceNodeId.uuidString, "target": $0.targetNodeId.uuidString] }
        ]
        
        let filePath = (scenarioDir as NSString).appendingPathComponent("\(s.name.replacingOccurrences(of: " ", with: "_")).json")
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted]) {
            try? jsonData.write(to: URL(fileURLWithPath: filePath))
            addLog("💾 Saved: \(s.name)")
        }
    }
    
    func loadScenarios() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: scenarioDir),
              let files = try? fm.contentsOfDirectory(atPath: scenarioDir) else { return }
        
        for file in files where file.hasSuffix(".json") {
            let path = (scenarioDir as NSString).appendingPathComponent(file)
            guard let data = fm.contents(atPath: path),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = dict["name"] as? String else { continue }
            
            let scenario = ScenarioModel(name: name)
            scenario.runCount = dict["runCount"] as? Int ?? 0
            scenarios.append(scenario)
        }
    }
    
    // MARK: - Schedule
    
    func startSchedule(interval: Int) {
        stopSchedule()
        scheduleIntervalSeconds = interval
        isScheduled = true
        addLog("⏱ Schedule started: every \(interval)s")
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.runScenario()
            }
        }
    }
    
    func stopSchedule() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        isScheduled = false
    }
    
    // MARK: - Local Node Execution (no backend needed)
    
    func executeNodeLocally(_ node: ScenarioNode, input: String = "") async -> String {
        switch node.type {
        case .code:
            return await runCodeLocally(language: node.config.codeLanguage, code: node.config.codeContent)
        case .http:
            return await runHTTPLocally(node.config)
        case .delay:
            try? await Task.sleep(nanoseconds: UInt64(node.config.delaySeconds) * 1_000_000_000)
            return "⏱ Delayed \(node.config.delaySeconds)s"
        case .trigger:
            return "▶️ Triggered"
        case .schedule:
            return "🕐 Schedule trigger"
        case .email:
            return "📧 Email: To=\(node.config.emailTo) Subject=\(node.config.emailSubject)"
        case .line:
            return await sendLINELocally(node.config)
        case .telegram:
            return await sendTelegramLocally(node.config)
        case .slack:
            return await sendSlackLocally(node.config)
        case .discord:
            return await sendDiscordLocally(node.config)
        case .openai, .gemini, .claude, .deepseek, .glm, .perplexity:
            return await callAILocally(node.config, input: input)
        case .transform:
            return "🔄 Transform: \(node.config.transformExpression)"
        case .filter:
            return "🔍 Filter: \(node.config.filterCondition)"
        default:
            return "⚙️ \(node.type.rawValue) executed"
        }
    }
    
    private func runCodeLocally(language: String, code: String) async -> String {
        let process = Process()
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        process.launchPath = "/bin/zsh"
        
        switch language {
        case "python":
            process.arguments = ["-c", "python3 -u -c \(shellEscape(code))"]
        case "javascript":
            process.arguments = ["-c", "node -e \(shellEscape(code))"]
        default:
            process.arguments = ["-c", "python3 -u -c \(shellEscape(code))"]
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errOutput = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if process.terminationStatus != 0 {
                return "❌ Exit \(process.terminationStatus)\n\(errOutput)"
            }
            return output.isEmpty ? "(no output)" : output
        } catch {
            return "❌ \(error.localizedDescription)"
        }
    }
    
    private func shellEscape(_ s: String) -> String {
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    
    private func runHTTPLocally(_ config: NodeConfig) async -> String {
        guard let url = URL(string: config.httpUrl) else { return "❌ Invalid URL" }
        var req = URLRequest(url: url)
        req.httpMethod = config.httpMethod
        req.timeoutInterval = TimeInterval(config.httpTimeout)
        if !config.httpBody.isEmpty && config.httpMethod != "GET" {
            req.httpBody = config.httpBody.data(using: .utf8)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            let truncated = body.count > 2000 ? String(body.prefix(2000)) + "..." : body
            return "✅ HTTP \(status)\n\(truncated)"
        } catch {
            return "❌ \(error.localizedDescription)"
        }
    }
    
    private func sendLINELocally(_ config: NodeConfig) async -> String {
        guard !config.lineChannelToken.isEmpty else { return "❌ LINE Channel Token required" }
        let url = URL(string: config.lineMessageType == "broadcast" ? "https://api.line.me/v2/bot/message/broadcast" : "https://api.line.me/v2/bot/message/push")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.lineChannelToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["messages": [["type": "text", "text": config.lineMessage]]]
        if config.lineMessageType == "push" {
            body["to"] = config.lineUserId
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200 ? "✅ LINE message sent" : "❌ LINE \(status): \(String(data: data, encoding: .utf8) ?? "")"
        } catch {
            return "❌ \(error.localizedDescription)"
        }
    }
    
    private func sendTelegramLocally(_ config: NodeConfig) async -> String {
        guard !config.telegramBotToken.isEmpty else { return "❌ Bot Token required" }
        let url = URL(string: "https://api.telegram.org/bot\(config.telegramBotToken)/sendMessage")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["chat_id": config.telegramChatId, "text": config.telegramMessage]
        if !config.telegramParseMode.isEmpty { body["parse_mode"] = config.telegramParseMode }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200 ? "✅ Telegram sent" : "❌ Telegram \(status): \(String(data: data, encoding: .utf8) ?? "")"
        } catch { return "❌ \(error.localizedDescription)" }
    }
    
    private func sendSlackLocally(_ config: NodeConfig) async -> String {
        guard !config.lineChannelToken.isEmpty else { return "❌ Slack Bot Token required" }
        let url = URL(string: "https://slack.com/api/chat.postMessage")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.lineChannelToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["channel": config.lineGroupId, "text": config.lineMessage]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200 ? "✅ Slack sent" : "❌ Slack \(status): \(String(data: data, encoding: .utf8) ?? "")"
        } catch { return "❌ \(error.localizedDescription)" }
    }
    
    private func sendDiscordLocally(_ config: NodeConfig) async -> String {
        guard !config.lineChannelToken.isEmpty else { return "❌ Discord Bot Token required" }
        let url = URL(string: "https://discord.com/api/v10/channels/\(config.lineGroupId)/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bot \(config.lineChannelToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["content": config.lineMessage]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200 ? "✅ Discord sent" : "❌ Discord \(status): \(String(data: data, encoding: .utf8) ?? "")"
        } catch { return "❌ \(error.localizedDescription)" }
    }
    
    private func callAILocally(_ config: NodeConfig, input: String) async -> String {
        let key = config.aiApiKey
        guard !key.isEmpty else { return "❌ API Key required" }
        
        var apiUrl: String
        var model: String
        var bodyDict: [String: Any]
        
        switch config.aiProvider {
        case "chatgpt":
            apiUrl = "https://api.openai.com/v1/chat/completions"
            model = "gpt-4o-mini"
            bodyDict = [
                "model": model,
                "messages": [
                    ["role": "system", "content": config.aiSystemPrompt.isEmpty ? "You are a helpful assistant." : config.aiSystemPrompt],
                    ["role": "user", "content": config.aiPrompt.isEmpty ? input : config.aiPrompt]
                ],
                "max_tokens": config.aiMaxTokens,
                "temperature": config.aiTemperature
            ]
        case "gemini":
            apiUrl = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(key)"
            bodyDict = ["contents": [["parts": [["text": config.aiPrompt.isEmpty ? input : config.aiPrompt]]]]]
        case "claude":
            apiUrl = "https://api.anthropic.com/v1/messages"
            bodyDict = [
                "model": "claude-sonnet-4-20250514",
                "max_tokens": config.aiMaxTokens,
                "messages": [["role": "user", "content": config.aiPrompt.isEmpty ? input : config.aiPrompt]]
            ]
        case "deepseek":
            apiUrl = "https://api.deepseek.com/chat/completions"
            bodyDict = [
                "model": "deepseek-chat",
                "messages": [["role": "user", "content": config.aiPrompt.isEmpty ? input : config.aiPrompt]],
                "max_tokens": config.aiMaxTokens
            ]
        default:
            return "❌ Unsupported provider: \(config.aiProvider)"
        }
        
        guard let url = URL(string: apiUrl) else { return "❌ Invalid API URL" }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if config.aiProvider == "claude" {
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if config.aiProvider != "gemini" {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        
        req.httpBody = try? JSONSerialization.data(withJSONObject: bodyDict)
        req.timeoutInterval = 60
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status != 200 {
                return "❌ AI \(status): \(String(data: data, encoding: .utf8) ?? "")"
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            // Extract response text
            if let choices = json?["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
            if let content = json?["content"] as? [[String: Any]],
               let text = content.first?["text"] as? String {
                return text
            }
            if let candidates = json?["candidates"] as? [[String: Any]],
               let parts = (candidates.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String {
                return text
            }
            return String(data: data, encoding: .utf8) ?? "(no response)"
        } catch {
            return "❌ \(error.localizedDescription)"
        }
    }
    
    func runScenario() async {
        guard let scenario = activeScenario else { return }
        
        isRunning = true
        scenario.isRunning = true
        scenario.runCount += 1
        addLog("🚀 Starting scenario: \(scenario.name)...")
        
        // Build execution order from connections (topological sort)
        let executionOrder = buildExecutionOrder(scenario)
        var lastOutput = ""
        var hasFailure = false
        
        for node in executionOrder {
            addLog("▶️ \(node.name)...")
            let result = await executeNodeLocally(node, input: lastOutput)
            node.lastOutput = result
            
            if result.hasPrefix("❌") {
                node.hasError = true
                hasFailure = true
                addLog("❌ \(node.name): \(result)")
                break // Stop on error
            } else {
                node.hasError = false
                lastOutput = result
                addLog("✅ \(node.name): \(String(result.prefix(200)))")
            }
        }
        
        isRunning = false
        scenario.isRunning = false
        addLog(hasFailure ? "❌ Scenario failed" : "✅ Scenario completed (\(executionOrder.count) nodes)")
        saveScenario()
    }
    
    private func buildExecutionOrder(_ scenario: ScenarioModel) -> [ScenarioNode] {
        // Find root nodes (no incoming connections)
        let targetIds = Set(scenario.connections.map { $0.targetNodeId })
        var roots = scenario.nodes.filter { !targetIds.contains($0.id) }
        if roots.isEmpty { roots = scenario.nodes }
        
        // BFS from roots
        var ordered: [ScenarioNode] = []
        var visited = Set<UUID>()
        var queue = roots
        
        while !queue.isEmpty {
            let node = queue.removeFirst()
            guard !visited.contains(node.id) else { continue }
            visited.insert(node.id)
            ordered.append(node)
            
            // Find children
            let childIds = scenario.connections.filter { $0.sourceNodeId == node.id }.map { $0.targetNodeId }
            for childId in childIds {
                if let child = scenario.nodes.first(where: { $0.id == childId }) {
                    queue.append(child)
                }
            }
        }
        
        // Add any unconnected nodes
        for node in scenario.nodes where !visited.contains(node.id) {
            ordered.append(node)
        }
        
        return ordered
    }

    
    func executeSingleNode(_ node: ScenarioNode) async {
        addLog("▶️ Testing node: \(node.name)...")
        
        let result = await executeNodeLocally(node)
        node.lastOutput = result
        
        if result.hasPrefix("❌") {
            node.hasError = true
            addLog("❌ Test failed: \(result)")
        } else {
            node.hasError = false
            addLog("✅ Test passed: \(String(result.prefix(300)))")
        }
    }
    
    
    private func jsonString(from anyCodable: AnyCodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(anyCodable), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "\(anyCodable.value)"
    }
    
    // MARK: - DTOs
    
    struct ScenarioExecuteRequest: Encodable {
        let id: String
        let name: String
        let nodes: [ScenarioNodeDTO]
        let connections: [ScenarioConnectionDTO]
    }
    
    struct ScenarioNodeDTO: Encodable {
        let id: String
        let nodeType: String
        let name: String
        let config: NodeConfig
        
        enum CodingKeys: String, CodingKey {
            case id, nodeType, name, config
        }
    }
    
    struct ScenarioConnectionDTO: Encodable {
        let id: String
        let sourceNodeId: String
        let targetNodeId: String
    }
    
    struct ScenarioExecutionResult: Decodable {
        let success: Bool
        let logs: [String]
        let nodeResults: [NodeExecutionResult]
    }
    
    struct NodeExecutionResult: Decodable {
        let nodeId: String
        let success: Bool
        let output: AnyCodable?
        let error: String?
    }
    
    // MARK: - Logging
    

    public func addLog(_ message: String) {
        let log = ScenarioLog(message: message)
        logs.insert(log, at: 0)
        
        // Keep only last 100 logs
        if logs.count > 100 {
            logs = Array(logs.prefix(100))
        }
    }
    
    public func clearLogs() {
        logs.removeAll()
    }
}

// MARK: - Scenario Log

struct ScenarioLog: Identifiable {
    let id = UUID()
    var timestamp = Date()
    let message: String
}

// MARK: - Errors



// MARK: - AnyCodable


