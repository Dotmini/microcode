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

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }

    private func setupWindow() {
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            
            // Dynamic transparency based on theme
            let isTransparent = appState.appTheme == .extraClear || appState.appTheme == .transparent || appState.appTheme == .crystalClear || appState.appTheme == .obsidianGlass
            window.backgroundColor = isTransparent ? .clear : .windowBackgroundColor
            window.isOpaque = !isTransparent
            window.hasShadow = true
            
            // Optimization: Disable backing store for purely transparent windows if applicable
            // window.isOpaque = false // Only if transparency needed
        }
    }
    
    private func performBackgroundStartup() async {
        // Warm up critical services
        _ = PreviewService.shared
        _ = AuthService.shared
        _ = AutoHealerService.shared
        
        // Log startup
        ReportLogManager.shared.log("App Started", type: .info)
        
        // Log startup performance
        await performanceManager.runOnECore {
            print("🚀 App Startup: Background services warmed up")
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

        // Configure appearance
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // applicationWillTerminate is NOT called on SIGTERM/SIGINT (e.g. a
        // `kill`, IDE stop, logout). Trap them so we still reap the backend
        // instead of leaving a re-parented CPU-spinning orphan.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN) // disable default termination; let the source run
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                ReportLogManager.shared.log("Signal \(sig) — stopping backend", type: .info)
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
        
        // Stop backend server
        BackendService.shared.stopBackend()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - Extracted Commands to Reduce Main Struct Size

struct AppCommands: Commands {
    @ObservedObject var appState: AppState
    
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New File") { appState.createNewFile() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Open File...") { appState.openFile() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Open Folder...") { appState.openFolder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
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
