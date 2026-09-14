//
//  AgentEcosystemConfigView.swift
//  MicroCode
//
//  Unified Agent & Ecosystem Configuration Hub.
//  Brings together:
//  1. External Coding Agents (Claude Code, Antigravity, Aider, Codex, Custom) via ACP
//  2. Platform Rules (.cursorrules, .cursor/rules/*.mdc, .windsurfrules, .clinerules, Zed, agent.md)
//  3. Model Context Protocol (MCP) Servers (.cursor/mcp.json, workspace MCP)
//  4. Context Protocol Bridge (@file, @git, @diff, @diagnostics, @symbol, @rules)
//  5. Inference Engine & Model Specifications (GLM-4, CodeGeeX)
//
//  Adheres strictly to Apple Human Interface Guidelines (HIG) and MicroCode's formal IDE theme.
//  Zero cartoon emojis, subtle monochromatic/refined tints, and native macOS controls.
//

import SwiftUI
import AppKit

public enum EcosystemTab: String, CaseIterable, Identifiable {
    case agents = "External Agents"
    case rules = "Platform Rules"
    case mcp = "MCP Servers"
    case context = "Context Bridge"
    case models = "Inference Models"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .agents: return "link"
        case .rules: return "doc.text.magnifyingglass"
        case .mcp: return "network"
        case .context: return "at"
        case .models: return "cpu"
        }
    }
}

