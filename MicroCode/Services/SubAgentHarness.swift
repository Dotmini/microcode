import Foundation
import SwiftUI
import Combine

/// Universal Autonomous SubAgent Harness & Execution Orchestrator for MicroCode
@MainActor
public final class SubAgentHarness: ObservableObject {
    public static let shared = SubAgentHarness()
    
    // MARK: - Published State
    @Published public private(set) var registeredDefinitions: [String: SubAgentDefinition] = [:]
    @Published public private(set) var activeSubagents: [SubAgentInstance] = []
    @Published public private(set) var recentLogs: [String] = []
    @Published public var showSubAgentMonitor: Bool = false
    
    // Background execution tasks keyed by SubAgent ID
    private var runningTasks: [String: Task<Void, Never>] = [:]
    private var subagentInboxes: [String: [String]] = [:]
    
    private init() {
        registerBuiltinArchetypes()
    }
    
    // MARK: - Pre-configured Built-in Archetypes
    
    private func registerBuiltinArchetypes() {
        let archetypes: [SubAgentDefinition] = [
            SubAgentDefinition(
                name: "architect",
                role: "System & Architecture Planner",
                description: "Analyzes project structure, evaluates dependencies, defines contracts, and designs technical architecture.",
                systemPrompt: "You are an expert Software Architect. Analyze project architecture, design modular interfaces, establish conventions, and provide high-level implementation blueprints.",
                allowedTools: ["file_read", "multi_file_read", "list_directory_tree", "grep_search", "find_symbol", "inspect_image", "extract_pdf"]
            ),
            SubAgentDefinition(
                name: "frontend_engineer",
                role: "Frontend Specialist",
                description: "Builds modern, responsive UI interfaces with React, Vue, Svelte, Tailwind CSS, Vite, or SwiftUI.",
                systemPrompt: "You are a master Frontend Engineer. Build production-grade, highly responsive, beautiful UI components with clean separation of concerns, modern CSS/Tailwind styling, and solid accessibility.",
                allowedTools: ["file_read", "file_write", "replace_in_file", "patch_file", "list_directory_tree", "shell", "inspect_image", "extract_pdf"]
            ),
            SubAgentDefinition(
                name: "backend_engineer",
                role: "Backend & Database Specialist",
                description: "Implements robust APIs, database schemas, microservices, and server logic with Rust, Go, Python, Node, or .NET.",
                systemPrompt: "You are a senior Backend Engineer. Implement high-throughput, secure REST/gRPC endpoints, clean database schemas, and rock-solid business logic with defensive error handling.",
                allowedTools: ["file_read", "file_write", "replace_in_file", "patch_file", "list_directory_tree", "shell", "extract_pdf"]
            ),
            SubAgentDefinition(
                name: "bug_hunter",
                role: "Autonomous Bug Hunter & Healer",
                description: "Performs root cause analysis, compiler error diagnostics, crash report inspection, and automated code patching.",
                systemPrompt: "You are an expert Code Debugger and Diagnostician. Trace errors to their exact source, analyze stack traces, identify edge-case faults, and generate surgical fixes.",
                allowedTools: ["file_read", "multi_file_read", "grep_search", "find_symbol", "replace_in_file", "patch_file", "shell", "inspect_image", "extract_pdf"]
            ),
            SubAgentDefinition(
                name: "test_runner",
                role: "QA & Unit Test Specialist",
                description: "Writes comprehensive unit, integration, and property-based test suites and verifies pass rates.",
                systemPrompt: "You are a Test Automation Specialist. Write rigorous unit and integration tests covering edge cases, assertions, and mocks.",
                allowedTools: ["file_read", "file_write", "replace_in_file", "patch_file", "shell"]
            ),
            SubAgentDefinition(
                name: "security_auditor",
                role: "Security & Performance Auditor",
                description: "Audits source code for vulnerabilities, injection vectors, memory safety issues, and performance bottlenecks.",
                systemPrompt: "You are a Cyber Security and Performance Auditor. Review code for security flaws, unsanitized inputs, auth bypasses, resource leaks, and unoptimized queries.",
                allowedTools: ["file_read", "multi_file_read", "grep_search", "find_symbol", "extract_pdf"]
            )
        ]
        
        for def in archetypes {
            registeredDefinitions[def.name] = def
        }
    }
    
    // MARK: - SubAgent Definition Management
    
    public func defineSubagent(
        name: String,
        role: String,
        description: String,
        systemPrompt: String,
        allowedTools: [String] = [],
        model: String = "inherit"
    ) -> SubAgentDefinition {
        let def = SubAgentDefinition(
            name: name,
            role: role,
            description: description,
            systemPrompt: systemPrompt,
            allowedTools: allowedTools,
            model: model
        )
        registeredDefinitions[name] = def
        log("Defined new SubAgent archetype: [\(name)] - \(role)")
        return def
    }
    
