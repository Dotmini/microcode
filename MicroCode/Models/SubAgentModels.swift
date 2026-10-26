import Foundation
import SwiftUI

// MARK: - SubAgent Lifecycle State

public enum SubAgentLifecycleState: String, Codable, CaseIterable {
    case idle = "idle"
    case running = "running"
    case waitingForInput = "waiting_for_input"
    case waitingForMessage = "waiting_for_message"
    case completed = "completed"
    case errored = "errored"
    case killed = "killed"
    
    public var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Running"
        case .waitingForInput: return "Waiting for Input"
        case .waitingForMessage: return "Waiting for Message"
        case .completed: return "Completed"
        case .errored: return "Errored"
        case .killed: return "Terminated"
        }
    }
    
    public var statusColor: Color {
        switch self {
        case .idle: return .secondary
        case .running: return .green
        case .waitingForInput, .waitingForMessage: return .orange
        case .completed: return .blue
        case .errored: return .red
        case .killed: return .gray
        }
    }
    
    public var statusIcon: String {
        switch self {
        case .idle: return "circle"
        case .running: return "bolt.fill"
        case .waitingForInput, .waitingForMessage: return "clock.fill"
        case .completed: return "checkmark.circle.fill"
        case .errored: return "exclamationmark.triangle.fill"
        case .killed: return "xmark.circle.fill"
        }
    }
}

// MARK: - Budget Config

public struct BudgetConfig: Codable, Hashable {
    public var maxModelCalls: Int?
    public var maxToolCalls: Int?
    public var maxTotalTokens: Int?
    
    public init(maxModelCalls: Int? = nil, maxToolCalls: Int? = nil, maxTotalTokens: Int? = nil) {
        self.maxModelCalls = maxModelCalls
        self.maxToolCalls = maxToolCalls
        self.maxTotalTokens = maxTotalTokens
    }
}

// MARK: - SubAgent Definition (Template)

public struct SubAgentDefinition: Identifiable, Codable, Hashable {
    public var id: String { name }
    public let name: String
    public let role: String
    public let description: String
    public let systemPrompt: String
    public let allowedTools: [String]
    public let model: String // "inherit" or specific model ID
    public var preferredProvider: String?
    public var preferredModel: String?
    public var budget: BudgetConfig?
    public let createdAt: Date
    
    public init(
        name: String,
        role: String,
        description: String,
        systemPrompt: String,
        allowedTools: [String] = [],
        model: String = "inherit",
        preferredProvider: String? = nil,
        preferredModel: String? = nil,
        budget: BudgetConfig? = nil,
        createdAt: Date = Date()
    ) {
        self.name = name
        self.role = role
        self.description = description
        self.systemPrompt = systemPrompt
        self.allowedTools = allowedTools
        self.model = model
        self.preferredProvider = preferredProvider
        self.preferredModel = preferredModel
        self.budget = budget
        self.createdAt = createdAt
    }
}

// MARK: - Universal Cross-Auth & Multi-Model Endpoint

public enum AgentAuthSource: String, Codable, CaseIterable, Identifiable {
    case auto = "auto"
    case byok = "byok"
    case subscription = "subscription"
    case acpCLI = "acp"
    case dotminiCloud = "cloud"
    case local = "local"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .auto: return "Auto (Smart Fallback)"
        case .byok: return "BYOK (API Key)"
        case .subscription: return "Subscription / OAuth"
        case .acpCLI: return "ACP / CLI (AGY / Claude / Codex)"
        case .dotminiCloud: return "Dotmini Cloud / AiPass"
        case .local: return "Local (Ollama / Omni)"
        }
    }
    
    public var shortBadge: String {
        switch self {
        case .auto: return "Auto"
        case .byok: return "BYOK"
        case .subscription: return "Sub"
        case .acpCLI: return "ACP/AGY"
        case .dotminiCloud: return "Cloud"
        case .local: return "Local"
        }
    }
    
    /// Maps to AIClient keyMode string when calling sendSync
    public var keyModeOverride: String? {
        switch self {
        case .auto: return nil
        case .byok: return "direct"
        case .subscription: return "subscription"
        case .acpCLI: return "subscription"
        case .dotminiCloud: return "cloud"
        case .local: return "local"
        }
    }
}

