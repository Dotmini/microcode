import Foundation
import SwiftUI

// MARK: - Inline SubAgent Card (Single agent in chat stream)

struct InlineSubAgentCard: View {
    let subagent: SubAgentInstance
    var onTap: (() -> Void)? = nil
    
    @State private var isPulsing = false
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 8) {
                // Status icon with pulse for running state
                ZStack {
                    if subagent.state == .running {
                        Circle()
                            .fill(Color.primary.opacity(0.1))
                            .frame(width: 20, height: 20)
                            .scaleEffect(isPulsing ? 1.3 : 1.0)
                            .opacity(isPulsing ? 0 : 0.5)
                            .animation(
                                Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: false),
                                value: isPulsing
                            )
                    }
                    
                    Image(systemName: subagent.state.statusIcon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(subagent.state == .running ? .primary : subagent.state.statusColor)
                }
                .frame(width: 20, height: 20)
                
                // Role text + Endpoint Badge
                Text(subagent.role)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let badge = subagent.endpointBadge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Status detail or spinner
                if subagent.state == .running {
                    HStack(spacing: 4) {
                        if let tool = subagent.currentToolExecution {
                            Text(tool)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                    }
                } else if subagent.state == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.5))
                } else if subagent.state == .errored {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 9))
                        .foregroundColor(.primary.opacity(0.5))
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            if subagent.state == .running {
                isPulsing = true
            }
        }
        .onChange(of: subagent.state) { newState in
            isPulsing = (newState == .running)
        }
    }
}

// MARK: - SubAgent Cluster View (Collapsible group for multiple subagents)

struct SubAgentClusterView: View {
    let subagents: [SubAgentInstance]
    var onSelectSubagent: ((SubAgentInstance) -> Void)? = nil
    var onShowAll: (() -> Void)? = nil
    
    @State private var isExpanded = false
    
    private var runningCount: Int {
        subagents.filter { $0.state == .running }.count
    }
    
    private var completedCount: Int {
        subagents.filter { $0.state == .completed }.count
    }
    
