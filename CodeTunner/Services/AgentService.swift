//
//  AgentService.swift
//  CodeTunner
//
//  Production AI Agent Service — Unified Pipeline
//  Direct AIClient streaming + AgentToolBox local execution
//  No backend dependency. Pure client-side agent.
//

import SwiftUI
import Combine
import CodeTunnerSupport

// MARK: - Agent Service

@MainActor
class AgentService: ObservableObject {
    static let shared = AgentService()
    
    @Published var messages: [AgentMessageModel] = []
    @Published var isLoading = false
    @Published var pendingChanges: [PendingChangeModel] = []
    @Published var editorContext: EditorContextModel?
    @Published var currentToolExecution: String? = nil
    
    // Real-time Activity Tracking
    @Published var activityLog: [AgentActivity] = []
    @Published var agentPhase: AgentPhase = .idle
    @Published var filesModified: [String] = []
    @Published var suggestedAction: SuggestedAction? = nil
    
    // Workspace Agent Files
    @Published var agentMdContent: String? = nil
    @Published var taskMdContent: String? = nil
    
    // Multi-Chat State
    @Published var chatSessions: [ChatSession] = []
    @Published var activeChatId: String?
    @Published var showChatSidebar: Bool = false
    
    // Services
    private let aiClient = AIClient.shared
    private let toolBox = AgentToolBox.shared
    private let memoryService = AgentMemoryService.shared
    
    private let chatStorageKey = "microcode_agent_chats"
    
    // Agent configuration
    private let maxToolIterations = 10
    private let maxContextChars = 60000
    
    // MARK: - System Prompt
    
    private var systemPrompt: String {
        var prompt = """
        You are MicroCode Agent, a senior full-stack software engineer embedded in the MicroCode IDE.
        You help the user understand, modify, debug, and build software projects.
        
        ## CRITICAL RULES
        1. You MUST take action — read files, WRITE changes, and RUN commands. Never just describe what should be done.
        2. ALWAYS read a file before modifying it — never guess file contents.
        3. Use grep_search to find relevant code before making changes.
        4. Make minimal, targeted edits using replace_in_file — don't rewrite entire files unless asked.
        5. After making changes, verify by reading the modified file or running the project.
        6. If a shell command fails, analyze the error and try to fix it.
        7. When the user asks about their project, use list_directory_tree first to understand the structure.
        
        ## WORKFLOW: When asked to modify code
        Step 1: file_read — read the target file
        Step 2: replace_in_file or file_write — make the actual changes  
        Step 3: shell — compile/run/test to verify
        Step 4: Report what you did
        
        ## WORKFLOW: When asked to run something
        Step 1: shell — execute the command
        Step 2: If it fails, read relevant files and fix the issue
        Step 3: shell — re-run to verify
        
        ## Style
        - Be concise and direct. No filler.
        - Show code changes clearly.
        - When uncertain, ask the user before proceeding.
        - ALWAYS follow through with actual tool calls. Reading is only the first step.
        """
        
        // Inject editor context
        if let ctx = editorContext {
            prompt += "\n\n## Current Editor State"
            if let file = ctx.activeFile { prompt += "\nActive file: \(file)" }
            if let lang = ctx.language { prompt += "\nLanguage: \(lang)" }
            if let line = ctx.cursorLine { prompt += "\nCursor line: \(line)" }
            if let sel = ctx.selectedText, !sel.isEmpty {
                let truncated = sel.count > 2000 ? String(sel.prefix(2000)) + "..." : sel
                prompt += "\nSelected text:\n```\n\(truncated)\n```"
            }
            if !ctx.openFiles.isEmpty {
                prompt += "\nOpen files: \(ctx.openFiles.joined(separator: ", "))"
            }
        }
        
        // Inject workspace info
        if let root = toolBox.workspaceRoot {
            prompt += "\n\nWorkspace root: \(root)"
        }
        
        // Inject semantic context from AuthenticLanguageCore (safely)
        if let smartContext = try? AuthenticLanguageCore.shared()?.aiContext() {
            if let desc = smartContext.llmContextDescription() {
                prompt += "\n\n## Semantic Context\n\(desc)"
            }
        }
        
        // Inject relevant memories
        if let _ = activeChatId {
            let memories = memoryService.recallMemories(query: messages.last?.content ?? "", limit: 3)
            if !memories.isEmpty {
                prompt += "\n\n## Recalled Context\n\(memoryService.formatMemoriesForContext(memories))"
            }
        }
        
        // Inject agent.md instructions if present
        if let agentMd = agentMdContent, !agentMd.isEmpty {
            prompt += "\n\n## Project Agent Instructions (agent.md)\n\(agentMd.prefix(3000))"
        }
        
        // Inject task.md if present
        if let taskMd = taskMdContent, !taskMd.isEmpty {
            prompt += "\n\n## Current Task (task.md)\n\(taskMd.prefix(2000))"
        }
        
        return prompt
    }
    
