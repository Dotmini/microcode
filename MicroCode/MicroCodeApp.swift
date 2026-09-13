//
//  MicroCodeApp.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2024 AIPRENEUR. All rights reserved.
//
//  Performance Optimized Entry Point
//

import SwiftUI
import AppKit

@main
struct MicroCodeApp: App {
    // Core delegates
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Core state - Initialized lazily where possible inside AppState
    @StateObject private var appState = AppState()
    
    // Services
    @StateObject private var performanceManager = PerformanceManager.shared

    init() {
        // Install crash/error capture as early as possible so Swift traps,
        // signals and exceptions during startup are recorded too.
        CrashReporter.shared.install()
        CrashReporter.shared.breadcrumb("MicroCodeApp.init")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1200, minHeight: 800)
                .preferredColorScheme(appState.appTheme.colorScheme)
                .onAppear {
                    // Critical: Perform window setup on main thread
                    setupWindow()
                    
                    // Defer heavy non-critical setup to background
                    Task.detached(priority: .background) {
                        await performBackgroundStartup()
                    }
                }
                .onOpenURL { url in
                    handleIncomingDeepLink(url)
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
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // ... (Menu commands remain same, omitted for brevity in optimization view)
            AppCommands(appState: appState)
        }

    }

    private func setupWindow() {
        if let window = NSApplication.shared.windows.first {
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
        // Warm up critical services
        _ = PreviewService.shared
        _ = AuthService.shared
        _ = AutoHealerService.shared
        
        // Start Local MCP & HTTP Daemon Bridge for Omni AI
        MCPServer.shared.startLocalHttpBridge(port: 18888)
        
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
                NotificationCenter.default.post(name: NSNotification.Name("MicroCodeAccountLoggedIn"), object: nil)
            }
            return
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }
        let host = components.host ?? url.path
        let queryItems = components.queryItems ?? []
        
        func queryValue(for key: String) -> String? {
            return queryItems.first(where: { $0.name.lowercased() == key.lowercased() })?.value
        }
        
        // Account Sync & License
        if let email = queryValue(for: "email"), !email.isEmpty {
            let token = queryValue(for: "token") ?? ""
            let name = queryValue(for: "name") ?? queryValue(for: "display_name") ?? ""
            // Legacy web pages can still open snippets, but account/session
            // tokens are accepted only through Supabase's OAuth callback.
            let key = ""
            UserDefaults.standard.set(email, forKey: "dotminiUserEmail")
            appState.syncGoogleOrDotminiAccount(email: email, token: token, displayName: name)
            NotificationCenter.default.post(name: NSNotification.Name("MicroCodeAccountLoggedIn"), object: nil, userInfo: ["email": email, "key": key])
        }
        
        // Universal Preview Dock Deep Link
        if host == "preview" || host == "preview_dock" || host == "preview-dock" {
            if let path = queryValue(for: "path"), !path.isEmpty {
                let fileURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                Task { @MainActor in
                    PreviewDockService.shared.openFile(url: fileURL, makeActive: true)
                }
            } else if let tab = queryValue(for: "tab"), !tab.isEmpty {
                Task { @MainActor in
                    PreviewDockService.shared.selectTab(id: tab)
                }
            } else {
                Task { @MainActor in
                    PreviewDockService.shared.isDockVisible = true
                    DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
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
        
        // Code Execution / Open
        if host == "open" || host == "run" || host == "playground" || host.contains("snippet") {
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
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Optimization: Don't block main thread with heavy inits here
        CrashReporter.shared.install() // idempotent backstop
        CrashReporter.shared.breadcrumb("applicationDidFinishLaunching")

        // Configure appearance and bring window to front
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate(ignoringOtherApps: true)

        // applicationWillTerminate is NOT called on SIGTERM/SIGINT (e.g. a
        // `kill`, IDE stop, logout). Trap them so we still reap the backend
        // instead of leaving a re-parented CPU-spinning orphan.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN) // disable default termination; let the source run
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                ReportLogManager.shared.log("Signal \(sig) — stopping backend", type: .info)
                DeviceRuntimeService.shared.shutdownAllRuntimes()
                BackendService.shared.stopBackend()
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }

        // Pre-load critical singletons if needed, but prefer lazy
    }

    func applicationWillTerminate(_ notification: Notification) {
        ReportLogManager.shared.log("App Terminating", type: .info)
        DeviceRuntimeService.shared.shutdownAllRuntimes()
        // Stop backend server
        BackendService.shared.stopBackend()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Terminate runtime children before AppKit tears down the final
        // window. Without this, an embedded AVD/dev-server could keep the
        // process responsive-but-unclosable and force users to Force Quit.
        DeviceRuntimeService.shared.shutdownAllRuntimes()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
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
            Button("Open File...") { appState.openFile() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Open Folder...") { appState.openFolder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Close Workspace") { appState.closeWorkspace() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .help) {
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
        
        CommandMenu("Code") {
            Button("Run Code") { appState.runCode() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Stop Execution") { appState.stopExecution() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!appState.isExecuting)
            Divider()
            Button("Format Code") { appState.formatCode() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Button("Refactor with AI") { appState.showRefactorDialog() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Explain Code") { appState.explainCode() }
                .keyboardShortcut("e", modifiers: [.command, .option])
            Divider()
            Button("AI Code Analysis") { appState.showingCodeAnalysis = true }
                .keyboardShortcut("a", modifiers: [.command, .option])
        }
        
        CommandMenu("View") {
            Button("Toggle Sidebar") { appState.toggleSidebar() }
                .keyboardShortcut("b", modifiers: [.command, .option])
            Button("Toggle Console") { appState.toggleConsole() }
                .keyboardShortcut("j", modifiers: [.command, .option])
            Button("Toggle Git Panel") { appState.toggleGitPanel() }
                .keyboardShortcut("g", modifiers: [.command, .option])
            Button("Remote Explorer (SSH)") { 
                appState.showingWelcomeHome = false
                appState.setEditorMode(.remoteX) 
            }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button("Embed & IoT Studio") {
                appState.showingWelcomeHome = false
                appState.setEditorMode(.embedded)
            }
            Button("Code Editor") {
                appState.showingWelcomeHome = false
                appState.setEditorMode(.code)
            }
            Button("Cell Mode (Notebook)") {
                appState.showingWelcomeHome = false
                appState.setEditorMode(.notebook)
            }
            Button("Playground Mode") {
                appState.showingWelcomeHome = false
                appState.setEditorMode(.playground)
            }
            Button("API Studio") {
                appState.openAPIStudio()
            }

            Divider()
            
            // Smart Tag Finder
            Menu("Tag Finder") {
                Button("#Function") { }
                Button("#Class") { }
                Button("#Fix") { }
                Button("#Feature") { }
                Button("#API") { }
                Button("#Model") { }
                Button("#View") { }
                Button("#Service") { }
            }
            
            Divider()

            Button("Runtime Manager") { appState.showingRuntimeManager = true }
                .keyboardShortcut("r", modifiers: [.command, .shift])
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
