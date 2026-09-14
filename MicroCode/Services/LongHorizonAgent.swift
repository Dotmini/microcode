// Copyright © 2025 Dotmini Software. All rights reserved.

import Foundation
import SwiftUI
import Combine

// MARK: - Task & Subtask Data Models

/// Represents the overall long-horizon task spanning multiple subtasks
public struct HorizonTask: Identifiable, Codable, Equatable {
    public let id: String
    public var title: String
    public var description: String
    public var subtasks: [Subtask]
    public var status: HorizonTaskStatus
    public var startedAt: Date
    public var estimatedDuration: TimeInterval?
    public var checkpoints: [Checkpoint]
    public var projectPath: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String,
        subtasks: [Subtask] = [],
        status: HorizonTaskStatus = .pending,
        startedAt: Date = Date(),
        estimatedDuration: TimeInterval? = nil,
        checkpoints: [Checkpoint] = [],
        projectPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.subtasks = subtasks
        self.status = status
        self.startedAt = startedAt
        self.estimatedDuration = estimatedDuration
        self.checkpoints = checkpoints
        self.projectPath = projectPath
    }
}

/// Status of the overall long-horizon task
public enum HorizonTaskStatus: String, Codable, CaseIterable {
    case pending
    case inProgress
    case paused
    case completed
    case failed
    case cancelled
}

/// Represents an individual, ordered subtask within a long-horizon task
public struct Subtask: Identifiable, Codable, Equatable {
    public let id: String
    public var title: String
    public var description: String
    public var status: Status
    public var dependencies: [String]
    public var result: String?
    public var duration: TimeInterval

    public enum Status: String, Codable, CaseIterable {
        case pending
        case inProgress
        case completed
        case failed
        case skipped
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String,
        status: Status = .pending,
        dependencies: [String] = [],
        result: String? = nil,
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.dependencies = dependencies
        self.result = result
        self.duration = duration
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case status
        case dependencies
        case result
        case duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle id as either String or Int
        if let stringId = try? container.decode(String.self, forKey: .id) {
            self.id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            self.id = "subtask_\(intId)"
        } else {
            self.id = UUID().uuidString
        }

        self.title = (try? container.decode(String.self, forKey: .title)) ?? "Untitled Subtask"
        self.description = (try? container.decode(String.self, forKey: .description)) ?? self.title
        self.status = (try? container.decode(Status.self, forKey: .status)) ?? .pending

        // Handle dependencies as array of String or Int
        if let stringDeps = try? container.decode([String].self, forKey: .dependencies) {
            self.dependencies = stringDeps
        } else if let intDeps = try? container.decode([Int].self, forKey: .dependencies) {
            self.dependencies = intDeps.map { "subtask_\($0)" }
        } else {
            self.dependencies = []
        }

        self.result = try? container.decode(String.self, forKey: .result)
        self.duration = (try? container.decode(TimeInterval.self, forKey: .duration)) ?? 0
    }
}

public typealias SubtaskStatus = Subtask.Status

/// Audit trail timeline event during long-horizon task execution
public struct TimelineEvent: Identifiable, Codable, Equatable {
    public let id: String
    public let timestamp: Date
    public let type: EventType
    public let message: String
    public let subtaskId: String?

    public enum EventType: String, Codable, CaseIterable {
        case subtaskStarted
        case subtaskCompleted
        case checkpoint
        case error
        case userInput
    }

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        type: EventType,
        message: String,
        subtaskId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.message = message
        self.subtaskId = subtaskId
    }
}

public typealias TimelineEventType = TimelineEvent.EventType

/// Checkpoint saved periodically or on demand for interruption resumption
public struct Checkpoint: Identifiable, Codable, Equatable {
    public let id: String
    public let subtaskId: String?
    public let timestamp: Date
    public let state: String
    public let filesModified: [String]

    public init(
        id: String = UUID().uuidString,
        subtaskId: String? = nil,
        timestamp: Date = Date(),
        state: String,
        filesModified: [String] = []
    ) {
        self.id = id
        self.subtaskId = subtaskId
        self.timestamp = timestamp
        self.state = state
        self.filesModified = filesModified
    }
}