    // MARK: - Init
    
    init() {
        loadChats()
        if chatSessions.isEmpty {
            let newChat = ChatSession.create(name: "Chat 1")
            chatSessions.append(newChat)
            activeChatId = newChat.id
        } else if activeChatId == nil {
            activeChatId = chatSessions.first?.id
        }
    }
    
    // MARK: - Set Workspace
    
    func setWorkspace(_ path: String) {
        toolBox.workspaceRoot = path
        loadAgentWorkspaceFiles(path)
    }
    
    // MARK: - Load agent.md / task.md / AI.arx
    
    private func loadAgentWorkspaceFiles(_ workspacePath: String) {
        let fm = FileManager.default
        
        // Load agent.md
        let agentMdPath = (workspacePath as NSString).appendingPathComponent("agent.md")
        if fm.fileExists(atPath: agentMdPath) {
            agentMdContent = try? String(contentsOfFile: agentMdPath, encoding: .utf8)
            logActivity(.info, "Loaded agent.md")
        }
        
        // Load task.md
        let taskMdPath = (workspacePath as NSString).appendingPathComponent("task.md")
        if fm.fileExists(atPath: taskMdPath) {
            taskMdContent = try? String(contentsOfFile: taskMdPath, encoding: .utf8)
            logActivity(.info, "Loaded task.md")
        }
        
        // Load or create AI.arx
        loadOrCreateArx(workspacePath)
    }
    
    // MARK: - AI.arx Storage
    
    private func loadOrCreateArx(_ workspacePath: String) {
        let arxPath = (workspacePath as NSString).appendingPathComponent(".microcode/AI.arx")
        let fm = FileManager.default
        
        if !fm.fileExists(atPath: arxPath) {
            // Create .microcode directory and AI.arx
            let dirPath = (workspacePath as NSString).appendingPathComponent(".microcode")
            try? fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
            let arxData = AIArxData(models: [], memory: [], artifacts: [], lastUpdated: Date())
            if let data = try? JSONEncoder().encode(arxData) {
                fm.createFile(atPath: arxPath, contents: data)
                logActivity(.info, "Created AI.arx")
            }
        } else {
            logActivity(.info, "Loaded AI.arx")
        }
    }
    
    func saveArx() {
        guard let root = toolBox.workspaceRoot else { return }
        let arxPath = (root as NSString).appendingPathComponent(".microcode/AI.arx")
        let arxData = AIArxData(
            models: [AIArxData.ModelUsage(provider: "current", model: "active", lastUsed: Date())],
            memory: activityLog.suffix(50).map { AIArxData.MemoryEntry(content: $0.message, timestamp: $0.timestamp, role: "agent") },
            artifacts: filesModified.map { AIArxData.Artifact(path: $0, type: "modified", timestamp: Date()) },
            lastUpdated: Date()
        )
        if let data = try? JSONEncoder().encode(arxData) {
            try? data.write(to: URL(fileURLWithPath: arxPath))
        }
    }
    
    // MARK: - Send Message (Production Agentic Loop)
    
