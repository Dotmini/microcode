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
                
                // Role text
                Text(subagent.role)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
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
    
    var body: some View {
        if let plan = planManager.currentPlan {
            VStack(alignment: .leading, spacing: 6) {
                // Header Row (Compact, Formal IDE Header)
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("Implementation Plan")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    if !plan.title.isEmpty && plan.title != "Implementation Plan" {
                        Text("— \(plan.title)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
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
                    
                    if plan.totalSteps > 0 {
                        Text("• \(plan.totalSteps) steps")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary.opacity(0.7))
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
                            .padding(.vertical, 2.5)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Inspect plan in side panel")
                    }
                    
                    Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                }
                
                // Pending Review Action Row (Clean, Formal, Understated)
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
                } else if plan.approvalState == .approved {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9.5))
                            .foregroundColor(.green.opacity(0.85))
                        Text("Approved — Agent is executing planned steps")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, 1)
                } else if plan.approvalState == .rejected {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                        Text("Rejected — No files were modified")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, 1)
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
        }
    }
}
