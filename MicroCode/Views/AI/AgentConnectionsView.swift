//
//  AgentConnectionsView.swift
//  MicroCode
//
//  Frictionless, 1-Click Agent Connections & Setup Wizard.
//  Inspired by Workser's zero-friction agent onboarding with embedded terminal,
//  1-click install/login runners, and live subscription verification.
//
//  Copyright © 2026 AIPRENEUR — SPU AI CLUB. All rights reserved.
//

import SwiftUI
import AppKit

// MARK: - Agent Connection Model

public enum AgentConnectionType: String, CaseIterable, Identifiable {
    case claudeCode = "claude_code"
    case agy = "agy"
    case openCode = "opencode"
    case codex = "codex"
    case microcodeNative = "microcode_native"
    case cursorAgent = "cursor_agent"
    case githubCopilot = "github_copilot"
    case freeModel = "free_model"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .agy: return "Antigravity (AGY)"
        case .openCode: return "OpenCode"
        case .codex: return "Codex"
        case .microcodeNative: return "MicroCode Native"
        case .cursorAgent: return "Cursor Agent"
        case .githubCopilot: return "GitHub Copilot"
        case .freeModel: return "Free AI Model"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .claudeCode: return "Anthropic CLI agent with hybrid reasoning"
        case .agy: return "Google Antigravity CLI (Gemini 3.8 / Claude / GPT-OSS)"
        case .openCode: return "Open-source coding agent & local models"
        case .codex: return "OpenAI Codex CLI & flagship coding models"
        case .microcodeNative: return "In-app engine with BYOK / Web Subscription"
        case .cursorAgent: return "Cursor background agent CLI"
        case .githubCopilot: return "GitHub Copilot workspace CLI"
        case .freeModel: return "DeepSeek & Nemotron free models — no card needed"
        }
    }
    
    public var requirementBadge: String {
        switch self {
        case .claudeCode: return "Needs Claude Pro"
        case .agy: return "Gemini 3.8 / Claude / GPT-OSS"
        case .openCode: return "Free & Local Models"
        case .codex: return "Needs ChatGPT Plus"
        case .microcodeNative: return "Ready — one click"
        case .cursorAgent: return "Needs Cursor Pro"
        case .githubCopilot: return "Needs Copilot (any paid plan)"
        case .freeModel: return "Free to run, no card needed"
        }
    }
    
    public var isRecommended: Bool {
        return self == .claudeCode || self == .agy
    }
    
    public var iconName: String {
        switch self {
        case .claudeCode: return "brain.head.profile"
        case .agy: return "sparkles"
        case .openCode: return "laptopcomputer"
        case .codex: return "cpu"
        case .microcodeNative: return "bolt.shield.fill"
        case .cursorAgent: return "square.stack.3d.up.fill"
        case .githubCopilot: return "chevron.left.forwardslash.chevron.right"
        case .freeModel: return "gift.fill"
        }
    }
    
    public var iconColor: Color {
        switch self {
        case .claudeCode: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .agy: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .openCode: return Color(red: 0.88, green: 0.35, blue: 0.28)
        case .codex: return Color(red: 0.06, green: 0.64, blue: 0.50)
        case .microcodeNative: return .accentColor
        case .cursorAgent: return .purple
        case .githubCopilot: return .primary
        case .freeModel: return .blue
        }
    }
    
    public var installCommand: String {
        switch self {
        case .claudeCode: return "npm install -g @anthropic-ai/claude-code"
        case .agy: return "curl -fsSL https://antigravity.google/install.sh | bash"
        case .openCode: return "npm install -g opencode-ai@latest"
        case .codex: return "npm install -g @openai/codex"
        case .cursorAgent: return "curl -fsSL https://cursor.com/install-cli | bash"
        case .githubCopilot: return "npm install -g @github/copilot-cli"
        case .freeModel, .microcodeNative: return ""
        }
    }
    
    public var loginCommand: String {
        switch self {
        case .claudeCode: return "claude auth login"
        case .agy: return "agy auth login"
        case .openCode: return "opencode auth login"
        case .codex: return "codex login"
        case .cursorAgent: return "cursor auth login"
        case .githubCopilot: return "copilot auth"
        case .freeModel, .microcodeNative: return ""
        }
    }
    
    var acpType: ACPAgentType? {
        switch self {
        case .claudeCode: return .claudeCode
        case .agy: return .agy
        case .openCode: return .openCode
        case .codex: return .codexEngine
        default: return nil
        }
    }
}