    func sendMessage(
        _ content: String,
        provider: String = "gemini",
        model: String = "gemini-2.5-flash",
        apiKey: String = "",
        attachments: [AIAttachment] = []
    ) async {
        // Add user message
        let userMessage = AgentMessageModel(
            id: UUID().uuidString, role: .user, content: content,
            toolResults: [], pendingChanges: [], timestamp: Date()
        )
        messages.append(userMessage)
        
        // Store memory
        if let chatId = activeChatId {
            memoryService.storeMemory(content: content, chatId: chatId, role: "user")
        }
        
        isLoading = true
        agentPhase = .thinking
        filesModified = []
        suggestedAction = nil
        logActivity(.thinking, "Processing request...")
        defer {
            isLoading = false
            agentPhase = .idle
            saveArx()
        }
        
        let detectedProvider = StreamableAIProvider(rawValue: provider) ?? StreamableAIProvider.detect(from: model)
        let toolSchemas = toolBox.toolSchemas()
        
        // Build conversation history for API
        var history = buildConversationHistory()
        
        // === Agentic Tool Loop ===
        var iteration = 0
        var finalText = ""
        var allToolResults: [ToolResultModel] = []
        var allChanges: [PendingChangeModel] = []
        
        while iteration < maxToolIterations {
            iteration += 1
            
            // Stream the response
            var streamedText = ""
            var receivedToolCalls: [AIToolCall] = []
            
            // Use streaming for first iteration (user sees thinking), sync for subsequent
            if iteration == 1 {
                // Streaming mode — user sees tokens in real-time
                let result = await withCheckedContinuation { (continuation: CheckedContinuation<(String, [AIToolCall]), Never>) in
                    var toolCalls: [AIToolCall] = []
                    var text = ""
                    
                    aiClient.sendMessage(
                        prompt: content,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: history,
                        provider: detectedProvider,
                        model: model,
                        apiKey: apiKey,
                        tools: toolSchemas,
                        onToken: { token in
                            text += token
                            // Update the last message in real-time (streaming effect)
                            self.updateStreamingMessage(text, toolResults: allToolResults)
                        },
                        onToolCall: { toolCall in
                            toolCalls.append(toolCall)
                        },
                        onComplete: { fullText in
                            continuation.resume(returning: (fullText, toolCalls))
                        },
                        onError: { error in
                            continuation.resume(returning: ("Error: \(error)", []))
                        }
                    )
                }
                streamedText = result.0
                receivedToolCalls = result.1
            } else {
                // Non-streaming for tool result follow-ups
                do {
                    // Build messages array with tool results
                    let syncMessages = buildSyncMessages(history: history, lastText: finalText, toolResults: allToolResults)
                    let result = try await aiClient.sendSync(
                        messages: syncMessages,
                        systemPrompt: systemPrompt,
                        provider: detectedProvider,
                        model: model,
                        apiKey: apiKey,
                        tools: toolSchemas
                    )
                    streamedText = result.text
                    receivedToolCalls = result.toolCalls
                    
                    updateStreamingMessage(streamedText, toolResults: allToolResults)
                } catch {
                    streamedText = "Error in tool loop iteration \(iteration): \(error.localizedDescription)"
                    break
                }
            }
            
            finalText = streamedText
            
            // If no tool calls, we're done
            if receivedToolCalls.isEmpty { break }
            
            // Execute ALL tool calls in this batch
            var batchResults: [(name: String, output: String, success: Bool)] = []
            
            for toolCall in receivedToolCalls {
                currentToolExecution = "Running \(toolCall.name)..."
                agentPhase = .executing(toolCall.name)
                logActivity(.tool, "\(toolCall.name)", detail: truncateArgs(toolCall.arguments))
                do {
                    let output = try await toolBox.execute(toolCall.name, params: toolCall.arguments)
                    
                    allToolResults.append(ToolResultModel(
                        toolCallId: toolCall.id,
                        toolName: toolCall.name,
                        success: true,
                        output: output,
                        error: nil
                    ))
                    
                    batchResults.append((name: toolCall.name, output: output, success: true))
                    logActivity(.success, "\(toolCall.name) ✓")
                    
                    // Track file changes
                    if toolCall.name == "file_write" || toolCall.name == "replace_in_file" {
                        if let path = toolCall.arguments["path"] as? String {
                            filesModified.append(path)
                            logActivity(.fileChange, "Modified: \(URL(fileURLWithPath: path).lastPathComponent)")
                            allChanges.append(PendingChangeModel(
                                id: UUID().uuidString,
                                filePath: path,
                                description: "Modified by \(toolCall.name)",
                                additions: 0, deletions: 0,
                                oldContent: "", newContent: "",
                                status: .accepted
                            ))
                        }
                    }
                    
                } catch {
                    allToolResults.append(ToolResultModel(
                        toolCallId: toolCall.id,
                        toolName: toolCall.name,
                        success: false,
                        output: "",
                        error: error.localizedDescription
                    ))
                    
                    batchResults.append((name: toolCall.name, output: error.localizedDescription, success: false))
                    logActivity(.error, "\(toolCall.name) failed: \(error.localizedDescription)")
                }
                
                currentToolExecution = nil
            }
            
            // Add assistant message ONCE per iteration (not per tool call)
            history.append((role: "assistant", content: streamedText))
            
            // Aggregate all tool results into ONE follow-up message
            let resultsText = batchResults.map { r in
                r.success
                    ? "✅ \(r.name) completed:\n\(r.output)"
                    : "❌ \(r.name) failed: \(r.output)"
            }.joined(separator: "\n\n---\n\n")
            
            history.append((role: "user", content: """
            Tool execution results:
            
            \(resultsText)
            
            Now continue with the task. If you have read the files, proceed to make the requested changes using file_write or replace_in_file, then run any commands using shell. Do NOT just describe what to do — actually do it.
            """))
        }
        
        // Finalize the assistant message
        let assistantMessage = AgentMessageModel(
            id: UUID().uuidString, role: .assistant, content: finalText,
            toolResults: allToolResults, pendingChanges: allChanges, timestamp: Date()
        )
        
        // Replace streaming placeholder with final
        if let lastIdx = messages.indices.last, messages[lastIdx].role == .assistant {
            messages[lastIdx] = assistantMessage
        } else {
            messages.append(assistantMessage)
        }
        
        pendingChanges.append(contentsOf: allChanges)
        
        // Generate post-completion suggestion
        if !filesModified.isEmpty {
            suggestedAction = SuggestedAction(
                title: "Run Project?",
                icon: "play.circle.fill",
                description: "\(filesModified.count) file(s) modified. Run to verify changes?"
            )
        }
        
        logActivity(.done, "Completed (\(iteration) iterations, \(allToolResults.count) tools)")
        agentPhase = .done
        
        // Store memory
        if let chatId = activeChatId {
            memoryService.storeMemory(content: finalText, chatId: chatId, role: "assistant")
        }
        
        saveChats()
    }
    
