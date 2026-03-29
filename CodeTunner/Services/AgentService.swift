import SwiftUI
import Combine
import CodeTunnerSupport

// MARK: - BMAD Agent Roles

enum BMadAgentRole: String, CaseIterable, Identifiable {
    case pm = "PM"
    case architect = "Architect"
    case developer = "Developer"
    case uxDesigner = "UX Designer"
    case qa = "QA Engineer"
    case devops = "DevOps"
    case analyst = "Analyst"
    case docWriter = "Doc Writer"
    case reviewer = "Reviewer"
    case mentor = "Mentor"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .pm: return "person.badge.clock"
        case .architect: return "building.2"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .uxDesigner: return "paintbrush"
        case .qa: return "checkmark.shield"
        case .devops: return "gearshape.2"
        case .analyst: return "chart.bar.xaxis"
        case .docWriter: return "doc.text"
        case .reviewer: return "eye"
        case .mentor: return "graduationcap"
        }
    }
    
    var color: Color {
        switch self {
        case .pm: return .blue
        case .architect: return .purple
        case .developer: return .green
        case .uxDesigner: return .pink
        case .qa: return .orange
        case .devops: return .cyan
        case .analyst: return .indigo
        case .docWriter: return .mint
        case .reviewer: return .yellow
        case .mentor: return .teal
        }
    }
    
    var description: String {
        switch self {
        case .pm: return "Requirements, PRD, user stories"
        case .architect: return "System design, tech stack"
        case .developer: return "Code implementation"
        case .uxDesigner: return "Interface design, wireframes"
        case .qa: return "Testing strategy, test cases"
        case .devops: return "CI/CD, deployment"
        case .analyst: return "Research, analysis"
        case .docWriter: return "Technical documentation"
        case .reviewer: return "Code review, best practices"
        case .mentor: return "Guidance, coaching"
        }
    }
    
    var systemPrompt: String {
        switch self {
        case .pm:
            return """
            You are an expert Product Manager AI. Your focus is on:
            - Understanding user needs and requirements
            - Creating clear PRDs (Product Requirement Documents)
            - Writing user stories with acceptance criteria
            - Prioritizing features based on value
            - Stakeholder communication
            Speak in terms of user value and business impact.
            """
        case .architect:
            return """
            You are a Senior Solution Architect AI. Your expertise includes:
            - System design and architecture patterns
            - Technology stack selection
            - Scalability and performance planning
            - API design and integration strategies
            - Security architecture
            Provide architectural diagrams and technical specifications.
            """
        case .developer:
            return """
            You are a Senior Software Developer AI. Your skills include:
            - Writing clean, maintainable code
            - Following best practices and design patterns
            - Implementing features efficiently
            - Debugging and problem-solving
            - Code optimization
            Focus on practical implementation with working code.
            """
        case .uxDesigner:
            return """
            You are a UX/UI Designer AI. Your expertise covers:
            - User experience design principles
            - Interface wireframing and mockups
            - User flow design
            - Accessibility considerations
            - Design system creation
            Think user-first and prioritize usability.
            """
        case .qa:
            return """
            You are a QA Engineer AI. Your focus is on:
            - Test strategy and planning
            - Writing test cases and scenarios
            - Automated testing approaches
            - Bug identification and reporting
            - Quality assurance processes
            Ensure comprehensive coverage and reliability.
            """
        case .devops:
            return """
            You are a DevOps Engineer AI. Your expertise includes:
            - CI/CD pipeline design
            - Infrastructure as Code
            - Containerization (Docker, Kubernetes)
            - Monitoring and observability
            - Deployment strategies
            Focus on automation and reliability.
            """
        case .analyst:
            return """
            You are a Business Analyst AI. Your skills include:
            - Market research and analysis
            - Competitive analysis
            - Data analysis and insights
            - Requirements gathering
            - ROI analysis
            Provide data-driven recommendations.
            """
        case .docWriter:
            return """
            You are a Technical Writer AI. Your expertise covers:
            - API documentation
            - User guides and tutorials
            - README creation
            - Code comments and documentation
            - Knowledge base articles
            Write clear, comprehensive documentation.
            """
        case .reviewer:
            return """
            You are a Code Reviewer AI. Your focus is on:
            - Code quality assessment
            - Best practices enforcement
            - Security vulnerability detection
            - Performance optimization suggestions
            - Maintainability improvements
            Provide constructive, actionable feedback.
            """
        case .mentor:
            return """
            You are an AI Mentor. Your role is to:
            - Guide developers through challenges
            - Explain concepts clearly
            - Suggest learning resources
            - Encourage best practices
            - Provide career development advice
            Be supportive, educational, and encouraging.
            """
        }
    }
}

