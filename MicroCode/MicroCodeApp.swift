//
//  MicroCodeApp.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2024 Dotmini Company Limited. All rights reserved.
//
//  Performance Optimized Entry Point
//

import SwiftUI
import AppKit
import UserNotifications

@main
struct MicroCodeApp: App {
    // Core delegates
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Core state - Initialized lazily where possible inside AppState
    @StateObject private var appState = AppState()
    
    // Services (non-observed reference so memory telemetry never invalidates the root WindowGroup)
    private let performanceManager = PerformanceManager.shared

    init() {
        // Install crash/error capture as early as possible so Swift traps,
        // signals and exceptions during startup are recorded too.
        CrashReporter.shared.install()
        CrashReporter.shared.breadcrumb("MicroCodeApp.init")
        
        // Launch ACP 1.0 JSON-RPC stdio server when invoked with `--acp-server`
        let args = CommandLine.arguments
        if args.contains("--acp-server") {
            let wsIdx = args.firstIndex(of: "--workspace")
            let workspacePath: String
            if let idx = wsIdx, idx + 1 < args.count {
                workspacePath = args[idx + 1]
            } else {
                workspacePath = FileManager.default.currentDirectoryPath
            }
            Task { @MainActor in
                ACPServerService.shared.startServing(workspacePath: workspacePath)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .ignoresSafeArea(.all, edges: .top)
                .frame(minWidth: 1200, minHeight: 800)
                .preferredColorScheme(appState.appTheme.colorScheme)
                .onAppear {
                    // Critical: Perform window setup on main thread
                    setupWindow()
                    
                    // Activate Idle State Compactor for <= 50MB RAM management
                    IdleStateCompactor.shared.startMonitoring()
                    
                    // Defer heavy non-critical setup to background
                    Task.detached(priority: .background) {
                        await performBackgroundStartup()
                    }
                    
                    // Handle any files/folders passed via CLI or open -a MicroCode before view appeared
                    for url in appDelegate.consumePendingOpenURLs() {
                        handleIncomingDeepLink(url)
                    }
                    let args = Array(CommandLine.arguments.dropFirst())
                    if !args.contains("--acp-server") {
                        var skipNext = false
                        for arg in args {
                            if skipNext { skipNext = false; continue }
                            if arg == "-NSDocumentRevisionsDebugMode" || arg == "-ApplePersistenceIgnoreState" {
                                skipNext = true
                                continue
                            }
                            guard !arg.hasPrefix("-") else { continue }
                            let expanded = (arg as NSString).expandingTildeInPath
                            if FileManager.default.fileExists(atPath: expanded) {
                                openLocalFileOrFolder(URL(fileURLWithPath: expanded))
                                break
                            }
                        }
                    }
                }
                .onOpenURL { url in
                    handleIncomingDeepLink(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MicroCodeOAuthCallback"))) { notification in
                    if let url = notification.object as? URL {
                        handleIncomingDeepLink(url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeOpenOmniAISnippet"))) { notif in
                    if let info = notif.userInfo,
                       let code = info["code"] as? String {
                        let lang = info["language"] as? String ?? "swift"
                        let shouldRun = info["shouldRun"] as? Bool ?? true
                        appState.openSnippetFromOmniAI(code: code, language: lang, shouldRun: shouldRun)
                    }
                }
                .onChange(of: appState.appTheme) { _ in
                    setupWindow()
                }
                .handlesExternalEvents(preferring: Set(arrayLiteral: "*"), allowing: Set(arrayLiteral: "*"))
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        .windowStyle(.hiddenTitleBar)
        .commands {
            // ... (Menu commands remain same, omitted for brevity in optimization view)
            AppCommands(appState: appState)
        }

    }

    private func setupWindow() {
        if let window = NSApplication.shared.windows.first {
            window.toolbar = nil
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)
            
            // Dynamic transparency based on theme
            let isTransparent = appState.appTheme.isGlass
            window.backgroundColor = isTransparent ? .clear : appState.appTheme.workspaceBackground
            window.isOpaque = !isTransparent
            window.hasShadow = true
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    private func performBackgroundStartup() async {
        // Stagger background warmup to allow cold-launch first frame to stay under 50MB RAM
        Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s deferral
            
            _ = PreviewService.shared
            _ = AuthService.shared
            _ = AutoHealerService.shared
            _ = LocalEcosystemDiscovery.shared
            
            // Background refresh of live models & local ecosystem engines
            await AIModelCatalog.shared.refreshIfNeeded(force: false)
            await MainActor.run {
                // Start Local MCP & HTTP Daemon Bridge for Omni AI
                MCPServer.shared.startLocalHttpBridge(port: 18888)
                TelemetryService.shared.start()
            }
        }
        
        // A license must be issued and signed by Dotmini's entitlement service.
        // Never manufacture mc_live_* values locally: they look valid in the UI
        // but fail at the gateway and leave the user in a false signed-in state.
        let defaults = UserDefaults.standard
        // v2 account migration: values in these UserDefaults keys used to be
        // Firebase ID tokens. A Supabase session lives in Keychain, so clear
        // the old credentials once instead of sending them to the new gateway.
        if !defaults.bool(forKey: "supabaseSessionMigrationV1Complete") {
            ["cloudGPUAuthToken", "cloudGPURefreshToken", "microRentToken", "dotminiLicenseKey"].forEach {
                defaults.removeObject(forKey: $0)
            }
            defaults.set(true, forKey: "supabaseSessionMigrationV1Complete")
        }
        let currentLicense = defaults.string(forKey: "dotminiLicenseKey") ?? ""
        if currentLicense.hasPrefix("mc_live_auto_") ||
            currentLicense.hasPrefix("mc_live_free_") ||
            currentLicense.hasPrefix("mc_live_pro_") ||
            currentLicense == "mc_live_admin_tirawatnantamas" {
            defaults.removeObject(forKey: "dotminiLicenseKey")
            print("Removed a legacy locally-generated license label")
        }
        
        // Log startup
        ReportLogManager.shared.log("App Started & Omni AI Local Bridge Initialized on Port 18888", type: .info)
        
        // Log startup performance
        await performanceManager.runOnECore {
            print("🚀 App Startup: Background services and Omni AI Bridge warmed up")
        }
    }
    
    // MARK: - Omni AI & Deep Link Integration
    
    private func handleIncomingDeepLink(_ url: URL) {
        NSApp.activate(ignoringOtherApps: true)

        if url.isFileURL {
            openLocalFileOrFolder(url)
            return
        }

        // Supabase OAuth uses the app URL scheme. Its browser callback carries
        // real access/refresh tokens; do not treat it as a human license key.
        if url.scheme?.lowercased() == "microcode", url.host?.lowercased() == "auth" {
            Task { @MainActor in
                guard await SupabaseAuthService.shared.handleCallback(url) else { return }
                let session = SupabaseAuthService.shared.session
                appState.syncGoogleOrDotminiAccount(
                    email: session?.email ?? "",
                    token: session?.accessToken ?? "",
                    displayName: session?.email.components(separatedBy: "@").first ?? "User"
                )
                TelemetryService.shared.record(name: "account_signed_in")
                TelemetryService.shared.flush()
                NotificationCenter.default.post(name: NSNotification.Name("MicroCodeAccountLoggedIn"), object: nil)
            }
            return
        }
        
        // Google Colab Cloud GPU Deep Link (e.g. microcode://colab?endpoint=https://...&token=mc_...)
        if (url.scheme?.lowercased() == "microcode" || url.scheme?.lowercased() == "codetuner"),
           (url.host?.lowercased() == "colab" || url.host?.lowercased() == "colab-connect" || url.host?.lowercased() == "colab_connect") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
                let queryItems = components.queryItems ?? []
                let endpoint = queryItems.first(where: { $0.name.lowercased() == "endpoint" || $0.name.lowercased() == "url" })?.value ?? ""
                let token = queryItems.first(where: { $0.name.lowercased() == "token" })?.value ?? ""
                Task { @MainActor in
                    await GoogleColabService.shared.connectToColab(endpoint: endpoint, token: token)
                    AppState.shared?.currentComputeTarget = .googleColab
                }
            }
            return
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }
        let host = components.host ?? url.path
        let queryItems = components.queryItems ?? []
        
        func queryValue(for key: String) -> String? {
            return queryItems.first(where: { $0.name.lowercased() == key.lowercased() })?.value
        }
        
        // Account identity is accepted only through the correlated Supabase
        // authorization-code callback above. Legacy snippet links cannot sign in.

        // Universal Preview Dock Deep Link
        if host == "preview" || host == "preview_dock" || host == "preview-dock" {
            if let path = queryValue(for: "path"), !path.isEmpty {
                let fileURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                Task { @MainActor in
                    PreviewDockService.shared.openFile(url: fileURL, makeActive: true)
                }
            } else if let tab = queryValue(for: "tab"), !tab.isEmpty {
                Task { @MainActor in
                    appState.showPreviewInspector(tab: tab)
                }
            } else {
                Task { @MainActor in
                    appState.showPreviewInspector()
                }
            }
            return
        }
        
        // Universal Agent & Ecosystem Settings Deep Link
        if host == "ecosystem" || host == "agent-settings" || host == "agent-config" || host == "rules" || host == "mcp" {
            let tab = queryValue(for: "tab") ?? (host == "rules" ? "rules" : (host == "mcp" ? "mcp" : "agents"))
            NotificationCenter.default.post(name: NSNotification.Name("MicroCode.OpenAgentEcosystem"), object: tab)
            return
        }
        
        // Extension Studio Deep Link
        if host == "extensions" || host == "extension-studio" {
            Task { @MainActor in
                appState.openExtensionStudio()
            }
            return
        }
        
        // Code Execution / Open
        if host == "open" || host == "run" || host == "playground" || host.contains("snippet") {
            if let path = queryValue(for: "path"), !path.isEmpty {
                let expanded = (path as NSString).expandingTildeInPath
                openLocalFileOrFolder(URL(fileURLWithPath: expanded))
                return
            }
            var rawCode = queryValue(for: "code") ?? ""
            if let b64 = queryValue(for: "base64"), let data = Data(base64Encoded: b64), let decoded = String(data: data, encoding: .utf8) {
                rawCode = decoded
            }
            
            let language = queryValue(for: "lang") ?? queryValue(for: "language") ?? "swift"
            let action = queryValue(for: "action") ?? (host == "run" ? "run" : "open")
            let shouldRun = (action == "run" || action == "open_and_run" || host == "run")
            
            if !rawCode.isEmpty {
                appState.openSnippetFromOmniAI(code: rawCode, language: language, shouldRun: shouldRun)
            }
        }
    }

    private func openLocalFileOrFolder(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        if isDir.boolValue {
            Task { @MainActor in
                await appState.openWorkspace(url: url)
                AgentService.shared.setWorkspace(url.path)
            }
        } else {
            let parentDir = url.deletingLastPathComponent()
            Task { @MainActor in
                if appState.workspaceFolder == nil {
                    await appState.openWorkspace(url: parentDir)
                    AgentService.shared.setWorkspace(parentDir.path)
                }
                await appState.loadFile(url: url)
            }
        }
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var signalSources: [DispatchSourceSignal] = []
    private var windowObserver: NSObjectProtocol?
    private weak var mainWorkspaceWindow: NSWindow?
    private var pendingOpenURLs: [URL] = []
    private var hasConsumedInitialOpenURLs = false

    func consumePendingOpenURLs() -> [URL] {
        hasConsumedInitialOpenURLs = true
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        return urls
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if !hasConsumedInitialOpenURLs {
                pendingOpenURLs.append(url)
            }
            NotificationCenter.default.post(name: Notification.Name("MicroCodeOAuthCallback"), object: url)
        }
    }

    var isAnyAITaskRunning: Bool {
        AgentService.shared.isLoading ||
        AgentService.shared.isProcessingQueue ||
        AIClient.shared.isStreaming ||
        ACPHostService.shared.isAnySessionRunning
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Optimization: Don't block main thread with heavy inits here
        CrashReporter.shared.install() // idempotent backstop
        CrashReporter.shared.breadcrumb("applicationDidFinishLaunching")

        // Configure appearance and bring window to front
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate(ignoringOtherApps: true)

        // Request user notification permission softly for background AI completion alerts
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        // Attach window delegate to primary workspace windows so closing the window (Cmd+W / red close button)
        // hides the window instead of destroying the view hierarchy or killing in-flight AI work.
        attachWindowDelegates()
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self, let win = note.object as? NSWindow else { return }
            self.configureManagedWindow(win)
        }

        // applicationWillTerminate is NOT called on SIGTERM/SIGINT (e.g. a
        // `kill`, IDE stop, logout). Trap them so we still reap the backend
        // instead of leaving a re-parented CPU-spinning orphan.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN) // disable default termination; let the source run
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                ReportLogManager.shared.log("Signal \(sig) — flushing AI checkpoints and stopping backend", type: .info)
                MainActor.assumeIsolated {
                    AgentService.shared.saveChats()
                    AgentService.shared.saveArx()
                    UserDefaults.standard.synchronize()
                    DeviceRuntimeService.shared.shutdownAllRuntimes()
                }
                BackendService.shared.stopBackend()
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
    }

    private func attachWindowDelegates() {
        for win in NSApp.windows {
            configureManagedWindow(win)
        }
    }

    private func configureManagedWindow(_ window: NSWindow) {
        // Only manage standard titled document/workspace windows (not panels, popovers, or sheets)
        guard window.styleMask.contains(.titled),
              window.styleMask.contains(.closable),
              !(window is NSPanel),
              window.sheetParent == nil else { return }
        if mainWorkspaceWindow == nil {
            mainWorkspaceWindow = window
        }
        if window.delegate !== self {
            window.delegate = self
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Keep the main workspace window alive in memory by hiding it instead of destroying it.
        // This guarantees any active AI streaming / tool execution continues uninterrupted in the background,
        // and reopening from the Dock restores the exact live UI state immediately.
        mainWorkspaceWindow = sender
        sender.orderOut(nil)
        if isAnyAITaskRunning {
            NSApp.dockTile.badgeLabel = "AI"
            AgentService.shared.postBackgroundStatusNotification(
                title: "MicroCode AI กำลังทำงานต่อเบื้องหลัง",
                body: "หน้าต่างถูกซ่อนไว้โดยไม่ตัดการทำงานของ AI คลิกไอคอน MicroCode บน Dock เพื่อกลับมาดูผลลัพธ์ได้ตลอดเวลา"
            )
        }
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.dockTile.badgeLabel = isAnyAITaskRunning ? "AI" : nil
        if !flag {
            if let win = mainWorkspaceWindow {
                win.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return false
            }
            for win in sender.windows where win.styleMask.contains(.titled) && !(win is NSPanel) {
                win.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return false
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ReportLogManager.shared.log("App Terminating", type: .info)
        AgentService.shared.saveChats()
        AgentService.shared.saveArx()
        DeviceRuntimeService.shared.shutdownAllRuntimes()
        // Stop backend server
        BackendService.shared.stopBackend()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isAnyAITaskRunning && !AgentService.shared.shouldTerminateAfterBackgroundCompletion {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "AI Agent กำลังทำงานอยู่เบื้องหลัง"
            alert.informativeText = "ขณะนี้ AI กำลังประมวลผลหรือแก้ไขโค้ดอยู่ คุณต้องการซ่อนหน้าต่างเพื่อให้ AI ทำงานต่อเบื้องหลังจนเสร็จแบบไม่ตัดจบ หรือต้องการบันทึก Checkpoint แล้วปิดแอปทันที?"
            alert.addButton(withTitle: "ทำงานต่อเบื้องหลัง (ซ่อนหน้าต่าง)")
            alert.addButton(withTitle: "ทำจนเสร็จแล้วปิดแอปอัตโนมัติ")
            alert.addButton(withTitle: "บันทึก Checkpoint แล้วปิดทันที")
            alert.addButton(withTitle: "ยกเลิก")

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                // Hide windows and continue running in background
                for win in sender.windows where win.isVisible && !(win is NSPanel) {
                    if mainWorkspaceWindow == nil { mainWorkspaceWindow = win }
                    win.orderOut(nil)
                }
                NSApp.dockTile.badgeLabel = "AI"
                AgentService.shared.postBackgroundStatusNotification(
                    title: "MicroCode AI กำลังทำงานต่อเบื้องหลัง",
                    body: "ระบบจะแจ้งเตือนเมื่อ AI ทำงานเสร็จสิ้น"
                )
                return .terminateCancel

            case .alertSecondButtonReturn:
                // Hide windows, let AI finish its current task + queue, then auto-quit
                AgentService.shared.shouldTerminateAfterBackgroundCompletion = true
                for win in sender.windows where win.isVisible && !(win is NSPanel) {
                    if mainWorkspaceWindow == nil { mainWorkspaceWindow = win }
                    win.orderOut(nil)
                }
                NSApp.dockTile.badgeLabel = "AI"
                AgentService.shared.postBackgroundStatusNotification(
                    title: "MicroCode AI จะปิดแอปอัตโนมัติเมื่อทำเสร็จ",
                    body: "ระบบกำลังทำงานต่อเบื้องหลังและจะบันทึกข้อมูลก่อนปิดแอปให้อัตโนมัติ"
                )
                return .terminateCancel

            case .alertThirdButtonReturn:
                // Flush checkpoints and terminate now
                AgentService.shared.saveChats()
                AgentService.shared.saveArx()
                DeviceRuntimeService.shared.shutdownAllRuntimes()
                return .terminateNow

            default:
                return .terminateCancel
            }
        }

        // Always flush latest chat & ARX state before terminating
        AgentService.shared.saveChats()
        AgentService.shared.saveArx()
        DeviceRuntimeService.shared.shutdownAllRuntimes()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Never kill the app when the last window is closed so background AI tasks and state survive
        return false
    }
}

// MARK: - Extracted Commands to Reduce Main Struct Size

struct AppCommands: Commands {
    @ObservedObject var appState: AppState
    
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                appState.showingSettingsDialog = true
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .newItem) {
            Button("New File") { appState.createNewFile() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New AI Conversation") {
                let ws = appState.workspaceFolder?.path ?? AgentService.shared.currentWorkspace
                _ = AgentService.shared.createNewChat(projectPath: ws)
                appState.switchToMode(.aiAgent)
            }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Open File...") { appState.openFile() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Open Folder...") { appState.openFolder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Close Tab") {
                if let cur = appState.currentFile {
                    appState.closeFile(cur)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(appState.currentFile == nil)
            Button("Close Other Tabs") {
                appState.closeOtherTabs()
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .disabled(appState.openFiles.count <= 1)
            Button("Close Workspace") { appState.closeWorkspace() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Divider()
            Button("Next Tab") {
                appState.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: .command)
            Button("Previous Tab") {
                appState.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts...") {
                appState.showingKeyboardShortcuts = true
            }
            .keyboardShortcut("/", modifiers: .command)
            Divider()
            Button("Welcome to MicroCode") { appState.showWelcomeScreen() }
            Button("First-Launch Onboarding...") { appState.showFirstLaunchOnboarding() }
        }
        
        CommandGroup(replacing: .saveItem) {
            Button("Save") { appState.saveCurrentFile() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!appState.hasUnsavedChanges)
            Button("Save As...") { appState.saveFileAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandMenu("Modes") {
            Button("Code Editor") { appState.switchToMode(.code) }
                .keyboardShortcut("1", modifiers: .control)
            Button("AI Agent Workspace") { appState.switchToMode(.aiAgent) }
                .keyboardShortcut("2", modifiers: .control)
            Button("Cell Mode (Notebook)") { appState.switchToMode(.notebook) }
                .keyboardShortcut("3", modifiers: .control)
            Button("Playground Mode") { appState.switchToMode(.playground) }
                .keyboardShortcut("4", modifiers: .control)
            Button("Science Mode") { appState.switchToMode(.science) }
                .keyboardShortcut("5", modifiers: .control)
            Button("IDE Web Browser") { appState.switchToMode(.browser) }
                .keyboardShortcut("6", modifiers: .control)
            Button("Remote Explorer (SSH)") { appState.switchToMode(.remoteX) }
                .keyboardShortcut("7", modifiers: .control)
            Button("Embed & IoT Studio") { appState.switchToMode(.embedded) }
                .keyboardShortcut("8", modifiers: .control)
            Button("API Studio") { appState.openAPIStudio() }
                .keyboardShortcut("9", modifiers: .control)
            Button("Extension Studio") { appState.switchToMode(.extensions) }
                .keyboardShortcut("e", modifiers: .control)
            Divider()
            Button("Welcome Dashboard") { appState.showingWelcomeHome = true }
                .keyboardShortcut("0", modifiers: .control)
        }
        
        CommandMenu("Code") {
            Button("Run Code") { appState.runCode() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Debug with LLDB (DAP)") {
                if let file = appState.currentFile {
                    appState.consoleVisible = true
                    let wsPath = appState.workspaceFolder?.path
                    Task { @MainActor in
                        await DebugService.shared.startDebugSession(
                            filePath: file.path,
                            workspacePath: wsPath
                        )
                    }
                }
            }
                .keyboardShortcut("y", modifiers: [.command, .option])
            Button("Build Project") { appState.buildProject() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Button("Stop Execution") { appState.stopExecution() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!appState.isExecuting)
            Divider()
            Button("Find in Workspace...") {
                appState.sidebarVisible = true
                NotificationCenter.default.post(
                    name: Notification.Name("MicroCodeOpenWorkspaceSearch"),
                    object: nil,
                    userInfo: ["replace": false]
                )
            }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Replace in Workspace...") {
                appState.sidebarVisible = true
                NotificationCenter.default.post(
                    name: Notification.Name("MicroCodeOpenWorkspaceSearch"),
                    object: nil,
                    userInfo: ["replace": true]
                )
            }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button("Format Code") { appState.formatCode() }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Button("Refactor with AI") { appState.showRefactorDialog() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Explain Code") { appState.explainCode() }
                .keyboardShortcut("e", modifiers: [.command, .option])
            Divider()
            Button("AI Code Analysis") { appState.showingCodeAnalysis = true }
                .keyboardShortcut("a", modifiers: [.command, .option])
        }
        
        CommandMenu("View") {
            Button("Toggle Sidebar") {
                withAnimation(.easeInOut(duration: 0.22)) {
                    appState.toggleSidebar()
                }
            }
                .keyboardShortcut("b", modifiers: .command)
            Button("Toggle Preview & Inspector") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.toggleAgenticContext()
                }
            }
                .keyboardShortcut("i", modifiers: .command)
            Button("Toggle Terminal / Console") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.toggleConsole()
                }
            }
                .keyboardShortcut("j", modifiers: .command)
            Button("Toggle Git Panel") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.toggleGitPanel()
                }
            }
                .keyboardShortcut("g", modifiers: [.command, .option])
            Button("Toggle Device Preview Dock") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.showingPreviewView.toggle()
                }
            }
                .keyboardShortcut("p", modifiers: [.command, .option])

            Divider()

            Button("Keyboard Shortcuts...") {
                appState.showingKeyboardShortcuts = true
            }
            .keyboardShortcut("/", modifiers: .command)

            Divider()

            Button("Increase Font Size") { appState.increaseFontSize() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Decrease Font Size") { appState.decreaseFontSize() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Reset Font Size") { appState.resetFontSize() }
                .keyboardShortcut("0", modifiers: .command)
        }
        
        CommandMenu("Tools") {
            Button("Runtime Manager") { appState.showingRuntimeManager = true }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button("Terminal") { appState.toggleConsole() }
                .keyboardShortcut("t", modifiers: [.command, .option])
        }
        
        CommandMenu("Git") {
            Button("Refresh Status") { appState.gitRefresh() }
                .keyboardShortcut("r", modifiers: [.command, .control])
            Button("Commit Changes") { appState.showCommitDialog() }
                .keyboardShortcut("k", modifiers: .command)
            Button("Push") { appState.gitPush() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Pull") { appState.gitPull() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Divider()
            Button("Git Settings...") { appState.showingGitSettings = true }
        }

        CommandMenu("Diagnostics") {
            Button("Open Crash & Error Logs Folder") {
                NSWorkspace.shared.activateFileViewerSelecting([CrashReporter.shared.logDirectory])
            }
            Button("Show Latest Crash Report") {
                let dir = CrashReporter.shared.logDirectory
                let latest = dir.appendingPathComponent("latest-crash.log")
                if FileManager.default.fileExists(atPath: latest.path) {
                    NSWorkspace.shared.open(latest)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
            }
            Button("Open Breadcrumb Trail") {
                NSWorkspace.shared.open(CrashReporter.shared.logDirectory.appendingPathComponent("breadcrumbs.log"))
            }
            Divider()
            Button("Detect Installed Languages") {
                Task { @MainActor in
                    let servers = LSPManager.shared.detectInstalledServers(refresh: true)
                    let langs = LSPManager.shared.detectedLanguages()
                    let rt = RuntimeManager.shared
                    rt.detectAll()
                    let alert = NSAlert()
                    alert.messageText = "Detected Languages on this Mac"
                    var body = "Language servers (full IDE support):\n"
                    body += servers.isEmpty ? "  (none found)\n"
                        : servers.map { "  • \($0.rawValue)" }.joined(separator: "\n") + "\n"
                    body += "\nLanguages with LSP: \(langs.isEmpty ? "(none)" : langs.joined(separator: ", "))"
                    body += "\n\nRuntimes:\n" + rt.runtimes.map {
                        "  • \($0.type.rawValue): \($0.isInstalled ? ($0.path ?? "installed") : "not found")"
                    }.joined(separator: "\n")
                    alert.informativeText = body
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Copy")
                    if alert.runModal() == .alertSecondButtonReturn {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(body, forType: .string)
                    }
                }
            }
            Divider()
            Button("Copy Recent Breadcrumbs") {
                let text = CrashReporter.shared.recentBreadcrumbs().joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
}