    // MARK: - Streaming Message Update
    
    private func updateStreamingMessage(_ text: String, toolResults: [ToolResultModel]) {
        let streamMsg = AgentMessageModel(
            id: "streaming", role: .assistant, content: text,
            toolResults: toolResults, pendingChanges: [], timestamp: Date()
        )
        
        if let lastIdx = messages.indices.last, messages[lastIdx].id == "streaming" {
            messages[lastIdx] = streamMsg
        } else {
            messages.append(streamMsg)
        }
    }
    
    // MARK: - History Building
    
    private func buildConversationHistory() -> [(role: String, content: String)] {
        let recent = Array(messages.suffix(20))
        return recent.compactMap { msg -> (role: String, content: String)? in
            switch msg.role {
            case .user: return (role: "user", content: msg.content)
            case .assistant: return (role: "assistant", content: String(msg.content.prefix(maxContextChars)))
            case .system, .tool: return nil
            }
        }
    }
    
    private func buildSyncMessages(history: [(role: String, content: String)], lastText: String, toolResults: [ToolResultModel]) -> [[(String, Any)]] {
        var msgs: [[(String, Any)]] = []
        
        for h in history {
            msgs.append([("_role", h.role), ("text", h.content)])
        }
        
        // Add tool results context
        if !toolResults.isEmpty {
            let resultsText = toolResults.map { r in
                r.success ? "[\(r.toolName)] ✅: \(r.output)" : "[\(r.toolName)] ❌: \(r.error ?? "unknown error")"
            }.joined(separator: "\n")
            msgs.append([("_role", "user"), ("text", "Tool results:\n\(resultsText)\n\nContinue with the task based on these results.")])
        }
        
        return msgs
    }
    
    // MARK: - Pending Changes
    
    func applyChange(_ changeId: String) {
        if let idx = pendingChanges.firstIndex(where: { $0.id == changeId }) {
            pendingChanges[idx].status = .accepted
        }
    }
    
