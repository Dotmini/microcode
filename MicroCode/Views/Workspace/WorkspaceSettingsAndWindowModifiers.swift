//
//  WorkspaceSettingsAndWindowModifiers.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2024 Dotmini Company Limited. All rights reserved.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Settings Sheet Window Anchor

private struct SettingsSheetWindowAnchor: NSViewRepresentable {
    @Binding var sheetWindow: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            if let win = view?.window, (win.isSheet || win.sheetParent != nil || win.className.contains("Sheet")) {
                sheetWindow = win
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let win = nsView.window,
           (win.isSheet || win.sheetParent != nil || win.className.contains("Sheet")),
           sheetWindow !== win {
            DispatchQueue.main.async {
                sheetWindow = win
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @StateObject private var modelCatalog = AIModelCatalog.shared
    @State private var hostSheetWindow: NSWindow? = nil
    
    // Local state for editing
    @State private var selectedProvider: String = ""
    @State private var selectedModel: String = ""
    @State private var apiKey: String = ""
    @State private var fontSize: CGFloat = 16
    @State private var fontFamily: String = "SF Mono"
    @State private var agentFontName: String = "SF Pro"
    @State private var agentFontSize: CGFloat = 16.0
    @State private var showLineNumbers: Bool = false
    @State private var showSidebar: Bool = true
    @State private var showConsole: Bool = true
    @State private var selectedTheme: AppTheme = .system
    @State private var playgroundFontName: String = "SF Mono"
    @State private var playgroundFontSize: CGFloat = 13.0
    @State private var playgroundFontWeight: Int = 2
    @State private var cellFontName: String = "SF Mono"
    @State private var cellFontSize: CGFloat = 13.0
    @State private var cellFontWeight: Int = 2
    @State private var agentMode: Bool = true
    @State private var agentAutoApproveTools: Bool = false
    @State private var agentCustomInstructions: String = ""
    @State private var agentMaxIterations: Int = 0
    @State private var selectedTab: Int = 2
    @State private var hasChanges: Bool = false
    @State private var microRentToken: String = ""
    @State private var authEmail = ""
    @State private var authPassword = ""
    @State private var isAuthenticating = false
    @State private var authError = ""
    @State private var currentPlan: String = "free"
    
    static let sidebarItems: [(tab: Int, title: String, icon: String)] = [
        (0, "General", "gearshape"),
        (1, "Editor", "text.cursor"),
        (2, "AI & Agent", "sparkles"),
        (11, "Connect with Phone", "iphone.radiowaves.left.and.right"),
        (12, "Team Collaboration", "person.2"),
        (9, "Cloud GPU", "cpu"),
        (10, "Skills", "sparkles.rectangle.stack"),
        (8, "MCP Servers", "server.rack"),
        (3, "Tools", "wrench.and.screwdriver"),
        (5, "Extensions", "puzzlepiece.extension"),
        (6, "Account & License", "person.badge.key"),
        (4, "About", "info.circle")
    ]

    static var visibleSidebarItems: [(tab: Int, title: String, icon: String)] {
        if AppEdition.isStandaloneAI {
            return sidebarItems.filter { ![1, 9, 5].contains($0.tab) }
        }
        return sidebarItems
    }

    var body: some View {
        HStack(spacing: 0) {
            // ── Sidebar (Codex-style) ──────────────────────────────────
            VStack(alignment: .leading, spacing: 2) {
                Button(action: { closeSettings() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back to app")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .padding(.bottom, 16)

                ForEach(Self.visibleSidebarItems, id: \.tab) { item in
                    CodexSidebarRow(title: item.title, icon: item.icon,
                                    selected: selectedTab == item.tab) {
                        selectedTab = item.tab
                    }
                }

                Spacer()

                Text("© 2025 MicroCode · Dotmini Software")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.65))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
            .frame(width: 236, alignment: .leading)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))

            Divider()

            // ── Content ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        Text(Self.sidebarItems.first { $0.tab == selectedTab }?.title ?? "Settings")
                            .font(.system(size: 20, weight: .bold))
                        Spacer()
                        HStack(spacing: 8) {
                            Button(action: { closeSettings() }) {
                                Text("Cancel")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.05))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.09), lineWidth: 1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.cancelAction)

                            Button(action: {
                                saveAllSettings(deferThemeUntilDismissed: true)
                                closeSettings()
                            }) {
                                Text("Save Changes")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.10))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.20), lineWidth: 1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                    Divider().opacity(0.5)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if selectedTab == 0 { generalSettingsContent }
                        else if selectedTab == 1 { editorSettingsContent }
                        else if selectedTab == 2 { aiSettingsContent }
                        else if selectedTab == 11 { PhoneCompanionSettingsView().environmentObject(appState) }
                        else if selectedTab == 12 { CollaborationView(isEmbeddedInSettings: true) }
                        else if selectedTab == 9 { CloudGPUView() }
                        else if selectedTab == 10 { AgentSkillsView() }
                        else if selectedTab == 8 { mcpSettingsPanel }
                        else if selectedTab == 3 { toolsSettingsContent }
                        else if selectedTab == 5 { ExtensionSettingsView() }
                        else if selectedTab == 6 { subscriptionSettingsContent }
                        else { aboutContent }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(SettingsSheetWindowAnchor(sheetWindow: $hostSheetWindow))
        .frame(minWidth: 880, idealWidth: 1000, maxWidth: 1240,
               minHeight: 600, idealHeight: 700, maxHeight: 920)
        .onExitCommand {
            closeSettings()
        }
        .onAppear {
            selectedTab = appState.settingsSelectedTab
            loadCurrentSettings()
        }
        .onChange(of: selectedTab) { newTab in
            appState.settingsSelectedTab = newTab
        }
        .sheet(item: $webLoginProvider) { prov in
            WebSubscriptionLoginSheet(provider: prov) {
                activateSubscriptionProvider(prov)
            }
        }
        .onDisappear {
            if appState.showingSettingsDialog {
                appState.showingSettingsDialog = false
            }
        }
    }
    
    private func closeSettings() {
        let capturedSheet = hostSheetWindow
        capturedSheet?.makeFirstResponder(nil)
        if appState.showingSettingsDialog {
            appState.showingSettingsDialog = false
        }
        dismiss()
        Self.ensureSheetDismissed(capturedSheet, appState: appState)
    }

    private static func ensureSheetDismissed(_ capturedSheet: NSWindow?, appState: AppState) {
        for delay in [0.08, 0.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !appState.showingSettingsDialog else { return }
                let targetSheet: NSWindow? = capturedSheet ?? NSApplication.shared.windows.first(where: {
                    ($0.isSheet || $0.sheetParent != nil) && $0.isVisible &&
                    abs($0.frame.width - 1000) < 380 && abs($0.frame.height - 700) < 280
                })
                guard let sheetWin = targetSheet, sheetWin.isVisible else { return }
                if let parent = sheetWin.sheetParent {
                    parent.endSheet(sheetWin, returnCode: .cancel)
                    sheetWin.orderOut(nil)
                    parent.makeKeyAndOrderFront(nil)
                } else if sheetWin.isSheet || sheetWin.className.contains("Sheet") {
                    sheetWin.orderOut(nil)
                }
            }
        }
    }
    
    // MARK: - Subscription Content
    
    private var subscriptionSettingsContent: some View {
        MicroCodeLicenseSettingsView()
            .environmentObject(appState)
    }
    
    // MARK: - Firebase Authentication
    private func authenticateWithFirebase() {
        guard !authEmail.isEmpty, !authPassword.isEmpty else { return }
        isAuthenticating = true
        authError = ""
        
        // API key must be configured via Settings → MicroRent, never hardcoded
        let apiKey = UserDefaults.standard.string(forKey: "firebaseApiKey") ?? ProcessInfo.processInfo.environment["FIREBASE_API_KEY"] ?? ""
        guard !apiKey.isEmpty else {
            authError = "Firebase API Key not configured. Set it in Settings → MicroRent."
            isAuthenticating = false
            return
        }
        let urlString = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            authError = "Invalid Configuration"
            isAuthenticating = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "email": authEmail,
            "password": authPassword,
            "returnSecureToken": true
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            authError = "Payload Error"
            isAuthenticating = false
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isAuthenticating = false
                
                if let error = error {
                    self.authError = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.authError = "No data received"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorObj = json["error"] as? [String: Any],
                       let message = errorObj["message"] as? String {
                        self.authError = message
                        if message == "INVALID_LOGIN_CREDENTIALS" {
                            self.authError = "Invalid Email or Password"
                        }
                    } else {
                        self.authError = "Server Error: \(httpResponse.statusCode)"
                    }
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let localId = json["localId"] as? String {
                        self.microRentToken = localId
                        self.hasChanges = true
                        self.authEmail = ""
                        self.authPassword = ""
                    } else {
                        self.authError = "Could not parse UID from response"
                    }
                } catch {
                    self.authError = "Invalid response format"
                }
            }
        }.resume()
    }
    
    private func checkSubscriptionStatus() {
        guard !microRentToken.isEmpty else { return }
        
        let baseURL = UserDefaults.standard.string(forKey: "firebaseRTDBUrl") ?? ProcessInfo.processInfo.environment["FIREBASE_RTDB_URL"] ?? ""
        guard !baseURL.isEmpty else { return }
        let urlString = "\(baseURL)/users/\(microRentToken)/subscriptionPlan.json"
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data, let planString = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    let unquoted = planString.replacingOccurrences(of: "\"", with: "")
                    if unquoted != "null" && !unquoted.isEmpty {
                        self.currentPlan = unquoted
                    } else {
                        self.currentPlan = "free"
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - About Content
    
    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    private var aboutContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // Real app icon (Apple-style)
            Group {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .resizable().scaledToFit().padding(28)
                        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.thinMaterial))
                }
            }
            .frame(width: 116, height: 116)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
            .padding(.bottom, 18)

            Text("MicroCode")
                .font(.system(size: 30, weight: .semibold))
            Text(appVersionString)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.top, 2)

            Text("The native AI-powered IDE for macOS")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.top, 10)

            HStack(spacing: 18) {
                Link(destination: URL(string: "https://github.com/Dotmini/microcode")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://dotmini.net")!) {
                    Label("dotmini.net", systemImage: "globe")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.top, 20)

            Spacer(minLength: 24)

            VStack(spacing: 3) {
                Text("Dotmini Software")
                    .font(.system(size: 12, weight: .semibold))
                Text("© 2025 Dotmini Software. All rights reserved.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - General Settings
    
    private var generalSettingsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Agent Settings on Page 1 (หน้าแรก)
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeader(title: "AI Agent & Automation")
                
                Toggle("Autonomous Agent Mode (Multi-turn tool loop & file edits)", isOn: $agentMode)
                    .onChange(of: agentMode) { _ in hasChanges = true }
                
                Toggle("Auto-Approve Tool Execution (Files, Shell, Refactor)", isOn: $agentAutoApproveTools)
                    .onChange(of: agentAutoApproveTools) { _ in hasChanges = true }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Max Tool Loop Iterations:")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Stepper(agentMaxIterations <= 0 ? "Unlimited (∞)" : "\(agentMaxIterations) steps", value: $agentMaxIterations, in: 0...200, step: 5)
                            .onChange(of: agentMaxIterations) { _ in hasChanges = true }
                    }
                    if agentMaxIterations <= 0 {
                        Text("No limit — Agent will continue multi-turn thinking & tool loops until the task is complete.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                
                HStack {
                    Text("Agent Font:")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker("", selection: $agentFontName) {
                        Text("SF Pro").tag("SF Pro")
                        Text("SF Mono").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Fira Code").tag("Fira Code")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .onChange(of: agentFontName) { _ in hasChanges = true }
                }
                
                HStack {
                    Text("Agent Size: \(Int(agentFontSize)) pt")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 120, alignment: .leading)
                    Slider(value: $agentFontSize, in: 12...26, step: 1)
                        .onChange(of: agentFontSize) { _ in hasChanges = true }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom System Instructions / Rules:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $agentCustomInstructions)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 70)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                        .onChange(of: agentCustomInstructions) { _ in hasChanges = true }
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            
            Divider()
            
            SettingsSectionHeader(title: "Appearance")
            
            Toggle("Show sidebar on startup", isOn: $showSidebar)
                .onChange(of: showSidebar) { _ in hasChanges = true }
            
            Toggle("Show console on startup", isOn: $showConsole)
                .onChange(of: showConsole) { _ in hasChanges = true }
                
            Divider()
            
            SettingsSectionHeader(title: "Theme")
            
            ThemePickerView(selectedTheme: $selectedTheme)
                .onChange(of: selectedTheme) { _ in hasChanges = true }
            
            // Theme Preview
            HStack {
                Text("Preview:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: selectedTheme.editorBackground))
                    .frame(width: 100, height: 60)
                    .overlay(
                        VStack(alignment: .leading, spacing: 2) {
                            Text("func main() {")
                                .foregroundColor(Color(nsColor: selectedTheme.keywordColor))
                            Text("  print(\"Hello\")")
                                .foregroundColor(Color(nsColor: selectedTheme.editorText))
                            Text("}")
                                .foregroundColor(Color(nsColor: selectedTheme.keywordColor))
                        }
                        .font(.system(size: 8, design: .monospaced))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
        }
    }
    
    // MARK: - Editor Settings
    
    private var editorSettingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // AI Agent & Chat Font
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "AI Agent & Chat Font")
                    
                    Picker("Font Family", selection: $agentFontName) {
                        Text("SF Pro").tag("SF Pro")
                        Text("SF Mono").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Fira Code").tag("Fira Code")
                        Text("Monaco").tag("Monaco")
                        Text("Helvetica Neue").tag("Helvetica Neue")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                    .onChange(of: agentFontName) { _ in hasChanges = true }
                    
                    HStack {
                        Text("Size: \(Int(agentFontSize))")
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $agentFontSize, in: 12...26, step: 1)
                            .onChange(of: agentFontSize) { _ in hasChanges = true }
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // Main Editor Font
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "Main Editor Font")
                    
                    Picker("Font Family", selection: $fontFamily) {
                        Text("SF Pro").tag("SF Pro")
                        Text("SF Mono").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Fira Code").tag("Fira Code")
                        Text("Monaco").tag("Monaco")
                        Text("Courier New").tag("Courier New")
                        Text("Helvetica Neue").tag("Helvetica Neue")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                    .onChange(of: fontFamily) { _ in hasChanges = true }
                    
                    HStack {
                        Text("Size: \(Int(fontSize))")
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $fontSize, in: 10...24, step: 1)
                            .onChange(of: fontSize) { _ in hasChanges = true }
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // Playground Font
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "Playground Font")
                    
                    Picker("Font Family", selection: $playgroundFontName) {
                        Text("SF Pro").tag("SF Pro")
                        Text("SF Mono").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Fira Code").tag("Fira Code")
                        Text("Monaco").tag("Monaco")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                    .onChange(of: playgroundFontName) { _ in hasChanges = true }
                    
                    HStack {
                        Text("Size: \(Int(playgroundFontSize))")
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $playgroundFontSize, in: 10...24, step: 1)
                            .onChange(of: playgroundFontSize) { _ in hasChanges = true }
                    }
                    
                    Picker("Font Weight", selection: $playgroundFontWeight) {
                        Text("Thin").tag(0)
                        Text("Light").tag(1)
                        Text("Regular").tag(2)
                        Text("Medium").tag(3)
                        Text("Semibold").tag(4)
                        Text("Bold").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: playgroundFontWeight) { _ in hasChanges = true }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // Cell Mode Font
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "Cell Mode Font")
                    
                    Picker("Font Family", selection: $cellFontName) {
                        Text("SF Pro").tag("SF Pro")
                        Text("SF Mono").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Fira Code").tag("Fira Code")
                        Text("Monaco").tag("Monaco")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                    .onChange(of: cellFontName) { _ in hasChanges = true }
                    
                    HStack {
                        Text("Size: \(Int(cellFontSize))")
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $cellFontSize, in: 10...24, step: 1)
                            .onChange(of: cellFontSize) { _ in hasChanges = true }
                    }
                    
                    Picker("Font Weight", selection: $cellFontWeight) {
                        Text("Thin").tag(0)
                        Text("Light").tag(1)
                        Text("Regular").tag(2)
                        Text("Medium").tag(3)
                        Text("Semibold").tag(4)
                        Text("Bold").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: cellFontWeight) { _ in hasChanges = true }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // Editing
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "Editing Preferences")
                    Toggle("Show line numbers", isOn: $showLineNumbers)
                        .onChange(of: showLineNumbers) { _ in hasChanges = true }
                    Text("Off by default. Large files in Performance mode hide line numbers automatically for stability.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Toggle("Word wrap", isOn: .constant(false))
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            }
            .padding()
        }
    }
    
    // MARK: - AI Settings
    
    // MARK: - AI Provider Registry
    
    private struct AIProviderInfo {
        let id: String
        let name: String
        let icon: String
        let color: Color
        let endpoint: String
        let models: [(name: String, id: String, badge: String)]
    }
    
    private var aiProviders: [AIProviderInfo] {
        modelCatalog.providers.map { provider in
            AIProviderInfo(
                id: provider.id,
                name: provider.name,
                icon: provider.icon,
                color: providerColor(provider.id),
                endpoint: provider.endpoint,
                models: provider.models.map { ($0.name, $0.id, $0.badge) }
            )
        } + [
            AIProviderInfo(id: "local", name: "Local LLM", icon: "desktopcomputer", color: .mint,
                          endpoint: LocalLLMService.shared.activeEndpoint,
                          models: LocalLLMService.shared.availableModels.map {
                              (name: $0.displayName, id: $0.id, badge: $0.size ?? "")
                          } + [("Auto-detect", "local-model", "SCAN")]),
        ]
    }

    private func providerColor(_ provider: String) -> Color {
        switch provider {
        case "omni": return .orange
        case "gemini": return .blue
        case "openai": return .green
        case "anthropic": return .pink
        case "deepseek": return .cyan
        case "openrouter": return .indigo
        case "groq": return .orange
        case "mistral": return .orange
        case "kimi": return .cyan
        case "perplexity": return .teal
        case "perch": return .mint
        case "tokenme": return .cyan
        case "typhoon": return .purple
        case "cerebras": return .pink
        case "together": return .blue
        case "fireworks": return .orange
        case "minimax": return .pink
        case "nvidia": return .green
        case "grok": return .purple
        case "qwen": return .indigo
        case "glm": return .red
        case "custom": return .teal
        default: return .secondary
        }
    }
    
    @State private var providerKeys: [String: String] = [:]
    @State private var providerBaseURLs: [String: String] = [:]
    @State private var providerCustomModels: [String: String] = [:]
    @State private var isTestingByokEndpoint: Bool = false
    @State private var byokEndpointStatusMessage: String = ""
    @State private var showAPIKey: [String: Bool] = [:]
    @State private var aiKeyMode: String = "direct"  // "cloud" = Dotmini proxy, "direct" = user's own key, "subscription" = ChatGPT/Claude/Gemini/DeepSeek subscription, "local" = local LLM
    @State private var dotminiLicenseKey: String = ""
    @ObservedObject private var subscriptionAuth = SubscriptionAuthManager.shared
    @ObservedObject private var healthProbe = SubscriptionHealthProbe.shared
    @ObservedObject private var supabaseAuth = SupabaseAuthService.shared
    
    private var aiSettingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // ── 1. Formal Mode Switcher (Dotmini Cloud vs Subscription vs BYOK vs Local) ──
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("AI Mode & Provider")
                        .font(.system(size: 13, weight: .semibold))
                }
                
                HStack(spacing: 8) {
                    // Mode Button: Cloud
                    Button {
                        aiKeyMode = "cloud"
                        let cloudList = modelCatalog.dotminiCloudModels
                        if let currentMatch = cloudList.first(where: { $0.id == selectedModel }) {
                            selectedProvider = currentMatch.provider
                        } else if let first = cloudList.first {
                            selectedProvider = first.provider
                            selectedModel = first.id
                        }
                        hasChanges = true
                    } label: {
                        HStack(spacing: 6) {
                            AIProviderBrandIcon(provider: "omni", size: 15)
                            Text("Dotmini Cloud")
                                .font(.system(size: 11.5, weight: aiKeyMode == "cloud" ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(aiKeyMode == "cloud" ? Color.primary.opacity(0.12) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(aiKeyMode == "cloud" ? Color.primary.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)

                    // Mode Button: Web Subscription (No API)
                    Button {
                        aiKeyMode = "subscription"
                        hasChanges = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles.rectangle.stack")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Text("Web Subscription")
                                .font(.system(size: 11.5, weight: aiKeyMode == "subscription" ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(aiKeyMode == "subscription" ? Color.primary.opacity(0.12) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(aiKeyMode == "subscription" ? Color.primary.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    
                    // Mode Button: BYOK
                    Button {
                        aiKeyMode = "direct"
                        if selectedProvider == "omni" || selectedProvider == "local" {
                            selectedProvider = "gemini"
                            if let first = modelCatalog.provider("gemini")?.models.first {
                                selectedModel = first.id
                            }
                        }
                        hasChanges = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "key")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text("Direct API Key")
                                .font(.system(size: 11.5, weight: aiKeyMode == "direct" ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(aiKeyMode == "direct" ? Color.primary.opacity(0.12) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(aiKeyMode == "direct" ? Color.primary.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    
                    // Mode Button: Enterprise API
                    Button {
                        aiKeyMode = "enterprise"
                        if let prof = EnterpriseAIAuthService.shared.activeProfile {
                            selectedProvider = prof.dialect.brandIconKey
                            selectedModel = prof.defaultModel.isEmpty ? (prof.availableModels.first ?? "gpt-4o") : prof.defaultModel
                        }
                        hasChanges = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "building.2.crop.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.indigo)
                            Text("Enterprise")
                                .font(.system(size: 11.5, weight: aiKeyMode == "enterprise" ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(aiKeyMode == "enterprise" ? Color.primary.opacity(0.12) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(aiKeyMode == "enterprise" ? Color.primary.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)

                    // Mode Button: Local
                    Button {
                        aiKeyMode = "local"
                        selectedProvider = "local"
                        selectedModel = localLLM.activeModel
                        hasChanges = true
                    } label: {
                        HStack(spacing: 6) {
                            AIProviderBrandIcon(provider: "local", size: 15)
                            Text("Local LLM")
                                .font(.system(size: 11.5, weight: aiKeyMode == "local" ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(aiKeyMode == "local" ? Color.primary.opacity(0.12) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(aiKeyMode == "local" ? Color.primary.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            )
            
            // ── 2. Mode-Specific Configuration ──
            if aiKeyMode == "enterprise" {
                EnterpriseConnectHubView { newProv, newModel in
                    selectedProvider = newProv
                    selectedModel = newModel
                    hasChanges = true
                }
                .environmentObject(appState)
            } else if aiKeyMode == "cloud" {
                // Dotmini Cloud Dedicated Panel
                let cloudModels = modelCatalog.dotminiCloudModels
                let hasCloudSession = supabaseAuth.session != nil
                let rawPlan = supabaseAuth.entitlement.plan.trimmingCharacters(in: .whitespacesAndNewlines)
                let planUpper = rawPlan.isEmpty ? "FREE" : rawPlan.uppercased()
                let isPaidPlan = ["lite", "pro", "advanced", "bundle_pro", "bundle", "enterprise", "admin"].contains(where: { rawPlan.lowercased().contains($0) })
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        AIProviderBrandIcon(provider: "omni", size: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Dotmini Cloud Subscription")
                                .font(.system(size: 13, weight: .semibold))
                            Text("microcode.dotmini.net/v1")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(modelCatalog.source)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Button(modelCatalog.isRefreshing ? "Refreshing…" : "Refresh Catalog") {
                            Task {
                                await modelCatalog.refreshIfNeeded(force: true)
                                await supabaseAuth.refreshEntitlement()
                                if let match = modelCatalog.dotminiCloudModels.first(where: { $0.id == selectedModel }) {
                                    selectedProvider = match.provider
                                } else if let first = modelCatalog.dotminiCloudModels.first {
                                    selectedProvider = first.provider
                                    selectedModel = first.id
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(modelCatalog.isRefreshing)
                    }
                    
                    Divider().opacity(0.6)
                    
                    HStack(spacing: 12) {
                        Text("Active Model:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 110, alignment: .leading)
                        
                        Picker("", selection: $selectedModel) {
                            ForEach(cloudModels, id: \.id) { m in
                                HStack {
                                    Text("\(m.name) (\(m.cloudTHBRateSummary))")
                                    if !m.badge.isEmpty {
                                        Text("[\(m.badge)]")
                                    }
                                }.tag(m.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .onChange(of: selectedModel) { newID in
                            if let matched = cloudModels.first(where: { $0.id == newID }) {
                                selectedProvider = matched.provider
                            } else {
                                selectedProvider = StreamableAIProvider.detect(from: newID).rawValue
                            }
                            hasChanges = true
                        }
                    }
                    
                    HStack(spacing: 10) {
                        Circle()
                            .fill(hasCloudSession ? ((isPaidPlan || supabaseAuth.entitlement.totalAvailableTHB > 0) ? Color.green : Color.orange) : Color.secondary)
                            .frame(width: 7, height: 7)
                        if let activeSession = supabaseAuth.session {
                            Text("\(activeSession.email) · Plan: \(planUpper)")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.primary)
                            if supabaseAuth.entitlement.isLoaded {
                                Text(String(format: "(Available: %@ · Plan: %@ + AI Top-Up: ฿%.2f)", supabaseAuth.entitlement.formattedAvailableCredit, supabaseAuth.entitlement.formattedPlanCreditSummary, supabaseAuth.entitlement.aiTopupBalanceTHB))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Top Up / Plans") {
                                appState.settingsSelectedTab = 6
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            Button("Web Console") {
                                NSWorkspace.shared.open(supabaseAuth.authenticatedPortalURL(path: "/dashboard"))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else if !dotminiLicenseKey.isEmpty || DotminiPlatformKeyService.shared.authorizationToken != nil {
                            Text("Dotmini Cloud Platform Key Configured")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                        } else {
                            Text("Not signed in — sign in on microcode.dotmini.net (auto-syncs) or Account & License.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Sign In") {
                                appState.settingsSelectedTab = 6
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                )
            } else if aiKeyMode == "direct" {
                // BYOK Dedicated Panel
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "key")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Bring Your Own Key (BYOK) & Custom Base URL")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("Isolated from Local/LAN LLM")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.teal)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.teal.opacity(0.12))
                            .cornerRadius(4)
                    }
                    
                    Text("Connect directly to official AI providers (OpenAI, Claude, Gemini, etc.) or any custom Base URL / remote Cloudflare Tunnel (`*.trycloudflare.com/v1`) without mixing with Local/LAN LLM.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 16) {
                        // Provider Picker
                        HStack(spacing: 8) {
                            Text("Active Provider:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .fixedSize()
                            
                            Picker("", selection: $selectedProvider) {
                                ForEach(aiProviders.filter { $0.id != "omni" && $0.id != "local" }, id: \.id) { p in
                                    Text(p.name).tag(p.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                            .onChange(of: selectedProvider) { newValue in
                                hasChanges = true
                                byokEndpointStatusMessage = ""
                                let customModel = (providerCustomModels[newValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                if !customModel.isEmpty {
                                    selectedModel = customModel
                                } else if let provider = aiProviders.first(where: { $0.id == newValue }),
                                          let first = provider.models.first {
                                    selectedModel = first.id
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Model Picker
                        HStack(spacing: 8) {
                            Text("Model:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .fixedSize()
                            
                            Picker("", selection: $selectedModel) {
                                if let provider = aiProviders.first(where: { $0.id == selectedProvider }) {
                                    let customId = (providerCustomModels[selectedProvider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !customId.isEmpty && !provider.models.contains(where: { $0.id == customId }) {
                                        Text("\(provider.name) : \(customId) [CUSTOM]").tag(customId)
                                    }
                                    ForEach(provider.models, id: \.id) { m in
                                        HStack {
                                            Text("\(provider.name) : \(m.name)")
                                            if !m.badge.isEmpty {
                                                Text("[\(m.badge)]")
                                            }
                                        }.tag(m.id)
                                    }
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                            .onChange(of: selectedModel) { _ in hasChanges = true }
                            
                            Button {
                                testAndFetchByokModels(for: selectedProvider)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isTestingByokEndpoint ? "arrow.triangle.2.circlepath" : "bolt.horizontal.circle")
                                        .font(.system(size: 11))
                                    Text(isTestingByokEndpoint ? "Fetching…" : "Fetch Models")
                                        .font(.system(size: 10.5, weight: .medium))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isTestingByokEndpoint)
                            .help("Query /v1/models (or /api/tags) from this provider's Base URL / Cloudflare Tunnel")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // ── Per-Provider Custom Base URL / Cloudflare Tunnel & Custom Model Override ──
                    byokCustomEndpointBox(for: selectedProvider)
                    
                    Divider().opacity(0.6)
                    
                    Text("Provider API Keys & Endpoints")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 6) {
                        ForEach(aiProviders.filter { $0.id != "omni" && $0.id != "local" }, id: \.id) { provider in
                            aiProviderKeyCard(provider)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                )
            } else if aiKeyMode == "subscription" {
                // Web Subscription Panel (ChatGPT Plus/Team, Claude Pro, Zhipu GLM)
                subscriptionAISettingsPanel
            } else {
                // Local LLM Panel
                localLLMSettingsPanel
            }
        }
    }
    
    @ObservedObject private var mcpServer = MCPServer.shared
    
    private var mcpSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("MCP Protocol Server")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                
                HStack(spacing: 4) {
                    Circle().fill(mcpServer.isRunning ? .green : .secondary.opacity(0.3)).frame(width: 6, height: 6)
                    Text(mcpServer.isRunning ? "Running" : "Stopped")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(mcpServer.isRunning ? .green : .secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.04)).cornerRadius(6)
                
                Button(mcpServer.isRunning ? "Stop" : "Start") {
                    if mcpServer.isRunning {
                        mcpServer.stop()
                    } else if let ws = appState.workspaceFolder?.path {
                        mcpServer.start(workspace: ws)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Text("Model Context Protocol server exposes workspace tools (read, write, search, terminal, git) to external AI clients like Claude Desktop, Cursor, and ChatGPT plugins.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            // Stats
            if mcpServer.isRunning {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Requests").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                        Text("\(mcpServer.requestCount)").font(.system(size: 16, weight: .bold, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clients").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                        Text("\(mcpServer.connectedClients)").font(.system(size: 16, weight: .bold, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tools").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                        Text("8").font(.system(size: 16, weight: .bold, design: .monospaced))
                    }
                    Spacer()
                    
                    if let last = mcpServer.lastActivity {
                        Text("Last: \(last, style: .relative) ago")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.03))
                .cornerRadius(8)
            }
            
            // Available Tools
            VStack(alignment: .leading, spacing: 6) {
                Text("Available Tools")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 4) {
                    mcpToolBadge("read_file", icon: "doc.text")
                    mcpToolBadge("write_file", icon: "pencil.and.outline")
                    mcpToolBadge("edit_file", icon: "doc.text.fill")
                    mcpToolBadge("search_files", icon: "magnifyingglass")
                    mcpToolBadge("list_files", icon: "folder")
                    mcpToolBadge("run_terminal", icon: "terminal.fill")
                    mcpToolBadge("git_status", icon: "point.3.filled.connected.trianglepath.dotted")
                    mcpToolBadge("get_diagnostics", icon: "exclamationmark.triangle")
                }
            }
            
            // Recent Logs
            if !mcpServer.logs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Activity")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    ForEach(mcpServer.logs.suffix(5)) { log in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(log.status == .success ? .green : log.status == .error ? .red : .blue)
                                .frame(width: 5, height: 5)
                            Text(log.method)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                            Text(log.detail)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(log.timestamp, style: .time)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
                .padding(10)
                .background(Color.black.opacity(0.15))
                .cornerRadius(6)
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
    
    @ViewBuilder
    private func mcpToolBadge(_ name: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9)).foregroundColor(.secondary)
            Text(name).font(.system(size: 9, design: .monospaced)).foregroundColor(.primary.opacity(0.7))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(4)
    }
    
    @State private var subscriptionTokenInputs: [String: String] = [:]
    @State private var subscriptionEmailInputs: [String: String] = [:]
    @State private var expandedProviderGuide: [String: Bool] = [:]
    @State private var copiedSnippetProvider: String? = nil
    @State private var webLoginProvider: SubscriptionProviderType? = nil

    private func activateSubscriptionProvider(_ provider: SubscriptionProviderType) {
        let chosenModel = provider.modelInfos.first?.modelID ?? provider.defaultModel
        aiKeyMode = "subscription"
        selectedProvider = provider.aiProviderID
        selectedModel = chosenModel
        appState.aiProvider = provider.aiProviderID
        appState.aiModel = chosenModel
        subscriptionAuth.activeProvider = provider
        // Strict isolation: NEVER copy Subscription tokens into BYOK `providerKeys` or `appState.apiKeys`
        UserDefaults.standard.set("subscription", forKey: "aiKeyMode")
        UserDefaults.standard.set(provider.rawValue, forKey: "subscriptionActiveProvider")
        UserDefaults.standard.set(provider.aiProviderID, forKey: "aiProvider")
        UserDefaults.standard.set(chosenModel, forKey: "aiModel")
        hasChanges = true
    }

    private var subscriptionAISettingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Web Subscription Mode (No API Billing)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Connect your active ChatGPT, Claude, Gemini, DeepSeek, or GitHub Copilot accounts without API usage fees.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    if subscriptionAuth.hasAnyConnected {
                        Button(role: .destructive) {
                            subscriptionAuth.clearAllAccounts()
                        } label: {
                            Text("Disconnect All")
                                .font(.system(size: 11))
                        }
                        .controlSize(.small)
                    }

                    Button {
                        Task { await healthProbe.runAll() }
                    } label: {
                        HStack(spacing: 5) {
                            if healthProbe.isRunning {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "stethoscope")
                                    .font(.system(size: 10))
                            }
                            Text(healthProbe.isRunning ? "Testing…" : "Test connections")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(healthProbe.isRunning)

                    Button {
                        Task {
                            await subscriptionAuth.detectLocalCLISessions()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 10))
                            Text("Auto-detect & Verify CLI Auth")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.bottom, 2)

            if !subscriptionAuth.lastDetectionMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: subscriptionAuth.detectedSessionCount > 0 ? "checkmark.circle.fill" : "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(subscriptionAuth.detectedSessionCount > 0 ? .green : .secondary)
                    Text(subscriptionAuth.lastDetectionMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
            }

            Divider().opacity(0.6)

            // Active Subscription Model Selection Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "cpu")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.blue)
                    Text("Active Subscription Model")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if subscriptionAuth.hasAnyConnected {
                        Text("\(subscriptionAuth.connectedModelInfos().count) Models Available")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(4)
                    }
                }
                
                if subscriptionAuth.hasAnyConnected {
                    let connectedModels = subscriptionAuth.connectedModelInfos()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: Binding(
                            get: {
                                if connectedModels.contains(where: { $0.modelID == selectedModel }) {
                                    return selectedModel
                                }
                                return connectedModels.first?.modelID ?? ""
                            },
                            set: { newModelID in
                                selectedModel = newModelID
                                if let info = connectedModels.first(where: { $0.modelID == newModelID }) {
                                    selectedProvider = info.aiProviderID
                                    appState.aiModel = info.modelID
                                    appState.aiProvider = info.aiProviderID
                                    subscriptionAuth.activeProvider = info.provider
                                    UserDefaults.standard.set(info.provider.rawValue, forKey: "subscriptionActiveProvider")
                                    UserDefaults.standard.set("subscription", forKey: "aiKeyMode")
                                    hasChanges = true
                                }
                            }
                        )) {
                            ForEach(subscriptionAuth.connectedProviders()) { prov in
                                Section(prov.displayName) {
                                    ForEach(prov.modelInfos) { m in
                                        HStack {
                                            Text("\(prov.displayName.components(separatedBy: " ").first ?? "Sub") : \(m.name)")
                                            if !m.badge.isEmpty {
                                                Text("[\(m.badge)]")
                                            }
                                        }
                                        .tag(m.modelID)
                                    }
                                }
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        
                        // Active Model Detail Banner
                        if let activeInfo = subscriptionAuth.findModel(id: selectedModel) {
                            let account = subscriptionAuth.getAccount(activeInfo.provider)
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(activeInfo.name)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text("[\(activeInfo.badge)]")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(.blue)
                                        Text("via \(activeInfo.provider.displayName)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Text(activeInfo.description)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if let account = account {
                                    Text(account.emailOrUser)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.04))
                                        .cornerRadius(4)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.2), lineWidth: 1))
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("No active web subscriptions connected. Sign in or connect at least one account below to enable subscription models.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.2), lineWidth: 1))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))

            Divider().opacity(0.6)

            // Provider Cards
            VStack(spacing: 12) {
                ForEach(SubscriptionProviderType.allCases) { provider in
                    let isConn = subscriptionAuth.isConnected(provider)
                    let account = subscriptionAuth.getAccount(provider)
                    let isGuideExpanded = expandedProviderGuide[provider.rawValue] ?? false
                    
                    VStack(alignment: .leading, spacing: 10) {
                        // Top Bar: Brand, Info, and Status
                        HStack(spacing: 10) {
                            AIProviderBrandIcon(provider: provider.providerIcon, size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(provider.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                    if isConn {
                                        Text("ACTIVE")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.green.opacity(0.12))
                                            .cornerRadius(3)
                                        
                                        if let src = account?.source, !src.isEmpty {
                                            Text(src)
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.primary.opacity(0.05))
                                                .cornerRadius(3)
                                        }
                                    }
                                }
                                Text(account?.emailOrUser ?? provider.helpInstruction)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                            
                        // Live health (from "Test connections")
                        if let health = healthProbe.results[provider.rawValue], isConn || health.status != .notConnected {
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(health.status == .ok ? Color.green : Color.orange)
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(health.status == .ok ? "\(health.hint) · \(health.latencyMs) ms · \(health.model)" : health.hint)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundColor(health.status == .ok ? .green : .orange)
                                    if health.status != .ok, !health.message.isEmpty {
                                        Text(health.message)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .lineLimit(3)
                                            .textSelection(.enabled)
                                    }
                                }
                                Spacer()
                            }
                        }

                        // Action Row
                        let isCurrentlySelectedSub = (aiKeyMode == "subscription" && subscriptionAuth.activeProvider == provider)
                        let existingByokKey = (providerKeys[provider.aiProviderID] ?? UserDefaults.standard.string(forKey: "\(provider.aiProviderID)_api_key") ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let showInlineKeyRow = (!isConn && (isGuideExpanded || provider == .tokenme || provider == .thai_gemini_enterprise)) || (isConn && isGuideExpanded && (provider.isAPIKeyBackedPortal || provider == .thai_gemini_enterprise))

                        HStack(spacing: 8) {
                            if isConn {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.shield.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 13))
                                    Text(isCurrentlySelectedSub ? "Active & Selected" : "Auto-Synced & Ready")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundColor(.green)
                                }
                                
                                Spacer()
                                
                                if !isCurrentlySelectedSub {
                                    Button("Use Subscription") {
                                        activateSubscriptionProvider(provider)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                
                                if provider.isAPIKeyBackedPortal {
                                    Button(isGuideExpanded ? "Close Key" : "Update Key") {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            expandedProviderGuide[provider.rawValue] = !isGuideExpanded
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                
                                Button("Disconnect") {
                                    subscriptionAuth.disconnect(provider: provider)
                                    hasChanges = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                // 🌟 Primary 1-Click Sign In & Auto-Sync
                                Button {
                                    webLoginProvider = provider
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.crop.circle.badge.checkmark")
                                            .font(.system(size: 12))
                                        Text(provider == .tokenme ? "Connect TokenMe" : "1-Click Sign In (Auto-Detect)")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.accentColor)
                                .controlSize(.regular)
                                
                                if provider == .tokenme {
                                    Button {
                                        NSWorkspace.shared.open(URL(string: "https://www.tokenme.limited")!)
                                    } label: {
                                        Label("Open Console", systemImage: "safari")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.regular)
                                }
                                
                                if provider.isAPIKeyBackedPortal && !existingByokKey.isEmpty {
                                    Button {
                                        subscriptionAuth.saveAccount(
                                            provider: provider,
                                            emailOrUser: "\(provider.shortLabel) Subscription",
                                            sessionToken: existingByokKey,
                                            source: "Synced API Key"
                                        )
                                        activateSubscriptionProvider(provider)
                                    } label: {
                                        Label("Sync Saved Key", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                    .controlSize(.regular)
                                }
                                
                                Spacer()
                                
                                if provider != .tokenme {
                                    // Advanced manual toggle (Hidden by default for non-technical users)
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            expandedProviderGuide[provider.rawValue] = !isGuideExpanded
                                        }
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: isGuideExpanded ? "chevron.up" : "gearshape")
                                                .font(.system(size: 9.5))
                                            Text(isGuideExpanded ? "Close Manual" : "Manual / Dev Mode")
                                                .font(.system(size: 10))
                                        }
                                        .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 2)

                        // Inline Token / API Key Entry (Always visible for TokenMe / Thai Gemini Enterprise when unconnected, or when toggled)
                        if showInlineKeyRow {
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    if provider == .thai_gemini_enterprise {
                                        TextField(
                                            "https://vertexaisearch.cloud.google/us/home/cid/1b5ab175-0783-4463-8a33-b61845396a2b/r/session/...",
                                            text: Binding(
                                                get: {
                                                    subscriptionTokenInputs[provider.rawValue]
                                                        ?? "https://vertexaisearch.cloud.google/us/home/cid/1b5ab175-0783-4463-8a33-b61845396a2b/r/session/2836962715286832461?csesidx=306441087"
                                                },
                                                set: { subscriptionTokenInputs[provider.rawValue] = $0 }
                                            )
                                        )
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11, design: .monospaced))
                                    } else {
                                        SecureField(
                                            provider == .tokenme
                                                ? "Paste TokenMe API key (tm_...) or cURL command"
                                                : "Paste Token / API Key / Cookie manually",
                                            text: Binding(
                                                get: { subscriptionTokenInputs[provider.rawValue] ?? "" },
                                                set: { subscriptionTokenInputs[provider.rawValue] = $0 }
                                            )
                                        )
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11, design: .monospaced))
                                    }
                                    
                                    if provider.isAPIKeyBackedPortal || provider == .thai_gemini_enterprise {
                                        Button("Paste") {
                                            if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                                               !clip.isEmpty {
                                                subscriptionTokenInputs[provider.rawValue] = clip
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                    
                                    Button("Connect") {
                                        let defaultVertexURL = "https://vertexaisearch.cloud.google/us/home/cid/1b5ab175-0783-4463-8a33-b61845396a2b/r/session/2836962715286832461?csesidx=306441087"
                                        let rawInput = subscriptionTokenInputs[provider.rawValue] ?? (provider == .thai_gemini_enterprise ? defaultVertexURL : "")
                                        let token = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                        let email = subscriptionEmailInputs[provider.rawValue] ?? ""
                                        if !token.isEmpty {
                                            subscriptionAuth.saveAccount(
                                                provider: provider,
                                                emailOrUser: email.isEmpty ? "\(provider.shortLabel) Subscription" : email,
                                                sessionToken: token,
                                                source: provider == .thai_gemini_enterprise ? "Vertex AI Search Session URL" : "Subscription Key"
                                            )
                                            subscriptionTokenInputs[provider.rawValue] = ""
                                            expandedProviderGuide[provider.rawValue] = false
                                            activateSubscriptionProvider(provider)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(provider != .thai_gemini_enterprise && (subscriptionTokenInputs[provider.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isConn ? Color.green.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        )
    }

    @ObservedObject private var localLLM = LocalLLMService.shared
    @ObservedObject private var llmGateway = LocalLLMGatewayService.shared
    @ObservedObject private var macLLMServer = MacLLMServer.shared
    
    @State private var showModelBrowser = false
    @State private var copiedGatewayQRLink = false
    @State private var copiedGatewayBaseURL = false
    @State private var copiedGatewayToken = false
    @State private var showQuickConnectToken = false
    @State private var isQRDropTargeted = false
    
    private var localLLMSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ── 0. macLLM Native Metal PagedAttention Kernel & Continuous Batching Engine ──
            macLLMKernelCard
            
            // ── 1. Local & LAN Servers (Auto-Discovery + Best Perf + 1-Field Smart Add/QR) ──
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Local & LAN Servers")
                        .font(.system(size: 13.5, weight: .semibold))
                    
                    if localLLM.isScanning {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    
                    Spacer()
                    
                    if !localLLM.detectedServers.isEmpty {
                        Button {
                            Task {
                                await localLLM.benchmarkAllServers()
                                if localLLM.autoSelectBestPerf {
                                    selectedProvider = "local"
                                    selectedModel = localLLM.activeModel
                                    hasChanges = true
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if localLLM.isBenchmarking {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "bolt").font(.system(size: 10.5, weight: .medium))
                                }
                                Text(localLLM.isBenchmarking ? "Testing…" : "Speed Test")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(localLLM.isBenchmarking || localLLM.isScanning)
                    }
                    
                    Button(action: { showModelBrowser = true }) {
                        Label("Models", systemImage: "square.grid.2x2")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button {
                        Task {
                            localLLM.scanLANEnabled = true
                            await localLLM.scanForServers()
                            if localLLM.activeServer != nil {
                                selectedProvider = "local"
                                selectedModel = localLLM.activeModel
                            }
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(localLLM.isScanning)
                }
                
                // Discovered Server List (This Mac + Wi-Fi/LAN + Paired QR)
                if localLLM.detectedServers.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.secondary.opacity(0.6))
                            .frame(width: 28, height: 28)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localLLM.isScanning ? "Searching This Mac & Local Network…" : "No exposed LLM server found yet")
                                .font(.system(size: 12, weight: .medium))
                            Text(localLLM.activeLANPeerCount > 0
                                 ? "Found \(String(localLLM.activeLANPeerCount)) Wi-Fi devices, but port 1234 is closed — on the other laptop's LM Studio, turn ON \"Serve on Local Network\"."
                                 : "Open LM Studio (turn ON Serve on Local Network) or Ollama — servers appear automatically.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                } else {
                    let poolServers = localLLM.connectedServers
                    let totalModels = poolServers.reduce(0) { $0 + $1.models.count }
                    HStack(spacing: 8) {
                        Circle()
                            .fill(poolServers.isEmpty ? Color.orange : Color.green)
                            .frame(width: 7, height: 7)
                        Text("Multi-Node Active Pool: \(poolServers.count) server(s) · \(totalModels) model(s) connected simultaneously")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.88))
                        Spacer()
                        if localLLM.detectedServers.filter({ $0.isOnline && !$0.requiresAuthToUnlock }).count > 1 {
                            Button {
                                localLLM.enableAllServersInPool()
                                localLLM.selectedModelId = "auto"
                                selectedProvider = "local"
                                selectedModel = "auto"
                                hasChanges = true
                            } label: {
                                Label("Load-Balance All (\(poolServers.count))", systemImage: "bolt.horizontal.circle.fill")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Route concurrent Local LLM requests across all connected servers using Least-In-Flight + Best-Perf load balancing")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.06))
                    .cornerRadius(7)

                    VStack(spacing: 6) {
                        ForEach(Array(localLLM.detectedServers.enumerated()), id: \.element.id) { index, server in
                            localServerRow(server: server, index: index)
                        }
                    }
                }
                
                // Installed Models across ALL connected servers in the pool
                let connectedPool = localLLM.connectedServers.filter { !$0.models.isEmpty }
                if !connectedPool.isEmpty {
                    Divider().opacity(0.5)
                    Text(connectedPool.count > 1
                         ? "Active Models Across \(connectedPool.count) Connected Servers"
                         : "Models on \(connectedPool[0].displayName)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 3) {
                        ForEach(connectedPool) { srv in
                            ForEach(srv.models) { model in
                                installedModelRow(model: model, server: srv, multiServerMode: connectedPool.count > 1)
                            }
                        }
                    }
                }
                
                Divider().opacity(0.5)
                
                // Single Unified Add / Pair Bar (IP, Host:Port, Port, comma-separated multi-endpoints, QR Link, Paste QR, or Drop QR Image)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        TextField("Add IP, Host:Port, or comma-separated list (e.g. 192.168.1.50:1234, 192.168.1.51:11434)", text: $localLLM.quickConnectInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                            .onChange(of: localLLM.quickConnectInput) { _ in
                                if localLLM.pairingStatusMessage != nil {
                                    localLLM.pairingStatusMessage = nil
                                }
                            }
                            .onSubmit {
                                connectQuickEndpointAction()
                            }
                        
                        if showQuickConnectToken || localLLM.detectedServers.contains(where: \.requiresAuthToUnlock) {
                            SecureField("Token", text: $localLLM.quickConnectAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                                .font(.system(size: 11, design: .monospaced))
                                .onSubmit {
                                    connectQuickEndpointAction()
                                }
                        }
                        
                        Button("Add") {
                            connectQuickEndpointAction()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(localLLM.quickConnectInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        
                        Button {
                            Task {
                                let ok = await localLLM.pairFromClipboard()
                                if ok {
                                    selectedProvider = "local"
                                    selectedModel = localLLM.activeModel
                                    hasChanges = true
                                }
                            }
                        } label: {
                            Label("Paste QR", systemImage: "doc.on.clipboard")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Connect from a copied QR image or link in Clipboard")
                        
                        Button {
                            pickQRCodeImageAndPair()
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Choose a QR code image file (or drop an image onto this card)")
                        
                        Button {
                            showQuickConnectToken.toggle()
                        } label: {
                            Image(systemName: "key")
                                .font(.system(size: 10.5))
                                .foregroundColor(showQuickConnectToken ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 3)
                        .help("Optional API Token")
                    }
                    
                    if let status = localLLM.pairingStatusMessage, !status.isEmpty {
                        Text(status)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isQRDropTargeted ? Color.primary.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .onDrop(of: [.image, .fileURL], isTargeted: $isQRDropTargeted) { providers in
                handleDroppedQRProviders(providers)
            }
            
            // ── 2. Share via QR Code (Identical Apple HIG Monochrome Language as Connect with Phone) ──
            localLLMWorldwideQRGatewayCard
        }
        .task {
            if localLLM.detectedServers.isEmpty && !localLLM.isScanning {
                await localLLM.scanForServers()
            }
        }
        .sheet(isPresented: $showModelBrowser) {
            ModelBrowserSheet(isPresented: $showModelBrowser) { activatedModelId in
                aiKeyMode = "local"
                selectedProvider = "local"
                selectedModel = activatedModelId
                appState.aiProvider = "local"
                appState.aiModel = activatedModelId
                UserDefaults.standard.set("local", forKey: "aiKeyMode")
                hasChanges = true
            }
        }
    }
    
    // MARK: - macLLM (vLLM for macOS) Metal PagedAttention Kernel Card
    
    private var macLLMKernelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 36, height: 36)
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary.opacity(0.85))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text("macLLM Kernel")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("vLLM FOR MACOS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.75))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(4)
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(macLLMServer.isRunning ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.4))
                                .frame(width: 5.5, height: 5.5)
                            Text(macLLMServer.isRunning ? "127.0.0.1:\(String(macLLMServer.listeningPort))" : "Offline")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(4)
                    }
                    
                    Text("\(macLLMServer.stats.gpuName) · \(String(macLLMServer.stats.unifiedMemoryGB)) GB Unified RAM · Metal PagedAttention (\(String(macLLMServer.stats.blockSizeTokens)) tok/block) · Continuous Batching")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button {
                    Task {
                        await macLLMServer.runFullBenchmark()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if macLLMServer.isBenchmarkingKernel {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "bolt.fill").font(.system(size: 9.5))
                        }
                        Text("Kernel Bench")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(macLLMServer.isBenchmarkingKernel)
                
                Button("Clear KV") {
                    macLLMServer.clearKVCache()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Clear Automatic Prefix Cache (APC) KV blocks")
            }
            
            // Telemetry Pills Row
            HStack(spacing: 8) {
                macLLMMetricPill(
                    title: "PAGED KV BLOCKS",
                    value: "\(String(macLLMServer.stats.usedKVBlocks + macLLMServer.stats.cachedPrefixBlocks)) / \(String(macLLMServer.stats.totalKVBlocks))",
                    subtitle: String(format: "%.1f%% pool", macLLMServer.stats.kvCacheUtilizationPercent)
                )
                macLLMMetricPill(
                    title: "PREFIX CACHE HIT",
                    value: String(format: "%.1f%%", macLLMServer.stats.prefixCacheHitRatePercent),
                    subtitle: "\(String(macLLMServer.stats.cachedPrefixBlocks)) APC blocks"
                )
                macLLMMetricPill(
                    title: "METAL KERNEL",
                    value: String(format: "%.1f µs", macLLMServer.stats.pagedAttentionLatencyUs),
                    subtitle: String(format: "%.1f GB/s", macLLMServer.stats.effectiveBandwidthGBps)
                )
                macLLMMetricPill(
                    title: "BATCH SCHEDULER",
                    value: "\(String(macLLMServer.stats.runningSequences)) run · \(String(macLLMServer.stats.waitingSequences)) wait",
                    subtitle: "\(String(macLLMServer.stats.totalRequestsServed)) reqs served"
                )
            }
            
            Text(macLLMServer.statusBanner)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .onAppear {
            macLLMServer.startIfNeeded(preferredPort: 11436)
        }
    }
    
    private func macLLMMetricPill(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035))
        .cornerRadius(7)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Share via QR Code Card (Matches PhoneCompanionSettingsView)
    
    private var localLLMWorldwideQRGatewayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 38, height: 38)
                    Image(systemName: "qrcode")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.primary.opacity(0.85))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Share via QR Code")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if llmGateway.isEnabled {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(llmGateway.isServerRunning ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.4))
                                    .frame(width: 5.5, height: 5.5)
                                Text(llmGateway.isServerRunning ? "Port \(String(llmGateway.listeningPort))" : "Starting")
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(4)
                        }
                    }
                    
                    Text("Scan with iPhone, Android, or another Mac to use this Local LLM over Wi-Fi or anywhere in the world.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Toggle("", isOn: $llmGateway.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            if llmGateway.isEnabled {
                Divider().opacity(0.5)
                
                HStack(alignment: .top, spacing: 16) {
                    // Left: Crisp White QR Card
                    VStack(alignment: .center, spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white)
                                .frame(width: 176, height: 176)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                                )
                            
                            if llmGateway.transportMode == .worldwide, case .starting(let statusMsg) = llmGateway.tunnelState {
                                VStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text(statusMsg)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.black.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 12)
                                }
                                .frame(width: 160, height: 160)
                            } else if let qrImage = llmGateway.qrCodeImage {
                                Image(nsImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 154, height: 154)
                            } else {
                                ProgressView().controlSize(.small)
                            }
                        }
                        
                        HStack(spacing: 6) {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(llmGateway.activePairingURL, forType: .string)
                                copiedGatewayQRLink = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copiedGatewayQRLink = false }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedGatewayQRLink ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 10, weight: .medium))
                                    Text(copiedGatewayQRLink ? "Copied" : "Copy Link")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.07))
                                .foregroundColor(.primary)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                if let url = URL(string: llmGateway.activePairingURL) {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 10, weight: .medium))
                                    Text("Open")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.04))
                                .foregroundColor(.secondary)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(width: 176)
                    }
                    
                    // Right: Monochrome Transport Radio Cards + Clean Endpoint Row
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            ForEach(LocalLLMShareTransportMode.allCases) { mode in
                                let isSelected = llmGateway.transportMode == mode
                                Button {
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        llmGateway.transportMode = mode
                                    }
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: mode.icon)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundColor(isSelected ? .primary : .secondary)
                                            .frame(width: 16, height: 16)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(mode.title)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            Text(mode == .lan ? "Instant on same network" : "Anywhere via HTTPS tunnel")
                                                .font(.system(size: 10.5))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                            .foregroundColor(isSelected ? .primary : .secondary.opacity(0.5))
                                            .font(.system(size: 12))
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .background(isSelected ? Color.primary.opacity(0.07) : Color.primary.opacity(0.02))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isSelected ? Color.primary.opacity(0.24) : Color.primary.opacity(0.07), lineWidth: 1)
                                    )
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        if llmGateway.transportMode == .lan && llmGateway.allNetworkAddresses.count > 1 {
                            HStack(spacing: 8) {
                                Text("Interface:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Picker("", selection: $llmGateway.selectedLANIP) {
                                    ForEach(llmGateway.allNetworkAddresses, id: \.ip) { item in
                                        Text("\(item.ip) (\(item.interface))").tag(item.ip)
                                    }
                                }
                                .labelsHidden()
                                .controlSize(.small)
                                .frame(maxWidth: 200)
                            }
                        } else if llmGateway.transportMode == .worldwide, case .failed(let err) = llmGateway.tunnelState {
                            HStack(spacing: 8) {
                                Text(err)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Button("Reconnect") {
                                    llmGateway.startWorldwideTunnel()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                        
                        // Clean Endpoint & Key Bar
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(llmGateway.activeOpenAIBaseURL)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary.opacity(0.9))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.primary.opacity(0.04))
                                    .cornerRadius(6)
                                
                                Button(copiedGatewayBaseURL ? "Copied" : "Copy URL") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(llmGateway.activeOpenAIBaseURL, forType: .string)
                                    copiedGatewayBaseURL = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copiedGatewayBaseURL = false }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button(copiedGatewayToken ? "Copied Key" : "Copy Key") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(llmGateway.apiToken, forType: .string)
                                    copiedGatewayToken = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copiedGatewayToken = false }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button {
                                    llmGateway.rotateToken()
                                } label: {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 10.5))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Generate new access token & QR code")
                            }
                            
                            if !llmGateway.connectedClients.isEmpty {
                                Text("\(String(llmGateway.connectedClients.count)) device(s) connected")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .onAppear {
            llmGateway.refreshNetworkAddresses()
            if llmGateway.isEnabled {
                llmGateway.startServerIfNeeded()
            }
        }
    }
    
    // MARK: - Clean Apple HIG Server & Model Rows
    
    private func localServerRow(server: DetectedLLMServer, index: Int) -> some View {
        let isActive = localLLM.selectedServerIndex == index && !server.requiresAuthToUnlock
        let isInPool = localLLM.isServerInActivePool(server) && server.isOnline && !server.requiresAuthToUnlock
        let inFlight = localLLM.inFlightCount(forEndpoint: server.endpoint)
        let isTestingThis = localLLM.benchmarkingServerID == server.id
        let isRemovablePaired = localLLM.pairedRemoteEndpoints.contains { item in
            "\(item.scheme.lowercased())://\(item.host.lowercased()):\(item.port)" == server.deduplicationKey.lowercased()
        }
        
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 28, height: 28)
                AIProviderBrandIcon(provider: server.type.brandKey, size: 17)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.nodeName != nil ? "\(server.nodeName!) · \(server.type.rawValue)" : server.type.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    
                    if server.sourceKind != .thisMac {
                        Text(server.sourceKind == .worldwideQR ? "QR" : server.sourceKind.rawValue)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(4)
                    }
                    
                    if server.isBestPerf {
                        HStack(spacing: 2) {
                            Image(systemName: "bolt.fill").font(.system(size: 8))
                            Text("Best").font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(.primary.opacity(0.85))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(4)
                    }

                    if inFlight > 0 {
                        Text("⚡ \(inFlight) active")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.14))
                            .cornerRadius(4)
                    }
                    
                    if server.requiresAuthToUnlock {
                        Text("Token Required")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 5) {
                    Text("\(server.hostPortLabel) · \(String(server.models.count)) model(s) · \(String(server.latencyMs)) ms")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    if let tps = server.tokensPerSecond {
                        Text("· \(String(format: "%.1f", tps)) tok/s")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.85))
                    }
                }
            }
            
            Spacer()
            
            if server.requiresAuthToUnlock {
                Button("Unlock") {
                    showQuickConnectToken = true
                    localLLM.quickConnectInput = server.endpoint
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                if !server.models.isEmpty {
                    Button {
                        Task {
                            await localLLM.benchmarkServer(server.id)
                            if localLLM.autoSelectBestPerf {
                                selectedProvider = "local"
                                selectedModel = localLLM.activeModel
                                hasChanges = true
                            }
                        }
                    } label: {
                        if isTestingThis {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "bolt")
                                .font(.system(size: 10.5))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(localLLM.isBenchmarking)
                    .help("Measure tok/s speed")
                }

                Button {
                    localLLM.toggleServerInPool(server)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isInPool ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundColor(isInPool ? .green : .secondary)
                        Text(isInPool ? "Connected" : "Paused")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Keep this server connected simultaneously in the Multi-Node Active Pool")
                
                if !server.models.isEmpty && isActive {
                    Picker("", selection: Binding(
                        get: { localLLM.selectedModelId },
                        set: { newId in
                            localLLM.selectedModelId = newId
                            LocalLLMService.cachedModel = newId
                            selectedProvider = "local"
                            selectedModel = newId
                            hasChanges = true
                        }
                    )) {
                        ForEach(server.models) { m in
                            Text(m.isWarmLoaded ? "⚡ \(m.displayName)" : m.displayName).tag(m.id)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 155)
                }
                
                if !isActive {
                    Button("Primary") {
                        localLLM.selectServer(at: index)
                        selectedProvider = "local"
                        selectedModel = localLLM.activeModel
                        hasChanges = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            if isRemovablePaired {
                Button {
                    localLLM.removePairedEndpoint(server.deduplicationKey)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 2)
                .help("Remove server")
            }
        }
        .padding(10)
        .background((isActive || isInPool) ? Color.primary.opacity(0.05) : Color.primary.opacity(0.02))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.primary.opacity(0.22) : (isInPool ? Color.green.opacity(0.28) : Color.primary.opacity(0.06)), lineWidth: 1)
        )
    }
    
    private func installedModelRow(model: LocalLLMModel, server: DetectedLLMServer, multiServerMode: Bool) -> some View {
        let pinnedId = "\(server.endpoint)||\(model.id)"
        let isSelected = (localLLM.selectedModelId == model.id && LocalLLMService.cachedEndpoint == server.endpoint)
            || selectedModel == pinnedId
            || (!multiServerMode && localLLM.selectedModelId == model.id)
        return HStack(spacing: 8) {
            Text(model.name)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)

            if multiServerMode {
                Text("\(server.displayName) · \(server.hostPortLabel)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
            }
            
            if model.isWarmLoaded {
                Text("Loaded")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
            }
            if let q = model.quantization {
                Text(q)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            if let s = model.size {
                Text(s)
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.primary)
            } else {
                Button("Select") {
                    localLLM.selectModelAcrossServers(modelId: model.id, endpointHint: server.endpoint)
                    selectedProvider = "local"
                    selectedModel = multiServerMode ? pinnedId : model.id
                    hasChanges = true
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isSelected ? Color.primary.opacity(0.05) : Color.clear)
        .cornerRadius(6)
    }
    
    // MARK: - Local LLM Helper Actions
    
    private func connectQuickEndpointAction() {
        let raw = localLLM.quickConnectInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let key = localLLM.quickConnectAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let ok = await localLLM.connectOrPairEndpoint(raw, explicitAPIKey: key.isEmpty ? nil : key)
            if ok {
                selectedProvider = "local"
                selectedModel = localLLM.activeModel
                hasChanges = true
            }
        }
    }
    
    private func pickQRCodeImageAndPair() {
        let panel = NSOpenPanel()
        panel.title = "Select Pairing QR Code Image"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            Task {
                let ok = await localLLM.pairFromQRImage(img)
                if ok {
                    selectedProvider = "local"
                    selectedModel = localLLM.activeModel
                    hasChanges = true
                }
            }
        }
    }
    
    private func handleDroppedQRProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let fileURL: URL?
                if let data = item as? Data {
                    fileURL = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    fileURL = item as? URL
                }
                if let fileURL, let img = NSImage(contentsOf: fileURL) {
                    Task { @MainActor in
                        let ok = await localLLM.pairFromQRImage(img)
                        if ok {
                            selectedProvider = "local"
                            selectedModel = localLLM.activeModel
                            hasChanges = true
                        }
                    }
                }
            }
            return true
        }
        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                if let img = object as? NSImage {
                    Task { @MainActor in
                        let ok = await localLLM.pairFromQRImage(img)
                        if ok {
                            selectedProvider = "local"
                            selectedModel = localLLM.activeModel
                            hasChanges = true
                        }
                    }
                }
            }
            return true
        }
        return false
    }
    
    private func byokCustomEndpointBox(for providerId: String) -> some View {
        let providerName = aiProviders.first(where: { $0.id == providerId })?.name ?? providerId.uppercased()
        let defaultEndpoint = aiProviders.first(where: { $0.id == providerId })?.endpoint ?? "https://api.openai.com/v1"
        let baseURLBinding = Binding<String>(
            get: { providerBaseURLs[providerId] ?? "" },
            set: { newVal in
                providerBaseURLs[providerId] = newVal
                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    UserDefaults.standard.removeObject(forKey: "byok_base_url_\(providerId)")
                    if providerId == "custom" {
                        UserDefaults.standard.removeObject(forKey: "byok_custom_base_url")
                    }
                } else {
                    UserDefaults.standard.set(trimmed, forKey: "byok_base_url_\(providerId)")
                    if providerId == "custom" {
                        UserDefaults.standard.set(trimmed, forKey: "byok_custom_base_url")
                    }
                }
                hasChanges = true
            }
        )
        let customModelBinding = Binding<String>(
            get: { providerCustomModels[providerId] ?? "" },
            set: { newVal in
                providerCustomModels[providerId] = newVal
                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    UserDefaults.standard.removeObject(forKey: "byok_custom_model_\(providerId)")
                } else {
                    UserDefaults.standard.set(trimmed, forKey: "byok_custom_model_\(providerId)")
                }
                hasChanges = true
            }
        )
        let hasCustomURL = !(providerBaseURLs[providerId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.teal)
                Text("\(providerName) — Custom Base URL / Cloudflare Tunnel")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                if hasCustomURL {
                    Button("Reset to Official URL") {
                        baseURLBinding.wrappedValue = ""
                        byokEndpointStatusMessage = "Reset to official endpoint (\(defaultEndpoint))"
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.orange)
                } else {
                    Text("Default: \(defaultEndpoint)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 8) {
                Text("Base URL:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)
                
                TextField(
                    providerId == "custom"
                        ? "https://your-tunnel.trycloudflare.com/v1 or https://custom-gateway.example.com/v1"
                        : "Leave blank for official (\(defaultEndpoint)) or enter Custom / Cloudflare Tunnel URL",
                    text: baseURLBinding
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                
                Button("Test & Load") {
                    testAndFetchByokModels(for: providerId)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isTestingByokEndpoint)
            }
            
            HStack(spacing: 8) {
                Text("Custom Model:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)
                
                TextField("Optional exact Model ID (e.g. qwen2.5-coder:32b, gpt-4.1, claude-sonnet-4-6)", text: customModelBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit {
                        applyCustomByokModel(for: providerId)
                    }
                
                Button("Use Model") {
                    applyCustomByokModel(for: providerId)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled((providerCustomModels[providerId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            if !byokEndpointStatusMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: byokEndpointStatusMessage.contains("Failed") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(byokEndpointStatusMessage.contains("Failed") ? .orange : .green)
                    Text(byokEndpointStatusMessage)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(hasCustomURL ? Color.teal.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    private func applyCustomByokModel(for providerId: String) {
        let trimmed = (providerCustomModels[providerId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedProvider = providerId
        selectedModel = trimmed
        appState.aiProvider = providerId
        appState.aiModel = trimmed
        UserDefaults.standard.set(providerId, forKey: "aiProvider")
        UserDefaults.standard.set(trimmed, forKey: "aiModel")
        UserDefaults.standard.set(trimmed, forKey: "byok_custom_model_\(providerId)")
        byokEndpointStatusMessage = "Active model set to '\(trimmed)'"
        hasChanges = true
    }
    
    private func testAndFetchByokModels(for providerId: String) {
        // Persist current key and base URL before probing so AIModelCatalog sees them immediately
        let trimmedKey = (providerKeys[providerId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            UserDefaults.standard.set(trimmedKey, forKey: "\(providerId)_api_key")
            appState.apiKeys[providerId] = trimmedKey
        }
        let trimmedURL = (providerBaseURLs[providerId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty {
            UserDefaults.standard.set(trimmedURL, forKey: "byok_base_url_\(providerId)")
            if providerId == "custom" {
                UserDefaults.standard.set(trimmedURL, forKey: "byok_custom_base_url")
            }
        } else {
            UserDefaults.standard.removeObject(forKey: "byok_base_url_\(providerId)")
        }
        
        isTestingByokEndpoint = true
        byokEndpointStatusMessage = "Connecting to endpoint and querying models…"
        Task {
            await AIModelCatalog.shared.fetchLiveModelsForProvider(providerId)
            await MainActor.run {
                isTestingByokEndpoint = false
                if let p = modelCatalog.provider(providerId), !p.models.isEmpty {
                    let liveCount = p.models.filter { $0.badge == "LIVE" || $0.badge == "CUSTOM" }.count
                    if let first = p.models.first {
                        let customOverride = (providerCustomModels[providerId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        selectedModel = customOverride.isEmpty ? first.id : customOverride
                    }
                    let resolvedURL = StreamableAIProvider(rawValue: providerId)?.directBaseURL ?? p.endpoint
                    if liveCount > 0 {
                        byokEndpointStatusMessage = "Connected to \(resolvedURL) — loaded \(liveCount) live models."
                    } else {
                        byokEndpointStatusMessage = "Endpoint ready (\(resolvedURL)). Select a model or enter a Custom Model ID."
                    }
                } else {
                    byokEndpointStatusMessage = "Failed to fetch models — verify URL or enter a Custom Model ID manually."
                }
            }
        }
    }

    private func aiProviderKeyCard(_ provider: AIProviderInfo) -> some View {
        let key = Binding<String>(
            get: { providerKeys[provider.id] ?? "" },
            set: { providerKeys[provider.id] = $0; hasChanges = true }
        )
        let isVisible = showAPIKey[provider.id] ?? false
        let hasKey = !(providerKeys[provider.id] ?? "").isEmpty
        let customURL = (providerBaseURLs[provider.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCustomURL = !customURL.isEmpty
        let isDefault = selectedProvider == provider.id
        let effectiveEndpoint = hasCustomURL ? customURL : provider.endpoint
        
        return HStack(spacing: 12) {
            // Col 1: Provider Info (Fixed 195pt) with authentic brand icon
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .frame(width: 28, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                    AIProviderBrandIcon(provider: provider.id, size: 18)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(provider.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        if isDefault {
                            Text("ACTIVE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 4).padding(.vertical, 1.5)
                                .background(Color.primary.opacity(0.1))
                                .cornerRadius(3)
                        }
                        if hasCustomURL {
                            Text("URL")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.teal)
                                .padding(.horizontal, 4).padding(.vertical, 1.5)
                                .background(Color.teal.opacity(0.14))
                                .cornerRadius(3)
                        }
                    }
                    Text(effectiveEndpoint)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(hasCustomURL ? .teal : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(width: 195, alignment: .leading)
            
            // Col 2: Key Input Field (Flexible)
            HStack(spacing: 8) {
                if isVisible {
                    TextField(provider.id == "custom" || hasCustomURL ? "API Key (optional for public tunnel)..." : "API Key...", text: key)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                } else {
                    SecureField(provider.id == "custom" || hasCustomURL ? "API Key (optional for Cloudflare Tunnel)" : "Paste API key here", text: key)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                
                Button {
                    showAPIKey[provider.id] = !isVisible
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(isVisible ? "Hide Key" : "Show Key")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            )
            
            // Col 3: Status / Action (Fixed 72pt, perfectly aligned)
            HStack(spacing: 6) {
                if isDefault {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        Text("Active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green)
                    }
                } else if hasKey || hasCustomURL || provider.id == "custom" {
                    Button {
                        selectedProvider = provider.id
                        let customModel = (providerCustomModels[provider.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !customModel.isEmpty {
                            selectedModel = customModel
                        } else if let first = provider.models.first {
                            selectedModel = first.id
                        }
                        hasChanges = true
                    } label: {
                        Text("Select")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10).padding(.vertical, 3.5)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "circle.dashed")
                        .foregroundColor(.secondary.opacity(0.35))
                        .font(.system(size: 12))
                }
            }
            .frame(width: 72, alignment: .trailing)
        }
        .frame(minHeight: 38, maxHeight: 38)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isDefault ? Color.primary.opacity(0.05) : Color.clear)
        )
    }
    
    // MARK: - Tools Settings
    
    private var toolsSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(title: "Code Execution")
            
            Toggle("Auto-run on save", isOn: .constant(false))
            Toggle("Clear console before run", isOn: .constant(true))
            
            SettingsSectionHeader(title: "Git")
            
            Toggle("Auto-fetch on open", isOn: .constant(true))
            Toggle("Show commit message suggestions", isOn: .constant(true))
            
            SettingsSectionHeader(title: "Refactoring")
            
            Toggle("Use AI for refactoring", isOn: .constant(true))
        }
    }
    
    // MARK: - Helpers
    
    private func loadCurrentSettings() {
        selectedProvider = appState.aiProvider
        selectedModel = appState.aiModel
        fontSize = appState.fontSize
        fontFamily = appState.fontFamily
        showLineNumbers = appState.showLineNumbers
        showSidebar = appState.sidebarVisible
        showConsole = appState.consoleVisible
        selectedTheme = appState.appTheme
        
        playgroundFontName = appState.playgroundFontName
        playgroundFontSize = appState.playgroundFontSize
        playgroundFontWeight = appState.playgroundFontWeight
        
        cellFontName = appState.cellFontName
        cellFontSize = appState.cellFontSize
        cellFontWeight = appState.cellFontWeight
        
        agentFontName = appState.agentFontName
        agentFontSize = appState.agentFontSize
        
        agentMode = appState.agentMode
        agentAutoApproveTools = appState.agentAutoApproveTools
        agentCustomInstructions = appState.agentCustomInstructions
        agentMaxIterations = appState.agentMaxIterations
        
        // Load ALL provider keys, custom BYOK base URLs, and custom model IDs
        let providers = [
            "gemini", "openai", "anthropic", "deepseek",
            "openrouter", "groq", "mistral", "kimi", "perplexity", "perch", "tokenme", "typhoon",
            "cerebras", "together", "fireworks", "minimax", "nvidia",
            "grok", "qwen", "glm", "custom"
        ]
        for p in providers {
            providerKeys[p] = appState.apiKeys[p] ?? UserDefaults.standard.string(forKey: "\(p)_api_key") ?? ""
            providerBaseURLs[p] = UserDefaults.standard.string(forKey: "byok_base_url_\(p)") ?? ""
            providerCustomModels[p] = UserDefaults.standard.string(forKey: "byok_custom_model_\(p)") ?? ""
        }
        if (providerBaseURLs["custom"] ?? "").isEmpty,
           let legacyCustomURL = UserDefaults.standard.string(forKey: "byok_custom_base_url"),
           !legacyCustomURL.isEmpty {
            providerBaseURLs["custom"] = legacyCustomURL
        }
        let legacyKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        if (providerKeys["openai"] ?? "").isEmpty && !legacyKey.isEmpty {
            providerKeys["openai"] = legacyKey
        }
        apiKey = providerKeys[selectedProvider] ?? ""
        let savedKeyMode = UserDefaults.standard.string(forKey: "aiKeyMode")
        aiKeyMode = savedKeyMode ?? "direct"
        microRentToken = ""
        dotminiLicenseKey = UserDefaults.standard.string(forKey: "dotminiLicenseKey") ?? ""
    }
    
    private func saveAllSettings(deferThemeUntilDismissed: Bool = false) {
        if appState.aiProvider != selectedProvider { appState.aiProvider = selectedProvider }
        if appState.aiModel != selectedModel { appState.aiModel = selectedModel }
        if appState.fontSize != fontSize { appState.fontSize = fontSize }
        if appState.fontFamily != fontFamily { appState.fontFamily = fontFamily }
        if appState.showLineNumbers != showLineNumbers { appState.showLineNumbers = showLineNumbers }
        if appState.sidebarVisible != showSidebar { appState.sidebarVisible = showSidebar }
        if appState.consoleVisible != showConsole { appState.consoleVisible = showConsole }
        if appState.appTheme != selectedTheme {
            let targetTheme = selectedTheme
            if deferThemeUntilDismissed {
                let state = appState
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    if state.appTheme != targetTheme {
                        state.appTheme = targetTheme
                    }
                }
            } else {
                appState.appTheme = targetTheme
            }
        }
        
        if appState.playgroundFontName != playgroundFontName { appState.playgroundFontName = playgroundFontName }
        if appState.playgroundFontSize != playgroundFontSize { appState.playgroundFontSize = playgroundFontSize }
        if appState.playgroundFontWeight != playgroundFontWeight { appState.playgroundFontWeight = playgroundFontWeight }
        
        if appState.cellFontName != cellFontName { appState.cellFontName = cellFontName }
        if appState.cellFontSize != cellFontSize { appState.cellFontSize = cellFontSize }
        if appState.cellFontWeight != cellFontWeight { appState.cellFontWeight = cellFontWeight }
        
        if appState.agentFontName != agentFontName { appState.agentFontName = agentFontName }
        if appState.agentFontSize != agentFontSize { appState.agentFontSize = agentFontSize }
        
        if appState.agentMode != agentMode { appState.agentMode = agentMode }
        if appState.agentAutoApproveTools != agentAutoApproveTools { appState.agentAutoApproveTools = agentAutoApproveTools }
        if appState.agentCustomInstructions != agentCustomInstructions { appState.agentCustomInstructions = agentCustomInstructions }
        if appState.agentMaxIterations != agentMaxIterations { appState.agentMaxIterations = agentMaxIterations }
        
        // Save ALL provider keys without triggering redundant Keychain IPC for unchanged keys
        let defaults = UserDefaults.standard
        defaults.set(aiKeyMode, forKey: "aiKeyMode")
        defaults.set(dotminiLicenseKey, forKey: "dotminiLicenseKey")
        defaults.set(agentFontName, forKey: "agentFontName")
        defaults.set(Double(agentFontSize), forKey: "agentFontSize")
        defaults.set(Double(fontSize), forKey: "fontSize")
        defaults.set(fontFamily, forKey: "fontFamily")
        defaults.set(playgroundFontName, forKey: "playgroundFontName")
        defaults.set(Double(playgroundFontSize), forKey: "playgroundFontSize")
        defaults.set(playgroundFontWeight, forKey: "playgroundFontWeight")
        defaults.set(cellFontName, forKey: "cellFontName")
        defaults.set(Double(cellFontSize), forKey: "cellFontSize")
        defaults.set(cellFontWeight, forKey: "cellFontWeight")
        defaults.set(agentMode, forKey: "agentMode")
        defaults.set(agentAutoApproveTools, forKey: "agentAutoApproveTools")
        defaults.set(agentCustomInstructions, forKey: "agentCustomInstructions")
        defaults.set(agentMaxIterations, forKey: "agentMaxIterations")
        let apiKeyBackedSubs: Set<String> = [
            "openrouter", "groq", "mistral", "kimi", "perplexity", "perch", "tokenme", "typhoon",
            "cerebras", "together", "fireworks", "minimax", "nvidia", "grok", "qwen", "deepseek", "glm"
        ]
        for (provider, rawKey) in providerKeys {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                let existingKey = appState.apiKeys[provider]
                if existingKey != key {
                    appState.apiKeys[provider] = key
                }
                defaults.set(key, forKey: "\(provider)_api_key")
                if apiKeyBackedSubs.contains(provider),
                   let subType = SubscriptionProviderType(rawValue: provider) {
                    let existingSubToken = SubscriptionAuthManager.shared.accounts[subType]?.sessionToken
                    if existingKey != key || existingSubToken != key {
                        SubscriptionAuthManager.shared.saveAccount(
                            provider: subType,
                            emailOrUser: "\(subType.shortLabel) Direct Key",
                            sessionToken: key,
                            source: "Direct API Key"
                        )
                    }
                }
            } else if appState.apiKeys[provider] != nil {
                appState.apiKeys.removeValue(forKey: provider)
                defaults.removeObject(forKey: "\(provider)_api_key")
            }
        }
        if let openai = providerKeys["openai"]?.trimmingCharacters(in: .whitespacesAndNewlines), !openai.isEmpty {
            defaults.set(openai, forKey: "apiKey")
        }
        
        for (provider, rawURL) in providerBaseURLs {
            let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                defaults.set(trimmed, forKey: "byok_base_url_\(provider)")
                if provider == "custom" {
                    defaults.set(trimmed, forKey: "byok_custom_base_url")
                }
            } else {
                defaults.removeObject(forKey: "byok_base_url_\(provider)")
                if provider == "custom" {
                    defaults.removeObject(forKey: "byok_custom_base_url")
                }
            }
        }
        for (provider, rawCustomModel) in providerCustomModels {
            let trimmed = rawCustomModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                defaults.set(trimmed, forKey: "byok_custom_model_\(provider)")
            } else {
                defaults.removeObject(forKey: "byok_custom_model_\(provider)")
            }
        }
        if aiKeyMode == "direct",
           let customActiveModel = providerCustomModels[selectedProvider]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customActiveModel.isEmpty {
            selectedModel = customActiveModel
            if appState.aiModel != customActiveModel {
                appState.aiModel = customActiveModel
            }
        }
        
        defaults.set(selectedProvider, forKey: "aiProvider")
        defaults.set(selectedModel, forKey: "aiModel")
        let providerToRefresh = selectedProvider
        Task {
            await AIModelCatalog.shared.fetchLiveModelsForProvider(providerToRefresh)
        }
        defaults.set(fontSize, forKey: "fontSize")
        defaults.set(fontFamily, forKey: "fontFamily")
        defaults.set(showLineNumbers, forKey: "showLineNumbers")
        defaults.set(showSidebar, forKey: "sidebarVisible")
        defaults.set(showConsole, forKey: "consoleVisible")
        defaults.set(selectedTheme.rawValue, forKey: "appTheme")
        
        defaults.set(playgroundFontName, forKey: "playgroundFontName")
        defaults.set(playgroundFontSize, forKey: "playgroundFontSize")
        defaults.set(playgroundFontWeight, forKey: "playgroundFontWeight")
        
        defaults.set(cellFontName, forKey: "cellFontName")
        defaults.set(cellFontSize, forKey: "cellFontSize")
        defaults.set(cellFontWeight, forKey: "cellFontWeight")
        
        defaults.removeObject(forKey: "microRentToken")
        unsetenv("MICRORENT_TOKEN")
        unsetenv("USE_MICRORENT_PROXY")
    }
    
    private func envVarName(for provider: String) -> String {
        switch provider {
        case "gemini": return "GEMINI_API_KEY"
        case "openai": return "OPENAI_API_KEY"
        case "anthropic": return "ANTHROPIC_API_KEY"
        case "glm": return "GLM_API_KEY"
        case "deepseek": return "DEEPSEEK_API_KEY"
        case "openrouter": return "OPENROUTER_API_KEY"
        case "groq": return "GROQ_API_KEY"
        case "mistral": return "MISTRAL_API_KEY"
        case "kimi": return "KIMI_API_KEY"
        case "perplexity": return "PERPLEXITY_API_KEY"
        case "perch": return "PERCH_API_KEY"
        case "tokenme": return "TOKENME_API_KEY"
        case "typhoon": return "TYPHOON_API_KEY"
        case "cerebras": return "CEREBRAS_API_KEY"
        case "together": return "TOGETHER_API_KEY"
        case "fireworks": return "FIREWORKS_API_KEY"
        case "minimax": return "MINIMAX_API_KEY"
        case "nvidia": return "NVIDIA_API_KEY"
        case "grok": return "GROK_API_KEY"
        case "qwen": return "QWEN_API_KEY"
        default: return "\(provider.uppercased())_API_KEY"
        }
    }
}

struct SettingsTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct CodexSidebarRow: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .frame(width: 18)
                    .foregroundColor(selected ? .primary : .secondary)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? .primary : .secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.09)
                          : (hovering ? Color.primary.opacity(0.045) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.top, 8)
    }
}

// MARK: - Simulator Sheet

struct SimulatorSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var platform: String = "ios"
    @State private var iosDevices: [SimulatorDevice] = []
    @State private var androidDevices: [(name: String, id: String)] = []
    @State private var flutterEmulators: [(name: String, id: String)] = []
    @State private var selectedDevice: String = ""
    @State private var selectedName: String = ""
    @State private var isLoading: Bool = false
    @State private var statusMessage: String = ""
    @State private var showingCreateSheet: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "iphone")
                    .foregroundColor(.accentColor)
                Text("Launch Simulator")
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button("Launch") {
                    launchSimulator()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDevice.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Platform picker
                Picker("Platform", selection: $platform) {
                    HStack {
                        Image(systemName: "apple.logo")
                        Text("iOS Simulator")
                    }.tag("ios")
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Android Emulator")
                    }.tag("android")
                    HStack {
                        Image(systemName: "bird.fill")
                        Text("Flutter")
                    }.tag("flutter")
                }
                .pickerStyle(.segmented)
                .onChange(of: platform) { _ in loadDevices() }
                
                HStack {
                    Text("SELECT DEVICE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: { showingCreateSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                            Text("Create")
                        }
                        .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                
                Divider()
                
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading devices...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            if platform == "ios" {
                                ForEach(iosDevices, id: \.udid) { device in
                                    DeviceRow(
                                        name: device.name,
                                        detail: device.runtime,
                                        isSelected: selectedDevice == device.udid,
                                        isBooted: device.state == "Booted"
                                    ) {
                                        selectedDevice = device.udid
                                        selectedName = device.name
                                    }
                                }
                                if iosDevices.isEmpty {
                                    EmptyDeviceView(message: "No iOS simulators found.")
                                }
                            } else if platform == "android" {
                                ForEach(androidDevices, id: \.id) { device in
                                    DeviceRow(
                                        name: device.name,
                                        detail: "Android",
                                        isSelected: selectedDevice == device.id,
                                        isBooted: false
                                    ) {
                                        selectedDevice = device.id
                                        selectedName = device.name
                                    }
                                }
                                if androidDevices.isEmpty {
                                    EmptyDeviceView(message: "No Android emulators found.")
                                }
                            } else {
                                ForEach(flutterEmulators, id: \.id) { emulator in
                                    DeviceRow(
                                        name: emulator.name,
                                        detail: "Flutter Emulator",
                                        isSelected: selectedDevice == emulator.id,
                                        isBooted: false
                                    ) {
                                        selectedDevice = emulator.id
                                        selectedName = emulator.name
                                    }
                                }
                                if flutterEmulators.isEmpty {
                                    EmptyDeviceView(message: "No Flutter emulators found.")
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
            }
            .padding(20)
        }
        .frame(width: 400, height: 400)
        .onAppear { loadDevices() }
        .sheet(isPresented: $showingCreateSheet) {
            CreateDeviceSheet(platform: platform) {
                loadDevices()
            }
        }
    }
    
    private func loadDevices() {
        isLoading = true
        selectedDevice = ""
        selectedName = ""
        
        Task {
            do {
                if platform == "ios" {
                    let devices = try await SimulatorManager.shared.listIOSSimulators()
                    await MainActor.run {
                        iosDevices = devices.sorted { $0.name < $1.name }
                        if iosDevices.isEmpty {
                            statusMessage = "No iOS simulators found. Create one above."
                        } else {
                            statusMessage = ""
                        }
                    }
                } else if platform == "android" {
                    let devices = try await SimulatorManager.shared.listAndroidEmulators()
                    await MainActor.run {
                        androidDevices = devices
                        if androidDevices.isEmpty {
                            statusMessage = "No Android devices found. Create one above."
                        } else {
                            statusMessage = ""
                        }
                    }
                } else {
                    let emulators = try await SimulatorManager.shared.listFlutterEmulators()
                    await MainActor.run {
                        flutterEmulators = emulators
                        if flutterEmulators.isEmpty {
                            statusMessage = "No Flutter emulators found. Create one above."
                        } else {
                            statusMessage = ""
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Error loading devices: \(error.localizedDescription)"
                }
            }
            isLoading = false
        }
    }
    
    private func launchSimulator() {
        statusMessage = "Launching \(selectedName)..."
        
        Task {
            do {
                if platform == "ios" {
                    try await SimulatorManager.shared.bootSimulator(udid: selectedDevice)
                    // Open Simulator app
                    let openSim = Process()
                    openSim.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    openSim.arguments = ["-a", "Simulator"]
                    try? openSim.run()
                    
                    await MainActor.run {
                        appState.consoleOutput += "📱 Launched iOS Simulator: \(selectedName)\n"
                        dismiss()
                    }
                } else if platform == "android" {
                    try await SimulatorManager.shared.launchAndroidEmulator(avdName: selectedDevice)
                    await MainActor.run {
                        appState.consoleOutput += "📱 Launched Android Emulator: \(selectedName)\n"
                        dismiss()
                    }
                } else {
                    // Flutter launch logic
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/local/bin/flutter")
                    process.arguments = ["emulators", "--launch", selectedDevice]
                    try? process.run()
                    
                    await MainActor.run {
                        appState.consoleOutput += "📱 Launched Flutter Emulator: \(selectedName)\n"
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Launch failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct EmptyDeviceView: View {
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

struct CreateDeviceSheet: View {
    let platform: String
    let onCreated: () -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String = ""
    @State private var selectedDeviceType: String = ""
    @State private var selectedRuntime: String = ""
    @State private var androidPackage: String = "system-images;android-33;google_apis;arm64-v8a"
    
    @State private var deviceTypes: [(name: String, id: String)] = []
    @State private var runtimes: [String] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Create \(platform == "ios" ? "Simulator" : "Emulator")")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            
            Divider()
            
            Form {
                Section("Device Info") {
                    TextField("Name", text: $name)
                    
                    if platform == "ios" {
                        Picker("Device Type", selection: $selectedDeviceType) {
                            Text("Select Type").tag("")
                            ForEach(deviceTypes, id: \.id) { type in
                                Text(type.name).tag(type.id)
                            }
                        }
                        
                        Picker("Runtime", selection: $selectedRuntime) {
                            Text("Select Runtime").tag("")
                            ForEach(runtimes, id: \.self) { runtime in
                                Text(runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")).tag(runtime)
                            }
                        }
                    } else {
                        TextField("System Image Package", text: $androidPackage)
                        Text("Example: system-images;android-33;google_apis;arm64-v8a")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
            }
            
            Spacer()
            
            Divider()
            
            HStack {
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.5).padding(.trailing, 8)
                }
                Button("Create") {
                    createDevice()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || (platform == "ios" && (selectedDeviceType.isEmpty || selectedRuntime.isEmpty)) || isLoading)
            }
            .padding()
        }
        .frame(width: 400, height: platform == "ios" ? 400 : 350)
        .onAppear {
            if platform == "ios" {
                fetchIOSOptions()
            }
        }
    }
    
    private func fetchIOSOptions() {
        isLoading = true
        Task {
            do {
                let types = try await SimulatorManager.shared.listAvailableDeviceTypes()
                let runs = try await SimulatorManager.shared.listAvailableRuntimes()
                await MainActor.run {
                    deviceTypes = types.sorted { $0.name < $1.name }
                    runtimes = runs.sorted()
                    if let firstType = deviceTypes.first(where: { $0.name.contains("iPhone 15") }) {
                        selectedDeviceType = firstType.id
                    }
                    if let lastRun = runtimes.last {
                        selectedRuntime = lastRun
                    }
                }
            } catch {
                errorMessage = "Failed to fetch options: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    private func createDevice() {
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                if platform == "ios" {
                    try await SimulatorManager.shared.createIOSSimulator(name: name, deviceTypeId: selectedDeviceType, runtimeId: selectedRuntime)
                } else {
                    try await SimulatorManager.shared.createAndroidEmulator(name: name, package: androidPackage)
                }
                await MainActor.run {
                    onCreated()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        }
    }
}


struct SimulatorDevice {
    let name: String
    let udid: String
    let state: String
    let runtime: String
}

struct DeviceRow: View {
    let name: String
    let detail: String
    let isSelected: Bool
    let isBooted: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "iphone")
                    .foregroundColor(isBooted ? .green : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isBooted {
                    Text("Running")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                }
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Syntax Highlighter

class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()
    
    private let keywords: [String: [String]] = [
        "swift": ["func", "var", "let", "class", "struct", "enum", "protocol", "extension", "import", "return", "if", "else", "for", "while", "switch", "case", "default", "guard", "throw", "try", "catch", "async", "await", "private", "public", "internal", "fileprivate", "static", "override", "init", "deinit", "self", "super", "nil", "true", "false", "in", "where", "typealias", "associatedtype", "some", "any", "@Published", "@State", "@Binding", "@ObservableObject", "@MainActor", "actor"],
        "python": ["def", "class", "import", "from", "return", "if", "elif", "else", "for", "while", "try", "except", "finally", "with", "as", "is", "not", "and", "or", "in", "True", "False", "None", "pass", "break", "continue", "raise", "yield", "lambda", "global", "nonlocal", "assert", "del", "async", "await", "self"],
        "py": ["def", "class", "import", "from", "return", "if", "elif", "else", "for", "while", "try", "except", "finally", "with", "as", "is", "not", "and", "or", "in", "True", "False", "None", "pass", "break", "continue", "raise", "yield", "lambda", "global", "nonlocal", "assert", "del", "async", "await", "self"],
        "javascript": ["function", "const", "let", "var", "class", "extends", "import", "export", "return", "if", "else", "for", "while", "switch", "case", "default", "try", "catch", "finally", "throw", "async", "await", "new", "this", "super", "true", "false", "null", "undefined", "typeof", "instanceof", "of", "in", "=>", "yield", "debugger"],
        "js": ["function", "const", "let", "var", "class", "extends", "import", "export", "return", "if", "else", "for", "while", "switch", "case", "default", "try", "catch", "finally", "throw", "async", "await", "new", "this", "super", "true", "false", "null", "undefined", "typeof", "instanceof", "of", "in", "=>", "yield", "debugger"],
        "typescript": ["function", "const", "let", "var", "class", "extends", "import", "export", "return", "if", "else", "for", "while", "switch", "case", "default", "try", "catch", "finally", "throw", "async", "await", "new", "this", "super", "true", "false", "null", "undefined", "typeof", "instanceof", "of", "in", "interface", "type", "enum", "implements", "readonly", "private", "public", "protected", "as", "is", "keyof", "declare", "abstract"],
        "ts": ["function", "const", "let", "var", "class", "extends", "import", "export", "return", "if", "else", "for", "while", "switch", "case", "default", "try", "catch", "finally", "throw", "async", "await", "new", "this", "super", "true", "false", "null", "undefined", "typeof", "instanceof", "of", "in", "interface", "type", "enum", "implements", "readonly", "private", "public", "protected", "as", "is", "keyof", "declare", "abstract"],
        "rust": ["fn", "let", "mut", "const", "struct", "enum", "impl", "trait", "use", "mod", "pub", "crate", "self", "super", "return", "if", "else", "for", "while", "loop", "match", "async", "await", "move", "ref", "where", "type", "dyn", "static", "unsafe", "extern", "true", "false", "Some", "None", "Ok", "Err"],
        "rs": ["fn", "let", "mut", "const", "struct", "enum", "impl", "trait", "use", "mod", "pub", "crate", "self", "super", "return", "if", "else", "for", "while", "loop", "match", "async", "await", "move", "ref", "where", "type", "dyn", "static", "unsafe", "extern", "true", "false", "Some", "None", "Ok", "Err"],
        "go": ["func", "var", "const", "type", "struct", "interface", "package", "import", "return", "if", "else", "for", "switch", "case", "default", "go", "select", "chan", "defer", "range", "map", "make", "new", "nil", "true", "false", "fallthrough", "goto"],
        "golang": ["func", "var", "const", "type", "struct", "interface", "package", "import", "return", "if", "else", "for", "switch", "case", "default", "go", "select", "chan", "defer", "range", "map", "make", "new", "nil", "true", "false", "fallthrough", "goto"],
        "java": ["class", "interface", "enum", "extends", "implements", "import", "package", "public", "private", "protected", "static", "final", "abstract", "return", "if", "else", "for", "while", "switch", "case", "default", "try", "catch", "finally", "throw", "throws", "new", "this", "super", "null", "true", "false", "void", "int", "boolean", "String", "@Override", "record", "sealed"],
        "kotlin": ["class", "interface", "object", "fun", "val", "var", "constructor", "init", "this", "super", "package", "import", "public", "private", "protected", "internal", "abstract", "final", "open", "override", "lateinit", "companion", "data", "sealed", "enum", "annotation", "suspend", "if", "else", "when", "for", "while", "do", "return", "break", "continue", "throw", "try", "catch", "finally", "is", "in", "as", "true", "false", "null"],
        "kt": ["class", "interface", "object", "fun", "val", "var", "constructor", "init", "this", "super", "package", "import", "public", "private", "protected", "internal", "abstract", "final", "open", "override", "lateinit", "companion", "data", "sealed", "enum", "annotation", "suspend", "if", "else", "when", "for", "while", "do", "return", "break", "continue", "throw", "try", "catch", "finally", "is", "in", "as", "true", "false", "null"],
        "c": ["int", "char", "float", "double", "void", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "struct", "union", "enum", "typedef", "const", "static", "extern", "sizeof", "NULL", "true", "false", "#include", "#define", "#ifdef", "#ifndef", "#endif"],
        "cpp": ["int", "char", "float", "double", "void", "bool", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "class", "struct", "union", "enum", "typedef", "const", "static", "extern", "virtual", "override", "public", "private", "protected", "namespace", "using", "template", "typename", "new", "delete", "nullptr", "true", "false", "#include", "#define", "constexpr", "concept", "co_await", "co_return"],
        "c++": ["int", "char", "float", "double", "void", "bool", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "class", "struct", "union", "enum", "typedef", "const", "static", "extern", "virtual", "override", "public", "private", "protected", "namespace", "using", "template", "typename", "new", "delete", "nullptr", "true", "false", "#include", "#define", "constexpr", "concept", "co_await", "co_return"],
        "objective-c": ["@interface", "@implementation", "@protocol", "@end", "@property", "@synthesize", "@dynamic", "@class", "@import", "@selector", "id", "instancetype", "BOOL", "YES", "NO", "nil", "Nil", "self", "super", "nonatomic", "strong", "weak", "readonly", "if", "else", "for", "while", "return"],
        "objc": ["@interface", "@implementation", "@protocol", "@end", "@property", "@synthesize", "@dynamic", "@class", "@import", "@selector", "id", "instancetype", "BOOL", "YES", "NO", "nil", "Nil", "self", "super", "nonatomic", "strong", "weak", "readonly", "if", "else", "for", "while", "return"],
        "csharp": ["class", "struct", "record", "interface", "enum", "namespace", "using", "public", "private", "protected", "internal", "static", "readonly", "virtual", "override", "abstract", "sealed", "async", "await", "if", "else", "switch", "case", "default", "for", "foreach", "in", "while", "do", "break", "continue", "return", "throw", "try", "catch", "finally", "from", "where", "select", "new", "this", "base", "null", "true", "false", "var", "Task", "string", "int", "bool"],
        "cs": ["class", "struct", "record", "interface", "enum", "namespace", "using", "public", "private", "protected", "internal", "static", "readonly", "virtual", "override", "abstract", "sealed", "async", "await", "if", "else", "switch", "case", "default", "for", "foreach", "in", "while", "do", "break", "continue", "return", "throw", "try", "catch", "finally", "from", "where", "select", "new", "this", "base", "null", "true", "false", "var", "Task", "string", "int", "bool"],
        "dart": ["class", "enum", "mixin", "extension", "typedef", "import", "export", "abstract", "const", "final", "late", "static", "factory", "required", "async", "await", "if", "else", "switch", "case", "default", "for", "while", "do", "break", "continue", "return", "throw", "try", "catch", "finally", "extends", "with", "implements", "super", "this", "new", "is", "true", "false", "null", "var", "dynamic", "void", "Widget", "BuildContext"],
        "php": ["function", "fn", "class", "interface", "trait", "enum", "extends", "implements", "public", "private", "protected", "static", "final", "readonly", "abstract", "const", "var", "if", "else", "elseif", "switch", "case", "default", "match", "for", "foreach", "as", "while", "do", "break", "continue", "return", "try", "catch", "finally", "throw", "echo", "print", "isset", "empty", "require", "include", "namespace", "use", "new", "true", "false", "null"],
        "ruby": ["def", "class", "module", "end", "if", "elsif", "else", "unless", "while", "until", "for", "in", "do", "begin", "rescue", "ensure", "raise", "return", "break", "next", "yield", "super", "self", "alias", "true", "false", "nil", "attr_accessor", "require", "include"],
        "rb": ["def", "class", "module", "end", "if", "elsif", "else", "unless", "while", "until", "for", "in", "do", "begin", "rescue", "ensure", "raise", "return", "break", "next", "yield", "super", "self", "alias", "true", "false", "nil", "attr_accessor", "require", "include"],
        "shell": ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until", "case", "esac", "select", "function", "export", "source", "alias", "local", "declare", "readonly", "return", "exit", "set", "unset", "echo", "printf", "test", "cd", "pwd", "true", "false"],
        "sh": ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until", "case", "esac", "select", "function", "export", "source", "alias", "local", "declare", "readonly", "return", "exit", "set", "unset", "echo", "printf", "test", "cd", "pwd", "true", "false"],
        "bash": ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until", "case", "esac", "select", "function", "export", "source", "alias", "local", "declare", "readonly", "return", "exit", "set", "unset", "echo", "printf", "test", "cd", "pwd", "true", "false"],
        "zsh": ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until", "case", "esac", "select", "function", "export", "source", "alias", "local", "declare", "readonly", "return", "exit", "set", "unset", "echo", "printf", "test", "cd", "pwd", "true", "false"],
        "sql": ["select", "from", "where", "insert", "into", "values", "update", "set", "delete", "join", "inner", "left", "right", "full", "outer", "cross", "on", "using", "group", "by", "having", "order", "asc", "desc", "limit", "offset", "union", "all", "intersect", "except", "distinct", "create", "alter", "drop", "truncate", "table", "view", "index", "schema", "database", "primary", "key", "foreign", "references", "and", "or", "not", "in", "is", "null", "like", "ilike", "between", "exists", "case", "when", "then", "else", "end", "cast", "as", "count", "sum", "avg", "min", "max", "coalesce"],
        "html": ["html", "head", "body", "div", "span", "p", "a", "img", "ul", "ol", "li", "table", "tr", "td", "th", "form", "input", "button", "script", "style", "link", "meta", "title", "class", "id", "href", "src", "nav", "header", "footer", "main", "section", "article", "svg", "path", "circle", "rect"],
        "css": ["color", "background", "margin", "padding", "border", "font", "display", "position", "top", "left", "right", "bottom", "width", "height", "flex", "grid", "justify", "align", "transform", "transition", "animation", "@media", "@keyframes", "hover", "active", "focus", "box-shadow", "border-radius", "opacity", "z-index"],
        "json": ["true", "false", "null"],
        "yaml": ["true", "false", "yes", "no", "on", "off", "null", "True", "False", "None"],
        "markdown": ["TODO", "FIXME", "NOTE", "WARNING", "IMPORTANT", "TIP"],
        "lua": ["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while", "print", "require"],
        "zig": ["const", "var", "fn", "pub", "usingnamespace", "struct", "enum", "union", "error", "test", "comptime", "inline", "extern", "export", "defer", "errdefer", "return", "break", "continue", "if", "else", "switch", "while", "for", "try", "catch", "async", "await", "suspend", "resume", "null", "undefined", "true", "false"],
        "r": ["if", "else", "repeat", "while", "function", "for", "in", "next", "break", "TRUE", "FALSE", "NULL", "Inf", "NaN", "NA", "library", "require"],
        "julia": ["function", "macro", "quote", "let", "local", "global", "const", "do", "struct", "module", "using", "import", "export", "return", "break", "continue", "if", "elseif", "else", "for", "while", "try", "catch", "finally", "throw", "true", "false", "nothing"],
        "elixir": ["def", "defp", "defmodule", "defmacro", "defprotocol", "defimpl", "do", "end", "if", "unless", "case", "cond", "with", "for", "try", "rescue", "catch", "after", "receive", "send", "import", "require", "use", "alias", "fn", "true", "false", "nil"],
        "solidity": ["contract", "interface", "library", "is", "pragma", "solidity", "import", "function", "modifier", "event", "error", "struct", "enum", "mapping", "public", "private", "internal", "external", "view", "pure", "payable", "memory", "storage", "calldata", "virtual", "override", "returns", "return", "emit", "revert", "require", "assert", "true", "false"],
        "ardium": ["fn", "var", "let", "mut", "struct", "class", "enum", "import", "extern", "async", "await", "export", "test", "interrupt", "@owned", "@State", "@External", "@export", "if", "else", "elif", "loop", "while", "for", "return", "break", "continue", "match", "true", "false", "nil", "null", "alloc", "free", "print", "println"]
    ]
    
    func highlight(_ code: String, language: String, fontSize: CGFloat, theme: AppTheme) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: code)
        let fullRange = NSRange(location: 0, length: code.utf16.count)
        
        // Base attributes from theme
        attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), range: fullRange)
        attributedString.addAttribute(.foregroundColor, value: theme.editorText, range: fullRange)
        
        // Get language keywords
        let lang = language.lowercased()
        let langKeywords = keywords[lang] ?? keywords["javascript"] ?? []
        
        // Highlight comments first (so they override everything else)
        highlightPattern(in: attributedString, pattern: "//[^\n]*", color: theme.commentColor)
        highlightPattern(in: attributedString, pattern: "#[^\n]*", color: theme.commentColor)
        highlightPattern(in: attributedString, pattern: "--[^\n]*", color: theme.commentColor)
        highlightPattern(in: attributedString, pattern: "/\\*[\\s\\S]*?\\*/", color: theme.commentColor)
        highlightPattern(in: attributedString, pattern: "<!--[\\s\\S]*?-->", color: theme.commentColor)
        
        // Highlight strings
        highlightPattern(in: attributedString, pattern: "\"[^\"\\\\]*(\\\\.[^\"\\\\]*)*\"", color: theme.stringColor)
        highlightPattern(in: attributedString, pattern: "'[^'\\\\]*(\\\\.[^'\\\\]*)*'", color: theme.stringColor)
        highlightPattern(in: attributedString, pattern: "`[^`]*`", color: theme.stringColor)
        
        // Highlight numbers
        highlightPattern(in: attributedString, pattern: "\\b\\d+(\\.\\d+)?\\b", color: theme.numberColor)
        highlightPattern(in: attributedString, pattern: "\\b0x[0-9a-fA-F]+\\b", color: theme.numberColor)
        
        // Highlight keywords (case-insensitive for SQL and HTML)
        let isCaseInsensitive = (lang == "sql" || lang == "html")
        let regexOptions: NSRegularExpression.Options = isCaseInsensitive ? [.caseInsensitive] : []
        for keyword in langKeywords {
            let escapedKeyword = NSRegularExpression.escapedPattern(for: keyword)
            highlightPattern(in: attributedString, pattern: "\\b\(escapedKeyword)\\b", color: theme.keywordColor, options: regexOptions)
        }
        
        // Highlight types (capitalized words - classes, structs, etc.)
        highlightPattern(in: attributedString, pattern: "\\b[A-Z][a-zA-Z0-9_]*\\b", color: theme.typeColor)
        
        // Highlight function calls
        highlightPattern(in: attributedString, pattern: "\\b[a-z_][a-zA-Z0-9_]*(?=\\()", color: theme.functionColor)
        
        // Highlight decorators/attributes (Swift, Python, Java, Ardium)
        highlightPattern(in: attributedString, pattern: "@[a-zA-Z_][a-zA-Z0-9_]*", color: theme.keywordColor)
        
        return attributedString
    }
    
    private func highlightPattern(in attributedString: NSMutableAttributedString, pattern: String, color: NSColor, options: NSRegularExpression.Options = []) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let string = attributedString.string
        let range = NSRange(location: 0, length: string.utf16.count)
        
        regex.enumerateMatches(in: string, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range {
                attributedString.addAttribute(.foregroundColor, value: color, range: matchRange)
            }
        }
    }
}

// MARK: - Modular Sheet Modifiers for Fast Type-Checking

struct PrimarySheetsModifier: ViewModifier {
    @ObservedObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $appState.showingAITrainer) {
                AITrainerView()
            }
            .sheet(isPresented: $appState.showingPythonEnv) {
                PythonEnvSheet()
            }
            .sheet(isPresented: $appState.showingRuntimeManager) {
                RuntimeManagerView()
            }
    }
}

struct SecondarySheetsModifier: ViewModifier {
    @ObservedObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $appState.showingGitSettings) {
                GitSettingsView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showingCommitDialog) {
                CommitSheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showingSimulatorDialog) {
                SimulatorSheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showingNewFileDialog) {
                NewFileSheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showingSubAgentMonitor) {
                SubAgentMonitorView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showingKeyboardShortcuts) {
                KeyboardShortcutsCheatSheetView()
                    .environmentObject(appState)
            }
    }
}

struct StudioSheetsModifier: ViewModifier {
    @ObservedObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $appState.showingCollaborationView) {
                CollaborationView()
                    .environmentObject(appState)
                    .frame(minWidth: 700, minHeight: 500)
            }
            .sheet(isPresented: $appState.showingCICDView) {
                CICDPipelineView()
                    .environmentObject(appState)
                    .frame(minWidth: 950, minHeight: 650)
            }
            .sheet(isPresented: $appState.showingDatabaseStudio) {
                DatabaseStudioView()
                    .environmentObject(appState)
                    .frame(minWidth: 1000, minHeight: 700)
            }
            .sheet(isPresented: $appState.showingContainerView) {
                ContainerView()
                    .environmentObject(appState)
                    .frame(minWidth: 950, minHeight: 650)
            }
            .sheet(isPresented: $appState.showingProjectRuntime) {
                ProjectRuntimeView()
            }
    }
}

// MARK: - Global Window-Level Shortcuts Modifier

struct GlobalKeyboardShortcutsModifier: ViewModifier {
    @ObservedObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .background(navigationAndPanelShortcuts)
            .background(executionAndControlModeShortcuts)
            .background(optionModeShortcuts)
    }

    @ViewBuilder
    private var navigationAndPanelShortcuts: some View {
        Group {
            // HUD Cheat Sheet (⌘/)
            Button("") {
                appState.showingKeyboardShortcuts.toggle()
            }
            .keyboardShortcut("/", modifiers: .command)
            .hidden()

            // Tabs & Navigation (⌘], ⌘[, ⌘⌥W)
            Button("") {
                appState.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: .command)
            .hidden()

            Button("") {
                appState.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: .command)
            .hidden()

            Button("") {
                appState.closeOtherTabs()
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .hidden()

            // Panels & Layout (⌘J, ⌘I, ⌘⌥G, ⌘⌥P)
            Button("") {
                appState.toggleConsole()
            }
            .keyboardShortcut("j", modifiers: .command)
            .hidden()

            Button("") {
                appState.toggleAgenticContext()
            }
            .keyboardShortcut("i", modifiers: .command)
            .hidden()

            Button("") {
                appState.toggleGitPanel()
            }
            .keyboardShortcut("g", modifiers: [.command, .option])
            .hidden()

            Button("") {
                appState.showingPreviewView.toggle()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .hidden()
        }
    }

    @ViewBuilder
    private var executionAndControlModeShortcuts: some View {
        Group {
            // Code Execution & Build (⌘R, ⌘⇧B, ⌘., ⌘⌥F)
            Button("") {
                appState.runCode()
            }
            .keyboardShortcut("r", modifiers: .command)
            .hidden()

            Button("") {
                appState.buildProject()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .hidden()

            Button("") {
                appState.stopExecution()
            }
            .keyboardShortcut(".", modifiers: .command)
            .hidden()

            Button("") {
                appState.formatCode()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .hidden()

            // Editor Modes (Control + 1..5)
            Button("") { appState.switchToMode(.code) }
                .keyboardShortcut("1", modifiers: .control)
                .hidden()
            Button("") { appState.switchToMode(.aiAgent) }
                .keyboardShortcut("2", modifiers: .control)
                .hidden()
            Button("") { appState.switchToMode(.notebook) }
                .keyboardShortcut("3", modifiers: .control)
                .hidden()
            Button("") { appState.switchToMode(.playground) }
                .keyboardShortcut("4", modifiers: .control)
                .hidden()
            Button("") { appState.switchToMode(.science) }
                .keyboardShortcut("5", modifiers: .control)
                .hidden()
        }
    }

    @ViewBuilder
    private var optionModeShortcuts: some View {
        Group {
            // Editor Modes (Control + 6..9, 0)
            Button("") { appState.switchToMode(.browser) }
                .keyboardShortcut("6", modifiers: .control)
                .hidden()
            Button("") { appState.switchToMode(.remoteX) }
                .keyboardShortcut("7", modifiers: .control)
                .hidden()
            Button("") { appState.switchToMode(.embedded) }
                .keyboardShortcut("8", modifiers: .control)
                .hidden()
            Button("") { appState.openAPIStudio() }
                .keyboardShortcut("9", modifiers: .control)
                .hidden()
            Button("") { appState.showingWelcomeHome = true }
                .keyboardShortcut("0", modifiers: .control)
                .hidden()

            // Option alternatives for Mode Switching (⌘⌥1..9)
            Button("") { appState.switchToMode(.code) }
                .keyboardShortcut("1", modifiers: [.command, .option])
                .hidden()
            Button("") { appState.switchToMode(.aiAgent) }
                .keyboardShortcut("2", modifiers: [.command, .option])
                .hidden()
            Button("") { appState.switchToMode(.notebook) }
                .keyboardShortcut("3", modifiers: [.command, .option])
                .hidden()
            Button("") { appState.switchToMode(.playground) }
                .keyboardShortcut("4", modifiers: [.command, .option])
                .hidden()
            Button("") { appState.switchToMode(.science) }
                .keyboardShortcut("5", modifiers: [.command, .option])
                .hidden()
        }
        .background(optionModeHighShortcuts)
    }

    @ViewBuilder
    private var optionModeHighShortcuts: some View {
        Group {
            Button("") { appState.switchToMode(.browser) }
                .keyboardShortcut("6", modifiers: [.command, .option])
                .hidden()
            Button("") { appState.switchToMode(.remoteX) }
                .keyboardShortcut("7", modifiers: [.command, .option])
                .hidden()
            Button("") { appState.switchToMode(.embedded) }
                .keyboardShortcut("8", modifiers: [.command, .option])
                .hidden()
            Button("") { appState.openAPIStudio() }
                .keyboardShortcut("9", modifiers: [.command, .option])
                .hidden()
        }
    }
}