public struct AgentModelEndpoint: Codable, Hashable, Equatable {
    public var authSource: AgentAuthSource
    public var provider: String
    public var model: String
    
    public init(
        authSource: AgentAuthSource = .auto,
        provider: String = "inherit",
        model: String = "inherit"
    ) {
        self.authSource = authSource
        self.provider = provider
        self.model = model
    }
    
    public var badgeLabel: String {
        let modelDisplay: String
        if model == "inherit" || model.isEmpty {
            modelDisplay = provider == "inherit" ? "Active Model" : provider.capitalized
        } else {
            modelDisplay = model
        }
        return "\(modelDisplay) • \(authSource.shortBadge)"
    }
}

// MARK: - CEO & Specialist Squad Presets

public struct AgentSquadMemberSpec: Identifiable, Codable, Hashable, Equatable {
    public var id: String
    public var typeName: String
    public var roleTitle: String
    public var endpoint: AgentModelEndpoint
    public var isEnabled: Bool
    
    public init(
        id: String = UUID().uuidString,
        typeName: String,
        roleTitle: String,
        endpoint: AgentModelEndpoint,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.typeName = typeName
        self.roleTitle = roleTitle
        self.endpoint = endpoint
        self.isEnabled = isEnabled
    }
}

public struct AgentSquadPreset: Identifiable, Codable, Hashable, Equatable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var icon: String
    public var isBuiltIn: Bool
    public var ceoEndpoint: AgentModelEndpoint
    public var subordinates: [AgentSquadMemberSpec]
    public var strictVerificationGate: Bool
    public var maxRevisionRounds: Int
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        subtitle: String,
        icon: String = "person.3.sequence.fill",
        isBuiltIn: Bool = false,
        ceoEndpoint: AgentModelEndpoint,
        subordinates: [AgentSquadMemberSpec],
        strictVerificationGate: Bool = true,
        maxRevisionRounds: Int = 2
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.icon = icon
        self.isBuiltIn = isBuiltIn
        self.ceoEndpoint = ceoEndpoint
        self.subordinates = subordinates
        self.strictVerificationGate = strictVerificationGate
        self.maxRevisionRounds = maxRevisionRounds
    }
    
    public static var builtInPresets: [AgentSquadPreset] {
        [
            AgentSquadPreset(
                id: "squad_titan_claude_gemini_deepseek",
                name: "Claude CEO + Gemini + DeepSeek",
                subtitle: "Claude (CEO) สั่งงาน • Gemini (Frontend/UI) • DeepSeek (Backend/Core) • Claude (QA)",
                icon: "crown.fill",
                isBuiltIn: true,
                ceoEndpoint: AgentModelEndpoint(authSource: .auto, provider: "anthropic", model: "claude-sonnet-4-6"),
                subordinates: [
                    AgentSquadMemberSpec(
                        id: "sub_arch",
                        typeName: "architect",
                        roleTitle: "Principal Systems Architect",
                        endpoint: AgentModelEndpoint(authSource: .auto, provider: "anthropic", model: "claude-sonnet-4-6"),
                        isEnabled: true
                    ),
                    AgentSquadMemberSpec(
                        id: "sub_fe",
                        typeName: "frontend_engineer",
                        roleTitle: "Frontend & UI Specialist",
                        endpoint: AgentModelEndpoint(authSource: .auto, provider: "gemini", model: "gemini-2.5-pro"),
                        isEnabled: true
                    ),
                    AgentSquadMemberSpec(
                        id: "sub_be",
                        typeName: "backend_engineer",
                        roleTitle: "Backend & Systems Engineer",
                        endpoint: AgentModelEndpoint(authSource: .auto, provider: "deepseek", model: "deepseek-chat"),
                        isEnabled: true
                    ),
                    AgentSquadMemberSpec(
                        id: "sub_qa",
                        typeName: "test_runner",
                        roleTitle: "QA & Verification Engineer",
                        endpoint: AgentModelEndpoint(authSource: .auto, provider: "anthropic", model: "claude-sonnet-4-6"),
                        isEnabled: true
                    )
                ]
            ),
            AgentSquadPreset(
                id: "squad_openai_deepseek",
                name: "ChatGPT CEO + DeepSeek + Gemini",
                subtitle: "ChatGPT/Codex (CEO) วางแผนตรวจงาน • DeepSeek (Backend) • Gemini (Frontend)",
                icon: "sparkles.rectangle.stack.fill",
                isBuiltIn: true,
                ceoEndpoint: AgentModelEndpoint(authSource: .auto, provider: "openai", model: "gpt-4.1"),
                subordinates: [
                    AgentSquadMemberSpec(
                        id: "sub_arch_oai",
                        typeName: "architect",
                        roleTitle: "Principal Systems Architect",
                        endpoint: AgentModelEndpoint(authSource: .auto, provider: "openai", model: "gpt-4.1"),
                        isEnabled: true
                    ),
                    AgentSquadMemberSpec(
                        id: "sub_fe_oai",
                        typeName: "frontend_engineer",
                        roleTitle: "Frontend & UI Specialist",
                        endpoint: AgentModelEndpoint(authSource: .auto, provider: "gemini", model: "gemini-2.5-flash"),
                        isEnabled: true
                    ),
                    AgentSquadMemberSpec(
                        id: "sub_be_oai",
                        typeName: "backend_engineer",
                        roleTitle: "Backend & Systems Engineer",
                        endpoint: AgentModelEndpoint(authSource: .auto, provider: "deepseek", model: "deepseek-chat"),
                        isEnabled: true
                    ),
                    AgentSquadMemberSpec(
                        id: "sub_qa_oai",
                        typeName: "bug_hunter",
                        roleTitle: "Bug Hunter & Verifier",
                        endpoint: AgentModelEndpoint(authSource: .auto, provider: "openai", model: "gpt-4.1"),
                        isEnabled: true
                    )
                ]
            ),
            AgentSquadPreset(
                id: "squad_agy_sovereign",
                name: "AGY + Claude + Dotmini Cloud",
                subtitle: "ผสม AGY/ACP + Subscription + Dotmini Cloud ทำงานร่วมกันอัตโนมัติ",
                icon: "cpu.fill",
                isBuiltIn: true,
                ceoEndpoint: AgentModelEndpoint(authSource: .acpCLI, provider: "gemini", model: "gemini-2.5-pro"),
                subordinates: [
                    AgentSquadMemberSpec(
                        id: "sub_fe_agy",
                        typeName: "frontend_engineer",
                        roleTitle: "Frontend & UI Specialist",
                        endpoint: AgentModelEndpoint(authSource: .subscription, provider: "gemini", model: "gemini-2.5-flash"),
                        isEnabled: true
                    ),
                    AgentSquadMemberSpec(
                        id: "sub_be_agy",
                        typeName: "backend_engineer",
                        roleTitle: "Backend & Systems Engineer",
                        endpoint: AgentModelEndpoint(authSource: .subscription, provider: "anthropic", model: "claude-sonnet-4-6"),
                        isEnabled: true
                    ),
                    AgentSquadMemberSpec(
                        id: "sub_sec_agy",
                        typeName: "security_auditor",
                        roleTitle: "Security & Code Verifier",
                        endpoint: AgentModelEndpoint(authSource: .subscription, provider: "gemini", model: "gemini-2.5-flash"),
                        isEnabled: true
                    )
                ]
            )
        ]
    }
}