    private let maxVisible = 8
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    // Green dot indicator if any running
                    if runningCount > 0 {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 5, height: 5)
                    } else {
                        Circle()
                            .fill(Color.primary.opacity(0.3))
                            .frame(width: 5, height: 5)
                    }
                    
                    // Count text
                    if runningCount > 0 {
                        Text("\(runningCount) subagent\(runningCount == 1 ? "" : "s") running")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                    } else {
                        Text("\(subagents.count) subagent\(subagents.count == 1 ? "" : "s") — \(completedCount) done")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            // Expanded list
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(Array(subagents.prefix(maxVisible))) { sub in
                        SubAgentClusterRow(subagent: sub)
                            .onTapGesture { onSelectSubagent?(sub) }
                    }
                    
                    if subagents.count > maxVisible {
                        Button(action: { onShowAll?() }) {
                            Text("See all (\(subagents.count))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.primary.opacity(0.6))
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - SubAgent Cluster Row (Mini card inside cluster)

struct SubAgentClusterRow: View {
    let subagent: SubAgentInstance
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: subagent.state.statusIcon)
                .font(.system(size: 9))
                .foregroundColor(subagent.state == .running ? .primary : subagent.state.statusColor)
                .frame(width: 14)
            
            Text(subagent.role)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            if let badge = subagent.endpointBadge, !badge.isEmpty {
                Text(badge)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundColor(.accentColor.opacity(0.9))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.08))
                    .cornerRadius(3)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if subagent.state == .running {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
            } else {
                Text(subagent.state.displayName)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(5)
    }
}

// MARK: - Plan Approval Inline Card (In chat stream)

struct PlanApprovalInlineCard: View {
    @ObservedObject var planManager = ImplementationPlanManager.shared
    @EnvironmentObject var appState: AppState
    var onViewPlan: (() -> Void)? = nil
    @State private var isExpanded: Bool = false
    
    private var cardBackground: Color {
        Color(nsColor: appState.appTheme.panelBackground)
    }
    
    private func cleanedPlanTitle(_ rawTitle: String) -> String {
        var cleaned = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["Implementation Plan:", "Implementation Plan -", "Implementation Plan —", "Implementation Plan"]
        for prefix in prefixes {
            if cleaned.lowercased().hasPrefix(prefix.lowercased()) {
                cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return cleaned
    }
    
    var body: some View {
        if let plan = planManager.currentPlan {
            let cleanTitle = cleanedPlanTitle(plan.title)
            VStack(alignment: .leading, spacing: 5) {
                // Header Row (Compact, Single-Line Formal IDE Header)
                HStack(spacing: 6) {
                    Image(systemName: plan.approvalState == .approved ? "checkmark.circle.fill" : "doc.text")
                        .font(.system(size: 11))
                        .foregroundColor(plan.approvalState == .approved ? .green.opacity(0.85) : .secondary)
                    
                    Text("Implementation Plan")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .fixedSize()
                    
                    if !cleanTitle.isEmpty {
                        Text("— \(cleanTitle)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 6)
                    
                    // Subtle Status Indicator (Minimal Dot + Text)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(
                                plan.approvalState == .approved ? Color.green.opacity(0.85) :
                                (plan.approvalState == .rejected ? Color.red.opacity(0.85) : Color.orange.opacity(0.85))
                            )
                            .frame(width: 5, height: 5)
                        
                        Text(plan.approvalState == .approved ? "Approved" : (plan.approvalState == .rejected ? "Rejected" : "Review required"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .fixedSize()
                    
                    if plan.totalSteps > 0 {
                        Text("• \(plan.totalSteps) steps")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary.opacity(0.7))
                            .fixedSize()
                    }
                    
                    if let onView = onViewPlan {
                        Button(action: onView) {
                            HStack(spacing: 3) {
                                Image(systemName: "sidebar.trailing")
                                    .font(.system(size: 9.5))
                                Text("Inspect")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help("Inspect plan in side panel")
                    }
                    
                    Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Collapse plan steps" : "Expand plan steps")
                    
                    if plan.approvalState != .pending {
                        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { planManager.clearPlan() } }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.7))
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .help("Dismiss plan banner")
                    }
                }
                
                // Pending Review Action Row (Shown strictly when awaiting review)
                if plan.approvalState == .pending {
                    HStack(spacing: 8) {
                        if !plan.summary.isEmpty {
                            Text(plan.summary)
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Button(action: { planManager.reject() }) {
                            Text("Reject")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { planManager.approve() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Approve")
                                    .font(.system(size: 10.5, weight: .medium))
                                Text("⌘↵")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3.5)
                            .background(Color.primary.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                    .padding(.top, 2)
                }
                
                // Expanded Step Preview (Compact & Clean)
                if isExpanded && !plan.sections.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(plan.sections.prefix(3)) { section in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title.uppercased())
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.8))
                                
                                ForEach(section.steps.prefix(4)) { step in
                                    HStack(alignment: .center, spacing: 5) {
                                        if let action = step.action {
                                            Text(action)
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal, 3)
                                                .padding(.vertical, 1)
                                                .background(Color.primary.opacity(0.06))
                                                .cornerRadius(2)
                                        } else {
                                            Circle()
                                                .fill(Color.secondary.opacity(0.5))
                                                .frame(width: 3.5, height: 3.5)
                                        }
                                        
                                        Text(step.description)
                                            .font(.system(size: 10))
                                            .foregroundColor(.primary.opacity(0.8))
                                            .lineLimit(1)
                                    }
                                    .padding(.leading, 2)
                                }
                            }
                        }
                    }
                    .padding(6)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(4)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(cardBackground)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .frame(maxWidth: 880)
        }
    }
}

// MARK: - CEO & Specialist Squad Live Boardroom Inline Card

struct CEOSquadBoardroomInlineView: View {
    @ObservedObject var harness = SubAgentHarness.shared
    @State private var isExpanded: Bool = true
    
    private var approvedCount: Int {
        harness.activeContracts.filter { $0.status == .approved }.count
    }
    
    var body: some View {
        if !harness.interAgentDialogue.isEmpty || !harness.activeContracts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // Executive Boardroom Header
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                    
                    Text(harness.activeSquadPreset?.name ?? "CEO & Specialist Squad")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if !harness.activeContracts.isEmpty {
                        Text("\(approvedCount)/\(harness.activeContracts.count) Verified")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(approvedCount == harness.activeContracts.count ? .green : .orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((approvedCount == harness.activeContracts.count ? Color.green : Color.orange).opacity(0.12))
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    Button {
                        harness.showSquadBuilderSheet = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 9))
                            Text("Squad Preset")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        harness.clearDialogueAndContracts()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss Boardroom feed")
                }
                
                if isExpanded {
                    // Active Task Contracts Strip
                    if !harness.activeContracts.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(harness.activeContracts) { contract in
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(contractStatusColor(contract.status))
                                            .frame(width: 6, height: 6)
                                        Text(contract.role)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text("• \(contract.status.rawValue)")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(contractStatusColor(contract.status))
                                            .lineLimit(1)
                                        if !contract.ownedPaths.isEmpty {
                                            Text("🔒 \(contract.ownedPaths.first ?? "")")
                                                .font(.system(size: 8.5, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.04))
                                    .cornerRadius(5)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(contractStatusColor(contract.status).opacity(0.25), lineWidth: 0.5)
                                    )
                                }
                            }
                        }
                    }
                    
                    // Live Inter-Agent Dialogue Stream (CEO <-> Subordinates)
                    if !harness.interAgentDialogue.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(harness.interAgentDialogue.suffix(8)) { msg in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(kindIcon(msg.kind))
                                        .font(.system(size: 10))
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text(msg.senderRole)
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.primary)
                                            Text("[\(msg.senderBadge)]")
                                                .font(.system(size: 8.5, design: .monospaced))
                                                .foregroundColor(.accentColor)
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 7.5, weight: .bold))
                                                .foregroundColor(.secondary)
                                            Text(msg.recipientRole)
                                                .font(.system(size: 9.5, weight: .semibold))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(msg.kind.rawValue)
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundColor(kindColor(msg.kind))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(kindColor(msg.kind).opacity(0.12))
                                                .cornerRadius(3)
                                        }
                                        
                                        Text(msg.content)
                                            .font(.system(size: 10))
                                            .foregroundColor(.primary.opacity(0.88))
                                            .lineLimit(3)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.025))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.22), lineWidth: 0.8)
            )
        }
    }
    
    private func contractStatusColor(_ status: SubAgentTaskContract.ContractStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .inProgress: return .blue
        case .underReview: return .orange
        case .revisionNeeded: return .red
        case .approved: return .green
        case .failed: return .red
        }
    }
    
    private func kindIcon(_ kind: InterAgentMessage.MessageKind) -> String {
        switch kind {
        case .briefing: return "📋"
        case .delegation: return "👉"
        case .peerSync: return "💬"
        case .verificationPassed: return "🧪"
        case .revisionRequested: return "🔄"
        case .approved: return "✅"
        }
    }
    
    private func kindColor(_ kind: InterAgentMessage.MessageKind) -> Color {
        switch kind {
        case .briefing: return .purple
        case .delegation: return .blue
        case .peerSync: return .cyan
        case .verificationPassed: return .teal
        case .revisionRequested: return .orange
        case .approved: return .green
        }
    }
}

