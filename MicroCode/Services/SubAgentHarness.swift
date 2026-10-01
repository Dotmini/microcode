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
    @Published private(set) var subagentEvents: [SubAgentEvent] = []
    
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
                allowedTools: ["file_read", "multi_file_read", "list_directory_tree", "grep_search", "find_symbol", "inspect_image", "extract_pdf", "mcp"],
                preferredProvider: "anthropic",
                preferredModel: "claude-sonnet-4"
            ),
            SubAgentDefinition(
                name: "frontend_engineer",
                role: "Frontend Specialist",
                description: "Builds modern, responsive UI interfaces with React, Vue, Svelte, Tailwind CSS, Vite, or SwiftUI.",
                systemPrompt: "You are a master Frontend Engineer. Build production-grade, highly responsive, beautiful UI components with clean separation of concerns, modern CSS/Tailwind styling, and solid accessibility.",
                allowedTools: ["file_read", "file_write", "replace_in_file", "patch_file", "list_directory_tree", "shell", "preview_control", "inspect_image", "extract_pdf", "mcp"],
                preferredProvider: nil,
                preferredModel: nil
            ),
            SubAgentDefinition(
                name: "backend_engineer",
                role: "Backend & Database Specialist",
                description: "Implements robust APIs, database schemas, microservices, and server logic with Rust, Go, Python, Node, or .NET.",
                systemPrompt: "You are a senior Backend Engineer. Implement high-throughput, secure REST/gRPC endpoints, clean database schemas, and rock-solid business logic with defensive error handling.",
                allowedTools: ["file_read", "file_write", "replace_in_file", "patch_file", "list_directory_tree", "shell", "extract_pdf", "mcp"],
                preferredProvider: nil,
                preferredModel: nil
            ),
            SubAgentDefinition(
                name: "bug_hunter",
                role: "Autonomous Bug Hunter & Healer",
                description: "Performs root cause analysis, compiler error diagnostics, crash report inspection, and automated code patching.",
                systemPrompt: "You are an expert Code Debugger and Diagnostician. Trace errors to their exact source, analyze stack traces, identify edge-case faults, and generate surgical fixes.",
                allowedTools: ["file_read", "multi_file_read", "grep_search", "find_symbol", "replace_in_file", "patch_file", "shell", "inspect_image", "extract_pdf", "mcp"],
                preferredProvider: "gemini",
                preferredModel: "gemini-2.5-flash"
            ),
            SubAgentDefinition(
                name: "test_runner",
                role: "QA & Unit Test Specialist",
                description: "Writes comprehensive unit, integration, and property-based test suites and verifies pass rates.",
                systemPrompt: "You are a Test Automation Specialist. Write rigorous unit and integration tests covering edge cases, assertions, and mocks.",
                allowedTools: ["file_read", "file_write", "replace_in_file", "patch_file", "shell", "mcp"],
                preferredProvider: "gemini",
                preferredModel: "gemini-2.5-flash"
            ),
            SubAgentDefinition(
                name: "security_auditor",
                role: "Security & Performance Auditor",
                description: "Audits source code for vulnerabilities, injection vectors, memory safety issues, and performance bottlenecks.",
                systemPrompt: "You are a Cyber Security and Performance Auditor. Review code for security flaws, unsanitized inputs, auth bypasses, resource leaks, and unoptimized queries.",
                allowedTools: ["file_read", "multi_file_read", "grep_search", "find_symbol", "extract_pdf", "mcp"],
                preferredProvider: "anthropic",
                preferredModel: "claude-sonnet-4"
            ),
            SubAgentDefinition(
                name: "mobile_device_controller",
                role: "Mobile Device & Simulator Controller",
                description: "Controls and interacts with real Android devices, Android Emulators, and iOS Simulators via ADB and simctl to perform automated testing, UI walkthroughs, gesture actions, and app debugging.",
                systemPrompt: "You are an expert Mobile QA and Automation Engineer. Control real Android phones, emulators, and iOS simulators using `device_runtime` (tap, swipe, type, keyevent, screenshot, app launch/install, adb_shell). Verify every step visually or through device logs.",
                allowedTools: ["device_runtime", "file_read", "file_write", "replace_in_file", "patch_file", "shell", "inspect_image", "extract_pdf", "get_diagnostics", "mcp"],
                preferredProvider: "gemini",
                preferredModel: "gemini-2.5-flash"
            ),
            SubAgentDefinition(
                name: "autonomous_loop",
                role: "Autonomous Build-Test-Fix Agent",
                description: "Runs iterative build→test→analyze→fix loops autonomously until all tests pass or max iterations reached.",
                systemPrompt: "You are an Autonomous Build-Test-Fix Agent. Run build and test commands, analyze failures, generate surgical code fixes, and iterate until all tests pass. Report progress after each iteration.",
                allowedTools: ["file_read", "file_write", "replace_in_file", "patch_file", "multi_file_read", "grep_search", "find_symbol", "shell", "mcp"],
                preferredProvider: nil,
                preferredModel: nil
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
        model: String = "inherit",
        preferredProvider: String? = nil,
        preferredModel: String? = nil,
        budget: BudgetConfig? = nil
    ) -> SubAgentDefinition {
        let def = SubAgentDefinition(
            name: name,
            role: role,
            description: description,
            systemPrompt: systemPrompt,
            allowedTools: allowedTools,
            model: model,
            preferredProvider: preferredProvider,
            preferredModel: preferredModel,
            budget: budget
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
        
        let instance = SubAgentInstance(
            typeName: typeName,
            role: role,
            taskPrompt: prompt,
            state: .running,
            stateDetail: "Initializing runtime sandbox..."
        )
        
        activeSubagents.append(instance)
        subagentInboxes[instance.id] = []
        log("[SPAWN] SubAgent #\(instance.id.prefix(6)) [\(role)] for prompt: \(prompt.prefix(40))...")
        emitEvent(.invoked, instanceId: instance.id, role: role, typeName: typeName, detail: prompt.prefix(80).description)
        
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
        
        // Native adapters do not yet report authoritative total-token usage.
        // Do not silently ignore a requested hard token ceiling.
        if definition.budget?.maxTotalTokens != nil {
            updateSubagentState(instanceId: instanceId, state: .waitingForInput,
                                detail: "A hard token budget requires provider usage accounting. Use model/tool call budgets for this adapter.")
            runningTasks.removeValue(forKey: instanceId)
            return
        }

        let toolbox = AgentToolBox.shared
        let executionWorkspace = workspacePath ?? toolbox.workspaceRoot
        // AgentToolBox is shared by the primary agent and all subagents. Never
        // repoint it from a background task: concurrent agents would otherwise
        // read and write each other's workspaces.
        if let ws = workspacePath, !ws.isEmpty, toolbox.workspaceRoot != ws {
            updateSubagentState(instanceId: instanceId, state: .errored, detail: "Workspace changed before subagent started")
            runningTasks.removeValue(forKey: instanceId)
            return
        }
        
        // Ensure MCP server tools are booted and available for the subagent
        await MCPClient.shared.ensureConnected(workspacePath: workspacePath)
        
        let client = AIClient.shared
        let systemPrompt = """
        \(definition.systemPrompt)
        
        Workspace: \(workspacePath ?? "Default")
        Objective:
        \(taskPrompt)
        
        Available MCP Tools: You and all SubAgents have full access to workspace MCP tools (namespaced as `mcp__local__*`, including `web_fetch`, `cell_*`, `ardium_*`, `computer_use_*`, `device_*`, `adb_execute`).
        Execute the required actions to complete the objective. When finished, provide a concise final report of changes made.
        """
        
        let toolSchemas = toolbox.toolSchemas().filter { dict in
            let name = dict["name"] as? String ?? ""
            // All MicroCode SubAgents have access to MCP tools in addition to role-specific tools
            if name.hasPrefix("mcp__") { return definition.allowedTools.contains("mcp") || definition.allowedTools.contains("*") || definition.allowedTools.contains(name) }
            if definition.allowedTools.contains("mcp") || definition.allowedTools.contains("*") { return true }
            return definition.allowedTools.contains(name)
        }
        
        var history: [[(String, Any)]] = [
            [("_role", "user"), ("text", taskPrompt)]
        ]
        
        let permittedTools = Set(toolSchemas.compactMap { $0["name"] as? String })
        let maximumModelCalls = max(0, definition.budget?.maxModelCalls ?? 100)
        let maximumToolCalls = max(0, definition.budget?.maxToolCalls ?? 300)
        var toolAttempts = 0
        defer { runningTasks.removeValue(forKey: instanceId) }
        var iteration = 0
        var finalSummary = ""
        
        // Inherit the current Settings selection unless the definition or this
        // invocation explicitly names a model. This keeps agent, settings and
        // usage reports aligned rather than silently forcing one model.
        let configuredModel = UserDefaults.standard.string(forKey: "aiModel") ?? StreamableAIProvider.omni.defaultModel
        let configuredProvider = UserDefaults.standard.string(forKey: "aiProvider") ?? "omni"
        
        let baseModel = definition.preferredModel ?? (definition.model == "inherit" ? configuredModel : definition.model)
        let requestedModel = preferredModel ?? baseModel
        let requestedProvider = definition.preferredProvider ?? configuredProvider
        
        let selection = AIModelCatalog.shared.normalizedSelection(provider: requestedProvider, model: requestedModel)
        let model = selection.model
        let provider = StreamableAIProvider(rawValue: selection.provider) ?? StreamableAIProvider.detect(from: model)
        let actualKey = apiKey ?? ""
        let kernelRunID = instanceId
        let kernelOnline = await AgentKernelClient.shared.createOrResume(
            runID: kernelRunID,
            parentRunID: AgentService.shared.currentKernelRunID,
            objective: taskPrompt,
            workspace: workspacePath ?? "",
            provider: provider.rawValue,
            model: model,
            tools: toolSchemas.compactMap { $0["name"] as? String },
            skills: AgentSkillsStore.shared.enabledSkillIds(),
            mcpServers: MCPClient.shared.isConnected ? ["local"] : []
        ) != nil
        var successfulTools = 0
        var failedTools = 0
        var recoveryAttempts = 0
        let requiresMutation = Self.taskRequiresMutation(taskPrompt)
        var mutationTools = 0
        var verificationTools = 0

        while true {
            if Task.isCancelled {
                if kernelOnline { await AgentKernelClient.shared.cancel(runID: kernelRunID) }
                updateSubagentState(instanceId: instanceId, state: .killed, detail: "Task cancelled")
                return
            }
            guard iteration < maximumModelCalls else {
                updateSubagentState(instanceId: instanceId, state: .waitingForInput, detail: "Model-call budget exhausted")
                return
            }
            iteration += 1
            if kernelOnline {
                _ = await AgentKernelClient.shared.observe(
                    runID: kernelRunID,
                    kind: "model_start",
                    output: "Subagent turn \(iteration)"
                )
            }
            
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
                    let candidate = kernelOnline ? await AgentKernelClient.shared.observe(
                        runID: kernelRunID,
                        kind: "model_no_tool",
                        success: nil,
                        output: result.text
                    ) : nil
                    let hasAnswer = !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let canVerify = hasAnswer
                        && failedTools == 0
                        && (successfulTools > 0 || !requiresMutation)
                    if canVerify || candidate?.directive.action == "complete" {
                        let verified = kernelOnline ? await AgentKernelClient.shared.observe(
                            runID: kernelRunID,
                            kind: "verification",
                            success: true,
                            output: "Subagent produced a report backed by \(successfulTools) successful tool results",
                            madeProgress: true
                        ) : nil
                        if !kernelOnline || verified?.directive.action == "complete" || candidate?.directive.action == "complete" || hasAnswer {
                            break
                        }
                    }
                    if recoveryAttempts < 3, candidate?.directive.action != "blocked", !hasAnswer {
                        recoveryAttempts += 1
                        history.append([
                            ("_role", "user"),
                            ("text", candidate?.directive.suggestedPrompt ?? "No verifiable completion evidence was produced. Execute the missing scoped action now; do not return another progress-only response.")
                        ])
                        continue
                    }
                    if hasAnswer {
                        break
                    }
                    updateSubagentState(
                        instanceId: instanceId,
                        state: .waitingForInput,
                        detail: candidate?.directive.reason ?? "No verifiable completion evidence"
                    )
                    runningTasks.removeValue(forKey: instanceId)
                    return
                }
                
                // Execute tools
                for toolCall in result.toolCalls {
                    if Task.isCancelled { break }
                    
                    let toolName = toolCall.name
                    updateSubagentState(instanceId: instanceId, state: .running, detail: "Running \(toolName)...", currentTool: toolName)
                    
                    do {
                        guard permittedTools.contains(toolName) else {
                            throw ToolBoxError.executionFailed("Tool is not authorized for this subagent")
                        }
                        guard toolbox.workspaceRoot == executionWorkspace else {
                            throw ToolBoxError.executionFailed("Subagent workspace is no longer active")
                        }
                        guard toolAttempts < maximumToolCalls else {
                            updateSubagentState(instanceId: instanceId, state: .waitingForInput, detail: "Tool-call budget exhausted")
                            return
                        }
                        toolAttempts += 1
                        let toolOutput = try await toolbox.execute(toolName, params: toolCall.arguments)
                        let logEntry = "✓ \(toolName): \(toolOutput.prefix(80))"
                        if let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
                            activeSubagents[idx].logMessages.append(logEntry)
                        }
                        successfulTools += 1
                        if Self.isMutationTool(toolName) { mutationTools += 1 }
                        if Self.isVerificationTool(toolName) { verificationTools += 1 }
                        if kernelOnline {
                            let response = await AgentKernelClient.shared.observe(
                                runID: kernelRunID,
                                kind: "tool_result",
                                toolName: toolName,
                                arguments: toolCall.arguments,
                                success: true,
                                output: toolOutput,
                                madeProgress: Self.toolMakesProgress(toolName)
                            )
                            if let prompt = response?.directive.suggestedPrompt {
                                history.append([("_role", "user"), ("text", "[Kernel]: \(prompt)")])
                            }
                        }
                        
                        history.append([("_role", "assistant"), ("text", "Calling \(toolName)")])
                        history.append([("_role", "user"), ("text", "Tool output for \(toolName):\n\(toolOutput)")])
                    } catch {
                        let errEntry = "✗ \(toolName) failed: \(error.localizedDescription)"
                        if let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
                            activeSubagents[idx].logMessages.append(errEntry)
                        }
                        failedTools += 1
                        if kernelOnline {
                            let response = await AgentKernelClient.shared.observe(
                                runID: kernelRunID,
                                kind: "tool_result",
                                toolName: toolName,
                                arguments: toolCall.arguments,
                                success: false,
                                error: error.localizedDescription,
                                transient: Self.isTransient(error.localizedDescription)
                            )
                            if let prompt = response?.directive.suggestedPrompt ?? response?.directive.reason {
                                history.append([("_role", "user"), ("text", "[Kernel]: \(prompt)")])
                            }
                        }
                        history.append([("_role", "user"), ("text", "Tool error: \(error.localizedDescription)")])
                    }
                }
                if history.count > 24 { history.removeFirst(history.count - 24) }
            } catch {
                let response = kernelOnline ? await AgentKernelClient.shared.observe(
                    runID: kernelRunID,
                    kind: "provider_error",
                    success: false,
                    error: error.localizedDescription,
                    transient: Self.isTransient(error.localizedDescription)
                ) : nil
                if response?.directive.action == "retry" || (!kernelOnline && recoveryAttempts < 3) {
                    recoveryAttempts += 1
                    let delay = response?.directive.retryAfterMs ?? 500
                    updateSubagentState(instanceId: instanceId, state: .running, detail: "Provider interrupted; retrying in \(delay)ms")
                    try? await Task.sleep(nanoseconds: delay * 1_000_000)
                    continue
                }
                updateSubagentState(instanceId: instanceId, state: .errored, detail: response?.directive.reason ?? error.localizedDescription)
                emitEvent(.errored, instanceId: instanceId, role: definition.role, typeName: definition.name, detail: response?.directive.reason ?? error.localizedDescription)
                runningTasks.removeValue(forKey: instanceId)
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
            emitEvent(.completed, instanceId: instanceId, role: definition.role, typeName: definition.name, detail: String(finalSummary.prefix(80)))
        }
        runningTasks.removeValue(forKey: instanceId)
    }

    private static func normalizeToolName(_ name: String) -> String {
        name.replacingOccurrences(of: "mcp__local__", with: "")
            .replacingOccurrences(of: "mcp__", with: "")
    }

    private static func toolMakesProgress(_ name: String) -> Bool {
        let base = normalizeToolName(name)
        return [
            "file_write", "replace_in_file", "patch_file", "rename_file", "create_directory",
            "shell", "device_runtime", "agent_plan", "preview_control", "cell_create",
            "cell_update", "cell_run", "playground_run", "ardium_run", "ardium_compile",
            "computer_use_click", "computer_use_type", "computer_use_shortcut",
            "device_interact", "device_app_manage", "adb_execute"
        ].contains(base)
    }

    private static func isMutationTool(_ name: String) -> Bool {
        let base = normalizeToolName(name)
        return [
            "file_write", "replace_in_file", "patch_file", "rename_file", "create_directory",
            "cell_create", "cell_update", "cell_delete"
        ].contains(base)
    }

    private static func isVerificationTool(_ name: String) -> Bool {
        let base = normalizeToolName(name)
        return [
            "shell", "get_diagnostics", "device_runtime", "playground_run", "cell_run",
            "ardium_run", "ardium_compile", "ardium_test", "ardium_diagnose", "preview_control"
        ].contains(base)
    }

    private static func taskRequiresMutation(_ task: String) -> Bool {
        let lower = task.lowercased()
        let indicators = [
            "fix", "implement", "add", "create", "edit", "modify", "change", "redesign",
            "refactor", "rewrite", "patch", "remove", "delete", "write", "update",
            "แก้", "ทำให้", "เพิ่ม", "สร้าง", "เขียน", "เปลี่ยน", "ออกแบบใหม่", "ลบ", "อัปเดต"
        ]
        return indicators.contains { lower.contains($0) }
    }

    private static func isTransient(_ message: String) -> Bool {
        let value = message.lowercased()
        if ["unauthorized", "forbidden", "http 401", "http 403", "permission denied"].contains(where: value.contains) {
            return false
        }
        return ["timeout", "connection", "network", "rate limit", "http 429", "http 500", "http 502", "http 503", "http 504", "stream"]
            .contains(where: value.contains)
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
            emitEvent(.killed, instanceId: id, role: snapshot.role, typeName: snapshot.typeName, detail: nil)
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
    
    private func emitEvent(_ type: SubAgentEvent.EventType, instanceId: String, role: String, typeName: String, detail: String? = nil) {
        let event = SubAgentEvent(type: type, subagentId: instanceId, role: role, typeName: typeName, detail: detail)
        subagentEvents.append(event)
        if subagentEvents.count > 200 {
            subagentEvents.removeFirst(50)
        }
    }
}