// MARK: - CEO Task Contract & Inter-Agent Dialogue

public struct SubAgentTaskContract: Identifiable, Codable, Equatable {
    public enum ContractStatus: String, Codable {
        case pending = "Pending"
        case inProgress = "In Progress"
        case underReview = "CEO Reviewing"
        case revisionNeeded = "Revision Ordered"
        case approved = "CEO Approved"
        case failed = "Failed"
    }
    
    public var id: String
    public var subagentId: String?
    public var typeName: String
    public var role: String
    public var objective: String
    public var ownedPaths: [String]
    public var acceptanceCriteria: String
    public var status: ContractStatus
    public var revisionCount: Int
    public var verificationSummary: String?
    
    public init(
        id: String = UUID().uuidString,
        subagentId: String? = nil,
        typeName: String,
        role: String,
        objective: String,
        ownedPaths: [String] = [],
        acceptanceCriteria: String = "Must pass syntax/build verification with zero regressions.",
        status: ContractStatus = .pending,
        revisionCount: Int = 0,
        verificationSummary: String? = nil
    ) {
        self.id = id
        self.subagentId = subagentId
        self.typeName = typeName
        self.role = role
        self.objective = objective
        self.ownedPaths = ownedPaths
        self.acceptanceCriteria = acceptanceCriteria
        self.status = status
        self.revisionCount = revisionCount
        self.verificationSummary = verificationSummary
    }
}

