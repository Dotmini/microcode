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
    @Published var currentToolExecution: String? = nil // UI: shows which tool is running
    
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
        
        ## Rules
        1. ALWAYS read a file before modifying it — never guess file contents.
        2. Use grep_search to find relevant code before making changes.
        3. Make minimal, targeted edits using replace_in_file — don't rewrite entire files unless asked.
        4. Explain your reasoning before taking action.
        5. After making changes, verify by reading the modified file.
        6. If a shell command fails, analyze the error and try to fix it.
        7. When the user asks about their project, use list_directory_tree first to understand the structure.
        
        ## Style
        - Be concise and direct. No filler.
        - Show code changes clearly.
        - When uncertain, ask the user before proceeding.
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
        if let chatId = activeChatId {
            let memories = memoryService.recallMemories(query: messages.last?.content ?? "", limit: 3)
            if !memories.isEmpty {
                prompt += "\n\n## Recalled Context\n\(memoryService.formatMemoriesForContext(memories))"
            }
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
        defer { isLoading = false }
        
        let detectedProvider = StreamableAIProvider.detect(from: model)
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
            
            // Execute tool calls
            for toolCall in receivedToolCalls {
                currentToolExecution = "Running \(toolCall.name)..."
                
                do {
                    let output = try await toolBox.execute(toolCall.name, params: toolCall.arguments)
                    
                    allToolResults.append(ToolResultModel(
                        toolCallId: toolCall.id,
                        toolName: toolCall.name,
                        success: true,
                        output: output,
                        error: nil
                    ))
                    
                    // Track file changes
                    if toolCall.name == "file_write" || toolCall.name == "replace_in_file" {
                        if let path = toolCall.arguments["path"] as? String {
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
                    
                    // Add tool result to history for next iteration
                    history.append((role: "assistant", content: streamedText))
                    history.append((role: "user", content: "[Tool Result: \(toolCall.name)]\n\(output)"))
                    
                } catch {
                    allToolResults.append(ToolResultModel(
                        toolCallId: toolCall.id,
                        toolName: toolCall.name,
                        success: false,
                        output: "",
                        error: error.localizedDescription
                    ))
                    
                    history.append((role: "assistant", content: streamedText))
                    history.append((role: "user", content: "[Tool Error: \(toolCall.name)] \(error.localizedDescription)"))
                }
                
                currentToolExecution = nil
            }
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