    func rejectChange(_ changeId: String) {
        if let idx = pendingChanges.firstIndex(where: { $0.id == changeId }) {
            pendingChanges[idx].status = .rejected
        }
    }
    
    // MARK: - Editor Context
    
    func updateEditorContext(activeFile: String?, content: String?, cursorLine: Int?, selectedText: String?, openFiles: [String] = [], language: String? = nil) {
        editorContext = EditorContextModel(
            activeFile: activeFile,
            activeContent: content,
            cursorLine: cursorLine,
            cursorColumn: nil,
            selectedText: selectedText,
            openFiles: openFiles,
            language: language
        )
    }
    
    // MARK: - Multi-Chat Management
    
    func createNewChat(name: String? = nil) -> ChatSession {
        let chatName = name ?? "Chat \(chatSessions.count + 1)"
        let newChat = ChatSession.create(name: chatName)
        chatSessions.insert(newChat, at: 0)
        activeChatId = newChat.id
        messages = []
        saveChats()
        return newChat
    }
    
    func switchChat(to chatId: String) {
        guard let chat = chatSessions.first(where: { $0.id == chatId }) else { return }
        saveCurrentChatMessages()
        activeChatId = chatId
        messages = chat.messages.map { $0.toModel() }
    }
    
    func deleteChat(_ chatId: String) {
        chatSessions.removeAll { $0.id == chatId }
        if activeChatId == chatId {
            if let firstChat = chatSessions.first {
                switchChat(to: firstChat.id)
            } else {
                let newChat = createNewChat()
                activeChatId = newChat.id
            }
        }
        saveChats()
    }
    
    func clearCurrentChat() {
        messages.removeAll()
        saveCurrentChatMessages()
    }
    
    func renameChat(_ chatId: String, to newName: String) {
        if let idx = chatSessions.firstIndex(where: { $0.id == chatId }) {
            chatSessions[idx].name = newName
            saveChats()
        }
    }
    
    // MARK: - Persistence
    
    private func saveCurrentChatMessages() {
        guard let activeId = activeChatId,
              let idx = chatSessions.firstIndex(where: { $0.id == activeId }) else { return }
        chatSessions[idx].messages = messages.map { AgentMessageData.from($0) }
        chatSessions[idx].updatedAt = Date()
        saveChats()
    }
    
    func saveChats() {
        if let activeId = activeChatId,
           let idx = chatSessions.firstIndex(where: { $0.id == activeId }) {
            chatSessions[idx].messages = messages.map { AgentMessageData.from($0) }
            chatSessions[idx].updatedAt = Date()
        }
        if let data = try? JSONEncoder().encode(chatSessions) {
            UserDefaults.standard.set(data, forKey: chatStorageKey)
        }
    }
    
    func loadChats() {
        guard let data = UserDefaults.standard.data(forKey: chatStorageKey),
              let chats = try? JSONDecoder().decode([ChatSession].self, from: data) else { return }
        chatSessions = chats
        if let activeId = activeChatId,
           let chat = chatSessions.first(where: { $0.id == activeId }) {
            messages = chat.messages.map { $0.toModel() }
        }
    }
    
    // MARK: - Activity Logging
    
    func logActivity(_ type: AgentActivity.ActivityType, _ message: String, detail: String? = nil) {
        let activity = AgentActivity(type: type, message: message, detail: detail, timestamp: Date())
        activityLog.append(activity)
        // Keep last 100 entries
        if activityLog.count > 100 {
            activityLog.removeFirst(activityLog.count - 100)
        }
    }
    
