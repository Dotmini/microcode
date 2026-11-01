//
//  CellAIAgentEngine.swift
//  MicroCode
//
//  Unified Multi-Provider AI Selector, Theme-Native Controls & Autonomous Agent Loop
//  for All Cell Mode Surfaces (NotebookAIPanel, Inline Agent Cells, Self-Healing & AgentCellModeView).
//  Supports Subscription (ChatGPT/Claude/Gemini/Copilot/TH-AI Passport), BYOK & Smart Routers,
//  Local LLMs (Ollama/LM Studio/MLX/9Router), ACP Harnesses (AGY/Claude Code/Codex/Gemini CLI...),
//  Dotmini Sovereign Cloud (Omni O1X), and Specialist SubAgent Archetypes.
//
//  Created by Dotmini Software
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import SwiftUI
import AppKit
import Combine

// MARK: - Cell SubAgent Specialist Roles

enum CellSubAgentRole: String, CaseIterable, Codable, Identifiable {
    case dataScientist = "data_scientist"
    case mainAgent = "main"
    case architect = "architect"
    case bugHunter = "bug_hunter"
    case backendEngineer = "backend_engineer"
    case frontendEngineer = "frontend_engineer"
    case testRunner = "test_runner"
    case securityAuditor = "security_auditor"
    case autonomousLoop = "autonomous_loop"
    case embeddedHardware = "embedded_hardware"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dataScientist: return "Notebook & Data Scientist"
        case .mainAgent: return "Full OS & Workspace Agent"
        case .architect: return "System Architect"
        case .bugHunter: return "Bug Hunter & Auto-Healer"
        case .backendEngineer: return "Backend & SQL Engineer"
        case .frontendEngineer: return "Visualization & UI Specialist"
        case .testRunner: return "Verification & Test Runner"
        case .securityAuditor: return "Security & Perf Auditor"
        case .autonomousLoop: return "Autonomous Build-Run-Fix Loop"
        case .embeddedHardware: return "Embedded & HIL Firmware Agent"
        }
    }

    var shortBadge: String {
        switch self {
        case .dataScientist: return "Data Science"
        case .mainAgent: return "Main Agent"
        case .architect: return "Architect"
        case .bugHunter: return "Bug Hunter"
        case .backendEngineer: return "Backend"
        case .frontendEngineer: return "Viz / UI"
        case .testRunner: return "Verifier"
        case .securityAuditor: return "Auditor"
        case .autonomousLoop: return "Auto-Loop"
        case .embeddedHardware: return "Embedded HIL"
        }
    }

    var icon: String {
        switch self {
        case .dataScientist: return "chart.xyaxis.line"
        case .mainAgent: return "cpu.fill"
        case .architect: return "square.stack.3d.up.fill"
        case .bugHunter: return "ladybug.fill"
        case .backendEngineer: return "server.rack"
        case .frontendEngineer: return "paintbrush.pointed.fill"
        case .testRunner: return "checkmark.seal.fill"
        case .securityAuditor: return "lock.shield.fill"
        case .autonomousLoop: return "arrow.triangle.2.circlepath.circle.fill"
        case .embeddedHardware: return "memorychip.fill"
        }
    }

    @MainActor
    var rolePrompt: String {
        switch self {
        case .dataScientist:
            return "Act as a Principal Data Scientist & Polyglot Notebook Architect. Design clean reproducible pipelines across Python, R, Julia, SQL, Rust, Go, C++, Ardium, and LaTeX cells, inspect outputs/dataframes, generate publication-quality visualizations, and verify cell execution results."
        case .mainAgent:
            return "Act as MicroCode Full OS & Workspace Autonomous Agent. Inspect, create, update, and run notebook cells as well as workspace files, shell commands, and MCP integrations to accomplish the user's goal end-to-end."
        case .architect:
            return SubAgentHarness.shared.registeredDefinitions["architect"]?.systemPrompt
                ?? "Act as a Principal Software & Data Architect. Analyze dependencies, structure clean multi-cell modular workflows, and establish clear contracts."
        case .bugHunter:
            return SubAgentHarness.shared.registeredDefinitions["bug_hunter"]?.systemPrompt
                ?? "Act as an Autonomous Debugger & Self-Healer. Diagnose tracebacks, compiler/runtime errors, and broken imports, patch cells or files surgically, and re-run to verify zero errors."
        case .backendEngineer:
            return SubAgentHarness.shared.registeredDefinitions["backend_engineer"]?.systemPrompt
                ?? "Act as a Senior Backend, Systems & SQL Engineer. Optimize queries, data pipelines, Rust/Go/C++/Python performance, and API integrations."
        case .frontendEngineer:
            return SubAgentHarness.shared.registeredDefinitions["frontend_engineer"]?.systemPrompt
                ?? "Act as a Visualization & Interactive UI Specialist. Build clear charts, dashboards, HTML/LaTeX reports, and polished interfaces."
        case .testRunner:
            return SubAgentHarness.shared.registeredDefinitions["test_runner"]?.systemPrompt
                ?? "Act as a QA & Reproducibility Verifier. Execute cells, validate assertions, check edge cases/NaNs, and confirm deterministic outputs."
        case .securityAuditor:
            return SubAgentHarness.shared.registeredDefinitions["security_auditor"]?.systemPrompt
                ?? "Act as a Security & Performance Auditor. Audit code and queries for vulnerabilities, credential leaks, memory bottlenecks, and O(N^2) traps."
        case .autonomousLoop:
            return SubAgentHarness.shared.registeredDefinitions["autonomous_loop"]?.systemPrompt
                ?? "Act as an Autonomous Run-Analyze-Fix Agent. Iteratively write, execute, inspect outputs, and repair cells or files until execution succeeds cleanly."
        case .embeddedHardware:
            return "Act as a Principal Embedded Firmware & Hardware-in-the-Loop (HIL) Engineer. Inspect connected physical microcontrollers (`embedded_list_hardware`), write and cross-compile real C/C++/Arduino/ESP-IDF/MicroPython firmware (`embedded_compile`), flash connected USB boards (`embedded_flash`), capture and verify real live UART serial telemetry (`embedded_serial_capture`, `embedded_serial_send`), and symbolicate DWARF panics/backtraces (`embedded_decode_crash`)."
        }
    }
}

// MARK: - Cell AI Selection Model (Global or Per-Cell Override)

struct CellAISelection: Codable, Equatable {
    var useGlobal: Bool = true
    var keyMode: String = "direct"        // "subscription", "direct", "local", "acp", "cloud"
    var provider: String = ""             // e.g. "gemini", "anthropic", "openai", "deepseek", "local", "agy", "claude_code", "omni"
    var model: String = ""                // e.g. "claude-sonnet-4-6", "gemini-2.5-pro", etc.
    var subscriptionProvider: String = "" // e.g. "chatgpt", "claude", "gemini", "copilot", "aipass"
    var localEndpoint: String = ""        // optional local server endpoint override
    var subAgentRole: String = CellSubAgentRole.dataScientist.rawValue

    static let inherit = CellAISelection(useGlobal: true)

    var roleEnum: CellSubAgentRole {
        CellSubAgentRole(rawValue: subAgentRole) ?? .dataScientist
    }

    // MARK: - Resolution Against AppState

    @MainActor
    func effectiveKeyMode(appState: AppState) -> String {
        if !useGlobal && !keyMode.isEmpty {
            return keyMode
        }
        if ACPHostService.shared.activeAgentId != nil {
            return "acp"
        }
        if let saved = UserDefaults.standard.string(forKey: "aiKeyMode"), !saved.isEmpty {
            return saved
        }
        if SubscriptionAuthManager.shared.hasAnyConnected {
            return "subscription"
        }
        let hasDirect = appState.apiKeys.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return hasDirect ? "direct" : "cloud"
    }

    @MainActor
    func effectiveProvider(appState: AppState) -> String {
        if !useGlobal && !provider.isEmpty {
            return provider
        }
        return appState.aiProvider.isEmpty ? "gemini" : appState.aiProvider
    }

    @MainActor
    func effectiveModel(appState: AppState) -> String {
        if !useGlobal && !model.isEmpty {
            return model
        }
        return appState.aiModel
    }

    @MainActor
    func effectiveSubscriptionProvider() -> String {
        if !useGlobal && !subscriptionProvider.isEmpty {
            return subscriptionProvider
        }
        return UserDefaults.standard.string(forKey: "subscriptionActiveProvider") ?? ""
    }

    @MainActor
    func activeACPAgentConfig(appState: AppState) -> ACPAgentConfig? {
        let mode = effectiveKeyMode(appState: appState)
        let prov = effectiveProvider(appState: appState)
        if useGlobal {
            if let id = ACPHostService.shared.activeAgentId {
                return ACPHostService.shared.registeredConfigs.first(where: { $0.id == id })
            }
            if ["subscription", "direct", "cloud", "local"].contains(mode) {
                return nil
            }
        } else {
            guard mode == "acp" else { return nil }
        }
        return Self.resolveACPConfig(forEngineId: prov)
    }

