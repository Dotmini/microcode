//
//  AgentConnectionsView.swift
//  MicroCode
//
//  Created and Designed by Dotmini Software
//  Founder & CEO: Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//
//  Description:
//  Frictionless, 1-Click Agent Connections & Setup Wizard.
//  Zero-friction agent onboarding with embedded terminal, 1-click install/login runners,
//  and live subscription / local ecosystem verification.
//

import SwiftUI
import AppKit

// MARK: - Agent Connection Model

public enum AgentConnectionType: String, CaseIterable, Identifiable {
    case claudeCode = "claude_code"
    case agy = "agy"
    case codex = "codex"
    case geminiCLI = "gemini_cli"
    case openCode = "opencode"
    case nineRouter = "9router"
    case cursorAgent = "cursor_agent"
    case githubCopilot = "github_copilot"
    case goose = "goose"
    case cline = "cline"
    case qwenCode = "qwen"
    case aider = "aider"
    case microcodeNative = "microcode_native"
    case freeModel = "free_model"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .agy: return "Antigravity (AGY)"
        case .codex: return "OpenAI Codex"
        case .geminiCLI: return "Google Gemini CLI"
        case .openCode: return "OpenCode"
        case .nineRouter: return "9Router Smart Gateway"
        case .cursorAgent: return "Cursor Agent"
        case .githubCopilot: return "GitHub Copilot CLI"
        case .goose: return "Block Goose (ACP)"
        case .cline: return "Cline CLI"
        case .qwenCode: return "Alibaba Qwen Code"
        case .aider: return "Aider Architect"
        case .microcodeNative: return "MicroCode Native"
        case .freeModel: return "Free AI Model"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .claudeCode: return "Anthropic CLI agent with hybrid reasoning"
        case .agy: return "Google Antigravity CLI (Live `agy models` discovery)"
        case .codex: return "OpenAI Codex CLI & flagship coding models"
        case .geminiCLI: return "Official `@google/gemini-cli` autonomous agent"
        case .openCode: return "Open-source coding agent & local models"
        case .nineRouter: return "3-Tier Smart Auto-Fallback Router (Sub → Cheap API → Free)"
        case .cursorAgent: return "Cursor background agent CLI (`cursor-agent`)"
        case .githubCopilot: return "GitHub Copilot workspace CLI (`copilot` / `gh copilot`)"
        case .goose: return "Block Goose native ACP v1 agent (`goose acp`)"
        case .cline: return "Cline autonomous coding CLI (`cline`)"
        case .qwenCode: return "Alibaba Qwen3-Coder terminal agent (`qwen`)"
        case .aider: return "Aider AI pair programming architect (`aider`)"
        case .microcodeNative: return "In-app engine with BYOK / Web Subscription"
        case .freeModel: return "DeepSeek & Nemotron free models — no card needed"
        }
    }
    
    public var requirementBadge: String {
        switch self {
        case .claudeCode: return "Claude Pro / API"
        case .agy: return "Live AGY Models"
        case .codex: return "ChatGPT Plus / API"
        case .geminiCLI: return "Free Tier / Google AI"
        case .openCode: return "Free & Local Models"
        case .nineRouter: return "localhost:20128 • Zero Downtime"
        case .cursorAgent: return "Cursor Pro"
        case .githubCopilot: return "GitHub Copilot"
        case .goose: return "ACP v1 Native"
        case .cline: return "Any Provider / 9Router"
        case .qwenCode: return "Qwen OAuth / Free Quota"
        case .aider: return "Git-Native Architect"
        case .microcodeNative: return "Ready — one click"
        case .freeModel: return "Free to run, no card needed"
        }
    }
    
    public var isRecommended: Bool {
        return self == .claudeCode || self == .agy || self == .nineRouter
    }
    
    public var iconName: String {
        return id
    }
    
    public var iconColor: Color {
        switch self {
        case .claudeCode: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .agy: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .openCode: return Color(red: 0.88, green: 0.35, blue: 0.28)
        case .codex: return Color(red: 0.06, green: 0.64, blue: 0.50)
        case .nineRouter: return .orange
        case .microcodeNative: return .accentColor
        case .cursorAgent: return .purple
        case .githubCopilot: return .primary
        default: return .blue
        }
    }
    
    public var installCommand: String {
        switch self {
        case .claudeCode: return "npm install -g @anthropic-ai/claude-code"
        case .agy: return "curl -fsSL https://antigravity.google/install.sh | bash"
        case .codex: return "npm install -g @openai/codex"
        case .geminiCLI: return "npm install -g @google/gemini-cli"
        case .openCode: return "npm install -g opencode-ai@latest"
        case .nineRouter: return "npm install -g 9router"
        case .cursorAgent: return "curl -fsSL https://cursor.com/install-cli | bash"
        case .githubCopilot: return "npm install -g @github/copilot"
        case .goose: return "brew install block-goose-cli"
        case .cline: return "npm install -g cline"
        case .qwenCode: return "npm install -g @qwen-code/qwen-code"
        case .aider: return "pipx install aider-chat"
        case .freeModel, .microcodeNative: return ""
        }
    }
    
    public var loginCommand: String {
        switch self {
        case .claudeCode: return "claude auth login"
        case .agy: return "agy auth login"
        case .codex: return "codex login"
        case .geminiCLI: return "gemini"
        case .openCode: return "opencode auth login"
        case .nineRouter: return "9router"
        case .cursorAgent: return "cursor-agent login"
        case .githubCopilot: return "copilot auth"
        case .goose: return "goose configure"
        case .cline: return "cline auth"
        case .qwenCode: return "qwen"
        case .aider: return "aider --version"
        case .freeModel, .microcodeNative: return ""
        }
    }
    
    var acpType: ACPAgentType? {
        switch self {
        case .claudeCode: return .claudeCode
        case .agy: return .agy
        case .openCode: return .openCode
        case .codex: return .codexEngine
        case .geminiCLI: return .geminiCLI
        case .cursorAgent: return .cursorAgent
        case .githubCopilot: return .githubCopilot
        case .goose: return .goose
        case .cline: return .cline
        case .qwenCode: return .qwenCode
        case .aider: return .aider
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
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var activeWizardTarget: AgentConnectionType? = nil
    @State private var toastMessage: String? = nil
    @AppStorage("use9RouterForHarnesses") private var use9RouterForHarnesses: Bool = false
    
    private var modalBackground: Color {
        colorScheme == .dark ? Color.black : Color(nsColor: .windowBackgroundColor)
    }
    
    private var cardSurface: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.03)
    }
    
    private var cardBorder: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.12)
    }
    
    public init() {}
    
    public var body: some View {
        ZStack {
            modalBackground
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
        .background(modalBackground)
        .overlay(alignment: .bottom) {
            if let toast = toastMessage {
                Text(toast)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(colorScheme == .dark ? Color.black.opacity(0.95) : Color.white.opacity(0.95))
                    .overlay(Capsule().stroke(Color.primary.opacity(0.2), lineWidth: 1))
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
                        .foregroundColor(Color.primary.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.08))
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
                    nineRouterProxyBanner
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
                .background(Color.primary.opacity(0.08))
            
            // Footer
            HStack {
                Button("Use the full setup guide") {
                    if let url = URL(string: "https://docs.microcode.dev/agents") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
                
                Spacer()
                
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text("Skip for now")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .background(modalBackground)
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
                // Authentic Brand Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .frame(width: 38, height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    
                    AIProviderBrandIcon(provider: type.id, size: 24)
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
                                .background(Color.primary.opacity(0.12))
                                .foregroundColor(.primary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(Color.primary.opacity(0.25), lineWidth: 0.8)
                                )
                        }
                    }
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(status.color == .secondary ? Color.secondary.opacity(0.35) : Color.primary.opacity(0.85))
                            .frame(width: 6, height: 6)
                        
                        Text(status.label)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        if isConnected {
                            Text("Active in Chat")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.primary.opacity(0.12))
                                .foregroundColor(.primary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(Color.primary.opacity(0.25), lineWidth: 0.8)
                                )
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isConnected ? Color.primary.opacity(0.4) : cardBorder, lineWidth: isConnected ? 1.5 : 1)
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
                        .fill(Color.primary.opacity(0.04))
                        .frame(width: 38, height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    AIProviderBrandIcon(provider: "local", size: 24)
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
                    .background(Color.primary.opacity(0.12))
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.25), lineWidth: 0.8)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 9Router Harness Proxy Banner
    
    private var nineRouterProxyBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 38, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                AIProviderBrandIcon(provider: "9router", size: 24)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Route CLI Harnesses via 9Router (localhost:20128)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("3-TIER SMART PROXY")
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.12))
                        .foregroundColor(.primary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.primary.opacity(0.25), lineWidth: 0.8)
                        )
                }
                Text("Injects OPENAI_BASE_URL & ANTHROPIC_BASE_URL=http://127.0.0.1:20128 into Claude Code, Codex, OpenCode, Cursor, Goose, Cline & Aider for automatic Tier 1 → Tier 2 → Tier 3 fallback.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Toggle("", isOn: $use9RouterForHarnesses)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(use9RouterForHarnesses ? Color.primary.opacity(0.4) : cardBorder, lineWidth: use9RouterForHarnesses ? 1.5 : 1)
                )
        )
    }
    
    // MARK: - Helpers
    
    private struct AgentStatus {
        let label: String
        let color: Color
    }
    
    private func statusFor(_ type: AgentConnectionType) -> AgentStatus {
        switch type {
        case .claudeCode:
            if discovery.engines.contains(where: { $0.id == "claude_code" && $0.isInstalled }) {
                return AgentStatus(label: "Ready — one click", color: .green)
            }
            return AgentStatus(label: "Not installed", color: .secondary)
            
        case .agy:
            if discovery.engines.contains(where: { $0.id == "agy" && $0.isInstalled }) {
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
            if discovery.engines.contains(where: { $0.id == "codex" && $0.isInstalled }) {
                return AgentStatus(label: "Ready — one click", color: .green)
            }
            return AgentStatus(label: "Not installed", color: .secondary)
            
        case .geminiCLI:
            if discovery.engines.contains(where: { $0.id == "gemini_cli" && $0.isInstalled }) {
                return AgentStatus(label: "Ready — one click", color: .green)
            }
            return AgentStatus(label: "Not installed (`npm i -g @google/gemini-cli`)", color: .secondary)
            
        case .nineRouter:
            if LocalLLMService.shared.detectedServers.contains(where: { $0.type == .nineRouter && $0.isOnline }) || ACPHostService.resolveExecutablePath("9router") != nil {
                return AgentStatus(label: "Ready on localhost:20128", color: .green)
            }
            return AgentStatus(label: "Install via `npm i -g 9router`", color: .secondary)
            
        case .cursorAgent:
            if discovery.engines.contains(where: { $0.id == "cursor" && $0.isInstalled }) || acpHost.detectedAgents[.cursorAgent] != nil {
                return AgentStatus(label: "Ready — one click", color: .green)
            }
            return AgentStatus(label: "Not installed", color: .secondary)
            
        case .githubCopilot:
            if discovery.engines.contains(where: { $0.id == "copilot" && $0.isInstalled }) || acpHost.detectedAgents[.githubCopilot] != nil {
                return AgentStatus(label: "Ready — one click", color: .green)
            }
            return AgentStatus(label: "Not installed", color: .secondary)
            
        case .goose:
            if discovery.engines.contains(where: { $0.id == "goose" && $0.isInstalled }) || acpHost.detectedAgents[.goose] != nil {
                return AgentStatus(label: "Ready — native ACP v1", color: .green)
            }
            return AgentStatus(label: "Not installed (`brew install block-goose-cli`)", color: .secondary)
            
        case .cline:
            if discovery.engines.contains(where: { $0.id == "cline" && $0.isInstalled }) || acpHost.detectedAgents[.cline] != nil {
                return AgentStatus(label: "Ready — one click", color: .green)
            }
            return AgentStatus(label: "Not installed (`npm i -g cline`)", color: .secondary)
            
        case .qwenCode:
            if discovery.engines.contains(where: { $0.id == "qwen" && $0.isInstalled }) || acpHost.detectedAgents[.qwenCode] != nil {
                return AgentStatus(label: "Ready — one click", color: .green)
            }
            return AgentStatus(label: "Not installed (`npm i -g @qwen-code/qwen-code`)", color: .secondary)
            
        case .aider:
            if discovery.engines.contains(where: { $0.id == "aider" && $0.isInstalled }) || acpHost.detectedAgents[.aider] != nil {
                return AgentStatus(label: "Ready — one click", color: .green)
            }
            return AgentStatus(label: "Not installed (`pipx install aider-chat`)", color: .secondary)
            
        case .microcodeNative:
            return AgentStatus(label: "Ready — one click", color: .green)
            
        case .freeModel:
            return AgentStatus(label: "Free to run", color: .blue)
        }
    }
    
    private func isCurrentAgent(_ type: AgentConnectionType) -> Bool {
        if !appState.isCurrentAIConnected {
            return false
        }
        if type == .nineRouter {
            return appState.aiProvider == "9router"
        }
        if let acpType = type.acpType {
            return appState.aiProvider == acpType.engineId
        }
        if type == .microcodeNative {
            let acpIds = Set(ACPAgentType.allCases.map(\.engineId))
            return !acpIds.contains(appState.aiProvider) && appState.aiProvider != "9router"
        }
        return false
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
    @Environment(\.colorScheme) private var colorScheme
    
    private var modalBackground: Color {
        colorScheme == .dark ? Color.black : Color(nsColor: .windowBackgroundColor)
    }
    
    private var cardSurface: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.03)
    }
    
    private var cardBorder: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.12)
    }
    
    @State private var terminalLog: String = ""
    @State private var terminalInput: String = ""
    @State private var isRunningCommand: Bool = false
    @State private var currentProcess: Process? = nil
    @State private var currentStdin: Pipe? = nil
    
    @State private var selectedModel: String = "Agent default"
    @State private var selectedEffort: String = "High"
    @State private var selectedPermission: ACPPermissionMode = .reviewEach
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
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 38, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                
                AIProviderBrandIcon(provider: target.id, size: 24)
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
                                .fill(Color.primary)
                                .frame(width: 5, height: 5)
                            Text("INSTALLED (\(path))")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.12))
                        .clipShape(Capsule())
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.secondary.opacity(0.4))
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
                    .foregroundColor(Color.primary.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close Wizard")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(modalBackground)
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
        .background(cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
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
                        .foregroundColor(.primary)
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
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    Text(terminalLog)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.1))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .id("terminalBottom")
                }
                .frame(height: 120)
                .background(colorScheme == .dark ? Color.black : Color(white: 0.95))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                )
                .onChange(of: terminalLog) { _ in
                    proxy.scrollTo("terminalBottom", anchor: .bottom)
                }
            }
        }
    }
    
    // MARK: - Step 4: Reasoning & Runtime Configuration
    
    private var reasoningConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("3. RUNTIME & CAPABILITY PROFILE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.6)
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AGENT AUTONOMY LEVEL")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $selectedPermission) {
                        ForEach(ACPPermissionMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
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
                    .foregroundColor(.primary)
                Text("High reasoning enables real-time token streaming of internal thoughts and step deliberation.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
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
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button {
                onBack()
            } label: {
                Text("Cancel")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            
            Button {
                connectAgent()
            } label: {
                Text("Connect \(target.title)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(modalBackground)
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
            .background(cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(cardBorder, lineWidth: 1)
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
        if target == .nineRouter {
            return AIModelCatalog.shared.provider("9router")?.models.map(\.id) ?? []
        }
        if let acpType = target.acpType {
            return discovery.models(for: acpType.engineId).map(\.id)
        }
        return []
    }
    
    private func connectAgent() {
        connectionError = nil
        let effortParam = selectedEffort == "Agent default" ? "high" : selectedEffort
        
        if target == .nineRouter {
            acpHost.activeAgentId = nil
            UserDefaults.standard.set("direct", forKey: "aiKeyMode")
            appState.aiProvider = "9router"
            let targetModel = selectedModel == "Agent default"
                ? (AIModelCatalog.shared.provider("9router")?.models.first?.id ?? "claude-sonnet-4-6")
                : selectedModel
            appState.aiModel = targetModel
            appState.saveSettings()
            Task { await AIModelCatalog.shared.fetchLiveModelsForProvider("9router") }
            onConnected()
            return
        }
        
        if let acpType = target.acpType {
            if let _ = acpHost.quickConnect(acpType, effort: effortParam) {
                UserDefaults.standard.set("acp", forKey: "aiKeyMode")
                let engId = acpType.engineId
                appState.aiProvider = engId
                let targetModel = selectedModel == "Agent default"
                    ? (discovery.models(for: engId).first?.id ?? "")
                    : selectedModel
                if !targetModel.isEmpty {
                    appState.aiModel = targetModel
                }
                appState.saveSettings()
                onConnected()
            } else {
                connectionError = "Could not find '\(acpType.defaultCommand)' executable. Please run the installation command above."
            }
            return
        }
        
        switch target {
        case .microcodeNative:
            acpHost.activeAgentId = nil
            appState.aiProvider = "gemini"
            appState.aiModel = AIModelCatalog.shared.provider("gemini")?.models.first?.id ?? ""
            appState.saveSettings()
            onConnected()
            
        case .freeModel:
            if let _ = discovery.engines.first(where: { $0.id == "opencode" && $0.isInstalled }) {
                _ = acpHost.quickConnect(.openCode, effort: effortParam)
                appState.aiProvider = "opencode"
                appState.aiModel = "opencode/nemotron-3.5-lightning-free"
            } else {
                appState.aiProvider = "deepseek"
                appState.aiModel = "deepseek-chat"
            }
            appState.saveSettings()
            onConnected()
            
        default:
            connectionError = "This agent is not currently installed."
        }
    }
}
