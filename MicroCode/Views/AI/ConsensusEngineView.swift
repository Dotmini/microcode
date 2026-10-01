import SwiftUI

// MARK: - Consensus Engine View
// Shows Builder vs. Auditor status, test results, and security findings
// Apple HIG Monochrome design

struct ConsensusEngineView: View {
    @StateObject private var orchestrator = ConsensusOrchestrator.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            consensusHeader
            Divider()
            
            // Content
            if let result = orchestrator.latestResult {
                resultView(result)
            } else if orchestrator.isActive {
                activeView
            } else {
                emptyView
            }
        }
    }
    
    // MARK: - Header
    
    private var consensusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 14))
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Consensus Engine")
                    .font(.system(size: 13, weight: .semibold))
                Text("Builder vs. Auditor — Verified Code Generation")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Phase indicator
            if orchestrator.isActive {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text(orchestrator.currentPhase.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
            
            // Controls
            Toggle(isOn: $orchestrator.consensusEnabled) {
                Text("Active")
                    .font(.system(size: 10))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            
            Menu {
                Toggle("Strict Mode (all tests must pass)", isOn: $orchestrator.strictMode)
                Toggle("Auto-apply on pass", isOn: $orchestrator.autoApplyOnPass)
                Divider()
                Button("Reset") { orchestrator.reset() }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }
    
    // MARK: - Active View (During Consensus)
    
    private var activeView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Dual agent visualization
            HStack(spacing: 40) {
                agentCard(
                    name: "Builder",
                    icon: "hammer.fill",
                    color: .blue,
                    isActive: orchestrator.currentPhase == .building,
                    phase: orchestrator.currentPhase == .building ? "Writing code..." : "Done"
                )
                
                // Arrow
                VStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                    Text("vs")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
                
                agentCard(
                    name: "Auditor",
                    icon: "shield.lefthalf.filled",
                    color: .red,
                    isActive: orchestrator.currentPhase == .auditing || orchestrator.currentPhase == .testing,
                    phase: orchestrator.currentPhase == .auditing ? "Generating tests..." :
                           orchestrator.currentPhase == .testing ? "Running tests..." : "Waiting..."
                )
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Result View
    
    private func resultView(_ result: ConsensusResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Verdict banner
                verdictBanner(result)
                
                // Stats row
                statsRow(result)
                
                Divider().padding(.horizontal, 14)
                
                // Security findings
                if !result.securityIssues.isEmpty {
                    securitySection(result.securityIssues)
                    Divider().padding(.horizontal, 14)
                }
                
                // Test results
                testResultsSection(result.auditorTests)
                
                // File changes
                if !result.builderChanges.isEmpty {
                    Divider().padding(.horizontal, 14)
                    changesSection(result.builderChanges)
                }
                
                // Action buttons
                if result.verdict == .rejected {
                    actionButtons(result)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Verdict Banner
    
    private func verdictBanner(_ result: ConsensusResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: result.verdict == .approved ? "checkmark.shield.fill" : "xmark.shield.fill")
                .font(.system(size: 24))
                .foregroundColor(result.verdict == .approved ? .green : .red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.verdict.rawValue)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(result.verdict == .approved ? .green : .red)
                Text(result.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(result.executionTimeMs)ms")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background((result.verdict == .approved ? Color.green : Color.red).opacity(0.05))
    }
    
    // MARK: - Stats Row
    
    private func statsRow(_ result: ConsensusResult) -> some View {
        HStack(spacing: 20) {
            statItem(label: "Tests", value: "\(result.totalTests)", color: .primary)
            statItem(label: "Passed", value: "\(result.passedTests)", color: .green)
            statItem(label: "Failed", value: "\(result.failedTests)", color: .red)
            statItem(label: "Security", value: "\(result.securityIssues.count)", 
                    color: result.securityIssues.isEmpty ? .green : .orange)
            statItem(label: "Files", value: "\(result.builderChanges.count)", color: .blue)
        }
        .padding(.horizontal, 14)
    }
    
    // MARK: - Security Section
    
    private func securitySection(_ findings: [SecurityFinding]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Text("Security Findings")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            
            ForEach(findings) { finding in
                HStack(spacing: 8) {
                    Text(finding.severity.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(severityColor(finding.severity))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(severityColor(finding.severity).opacity(0.1))
                        .cornerRadius(3)
                        .frame(width: 60)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(finding.title)
                            .font(.system(size: 11, weight: .medium))
                        Text(finding.description)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    Text(URL(fileURLWithPath: finding.filePath).lastPathComponent)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
        }
    }
    
    // MARK: - Test Results
    
    private func testResultsSection(_ tests: [AuditorTestCase]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.system(size: 11))
                Text("Auditor Tests")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            
            ForEach(tests) { test in
                HStack(spacing: 8) {
                    Image(systemName: test.status == .passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(test.status == .passed ? .green : .red)
                    
                    Text(test.category.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(3)
                        .frame(width: 80)
                    
                    Text(test.name)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if test.status == .failed {
                        Text(test.output.prefix(60))
                            .font(.system(size: 9))
                            .foregroundColor(.red.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 3)
            }
        }
    }
    
    // MARK: - Changes Section
    
    private func changesSection(_ changes: [SandboxFileChange]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 11))
                Text("Builder Changes")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            
            ForEach(changes) { change in
                HStack(spacing: 8) {
                    Image(systemName: change.changeType == .create ? "plus.circle.fill" :
                          change.changeType == .delete ? "minus.circle.fill" : "pencil.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(change.changeType == .create ? .green :
                                        change.changeType == .delete ? .red : .blue)
                    
                    Text(change.filePath)
                        .font(.system(size: 10, design: .monospaced))
                    
                    Spacer()
                    
                    Text(change.changeType.rawValue)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 3)
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private func actionButtons(_ result: ConsensusResult) -> some View {
        HStack(spacing: 12) {
            Spacer()
            
            Button("Apply Anyway (Override)") {
                orchestrator.forceApply(
                    result: result,
                    workspaceRoot: "" // Would come from context
                )
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(5)
            
            Button("Retry with Builder") {
                orchestrator.reset()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.07))
            .cornerRadius(5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
    
    // MARK: - Components
    
    private func agentCard(name: String, icon: String, color: Color, isActive: Bool, phase: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(isActive ? 0.15 : 0.05))
                    .frame(width: 56, height: 56)
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(color.opacity(isActive ? 1.0 : 0.4))
                
                if isActive {
                    Circle()
                        .stroke(color, lineWidth: 2)
                        .frame(width: 56, height: 56)
                        .opacity(0.5)
                }
            }
            
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isActive ? .primary : .secondary)
            
            Text(phase)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
    
    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }
    
    private func severityColor(_ severity: SecurityFinding.Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        case .info: return .gray
        }
    }
    
    // MARK: - Empty View
    
    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            
            HStack(spacing: 30) {
                VStack(spacing: 6) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.blue.opacity(0.3))
                    Text("Builder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Text("vs")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.4))
                
                VStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 28))
                        .foregroundColor(.red.opacity(0.3))
                    Text("Auditor")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Text("Consensus Engine will verify code changes before applying")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text(orchestrator.consensusEnabled ? "✓ Active" : "○ Disabled")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(orchestrator.consensusEnabled ? .green : .secondary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
