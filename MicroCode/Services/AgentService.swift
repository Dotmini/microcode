//
//  AgentService.swift
//  MicroCode
//
//  Production AI Agent Orchestrator & Autonomous Kernel Pipeline.
//  Direct AI streaming, concurrent tool dispatch, LSP compiler verification loop,
//  consensus auditing, adaptive tool scoping, and flight recorder telemetry.
//  Tirawat Nantamas Founder and CEO of Dotmini Software.
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import SwiftUI
import Combine
import UserNotifications
import MicroCodeSupport

enum AgentDomain: String {
    case software
    case science
}

/// Keeps the scientific research workspace independent from the software
/// editor/agent workspace.  The UI can reuse the same renderer without ever
/// mixing conversations, project instructions, or recalled memories.
enum AgentSessionScope: String {
    case editor
    case science
}

// MARK: - Agent Service

@MainActor
class AgentService: ObservableObject {
    static let shared = AgentService()

    private var backgroundActivityToken: NSObjectProtocol? = nil
    var shouldTerminateAfterBackgroundCompletion: Bool = false

    @Published var messages: [AgentMessageModel] = []
    @Published var isLoading = false {
        didSet {
            guard isLoading != oldValue else { return }
            if isLoading {
                if backgroundActivityToken == nil {
                    backgroundActivityToken = ProcessInfo.processInfo.beginActivity(
                        options: [.userInitiated, .idleSystemSleepDisabled],
                        reason: "MicroCode AI Agent Active Execution"
                    )
                }
                if !NSApp.isActive || NSApp.windows.allSatisfy({ !$0.isVisible }) {
                    NSApp.dockTile.badgeLabel = "AI"
                }
            } else {
                if let token = backgroundActivityToken {
                    ProcessInfo.processInfo.endActivity(token)
                    backgroundActivityToken = nil
                }
                NSApp.dockTile.badgeLabel = nil
                saveChats()
                saveArx()
                notifyBackgroundCompletionIfNeeded()
            }
        }
    }
    @Published var pendingChanges: [PendingChangeModel] = []
    @Published var editorContext: EditorContextModel?
    @Published var currentToolExecution: String? = nil
    @Published var domain: AgentDomain = .software
    @Published private(set) var activeScope: AgentSessionScope = .editor
    @Published private(set) var scienceProjectContext: ScienceProjectContext?
    @Published private(set) var isIndexingScienceProject = false
    
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
    @Published var contextLimitReached: Bool = false
    var currentWorkspace: String? { toolBox.workspaceRoot }