    private func truncateArgs(_ args: [String: Any]) -> String {
        let keys = args.keys.sorted()
        let parts = keys.prefix(3).map { key -> String in
            let val = args[key]
            let str = "\(val ?? "nil")"
            return "\(key)=\(str.prefix(50))"
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Agent Activity Model

struct AgentActivity: Identifiable {
    let id = UUID()
    let type: ActivityType
    let message: String
    let detail: String?
    let timestamp: Date
    
    enum ActivityType {
        case thinking, tool, success, error, fileChange, info, done
        
        var icon: String {
            switch self {
            case .thinking: return "brain"
            case .tool: return "wrench.and.screwdriver"
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .fileChange: return "doc.badge.arrow.up"
            case .info: return "info.circle"
            case .done: return "flag.checkered"
            }
        }
        
        var color: Color {
            switch self {
            case .thinking: return .purple
            case .tool: return .blue
            case .success: return .green
            case .error: return .red
            case .fileChange: return .orange
            case .info: return .secondary
            case .done: return .green
            }
        }
    }
}

// MARK: - Agent Phase

enum AgentPhase: Equatable {
    case idle
    case thinking
    case executing(String) // tool name
    case done
    
    static func == (lhs: AgentPhase, rhs: AgentPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.thinking, .thinking), (.done, .done): return true
        case (.executing(let a), .executing(let b)): return a == b
        default: return false
        }
    }
    
    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .thinking: return "Thinking..."
        case .executing(let tool): return "Running \(tool)"
        case .done: return "Done"
        }
    }
    
    var icon: String {
        switch self {
        case .idle: return "circle"
        case .thinking: return "brain"
        case .executing: return "gearshape.2.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .idle: return .secondary
        case .thinking: return .purple
        case .executing: return .blue
        case .done: return .green
        }
    }
}

// MARK: - Suggested Action

struct SuggestedAction {
    let title: String
    let icon: String
    let description: String
}

// MARK: - AI.arx Data Model

struct AIArxData: Codable {
    var models: [ModelUsage]
    var memory: [MemoryEntry]
    var artifacts: [Artifact]
    var lastUpdated: Date
    
    struct ModelUsage: Codable {
        let provider: String
        let model: String
        let lastUsed: Date
    }
    
    struct MemoryEntry: Codable {
        let content: String
        let timestamp: Date
        let role: String
    }
    
    struct Artifact: Codable {
        let path: String
        let type: String
        let timestamp: Date
    }
}

// MARK: - Models

struct ChatSession: Identifiable, Codable {
    let id: String
    var name: String
    var messages: [AgentMessageData]
    var createdAt: Date
    var updatedAt: Date
    
    static func create(name: String = "New Chat") -> ChatSession {
        ChatSession(id: UUID().uuidString, name: name, messages: [], createdAt: Date(), updatedAt: Date())
    }
}

struct AgentMessageData: Codable, Identifiable {
    let id: String
    let role: String
    let content: String
    let timestamp: Date
    
    static func from(_ model: AgentMessageModel) -> AgentMessageData {
        AgentMessageData(id: model.id, role: model.role.rawValue, content: model.content, timestamp: model.timestamp)
    }
    
    func toModel() -> AgentMessageModel {
        AgentMessageModel(
            id: id,
            role: AgentMessageModel.MessageRole(rawValue: role) ?? .assistant,
            content: content, toolResults: [], pendingChanges: [], timestamp: timestamp
        )
    }
}

struct AgentMessageModel: Identifiable {
    let id: String
    let role: MessageRole
    let content: String
    let toolResults: [ToolResultModel]
    let pendingChanges: [PendingChangeModel]
    let timestamp: Date
    
    enum MessageRole: String, Codable {
        case user, assistant, system, tool
    }
}

struct ToolResultModel {
    let toolCallId: String
    let toolName: String
    let success: Bool
    let output: String
    let error: String?
}

struct PendingChangeModel: Identifiable {
    let id: String
    let filePath: String
    let description: String
    let additions: Int
    let deletions: Int
    let oldContent: String
    let newContent: String
    var status: PendingChangeStatus
    
    enum PendingChangeStatus {
        case pending, accepted, rejected
    }
}

struct EditorContextModel {
    let activeFile: String?
    let activeContent: String?
    let cursorLine: Int?
    let cursorColumn: Int?
    let selectedText: String?
    let openFiles: [String]
    let language: String?
}

struct ProjectContextModel: Codable {
    let root_path: String
    let project_type: String
    let files: [FileInfoModel]?
    let recent_files: [String]?
}

struct FileInfoModel: Codable {
    let path: String
    let relative_path: String
    let size: Int
    let is_directory: Bool
}

struct ToolDefinitionModel: Codable, Identifiable {
    var id: String { name }
    let name: String
    let description: String
}