    @MainActor
    static func resolveACPConfig(forEngineId engineId: String) -> ACPAgentConfig? {
        let type: ACPAgentType? = {
            switch engineId {
            case "agy": return .agy
            case "codex": return .codexEngine
            case "claude_code": return .claudeCode
            case "gemini_cli": return .geminiCLI
            case "opencode": return .openCode
            case "cursor": return .cursorAgent
            case "copilot": return .githubCopilot
            case "goose": return .goose
            case "cline": return .cline
            case "qwen": return .qwenCode
            case "aider": return .aider
            case "zed": return .zedEngine
            default: return nil
            }
        }()
        guard let agentType = type else { return nil }
        let acpHost = ACPHostService.shared
        let discoveredBinary = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == engineId })?.binaryPath
            ?? ACPHostService.resolveAgentBinary(for: agentType)
            ?? agentType.defaultCommand
        if var existing = acpHost.registeredConfigs.first(where: { $0.type == agentType }) {
            if !FileManager.default.isExecutableFile(atPath: existing.command) {
                existing.command = discoveredBinary
                acpHost.registerAgent(existing)
            }
            return existing
        }
        let cfg = ACPAgentConfig.defaultConfig(for: agentType, command: discoveredBinary)
        acpHost.registerAgent(cfg)
        return cfg
    }

    @MainActor
    func modeBadgeTitle(appState: AppState) -> String {
        if activeACPAgentConfig(appState: appState) != nil { return "ACP" }
        let mode = effectiveKeyMode(appState: appState)
        let prov = effectiveProvider(appState: appState)
        let mod = effectiveModel(appState: appState)
        if mode == "local" || prov == "local" { return "Local" }
        if mode == "subscription" { return "Sub" }
        if (mode == "cloud" || prov == "omni") && mod.lowercased().hasPrefix("omni") { return "Cloud" }
        return "BYOK"
    }

    @MainActor
    func brandIconKey(appState: AppState) -> String {
        if let acp = activeACPAgentConfig(appState: appState) {
            return acp.type.brandIconKey
        }
        let mode = effectiveKeyMode(appState: appState)
        let prov = effectiveProvider(appState: appState)
        let mod = effectiveModel(appState: appState)
        if mode == "subscription" {
            let sub = effectiveSubscriptionProvider()
            if !sub.isEmpty { return sub }
        }
        let detected = StreamableAIProvider.detect(from: mod).rawValue
        if prov.isEmpty || prov == "omni" {
            return detected != "omni" ? detected : "microcode"
        }
        return prov
    }

    @MainActor
    func isConnected(appState: AppState) -> Bool {
        if useGlobal {
            return appState.isCurrentAIConnected
        }
        let mode = effectiveKeyMode(appState: appState)
        let prov = effectiveProvider(appState: appState)
        switch mode {
        case "acp":
            return LocalEcosystemDiscovery.shared.engines.contains(where: { $0.id == prov && $0.isInstalled })
                || activeACPAgentConfig(appState: appState) != nil
        case "subscription":
            return SubscriptionAuthManager.shared.hasAnyConnected || !appState.resolveApiKey(for: prov).isEmpty
        case "local":
            return LocalLLMService.shared.detectedServers.contains(where: { $0.isOnline })
        case "cloud":
            return AuthService.shared.currentUser != nil || !appState.resolveApiKey(for: "omni").isEmpty
        default:
            if prov == "9router" {
                return LocalLLMService.shared.detectedServers.contains(where: { $0.type == .nineRouter && $0.isOnline })
                    || ACPHostService.resolveExecutablePath("9router") != nil
                    || !appState.resolveApiKey(for: "9router").isEmpty
            }
            return !appState.resolveApiKey(for: prov).isEmpty
        }
    }

    @MainActor
    func displayTitle(appState: AppState, includeDefaultPrefix: Bool = false) -> String {
        let prefix = (useGlobal && includeDefaultPrefix) ? "Default · " : ""
        let prov = effectiveProvider(appState: appState)
        let mod = effectiveModel(appState: appState)
        let mode = effectiveKeyMode(appState: appState)

        if let acp = activeACPAgentConfig(appState: appState) {
            let engineId = acp.type.engineId
            let engineModels = LocalEcosystemDiscovery.shared.models(for: engineId)
            let modelName = engineModels.first(where: { $0.id == mod })?.name
                ?? AIModelCatalog.shared.model(id: mod)?.name
                ?? engineModels.first?.name
                ?? (mod.isEmpty ? acp.name : AIModelCatalog.formatModelName(mod))
            return "\(prefix)\(acp.name) : \(modelName)"
        }

        if mode == "subscription" {
            let subRaw = effectiveSubscriptionProvider()
            let provType = SubscriptionProviderType(rawValue: subRaw)
            if let info = SubscriptionAuthManager.shared.findModel(id: mod, provider: provType)
                ?? SubscriptionAuthManager.shared.findModel(id: mod) {
                let pName = (provType ?? info.provider).displayName.components(separatedBy: " ").first ?? "Sub"
                return "\(prefix)\(pName) : \(info.name)"
            }
            let fallback = mod.isEmpty ? "Default" : AIModelCatalog.formatModelName(mod)
            return "\(prefix)Sub : \(fallback)"
        }

        if mode == "local" || prov == "local" {
            let mName = LocalLLMService.shared.availableModels.first(where: { $0.id == mod })?.displayName
                ?? (mod.isEmpty ? "Local Model" : mod)
            return "\(prefix)Local : \(mName)"
        }

        let modelDef = AIModelCatalog.shared.model(id: mod)
        let fallbackName = AIModelCatalog.shared.provider(prov)?.models.first?.name
        let resolvedName = modelDef?.name ?? (mod.isEmpty ? fallbackName : nil)
        let formatted = AIModelCatalog.formatFullDisplayName(provider: prov, modelId: mod, modelName: resolvedName)
        return "\(prefix)\(formatted)"
    }

    /// Clean, concise model name without redundant provider/tier prefix bloat (the brand icon already conveys provider).
    @MainActor
    func conciseModelTitle(appState: AppState, includeDefaultPrefix: Bool = false) -> String {
        let prefix = (useGlobal && includeDefaultPrefix) ? "Default · " : ""
        let prov = effectiveProvider(appState: appState)
        let mod = effectiveModel(appState: appState)
        let mode = effectiveKeyMode(appState: appState)

        func stripParenthetical(_ raw: String) -> String {
            if let parenIdx = raw.firstIndex(of: "("), parenIdx > raw.startIndex {
                let trimmed = raw[..<parenIdx].trimmingCharacters(in: .whitespaces)
                if trimmed.count >= 6 { return trimmed }
            }
            return raw
        }

        if let acp = activeACPAgentConfig(appState: appState) {
            let engineId = acp.type.engineId
            let engineModels = LocalEcosystemDiscovery.shared.models(for: engineId)
            let modelName = engineModels.first(where: { $0.id == mod })?.name
                ?? AIModelCatalog.shared.model(id: mod)?.name
                ?? engineModels.first?.name
                ?? (mod.isEmpty ? "" : AIModelCatalog.formatModelName(mod))
            if modelName.isEmpty || modelName.caseInsensitiveCompare(acp.name) == .orderedSame {
                return "\(prefix)\(acp.name)"
            }
            return "\(prefix)\(acp.name) · \(stripParenthetical(modelName))"
        }

        if mode == "subscription" {
            let subRaw = effectiveSubscriptionProvider()
            let provType = SubscriptionProviderType(rawValue: subRaw)
            if let info = SubscriptionAuthManager.shared.findModel(id: mod, provider: provType)
                ?? SubscriptionAuthManager.shared.findModel(id: mod) {
                return "\(prefix)\(stripParenthetical(info.name))"
            }
            let fallback = mod.isEmpty ? "Subscription AI" : AIModelCatalog.formatModelName(mod)
            return "\(prefix)\(stripParenthetical(fallback))"
        }

        if mode == "local" || prov == "local" {
            let mName = LocalLLMService.shared.availableModels.first(where: { $0.id == mod })?.displayName
                ?? (mod.isEmpty ? "Local LLM" : mod)
            return "\(prefix)\(mName)"
        }

        if let modelDef = AIModelCatalog.shared.model(id: mod) {
            return "\(prefix)\(stripParenthetical(modelDef.name))"
        }
        if !mod.isEmpty {
            return "\(prefix)\(stripParenthetical(AIModelCatalog.formatModelName(mod)))"
        }
        if let firstModel = AIModelCatalog.shared.provider(prov)?.models.first {
            return "\(prefix)\(stripParenthetical(firstModel.name))"
        }
        return "\(prefix)\(prov.capitalized)"
    }
}

// MARK: - Structured Tool Step Model & Antigravity Minimalist Timeline

struct CellAgentToolStep: Identifiable, Equatable {
    let id: String
    let toolName: String
    var summary: String
    var output: String
    var isRunning: Bool
    var isError: Bool
    let startedAt: Date
    var durationMs: Int?

    var icon: String {
        switch toolName {
        case "cell_list": return "list.number"
        case "cell_read": return "doc.text.magnifyingglass"
        case "cell_create": return "plus.rectangle.on.rectangle"
        case "cell_update": return "pencil"
        case "cell_delete": return "trash"
        case "cell_run", "playground_run", "ardium_run": return "play.fill"
        case "shell": return "terminal"
        case "file_read", "multi_file_read": return "doc.text"
        case "file_write", "replace_in_file", "patch_file", "apply_patch": return "square.and.pencil"
        case "grep_search", "codebase_search", "file_search": return "magnifyingglass"
        case "web_fetch": return "globe"
        case "pns_nervous_system": return "point.3.connected.trianglepath.dotted"
        case "embedded_list_hardware": return "cable.connector"
        case "embedded_compile": return "hammer.fill"
        case "embedded_flash": return "bolt.fill"
        case "embedded_serial_capture": return "waveform.path.ecg"
        case "embedded_serial_send": return "paperplane.fill"
        case "embedded_decode_crash": return "ladybug.fill"
        default:
            if toolName.hasPrefix("mcp__") { return "puzzlepiece.extension" }
            return "wrench.and.screwdriver"
        }
    }

    var friendlyTitle: String {
        switch toolName {
        case "cell_list": return isRunning ? "Listing cells" : "Listed cells"
        case "cell_read": return isRunning ? "Inspecting" : "Inspected"
        case "cell_create": return isRunning ? "Creating" : "Created"
        case "cell_update": return isRunning ? "Editing" : "Edited"
        case "cell_delete": return isRunning ? "Removing" : "Removed"
        case "cell_run": return isRunning ? "Executing" : "Executed"
        case "playground_run": return isRunning ? "Running snippet" : "Ran snippet"
        case "ardium_run": return isRunning ? "Running Ardium" : "Ran Ardium"
        case "shell": return isRunning ? "Running command" : "Ran command"
        case "file_read", "multi_file_read": return isRunning ? "Reading" : "Read"
        case "file_write": return isRunning ? "Writing" : "Wrote"
        case "replace_in_file", "patch_file", "apply_patch": return isRunning ? "Editing" : "Edited"
        case "codebase_search", "grep_search", "file_search": return isRunning ? "Searching" : "Searched"
        case "list_directory_tree": return isRunning ? "Listing" : "Listed"
        case "embedded_list_hardware": return isRunning ? "Probing hardware" : "Probed hardware"
        case "embedded_compile": return isRunning ? "Cross-compiling firmware" : "Cross-compiled firmware"
        case "embedded_flash": return isRunning ? "Flashing microcontroller" : "Flashed microcontroller"
        case "embedded_serial_capture": return isRunning ? "Capturing UART serial" : "Captured UART serial"
        case "embedded_serial_send": return isRunning ? "Sending UART command" : "Sent UART command"
        case "embedded_decode_crash": return isRunning ? "Symbolicating DWARF crash" : "Symbolicated DWARF crash"
        default:
            let clean = toolName.replacingOccurrences(of: "mcp__", with: "").replacingOccurrences(of: "_", with: " ")
            return isRunning ? "Running \(clean)" : "Ran \(clean)"
        }
    }
}

/// Formal, borderless collapsible action timeline matching MicroCode's main AIAgentView (`ToolExecutionStepsView`).
struct CellAgentToolStepsTimeline: View {
    let steps: [CellAgentToolStep]
    @EnvironmentObject var appState: AppState
    @State private var isExpanded: Bool = true
    @State private var isHeaderHovered: Bool = false

    private var hasRunningStep: Bool {
        steps.contains(where: { $0.isRunning })
    }

    private var errorCount: Int {
        steps.filter { !$0.isRunning && $0.isError }.count
    }

    private var totalDurationText: String? {
        let totalMs = steps.compactMap(\.durationMs).reduce(0, +)
        guard totalMs > 0 else { return nil }
        return totalMs >= 1000
            ? String(format: "%.1fs", Double(totalMs) / 1000.0)
            : "\(totalMs)ms"
    }