// MARK: - Custom Agent Squad Preset Builder Sheet

struct AgentSquadBuilderSheet: View {
    @ObservedObject var harness = SubAgentHarness.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPresetId: String = ""
    @State private var draftPreset: AgentSquadPreset = AgentSquadPreset.builtInPresets[0]
    
    private let providerOptions: [(id: String, label: String)] = [
        ("anthropic", "Anthropic (Claude)"),
        ("gemini", "Google (Gemini)"),
        ("openai", "OpenAI (ChatGPT / Codex)"),
        ("deepseek", "DeepSeek"),
        ("glm", "Z.ai (GLM)"),
        ("qwen", "Alibaba (Qwen)"),
        ("kimi", "Moonshot (Kimi)"),
        ("openrouter", "OpenRouter"),
        ("groq", "Groq"),
        ("aipass", "TH-AI Passport (AiPass)"),
        ("omni", "Dotmini Omni Cloud"),
        ("local", "Local (Ollama / Omni)"),
        ("inherit", "Inherit Active Global Model")
    ]
    
    private let quickModelsByProvider: [String: [String]] = [
        "anthropic": ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5"],
        "gemini": ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-3.1-pro-preview"],
        "openai": ["gpt-4.1", "gpt-4.1-mini", "o3", "o4-mini"],
        "deepseek": ["deepseek-chat", "deepseek-reasoner"],
        "glm": ["glm-4.5", "glm-4.5-air"],
        "qwen": ["qwen-max", "qwen-plus", "qwen2.5-coder-32b-instruct"],
        "kimi": ["kimi-k2-0711-preview"],
        "aipass": ["claude-sonnet-4-6", "gemini-2.5-pro", "gpt-4.1", "deepseek-chat"],
        "omni": ["gemini-2.5-flash", "claude-sonnet-4-6"],
        "local": ["qwen2.5-coder:14b", "deepseek-r1:14b", "llama3.3"]
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Bar
            HStack {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("CEO & Specialist Squad Preset Builder")
                        .font(.system(size: 13.5, weight: .bold))
                    Text("ผสมโมเดลข้ามค่าย (Claude + Gemini + ChatGPT + DeepSeek) ใช้ได้ทั้ง Sub, BYOK, AGY/ACP, Dotmini Cloud")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(14)
            
            Divider()
            
            HStack(alignment: .top, spacing: 0) {
                // Left Sidebar: Preset List
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("SQUAD PRESETS")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            let newPreset = AgentSquadPreset(
                                id: "custom_\(UUID().uuidString.prefix(8))",
                                name: "My Custom Squad",
                                subtitle: "Custom CEO + Specialist SubAgent Team",
                                icon: "person.3.fill",
                                isBuiltIn: false,
                                ceoEndpoint: AgentModelEndpoint(authSource: .auto, provider: "anthropic", model: "claude-sonnet-4-6"),
                                subordinates: AgentSquadPreset.builtInPresets[0].subordinates
                            )
                            harness.saveCustomSquadPreset(newPreset)
                            selectPreset(newPreset)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                Text("New")
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(harness.squadPresets) { preset in
                                let isSelected = draftPreset.id == preset.id
                                let isActive = harness.activeSquadPresetId == preset.id
                                Button {
                                    selectPreset(preset)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Image(systemName: preset.icon)
                                                .font(.system(size: 10.5))
                                                .foregroundColor(isActive ? .orange : .secondary)
                                            Text(preset.name)
                                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            Spacer()
                                            if isActive {
                                                Text("ACTIVE")
                                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.green)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.green.opacity(0.14))
                                                    .cornerRadius(3)
                                            }
                                        }
                                        Text(preset.subtitle)
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                    }
                }
                .frame(width: 235)
                .background(Color.primary.opacity(0.02))
                
