//
//  BackgroundAgentService.swift
//  MicroCode
//
//  Feature 9: Background Agent — Persistent autonomous agent that watches for
//  file changes, build errors, and proactively suggests or applies fixes.
//  Uses FSEvents for file watching and integrates with SubAgentHarness.
//  Tirawat Nantamas Founder and CEO of Dotmini Software.
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import Foundation
import Combine

// MARK: - Background Agent Task

struct BackgroundAgentTask: Identifiable {
    let id: String
    let trigger: BackgroundTrigger
    let description: String
    let createdAt: Date
    var status: BackgroundTaskStatus
    var result: String?
    
    enum BackgroundTaskStatus: String {
        case queued = "Queued"
        case running = "Running"
        case completed = "Completed"
        case failed = "Failed"
        case dismissed = "Dismissed"
    }
}

enum BackgroundTrigger: String {
    case fileChange = "File Changed"
    case buildError = "Build Error"
    case diagnosticError = "LSP Error"
    case runtimeError = "Runtime Error"
    case manual = "Manual"
    case schedule = "Scheduled"
    case longHorizon = "Long Horizon"
}

// MARK: - Background Agent Configuration

struct BackgroundAgentConfig {
    var enabled: Bool = false
    var watchForFileChanges: Bool = true
    var watchForBuildErrors: Bool = true
    var watchForDiagnostics: Bool = true
    var autoFixEnabled: Bool = false  // Requires user approval by default
    var maxConcurrentTasks: Int = 2
    var debounceSeconds: Double = 3.0
    var ignoredPatterns: [String] = [
        ".git", ".build", "node_modules", ".DS_Store",
        "*.o", "*.pyc", "__pycache__", ".swp", "*.lock"
    ]
}

// MARK: - Background Agent Service

@MainActor
class BackgroundAgentService: ObservableObject {
    
    static let shared = BackgroundAgentService()
    
    @Published var config = BackgroundAgentConfig()
    @Published var taskQueue: [BackgroundAgentTask] = []
    @Published var isWatching: Bool = false
    @Published var recentLogs: [String] = []
    @Published var stats = BackgroundAgentStats()
    
    struct BackgroundAgentStats {
        var filesWatched: Int = 0
        var errorsDetected: Int = 0
        var fixesApplied: Int = 0
        var tasksFailed: Int = 0
        var uptime: TimeInterval = 0
    }
    
    // FSEvents stream
    private var eventStream: FSEventStreamRef?
    private var watchedPath: String?
    private var startTime: Date?
    
    // Debounce tracking
    private var pendingChanges: [String: Date] = [:]
    private var debounceTask: Task<Void, Never>?
    
    // Diagnostic monitoring
    private var diagnosticCancellable: AnyCancellable?
    private var previousDiagnosticErrors: [String: Int] = [:]
    
    // Running tasks
    private var activeTasks: [String: Task<Void, Never>] = [:]
    
    private init() {}
    
    // MARK: - Lifecycle
    
    func startWatching(path: String) {
        guard !isWatching else {
            log("Already watching \(path)")
            return
        }
        
        watchedPath = path
        startTime = Date()
        
        // Start file system watcher
        startFSEvents(path: path)
        
        // Start diagnostic monitor
        startDiagnosticMonitor()
        
        isWatching = true
        log("🟢 Background Agent started watching: \(path)")
    }
    
    func stopWatching() {
        stopFSEvents()
        stopDiagnosticMonitor()
        
        // Cancel all active tasks
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
        debounceTask?.cancel()
        
        isWatching = false
        if let start = startTime {
            stats.uptime += Date().timeIntervalSince(start)
        }
        startTime = nil
        log("🔴 Background Agent stopped")
    }
    
    func toggleWatching(path: String) {
        if isWatching {
            stopWatching()
        } else {
            startWatching(path: path)
        }
    }
    
    // MARK: - FSEvents File Watching
    
    private func startFSEvents(path: String) {
        let pathsToWatch = [path as CFString] as CFArray
        
        var context = FSEventStreamContext()
        // Store a raw pointer to self for the callback
        context.info = Unmanaged.passUnretained(self).toOpaque()
        
        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )
        