    private var groupSummaryText: String {
        if let active = steps.last(where: { $0.isRunning }) {
            let detail = active.summary.isEmpty ? "" : " \(active.summary)"
            return "\(active.friendlyTitle)\(detail)…"
        }
        let n = steps.count
        let noun = n == 1 ? "step" : "steps"
        if errorCount > 0 {
            return "Executed \(n) \(noun) (\(errorCount) failed)"
        }
        return "Executed \(n) \(noun)"
    }

    var body: some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        if hasRunningStep {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.72)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.8))
                                .frame(width: 10)
                        }

                        Text(groupSummaryText)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(isHeaderHovered ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if !hasRunningStep, let dur = totalDurationText {
                            Text("· \(dur)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.7))
                                .fixedSize()
                        }

                        Spacer(minLength: 4)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHeaderHovered = $0 }

                if isExpanded {
                    HStack(alignment: .top, spacing: 0) {
                        Rectangle()
                            .fill(Color.primary.opacity(appState.appTheme.isDark ? 0.12 : 0.09))
                            .frame(width: 1)
                            .padding(.leading, 5)
                            .padding(.vertical, 2)

                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(steps) { step in
                                CellAgentToolStepRow(step: step)
                            }
                        }
                        .padding(.leading, 9)
                    }
                }
            }
        }
    }
}

struct CellAgentToolStepRow: View {
    let step: CellAgentToolStep
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(action: {
                if !step.output.isEmpty {
                    withAnimation(.easeInOut(duration: 0.14)) { isExpanded.toggle() }
                }
            }) {
                HStack(spacing: 6) {
                    Group {
                        if step.isRunning {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.68)
                        } else if step.isError {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(Color.red.opacity(0.85))
                        } else {
                            Image(systemName: step.icon)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 13, height: 13)

                    Text(step.friendlyTitle)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(step.isError ? Color.red.opacity(0.9) : .primary.opacity(0.86))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if !step.summary.isEmpty {
                        Text(step.summary)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 4)

                    if let ms = step.durationMs {
                        Text(ms >= 1000 ? String(format: "%.1fs", Double(ms) / 1000.0) : "\(ms)ms")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.68))
                            .fixedSize()
                    }

                    if !step.output.isEmpty {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondary.opacity(isHovered || isExpanded ? 0.9 : 0.45))
                            .fixedSize()
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered && !step.output.isEmpty ? Color.primary.opacity(0.045) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            if isExpanded && !step.output.isEmpty {
                ScrollView {
                    Text(step.output.prefix(4000))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(step.isError ? Color.red.opacity(0.9) : .primary.opacity(0.84))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 150)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(appState.appTheme.isDark ? 0.045 : 0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.primary.opacity(appState.appTheme.isDark ? 0.10 : 0.07), lineWidth: 0.8)
                )
                .padding(.leading, 6)
                .padding(.bottom, 3)
            }
        }
    }
}

// MARK: - Formal Minimalist Agent / Ask Segmented Mode Switcher