/// Internal serialized state structure packed into Checkpoint.state
struct CheckpointState: Codable {
    let taskId: String
    let taskTitle: String
    let taskDescription: String
    let projectPath: String?
    let subtasks: [Subtask]
    let progress: Double
    let timestamp: Date
    let timeline: [TimelineEvent]
    let filesModified: [String]
}

// MARK: - Long-Horizon Errors

public enum LongHorizonError: LocalizedError {
    case noActiveTask
    case taskAlreadyExecuting
    case subtaskTimeout(String, TimeInterval)
    case executionCancelled
    case executionPaused
    case planningFailed(String)
    case checkpointNotFound(String)
    case invalidCheckpointState

    public var errorDescription: String? {
        switch self {
        case .noActiveTask:
            return "No active long-horizon task."
        case .taskAlreadyExecuting:
            return "A long-horizon task is already executing."
        case .subtaskTimeout(let id, let timeout):
            return "Subtask '\(id)' timed out after \(Int(timeout / 60)) minutes."
        case .executionCancelled:
            return "Task execution was cancelled."
        case .executionPaused:
            return "Task execution was paused."
        case .planningFailed(let reason):
            return "Failed to plan subtasks: \(reason)"
        case .checkpointNotFound(let id):
            return "Checkpoint '\(id)' was not found."
        case .invalidCheckpointState:
            return "Invalid checkpoint state format."
        }
    }
}


// MARK: - Long-Horizon Agent Service

/// Service managing multi-step, long-running coding tasks with checkpointing, pause/resume, and tool execution.
@MainActor
public class LongHorizonAgent: ObservableObject {
    public static let shared = LongHorizonAgent()

    // MARK: - Published Properties

    @Published public var currentTask: HorizonTask?
    @Published public var isExecuting: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var subtasks: [Subtask] = []
    @Published public var timeline: [TimelineEvent] = []

    // MARK: - Private State

    private var executionTask: Task<Void, Never>?
    private var isPaused: Bool = false
    private var isCancelled: Bool = false
    private var filesModifiedDuringTask: Set<String> = []

    /// Maximum timeout per individual subtask: 30 minutes
    private let maxSubtaskTimeout: TimeInterval = 30 * 60

    private init() {}

    // MARK: - Public Control API

    /// Starts a long-horizon task: generates a plan using AI, then begins sequential execution
    public func startTask(description: String, projectPath: String) async throws {
        guard !isExecuting else {
            throw LongHorizonError.taskAlreadyExecuting
        }

        isExecuting = true
        isPaused = false
        isCancelled = false
        progress = 0.0
        timeline.removeAll()
        filesModifiedDuringTask.removeAll()

        addTimelineEvent(type: .userInput, message: "Task initiated: \(description.prefix(120))")

        // Bind workspace root for tool executions
        AgentToolBox.shared.workspaceRoot = projectPath

        // Step 1: Plan subtasks via AI
        let plannedSubtasks: [Subtask]
        do {
            plannedSubtasks = try await planSubtasks(description: description, context: projectPath)
        } catch {
            isExecuting = false
            addTimelineEvent(type: .error, message: "Task planning failed: \(error.localizedDescription)")
            throw error
        }

        guard !plannedSubtasks.isEmpty else {
            isExecuting = false
            let err = LongHorizonError.planningFailed("The planner returned an empty subtask array.")
            addTimelineEvent(type: .error, message: err.localizedDescription)
            throw err
        }

        // Initialize current task
        let firstLine = description.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? "Long-Horizon Task"
        let taskTitle = firstLine.isEmpty ? "Long-Horizon Task" : String(firstLine.prefix(80))
        let estimatedSecs = Double(plannedSubtasks.count * 180)

        let task = HorizonTask(
            id: UUID().uuidString,
            title: taskTitle,
            description: description,
            subtasks: plannedSubtasks,
            status: .inProgress,
            startedAt: Date(),
            estimatedDuration: estimatedSecs,
            checkpoints: [],
            projectPath: projectPath
        )

        self.currentTask = task
        self.subtasks = plannedSubtasks

        // Initial checkpoint before execution
        _ = try? await checkpoint()

        // Step 2: Begin execution loop in background task
        executionTask?.cancel()
        executionTask = Task { @MainActor in
            await runExecutionLoop()
        }
    }

