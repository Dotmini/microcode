import Foundation
import SwiftUI

/// Live HUD & Interactive Process Monitor for SubAgents
public struct SubAgentMonitorView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var harness = SubAgentHarness.shared
    @State private var selectedSubagentId: String? = nil
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    private var selectedSubagent: SubAgentInstance? {
        guard let id = selectedSubagentId else { return nil }
        return harness.activeSubagents.first(where: { $0.id == id })
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
                
                Text("SubAgent Process Monitor")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Count badge
                let runningCount = harness.activeSubagents.filter { $0.state == .running }.count
                if runningCount > 0 {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                        Text("\(runningCount) Active")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.9))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(12)
                }
                
                // Terminate All button
                if !harness.activeSubagents.filter({ $0.state == .running }).isEmpty {
                    Button(action: { harness.killAllSubagents() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.circle")
                                .font(.system(size: 11))
                            Text("Kill All")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Terminate all running subagents")
                }
                
                // Done Button (Closes sheet reliably)
                Button(action: {
                    appState.showingSubAgentMonitor = false
                    harness.showSubAgentMonitor = false
                    dismiss()
                }) {
                    Text("Done")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: appState.appTheme.workspaceBackground).opacity(0.98))
            
            Divider().opacity(0.3)
            
            // Content Area: Master List + Inline Detail Inspector
            HSplitView {
                // SubAgents List
                VStack(spacing: 0) {
                    if harness.activeSubagents.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary.opacity(0.4))
                            Text("No SubAgents deployed")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("The Main Agent will autonomously invoke domain specialists for complex tasks.")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(32)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(harness.activeSubagents) { sub in
                                    SubAgentCard(
                                        subagent: sub,
                                        isSelected: selectedSubagentId == sub.id,
                                        onKill: {
                                            harness.killSubagent(id: sub.id)
                                        },
                                        onInspect: {
                                            if selectedSubagentId == sub.id {
                                                selectedSubagentId = nil
                                            } else {
                                                selectedSubagentId = sub.id
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(14)
                        }
                    }
                }
                .frame(minWidth: 280)
                
                // Inline Detail Inspector
                if let sub = selectedSubagent {
                    SubAgentDetailInlineView(subagent: sub, onClose: {
                        selectedSubagentId = nil
                    })
                    .frame(minWidth: 300, maxWidth: .infinity)
                }
            }
            .background(Color(nsColor: appState.appTheme.workspaceBackground))
        }
        .frame(minWidth: selectedSubagentId != nil ? 680 : 460, minHeight: 440)
        .background(Color(nsColor: appState.appTheme.workspaceBackground))
    }
}

// MARK: - SubAgent Card

struct SubAgentCard: View {
    let subagent: SubAgentInstance
    var isSelected: Bool = false
    var onKill: () -> Void
    var onInspect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // Status Icon & Role
                Image(systemName: subagent.state.statusIcon)
                    .font(.system(size: 11))
                    .foregroundColor(subagent.state.statusColor)
                
                Text(subagent.role)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("(\(subagent.typeName))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Status Pill
                Text(subagent.state.displayName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(subagent.state.statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(subagent.state.statusColor.opacity(0.12))
                    .cornerRadius(4)
                
                // Kill Button if active
                if subagent.state == .running {
                    Button(action: onKill) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Terminate process")
                }
            }
            
            // Detail / Tool status
            if let detail = subagent.stateDetail {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // Task Prompt preview
            Text(subagent.taskPrompt)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.8))
                .lineLimit(1)
            
            // Bottom Meta info (Tokens & Inspect button)
            HStack {
                if subagent.tokensUsed > 0 {
                    Text("~\(subagent.tokensUsed) tokens")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                
                Spacer()
                
                Button(action: onInspect) {
                    Text(isSelected ? "Hide Log ▴" : "View Log ➔")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(isSelected ? Color.primary.opacity(0.08) : Color.primary.opacity(0.035))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - SubAgent Detail Inline Inspector

struct SubAgentDetailInlineView: View {
    let subagent: SubAgentInstance
    var onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: subagent.state.statusIcon)
                    .foregroundColor(subagent.state.statusColor)
                Text("\(subagent.role)")
                    .font(.system(size: 13, weight: .bold))
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            
            Divider().opacity(0.3)
            
            // Objective
            VStack(alignment: .leading, spacing: 3) {
                Text("Assigned Prompt:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(subagent.taskPrompt)
                    .font(.system(size: 10.5, design: .monospaced))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(5)
            }
            
            // Logs & Tool Calls
            VStack(alignment: .leading, spacing: 3) {
                Text("Execution Transcript:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if subagent.logMessages.isEmpty {
                            Text("No execution log recorded yet.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(subagent.logMessages, id: \.self) { log in
                                Text(log)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.primary.opacity(0.9))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                .frame(maxHeight: 180)
                .background(Color.black.opacity(0.2))
                .cornerRadius(5)
            }
            
            // Final Report
            if let report = subagent.finalReport {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Report:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    ScrollView {
                        Text(report)
                            .font(.system(size: 10.5))
                            .padding(6)
                    }
                    .frame(maxHeight: 120)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(5)
                }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.025))
    }
}