// MARK: - BMAD Phases

enum BMadPhase: String, CaseIterable, Identifiable {
    case analysis = "Analysis"
    case planning = "Planning"
    case solutioning = "Solutioning"
    case implementation = "Implementation"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .analysis: return "📊"
        case .planning: return "📝"
        case .solutioning: return "🏗️"
        case .implementation: return "⚡"
        }
    }
    
    var description: String {
        switch self {
        case .analysis: return "Research, brainstorm, explore"
        case .planning: return "PRD, specs, requirements"
        case .solutioning: return "Architecture, UX design"
        case .implementation: return "Code development"
        }
    }
    
    var suggestedAgents: [BMadAgentRole] {
        switch self {
        case .analysis: return [.analyst, .pm, .mentor]
        case .planning: return [.pm, .architect, .uxDesigner]
        case .solutioning: return [.architect, .uxDesigner, .devops]
        case .implementation: return [.developer, .qa, .reviewer]
        }
    }
}

// MARK: - Agent Service

@MainActor
class AgentService: ObservableObject {
    static let shared = AgentService()
    
    @Published var sessionId: String?
    @Published var messages: [AgentMessageModel] = []
    @Published var isLoading = false
    @Published var context: ProjectContextModel?
    @Published var tools: [ToolDefinitionModel] = []
    @Published var pendingChanges: [PendingChangeModel] = []
    @Published var editorContext: EditorContextModel?
    
    // BMAD Agent State
    @Published var selectedAgent: BMadAgentRole = .developer
    @Published var selectedPhase: BMadPhase = .implementation
    
    // Multi-Chat State
    @Published var chatSessions: [ChatSession] = []
    @Published var activeChatId: String?
    @Published var showChatSidebar: Bool = false
    
    // Memory Service (semantic recall)
    private let memoryService = AgentMemoryService.shared
    private let toolExecutor = AgentToolExecutor.shared
    
    private let chatStorageKey = "microcode_agent_chats"
    private let baseURL = "http://127.0.0.1:3000"
    
    init() {
        loadChats()
        // Create default chat if none exist
        if chatSessions.isEmpty {
            let newChat = ChatSession.create(name: "Chat 1")
            chatSessions.append(newChat)
            activeChatId = newChat.id
        } else if activeChatId == nil {
            activeChatId = chatSessions.first?.id
        }
    }
    
