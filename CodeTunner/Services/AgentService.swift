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
    
    // Stop / Cancel
    @Published var isCancelled = false
    
    // Message Queue — send follow-ups while AI is working
    @Published var messageQueue: [QueuedMessage] = []
    @Published var isProcessingQueue = false
    
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
    
    // Model selection
    @Published var selectedModel: String = ""
    
    // Services
    private let aiClient = AIClient.shared
    private let toolBox = AgentToolBox.shared
    private let memoryService = AgentMemoryService.shared
    private let tokenOptimizer = TokenOptimizer.shared
    
    private let chatStorageKey = "microcode_agent_chats"
    
    // Agent configuration
    private let maxToolIterations = 25
    private let maxContextChars = 80000
    
    // Token stats (read from optimizer)
    var tokenStats: TokenUsageStats { tokenOptimizer.stats }
    
    // MARK: - Stop Generation
    
    func stopGeneration() {
        isCancelled = true
        isLoading = false
        agentPhase = .idle
        currentToolExecution = nil
        logActivity(.info, "Generation stopped by user")
        
        // Append stop marker to last AI message
        if let lastIdx = messages.lastIndex(where: { $0.role == .assistant }) {
            let current = messages[lastIdx].content
            messages[lastIdx] = AgentMessageModel(
                id: messages[lastIdx].id, role: .assistant,
                content: current + "\n\n⏹ *Generation stopped*",
                toolResults: messages[lastIdx].toolResults,
                pendingChanges: messages[lastIdx].pendingChanges,
                timestamp: messages[lastIdx].timestamp
            )
        }
        
        // Process next in queue if any
        processQueue()
    }
    
    // MARK: - Message Queue
    
    func enqueueMessage(_ text: String, attachments: [AIAttachment] = []) {
        messageQueue.append(QueuedMessage(text: text, attachments: attachments))
        if !isLoading {
            processQueue()
        }
    }
    
    func processQueue() {
        guard !messageQueue.isEmpty, !isLoading else { return }
        let next = messageQueue.removeFirst()
        isProcessingQueue = !messageQueue.isEmpty
        
        // This will be called from AIAgentView.sendMessage with proper context
        NotificationCenter.default.post(name: .agentProcessQueueItem, object: next)
    }
    
    // MARK: - System Prompt (Dual Mode: Chat + Agent)
    
    private func buildSystemPrompt(for message: String) -> String {
        let complexity = tokenOptimizer.detectComplexity(message)
        let budget = TokenBudget.forTask(complexity)
        let isChatMode = complexity == .chat
        
        var prompt: String
        
        if isChatMode {
            // CHAT MODE: Professional, knowledgeable conversationalist
            prompt = """
            You are MicroCode AI — a professional software engineering assistant integrated into the MicroCode IDE.
            
            ## Communication Style
            - Maintain a professional, clear, and authoritative tone at all times.
            - Provide well-structured, accurate, and insightful responses.
            - Use precise technical terminology when discussing software engineering topics.
            - When the user writes in Thai, respond in Thai. When in English, respond in English.
            - Be thorough but concise — avoid unnecessary filler or overly casual language.
            - If the conversation shifts to coding, transition seamlessly into engineering mode.
            
            ## Capabilities
            - Deep expertise across all major programming languages and frameworks.
            - Architecture design, system analysis, and best practices guidance.
            - General knowledge discussions with the same professional standard.
            """
        } else {
            // AGENT MODE: Senior engineer with tools
            prompt = """
            You are MicroCode AI — a senior full-stack software engineer integrated into the MicroCode IDE.
            Your role is to help the user understand, modify, debug, and build production-quality software.
            
            ## Communication Style
            - Professional, authoritative, and precise.
            - Use structured output: headings, bullet points, and code blocks.
            - When the user writes in Thai, respond in Thai. When in English, respond in English.
            - Be direct. No filler. Lead with the most important information.
            
            ## Rules
            1. Take action — read files, WRITE changes, RUN commands. Don't just describe.
            2. Read a file before modifying it.
            3. Use grep_search to find relevant code before making changes.
            4. Make minimal, targeted edits using replace_in_file or patch_file.
            5. After changes, verify by reading the modified file or running the project.
            6. If a command fails, analyze the error and fix it immediately.
            7. Use list_directory_tree to understand project structure.
            8. Use multi_file_read to read multiple files efficiently.
            9. Use find_symbol to locate function/class definitions.
            10. For multi-file changes, use patch_file for efficiency.
            
            ## Workflow: Modify Code
            1. file_read → 2. replace_in_file/patch_file → 3. shell (verify) → 4. Report
            
            ## Workflow: Create Project
            1. list_directory_tree → 2. create_directory → 3. file_write (multiple) → 4. shell (install/build)
            
            ## Output Quality
            - Show code changes clearly with before/after context.
            - When uncertain, ask for clarification before proceeding.
            - ALWAYS follow through with tool calls — never leave work incomplete.
            """
        }
        
        // Inject editor context (compressed)
        if !isChatMode, let ctx = editorContext {
            var editorInfo = "\n\n## Editor"
            if let file = ctx.activeFile { editorInfo += "\nFile: \(file)" }
            if let lang = ctx.language { editorInfo += " (\(lang))" }
            if let line = ctx.cursorLine { editorInfo += " L\(line)" }
            if let sel = ctx.selectedText, !sel.isEmpty {
                let compressed = tokenOptimizer.compressFileContent(sel, query: message, budget: 500)
                editorInfo += "\nSelected:\n```\n\(compressed)\n```"
            }
            if !ctx.openFiles.isEmpty {
                editorInfo += "\nOpen: \(ctx.openFiles.suffix(5).map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "))"
            }
            prompt += editorInfo
        }
        
        // Workspace root
        if let root = toolBox.workspaceRoot {
            prompt += "\n\nWorkspace: \(root)"
        }
        
        // Inject semantic context (if available)
        if !isChatMode {
            if let smartContext = try? AuthenticLanguageCore.shared()?.aiContext() {
                if let desc = smartContext.llmContextDescription() {
                    let compressed = tokenOptimizer.compressText(desc, targetTokens: 500)
                    prompt += "\n\n## Semantic Context\n\(compressed)"
                }
            }
        }
        
        // Inject relevant memories (with cross-chat recall)
        if let chatId = activeChatId {
            let currentChatMemories = memoryService.recallMemories(query: message, limit: 2, includeCurrentChat: true)
            let crossChatMemories = memoryService.recallCrossChatMemories(query: message, currentChatId: chatId, limit: 2)
            let allMemories = currentChatMemories + crossChatMemories
            if !allMemories.isEmpty {
                prompt += "\n\n## Memory\n\(memoryService.formatMemoriesForContext(allMemories, maxTokens: budget.maxContextTokens / 4))"
            }
        }
        
        // Inject agent.md (compressed)
        if !isChatMode, let agentMd = agentMdContent, !agentMd.isEmpty {
            let compressed = tokenOptimizer.compressText(agentMd, targetTokens: 800)
            prompt += "\n\n## agent.md\n\(compressed)"
        }
        
        // Inject task.md (compressed)
        if !isChatMode, let taskMd = taskMdContent, !taskMd.isEmpty {
            let compressed = tokenOptimizer.compressText(taskMd, targetTokens: 500)
            prompt += "\n\n## task.md\n\(compressed)"
        }
        
        // Apply final compression to system prompt
        return tokenOptimizer.compressSystemPrompt(prompt, budget: budget.maxSystemTokens)
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
        
        // Create .microcode directory
        let microcodeDir = (workspacePath as NSString).appendingPathComponent(".microcode")
        if !fm.fileExists(atPath: microcodeDir) {
            try? fm.createDirectory(atPath: microcodeDir, withIntermediateDirectories: true)
        }
        
        // Load or create agent.md
        let agentMdPath = (microcodeDir as NSString).appendingPathComponent("agent.md")
        if fm.fileExists(atPath: agentMdPath) {
            agentMdContent = try? String(contentsOfFile: agentMdPath, encoding: .utf8)
            logActivity(.info, "Loaded agent.md")
        } else {
            let defaultAgentMd = """
            # Agent Instructions
            
            ## Project Context
            This file provides project-level instructions to the MicroCode AI Agent.
            Edit this file to customize how the agent behaves in this workspace.
            
            ## Rules
            - Follow existing code style and conventions
            - Write tests for new features
            - Use descriptive commit messages
            
            ## Tech Stack
            <!-- Add your project's tech stack here -->
            
            ## Important Files
            <!-- List key files the agent should know about -->
            """
            try? defaultAgentMd.write(toFile: agentMdPath, atomically: true, encoding: .utf8)
            agentMdContent = defaultAgentMd
            logActivity(.info, "Created agent.md")
        }
        
        // Load or create task.md
        let taskMdPath = (microcodeDir as NSString).appendingPathComponent("task.md")
        if fm.fileExists(atPath: taskMdPath) {
            taskMdContent = try? String(contentsOfFile: taskMdPath, encoding: .utf8)
            logActivity(.info, "Loaded task.md")
        } else {
            let defaultTaskMd = """
            # Current Task
            
            ## Objective
            <!-- Describe the current task here -->
            
            ## Steps
            - [ ] Step 1
            - [ ] Step 2
            - [ ] Step 3
            
            ## Notes
            <!-- Any additional context for the AI agent -->
            """
            try? defaultTaskMd.write(toFile: taskMdPath, atomically: true, encoding: .utf8)
            taskMdContent = defaultTaskMd
            logActivity(.info, "Created task.md")
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
        isCancelled = false
        agentPhase = .thinking
        filesModified = []
        suggestedAction = nil
        logActivity(.thinking, "Processing request...")
        defer {
            isLoading = false
            agentPhase = .idle
            saveArx()
            objectWillChange.send()
            // Auto-process queue
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                self.processQueue()
            }
        }
        
        // Detect task complexity and choose budget
        let complexity = tokenOptimizer.detectComplexity(content)
        let budget = TokenBudget.forTask(complexity)
        let isChatMode = complexity == .chat
        
        let detectedProvider = StreamableAIProvider(rawValue: provider) ?? StreamableAIProvider.detect(from: model)
        let toolSchemas = isChatMode ? [] : toolBox.toolSchemas()  // No tools in chat mode
        
        // Build optimized system prompt
        let optimizedSystemPrompt = buildSystemPrompt(for: content)
        
        // Build and compress conversation history
        var rawHistory = buildConversationHistory()
        var history = tokenOptimizer.compressHistory(rawHistory, budget: budget.maxHistoryTokens)
        
        logActivity(.info, "Mode: \(isChatMode ? "Chat" : "Agent") | Budget: \(budget.totalBudget) tokens")
        
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
                        systemPrompt: optimizedSystemPrompt,
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
                        systemPrompt: optimizedSystemPrompt,
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
            
            // If no native tool calls, try to parse text-based tool calls (for local LLMs)
            if receivedToolCalls.isEmpty {
                let parsedCalls = parseTextBasedToolCalls(streamedText)
                if !parsedCalls.isEmpty {
                    receivedToolCalls = parsedCalls
                    logActivity(.info, "Parsed \(parsedCalls.count) tool call(s) from text output")
                }
            }
            
            // If still no tool calls, we're done
            if receivedToolCalls.isEmpty { break }
            
            // Execute ALL tool calls in this batch
            var batchResults: [(name: String, output: String, success: Bool)] = []
            
            for toolCall in receivedToolCalls {
                currentToolExecution = "Running \(toolCall.name)..."
                agentPhase = .executing(toolCall.name)
                logActivity(.tool, "\(toolCall.name)", detail: truncateArgs(toolCall.arguments))
                
                // Capture old content for diff BEFORE execution
                var oldContent: String? = nil
                if (toolCall.name == "file_write" || toolCall.name == "replace_in_file"),
                   let path = toolCall.arguments["path"] as? String {
                    oldContent = try? String(contentsOfFile: path, encoding: .utf8)
                }
                
                do {
                    var output = try await toolBox.execute(toolCall.name, params: toolCall.arguments)
                    
                    // Compress tool output to save tokens
                    output = tokenOptimizer.compressToolOutput(output, toolName: toolCall.name, budget: 2000)
                    
                    allToolResults.append(ToolResultModel(
                        toolCallId: toolCall.id,
                        toolName: toolCall.name,
                        success: true,
                        output: output,
                        error: nil
                    ))
                    
                    batchResults.append((name: toolCall.name, output: output, success: true))
                    logActivity(.success, "\(toolCall.name) ✓")
                    
                    // Track file changes with diff
                    if toolCall.name == "file_write" || toolCall.name == "replace_in_file" {
                        if let path = toolCall.arguments["path"] as? String {
                            filesModified.append(path)
                            
                            // Read new content for diff
                            let newContent = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                            let old = oldContent ?? ""
                            
                            // Compute additions/deletions
                            let oldLines = old.components(separatedBy: "\n")
                            let newLines = newContent.components(separatedBy: "\n")
                            let additions = max(0, newLines.count - oldLines.count)
                            let deletions = max(0, oldLines.count - newLines.count)
                            
                            logActivity(.fileChange, "Modified: \(URL(fileURLWithPath: path).lastPathComponent) (+\(additions) -\(deletions))")
                            allChanges.append(PendingChangeModel(
                                id: UUID().uuidString,
                                filePath: path,
                                description: "Modified by \(toolCall.name)",
                                additions: additions, deletions: deletions,
                                oldContent: String(old.suffix(5000)), newContent: String(newContent.suffix(5000)),
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
        
        // Update token stats
        let inputTokens = tokenOptimizer.estimateTokens(optimizedSystemPrompt) + history.reduce(0) { $0 + tokenOptimizer.estimateTokens($1.content) }
        let outputTokens = tokenOptimizer.estimateTokens(finalText)
        tokenOptimizer.stats.inputTokens += inputTokens
        tokenOptimizer.stats.outputTokens += outputTokens
        tokenOptimizer.stats.totalRequests += 1
        tokenOptimizer.stats.totalCost += tokenOptimizer.estimateCost(inputTokens: inputTokens, outputTokens: outputTokens, model: model)
        tokenOptimizer.stats.compressionRatio = Double(tokenOptimizer.stats.savedTokens) / max(1, Double(tokenOptimizer.stats.inputTokens + tokenOptimizer.stats.savedTokens))
        
        logActivity(.done, "Completed (\(iteration) iterations, \(allToolResults.count) tools, ~\(inputTokens + outputTokens) tokens)")
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
        
        // Summarize current chat before switching (if it has enough messages)
        if let currentId = activeChatId, messages.count > 6 {
            let chatMessages = messages
                .filter { $0.role == .user || $0.role == .assistant }
                .map { (role: $0.role.rawValue, content: $0.content) }
            memoryService.summarizeChat(chatId: currentId, messages: chatMessages)
        }
        
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
    
    // MARK: - Text-Based Tool Call Parser (for Local LLMs)
    // Local models (Gemma, Llama, etc.) don't support native function calling.
    // They output tool calls as text like: list_directory_tree(path:".")
    // This parser extracts those into executable AIToolCall objects.
    
    private func parseTextBasedToolCalls(_ text: String) -> [AIToolCall] {
        var calls: [AIToolCall] = []
        let knownTools = ["file_read", "file_write", "replace_in_file", "grep_search", "list_directory_tree", "shell"]
        
        // Pattern 1: tool_name(key:"value", key2:"value2")
        // Also handles <|"> tokens from some models
        for tool in knownTools {
            let pattern = "\(tool)\\s*\\(([^)]+)\\)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            
            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let argsString = nsText.substring(with: match.range(at: 1))
                let args = parseToolArgs(argsString, toolName: tool)
                if !args.isEmpty {
                    calls.append(AIToolCall(id: UUID().uuidString, name: tool, arguments: args))
                }
            }
        }
        
        // Pattern 2: ```json { "name": "tool_name", "arguments": {...} } ```
        let jsonBlockPattern = "```(?:json)?\\s*\\{[\\s\\S]*?\"name\"\\s*:\\s*\"([^\"]+)\"[\\s\\S]*?\"arguments\"\\s*:\\s*(\\{[^}]+\\})[\\s\\S]*?```"
        if let regex = try? NSRegularExpression(pattern: jsonBlockPattern, options: []) {
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
        
        // Pattern 3: <tool_call> JSON </tool_call>
        let xmlPattern = "<tool_call>\\s*(\\{[\\s\\S]*?\\})\\s*</tool_call>"
        if let regex = try? NSRegularExpression(pattern: xmlPattern, options: []) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let jsonStr = nsText.substring(with: match.range(at: 1))
                if let data = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let name = json["name"] as? String,
                   let args = json["arguments"] as? [String: Any],
                   knownTools.contains(name) {
                    calls.append(AIToolCall(id: UUID().uuidString, name: name, arguments: args))
                }
            }
        }
        
        return calls
    }
    
    private func parseToolArgs(_ argsString: String, toolName: String) -> [String: Any] {
        var args: [String: Any] = [:]
        
        // Clean up token artifacts like <|"> or <|'>
        let cleaned = argsString
            .replacingOccurrences(of: "<|\"", with: "")
            .replacingOccurrences(of: "\"|>", with: "")
            .replacingOccurrences(of: "<|'>", with: "")
            .replacingOccurrences(of: "'|>", with: "")
            .replacingOccurrences(of: "<|", with: "")
            .replacingOccurrences(of: "|>", with: "")
        
        // Parse key:value or key="value" or key:'value' pairs
        let kvPattern = "(\\w+)\\s*[:=]\\s*(?:\"([^\"]*)\"|'([^']*)'|([^,)]+))"
        guard let regex = try? NSRegularExpression(pattern: kvPattern, options: []) else { return args }
        let nsStr = cleaned as NSString
        let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: nsStr.length))
        
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let key = nsStr.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            var value = ""
            for i in 2...min(4, match.numberOfRanges - 1) {
                let range = match.range(at: i)
                if range.location != NSNotFound {
                    value = nsStr.substring(with: range).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            if !key.isEmpty && !value.isEmpty {
                args[key] = value
            }
        }
        
        // For simple single-arg tools, infer the key
        if args.isEmpty {
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !trimmed.isEmpty {
                switch toolName {
                case "file_read", "list_directory_tree": args["path"] = trimmed
                case "grep_search": args["pattern"] = trimmed
                case "shell": args["command"] = trimmed
                default: break
                }
            }
        }
        
        return args
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

// MARK: - Queue Model

struct QueuedMessage {
    let id = UUID()
    let text: String
    let attachments: [AIAttachment]
    let timestamp = Date()
}

extension Notification.Name {
    static let agentProcessQueueItem = Notification.Name("agentProcessQueueItem")
}