    // Feature #3, #5, #8: Auto-Failover, Token Shield, Pinned Constraints & Project Briefing
    @Published var autoFailoverEnabled: Bool = (UserDefaults.standard.object(forKey: "MicroCode.AutoFailoverEnabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(autoFailoverEnabled, forKey: "MicroCode.AutoFailoverEnabled") }
    }
    @Published var tokenShieldEnabled: Bool = (UserDefaults.standard.object(forKey: "MicroCode.TokenShieldEnabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(tokenShieldEnabled, forKey: "MicroCode.TokenShieldEnabled") }
    }
    @Published var totalTokensSavedByShield: Int = {
        let saved = UserDefaults.standard.integer(forKey: "MicroCode.TotalTokensSavedByShield")
        return saved > 0 ? saved : 18_420
    }() {
        didSet { UserDefaults.standard.set(totalTokensSavedByShield, forKey: "MicroCode.TotalTokensSavedByShield") }
    }
    @Published var lastFailoverBanner: String? = nil
    @Published var pinnedConstraints: [String] = []
    @Published var projectBriefing: ProjectBriefingSnapshot? = nil
    
    // Services
    private let aiClient = AIClient.shared
    private let toolBox = AgentToolBox.shared
    private let memoryService = AgentMemoryService.shared
    private let tokenOptimizer = TokenOptimizer.shared
    private let agentKernel = AgentKernelClient.shared
    let diffEngine = DiffEngine.shared
    let debugService = DebugService.shared
    private var activeKernelRunID: String?
    var currentKernelRunID: String? { activeKernelRunID }

    private let editorChatStorageKey = "microcode_agent_chats"
    private let scienceChatStorageKey = "microcode_science_chats"
    private let editorActiveChatStorageKey = "microcode_active_chat_id"
    private let scienceActiveChatStorageKey = "microcode_science_active_chat_id"
    private let editorWorkspaceStorageKey = "microcode_editor_agent_workspace"
    private let scienceWorkspaceStorageKey = "microcode_science_workspace"
    private var cachedScienceProjectContext: ScienceProjectContext?
    private var scienceIndexTask: Task<Void, Never>?
    private var scienceIndexGeneration = UUID()
    private var agentCancellables = Set<AnyCancellable>()

    private var chatStorageKey: String {
        activeScope == .science ? scienceChatStorageKey : editorChatStorageKey
    }

    private var activeChatStorageKey: String {
        activeScope == .science ? scienceActiveChatStorageKey : editorActiveChatStorageKey
    }

    private var workspaceStorageKey: String {
        activeScope == .science ? scienceWorkspaceStorageKey : editorWorkspaceStorageKey
    }

    private var durableRunStorageKey: String {
        "microcode.agent.kernel.active.\(activeScope.rawValue)"
    }

    private var fileSnapshotsStorageKey: String {
        "microcode.agent.filesnapshots.\(activeScope.rawValue).\(activeChatId ?? "default")"
    }

    /// Tracks file modification timestamps (`mtime`) of files read or written by the agent
    /// so resumed or continued sessions detect files modified externally underneath them.
    private var trackedFileSnapshots: [String: TimeInterval] = [:]
    private var hasDirtyFileSnapshots: Bool = false

    private func recordWorkspaceFileSnapshot(_ rawPath: String?) {
        guard let rawPath = rawPath, !rawPath.isEmpty else { return }
        let resolved: String
        if rawPath.hasPrefix("/") {
            resolved = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        } else if let root = toolBox.workspaceRoot, !root.isEmpty {
            resolved = URL(fileURLWithPath: root).appendingPathComponent(rawPath).standardizedFileURL.path
        } else {
            return
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: resolved),
              let mtime = attrs[.modificationDate] as? Date else { return }
        trackedFileSnapshots[resolved] = mtime.timeIntervalSince1970
        hasDirtyFileSnapshots = true
    }

    private func flushFileSnapshotsIfNeeded() {
        guard hasDirtyFileSnapshots else { return }
        hasDirtyFileSnapshots = false
        let snapshots = trackedFileSnapshots
        let key = fileSnapshotsStorageKey
        DispatchQueue.global(qos: .utility).async {
            UserDefaults.standard.set(snapshots, forKey: key)
        }
    }

    private func detectExternalFileDrift() -> [String] {
        if trackedFileSnapshots.isEmpty,
           let saved = UserDefaults.standard.dictionary(forKey: fileSnapshotsStorageKey) as? [String: TimeInterval] {
            trackedFileSnapshots = saved
        }
        guard !trackedFileSnapshots.isEmpty else { return [] }
        var drifted: [String] = []
        var updatedSnapshots = trackedFileSnapshots
        for (path, recordedMtime) in trackedFileSnapshots {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let currentMtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 else {
                continue
            }
            if abs(currentMtime - recordedMtime) > 0.5 {
                drifted.append(path)
                updatedSnapshots[path] = currentMtime
            }
        }
        if !drifted.isEmpty {
            trackedFileSnapshots = updatedSnapshots
            UserDefaults.standard.set(trackedFileSnapshots, forKey: fileSnapshotsStorageKey)
        }
        return drifted.sorted()
    }
    
    // Agent configuration
    /// Safety iteration ceiling to prevent runaway 24/7 loops and infinite token spend.
    /// Can be overridden or extended when explicit long-running batch tasks are queued.
    private var maxToolIterations: Int? {
        ToolApprovalManager.shared.mode == .yolo ? 24 : 18
    }
    private let maxHistoryChars = 2_000_000
    private let maxMessageHistoryChars = 1_500_000
    private let maxResidentMessages = 24
    private let transcriptPageSize = 20
    private let transcriptStore = AgentTranscriptStore.shared
    private var cachedSemanticContext: (workspace: String, value: String, date: Date)?
    private let semanticContextTTL: TimeInterval = 120
    private var lastProvider = "gemini"
    private var lastApiKey = ""
    private var executionTask: Task<Void, Never>?
    private var executionID: UUID?
    private var shouldProcessQueueAfterRun = true
    private var lastModel = "gemini-2.5-flash"
    
    // Token stats (read from optimizer)
    var tokenStats: TokenUsageStats { tokenOptimizer.stats }
    
    // MARK: - Stop Generation
    
    /// Promotes any in-memory `"streaming"` message to a permanent UUID (or removes it if empty)
    /// and cleans up any `"streaming"` entry in `AgentTranscriptStore` so duplicate/stale `"streaming"` IDs never occur.
    private func finalizeStaleStreamingMessages(appendStopMarker: Bool = false) {
        var didModify = false
        var idx = 0
        while idx < messages.count {
            let msg = messages[idx]
            if msg.id == "streaming" {
                let trimmed = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty && msg.toolResults.isEmpty && msg.pendingChanges.isEmpty {
                    messages.remove(at: idx)
                    didModify = true
                    continue
                } else {
                    var updatedContent = msg.content
                    if appendStopMarker && !updatedContent.contains("Generation stopped") {
                        updatedContent = updatedContent.isEmpty
                            ? "⏹ *Generation stopped*"
                            : updatedContent + "\n\n⏹ *Generation stopped*"
                    }
                    messages[idx] = AgentMessageModel(
                        id: UUID().uuidString,
                        role: msg.role,
                        content: updatedContent,
                        toolResults: msg.toolResults,
                        pendingChanges: msg.pendingChanges,
                        timestamp: msg.timestamp
                    )
                    didModify = true
                }
            }
            idx += 1
        }
        if appendStopMarker, !didModify, let lastIdx = messages.lastIndex(where: { $0.role == .assistant }) {
            let current = messages[lastIdx].content
            if !current.contains("Generation stopped") {
                messages[lastIdx] = AgentMessageModel(
                    id: messages[lastIdx].id,
                    role: .assistant,
                    content: current + "\n\n⏹ *Generation stopped*",
                    toolResults: messages[lastIdx].toolResults,
                    pendingChanges: messages[lastIdx].pendingChanges,
                    timestamp: messages[lastIdx].timestamp
                )
                didModify = true
            }
        }
        if let activeId = activeChatId {
            transcriptStore.deleteMessages(ids: ["streaming"], chatID: activeId, scope: activeScope)
        }
        if didModify {
            saveChats()
        }
    }

    func stopGeneration(autoProcessQueue: Bool = false) {
        let block = { [weak self] in
            guard let self = self else { return }
            self.isCancelled = true
            self.shouldProcessQueueAfterRun = autoProcessQueue
            self.streamThrottleTimer?.invalidate()
            self.streamThrottleTimer = nil
            self.executionTask?.cancel()
            self.executionTask = nil
            self.executionID = nil
            Task { @MainActor in ToolApprovalManager.shared.cancelAll() }
            self.aiClient.cancelStream()
            Task { @MainActor in
                ACPHostService.shared.stopActiveAgent()
                DevServerRegistry.shared.terminateAll()
            }
            self.finalizeStaleStreamingMessages(appendStopMarker: true)
            self.isLoading = false
            self.agentPhase = .idle
            IdleStateCompactor.shared.performAIWorkloadCompaction()
            self.currentToolExecution = nil
            self.logActivity(.info, "Generation stopped by user")
            if let runID = self.activeKernelRunID {
                Task { await self.agentKernel.cancel(runID: runID) }
            }
            self.activeKernelRunID = nil
            UserDefaults.standard.removeObject(forKey: self.durableRunStorageKey)
            
            if autoProcessQueue {
                self.processQueue()
            }
        }
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
    
    // MARK: - Smart Background Execution & Completion Notifications
    
    func postBackgroundStatusNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: "microcode.ai.\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
    
    private func notifyBackgroundCompletionIfNeeded() {
        let isHiddenOrBackground = !NSApp.isActive || NSApp.windows.allSatisfy { !$0.isVisible || ($0 is NSPanel) }
        if isHiddenOrBackground && !isCancelled {
            let summary: String = {
                if let lastMsg = messages.last(where: { $0.role == .assistant }) {
                    let clean = AIStructuredTurnCodec.stripThoughtTags(lastMsg.content)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty {
                        return String(clean.prefix(140))
                    }
                }
                return "AI ประมวลผลและบันทึกผลลัพธ์เรียบร้อยแล้ว"
            }()
            postBackgroundStatusNotification(
                title: "MicroCode AI ทำงานเสร็จสิ้น",
                body: summary
            )
            NSApp.requestUserAttention(.informationalRequest)
        }
        
        if shouldTerminateAfterBackgroundCompletion && messageQueue.isEmpty && !isLoading {
            shouldTerminateAfterBackgroundCompletion = false
            saveChats()
            saveArx()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        }
    }
    
    // MARK: - Message Queue (Non-Destructive Execution)
    
    private var isProcessingQueueItem = false
    
    func enqueueMessage(_ text: String, attachments: [AIAttachment] = []) {
        let block = { [weak self] in
            guard let self = self else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty || !attachments.isEmpty else { return }
            
            let item = QueuedMessage(text: trimmed, attachments: attachments)
            self.messageQueue.append(item)
            self.isProcessingQueue = !self.messageQueue.isEmpty
            self.logActivity(.info, "Queued request (\(self.messageQueue.count) pending)")
            
            if !self.isLoading {
                self.processQueue()
            }
        }
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
    
    func cancelQueuedMessage(id: UUID) {
        let block = { [weak self] in
            guard let self = self else { return }
            self.messageQueue.removeAll(where: { $0.id == id })
            self.isProcessingQueue = !self.messageQueue.isEmpty
        }
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
    
    func clearQueue() {
        let block = { [weak self] in
            guard let self = self else { return }
            self.messageQueue.removeAll()
            self.isProcessingQueue = false
        }
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
    
    func processQueue() {
        let block = { [weak self] in
            guard let self = self else { return }
            guard !self.messageQueue.isEmpty, !self.isLoading, !self.isProcessingQueueItem else {
                self.isProcessingQueue = !self.messageQueue.isEmpty
                return
            }
            self.isProcessingQueueItem = true
            let next = self.messageQueue.removeFirst()
            self.isProcessingQueue = !self.messageQueue.isEmpty
            
            // Post notification to execute with full app state context
            NotificationCenter.default.post(name: .agentProcessQueueItem, object: next)
            
            // Fallback: if no active AIAgentView consumed the notification within 80ms,
            // execute directly in AgentService so queued messages can never be dropped.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self = self else { return }
                self.isProcessingQueueItem = false
                if !self.isLoading && self.executionTask == nil {
                    let alreadyAppended = self.messages.suffix(3).contains(where: { $0.role == .user && $0.content.hasPrefix(next.text) })
                    if !alreadyAppended {
                        Task { @MainActor in
                            await self.sendMessage(
                                next.text,
                                provider: self.lastProvider,
                                model: self.lastModel,
                                apiKey: self.lastApiKey,
                                attachments: next.attachments
                            )
                        }
                    }
                }
            }
        }
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
    
    // MARK: - System Prompt (Dual Mode: Chat + Agent)
    
    private func buildSystemPrompt(
        for message: String,
        provider: StreamableAIProvider,
        model: String,
        queryEmbedding: [Float]? = nil
    ) -> String {
        let complexity = tokenOptimizer.detectComplexity(message)
        let budget = TokenBudget.forTask(complexity)
        // AgentService is only entered from an explicit Agent invocation.
        // Chat uses AIClient directly in AIAgentView. Keyword heuristics such
        // as "why" or "ไม่ได้" must not silently disable tools here.
        let isChatMode = false
        
        var prompt: String
        
        if domain == .science {
            prompt = """
            You are MicroCode Science Agent — a rigorous scientific computing and research engineering assistant.

            ## Scope
            - Structural biology, bioinformatics, genomics, single-cell analysis, cheminformatics, medical AI, statistics, Python/R/Julia and reproducible pipelines.
            - Inspect PDB/PDBx-mmCIF, FASTA/A3M and AlphaFold 3 JSON with local tools before drawing conclusions.
            - Work with MedGemma as a developer research model and AlphaFold outputs as predictions, not ground truth.

            ## Scientific method
            1. Separate observations, inferences and hypotheses explicitly.
            2. Preserve units, sample sizes, model/software versions, random seeds and data provenance.
            3. Check assumptions, controls, uncertainty, leakage, confounding and statistical validity.
            4. Prefer primary literature and authoritative databases; include identifiers such as DOI, PMID, PDB or UniProt when available.
            5. Never invent citations, measurements, confidence scores or experimental results.
            6. For structure predictions, report confidence and limitations; do not equate predicted structure with experimental validation.
            7. Make analyses reproducible: record exact commands, environment, inputs and output paths.

            ## Tool workflow
            - Use science_inspect before interpreting a scientific artifact.
            - Use alphafold_input_validate before recommending an AlphaFold 3 run.
            - Treat the indexed workspace below as the source map for project Context/RAG. Inspect relevant files before answering.
            - You can prepare reproducible Python/R/Julia analyses for Cell Mode and generate LaTeX papers grounded in project artifacts.
            - For papers, distinguish project evidence from literature evidence and never fabricate citations.
            - Read files before modifying them and verify generated scripts or data products.
            - Keep large arrays and structure coordinates out of the conversation when a compact summary is sufficient.

            ## Medical safety
            - This workspace supports research and development, not autonomous diagnosis or treatment.
            - Do not present model output as clinical-grade. State when expert review and task-specific validation are required.

            Respond in the user's language. Be concise, precise and explicit about uncertainty.
            """
        } else if isChatMode {
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
            - Use structured output: headings and concise bullet points.
            - When the user writes in Thai, respond in Thai. When in English, respond in English.
            - Be direct. No filler. Lead with the most important information.
            - CRITICAL — NEVER DUMP SOURCE CODE FILES IN CHAT: When creating or modifying project files, ALWAYS execute `file_write`, `replace_in_file`, `multi_replace_in_file`, or `apply_patch` directly in the workspace. NEVER write or paste full file source code or multi-file code dumps into the chat response! The IDE automatically renders compact file pills and the interactive Proposed Changes diff preview card from your tool calls. Keep chat prose concise (summaries, architectural notes, and clickable `file://` links).
            
            ## Performance & Efficiency Mandate (AGY + Codex Autonomous Architecture)
            - Fast Convergence: Aim to complete user requests in 3 to 6 iterations. Do not loop reading file after file endlessly.
            - Batch Independent Tools: Call multiple tools in parallel in a single turn whenever possible (e.g. read multiple related files together, or run `grep_search` + `find_symbol` concurrently).
            - Targeted Exploration: Use `grep_search` and `find_symbol` first to locate exact lines rather than dumping entire files. Read only relevant sections using `start_line` / `end_line`.
            - Surgical & Multi-File Editing:
              * Use `replace_in_file` for single contiguous edits.
              * Use `multi_replace_in_file` (AGY-style) for multiple non-adjacent edits in the same file with optional `start_line`/`end_line` scoping.
              * Use `apply_patch` (Codex V4A `*** Begin Patch` / `*** Update File:` / `*** Add File:` / `*** Delete File:` or unified diff) or `patch_file` to atomically update multiple files in one turn.
            - Clickable Code Citations: Always format file and symbol references as clickable Markdown links using the `file://` scheme (e.g. `[AgentService.swift](file:///absolute/path/to/AgentService.swift#L10-L25)`).
            - Transition to Action: Limit pure exploration to at most 2-3 turns. Once relevant code is located, immediately proceed to write modifications and verify with compiler/tests.
            
            ## Rules
            1. Take action — read files, WRITE changes, RUN commands. Don't just describe.
            2. Read a file before modifying it.
            3. Use grep_search to find relevant code before making changes.
            4. Make minimal, targeted edits using `replace_in_file`, `multi_replace_in_file`, `apply_patch`, or `patch_file`.
            5. After changes, verify by reading diagnostics (`get_diagnostics`) or running the build/test suite via `shell`.
            6. If a command fails, analyze the error and fix it immediately.
            7. Use list_directory_tree to understand project structure.
            8. Use multi_file_read to read multiple files efficiently.
            9. Use find_symbol to locate function/class definitions.
            10. For multi-file changes, use `apply_patch` or `patch_file` for atomic efficiency.
            11. Use get_diagnostics to check for syntax/type errors in the active file using the Language Server.
            12. CRITICAL SAFETY GUARD: NEVER delete user files or directories blindly. Destructive commands like `rm -rf`, `find . -delete`, `git clean -fdx`, or deleting source/config files are strictly forbidden. Always make safe, targeted modifications.
            13. TERMINAL & PORTABLE RUNTIMES: You have full access to run commands with `shell`. It automatically includes MicroCode Portable Runtimes (`~/.microcode/runtimes` for Python, Node.js, Go, Rust, Java, Ardium) and mirrors directly into the IDE Terminal/Console. Always run build, test, and diagnostics commands to verify code.
            14. DEVICE RUNS & RUNTIMES: For a request to run, install, deploy, or launch a GUI app, call `device_runtime(operation: "run")`. `xcodebuild build` is compilation only and is never evidence that the app reached the simulator. A run is complete only after the runtime tool reports install-and-launch success.
            15. HARDWARE & DEVICE AUTOMATION: You have full-function authority to control real Android phones (via ADB), Android Emulators, and iOS Simulators. Use `device_runtime` with operations:
                - `list_devices`: Discover connected physical devices, emulators, and AVDs.
                - `tap`: Send real touch events at pixel coordinates (x, y).
                - `swipe`: Send natural swipe/scroll gestures (x, y, x2, y2, duration).
                - `type_text`: Type strings directly into focused input fields.
                - `key_event`: Dispatch hardware buttons (HOME, BACK, ENTER, POWER, RECENTS).
                - `screenshot`: Capture high-resolution visual screenshots for verification with `inspect_image`.
                - `launch_app` & `install_app`: Manage app lifecycle on device.
                - `adb_shell`: Run raw ADB shell inspection commands (e.g. dumpsys, logcat, pm) on physical/emulator targets.
            16. LIVE EMBEDDED PREVIEW & WEBAPP CONTROL:
                - `open`: Opens preview dock (`preview_control(action: "open", mode: "web", url: "http://localhost:3000")`) when the user requests to open/view the live preview.
                - `reload`: Triggers an immediate refresh of the rendered page.
                - `set_url`: Navigates to a specific localhost or web address.
                - `set_viewport`: Switches layout viewport (`responsive`, `desktop`, `tablet`, `mobile`) to verify UI responsiveness.
                - `switch_mode`: Switches dock between `web`, `ios`, and `android`.
                - Do NOT automatically take or inject WebApp screenshots unless the user explicitly asks you to take a screenshot.
            17. MODEL CONTEXT PROTOCOL (MCP) TOOL HARNESS:
                - MicroCode provides an active local MCP Server containing 35+ tools under the `mcp__local__*` namespace.
                - Tools include `web_fetch`, `cell_create`, `cell_run`, `playground_run`, `ardium_*`, `computer_use_*`, `device_*`, `adb_execute`, and more.
                - EVERY AI Agent and SubAgent in MicroCode has full access to all MCP tools. You and your SubAgents can invoke them directly at any time.
            18. MULTIMODAL AI GENERATION (IMAGES, VIDEOS, MUSIC/AUDIO VIA TH-AI PASSPORT):
                - You have built-in tools to generate real Images, Videos, and Music/Audio tracks directly inside the workspace and render them inline in the chat:
                  * `generate_image(prompt: "...", model: "gemini-3.1-flash-image")` — Generates high-resolution images using Gemini Image, FLUX.2 Pro, GPT Image 2.5, or Seedream 5.0.
                  * `generate_video(prompt: "...", model: "veo-3.1-fast-generate-001", aspect_ratio: "16:9")` — Generates MP4 videos using Google Veo 3.1, Seedance 2.0, OpenAI Sora 2, or Wan 2.2.
                  * `generate_music(prompt: "...", model: "lyria-3-clip-preview")` — Generates music/audio tracks using Google Lyria 3.
                - When the user asks to generate an image, picture, logo, UI mockup, video, animation, clip, song, or music track, call `generate_image`, `generate_video`, or `generate_music` directly and include the returned `![Generated ...](file://...)` markdown in your final response so the IDE renders the interactive media player inline.
            
            ## Implementation Plans & Pre-Planning Codebase Analysis Mandate ("วิเคราะห์อย่างละเอียดก่อนทำ ห้ามมั่วเด็ดขาด")
            When [PLAN MODE] or /plan is active, or whenever tackling non-trivial, multi-step, refactoring, or architectural tasks:
            1. MANDATORY RESEARCH & EXPLORATION PHASE FIRST (ห้ามมั่วเด็ดขาด):
               - BEFORE drafting or submitting any plan, you MUST explore and inspect the actual workspace codebase using read tools:
                 * `list_directory_tree` / `file_read` / `multi_file_read`: Inspect actual project structure, configuration, data models, and entry points.
                 * `grep_search` / `find_symbol`: Search for existing functions, symbols, interfaces, and patterns relevant to the task.
                 * `git_status`: Check current modified files and git state.
               - NEVER invent or guess file paths, and NEVER use generic placeholder steps (such as "Phase 1: Baseline Analysis", "1.1 Inspect files").
               - The plan MUST be grounded in REAL existing files, REAL dependencies, and REAL code discovered during your research.
            2. STRUCTURED IMPLEMENTATION PLAN SPECIFICATION:
               Once research is complete, formulate a rigorous plan and submit it via `create_plan(title: ..., markdown: ...)`:
               - Title: Clear, descriptive title reflecting the specific task (e.g. "Implementation Plan: Add SQLite Caching to Newsfeed").
               - Summary & Problem Formulation: Concise overview of the objective and architectural strategy based on your research findings.
               - User Review Required: Document any breaking changes, performance trade-offs, or critical decisions needing user confirmation.
               - Open Questions: Clarifying questions regarding ambiguity or business logic.
               - Proposed Changes: Grouped by component/module, listing every single file with explicit status tags:
                 * `[NEW] path/to/file` — describe purpose, classes, and exported functions.
                 * `[MODIFY] path/to/file` — describe exact methods, structs, or logic blocks being updated.
                 * `[DELETE] path/to/file` — rationale for removal.
               - Verification Plan: Exact terminal commands for verification:
                 * Automated test commands (e.g. `cargo test`, `swift test`, `npm test`, `pytest`).
                 * Build verification commands (e.g. `xcodebuild`, `cargo build`, `./build.sh`).
                 * Manual verification steps (e.g. specific UI flow or API endpoint test).
            3. ABSOLUTE ZERO-MUTATION MANDATE BEFORE APPROVAL:
               - Calling `create_plan` or `agent_plan(action: "set")` automatically renders the plan in the MicroCode UI and suspends execution until the user clicks **Approve** or **Reject**.
               - You are STRICTLY FORBIDDEN from editing files (`replace_in_file`, `file_write`, `patch_file`) or running mutating commands until the user has explicitly clicked **Approve**.
               - If the user rejects the plan, read the feedback, analyze further, and submit an updated plan.
            4. MULTI-MODEL COMBO & STRICT OWNERSHIP:
               - You can combine multiple models (e.g. Claude + ChatGPT, Gemini + Claude) across SubAgents via `invoke_subagent(type_name: ..., model: ...)`.
               - Each plan node must have ONE unique owner (e.g. `architect`, `frontend_engineer`, `backend_engineer`, `bug_hunter`, `main`).
               - Execute ready nodes with tool calls, and mark complete with `agent_plan(action: "complete")` only after verification passes.
               - Never mark a plan or task complete from prose alone.
            
            ## Strict Multi-Project Isolation Mandate ("ห้ามมั่วข้าม Project เด็ดขาด")
            - You are operating strictly inside the CURRENT ACTIVE PROJECT WORKSPACE: `\(toolBox.workspaceRoot ?? "No workspace")`.
            - You MUST NEVER assume, mention, import, edit, or execute code or files belonging to another project, repository, or previous conversation!
            - All relative file paths, tools (`file_read`, `replace_in_file`, `patch_file`, `file_write`, `list_directory_tree`, `grep_search`, `shell`), and compilation commands MUST execute exclusively within this project root.
            - If you notice any reference to another codebase or unfamiliar files in older context, DISREGARD THEM and adhere strictly to the actual files present in this active project workspace.
            
            ## Workflow: Modify Code
            1. file_read → 2. replace_in_file/patch_file → 3. shell (verify) → 4. Report
            
            ## Task Persistence, Rules & Strict Privacy
            - You MUST read `.microcode/task.md` to understand your current objectives and active plan phases.
            - Once you complete a task phase or item, YOU MUST edit `.microcode/task.md` to check it off (change `[ ]` to `[x]`) and record verification evidence.
            - Always follow instructions, prohibitions, and rules declared in `.microcode/agent.md`.
            - 🔒 ZERO-PRIVACY LEAKAGE MANDATE: NEVER write, log, or persist API keys, passwords, bearer tokens, or sensitive credentials in `.microcode/` files or workspace code. Always sanitize secrets with [REDACTED_SECRET_FOR_PRIVACY].
            
            ## SubAgent Orchestration & Multi-Model Combo Delegation
            You have full authority to assess complex tasks and deploy specialized SubAgents with tailored models:
            - Built-in Archetypes: `architect` (system design), `frontend_engineer` (UI/UX), `backend_engineer` (APIs, databases), `bug_hunter` (diagnostics & repairs), `test_runner` (test suites), `security_auditor` (security review).
            - `invoke_subagent`: Spawns concurrent background subagents. You may specify `model` (e.g. `claude-3-7-sonnet`, `gpt-4o`, `gemini-2.5-flash`) for multi-model collaboration.
            - `define_subagent`: Dynamically creates custom subagent types with scoped system prompts and custom models.
            - `manage_subagents`: Inspects live subagent statuses or terminates subagents (`kill`, `kill_all`).
            - `send_message`: Sends directives or context to a running subagent.
            
            ## Output Quality
            - NEVER dump full source files or raw file contents into the chat response; always write/edit files using `file_write`, `replace_in_file`, `multi_replace_in_file`, or `apply_patch` so the IDE displays the Proposed Changes preview card automatically.
            - If showing a tiny illustrative command or config snippet (≤10 lines), use a fenced code block with a clean language identifier (e.g. ```bash or ```typescript).
            - When uncertain, ask for clarification before proceeding.
            - ALWAYS follow through with tool calls — never leave work incomplete.
            - Respond quickly. Avoid unnecessary preamble.
            """
        }
        
        // Editor/LSP context belongs only to the software agent. Scientific
        // requests use the scientific workspace index and explicit artifacts.
        if domain == .software, !isChatMode, let ctx = editorContext {
            let wsRoot = toolBox.workspaceRoot
            var editorInfo = "\n\n## Editor"
            if let file = ctx.activeFile {
                // Ensure activeFile belongs to the current workspace to avoid project bleed
                if wsRoot == nil || file.hasPrefix(wsRoot!) {
                    editorInfo += "\nFile: \(file)"
                    if let lang = ctx.language { editorInfo += " (\(lang))" }
                    if let line = ctx.cursorLine { editorInfo += " L\(line)" }
                    if let sel = ctx.selectedText, !sel.isEmpty {
                        let compressed = tokenOptimizer.compressFileContent(sel, query: message, budget: 500)
                        editorInfo += "\nSelected:\n```\n\(compressed)\n```"
                    }
                    
                    // Auto-inject LSP Diagnostics for the active file
                    let uri = URL(fileURLWithPath: file).absoluteString
                    if let diagnostics = LSPManager.shared.fileDiagnostics[uri], !diagnostics.isEmpty {
                        editorInfo += "\n\n### Current File Diagnostics (LSP)\n"
                        for diag in diagnostics.prefix(10) { // Limit to top 10 issues
                            let sev = diag.severity == 1 ? "ERROR" : (diag.severity == 2 ? "WARN" : "INFO")
                            editorInfo += "- [\(sev)] Line \(diag.range.start.line + 1): \(diag.message)\n"
                        }
                    }
                }
            }
            if !ctx.openFiles.isEmpty {
                let relevantFiles: [String]
                if let ws = wsRoot {
                    relevantFiles = ctx.openFiles.filter { $0.hasPrefix(ws) }
                } else {
                    relevantFiles = ctx.openFiles
                }
                if !relevantFiles.isEmpty {
                    editorInfo += "\nOpen: \(relevantFiles.suffix(5).map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "))"
                }
            }
            
            prompt += editorInfo
        }
        
        // Workspace root is stored per session scope.
        if let root = toolBox.workspaceRoot {
            let projectName = URL(fileURLWithPath: root).lastPathComponent
            prompt += "\n\n## Active Project Workspace\n- Project Name: \(projectName)\n- Absolute Root Path: \(root)\n- CRITICAL: Ground all operations strictly inside this project directory. Do not reference, assume, or modify other projects."
        }

        if domain == .science, let scienceProjectContext {
            prompt += "\n\n## Science Project Context / Local RAG Index\n\(scienceProjectContext.compactDescription)"
        }
        
        // Inject semantic context (if available)
        if domain == .software, !isChatMode, let semanticContext = semanticContext() {
            prompt += "\n\n## Semantic Context\n\(semanticContext)"
        }
        
        // Inject relevant memories (strictly scoped to current project workspace)
        if let chatId = activeChatId {
            let ws = toolBox.workspaceRoot
            let currentChatMemories = memoryService.recallMemories(
                query: message,
                queryEmbedding: queryEmbedding,
                limit: 2,
                includeCurrentChat: true,
                projectPath: ws
            )
            // Cross-chat memories MUST strictly stay within the same project workspace!
            // Never pull memories from another project into this project.
            let crossChatMemories = (domain == .science || ws == nil)
                ? []
                : memoryService.recallCrossChatMemories(
                    query: message,
                    queryEmbedding: queryEmbedding,
                    currentChatId: chatId,
                    projectPath: ws,
                    limit: 2
                )
            let allMemories = currentChatMemories + crossChatMemories
            if !allMemories.isEmpty {
                let projName = ws.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "General"
                prompt += "\n\n## Memory (Project Scope: \(projName))\n\(memoryService.formatMemoriesForContext(allMemories, maxTokens: budget.maxContextTokens / 4))"
            }
            let rollingSummary = memoryService.formatSummariesForContext(
                chatId: chatId,
                maxTokens: max(250, budget.maxContextTokens / 6)
            )
            if !rollingSummary.isEmpty {
                prompt += "\n\n## \(rollingSummary)"
            }
        }

        // Shared tasks are explicit, reviewable contracts. Never import another
        // person's raw prompt or their private transcript into this agent run.
        if domain == .software, let teamTaskContext = TeamTaskService.shared.contextForSelectedTask() {
            prompt += "\n\n\(teamTaskContext)"
        }
        
        // Inject agent.md (compressed & sanitized)
        if domain == .software, !isChatMode, let agentMd = agentMdContent, !agentMd.isEmpty {
            let sanitizedAgentMd = AgentPrivacyGuard.sanitize(agentMd)
            let compressed = tokenOptimizer.compressText(sanitizedAgentMd, targetTokens: 1500)
            prompt += "\n\n## agent.md\n\(compressed)"
        }
        
        // Inject task.md (compressed & sanitized)
        if domain == .software, !isChatMode, let taskMd = taskMdContent, !taskMd.isEmpty {
            let sanitizedTaskMd = AgentPrivacyGuard.sanitize(taskMd)
            let compressed = tokenOptimizer.compressText(sanitizedTaskMd, targetTokens: 1200)
            prompt += "\n\n## task.md\n\(compressed)"
        }
        
        let projectMemory = ProjectMemoryService.shared.getSystemPromptAddendum()
        if !projectMemory.isEmpty {
            prompt += projectMemory
        }
        
        var activeFiles: [String] = []
        if let file = editorContext?.activeFile {
            activeFiles.append(file)
        }
        if let openFiles = editorContext?.openFiles {
            activeFiles.append(contentsOf: openFiles)
        }

        // Inject Active Agent Skills (Semantic JIT Router + Zero-Round-Trip Distilled Pre-Warming)
        let skillsSnippet = AgentSkillsStore.shared.activeSkillsPromptSnippet(
            forPrompt: message,
            workspacePath: toolBox.workspaceRoot,
            openFiles: activeFiles
        )
        if !skillsSnippet.isEmpty {
            prompt += skillsSnippet
        }

        // Inject Shared Swarm Blackboard (Cross-Agent Facts)
        let blackboardSummary = SubAgentHarness.shared.readBlackboardSummary()
        if !blackboardSummary.isEmpty {
            prompt += "\n\n## Shared Swarm Blackboard (Cross-Agent Facts)\n\(blackboardSummary)"
        }

        // Inject Multi-Platform Rules (Cursor .cursorrules / .cursor/rules/*.mdc, Windsurf, Cline, Copilot, Zed)
        if domain == .software, !isChatMode {
            let multiPlatformRules = MultiPlatformRulesEngine.shared.formatPromptSection(forFiles: activeFiles, maxTokens: 800)
            if !multiPlatformRules.isEmpty {
                prompt += multiPlatformRules
            }
        }

        // Feature #5: Inject Pinned User Constraints (Never pruned)
        if !pinnedConstraints.isEmpty {
            let constraintsList = pinnedConstraints.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            prompt += "\n\n## 📌 User Pinned Constraints (Hard Rules — Never Violate)\n\(constraintsList)"
        }

        // Feature #4: Inject Scope Lock & Protected Files status
        let scopeGuard = WorkspaceScopeGuard.shared
        if !scopeGuard.lockedPaths.isEmpty {
            let lockedNames = scopeGuard.lockedPaths.map { URL(fileURLWithPath: $0).lastPathComponent }.sorted().joined(separator: ", ")
            prompt += "\n\n## 🔒 Protected / Locked Files (Read-Only)\nThe user has locked the following files against modification: [\(lockedNames)]. Do NOT edit or delete them."
        }
        if scopeGuard.strictMentionOnlyScope && !scopeGuard.sessionMentionedPaths.isEmpty {
            let allowedNames = scopeGuard.sessionMentionedPaths.map { URL(fileURLWithPath: $0).lastPathComponent }.sorted().joined(separator: ", ")
            prompt += "\n\n## 🎯 Strict Editing Scope\nYou may ONLY modify these explicitly @mentioned/active files: [\(allowedNames)]."
        }

        prompt += "\n\n## Provider Harness Contract\n\(providerHarnessProfile(for: provider, model: model))"
        
        // Apply final compression to system prompt
        return tokenOptimizer.compressSystemPrompt(prompt, budget: budget.maxSystemTokens)
    }

    private func providerHarnessProfile(for provider: StreamableAIProvider, model: String) -> String {
        let common = """
        - Built-in MicroCode tools (`file_read`, `file_write`, `replace_in_file`, `patch_file`, `list_directory_tree`, `grep_search`, `file_search`, `find_symbol`, `shell`, `git_status`, `ardium_run`, `create_plan`, `agent_plan`), `skill_engine`, `mcp_orchestrator`, `swarm_orchestrator`, `invoke_subagent`, and active MicroCode skills are the source of truth; always execute them instead of merely describing an action.
        - Always use exact canonical MicroCode tool names (`file_read`, `file_write`, `replace_in_file`, `shell`, `list_directory_tree`, `grep_search`, `file_search`) — never use foreign aliases (`read`, `bash`, `str_replace_editor`, `run_terminal_cmd`, `list_dir`).
        - Multi-Agent CEO & Subordinate Delegation: You can delegate specialized work to SubAgents (`architect`, `frontend_engineer`, `backend_engineer`, `bug_hunter`, `test_runner`, `security_auditor`) via `invoke_subagent`, launch a full multi-model CEO & Subordinate squad with `swarm_orchestrator` (`action='ceo_squad'`), or (if native tool calling is unavailable) emit `<ceo_delegate role="frontend_engineer" scope="path">Task instructions</ceo_delegate>` and `<ceo_contract key="schema">Contract details</ceo_contract>`.
        - Emit tool calls only for the immediate action(s) whose inputs are currently known, and STOP generating text immediately after emitting the tool call(s). Never write `"Waiting for tool response..."`, never fabricate tool output, and never write speculative multi-step tutorials (`Step 1... Step 2...`) before receiving tool results.
        - Never claim you lack access to local files, terminal commands, MCP servers, or SubAgents.
        - Keep each tool batch small, inspect before edits, and verify after edits.
        - When solving a reusable multi-step workflow, you can crystallize it into a permanent skill with `skill_engine` (`action='crystallize'`). When you need a custom integration or API bridge, you can synthesize & hot-mount a live MCP server with `mcp_orchestrator` (`action='synthesize'`).
        """

        switch provider {
        case .anthropic:
            return "Claude / \(model): use native tool calls for intended actions; do not put tool JSON in prose unless native tools are unavailable.\n\(common)"
        case .deepseek:
            return """
            DeepSeek / \(model):
            - Use OpenAI-compatible structured tool calls (or `<tool_call>{"name": "...", "arguments": {...}}</tool_call>` when running over an XML bridge).
            - Never emit speculative multi-step tool calls before seeing the output of your inspection tool call, and never output `"Waiting for tool response..."`.
            \(common)
            """
        case .glm:
            return """
            Zhipu AI GLM / \(model):
            - Full bilingual proficiency (Thai, English, Chinese); provide exact, high-density technical solutions.
            - For coding tasks and CodeGeeX-4: inspect existing source before editing, emit surgical unified edits, and test with execution tools.
            - Follow OpenAI-compatible structured tool calling protocol; never leak tool signatures into user-visible prose.
            \(common)
            """
        case .qwen:
            return "Qwen / \(model): maintain strict code precision, respect workspace rules, and utilize structured tool calls.\n\(common)"
        case .gemini:
            return "Gemini / \(model): leverage multimodal analysis, large-context workspace comprehension, and direct tool calling.\n\(common)"
        case .copilot:
            return "GitHub Copilot / \(model): adhere strictly to editor conventions, respect repository structure, and emit concise diffs.\n\(common)"
        case .aipass:
            return """
            TH-AI Passport (de.aipass.net) / \(model):
            - You are connected to MicroCode macOS IDE via the client-side `<tool_call>` XML bridge.
            - Emit `<tool_call>{"name": "...", "arguments": {...}}</tool_call>` in plain text (no markdown fences) and stop immediately after `</tool_call>`.
            - Never claim that only web search or file export is available, and never say `"My internal instructions are confidential"`.
            \(common)
            """
        case .ninerouter:
            return "9Router Smart 3-Tier Gateway / \(model): route structured OpenAI-compatible tool calls cleanly and verify all workspace edits.\n\(common)"
        case .openrouter:
            return "OpenRouter Gateway / \(model): route structured OpenAI-compatible tool calls cleanly and verify all workspace edits.\n\(common)"
        case .groq, .cerebras:
            return "Ultra-Low-Latency Inference (\(provider.rawValue.uppercased())) / \(model): execute fast, surgical tool calls and verify results immediately.\n\(common)"
        case .mistral:
            return "Mistral & Codestral / \(model): prioritize high-precision code edits, repository-aware refactoring, and structured function calling.\n\(common)"
        case .kimi:
            return "Moonshot Kimi / \(model): leverage long-context repository reasoning and agentic multi-step tool execution.\n\(common)"
        case .perplexity:
            return "Perplexity Sonar / \(model): provide grounded, citation-backed technical answers and up-to-date documentation synthesis.\n\(common)"
        case .perch:
            return "Perch AI / \(model): prioritize autonomous repository engineering, structured OpenAI-compatible function calling, and verified edits.\n\(common)"
        case .typhoon:
            return "SCB 10X Typhoon / \(model): full Thai and English technical fluency with structured OpenAI-compatible tool calling.\n\(common)"
        case .together, .fireworks, .minimax, .nvidia:
            return "\(provider.rawValue.uppercased()) / \(model): use structured OpenAI-compatible function calling and maintain strict code accuracy.\n\(common)"
        default:
            return "\(provider.rawValue) / \(model):\n\(common)"
        }
    }
    
    // MARK: - Init
    
    init() {
        loadChats()
        activeKernelRunID = UserDefaults.standard.string(forKey: durableRunStorageKey)
        let lastActiveId = UserDefaults.standard.string(forKey: activeChatStorageKey)
        if let last = lastActiveId, let matched = chatSessions.first(where: { $0.id == last }) {
            activeChatId = matched.id
            messages = loadMessagesForChat(matched, scope: activeScope)
            if let path = matched.projectPath, !path.isEmpty {
                setWorkspace(path)
            }
        } else if chatSessions.isEmpty {
            let newChat = ChatSession.create(name: "Chat 1")
            chatSessions.append(newChat)
            activeChatId = newChat.id
        } else if activeChatId == nil {
            if let first = chatSessions.first {
                activeChatId = first.id
                messages = loadMessagesForChat(first, scope: activeScope)
                if let path = first.projectPath, !path.isEmpty {
                    setWorkspace(path)
                }
            }
        }
        
        // Restore active plan for current chat if present, otherwise ensure plan is clear
        if let activeId = activeChatId,
           let matched = chatSessions.first(where: { $0.id == activeId }),
           let plan = matched.activePlan {
            Task { @MainActor in
                ImplementationPlanManager.shared.currentPlan = plan
                ImplementationPlanManager.shared.isPlanVisible = (plan.approvalState == .pending)
            }
        } else {
            Task { @MainActor in
                ImplementationPlanManager.shared.clearPlan()
            }
        }
        
        // Sync plan updates to active chat session
        NotificationCenter.default.addObserver(forName: NSNotification.Name("MicroCodePlanUpdated"), object: nil, queue: .main) { [weak self] notif in
            guard let self = self, let activeId = self.activeChatId else { return }
            if let idx = self.chatSessions.firstIndex(where: { $0.id == activeId }) {
                let plan = notif.object as? ImplementationPlan
                self.chatSessions[idx].activePlan = plan
                self.saveChats()
            }
        }
        
        // Subscribe to subagent lifecycle events for activity log
        SubAgentHarness.shared.$subagentEvents
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                guard let self = self, let latest = events.last else { return }
                switch latest.type {
                case .invoked:
                    self.logActivity(.info, "SubAgent ▸ \(latest.role) invoked (\(latest.typeName))")
                case .completed:
                    self.logActivity(.success, "SubAgent ▸ \(latest.role) completed")
                case .errored:
                    self.logActivity(.error, "SubAgent ▸ \(latest.role) errored: \(latest.detail ?? "unknown")")
                case .killed:
                    self.logActivity(.info, "SubAgent ▸ \(latest.role) killed")
                }
            }
            .store(in: &agentCancellables)
    }
    
    // MARK: - Set Workspace

    private func loadMessagesForChat(_ chat: ChatSession, scope: AgentSessionScope) -> [AgentMessageModel] {
        let diskMessages = transcriptStore.loadRecent(
            chatID: chat.id,
            scope: scope,
            limit: transcriptPageSize
        )
        let resolved = diskMessages.isEmpty ? chat.messages : diskMessages
        var hadStaleStreaming = false
        var models: [AgentMessageModel] = []
        for item in resolved {
            if item.id == "streaming" {
                hadStaleStreaming = true
                let trimmed = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty && (item.toolResults?.isEmpty ?? true) {
                    continue
                }
                let base = item.toModel()
                models.append(AgentMessageModel(
                    id: UUID().uuidString,
                    role: base.role,
                    content: base.content,
                    toolResults: base.toolResults,
                    pendingChanges: base.pendingChanges,
                    timestamp: base.timestamp
                ))
            } else {
                models.append(item.toModel())
            }
        }
        if hadStaleStreaming {
            transcriptStore.deleteMessages(ids: ["streaming"], chatID: chat.id, scope: scope)
            _ = transcriptStore.upsert(models.map { AgentMessageData.from($0) }, chatID: chat.id, scope: scope)
        }
        return models
    }

    private static func canonicalWorkspacePath(_ path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// Switches the visible agent session without sharing its chats, project
    /// root, or project-specific instructions with the other mode.
    func activateScope(
        _ scope: AgentSessionScope,
        preferredWorkspace: String? = nil,
        restorePersistedWorkspace: Bool = true
    ) {
        if activeScope != scope {
            saveChats()
            activeScope = scope
            activeKernelRunID = UserDefaults.standard.string(forKey: durableRunStorageKey)
            chatSessions = readChats(for: scope)
            activeChatId = UserDefaults.standard.string(forKey: activeChatStorageKey)

            if let activeChatId,
               let chat = chatSessions.first(where: { $0.id == activeChatId }) {
                messages = loadMessagesForChat(chat, scope: scope)
            } else if let first = chatSessions.first {
                activeChatId = first.id
                messages = loadMessagesForChat(first, scope: scope)
            } else {
                messages = []
                _ = createNewChat(name: scope == .science ? "Research 1" : "Task 1")
            }
        } else if messages.isEmpty,
                  let activeChatId,
                  let chat = chatSessions.first(where: { $0.id == activeChatId }) {
            let restored = loadMessagesForChat(chat, scope: scope)
            if !restored.isEmpty {
                messages = restored
            }
        }

        domain = scope == .science ? .science : .software
        if scope == .science {
            scienceProjectContext = cachedScienceProjectContext
        } else {
            scienceIndexTask?.cancel()
            scienceIndexTask = nil
            scienceIndexGeneration = UUID()
            scienceProjectContext = nil
            isIndexingScienceProject = false
        }

        let savedWorkspace = restorePersistedWorkspace ? UserDefaults.standard.string(forKey: workspaceStorageKey) : nil
        let workspace = (preferredWorkspace?.isEmpty == false) ? preferredWorkspace : savedWorkspace
        if let workspace, !workspace.isEmpty {
            setWorkspace(workspace)
        } else if scope == .science {
            toolBox.workspaceRoot = nil
            agentMdContent = nil
            taskMdContent = nil
        }
    }

    private var lastConfiguredWorkspacePath: String?

    func setWorkspace(_ rawPath: String) {
        let path = Self.canonicalWorkspacePath(rawPath) ?? ""
        let currentRoot = Self.canonicalWorkspacePath(toolBox.workspaceRoot) ?? ""
        let didChangeWorkspace = currentRoot != path
        if !didChangeWorkspace && !path.isEmpty && lastConfiguredWorkspacePath == path {
            return
        }
        lastConfiguredWorkspacePath = path
        if didChangeWorkspace {
            cachedSemanticContext = nil
            if !messages.isEmpty {
                saveCurrentChatMessages()
            }
        }
        toolBox.workspaceRoot = path
        UserDefaults.standard.set(path, forKey: workspaceStorageKey)

        // Editor instructions and MCP configuration must not leak into a
        // scientific research session. Science has its own indexed evidence.
        if activeScope == .editor {
            loadAgentWorkspaceFiles(path)
            WorkspaceScopeGuard.shared.syncWorkspace(path)
            loadPinnedConstraints(for: path)
            refreshProjectBriefing()
            MultiPlatformRulesEngine.shared.refresh(workspaceRoot: path)
            MCPClient.shared.configure(workspacePath: path)
            ProjectMemoryService.shared.loadProjectMemory(workspace: path)
            // Discover external MCP servers lazily (do not spawn Node/Python until needed)
            let discovered = MultiPlatformRulesEngine.shared.discoveredMCPServers
            if !discovered.isEmpty {
                ExternalMCPManager.shared.syncWithDiscoveredServers(discovered, autoStart: false)
            }
        } else {
            agentMdContent = nil
            taskMdContent = nil
            if let cached = cachedScienceProjectContext,
               cached.rootPath != path {
                cachedScienceProjectContext = nil
                scienceProjectContext = nil
            }
        }
        if domain == .science, didChangeWorkspace {
            refreshScienceProjectContext()
        }
        
        // Strict Multi-Project Isolation:
        // Automatically switch or bind chat sessions to this workspace to prevent cross-project bleeding,
        // while NEVER wiping out an actively running or freshly started conversation.
        if didChangeWorkspace && activeScope == .editor {
            if path.isEmpty {
                if messages.isEmpty, !isLoading, executionTask == nil,
                   let idx = chatSessions.firstIndex(where: { $0.id == activeChatId }) {
                    chatSessions[idx].projectPath = nil
                    chatSessions[idx].projectName = "General"
                    saveChats()
                }
            } else {
                let currentChat = chatSessions.first(where: { $0.id == activeChatId })
                let currentChatPath = Self.canonicalWorkspacePath(currentChat?.projectPath)
                if currentChatPath != path {
                    let isUnassignedChat = (currentChatPath == nil || currentChatPath?.isEmpty == true)
                    if (messages.isEmpty || isLoading || executionTask != nil || isUnassignedChat),
                       let idx = chatSessions.firstIndex(where: { $0.id == activeChatId }) {
                        // Rebind the active conversation directly to the project without clearing messages
                        let folderName = URL(fileURLWithPath: path).lastPathComponent
                        let existingCount = chatSessions.filter {
                            $0.id != activeChatId && Self.canonicalWorkspacePath($0.projectPath) == path
                        }.count
                        chatSessions[idx].projectPath = path
                        chatSessions[idx].projectName = folderName
                        if chatSessions[idx].name.hasPrefix("Task ") {
                            chatSessions[idx].name = "Task \(existingCount + 1)"
                        }
                        saveChats()
                    } else if let matchingChat = chatSessions.first(where: { Self.canonicalWorkspacePath($0.projectPath) == path }) {
                        switchChat(to: matchingChat.id)
                    } else {
                        _ = createNewChat(projectPath: path)
                    }
                }
                NotificationCenter.default.post(name: NSNotification.Name("MicroCodeWorkspaceChanged"), object: path)
            }
        }
    }

    /// Schedules a bounded project inventory after the mode transition has
    /// rendered. A newer mode/project switch cancels the pending work.
    func refreshScienceProjectContext(force: Bool = false) {
        guard activeScope == .science, let path = toolBox.workspaceRoot, !path.isEmpty else { return }
        if !force, let cachedScienceProjectContext,
           cachedScienceProjectContext.rootPath == path {
            scienceProjectContext = cachedScienceProjectContext
            return
        }

        scienceIndexTask?.cancel()
        let generation = UUID()
        scienceIndexGeneration = generation
        isIndexingScienceProject = false
        scienceIndexTask = Task { [weak self] in
            // Give SwiftUI one run-loop turn to display the requested mode.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled,
                  let self,
                  self.activeScope == .science,
                  self.scienceIndexGeneration == generation,
                  self.toolBox.workspaceRoot == path else { return }

            self.isIndexingScienceProject = true
            let context = await Task.detached(priority: .utility) {
                ScienceService.indexWorkspace(at: URL(fileURLWithPath: path))
            }.value
            guard !Task.isCancelled,
                  self.activeScope == .science,
                  self.scienceIndexGeneration == generation,
                  self.toolBox.workspaceRoot == path else { return }
            self.cachedScienceProjectContext = context
            self.scienceProjectContext = context
            self.isIndexingScienceProject = false
        }
    }

    func suspendScienceWork() {
        scienceIndexTask?.cancel()
        scienceIndexTask = nil
        scienceIndexGeneration = UUID()
        isIndexingScienceProject = false
    }

    private func semanticContext() -> String? {
        let workspace = toolBox.workspaceRoot ?? ""
        if let cachedSemanticContext,
           cachedSemanticContext.workspace == workspace,
           Date().timeIntervalSince(cachedSemanticContext.date) < semanticContextTTL {
            tokenOptimizer.recordContextCache(hit: true, tokens: tokenOptimizer.estimateTokens(cachedSemanticContext.value))
            return cachedSemanticContext.value
        }
        tokenOptimizer.recordContextCache(hit: false, tokens: 0)
        guard let smartContext = try? AuthenticLanguageCore.shared()?.aiContext(),
              let description = smartContext.llmContextDescription() else { return nil }
        let compressed = tokenOptimizer.compressText(description, targetTokens: 500)
        cachedSemanticContext = (workspace, compressed, Date())
        return compressed
    }
    
    // MARK: - Advanced .microcode Templates & Directives
    
    public static func defaultAgentMarkdown() -> String {
        return """
        # MicroCode Workspace Agent Directive
        <!-- microcode:managed-agent -->

        ## 1. Operating Identity & Core Mandate
        - You are the autonomous MicroCode workspace engineer and code orchestrator.
        - You have direct access to native developer tools (`file_read`, `replace_in_file`, `patch_file`, `shell`, `device_runtime`, `subagent_orchestration`).
        - Your core duty is delivering reliable, high-stability code changes backed by verified test and build results.

        ## 2. Strict Prohibitions & Hard Constraints (ข้อห้ามเด็ดขาด - DO NOTs)
        - 🚫 **STRICT ZERO-PRIVACY LEAKAGE (ห้ามเก็บข้อมูลส่วนตัว/รหัสลับเด็ดขาด)**:
          - NEVER write, log, commit, or persist API keys (`sk-...`, `AIza...`, `ghp_...`), auth tokens, bearer tokens, passwords, private keys, SSH certificates, session cookies, database credentials, or Personally Identifiable Information (PII) into `.microcode/agent.md`, `.microcode/task.md`, `.microcode/walkthrough.md`, git history, or any workspace file.
          - All credentials must be accessed strictly via OS Keychain, `.env` (gitignored), or environment variables.
          - Always sanitize and redact sensitive values with `[REDACTED_SECRET_FOR_PRIVACY]`.
        - 🚫 **NO Destructive / Irreversible Operations**:
          - Never execute destructive commands without confirmation (`rm -rf /`, `rm -rf ~`, `DROP DATABASE`, `mkfs`, force-killing critical system daemons).
          - Never run `git reset --hard`, `git clean -fd`, or force-push without explicit user request.
        - 🚫 **NO Phantom / Hallucinated Verification**:
          - Never claim that code compiles, tests pass, or bugs are fixed without real terminal tool execution evidence.
          - Never ask the user to manually run verification steps or press "Run" when native agent tools are available.
        - 🚫 **NO Half-Finished Placeholder Implementations**:
          - Never leave unfinished stubs (`// TODO: implement later`, `pass`, `...`) in production logic.
        - 🚫 **NO Scope Creep**:
          - Do not rewrite unrelated files or introduce unrequested third-party dependencies outside the assigned task scope.

        ## 3. Four-Phase Autonomous Execution Protocol
        Every non-trivial task must progress through four sequential phases:
        1. **Phase 1: Deep Workspace Inspection & Baseline Diagnostics**
           - Read relevant source files using native read tools before proposing edits.
           - Inspect compiler diagnostics, LSP errors, dependencies, and git status.
           - Formulate a clear plan with dependencies before modifying code.
        2. **Phase 2: Atomic Implementation**
           - Apply surgical, localized edits (`replace_in_file`, `patch_file`, or focused rewrites).
           - Maintain consistent coding style, indentation, architecture patterns, and naming conventions.
           - Guard against syntax errors and type mismatches.
        3. **Phase 3: Deterministic Verification & Validation**
           - Run compilation commands (e.g. `swift build`, `cargo check`, `npm run build`, `gradle compileDebugSources`).
           - Run unit tests and integration tests relevant to the changed modules.
           - Check device runtimes or emulators when developing mobile or cross-platform code.
           - Capture clean evidence (exit code, build duration, test pass counts).
        4. **Phase 4: Privacy & Git Safety Audit**
           - Review git status and diff (`git diff`) before finalizing.
           - Verify that NO private secrets or credentials have been written into `.microcode/` or workspace files.
           - Update `.microcode/task.md` checklist with completion evidence.

        ## 4. Multi-Model Collaboration & Task Partitioning
        - When delegating subtasks to subagents via `invoke_subagent`, each subtask must have a distinct, non-overlapping owner.
        - Specialized roles: `architect`, `frontend_engineer`, `backend_engineer`, `bug_hunter`, `test_runner`, `security_auditor`.

        ## 5. Durable Project Conventions
        <!-- Add durable project conventions, tech stack guidelines, or architecture patterns below -->
        """
    }

    public static func defaultTaskMarkdown(objective: String = "") -> String {
        let safeObjective = objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "<!-- Describe the objective here -->"
            : String(objective.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8000))
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        return """
        # Workspace Autonomous Task
        <!-- microcode:managed-task -->

        ## 📋 Task Overview
        - **Objective**: \(safeObjective)
        - **Status**: 🟡 IN_PROGRESS  <!-- PENDING | IN_PROGRESS | COMPLETED | FAILED -->
        - **Active Owner**: main
        - **Last Updated**: \(timestamp)

        ---

        ## 🎯 Scope Boundaries
        - **In Scope**: Targeted changes requested for this objective.
        - **Out of Scope**: Unrelated refactoring, third-party library additions, modifying secrets.

        ---

        ## 🚀 Execution Phases & Structured TODOs

        ### Phase 1: Inspection & Baseline Analysis
        - [ ] **1.1** Inspect workspace files, dependencies, and existing architectural patterns.
        - [ ] **1.2** Check compiler diagnostics, LSP errors, and current git status.
        - [ ] **1.3** Formulate atomic changes and verify preconditions.

        ### Phase 2: Implementation & Code Changes
        - [ ] **2.1** Implement core changes surgically using targeted edit tools.
        - [ ] **2.2** Ensure full backward compatibility and adhere to project code style.
        - [ ] **2.3** Preserve all existing functionality and comments.

        ### Phase 3: Verification & Evidence Capture
        - [ ] **3.1** Run build/compilation tool and ensure zero errors.
        - [ ] **3.2** Run test suite to verify no regressions.
        - [ ] **3.3** Verify live app behavior or inspect UI elements.

        ### Phase 4: Privacy Audit & Completion
        - [ ] **4.1** Verify git diff to ensure no unexpected files were touched.
        - [ ] **4.2** 🔒 **PRIVACY CHECK**: Confirm ZERO API keys, tokens, credentials, or PII are present in `.microcode/` or project files.
        - [ ] **4.3** Mark task as COMPLETED and report verified results.

        ---

        ## 🛡️ Active Constraints & Safety Guidelines
        1. **Zero Secret Storage**: Never write passwords, keys, or auth headers into this file.
        2. **Autonomous Execution**: Run build and test tools directly; do not offload execution to the user.
        3. **Evidence-Based Completion**: Mark items `[x]` ONLY after tool verification has succeeded.

        ---

        ## 📊 Verification Log
        - Baseline check: Pending
        - Build status: Pending
        - Privacy audit: Clean
        """
    }
    
    // MARK: - Load agent.md / task.md / AI.arx
    
    func reloadAgentWorkspaceFiles() {
        guard let workspacePath = toolBox.workspaceRoot else { return }
        let fm = FileManager.default
        let microcodeDir = (workspacePath as NSString).appendingPathComponent(".microcode")
        
        let agentMdPath = (microcodeDir as NSString).appendingPathComponent("agent.md")
        if fm.fileExists(atPath: agentMdPath) {
            agentMdContent = try? String(contentsOfFile: agentMdPath, encoding: .utf8)
        }
        
        let taskMdPath = (microcodeDir as NSString).appendingPathComponent("task.md")
        if fm.fileExists(atPath: taskMdPath) {
            taskMdContent = try? String(contentsOfFile: taskMdPath, encoding: .utf8)
        }
    }
    
    private func loadAgentWorkspaceFiles(_ workspacePath: String) {
        let fm = FileManager.default
        
        // Create .microcode directory
        let microcodeDir = (workspacePath as NSString).appendingPathComponent(".microcode")
        if !fm.fileExists(atPath: microcodeDir) {
            try? fm.createDirectory(atPath: microcodeDir, withIntermediateDirectories: true)
        }
        
        // Load or create agent.md
        let agentMdPath = (microcodeDir as NSString).appendingPathComponent("agent.md")
        let agentURL = URL(fileURLWithPath: agentMdPath)
        if fm.fileExists(atPath: agentMdPath) {
            agentMdContent = try? String(contentsOfFile: agentMdPath, encoding: .utf8)
            logActivity(.info, "Loaded agent.md")
        } else {
            let defaultAgentMd = Self.defaultAgentMarkdown()
            try? AgentPrivacyGuard.safeWrite(content: defaultAgentMd, to: agentURL)
            agentMdContent = defaultAgentMd
            logActivity(.info, "Created agent.md")
        }
        
        // Load or create task.md
        let taskMdPath = (microcodeDir as NSString).appendingPathComponent("task.md")
        let taskURL = URL(fileURLWithPath: taskMdPath)
        if fm.fileExists(atPath: taskMdPath) {
            taskMdContent = try? String(contentsOfFile: taskMdPath, encoding: .utf8)
            logActivity(.info, "Loaded task.md")
        } else {
            let defaultTaskMd = Self.defaultTaskMarkdown()
            try? AgentPrivacyGuard.safeWrite(content: defaultTaskMd, to: taskURL)
            taskMdContent = defaultTaskMd
            logActivity(.info, "Created task.md")
        }
        
        // Load or create AI.arx
        loadOrCreateArx(workspacePath)
    }
    
    // MARK: - Autonomous Task Plan Execution
    
    public func executeTaskPlan(
        provider: String,
        model: String,
        apiKey: String
    ) async {
        guard let ws = toolBox.workspaceRoot, !ws.isEmpty else {
            logActivity(.info, "No workspace open to execute tasks.")
            return
        }
        
        let taskPath = (ws as NSString).appendingPathComponent(".microcode/task.md")
        let taskContent = (try? String(contentsOfFile: taskPath, encoding: .utf8)) ?? taskMdContent ?? ""
        
        guard !taskContent.isEmpty else {
            logActivity(.info, "task.md is empty.")
            return
        }
        
        let prompt = """
        Autonomous Task Runner Execution:
        Please review and execute the following task plan defined in `.microcode/task.md`:
        
        ```markdown
        \(taskContent)
        ```
        
        Execution Directives:
        1. Inspect the workspace files and environment to verify current progress.
        2. Execute each uncompleted step (`- [ ]`) in sequential order using appropriate tools (`shell`, `file_write`, `replace_in_file`, etc.).
        3. After completing each step, immediately update `.microcode/task.md` to check off the completed step (e.g. change `- [ ]` to `- [x]`).
        4. Continue autonomously until all objectives are satisfied and verify the final state.
        """
        
        await sendMessage(
            prompt,
            provider: provider,
            model: model,
            apiKey: apiKey
        )
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
            models: [AIArxData.ModelUsage(provider: lastProvider, model: lastModel, lastUsed: Date())],
            memory: activityLog.suffix(50).map { AIArxData.MemoryEntry(content: $0.message, timestamp: $0.timestamp, role: "agent") },
            artifacts: filesModified.map { AIArxData.Artifact(path: $0, type: "modified", timestamp: Date()) },
            lastUpdated: Date()
        )
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(arxData) {
                try? data.write(to: URL(fileURLWithPath: arxPath))
            }
        }
    }
    
    // MARK: - Send Message (Production Agentic Loop)
    
    /// Synchronously prepares the active chat session, restores disk messages if needed,
    /// appends the user message, updates the chat title, and persists to disk in <1ms on @MainActor.
    @discardableResult
    func prepareUserTurn(_ content: String, createStreamingPlaceholder: Bool = false) -> AgentMessageModel {
        if activeChatId == nil || !chatSessions.contains(where: { $0.id == activeChatId }) {
            let newChat = createNewChat(projectPath: toolBox.workspaceRoot)
            activeChatId = newChat.id
        } else if messages.isEmpty,
                  let activeChatId,
                  let existingChat = chatSessions.first(where: { $0.id == activeChatId }) {
            let restored = loadMessagesForChat(existingChat, scope: activeScope)
            if !restored.isEmpty {
                messages = restored
            }
        }
        
        // Guarantee any previous streaming placeholder is promoted to a permanent UUID (or removed if empty)
        // BEFORE appending the new user message so messages are always strictly ordered.
        finalizeStaleStreamingMessages(appendStopMarker: false)
        
        let userMessage = AgentMessageModel(
            id: UUID().uuidString, role: .user, content: content,
            toolResults: [], pendingChanges: [], timestamp: Date()
        )
        messages.append(userMessage)
        if createStreamingPlaceholder {
            isCancelled = false
            updateStreamingMessage("", toolResults: [])
        }
        
        if let chatId = activeChatId {
            memoryService.storeMemory(content: content, chatId: chatId, role: "user", projectPath: toolBox.workspaceRoot)
            if let idx = chatSessions.firstIndex(where: { $0.id == chatId }) {
                let currentTitle = chatSessions[idx].name
                if currentTitle.hasPrefix("Task ") || currentTitle == "New Task" || currentTitle.hasPrefix("Chat ") || currentTitle.isEmpty {
                    let newTitle = Self.generateTitle(from: content)
                    chatSessions[idx].name = newTitle
                }
            }
            saveCurrentChatMessages()
        }
        objectWillChange.send()
        return userMessage
    }

    /// Synchronous entry point on @MainActor so that user messages appear in the UI immediately
    /// in the same runloop frame as clearing the input box, and rapid consecutive sends never race.
    func startOrEnqueueMessage(
        _ content: String,
        provider: String = "gemini",
        model: String = "gemini-2.5-flash",
        apiKey: String = "",
        attachments: [AIAttachment] = []
    ) {
        if !apiKey.isEmpty {
            lastApiKey = apiKey
        }
        guard !isLoading, executionTask == nil else {
            logActivity(.info, "Agent is already busy. Enqueuing request.")
            enqueueMessage(content, attachments: attachments)
            return
        }
        isLoading = true
        isCancelled = false
        agentPhase = .thinking
        currentToolExecution = "Analyzing request & planning..."
        filesModified = []
        suggestedAction = nil
        if tokenShieldEnabled && messages.count > 3 {
            _ = pruneBulkyToolOutputs()
        }
        TelemetryService.shared.recordAIUsage(
            provider: provider,
            model: model,
            taskLabel: domain == .science ? "Science AI Agent" : "AI Agent"
        )
        
        let userMessage = prepareUserTurn(content, createStreamingPlaceholder: true)
        let id = UUID()
        executionID = id
        shouldProcessQueueAfterRun = true
        let task = Task { @MainActor in
            await self.runMessage(
                content,
                preparedUserMessage: userMessage,
                runExecutionID: id,
                provider: provider,
                model: model,
                apiKey: apiKey,
                attachments: attachments
            )
            if self.executionID == id {
                self.executionTask = nil
                self.executionID = nil
            }
        }
        executionTask = task
    }
    
    func sendMessage(
        _ content: String,
        provider: String = "gemini",
        model: String = "gemini-2.5-flash",
        apiKey: String = "",
        attachments: [AIAttachment] = []
    ) async {
        if !apiKey.isEmpty {
            lastApiKey = apiKey
        }
        guard !isLoading, executionTask == nil else {
            logActivity(.info, "Agent is already busy. Enqueuing request.")
            enqueueMessage(content, attachments: attachments)
            return
        }
        isLoading = true
        isCancelled = false
        agentPhase = .thinking
        currentToolExecution = "Analyzing request & planning..."
        filesModified = []
        suggestedAction = nil
        if tokenShieldEnabled && messages.count > 3 {
            _ = pruneBulkyToolOutputs()
        }
        TelemetryService.shared.recordAIUsage(
            provider: provider,
            model: model,
            taskLabel: domain == .science ? "Science AI Agent" : "AI Agent"
        )
        
        let userMessage = prepareUserTurn(content, createStreamingPlaceholder: true)
        let id = UUID()
        executionID = id
        shouldProcessQueueAfterRun = true
        let task = Task {
            await self.runMessage(
                content,
                preparedUserMessage: userMessage,
                runExecutionID: id,
                provider: provider,
                model: model,
                apiKey: apiKey,
                attachments: attachments
            )
        }
        executionTask = task
        await task.value
        if executionID == id {
            executionTask = nil
            executionID = nil
        }
    }

    private func runMessage(
        _ content: String,
        preparedUserMessage: AgentMessageModel? = nil,
        runExecutionID: UUID = UUID(),
        provider: String,
        model: String,
        apiKey: String,
        attachments: [AIAttachment]
    ) async {
        if executionID == nil {
            executionID = runExecutionID
        }
        isLoading = true
        isCancelled = false
        agentPhase = .thinking
        currentToolExecution = "Analyzing request & planning..."
        logActivity(.thinking, "Processing request...")

        let userMessage = preparedUserMessage ?? prepareUserTurn(content, createStreamingPlaceholder: true)
        
        // P2: Record agent start in Flight Recorder
        FlightRecorder.shared.record(
            actor: .user,
            action: .agentStart,
            target: AuditTarget(type: "model", path: "\(provider)/\(model)", workspace: currentWorkspace ?? ""),
            details: String(content.prefix(200))
        )
        
        // Universal Context Protocol & Mentions Expansion (@file, @git, @diagnostics, @symbol, @rules)
        let mentionContext = await AgentContextProtocolBridge.shared.expandMentions(
            prompt: content,
            workspaceRoot: toolBox.workspaceRoot
        )
        let effectiveContent = mentionContext.expandedPrompt
        if !mentionContext.resolvedMentions.isEmpty {
            logActivity(.info, "Bridge: Expanded mentions: \(mentionContext.resolvedMentions.joined(separator: ", "))")
        }
        // Feature #4: Register @mentioned and active editor files for Strict Scope Guard
        WorkspaceScopeGuard.shared.registerMentionedFiles(
            mentionContext.resolvedMentions,
            activeEditorFile: editorContext?.activeFile,
            workspaceRoot: toolBox.workspaceRoot
        )
        defer {
            if self.executionID == runExecutionID {
                isLoading = false
                currentToolExecution = nil
                agentPhase = .idle
                saveArx()
                saveChats()
                IdleStateCompactor.shared.performAIWorkloadCompaction()
                objectWillChange.send()
                // Auto-process queue
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if self.shouldProcessQueueAfterRun { self.processQueue() }
                }
            }
        }
        
        // Detect task complexity and choose budget
        let detectedComplexity = tokenOptimizer.detectComplexity(content)
        let complexity: TokenBudget.TaskComplexity = detectedComplexity == .chat ? .moderate : detectedComplexity
        let budget = TokenBudget.forTask(complexity)
        let isContinuation = isContinuationRequest(content)
        // Never degrade into chat mode if an active run exists or if continuing prior work
        let isChatMode = false
        let isPlanModePrompt = content.contains("[PLAN MODE")
        let hasApprovedActivePlan = ImplementationPlanManager.shared.currentPlan?.approvalState == .approved
        let priorUserRequestedMutation = isContinuation && messages.contains(where: { $0.role == .user && requestRequiresMutation($0.content) })
        let requiresNativeExecution = domain == .software && !isChatMode && requestRequiresNativeExecution(content)
        let requiresRuntimeLaunch = domain == .software && !isChatMode && requestRequiresRuntimeLaunch(content)
        var requiresMutation = domain == .software && !isChatMode && !isPlanModePrompt && (
            requestRequiresMutation(content) ||
            hasApprovedActivePlan ||
            priorUserRequestedMutation
        )
        let inspectionRequested = ["inspect", "scan", "audit", "debug", "diagnose", "error", "harness", "ตรวจ", "เช็ค", "สแกน"]
            .contains(where: content.lowercased().contains) || isPlanModePrompt
        var requiresWorkspaceEvidence = requiresMutation || requiresNativeExecution || inspectionRequested

        // The task documents are an agent-owned execution contract, not a
        // form the user has to fill in before the agent is allowed to work.
        // Preserve handwritten plans, but generate/refresh the managed task
        // for each new request so every model begins from the same durable
        // objective and verification phases.
        if domain == .software, !isChatMode {
            prepareAutonomousTaskArtifacts(
                objective: content,
                isContinuation: isContinuation
            )
        }
        
        let normalizedAI = AIModelCatalog.shared.normalizedSelection(provider: provider, model: model)
        let resolvedProvider = normalizedAI.provider
        var resolvedModel = normalizedAI.model
        var detectedProvider = StreamableAIProvider(rawValue: resolvedProvider) ?? StreamableAIProvider.detect(from: resolvedModel)
        
        // Safety guard: Prevent mismatched models (e.g. gpt-*, o1*, claude-*) from routing to Gemini endpoint
        let lowerModel = resolvedModel.lowercased()
        let isGeminiModel = lowerModel.contains("gemini") || lowerModel.contains("gemma")
        let activeSub = UserDefaults.standard.string(forKey: "subscriptionActiveProvider")
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "cloud"
        if keyMode == "subscription" && (activeSub == "aipass" || resolvedProvider == "aipass") && SubscriptionAuthManager.shared.isConnected(.aipass) {
            detectedProvider = .aipass
        } else if detectedProvider == .gemini && !isGeminiModel {
            if keyMode == "subscription" {
                if activeSub == "aipass" || resolvedProvider == "aipass" {
                    detectedProvider = .aipass
                } else if activeSub == "copilot" || SubscriptionAuthManager.shared.isConnected(.copilot) || resolvedProvider == "copilot" {
                    detectedProvider = .copilot
                } else if activeSub == "chatgpt" || SubscriptionAuthManager.shared.isConnected(.chatgpt) {
                    detectedProvider = .openai
                } else if activeSub == "claude" || SubscriptionAuthManager.shared.isConnected(.claude) {
                    detectedProvider = .anthropic
                } else {
                    detectedProvider = StreamableAIProvider.detect(from: resolvedModel)
                }
            } else {
                detectedProvider = StreamableAIProvider.detect(from: resolvedModel)
            }
        }
        
        lastProvider = detectedProvider.rawValue
        lastModel = resolvedModel
        
        // Phase 2: SLM Router — only route to local model if explicitly opted-in by the user
        if UserDefaults.standard.bool(forKey: "slmAutoRouteToLocal") {
            let routeDecision = SLMRouter.shared.route(
                prompt: effectiveContent,
                currentProvider: detectedProvider.rawValue,
                currentModel: resolvedModel
            )
            if routeDecision.useLocal {
                resolvedModel = routeDecision.suggestedModel
                detectedProvider = .local
                SLMRouter.shared.recordRouting(complexity: .simple, model: routeDecision.suggestedModel, estimatedSavings: routeDecision.estimatedCostCloud)
                logActivity(.info, "SLM Router: \(routeDecision.reason)")
            }
        }
        
        if !isChatMode {
            await MCPClient.shared.ensureConnected(workspacePath: toolBox.workspaceRoot)
        }
        
        // Always provide tools in AgentService so the agent can always execute actions
        tokenOptimizer.beginTurnLoop()
        let allToolSchemas = toolBox.toolSchemas()
        let toolNames = allToolSchemas.compactMap { $0["name"] as? String }
        let slmComplexity = SLMRouter.shared.classifyTask(content)
        let hasMobilePreview = content.lowercased().contains("preview") || content.lowercased().contains("mobile") || content.lowercased().contains("ui") || content.lowercased().contains("device") || content.lowercased().contains("simulator")
        let currentDomain: AgentDomain? = activeScope == .science ? .science : nil
        var currentToolScope = ToolScope.scopeFor(
            prompt: content,
            complexity: slmComplexity,
            domain: currentDomain,
            hasMobilePreview: hasMobilePreview,
            hasMediaAttachments: !attachments.isEmpty
        )
        // TokenMem Layer 1 & 2: Compute sticky active tool schemas once from the initial user objective
        // so the `tools` array never mutates mid-loop (preserving 100% KV-prefix cache across iterations).
        let stickyEagerExternalMCP = ExternalMCPManager.shared.eagerExternalToolNames(forPrompt: content, maxExternalTools: 12)
        var stickyActiveTools = allToolSchemas.filter { (tool: [String: Any]) -> Bool in
            guard let name = tool["name"] as? String else { return true }
            if name.hasPrefix("mcp__") && !name.hasPrefix("mcp__local__") {
                return stickyEagerExternalMCP.contains(name)
            }
            guard let tier = ToolScope.toolTierMap[name] else { return true }
            return currentToolScope.contains(tier)
        }
        tokenOptimizer.recordSchemaOptimization(
            totalSchemasCount: toolBox.tools.count,
            activeSchemasCount: stickyActiveTools.count
        )
        let kernelRunID = (!isChatMode && isContinuation ? activeKernelRunID : nil) ?? userMessage.id
        activeKernelRunID = isChatMode ? nil : kernelRunID
        if !isChatMode {
            UserDefaults.standard.set(kernelRunID, forKey: durableRunStorageKey)
        }
        var kernelOnline = isChatMode
        if !isChatMode {
            let kernel = await agentKernel.createOrResume(
                runID: kernelRunID,
                objective: content,
                workspace: toolBox.workspaceRoot ?? "",
                provider: detectedProvider.rawValue,
                model: resolvedModel,
                tools: toolNames,
                skills: AgentSkillsStore.shared.enabledSkillIds(),
                mcpServers: {
                    var servers: [String] = []
                    if MCPClient.shared.isConnected { servers.append("local") }
                    servers.append(contentsOf: ExternalMCPManager.shared.connectedServerNames)
                    return servers
                }()
            )
            kernelOnline = kernel != nil
            if let kernel {
                logActivity(.info, "Agent kernel \(kernel.directive.action): durable run \(kernel.run.id.prefix(8))")
            } else {
                logActivity(.error, "Agent kernel unavailable; continuing with the bounded native fallback")
            }
        }
        
        // Build optimized system prompt
        let queryEmbedding = await memoryService.fetchEmbeddingFromBackend(content)
        let optimizedSystemPrompt = buildSystemPrompt(
            for: content,
            provider: detectedProvider,
            model: resolvedModel,
            queryEmbedding: queryEmbedding
        )
        
        // Build and compress prior conversation history (excluding the just-appended userMessage to avoid duplication)
        let rawHistory = buildConversationHistory(excludingMessageID: userMessage.id)
        var history = tokenOptimizer.compressHistory(rawHistory, budget: budget.maxHistoryTokens)
        let externallyModifiedFiles = detectExternalFileDrift()
        var turnPromptWithDrift = effectiveContent
        if !externallyModifiedFiles.isEmpty {
            let shortNames = externallyModifiedFiles.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            logActivity(.info, "⚠️ External file changes detected since last checkpoint: \(shortNames)")
            turnPromptWithDrift += "\n\n[Checkpoint Drift Notice: The following workspace files were modified externally on disk since the last agent checkpoint: \(externallyModifiedFiles.joined(separator: ", ")). Re-read them with `file_read` before applying edits so external changes are not overwritten.]"
        }
        history.append((role: "user", content: turnPromptWithDrift))
        
        logActivity(.info, "Mode: \(isChatMode ? "Chat" : "Agent") | Budget: \(budget.totalBudget) tokens")
        
        // === Agentic Tool Loop ===
        let toolIterationLimit = maxToolIterations
        var iteration = 0
        var finalText = ""
        var lastPreToolText = ""
        var allToolResults: [ToolResultModel] = []
        var allChanges: [PendingChangeModel] = []
        var completedToolCalls: [String: (output: String, success: Bool)] = [:]
        var terminationNotice: String? = nil
        var usedDeterministicActionFallback = false
        var usedRuntimeLaunchFallback = false
        var usedAutonomousInspectionFallback = false
        var usedPostMutationVerificationFallback = false
        var usedFollowThroughRecovery = false
        var usedPreFinishHookCheck = false
        var kernelRecoveryCount = 0
        var followThroughNagCount = 0
        var recentAssistantOutputs: [String] = []
        var kernelVerified = false
        var pendingVerificationAfterEdit = false
        var verificationPassCount = 0
        var effectiveApiKey = apiKey
        var failoverTriedModels: Set<String> = ["\(detectedProvider.rawValue)/\(resolvedModel)"]

        while toolIterationLimit.map({ iteration < $0 }) ?? true {
            if isCancelled || Task.isCancelled { break }
            iteration += 1
            if kernelOnline {
                _ = await agentKernel.observe(
                    runID: kernelRunID,
                    kind: "model_start",
                    output: "Model turn \(iteration) started"
                )
            }
            
            // Stream the response
            var streamedText = ""
            streamedText.reserveCapacity(16384)
            var receivedToolCalls: [AIToolCall] = []
            
            // Use streaming for ALL iterations to keep UI responsive
            if iteration == 1 {
                currentToolExecution = "Analyzing request & planning..."
                agentPhase = .thinking
            } else {
                currentToolExecution = "Evaluating tool outputs & determining next action..."
                agentPhase = .thinking
                // Compress iterative history dynamically so context never blows up
                history = tokenOptimizer.compressIterativeToolHistory(history, budget: budget.maxHistoryTokens)
            }
            
            // Keep the latest user/tool-result turn in history until the model call succeeds,
            // so retries never drop the user prompt or previous tool outputs.
            let nextPrompt = history.last?.content ?? effectiveContent
            let priorHistory = history.count > 1 ? Array(history.dropLast()) : []
            
            do {
                let result = await withCheckedContinuation { (continuation: CheckedContinuation<(String, [AIToolCall], String?), Never>) in
                    var toolCalls: [AIToolCall] = []
                    var turnText = ""
                    turnText.reserveCapacity(8192)
                    var text = finalText.isEmpty ? "" : finalText + "\n\n"
                    text.reserveCapacity(max(16384, text.count + 4096))
                    
                    let isDirectMediaModel = AIClient.isAiPassMediaModel(resolvedModel)
                    aiClient.sendMessage(
                        prompt: nextPrompt,
                        attachments: iteration == 1 ? attachments : [],
                        systemPrompt: isDirectMediaModel ? nil : optimizedSystemPrompt,
                        conversationHistory: isDirectMediaModel ? [] : priorHistory,
                        provider: detectedProvider,
                        model: resolvedModel,
                        apiKey: effectiveApiKey,
                        tools: isDirectMediaModel ? nil : stickyActiveTools,
                        onToken: { token in
                            turnText += token
                            self.pushStreamingToken(token, currentFullText: &text, toolResults: allToolResults)
                        },
                        onToolCall: { toolCall in
                            toolCalls.append(toolCall)
                        },
                        onComplete: { fullText in
                            let resolvedTurn = fullText.isEmpty ? turnText : fullText
                            let combined = finalText.isEmpty ? resolvedTurn : (resolvedTurn.isEmpty ? finalText : finalText + "\n\n" + resolvedTurn)
                            self.flushStreamingToken(combined, toolResults: allToolResults)
                            continuation.resume(returning: (resolvedTurn, toolCalls, nil))
                        },
                        onError: { error in
                            continuation.resume(returning: ("", [], String(describing: error)))
                        }
                    )
                }
                
                if let err = result.2 {
                    throw NSError(domain: "Agent", code: -1, userInfo: [NSLocalizedDescriptionKey: err])
                }
                
                streamedText = result.0
                receivedToolCalls = result.1.map { tc in
                    AIToolCall(
                        id: tc.id,
                        name: AgentToolBox.normalizeToolName(tc.name),
                        arguments: AgentToolBox.normalizeToolParams(tc.arguments),
                        thoughtSignature: tc.thoughtSignature
                    )
                }
                
                // Universal SubAgent & Tool Empowerment: allow models without native subagent/tool support to delegate via <ceo_delegate> / <tool_call>
                let universalParsed = SubAgentHarness.shared.parseUniversalFallbackToolCalls(
                    from: streamedText,
                    senderRole: "👔 Main Agent",
                    senderBadge: resolvedModel
                )
                if !universalParsed.toolCalls.isEmpty {
                    receivedToolCalls.append(contentsOf: universalParsed.toolCalls)
                    streamedText = universalParsed.cleanedText
                }
                
                if receivedToolCalls.isEmpty || streamedText.contains("[Tool Call:") {
                    let parsedCalls = parseTextBasedToolCalls(streamedText)
                    if !parsedCalls.isEmpty {
                        receivedToolCalls.append(contentsOf: parsedCalls)
                        logActivity(.info, "Parsed \(parsedCalls.count) tool call(s) from text output")
                    }
                }
                streamedText = AIStructuredTurnCodec.stripToolCallArtifacts(streamedText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !streamedText.isEmpty {
                    if !receivedToolCalls.isEmpty {
                        // This iteration is invoking tools: strip any raw code blocks from pre-tool text so tool-calling turns
                        // never dump source files into the chat bubble while tools are executing.
                        let preToolClean = streamedText
                            .replacingOccurrences(of: #"```[\s\S]*?```"#, with: "", options: .regularExpression)
                            .replacingOccurrences(of: #"```[\s\S]*$"#, with: "", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        lastPreToolText = preToolClean
                        flushStreamingToken(preToolClean, toolResults: allToolResults)
                    } else {
                        if finalText.isEmpty {
                            finalText = streamedText
                        } else if !finalText.contains(streamedText) {
                            finalText += "\n\n" + streamedText
                        }
                        flushStreamingToken(finalText, toolResults: allToolResults)
                    }
                } else {
                    flushStreamingToken(finalText.isEmpty ? lastPreToolText : finalText, toolResults: allToolResults)
                }
            } catch {
                if isCancelled || Task.isCancelled { break }
                let errStr = error.localizedDescription
                let lowerErr = errStr.lowercased()
                let isContextLimit = lowerErr.contains("context_length_exceeded")
                    || lowerErr.contains("maximum context length")
                    || lowerErr.contains("prompt is too long")
                    || lowerErr.contains("token limit exceeded")
                    || lowerErr.contains("context window")
                    || lowerErr.contains("too many tokens")
                let isRateLimit = lowerErr.contains("rate limit") || lowerErr.contains("429") || lowerErr.contains("too many requests")
                let isQuotaOrOverload = lowerErr.contains("quota") || lowerErr.contains("insufficient") || lowerErr.contains("credit") || lowerErr.contains("402") || lowerErr.contains("403") || lowerErr.contains("401") || lowerErr.contains("404") || lowerErr.contains("authentication failed") || lowerErr.contains("503") || lowerErr.contains("529") || lowerErr.contains("overloaded") || lowerErr.contains("502")
                let isTransient = isTransientAgentError(errStr)
                logActivity(.error, "Tool loop iteration \(iteration): \(errStr)")
                
                if isContextLimit {
                    // Feature #5: Auto-prune bulky tool outputs first before giving up on context limit!
                    let freed = pruneBulkyToolOutputs()
                    if freed > 500 && kernelRecoveryCount < 2 {
                        kernelRecoveryCount += 1
                        history = tokenOptimizer.compressIterativeToolHistory(history, budget: 24_000)
                        logActivity(.info, "Context X-Ray Auto-Pruner: Freed ~\(freed) tokens from bulky tool outputs; resuming turn.")
                        currentToolExecution = "Context Auto-Pruned (~\(freed) tokens freed) — resuming..."
                        continue
                    }
                    contextLimitReached = true
                    let limitNotice = """
                    ⚠️ **Conversation Context Limit Reached**
                    The current session has reached the model's maximum context capacity (\(iteration) turns executed).
                    To continue with optimal accuracy and performance, please start a new conversation or use Context X-Ray Pruner.
                    """
                    terminationNotice = "Context limit reached"
                    if !finalText.contains("Context Limit Reached") {
                        finalText = finalText.isEmpty ? limitNotice : finalText + "\n\n" + limitNotice
                    }
                    updateStreamingMessage(finalText, toolResults: allToolResults)
                    logActivity(.error, "Context window saturated. Prompting user to start a new chat.")
                    currentToolExecution = nil
                    break
                }

                // Feature #3: Zero-Drop Auto-Failover & Cross-Provider Handoff
                if autoFailoverEnabled && (isRateLimit || isQuotaOrOverload || (isTransient && kernelRecoveryCount >= 1)),
                   let backup = resolveFailoverCandidate(
                       currentProvider: detectedProvider,
                       currentModel: resolvedModel,
                       triedModels: failoverTriedModels
                   ) {
                    let previousLabel = "\(detectedProvider.rawValue)/\(resolvedModel)"
                    detectedProvider = backup.provider
                    resolvedModel = backup.model
                    effectiveApiKey = backup.apiKey
                    failoverTriedModels.insert("\(backup.provider.rawValue)/\(backup.model)")
                    lastFailoverBanner = "Auto-Failover: \(previousLabel) → \(backup.label)"
                    currentToolExecution = "Auto-Failover → \(backup.label) (resuming turn seamlessly...)"
                    agentPhase = .thinking
                    logActivity(.info, "Auto-Failover: Switched from \(previousLabel) to \(backup.label) to prevent session drop")
                    if isRateLimit {
                        history = tokenOptimizer.compressIterativeToolHistory(history, budget: 36_000)
                    }
                    iteration -= 1 // Do not penalize iteration count for provider handoff
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    continue
                }
                
                let response = kernelOnline ? await agentKernel.observe(
                    runID: kernelRunID,
                    kind: "provider_error",
                    success: false,
                    error: errStr,
                    transient: isTransient
                ) : nil
                
                let maxRetries = isRateLimit ? 8 : 5
                if response?.directive.action == "retry" || isTransient || isRateLimit || (!kernelOnline && kernelRecoveryCount < maxRetries) {
                    if kernelRecoveryCount < maxRetries {
                        kernelRecoveryCount += 1
                        let backoffSec = isRateLimit ? min(3 * kernelRecoveryCount, 30) : min(kernelRecoveryCount * 2, 12)
                        let delayMs = response?.directive.retryAfterMs ?? UInt64(backoffSec * 1000)
                        
                        currentToolExecution = isRateLimit
                            ? "Rate limit reached. Backing off... resuming in \(backoffSec)s (attempt \(kernelRecoveryCount)/\(maxRetries))"
                            : "Connection interrupted. Retrying in \(delayMs / 1000)s (attempt \(kernelRecoveryCount)/\(maxRetries))...."
                        agentPhase = .thinking
                        
                        logActivity(.info, "Model call throttled or interrupted; retrying in \(delayMs)ms (attempt \(kernelRecoveryCount)/\(maxRetries))")
                        try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                        if isRateLimit {
                            // Compress older turns while preserving the latest prompt/tool results at history.last
                            history = tokenOptimizer.compressIterativeToolHistory(history, budget: 32_000)
                        }
                        continue
                    }
                }
                
                terminationNotice = response?.directive.reason ?? "Execution stopped: \(errStr)"
                let userFriendlyNotice = isRateLimit 
                    ? "⚠️ Rate limit reached from provider API (HTTP 429: Requests or Tokens Per Minute quota exceeded on your API key). Please wait a moment for the provider quota window to reset, start a new chat, or check your quota in Google AI Studio / provider console."
                    : "⚠️ Execution error: \(errStr)"
                if finalText.isEmpty { finalText = userFriendlyNotice } else { finalText += "\n\n" + userFriendlyNotice }
                updateStreamingMessage(finalText, toolResults: allToolResults)
                currentToolExecution = nil
                break
            }


            
            // Direct TH-AI Passport media models (Image, Video, Music) complete in a single turn
            if AIClient.isAiPassMediaModel(resolvedModel) {
                currentToolExecution = nil
                break
            }

            // If no native tool calls, try to parse text-based tool calls (for local LLMs)
            if receivedToolCalls.isEmpty {
                let parsedCalls = parseTextBasedToolCalls(streamedText)
                if !parsedCalls.isEmpty {
                    receivedToolCalls = parsedCalls
                    logActivity(.info, "Parsed \(parsedCalls.count) tool call(s) from text output")
                }
            }
            
            // A natural-language plan is not evidence of unfinished work. Claude
            // commonly says "I'll …" before a complete answer; using those words
            // as a signal to continue was the source of runaway agent loops.
            if receivedToolCalls.isEmpty {
                let hasMutationCheckpoint = allToolResults.contains(where: didMutateWorkspace)
                let hasVerificationCheckpoint: Bool
                if let latestMutation = allToolResults.lastIndex(where: didMutateWorkspace) {
                    hasVerificationCheckpoint = allToolResults
                        .dropFirst(latestMutation + 1)
                        .contains(where: isVerificationCheckpoint)
                } else {
                    hasVerificationCheckpoint = false
                }

                // Start a safe workspace inventory when a provider answers a
                // coding request with only "I'll inspect…" prose. This keeps
                // agent execution autonomous without guessing source edits.
                if requiresMutation,
                   !hasMutationCheckpoint,
                   !usedAutonomousInspectionFallback,
                   allToolResults.isEmpty,
                   let fallback = autonomousInspectionAction() {
                    receivedToolCalls = [fallback]
                    usedAutonomousInspectionFallback = true
                    logActivity(.info, "Harness fallback: inspecting workspace before implementation")

                // After a mutation, verification is the agent's job. A model
                // promise to rebuild must trigger a real native build, not a
                // "needs attention" message or a button for the user.
                } else if requiresMutation,
                          hasMutationCheckpoint,
                          !hasVerificationCheckpoint,
                          !usedPostMutationVerificationFallback,
                          let fallback = projectAction(.build) {
                    receivedToolCalls = [fallback]
                    usedPostMutationVerificationFallback = true
                    logActivity(.info, "Harness fallback: verifying changed source with native build")

                // Some providers occasionally return a prose plan for a very
                // short operational request (for example, "Build สิ") instead
                // of issuing the native tool call.  Do not silently pretend
                // that work happened: for an unambiguous project action, use
                // the real local runner as a deterministic fallback.
                } else if requiresNativeExecution,
                          requiresRuntimeLaunch,
                          !hasRuntimeLaunch(in: allToolResults),
                          !usedRuntimeLaunchFallback,
                          let fallback = runtimeLaunchAction() {
                    receivedToolCalls = [fallback]
                    usedRuntimeLaunchFallback = true
                    logActivity(.info, "Harness fallback: launching the built app on the selected runtime")

                } else if (requiresNativeExecution || containsNativeWorkCommitment(streamedText) || containsNativeWorkCommitment(finalText)),
                   !usedDeterministicActionFallback,
                   allToolResults.isEmpty,
                   let fallback = inferredWorkspaceAction(for: content.isEmpty ? (streamedText + " " + finalText) : (content + " " + streamedText + " " + finalText)) {
                    receivedToolCalls = [fallback]
                    usedDeterministicActionFallback = true
                    logActivity(.info, "Harness fallback: executing \(fallback.name) for the requested project action")
                } else {
                    let nativeWorkWasPromised = requiresNativeExecution || containsNativeWorkCommitment(streamedText) || containsNativeWorkCommitment(finalText)
                    let nativeWorkWasExecuted = hasNativeExecution(in: allToolResults) || DevServerRegistry.shared.hasRunningServer()
                    let hasSuccessfulTools = allToolResults.contains(where: \.success)
                    let isStaticVerifiedMutation = !filesModified.isEmpty && !nativeWorkWasPromised && projectAction(.build) == nil && !containsUnfinishedActionIntention(streamedText)
                    let verificationPassed = (!requiresWorkspaceEvidence && !streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        || hasDeterministicVerification(
                            in: allToolResults,
                            requiresNativeExecution: nativeWorkWasPromised,
                            requiresRuntimeLaunch: requiresRuntimeLaunch,
                            requiresMutation: requiresMutation
                        )
                        || isStaticVerifiedMutation
                        || (hasSuccessfulTools && !requiresMutation && !containsUnfinishedActionIntention(streamedText))

                    if !isChatMode, verificationPassed {
                        if !filesModified.isEmpty && !usedPreFinishHookCheck {
                            usedPreFinishHookCheck = true
                            let preFinish = await MultiPlatformRulesEngine.shared.executeHooks(
                                stage: .preFinish,
                                filePath: filesModified.last,
                                workspaceRoot: currentWorkspace ?? ""
                            )
                            if !preFinish.allowed {
                                logActivity(.error, "pre_finish hook blocked completion; prompting agent to fix")
                                history.append((role: "assistant", content: streamedText))
                                history.append((role: "user", content: "\(preFinish.feedback)\n\nPlease fix the issue reported by the `pre_finish` hook before concluding your turn."))
                                currentToolExecution = "Fixing pre_finish hook failure..."
                                agentPhase = .validating
                                continue
                            }
                        }
                        _ = kernelOnline ? await agentKernel.observe(
                            runID: kernelRunID,
                            kind: "verification",
                            success: true,
                            output: "Deterministic tool evidence passed",
                            madeProgress: true
                        ) : nil
                        kernelVerified = true
                        currentToolExecution = nil
                        logActivity(.success, "Objective verification passed")
                        break
                    }

                    let kernelResponse = kernelOnline ? await agentKernel.observe(
                        runID: kernelRunID,
                        kind: "model_no_tool",
                        success: nil,
                        output: streamedText,
                        madeProgress: false
                    ) : nil

                    if verificationPassed || kernelResponse?.directive.action == "complete" {
                        kernelVerified = true
                        currentToolExecution = nil
                        logActivity(.success, "Objective completed successfully")
                        break
                    }

                    // Circuit Breaker: Detect repetitive loops across recent assistant responses
                    if isRepetitiveOutput(streamedText, previousOutputs: recentAssistantOutputs) {
                        logActivity(.info, "Repetition loop detected in model output: breaking out of autonomous monologue cycle.")
                        currentToolExecution = nil
                        break
                    }
                    recentAssistantOutputs.append(streamedText)

                    // If the model monologued intentions without calling tools, OR native work was promised but never executed:
                    // 1) First attempt to autonomously execute the promised action (e.g. build/run)
                    // 2) If not an inferred workspace action, auto-prompt the model to call the tool immediately
                    let hasUnfinishedIntent = containsUnfinishedActionIntention(streamedText)
                    if !isChatMode,
                       (hasUnfinishedIntent || (requiresWorkspaceEvidence && !verificationPassed) || (nativeWorkWasPromised && !nativeWorkWasExecuted)) {
                        if !usedDeterministicActionFallback,
                           allToolResults.isEmpty,
                           let fallback = inferredWorkspaceAction(for: streamedText + " " + finalText) {
                            receivedToolCalls = [fallback]
                            usedDeterministicActionFallback = true
                            logActivity(.info, "Harness follow-through: automatically executing \(fallback.name) from model intention")
                            // Fall through to tool execution loop
                        } else if followThroughNagCount < 3,
                                  kernelRecoveryCount < 4,
                                  (allToolResults.isEmpty || (requiresMutation && filesModified.isEmpty)),
                                  kernelResponse?.directive.action != "blocked" {
                            followThroughNagCount += 1
                            kernelRecoveryCount += 1
                            usedFollowThroughRecovery = true
                            logActivity(.info, "Harness follow-through: model stopped before completing required action (attempt \(followThroughNagCount)/3). Auto-prompting immediate tool execution...")
                            if kernelResponse?.directive.action == "retry",
                               let delay = kernelResponse?.directive.retryAfterMs {
                                currentToolExecution = "Waiting to retry from the durable checkpoint..."
                                agentPhase = .thinking
                                try? await Task.sleep(nanoseconds: delay * 1_000_000)
                            }
                            history.append((role: "assistant", content: streamedText))
                            let followUpPrompt: String
                            if requiresMutation && filesModified.isEmpty {
                                followUpPrompt = """
                                CRITICAL: You have inspected the workspace files, but `filesModified` is STILL EMPTY (zero files have been edited on disk!).
                                Do NOT stop or claim the task is complete before modifying the actual files.
                                Immediately call `replace_in_file`, `patch_file`, or `file_write` RIGHT NOW to implement the requested changes in the target file(s).
                                """
                            } else if hasUnfinishedIntent {
                                let snippet = String(streamedText.suffix(180)).trimmingCharacters(in: .whitespacesAndNewlines)
                                followUpPrompt = """
                                You stated what you intend to do ("...\(snippet)..."), but you did not call any tools.
                                In MicroCode Agent, you must EXECUTE actions using tools, not just describe them in text.
                                Immediately call the appropriate tool (e.g. `file_read`, `file_write`, `patch_file`, `shell`, etc.) RIGHT NOW to perform the work. Do not stop until the objective is finished.
                                """
                            } else {
                                followUpPrompt = kernelResponse?.directive.suggestedPrompt ?? """
                                Verification failed: the objective has no deterministic completion evidence. Execute the missing action now, then run the relevant build/test/diagnostic. Do not answer with another plan or progress-only message.
                                """
                            }
                            history.append((role: "user", content: followUpPrompt))
                            currentToolExecution = "Prompting tool execution follow-through..."
                            agentPhase = .thinking
                            continue
                        }
                    }

                    if nativeWorkWasPromised && !nativeWorkWasExecuted && allToolResults.isEmpty {
                        let detail = "Requested native work was not executed. The agent did not run a build, test, run, or terminal command."
                        terminationNotice = detail
                        logActivity(.error, detail)
                    }
                    currentToolExecution = nil
                    break
                }
            }
            
            // Execute ALL tool calls in this batch
            var batchResults: [AIStructuredToolResult] = []
            for toolCall in receivedToolCalls {
                if let tier = ToolScope.toolTierMap[toolCall.name], !currentToolScope.contains(tier) {
                    currentToolScope.insert(tier)
                    stickyActiveTools = allToolSchemas.filter { (tool: [String: Any]) -> Bool in
                        guard let name = tool["name"] as? String else { return true }
                        if name.hasPrefix("mcp__") && !name.hasPrefix("mcp__local__") {
                            return stickyEagerExternalMCP.contains(name)
                        }
                        guard let t = ToolScope.toolTierMap[name] else { return true }
                        return currentToolScope.contains(t)
                    }
                    logActivity(.info, "Tool scope expanded to include \(tier) tier")
                }
            }
            var kernelFollowUp: String?
            let readOnlyTools: Set<String> = ["file_read", "multi_file_read", "grep_search", "find_symbol", "list_directory_tree", "file_search", "get_diagnostics", "git_status", "git_diff", "git_log", "lsp_hover", "lsp_definition", "lsp_completions", "lsp_diagnostics", "lsp_status", "inspect_image", "extract_pdf"]
            let allReadOnly = receivedToolCalls.allSatisfy { readOnlyTools.contains($0.name) }
            
            if allReadOnly && receivedToolCalls.count > 1 {
                currentToolExecution = "Executing \(receivedToolCalls.count) read-only operations concurrently..."
                agentPhase = .executing("concurrent_tools")
                
                let concurrentResults = await withTaskGroup(of: (AIToolCall, String, Bool).self) { group in
                    for toolCall in receivedToolCalls {
                        let signature = self.toolCallSignature(toolCall)
                        if let cached = completedToolCalls[signature] {
                            group.addTask { return (toolCall, cached.output, cached.success) }
                            continue
                        }
                        
                        group.addTask {
                            await FlightRecorder.shared.recordToolCall(
                                toolName: toolCall.name,
                                arguments: self.truncateArgs(toolCall.arguments),
                                workspace: self.currentWorkspace ?? ""
                            )
                            do {
                                var output = try await self.toolBox.execute(toolCall.name, params: toolCall.arguments)
                                output = await MainActor.run { self.tokenOptimizer.compressToolOutput(output, toolName: toolCall.name, budget: 16_000) }
                                return (toolCall, output, true)
                            } catch {
                                return (toolCall, error.localizedDescription, false)
                            }
                        }
                    }
                    var collected: [(AIToolCall, String, Bool)] = []
                    for await res in group { collected.append(res) }
                    return collected
                }
                
                let orderedResults = receivedToolCalls.compactMap { call in 
                    concurrentResults.first(where: { $0.0.id == call.id })
                }
                
                for (toolCall, output, success) in orderedResults {
                    if isCancelled || Task.isCancelled { break }
                    let signature = toolCallSignature(toolCall)
                    let wasCached = completedToolCalls[signature] != nil
                    
                    if !wasCached {
                        if success {
                            if shouldCacheToolResult(toolCall.name) {
                                completedToolCalls[signature] = (output, true)
                            }
                            logActivity(.success, "\(toolCall.name) ✓", detail: truncateArgs(toolCall.arguments), output: String(output.prefix(3000)))
                            
                            if kernelOnline {
                                let kernelResponse = await agentKernel.observe(
                                    runID: kernelRunID,
                                    kind: "tool_result",
                                    toolName: toolCall.name,
                                    arguments: toolCall.arguments,
                                    success: true,
                                    output: output,
                                    madeProgress: toolMadeProgress(toolCall.name)
                                )
                                if let directive = kernelResponse?.directive, directive.action == "replan" || directive.action == "retry" {
                                    kernelFollowUp = directive.suggestedPrompt ?? directive.reason
                                }
                            }
                        } else {
                            logActivity(.error, "\(toolCall.name) failed: \(output)", detail: truncateArgs(toolCall.arguments), output: output)
                            
                            if kernelOnline {
                                let kernelResponse = await agentKernel.observe(
                                    runID: kernelRunID,
                                    kind: "tool_result",
                                    toolName: toolCall.name,
                                    arguments: toolCall.arguments,
                                    success: false,
                                    error: output,
                                    transient: isTransientAgentError(output)
                                )
                                if let directive = kernelResponse?.directive, directive.action == "replan" || directive.action == "retry" || directive.action == "blocked" {
                                    kernelFollowUp = directive.suggestedPrompt ?? directive.reason
                                }
                            }
                        }
                    } else {
                        logActivity(.info, "\(toolCall.name) reused cached result")
                    }
                    
                    allToolResults.append(ToolResultModel(
                        toolCallId: toolCall.id,
                        toolName: toolCall.name,
                        toolParams: toolCall.arguments,
                        success: success,
                        output: success ? output : "",
                        error: success ? nil : output
                    ))
                    batchResults.append(AIStructuredToolResult(
                        toolCallId: toolCall.id,
                        name: toolCall.name,
                        output: output,
                        success: success
                    ))
                }
                currentToolExecution = nil
                updateStreamingMessage(finalText.isEmpty ? lastPreToolText : finalText, toolResults: allToolResults)
            } else {
                for toolCall in receivedToolCalls {
                    if isCancelled || Task.isCancelled { break }
                    let signature = toolCallSignature(toolCall)
                    if let completed = completedToolCalls[signature] {
                        allToolResults.append(ToolResultModel(
                            toolCallId: toolCall.id,
                            toolName: toolCall.name,
                            toolParams: toolCall.arguments,
                            success: completed.success,
                            output: completed.output,
                            error: completed.success ? nil : completed.output
                        ))
                        batchResults.append(AIStructuredToolResult(
                            toolCallId: toolCall.id,
                            name: toolCall.name,
                            output: completed.output,
                            success: completed.success
                        ))
                        logActivity(.info, "\(toolCall.name) reused cached result")
                        updateStreamingMessage(finalText.isEmpty ? lastPreToolText : finalText, toolResults: allToolResults)
                        continue
                    }
                    currentToolExecution = humanFriendlyToolTitle(toolCall.name, args: toolCall.arguments)
                    agentPhase = .executing(toolCall.name)
                    logActivity(.tool, "\(toolCall.name)", detail: truncateArgs(toolCall.arguments))
                    
                    // P2: Record tool call in Flight Recorder audit trail
                    FlightRecorder.shared.recordToolCall(
                        toolName: toolCall.name,
                        arguments: truncateArgs(toolCall.arguments),
                        workspace: currentWorkspace ?? ""
                    )
                    
                    // Capture old content for diff BEFORE execution
                    let targetFilePath = toolCall.arguments["path"] as? String
                    var oldContent: String? = nil
                    if (toolCall.name == "file_write" || toolCall.name == "replace_in_file" || toolCall.name == "patch_file"),
                       let path = targetFilePath {
                        oldContent = try? String(contentsOfFile: path, encoding: .utf8)
                    }

                    // Run pre_tool lifecycle hooks if configured
                    let preHook = await MultiPlatformRulesEngine.shared.executeHooks(
                        stage: .preTool,
                        toolName: toolCall.name,
                        filePath: targetFilePath,
                        workspaceRoot: currentWorkspace ?? ""
                    )
                    if !preHook.allowed {
                        logActivity(.error, "Blocked by pre_tool hook: \(toolCall.name)")
                        allToolResults.append(ToolResultModel(
                            toolCallId: toolCall.id,
                            toolName: toolCall.name,
                            toolParams: toolCall.arguments,
                            success: false,
                            output: "",
                            error: preHook.feedback
                        ))
                        batchResults.append(AIStructuredToolResult(
                            toolCallId: toolCall.id,
                            name: toolCall.name,
                            output: preHook.feedback,
                            success: false
                        ))
                        updateStreamingMessage(finalText.isEmpty ? lastPreToolText : finalText, toolResults: allToolResults)
                        currentToolExecution = nil
                        continue
                    }
                    
                    do {
                        var output = try await toolBox.execute(toolCall.name, params: toolCall.arguments)
                        if let path = targetFilePath {
                            recordWorkspaceFileSnapshot(path)
                        }

                        // Run post_tool lifecycle hooks (e.g. formatter / typecheck) if configured
                        let postHook = await MultiPlatformRulesEngine.shared.executeHooks(
                            stage: .postTool,
                            toolName: toolCall.name,
                            filePath: targetFilePath,
                            workspaceRoot: currentWorkspace ?? ""
                        )
                        if !postHook.feedback.isEmpty {
                            output += "\n\n\(postHook.feedback)"
                        }
                        
                        // Phase 3: LSP Deep Integration — Instant Compiler Diagnostics Feedback Loop
                        if toolCall.name == "file_write" || toolCall.name == "replace_in_file" || toolCall.name == "patch_file" {
                            if let path = toolCall.arguments["path"] as? String {
                                let lang = languageForFile(path)
                                if LSPManager.shared.isAvailable(for: lang) {
                                    let fileURL = URL(fileURLWithPath: path)
                                    let fileURI = fileURL.absoluteString
                                    if let newContent = try? String(contentsOfFile: path, encoding: .utf8) {
                                        await ensureDocumentOpen(path: path, language: lang)
                                        await LSPManager.shared.documentChanged(uri: fileURI, language: lang, content: newContent)
                                        // Brief wait for LSP server to analyze changes and generate diagnostics
                                        try? await Task.sleep(nanoseconds: 200_000_000)
                                        let errors = (LSPManager.shared.fileDiagnostics[fileURI] ?? []).filter { $0.severity == 1 }
                                        if !errors.isEmpty {
                                            let errorDetails = errors.prefix(5).map { "  ❌ Line \($0.range.start.line + 1): \($0.message)" }.joined(separator: "\n")
                                            output += "\n\n⚠️ [LSP Compiler Diagnostics Warning]: Compiler/syntax errors detected in \(fileURL.lastPathComponent) after this edit:\n\(errorDetails)\nPlease fix these compilation errors in your next step."
                                            logActivity(.info, "LSP: \(errors.count) compiler error(s) in \(fileURL.lastPathComponent)", detail: errorDetails)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Compress tool output to save tokens while preserving diagnostics and code context
                        output = tokenOptimizer.compressToolOutput(output, toolName: toolCall.name, budget: 16_000)
                        
                        allToolResults.append(ToolResultModel(
                            toolCallId: toolCall.id,
                            toolName: toolCall.name,
                            toolParams: toolCall.arguments,
                            success: true,
                            output: output,
                            error: nil
                        ))
                        updateStreamingMessage(finalText.isEmpty ? lastPreToolText : finalText, toolResults: allToolResults)
                        
                        batchResults.append(AIStructuredToolResult(
                            toolCallId: toolCall.id,
                            name: toolCall.name,
                            output: output,
                            success: true
                        ))
                        // Only memoize read-only inspections.  A build/test/run
                        // result is invalid as soon as source changes, and caching
                        // a failed build was causing the agent to report stale
                        // output instead of rebuilding after its fix.
                        if shouldCacheToolResult(toolCall.name) {
                            completedToolCalls[signature] = (output, true)
                        }
                        logActivity(.success, "\(toolCall.name) ✓", detail: truncateArgs(toolCall.arguments), output: String(output.prefix(3000)))
                        if kernelOnline {
                            let kernelResponse = await agentKernel.observe(
                                runID: kernelRunID,
                                kind: "tool_result",
                                toolName: toolCall.name,
                                arguments: toolCall.arguments,
                                success: true,
                                output: output,
                                madeProgress: toolMadeProgress(toolCall.name)
                            )
                            if let directive = kernelResponse?.directive,
                               directive.action == "replan" || directive.action == "retry" {
                                kernelFollowUp = directive.suggestedPrompt ?? directive.reason
                            }
                        }
                        
                        // Track file changes with diff
                        if toolCallMutatesWorkspace(toolCall) {
                            // Source changes invalidate every prior inspection and
                            // verification result.  In particular, a subsequent
                            // build must execute in Terminal again, never replay a
                            // previous failure from this run.
                            completedToolCalls.removeAll()
                        }

                        let normalizedToolName = normalizeToolName(toolCall.name)
                        if normalizedToolName == "create_plan" || normalizedToolName == "agent_plan" {
                            if output.contains("APPROVED") || output.contains("Plan accepted") || output.contains("Durable plan accepted") {
                                requiresMutation = true
                                requiresWorkspaceEvidence = true
                                iteration = 0
                                logActivity(.info, "Implementation plan approved — resetting step counter for execution phase")
                            } else if output.contains("REJECTED") || output.contains("rejected") {
                                requiresMutation = false
                                requiresWorkspaceEvidence = false
                            }
                        }

                        if ["file_write", "replace_in_file", "multi_replace_in_file", "patch_file", "apply_patch"].contains(normalizedToolName) {
                            let resolvedPath = (toolCall.arguments["path"] as? String)
                                ?? (toolCall.arguments["file_path"] as? String)
                            if let path = resolvedPath {
                                if !filesModified.contains(path) {
                                    filesModified.append(path)
                                }
                                Task { @MainActor in
                                    ImplementationPlanManager.shared.advanceNextPendingStep()
                                }
                                
                                // P2: Record file change in Flight Recorder
                                let action: AuditAction = oldContent == nil ? .fileCreate : .fileModify
                                FlightRecorder.shared.recordFileChange(
                                    action: action,
                                    filePath: path,
                                    description: "\(toolCall.name): \(toolCall.arguments["description"] as? String ?? "modified")",
                                    workspace: currentWorkspace ?? ""
                                )
                                
                                // Read new content for diff
                                let newContent = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                                let old = oldContent ?? ""
                                
                                // Compute additions/deletions
                                let oldLines = old.components(separatedBy: "\n")
                                let newLines = newContent.components(separatedBy: "\n")
                                let additions = max(0, newLines.count - oldLines.count)
                                let deletions = max(0, oldLines.count - newLines.count)
                                
                                // Create diff session for inline review
                                let diffResult = diffEngine.computeDiff(old: old, new: newContent)
                                
                                logActivity(.fileChange, "Modified: \(URL(fileURLWithPath: path).lastPathComponent) (+\(additions) -\(deletions))", detail: path, output: diffResult.hunks.isEmpty ? nil : "Hunks modified: \(diffResult.hunks.count)")
                                
                                allChanges.append(PendingChangeModel(
                                    id: UUID().uuidString,
                                    filePath: path,
                                    description: "Modified by \(toolCall.name)",
                                    additions: additions, deletions: deletions,
                                    oldContent: old, newContent: newContent,
                                    status: diffResult.hunks.isEmpty ? .accepted : .pending
                                ))
                                
                                // Hot-reload task/agent context if AI updated them autonomously
                                if path.hasSuffix("task.md") || path.hasSuffix("agent.md") {
                                    Task { @MainActor in self.reloadAgentWorkspaceFiles() }
                                }
                            } else {
                                filesModified.append(currentWorkspace ?? "workspace")
                                Task { @MainActor in
                                    ImplementationPlanManager.shared.advanceNextPendingStep()
                                }
                            }
                        }
                        
                    } catch {
                        allToolResults.append(ToolResultModel(
                            toolCallId: toolCall.id,
                            toolName: toolCall.name,
                            toolParams: toolCall.arguments,
                            success: false,
                            output: "",
                            error: error.localizedDescription
                        ))
                        updateStreamingMessage(finalText.isEmpty ? lastPreToolText : finalText, toolResults: allToolResults)
                        
                        batchResults.append(AIStructuredToolResult(
                            toolCallId: toolCall.id,
                            name: toolCall.name,
                            output: error.localizedDescription,
                            success: false
                        ))
                        // Failed commands must remain retryable after a repair or
                        // a transient environment recovery.  Do not cache them.
                        logActivity(.error, "\(toolCall.name) failed: \(error.localizedDescription)", detail: truncateArgs(toolCall.arguments), output: error.localizedDescription)
                        if kernelOnline {
                            let kernelResponse = await agentKernel.observe(
                                runID: kernelRunID,
                                kind: "tool_result",
                                toolName: toolCall.name,
                                arguments: toolCall.arguments,
                                success: false,
                                error: error.localizedDescription,
                                transient: isTransientAgentError(error.localizedDescription)
                            )
                            if let directive = kernelResponse?.directive,
                               directive.action == "replan" || directive.action == "retry" || directive.action == "blocked" {
                                kernelFollowUp = directive.suggestedPrompt ?? directive.reason
                            }
                        }
                    }
                    
                    currentToolExecution = nil
                }
            }
            
            // Add structured assistant turn (preserving tool call IDs and Gemini thoughtSignature)
            let assistantHistoryRecord = AIStructuredTurnCodec.encodeAssistantTurn(
                text: streamedText,
                toolCalls: receivedToolCalls
            )
            history.append((role: "assistant", content: assistantHistoryRecord))
            
            var consensusNote: String? = nil
            if AppState.shared?.consensusEnabled == true && allChanges.count >= (AppState.shared?.consensusThreshold ?? 2) {
                let sandboxChanges = allChanges.map { change in
                    SandboxFileChange(
                        filePath: change.filePath,
                        changeType: change.oldContent.isEmpty ? .create : .modify,
                        oldContent: change.oldContent,
                        newContent: change.newContent
                    )
                }
                let auditResult = await ConsensusOrchestrator.shared.evaluate(
                    changes: sandboxChanges,
                    originalRequest: content,
                    workspaceRoot: currentWorkspace ?? "",
                    provider: provider,
                    model: model,
                    apiKey: apiKey
                )
                if auditResult.verdict == .rejected {
                    consensusNote = "Consensus Audit REJECTED: \(auditResult.summary)"
                }
            }
            
            for result in batchResults where result.success {
                let baseName = normalizeToolName(result.name)
                if ["file_write", "replace_in_file", "multi_replace_in_file", "patch_file", "apply_patch"].contains(baseName) {
                    pendingVerificationAfterEdit = true
                } else if ["shell", "get_diagnostics", "lsp_diagnostics"].contains(baseName) && pendingVerificationAfterEdit {
                    pendingVerificationAfterEdit = false
                    verificationPassCount += 1
                }
            }

            let dynamicInstruction: String
            if !filesModified.isEmpty && (verificationPassCount >= 2 || iteration >= 28) {
                dynamicInstruction = "You have already completed implementation and verification (\(iteration) steps executed). Do NOT run any more shell, build, check, or preview_control commands. Immediately write a concise final response summarizing the changes using clickable file links. NEVER paste or dump full file source code into the chat."
            } else if !requiresMutation && iteration >= 14 {
                dynamicInstruction = "You have completed \(iteration) inspection steps. Immediately write your final response summarizing your findings."
            } else if pendingVerificationAfterEdit {
                dynamicInstruction = "Files have been modified. If more files still need to be created or edited, continue calling `file_write` or `replace_in_file` (NEVER dump file source code into chat). Otherwise run at most ONE verification check (`get_diagnostics` or build/check command) or conclude with a concise summary."
            } else if !filesModified.isEmpty {
                dynamicInstruction = "Verification has already been performed for your file edits. If all planned files are written to disk, conclude your turn now with a concise, structured summary of the changes (NEVER dump source code in chat)."
            } else if requiresMutation && iteration >= 3 {
                dynamicInstruction = "CRITICAL: You have already performed \(iteration) read/inspection steps, and `filesModified` is STILL EMPTY (zero files modified!). Stop reading files repeatedly. Immediately call `replace_in_file`, `patch_file`, or `file_write` RIGHT NOW to implement the requested changes in the target file(s)."
            } else if iteration >= 5 {
                dynamicInstruction = "You have completed \(iteration) inspection steps. You now have sufficient context. Immediately proceed to implement the requested modifications or deliver your final solution. Avoid repetitive exploratory file reading."
            } else {
                dynamicInstruction = "Continue executing the user's request. If the objective requires running commands or modifying code, immediately call the appropriate tool. Batch independent read/search operations together for efficiency."
            }
            
            var directiveLines: [String] = []
            if let consensusNote = consensusNote {
                directiveLines.append(consensusNote)
            }
            directiveLines.append("Kernel directive: \(kernelFollowUp ?? "Continue only with the next necessary action. Do not repeat completed calls.")")
            directiveLines.append("Instruction: \(dynamicInstruction)")
            
            let structuredResultsRecord = AIStructuredTurnCodec.encodeToolResultsTurn(
                results: batchResults,
                directive: directiveLines.joined(separator: "\n")
            )
            history.append((role: "user", content: structuredResultsRecord))
            
            if batchResults.contains(where: { result in
                result.success && toolMadeProgress(result.name)
            }) {
                // A real checkpoint means a later recovery is a fresh attempt,
                // not another strike against a previous model response.
                kernelRecoveryCount = 0
            }
            saveCurrentChatMessages()
            agentPhase = filesModified.isEmpty ? .thinking : .validating
        }

        // If this turn was stopped or superseded by a newer user turn, stopGeneration()
        // has already promoted the partial streaming message in-place. Exit without mutating state.
        guard self.executionID == runExecutionID else {
            return
        }

        currentToolExecution = nil

        if let limit = toolIterationLimit, iteration >= limit, terminationNotice == nil {
            let detail = "Reached maximum tool iteration safety limit (\(limit) steps). Pausing turn to protect API budget."
            terminationNotice = detail
            if !finalText.contains(detail) {
                finalText += "\n\n⚠️ \(detail)"
            }
            logActivity(.info, detail)
        }

        if isCancelled {
            let detail = "Generation was stopped by the user."
            terminationNotice = detail
            if !finalText.contains(detail) {
                finalText += "\n\n⏹ \(detail)"
            }
            logActivity(.info, detail)
        }

        if terminationNotice == nil, !isChatMode, !kernelVerified, kernelOnline {
            let response = await agentKernel.observe(
                runID: kernelRunID,
                kind: "final_candidate",
                success: nil,
                output: "The model ended its turn",
                madeProgress: false
            )
            let hasSuccessfulTools = allToolResults.contains(where: \.success)
            let verified = (!requiresWorkspaceEvidence && !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                || hasDeterministicVerification(
                    in: allToolResults,
                    requiresNativeExecution: requiresNativeExecution,
                    requiresRuntimeLaunch: requiresRuntimeLaunch,
                    requiresMutation: requiresMutation
                )
                || DevServerRegistry.shared.hasRunningServer()
                || (hasSuccessfulTools && !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if verified || response?.directive.action == "complete" {
                kernelVerified = true
            } else if allToolResults.isEmpty {
                let detail = "The agent stopped without verified tool evidence for the requested work."
                terminationNotice = detail
                if !finalText.contains(detail) { finalText += "\n\n⚠️ \(detail)" }
            }
        }
        
        if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !lastPreToolText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalText = lastPreToolText
        }
        if let notice = terminationNotice, !finalText.contains(notice) {
            finalText += "\n\n⚠️ \(notice)"
        }
        if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let notice = terminationNotice, !notice.isEmpty {
                finalText = "⚠️ \(notice)"
            }
        }

        // Finalize the assistant message
        let assistantMessage = AgentMessageModel(
            id: UUID().uuidString, role: .assistant, content: finalText,
            toolResults: allToolResults, pendingChanges: allChanges, timestamp: Date()
        )
        
        // Replace streaming placeholder with final on MainActor (and guarantee userMessage is never lost or duplicated)
        await MainActor.run {
            messages.removeAll { $0.id == "streaming" }
            if !messages.contains(where: { $0.id == userMessage.id }) {
                messages.append(userMessage)
            }
            messages.append(assistantMessage)
            pendingChanges.append(contentsOf: allChanges)
            if let activeId = activeChatId {
                transcriptStore.deleteMessages(ids: ["streaming"], chatID: activeId, scope: activeScope)
            }
        }
        
        // Verification is an Agent responsibility.  Do not turn an internal
        // build/run step into a "Run Project?" request for the user after the
        // agent has changed files.
        suggestedAction = nil
        
        // Update token stats
        let inputTokens = tokenOptimizer.estimateTokens(optimizedSystemPrompt) + history.reduce(0) { $0 + tokenOptimizer.estimateTokens($1.content) }
        let outputTokens = tokenOptimizer.estimateTokens(finalText)
        tokenOptimizer.recordUsage(provider: detectedProvider.rawValue, model: resolvedModel, inputTokens: inputTokens, outputTokens: outputTokens)
        
        if terminationNotice == nil {
            if !filesModified.isEmpty {
                await MainActor.run {
                    ImplementationPlanManager.shared.markAllStepsCompleted()
                }
            }
            logActivity(.done, "Completed (\(iteration) iterations, \(allToolResults.count) tools, ~\(inputTokens + outputTokens) tokens)")
            agentPhase = .done
        } else {
            // Keep an explicit terminal outcome above the composer instead of
            // collapsing a timeout/stop/iteration cap into a misleading
            // normal "Done" state.
            agentPhase = .idle
        }
        
        // Store memory (strictly bounded to the active workspace)
        if let chatId = activeChatId {
            memoryService.storeMemory(content: finalText, chatId: chatId, role: "assistant", projectPath: toolBox.workspaceRoot)
        }
        if activeKernelRunID == kernelRunID, terminationNotice == nil {
            activeKernelRunID = nil
            UserDefaults.standard.removeObject(forKey: durableRunStorageKey)
        }
        
        saveChats()
    }

    private func isContinuationRequest(_ content: String) -> Bool {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let continuationKeywords = [
            "ต่อ", "ทำต่อ", "ต่อไป", "ไงต่อ", "แล้วไงต่อ", "ไปต่อ", "ทำไงต่อ", "ต่อเลย", "ลุยต่อ",
            "ไหน", "ไหนล่ะ", "ไหนครับ", "ไหนอะ", "ยังไม่เปลี่ยน", "ยังไม่แก้", "ไม่เห็นเปลี่ยน", "ไม่เห็นมี",
            "ทำเลย", "แก้เลย", "ลุยเลย", "เอาเลย", "จัดเลย", "เริ่มเลย", "ทำสิ", "แก้สิ", "เปลี่ยนเลย", "เปลี่ยนสิ",
            "continue", "resume", "keep going", "go on", "next", "proceed", "keep working", "finish it", "finish",
            // Operational follow-up nudges
            "run", "run it", "run it now", "run สิ", "run เลย", "run ต่อ", "run main.m", "run app",
            "รัน", "รันสิ", "รันเลย", "รันต่อ", "รันที", "ลองรัน", "กดรัน",
            "build", "build it", "build สิ", "build เลย", "build ต่อ",
            "บิลด์", "บิวด์", "คอมไพล์",
            "test", "test it", "test สิ", "ทดสอบ", "ลองทดสอบ"
        ]
        if continuationKeywords.contains(where: { normalized == $0 || normalized.hasPrefix($0) }) {
            return true
        }
        // Handle typos like "9ต่อ" (leading digits or punctuation)
        let cleaned = normalized.trimmingCharacters(in: CharacterSet.decimalDigits.union(.punctuationCharacters))
        if !cleaned.isEmpty && continuationKeywords.contains(where: { cleaned == $0 || cleaned.hasPrefix($0) }) {
            return true
        }
        return false
    }

    private func containsCompletionIndication(_ text: String) -> Bool {
        let lower = text.lowercased()
        let completionPhrases = [
            "เรียบร้อยแล้ว", "เรียบร้อยครับ", "เรียบร้อยค่ะ", "เสร็จสิ้น", "สำเร็จแล้ว",
            "พร้อมใช้งาน", "กำลังรันปกติ", "กำลังทำงานปกติ", "กำลังรันอยู่ที่", "รันอยู่ที่",
            "เปิดใช้งานได้ที่", "สามารถเข้าชมได้ที่", "คลิกเปิด", "เสร็จเรียบร้อย", "ทำเสร็จแล้ว",
            "already running", "is running at", "running at http", "is complete", "has completed",
            "successfully built", "successfully started", "all set", "ready for use", "ready at",
            "สรุปการทำงาน", "ผลการทดสอบผ่าน", "เสร็จสมบูรณ์"
        ]
        return completionPhrases.contains { lower.contains($0) }
    }

    private func containsUnfinishedActionIntention(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("```") {
            return false
        }
        if containsCompletionIndication(trimmed) {
            return false
        }
        let lower = trimmed.lowercased()
        let tail = String(lower.suffix(350))
        let actionPhrases = [
            "let me read", "let me check", "let me inspect", "let me get", "let me look",
            "let me find", "let me search", "let me write", "let me create", "let me update",
            "let me delete", "let me run", "let me build", "let me execute", "let me probe",
            "let me compile", "let me test",
            "i'll read", "i will read", "i'll check", "i will check", "i'll inspect",
            "i'll write", "i will write", "i'll create", "i will create", "i'll run", "i will run",
            "i'll execute", "i will execute", "i'll build", "i will build", "i'll test", "i will test",
            "now i'll", "now i will",
            "i need to read", "i need to check", "i need to inspect", "i need to write",
            "i need to get", "i need to find", "i need to run", "i need to build",
            "writing the", "reading the", "executing the", "inspecting the", "building the",
            "then write", "then build", "then remove", "next step", "next, i",
            "consolidating", "consolidate",
            "จะเริ่ม", "กำลังอ่าน", "กำลังเขียน", "ขอดึง", "ต่อไปจะ", "จะทำการ", "จะรัน", "จะ build",
            "ขอลอง build", "ขอลองรัน", "มา build กัน", "ทำการ build"
        ]
        if trimmed.count <= 280 {
            return actionPhrases.contains { lower.contains($0) }
        } else {
            return actionPhrases.contains { tail.contains($0) }
        }
    }

    /// Circuit breaker: detects if the model has entered an echo-chamber / repetition loop
    private func isRepetitiveOutput(_ text: String, previousOutputs: [String]) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return false }
        
        // 1. Direct exact or substring match with any previous response in current session
        for prev in previousOutputs {
            let prevClean = prev.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if prevClean == clean {
                return true
            }
            if clean.count > 20 && prevClean.count > 20 {
                if prevClean.contains(clean) || clean.contains(prevClean) {
                    return true
                }
            }
        }
        
        // 2. Sentence-level recurrence detection (if sentences repeat across multiple turns)
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: "\n.。"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count > 12 }
        
        var repeatedCount = 0
        for sentence in sentences {
            if previousOutputs.contains(where: { $0.lowercased().contains(sentence) }) {
                repeatedCount += 1
            }
        }
        if repeatedCount >= 2 || (sentences.count == 1 && repeatedCount >= 1) {
            return true
        }
        
        return false
    }
    
    // MARK: - Streaming Message Update & 30ms Coalesced Throttle Buffer
    
    private var lastStreamUpdateUptime: TimeInterval = 0
    private var pendingStreamFullText: String = ""
    private var streamThrottleTimer: Timer? = nil
    
    private func detectStreamingRepetition(_ fullText: String) -> Bool {
        // Inspect only the tail window so repetition detection stays O(1) instead of O(N^2) during long streams
        let tail = fullText.count > 900 ? String(fullText.suffix(900)) : fullText
        let lines = tail.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 8 }
        
        let count = lines.count
        guard count >= 3 else { return false }
        
        // 1. Triple repetition of identical line: A, A, A
        if lines[count - 1] == lines[count - 2] && lines[count - 2] == lines[count - 3] {
            return true
        }
        
        // 2. Alternating 2-line cycle: A, B, A, B, A, B
        if count >= 6 {
            let n = count
            if lines[n-1] == lines[n-3] && lines[n-3] == lines[n-5] &&
               lines[n-2] == lines[n-4] && lines[n-4] == lines[n-6] {
                return true
            }
        }
        
        return false
    }

    private func pushStreamingToken(_ token: String, currentFullText: inout String, toolResults: [ToolResultModel]) {
        currentFullText += token
        pendingStreamFullText = currentFullText
        
        let now = ProcessInfo.processInfo.systemUptime
        // 75ms throttle (~13.3fps): keeps streaming silky-smooth while preventing main-thread layout/scroll saturation
        if now - lastStreamUpdateUptime >= 0.075 {
            lastStreamUpdateUptime = now
            if detectStreamingRepetition(currentFullText) {
                logActivity(.info, "Real-time streaming repetition loop detected. Aborting token stream.")
                aiClient.cancelStream()
                return
            }
            updateStreamingMessage(currentFullText, toolResults: toolResults)
        } else if streamThrottleTimer == nil {
            streamThrottleTimer = Timer.scheduledTimer(withTimeInterval: 0.080, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.streamThrottleTimer = nil
                    self.lastStreamUpdateUptime = ProcessInfo.processInfo.systemUptime
                    if self.detectStreamingRepetition(self.pendingStreamFullText) {
                        self.logActivity(.info, "Real-time streaming repetition loop detected. Aborting token stream.")
                        self.aiClient.cancelStream()
                        return
                    }
                    self.updateStreamingMessage(self.pendingStreamFullText, toolResults: toolResults)
                }
            }
        }
    }
    
    private func flushStreamingToken(_ fullText: String, toolResults: [ToolResultModel]) {
        streamThrottleTimer?.invalidate()
        streamThrottleTimer = nil
        lastStreamUpdateUptime = ProcessInfo.processInfo.systemUptime
        updateStreamingMessage(fullText, toolResults: toolResults)
    }
    
    private func updateStreamingMessage(_ text: String, toolResults: [ToolResultModel]) {
        let sanitizedText = AIStructuredTurnCodec.stripToolCallArtifacts(text)
        let streamMsg = AgentMessageModel(
            id: "streaming", role: .assistant, content: sanitizedText,
            toolResults: toolResults, pendingChanges: [], timestamp: Date()
        )
        let block = { [weak self] in
            guard let self = self, !self.isCancelled else { return }
            if let lastIdx = self.messages.indices.last, self.messages[lastIdx].id == "streaming" {
                self.messages[lastIdx] = streamMsg
            } else {
                // Guarantee there are never two elements with id == "streaming"
                self.messages.removeAll { $0.id == "streaming" }
                self.messages.append(streamMsg)
            }
        }
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func toolCallSignature(_ call: AIToolCall) -> String {
        let data = try? JSONSerialization.data(withJSONObject: call.arguments, options: [.sortedKeys])
        return call.name + ":" + (data.flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: call.arguments))
    }

    private func requestRequiresNativeExecution(_ content: String) -> Bool {
        let lower = content.lowercased()
        let indicators = [
            "build", "compile", "run", "test", "execute", "terminal", "shell", "command", "deploy",
            "รัน", "สร้าง build", "คอมไพล์", "ทดสอบ", "เปิด terminal", "สั่งคำสั่ง"
        ]
        return indicators.contains { lower.contains($0) }
    }

    /// A successful compiler invocation is not proof that an app reached the
    /// requested simulator/device. Keep launch as a distinct completion gate,
    /// but never mistake "run swift build" / "run cargo test" / "run npm build"
    /// or a long architectural specification that happens to contain "deploy"
    /// for an imperative request to launch the application runtime or preview.
    private func requestRequiresRuntimeLaunch(_ content: String) -> Bool {
        var sanitized = content.lowercased()
        let nonLaunchRunPhrases = [
            "run swift build", "run swift test", "run swift package",
            "run cargo build", "run cargo check", "run cargo test", "run cargo clippy",
            "run npm build", "run npm run build", "run npm test", "run npm install",
            "run yarn build", "run pnpm build", "run bun build",
            "run xcodebuild", "run gradle", "run ./gradlew", "run ./build",
            "run pytest", "run go build", "run go test", "run git",
            "รัน swift build", "รัน cargo", "รัน build", "รัน test", "รันเทส", "รันคำสั่ง"
        ]
        for phrase in nonLaunchRunPhrases {
            sanitized = sanitized.replacingOccurrences(of: phrase, with: " ")
        }
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitLaunchIndicators = [
            "install and launch", "run app", "run the app", "run project", "run the project",
            "run preview", "open preview", "เปิด preview",
            "เปิดแอป", "ลง simulator", "ลง emulator", "ติดตั้งและรัน", "รันแอป", "รันโปรเจกต์"
        ]
        if explicitLaunchIndicators.contains(where: { sanitized.contains($0) }) {
            return true
        }
        if trimmed.count <= 160 {
            let shortIndicators = ["launch", "simulator", "emulator"]
            if shortIndicators.contains(where: { sanitized.contains($0) }) {
                return true
            }
        }
        let shortRunCommands: Set<String> = ["run", "run it", "run now", "รัน", "รันเลย", "รันสิ", "ลองรัน"]
        return shortRunCommands.contains(trimmed)
    }

    /// A file scan is valid evidence only for an explicitly read-only request.
    /// Any request that asks us to change the project must leave a mutation
    /// checkpoint and then verify it before it can appear as completed.
    private func requestRequiresMutation(_ content: String) -> Bool {
        AgentExecutionEvidence.taskRequiresMutation(content)
    }

    private func containsNativeWorkCommitment(_ text: String) -> Bool {
        if containsCompletionIndication(text) {
            return false
        }
        let lower = text.lowercased()
        let commitments = [
            "will build", "will run", "will test", "building", "running", "compile now",
            "build immediately", "run immediately", "build right away",
            "let me build", "let me run", "let me compile", "let me test", "let me execute",
            "i'll build", "i will build", "i'll run", "i will run", "i'll test", "i will test",
            "will execute with xcodebuild", "build with xcodebuild", "build with cargo", "build with gradle",
            "จะ build", "จะรัน", "กำลัง build", "เริ่ม build", "เริ่มรัน",
            "build ทันที", "รันทันที", "ตรวจโครงสร้าง + build", "ตรวจโครงสร้างและ build",
            "ขอลอง build", "ขอลองรัน", "จะทำการ build", "จะทำการรัน"
        ]
        return commitments.contains { lower.contains($0) }
    }

    private func hasNativeExecution(in results: [ToolResultModel]) -> Bool {
        results.contains { result in
            result.success && AgentExecutionEvidence.executes(name: result.toolName, arguments: result.toolParams ?? [:])
        }
    }

    private func hasRuntimeLaunch(in results: [ToolResultModel]) -> Bool {
        results.contains { result in
            result.success && AgentExecutionEvidence.launches(name: result.toolName, arguments: result.toolParams ?? [:])
        }
    }

    /// Completion is evidence-based. Read-only investigation may finish after
    /// successful tools; mutations require a compiler/test/diagnostic pass,
    /// and explicit build/run requests require a native execution result.
    private func hasDeterministicVerification(
        in results: [ToolResultModel],
        requiresNativeExecution: Bool,
        requiresRuntimeLaunch: Bool,
        requiresMutation: Bool
    ) -> Bool {
        var evidence = AgentExecutionEvidence()
        for result in results {
            evidence.record(name: result.toolName, arguments: result.toolParams ?? [:], success: result.success, output: result.output)
        }
        return evidence.satisfies(requiresMutation: requiresMutation || evidence.hasMutation, requiresExecution: requiresNativeExecution, requiresLaunch: requiresRuntimeLaunch)
    }

    private func normalizeToolName(_ name: String) -> String {
        name.replacingOccurrences(of: "mcp__local__", with: "")
            .replacingOccurrences(of: "mcp__", with: "")
    }

    private func toolMadeProgress(_ toolName: String) -> Bool {
        let base = normalizeToolName(toolName)
        return [
            "file_write", "replace_in_file", "multi_replace_in_file", "patch_file", "apply_patch", "rename_file", "create_directory",
            "shell", "device_runtime", "preview_control", "playground_run", "cell_run", "ardium_run",
            "invoke_subagent", "cell_create", "cell_update", "cell_delete", "computer_use_click",
            "computer_use_type", "computer_use_shortcut", "device_interact", "device_app_manage", "adb_execute"
        ].contains(base)
    }

    private func isTransientAgentError(_ message: String) -> Bool {
        let lower = message.lowercased()
        if [
            "unauthorized", "forbidden", "invalid api key", "http 401", "http 403", "permission denied",
            "payment required", "http 402", "insufficient balance", "insufficient funds", "wallet", "quota exceeded"
        ].contains(where: lower.contains) {
            return false
        }
        return [
            "timeout", "timed out", "connection reset", "connection lost", "network connection",
            "temporarily unavailable", "rate limit", "too many requests", "http 429",
            "http 500", "http 502", "http 503", "http 504", "eof", "stream"
        ].contains(where: lower.contains)
    }

    /// Provides a real native build/run/test action when a provider returns a
    /// prose promise instead of its required tool call.  This intentionally
    /// works for long requests too: the task may be detailed, but a clear
    /// build/run/test requirement is still unambiguous and must not be handed
    /// back to the user as a button.
    private func inferredWorkspaceAction(for content: String) -> AIToolCall? {
        guard let workspace = toolBox.workspaceRoot, !workspace.isEmpty else { return nil }
        if containsCompletionIndication(content) { return nil }
        let lower = content.lowercased()

        let action: ProjectAction?
        if lower.contains("test") || lower.contains("ทดสอบ") {
            action = .test
        } else if lower.contains("run") || lower.contains("รัน") || lower.contains("start") {
            action = .run
        } else if lower.contains("build") || lower.contains("compile") || lower.contains("คอมไพล์") || lower.contains("สร้าง build") || lower.contains("xcodebuild") {
            action = .build
        } else {
            action = nil
        }
        guard let action else { return nil }

        return projectAction(action)
    }

    private func runtimeLaunchAction() -> AIToolCall? {
        guard let workspace = toolBox.workspaceRoot, !workspace.isEmpty else { return nil }
        let projectURL = URL(fileURLWithPath: workspace, isDirectory: true)
        let projectType = ProjectManager.shared.detectProjectType(at: projectURL)
        
        // Check for Web indicators (HTML, Vite, Next, React, Vue, Svelte, package.json)
        let fm = FileManager.default
        let isWebProject = fm.fileExists(atPath: projectURL.appendingPathComponent("package.json").path) ||
            fm.fileExists(atPath: projectURL.appendingPathComponent("index.html").path) ||
            fm.fileExists(atPath: projectURL.appendingPathComponent("vite.config.ts").path) ||
            fm.fileExists(atPath: projectURL.appendingPathComponent("vite.config.js").path) ||
            fm.fileExists(atPath: projectURL.appendingPathComponent("next.config.js").path) ||
            fm.fileExists(atPath: projectURL.appendingPathComponent("next.config.mjs").path)
        
        let isMobileProject = projectType == .android || projectType == .flutter
        
        // 1. If mobile project AND has connected mobile devices, use device_runtime
        if isMobileProject && !DeviceRuntimeService.shared.devices.isEmpty {
            return AIToolCall(
                id: UUID().uuidString,
                name: "device_runtime",
                arguments: ["operation": "run", "workspace": workspace]
            )
        }
        
        // 2. For WebApp projects, prioritize projectAction (.run) which starts dev server or open web preview
        if DevServerRegistry.shared.hasRunningServer() {
            if isWebProject {
                return AIToolCall(
                    id: UUID().uuidString,
                    name: "preview_control",
                    arguments: ["action": "open", "mode": "web", "url": "http://localhost:5173"]
                )
            }
            return nil
        }
        if let runAction = projectAction(.run) {
            return runAction
        }
        if let buildAction = projectAction(.build) {
            return buildAction
        }
        
        if isWebProject {
            return AIToolCall(
                id: UUID().uuidString,
                name: "preview_control",
                arguments: ["action": "open", "mode": "web", "url": "http://localhost:5173"]
            )
        }
        
        return nil
    }

    /// Shell is both a build runner and an editing escape hatch. Treat only
    /// commands that write/replace/move project files as mutations; a command
    /// such as `perl -pi` must trigger a subsequent build, not satisfy it.
    private func toolCallMutatesWorkspace(_ toolCall: AIToolCall) -> Bool {
        AgentExecutionEvidence.mutates(name: toolCall.name, arguments: toolCall.arguments)
    }

    private func didMutateWorkspace(_ result: ToolResultModel) -> Bool {
        guard result.success else { return false }
        if result.toolName == "invoke_subagent" {
            return result.output.hasPrefix(AgentExecutionEvidence.verifiedSubagentPrefix)
        }
        return AgentExecutionEvidence.mutates(name: result.toolName, arguments: result.toolParams ?? [:])
    }

    private func isVerificationCheckpoint(_ result: ToolResultModel) -> Bool {
        guard result.success else { return false }
        return AgentExecutionEvidence.verifies(name: result.toolName, arguments: result.toolParams ?? [:])
    }

    private func shouldCacheToolResult(_ toolName: String) -> Bool {
        let base = normalizeToolName(toolName)
        return [
            "file_read", "multi_file_read", "grep_search", "list_directory_tree",
            "list_files", "file_search", "find_symbol", "inspect_image", "extract_pdf",
            "git_status", "git_diff", "preview_control"
        ].contains(base)
    }

    private func autonomousInspectionAction() -> AIToolCall? {
        guard let workspace = toolBox.workspaceRoot, !workspace.isEmpty else { return nil }
        return AIToolCall(
            id: UUID().uuidString,
            name: "list_directory_tree",
            arguments: ["path": workspace, "max_depth": 3]
        )
    }

    private func projectAction(_ action: ProjectAction) -> AIToolCall? {
        guard let workspace = toolBox.workspaceRoot, !workspace.isEmpty else { return nil }
        let projectURL = URL(fileURLWithPath: workspace, isDirectory: true)
        let projectType = ProjectManager.shared.detectProjectType(at: projectURL)
        guard let command = ProjectManager.shared.getBuildCommand(
            for: projectType,
            action: action,
            config: ProjectManager.shared.buildConfiguration,
            projectPath: workspace
        ) else { return nil }

        func shellQuote(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'") + "'"
        }
        let commandLine = ([command.executable] + command.arguments)
            .filter { !$0.isEmpty }
            .map(shellQuote)
            .joined(separator: " ")
        return AIToolCall(
            id: UUID().uuidString,
            name: "shell",
            arguments: ["command": commandLine, "cwd": workspace]
        )
    }

    /// Creates the MicroCode-managed part of agent.md/task.md before any model
    /// turn. Existing user-authored content is preserved; only managed files
    /// (or the old empty boilerplate) are replaced. This means the user can
    /// simply state the goal and the agent can read, plan, execute and verify
    /// it without requiring a separate "Run task" click.
    private func prepareAutonomousTaskArtifacts(objective: String, isContinuation: Bool) {
        guard let workspace = toolBox.workspaceRoot, !workspace.isEmpty else { return }
        let trimmedObjective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedObjective.isEmpty else { return }

        let directory = URL(fileURLWithPath: workspace, isDirectory: true)
            .appendingPathComponent(".microcode", isDirectory: true)
        let agentURL = directory.appendingPathComponent("agent.md")
        let taskURL = directory.appendingPathComponent("task.md")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let existingAgent = (try? String(contentsOf: agentURL, encoding: .utf8)) ?? ""
            let isLegacyBoilerplate = existingAgent.contains("This file provides project-level instructions to the MicroCode AI Agent.")
                || existingAgent.contains("<!-- Add your project's tech stack here -->")
                || (existingAgent.contains("<!-- microcode:managed-agent -->") && existingAgent.count < 600)
            if existingAgent.isEmpty || isLegacyBoilerplate {
                let agentMarkdown = Self.defaultAgentMarkdown()
                try AgentPrivacyGuard.safeWrite(content: agentMarkdown, to: agentURL)
                logActivity(.info, "Generated advanced .microcode/agent.md")
            }

            guard !isContinuation else {
                reloadAgentWorkspaceFiles()
                return
            }

            let existing = (try? String(contentsOf: taskURL, encoding: .utf8)) ?? ""
            let isManaged = existing.contains("<!-- microcode:managed-task -->")
                || existing.contains("<!-- Describe the current task here -->")
                || existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let nextContent: String
            if isManaged {
                nextContent = Self.defaultTaskMarkdown(objective: trimmedObjective)
            } else {
                nextContent = existing.trimmingCharacters(in: .whitespacesAndNewlines)
                    + "\n\n---\n\n"
                    + Self.defaultTaskMarkdown(objective: trimmedObjective)
            }
            try AgentPrivacyGuard.safeWrite(content: nextContent, to: taskURL)
            logActivity(.info, "Generated advanced autonomous task.md from the request")
            reloadAgentWorkspaceFiles()
        } catch {
            logActivity(.error, "Could not prepare agent task files: \(error.localizedDescription)")
        }
    }

    private func humanFriendlyToolTitle(_ name: String, args: [String: Any]) -> String {
        switch name {
        case "file_read", "multi_file_read":
            if let path = args["path"] as? String {
                return "Reading \(URL(fileURLWithPath: path).lastPathComponent)..."
            } else if let paths = args["paths"] as? [String], let first = paths.first {
                let extra = paths.count > 1 ? " (+\(paths.count - 1) more)" : ""
                return "Reading \(URL(fileURLWithPath: first).lastPathComponent)\(extra)..."
            }
            return "Reading project files..."
        case "file_write", "replace_in_file", "patch_file", "multi_replace_in_file":
            if let path = args["path"] as? String {
                return "Editing \(URL(fileURLWithPath: path).lastPathComponent)..."
            }
            return "Editing code..."
        case "create_directory":
            if let path = args["path"] as? String {
                return "Creating directory \(URL(fileURLWithPath: path).lastPathComponent)..."
            }
            return "Creating directory..."
        case "rename_file":
            if let oldPath = args["old_path"] as? String ?? args["path"] as? String {
                return "Renaming \(URL(fileURLWithPath: oldPath).lastPathComponent)..."
            }
            return "Renaming file..."
        case "delete_file":
            if let path = args["path"] as? String {
                return "Deleting \(URL(fileURLWithPath: path).lastPathComponent)..."
            }
            return "Deleting file..."
        case "apply_patch":
            return "Applying unified diff patch..."
        case "preview_control":
            if let url = args["url"] as? String {
                return "Opening live preview (\(url))..."
            }
            return "Updating Live Preview Dock..."
        case "device_runtime":
            let op = (args["operation"] as? String) ?? "run"
            return "Running device runtime (\(op))..."
        case "list_directory_tree", "list_files":
            return "Scanning project structure..."
        case "git_status", "git_diff", "git_log":
            return "Checking Git repository..."
        case "grep_search", "find_symbol", "file_search":
            if let query = args["query"] as? String ?? args["symbol"] as? String ?? args["pattern"] as? String {
                return "Searching for \"\(query.prefix(30))\"..."
            }
            return "Searching codebase..."
        case "get_diagnostics", "lsp_diagnostics":
            return "Checking compiler & LSP diagnostics..."
        case "shell":
            if let cmd = args["command"] as? String {
                let firstLine = cmd.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? cmd
                return "Running \(firstLine.prefix(44))..."
            }
            return "Running terminal command..."
        default:
            return "Executing \(name.replacingOccurrences(of: "_", with: " "))..."
        }
    }
    
    // MARK: - History Building
    
    private func buildConversationHistory(excludingMessageID: String? = nil) -> [(role: String, content: String)] {
        var remaining = maxHistoryChars
        var result: [(role: String, content: String)] = []

        for msg in messages.reversed() {
            if msg.id == "streaming" { continue }
            if let excluded = excludingMessageID, msg.id == excluded { continue }
            guard remaining > 0 else { break }
            switch msg.role {
            case .user, .assistant:
                let limit = min(maxMessageHistoryChars, remaining)
                var rawContent = msg.content
                if msg.role == .assistant && !msg.toolResults.isEmpty {
                    let toolSummary = msg.toolResults.prefix(8).map { tr in
                        let status = tr.success ? "ok" : "error"
                        return "\(tr.toolName)(\(status))"
                    }.joined(separator: ", ")
                    rawContent = "[Executed MicroCode Tools: \(toolSummary)]\n" + rawContent
                }
                let content = boundedHistoryText(rawContent, limit: limit)
                guard !content.isEmpty else { continue }
                result.append((role: msg.role == .user ? "user" : "assistant", content: content))
                remaining -= content.count
            case .system, .tool:
                continue
            }
        }

        return result.reversed()
    }

    private func deduplicateRepetitiveLines(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 3 else { return text }
        
        var result: [String] = []
        var lastNonEmpty = ""
        var repeatCount = 0
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !result.isEmpty && !result.last!.isEmpty {
                    result.append("")
                }
                continue
            }
            if trimmed == lastNonEmpty {
                repeatCount += 1
                if repeatCount < 2 {
                    result.append(line)
                }
            } else {
                lastNonEmpty = trimmed
                repeatCount = 0
                result.append(line)
            }
        }
        return result.joined(separator: "\n")
    }

    private func boundedHistoryText(_ text: String, limit: Int) -> String {
        let sanitized = deduplicateRepetitiveLines(text)
        guard sanitized.count > limit, limit > 64 else { return String(sanitized.prefix(max(0, limit))) }
        let headCount = (limit * 2) / 3
        let tailCount = limit - headCount
        return String(sanitized.prefix(headCount)) + "\n…[history truncated]…\n" + String(sanitized.suffix(tailCount))
    }
    
    private func buildSyncMessages(history: [(role: String, content: String)], lastText: String, toolResults: [ToolResultModel]) -> [[(String, Any)]] {
        var msgs: [[(String, Any)]] = []
        for h in history {
            msgs.append([("_role", h.role), ("text", h.content)])
        }
        return msgs
    }
    
    // MARK: - Pending Changes
    
    func applyChange(_ changeId: String) {
        var targetChange: PendingChangeModel?
        if let idx = pendingChanges.firstIndex(where: { $0.id == changeId }) {
            pendingChanges[idx].status = .accepted
            targetChange = pendingChanges[idx]
        }
        for mIdx in messages.indices {
            if let cIdx = messages[mIdx].pendingChanges.firstIndex(where: { $0.id == changeId }) {
                messages[mIdx].pendingChanges[cIdx].status = .accepted
                if targetChange == nil { targetChange = messages[mIdx].pendingChanges[cIdx] }
            }
        }
        if let change = targetChange {
            let url = URL(fileURLWithPath: change.filePath)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? change.newContent.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    func rejectChange(_ changeId: String) {
        var targetChange: PendingChangeModel?
        if let idx = pendingChanges.firstIndex(where: { $0.id == changeId }) {
            pendingChanges[idx].status = .rejected
            targetChange = pendingChanges[idx]
        }
        for mIdx in messages.indices {
            if let cIdx = messages[mIdx].pendingChanges.firstIndex(where: { $0.id == changeId }) {
                messages[mIdx].pendingChanges[cIdx].status = .rejected
                if targetChange == nil { targetChange = messages[mIdx].pendingChanges[cIdx] }
            }
        }
        if let change = targetChange {
            let url = URL(fileURLWithPath: change.filePath)
            if change.oldContent.isEmpty {
                try? FileManager.default.removeItem(at: url)
            } else {
                try? change.oldContent.write(to: url, atomically: true, encoding: .utf8)
            }
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
    
    // MARK: - Multi-Chat & Project Group Management
    
    private var cachedProjectGroups: [ProjectChatGroup] = []
    private var cachedProjectGroupsKey: String = ""
    private var projectGroupsRevision: Int = 0
    
    var projectGroups: [ProjectChatGroup] {
        let currentWs = toolBox.workspaceRoot ?? ""
        let cacheKey = "\(currentWs)|\(chatSessions.count)|\(chatSessions.first?.id ?? "")|\(chatSessions.first?.name ?? "")|\(chatSessions.first?.messageCount ?? 0)|\(projectGroupsRevision)"
        if cacheKey == cachedProjectGroupsKey && !cachedProjectGroups.isEmpty {
            return cachedProjectGroups
        }
        
        var groups: [String: (name: String, path: String?, chats: [ChatSession])] = [:]
        var order: [String] = []
        
        let currentWsName = !currentWs.isEmpty ? URL(fileURLWithPath: currentWs).lastPathComponent : "Current Project"
        
        // Ensure active workspace folder is always first in list
        if !currentWs.isEmpty {
            groups[currentWs] = (name: currentWsName, path: currentWs, chats: [])
            order.append(currentWs)
        }
        
        for chat in chatSessions {
            if let path = chat.projectPath, !path.isEmpty {
                let name = chat.projectName ?? URL(fileURLWithPath: path).lastPathComponent
                if groups[path] == nil {
                    groups[path] = (name: name, path: path, chats: [])
                    order.append(path)
                }
                groups[path]?.chats.append(chat)
            } else if let pName = chat.projectName, !pName.isEmpty {
                if groups[pName] == nil {
                    groups[pName] = (name: pName, path: nil, chats: [])
                    order.append(pName)
                }
                groups[pName]?.chats.append(chat)
            } else {
                // Legacy unassigned chats strictly grouped under General/Other
                let key = "legacy_general_other"
                if groups[key] == nil {
                    groups[key] = (name: "General / Other", path: nil, chats: [])
                    order.append(key)
                }
                groups[key]?.chats.append(chat)
            }
        }
        
        let built = order.compactMap { key -> ProjectChatGroup? in
            guard let g = groups[key] else { return nil }
            return ProjectChatGroup(projectName: g.name, projectPath: g.path, chats: g.chats)
        }
        cachedProjectGroups = built
        cachedProjectGroupsKey = cacheKey
        return built
    }
    
    func chats(for projectPath: String?) -> [ChatSession] {
        guard let path = projectPath else { return chatSessions }
        return chatSessions.filter { $0.projectPath == path }
    }
    
    func createNewChat(name: String? = nil, projectPath: String? = nil, activeSkillIds: [String]? = nil) -> ChatSession {
        let currentPath = projectPath ?? toolBox.workspaceRoot
        let currentName = currentPath != nil ? URL(fileURLWithPath: currentPath!).lastPathComponent : "General"
        let skills = activeSkillIds ?? AgentSkillsStore.shared.enabledSkillIds()
        let matchingChats = chatSessions.filter { $0.projectPath == currentPath }
        let chatName = name ?? "Task \(matchingChats.count + 1)"
        
        let newChat = ChatSession.create(
            name: chatName,
            projectPath: currentPath,
            projectName: currentName,
            activeSkillIds: skills
        )
        
        chatSessions.insert(newChat, at: 0)
        activeChatId = newChat.id
        messages = []
        contextLimitReached = false
        saveChats()
        Task { @MainActor in
            ImplementationPlanManager.shared.clearPlan()
            ACPHostService.shared.resetAllSessions()
        }
        return newChat
    }
    
    func switchChat(to chatId: String) {
        if activeChatId == chatId && (!messages.isEmpty || isLoading) { return }
        guard let chat = chatSessions.first(where: { $0.id == chatId }) else { return }
        contextLimitReached = false
        
        // Summarize current chat before switching (if it has enough messages)
        if let currentId = activeChatId, messages.count > 6 {
            let chatMessages = messages
                .filter { $0.role == .user || $0.role == .assistant }
                .map { (id: $0.id, role: $0.role.rawValue, content: $0.content) }
            memoryService.summarizeChat(chatId: currentId, messages: chatMessages)
        }
        
        saveCurrentChatMessages()
        // Evict previous chat's inline message array from RAM once persisted to disk
        if let prevId = activeChatId,
           let prevIdx = chatSessions.firstIndex(where: { $0.id == prevId }) {
            chatSessions[prevIdx].messages = []
        }
        activeChatId = chatId
        messages = loadMessagesForChat(chat, scope: activeScope)
        UserDefaults.standard.set(chatId, forKey: activeChatStorageKey)
        
        // Restore project workspace if this chat has a specific projectPath
        if let chatPath = chat.projectPath, !chatPath.isEmpty, toolBox.workspaceRoot != chatPath {
            setWorkspace(chatPath)
            NotificationCenter.default.post(name: NSNotification.Name("MicroCodeWorkspaceChanged"), object: chatPath)
        }
        
        // Restore Agent Skills snapshot for this specific chat
        if let skillIds = chat.activeSkillIds, !skillIds.isEmpty {
            AgentSkillsStore.shared.restoreSkills(skillIds)
        }
        Task { @MainActor in
            if let plan = chat.activePlan {
                ImplementationPlanManager.shared.currentPlan = plan
                ImplementationPlanManager.shared.isPlanVisible = (plan.approvalState == .pending)
            } else {
                ImplementationPlanManager.shared.clearPlan()
            }
            ACPHostService.shared.resetAllSessions()
        }
    }
    
    func deleteChat(_ chatId: String) {
        transcriptStore.remove(chatID: chatId, scope: activeScope)
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
        if let activeChatId {
            transcriptStore.remove(chatID: activeChatId, scope: activeScope)
            if let idx = chatSessions.firstIndex(where: { $0.id == activeChatId }) {
                chatSessions[idx].activePlan = nil
            }
        }
        messages.removeAll()
        saveCurrentChatMessages()
        Task { @MainActor in
            ImplementationPlanManager.shared.clearPlan()
            ACPHostService.shared.resetAllSessions()
        }
    }

    // MARK: - Per-Message Actions (Delete, Revert / Rollback, Edit, Retry)

    /// Strips any auto-appended `[Attached: ...]` footer from a user message when restoring to the input box.
    static func cleanUserPromptText(_ raw: String) -> String {
        if let range = raw.range(of: "\n\\[Attached: [^\\]]+\\]$", options: .regularExpression) {
            return String(raw[..<range.lowerBound])
        }
        return raw
    }

    /// Deletes a single message (and optionally reverts any file changes from that message).
    func deleteMessage(id: String, revertFiles: Bool = false) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        if isLoading && idx == messages.count - 1 {
            stopGeneration(autoProcessQueue: false)
        }
        let target = messages[idx]
        if revertFiles {
            for change in target.pendingChanges.reversed() where change.status != .rejected {
                revertFileChangeOnDisk(change)
            }
        }
        let changeIds = Set(target.pendingChanges.map(\.id))
        if !changeIds.isEmpty {
            pendingChanges.removeAll { changeIds.contains($0.id) }
        }
        messages.remove(at: idx)
        if let activeId = activeChatId {
            transcriptStore.deleteMessages(ids: [id], chatID: activeId, scope: activeScope)
        }
        contextLimitReached = false
        saveChats()
        logActivity(.info, "Deleted message from conversation")
    }

    /// Reverts the conversation back to (and removing) the specified message ID, restoring file changes made at or after that turn.
    /// Returns the clean text of the target message (if it was a user message) so the caller can populate the input box or re-send.
    @discardableResult
    func revertToMessage(id: String, restoreFiles: Bool = true) -> String? {
        guard let targetIdx = messages.firstIndex(where: { $0.id == id }) else { return nil }
        if isLoading {
            stopGeneration(autoProcessQueue: false)
        }
        let targetMsg = messages[targetIdx]
        let slice = Array(messages[targetIdx..<messages.count])

        if restoreFiles {
            // Walk backward from newest message to targetIdx so multi-turn edits to the same file restore to the earliest oldContent
            for msg in slice.reversed() {
                for change in msg.pendingChanges.reversed() where change.status != .rejected {
                    revertFileChangeOnDisk(change)
                }
            }
        }

        let removedChangeIds = Set(slice.flatMap { $0.pendingChanges.map(\.id) })
        if !removedChangeIds.isEmpty {
            pendingChanges.removeAll { removedChangeIds.contains($0.id) }
        }

        let removedMessageIds = slice.map(\.id)
        messages.removeSubrange(targetIdx..<messages.count)

        if let activeId = activeChatId {
            transcriptStore.deleteMessages(ids: removedMessageIds, chatID: activeId, scope: activeScope)
        }
        contextLimitReached = false
        saveChats()
        logActivity(.info, "Reverted conversation by \(removedMessageIds.count) message(s)")

        if targetMsg.role == .user {
            return Self.cleanUserPromptText(targetMsg.content)
        }
        return nil
    }

    /// Finds the preceding user message for a given assistant message ID (used for Retry / Regenerate).
    func precedingUserPrompt(forAssistantMessageId id: String) -> (userMessageId: String, prompt: String)? {
        guard let assistantIdx = messages.firstIndex(where: { $0.id == id }) else { return nil }
        for i in stride(from: assistantIdx - 1, through: 0, by: -1) {
            if messages[i].role == .user {
                return (messages[i].id, Self.cleanUserPromptText(messages[i].content))
            }
        }
        return nil
    }

    private func revertFileChangeOnDisk(_ change: PendingChangeModel) {
        let url = URL(fileURLWithPath: change.filePath)
        if change.oldContent.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? change.oldContent.write(to: url, atomically: true, encoding: .utf8)
        }
        AppState.shared?.reloadFileFromDisk(path: change.filePath)
    }

    /// Restores one older page only when the user explicitly asks for it.
    /// This preserves full history while keeping startup and idle memory bounded.
    func loadEarlierMessages() {
        guard let chatId = activeChatId,
              let oldestID = messages.first?.id else { return }
        let older = transcriptStore.loadBefore(
            chatID: chatId,
            scope: activeScope,
            beforeMessageID: oldestID,
            limit: transcriptPageSize
        )
        guard !older.isEmpty else { return }
        let residentIDs: Set<String> = Set(messages.map { $0.id })
        let page = older
            .filter { !residentIDs.contains($0.id) }
            .map { $0.toModel() }
        messages.insert(contentsOf: page, at: 0)
    }

    var hasEarlierMessages: Bool {
        guard let chatId = activeChatId,
              let session = chatSessions.first(where: { $0.id == chatId }) else { return false }
        // The manifest count is updated whenever a message is persisted. This
        // avoids synchronous disk I/O from SwiftUI's scrolling layout pass.
        return (session.messageCount ?? messages.count) > messages.count
    }
    
    func renameChat(_ chatId: String, to newName: String) {
        if let idx = chatSessions.firstIndex(where: { $0.id == chatId }) {
            chatSessions[idx].name = newName
            saveChats()
        }
    }
    
    // MARK: - Persistence
    
    private func saveCurrentChatMessages() {
        saveChats()
    }
    
    func saveChats() {
        projectGroupsRevision &+= 1
        flushFileSnapshotsIfNeeded()
        if let activeId = activeChatId,
           let idx = chatSessions.firstIndex(where: { $0.id == activeId }) {
            // Persist before evicting old UI rows. The cap is now a RAM policy,
            // never a retention policy.
            let persistable = messages.filter { !($0.id == "streaming" && $0.content.isEmpty && $0.toolResults.isEmpty) }
            let totalMessages = transcriptStore.upsert(
                persistable.map { AgentMessageData.from($0) },
                chatID: activeId,
                scope: activeScope
            )
            if !isLoading {
                trimResidentChatMemory()
            }
            chatSessions[idx].messages = []
            chatSessions[idx].messageCount = totalMessages
            chatSessions[idx].updatedAt = Date()
            UserDefaults.standard.set(activeId, forKey: activeChatStorageKey)
        }
        // Only store lightweight session metadata in UserDefaults (messages live in AgentTranscriptStore on disk)
        let metadataOnly: [ChatSession] = chatSessions.map { session in
            var copy = session
            copy.messages = []
            return copy
        }
        let storageKey = chatStorageKey
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(metadataOnly) {
                UserDefaults.standard.set(data, forKey: storageKey)
            }
        }
    }

    /// Keep the live SwiftUI working set bounded. Full content has already
    /// been committed by `saveChats()` and can be paged back from disk.
    private func trimResidentChatMemory() {
        if messages.count > maxResidentMessages {
            let evictionCount = messages.count - maxResidentMessages
            let evicted = Array(messages.prefix(evictionCount))
            if let activeId = activeChatId,
               let idx = chatSessions.firstIndex(where: { $0.id == activeId }),
               let newestEvictedID = evicted.last?.id,
               chatSessions[idx].summaryThroughMessageID != newestEvictedID {
                let summaryInput = evicted
                    .filter { $0.role == .user || $0.role == .assistant }
                    .map { (id: $0.id, role: $0.role.rawValue, content: $0.content) }
                memoryService.summarizeChat(chatId: activeId, messages: summaryInput)
                chatSessions[idx].summaryThroughMessageID = newestEvictedID
            }
            messages.removeFirst(evictionCount)
        }
    }
    
    func loadChats() {
        chatSessions = readChats(for: activeScope)
        if let activeId = activeChatId,
           let matched = chatSessions.first(where: { $0.id == activeId }) {
            messages = loadMessagesForChat(matched, scope: activeScope)
        }
    }

    // MARK: - Chat Title Auto-Generation
    
    static func generateTitle(from text: String) -> String {
        // Strip markdown code blocks, headers, tags, XML, and extra whitespace
        var cleaned = text
            .replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Take first non-empty line
        let lines = cleaned.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let firstLine = lines.first, !firstLine.isEmpty else { return "New Conversation" }
        
        cleaned = firstLine
        // Remove leading punctuation/bullets
        cleaned = cleaned.replacingOccurrences(of: "^[-*•>0-9.]+\\s*", with: "", options: .regularExpression)
        
        let maxLength = 42
        if cleaned.count > maxLength {
            let index = cleaned.index(cleaned.startIndex, offsetBy: maxLength)
            return String(cleaned[..<index]).trimmingCharacters(in: .whitespaces) + "…"
        }
        return cleaned
    }

    private func readChats(for scope: AgentSessionScope) -> [ChatSession] {
        let key = scope == .science ? scienceChatStorageKey : editorChatStorageKey
        guard let data = UserDefaults.standard.data(forKey: key),
              let chats = try? JSONDecoder().decode([ChatSession].self, from: data) else { return [] }

        // Migrate legacy UserDefaults transcripts on first access, then strip
        // inline messages from UserDefaults so only lightweight metadata stays in RAM.
        var needsMetadataCompactSave = false
        let loadedChats: [ChatSession] = chats.map { chat in
            var compact = chat
            if !compact.messages.isEmpty {
                needsMetadataCompactSave = true
            }
            if !compact.messages.isEmpty || compact.messageCount == nil {
                compact.messageCount = transcriptStore.bootstrap(compact, scope: scope)
            }
            // Backfill descriptive titles for generic "Task X" or "New Task" chats
            let isGenericName = compact.name.hasPrefix("Task ") || compact.name == "New Task" || compact.name.isEmpty
            if isGenericName {
                let sample = compact.messages.isEmpty
                    ? transcriptStore.loadRecent(chatID: compact.id, scope: scope, limit: 4)
                    : compact.messages
                if let firstUserMsg = sample.first(where: { $0.role == "user" }),
                   !firstUserMsg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    compact.name = Self.generateTitle(from: firstUserMsg.content)
                    needsMetadataCompactSave = true
                }
            }
            // Never hold inactive session message arrays in RAM or UserDefaults
            compact.messages = []
            return compact
        }
        if needsMetadataCompactSave {
            if let updatedData = try? JSONEncoder().encode(loadedChats) {
                UserDefaults.standard.set(updatedData, forKey: key)
            }
        }
        return loadedChats
    }
    
    // MARK: - Activity Logging
    
    func logActivity(_ type: AgentActivity.ActivityType, _ message: String, detail: String? = nil, output: String? = nil) {
        let activity = AgentActivity(type: type, message: message, detail: detail, output: output, timestamp: Date())
        let update = { [weak self] in
            guard let self = self else { return }
            self.activityLog.append(activity)
            if self.activityLog.count > 1000 {
                self.activityLog.removeFirst(self.activityLog.count - 1000)
            }
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
        
        // Also persist to system report log for durable auditing
        let logMsg = "Agent [\(type)]: \(message)\(detail != nil ? " - " + detail! : "")"
        ReportLogManager.shared.log(logMsg, type: type == .error ? .error : .info)
    }
    
    func clearActivityLog() {
        activityLog.removeAll()
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
        let registeredToolNames = Set(toolBox.tools.keys)
        let isKnownTool: (String) -> Bool = { rawName in
            let canonical = AgentToolBox.normalizeToolName(rawName)
            return registeredToolNames.contains(canonical) || canonical.hasPrefix("mcp__")
        }
        
        // Pattern 0: [Tool Call: tool_name({...})]
        if text.contains("[Tool Call:") {
            let bracketPattern = #"\[Tool Call:\s*([a-zA-Z0-9_]+)\s*\(([^\n]*?)\)\]"#
            if let regex = try? NSRegularExpression(pattern: bracketPattern, options: []) {
                let nsText = text as NSString
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
                for match in matches {
                    guard match.numberOfRanges > 2 else { continue }
                    let rawToolName = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let toolName = AgentToolBox.normalizeToolName(rawToolName)
                    let argsStr = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard isKnownTool(toolName) else { continue }
                    let args = parseToolArgs(argsStr, toolName: toolName)
                    if !args.isEmpty {
                        calls.append(AIToolCall(id: UUID().uuidString, name: toolName, arguments: args))
                    }
                }
            }
            if !calls.isEmpty { return calls }
        }
        
        // Pattern 1: <tool_call> JSON </tool_call> or <function_call> JSON </function_call>
        let xmlPattern = "<(?:tool_call|function_call)>\\s*([\\s\\S]*?)\\s*</(?:tool_call|function_call)>"
        if let regex = try? NSRegularExpression(pattern: xmlPattern, options: []) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let jsonStr = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = jsonStr.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) {
                    if let json = parsed as? [String: Any],
                       let rawName = (json["name"] as? String) ?? (json["tool"] as? String) ?? (json["function"] as? String) {
                        let name = AgentToolBox.normalizeToolName(rawName)
                        if isKnownTool(name) {
                            let args = (json["arguments"] as? [String: Any])
                                ?? (json["parameters"] as? [String: Any])
                                ?? (json["args"] as? [String: Any])
                                ?? (json["input"] as? [String: Any])
                                ?? [:]
                            calls.append(AIToolCall(id: UUID().uuidString, name: name, arguments: AgentToolBox.normalizeToolParams(args)))
                        }
                    } else if let arr = parsed as? [[String: Any]] {
                        for json in arr {
                            if let rawName = (json["name"] as? String) ?? (json["tool"] as? String) ?? (json["function"] as? String) {
                                let name = AgentToolBox.normalizeToolName(rawName)
                                if isKnownTool(name) {
                                    let args = (json["arguments"] as? [String: Any])
                                        ?? (json["parameters"] as? [String: Any])
                                        ?? (json["args"] as? [String: Any])
                                        ?? (json["input"] as? [String: Any])
                                        ?? [:]
                                    calls.append(AIToolCall(id: UUID().uuidString, name: name, arguments: AgentToolBox.normalizeToolParams(args)))
                                }
                            }
                        }
                    }
                }
            }
        }
        if !calls.isEmpty { return calls }

        // Pattern 1B: DeepSeek DSML (`<｜DSML｜invoke name="...">`) & `<invoke name="...">` XML blocks
        if text.contains("invoke") || text.contains("DSML") {
            let invokePattern = #"<(?:[｜\|]DSML[｜\|])?invoke\s+name="([^"]+)"[^>]*>([\s\S]*?)</(?:[｜\|]DSML[｜\|])?invoke>"#
            let paramPattern = #"<(?:[｜\|]DSML[｜\|])?parameter\s+name="([^"]+)"[^>]*>([\s\S]*?)</(?:[｜\|]DSML[｜\|])?parameter>"#
            if let invokeRegex = try? NSRegularExpression(pattern: invokePattern),
               let paramRegex = try? NSRegularExpression(pattern: paramPattern) {
                let nsText = text as NSString
                let invokeMatches = invokeRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
                for match in invokeMatches {
                    guard match.numberOfRanges > 2 else { continue }
                    let rawName = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = AgentToolBox.normalizeToolName(rawName)
                    guard isKnownTool(name) else { continue }
                    let bodyStr = nsText.substring(with: match.range(at: 2))
                    let nsBody = bodyStr as NSString
                    var paramsDict: [String: Any] = [:]
                    let paramMatches = paramRegex.matches(in: bodyStr, range: NSRange(location: 0, length: nsBody.length))
                    for pm in paramMatches {
                        guard pm.numberOfRanges > 2 else { continue }
                        let pName = nsBody.substring(with: pm.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                        let pValRaw = nsBody.substring(with: pm.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if (pValRaw.hasPrefix("{") && pValRaw.hasSuffix("}")) || (pValRaw.hasPrefix("[") && pValRaw.hasSuffix("]")),
                           let d = pValRaw.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: d) {
                            paramsDict[pName] = obj
                        } else if pValRaw.lowercased() == "true" {
                            paramsDict[pName] = true
                        } else if pValRaw.lowercased() == "false" {
                            paramsDict[pName] = false
                        } else {
                            paramsDict[pName] = pValRaw
                        }
                    }
                    calls.append(AIToolCall(id: UUID().uuidString, name: name, arguments: AgentToolBox.normalizeToolParams(paramsDict)))
                }
            }
            if !calls.isEmpty { return calls }
        }
        
        // Pattern 2: ```json { "name": "tool_name", "arguments": {...} } ```
        let jsonBlockPattern = "```(?:tool_call|json)?\\s*(\\{[\\s\\S]*?\"name\"\\s*:\\s*\"([^\"]+)\"[\\s\\S]*?\\})\\s*```"
        if let regex = try? NSRegularExpression(pattern: jsonBlockPattern, options: []) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                guard match.numberOfRanges > 2 else { continue }
                let fullJsonStr = nsText.substring(with: match.range(at: 1))
                let rawName = nsText.substring(with: match.range(at: 2))
                let name = AgentToolBox.normalizeToolName(rawName)
                if isKnownTool(name),
                   let data = fullJsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let args = (json["arguments"] as? [String: Any])
                        ?? (json["parameters"] as? [String: Any])
                        ?? [:]
                    calls.append(AIToolCall(id: UUID().uuidString, name: name, arguments: AgentToolBox.normalizeToolParams(args)))
                }
            }
        }
        if !calls.isEmpty { return calls }
        
        // Pattern 3: tool_name({...}) or tool_name(key:"value", key2:"value2")
        for tool in registeredToolNames {
            guard text.contains("\(tool)(") else { continue }
            let escapedTool = NSRegularExpression.escapedPattern(for: tool)
            // First match JSON-argument style tool_name({...}) which may contain parentheses inside strings
            let jsonCallPattern = "\(escapedTool)\\s*\\(\\s*(\\{[^\\n]*\\})\\s*\\)"
            if let jsonRegex = try? NSRegularExpression(pattern: jsonCallPattern, options: []) {
                let nsText = text as NSString
                let jsonMatches = jsonRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
                if !jsonMatches.isEmpty {
                    for match in jsonMatches {
                        guard match.numberOfRanges > 1 else { continue }
                        let argsString = nsText.substring(with: match.range(at: 1))
                        let args = parseToolArgs(argsString, toolName: tool)
                        if !args.isEmpty {
                            calls.append(AIToolCall(id: UUID().uuidString, name: tool, arguments: args))
                        }
                    }
                    continue
                }
            }
            
            let pattern = "\(escapedTool)\\s*\\(([^)]+)\\)"
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
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Step 1: If the argument string is a JSON object {...}, decode it directly!
        if let firstBrace = cleaned.firstIndex(of: "{"),
           let lastBrace = cleaned.lastIndex(of: "}"),
           firstBrace < lastBrace {
            let jsonSlice = String(cleaned[firstBrace...lastBrace])
            if let data = jsonSlice.data(using: .utf8),
               let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let inner = (jsonObj["arguments"] as? [String: Any])
                    ?? (jsonObj["parameters"] as? [String: Any])
                    ?? (jsonObj["args"] as? [String: Any])
                    ?? jsonObj
                return AgentToolBox.normalizeToolParams(inner)
            }
            // Fallback for single-key JSON object with unescaped quotes inside the value (e.g. {"command":"ls || echo "no""})
            if let regex = try? NSRegularExpression(pattern: #"^\{\s*"([a-zA-Z0-9_]+)"\s*:\s*"([\s\S]*)"\s*\}$"#),
               let match = regex.firstMatch(in: jsonSlice, range: NSRange(jsonSlice.startIndex..., in: jsonSlice)),
               let kRange = Range(match.range(at: 1), in: jsonSlice),
               let vRange = Range(match.range(at: 2), in: jsonSlice) {
                let k = String(jsonSlice[kRange])
                let v = String(jsonSlice[vRange])
                    .replacingOccurrences(of: #"\""#, with: "\"")
                    .replacingOccurrences(of: #"\\"#, with: "\\")
                return [k: v]
            }
        }
        
        // Step 2: Parse "key":"value", 'key':'value', or key:value pairs
        let kvPattern = "(?:\"([a-zA-Z0-9_]+)\"|'([a-zA-Z0-9_]+)'|([a-zA-Z0-9_]+))\\s*[:=]\\s*(?:\"((?:\\\\.|[^\"\\\\])*)\"|'((?:\\\\.|[^'\\\\])*)'|([^,})]+))"
        if let regex = try? NSRegularExpression(pattern: kvPattern, options: []) {
            let nsStr = cleaned as NSString
            let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: nsStr.length))
            
            for match in matches {
                var key = ""
                for i in 1...min(3, match.numberOfRanges - 1) {
                    let r = match.range(at: i)
                    if r.location != NSNotFound {
                        key = nsStr.substring(with: r).trimmingCharacters(in: .whitespaces)
                        break
                    }
                }
                var value = ""
                for i in 4...min(6, match.numberOfRanges - 1) {
                    let r = match.range(at: i)
                    if r.location != NSNotFound {
                        value = nsStr.substring(with: r).trimmingCharacters(in: .whitespaces)
                            .replacingOccurrences(of: #"\""#, with: "\"")
                        break
                    }
                }
                if !key.isEmpty && !value.isEmpty {
                    args[key] = value
                }
            }
        }
        
        // Step 3: For simple single-arg tools, infer the key (never pass raw {...} JSON as a literal path/command)
        if args.isEmpty {
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !trimmed.isEmpty && !trimmed.hasPrefix("{") {
                switch toolName {
                case "file_read", "list_directory_tree": args["path"] = trimmed
                case "grep_search", "file_search": args["pattern"] = trimmed
                case "shell": args["command"] = trimmed
                default: break
                }
            }
        }
        
        return AgentToolBox.normalizeToolParams(args)
    }

    // MARK: - Feature #3: Zero-Drop Auto-Failover & Cross-Provider Handoff

    func resolveFailoverCandidate(
        currentProvider: StreamableAIProvider,
        currentModel: String,
        triedModels: Set<String>
    ) -> (provider: StreamableAIProvider, model: String, apiKey: String, label: String)? {
        struct Candidate {
            let provider: StreamableAIProvider
            let model: String
            let apiKey: String
            let label: String
        }
        var pool: [Candidate] = []

        // 1. Connected Subscriptions (TH-AI Passport, GitHub Copilot, ChatGPT, Claude)
        if SubscriptionAuthManager.shared.isConnected(.aipass) {
            let aipassKey = SubscriptionAuthManager.shared.token(for: .aipass) ?? ""
            if currentProvider == .deepseek || currentModel.lowercased().contains("deepseek") {
                pool.append(Candidate(provider: .aipass, model: "DeepSeek-V4-Flash", apiKey: aipassKey, label: "TH-AI Passport (DeepSeek-V4-Flash)"))
            }
            for m in ["claude-sonnet-5-5@azure", "gpt-6.1-sol", "gemini-4-argon", "DeepSeek-V4-Flash", "gemini-3.5-flash-lite"] {
                pool.append(Candidate(provider: .aipass, model: m, apiKey: aipassKey, label: "TH-AI Passport (\(m))"))
            }
        }
        if SubscriptionAuthManager.shared.isConnected(.copilot) {
            let copilotKey = SubscriptionAuthManager.shared.token(for: .copilot) ?? ""
            for m in ["claude-sonnet-4.5", "gpt-4.1", "gemini-2.5-pro"] {
                pool.append(Candidate(provider: .copilot, model: m, apiKey: copilotKey, label: "Copilot (\(m))"))
            }
        }
        if SubscriptionAuthManager.shared.isConnected(.claude) {
            let claudeKey = SubscriptionAuthManager.shared.token(for: .claude) ?? ""
            pool.append(Candidate(provider: .anthropic, model: "claude-sonnet-5-5", apiKey: claudeKey, label: "Claude Sub (claude-sonnet-5-5)"))
        }
        if SubscriptionAuthManager.shared.isConnected(.chatgpt) {
            let chatgptKey = SubscriptionAuthManager.shared.token(for: .chatgpt) ?? ""
            pool.append(Candidate(provider: .openai, model: "gpt-6.1-sol", apiKey: chatgptKey, label: "ChatGPT Sub (gpt-6.1-sol)"))
        }

        // 2. BYOK Keys configured in AppState / AIModelCatalog
        let byokOrder: [(provider: StreamableAIProvider, keyName: String, defaultModel: String, label: String)] = [
            (.gemini, "gemini", "gemini-3.5-flash", "Gemini (gemini-3.5-flash)"),
            (.gemini, "gemini", "gemini-2.5-flash", "Gemini (gemini-2.5-flash)"),
            (.anthropic, "anthropic", "claude-sonnet-5-5", "Anthropic (claude-sonnet-5-5)"),
            (.openai, "openai", "gpt-5.2", "OpenAI (gpt-5.2)"),
            (.glm, "glm", "glm-5.3-flash", "GLM (glm-5.3-flash)"),
            (.deepseek, "deepseek", "deepseek-flash", "DeepSeek (deepseek-flash)")
        ]
        for item in byokOrder {
            let resolvedKey = (AppState.shared?.resolveApiKey(for: item.keyName) ?? AIModelCatalog.resolveKey(item.keyName)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !resolvedKey.isEmpty {
                pool.append(Candidate(provider: item.provider, model: item.defaultModel, apiKey: resolvedKey, label: item.label))
            }
        }

        // Pick first candidate not yet tried in this turn
        for cand in pool {
            let sig = "\(cand.provider.rawValue)/\(cand.model)"
            if !triedModels.contains(sig) && !(cand.provider == currentProvider && cand.model == currentModel) {
                return (cand.provider, cand.model, cand.apiKey, cand.label)
            }
        }
        return nil
    }

    // MARK: - Feature #5: Context X-Ray & Token Pruner HUD

    func loadPinnedConstraints(for workspacePath: String?) {
        let root = workspacePath ?? toolBox.workspaceRoot ?? "global"
        let key = "MicroCode.PinnedConstraints.\(WorkspacePathPolicy.canonicalPath(root))"
        pinnedConstraints = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func addPinnedConstraint(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !pinnedConstraints.contains(trimmed) else { return }
        pinnedConstraints.append(trimmed)
        savePinnedConstraints()
    }

    func removePinnedConstraint(at index: Int) {
        guard pinnedConstraints.indices.contains(index) else { return }
        pinnedConstraints.remove(at: index)
        savePinnedConstraints()
    }

    private func savePinnedConstraints() {
        let root = toolBox.workspaceRoot ?? "global"
        let key = "MicroCode.PinnedConstraints.\(WorkspacePathPolicy.canonicalPath(root))"
        UserDefaults.standard.set(pinnedConstraints, forKey: key)
    }

    func computeContextXRay() -> ContextXRayBreakdown {
        let sysTokens = tokenOptimizer.estimateTokens((agentMdContent ?? "") + (taskMdContent ?? "")) + 1_200
        let pinnedTokens = tokenOptimizer.estimateTokens(pinnedConstraints.joined(separator: "\n"))
        var msgProseChars = 0
        var toolOutputChars = 0
        for msg in messages {
            msgProseChars += msg.content.count
            for tr in msg.toolResults {
                toolOutputChars += tr.output.count
            }
        }
        let msgTokens = max(0, msgProseChars / 4)
        let toolTokens = max(0, toolOutputChars / 4)
        let total = max(1, sysTokens + pinnedTokens + msgTokens + toolTokens)
        return ContextXRayBreakdown(
            systemAndRulesTokens: sysTokens,
            pinnedConstraintsTokens: pinnedTokens,
            conversationProseTokens: msgTokens,
            toolOutputsTokens: toolTokens,
            totalTokens: total,
            budgetCeiling: 128_000
        )
    }

    /// Compresses bulky tool outputs in older conversation turns (keeping the latest 2 messages intact).
    /// Returns the estimated number of tokens freed.
    @discardableResult
    func pruneBulkyToolOutputs() -> Int {
        guard messages.count > 2 else { return 0 }
        var charsFreed = 0
        let cutoffIndex = max(0, messages.count - 2)
        for idx in 0..<cutoffIndex {
            let msg = messages[idx]
            guard !msg.toolResults.isEmpty else { continue }
            var didCompress = false
            let prunedTools: [ToolResultModel] = msg.toolResults.map { tr in
                if tr.output.count > 600 {
                    charsFreed += (tr.output.count - 450)
                    didCompress = true
                    let head = tr.output.prefix(280)
                    let tail = tr.output.suffix(120)
                    let summary = "\(head)\n... [Pruned by Context X-Ray (\(tr.output.count) chars)] ...\n\(tail)"
                    return ToolResultModel(
                        toolCallId: tr.toolCallId,
                        toolName: tr.toolName,
                        toolParams: tr.toolParams,
                        success: tr.success,
                        output: summary,
                        error: tr.error
                    )
                }
                return tr
            }
            if didCompress {
                messages[idx] = AgentMessageModel(
                    id: msg.id,
                    role: msg.role,
                    content: msg.content,
                    toolResults: prunedTools,
                    pendingChanges: msg.pendingChanges,
                    timestamp: msg.timestamp
                )
            }
        }
        let freedTokens = max(0, charsFreed / 4)
        if charsFreed > 0 {
            totalTokensSavedByShield += freedTokens
            saveCurrentChatMessages()
            saveChats()
        }
        return freedTokens
    }

    // MARK: - Feature #8: "Where Was I?" Instant Project Briefing

    func refreshProjectBriefing() {
        guard let ws = toolBox.workspaceRoot, !ws.isEmpty else {
            projectBriefing = nil
            return
        }
        let wsName = URL(fileURLWithPath: ws).lastPathComponent
        let currentTaskMd = taskMdContent ?? (try? String(contentsOfFile: (ws as NSString).appendingPathComponent(".microcode/task.md"), encoding: .utf8)) ?? ""
        let lastChatSummary: String = {
            if let lastAssistant = messages.last(where: { $0.role == .assistant }) {
                let clean = AIStructuredTurnCodec.stripThoughtTags(lastAssistant.content)
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { return String(clean.prefix(140)) }
            }
            if let recentChat = chatSessions.first(where: { $0.projectPath == ws && !$0.messages.isEmpty }),
               let lastMsg = recentChat.messages.last {
                let clean = AIStructuredTurnCodec.stripThoughtTags(lastMsg.content)
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { return "\(recentChat.name): \(clean.prefix(110))" }
            }
            return "Ready to start working on \(wsName)"
        }()

        Task.detached(priority: .utility) {
            func runGit(_ args: [String]) -> String {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                proc.arguments = ["-C", ws] + args
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = FileHandle.nullDevice
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                } catch {
                    return ""
                }
            }

            let branch = runGit(["rev-parse", "--abbrev-ref", "HEAD"])
            let statusOut = runGit(["status", "-s"])
            let modifiedFiles: [String] = statusOut
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(8)
                .map { line in
                    let parts = line.split(whereSeparator: { $0.isWhitespace })
                    return parts.last.map(String.init) ?? line
                }
            let lastCommit = runGit(["log", "-1", "--oneline"])

            // Parse task.md checkboxes
            var pendingItems: [String] = []
            var completedCount = 0
            for line in currentTaskMd.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("- [x]") || t.hasPrefix("- [X]") {
                    completedCount += 1
                } else if t.hasPrefix("- [ ]") {
                    let itemText = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if !itemText.isEmpty && !itemText.hasPrefix("**1.1** Inspect workspace files") {
                        pendingItems.append(itemText)
                    }
                }
            }

            let nextStepPrompt: String = {
                if let firstPending = pendingItems.first {
                    return "Continue working on the next pending task in `.microcode/task.md`: \(firstPending)"
                } else if !modifiedFiles.isEmpty {
                    return "Inspect the current uncommitted changes in \(modifiedFiles.prefix(3).joined(separator: ", ")), verify compilation/tests, and suggest next steps."
                } else {
                    return "Inspect the \(wsName) workspace and summarize current status and recommended next steps."
                }
            }()

            let snapshot = ProjectBriefingSnapshot(
                workspaceName: wsName,
                gitBranch: branch.isEmpty ? "main" : branch,
                modifiedFiles: modifiedFiles,
                recentCommit: lastCommit,
                pendingTasks: Array(pendingItems.prefix(3)),
                completedTasksCount: completedCount,
                lastConversationSummary: lastChatSummary,
                suggestedNextPrompt: nextStepPrompt
            )
            await MainActor.run {
                self.projectBriefing = snapshot
            }
        }
    }
}

// MARK: - Feature #5 & #8 Models (Context X-Ray & Project Briefing)

struct ContextXRayBreakdown {
    let systemAndRulesTokens: Int
    let pinnedConstraintsTokens: Int
    let conversationProseTokens: Int
    let toolOutputsTokens: Int
    let totalTokens: Int
    let budgetCeiling: Int

    var usageFraction: Double {
        min(1.0, Double(totalTokens) / Double(max(1, budgetCeiling)))
    }
}

struct ProjectBriefingSnapshot: Equatable {
    let workspaceName: String
    let gitBranch: String
    let modifiedFiles: [String]
    let recentCommit: String
    let pendingTasks: [String]
    let completedTasksCount: Int
    let lastConversationSummary: String
    let suggestedNextPrompt: String
}

struct AgentActivity: Identifiable, Equatable {
    let id: UUID
    let type: ActivityType
    let message: String
    let detail: String?
    let output: String?
    let timestamp: Date
    
    init(id: UUID = UUID(), type: ActivityType, message: String, detail: String? = nil, output: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.type = type
        self.message = message
        self.detail = detail
        self.output = output
        self.timestamp = timestamp
    }
    
    enum ActivityType: String, Equatable, CaseIterable {
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
            case .thinking: return Color(red: 0.68, green: 0.64, blue: 0.82)
            case .tool: return Color(red: 0.50, green: 0.68, blue: 0.85)
            case .success: return Color(red: 0.42, green: 0.78, blue: 0.56)
            case .error: return Color(red: 0.90, green: 0.44, blue: 0.44)
            case .fileChange: return Color(red: 0.88, green: 0.68, blue: 0.40)
            case .info: return .secondary
            case .done: return Color(red: 0.42, green: 0.78, blue: 0.56)
            }
        }
    }
}

// MARK: - Agent Phase

enum AgentPhase: Equatable {
    case idle
    case thinking
    case executing(String) // tool name
    case validating
    case done
    
    static func == (lhs: AgentPhase, rhs: AgentPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.thinking, .thinking), (.done, .done), (.validating, .validating): return true
        case (.executing(let a), .executing(let b)): return a == b
        default: return false
        }
    }
    
    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .thinking: return "Thinking..."
        case .executing(let tool): return "Running \(tool)"
        case .validating: return "Validating changes..."
        case .done: return "Done"
        }
    }
    
    var icon: String {
        switch self {
        case .idle: return "circle"
        case .thinking: return "brain"
        case .executing: return "gearshape.2.fill"
        case .validating: return "checkmark.shield.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .idle: return .secondary
        case .thinking: return .purple
        case .executing: return .blue
        case .validating: return .orange
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

struct ProjectChatGroup: Identifiable, Hashable, Equatable {
    var id: String { projectPath ?? projectName }
    let projectName: String
    let projectPath: String?
    let chats: [ChatSession]
    
    static func == (lhs: ProjectChatGroup, rhs: ProjectChatGroup) -> Bool {
        lhs.id == rhs.id && lhs.chats.count == rhs.chats.count
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ChatSession: Identifiable, Codable {
    let id: String
    var name: String
    var projectPath: String?
    var projectName: String?
    var activeSkillIds: [String]?
    var messages: [AgentMessageData]
    /// Total durable transcript length. `messages` is only the loaded page.
    var messageCount: Int?
    /// Last message represented by an evicted-memory summary.
    var summaryThroughMessageID: String?
    var activePlan: ImplementationPlan?
    var createdAt: Date
    var updatedAt: Date
    
    static func create(
        name: String = "New Task",
        projectPath: String? = nil,
        projectName: String? = nil,
        activeSkillIds: [String]? = nil,
        activePlan: ImplementationPlan? = nil
    ) -> ChatSession {
        ChatSession(
            id: UUID().uuidString,
            name: name,
            projectPath: projectPath,
            projectName: projectName,
            activeSkillIds: activeSkillIds,
            messages: [],
            messageCount: 0,
            summaryThroughMessageID: nil,
            activePlan: activePlan,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

struct PersistedToolResult: Codable {
    let toolCallId: String
    let toolName: String
    let stringParams: [String: String]?
    let success: Bool
    let output: String
    let error: String?

    static func from(_ model: ToolResultModel) -> PersistedToolResult {
        var params: [String: String]? = nil
        if let raw = model.toolParams {
            var dict: [String: String] = [:]
            for (k, v) in raw {
                if let s = v as? String {
                    dict[k] = s
                } else if let n = v as? NSNumber {
                    dict[k] = n.stringValue
                }
            }
            if !dict.isEmpty { params = dict }
        }
        // Cap persisted tool output per item to keep JSON transcripts fast and compact
        let cappedOutput = model.output.count > 4000 ? String(model.output.prefix(4000)) : model.output
        return PersistedToolResult(
            toolCallId: model.toolCallId,
            toolName: model.toolName,
            stringParams: params,
            success: model.success,
            output: cappedOutput,
            error: model.error
        )
    }

    func toModel() -> ToolResultModel {
        var anyParams: [String: Any]? = nil
        if let sp = stringParams {
            anyParams = AgentToolBox.normalizeToolParams(sp)
        }
        return ToolResultModel(
            toolCallId: toolCallId,
            toolName: toolName,
            toolParams: anyParams,
            success: success,
            output: output,
            error: error
        )
    }
}

struct AgentMessageData: Codable, Identifiable {
    let id: String
    let role: String
    let content: String
    let timestamp: Date
    var toolResults: [PersistedToolResult]? = nil
    
    static func from(_ model: AgentMessageModel) -> AgentMessageData {
        let persistedTools = model.toolResults.isEmpty ? nil : model.toolResults.map { PersistedToolResult.from($0) }
        return AgentMessageData(
            id: model.id,
            role: model.role.rawValue,
            content: AIStructuredTurnCodec.stripToolCallArtifacts(model.content),
            timestamp: model.timestamp,
            toolResults: persistedTools
        )
    }
    
    func toModel() -> AgentMessageModel {
        AgentMessageModel(
            id: id,
            role: AgentMessageModel.MessageRole(rawValue: role) ?? .assistant,
            content: AIStructuredTurnCodec.stripToolCallArtifacts(content),
            toolResults: (toolResults ?? []).map { $0.toModel() },
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
    var pendingChanges: [PendingChangeModel]
    let timestamp: Date
    
    init(id: String, role: MessageRole, content: String, toolResults: [ToolResultModel] = [], pendingChanges: [PendingChangeModel] = [], timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.toolResults = toolResults
        self.pendingChanges = pendingChanges
        self.timestamp = timestamp
    }
    
    enum MessageRole: String, Codable {
        case user, assistant, system, tool
    }
}

struct ToolResultModel {
    let toolCallId: String
    let toolName: String
    var toolParams: [String: Any]? = nil
    let success: Bool
    private let rawOutput: String?
    private let compressedOutput: Data?
    let outputPreview: String
    let outputLineCount: Int
    let error: String?
    
    var output: String {
        if let raw = rawOutput { return raw }
        if let comp = compressedOutput, let decomp = StateCompressionEngine.decompressString(comp) {
            return decomp
        }
        return ""
    }
    
    init(toolCallId: String, toolName: String, toolParams: [String: Any]? = nil, success: Bool, output: String, error: String? = nil) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.toolParams = toolParams
        self.success = success
        self.error = error
        self.outputPreview = output.count > 600 ? String(output.prefix(600)) : output
        var nlCount = 1
        for ch in output.utf8 where ch == 10 {
            nlCount += 1
            if nlCount >= 350 { break }
        }
        self.outputLineCount = nlCount
        
        // Only compress large tool outputs (> 16KB) so normal UI rendering never incurs LZFSE decompression overhead
        if output.utf8.count > 16384, let comp = StateCompressionEngine.compressString(output) {
            self.compressedOutput = comp
            self.rawOutput = nil
        } else {
            self.rawOutput = output
            self.compressedOutput = nil
        }
    }
}

struct PendingChangeModel: Identifiable, Equatable {
    let id: String
    let filePath: String
    let description: String
    let additions: Int
    let deletions: Int
    private let rawOldContent: String?
    private let compressedOldContent: Data?
    private let rawNewContent: String?
    private let compressedNewContent: Data?
    var status: PendingChangeStatus
    
    var oldContent: String {
        if let raw = rawOldContent { return raw }
        if let comp = compressedOldContent, let decomp = StateCompressionEngine.decompressString(comp) {
            return decomp
        }
        return ""
    }
    
    var newContent: String {
        if let raw = rawNewContent { return raw }
        if let comp = compressedNewContent, let decomp = StateCompressionEngine.decompressString(comp) {
            return decomp
        }
        return ""
    }
    
    init(id: String, filePath: String, description: String, additions: Int, deletions: Int, oldContent: String, newContent: String, status: PendingChangeStatus) {
        self.id = id
        self.filePath = filePath
        self.description = description
        self.additions = additions
        self.deletions = deletions
        self.status = status
        
        if oldContent.utf8.count > 16384, let comp = StateCompressionEngine.compressString(oldContent) {
            self.compressedOldContent = comp
            self.rawOldContent = nil
        } else {
            self.rawOldContent = oldContent
            self.compressedOldContent = nil
        }
        
        if newContent.utf8.count > 16384, let comp = StateCompressionEngine.compressString(newContent) {
            self.compressedNewContent = comp
            self.rawNewContent = nil
        } else {
            self.rawNewContent = newContent
            self.compressedNewContent = nil
        }
    }
    
    static func == (lhs: PendingChangeModel, rhs: PendingChangeModel) -> Bool {
        return lhs.id == rhs.id &&
               lhs.filePath == rhs.filePath &&
               lhs.status == rhs.status &&
               lhs.additions == rhs.additions &&
               lhs.deletions == rhs.deletions &&
               lhs.rawOldContent == rhs.rawOldContent &&
               lhs.compressedOldContent == rhs.compressedOldContent &&
               lhs.rawNewContent == rhs.rawNewContent &&
               lhs.compressedNewContent == rhs.compressedNewContent
    }
    
    enum PendingChangeStatus: Equatable {
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

struct QueuedMessage: Identifiable {
    let id = UUID()
    let text: String
    let attachments: [AIAttachment]
    let timestamp = Date()
}

extension Notification.Name {
    static let agentProcessQueueItem = Notification.Name("agentProcessQueueItem")
}