// MARK: - Main Agent Connections View

public struct AgentConnectionsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var acpHost = ACPHostService.shared
    @ObservedObject var discovery = LocalEcosystemDiscovery.shared
    @Environment(\.presentationMode) var presentationMode
    
    @State private var activeWizardTarget: AgentConnectionType? = nil
    @State private var toastMessage: String? = nil
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
            
            if let target = activeWizardTarget {
                AgentSetupWizardView(target: target, onBack: {
                    activeWizardTarget = nil
                }, onConnected: {
                    activeWizardTarget = nil
                    presentationMode.wrappedValue.dismiss()
                })
            } else {
                connectionsList
            }
        }
        .frame(minWidth: 740, idealWidth: 780, minHeight: 580, idealHeight: 620)
        .overlay(alignment: .bottom) {
            if let toast = toastMessage {
                Text(toast)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            acpHost.detectInstalledAgents()
            Task {
                await discovery.refresh()
            }
        }
    }
    
    // MARK: - Connections List
    
    private var connectionsList: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agent connections")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("MicroCode runs your tasks on an AI coding agent installed on this computer, under your own subscription. You stay signed in to the agent's own CLI — MicroCode never sees those credentials.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                }
                
                Spacer()
                
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            // List of Agents
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(AgentConnectionType.allCases) { type in
                        if type == .freeModel {
                            freeModelCard
                        } else {
                            agentCard(for: type)
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 20)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Use the full setup guide") {
                    if let url = URL(string: "https://docs.microcode.dev/agents") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.system(size: 11))
                .buttonStyle(.link)
                
                Spacer()
                
                Button("Skip for now") {
                    presentationMode.wrappedValue.dismiss()
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        }
    }
    
    // MARK: - Agent Card
    
    private func agentCard(for type: AgentConnectionType) -> some View {
        let status = statusFor(type)
        let isConnected = isCurrentAgent(type)
        
        return Button {
            activeWizardTarget = type
        } label: {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(type.iconColor.opacity(0.12))
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: type.iconName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(type.iconColor)
                }
                
                // Details
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(type.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if !type.requirementBadge.isEmpty {
                            Text(type.requirementBadge)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06))
                                .foregroundColor(.secondary)
                                .clipShape(Capsule())
                        }
                        
                        if type.isRecommended {
                            Text("Recommended")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.14))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
                    }
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 6, height: 6)
                        
                        Text(status.label)
                            .font(.system(size: 11))
                            .foregroundColor(status.color == .secondary ? .secondary : status.color)
                        
                        if isConnected {
                            Text("• Active in Chat")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isConnected ? Color.green.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: isConnected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Free Model Banner Card
    
    private var freeModelCard: some View {
        Button {
            connectFreeModel()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: "gift.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Don't have an AI subscription? Try a free AI model")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Sets up OpenCode / MicroCode with nemotron-3.5-lightning-free — free to run, no card needed.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("1-Click Connect")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blue.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.blue.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helpers
    
    private struct AgentStatus {
        let label: String
        let color: Color
    }
    
    private func statusFor(_ type: AgentConnectionType) -> AgentStatus {
        switch type {
        case .claudeCode:
            if let _ = discovery.engines.first(where: { $0.id == "claude_code" && $0.isInstalled }) {
                return AgentStatus(label: "Ready — one click", color: .green)
            }
            return AgentStatus(label: "Not installed", color: .secondary)
            
        case .agy:
            if let _ = discovery.engines.first(where: { $0.id == "agy" && $0.isInstalled }) {
                return AgentStatus(label: "Ready — one click", color: .green)
            }
            return AgentStatus(label: "Not installed", color: .secondary)
            
        case .openCode:
            if let engine = discovery.engines.first(where: { $0.id == "opencode" && $0.isInstalled }) {
                if engine.isAuthenticated {
                    return AgentStatus(label: "Ready — one click", color: .green)
                } else {
                    return AgentStatus(label: "Installed, needs sign-in", color: .orange)
                }
            }
            return AgentStatus(label: "Not installed", color: .secondary)
            
        case .codex:
            if let _ = discovery.engines.first(where: { $0.id == "codex" && $0.isInstalled }) {
                return AgentStatus(label: "Ready — one click", color: .green)
            }
            return AgentStatus(label: "Not installed", color: .secondary)
            
        case .microcodeNative:
            return AgentStatus(label: "Ready — one click", color: .green)
            
        case .cursorAgent, .githubCopilot:
            return AgentStatus(label: "Not installed", color: .secondary)
            
        case .freeModel:
            return AgentStatus(label: "Free to run", color: .blue)
        }
    }
    
    private func isCurrentAgent(_ type: AgentConnectionType) -> Bool {
        switch type {
        case .agy:
            return appState.aiProvider == "agy"
        case .claudeCode:
            return appState.aiProvider == "claude_code"
        case .openCode:
            return appState.aiProvider == "opencode"
        case .codex:
            return appState.aiProvider == "codex"
        case .microcodeNative:
            return !["agy", "claude_code", "opencode", "codex", "zed"].contains(appState.aiProvider)
        default:
            return false
        }
    }
    
    private func connectFreeModel() {
        if let openCode = discovery.engines.first(where: { $0.id == "opencode" && $0.isInstalled }) {
            appState.aiProvider = "opencode"
            appState.aiModel = "opencode/nemotron-3.5-lightning-free"
            _ = acpHost.quickConnect(.openCode)
            showToast("Connected to Free Nemotron 3.5 via OpenCode!")
        } else {
            appState.aiProvider = "deepseek"
            appState.aiModel = "deepseek-flash"
            showToast("Configured Free DeepSeek Flash model!")
        }
        appState.saveSettings()
    }
    
    private func showToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
        }
    }
}