    // MARK: - SubAgent Spawning & Execution
    
    @discardableResult
    public func invokeSubagent(
        typeName: String,
        role: String,
        prompt: String,
        workspacePath: String? = nil,
        preferredModel: String? = nil,
        apiKey: String? = nil
    ) -> SubAgentInstance {
        let def = registeredDefinitions[typeName] ?? SubAgentDefinition(
            name: typeName,
            role: role,
            description: "Custom SubAgent",
            systemPrompt: "You are a specialized subagent executing a targeted subtask: \(role)",
            allowedTools: []
        )
        
        var instance = SubAgentInstance(
            typeName: typeName,
            role: role,
            taskPrompt: prompt,
            state: .running,
            stateDetail: "Initializing runtime sandbox..."
        )
        
        activeSubagents.append(instance)
        subagentInboxes[instance.id] = []
        log("[SPAWN] SubAgent #\(instance.id.prefix(6)) [\(role)] for prompt: \(prompt.prefix(40))...")
        
        // Launch autonomous background task
        let instanceId = instance.id
        let task = Task { [weak self] () -> Void in
            guard let self = self else { return }
            await self.executeSubagentLoop(
                instanceId: instanceId,
                definition: def,
                taskPrompt: prompt,
                workspacePath: workspacePath,
                preferredModel: preferredModel,
                apiKey: apiKey
            )
        }
        runningTasks[instanceId] = task
        
        return instance
    }
    
    // MARK: - Execution Loop for SubAgent
    
    private func executeSubagentLoop(
        instanceId: String,
        definition: SubAgentDefinition,
        taskPrompt: String,
        workspacePath: String?,
        preferredModel: String?,
        apiKey: String?
    ) async {
        guard let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) else { return }
        
        activeSubagents[idx].state = .running
        activeSubagents[idx].stateDetail = "Executing task..."
        activeSubagents[idx].logMessages.append("Started execution at \(Date())")
        
        let toolbox = AgentToolBox.shared
        // AgentToolBox is shared by the primary agent and all subagents. Never
        // repoint it from a background task: concurrent agents would otherwise
        // read and write each other's workspaces.
        if let ws = workspacePath, !ws.isEmpty, toolbox.workspaceRoot != ws {
            updateSubagentState(instanceId: instanceId, state: .errored, detail: "Workspace changed before subagent started")
            runningTasks.removeValue(forKey: instanceId)
            return
        }
        
        let client = AIClient.shared
        let systemPrompt = """
        \(definition.systemPrompt)
        
        Workspace: \(workspacePath ?? "Default")
        Objective:
        \(taskPrompt)
        
        Execute the required actions to complete the objective. When finished, provide a concise final report of changes made.
        """
        
        let toolSchemas = toolbox.toolSchemas().filter { dict in
            let name = dict["name"] as? String ?? ""
            // Empty means no capability. A newly defined subagent must be
            // granted tools explicitly instead of accidentally receiving all.
            return definition.allowedTools.contains(name)
        }
        
        var history: [[(String, Any)]] = [
            [("_role", "user"), ("text", taskPrompt)]
        ]
        
        var iteration = 0
        let maxIterations = 8
        var finalSummary = ""
        
        // Inherit the current Settings selection unless the definition or this
        // invocation explicitly names a model. This keeps agent, settings and
        // usage reports aligned rather than silently forcing one model.
        let configuredModel = UserDefaults.standard.string(forKey: "aiModel") ?? StreamableAIProvider.omni.defaultModel
        let requestedModel = preferredModel ?? (definition.model == "inherit" ? configuredModel : definition.model)
        let configuredProvider = UserDefaults.standard.string(forKey: "aiProvider") ?? "omni"
        let selection = AIModelCatalog.shared.normalizedSelection(provider: configuredProvider, model: requestedModel)
        let model = selection.model
        let provider = StreamableAIProvider(rawValue: selection.provider) ?? StreamableAIProvider.detect(from: model)
        let actualKey = apiKey ?? ""
        
