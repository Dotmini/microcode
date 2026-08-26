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

// MARK: - SubAgent Definition (Template)

public struct SubAgentDefinition: Identifiable, Codable, Hashable {
    public var id: String { name }
    public let name: String
    public let role: String
    public let description: String
    public let systemPrompt: String
    public let allowedTools: [String]
    public let model: String // "inherit" or specific model ID
    public let createdAt: Date
    
    public init(
        name: String,
        role: String,
        description: String,
        systemPrompt: String,
        allowedTools: [String] = [],
        model: String = "inherit",
        createdAt: Date = Date()
    ) {
        self.name = name
        self.role = role
        self.description = description
        self.systemPrompt = systemPrompt
        self.allowedTools = allowedTools
        self.model = model
        self.createdAt = createdAt
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
        finishedAt: Date? = nil
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