public struct InterAgentMessage: Identifiable, Codable, Equatable {
    public enum MessageKind: String, Codable {
        case briefing = "CEO Briefing"
        case delegation = "Task Assigned"
        case peerSync = "Team Sync"
        case verificationPassed = "Verified"
        case revisionRequested = "CEO Revision Order"
        case approved = "CEO Approved"
    }
    
    public let id: String
    public let timestamp: Date
    public let senderRole: String
    public let senderBadge: String
    public let recipientRole: String
    public let kind: MessageKind
    public let content: String
    public let ownedFiles: [String]
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        senderRole: String,
        senderBadge: String,
        recipientRole: String,
        kind: MessageKind,
        content: String,
        ownedFiles: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.senderRole = senderRole
        self.senderBadge = senderBadge
        self.recipientRole = recipientRole
        self.kind = kind
        self.content = content
        self.ownedFiles = ownedFiles
    }
}

// MARK: - SubAgent Instance (Active Runtime Process)

public struct SubAgentInstance: Identifiable, Codable {
    public let id: String
    public let typeName: String
    public var role: String
    public var taskPrompt: String
    public var state: SubAgentLifecycleState
    public var stateDetail: String?
    public var currentToolExecution: String?
    public var logMessages: [String]
    public var finalReport: String?
    public var tokensUsed: Int
    public var startedAt: Date
    public var finishedAt: Date?
    public var endpointBadge: String?
    public var ownedPaths: [String]
    public var revisionRound: Int
    
    public init(
        id: String = UUID().uuidString,
        typeName: String,
        role: String,
        taskPrompt: String,
        state: SubAgentLifecycleState = .idle,
        stateDetail: String? = nil,
        currentToolExecution: String? = nil,
        logMessages: [String] = [],
        finalReport: String? = nil,
        tokensUsed: Int = 0,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        endpointBadge: String? = nil,
        ownedPaths: [String] = [],
        revisionRound: Int = 0
    ) {
        self.id = id
        self.typeName = typeName
        self.role = role
        self.taskPrompt = taskPrompt
        self.state = state
        self.stateDetail = stateDetail
        self.currentToolExecution = currentToolExecution
        self.logMessages = logMessages
        self.finalReport = finalReport
        self.tokensUsed = tokensUsed
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.endpointBadge = endpointBadge
        self.ownedPaths = ownedPaths
        self.revisionRound = revisionRound
    }
}

// MARK: - Inter-Agent Message Packet

public struct SubAgentMessagePacket: Identifiable, Codable {
    public let id: String
    public let senderId: String
    public let recipientId: String
    public let message: String
    public let timestamp: Date
    
    public init(
        id: String = UUID().uuidString,
        senderId: String,
        recipientId: String,
        message: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.senderId = senderId
        self.recipientId = recipientId
        self.message = message
        self.timestamp = timestamp
    }
}
