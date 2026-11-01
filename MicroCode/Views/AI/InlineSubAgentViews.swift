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
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.05))
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
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.05))
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
                // Header Row (Compact, Responsive Formal IDE Header)
                HStack(spacing: 6) {
                    Image(systemName: plan.approvalState == .approved ? "checkmark.circle" : "doc.text")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("Implementation Plan")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .layoutPriority(2)
                    
                    if !cleanTitle.isEmpty {
                        Text("— \(cleanTitle)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    
                    Spacer(minLength: 4)
                    
                    // Subtle Status Indicator (Minimal Monochrome Dot + Text)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(
                                plan.approvalState == .approved ? Color.primary.opacity(0.75) :
                                (plan.approvalState == .rejected ? Color.red.opacity(0.75) : Color.secondary.opacity(0.65))
                            )
                            .frame(width: 5, height: 5)
                        
                        Text(plan.approvalState == .approved ? "Approved" : (plan.approvalState == .rejected ? "Rejected" : "Review"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .layoutPriority(1)
                    
                    if plan.totalSteps > 0 {
                        Text("• \(plan.totalSteps) steps")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary.opacity(0.7))
                            .lineLimit(1)
                    }
                    
                    if let onView = onViewPlan {
                        Button(action: onView) {
                            HStack(spacing: 3) {
                                Image(systemName: "sidebar.trailing")
                                    .font(.system(size: 9.5))
                                Text("Inspect")
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .layoutPriority(3)
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

// MARK: - Multi-Agent Team Orchestration Inline Card (AGY / Cursor Formal Design)

struct CEOSquadBoardroomInlineView: View {
    @ObservedObject var harness = SubAgentHarness.shared
    @State private var isExpanded: Bool = true
    
    private var approvedCount: Int {
        harness.activeContracts.filter { $0.status == .approved }.count
    }
    
    var body: some View {
        if !harness.interAgentDialogue.isEmpty || !harness.activeContracts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // Formal IDE Orchestration Header (Monochrome, Zero Crown / Neon Colors)
                HStack(spacing: 7) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text(cleanFormalText(harness.activeSquadPreset?.name ?? "Agent Team"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if !harness.activeContracts.isEmpty {
                        Text("\(approvedCount)/\(harness.activeContracts.count) verified")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                    }
                    
                    Spacer()
                    
                    Button {
                        harness.showSquadBuilderSheet = true
                    } label: {
                        HStack(spacing: 3.5) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 9))
                            Text("Configure")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        harness.clearDialogueAndContracts()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss team activity")
                }
                
                if isExpanded {
                    // Active Task Contracts Strip (Clean Monochrome Pills)
                    if !harness.activeContracts.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(harness.activeContracts) { contract in
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(contractDotColor(contract.status))
                                            .frame(width: 5, height: 5)
                                        Text(cleanFormalText(contract.role))
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text("· \(contract.status.displayLabel)")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                        if let firstPath = contract.ownedPaths.first, !firstPath.isEmpty {
                                            HStack(spacing: 2.5) {
                                                Image(systemName: "lock")
                                                    .font(.system(size: 7.5, weight: .medium))
                                                Text(firstPath)
                                                    .font(.system(size: 8.5, design: .monospaced))
                                            }
                                            .foregroundColor(.secondary.opacity(0.7))
                                            .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.035))
                                    .cornerRadius(5)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                    )
                                }
                            }
                        }
                    }
                    
                    // Live Inter-Agent Activity Stream (Formal Monochrome Rows)
                    if !harness.interAgentDialogue.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(harness.interAgentDialogue.suffix(8)) { msg in
                                HStack(alignment: .top, spacing: 7) {
                                    Image(systemName: kindSymbol(msg.kind))
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .frame(width: 12, height: 14)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text(cleanFormalRole(msg.senderRole))
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.primary)
                                            if !msg.senderBadge.isEmpty {
                                                Text(msg.senderBadge)
                                                    .font(.system(size: 8.5, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 0.5)
                                                    .background(Color.primary.opacity(0.04))
                                                    .cornerRadius(3)
                                            }
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 7, weight: .semibold))
                                                .foregroundColor(.secondary.opacity(0.7))
                                            Text(cleanFormalRole(msg.recipientRole))
                                                .font(.system(size: 9.5, weight: .regular))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(msg.kind.displayLabel)
                                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.primary.opacity(0.05))
                                                .cornerRadius(3)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 3)
                                                        .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
                                                )
                                        }
                                        
                                        Text(cleanFormalText(msg.content))
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .lineLimit(3)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.02))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
                                )
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.025))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    private func contractDotColor(_ status: SubAgentTaskContract.ContractStatus) -> Color {
        switch status {
        case .inProgress, .underReview:
            return Color.primary.opacity(0.85)
        case .approved:
            return Color.primary.opacity(0.55)
        case .failed:
            return Color.red.opacity(0.75)
        case .pending, .revisionNeeded:
            return Color.secondary.opacity(0.45)
        }
    }
    
    private func kindSymbol(_ kind: InterAgentMessage.MessageKind) -> String {
        switch kind {
        case .briefing: return "list.bullet.rectangle"
        case .delegation: return "arrow.turn.down.right"
        case .peerSync: return "arrow.left.arrow.right"
        case .verificationPassed: return "checkmark"
        case .revisionRequested: return "arrow.clockwise"
        case .approved: return "checkmark.circle"
        }
    }
    
    private func cleanFormalRole(_ raw: String) -> String {
        var cleaned = cleanFormalText(raw)
        if cleaned == "CEO" {
            return "Lead"
        }
        cleaned = cleaned.replacingOccurrences(of: "CEO (", with: "Lead (")
        cleaned = cleaned.replacingOccurrences(of: "CEO & Specialist Squad", with: "Agent Team")
        return cleaned
    }
    
    private func cleanFormalText(_ raw: String) -> String {
        let strippedTokens = ["👑", "👔", "✅", "👉", "🧪", "🔄", "📋", "🚀", "🔍", "🛠️", "🔒"]
        var out = raw
        for tok in strippedTokens {
            out = out.replacingOccurrences(of: tok, with: "")
        }
        out = out.replacingOccurrences(of: "CEO & Specialist Squad", with: "Agent Team")
        out = out.replacingOccurrences(of: "Claude CEO", with: "Claude")
        out = out.replacingOccurrences(of: "ChatGPT CEO", with: "ChatGPT")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
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
        "omni": ["omni-o1x-pro", "omni-o1x-lite"],
        "local": ["qwen2.5-coder:14b", "deepseek-r1:14b", "llama3.3"]
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Bar
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Multi-Agent Team Preset Builder")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Configure cross-provider orchestrator & specialist subagents (Subscription, BYOK, ACP, Local)")
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
                        Text("TEAM PRESETS")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            let newPreset = AgentSquadPreset(
                                id: "custom_\(UUID().uuidString.prefix(8))",
                                name: "Custom Agent Team",
                                subtitle: "Lead Orchestrator + Specialist Subagents",
                                icon: "square.stack.3d.up",
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
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.primary)
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
                                let safeIcon = preset.icon == "crown.fill" ? "square.stack.3d.up" : preset.icon
                                Button {
                                    selectPreset(preset)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Image(systemName: safeIcon)
                                                .font(.system(size: 10.5))
                                                .foregroundColor(isActive ? .primary : .secondary)
                                            Text(preset.name.replacingOccurrences(of: "CEO ", with: ""))
                                                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            Spacer()
                                            if isActive {
                                                Text("ACTIVE")
                                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.primary.opacity(0.07))
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
                                    .background(isSelected ? Color.primary.opacity(0.08) : Color.primary.opacity(0.025))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.primary.opacity(isSelected ? 0.14 : 0.05), lineWidth: 0.5)
                                    )
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
                                TextField("Team Name", text: $draftPreset.name)
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
                        
                        // Lead Orchestrator Configuration Box
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "cpu")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("Lead Orchestrator (Task Decomposition & Verification)")
                                    .font(.system(size: 11, weight: .semibold))
                                Spacer()
                                Text(draftPreset.ceoEndpoint.badgeLabel)
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.06))
                                    .cornerRadius(4)
                            }
                            
                            endpointEditorRow(endpoint: $draftPreset.ceoEndpoint)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.09), lineWidth: 0.8)
                        )
                        
                        // Specialist Subagents Section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("SPECIALIST SUBAGENTS")
                                    .font(.system(size: 10, weight: .semibold))
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
                                        Image(systemName: "plus")
                                        Text("Add Specialist")
                                    }
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.primary)
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
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(Color.primary.opacity(0.05))
                                            .cornerRadius(4)
                                        Button {
                                            draftPreset.subordinates.removeAll { $0.id == member.id }
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.secondary)
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