        while iteration < maxIterations {
            if Task.isCancelled {
                updateSubagentState(instanceId: instanceId, state: .killed, detail: "Task cancelled")
                return
            }
            iteration += 1
            
            // Check for incoming inbox messages
            if let inbox = subagentInboxes[instanceId], !inbox.isEmpty {
                for msg in inbox {
                    history.append([("_role", "user"), ("text", "[Parent Agent Message]: \(msg)")])
                }
                subagentInboxes[instanceId]?.removeAll()
            }
            
            do {
                updateSubagentState(instanceId: instanceId, state: .running, detail: "Thinking (Turn \(iteration))...")
                
                let result = try await client.sendSync(
                    messages: history,
                    systemPrompt: systemPrompt,
                    provider: provider,
                    model: model,
                    apiKey: actualKey,
                    tools: toolSchemas
                )
                
                finalSummary = result.text
                if let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
                    activeSubagents[idx].tokensUsed += (result.text.count / 4) + 200
                }
                
                if result.toolCalls.isEmpty {
                    break
                }
                
                // Execute tools
                for toolCall in result.toolCalls {
                    if Task.isCancelled { break }
                    
                    let toolName = toolCall.name
                    updateSubagentState(instanceId: instanceId, state: .running, detail: "Running \(toolName)...", currentTool: toolName)
                    
                    do {
                        let toolOutput = try await toolbox.execute(toolName, params: toolCall.arguments)
                        let logEntry = "✓ \(toolName): \(toolOutput.prefix(80))"
                        if let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
                            activeSubagents[idx].logMessages.append(logEntry)
                        }
                        
                        history.append([("_role", "assistant"), ("text", "Calling \(toolName)")])
                        history.append([("_role", "user"), ("text", "Tool output for \(toolName):\n\(toolOutput)")])
                    } catch {
                        let errEntry = "✗ \(toolName) failed: \(error.localizedDescription)"
                        if let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
                            activeSubagents[idx].logMessages.append(errEntry)
                        }
                        history.append([("_role", "user"), ("text", "Tool error: \(error.localizedDescription)")])
                    }
                }
            } catch {
                updateSubagentState(instanceId: instanceId, state: .errored, detail: error.localizedDescription)
                return
            }
        }
        
        // Finalize SubAgent
        if let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
            // Single mutation: copy → modify → assign back. @Published fires once.
            var snapshot = activeSubagents[idx]
            snapshot.state = .completed
            snapshot.stateDetail = "Finished successfully"
            snapshot.finalReport = finalSummary
            snapshot.finishedAt = Date()
            snapshot.currentToolExecution = nil
            activeSubagents[idx] = snapshot
            log("[DONE] SubAgent #\(instanceId.prefix(6)) [\(definition.role)] completed successfully.")
        }
        runningTasks.removeValue(forKey: instanceId)
    }
    
    private func updateSubagentState(
        instanceId: String,
        state: SubAgentLifecycleState,
        detail: String?,
        currentTool: String? = nil
    ) {
        guard let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) else { return }
        // Single mutation: copy → modify → assign back. @Published fires once.
        var snapshot = activeSubagents[idx]
        snapshot.state = state
        snapshot.stateDetail = detail
        snapshot.currentToolExecution = currentTool
        activeSubagents[idx] = snapshot
    }
    
    // MARK: - Process Lifecycle: Kill & Send Message
    
    public func killSubagent(id: String) {
        if let task = runningTasks[id] {
            task.cancel()
            runningTasks.removeValue(forKey: id)
        }
        if let idx = activeSubagents.firstIndex(where: { $0.id == id }) {
            var snapshot = activeSubagents[idx]
            snapshot.state = .killed
            snapshot.stateDetail = "Terminated by user/main agent"
            snapshot.finishedAt = Date()
            snapshot.currentToolExecution = nil
            activeSubagents[idx] = snapshot
            log("[KILLED] Terminated SubAgent #\(id.prefix(6))")
        }
    }
    
    public func killAllSubagents() {
        for (id, task) in runningTasks {
            task.cancel()
            if let idx = activeSubagents.firstIndex(where: { $0.id == id }) {
                var snapshot = activeSubagents[idx]
                snapshot.state = .killed
                snapshot.stateDetail = "Terminated by Kill All"
                snapshot.finishedAt = Date()
                activeSubagents[idx] = snapshot
            }
        }
        runningTasks.removeAll()
        log("[KILLED] Terminated ALL active SubAgents")
    }
    
    public func sendMessage(recipientId: String, message: String) -> Bool {
        guard activeSubagents.contains(where: { $0.id == recipientId }) else { return false }
        if subagentInboxes[recipientId] == nil {
            subagentInboxes[recipientId] = []
        }
        subagentInboxes[recipientId]?.append(message)
        log("[MSG] Sent message to SubAgent #\(recipientId.prefix(6)): \(message.prefix(30))...")
        return true
    }
    
    public func getSubagentStatusSummary() -> String {
        if activeSubagents.isEmpty {
            return "No subagents currently active."
        }
        return activeSubagents.map { sub in
            "- [\(sub.id.prefix(6))] \(sub.role) (\(sub.typeName)): \(sub.state.displayName) - \(sub.stateDetail ?? "")"
        }.joined(separator: "\n")
    }
    
    private func log(_ msg: String) {
        recentLogs.append("[\(Date().formatted(date: .omitted, time: .standard))] \(msg)")
        if recentLogs.count > 100 {
            recentLogs.removeFirst()
        }
    }
}