    func createSession(workspacePath: String) async {
        isLoading = true
        defer { isLoading = false }
        
        guard let url = URL(string: "\(baseURL)/api/agent/session/create") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["workspace_path": workspacePath]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sid = json["session_id"] as? String {
                sessionId = sid
                await fetchContext()
                await fetchTools()
            }
        } catch {
            print("Failed to create session: \(error)")
        }
    }
    
    func fetchContext() async {
        guard let sid = sessionId else { return }
        guard let url = URL(string: "\(baseURL)/api/agent/context/\(sid)") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            context = try? JSONDecoder().decode(ProjectContextModel.self, from: data)
        } catch {
            print("Failed to fetch context: \(error)")
        }
    }
    
    func fetchTools() async {
        guard let url = URL(string: "\(baseURL)/api/agent/tools") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONDecoder().decode([String: [ToolDefinitionModel]].self, from: data),
               let t = json["tools"] {
                tools = t
            }
        } catch {
            print("Failed to fetch tools: \(error)")
        }
    }
    
    // MARK: - Production Enhanced Chat
    
    func sendEnhancedMessage(_ content: String, provider: String = "gemini", model: String = "gemini-2.5-flash", apiKey: String = "", autoExecute: Bool = true) async {
        guard let sid = sessionId else { return }
        
        // Add user message immediately
        let userMessage = AgentMessageModel(
            id: UUID().uuidString,
            role: .user,
            content: content,
            toolResults: [],
            pendingChanges: [],
            timestamp: Date()
        )
        messages.append(userMessage)
        
        isLoading = true
        defer { isLoading = false }
        
        guard let url = URL(string: "\(baseURL)/api/agent/enhanced-chat") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build request with editor context
        var body: [String: Any] = [
            "session_id": sid,
            "message": content,
            "provider": provider,
            "model": model,
            "auto_execute": autoExecute
        ]
        
        if let ctx = editorContext {
            var contextDict: [String: Any] = [
                "active_file": ctx.activeFile as Any,
                "active_content": ctx.activeContent as Any,
                "cursor_line": ctx.cursorLine as Any,
                "cursor_column": ctx.cursorColumn as Any,
                "selected_text": ctx.selectedText as Any,
                "open_files": ctx.openFiles,
                "language": ctx.language as Any
            ]
            
            // Inject AuthenticAIContext (Smart Core)
            if let smartContext = AuthenticLanguageCore.shared().aiContext() {
                contextDict["semantic_context"] = smartContext.llmContextDescription
            }
            
            body["editor_context"] = contextDict
        }
        
        // Add BMAD agent context
        body["agent_role"] = selectedAgent.rawValue
        body["phase"] = selectedPhase.rawValue
        
        // Recall relevant memories and inject into system prompt
        let relevantMemories = memoryService.recallMemories(query: content, limit: 5)
        var systemPrompt = selectedAgent.systemPrompt
        if !relevantMemories.isEmpty {
            let memoryContext = memoryService.formatMemoriesForContext(relevantMemories)
            systemPrompt += "\n\n" + memoryContext
        }
        body["system_prompt"] = systemPrompt
        
        if !apiKey.isEmpty {
            body["api_key"] = apiKey
        }
        
        if let chatId = activeChatId {
            memoryService.storeMemory(content: content, chatId: chatId, role: "user")
        }
        
        // Inject Tool Instructions
        let toolInstructions = """
        
        ## AVAILABLE TOOLS
        You have access to the following tools to control the local environment. To use a tool, you MUST output a VALID JSON object wrapped in <tool_code> tags.
        
        Format:
        <tool_code>
        {
          "tool": "tool_name",
          "params": {
            "param1": "value1"
          }
        }
        </tool_code>
        
        Tools:
        \(toolExecutor.availableTools.map { "- \($0.name): \($0.description) Protocol: \($0.parameters)" }.joined(separator: "\n"))
        
        Example: To create a file
        <tool_code>
        {
          "tool": "create_file",
          "params": {
             "path": "/Users/me/project/main.swift",
             "content": "print('hello')"
          }
        }
        </tool_code>
        """
        body["system_prompt"] = (body["system_prompt"] as? String ?? "") + toolInstructions
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let responseContent = json["content"] as? String ?? ""
                
                var toolResults: [ToolResultModel] = []
                if let results = json["tool_results"] as? [[String: Any]] {
                    for r in results {
                        toolResults.append(ToolResultModel(
                            toolCallId: r["tool_call_id"] as? String ?? "",
                            toolName: r["tool_name"] as? String ?? "Unknown Tool",
                            success: r["success"] as? Bool ?? false,
                            output: r["output"] as? String ?? "",
                            error: r["error"] as? String
                        ))
                    }
                }
                
                var changes: [PendingChangeModel] = []
                if let pending = json["pending_changes"] as? [[String: Any]] {
                    for p in pending {
                        let diff = p["diff"] as? [String: Any]
                        changes.append(PendingChangeModel(
                            id: p["id"] as? String ?? UUID().uuidString,
                            filePath: diff?["file_path"] as? String ?? "",
                            description: p["description"] as? String ?? "",
                            additions: diff?["additions"] as? Int ?? 0,
                            deletions: diff?["deletions"] as? Int ?? 0,
                            oldContent: diff?["old_content"] as? String ?? "",
                            newContent: diff?["new_content"] as? String ?? "",
                            status: .pending
                        ))
                    }
                    pendingChanges.append(contentsOf: changes)
                }
                
                // Detect and Execute Local Tools
                var finalContent = responseContent
                var localToolResults: [ToolResultModel] = []
                
                // Regex to find <tool_code>...</tool_code>
                let pattern = "<tool_code>([\\s\\S]*?)</tool_code>"
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let nsString = finalContent as NSString
                    let matches = regex.matches(in: finalContent, range: NSRange(location: 0, length: nsString.length))
                    
                    for match in matches {
                        if match.numberOfRanges > 1 {
                            let jsonString = nsString.substring(with: match.range(at: 1))
                            
                            // Execute Tool
                            if let data = jsonString.data(using: .utf8),
                               let jsonCall = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let toolName = jsonCall["tool"] as? String,
                               let params = jsonCall["params"] as? [String: Any] {
                                
                                // Run synchronously for now (or await if we make this function async properly)
                                // Since we are in an async function, we can await!
                                let result = await toolExecutor.execute(toolName: toolName, params: params)
                                
                                var output = ""
                                var isSuccess = false
                                
                                switch result {
                                case .success(let out, let metadata):
                                    output = out
                                    isSuccess = true
                                    
                                    // Handle Diff / Pending Change
                                    if let meta = metadata, meta["type"] as? String == "edit_file" {
                                        let oldContent = meta["old_content"] as? String ?? ""
                                        let newContent = meta["new_content"] as? String ?? ""
                                        let path = meta["path"] as? String ?? ""
                                        
                                        // Calculate rough stats (simplified)
                                        let oldLines = oldContent.components(separatedBy: .newlines)
                                        let newLines = newContent.components(separatedBy: .newlines)
                                        let deletions = max(0, oldLines.count - newLines.count) // Very rough
                                        let additions = max(0, newLines.count - oldLines.count)
                                        
                                        let change = PendingChangeModel(
                                            id: UUID().uuidString,
                                            filePath: path,
                                            description: "Edited by Agent",
                                            additions: additions,
                                            deletions: deletions,
                                            oldContent: oldContent,
                                            newContent: newContent,
                                            status: .accepted // Auto-applied by tool
                                        )
                                        // Append to changes list
                                        localToolResults.append(ToolResultModel(
                                            toolCallId: UUID().uuidString,
                                            toolName: "diff_viewer", // psuedo-tool for UI
                                            success: true,
                                            output: "Diff generated",
                                            error: nil
                                        ))
                                        
                                        // We need to append to the MAIN changes list, but that's local scope.
                                        // We'll append it to the message's pendingChanges
                                        changes.append(change)
                                    }
                                    
                                case .failure(let err):
                                    output = err
                                    isSuccess = false
                                }
                                
                                localToolResults.append(ToolResultModel(
                                    toolCallId: UUID().uuidString,
                                    toolName: toolName,
                                    success: isSuccess,
                                    output: output,
                                    error: isSuccess ? nil : output
                                ))
                            }
                        }
                    }
                    
                    // Remove tool blocks from content to avoid clutter (optional, but requested "As Others IDE")
                    // Actually, keeping the "Thinking" or "Action" visible is often good. 
                    // Let's strip it for cleaner chat, relying on the UI to show the tool result.
                    finalContent = regex.stringByReplacingMatches(in: finalContent, range: NSRange(location: 0, length: nsString.length), withTemplate: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Merge remote and local tool results
                toolResults.append(contentsOf: localToolResults)
                
                let assistantMessage = AgentMessageModel(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: finalContent, // Use cleaned content
                    toolResults: toolResults,
                    pendingChanges: changes,
                    timestamp: Date()
                )
                messages.append(assistantMessage)
                
                // Store assistant response as memory
                if let chatId = activeChatId {
                    memoryService.storeMemory(content: responseContent, chatId: chatId, role: "assistant")
                }
            }
        } catch {
            let errorMessage = AgentMessageModel(
                id: UUID().uuidString,
                role: .assistant,
                content: "Error: \(error.localizedDescription)",
                toolResults: [],
                pendingChanges: [],
                timestamp: Date()
            )
            messages.append(errorMessage)
        }
    }
    
    // Legacy chat for compatibility
    func sendMessage(_ content: String, provider: String = "gemini", model: String = "gemini-2.5-flash", apiKey: String = "") async {
        await sendEnhancedMessage(content, provider: provider, model: model, apiKey: apiKey, autoExecute: true)
    }
    
    // MARK: - Pending Changes
    
    func applyChange(_ changeId: String) async {
        guard let url = URL(string: "\(baseURL)/api/agent/apply-change/\(changeId)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool, success {
                if let idx = pendingChanges.firstIndex(where: { $0.id == changeId }) {
                    pendingChanges[idx].status = .accepted
                }
                let msg = AgentMessageModel(
                    id: UUID().uuidString,
                    role: .system,
                    content: "✅ Applied changes",
                    toolResults: [],
                    pendingChanges: [],
                    timestamp: Date()
                )
                messages.append(msg)
            }
        } catch {
            print("Apply change failed: \(error)")
        }
    }
    
    func rejectChange(_ changeId: String) async {
        guard let url = URL(string: "\(baseURL)/api/agent/reject-change/\(changeId)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            if let idx = pendingChanges.firstIndex(where: { $0.id == changeId }) {
                pendingChanges[idx].status = .rejected
            }
        } catch {
            print("Reject change failed: \(error)")
        }
    }
    
    func executeTool(name: String, arguments: [String: Any]) async {
        guard let sid = sessionId else { return }
        guard let url = URL(string: "\(baseURL)/api/agent/tool/execute") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "session_id": sid,
            "tool_name": name,
            "arguments": arguments
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let output = json["output"] as? String ?? "Tool executed"
                let success = json["success"] as? Bool ?? false
                
                let msg = AgentMessageModel(
                    id: UUID().uuidString,
                    role: .tool,
                    content: success ? "✅ \(name): \(output)" : "❌ \(name) failed",
                    toolResults: [],
                    pendingChanges: [],
                    timestamp: Date()
                )
                messages.append(msg)
            }
        } catch {
            print("Tool execution failed: \(error)")
        }
    }
    
    func undo() async {
        guard let sid = sessionId else { return }
        guard let url = URL(string: "\(baseURL)/api/agent/undo/\(sid)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                let msg = AgentMessageModel(
                    id: UUID().uuidString,
                    role: .system,
                    content: "↩️ Undo: \(message)",
                    toolResults: [],
                    pendingChanges: [],
                    timestamp: Date()
                )
                messages.append(msg)
            }
        } catch {
            print("Undo failed: \(error)")
        }
    }
    
    // MARK: - Editor Context Update
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
        messages = [] // Clear current messages for new chat
        saveChats()
        return newChat
    }
    
    func switchChat(to chatId: String) {
        guard let chat = chatSessions.first(where: { $0.id == chatId }) else { return }
        
        // Save current chat messages
        saveCurrentChatMessages()
        
        // Switch to new chat
        activeChatId = chatId
        messages = chat.messages.map { $0.toModel() }
    }
    
    func deleteChat(_ chatId: String) {
        chatSessions.removeAll { $0.id == chatId }
        
        // If deleted active chat, switch to first available
        if activeChatId == chatId {
            if let firstChat = chatSessions.first {
                switchChat(to: firstChat.id)
            } else {
                // Create new chat if all deleted
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
    
    private func saveCurrentChatMessages() {
        guard let activeId = activeChatId,
              let idx = chatSessions.firstIndex(where: { $0.id == activeId }) else { return }
        
        chatSessions[idx].messages = messages.map { AgentMessageData.from($0) }
        chatSessions[idx].updatedAt = Date()
        saveChats()
    }
    
    func saveChats() {
        // Save current messages to active chat first
        if let activeId = activeChatId,
           let idx = chatSessions.firstIndex(where: { $0.id == activeId }) {
            chatSessions[idx].messages = messages.map { AgentMessageData.from($0) }
            chatSessions[idx].updatedAt = Date()
        }
        
        // Encode and save to UserDefaults
        if let data = try? JSONEncoder().encode(chatSessions) {
            UserDefaults.standard.set(data, forKey: chatStorageKey)
        }
    }
    
    func loadChats() {
        guard let data = UserDefaults.standard.data(forKey: chatStorageKey),
              let chats = try? JSONDecoder().decode([ChatSession].self, from: data) else { return }
        
        chatSessions = chats
        
        // Load active chat messages
        if let activeId = activeChatId,
           let chat = chatSessions.first(where: { $0.id == activeId }) {
            messages = chat.messages.map { $0.toModel() }
        }
    }
}

// MARK: - Models

// Multi-Chat Support
struct ChatSession: Identifiable, Codable {
    let id: String
    var name: String
    var messages: [AgentMessageData]
    var createdAt: Date
    var updatedAt: Date
    
    static func create(name: String = "New Chat") -> ChatSession {
        ChatSession(
            id: UUID().uuidString,
            name: name,
            messages: [],
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// Codable message data for persistence
struct AgentMessageData: Codable, Identifiable {
    let id: String
    let role: String
    let content: String
    let timestamp: Date
    
    static func from(_ model: AgentMessageModel) -> AgentMessageData {
        AgentMessageData(
            id: model.id,
            role: model.role.rawValue,
            content: model.content,
            timestamp: model.timestamp
        )
    }
    
    func toModel() -> AgentMessageModel {
        AgentMessageModel(
            id: id,
            role: AgentMessageModel.MessageRole(rawValue: role) ?? .assistant,
            content: content,
            toolResults: [],
            pendingChanges: [],
            timestamp: timestamp
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

// Production Models - Like Cursor/Windsurf

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