public struct AgentEcosystemConfigView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var acpHost = ACPHostService.shared
    @ObservedObject var rulesEngine = MultiPlatformRulesEngine.shared
    @ObservedObject var bridge = AgentContextProtocolBridge.shared
    @ObservedObject var discovery = LocalEcosystemDiscovery.shared
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) private var colorScheme

    private var modalBackground: Color {
        colorScheme == .dark ? Color.black : Color(nsColor: .windowBackgroundColor)
    }
    private var cardSurface: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.04)
    }
    private var cardBorder: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.12)
    }
    private var inputBackground: Color {
        colorScheme == .dark ? Color.black : Color(nsColor: .controlBackgroundColor)
    }

    @State private var selectedTab: EcosystemTab
    @State private var filterQuery: String = ""
    @State private var expandedRuleId: String? = nil
    
    // Agent config state
    @State private var detectedPaths: [ACPAgentType: String] = [:]
    @State private var isDetecting: Bool = false
    @State private var expandedAgentType: ACPAgentType? = nil
    @State private var customCommand: [ACPAgentType: String] = [:]
    @State private var customArgs: [ACPAgentType: String] = [:]
    @State private var permissionModes: [ACPAgentType: ACPPermissionMode] = [:]
    @State private var testExecutionOutputs: [ACPAgentType: String] = [:]
    @State private var isTestingExecution: [ACPAgentType: Bool] = [:]

    public init(initialTab: EcosystemTab = .agents) {
        _selectedTab = State(initialValue: initialTab)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar
            Divider()

            // Segmented Tab Bar
            tabPickerBar
            Divider()

            // Main Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedTab {
                    case .agents:
                        externalAgentsSection
                    case .rules:
                        platformRulesSection
                    case .mcp:
                        mcpServersSection
                    case .context:
                        contextProtocolSection
                    case .models:
                        inferenceModelsSection
                    }
                }
                .padding(22)
            }
        }
        .frame(minWidth: 760, idealWidth: 840, minHeight: 560, idealHeight: 640)
        .background(modalBackground)
        .onAppear {
            detectInstalledAgents()
            loadExistingConfigs()
            rulesEngine.refresh(workspaceRoot: rulesEngine.currentWorkspace)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 36, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(cardBorder, lineWidth: 1))
                Image(systemName: "slider.horizontal.2.square")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Agent & Ecosystem Settings")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("UNIFIED")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .foregroundColor(Color.primary.opacity(0.7))
                        .clipShape(Capsule())
                }
                Text("External coding agents, cross-platform rules, MCP servers, and context protocol")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                detectInstalledAgents()
                rulesEngine.refresh(workspaceRoot: rulesEngine.currentWorkspace)
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Rescan CLI agents, .cursorrules, and workspace MCP files")

            Button {
                presentationMode.wrappedValue.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close Settings")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(modalBackground)
    }

    // MARK: - Tab Picker Bar

    private var tabPickerBar: some View {
        HStack(spacing: 6) {
            ForEach(EcosystemTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))

                        if tab == .agents && !acpHost.registeredConfigs.isEmpty {
                            Text("\(acpHost.registeredConfigs.count)")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.12))
                                .foregroundColor(.primary)
                                .clipShape(Capsule())
                        } else if tab == .rules && !rulesEngine.discoveredRules.isEmpty {
                            Text("\(rulesEngine.discoveredRules.count)")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.10))
                                .foregroundColor(Color.primary.opacity(0.7))
                                .clipShape(Capsule())
                        } else if tab == .mcp && !rulesEngine.discoveredMCPServers.isEmpty {
                            Text("\(rulesEngine.discoveredMCPServers.count)")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.10))
                                .foregroundColor(Color.primary.opacity(0.7))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? Color.primary.opacity(0.12) : Color.clear)
                    )
                    .foregroundColor(isSelected ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(modalBackground)
    }

    // MARK: - Section 1: External Agents (ACP)

    private var externalAgentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Autonomous & External Coding Agents")
                    .font(.system(size: 13, weight: .semibold))
                Text("Connect external CLI coding agents via stdio Agent Client Protocol (ACP). Agents execute tasks and report streaming events directly into MicroCode.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(ACPAgentType.allCases) { type in
                    agentRow(type: type)
                }
            }
        }
    }

    private func agentRow(type: ACPAgentType) -> some View {
        let detectedPath = detectedPaths[type]
        let isDetected = detectedPath != nil && !detectedPath!.isEmpty
        let isRegistered = acpHost.registeredConfigs.contains(where: { $0.type == type })
        let isActive = acpHost.activeAgentId != nil && acpHost.registeredConfigs.first(where: { $0.id == acpHost.activeAgentId })?.type == type
        let isExpanded = expandedAgentType == type

        return VStack(alignment: .leading, spacing: 0) {
            // Main Agent Summary Row
            HStack(spacing: 12) {
                // Authentic Agent Brand Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(cardSurface)
                        .frame(width: 34, height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(cardBorder, lineWidth: 1)
                        )
                    AIProviderBrandIcon(provider: type.rawValue, size: 20)
                }

                // Title & Subtitle
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(type.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.12))
                                .foregroundColor(.primary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(Color.primary.opacity(0.25), lineWidth: 0.8)
                                )
                        }
                    }

                    HStack(spacing: 6) {
                        if isDetected, let path = detectedPath {
                            Circle()
                                .fill(Color.primary.opacity(0.85))
                                .frame(width: 6, height: 6)
                            Text(path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else if type == .codexEngine {
                            Circle()
                                .fill(Color.primary.opacity(0.3))
                                .frame(width: 6, height: 6)
                            Text("Internal MicroCore Engine")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        } else if type == .custom {
                            Circle()
                                .fill(Color.primary.opacity(0.3))
                                .frame(width: 6, height: 6)
                            Text("Custom binary executable")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        } else {
                            Circle()
                                .fill(Color.primary.opacity(0.3))
                                .frame(width: 6, height: 6)
                            Text("Not detected in PATH (\(type.defaultCommand))")
                                .font(.system(size: 10))
                                .foregroundColor(Color.primary.opacity(0.4))
                        }
                    }
                }

                Spacer()

                // Actions
                HStack(spacing: 8) {
                    if isActive {
                        Button("Disconnect") {
                            acpHost.activeAgentId = nil
                            let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "direct"
                            if keyMode == "subscription", let first = SubscriptionAuthManager.shared.connectedModelInfos().first {
                                appState.aiProvider = first.aiProviderID
                                appState.aiModel = first.modelID
                            } else if keyMode == "cloud", let first = AIModelCatalog.shared.provider("omni")?.models.first {
                                appState.aiProvider = "omni"
                                appState.aiModel = first.id
                            } else {
                                let byok = AIModelCatalog.shared.providers.filter { !["omni", "agy", "codex", "claude_code", "zed"].contains($0.id) && !(appState.apiKeys[$0.id]?.isEmpty ?? true) }
                                if let prov = byok.first, let firstM = prov.models.first {
                                    appState.aiProvider = prov.id
                                    appState.aiModel = firstM.id
                                } else {
                                    appState.aiProvider = "deepseek"
                                    appState.aiModel = "deepseek-flash"
                                }
                            }
                            appState.saveSettings()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .buttonStyle(.plain)
                    } else if isDetected || isRegistered || type == .codexEngine {
                        Button("Connect") {
                            connectAgent(type: type)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .buttonStyle(.plain)
                    } else {
                        Button("Configure") {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                expandedAgentType = isExpanded ? nil : type
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .buttonStyle(.plain)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            expandedAgentType = isExpanded ? nil : type
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Collapse settings" : "Expand settings")
                }
            }
            .padding(12)

            // Collapsible Settings Drawer
            if isExpanded {
                Divider()
                    .background(Color.primary.opacity(0.08))
                VStack(alignment: .leading, spacing: 12) {
                    // Executable Path
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Executable Binary Path")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            TextField(type.defaultCommand.isEmpty ? "/path/to/executable" : type.defaultCommand, text: Binding(
                                get: { customCommand[type] ?? detectedPath ?? type.defaultCommand },
                                set: { customCommand[type] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))

                            Button("Browse…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = true
                                panel.canChooseDirectories = false
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    customCommand[type] = url.path
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    // CLI Arguments
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default Launch Arguments")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField("e.g. --dangerously-skip-permissions --verbose", text: Binding(
                            get: { customArgs[type] ?? "" },
                            set: { customArgs[type] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    }

                    // Permission Mode
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Permission Policy")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Picker("", selection: Binding(
                            get: { permissionModes[type] ?? .reviewEach },
                            set: { permissionModes[type] = $0 }
                        )) {
                            ForEach(ACPPermissionMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Test Execution & Save
                    HStack {
                        Button {
                            testAgentExecution(type: type)
                        } label: {
                            HStack(spacing: 5) {
                                if isTestingExecution[type] == true {
                                    ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "play.fill").font(.system(size: 8))
                                }
                                Text("Test Command")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isTestingExecution[type] == true)

                        Spacer()

                        Button("Save Configuration") {
                            saveAgentConfig(type: type)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .buttonStyle(.plain)
                    }

                    // Test output if available
                    if let output = testExecutionOutputs[type], !output.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Output:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(output)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.primary)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(inputBackground)
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(cardBorder, lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.02))
            }
        }
        .background(cardSurface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? Color.primary.opacity(0.4) : cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Section 2: Platform Rules

    private var filteredRules: [PlatformRule] {
        if filterQuery.isEmpty { return rulesEngine.discoveredRules }
        return rulesEngine.discoveredRules.filter {
            $0.fileName.localizedCaseInsensitiveContains(filterQuery) ||
            $0.summaryDescription.localizedCaseInsensitiveContains(filterQuery) ||
            $0.source.rawValue.localizedCaseInsensitiveContains(filterQuery) ||
            $0.content.localizedCaseInsensitiveContains(filterQuery)
        }
    }

    private var platformRulesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Discovered Workspace Guidelines & Platform Rules")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Rules automatically loaded from Cursor (.cursorrules, .cursor/rules/*.mdc), Windsurf (.windsurfrules), Cline (.clinerules), Zed, Copilot, and MicroCode.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Search Bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("Search rules by name, description, or content…", text: $filterQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(inputBackground)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(cardBorder, lineWidth: 1))

                if !filterQuery.isEmpty {
                    Button("Clear") { filterQuery = "" }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            if filteredRules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(Color.primary.opacity(0.3))
                    Text(filterQuery.isEmpty ? "No platform rules discovered in active workspace" : "No rules matching query")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text("Create a `.cursorrules`, `.cursor/rules/*.mdc`, or `.microcode/agent.md` file in your workspace to provide persistent agent instructions.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(cardSurface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredRules) { rule in
                        ruleItemView(rule: rule)
                    }
                }
            }

            if !rulesEngine.ignoredPatterns.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ignored Patterns (.cursorignore)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(rulesEngine.ignoredPatterns.joined(separator: ", "))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(inputBackground)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(cardBorder, lineWidth: 1))
                }
                .padding(.top, 8)
            }
        }
    }

    private func ruleItemView(rule: PlatformRule) -> some View {
        let isExpanded = expandedRuleId == rule.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // Platform Source Badge
                Text(rule.source.badge)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08))
                    .foregroundColor(.primary)
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.fileName)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                    if !rule.summaryDescription.isEmpty {
                        Text(rule.summaryDescription)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if !rule.globs.isEmpty {
                    Text(rule.globs.joined(separator: ", "))
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .foregroundColor(.secondary)
                        .cornerRadius(4)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        expandedRuleId = isExpanded ? nil : rule.id
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)

            if isExpanded {
                Divider()
                    .background(Color.primary.opacity(0.08))
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("File Content:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(rule.content, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(rule.content)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(8)
                    }
                    .frame(maxHeight: 200)
                    .background(inputBackground)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(cardBorder, lineWidth: 1))
                }
                .padding(10)
                .background(Color.primary.opacity(0.02))
            }
        }
        .background(cardSurface)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
    }

    // MARK: - Section 3: MCP Servers

    private var mcpServersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Model Context Protocol (MCP) Servers")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Universal tools and resource bridges declared in `.cursor/mcp.json` or `.mcp.json`.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if rulesEngine.discoveredMCPServers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "network")
                        .font(.system(size: 32))
                        .foregroundColor(Color.primary.opacity(0.3))
                    Text("No external MCP servers detected")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text("Declare tools in `.cursor/mcp.json` or `.mcp.json` to auto-bind external MCP tool servers into MicroCode.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(cardSurface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
            } else {
                VStack(spacing: 10) {
                    ForEach(rulesEngine.discoveredMCPServers) { server in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(server.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(server.sourcePlatform)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            HStack(spacing: 8) {
                                Text("Command:")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("\(server.command) \(server.args.joined(separator: " "))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.06))
                                    .cornerRadius(4)
                            }

                            if !server.env.isEmpty {
                                Text("Environment: \(server.env.keys.joined(separator: ", "))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .background(cardSurface)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
                    }
                }
            }
        }
    }

    // MARK: - Section 4: Context Protocol

    private var contextProtocolSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("OpenCode Context Protocol (@ Mentions)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Type `@` in prompt to dynamically embed real-time workspace context directly into the conversation.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                mentionTableRow(tag: "@file:path", desc: "Injects full file content into prompt. E.g. `@file:Sources/App.swift` or `@ContentView.swift`")
                mentionTableRow(tag: "@git / @diff", desc: "Attaches live git status and git diff HEAD changes.")
                mentionTableRow(tag: "@diagnostics", desc: "Attaches real-time LSP compiler diagnostics, errors, and warnings.")
                mentionTableRow(tag: "@symbol:name", desc: "Searches and embeds symbol definitions across the entire workspace.")
                mentionTableRow(tag: "@rules", desc: "Embeds active Cursor, Zed, and MicroCode project guidelines.")
            }
            .padding(12)
            .background(cardSurface)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))

            // Metrics
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Mentions Expanded")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("\(bridge.totalMentionsExpanded)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardSurface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Multi-File Diffs Applied")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("\(bridge.totalDiffsApplied)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardSurface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
            }
        }
    }

    private func mentionTableRow(tag: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(tag)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08))
                .foregroundColor(.primary)
                .cornerRadius(4)
                .frame(width: 120, alignment: .leading)

            Text(desc)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Section 5: Inference Models

    private var inferenceModelsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with Rescan Action
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Discovered Local Engines & Models Hub")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Dynamically discovered from local tools on your machine: Google Antigravity (AGY CLI), OpenAI Codex (~/.codex), Anthropic Claude Code (~/.claude), and Zed / ZCode (~/.config/zed).")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    Task {
                        await discovery.refresh()
                    }
                } label: {
                    if discovery.isScanning {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Label("Rescan Engines", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(discovery.isScanning)
            }

            // Discovered Engines Cards
            ForEach(discovery.engines) { engine in
                VStack(alignment: .leading, spacing: 10) {
                    // Engine Card Header
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(cardSurface)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(cardBorder, lineWidth: 1)
                                )
                            AIProviderBrandIcon(provider: engine.id, size: 16)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(engine.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)
                                if engine.isInstalled {
                                    Text("INSTALLED")
                                        .font(.system(size: 8, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.primary.opacity(0.12))
                                        .foregroundColor(.primary)
                                        .clipShape(Capsule())
                                }
                                if let active = engine.activeModel {
                                    Text("ACTIVE: \(active)")
                                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.primary.opacity(0.12))
                                        .foregroundColor(.primary)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule().stroke(Color.primary.opacity(0.25), lineWidth: 0.8)
                                        )
                                }
                            }
                            if let bin = engine.binaryPath {
                                Text(bin)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Text("\(engine.models.count) models")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Divider().opacity(0.3)

                    // Models grid / list
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(engine.models) { m in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(m.name)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        if !m.badge.isEmpty {
                                            Text(m.badge)
                                                .font(.system(size: 8, weight: .bold))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.primary.opacity(0.08))
                                                .foregroundColor(.primary)
                                                .cornerRadius(3)
                                        }
                                    }
                                    Text(m.id)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.02))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(cardBorder, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(14)
                .background(cardSurface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(cardBorder, lineWidth: 1)
                )
            }

            // Cloud & Specialized Models Reference
            VStack(alignment: .leading, spacing: 10) {
                Text("Specialized & Cloud Runtimes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                let specialized = [
                    ("glm-4-plus", "Zhipu GLM-4 Plus", "Dual-language reasoning and 128k context"),
                    ("codegeex-4", "CodeGeeX-4", "Multilingual code synthesis & refactoring"),
                    ("deepseek-chat", "DeepSeek V3", "Direct API high-speed reasoning"),
                    ("gemini-2.5-pro", "Gemini 2.5 Pro", "Direct Google API multimodal reasoning")
                ]

                ForEach(specialized, id: \.0) { mid, name, desc in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name).font(.system(size: 11, weight: .semibold)).foregroundColor(.primary)
                            Text(desc).font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(mid).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(6)
                }
            }
            .padding(14)
            .background(cardSurface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(cardBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Helper Methods

    private func detectInstalledAgents() {
        isDetecting = true
        Task.detached(priority: .userInitiated) {
            var found: [ACPAgentType: String] = [:]
            for type in ACPAgentType.allCases {
                guard !type.defaultCommand.isEmpty else { continue }
                let checkPaths = [
                    "/usr/local/bin/\(type.defaultCommand)",
                    "/opt/homebrew/bin/\(type.defaultCommand)",
                    "\(NSHomeDirectory())/.local/bin/\(type.defaultCommand)",
                    "\(NSHomeDirectory())/.npm-global/bin/\(type.defaultCommand)",
                    "\(NSHomeDirectory())/.cargo/bin/\(type.defaultCommand)",
                    "\(NSHomeDirectory())/.opencode/bin/\(type.defaultCommand)"
                ]
                
                var resolved: String? = nil
                for path in checkPaths {
                    if FileManager.default.isExecutableFile(atPath: path) {
                        resolved = path
                        break
                    }
                }

                if resolved == nil {
                    // Fallback to which
                    let proc = Process()
                    let pipe = Pipe()
                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
                    proc.arguments = [type.defaultCommand]
                    proc.standardOutput = pipe
                    proc.standardError = Pipe()
                    try? proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !line.isEmpty && FileManager.default.isExecutableFile(atPath: line) {
                            resolved = line
                        }
                    }
                }

                if let r = resolved {
                    found[type] = r
                }
            }

            await MainActor.run {
                self.detectedPaths = found
                self.isDetecting = false
            }
        }
    }

    private func loadExistingConfigs() {
        for config in acpHost.registeredConfigs {
            customCommand[config.type] = config.command
            customArgs[config.type] = config.arguments.joined(separator: " ")
            permissionModes[config.type] = config.permissionMode
        }
    }

    private func connectAgent(type: ACPAgentType) {
        let config: ACPAgentConfig
        if let existing = acpHost.registeredConfigs.first(where: { $0.type == type }) {
            config = existing
        } else {
            let path = customCommand[type] ?? detectedPaths[type] ?? type.defaultCommand
            let newConfig = ACPAgentConfig(
                id: UUID(),
                name: type.displayName,
                type: type,
                command: path,
                arguments: (customArgs[type] ?? "").split(separator: " ").map(String.init),
                environment: [:],
                permissionMode: permissionModes[type] ?? .reviewEach,
                isEnabled: true,
                autoDetected: detectedPaths[type] != nil,
                lastConnected: Date()
            )
            acpHost.registerAgent(newConfig)
            config = newConfig
        }
        acpHost.activeAgentId = config.id
        
        // Sync appState provider and model
        let engineId: String
        switch type {
        case .agy: engineId = "agy"
        case .codexEngine: engineId = "codex"
        case .claudeCode: engineId = "claude_code"
        case .openCode: engineId = "opencode"
        case .zedEngine: engineId = "zed"
        case .aider: engineId = "aider"
        case .custom: engineId = "custom"
        }
        appState.aiProvider = engineId
        let engineModels = LocalEcosystemDiscovery.shared.models(for: engineId)
        if let firstModel = engineModels.first?.id {
            appState.aiModel = firstModel
        }
        appState.saveSettings()
    }

    private func saveAgentConfig(type: ACPAgentType) {
        let path = customCommand[type] ?? detectedPaths[type] ?? type.defaultCommand
        let args = (customArgs[type] ?? "").split(separator: " ").map(String.init)
        let mode = permissionModes[type] ?? .reviewEach

        if let existing = acpHost.registeredConfigs.first(where: { $0.type == type }) {
            let updated = ACPAgentConfig(
                id: existing.id,
                name: existing.name,
                type: type,
                command: path,
                arguments: args,
                environment: existing.environment,
                permissionMode: mode,
                isEnabled: existing.isEnabled,
                autoDetected: detectedPaths[type] != nil,
                lastConnected: existing.lastConnected
            )
            acpHost.registerAgent(updated)
        } else {
            let newConfig = ACPAgentConfig(
                id: UUID(),
                name: type.displayName,
                type: type,
                command: path,
                arguments: args,
                environment: [:],
                permissionMode: mode,
                isEnabled: true,
                autoDetected: detectedPaths[type] != nil,
                lastConnected: Date()
            )
            acpHost.registerAgent(newConfig)
        }
    }

    private func testAgentExecution(type: ACPAgentType) {
        let cmd = customCommand[type] ?? detectedPaths[type] ?? type.defaultCommand
        guard !cmd.isEmpty else {
            testExecutionOutputs[type] = "Command path is empty."
            return
        }

        isTestingExecution[type] = true
        testExecutionOutputs[type] = "Executing \(cmd) --version…"

        Task.detached(priority: .userInitiated) {
            let proc = Process()
            let pipe = Pipe()
            let errPipe = Pipe()

            if cmd.hasPrefix("/") {
                proc.executableURL = URL(fileURLWithPath: cmd)
            } else {
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = [cmd, "--version"]
            }

            if proc.arguments == nil || proc.arguments!.isEmpty {
                proc.arguments = ["--version"]
            }

            proc.standardOutput = pipe
            proc.standardError = errPipe

            do {
                try proc.run()
                proc.waitUntilExit()
                let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                let res = !outStr.isEmpty ? outStr : errStr

                await MainActor.run {
                    self.isTestingExecution[type] = false
                    self.testExecutionOutputs[type] = res.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch {
                await MainActor.run {
                    self.isTestingExecution[type] = false
                    self.testExecutionOutputs[type] = "Execution failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
