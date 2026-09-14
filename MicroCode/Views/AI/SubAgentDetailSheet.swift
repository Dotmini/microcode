import Foundation
import SwiftUI

// MARK: - SubAgent Detail Sheet

struct SubAgentDetailSheet: View {
    let subagent: SubAgentInstance
    var onClose: (() -> Void)? = nil
    
    @State private var showFullLog = false
    
    private var elapsedTime: String {
        let start = subagent.startedAt
        let end = subagent.finishedAt ?? Date()
        let interval = end.timeIntervalSince(start)
        if interval < 60 {
            return "\(Int(interval))s"
        } else {
            let minutes = Int(interval) / 60
            let seconds = Int(interval) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: subagent.state.statusIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(subagent.state == .running ? .primary : subagent.state.statusColor)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(subagent.role)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(subagent.typeName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status pill
                HStack(spacing: 4) {
                    if subagent.state == .running {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                    }
                    Text(subagent.state.displayName)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.primary.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)
                
                // Close button
                if let onClose = onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 18, height: 18)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            Divider().opacity(0.3)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Task Prompt
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Task Prompt:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Text(subagent.taskPrompt)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.9))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(6)
                    }
                    
                    // Meta info row
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text(elapsedTime)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .foregroundColor(.secondary)
                        
                        if subagent.tokensUsed > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "text.word.spacing")
                                    .font(.system(size: 9))
                                Text("~\(subagent.tokensUsed) tokens")
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    // Current tool execution
                    if let tool = subagent.currentToolExecution, subagent.state == .running {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.65)
                            Text(tool)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.7))
                            Text("~")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // State detail
                    if let detail = subagent.stateDetail {
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    
                    // Execution Log
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Execution Transcript:")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if subagent.logMessages.count > 10 {
                                Button(action: { showFullLog.toggle() }) {
                                    Text(showFullLog ? "Collapse" : "Expand")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.primary.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            if subagent.logMessages.isEmpty {
                                Text(subagent.state == .running ? "Working..." : "No execution log recorded.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.6))
                            } else {
                                let displayLogs = showFullLog ? subagent.logMessages : Array(subagent.logMessages.suffix(10))
                                
                                if !showFullLog && subagent.logMessages.count > 10 {
                                    Text("... \(subagent.logMessages.count - 10) earlier entries hidden")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary.opacity(0.4))
                                }
                                
                                ForEach(Array(displayLogs.enumerated()), id: \.offset) { _, log in
                                    Text(log)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.primary.opacity(0.85))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.black.opacity(0.15))
                        .cornerRadius(6)
                    }
                    
                    // Final Report
                    if let report = subagent.finalReport {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Final Report:")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Text(report)
                                .font(.system(size: 10.5))
                                .foregroundColor(.primary.opacity(0.9))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(6)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(minWidth: 380, idealWidth: 440, maxWidth: 520)
        .frame(minHeight: 300, idealHeight: 420, maxHeight: 560)
        .background(Color(red: 0.11, green: 0.11, blue: 0.13))
    }
}