    /// Plans ordered subtasks from description and project context using AIClient.streamCompletion
    public func planSubtasks(description: String, context: String) async throws -> [Subtask] {
        let systemPrompt = """
        Break this coding task into ordered subtasks. Return JSON array.
        Respond ONLY with a valid JSON array of objects. Do not include markdown code block markers or any commentary.
        Each object must have the following schema:
        {
          "id": "subtask_1",
          "title": "Clear concise title",
          "description": "Specific actionable instructions for this step",
          "dependencies": []
        }
        Ensure dependencies correctly list prerequisite subtask IDs (e.g. ["subtask_1"]).
        """

        let userPrompt = """
        TASK DESCRIPTION:
        \(description)

        PROJECT CONTEXT / ROOT:
        \(context)
        """

        let messages = [
            (role: "system", content: systemPrompt),
            (role: "user", content: userPrompt)
        ]

        let stream = try await AIClient.shared.streamCompletion(
            messages: messages,
            tools: nil,
            stream: false
        )

        var fullResponse = ""
        for try await chunk in stream {
            fullResponse += chunk
        }

        return parseSubtaskPlan(from: fullResponse)
    }

    /// Executes a single subtask with a 30-minute timeout and tool loop
    public func executeSubtask(_ subtask: Subtask) async throws {
        guard let index = subtasks.firstIndex(where: { $0.id == subtask.id }) else { return }

        subtasks[index].status = .inProgress
        addTimelineEvent(type: .subtaskStarted, message: "Started subtask: \(subtask.title)", subtaskId: subtask.id)

        let startTime = Date()

        do {
            // Enforce max 30-minute timeout for the subtask
            try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await self.performSubtaskAgentLoop(subtask: subtask)
                }

                group.addTask {
                    let nanoseconds = UInt64(self.maxSubtaskTimeout * 1_000_000_000)
                    try await Task.sleep(nanoseconds: nanoseconds)
                    throw LongHorizonError.subtaskTimeout(subtask.id, self.maxSubtaskTimeout)
                }

                // First one to complete wins
                let resultSummary = try await group.next() ?? "Subtask finished."
                group.cancelAll()

                // Mark completed
                if let updatedIndex = self.subtasks.firstIndex(where: { $0.id == subtask.id }) {
                    self.subtasks[updatedIndex].status = .completed
                    self.subtasks[updatedIndex].result = resultSummary
                    self.subtasks[updatedIndex].duration = Date().timeIntervalSince(startTime)
                }

                self.addTimelineEvent(
                    type: .subtaskCompleted,
                    message: "Completed subtask: \(subtask.title)",
                    subtaskId: subtask.id
                )
            }
        } catch {
            if let updatedIndex = self.subtasks.firstIndex(where: { $0.id == subtask.id }) {
                self.subtasks[updatedIndex].status = isCancelled ? .skipped : .failed
                self.subtasks[updatedIndex].result = error.localizedDescription
                self.subtasks[updatedIndex].duration = Date().timeIntervalSince(startTime)
            }

            self.addTimelineEvent(
                type: .error,
                message: "Subtask '\(subtask.title)' failed: \(error.localizedDescription)",
                subtaskId: subtask.id
            )
            throw error
        }
    }

    /// Saves the current execution state to memory and disk for interruption resumption
    @discardableResult
    public func checkpoint() async throws -> Checkpoint {
        guard let task = currentTask else {
            throw LongHorizonError.noActiveTask
        }

        let stateObj = CheckpointState(
            taskId: task.id,
            taskTitle: task.title,
            taskDescription: task.description,
            projectPath: task.projectPath,
            subtasks: self.subtasks,
            progress: self.progress,
            timestamp: Date(),
            timeline: self.timeline,
            filesModified: Array(self.filesModifiedDuringTask)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let stateData = try encoder.encode(stateObj)
        let stateString = String(data: stateData, encoding: .utf8) ?? "{}"

        let activeSubtaskId = subtasks.first(where: { $0.status == .inProgress })?.id
        let checkpoint = Checkpoint(
            id: UUID().uuidString,
            subtaskId: activeSubtaskId,
            timestamp: Date(),
            state: stateString,
            filesModified: Array(self.filesModifiedDuringTask)
        )

        self.currentTask?.checkpoints.append(checkpoint)

        addTimelineEvent(
            type: .checkpoint,
            message: "Saved checkpoint (\(checkpoint.id.prefix(8)))",
            subtaskId: activeSubtaskId
        )

        try saveCheckpointToDisk(checkpoint: checkpoint, task: task)

        return checkpoint
    }

    /// Resumes execution from a previously saved checkpoint
    public func resume(from checkpoint: Checkpoint) async throws {
        guard !isExecuting else {
            throw LongHorizonError.taskAlreadyExecuting
        }

        guard let data = checkpoint.state.data(using: .utf8) else {
            throw LongHorizonError.invalidCheckpointState
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(CheckpointState.self, from: data)

        // Restore in-memory state
        self.subtasks = state.subtasks
        self.progress = state.progress
        self.timeline = state.timeline
        self.filesModifiedDuringTask = Set(state.filesModified)

        if let root = state.projectPath {
            AgentToolBox.shared.workspaceRoot = root
        }

        let restoredTask = HorizonTask(
            id: state.taskId,
            title: state.taskTitle,
            description: state.taskDescription,
            subtasks: state.subtasks,
            status: .inProgress,
            startedAt: state.timestamp,
            estimatedDuration: Double(state.subtasks.count * 180),
            checkpoints: [checkpoint],
            projectPath: state.projectPath
        )

        self.currentTask = restoredTask

        // Reset any subtask that was interrupted mid-flight to pending
        for i in 0..<self.subtasks.count {
            if self.subtasks[i].status == .inProgress {
                self.subtasks[i].status = .pending
            }
        }

        addTimelineEvent(
            type: .checkpoint,
            message: "Resumed execution from checkpoint (\(checkpoint.id.prefix(8)))",
            subtaskId: checkpoint.subtaskId
        )

        isExecuting = true
        isPaused = false
        isCancelled = false

        executionTask?.cancel()
        executionTask = Task { @MainActor in
            await runExecutionLoop()
        }
    }

    /// Pauses execution safely after the current action or between subtasks
    public func pauseExecution() {
        guard isExecuting else { return }
        isPaused = true
        isExecuting = false
        currentTask?.status = .paused
        addTimelineEvent(type: .userInput, message: "Execution paused by user")

        Task { @MainActor in
            _ = try? await self.checkpoint()
        }
    }

    /// Cancels execution immediately and marks running subtasks as skipped
    public func cancelExecution() {
        isCancelled = true
        isExecuting = false
        executionTask?.cancel()
        currentTask?.status = .cancelled

        for i in 0..<subtasks.count {
            if subtasks[i].status == .inProgress {
                subtasks[i].status = .skipped
                subtasks[i].result = "Cancelled by user"
            }
        }

        addTimelineEvent(type: .userInput, message: "Execution cancelled by user")

        Task { @MainActor in
            _ = try? await self.checkpoint()
        }
    }

    // MARK: - Internal Execution Engine

    /// Sequential execution loop across all planned subtasks respecting dependencies
    private func runExecutionLoop() async {
        while !isCancelled && !isPaused {
            guard let nextIndex = findNextExecutableSubtaskIndex() else {
                break
            }

            let subtaskToRun = subtasks[nextIndex]
            do {
                try await executeSubtask(subtaskToRun)
            } catch {
                if isCancelled {
                    addTimelineEvent(type: .userInput, message: "Execution stopped: cancelled", subtaskId: subtaskToRun.id)
                    break
                } else if isPaused {
                    addTimelineEvent(type: .userInput, message: "Execution stopped: paused", subtaskId: subtaskToRun.id)
                    break
                } else {
                    handleSubtaskFailure(failedIndex: nextIndex)
                }
            }

            updateProgress()
            _ = try? await checkpoint()
        }

        // Finalize task status
        isExecuting = false
        if isCancelled {
            currentTask?.status = .cancelled
        } else if isPaused {
            currentTask?.status = .paused
        } else {
            let allFinished = subtasks.allSatisfy { $0.status == .completed || $0.status == .skipped }
            let hasFailures = subtasks.contains { $0.status == .failed }

            if allFinished && !hasFailures {
                currentTask?.status = .completed
                progress = 1.0
                addTimelineEvent(type: .userInput, message: "Long-horizon task completed successfully!")
            } else {
                currentTask?.status = .failed
                addTimelineEvent(type: .error, message: "Long-horizon task finished with errors.")
            }
        }

        _ = try? await checkpoint()
    }

    /// Runs multi-turn agent tool loop for a single subtask
    private func performSubtaskAgentLoop(subtask: Subtask) async throws -> String {
        let systemPrompt = """
        You are an autonomous long-horizon software engineering agent executing a specific subtask of a larger task.
        Subtask Title: \(subtask.title)
        Subtask Description: \(subtask.description)
        Workspace Root: \(AgentToolBox.shared.workspaceRoot ?? ".")

        You have access to tools for reading and modifying files, executing shell commands, and searching code.
        Guidelines:
        1. Examine existing files first to understand context before making edits.
        2. Apply edits cleanly using file_write, replace_in_file, or patch_file.
        3. Verify results or run tests using shell tool where appropriate.
        4. When the subtask is completely finished, provide a concise summary of your work and results.
        """

        var conversation: [(role: String, content: String)] = [
            (role: "system", content: systemPrompt),
            (role: "user", content: "Begin execution of subtask: '\(subtask.title)'. Instructions: \(subtask.description)")
        ]

        let toolSchemas = AgentToolBox.shared.toolSchemas()
        var turn = 0
        let maxTurns = 15
        var finalSummary = ""

        while turn < maxTurns {
            if isCancelled { throw LongHorizonError.executionCancelled }
            if isPaused { throw LongHorizonError.executionPaused }

            turn += 1

            var nativeToolCalls: [AIToolCall] = []
            let stream = try await AIClient.shared.streamCompletion(
                messages: conversation,
                tools: toolSchemas,
                stream: true,
                onToolCall: { toolCall in
                    nativeToolCalls.append(toolCall)
                }
            )

            var streamedText = ""
            for try await token in stream {
                streamedText += token
            }

            // If no native tool calls were received, parse text-based tool calls
            var toolCallsToExecute = nativeToolCalls
            if toolCallsToExecute.isEmpty {
                toolCallsToExecute = parseTextBasedToolCalls(streamedText)
            }

            // If still no tool calls, the model concluded its subtask response
            if toolCallsToExecute.isEmpty {
                let trimmed = streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
                finalSummary = trimmed.isEmpty ? "Subtask completed successfully." : trimmed
                break
            }

            // Append assistant thinking/response to conversation
            conversation.append((role: "assistant", content: streamedText.isEmpty ? "Invoking tools..." : streamedText))

            // Execute the tool calls sequentially
            for toolCall in toolCallsToExecute {
                if isCancelled { throw LongHorizonError.executionCancelled }

                let toolName = toolCall.name
                let params = toolCall.arguments
                trackFileModifications(toolName: toolName, params: params)

                let toolOutput: String
                do {
                    toolOutput = try await AgentToolBox.shared.execute(toolName, params: params)
                } catch {
                    toolOutput = "Error executing tool \(toolName): \(error.localizedDescription)"
                }

                conversation.append((role: "user", content: "Result of \(toolName):\n\(toolOutput)"))
            }
        }

        if finalSummary.isEmpty {
            finalSummary = "Subtask executed up to turn limit (\(maxTurns) turns)."
        }

        return finalSummary
    }

    /// Finds the index of the next pending subtask whose dependencies have all completed
    private func findNextExecutableSubtaskIndex() -> Int? {
        for (index, subtask) in subtasks.enumerated() {
            guard subtask.status == .pending else { continue }

            let deps = subtask.dependencies
            if deps.isEmpty {
                return index
            }

            let allDepsCompleted = deps.allSatisfy { depId in
                subtasks.first(where: { $0.id == depId })?.status == .completed
            }

            if allDepsCompleted {
                return index
            }

            let anyDepFailedOrSkipped = deps.contains { depId in
                if let dep = subtasks.first(where: { $0.id == depId }) {
                    return dep.status == .failed || dep.status == .skipped
                }
                return false
            }

            if anyDepFailedOrSkipped {
                subtasks[index].status = .skipped
                subtasks[index].result = "Skipped: prerequisite subtask failed or was skipped."
                addTimelineEvent(
                    type: .subtaskCompleted,
                    message: "Subtask '\(subtask.title)' skipped: unmet dependency",
                    subtaskId: subtask.id
                )
            }
        }
        return nil
    }

    /// Marks dependent subtasks as skipped when a prerequisite subtask fails
    private func handleSubtaskFailure(failedIndex: Int) {
        let failedSubtaskId = subtasks[failedIndex].id
        for i in 0..<subtasks.count {
            if subtasks[i].status == .pending && subtasks[i].dependencies.contains(failedSubtaskId) {
                subtasks[i].status = .skipped
                subtasks[i].result = "Skipped: prerequisite '\(subtasks[failedIndex].title)' failed."
                addTimelineEvent(
                    type: .subtaskCompleted,
                    message: "Subtask '\(subtasks[i].title)' skipped due to prior failure",
                    subtaskId: subtasks[i].id
                )
            }
        }
    }

    /// Updates progress metric based on completed and skipped subtasks
    private func updateProgress() {
        guard !subtasks.isEmpty else {
            progress = 0.0
            return
        }
        let completedCount = subtasks.filter { $0.status == .completed || $0.status == .skipped }.count
        progress = Double(completedCount) / Double(subtasks.count)
    }

    /// Appends a timeline event
    private func addTimelineEvent(type: TimelineEvent.EventType, message: String, subtaskId: String? = nil) {
        let event = TimelineEvent(type: type, message: message, subtaskId: subtaskId)
        timeline.append(event)
    }

    /// Records file modifications made by tools for inclusion in checkpoints
    private func trackFileModifications(toolName: String, params: [String: Any]) {
        let modifyingTools: Set<String> = ["file_write", "replace_in_file", "patch_file", "rename_file", "create_directory"]
        guard modifyingTools.contains(toolName) else { return }

        if let path = params["path"] as? String ?? params["filePath"] as? String ?? params["target"] as? String {
            filesModifiedDuringTask.insert(path)
        }
    }

    // MARK: - Plan & Response Parsing Helpers

    /// Parses subtask plan JSON array from LLM response with clean fallbacks
    private func parseSubtaskPlan(from rawText: String) -> [Subtask] {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences if present
        if text.hasPrefix("```json") {
            text = text.replacingOccurrences(of: "```json", with: "")
        }
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```", with: "")
        }
        if text.hasSuffix("```") {
            text = String(text.dropLast(3))
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON array bounds
        if let start = text.range(of: "["),
           let end = text.range(of: "]", options: .backwards) {
            text = String(text[start.lowerBound...end.upperBound])
        }

        if let data = text.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Subtask].self, from: data),
           !decoded.isEmpty {
            return decoded
        }

        // Fallback line-based parser if model returns numbered or bulleted list
        var fallbackSubtasks: [Subtask] = []
        let lines = rawText.components(separatedBy: .newlines)
        var counter = 1

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || (trimmed.first?.isNumber == true && trimmed.contains(".")) {
                let cleanLine = trimmed
                    .replacingOccurrences(of: "^[-*\\d.]+\\s*", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)

                guard !cleanLine.isEmpty else { continue }

                let id = "subtask_\(counter)"
                let dep = counter > 1 ? ["subtask_\(counter - 1)"] : []
                fallbackSubtasks.append(
                    Subtask(
                        id: id,
                        title: cleanLine,
                        description: cleanLine,
                        status: .pending,
                        dependencies: dep
                    )
                )
                counter += 1
            }
        }

        if !fallbackSubtasks.isEmpty {
            return fallbackSubtasks
        }

        // Default single subtask fallback
        return [
            Subtask(
                id: "subtask_1",
                title: "Execute Long-Horizon Task",
                description: rawText.prefix(200).description,
                status: .pending,
                dependencies: []
            )
        ]
    }

    /// Extracts text-based tool calls from LLMs without native function calling
    private func parseTextBasedToolCalls(_ text: String) -> [AIToolCall] {
        var calls: [AIToolCall] = []
        let knownTools = ["file_read", "file_write", "replace_in_file", "grep_search", "list_directory_tree", "shell", "patch_file", "find_symbol"]

        // Pattern: tool_name(key:"value")
        for tool in knownTools {
            let pattern = "\(tool)\\s*\\(([^)]+)\\)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let argsString = nsText.substring(with: match.range(at: 1))
                let args = parseToolArguments(argsString)
                if !args.isEmpty {
                    calls.append(AIToolCall(id: UUID().uuidString, name: tool, arguments: args))
                }
            }
        }

        // Pattern: ```json { "name": "tool_name", "arguments": {...} } ```
        let jsonPattern = "```(?:json)?\\s*\\{[\\s\\S]*?\"name\"\\s*:\\s*\"([^\"]+)\"[\\s\\S]*?\"arguments\"\\s*:\\s*(\\{[^}]+\\})[\\s\\S]*?```"
        if let regex = try? NSRegularExpression(pattern: jsonPattern, options: []) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                guard match.numberOfRanges > 2 else { continue }
                let name = nsText.substring(with: match.range(at: 1))
                let argsStr = nsText.substring(with: match.range(at: 2))
                if knownTools.contains(name),
                   let data = argsStr.data(using: .utf8),
                   let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    calls.append(AIToolCall(id: UUID().uuidString, name: name, arguments: args))
                }
            }
        }

        return calls
    }

    /// Parses key-value pairs from tool call argument string
    private func parseToolArguments(_ argString: String) -> [String: Any] {
        var result: [String: Any] = [:]
        let parts = argString.components(separatedBy: ",")
        for part in parts {
            let pair = part.components(separatedBy: ":")
            if pair.count >= 2 {
                let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
                let val = pair.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
                result[key] = val
            }
        }
        return result
    }

    // MARK: - Checkpoint Disk Storage

    /// Persists checkpoint to Application Support and project folder
    private func saveCheckpointToDisk(checkpoint: Checkpoint, task: HorizonTask) throws {
        let fm = FileManager.default

        // 1. App Support directory
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let checkpointsDir = appSupport.appendingPathComponent("MicroCode/LongHorizonCheckpoints/\(task.id)")
            try fm.createDirectory(at: checkpointsDir, withIntermediateDirectories: true)

            let checkpointURL = checkpointsDir.appendingPathComponent("checkpoint_\(checkpoint.id).json")
            let latestURL = checkpointsDir.appendingPathComponent("latest.json")

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(checkpoint)

            try data.write(to: checkpointURL, options: .atomic)
            try data.write(to: latestURL, options: .atomic)
        }

        // 2. Project directory mirror (if workspace exists)
        if let projectPath = task.projectPath {
            let projectDir = URL(fileURLWithPath: projectPath).appendingPathComponent(".microcode/checkpoints")
            if fm.fileExists(atPath: projectPath) {
                try? fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
                let latestURL = projectDir.appendingPathComponent("latest_checkpoint.json")
                if let data = try? JSONEncoder().encode(checkpoint) {
                    try? data.write(to: latestURL, options: .atomic)
                }
            }
        }
    }
}