        eventStream = FSEventStreamCreate(
            nil,
            { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                guard let info = clientCallBackInfo else { return }
                let service = Unmanaged<BackgroundAgentService>.fromOpaque(info).takeUnretainedValue()
                
                guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                
                Task { @MainActor in
                    service.handleFileEvents(paths: paths)
                }
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // latency in seconds
            flags
        )
        
        if let stream = eventStream {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(stream)
            stats.filesWatched += 1
        }
    }
    
    private func stopFSEvents() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }
    
    private func handleFileEvents(paths: [String]) {
        guard config.enabled, config.watchForFileChanges else { return }
        
        let now = Date()
        var relevantChanges: [String] = []
        
        for path in paths {
            // Skip ignored patterns
            if shouldIgnore(path: path) { continue }
            
            // Skip non-source files
            guard isSourceFile(path) else { continue }
            
            // Debounce: skip if already processed recently
            if let lastChange = pendingChanges[path],
               now.timeIntervalSince(lastChange) < config.debounceSeconds {
                continue
            }
            
            pendingChanges[path] = now
            relevantChanges.append(path)
        }
        
        guard !relevantChanges.isEmpty else { return }
        
        // Debounce batch processing
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(config.debounceSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.processFileChanges(relevantChanges)
        }
    }
    
    private func processFileChanges(_ paths: [String]) {
        let changedFiles = paths.map { URL(fileURLWithPath: $0).lastPathComponent }
        log("📝 Files changed: \(changedFiles.joined(separator: ", "))")
        
        // Check if changed files have diagnostics
        for path in paths {
            let uri = URL(fileURLWithPath: path).absoluteString
            if let diags = LSPManager.shared.fileDiagnostics[uri] {
                let errors = diags.filter { $0.severity == 1 }
                if !errors.isEmpty {
                    enqueueTask(
                        trigger: .fileChange,
                        description: "Analyze \(errors.count) error(s) in \(URL(fileURLWithPath: path).lastPathComponent) after file change"
                    )
                }
            }
        }
    }
    
    // MARK: - Diagnostic Monitoring
    
    private func startDiagnosticMonitor() {
        guard config.watchForDiagnostics else { return }
        
        diagnosticCancellable = LSPManager.shared.$fileDiagnostics
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] diagnostics in
                self?.handleDiagnosticsUpdate(diagnostics)
            }
    }
    
    private func stopDiagnosticMonitor() {
        diagnosticCancellable?.cancel()
        diagnosticCancellable = nil
    }
    
    private func handleDiagnosticsUpdate(_ diagnostics: [String: [LSPDiagnostic]]) {
        guard config.enabled, config.watchForDiagnostics else { return }
        
        for (uri, diags) in diagnostics {
            let errors = diags.filter { $0.severity == 1 }
            let currentErrorCount = errors.count
            let previousCount = previousDiagnosticErrors[uri] ?? 0
            
            // New errors appeared
            if currentErrorCount > previousCount {
                let newErrors = currentErrorCount - previousCount
                let fileName = URL(string: uri)?.lastPathComponent ?? uri
                stats.errorsDetected += newErrors
                
                enqueueTask(
                    trigger: .diagnosticError,
                    description: "Investigate \(newErrors) new error(s) in \(fileName)"
                )
            }
            
            previousDiagnosticErrors[uri] = currentErrorCount
        }
    }
    
    // MARK: - Build Error Watching
    
    func reportBuildError(output: String, command: String) {
        guard config.enabled, config.watchForBuildErrors else { return }
        
        stats.errorsDetected += 1
        enqueueTask(
            trigger: .buildError,
            description: "Analyze build failure: \(command.prefix(60))..."
        )
    }
    
    // MARK: - Task Queue
    
    func enqueueTask(trigger: BackgroundTrigger, description: String) {
        // Check if similar task already queued
        let isDuplicate = taskQueue.contains { task in
            task.status == .queued && task.description == description
        }
        guard !isDuplicate else { return }
        
        // Enforce max queue size
        while taskQueue.filter({ $0.status == .queued }).count >= 10 {
            if let idx = taskQueue.firstIndex(where: { $0.status == .queued }) {
                taskQueue[idx].status = .dismissed
            }
        }
        
        let task = BackgroundAgentTask(
            id: UUID().uuidString,
            trigger: trigger,
            description: description,
            createdAt: Date(),
            status: .queued
        )
        taskQueue.append(task)
        log("📋 Task queued: \(description)")
        
        // Auto-process if under limit
        processNextTask()
    }
    
    private func processNextTask() {
        let runningCount = activeTasks.count
        guard runningCount < config.maxConcurrentTasks else { return }
        
        guard let taskIndex = taskQueue.firstIndex(where: { $0.status == .queued }) else { return }
        
        taskQueue[taskIndex].status = .running
        let bgTask = taskQueue[taskIndex]
        
        let swiftTask = Task { @MainActor in
            await executeBackgroundTask(bgTask)
        }
        activeTasks[bgTask.id] = swiftTask
    }
    
    private func executeBackgroundTask(_ bgTask: BackgroundAgentTask) async {
        log("🔄 Executing: \(bgTask.description)")
        
        // Build a prompt based on the trigger
        let prompt: String
        switch bgTask.trigger {
        case .buildError:
            prompt = """
            [Background Agent] A build error was detected. Analyze the error and suggest a fix.
            Task: \(bgTask.description)
            Instructions: Read the relevant file(s), identify the root cause, and if auto-fix is enabled, apply the fix. Otherwise, provide a clear explanation of the issue and suggested solution.
            """
        case .diagnosticError:
            prompt = """
            [Background Agent] New LSP diagnostic errors were detected.
            Task: \(bgTask.description)
            Instructions: Use lsp_diagnostics to check the current errors, read the source file to understand the context, and suggest or apply fixes. Focus on compilation errors first, then warnings.
            """
        case .fileChange:
            prompt = """
            [Background Agent] File changes detected with errors.
            Task: \(bgTask.description)
            Instructions: Check the file diagnostics, analyze the errors that appeared after the change, and provide a fix suggestion.
            """
        case .manual:
            prompt = """
            [Background Agent] Manual task requested.
            Task: \(bgTask.description)
            """
        case .schedule:
            prompt = """
            [Background Agent] Scheduled task.
            Task: \(bgTask.description)
            """
        case .runtimeError:
            prompt = """
            [Background Agent] A runtime error was detected.
            Task: \(bgTask.description)
            Instructions: Analyze the runtime error, identify the root cause from the stack trace, and suggest a fix. If auto-fix is enabled, apply the fix directly.
            """
        case .longHorizon:
            prompt = """
            [Background Agent] Long-horizon task checkpoint.
            Task: \(bgTask.description)
            Instructions: Continue the multi-step coding task from the last checkpoint. Execute the next subtask in the plan.
            """
        }
        
        do {
            // Use SubAgentHarness to spawn a background sub-agent
            let harness = SubAgentHarness.shared
            let instance = try await harness.invokeSubagent(
                typeName: "bug_hunter",
                role: "Background Agent",
                prompt: prompt,
                workspacePath: watchedPath,
                preferredModel: nil,
                apiKey: nil
            )
            
            // Wait for completion (with timeout)
            let timeout: UInt64 = 120_000_000_000 // 2 minutes
            let startTime = Date()
            
            while true {
                if Task.isCancelled { break }
                
                // Check if sub-agent completed
                if let sub = harness.activeSubagents.first(where: { $0.id == instance.id }) {
                    if sub.state == .completed || sub.state == .killed || sub.state == .errored {
                        if let idx = taskQueue.firstIndex(where: { $0.id == bgTask.id }) {
                            taskQueue[idx].status = sub.state == .completed ? .completed : .failed
                            taskQueue[idx].result = sub.finalReport
                        }
                        if sub.state == .completed {
                            stats.fixesApplied += 1
                            log("✅ Completed: \(bgTask.description)")
                        } else {
                            stats.tasksFailed += 1
                            log("❌ Failed: \(bgTask.description)")
                        }
                        break
                    }
                }
                
                // Timeout check
                if Date().timeIntervalSince(startTime) > Double(timeout) / 1_000_000_000 {
                    harness.killSubagent(id: instance.id)
                    if let idx = taskQueue.firstIndex(where: { $0.id == bgTask.id }) {
                        taskQueue[idx].status = .failed
                        taskQueue[idx].result = "Task timed out after 2 minutes"
                    }
                    stats.tasksFailed += 1
                    log("⏰ Timeout: \(bgTask.description)")
                    break
                }
                
                try? await Task.sleep(nanoseconds: 500_000_000) // Check every 500ms
            }
        } catch {
            if let idx = taskQueue.firstIndex(where: { $0.id == bgTask.id }) {
                taskQueue[idx].status = .failed
                taskQueue[idx].result = error.localizedDescription
            }
            stats.tasksFailed += 1
            log("❌ Error: \(error.localizedDescription)")
        }
        
        activeTasks.removeValue(forKey: bgTask.id)
        
        // Process next queued task
        processNextTask()
    }
    
    // MARK: - Task Management
    
    func dismissTask(id: String) {
        if let idx = taskQueue.firstIndex(where: { $0.id == id }) {
            taskQueue[idx].status = .dismissed
        }
    }
    
    func clearCompletedTasks() {
        taskQueue.removeAll { $0.status == .completed || $0.status == .dismissed || $0.status == .failed }
    }
    
    func retryTask(id: String) {
        guard let idx = taskQueue.firstIndex(where: { $0.id == id }) else { return }
        let task = taskQueue[idx]
        enqueueTask(trigger: task.trigger, description: task.description)
    }
    
    // MARK: - Status
    
    func getStatusSummary() -> String {
        var output = "Background Agent Status:\n\n"
        output += "• State: \(isWatching ? "🟢 Watching" : "⚫ Stopped")\n"
        
        if let path = watchedPath {
            output += "• Path: \(path)\n"
        }
        
        if let start = startTime {
            let elapsed = Date().timeIntervalSince(start)
            let hours = Int(elapsed) / 3600
            let minutes = (Int(elapsed) % 3600) / 60
            output += "• Uptime: \(hours)h \(minutes)m\n"
        }
        
        output += "\n📊 Statistics:\n"
        output += "  Errors detected: \(stats.errorsDetected)\n"
        output += "  Fixes applied: \(stats.fixesApplied)\n"
        output += "  Tasks failed: \(stats.tasksFailed)\n"
        
        let queued = taskQueue.filter { $0.status == .queued }.count
        let running = taskQueue.filter { $0.status == .running }.count
        let completed = taskQueue.filter { $0.status == .completed }.count
        output += "\n📋 Task Queue: \(queued) queued, \(running) running, \(completed) completed\n"
        
        if !taskQueue.isEmpty {
            output += "\nRecent Tasks:\n"
            for task in taskQueue.suffix(5) {
                let icon: String
                switch task.status {
                case .queued: icon = "⏳"
                case .running: icon = "🔄"
                case .completed: icon = "✅"
                case .failed: icon = "❌"
                case .dismissed: icon = "🚫"
                }
                output += "  \(icon) [\(task.trigger.rawValue)] \(task.description)\n"
            }
        }
        
        return output
    }
    
    // MARK: - Helpers
    
    private func shouldIgnore(path: String) -> Bool {
        for pattern in config.ignoredPatterns {
            if pattern.hasPrefix("*.") {
                let ext = "." + pattern.dropFirst(2)
                if path.hasSuffix(ext) { return true }
            } else if path.contains("/\(pattern)/") || path.hasSuffix("/\(pattern)") {
                return true
            }
        }
        return false
    }
    
    private func isSourceFile(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let sourceExtensions = [
            "swift", "rs", "py", "js", "ts", "tsx", "jsx",
            "go", "java", "kt", "cpp", "c", "h", "hpp",
            "rb", "dart", "php", "cs", "m", "mm",
            "html", "css", "json", "yaml", "yml", "toml",
            "ar" // Ardium
        ]
        return sourceExtensions.contains(ext)
    }
    
    private func log(_ msg: String) {
        let entry = "[\(Date().formatted(date: .omitted, time: .standard))] \(msg)"
        recentLogs.append(entry)
        if recentLogs.count > 200 {
            recentLogs.removeFirst()
        }
        print("🤖 [BackgroundAgent] \(msg)")
    }
}

