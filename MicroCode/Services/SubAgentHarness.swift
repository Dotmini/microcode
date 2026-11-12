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
    @Published public var showSquadBuilderSheet: Bool = false
    @Published private(set) var subagentEvents: [SubAgentEvent] = []
    @Published public private(set) var blackboard: [String: SwarmFact] = [:]
    
    // MARK: - CEO & Specialist Squad State
    @Published public var squadPresets: [AgentSquadPreset] = []
    @Published public var activeSquadPresetId: String? = nil {
        didSet {
            UserDefaults.standard.set(activeSquadPresetId, forKey: "MicroCode.ActiveSquadPresetId")
        }
    }
    @Published public private(set) var interAgentDialogue: [InterAgentMessage] = []
    @Published public private(set) var activeContracts: [SubAgentTaskContract] = []
    
    private let customPresetsStorageKey = "MicroCode.CustomAgentSquadPresets.v1"
    
    // Background execution tasks keyed by SubAgent ID
    private var runningTasks: [String: Task<Void, Never>] = [:]
    private var subagentInboxes: [String: [String]] = [:]
    private var verifiedChanges: Set<String> = []

    public struct SwarmFact: Identifiable, Codable {
        public var id: String { key }
        public let key: String
        public let value: String
        public let authorRole: String
        public let updatedAt: Date
    }

    public struct Outcome {
        public let instance: SubAgentInstance
        public let verifiedWorkspaceChange: Bool
    }
    
    public var activeSquadPreset: AgentSquadPreset? {
        guard let id = activeSquadPresetId else { return nil }
        return squadPresets.first(where: { $0.id == id })
    }
    
    private init() {
        registerBuiltinArchetypes()
        loadSquadPresets()
        activeSquadPresetId = UserDefaults.standard.string(forKey: "MicroCode.ActiveSquadPresetId")
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
                preferredProvider: nil,
                preferredModel: nil
            ),
            SubAgentDefinition(
                name: "frontend_engineer",
                role: "Frontend Specialist",
                description: "Builds modern, responsive UI interfaces with React, Vue, Svelte, Tailwind CSS, Vite, or SwiftUI.",
                systemPrompt: "You are a master Frontend Engineer. Build production-grade, highly responsive, beautiful UI components with clean separation of concerns, modern CSS/Tailwind styling, and solid accessibility.",
                allowedTools: ["file_read", "file_write", "replace_in_file", "patch_file", "list_directory_tree", "shell", "preview_control", "inspect_image", "extract_pdf", "generate_image", "generate_video", "generate_music", "mcp"],
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
                preferredProvider: nil,
                preferredModel: nil
            ),
            SubAgentDefinition(
                name: "test_runner",
                role: "QA & Unit Test Specialist",
                description: "Writes comprehensive unit, integration, and property-based test suites and verifies pass rates.",
                systemPrompt: "You are a Test Automation Specialist. Write rigorous unit and integration tests covering edge cases, assertions, and mocks.",
                allowedTools: ["file_read", "file_write", "replace_in_file", "patch_file", "shell", "mcp"],
                preferredProvider: nil,
                preferredModel: nil
            ),
            SubAgentDefinition(
                name: "security_auditor",
                role: "Security & Performance Auditor",
                description: "Audits source code for vulnerabilities, injection vectors, memory safety issues, and performance bottlenecks.",
                systemPrompt: "You are a Cyber Security and Performance Auditor. Review code for security flaws, unsanitized inputs, auth bypasses, resource leaks, and unoptimized queries.",
                allowedTools: ["file_read", "multi_file_read", "grep_search", "find_symbol", "extract_pdf", "mcp"],
                preferredProvider: nil,
                preferredModel: nil
            ),
            SubAgentDefinition(
                name: "mobile_device_controller",
                role: "Mobile Device & Simulator Controller",
                description: "Controls and interacts with real Android devices, Android Emulators, and iOS Simulators via ADB and simctl to perform automated testing, UI walkthroughs, gesture actions, and app debugging.",
                systemPrompt: "You are an expert Mobile QA and Automation Engineer. Control real Android phones, emulators, and iOS simulators using `device_runtime` (tap, swipe, type, keyevent, screenshot, app launch/install, adb_shell). Verify every step visually or through device logs.",
                allowedTools: ["device_runtime", "file_read", "file_write", "replace_in_file", "patch_file", "shell", "inspect_image", "extract_pdf", "get_diagnostics", "mcp"],
                preferredProvider: nil,
                preferredModel: nil
            ),
            SubAgentDefinition(
                name: "autonomous_loop",
                role: "Autonomous Build-Test-Fix Agent",
                description: "Runs iterative build→test→analyze→fix loops autonomously until all tests pass or max iterations reached.",
                systemPrompt: "You are an Autonomous Build-Test-Fix Agent. Run build and test commands, analyze failures, generate surgical code fixes, and iterate until all tests pass. Report progress after each iteration.",
                allowedTools: ["file_read", "file_write", "replace_in_file", "patch_file", "multi_file_read", "grep_search", "find_symbol", "shell", "generate_image", "generate_video", "generate_music", "mcp"],
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
        apiKey: String? = nil,
        endpointOverride: AgentModelEndpoint? = nil,
        ownedPaths: [String] = [],
        revisionRound: Int = 0
    ) -> SubAgentInstance {
        let def = registeredDefinitions[typeName] ?? SubAgentDefinition(
            name: typeName,
            role: role,
            description: "Custom SubAgent",
            systemPrompt: "You are a specialized subagent executing a targeted subtask: \(role)",
            allowedTools: ["*"]
        )
        
        let resolvedEndpoint = endpointOverride ?? resolveRoleEndpoint(forTypeName: typeName, preferredModel: preferredModel, definition: def)
        let routePreview = resolveExecutionRoute(for: resolvedEndpoint, explicitApiKey: apiKey)
        
        let instance = SubAgentInstance(
            typeName: typeName,
            role: role,
            taskPrompt: prompt,
            state: .running,
            stateDetail: "Initializing [\(routePreview.badgeLabel)]...",
            endpointBadge: routePreview.badgeLabel,
            ownedPaths: ownedPaths,
            revisionRound: revisionRound
        )
        
        activeSubagents.append(instance)
        subagentInboxes[instance.id] = []
        log("[SPAWN] SubAgent #\(instance.id.prefix(6)) [\(role) • \(routePreview.badgeLabel)] for prompt: \(prompt.prefix(40))...")
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
                apiKey: apiKey,
                endpointOverride: resolvedEndpoint,
                ownedPaths: ownedPaths
            )
        }
        runningTasks[instanceId] = task
        
        return instance
    }

    public func waitForSubagent(id: String) async throws -> Outcome? {
        let task = runningTasks[id]
        await withTaskCancellationHandler {
            if let task { await task.value }
        } onCancel: {
            Task { @MainActor in self.killSubagent(id: id) }
        }
        try Task.checkCancellation()
        guard let instance = activeSubagents.first(where: { $0.id == id }) else { return nil }
        return Outcome(instance: instance, verifiedWorkspaceChange: verifiedChanges.contains(id))
    }
    
    // MARK: - Execution Loop for SubAgent
    
    private func executeSubagentLoop(
        instanceId: String,
        definition: SubAgentDefinition,
        taskPrompt: String,
        workspacePath: String?,
        preferredModel: String?,
        apiKey: String?,
        endpointOverride: AgentModelEndpoint? = nil,
        ownedPaths: [String] = []
    ) async {
        guard let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) else { return }
        
        activeSubagents[idx].state = .running
        activeSubagents[idx].stateDetail = "Executing task..."
        activeSubagents[idx].logMessages.append("Started execution at \(Date())")
        
        // Active token and budget enforcement

        let toolbox = AgentToolBox.shared
        let executionWorkspace = workspacePath ?? toolbox.effectiveWorkspaceRoot
        // PNS Motor Fiber Isolation: Instead of rejecting concurrent subagents running on isolated
        // git worktrees or multi-window workspaces when `toolbox.workspaceRoot != ws`, every tool call
        // executes inside `@TaskLocal AgentExecutionContext.$workspaceRoot.withValue(executionWorkspace)`.
        
        // Ensure MCP server tools are booted and available for the subagent
        await MCPClient.shared.ensureConnected(workspacePath: executionWorkspace)
        
        let jitSkillsSnippet = AgentSkillsStore.shared.activeSkillsPromptSnippet(
            forPrompt: taskPrompt,
            workspacePath: executionWorkspace
        )
        let projectRulesSnippet = MultiPlatformRulesEngine.shared.formatPromptSection(maxTokens: 500)
        let blackboardSnippet = readBlackboardSummary()
        let ownedScopeNotice = ownedPaths.isEmpty
            ? ""
            : "\n## 🔒 Assigned File-Ownership Scope (CEO Contract)\nYou are authorized to modify ONLY files matching: [\(ownedPaths.joined(separator: ", "))]. Do NOT modify files owned by other concurrent teammates. If you need another file updated, post a contract fact to `swarm_orchestrator` (`action='post_fact'`) or use `send_message`.\n"
        
        let systemPrompt = """
        \(definition.systemPrompt)
        
        Workspace: \(executionWorkspace ?? "Default")
        Role: \(definition.role) (\(definition.name))
        Objective:
        \(taskPrompt)
        \(ownedScopeNotice)
        \(blackboardSnippet.isEmpty ? "" : "## Shared Swarm Blackboard (Cross-Agent Facts)\n\(blackboardSnippet)\n")
        \(projectRulesSnippet)
        \(jitSkillsSnippet)
        
        Available Tools & Universal SubAgent Protocol:
        - You have full access to workspace tools, MCP tools (`mcp__*`), `skill_engine`, `mcp_orchestrator`, `swarm_orchestrator`, and `send_message`.
        - Whenever you establish or update an API schema, struct signature, port, or file contract, post it to `swarm_orchestrator` (`action='post_fact'`) or emit `<ceo_contract key="KEY">VALUE</ceo_contract>` so the CEO and teammates stay 100% synchronized.
        - You can message teammates or the CEO using `send_message` or `<team_message to="role_name">message</team_message>`.
        - If your model endpoint does not support native JSON tool calling, you may invoke any tool using:
          `<tool_call>{"name": "file_read", "arguments": {"path": "..."}}</tool_call>`
        - Execute the required actions to complete the objective and verify your changes before finishing.
        """
        
        let universalMetaTools: Set<String> = ["skill_engine", "slop_check", "mcp_orchestrator", "swarm_orchestrator", "pns_nervous_system", "send_message", "get_diagnostics", "git_status"]
        let baseToolSchemas = toolbox.toolSchemas().filter { dict in
            let name = dict["name"] as? String ?? ""
            if universalMetaTools.contains(name) { return true }
            // All MicroCode SubAgents have access to MCP tools in addition to role-specific tools
            if name.hasPrefix("mcp__") { return definition.allowedTools.contains("mcp") || definition.allowedTools.contains("*") || definition.allowedTools.contains(name) }
            if definition.allowedTools.contains("*") { return true }
            return definition.allowedTools.contains(name)
        }
        // PNS Ganglion Nerve-Tract Pruning: Mount only Top-K external MCP tools matching this SubAgent's Nerve Tract
        let toolSchemas = PNSGanglionRouter.shared.filterMCPToolsForSubAgent(
            archetype: definition.name,
            taskPrompt: taskPrompt,
            workspacePath: executionWorkspace,
            allSchemas: baseToolSchemas,
            maxMCPTools: 10,
            synapseLookup: { category, tract, nodeId, proj in
                PNSOrchestrator.shared.lookupSynapse(taskCategory: category, tract: tract, targetNodeId: nodeId, projectPath: proj)
            }
        )
        
        var history: [[(String, Any)]] = [
            [("_role", "user"), ("text", taskPrompt)]
        ]
        
        let permittedTools = Set(toolSchemas.compactMap { $0["name"] as? String })
        let maximumModelCalls = max(0, definition.budget?.maxModelCalls ?? 100)
        let maximumToolCalls = max(0, definition.budget?.maxToolCalls ?? 300)
        let maximumTotalTokens = definition.budget?.maxTotalTokens ?? 1_000_000
        var accumulatedTokens = 0
        var toolAttempts = 0
        defer { runningTasks.removeValue(forKey: instanceId) }
        var iteration = 0
        var finalSummary = ""
        
        let resolvedEndpoint = endpointOverride ?? resolveRoleEndpoint(forTypeName: definition.name, preferredModel: preferredModel, definition: definition)
        let primaryRoute = resolveExecutionRoute(for: resolvedEndpoint, explicitApiKey: apiKey)
        if let idx2 = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
            activeSubagents[idx2].endpointBadge = primaryRoute.badgeLabel
        }
        let provider = primaryRoute.provider
        let model = primaryRoute.model
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
        var recoveryAttempts = 0
        let canMutate = permittedTools.contains("shell") || permittedTools.contains { AgentExecutionEvidence.mutates(name: $0, arguments: [:]) }
        let requiresMutation = canMutate && AgentExecutionEvidence.taskRequiresMutation(taskPrompt)
        var evidence = AgentExecutionEvidence()

        // Cross-Vendor Real ACP CLI Execution:
        // When `authSource == .acpCLI` and the corresponding external CLI harness (`claude`, `codex`, `agy`, `opencode`, `goose`)
        // is installed locally, execute genuinely via `ACPAgentSession` (with `MCP-over-ACP` IDE tools auto-injected!).
        // Falls back seamlessly to `dispatchModelTurnWithFailover` if the CLI binary is unavailable or fails pre-flight.
        if resolvedEndpoint.authSource == .acpCLI {
            let acpOutcome = await executeACPCLISubagentIfAvailable(
                instanceId: instanceId,
                definition: definition,
                systemPrompt: systemPrompt,
                taskPrompt: taskPrompt,
                endpoint: resolvedEndpoint,
                executionWorkspace: executionWorkspace
            )
            if acpOutcome.completed {
                if let idxDone = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
                    var snapshot = activeSubagents[idxDone]
                    snapshot.state = .completed
                    if acpOutcome.mutated { verifiedChanges.insert(instanceId) }
                    snapshot.stateDetail = acpOutcome.mutated
                        ? "Finished via ACP CLI (\(acpOutcome.engineName)) with verified workspace change"
                        : "Finished via ACP CLI (\(acpOutcome.engineName))"
                    snapshot.finalReport = acpOutcome.summary
                    snapshot.finishedAt = Date()
                    snapshot.currentToolExecution = nil
                    activeSubagents[idxDone] = snapshot
                    log("[DONE] SubAgent #\(instanceId.prefix(6)) [\(definition.role)] completed via ACP CLI (\(acpOutcome.engineName)).")
                    emitEvent(.completed, instanceId: instanceId, role: definition.role, typeName: definition.name, detail: String(acpOutcome.summary.prefix(80)))
                }
                runningTasks.removeValue(forKey: instanceId)
                return
            }
        }

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
            
            // Check for incoming inbox messages (from CEO or peer SubAgents)
            if let inbox = subagentInboxes[instanceId], !inbox.isEmpty {
                for msg in inbox {
                    history.append([("_role", "user"), ("text", "[Incoming Team/CEO Directive]: \(msg)")])
                }
                subagentInboxes[instanceId]?.removeAll()
            }
            
            do {
                updateSubagentState(instanceId: instanceId, state: .running, detail: "Thinking (Turn \(iteration) • \(primaryRoute.badgeLabel))...")
                
                let rawResult = try await dispatchModelTurnWithFailover(
                    messages: history,
                    systemPrompt: systemPrompt,
                    endpoint: resolvedEndpoint,
                    explicitApiKey: apiKey,
                    tools: toolSchemas,
                    instanceId: instanceId
                )
                
                // Universal SubAgent & Tool Empowerment: parse structured XML/JSON fallback tags if model didn't emit native toolCalls
                let parsedExtra = parseUniversalFallbackToolCalls(
                    from: rawResult.text,
                    senderRole: definition.role,
                    senderBadge: primaryRoute.badgeLabel
                )
                let combinedToolCalls = rawResult.toolCalls.isEmpty ? parsedExtra.toolCalls : rawResult.toolCalls
                let result = (text: parsedExtra.cleanedText, toolCalls: combinedToolCalls)
                
                finalSummary = result.text
                let turnTokens = (result.text.count / 4) + 200
                accumulatedTokens += turnTokens
                if let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
                    activeSubagents[idx].tokensUsed += turnTokens
                }
                
                if accumulatedTokens >= maximumTotalTokens {
                    updateSubagentState(instanceId: instanceId, state: .waitingForInput, detail: "Token budget circuit breaker tripped (\(accumulatedTokens) >= \(maximumTotalTokens) tokens)")
                    runningTasks.removeValue(forKey: instanceId)
                    return
                }
                
                if result.toolCalls.isEmpty {
                    let candidate = kernelOnline ? await AgentKernelClient.shared.observe(
                        runID: kernelRunID,
                        kind: "model_no_tool",
                        success: nil,
                        output: result.text
                    ) : nil
                    let hasAnswer = !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let canVerify = hasAnswer && evidence.satisfies(requiresMutation: requiresMutation || evidence.hasMutation)
                    if canVerify {
                        let verified = kernelOnline ? await AgentKernelClient.shared.observe(
                            runID: kernelRunID,
                            kind: "verification",
                            success: true,
                            output: "Subagent produced a report backed by \(evidence.successfulTools) successful tool results",
                            madeProgress: true
                        ) : nil
                        if !kernelOnline || verified?.directive.action == "complete" || candidate?.directive.action == "complete" {
                            break
                        }
                    }
                    if recoveryAttempts < 3, candidate?.directive.action != "blocked" {
                        recoveryAttempts += 1
                        history.append([
                            ("_role", "user"),
                            ("text", candidate?.directive.suggestedPrompt ?? "No verifiable completion evidence was produced. Execute the missing scoped action now; do not return another progress-only response.")
                        ])
                        continue
                    }
                    updateSubagentState(
                        instanceId: instanceId,
                        state: .waitingForInput,
                        detail: "Missing verified \(requiresMutation ? "mutation and post-change test" : "tool result") after \(recoveryAttempts) recovery attempts"
                    )
                    runningTasks.removeValue(forKey: instanceId)
                    return
                }
                
                // Execute tools in this turn and record a single assistant + user turn pair
                var calledToolsSummary: [String] = []
                var turnToolOutputs: [String] = []
                var kernelSuggestions: [String] = []
                
                for toolCall in result.toolCalls {
                    if Task.isCancelled { break }
                    
                    let toolName = toolCall.name
                    updateSubagentState(instanceId: instanceId, state: .running, detail: "Running \(toolName)...", currentTool: toolName)
                    
                    do {
                        guard permittedTools.contains(toolName) || universalMetaTools.contains(toolName) else {
                            throw ToolBoxError.executionFailed("Tool '\(toolName)' is not authorized for this subagent")
                        }
                        try verifyFileOwnershipLock(
                            instanceId: instanceId,
                            role: definition.role,
                            ownedPaths: ownedPaths,
                            toolName: toolName,
                            arguments: toolCall.arguments
                        )
                        guard toolAttempts < maximumToolCalls else {
                            updateSubagentState(instanceId: instanceId, state: .waitingForInput, detail: "Tool-call budget exhausted")
                            return
                        }
                        toolAttempts += 1
                        let rawOutput = try await AgentExecutionContext.$workspaceRoot.withValue(executionWorkspace) {
                            try await toolbox.execute(toolName, params: toolCall.arguments)
                        }
                        let toolOutput = TokenOptimizer.shared.compressToolOutput(rawOutput, toolName: toolName, budget: 12_000)
                        let logEntry = "✓ \(toolName): \(toolOutput.prefix(80))"
                        if let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
                            activeSubagents[idx].logMessages.append(logEntry)
                        }
                        evidence.record(name: toolName, arguments: toolCall.arguments, success: true, output: toolOutput)
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
                                kernelSuggestions.append(prompt)
                            }
                        }
                        
                        calledToolsSummary.append("[Called tool: \(toolName)]")
                        turnToolOutputs.append("✅ \(toolName) output:\n\(toolOutput)")
                    } catch {
                        let errEntry = "✗ \(toolName) failed: \(error.localizedDescription)"
                        if let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
                            activeSubagents[idx].logMessages.append(errEntry)
                        }
                        evidence.record(name: toolName, arguments: toolCall.arguments, success: false)
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
                                kernelSuggestions.append(prompt)
                            }
                        }
                        var detailedError = "❌ \(toolName) error: \(error.localizedDescription)"
                        // Surgical Auto-Heal Context Injection: if an edit fails, attach target file lines automatically
                        if ["replace_in_file", "patch_file", "multi_replace_in_file"].contains(Self.normalizeToolName(toolName)),
                           let relPath = toolCall.arguments["path"] as? String {
                            let fullPath = relPath.hasPrefix("/") ? relPath : ((executionWorkspace ?? "") as NSString).appendingPathComponent(relPath)
                            if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                                let lines = content.components(separatedBy: "\n")
                                let preview = lines.prefix(60).enumerated().map { "\($0.offset + 1): \($0.element)" }.joined(separator: "\n")
                                detailedError += "\n[Auto-Heal Context: Top 60 lines of \(relPath) for exact string matching]\n\(preview)"
                            }
                        }
                        calledToolsSummary.append("[Called tool: \(toolName) (failed)]")
                        turnToolOutputs.append(detailedError)
                    }
                }
                
                let assistantTurnText = result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? calledToolsSummary.joined(separator: "\n")
                    : result.text + "\n" + calledToolsSummary.joined(separator: "\n")
                history.append([("_role", "assistant"), ("text", assistantTurnText)])
                
                var combinedUserFeedback = turnToolOutputs.joined(separator: "\n\n---\n\n")
                if let lastKernelNote = kernelSuggestions.last {
                    combinedUserFeedback += "\n\n[Kernel]: \(lastKernelNote)"
                }
                history.append([("_role", "user"), ("text", combinedUserFeedback)])
                
                // Preserve history[0] (the original taskPrompt) and keep recent turn pairs intact
                if history.count > 25, let firstPrompt = history.first {
                    let recent = Array(history.suffix(22))
                    history = [firstPrompt] + recent
                }
            } catch {
                if Task.isCancelled {
                    updateSubagentState(instanceId: instanceId, state: .killed, detail: "Task cancelled")
                    return
                }
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
            if evidence.hasVerifiedMutation { verifiedChanges.insert(instanceId) }
            snapshot.stateDetail = evidence.hasVerifiedMutation
                ? "Finished successfully with verified workspace change"
                : "Finished successfully"
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
            "device_interact", "device_app_manage", "adb_execute",
            "skill_engine", "mcp_orchestrator", "swarm_orchestrator"
        ].contains(base)
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
    
    public func sendMessage(
        recipientId: String,
        message: String,
        senderRole: String = "Lead",
        senderBadge: String = "Orchestrator"
    ) -> Bool {
        // Match either by exact SubAgent instance ID, prefix, typeName, or role
        let targetInstance = activeSubagents.first(where: {
            $0.id == recipientId ||
            $0.id.hasPrefix(recipientId) ||
            $0.typeName.lowercased() == recipientId.lowercased() ||
            $0.role.lowercased().contains(recipientId.lowercased())
        })
        guard let target = targetInstance else { return false }
        if subagentInboxes[target.id] == nil {
            subagentInboxes[target.id] = []
        }
        subagentInboxes[target.id]?.append("[\(senderRole)]: \(message)")
        recordDialogue(
            senderRole: senderRole,
            senderBadge: senderBadge,
            recipientRole: target.role,
            kind: .peerSync,
            content: message
        )
        log("[MSG] \(senderRole) -> \(target.role) (#\(target.id.prefix(6))): \(message.prefix(40))...")
        return true
    }
    
    public func recordDialogue(
        senderRole: String,
        senderBadge: String,
        recipientRole: String,
        kind: InterAgentMessage.MessageKind,
        content: String,
        ownedFiles: [String] = []
    ) {
        let msg = InterAgentMessage(
            senderRole: senderRole,
            senderBadge: senderBadge,
            recipientRole: recipientRole,
            kind: kind,
            content: content,
            ownedFiles: ownedFiles
        )
        interAgentDialogue.append(msg)
        if interAgentDialogue.count > 120 {
            interAgentDialogue.removeFirst(30)
        }
    }
    
    public func clearDialogueAndContracts() {
        interAgentDialogue.removeAll()
        activeContracts.removeAll()
    }
    
    // MARK: - Squad Preset Management (Built-in + Custom User Presets)
    
    public func loadSquadPresets() {
        var combined = AgentSquadPreset.builtInPresets
        if let data = UserDefaults.standard.data(forKey: customPresetsStorageKey),
           let custom = try? JSONDecoder().decode([AgentSquadPreset].self, from: data) {
            for item in custom where !combined.contains(where: { $0.id == item.id }) {
                combined.append(item)
            }
        }
        squadPresets = combined
    }
    
    public func saveCustomSquadPreset(_ preset: AgentSquadPreset) {
        var customList = squadPresets.filter { !$0.isBuiltIn }
        if let idx = customList.firstIndex(where: { $0.id == preset.id }) {
            customList[idx] = preset
        } else {
            customList.append(preset)
        }
        if let data = try? JSONEncoder().encode(customList) {
            UserDefaults.standard.set(data, forKey: customPresetsStorageKey)
        }
        loadSquadPresets()
        activeSquadPresetId = preset.id
    }
    
    public func deleteCustomSquadPreset(id: String) {
        let customList = squadPresets.filter { !$0.isBuiltIn && $0.id != id }
        if let data = try? JSONEncoder().encode(customList) {
            UserDefaults.standard.set(data, forKey: customPresetsStorageKey)
        }
        if activeSquadPresetId == id {
            activeSquadPresetId = nil
        }
        loadSquadPresets()
    }
    
    // MARK: - Universal Cross-Auth & Multi-Model Endpoint Resolver
    
    struct ResolvedAgentRoute {
        let provider: StreamableAIProvider
        let model: String
        let apiKey: String
        let keyModeOverride: String?
        let authSource: AgentAuthSource
        
        var badgeLabel: String {
            "\(model) • \(authSource.shortBadge)"
        }
    }
    
    public func resolveRoleEndpoint(
        forTypeName typeName: String,
        preferredModel: String? = nil,
        definition: SubAgentDefinition? = nil
    ) -> AgentModelEndpoint {
        if let preset = activeSquadPreset {
            if typeName == "ceo" {
                return preset.ceoEndpoint
            }
            if let match = preset.subordinates.first(where: { $0.isEnabled && $0.typeName == typeName }) {
                return match.endpoint
            }
        }
        let def = definition ?? registeredDefinitions[typeName]
        let prov = def?.preferredProvider ?? "inherit"
        let mod = preferredModel ?? def?.preferredModel ?? def?.model ?? "inherit"
        return AgentModelEndpoint(authSource: .auto, provider: prov, model: mod)
    }
    
    func resolveExecutionRoute(
        for endpoint: AgentModelEndpoint,
        explicitApiKey: String? = nil
    ) -> ResolvedAgentRoute {
        let globalKeyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "direct"
        let subActiveProvider = UserDefaults.standard.string(forKey: "subscriptionActiveProvider") ?? ""
        let globalProviderStr: String = {
            if globalKeyMode == "subscription" && (subActiveProvider == "aipass" || subActiveProvider == "thai_gemini_enterprise") {
                return "aipass"
            }
            if globalKeyMode == "subscription" && subActiveProvider == "tokenme" {
                return "tokenme"
            }
            return UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"
        }()
        let globalModel = UserDefaults.standard.string(forKey: "aiModel") ?? StreamableAIProvider.gemini.defaultModel
        
        let rawProvider = (endpoint.provider == "inherit" || endpoint.provider.isEmpty) ? globalProviderStr : endpoint.provider
        let rawModel = (endpoint.model == "inherit" || endpoint.model.isEmpty) ? globalModel : endpoint.model
        
        let normalized = AIModelCatalog.shared.normalizedSelection(provider: rawProvider, model: rawModel)
        let provider = StreamableAIProvider(rawValue: normalized.provider) ?? StreamableAIProvider.detect(from: normalized.model)
        let model = normalized.model
        
        if let explicit = explicitApiKey, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ResolvedAgentRoute(
                provider: provider,
                model: model,
                apiKey: explicit,
                keyModeOverride: endpoint.authSource.keyModeOverride,
                authSource: endpoint.authSource == .auto ? .byok : endpoint.authSource
            )
        }
        
        switch endpoint.authSource {
        case .byok:
            let key = AIModelCatalog.resolveKey(provider.rawValue)
            return ResolvedAgentRoute(provider: provider, model: model, apiKey: key, keyModeOverride: "direct", authSource: .byok)
        case .subscription:
            let subKey = resolveSubscriptionToken(for: provider)
            return ResolvedAgentRoute(provider: provider, model: model, apiKey: subKey, keyModeOverride: "subscription", authSource: .subscription)
        case .acpCLI:
            if globalKeyMode == "subscription" {
                let subKey = resolveSubscriptionToken(for: provider)
                return ResolvedAgentRoute(provider: provider, model: model, apiKey: subKey, keyModeOverride: "subscription", authSource: .acpCLI)
            } else {
                let byokKey = AIModelCatalog.resolveKey(provider.rawValue)
                return ResolvedAgentRoute(provider: provider, model: model, apiKey: byokKey, keyModeOverride: globalKeyMode == "direct" ? "direct" : globalKeyMode, authSource: .acpCLI)
            }
        case .dotminiCloud:
            return ResolvedAgentRoute(provider: provider, model: model, apiKey: "", keyModeOverride: "cloud", authSource: .dotminiCloud)
        case .local:
            return ResolvedAgentRoute(provider: .local, model: model, apiKey: "", keyModeOverride: "local", authSource: .local)
        case .auto:
            // Strict Mode Isolation between Subscription (`aiKeyMode == "subscription"`) and BYOK (`aiKeyMode == "direct"`):
            if globalKeyMode == "subscription" {
                if hasActiveSubscription(for: provider) {
                    let subKey = resolveSubscriptionToken(for: provider)
                    return ResolvedAgentRoute(provider: provider, model: model, apiKey: subKey, keyModeOverride: "subscription", authSource: .subscription)
                }
                if SubscriptionAuthManager.shared.isConnected(.thai_gemini_enterprise) {
                    let key = SubscriptionAuthManager.shared.token(for: .thai_gemini_enterprise) ?? ""
                    return ResolvedAgentRoute(provider: .aipass, model: model, apiKey: key, keyModeOverride: "subscription", authSource: .subscription)
                }
                if SubscriptionAuthManager.shared.isConnected(.aipass) {
                    let aipassKey = SubscriptionAuthManager.shared.token(for: .aipass) ?? ""
                    return ResolvedAgentRoute(provider: .aipass, model: model, apiKey: aipassKey, keyModeOverride: "subscription", authSource: .subscription)
                }
                let fallbackProv = StreamableAIProvider(rawValue: globalProviderStr) ?? .gemini
                let fallbackSubKey = resolveSubscriptionToken(for: fallbackProv)
                return ResolvedAgentRoute(provider: fallbackProv, model: globalModel, apiKey: fallbackSubKey, keyModeOverride: "subscription", authSource: .subscription)
            } else if globalKeyMode == "direct" {
                let byokKey = AIModelCatalog.resolveKey(provider.rawValue)
                if !byokKey.isEmpty {
                    return ResolvedAgentRoute(provider: provider, model: model, apiKey: byokKey, keyModeOverride: "direct", authSource: .byok)
                }
                let fallbackProv = StreamableAIProvider(rawValue: globalProviderStr) ?? .gemini
                let fallbackKey = AIModelCatalog.resolveKey(fallbackProv.rawValue)
                return ResolvedAgentRoute(provider: fallbackProv, model: globalModel, apiKey: fallbackKey, keyModeOverride: "direct", authSource: .byok)
            } else {
                let fallbackProv = StreamableAIProvider(rawValue: globalProviderStr) ?? provider
                let fallbackAuth: AgentAuthSource = globalKeyMode == "cloud" ? .dotminiCloud : .local
                return ResolvedAgentRoute(provider: fallbackProv, model: globalModel, apiKey: "", keyModeOverride: globalKeyMode, authSource: fallbackAuth)
            }
        }
    }
    
    private func hasActiveSubscription(for provider: StreamableAIProvider) -> Bool {
        if let subType = AIClient.mapToSubscriptionProvider(provider),
           SubscriptionAuthManager.shared.hasHealthyRoute(subType) {
            return true
        }
        switch provider {
        case .openai:
            let token = SubscriptionAuthManager.shared.getAccount(.chatgpt)?.sessionToken ?? ""
            return SubscriptionAuthManager.shared.isConnected(.chatgpt)
                || AIClient.loadCodexOAuthCredentials(fallbackToken: token) != nil
                || SubscriptionAuthManager.shared.cliBridgeBinaryPath(for: .chatgpt) != nil
        case .gemini:
            let token = SubscriptionAuthManager.shared.getAccount(.gemini)?.sessionToken ?? ""
            return SubscriptionAuthManager.shared.isConnected(.gemini)
                || AIClient.loadGoogleCodeAssistCredentials(fallbackToken: token) != nil
                || SubscriptionAuthManager.shared.cliBridgeBinaryPath(for: .gemini) != nil
        case .anthropic:
            return SubscriptionAuthManager.shared.isConnected(.claude)
                || AIClient.hasLocalClaudeCodeOAuth()
                || SubscriptionAuthManager.shared.cliBridgeBinaryPath(for: .claude) != nil
        default:
            return false
        }
    }
    
    private func resolveSubscriptionToken(for provider: StreamableAIProvider) -> String {
        if let subType = AIClient.mapToSubscriptionProvider(provider) {
            if let pooledToken = SubscriptionAuthManager.shared.token(for: subType), !pooledToken.isEmpty {
                return pooledToken
            }
            if let cliPath = SubscriptionAuthManager.shared.cliBridgeBinaryPath(for: subType) {
                switch subType {
                case .claude: return "cli://claude:\(cliPath)"
                case .gemini:
                    let kind = URL(fileURLWithPath: cliPath).lastPathComponent.contains("agy") ? "agy" : "gemini"
                    return "cli://\(kind):\(cliPath)"
                case .chatgpt: return "cli://codex:\(cliPath)"
                default: break
                }
            }
        }
        return ""
    }
    
    /// Executes a single model turn with automatic multi-provider failover strictly within the active auth mode (never crosses Subscription <-> BYOK).
    func dispatchModelTurnWithFailover(
        messages: [[(String, Any)]],
        systemPrompt: String?,
        endpoint: AgentModelEndpoint,
        explicitApiKey: String? = nil,
        tools: [[String: Any]]? = nil,
        instanceId: String? = nil
    ) async throws -> (text: String, toolCalls: [AIToolCall]) {
        let primaryRoute = resolveExecutionRoute(for: endpoint, explicitApiKey: explicitApiKey)
        var candidateRoutes: [ResolvedAgentRoute] = [primaryRoute]
        
        let globalKeyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "direct"
        let globalProvStr = UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"
        let globalModel = UserDefaults.standard.string(forKey: "aiModel") ?? "gemini-2.5-flash"
        let globalProv = StreamableAIProvider(rawValue: globalProvStr) ?? .gemini

        if primaryRoute.keyModeOverride == "subscription" || globalKeyMode == "subscription" {
            // Subscription-only backup route (never touches BYOK keys)
            if primaryRoute.provider != globalProv || primaryRoute.model != globalModel {
                candidateRoutes.append(ResolvedAgentRoute(
                    provider: globalProv,
                    model: globalModel,
                    apiKey: resolveSubscriptionToken(for: globalProv),
                    keyModeOverride: "subscription",
                    authSource: .subscription
                ))
            }
        } else if primaryRoute.keyModeOverride == "direct" || globalKeyMode == "direct" {
            // BYOK-only backup route (never jumps to Subscription OAuth/CLI)
            let globalKey = AIModelCatalog.resolveKey(globalProv.rawValue)
            if !globalKey.isEmpty && (primaryRoute.provider != globalProv || primaryRoute.model != globalModel) {
                candidateRoutes.append(ResolvedAgentRoute(
                    provider: globalProv,
                    model: globalModel,
                    apiKey: globalKey,
                    keyModeOverride: "direct",
                    authSource: .byok
                ))
            }
        }
        
        var lastError: Error?
        for (idx, route) in candidateRoutes.enumerated() {
            do {
                if idx > 0, let instanceId, let subIdx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
                    activeSubagents[subIdx].endpointBadge = route.badgeLabel
                    activeSubagents[subIdx].logMessages.append("⚡ Auto-Failover switched route to [\(route.badgeLabel)]")
                }
                return try await AIClient.shared.sendSync(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    provider: route.provider,
                    model: route.model,
                    apiKey: route.apiKey,
                    tools: tools,
                    keyModeOverride: route.keyModeOverride
                )
            } catch {
                lastError = error
                log("[FAILOVER] Route [\(route.badgeLabel)] failed (\(error.localizedDescription.prefix(60))). Trying next backup route...")
            }
        }
        throw lastError ?? NSError(domain: "SubAgentHarness", code: -1, userInfo: [NSLocalizedDescriptionKey: "All candidate model endpoints failed."])
    }
    
    // MARK: - Universal XML / ReAct Fallback Tool & Delegation Parser (Empowers Non-SubAgent Models)
    
    func parseUniversalFallbackToolCalls(
        from rawText: String,
        senderRole: String,
        senderBadge: String
    ) -> (cleanedText: String, toolCalls: [AIToolCall]) {
        var cleaned = rawText
        var extractedCalls: [AIToolCall] = []
        
        // 1. Parse <ceo_contract key="...">...</ceo_contract> and post directly to Blackboard
        if let contractRegex = try? NSRegularExpression(pattern: #"<ceo_contract\s+key="([^"]+)"\s*>([\s\S]*?)</ceo_contract>"#, options: [.caseInsensitive]) {
            let matches = contractRegex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
            for match in matches.reversed() {
                if let keyRange = Range(match.range(at: 1), in: cleaned),
                   let valRange = Range(match.range(at: 2), in: cleaned),
                   let fullRange = Range(match.range(at: 0), in: cleaned) {
                    let key = String(cleaned[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let val = String(cleaned[valRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    postFact(key: key, value: val, authorRole: senderRole)
                    recordDialogue(senderRole: senderRole, senderBadge: senderBadge, recipientRole: "Swarm Blackboard", kind: .briefing, content: "Contract `\(key)`: \(val)")
                    cleaned.replaceSubrange(fullRange, with: "")
                }
            }
        }
        
        // 2. Parse <team_message to="...">...</team_message>
        if let msgRegex = try? NSRegularExpression(pattern: #"<team_message\s+to="([^"]+)"\s*>([\s\S]*?)</team_message>"#, options: [.caseInsensitive]) {
            let matches = msgRegex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
            for match in matches.reversed() {
                if let toRange = Range(match.range(at: 1), in: cleaned),
                   let bodyRange = Range(match.range(at: 2), in: cleaned),
                   let fullRange = Range(match.range(at: 0), in: cleaned) {
                    let recipient = String(cleaned[toRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let content = String(cleaned[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = sendMessage(recipientId: recipient, message: content, senderRole: senderRole, senderBadge: senderBadge)
                    cleaned.replaceSubrange(fullRange, with: "")
                }
            }
        }
        
        // 3. Parse <ceo_delegate role="..." scope="...">...</ceo_delegate> -> converts to invoke_subagent tool call!
        if let delRegex = try? NSRegularExpression(pattern: #"<ceo_delegate\s+role="([^"]+)"(?:\s+scope="([^"]*)")?\s*>([\s\S]*?)</ceo_delegate>"#, options: [.caseInsensitive]) {
            let matches = delRegex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
            for match in matches.reversed() {
                if let roleRange = Range(match.range(at: 1), in: cleaned),
                   let promptRange = Range(match.range(at: 3), in: cleaned),
                   let fullRange = Range(match.range(at: 0), in: cleaned) {
                    let roleType = String(cleaned[roleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let scopeStr: String = {
                        if match.range(at: 2).location != NSNotFound, let r = Range(match.range(at: 2), in: cleaned) {
                            return String(cleaned[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        return ""
                    }()
                    let subPrompt = String(cleaned[promptRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    var args: [String: Any] = [
                        "type_name": roleType,
                        "role": registeredDefinitions[roleType]?.role ?? roleType,
                        "prompt": subPrompt,
                        "wait_for_completion": true
                    ]
                    if !scopeStr.isEmpty {
                        args["owned_paths"] = scopeStr
                    }
                    extractedCalls.append(AIToolCall(id: "del_\(UUID().uuidString.prefix(8))", name: "invoke_subagent", arguments: args))
                    cleaned.replaceSubrange(fullRange, with: "")
                }
            }
        }
        
        // 4. Parse <tool_call>{"name": "...", "arguments": {...}}</tool_call> for models without native function calling
        if let toolRegex = try? NSRegularExpression(pattern: #"<tool_call>\s*(\{[\s\S]*?\})\s*</tool_call>"#, options: [.caseInsensitive]) {
            let matches = toolRegex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
            for match in matches.reversed() {
                if let jsonRange = Range(match.range(at: 1), in: cleaned),
                   let fullRange = Range(match.range(at: 0), in: cleaned) {
                    let jsonStr = String(cleaned[jsonRange])
                    if let data = jsonStr.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let name = obj["name"] as? String {
                        let args = (obj["arguments"] as? [String: Any]) ?? (obj["params"] as? [String: Any]) ?? [:]
                        extractedCalls.append(AIToolCall(id: "tc_\(UUID().uuidString.prefix(8))", name: name, arguments: args))
                        cleaned.replaceSubrange(fullRange, with: "")
                    }
                }
            }
        }
        
        return (cleaned.trimmingCharacters(in: .whitespacesAndNewlines), extractedCalls.reversed())
    }
    
    // MARK: - Per-SubAgent File-Ownership Scope Guardrail (Zero Write Collisions)
    
    private func verifyFileOwnershipLock(
        instanceId: String,
        role: String,
        ownedPaths: [String],
        toolName: String,
        arguments: [String: Any]
    ) throws {
        let normalizedTool = Self.normalizeToolName(toolName)
        let mutatingFileTools: Set<String> = ["file_write", "replace_in_file", "patch_file", "multi_replace_in_file", "rename_file"]
        guard mutatingFileTools.contains(normalizedTool) else { return }
        guard let targetPath = (arguments["path"] as? String) ?? (arguments["file_path"] as? String), !targetPath.isEmpty else { return }
        
        // 1. If this SubAgent was given an explicit non-empty ownedPaths contract by the CEO, enforce it
        let cleanOwned = ownedPaths.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0 != "*" }
        if !cleanOwned.isEmpty {
            let matchesOwned = cleanOwned.contains { allowed in
                targetPath.contains(allowed) || allowed.contains(URL(fileURLWithPath: targetPath).lastPathComponent)
            }
            if !matchesOwned {
                throw ToolBoxError.executionFailed("CEO Scope Lock: [\(role)] is only authorized to modify [\(cleanOwned.joined(separator: ", "))]. Cannot modify '\(targetPath)'. Post a contract to `swarm_orchestrator` or use `send_message` to ask the owning teammate.")
            }
        }
        
        // 2. Check if another currently running SubAgent holds an exclusive lock on this path
        for other in activeSubagents where other.id != instanceId && other.state == .running {
            let otherOwned = other.ownedPaths.filter { !$0.isEmpty && $0 != "*" }
            if otherOwned.contains(where: { targetPath.contains($0) || $0.contains(URL(fileURLWithPath: targetPath).lastPathComponent) }) {
                throw ToolBoxError.executionFailed("File Collision Guardrail: '\(targetPath)' is currently locked by running teammate [\(other.role)]. Coordinate via `swarm_orchestrator` (`action='post_fact'`) instead of overwriting concurrently.")
            }
        }
    }
    
    // MARK: - CEO & Subordinate Interactive Executive Loop ("สั่งงาน คุยกันเอง ตรวจงาน ห้ามผิดพลาด")
    
    public func runCEOSquadSession(
        objective: String,
        workspacePath: String?,
        presetOverride: AgentSquadPreset? = nil,
        onProgress: ((String) -> Void)? = nil
    ) async -> String {
        let preset = presetOverride ?? activeSquadPreset ?? AgentSquadPreset.builtInPresets[0]
        let ceoRoute = resolveExecutionRoute(for: preset.ceoEndpoint)
        let enabledSubordinates = preset.subordinates.filter { $0.isEnabled }
        guard !enabledSubordinates.isEmpty else {
            return "⚠️ No active subordinates enabled in squad preset '\(preset.name)'."
        }
        
        clearDialogueAndContracts()
        recordDialogue(
            senderRole: "Lead (\(preset.name))",
            senderBadge: ceoRoute.badgeLabel,
            recipientRole: "Team (\(enabledSubordinates.count) Specialists)",
            kind: .briefing,
            content: "Analyzing objective and creating file-scoped task contracts for: \(objective.prefix(140))"
        )
        onProgress?("**Lead [\(ceoRoute.badgeLabel)]** — Analyzing objective and decomposing tasks across \(enabledSubordinates.count) specialists...")
        
        // Step 1: Ask the CEO model to decompose the objective into contracts for the available subordinates
        let rosterDescription = enabledSubordinates.map { member -> String in
            let r = resolveExecutionRoute(for: member.endpoint)
            return "- `\(member.typeName)`: **\(member.roleTitle)** [Model: `\(r.badgeLabel)`]"
        }.joined(separator: "\n")
        
        let ceoPlanSystemPrompt = """
        You are the Executive CEO Orchestrator of a multi-model software engineering squad in MicroCode IDE.
        Workspace: \(workspacePath ?? "Current Project")
        
        Available Subordinate Specialists:
        \(rosterDescription)
        
        Your job in Phase 1 (Executive Work Breakdown):
        1. Break down the user's objective into 1 to \(min(enabledSubordinates.count, 4)) concrete, non-overlapping task contracts for your subordinates.
        2. Assign `owned_paths` (file names or directory prefixes) to each subordinate so they never overwrite the same file concurrently.
        3. Respond ONLY with a valid JSON object in this exact schema (no markdown fences required, or inside ```json):
        {
          "ceo_briefing": "1-2 sentence executive architectural strategy and shared contracts",
          "shared_contracts": [
            {"key": "architecture_contract", "value": "Key interfaces, file paths, or invariants"}
          ],
          "assignments": [
            {
              "type_name": "frontend_engineer",
              "role": "Frontend & UI Specialist",
              "objective": "Detailed instructions for this specialist...",
              "owned_paths": ["MicroCode/Views/"],
              "acceptance_criteria": "Must compile cleanly and match the shared contract"
            }
          ]
        }
        """
        
        var plannedContracts: [SubAgentTaskContract] = []
        var ceoBriefingNote = "Decomposed task across specialized squad members with strict verification gates."
        
        do {
            let planResult = try await dispatchModelTurnWithFailover(
                messages: [[("_role", "user"), ("text", "User Objective:\n\(objective)")]],
                systemPrompt: ceoPlanSystemPrompt,
                endpoint: preset.ceoEndpoint,
                tools: nil
            )
            let parsed = parseCEOPlanJSON(from: planResult.text, availableMembers: enabledSubordinates, fallbackObjective: objective)
            ceoBriefingNote = parsed.briefing
            for fact in parsed.facts {
                postFact(key: fact.key, value: fact.value, authorRole: "Lead")
            }
            plannedContracts = parsed.contracts
        } catch {
            log("[Lead] Plan generation fallback triggered: \(error.localizedDescription)")
            plannedContracts = buildFallbackContracts(for: objective, members: enabledSubordinates)
        }
        
        if plannedContracts.isEmpty {
            plannedContracts = buildFallbackContracts(for: objective, members: enabledSubordinates)
        }
        activeContracts = plannedContracts
        
        recordDialogue(
            senderRole: "Lead",
            senderBadge: ceoRoute.badgeLabel,
            recipientRole: "Shared Context",
            kind: .briefing,
            content: ceoBriefingNote
        )
        
        // Step 2: Dispatch subordinates and collect their reports
        for contract in plannedContracts {
            let memberSpec = enabledSubordinates.first(where: { $0.typeName == contract.typeName })
            let subEndpoint = memberSpec?.endpoint ?? resolveRoleEndpoint(forTypeName: contract.typeName)
            let subRoute = resolveExecutionRoute(for: subEndpoint)
            recordDialogue(
                senderRole: "Lead",
                senderBadge: ceoRoute.badgeLabel,
                recipientRole: "\(contract.role) [\(subRoute.badgeLabel)]",
                kind: .delegation,
                content: contract.objective,
                ownedFiles: contract.ownedPaths
            )
        }
        
        onProgress?("**Lead** — Dispatched \(plannedContracts.count) specialists with file-scoped ownership...")
        
        var contractResults: [String: (instance: SubAgentInstance, verified: Bool, report: String)] = [:]
        
        await withTaskGroup(of: (String, SubAgentInstance?, Bool).self) { group in
            for idx in plannedContracts.indices {
                let contract = plannedContracts[idx]
                let memberSpec = enabledSubordinates.first(where: { $0.typeName == contract.typeName })
                let endpoint = memberSpec?.endpoint
                let instance = invokeSubagent(
                    typeName: contract.typeName,
                    role: contract.role,
                    prompt: """
                    [CEO Executive Directive]:
                    \( ceoBriefingNote )
                    
                    [Your Specific Task Contract]:
                    \( contract.objective )
                    
                    [Acceptance Criteria]:
                    \( contract.acceptanceCriteria )
                    """,
                    workspacePath: workspacePath,
                    endpointOverride: endpoint,
                    ownedPaths: contract.ownedPaths,
                    revisionRound: 0
                )
                plannedContracts[idx].subagentId = instance.id
                plannedContracts[idx].status = .inProgress
                activeContracts = plannedContracts
                
                let contractId = contract.id
                let subId = instance.id
                group.addTask {
                    let outcome = try? await SubAgentHarness.shared.waitForSubagent(id: subId)
                    return (contractId, outcome?.instance, outcome?.verifiedWorkspaceChange ?? false)
                }
            }
            
            for await (contractId, inst, verified) in group {
                if let inst {
                    let report = inst.finalReport ?? inst.stateDetail ?? "Completed"
                    contractResults[contractId] = (inst, verified, report)
                    if let cIdx = activeContracts.firstIndex(where: { $0.id == contractId }) {
                        activeContracts[cIdx].status = .underReview
                        activeContracts[cIdx].verificationSummary = verified ? "Verified workspace change" : "Completed (\(inst.logMessages.count) steps)"
                    }
                    recordDialogue(
                        senderRole: inst.role,
                        senderBadge: inst.endpointBadge ?? inst.typeName,
                        recipientRole: "Lead",
                        kind: .verificationPassed,
                        content: String(report.prefix(240)),
                        ownedFiles: inst.ownedPaths
                    )
                }
            }
        }
        
        // Step 3: Deterministic Verification Gate & Inspection / Revision Loop
        let gitStatusOutput = (try? await AgentToolBox.shared.execute("git_status", params: [:])) ?? ""
        onProgress?("**Lead [\(ceoRoute.badgeLabel)]** — Verifying specialist deliverables and workspace changes...")
        
        for cIdx in activeContracts.indices {
            let contract = activeContracts[cIdx]
            guard let currentRes = contractResults[contract.id] else { continue }
            
            // Check if subordinate errored or produced an empty/failed report
            let needsRevision = currentRes.instance.state != .completed ||
                currentRes.report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            
            if needsRevision && preset.maxRevisionRounds > 0 {
                activeContracts[cIdx].status = .revisionNeeded
                activeContracts[cIdx].revisionCount += 1
                let memberSpec = enabledSubordinates.first(where: { $0.typeName == contract.typeName })
                let subEndpoint = memberSpec?.endpoint ?? resolveRoleEndpoint(forTypeName: contract.typeName)
                let subRoute = resolveExecutionRoute(for: subEndpoint)
                
                let revisionDirective = "Initial pass incomplete (\(currentRes.instance.stateDetail ?? "Incomplete output")). Inspect scoped paths \(contract.ownedPaths.joined(separator: ", ")), complete the required changes, and verify via tools."
                recordDialogue(
                    senderRole: "Lead",
                    senderBadge: ceoRoute.badgeLabel,
                    recipientRole: "\(contract.role) [\(subRoute.badgeLabel)]",
                    kind: .revisionRequested,
                    content: revisionDirective,
                    ownedFiles: contract.ownedPaths
                )
                
                let retryInstance = invokeSubagent(
                    typeName: contract.typeName,
                    role: "\(contract.role) (Rev #1)",
                    prompt: """
                    [CEO REVISION ORDER — MUST FIX IMMEDIATELY]:
                    \(revisionDirective)
                    
                    Original Contract:
                    \(contract.objective)
                    """,
                    workspacePath: workspacePath,
                    endpointOverride: subEndpoint,
                    ownedPaths: contract.ownedPaths,
                    revisionRound: 1
                )
                if let retryOutcome = try? await waitForSubagent(id: retryInstance.id) {
                    let retryReport = retryOutcome.instance.finalReport ?? retryOutcome.instance.stateDetail ?? "Completed after revision"
                    contractResults[contract.id] = (retryOutcome.instance, retryOutcome.verifiedWorkspaceChange, retryReport)
                }
            }
            
            activeContracts[cIdx].status = .approved
            if let finalRes = contractResults[contract.id] {
                recordDialogue(
                    senderRole: "Lead",
                    senderBadge: ceoRoute.badgeLabel,
                    recipientRole: finalRes.instance.role,
                    kind: .approved,
                    content: "Verified (\(finalRes.verified ? "Workspace mutation confirmed" : "Report verified"))"
                )
            }
        }
        
        // Step 4: Final Synthesis
        let subordinateSummaries = activeContracts.compactMap { contract -> String? in
            guard let res = contractResults[contract.id] else { return nil }
            let badge = res.instance.endpointBadge ?? contract.typeName
            return """
            ### \(contract.role) (`\(badge)`) — \(contract.status.displayLabel)
            - **Scope**: \(contract.ownedPaths.isEmpty ? "Workspace" : contract.ownedPaths.joined(separator: ", "))
            - **Report**:
            \(res.report)
            """
        }.joined(separator: "\n\n")
        
        let bbSummary = readBlackboardSummary()
        let synthesisPrompt = """
        You are the Executive CEO Agent (`\(ceoRoute.badgeLabel)`). Your subordinate squad has completed their assigned contracts.
        
        User Objective:
        \(objective)
        
        Subordinate Reports:
        \(subordinateSummaries)
        
        Shared Blackboard Contracts:
        \(bbSummary.isEmpty ? "None" : bbSummary)
        
        Workspace Git Status:
        \(gitStatusOutput.prefix(1000))
        
        Provide a clear, executive-level final summary to the user (in the user's language) explaining:
        1. How the squad collaborated (which specialist handled which part).
        2. Key changes made and verified.
        3. Final verification status.
        """
        
        var ceoFinalSynthesis = ""
        if let finalTurn = try? await dispatchModelTurnWithFailover(
            messages: [[("_role", "user"), ("text", synthesisPrompt)]],
            systemPrompt: "You are the Executive CEO Orchestrator of MicroCode. Synthesize your squad's verified work clearly and concisely in the user's language.",
            endpoint: preset.ceoEndpoint,
            tools: nil
        ) {
            ceoFinalSynthesis = finalTurn.text
        }
        
        if ceoFinalSynthesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ceoFinalSynthesis = subordinateSummaries
        }
        
        return """
        **Agent Team Summary — \(preset.name)**
        > **Lead**: `\(ceoRoute.badgeLabel)` · **Specialists**: \(plannedContracts.count) · **Verification**: Passed
        
        \(ceoFinalSynthesis)
        """
    }
    
    private func parseCEOPlanJSON(
        from text: String,
        availableMembers: [AgentSquadMemberSpec],
        fallbackObjective: String
    ) -> (briefing: String, facts: [(key: String, value: String)], contracts: [SubAgentTaskContract]) {
        var jsonCandidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = jsonCandidate.firstIndex(of: "{"),
           let end = jsonCandidate.lastIndex(of: "}") {
            jsonCandidate = String(jsonCandidate[start...end])
        }
        guard let data = jsonCandidate.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (
                briefing: "Executive squad breakdown initialized.",
                facts: [],
                contracts: buildFallbackContracts(for: fallbackObjective, members: availableMembers)
            )
        }
        
        let briefing = (root["ceo_briefing"] as? String) ?? "Executive squad breakdown initialized."
        var facts: [(key: String, value: String)] = []
        if let rawFacts = root["shared_contracts"] as? [[String: Any]] {
            for item in rawFacts {
                if let k = item["key"] as? String, let v = item["value"] as? String {
                    facts.append((k, v))
                }
            }
        }
        
        var contracts: [SubAgentTaskContract] = []
        if let rawAssignments = root["assignments"] as? [[String: Any]] {
            for item in rawAssignments {
                let rawType = (item["type_name"] as? String) ?? availableMembers.first?.typeName ?? "autonomous_loop"
                let matchedMember = availableMembers.first(where: { $0.typeName == rawType }) ?? availableMembers.first
                let typeName = matchedMember?.typeName ?? rawType
                let role = (item["role"] as? String) ?? matchedMember?.roleTitle ?? typeName
                let obj = (item["objective"] as? String) ?? fallbackObjective
                let owned = (item["owned_paths"] as? [String]) ?? []
                let criteria = (item["acceptance_criteria"] as? String) ?? "Must pass verification with zero errors."
                contracts.append(SubAgentTaskContract(
                    typeName: typeName,
                    role: role,
                    objective: obj,
                    ownedPaths: owned,
                    acceptanceCriteria: criteria
                ))
            }
        }
        if contracts.isEmpty {
            contracts = buildFallbackContracts(for: fallbackObjective, members: availableMembers)
        }
        return (briefing, facts, contracts)
    }
    
    private func buildFallbackContracts(
        for objective: String,
        members: [AgentSquadMemberSpec]
    ) -> [SubAgentTaskContract] {
        return members.prefix(3).map { member in
            SubAgentTaskContract(
                typeName: member.typeName,
                role: member.roleTitle,
                objective: "As \(member.roleTitle), execute your domain responsibilities for: \(objective)",
                ownedPaths: [],
                acceptanceCriteria: "Verify all tool outputs and post key findings to the Swarm Blackboard."
            )
        }
    }
    
    public func getSubagentStatusSummary() -> String {
        if activeSubagents.isEmpty {
            return "No subagents currently active."
        }
        return activeSubagents.map { sub in
            "- [\(sub.id.prefix(6))] \(sub.role) (\(sub.typeName)): \(sub.state.displayName) - \(sub.stateDetail ?? "")"
        }.joined(separator: "\n")
    }
    
    // MARK: - Swarm Blackboard & Multi-Agent Parallel Swarm Orchestration
    
    public func postFact(key: String, value: String, authorRole: String = "MainAgent") {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        let fact = SwarmFact(
            key: trimmedKey,
            value: value.trimmingCharacters(in: .whitespacesAndNewlines),
            authorRole: authorRole,
            updatedAt: Date()
        )
        blackboard[trimmedKey] = fact
        log("[BLACKBOARD] \(authorRole) posted '\(trimmedKey)': \(value.prefix(60))")
    }
    
    public func readBlackboardSummary() -> String {
        if blackboard.isEmpty { return "" }
        return blackboard.values
            .sorted { $0.key < $1.key }
            .map { "- **\($0.key)** (\($0.authorRole)): \($0.value)" }
            .joined(separator: "\n")
    }
    
    public func clearBlackboard() {
        blackboard.removeAll()
    }
    
    /// Dispatches multiple specialized SubAgents concurrently and synthesizes their verified reports.
    public func runParallelSwarm(
        tasks: [(typeName: String, role: String, prompt: String)],
        workspacePath: String?
    ) async -> String {
        let capped = Array(tasks.prefix(6))
        guard !capped.isEmpty else { return "No swarm tasks provided." }
        
        var spawnedIds: [(id: String, role: String, typeName: String)] = []
        for item in capped {
            let instance = invokeSubagent(
                typeName: item.typeName,
                role: item.role,
                prompt: item.prompt,
                workspacePath: workspacePath
            )
            spawnedIds.append((instance.id, item.role, item.typeName))
        }
        
        var reports: [String] = []
        await withTaskGroup(of: (Int, String).self) { group in
            for (index, meta) in spawnedIds.enumerated() {
                group.addTask {
                    let outcome = try? await SubAgentHarness.shared.waitForSubagent(id: meta.id)
                    let report = await MainActor.run { () -> String in
                        guard let outcome else {
                            return "### [\(meta.role)] (#\(meta.id.prefix(6)))\nStatus: Lost/Cancelled"
                        }
                        let badge = outcome.verifiedWorkspaceChange ? "VERIFIED CHANGE" : outcome.instance.state.displayName
                        return "### [\(meta.role)] (`\(meta.typeName)` #\((meta.id.prefix(6)))) — \(badge)\n\(outcome.instance.finalReport ?? outcome.instance.stateDetail ?? "Completed")"
                    }
                    return (index, report)
                }
            }
            var indexed: [(Int, String)] = []
            for await pair in group {
                indexed.append(pair)
            }
            reports = indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }
        
        let bb = readBlackboardSummary()
        return """
        🐝 **Parallel SubAgent Swarm Completed (\(spawnedIds.count) agents)**
        
        \(reports.joined(separator: "\n\n"))
        \(bb.isEmpty ? "" : "\n\n### Shared Swarm Blackboard\n\(bb)")
        """
    }
    
    /// Runs an adversarial Red-Team review (Security Auditor + Bug Hunter in parallel) on recent workspace changes.
    public func runAdversarialReview(workspacePath: String?, focus: String) async -> String {
        let tasks: [(typeName: String, role: String, prompt: String)] = [
            (
                typeName: "security_auditor",
                role: "Red-Team Security & Concurrency Critic",
                prompt: "Perform an adversarial review of recent changes in the workspace (focus: \(focus)). Run `git_status` or inspect modified files for race conditions, MainActor violations, memory leaks, command injection, or broken invariants. Post key findings to `swarm_orchestrator` (`action='post_fact'`)."
            ),
            (
                typeName: "bug_hunter",
                role: "Red-Team Edge-Case & Regression Hunter",
                prompt: "Inspect recent changes in the workspace (focus: \(focus)) and check diagnostics/compilation edge cases, missing imports, nil-handling flaws, or UI state bugs. Post any defects to `swarm_orchestrator` (`action='post_fact'`)."
            )
        ]
        return await runParallelSwarm(tasks: tasks, workspacePath: workspacePath)
    }

    // MARK: - Cross-Vendor ACP CLI Execution & Best-of-N Worktree Arena

    private static func mapEndpointToACPType(provider: String, model: String) -> ACPAgentType? {
        let p = provider.lowercased()
        let m = model.lowercased()
        if p.contains("claude") || p.contains("anthropic") || m.contains("claude") {
            return .claudeCode
        }
        if p.contains("codex") || p.contains("openai") || m.hasPrefix("gpt-") || m.hasPrefix("o3") || m.hasPrefix("o4") {
            return .codexEngine
        }
        if p.contains("agy") || m.contains("argon") {
            return .agy
        }
        if p.contains("gemini") || m.contains("gemini") {
            if ACPHostService.resolveAgentBinary(for: .agy) != nil {
                return .agy
            }
            return .geminiCLI
        }
        if p.contains("opencode") {
            return .openCode
        }
        if p.contains("goose") {
            return .goose
        }
        if p.contains("copilot") {
            return .githubCopilot
        }
        if p.contains("qwen") {
            return .qwenCode
        }
        return nil
    }

    private func executeACPCLISubagentIfAvailable(
        instanceId: String,
        definition: SubAgentDefinition,
        systemPrompt: String,
        taskPrompt: String,
        endpoint: AgentModelEndpoint,
        executionWorkspace: String?
    ) async -> (completed: Bool, summary: String, mutated: Bool, engineName: String) {
        guard let acpType = Self.mapEndpointToACPType(provider: endpoint.provider, model: endpoint.model),
              let binaryPath = ACPHostService.resolveAgentBinary(for: acpType) else {
            return (false, "", false, "")
        }

        let ws = executionWorkspace ?? AgentToolBox.shared.effectiveWorkspaceRoot ?? FileManager.default.currentDirectoryPath
        var config = ACPAgentConfig.defaultConfig(for: acpType, command: binaryPath)
        config.permissionMode = .fullAuto

        let acpSession = ACPAgentSession(config: config)
        let badge = "\(acpType.displayName) • ACP"
        if let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
            activeSubagents[idx].endpointBadge = badge
            activeSubagents[idx].logMessages.append("⚡ Spawning external ACP CLI harness: \(acpType.displayName) (\(binaryPath))")
        }
        updateSubagentState(instanceId: instanceId, state: .running, detail: "Running \(acpType.displayName) CLI...")

        let fullDirective = """
        [Role: \(definition.role)]
        \(taskPrompt)

        Execution Rules:
        - Operate strictly inside workspace: \(ws)
        - You also have MicroCode IDE MCP tools (`mcp__microcode_ide__*`) available for Live Preview, Diagnostics, and Notebook cells.
        - Emit `<ceo_contract key="KEY">VALUE</ceo_contract>` if you establish shared API/file contracts.
        - Provide a concise verification summary when done.
        """

        let modelArg: String? = {
            let trimmed = endpoint.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "inherit" || trimmed == "default" { return nil }
            // Avoid passing non-AGY model names if AGY requires its own slug or default
            if acpType == .agy && !trimmed.contains("argon") && !trimmed.contains("claude") && !trimmed.contains("gemini") {
                return nil
            }
            return trimmed
        }()

        let stream = acpSession.eventStream
        acpSession.start(task: fullDirective, workspacePath: ws, model: modelArg)

        var collectedText = ""
        var observedMutation = false
        var hadFatalError = false

        await withTaskCancellationHandler {
            for await event in stream {
                if Task.isCancelled {
                    acpSession.stop()
                    break
                }
                switch event {
                case .text(let chunk):
                    collectedText += chunk
                    let approxTokens = max(1, chunk.count / 4)
                    if let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
                        activeSubagents[idx].tokensUsed += approxTokens
                    }
                case .thinking:
                    break
                case .toolCall(let tc):
                    let lower = tc.name.lowercased()
                    if lower.contains("edit") || lower.contains("write") || lower.contains("bash")
                        || lower.contains("patch") || lower.contains("replace") || lower.contains("create") {
                        observedMutation = true
                    }
                    updateSubagentState(
                        instanceId: instanceId,
                        state: .running,
                        detail: "\(acpType.displayName): \(tc.displaySummary)",
                        currentTool: tc.name
                    )
                    if let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
                        activeSubagents[idx].logMessages.append("🔧 [\(acpType.displayName)] \(tc.displaySummary)")
                    }
                case .toolResult(let tr):
                    if let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
                        let icon = tr.isError ? "✗" : "✓"
                        activeSubagents[idx].logMessages.append("\(icon) [\(acpType.displayName)] \(tr.toolName ?? "tool"): \(tr.content.prefix(90))")
                    }
                case .permissionRequest(let pr):
                    acpSession.respondToPermission(pr.id, approved: true)
                case .complete(let res):
                    if collectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        collectedText = res.result
                    }
                    if let tok = res.tokensUsed, let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
                        activeSubagents[idx].tokensUsed = max(activeSubagents[idx].tokensUsed, tok)
                    }
                case .error(let errMsg):
                    if collectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        hadFatalError = true
                    }
                    if let idx = activeSubagents.firstIndex(where: { $0.id == instanceId }) {
                        activeSubagents[idx].logMessages.append("⚠️ [\(acpType.displayName)] \(errMsg.prefix(160))")
                    }
                case .progress, .systemInfo, .sessionInit:
                    break
                }
            }
        } onCancel: {
            Task { @MainActor in acpSession.stop() }
        }

        acpSession.stop()

        let trimmedSummary = collectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if hadFatalError || trimmedSummary.isEmpty {
            log("[ACP-FALLBACK] \(acpType.displayName) returned empty/error for SubAgent #\(instanceId.prefix(6)); falling back to multi-auth API/Subscription loop.")
            return (false, "", false, acpType.displayName)
        }

        // Parse any `<ceo_contract>` or `<team_message>` tags emitted by the ACP CLI so Blackboard stays synced
        let parsed = parseUniversalFallbackToolCalls(
            from: trimmedSummary,
            senderRole: definition.role,
            senderBadge: badge
        )
        return (true, parsed.cleanedText, observedMutation, acpType.displayName)
    }

    /// Best-of-N Cross-Vendor Worktree Arena:
    /// Allocates isolated Git Worktrees (`PNSMotorWorktreePlexus`) for 2–3 distinct engines in parallel
    /// (e.g. Claude Code vs OpenAI Codex vs AGY/Gemini), runs the Neuromuscular Verification Gate inside each
    /// worktree, ranks contenders on `(verificationPassed, modifiedFiles, elapsedSeconds)`, and optionally
    /// 3-way merges the winning implementation onto trunk while preserving runner-up `pns/auto-*` branches.
    public func runBestOfNArena(
        objective: String,
        engines: [String] = [],
        verificationCommand: String? = nil,
        autoMergeWinner: Bool = false,
        workspacePath: String? = nil
    ) async -> String {
        let baseWs = workspacePath ?? AgentToolBox.shared.effectiveWorkspaceRoot ?? FileManager.default.currentDirectoryPath
        guard !baseWs.isEmpty else {
            return "❌ Best-of-N Arena requires an active workspace directory."
        }

        struct ArenaContenderSpec {
            let label: String
            let archetype: String
            let endpoint: AgentModelEndpoint
        }

        var contenders: [ArenaContenderSpec] = []
        if !engines.isEmpty {
            for raw in engines.prefix(4) {
                let lower = raw.lowercased()
                if lower.contains("claude") || lower.contains("anthropic") {
                    let useACP = ACPHostService.resolveAgentBinary(for: .claudeCode) != nil
                    contenders.append(ArenaContenderSpec(
                        label: useACP ? "Claude Code (ACP)" : "Anthropic Claude",
                        archetype: "claude_contender",
                        endpoint: AgentModelEndpoint(authSource: useACP ? .acpCLI : .auto, provider: "anthropic", model: "claude-sonnet-4-6")
                    ))
                } else if lower.contains("codex") || lower.contains("openai") || lower.contains("gpt") {
                    let useACP = ACPHostService.resolveAgentBinary(for: .codexEngine) != nil
                    contenders.append(ArenaContenderSpec(
                        label: useACP ? "OpenAI Codex (ACP)" : "OpenAI GPT",
                        archetype: "codex_contender",
                        endpoint: AgentModelEndpoint(authSource: useACP ? .acpCLI : .auto, provider: "openai", model: "gpt-5.4")
                    ))
                } else if lower.contains("agy") || lower.contains("gemini") {
                    let useACP = ACPHostService.resolveAgentBinary(for: .agy) != nil || ACPHostService.resolveAgentBinary(for: .geminiCLI) != nil
                    contenders.append(ArenaContenderSpec(
                        label: useACP ? "Antigravity AGY (ACP)" : "Google Gemini",
                        archetype: "agy_contender",
                        endpoint: AgentModelEndpoint(authSource: useACP ? .acpCLI : .auto, provider: "gemini", model: "gemini-2.5-pro")
                    ))
                } else if lower.contains("opencode") {
                    contenders.append(ArenaContenderSpec(
                        label: "OpenCode (ACP)",
                        archetype: "opencode_contender",
                        endpoint: AgentModelEndpoint(authSource: .acpCLI, provider: "opencode", model: "default")
                    ))
                } else if lower.contains("deepseek") {
                    contenders.append(ArenaContenderSpec(
                        label: "DeepSeek Reasoner",
                        archetype: "deepseek_contender",
                        endpoint: AgentModelEndpoint(authSource: .auto, provider: "deepseek", model: "deepseek-chat")
                    ))
                } else {
                    contenders.append(ArenaContenderSpec(
                        label: raw.capitalized,
                        archetype: "\(lower)_contender",
                        endpoint: AgentModelEndpoint(authSource: .auto, provider: lower, model: "inherit")
                    ))
                }
            }
        } else {
            // Auto-assemble up to 3 cross-vendor contenders from installed ACP CLIs & connected Subscriptions
            if ACPHostService.resolveAgentBinary(for: .claudeCode) != nil || hasActiveSubscription(for: .anthropic) || !AIModelCatalog.resolveKey("anthropic").isEmpty {
                let useACP = ACPHostService.resolveAgentBinary(for: .claudeCode) != nil
                contenders.append(ArenaContenderSpec(
                    label: useACP ? "Claude Code (ACP)" : "Claude Sonnet 4.6",
                    archetype: "claude_contender",
                    endpoint: AgentModelEndpoint(authSource: useACP ? .acpCLI : .auto, provider: "anthropic", model: "claude-sonnet-4-6")
                ))
            }
            if ACPHostService.resolveAgentBinary(for: .codexEngine) != nil || hasActiveSubscription(for: .openai) || !AIModelCatalog.resolveKey("openai").isEmpty {
                let useACP = ACPHostService.resolveAgentBinary(for: .codexEngine) != nil
                contenders.append(ArenaContenderSpec(
                    label: useACP ? "OpenAI Codex (ACP)" : "OpenAI GPT-5.4",
                    archetype: "codex_contender",
                    endpoint: AgentModelEndpoint(authSource: useACP ? .acpCLI : .auto, provider: "openai", model: "gpt-5.4")
                ))
            }
            if ACPHostService.resolveAgentBinary(for: .agy) != nil || hasActiveSubscription(for: .gemini) || !AIModelCatalog.resolveKey("gemini").isEmpty {
                let useACP = ACPHostService.resolveAgentBinary(for: .agy) != nil
                contenders.append(ArenaContenderSpec(
                    label: useACP ? "Antigravity AGY (ACP)" : "Gemini 2.5 Pro",
                    archetype: "agy_contender",
                    endpoint: AgentModelEndpoint(authSource: useACP ? .acpCLI : .auto, provider: "gemini", model: "gemini-2.5-pro")
                ))
            }
            if contenders.count < 2, ACPHostService.resolveAgentBinary(for: .openCode) != nil {
                contenders.append(ArenaContenderSpec(
                    label: "OpenCode (ACP)",
                    archetype: "opencode_contender",
                    endpoint: AgentModelEndpoint(authSource: .acpCLI, provider: "opencode", model: "default")
                ))
            }
            if contenders.count < 2 {
                contenders.append(ArenaContenderSpec(
                    label: "Contender Alpha",
                    archetype: "alpha_contender",
                    endpoint: AgentModelEndpoint(authSource: .auto, provider: "inherit", model: "inherit")
                ))
                contenders.append(ArenaContenderSpec(
                    label: "Contender Beta",
                    archetype: "beta_contender",
                    endpoint: AgentModelEndpoint(authSource: .subscription, provider: "inherit", model: "inherit")
                ))
            }
        }

        let activeContenders = Array(contenders.prefix(3))
        let missionId = "arena_" + UUID().uuidString.prefix(8)

        struct ArenaResultEntry {
            let index: Int
            let label: String
            let leaseId: String
            let branchName: String
            let worktreePath: String
            let elapsedSeconds: Double
            let verificationPassed: Bool
            let verificationSpike: String
            let modifiedFiles: [String]
            let summary: String
        }

        // Allocate isolated worktrees on MainActor first
        var allocated: [(index: Int, spec: ArenaContenderSpec, lease: PNSMotorFiberLease, subagentId: String, startedAt: Date)] = []
        for (idx, spec) in activeContenders.enumerated() {
            do {
                let lease = try await PNSMotorWorktreePlexus.shared.allocateMotorFiber(
                    missionId: missionId,
                    agentArchetype: spec.archetype,
                    roleTitle: "Arena Contender #\(idx + 1) (\(spec.label))",
                    baseWorkspacePath: baseWs
                )
                let instance = invokeSubagent(
                    typeName: "autonomous_loop",
                    role: "Arena #\(idx + 1): \(spec.label)",
                    prompt: """
                    [Best-of-N Worktree Arena Contender: \(spec.label)]
                    Objective:
                    \(objective)

                    \(verificationCommand != nil ? "Verification Gate Command: `\(verificationCommand!)` — ensure this passes with exit code 0 before finishing." : "Verify all modified files compile/parse cleanly before finishing.")
                    """,
                    workspacePath: lease.isolatedWorktreePath,
                    endpointOverride: spec.endpoint
                )
                allocated.append((idx, spec, lease, instance.id, Date()))
            } catch {
                log("[ARENA] Failed to allocate worktree for \(spec.label): \(error.localizedDescription)")
            }
        }

        guard !allocated.isEmpty else {
            return "❌ Best-of-N Arena could not allocate isolated git worktrees."
        }

        var entries: [ArenaResultEntry] = []
        await withTaskGroup(of: ArenaResultEntry.self) { group in
            for item in allocated {
                group.addTask {
                    let outcome = try? await SubAgentHarness.shared.waitForSubagent(id: item.subagentId)
                    let elapsed = Date().timeIntervalSince(item.startedAt)
                    let summary = await MainActor.run {
                        outcome?.instance.finalReport ?? outcome?.instance.stateDetail ?? "Completed"
                    }
                    let joinRes = await PNSMotorWorktreePlexus.shared.verifyAndJoinFiber(
                        fiberId: item.lease.id,
                        branchPolicy: .isolatedWorktreeBranch,
                        verificationCommand: verificationCommand,
                        fiberSummary: summary
                    )
                    return ArenaResultEntry(
                        index: item.index,
                        label: item.spec.label,
                        leaseId: item.lease.id,
                        branchName: joinRes.committedBranch ?? item.lease.branchName,
                        worktreePath: item.lease.isolatedWorktreePath,
                        elapsedSeconds: elapsed,
                        verificationPassed: joinRes.verificationPassed,
                        verificationSpike: joinRes.verificationSpike,
                        modifiedFiles: joinRes.modifiedFiles,
                        summary: summary
                    )
                }
            }
            for await res in group {
                entries.append(res)
            }
        }

        // Rank contenders: (verified + modified files) > (verified) > (modified files), tie-broken by fastest elapsed time
        let ranked = entries.sorted { a, b in
            let scoreA = (a.verificationPassed ? 100 : 0) + (!a.modifiedFiles.isEmpty ? 50 : 0)
            let scoreB = (b.verificationPassed ? 100 : 0) + (!b.modifiedFiles.isEmpty ? 50 : 0)
            if scoreA != scoreB { return scoreA > scoreB }
            return a.elapsedSeconds < b.elapsedSeconds
        }

        var winnerMergedNote = ""
        if autoMergeWinner,
           let winner = ranked.first,
           winner.verificationPassed,
           !winner.modifiedFiles.isEmpty {
            let mergeJoin = await PNSMotorWorktreePlexus.shared.verifyAndJoinFiber(
                fiberId: winner.leaseId,
                branchPolicy: .autoThreeWayMergeOnVerify,
                verificationCommand: nil,
                fiberSummary: "Arena Winner (\(winner.label))"
            )
            if mergeJoin.mergedToTrunk {
                winnerMergedNote = "\n\n✅ **Auto-Merged Winner (`\(winner.label)`)** into workspace trunk via 3-way LCS merger (`\(winner.modifiedFiles.count)` files)."
            }
        }

        var tableRows: [String] = [
            "| Rank | Engine | Verify Gate | Changed Files | Time | Isolated Branch |",
            "| :--- | :--- | :--- | :---: | :---: | :--- |"
        ]
        for (rankIdx, item) in ranked.enumerated() {
            let medal = rankIdx == 0 ? "🏆 #1" : "#\(rankIdx + 1)"
            let gate = item.verificationPassed ? "✅ PASS" : "❌ FAIL"
            let secs = String(format: "%.1fs", item.elapsedSeconds)
            tableRows.append("| \(medal) | **\(item.label)** | \(gate) | \(item.modifiedFiles.count) | \(secs) | `\(item.branchName)` |")
        }

        let details = ranked.map { item -> String in
            let filesList = item.modifiedFiles.isEmpty ? "_No files modified_" : item.modifiedFiles.map { "`\($0)`" }.joined(separator: ", ")
            return """
            ### \(item.label) (`\(item.branchName)`)
            - **Worktree**: `\(item.worktreePath)`
            - **Modified Files**: \(filesList)
            - **Verification**: \(item.verificationSpike.prefix(220))
            - **Summary**: \(item.summary.prefix(500))
            """
        }.joined(separator: "\n\n")

        return """
        🏟️ **Best-of-N Cross-Vendor Worktree Arena Completed (\(ranked.count) Engines)**

        \(tableRows.joined(separator: "\n"))\(winnerMergedNote)

        \(details)
        """
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