struct CellModeTogglePill: View {
    @Binding var isAgentMode: Bool
    var compact: Bool = false
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 1) {
            modeButton(
                title: "Agent",
                selected: isAgentMode
            ) {
                withAnimation(.easeInOut(duration: 0.14)) { isAgentMode = true }
            }
            modeButton(
                title: "Ask",
                selected: !isAgentMode
            ) {
                withAnimation(.easeInOut(duration: 0.14)) { isAgentMode = false }
            }
        }
        .padding(2)
        .background(Color.primary.opacity(appState.appTheme.isDark ? 0.06 : 0.045))
        .cornerRadius(5)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.primary.opacity(appState.appTheme.isDark ? 0.11 : 0.08), lineWidth: 0.8)
        )
        .fixedSize(horizontal: true, vertical: false)
        .help(isAgentMode
              ? "Agent Mode: Autonomous tool calling (inspect, create, edit & execute cells, files, and MCP tools)"
              : "Ask Mode: Read-only Q&A and code generation without auto-mutating cells")
    }

    @ViewBuilder
    private func modeButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 10 : 10.5, weight: selected ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(selected ? .primary : .secondary)
                .padding(.horizontal, compact ? 6.5 : 8)
                .padding(.vertical, compact ? 2 : 3)
                .background(
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(selected ? Color.primary.opacity(appState.appTheme.isDark ? 0.13 : 0.09) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Unified AI Model & Role Selector Pill (Global or Per-Cell, Responsive)

struct CellAIModelSelectorPill: View {
    @EnvironmentObject var appState: AppState
    /// Pass `nil` to read/write global Cell Mode AI (`appState`), or pass a binding for per-cell override.
    var selection: Binding<CellAISelection>? = nil
    var showRoleSelector: Bool = false
    var roleBinding: Binding<String>? = nil
    var maxWidth: CGFloat? = 210
    var compact: Bool = false
    var minimalChrome: Bool = false
    var roleIconOnly: Bool = false

    @ObservedObject private var modelCatalog = AIModelCatalog.shared
    @ObservedObject private var acpHost = ACPHostService.shared
    @State private var showingAgentConnections = false

    private var effectiveSelection: CellAISelection {
        selection?.wrappedValue ?? .inherit
    }

    private var activeRole: CellSubAgentRole {
        if let r = roleBinding?.wrappedValue {
            return CellSubAgentRole(rawValue: r) ?? .dataScientist
        }
        return effectiveSelection.roleEnum
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                CellAIModelMenuPresenter.present(
                    appState: appState,
                    selection: selection,
                    roleBinding: roleBinding,
                    onOpenConnections: { showingAgentConnections = true }
                )
            }) {
                HStack(spacing: 4.5) {
                    if !effectiveSelection.isConnected(appState: appState) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: compact ? 9.5 : 10.5, weight: .medium))
                            .foregroundColor(.accentColor)
                            .fixedSize()
                        Text("Connect AI")
                            .font(.system(size: compact ? 10 : 11, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    } else {
                        AIProviderBrandIcon(
                            provider: effectiveSelection.brandIconKey(appState: appState),
                            size: compact ? 11.5 : 12.5
                        )
                        .fixedSize()
                        Text(effectiveSelection.conciseModelTitle(appState: appState, includeDefaultPrefix: selection != nil && !effectiveSelection.useGlobal ? false : false))
                            .font(.system(size: compact ? 10 : 11, weight: .medium))
                            .foregroundColor(minimalChrome ? .secondary : .primary.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.8))
                        .fixedSize()
                }
                .frame(minWidth: 52, maxWidth: maxWidth, alignment: .leading)
                .fixedSize(horizontal: maxWidth == nil, vertical: false)
                .padding(.horizontal, compact ? 6 : 7.5)
                .padding(.vertical, compact ? 2.5 : 3.5)
                .background(
                    minimalChrome
                        ? Color.primary.opacity(0.035)
                        : (appState.appTheme.isGlass
                            ? Color.primary.opacity(0.055)
                            : Color(nsColor: appState.appTheme.elevatedBackground))
                )
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(
                            (!effectiveSelection.useGlobal && selection != nil)
                                ? Color.accentColor.opacity(0.4)
                                : Color.primary.opacity(minimalChrome ? 0.06 : (appState.appTheme.isDark ? 0.11 : 0.08)),
                            lineWidth: 0.8
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(-1)
            .help("\(effectiveSelection.modeBadgeTitle(appState: appState)) · \(effectiveSelection.displayTitle(appState: appState, includeDefaultPrefix: selection != nil))")

            if showRoleSelector {
                if roleIconOnly {
                    roleMenu(showLabel: false)
                } else {
                    ViewThatFits(in: .horizontal) {
                        roleMenu(showLabel: true)
                        roleMenu(showLabel: false)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAgentConnections) {
            AgentConnectionsView()
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private func roleMenu(showLabel: Bool) -> some View {
        Menu {
            Text("Specialist Role")
                .font(.caption)
            Divider()
            ForEach(CellSubAgentRole.allCases) { role in
                Button {
                    if let rb = roleBinding {
                        rb.wrappedValue = role.rawValue
                    } else if let sel = selection {
                        sel.wrappedValue.subAgentRole = role.rawValue
                    }
                } label: {
                    HStack {
                        Image(systemName: role.icon)
                        Text(role.displayName)
                        if activeRole == role {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3.5) {
                Image(systemName: activeRole.icon)
                    .font(.system(size: compact ? 9 : 10, weight: .regular))
                    .foregroundColor(.secondary)
                    .fixedSize()
                if showLabel {
                    Text(activeRole.shortBadge)
                        .font(.system(size: compact ? 10 : 10.5, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.75))
                    .fixedSize()
            }
            .padding(.horizontal, compact ? 5.5 : 6.5)
            .padding(.vertical, compact ? 2.5 : 3.5)
            .background(
                minimalChrome
                    ? Color.primary.opacity(0.035)
                    : (appState.appTheme.isGlass
                        ? Color.primary.opacity(0.055)
                        : Color(nsColor: appState.appTheme.elevatedBackground))
            )
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(minimalChrome ? 0.06 : (appState.appTheme.isDark ? 0.11 : 0.08)), lineWidth: 0.8)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help("Specialist Role: \(activeRole.displayName)")
    }
}

// MARK: - Native NSMenu Presenter for All AI Providers / Subscriptions / ACP / Local / Roles

@MainActor
enum CellAIModelMenuPresenter {
    private static func makeActionItem(
        _ title: String,
        brandKey: String? = nil,
        systemImage: String? = nil,
        checked: Bool = false,
        enabled: Bool = true,
        action: (() -> Void)? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action != nil ? #selector(ClosureMenuActionHandler.performMenuAction(_:)) : nil,
            keyEquivalent: ""
        )
        if let action {
            item.target = ClosureMenuActionHandler.shared
            item.representedObject = action
        }
        item.isEnabled = enabled
        item.state = checked ? .on : .off
        if let brandKey {
            item.image = AIProviderBrandIcon.menuImage(for: brandKey, size: 15)
        } else if let systemImage, let img = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
            item.image = img
        }
        return item
    }

    private static func makeSubmenuItem(
        _ title: String,
        brandKey: String? = nil,
        systemImage: String? = nil,
        checked: Bool = false,
        submenu: NSMenu
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        item.state = checked ? .on : .off
        if let brandKey {
            item.image = AIProviderBrandIcon.menuImage(for: brandKey, size: 15)
        } else if let systemImage, let img = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
            item.image = img
        }
        return item
    }

    private static func hasActiveKey(_ provider: String, appState: AppState) -> Bool {
        if provider == "local" {
            return LocalLLMService.shared.activeServer?.isOnline == true
        }
        if provider == "9router" {
            return LocalLLMService.shared.detectedServers.contains(where: { $0.type == .nineRouter && $0.isOnline })
                || ACPHostService.resolveExecutablePath("9router") != nil
                || !appState.resolveApiKey(for: "9router").isEmpty
        }
        return !appState.resolveApiKey(for: provider).isEmpty
    }

    static func applyGlobalChoice(
        appState: AppState,
        keyMode: String,
        provider: String,
        model: String,
        subscriptionProvider: SubscriptionProviderType? = nil,
        localEndpoint: String? = nil
    ) {
        if keyMode == "acp" {
            UserDefaults.standard.set("acp", forKey: "aiKeyMode")
            if let cfg = CellAISelection.resolveACPConfig(forEngineId: provider) {
                ACPHostService.shared.activeAgentId = cfg.id
            }
            appState.aiProvider = provider
            appState.aiModel = model
            appState.saveSettings()
            return
        }

        ACPHostService.shared.stopActiveAgent()
        ACPHostService.shared.activeAgentId = nil
        UserDefaults.standard.set(keyMode, forKey: "aiKeyMode")
        appState.aiProvider = provider
        appState.aiModel = model

        if let sub = subscriptionProvider {
            SubscriptionAuthManager.shared.activeProvider = sub
            UserDefaults.standard.set(sub.rawValue, forKey: "subscriptionActiveProvider")
        }
        if let endpoint = localEndpoint, !endpoint.isEmpty {
            LocalLLMService.shared.selectedModelId = model
            LocalLLMService.cachedEndpoint = endpoint
            LocalLLMService.cachedModel = model
        }
        appState.saveSettings()
    }

    static func present(
        appState: AppState,
        selection: Binding<CellAISelection>?,
        roleBinding: Binding<String>? = nil,
        onOpenConnections: @escaping () -> Void
    ) {
        Task { await AIModelCatalog.shared.refreshIfNeeded(force: false) }
        let rootMenu = NSMenu(title: "Select Cell Mode AI")
        rootMenu.autoenablesItems = false

        let currentSel = selection?.wrappedValue ?? .inherit
        let curMode = currentSel.effectiveKeyMode(appState: appState)
        let curProv = currentSel.effectiveProvider(appState: appState)
        let curMod = currentSel.effectiveModel(appState: appState)

        // Optional Per-Cell Default Inheritance Item
        if let selBinding = selection {
            let globalTitle = CellAISelection.inherit.displayTitle(appState: appState)
            rootMenu.addItem(makeActionItem(
                "Use Cell Mode Default (\(globalTitle))",
                systemImage: "sparkles",
                checked: selBinding.wrappedValue.useGlobal
            ) {
                let role = selBinding.wrappedValue.subAgentRole
                var next = CellAISelection.inherit
                next.subAgentRole = role
                selBinding.wrappedValue = next
            })
            rootMenu.addItem(.separator())
        }

        func commitChoice(
            keyMode: String,
            provider: String,
            model: String,
            subType: SubscriptionProviderType? = nil,
            localEndpoint: String? = nil
        ) {
            if let selBinding = selection {
                var updated = selBinding.wrappedValue
                updated.useGlobal = false
                updated.keyMode = keyMode
                updated.provider = provider
                updated.model = model
                updated.subscriptionProvider = subType?.rawValue ?? ""
                updated.localEndpoint = localEndpoint ?? ""
                selBinding.wrappedValue = updated
            } else {
                applyGlobalChoice(
                    appState: appState,
                    keyMode: keyMode,
                    provider: provider,
                    model: model,
                    subscriptionProvider: subType,
                    localEndpoint: localEndpoint
                )
            }
        }

        // 1. Subscription (ChatGPT, Claude, Gemini, Copilot, TH-AI Passport)
        let subMenu = NSMenu(title: "Subscription")
        subMenu.autoenablesItems = false
        let connected = SubscriptionAuthManager.shared.connectedProviders()
        let connectedSet = Set(connected)
        let orderedSubProviders = connected + SubscriptionProviderType.allCases.filter { !connectedSet.contains($0) }
        var addedSubSep = false
        for prov in orderedSubProviders {
            let isConn = connectedSet.contains(prov)
            if !isConn && !connected.isEmpty && !addedSubSep {
                subMenu.addItem(.separator())
                addedSubSep = true
            }
            let provMenu = NSMenu(title: prov.displayName)
            provMenu.autoenablesItems = false

            func makeSubItem(_ subModel: SubscriptionModelInfo) -> NSMenuItem {
                let title = subModel.badge.isEmpty ? subModel.name : "\(subModel.name) [\(subModel.badge)]"
                let checked = (!currentSel.useGlobal || selection == nil)
                    && curMode == "subscription"
                    && curMod == subModel.modelID
                return makeActionItem(title, brandKey: subModel.provider.rawValue, checked: checked) {
                    commitChoice(keyMode: "subscription", provider: subModel.aiProviderID, model: subModel.modelID, subType: subModel.provider)
                }
            }

            if prov == .aipass {
                let allModels = prov.modelInfos
                let chatModels = allModels.filter { !AIClient.isAiPassMediaModel($0.modelID) && !["IMAGE", "VIDEO", "MUSIC"].contains($0.badge) }
                let imgModels = allModels.filter { $0.badge == "IMAGE" || AIClient.isAiPassImageModel($0.modelID) }
                let vidModels = allModels.filter { $0.badge == "VIDEO" || AIClient.isAiPassVideoModel($0.modelID) }
                let musModels = allModels.filter { $0.badge == "MUSIC" || AIClient.isAiPassMusicModel($0.modelID) }

                let chatSub = NSMenu(title: "Chat")
                chatModels.forEach { chatSub.addItem(makeSubItem($0)) }
                provMenu.addItem(makeSubmenuItem("Chat, Coding & Reasoning (\(chatModels.count))", brandKey: "aipass", submenu: chatSub))

                if !imgModels.isEmpty {
                    let imgSub = NSMenu(title: "Image")
                    imgModels.forEach { imgSub.addItem(makeSubItem($0)) }
                    provMenu.addItem(makeSubmenuItem("Image Generation (\(imgModels.count))", brandKey: "aipass", submenu: imgSub))
                }
                if !vidModels.isEmpty {
                    let vidSub = NSMenu(title: "Video")
                    vidModels.forEach { vidSub.addItem(makeSubItem($0)) }
                    provMenu.addItem(makeSubmenuItem("Video Generation (\(vidModels.count))", brandKey: "aipass", submenu: vidSub))
                }
                if !musModels.isEmpty {
                    let musSub = NSMenu(title: "Music")
                    musModels.forEach { musSub.addItem(makeSubItem($0)) }
                    provMenu.addItem(makeSubmenuItem("Audio & Music Generation (\(musModels.count))", brandKey: "aipass", submenu: musSub))
                }
            } else {
                for subModel in prov.modelInfos.prefix(100) {
                    provMenu.addItem(makeSubItem(subModel))
                }
            }

            provMenu.addItem(.separator())
            if isConn {
                provMenu.addItem(makeActionItem("Fetch Live Models Now", systemImage: "arrow.clockwise") {
                    Task { await SubscriptionAuthManager.shared.fetchLiveModels(for: prov) }
                })
            } else {
                provMenu.addItem(makeActionItem("Connect \(prov.displayName) in Agent Connections…", systemImage: "link") {
                    onOpenConnections()
                })
            }
            subMenu.addItem(makeSubmenuItem("\(prov.displayName)\(isConn ? " (Active)" : "")", brandKey: prov.rawValue, submenu: provMenu))
        }
        rootMenu.addItem(makeSubmenuItem(
            "Subscription (ChatGPT, Claude, Gemini, TH-AI Pass)",
            brandKey: connected.first?.rawValue ?? "claude",
            checked: (!currentSel.useGlobal || selection == nil) && curMode == "subscription",
            submenu: subMenu
        ))

        // 2. BYOK & Smart Routers
        let byokMenu = NSMenu(title: "BYOK")
        byokMenu.autoenablesItems = false
        let acpSet: Set<String> = ["omni", "agy", "codex", "claude_code", "opencode", "zed", "gemini_cli", "cursor", "goose", "cline", "aider", "local"]
        let byokProviders = AIModelCatalog.shared.providers.filter { !acpSet.contains($0.id) }
        for prov in byokProviders {
            let hasKey = hasActiveKey(prov.id, appState: appState)
            let provMenu = NSMenu(title: prov.name)
            provMenu.autoenablesItems = false
            for m in prov.models.prefix(100) {
                let label = m.badge.isEmpty ? m.name : "\(m.name) (\(m.badge))"
                let checked = (!currentSel.useGlobal || selection == nil)
                    && curMode == "direct"
                    && curProv == prov.id
                    && curMod == m.id
                provMenu.addItem(makeActionItem(label, brandKey: prov.id, checked: checked) {
                    commitChoice(keyMode: "direct", provider: prov.id, model: m.id)
                })
            }
            provMenu.addItem(.separator())
            if hasKey || prov.id == "9router" {
                provMenu.addItem(makeActionItem("Fetch Live Models Now", systemImage: "arrow.clockwise") {
                    Task { await AIModelCatalog.shared.fetchLiveModelsForProvider(prov.id) }
                })
            } else {
                provMenu.addItem(makeActionItem("Set \(prov.name) API Key in Settings…", systemImage: "key") {
                    appState.showingSettingsDialog = true
                })
            }
            let suffix = prov.id == "9router" ? (hasKey ? " (Ready)" : " (localhost:20128)") : (hasKey ? "" : " (No Key)")
            byokMenu.addItem(makeSubmenuItem("\(prov.name)\(suffix)", brandKey: prov.id, submenu: provMenu))
        }
        rootMenu.addItem(makeSubmenuItem(
            "BYOK & Smart Routers (Gemini, Claude, OpenAI, DeepSeek, 9Router…)",
            brandKey: curMode == "direct" ? curProv : "9router",
            checked: (!currentSel.useGlobal || selection == nil) && curMode == "direct",
            submenu: byokMenu
        ))

        // 3. Local LLM (Ollama, LM Studio, MLX, 9Router)
        let localMenu = NSMenu(title: "Local LLM")
        localMenu.autoenablesItems = false
        let onlineServers = LocalLLMService.shared.detectedServers.filter { $0.isOnline }
        if onlineServers.isEmpty {
            localMenu.addItem(makeActionItem("No Running Local LLM Server Found", enabled: false))
            localMenu.addItem(.separator())
            localMenu.addItem(makeActionItem("Scan Local Engines (Ollama, LM Studio, MLX, 9Router)", systemImage: "arrow.clockwise") {
                Task {
                    await LocalLLMService.shared.scanForServers()
                    AIModelCatalog.shared.integrateLocalModels()
                }
            })
        } else {
            for srv in onlineServers {
                let srvMenu = NSMenu(title: srv.displayName)
                srvMenu.autoenablesItems = false
                if srv.models.isEmpty {
                    srvMenu.addItem(makeActionItem("No models loaded on this server", enabled: false))
                } else {
                    for m in srv.models {
                        let title = (m.size?.isEmpty == false) ? "\(m.displayName) • \(m.size!)" : m.displayName
                        let checked = (!currentSel.useGlobal || selection == nil)
                            && (curMode == "local" || curProv == "local")
                            && curMod == m.id
                        srvMenu.addItem(makeActionItem(title, brandKey: srv.type.brandKey, checked: checked) {
                            commitChoice(keyMode: "local", provider: "local", model: m.id, localEndpoint: srv.endpoint)
                        })
                    }
                }
                localMenu.addItem(makeSubmenuItem("\(srv.displayName) (\(srv.models.count) models)", brandKey: srv.type.brandKey, submenu: srvMenu))
            }
            localMenu.addItem(.separator())
            localMenu.addItem(makeActionItem("Rescan Local Engines", systemImage: "arrow.clockwise") {
                Task {
                    await LocalLLMService.shared.scanForServers()
                    AIModelCatalog.shared.integrateLocalModels()
                }
            })
        }
        rootMenu.addItem(makeSubmenuItem(
            "Local LLM (Ollama, LM Studio, MLX)",
            brandKey: "local",
            checked: (!currentSel.useGlobal || selection == nil) && (curMode == "local" || curProv == "local"),
            submenu: localMenu
        ))

        // 4. ACP External Harnesses
        let acpMenu = NSMenu(title: "ACP Harnesses")
        acpMenu.autoenablesItems = false
        for engine in LocalEcosystemDiscovery.shared.engines where engine.id != "zed" || engine.isInstalled {
            let engMenu = NSMenu(title: engine.name)
            engMenu.autoenablesItems = false
            if engine.models.isEmpty {
                engMenu.addItem(makeActionItem("Connect \(engine.name) in Agent Connections…", brandKey: engine.id) {
                    onOpenConnections()
                })
            } else {
                for m in engine.models {
                    let title = m.badge.isEmpty ? m.name : "\(m.name) (\(m.badge))"
                    let checked = (!currentSel.useGlobal || selection == nil)
                        && curMode == "acp"
                        && curProv == engine.id
                        && curMod == m.id
                    engMenu.addItem(makeActionItem(title, brandKey: engine.id, checked: checked) {
                        commitChoice(keyMode: "acp", provider: engine.id, model: m.id)
                    })
                }
            }
            acpMenu.addItem(makeSubmenuItem(engine.name + (engine.isInstalled ? "" : " (Not Installed)"), brandKey: engine.id, submenu: engMenu))
        }
        rootMenu.addItem(makeSubmenuItem(
            "ACP Harnesses (Claude Code, AGY, Codex, Gemini CLI, Goose, Cursor…)",
            brandKey: curMode == "acp" ? currentSel.brandIconKey(appState: appState) : "agy",
            checked: (!currentSel.useGlobal || selection == nil) && curMode == "acp",
            submenu: acpMenu
        ))

        // 5. Dotmini Sovereign AI (Omni O1X)
        let cloudMenu = NSMenu(title: "Dotmini Sovereign AI")
        cloudMenu.autoenablesItems = false
        if let omni = AIModelCatalog.shared.provider("omni") {
            let omniModels = omni.models.filter { $0.id.lowercased().hasPrefix("omni") }
            for m in omniModels {
                let checked = (!currentSel.useGlobal || selection == nil)
                    && curMode == "cloud"
                    && curMod == m.id
                cloudMenu.addItem(makeActionItem(m.name, brandKey: "microcode", checked: checked) {
                    commitChoice(keyMode: "cloud", provider: "omni", model: m.id)
                })
            }
        }
        rootMenu.addItem(makeSubmenuItem(
            "Dotmini Sovereign AI (Omni O1X)",
            brandKey: "microcode",
            checked: (!currentSel.useGlobal || selection == nil) && curMode == "cloud",
            submenu: cloudMenu
        ))

        // 6. Specialist Agent Role Submenu (if applicable)
        if roleBinding != nil || selection != nil {
            rootMenu.addItem(.separator())
            let roleMenu = NSMenu(title: "Specialist Agent Role")
            roleMenu.autoenablesItems = false
            let currentRoleRaw = roleBinding?.wrappedValue ?? selection?.wrappedValue.subAgentRole ?? CellSubAgentRole.dataScientist.rawValue
            for role in CellSubAgentRole.allCases {
                roleMenu.addItem(makeActionItem(
                    role.displayName,
                    systemImage: role.icon,
                    checked: currentRoleRaw == role.rawValue
                ) {
                    if let rb = roleBinding {
                        rb.wrappedValue = role.rawValue
                    }
                    if let sb = selection {
                        sb.wrappedValue.subAgentRole = role.rawValue
                    }
                })
            }
            let activeRole = CellSubAgentRole(rawValue: currentRoleRaw) ?? .dataScientist
            rootMenu.addItem(makeSubmenuItem(
                "Agent Role: \(activeRole.displayName)",
                systemImage: activeRole.icon,
                submenu: roleMenu
            ))
        }

        rootMenu.addItem(.separator())
        rootMenu.addItem(makeActionItem("Manage Agent Connections & Setup…", systemImage: "slider.horizontal.2.square") {
            onOpenConnections()
        })
        rootMenu.addItem(makeActionItem("Rescan Local Engines & Cloud APIs", systemImage: "arrow.triangle.2.circlepath") {
            Task {
                await AIModelCatalog.shared.refreshLiveProviderModels()
                await LocalEcosystemDiscovery.shared.refresh(force: true)
                await LocalLLMService.shared.scanForServers()
                AIModelCatalog.shared.integrateLocalModels()
            }
        })
        rootMenu.addItem(makeActionItem("AI Settings…", systemImage: "gearshape") {
            appState.showingSettingsDialog = true
        })

        rootMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

// MARK: - Unified Cell Mode Autonomous Agent & Chat Coordinator

private final class CellStreamGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(String, [AIToolCall], String?), Never>?

    init(_ continuation: CheckedContinuation<(String, [AIToolCall], String?), Never>) {
        self.continuation = continuation
    }

    @discardableResult
    func resumeOnce(_ value: (String, [AIToolCall], String?)) -> Bool {
        lock.lock()
        guard let cont = continuation else {
            lock.unlock()
            return false
        }
        continuation = nil
        lock.unlock()
        cont.resume(returning: value)
        return true
    }
}

@MainActor
final class CellAgentCoordinator {
    static let shared = CellAgentCoordinator()

    private var activeTasks: [String: Task<Void, Never>] = [:]
    private var cancelledSessions: Set<String> = []

    private init() {}

    func isRunning(sessionId: String) -> Bool {
        activeTasks[sessionId] != nil
    }

    func stop(sessionId: String) {
        cancelledSessions.insert(sessionId)
        activeTasks[sessionId]?.cancel()
        activeTasks.removeValue(forKey: sessionId)
        AIClient.shared.cancelStream()
        ACPHostService.shared.stopActiveAgent()
    }

    /// Builds a concise, structured snapshot of the active Notebook & attached DataFiles for Agent/Ask prompts.
    func buildNotebookContextSnapshot(viewModel: NotebookViewModel) -> String {
        guard let notebook = viewModel.activeNotebook else {
            return "No active notebook loaded."
        }
        var ctx = "## Active Notebook: \(notebook.name)\n"
        ctx += "- Working Directory: `\(viewModel.workingDirectory.path)`\n"
        ctx += "- Total Cells: \(notebook.cells.count)\n"
        if !notebook.dataFiles.isEmpty {
            let filesDesc = notebook.dataFiles.map {
                let sz = ByteCountFormatter.string(fromByteCount: $0.size, countStyle: .file)
                return "\($0.name) (\(sz), path: \($0.url.path))"
            }.joined(separator: ", ")
            ctx += "- Attached Datasets: \(filesDesc)\n"
        }
        ctx += "\n"

        for (i, cell) in notebook.cells.enumerated() {
            let selectedMark = (cell.id == viewModel.selectedCellId) ? " [SELECTED]" : ""
            let tagMark = cell.tag.isEmpty ? "" : " [tag: \(cell.tag)]"
            ctx += "### Cell #\(i + 1) (id: `\(cell.id.uuidString)`, type: \(cell.type.rawValue), lang: \(cell.language.rawValue))\(selectedMark)\(tagMark)\n"
            let code = cell.content.count > 2200 ? String(cell.content.prefix(2200)) + "\n... (truncated)" : cell.content
            ctx += "```\(cell.language.fileExtension)\n\(code)\n```\n"
            if !cell.output.isEmpty {
                let out = cell.output.count > 1200 ? String(cell.output.prefix(1200)) + "\n... (truncated)" : cell.output
                ctx += "Output:\n```\n\(out)\n```\n"
            }
            if !cell.outputImages.isEmpty {
                ctx += "Generated Images/Plots: \(cell.outputImages.map(\.lastPathComponent).joined(separator: ", "))\n"
            }
            ctx += "\n"
        }
        return ctx
    }

    // MARK: - Unified Run Entry Point

    func startExecution(
        sessionId: String,
        prompt: String,
        selection: CellAISelection,
        isAgentMode: Bool,
        appState: AppState,
        notebookContext: String,
        workspaceRoot: String,
        conversationHistory: [(role: String, content: String)] = [],
        maxAgentTurns: Int = 12,
        onStatus: @escaping @MainActor (String) -> Void,
        onThought: @escaping @MainActor (String) -> Void,
        onText: @escaping @MainActor (String) -> Void,
        onToolSteps: @escaping @MainActor ([CellAgentToolStep]) -> Void,
        onComplete: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        stop(sessionId: sessionId)
        cancelledSessions.remove(sessionId)

        let task = Task { @MainActor in
            defer {
                self.activeTasks.removeValue(forKey: sessionId)
            }

            let role = selection.roleEnum
            let keyMode = selection.effectiveKeyMode(appState: appState)
            var acpConfig = selection.activeACPAgentConfig(appState: appState)

            // Native ChatGPT Plus / Pro Codex OAuth check
            var useDirectCodexOAuth = false
            let effProv = selection.effectiveProvider(appState: appState)
            let chatgptSubToken = SubscriptionAuthManager.shared.getAccount(.chatgpt)?.sessionToken ?? ""
            if keyMode == "subscription" && effProv == "openai" && !chatgptSubToken.hasPrefix("sk-"),
               AIClient.loadCodexOAuthCredentials(fallbackToken: chatgptSubToken) != nil {
                useDirectCodexOAuth = true
            } else if acpConfig?.type == .codexEngine,
                      let cmd = acpConfig?.command,
                      !FileManager.default.isExecutableFile(atPath: cmd),
                      AIClient.loadCodexOAuthCredentials(fallbackToken: chatgptSubToken) != nil {
                acpConfig = nil
                useDirectCodexOAuth = true
            }

            // 1. ACP External Harness Route
            if let activeACP = acpConfig {
                await self.executeACPRoute(
                    sessionId: sessionId,
                    config: activeACP,
                    prompt: prompt,
                    selection: selection,
                    isAgentMode: isAgentMode,
                    role: role,
                    appState: appState,
                    notebookContext: notebookContext,
                    workspaceRoot: workspaceRoot,
                    onStatus: onStatus,
                    onThought: onThought,
                    onText: onText,
                    onToolSteps: onToolSteps,
                    onComplete: onComplete,
                    onError: onError
                )
                return
            }

            // 2. Unified Native AIClient Route (Subscription, BYOK, Local LLM, Dotmini Cloud)
            await self.executeNativeRoute(
                sessionId: sessionId,
                prompt: prompt,
                selection: selection,
                useDirectCodexOAuth: useDirectCodexOAuth,
                isAgentMode: isAgentMode,
                role: role,
                appState: appState,
                notebookContext: notebookContext,
                workspaceRoot: workspaceRoot,
                conversationHistory: conversationHistory,
                maxAgentTurns: maxAgentTurns,
                onStatus: onStatus,
                onThought: onThought,
                onText: onText,
                onToolSteps: onToolSteps,
                onComplete: onComplete,
                onError: onError
            )
        }

        activeTasks[sessionId] = task
    }

    // MARK: - ACP Harness Execution Route

    private func executeACPRoute(
        sessionId: String,
        config: ACPAgentConfig,
        prompt: String,
        selection: CellAISelection,
        isAgentMode: Bool,
        role: CellSubAgentRole,
        appState: AppState,
        notebookContext: String,
        workspaceRoot: String,
        onStatus: @escaping @MainActor (String) -> Void,
        onThought: @escaping @MainActor (String) -> Void,
        onText: @escaping @MainActor (String) -> Void,
        onToolSteps: @escaping @MainActor ([CellAgentToolStep]) -> Void,
        onComplete: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) async {
        onStatus("Connecting to \(config.name)…")
        let session = ACPHostService.shared.getOrCreateSession(for: config)
        let effModel = selection.effectiveModel(appState: appState)
        let chosenModel: String? = effModel.isEmpty ? nil : effModel

        let modeDirective = isAgentMode
            ? "MODE: Autonomous Agent Mode. Inspect files/datasets, execute commands/tools, and provide verified runnable code and results."
            : "MODE: Ask / Chat Mode (Read-Only). Do NOT modify files on disk; answer concisely with clear code blocks."

        let fullTask = """
        [MicroCode Cell Mode — \(role.displayName)]
        \(role.rolePrompt)
        \(modeDirective)

        \(notebookContext)

        ## User Request
        \(prompt)
        """

        let stream = session.eventStream
        let expanded = await AgentContextProtocolBridge.shared.expandMentions(prompt: fullTask, workspaceRoot: workspaceRoot)
        session.start(task: expanded.expandedPrompt, workspacePath: workspaceRoot, model: chosenModel)

        var accumulatedThinking = ""
        var accumulatedText = ""
        var steps: [CellAgentToolStep] = []

        for await event in stream {
            if Task.isCancelled || cancelledSessions.contains(sessionId) { return }
            switch event {
            case .sessionInit:
                onStatus("\(config.name) initialized…")
            case .progress(let prog):
                onStatus(prog.message)
            case .thinking(let delta):
                accumulatedThinking += delta
                onStatus("\(config.name) reasoning…")
                onThought(accumulatedThinking)
            case .text(let delta):
                accumulatedText += delta
                onStatus("Streaming response…")
                let extracted = Self.splitThoughtAndVisibleText(accumulatedText)
                if !extracted.thought.isEmpty {
                    onThought(accumulatedThinking.isEmpty ? extracted.thought : accumulatedThinking + "\n" + extracted.thought)
                }
                onText(extracted.visible)
            case .toolCall(let call):
                onStatus("Running \(call.name)…")
                steps.append(CellAgentToolStep(
                    id: call.id,
                    toolName: call.name,
                    summary: call.displaySummary,
                    output: "",
                    isRunning: true,
                    isError: false,
                    startedAt: Date(),
                    durationMs: nil
                ))
                onToolSteps(steps)
            case .toolResult(let res):
                onStatus("Analyzing \(res.toolName ?? "tool") output…")
                if let idx = steps.firstIndex(where: { $0.id == res.toolCallId }) {
                    let elapsed = Int(Date().timeIntervalSince(steps[idx].startedAt) * 1000)
                    steps[idx].isRunning = false
                    steps[idx].isError = res.isError
                    steps[idx].output = res.content
                    steps[idx].durationMs = max(1, elapsed)
                } else {
                    steps.append(CellAgentToolStep(
                        id: res.toolCallId,
                        toolName: res.toolName ?? "tool",
                        summary: "",
                        output: res.content,
                        isRunning: false,
                        isError: res.isError,
                        startedAt: Date(),
                        durationMs: nil
                    ))
                }
                onToolSteps(steps)
            case .complete(let res):
                if accumulatedText.isEmpty && !res.result.isEmpty {
                    accumulatedText = res.result
                }
                let extracted = Self.splitThoughtAndVisibleText(accumulatedText)
                if !extracted.thought.isEmpty {
                    onThought(accumulatedThinking.isEmpty ? extracted.thought : accumulatedThinking + "\n" + extracted.thought)
                }
                onText(extracted.visible)
                onStatus("")
                onComplete(extracted.visible)
                return
            case .error(let err):
                onStatus("")
                onError("\(config.name): \(err)")
                return
            default:
                break
            }
        }
        onStatus("")
        let extracted = Self.splitThoughtAndVisibleText(accumulatedText)
        onComplete(extracted.visible)
    }

    // MARK: - Native Multi-Provider Agent & Ask Loop

    private func executeNativeRoute(
        sessionId: String,
        prompt: String,
        selection: CellAISelection,
        useDirectCodexOAuth: Bool,
        isAgentMode: Bool,
        role: CellSubAgentRole,
        appState: AppState,
        notebookContext: String,
        workspaceRoot: String,
        conversationHistory: [(role: String, content: String)],
        maxAgentTurns: Int,
        onStatus: @escaping @MainActor (String) -> Void,
        onThought: @escaping @MainActor (String) -> Void,
        onText: @escaping @MainActor (String) -> Void,
        onToolSteps: @escaping @MainActor ([CellAgentToolStep]) -> Void,
        onComplete: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) async {
        let keyMode = selection.effectiveKeyMode(appState: appState)
        let providerString = useDirectCodexOAuth ? "openai" : selection.effectiveProvider(appState: appState)
        let provider = StreamableAIProvider(rawValue: providerString) ?? .gemini

        let resolvedModel: String = {
            let rawModel = selection.effectiveModel(appState: appState)
            if useDirectCodexOAuth {
                let lower = rawModel.lowercased()
                if !lower.isEmpty && (lower.hasPrefix("gpt") || lower.contains("codex")) {
                    return rawModel
                }
                return AIClient.loadCodexOAuthCredentials(fallbackToken: "")?.defaultModel ?? "gpt-5.2-codex"
            }
            if !rawModel.isEmpty { return rawModel }
            return AIModelCatalog.shared.provider(providerString)?.models.first?.id ?? provider.defaultModel
        }()

        let apiKey: String = {
            if useDirectCodexOAuth { return "codex_oauth" }
            if keyMode == "local" || providerString == "local" { return "local" }
            return appState.resolveApiKey(for: providerString)
        }()

        let isDirectMediaModel = AIClient.isAiPassMediaModel(resolvedModel)

        // Assemble Notebook + Workspace + PNS-filtered MCP tools when Agent Mode is active
        let toolBox = AgentToolBox.shared
        if toolBox.workspaceRoot == nil || toolBox.workspaceRoot?.isEmpty == true {
            toolBox.workspaceRoot = workspaceRoot
        }

        let activeTools: [[String: Any]]? = {
            guard isAgentMode && !isDirectMediaModel else { return nil }
            let coreCellAndWorkspaceTools: Set<String> = [
                "cell_list", "cell_read", "cell_create", "cell_update", "cell_delete", "cell_run",
                "playground_run", "ardium_run",
                "embedded_list_hardware", "embedded_compile", "embedded_flash",
                "embedded_serial_capture", "embedded_serial_send", "embedded_decode_crash",
                "file_read", "multi_file_read", "file_write", "replace_in_file", "patch_file",
                "list_directory_tree", "file_search", "grep_search", "codebase_search",
                "shell", "web_fetch", "git_status", "get_diagnostics",
                "pns_nervous_system", "skill_engine", "mcp_orchestrator", "invoke_subagent",
                "generate_image", "generate_video", "generate_music"
            ]
            let candidateSchemas = toolBox.toolSchemas().filter { schema in
                let name = schema["name"] as? String ?? ""
                return coreCellAndWorkspaceTools.contains(name) || name.hasPrefix("mcp__")
            }
            return PNSGanglionRouter.shared.filterMCPToolsForSubAgent(
                archetype: role.rawValue,
                taskPrompt: prompt,
                workspacePath: workspaceRoot,
                allSchemas: candidateSchemas,
                maxMCPTools: 10,
                synapseLookup: { category, tract, nodeId, proj in
                    PNSOrchestrator.shared.lookupSynapse(
                        taskCategory: category,
                        tract: tract,
                        targetNodeId: nodeId,
                        projectPath: proj
                    )
                }
            )
        }()

        let systemPrompt = Self.buildSystemPrompt(
            role: role,
            isAgentMode: isAgentMode,
            workspaceRoot: workspaceRoot,
            notebookContext: notebookContext
        )

        var history = conversationHistory
        var currentPrompt = prompt
        var accumulatedThought = ""
        var accumulatedVisibleText = ""
        var toolSteps: [CellAgentToolStep] = []
        let maxIterations = isAgentMode && !isDirectMediaModel ? max(1, maxAgentTurns) : 1

        for turn in 1...maxIterations {
            if Task.isCancelled || cancelledSessions.contains(sessionId) { return }
            onStatus(turn == 1 ? (isAgentMode ? "Agent analyzing cells…" : "Generating…") : "Agent reasoning (step \(turn))…")

            let priorVisible = accumulatedVisibleText
            let priorThought = accumulatedThought

            let turnOutcome = await runSingleModelCall(
                prompt: currentPrompt,
                systemPrompt: isDirectMediaModel ? nil : systemPrompt,
                conversationHistory: isDirectMediaModel ? [] : history,
                provider: provider,
                model: resolvedModel,
                apiKey: apiKey,
                selection: selection,
                effectiveKeyMode: keyMode,
                tools: activeTools,
                onStreamUpdate: { liveRaw in
                    let cleaned = AIStructuredTurnCodec.stripToolCallArtifacts(liveRaw)
                    let split = Self.splitThoughtAndVisibleText(cleaned)
                    if !split.thought.isEmpty {
                        let mergedThought = priorThought.isEmpty ? split.thought : priorThought + "\n\n" + split.thought
                        onThought(mergedThought)
                    }
                    let mergedText: String
                    if priorVisible.isEmpty {
                        mergedText = split.visible
                    } else if split.visible.isEmpty {
                        mergedText = priorVisible
                    } else {
                        mergedText = priorVisible + "\n\n" + split.visible
                    }
                    onText(mergedText)
                }
            )

            if Task.isCancelled || cancelledSessions.contains(sessionId) { return }

            if let errorMessage = turnOutcome.error {
                onStatus("")
                onError(errorMessage)
                return
            }

            let rawTurnText = turnOutcome.text
            var toolCalls = turnOutcome.toolCalls.map { tc in
                AIToolCall(
                    id: tc.id,
                    name: AgentToolBox.normalizeToolName(tc.name),
                    arguments: AgentToolBox.normalizeToolParams(tc.arguments),
                    thoughtSignature: tc.thoughtSignature
                )
            }

            // Parse fallback XML/text tool calls for providers/local models without native function calling
            if isAgentMode {
                let universal = SubAgentHarness.shared.parseUniversalFallbackToolCalls(
                    from: rawTurnText,
                    senderRole: role.displayName,
                    senderBadge: resolvedModel
                )
                if !universal.toolCalls.isEmpty {
                    toolCalls.append(contentsOf: universal.toolCalls)
                }
                if toolCalls.isEmpty {
                    let xmlCalls = Self.parseFallbackToolCalls(from: rawTurnText)
                    if !xmlCalls.isEmpty {
                        toolCalls.append(contentsOf: xmlCalls)
                    }
                }
            }

            let strippedText = Self.stripLegacyCallTags(AIStructuredTurnCodec.stripToolCallArtifacts(rawTurnText))
            let split = Self.splitThoughtAndVisibleText(strippedText)
            if !split.thought.isEmpty {
                accumulatedThought = accumulatedThought.isEmpty ? split.thought : accumulatedThought + "\n\n" + split.thought
                onThought(accumulatedThought)
            }
            let visibleTurnText = split.visible.trimmingCharacters(in: .whitespacesAndNewlines)
            if !visibleTurnText.isEmpty {
                accumulatedVisibleText = accumulatedVisibleText.isEmpty
                    ? visibleTurnText
                    : accumulatedVisibleText + "\n\n" + visibleTurnText
                onText(accumulatedVisibleText)
            }

            // If Ask mode or no tool calls requested, we're done!
            guard isAgentMode && !toolCalls.isEmpty else {
                onStatus("")
                onComplete(accumulatedVisibleText)
                return
            }

            // Append user prompt + assistant tool-calls turn to structured history
            history.append((role: "user", content: currentPrompt))
            history.append((
                role: "assistant",
                content: AIStructuredTurnCodec.encodeAssistantTurn(text: visibleTurnText, toolCalls: toolCalls)
            ))

            // Execute each tool call inside @TaskLocal workspace isolation
            var structuredResults: [AIStructuredToolResult] = []

            for call in toolCalls {
                if Task.isCancelled || cancelledSessions.contains(sessionId) { return }
                let summary = Self.summarizeToolArgs(name: call.name, args: call.arguments)
                let stepId = call.id
                let startAt = Date()

                toolSteps.append(CellAgentToolStep(
                    id: stepId,
                    toolName: call.name,
                    summary: summary,
                    output: "",
                    isRunning: true,
                    isError: false,
                    startedAt: startAt,
                    durationMs: nil
                ))
                onToolSteps(toolSteps)
                onStatus("Executing \(call.name)…")

                let (output, isErr) = await AgentExecutionContext.$workspaceRoot.withValue(workspaceRoot) {
                    do {
                        let out = try await toolBox.execute(call.name, params: call.arguments)
                        return (out, false)
                    } catch {
                        return ("Tool error (\(call.name)): \(error.localizedDescription)", true)
                    }
                }

                let elapsedMs = max(1, Int(Date().timeIntervalSince(startAt) * 1000))
                if let idx = toolSteps.firstIndex(where: { $0.id == stepId }) {
                    toolSteps[idx].isRunning = false
                    toolSteps[idx].isError = isErr
                    toolSteps[idx].output = output
                    toolSteps[idx].durationMs = elapsedMs
                }
                onToolSteps(toolSteps)

                // Feed Hebbian signal into PNS if MCP tool was used
                if call.name.hasPrefix("mcp__") {
                    let parts = call.name.components(separatedBy: "__")
                    if parts.count >= 2 {
                        PNSGanglionRouter.shared.recordMCPImpulse(serverName: parts[1])
                    }
                }

                let boundedOut = output.count > 8000 ? String(output.prefix(8000)) + "\n... (output truncated)" : output
                structuredResults.append(AIStructuredToolResult(
                    toolCallId: call.id,
                    name: call.name,
                    output: boundedOut,
                    success: !isErr
                ))
            }

            currentPrompt = AIStructuredTurnCodec.encodeToolResultsTurn(
                results: structuredResults,
                directive: "Review the tool execution outputs above. Continue executing tools if more steps or verification are required, or provide a clear final answer summarizing what was done."
            )
        }

        onStatus("")
        onComplete(accumulatedVisibleText)
    }

    // MARK: - Single Turn Wrapper Around AIClient.shared (Respects Per-Cell KeyMode & Sub Overrides)

    private func runSingleModelCall(
        prompt: String,
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        provider: StreamableAIProvider,
        model: String,
        apiKey: String,
        selection: CellAISelection,
        effectiveKeyMode: String,
        tools: [[String: Any]]?,
        onStreamUpdate: @escaping @MainActor (String) -> Void
    ) async -> (text: String, toolCalls: [AIToolCall], error: String?) {
        await withCheckedContinuation { (continuation: CheckedContinuation<(String, [AIToolCall], String?), Never>) in
            let gate = CellStreamGate(continuation)
            var streamed = ""
            var collectedCalls: [AIToolCall] = []

            // Scope UserDefaults keyMode/subscriptionProvider & LocalLLM endpoint synchronously around AIClient dispatch
            // when a per-cell override specifies a different auth route than global AppState.
            let defaults = UserDefaults.standard
            let savedKeyMode = defaults.string(forKey: "aiKeyMode")
            let savedSubProv = defaults.string(forKey: "subscriptionActiveProvider")
            let savedLocalEndpoint = LocalLLMService.cachedEndpoint

            if !selection.useGlobal {
                defaults.set(effectiveKeyMode, forKey: "aiKeyMode")
                if !selection.subscriptionProvider.isEmpty {
                    defaults.set(selection.subscriptionProvider, forKey: "subscriptionActiveProvider")
                }
                if !selection.localEndpoint.isEmpty {
                    LocalLLMService.cachedEndpoint = selection.localEndpoint
                }
            }

            defer {
                if !selection.useGlobal {
                    if let savedKeyMode { defaults.set(savedKeyMode, forKey: "aiKeyMode") }
                    if let savedSubProv { defaults.set(savedSubProv, forKey: "subscriptionActiveProvider") }
                    LocalLLMService.cachedEndpoint = savedLocalEndpoint
                }
            }

            AIClient.shared.sendMessage(
                prompt: prompt,
                attachments: [],
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                provider: provider,
                model: model,
                apiKey: apiKey,
                tools: tools,
                onToken: { token in
                    streamed += token
                    Task { @MainActor in
                        onStreamUpdate(streamed)
                    }
                },
                onToolCall: { tc in
                    collectedCalls.append(tc)
                },
                onComplete: { full in
                    let final = full.isEmpty ? streamed : full
                    _ = gate.resumeOnce((final, collectedCalls, nil))
                },
                onError: { err in
                    _ = gate.resumeOnce((streamed, collectedCalls, err))
                }
            )
        }
    }

    // MARK: - System Prompt & Parsing Utilities

    private static func buildSystemPrompt(
        role: CellSubAgentRole,
        isAgentMode: Bool,
        workspaceRoot: String,
        notebookContext: String
    ) -> String {
        if role == .embeddedHardware {
            if isAgentMode {
                return """
                You are MicroCode Embedded & Hardware-in-the-Loop (HIL) Autonomous Agent.
                \(role.rolePrompt)

                ## Hardware-in-the-Loop (HIL) Tools (100% Real Hardware & Cross-Toolchains — Zero Mock)
                - `embedded_list_hardware`: Enumerate physical USB microcontrollers via IOKit (`VID:PID`, `/dev/cu.*`, silicon fingerprint), UF2/ST-Link bootloader volumes, mDNS LAN nodes, and BLE peripherals.
                - `embedded_compile`: Write updated firmware `code` (optional) into Embedded Studio and cross-compile for the active MCU via PlatformIO (`pio`), Arduino CLI, ESP-IDF, or MicroPython `py_compile`. Returns compiler diagnostics, Pin Electrical DRC warnings, and exact ELF Flash/SRAM bytes.
                - `embedded_flash`: Compile and flash the real firmware binary onto the connected physical microcontroller via Smart Port Arbiter.
                - `embedded_serial_capture`: Capture real live UART serial telemetry from the connected board (`duration_ms`, optional `stop_pattern`).
                - `embedded_serial_send`: Transmit a real UTF-8 command line over POSIX UART serial to the microcontroller.
                - `embedded_decode_crash`: Symbolicate ESP32 Guru Meditation `Backtrace:` or ARM Cortex-M `HardFault` addresses into exact C++ functions and `file:line` via DWARF `addr2line`.
                - Plus full Workspace & OS tools (`file_read`, `file_write`, `replace_in_file`, `shell`, `grep_search`, `mcp__*`).

                ## Autonomous HIL Engineering Rules
                1. When asked to build, fix, or verify firmware, **proactively call `embedded_compile`** (passing `code` if modifying the sketch) to verify zero compiler errors and zero critical GPIO electrical DRC conflicts!
                2. Only call `embedded_flash` when the user asks to flash/upload/run on the board or verify on physical hardware (and confirm via `embedded_list_hardware` first if port state is unknown).
                3. If a crash dump or `Guru Meditation Error` appears, call `embedded_decode_crash` to pinpoint the exact faulting source line before patching.
                4. Never use blocking `delay()` inside FreeRTOS tasks when `vTaskDelay(pdMS_TO_TICKS(...))` is appropriate, and respect boot strapping / Native USB / Flash-PSRAM pins.
                5. Respond in Thai when the user writes in Thai, and in English when the user writes in English. Be concise and technical.

                \(notebookContext)
                """
            } else {
                return """
                You are MicroCode Embedded Systems Copilot in **Ask Mode (Read-Only)**.
                \(role.rolePrompt)

                ## Rules
                1. Produce complete, production-ready firmware blocks tagged with ```cpp, ```c, or ```python so the user can 1-click Replace or Append to the Sketch.
                2. Respect pin electrical constraints, FreeRTOS task/ISR safety, and non-blocking patterns.
                3. Respond in Thai when the user writes in Thai, and in English when the user writes in English.

                \(notebookContext)
                """
            }
        }
        if isAgentMode {
            return """
            You are MicroCode Cell Mode Autonomous Agent (\(role.displayName)).
            \(role.rolePrompt)

            ## Environment & Capabilities
            - Working Directory: `\(workspaceRoot)`
            - Supported Cell Languages: Python, R, Julia, SQL, Ardium, Rust, Go, C++, Objective-C, Java, R Markdown, LaTeX, Markdown.
            - You have direct access to **Notebook Cell Tools**:
              - `cell_list`: List all cells and attached datasets in the active notebook.
              - `cell_read`: Read the full code, output, and plot paths of any cell (`cell_number` 1-based or `cell_id`).
              - `cell_create`: Create a new cell (`type`: `code`/`markdown`/`raw`, `language`, `code`, optional `after_cell_number`, optional `auto_run`: true).
              - `cell_update`: Modify an existing cell's `code`, `language`, or `tag` (`cell_number` 1-based, optional `auto_run`: true).
              - `cell_run`: Execute an existing cell in the live Notebook (`cell_number` 1-based) or run a standalone code snippet (`code` + `language`) and inspect real stdout/stderr/plots.
              - `cell_delete`: Delete a cell by `cell_number`.
            - You ALSO have full access to **Workspace & OS Tools** (`file_read`, `file_write`, `replace_in_file`, `list_directory_tree`, `grep_search`, `codebase_search`, `shell`, `web_fetch`, `pns_nervous_system`, and connected `mcp__*` tools).

            ## Execution Rules
            1. When asked to build, analyze, plot, debug, or run cells, **use `cell_create` / `cell_update` / `cell_run` proactively** and verify the real execution output!
            2. If a cell execution fails with a traceback, inspect the error, fix the cell with `cell_update`, and re-run with `cell_run` until it succeeds.
            3. Never overwrite unrelated user cells unless asked to edit that specific cell; prefer `cell_create` to add new pipeline steps cleanly.
            4. Respond in Thai when the user writes in Thai, and in English when the user writes in English. Keep summaries concise and technical.

            \(notebookContext)
            """
        } else {
            return """
            You are MicroCode Cell Mode AI Assistant (\(role.displayName)) in **Ask Mode (Read-Only)**.
            \(role.rolePrompt)

            ## Rules
            1. You see all cells, languages, datasets, and outputs in the current notebook below.
            2. Wrap runnable code inside fenced markdown blocks with the exact language tag (e.g. ```python, ```r, ```sql, ```rust, ```go, ```cpp, ```ardium, ```latex) so the user can 1-click Insert or Apply it to a cell.
            3. Specify which cell number a fix applies to when debugging errors.
            4. Respond in Thai when the user writes in Thai, and in English when the user writes in English. Be concise and direct.

            \(notebookContext)
            """
        }
    }

    static func splitThoughtAndVisibleText(_ raw: String) -> (thought: String, visible: String) {
        var text = raw
        var thoughts: [String] = []

        // Closed <thought>...</thought> or <think>...</think>
        let closedPattern = #"<(?:thought|think)>([\s\S]*?)</(?:thought|think)>"#
        if let regex = try? NSRegularExpression(pattern: closedPattern, options: [.caseInsensitive]) {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for m in matches where m.numberOfRanges > 1 {
                let inner = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !inner.isEmpty { thoughts.append(inner) }
            }
            text = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }

        // Unclosed streaming <thought>... or <think>... at end
        if let openRange = text.range(of: #"<(?:thought|think)>"#, options: [.regularExpression, .caseInsensitive]) {
            let trailing = String(text[openRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trailing.isEmpty { thoughts.append(trailing) }
            text = String(text[..<openRange.lowerBound])
        }

        return (thoughts.joined(separator: "\n\n"), text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func stripLegacyCallTags(_ text: String) -> String {
        guard text.contains("<call:") else { return text }
        return text.replacingOccurrences(
            of: #"<call:[a-zA-Z0-9_]+>[\s\S]*?</call:[a-zA-Z0-9_]+>"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func parseFallbackToolCalls(from text: String) -> [AIToolCall] {
        var calls: [AIToolCall] = []

        // 1. <tool_call>{"name": "...", "arguments": {...}}</tool_call>
        let tcPattern = #"<tool_call>\s*(\{[\s\S]*?\})\s*</tool_call>"#
        if let regex = try? NSRegularExpression(pattern: tcPattern) {
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let jsonStr = ns.substring(with: match.range(at: 1))
                if let data = jsonStr.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let name = obj["name"] as? String {
                    let args = (obj["arguments"] as? [String: Any]) ?? (obj["params"] as? [String: Any]) ?? [:]
                    calls.append(AIToolCall(
                        id: "tc_\(UUID().uuidString.prefix(8))",
                        name: AgentToolBox.normalizeToolName(name),
                        arguments: AgentToolBox.normalizeToolParams(args)
                    ))
                }
            }
        }

        // 2. Legacy <call:tool_name>{...}</call:tool_name>
        let legacyPattern = #"<call:([a-zA-Z0-9_]+)>\s*(\{[\s\S]*?\})\s*</call:\1>"#
        if let regex = try? NSRegularExpression(pattern: legacyPattern) {
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let rawName = ns.substring(with: match.range(at: 1))
                let jsonStr = ns.substring(with: match.range(at: 2))
                if let data = jsonStr.data(using: .utf8),
                   let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    calls.append(AIToolCall(
                        id: "tc_\(UUID().uuidString.prefix(8))",
                        name: AgentToolBox.normalizeToolName(rawName),
                        arguments: AgentToolBox.normalizeToolParams(args)
                    ))
                }
            }
        }
        return calls
    }

    private static func summarizeToolArgs(name: String, args: [String: Any]) -> String {
        if name.hasPrefix("embedded_") {
            if let port = args["port"] as? String { return port }
            if let cmd = args["command"] as? String { return String(cmd.prefix(40)) }
            if let dur = args["duration_ms"] { return "\(dur)ms" }
            if args["code"] != nil { return "updated sketch" }
            return ""
        }
        if let num = args["cell_number"] {
            if let lang = args["language"] as? String {
                return "Cell #\(num) (\(lang))"
            }
            return "Cell #\(num)"
        }
        if let lang = args["language"] as? String, name.hasPrefix("cell_") || name == "playground_run" {
            return lang
        }
        if let path = args["path"] as? String {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let cmd = args["command"] as? String {
            return String(cmd.prefix(48))
        }
        if let query = args["query"] as? String {
            return String(query.prefix(40))
        }
        return ""
    }
}

// MARK: - AppKit Prompt Composer (Enter = Send, Shift+Enter = Newline, IME-Safe, Click-Selects Cell)

final class CellPromptNSTextView: NSTextView {
    var placeholderText: String = "" {
        didSet {
            if oldValue != placeholderText {
                needsDisplay = true
            }
        }
    }
    var placeholderColor: NSColor = .placeholderTextColor
    var onSubmitAction: (() -> Void)?
    var onFocusChanged: ((Bool) -> Void)?
    var onHeightRecalcRequested: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        onFocusChanged?(true)
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChanged?(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocusChanged?(false) }
        return ok
    }

    override func keyDown(with event: NSEvent) {
        // Respect active Thai / CJK IME composition
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        // Return (36) or Numpad Enter (76)
        if event.keyCode == 36 || event.keyCode == 76 {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.shift) {
                super.insertNewline(nil)
                onHeightRecalcRequested?()
                return
            } else {
                onSubmitAction?()
                return
            }
        }

        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
        onHeightRecalcRequested?()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.size.width
        super.setFrameSize(newSize)
        if abs(oldWidth - newSize.width) > 0.5 {
            onHeightRecalcRequested?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderText.isEmpty else { return }

        let inset = textContainerInset
        let pad = textContainer?.lineFragmentPadding ?? 4
        let rect = NSRect(
            x: inset.width + pad,
            y: inset.height,
            width: max(20, bounds.width - (inset.width + pad) * 2),
            height: max(18, bounds.height - inset.height * 2)
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 12.5),
            .foregroundColor: placeholderColor,
            .paragraphStyle: paragraph
        ]
        (placeholderText as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
    }
}

struct CellPromptInputView: View {
    @Binding var text: String
    var placeholder: String
    var isDark: Bool
    var minHeight: CGFloat = 28
    var maxHeight: CGFloat = 132
    var fontSize: CGFloat = 12.5
    var onFocus: ((Bool) -> Void)? = nil
    var onSubmit: () -> Void

    @State private var measuredHeight: CGFloat = 28

    var body: some View {
        CellPromptRepresentable(
            text: $text,
            measuredHeight: $measuredHeight,
            placeholder: placeholder,
            isDark: isDark,
            minHeight: minHeight,
            maxHeight: maxHeight,
            fontSize: fontSize,
            onFocus: onFocus,
            onSubmit: onSubmit
        )
        .frame(height: min(max(measuredHeight, minHeight), maxHeight))
    }
}

private struct CellPromptRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    var placeholder: String
    var isDark: Bool
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var fontSize: CGFloat
    var onFocus: ((Bool) -> Void)?
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 240, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 3
        layoutManager.addTextContainer(textContainer)

        let textView = CellPromptNSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: minHeight), textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.delegate = context.coordinator

        let fg = isDark ? NSColor(white: 0.94, alpha: 1.0) : NSColor(white: 0.10, alpha: 1.0)
        textView.textColor = fg
        textView.insertionPointColor = fg
        textView.placeholderColor = isDark ? NSColor(white: 0.52, alpha: 1.0) : NSColor(white: 0.48, alpha: 1.0)
        textView.placeholderText = placeholder
        textView.string = text

        let coord = context.coordinator
        textView.onSubmitAction = { [weak coord] in
            coord?.parent.onSubmit()
        }
        textView.onFocusChanged = { [weak coord] focused in
            coord?.parent.onFocus?(focused)
        }
        textView.onHeightRecalcRequested = { [weak coord, weak textView] in
            guard let coord, let textView else { return }
            coord.recalculateHeight(for: textView)
        }

        scrollView.documentView = textView
        DispatchQueue.main.async {
            context.coordinator.recalculateHeight(for: textView)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? CellPromptNSTextView else { return }

        let fg = isDark ? NSColor(white: 0.94, alpha: 1.0) : NSColor(white: 0.10, alpha: 1.0)
        if textView.textColor != fg {
            textView.textColor = fg
            textView.insertionPointColor = fg
        }
        textView.placeholderColor = isDark ? NSColor(white: 0.52, alpha: 1.0) : NSColor(white: 0.48, alpha: 1.0)
        if textView.placeholderText != placeholder {
            textView.placeholderText = placeholder
        }

        if textView.string != text && !textView.hasMarkedText() {
            context.coordinator.isProgrammaticUpdate = true
            textView.string = text
            context.coordinator.isProgrammaticUpdate = false
            textView.needsDisplay = true
            context.coordinator.recalculateHeight(for: textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CellPromptRepresentable
        var isProgrammaticUpdate = false

        init(_ parent: CellPromptRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate,
                  let tv = notification.object as? CellPromptNSTextView else { return }
            if parent.text != tv.string {
                parent.text = tv.string
            }
            recalculateHeight(for: tv)
        }

        func recalculateHeight(for textView: NSTextView) {
            guard let lm = textView.layoutManager,
                  let tc = textView.textContainer else { return }
            lm.ensureLayout(for: tc)
            let used = lm.usedRect(for: tc).height
            let rawHeight: CGFloat
            if textView.string.isEmpty {
                // Account for multi-line placeholder gracefully if narrow
                rawHeight = max(parent.minHeight, 30)
            } else {
                rawHeight = used + textView.textContainerInset.height * 2 + 4
            }
            let clamped = min(max(ceil(rawHeight), parent.minHeight), parent.maxHeight)
            if abs(parent.measuredHeight - clamped) > 0.5 {
                DispatchQueue.main.async {
                    self.parent.measuredHeight = clamped
                }
            }
        }
    }
}