// MARK: - Agent Tools for Background Agent

struct BackgroundAgentControlTool: AgentTool {
    let name = "background_agent"
    let description = "Control the Background Agent that watches for file changes, build errors, and diagnostics. Can start/stop watching, check status, enqueue manual tasks, or configure behavior."
    let parameters = [
        ToolParameter(name: "action", type: "string", description: "Action: 'start', 'stop', 'status', 'enqueue', 'config'", required: true),
        ToolParameter(name: "path", type: "string", description: "Workspace path (required for 'start')", required: false),
        ToolParameter(name: "task", type: "string", description: "Task description (required for 'enqueue')", required: false),
        ToolParameter(name: "auto_fix", type: "boolean", description: "Enable auto-fix mode (for 'config')", required: false),
        ToolParameter(name: "watch_files", type: "boolean", description: "Watch for file changes (for 'config')", required: false),
        ToolParameter(name: "watch_builds", type: "boolean", description: "Watch for build errors (for 'config')", required: false),
        ToolParameter(name: "watch_diagnostics", type: "boolean", description: "Watch for LSP diagnostics (for 'config')", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let action = params["action"] as? String else {
            throw ToolBoxError.invalidParams("Missing 'action'")
        }
        
        switch action.lowercased() {
        case "start":
            guard let path = params["path"] as? String else {
                throw ToolBoxError.invalidParams("Missing 'path' for start action")
            }
            return await MainActor.run {
                let service = BackgroundAgentService.shared
                service.config.enabled = true
                service.startWatching(path: path)
                return "Background Agent started watching: \(path)"
            }
            
        case "stop":
            return await MainActor.run {
                let service = BackgroundAgentService.shared
                service.stopWatching()
                service.config.enabled = false
                return "Background Agent stopped."
            }
            
        case "status":
            return await MainActor.run {
                return BackgroundAgentService.shared.getStatusSummary()
            }
            
        case "enqueue":
            guard let task = params["task"] as? String else {
                throw ToolBoxError.invalidParams("Missing 'task' for enqueue action")
            }
            return await MainActor.run {
                BackgroundAgentService.shared.enqueueTask(trigger: .manual, description: task)
                return "Task enqueued: \(task)"
            }
            
        case "config":
            let autoFix = params["auto_fix"] as? Bool
            let watchFiles = params["watch_files"] as? Bool
            let watchBuilds = params["watch_builds"] as? Bool
            let watchDiags = params["watch_diagnostics"] as? Bool
            
            return await MainActor.run {
                let service = BackgroundAgentService.shared
                if let v = autoFix { service.config.autoFixEnabled = v }
                if let v = watchFiles { service.config.watchForFileChanges = v }
                if let v = watchBuilds { service.config.watchForBuildErrors = v }
                if let v = watchDiags { service.config.watchForDiagnostics = v }
                
                var output = "Background Agent Configuration Updated:\n"
                output += "  Auto-fix: \(service.config.autoFixEnabled ? "ON" : "OFF")\n"
                output += "  Watch files: \(service.config.watchForFileChanges ? "ON" : "OFF")\n"
                output += "  Watch builds: \(service.config.watchForBuildErrors ? "ON" : "OFF")\n"
                output += "  Watch diagnostics: \(service.config.watchForDiagnostics ? "ON" : "OFF")\n"
                output += "  Max concurrent: \(service.config.maxConcurrentTasks)\n"
                output += "  Debounce: \(service.config.debounceSeconds)s\n"
                return output
            }
            
        default:
            throw ToolBoxError.invalidParams("Unknown action '\(action)'. Use: start, stop, status, enqueue, config")
        }
    }
}