                Divider()
                
                // Right Editor Pane
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Preset Identity
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Preset Name")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                TextField("Squad Name", text: $draftPreset.name)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Description")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                TextField("Description", text: $draftPreset.subtitle)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5))
                            }
                        }
                        
                        // CEO Configuration Box
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "crown.fill")
                                    .foregroundColor(.orange)
                                Text("👔 CEO Executive Orchestrator (คนวางแผน สั่งงาน และตรวจรับงาน)")
                                    .font(.system(size: 11.5, weight: .bold))
                                Spacer()
                                Text(draftPreset.ceoEndpoint.badgeLabel)
                                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12))
                                    .cornerRadius(4)
                            }
                            
                            endpointEditorRow(endpoint: $draftPreset.ceoEndpoint)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.25), lineWidth: 0.8)
                        )
                        
                        // Subordinate Specialists Section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("🛠️ SUBORDINATE SPECIALISTS (ทีมลูกน้องเฉพาะทาง)")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Menu {
                                    ForEach(Array(harness.registeredDefinitions.values.sorted(by: { $0.name < $1.name }))) { def in
                                        Button("+ Add \(def.role) (\(def.name))") {
                                            draftPreset.subordinates.append(
                                                AgentSquadMemberSpec(
                                                    typeName: def.name,
                                                    roleTitle: def.role,
                                                    endpoint: AgentModelEndpoint(authSource: .auto, provider: "gemini", model: "gemini-2.5-flash"),
                                                    isEnabled: true
                                                )
                                            )
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Add Specialist")
                                    }
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.accentColor)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                            
                            ForEach($draftPreset.subordinates) { $member in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Toggle("", isOn: $member.isEnabled)
                                            .labelsHidden()
                                            .controlSize(.mini)
                                        Text(member.roleTitle)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text("(\(member.typeName))")
                                            .font(.system(size: 9.5, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(member.endpoint.badgeLabel)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.accentColor)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(Color.accentColor.opacity(0.1))
                                            .cornerRadius(4)
                                        Button {
                                            draftPreset.subordinates.removeAll { $0.id == member.id }
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.red.opacity(0.75))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    if member.isEnabled {
                                        endpointEditorRow(endpoint: $member.endpoint)
                                    }
                                }
                                .padding(9)
                                .background(Color.primary.opacity(0.03))
                                .cornerRadius(7)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
                                )
                            }
                        }
                        
                        // Verification & Guardrails
                        HStack(spacing: 16) {
                            Toggle("Strict Verification Gate (ห้ามผิดพลาด — บังคับตรวจผลรันจริงก่อนอนุมัติ)", isOn: $draftPreset.strictVerificationGate)
                                .font(.system(size: 10.5, weight: .medium))
                                .controlSize(.small)
                            Spacer()
                            Stepper("Max CEO Revision Rounds: \(draftPreset.maxRevisionRounds)", value: $draftPreset.maxRevisionRounds, in: 0...3)
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.025))
                        .cornerRadius(6)
                    }
                    .padding(14)
                }
            }
            
            Divider()
            
            // Bottom Action Bar
            HStack {
                if !draftPreset.isBuiltIn {
                    Button(role: .destructive) {
                        harness.deleteCustomSquadPreset(id: draftPreset.id)
                        if let first = harness.squadPresets.first {
                            selectPreset(first)
                        }
                    } label: {
                        Text("Delete Preset")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Button {
                    var toSave = draftPreset
                    if toSave.isBuiltIn {
                        // Save customized copy if modifying a built-in preset
                        toSave.id = "custom_\(UUID().uuidString.prefix(6))"
                        toSave.isBuiltIn = false
                        if !toSave.name.hasSuffix(" (Custom)") {
                            toSave.name += " (Custom)"
                        }
                    }
                    harness.saveCustomSquadPreset(toSave)
                    dismiss()
                } label: {
                    Text("Save & Activate Squad")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button {
                    harness.activeSquadPresetId = draftPreset.id
                    dismiss()
                } label: {
                    Text("Activate Preset")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.1))
                        .foregroundColor(.primary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 760, height: 540)
        .onAppear {
            if let active = harness.activeSquadPreset {
                selectPreset(active)
            } else if let first = harness.squadPresets.first {
                selectPreset(first)
            }
        }
    }
    
    private func selectPreset(_ preset: AgentSquadPreset) {
        selectedPresetId = preset.id
        draftPreset = preset
    }
    
    @ViewBuilder
    private func endpointEditorRow(endpoint: Binding<AgentModelEndpoint>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                // Auth Source Picker
                Picker("Auth", selection: endpoint.authSource) {
                    ForEach(AgentAuthSource.allCases) { auth in
                        Text(auth.displayName).tag(auth)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 195)
                
                // Provider Picker
                Picker("Provider", selection: endpoint.provider) {
                    ForEach(providerOptions, id: \.id) { opt in
                        Text(opt.label).tag(opt.id)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 175)
                
                // Model ID TextField + Quick Menu
                TextField("Model ID (e.g. claude-sonnet-4-6)", text: endpoint.model)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .font(.system(size: 10.5, design: .monospaced))
                
                if let suggestions = quickModelsByProvider[endpoint.wrappedValue.provider], !suggestions.isEmpty {
                    Menu {
                        ForEach(suggestions, id: \.self) { m in
                            Button(m) {
                                endpoint.wrappedValue.model = m
                            }
                        }
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .padding(4)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Pick popular model for \(endpoint.wrappedValue.provider)")
                }
            }
        }
    }
}
