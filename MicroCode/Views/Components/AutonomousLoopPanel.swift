// Copyright © 2025 Dotmini Software. All rights reserved.

import Foundation
import SwiftUI
import Combine
import AppKit

/// A SwiftUI view for the Autonomous Build-Test-Fix Loop panel (Feature 4).
/// Visualizes the iterative autonomous loop: Build → Test → Analyze → Fix → repeat.
struct AutonomousLoopPanel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var loopService: AutonomousLoopService
    
    // MARK: - State
    @State private var localConfig: LoopConfig = LoopConfig()
    @State private var selectedIterationId: UUID? = nil
    @State private var consoleTab: ConsoleTab = .all
    @State private var isConfigExpanded: Bool = false
    @State private var isAutoScrollEnabled: Bool = true
    @State private var copiedNotice: Bool = false
    
    enum ConsoleTab: String, CaseIterable, Identifiable {
        case all = "All"
        case build = "Build"
        case test = "Test"
        case analysis = "Analysis"
        
        var id: String { rawValue }
    }
    
    // MARK: - Initializer
    init(loopService: AutonomousLoopService = .shared) {
        self.loopService = loopService
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Top Progress & Status Header
            headerView
            
            Divider()
            
            // Phase Step Visualization
            phasePipelineView
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Main Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Completed Summary Card
                    if let summary = loopService.summary {
                        summaryCardView(summary: summary)
                    }
                    
                    // Controls & Configuration
                    controlsAndConfigSection
                    
                    // Iteration History
                    iterationHistorySection
                    
                    // Live Console Output
                    consoleOutputSection
                }
                .padding(14)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            initializeConfigIfNeeded()
        }
        .onChange(of: loopService.iterations.count) { _ in
            // When a new iteration is added while running, select it
            if loopService.isRunning, let lastId = loopService.iterations.last?.id {
                selectedIterationId = lastId
            }
        }
    }
    
    // MARK: - Selected Iteration
    private var activeIteration: LoopIteration? {
        if let selectedId = selectedIterationId,
           let found = loopService.iterations.first(where: { $0.id == selectedId }) {
            return found
        }
        return loopService.iterations.last
    }
    
    // MARK: - 1. Progress Header
    private var headerView: some View {
        HStack(spacing: 12) {
            // Icon & Title
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(loopService.isRunning ? .accentColor : .secondary)
                    .rotationEffect(.degrees(loopService.isRunning ? 360 : 0))
                    .animation(
                        loopService.isRunning
                            ? Animation.linear(duration: 2).repeatForever(autoreverses: false)
                            : .default,
                        value: loopService.isRunning
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Autonomous Loop")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(iterationProgressText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Current Phase Pill
            currentPhaseBadge
            
            // Controls Toolbar
            HStack(spacing: 6) {
                if !loopService.isRunning {
                    Button(action: startLoopAction) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Start")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                } else {
                    if loopService.currentPhase == .paused {
                        Button(action: resumeLoopAction) {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10))
                                Text("Resume")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: pauseLoopAction) {
                            HStack(spacing: 4) {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 10))
                                Text("Pause")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: stopLoopAction) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                            Text("Stop")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private var iterationProgressText: String {
        let total = loopService.config.maxIterations
        let current = loopService.iterations.last?.number ?? 0
        
        if loopService.isRunning {
            return "Iteration \(current)/\(total)"
        } else if loopService.currentPhase == .completed {
            return "Completed (\(loopService.iterations.count)/\(total) iterations)"
        } else if loopService.currentPhase == .paused {
            return "Paused at Iteration \(current)/\(total)"
        } else {
            return "Ready (Max \(total) iterations)"
        }
    }
    
    private var currentPhaseBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(phaseBadgeColor)
                .frame(width: 7, height: 7)
            
            Text(phaseBadgeText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(phaseBadgeBackgroundColor)
        .clipShape(Capsule())
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: loopService.currentPhase)
    }
    
    private var phaseBadgeColor: Color {
        switch loopService.currentPhase {
        case .idle: return .secondary
        case .building, .testing, .analyzing, .fixing: return .blue
        case .paused: return .orange
        case .completed: return .green
        }
    }
    
    private var phaseBadgeBackgroundColor: Color {
        switch loopService.currentPhase {
        case .idle: return Color.primary.opacity(0.06)
        case .building, .testing, .analyzing, .fixing: return Color.blue.opacity(0.2)
        case .paused: return Color.orange.opacity(0.15)
        case .completed: return Color.green.opacity(0.15)
        }
    }
    
    private var phaseBadgeText: String {
        switch loopService.currentPhase {
        case .idle: return "Idle"
        case .building: return "Building"
        case .testing: return "Testing"
        case .analyzing: return "Analyzing"
        case .fixing: return "Fixing"
        case .paused: return "Paused"
        case .completed: return "Done"
        }
    }
    
    // MARK: - 2. Phase Visualization (Horizontal Step Indicators)
    private var phasePipelineView: some View {
        HStack(spacing: 8) {
            pipelineStep(
                title: "Build",
                icon: "hammer.fill",
                phase: .building,
                status: buildStepStatus
            )
            
            connectorArrow
            
            pipelineStep(
                title: "Test",
                icon: "flask.fill",
                phase: .testing,
                status: testStepStatus
            )
            
            connectorArrow
            
            pipelineStep(
                title: "Analyze",
                icon: "sparkles",
                phase: .analyzing,
                status: analyzeStepStatus
            )
            
            connectorArrow
            
            pipelineStep(
                title: "Fix",
                icon: "wrench.and.screwdriver.fill",
                phase: .fixing,
                status: fixStepStatus
            )
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: loopService.currentPhase)
    }
    
    private var connectorArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.secondary.opacity(0.5))
    }
    
    private func pipelineStep(
        title: String,
        icon: String,
        phase: LoopPhase,
        status: StepState
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(status.textColor)
            
            Text(title)
                .font(.system(size: 11, weight: status == .active ? .bold : .medium))
                .foregroundColor(status.textColor)
            
            if status == .active {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
            } else if status == .success {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.green)
            } else if status == .failure {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(status.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(status.borderColor, lineWidth: status == .active ? 1.5 : 1)
        )
        .cornerRadius(6)
    }
    
    private enum StepState {
        case pending
        case active
        case success
        case failure
        
        var backgroundColor: Color {
            switch self {
            case .pending: return Color.primary.opacity(0.04)
            case .active: return Color.blue.opacity(0.2)
            case .success: return Color.green.opacity(0.15)
            case .failure: return Color.red.opacity(0.15)
            }
        }
        
        var borderColor: Color {
            switch self {
            case .pending: return Color.primary.opacity(0.1)
            case .active: return Color.blue.opacity(0.5)
            case .success: return Color.green.opacity(0.4)
            case .failure: return Color.red.opacity(0.4)
            }
        }
        
        var textColor: Color {
            switch self {
            case .pending: return .secondary
            case .active, .success, .failure: return .primary
            }
        }
    }
    
    private var buildStepStatus: StepState {
        if loopService.currentPhase == .building {
            return .active
        }
        guard let iteration = activeIteration else { return .pending }
        if let build = iteration.buildResult {
            return build.passed ? .success : .failure
        }
        return .pending
    }
    
    private var testStepStatus: StepState {
        if loopService.currentPhase == .testing {
            return .active
        }
        guard let iteration = activeIteration else { return .pending }
        if let test = iteration.testResult {
            return test.passed ? .success : .failure
        }
        return .pending
    }
    
    private var analyzeStepStatus: StepState {
        if loopService.currentPhase == .analyzing {
            return .active
        }
        guard let iteration = activeIteration else { return .pending }
        if iteration.analysisResult != nil {
            return .success
        }
        return .pending
    }
    
    private var fixStepStatus: StepState {
        if loopService.currentPhase == .fixing {
            return .active
        }
        guard let iteration = activeIteration else { return .pending }
        if iteration.fixApplied != nil {
            return .success
        }
        return .pending
    }
    
    // MARK: - 3. Summary Card
    private func summaryCardView(summary: LoopSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: summary.testsPassedFinal ? "checkmark.seal.fill" : "info.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(summary.testsPassedFinal ? .green : .secondary)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.testsPassedFinal ? "Loop Succeeded: Tests Passed!" : "Loop Execution Completed")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Executed in \(String(format: "%.1f", summary.totalDuration))s across \(summary.totalIterations) iteration(s)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Dismiss") {
                    loopService.summary = nil
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Metrics grid
            HStack(spacing: 12) {
                summaryMetric(label: "Iterations", value: "\(summary.totalIterations)", icon: "repeat")
                summaryMetric(label: "Duration", value: String(format: "%.1fs", summary.totalDuration), icon: "stopwatch")
                summaryMetric(label: "Fixes Applied", value: "\(summary.fixesApplied)", icon: "bandage")
                summaryMetric(label: "Files Modified", value: "\(summary.filesModified.count)", icon: "doc.badge.ellipsis")
            }
            
            // Modified files list
            if !summary.filesModified.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Modified Files:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    ForEach(summary.filesModified, id: \.self) { file in
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(file)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(6)
            }
        }
        .padding(12)
        .background(summary.testsPassedFinal ? Color.green.opacity(0.1) : Color.primary.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(summary.testsPassedFinal ? Color.green.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(8)
    }
    
    private func summaryMetric(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(6)
    }
    
    // MARK: - 4. Controls & Configuration Section
    private var controlsAndConfigSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $isConfigExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    // Working Directory
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Working Directory")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Use Workspace") {
                                localConfig.workingDirectory = appState.activeTerminalDirectory
                                autoDetectCommands()
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                        
                        TextField("Path to repository root", text: $localConfig.workingDirectory)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    
                    // Build Command
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Build Command")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Auto-detect") {
                                if let detected = loopService.detectBuildCommand(in: currentDir) {
                                    localConfig.buildCommand = detected
                                }
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                        
                        TextField("e.g. cargo build, npm run build, make", text: $localConfig.buildCommand)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    
                    // Test Command
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Test Command")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Auto-detect") {
                                if let detected = loopService.detectTestCommand(in: currentDir) {
                                    localConfig.testCommand = detected
                                }
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                        
                        TextField("e.g. cargo test, pytest, npm test", text: $localConfig.testCommand)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    
                    Divider()
                    
                    // Steppers & Toggles
                    HStack(spacing: 16) {
                        // Max Iterations Stepper
                        Stepper(value: $localConfig.maxIterations, in: 1...20) {
                            HStack(spacing: 4) {
                                Text("Max Iterations:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text("\(localConfig.maxIterations)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        // Max Diff Lines Stepper
                        Stepper(value: $localConfig.maxDiffLines, in: 10...200, step: 10) {
                            HStack(spacing: 4) {
                                Text("Max Diff:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text("\(localConfig.maxDiffLines) lines")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    
                    HStack(spacing: 16) {
                        // Max Duration
                        Stepper(
                            value: Binding(
                                get: { Int(localConfig.maxDurationSeconds / 60) },
                                set: { localConfig.maxDurationSeconds = TimeInterval($0 * 60) }
                            ),
                            in: 1...60
                        ) {
                            HStack(spacing: 4) {
                                Text("Max Duration:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text("\(Int(localConfig.maxDurationSeconds / 60)) min")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        // Auto Apply Toggle
                        Toggle("Auto-apply fixes", isOn: $localConfig.autoApply)
                            .font(.system(size: 11))
                    }
                }
                .padding(.top, 6)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Loop Configuration")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    if !localConfig.buildCommand.isEmpty || !localConfig.testCommand.isEmpty {
                        Text("\(localConfig.buildCommand) • \(localConfig.testCommand)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        .cornerRadius(8)
    }
    
    // MARK: - 5. Iteration History Section
    private var iterationHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Iteration History")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("(\(loopService.iterations.count))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !loopService.iterations.isEmpty {
                    Button("Select Latest") {
                        selectedIterationId = loopService.iterations.last?.id
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            
            if loopService.iterations.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("No iterations recorded yet")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
                .background(Color.primary.opacity(0.02))
                .cornerRadius(6)
            } else {
                VStack(spacing: 6) {
                    ForEach(loopService.iterations) { iteration in
                        iterationRow(iteration: iteration)
                    }
                }
            }
        }
    }
    
    private func iterationRow(iteration: LoopIteration) -> some View {
        let isSelected = (selectedIterationId == iteration.id) || (selectedIterationId == nil && iteration.id == loopService.iterations.last?.id)
        
        return Button {
            selectedIterationId = iteration.id
        } label: {
            HStack(spacing: 10) {
                // Iteration number
                Text("#\(iteration.number)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(width: 28, alignment: .leading)
                
                // Status pill
                statusBadge(status: iteration.status)
                
                // Duration
                if let completedAt = iteration.completedAt {
                    let dur = completedAt.timeIntervalSince(iteration.startedAt)
                    Text(String(format: "%.1fs", dur))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text("running...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.blue)
                }
                
                // Results summary
                HStack(spacing: 6) {
                    if let build = iteration.buildResult {
                        resultMiniPill(label: "Build", passed: build.passed)
                    }
                    if let test = iteration.testResult {
                        resultMiniPill(label: "Test", passed: test.passed)
                    }
                }
                
                Spacer()
                
                // Fix description if any
                if let fix = iteration.fixApplied {
                    Text(fix)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 160, alignment: .trailing)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isSelected ? .primary : .secondary.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Color.blue.opacity(0.12) : Color.primary.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    private func statusBadge(status: IterationStatus) -> some View {
        HStack(spacing: 3) {
            switch status {
            case .passed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.green)
                Text("Passed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.red)
                Text("Failed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
            case .building, .testing, .analyzing, .fixing:
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 8, height: 8)
                Text(status.rawValue.capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
            case .skipped:
                Image(systemName: "minus.circle")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text("Skipped")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(iterationStatusBackground(status))
        .cornerRadius(4)
    }
    
    private func iterationStatusBackground(_ status: IterationStatus) -> Color {
        switch status {
        case .passed: return Color.green.opacity(0.15)
        case .failed: return Color.red.opacity(0.15)
        case .building, .testing, .analyzing, .fixing: return Color.blue.opacity(0.2)
        case .skipped: return Color.primary.opacity(0.05)
        }
    }
    
    private func resultMiniPill(label: String, passed: Bool) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Image(systemName: passed ? "checkmark" : "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(passed ? .green : .red)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(passed ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(3)
    }
    
    // MARK: - 6. Current Output (Live Console View)
    private var consoleOutputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("Output Console")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    if let iteration = activeIteration {
                        Text("(Iteration #\(iteration.number))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Tabs
                Picker("", selection: $consoleTab) {
                    ForEach(ConsoleTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                
                // Copy button
                Button {
                    copyConsoleOutput()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedNotice ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(copiedNotice ? "Copied" : "Copy")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            
            // Console Terminal Box
            consoleTerminalBox
        }
    }
    
    private var consoleTerminalBox: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    let content = computedConsoleOutput
                    if content.isEmpty {
                        Text("No console output for this iteration.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(10)
                    } else {
                        Text(content)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    
                    // Bottom anchor for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("ConsoleBottom")
                }
            }
            .frame(minHeight: 180, maxHeight: 320)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .cornerRadius(6)
            .onChange(of: computedConsoleOutput) { _ in
                if isAutoScrollEnabled {
                    withAnimation {
                        proxy.scrollTo("ConsoleBottom", anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var computedConsoleOutput: String {
        guard let iteration = activeIteration else {
            return "Start a loop to see build, test, and fix outputs."
        }
        
        switch consoleTab {
        case .all:
            var fullStream: [String] = []
            
            if let build = iteration.buildResult {
                fullStream.append("$ \(build.command)")
                if !build.stdout.isEmpty { fullStream.append(build.stdout) }
                if !build.stderr.isEmpty { fullStream.append("[stderr]\n\(build.stderr)") }
                fullStream.append("[Build exit: \(build.exitCode), \(String(format: "%.2fs", build.duration))]")
            }
            
            if let test = iteration.testResult {
                if !fullStream.isEmpty { fullStream.append("\n" + String(repeating: "-", count: 40) + "\n") }
                fullStream.append("$ \(test.command)")
                if !test.stdout.isEmpty { fullStream.append(test.stdout) }
                if !test.stderr.isEmpty { fullStream.append("[stderr]\n\(test.stderr)") }
                fullStream.append("[Test exit: \(test.exitCode), \(String(format: "%.2fs", test.duration))]")
            }
            
            if let analysis = iteration.analysisResult {
                if !fullStream.isEmpty { fullStream.append("\n" + String(repeating: "-", count: 40) + "\n") }
                fullStream.append("[Analysis]\n\(analysis)")
            }
            
            if let fix = iteration.fixApplied {
                if !fullStream.isEmpty { fullStream.append("\n" + String(repeating: "-", count: 40) + "\n") }
                fullStream.append("[Fix Applied]\n\(fix)")
            }
            
            return fullStream.joined(separator: "\n")
            
        case .build:
            guard let build = iteration.buildResult else {
                return "No build result recorded for this iteration."
            }
            var output = "$ \(build.command)\n"
            if !build.stdout.isEmpty { output += build.stdout + "\n" }
            if !build.stderr.isEmpty { output += "\n[stderr]\n" + build.stderr + "\n" }
            output += "\nExit code: \(build.exitCode) (\(String(format: "%.2fs", build.duration)))"
            return output
            
        case .test:
            guard let test = iteration.testResult else {
                return "No test result recorded for this iteration."
            }
            var output = "$ \(test.command)\n"
            if !test.stdout.isEmpty { output += test.stdout + "\n" }
            if !test.stderr.isEmpty { output += "\n[stderr]\n" + test.stderr + "\n" }
            output += "\nExit code: \(test.exitCode) (\(String(format: "%.2fs", test.duration)))"
            return output
            
        case .analysis:
            var parts: [String] = []
            if let analysis = iteration.analysisResult {
                parts.append("Analysis:\n\(analysis)")
            }
            if let fix = iteration.fixApplied {
                parts.append("Fix Plan / Applied:\n\(fix)")
            }
            return parts.isEmpty ? "No analysis or fix recorded for this iteration." : parts.joined(separator: "\n\n")
        }
    }
    
    // MARK: - Actions
    private func startLoopAction() {
        // Sync working directory if empty
        if localConfig.workingDirectory.isEmpty {
            localConfig.workingDirectory = currentDir
        }
        
        // Auto-detect commands if empty
        if localConfig.buildCommand.isEmpty, let b = loopService.detectBuildCommand(in: currentDir) {
            localConfig.buildCommand = b
        }
        if localConfig.testCommand.isEmpty, let t = loopService.detectTestCommand(in: currentDir) {
            localConfig.testCommand = t
        }
        
        Task {
            await loopService.startLoop(config: localConfig)
        }
    }
    
    private func pauseLoopAction() {
        loopService.pauseLoop()
    }
    
    private func resumeLoopAction() {
        Task {
            await loopService.resumeLoop()
        }
    }
    
    private func stopLoopAction() {
        loopService.cancelLoop()
    }
    
    private func copyConsoleOutput() {
        let text = computedConsoleOutput
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        withAnimation {
            copiedNotice = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedNotice = false
        }
    }
    
    private var currentDir: String {
        if !localConfig.workingDirectory.isEmpty {
            return localConfig.workingDirectory
        }
        return appState.activeTerminalDirectory
    }
    
    private func initializeConfigIfNeeded() {
        localConfig = loopService.config
        if localConfig.workingDirectory.isEmpty {
            localConfig.workingDirectory = currentDir
        }
        autoDetectCommands()
    }
    
    private func autoDetectCommands() {
        let dir = currentDir
        if localConfig.buildCommand.isEmpty, let b = loopService.detectBuildCommand(in: dir) {
            localConfig.buildCommand = b
        }
        if localConfig.testCommand.isEmpty, let t = loopService.detectTestCommand(in: dir) {
            localConfig.testCommand = t
        }
    }
}