// MARK: - Agent Setup Wizard View (with Embedded Interactive Terminal)

public struct AgentSetupWizardView: View {
    let target: AgentConnectionType
    let onBack: () -> Void
    let onConnected: () -> Void
    
    @EnvironmentObject var appState: AppState
    @ObservedObject var acpHost = ACPHostService.shared
    @ObservedObject var discovery = LocalEcosystemDiscovery.shared
    
    @State private var terminalLog: String = ""
    @State private var terminalInput: String = ""
    @State private var isRunningCommand: Bool = false
    @State private var currentProcess: Process? = nil
    @State private var currentStdin: Pipe? = nil
    
    @State private var selectedModel: String = "Agent default"
    @State private var selectedEffort: String = "High"
    @State private var copyFeedbackInstall: Bool = false
    @State private var copyFeedbackLogin: Bool = false
    @State private var connectionError: String? = nil
    
    private var detectedPath: String? {
        if let type = target.acpType {
            return acpHost.detectedAgents[type]
        }
        return nil
    }
    
    private var isDetected: Bool {
        if let path = detectedPath, !path.isEmpty {
            return true
        }
        return false
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar
            Divider()
            
            // Main Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Security & Subprocess Isolation Notice
                    securityNoticeBanner
                    
                    // Step 1: Toolchain Installation
                    if !target.installCommand.isEmpty {
                        installationSection
                    }
                    
                    // Step 2: Authentication
                    if !target.loginCommand.isEmpty {
                        authenticationSection
                    }
                    
                    // Step 3: Diagnostics Console
                    diagnosticsConsoleSection
                    
                    // Step 4: Reasoning & Runtime Configuration
                    reasoningConfigurationSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            
            // Connection Error Banner
            if let err = connectionError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color.orange.opacity(0.2)), alignment: .top)
            }
            
            Divider()
            
            // Footer Navigation Bar
            footerBar
        }
        .onAppear {
            let user = NSUserName()
            let host = ProcessInfo.processInfo.hostName
            terminalLog = "\(user)@\(host) ~ %\n"
            acpHost.detectInstalledAgents()
        }
        .onDisappear {
            currentProcess?.terminate()
            currentProcess = nil
            currentStdin = nil
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 14) {
            // Agent Branding Tile
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(target.iconColor.opacity(0.14))
                    .frame(width: 38, height: 38)
                
                Image(systemName: target.iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(target.iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Connect \(target.title)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    // Status Badge
                    if isDetected, let path = detectedPath {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5, height: 5)
                            Text("INSTALLED (\(path))")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.secondary.opacity(0.6))
                                .frame(width: 5, height: 5)
                            Text("NOT DETECTED IN PATH")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                    }
                }
                
                Text("AGENT CLIENT PROTOCOL (ACP) • LOCAL STDIO BRIDGE")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.6)
            }
            
            Spacer()
            
            Button {
                onBack()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close Wizard")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
    
    // MARK: - Security Notice Banner
    
    private var securityNoticeBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .padding(.top, 1)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Subprocess Sandboxing & Privacy Assurance")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Tasks execute strictly within your local shell via standard input/output (stdio NDJSON). MicroCode does not transmit, intercept, or store credentials; your subscription tokens remain entirely within your local CLI environment.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    // MARK: - Step 1: Toolchain Installation
    
    private var installationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("1. CLI TOOLCHAIN INSTALLATION")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.6)
                
                Spacer()
                
                if isDetected {
                    Text("Verified")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
            
            commandRow(
                command: target.installCommand,
                isCopied: copyFeedbackInstall,
                onCopy: { copyToClipboard(target.installCommand, isInstall: true) },
                onRun: { runInTerminal(target.installCommand) }
            )
        }
    }
    
    // MARK: - Step 2: Authentication
    
    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("2. LOCAL AUTHENTICATION")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.6)
            
            commandRow(
                command: target.loginCommand,
                isCopied: copyFeedbackLogin,
                onCopy: { copyToClipboard(target.loginCommand, isInstall: false) },
                onRun: { runInTerminal(target.loginCommand) }
            )
            
            Text("Launches the official CLI authentication flow in your local environment. MicroCode never observes or receives credentials.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Step 3: Diagnostics Console
    
    private var diagnosticsConsoleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("DIAGNOSTICS & VERIFICATION CONSOLE", systemImage: "terminal")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.6)
                
                Spacer()
                
                if isRunningCommand {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Executing…")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                Button("Clear") {
                    terminalLog = ""
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(terminalLog.isEmpty ? "No active diagnostics. Click 'Run' on any command above to test local execution." : terminalLog)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(terminalLog.isEmpty ? .secondary.opacity(0.6) : .white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .id("terminal_bottom")
                    }
                    .frame(height: 105)
                    .background(Color(red: 0.10, green: 0.10, blue: 0.12))
                    .onChange(of: terminalLog) { _ in
                        proxy.scrollTo("terminal_bottom", anchor: .bottom)
                    }
                }
                
                Divider()
                
                // Terminal Input Line
                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    TextField("Enter shell command or respond to interactive prompt…", text: $terminalInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.white)
                        .onSubmit {
                            let input = terminalInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !input.isEmpty else { return }
                            terminalInput = ""
                            if let _ = currentStdin {
                                sendInputToRunningProcess(input + "\n")
                            } else {
                                runInTerminal(input)
                            }
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(red: 0.08, green: 0.08, blue: 0.09))
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Step 4: Reasoning Configuration
    
    private var reasoningConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("3. REASONING & RUNTIME CONFIGURATION")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.6)
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DEFAULT MODEL")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $selectedModel) {
                        Text("Agent default").tag("Agent default")
                        ForEach(availableModelsForTarget(), id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("REASONING EFFORT")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $selectedEffort) {
                        Text("High (Real-time thinking stream)").tag("High")
                        Text("Agent default").tag("Agent default")
                        Text("Medium").tag("Medium")
                        Text("Low").tag("Low")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9.5))
                    .foregroundColor(.accentColor)
                Text("High reasoning enables real-time token streaming of internal thoughts and step deliberation.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    // MARK: - Footer Navigation Bar
    
    private var footerBar: some View {
        HStack {
            Button {
                onBack()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Back to Agents")
                }
                .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Cancel") {
                onBack()
            }
            .font(.system(size: 11))
            .buttonStyle(.bordered)
            .controlSize(.regular)
            
            Button("Connect \(target.title)") {
                connectAgent()
            }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }
    
    // MARK: - Subviews & Actions
    
    private func commandRow(command: String, isCopied: Bool, onCopy: @escaping () -> Void, onRun: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("$")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            Button {
                onCopy()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                    Text(isCopied ? "Copied" : "Copy")
                        .font(.system(size: 10.5))
                }
                .frame(width: 65, height: 26)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Button {
                onRun()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8))
                    Text("Run")
                        .font(.system(size: 10.5))
                }
                .frame(width: 55, height: 26)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
    
    private func copyToClipboard(_ text: String, isInstall: Bool) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if isInstall {
            copyFeedbackInstall = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copyFeedbackInstall = false }
        } else {
            copyFeedbackLogin = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copyFeedbackLogin = false }
        }
    }
    
    private func runInTerminal(_ cmd: String) {
        guard !isRunningCommand else { return }
        isRunningCommand = true
        terminalLog += "\n$ \(cmd)\n"
        
        let proc = Process()
        let pipe = Pipe()
        let stdin = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-c", cmd]
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.standardInput = stdin
        
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(home)/.local/bin:\(home)/.opencode/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        proc.environment = env
        
        currentProcess = proc
        currentStdin = stdin
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self.terminalLog += text
            }
        }
        
        proc.terminationHandler = { p in
            DispatchQueue.main.async {
                self.isRunningCommand = false
                self.terminalLog += "\n[Process exited with code \(p.terminationStatus)]\n"
                self.currentProcess = nil
                self.currentStdin = nil
                self.acpHost.detectInstalledAgents()
            }
        }
        
        do {
            try proc.run()
        } catch {
            isRunningCommand = false
            terminalLog += "Failed to start process: \(error.localizedDescription)\n"
        }
    }
    
    private func sendInputToRunningProcess(_ text: String) {
        guard let stdin = currentStdin, let data = text.data(using: .utf8) else { return }
        try? stdin.fileHandleForWriting.write(contentsOf: data)
        terminalLog += text
    }
    
    private func availableModelsForTarget() -> [String] {
        switch target {
        case .agy:
            return discovery.models(for: "agy").map(\.id)
        case .claudeCode:
            return discovery.models(for: "claude_code").map(\.id)
        case .openCode:
            return discovery.models(for: "opencode").map(\.id)
        case .codex:
            return discovery.models(for: "codex").map(\.id)
        default:
            return []
        }
    }
    
    private func connectAgent() {
        connectionError = nil
        let effortParam = selectedEffort == "Agent default" ? "high" : selectedEffort
        
        switch target {
        case .agy:
            if let _ = acpHost.quickConnect(.agy, effort: effortParam) {
                appState.aiProvider = "agy"
                let targetModel = selectedModel == "Agent default" ? (discovery.models(for: "agy").first?.id ?? "gemini-3.8-flash-high") : selectedModel
                appState.aiModel = targetModel
                appState.saveSettings()
                onConnected()
            } else {
                connectionError = "Could not find 'agy' executable. Please run the installation command above."
            }
            
        case .claudeCode:
            if let _ = acpHost.quickConnect(.claudeCode, effort: effortParam) {
                appState.aiProvider = "claude_code"
                let targetModel = selectedModel == "Agent default" ? (discovery.models(for: "claude_code").first?.id ?? "haiku") : selectedModel
                appState.aiModel = targetModel
                appState.saveSettings()
                onConnected()
            } else {
                connectionError = "Could not find 'claude' executable. Please run the installation command above."
            }
            
        case .openCode:
            if let _ = acpHost.quickConnect(.openCode, effort: effortParam) {
                appState.aiProvider = "opencode"
                let targetModel = selectedModel == "Agent default" ? (discovery.models(for: "opencode").first?.id ?? "opencode/nemotron-3.5-lightning-free") : selectedModel
                appState.aiModel = targetModel
                appState.saveSettings()
                onConnected()
            } else {
                connectionError = "Could not find 'opencode' executable. Please run the installation command above."
            }
            
        case .codex:
            if let _ = acpHost.quickConnect(.codexEngine, effort: effortParam) {
                appState.aiProvider = "codex"
                let targetModel = selectedModel == "Agent default" ? (discovery.models(for: "codex").first?.id ?? "gpt-6-astra") : selectedModel
                appState.aiModel = targetModel
                appState.saveSettings()
                onConnected()
            } else {
                connectionError = "Could not find 'codex' executable. Please run the installation command above or use MicroCode Native."
            }
            
        case .microcodeNative:
            acpHost.activeAgentId = nil
            appState.aiProvider = "deepseek"
            appState.aiModel = "deepseek-flash"
            appState.saveSettings()
            onConnected()
            
        case .freeModel:
            if let _ = discovery.engines.first(where: { $0.id == "opencode" && $0.isInstalled }) {
                _ = acpHost.quickConnect(.openCode, effort: effortParam)
                appState.aiProvider = "opencode"
                appState.aiModel = "opencode/nemotron-3.5-lightning-free"
            } else {
                appState.aiProvider = "deepseek"
                appState.aiModel = "deepseek-flash"
            }
            appState.saveSettings()
            onConnected()
            
        default:
            connectionError = "This agent is not currently installed."
        }
    }
}
