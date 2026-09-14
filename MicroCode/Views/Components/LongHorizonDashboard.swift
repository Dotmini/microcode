// Copyright © 2025 Dotmini Software. All rights reserved.

import Foundation
import SwiftUI
import Combine
import AppKit

/// SwiftUI dashboard view for Long-Horizon Agent (Feature 7).
/// Displays task progress, interactive subtask timeline, live execution output,
/// chronological audit log, and checkpoint restoration controls.
public struct LongHorizonDashboard: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var agent: LongHorizonAgent

    // MARK: - View State
    @State private var taskPrompt: String = ""
    @State private var isStartingTask: Bool = false
    @State private var errorMessage: String?
    @State private var showErrorAlert: Bool = false

    // Subtask & Detail Expansion
    @State private var expandedSubtaskIds: Set<String> = []
    @State private var selectedSubtaskId: String?

    // Live Execution Console State
    @State private var autoScrollConsole: Bool = true
    @State private var showCopiedToast: Bool = false
    @State private var consoleFilter: ConsoleFilter = .all

    // Timeline Sidebar Filter
    @State private var timelineFilter: TimelineEventFilter = .all

    // Checkpoint Management State
    @State private var showRestoreConfirmation: Bool = false
    @State private var checkpointToRestore: Checkpoint?
    @State private var isCheckpointsExpanded: Bool = false
    @State private var isSavingCheckpoint: Bool = false

    // UI Layout Mode
    @State private var activeTab: DashboardTab = .execution

    public enum DashboardTab: String, CaseIterable, Identifiable {
        case execution = "Subtasks & Execution"
        case timeline = "Audit Timeline"
        case checkpoints = "Checkpoints"

        public var id: String { rawValue }
    }

    public enum TimelineEventFilter: String, CaseIterable, Identifiable {
        case all = "All Events"
        case subtasks = "Subtasks"
        case checkpoints = "Checkpoints"
        case errors = "Errors"
        case user = "User"

        public var id: String { rawValue }
    }

    public enum ConsoleFilter: String, CaseIterable, Identifiable {
        case all = "All Output"
        case tools = "Tools"
        case results = "Results"

        public var id: String { rawValue }
    }

    // MARK: - Initializer
    public init(agent: LongHorizonAgent = .shared) {
        self.agent = agent
    }

    // MARK: - Body
    public var body: some View {
        VStack(spacing: 0) {
            // Task Header & Progress Bar
            taskHeaderView
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Controls & Quick Action Toolbar
            controlsToolbarView
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))

            Divider()

            // Main Content Area
            if agent.currentTask == nil && agent.subtasks.isEmpty {
                emptyTaskStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mainDashboardSplitView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Restore Checkpoint", isPresented: $showRestoreConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restore State", role: .destructive) {
                if let cp = checkpointToRestore {
                    restore(from: cp)
                }
            }
        } message: {
            if let cp = checkpointToRestore {
                Text("Are you sure you want to restore to checkpoint \(String(cp.id.prefix(8))) from \(formattedDate(cp.timestamp))? In-progress execution will be reset to this point.")
            } else {
                Text("Restore the selected checkpoint?")
            }
        }
        .alert("Long-Horizon Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unexpected error occurred during execution.")
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Console logs copied to clipboard")
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - 1. Task Header View
    private var taskHeaderView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // Task Leading Icon
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 38, height: 38)

                    Image(systemName: agent.isExecuting ? "arrow.triangle.2.circlepath" : "chart.line.uptrend.xyaxis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(agent.isExecuting ? .blue : .primary)
                        .rotationEffect(.degrees(agent.isExecuting ? 360 : 0))
                        .animation(agent.isExecuting ? Animation.linear(duration: 2).repeatForever(autoreverses: false) : .default, value: agent.isExecuting)
                }

                // Task Details & Status Badge
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(agent.currentTask?.title ?? "Long-Horizon Autonomous Agent")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let task = agent.currentTask {
                            taskStatusBadge(for: task.status)
                        } else {
                            Text("IDLE")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .foregroundColor(.secondary)
                                .cornerRadius(4)
                        }

                        Spacer()

                        // Last Checkpoint Quick Chip
                        if let lastCp = agent.currentTask?.checkpoints.last {
                            HStack(spacing: 5) {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.primary)
                                Text("Last Checkpoint: \(relativeTimeString(lastCp.timestamp))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Button(action: {
                                    checkpointToRestore = lastCp
                                    showRestoreConfirmation = true
                                }) {
                                    Text("Restore")
                                        .font(.caption2.bold())
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }

                    // Metadata chips: Duration, Subtask ratio, Workspace
                    HStack(spacing: 12) {
                        if let task = agent.currentTask {
                            if let est = task.estimatedDuration {
                                Label("Est. ~\(formatDuration(est))", systemImage: "clock")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Label("Elapsed: \(formatDuration(Date().timeIntervalSince(task.startedAt)))", systemImage: "hourglass")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Label("\(completedSubtasksCount)/\(agent.subtasks.count) Subtasks", systemImage: "checklist")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Ready to plan and execute multi-step software engineering tasks")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Minimal White/Gray Overall Progress Bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Overall Progress")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(Int(agent.progress * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background Bar
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.2))

                        // Filled Bar
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary)
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(agent.progress))))
                            .animation(.easeInOut(duration: 0.35), value: agent.progress)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - 2. Controls & Quick Action Toolbar
    private var controlsToolbarView: some View {
        HStack(spacing: 10) {
            // Execution Controls
            if agent.isExecuting {
                Button(action: { agent.pauseExecution() }) {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .help("Pause execution safely after current tool action")

                Button(role: .destructive, action: { agent.cancelExecution() }) {
                    Label("Cancel", systemImage: "xmark")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .help("Cancel remaining task execution")
            } else {
                // Resume Button (if paused or can resume from checkpoint)
                let canResume = (agent.currentTask?.status == .paused || (!agent.subtasks.isEmpty && agent.subtasks.contains { $0.status == .pending || $0.status == .failed }))
                if canResume {
                    Button(action: {
                        if let lastCp = agent.currentTask?.checkpoints.last {
                            restore(from: lastCp)
                        }
                    }) {
                        Label("Resume", systemImage: "play.fill")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primary)
                    .help("Resume execution from latest checkpoint")
                }

                // New Task Button
                Button(action: {
                    withAnimation(.easeInOut) {
                        agent.currentTask = nil
                        agent.subtasks = []
                    }
                }) {
                    Label("New Task", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .help("Clear current task and enter a new prompt")
            }

            // Save Manual Checkpoint
            if agent.currentTask != nil {
                Button(action: { saveManualCheckpoint() }) {
                    HStack(spacing: 4) {
                        if isSavingCheckpoint {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Image(systemName: "bookmark.badge.plus")
                        }
                        Text("Checkpoint")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .disabled(isSavingCheckpoint)
                .help("Create an immediate snapshot checkpoint")
            }

            Spacer()

            // View Mode Tab Switcher
            Picker("", selection: $activeTab) {
                ForEach(DashboardTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
        }
    }

    // MARK: - 3. Main Split View Area
    private var mainDashboardSplitView: some View {
        HSplitView {
            // Left Pane: Subtasks Timeline & Live Execution Console
            VStack(spacing: 0) {
                switch activeTab {
                case .execution:
                    VSplitView {
                        // Subtasks vertical timeline list
                        subtaskTimelineListView
                            .frame(minHeight: 220)

                        // Live execution output console
                        liveExecutionConsoleView
                            .frame(minHeight: 180)
                    }

                case .timeline:
                    chronologicalTimelineView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .checkpoints:
                    checkpointManagerView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 420)

            // Right Pane: Collapsible Activity & Checkpoint Sidebar
            sidebarView
                .frame(minWidth: 260, maxWidth: 360)
        }
    }

    // MARK: - 4. Subtasks Vertical Timeline List
    private var subtaskTimelineListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar
            HStack {
                Text("SUBTASK TIMELINE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(completedSubtasksCount) of \(agent.subtasks.count) Completed")
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))

            Divider()

            // Scrollable Timeline
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(agent.subtasks.enumerated()), id: \.element.id) { index, subtask in
                        subtaskTimelineRow(subtask: subtask, index: index, isLast: index == agent.subtasks.count - 1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func subtaskTimelineRow(subtask: Subtask, index: Int, isLast: Bool) -> some View {
        let isExpanded = expandedSubtaskIds.contains(subtask.id)
        let isCurrent = subtask.status == .inProgress

        return HStack(alignment: .top, spacing: 12) {
            // Vertical timeline node & connector
            VStack(spacing: 0) {
                // Top connector line
                if index > 0 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2, height: 12)
                } else {
                    Spacer().frame(height: 12)
                }

                // Node Status Icon
                subtaskStatusIcon(for: subtask.status)
                    .frame(width: 20, height: 20)

                // Bottom connector line
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                }
            }
            .frame(width: 24)

            // Subtask Card
            VStack(alignment: .leading, spacing: 6) {
                // Clickable Header Row
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedSubtaskIds.remove(subtask.id)
                        } else {
                            expandedSubtaskIds.insert(subtask.id)
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        // Subtask Number
                        Text("#\(index + 1)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)

                        // Subtask Title
                        Text(subtask.title)
                            .font(.system(size: 12.5, weight: isCurrent ? .bold : .medium))
                            .foregroundColor(isCurrent ? .primary : .primary.opacity(0.9))
                            .lineLimit(1)

                        Spacer()

                        // Files Modified Count Badge
                        let filesCount = filesModifiedCount(for: subtask)
                        if filesCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 9))
                                Text("\(filesCount)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                            .foregroundColor(.secondary)
                        }

                        // Duration Badge
                        if subtask.duration > 0 {
                            Text(formatDuration(subtask.duration))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        // Expand/Collapse Chevron
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                // Expandable Details Section
                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                            .opacity(0.4)

                        // Instructions / Description
                        Text(subtask.description)
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        // Dependencies
                        if !subtask.dependencies.isEmpty {
                            HStack(spacing: 4) {
                                Text("Dependencies:")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)

                                ForEach(subtask.dependencies, id: \.self) { dep in
                                    Text(dep)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(3)
                                }
                            }
                        }

                        // Execution Result / Output Box
                        if let res = subtask.result, !res.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("OUTPUT / RESULT:")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(res)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .lineLimit(6)
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                .cornerRadius(4)
                            }
                        }

                        // Modified Files List
                        let paths = filesModified(for: subtask)
                        if !paths.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("MODIFIED FILES:")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)

                                ForEach(paths, id: \.self) { path in
                                    HStack(spacing: 4) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        Text(path)
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }

                        // Retry Single Subtask Action
                        if subtask.status == .failed || subtask.status == .pending {
                            HStack {
                                Spacer()
                                Button(action: {
                                    Task {
                                        try? await agent.executeSubtask(subtask)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.counterclockwise")
                                        Text("Run This Subtask")
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? Color.primary.opacity(0.04) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isCurrent ? Color.primary.opacity(0.2) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .padding(.vertical, 2)
    }

    // MARK: - 5. Live Execution View (Scrolling Console)
    private var liveExecutionConsoleView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Console Toolbar Header
            HStack(spacing: 8) {
                // Active Subtask Indicator
                if let active = agent.subtasks.first(where: { $0.status == .inProgress }) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 7, height: 7)
                    Text("EXECUTING: \(active.title)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text("LIVE EXECUTION CONSOLE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Console Filter
                Picker("", selection: $consoleFilter) {
                    ForEach(ConsoleFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                // Auto-scroll toggle
                Button(action: { autoScrollConsole.toggle() }) {
                    Image(systemName: autoScrollConsole ? "arrow.down.to.line.circle.fill" : "arrow.down.to.line.circle")
                        .font(.system(size: 12))
                        .foregroundColor(autoScrollConsole ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle auto-scrolling to bottom on new output")

                // Copy console logs
                Button(action: copyConsoleOutput) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy console output to clipboard")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))

            Divider()

            // Monospace Output Console
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        let events = filteredConsoleEvents
                        if events.isEmpty {
                            Text("// Ready for execution. Real-time logs and tool traces will stream here.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(12)
                        } else {
                            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                                consoleEventRow(event: event)
                                    .id(event.id)
                            }
                        }

                        // Bottom anchor for auto-scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("console_bottom")
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.85))
                .onChange(of: agent.timeline.count) { _ in
                    if autoScrollConsole {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("console_bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func consoleEventRow(event: TimelineEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(formattedTime(event.timestamp))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
                .frame(width: 58, alignment: .leading)

            // Event Type Tag
            Text(eventTag(for: event.type))
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(eventTagBackground(for: event.type))
                .foregroundColor(eventTagForeground(for: event.type))
                .cornerRadius(3)

            // Message text
            Text(event.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }

    // MARK: - 6. Timeline Sidebar (Chronological Audit Log)
    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Sidebar Header
            HStack {
                Text("ACTIVITY & CHECKPOINTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer()

                // Filter Menu
                Picker("", selection: $timelineFilter) {
                    ForEach(TimelineEventFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))

            Divider()

            // Checkpoints Section Header / Banner
            if let task = agent.currentTask, !task.checkpoints.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.primary)
                        Text("\(task.checkpoints.count) Checkpoints Saved")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary)

                        Spacer()

                        Button(action: { isCheckpointsExpanded.toggle() }) {
                            Image(systemName: isCheckpointsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if isCheckpointsExpanded {
                        ForEach(task.checkpoints.suffix(4).reversed(), id: \.id) { cp in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Snapshot \(String(cp.id.prefix(8)))")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.primary)
                                    Text("\(formattedTime(cp.timestamp)) · \(cp.filesModified.count) files")
                                        .font(.system(size: 9.5))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button("Restore") {
                                    checkpointToRestore = cp
                                    showRestoreConfirmation = true
                                }
                                .font(.system(size: 10, weight: .medium))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            .padding(6)
                            .background(Color.secondary.opacity(0.06))
                            .cornerRadius(4)
                        }
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.05))

                Divider()
            }

            // Chronological Audit Events List
            ScrollView {
                LazyVStack(spacing: 8) {
                    let filtered = filteredTimelineEvents
                    if filtered.isEmpty {
                        Text("No events recorded yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 20)
                    } else {
                        ForEach(filtered) { event in
                            timelineEventRow(event: event)
                        }
                    }
                }
                .padding(10)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func timelineEventRow(event: TimelineEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Icon
            timelineIcon(for: event.type)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(formattedTime(event.timestamp))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    if let subtaskId = event.subtaskId {
                        Text(subtaskId)
                            .font(.system(size: 8.5, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1))
                            .foregroundColor(.secondary)
                            .cornerRadius(2)
                    }
                }

                Text(event.message)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(6)
    }

    // MARK: - 7. Empty State / Task Initiation View
    private var emptyTaskStateView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 20)

                // Hero Icon
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 40))
                    .foregroundColor(.primary)

                VStack(spacing: 6) {
                    Text("Plan a Long-Horizon Engineering Task")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)

                    Text("Describe a complex multi-hour task. The agent decomposes it into an ordered plan,\nexecutes subtasks sequentially with tool verification, and maintains safe checkpoints.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                // Prompt Input Box
                VStack(alignment: .leading, spacing: 8) {
                    Text("TASK DESCRIPTION")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    TextEditor(text: $taskPrompt)
                        .font(.system(size: 12.5))
                        .frame(height: 120)
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )

                    // Quick Template Chips
                    HStack(spacing: 6) {
                        Text("Templates:")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)

                        templateChip(title: "Full Unit Test Suite", prompt: "Write comprehensive unit tests for all services and models in this project with 80%+ coverage.")
                        templateChip(title: "Architecture Refactoring", prompt: "Refactor backend API client models to clean async/await Swift concurrency and error handling.")
                        templateChip(title: "Fix LSP Diagnostics", prompt: "Inspect LSP diagnostic errors across the workspace, analyze root causes, and apply fixes.")
                    }

                    // Start Button
                    HStack {
                        Spacer()
                        Button(action: { startNewTask() }) {
                            HStack(spacing: 6) {
                                if isStartingTask {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else {
                                    Image(systemName: "play.fill")
                                }
                                Text(isStartingTask ? "Planning Subtasks..." : "Start Long-Horizon Task")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.primary)
                        .disabled(taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStartingTask)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: 580)
                .padding(16)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )

                Spacer().frame(height: 30)
            }
            .padding(20)
        }
    }

    private func templateChip(title: String, prompt: String) -> some View {
        Button(action: {
            taskPrompt = prompt
        }) {
            Text(title)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .foregroundColor(.primary)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 8. Dedicated Checkpoint Manager View (Tab 3)
    private var checkpointManagerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CHECKPOINT INVENTORY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer()

                Button("Create Checkpoint Now") {
                    saveManualCheckpoint()
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Divider()

            if let task = agent.currentTask, !task.checkpoints.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(task.checkpoints.reversed(), id: \.id) { cp in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "bookmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.primary)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Checkpoint ID: \(cp.id)")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.primary)

                                        Spacer()

                                        Text(formattedDate(cp.timestamp))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    if let subId = cp.subtaskId {
                                        Text("Subtask: \(subId)")
                                            .font(.caption2.monospaced())
                                            .foregroundColor(.secondary)
                                    }

                                    Text("\(cp.filesModified.count) files modified at snapshot")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    if !cp.filesModified.isEmpty {
                                        HStack(spacing: 4) {
                                            ForEach(cp.filesModified.prefix(3), id: \.self) { f in
                                                Text(URL(fileURLWithPath: f).lastPathComponent)
                                                    .font(.system(size: 9.5, design: .monospaced))
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.secondary.opacity(0.1))
                                                    .cornerRadius(3)
                                            }
                                            if cp.filesModified.count > 3 {
                                                Text("+\(cp.filesModified.count - 3) more")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }

                                Spacer()

                                Button("Restore") {
                                    checkpointToRestore = cp
                                    showRestoreConfirmation = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.primary)
                                .controlSize(.small)
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.06))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No checkpoints recorded for this task.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - 9. Dedicated Chronological Audit View (Tab 2)
    private var chronologicalTimelineView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CHRONOLOGICAL EXECUTION AUDIT")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(agent.timeline.count) Total Events")
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(agent.timeline) { event in
                        HStack(alignment: .top, spacing: 10) {
                            timelineIcon(for: event.type)
                                .frame(width: 18, height: 18)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(formattedDate(event.timestamp))
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(.secondary)

                                    Text("[\(event.type.rawValue)]")
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(eventTagForeground(for: event.type))

                                    Spacer()

                                    if let subId = event.subtaskId {
                                        Text(subId)
                                            .font(.system(size: 9.5, design: .monospaced))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.1))
                                            .cornerRadius(3)
                                    }
                                }

                                Text(event.message)
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(6)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Actions & Event Handlers

    private func startNewTask() {
        let trimmed = taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isStartingTask = true
        let root = appState.workspaceFolder?.path ?? FileManager.default.currentDirectoryPath

        Task { @MainActor in
            do {
                try await agent.startTask(description: trimmed, projectPath: root)
                isStartingTask = false
                taskPrompt = ""
            } catch {
                isStartingTask = false
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func restore(from checkpoint: Checkpoint) {
        Task { @MainActor in
            do {
                try await agent.resume(from: checkpoint)
            } catch {
                errorMessage = "Failed to restore checkpoint: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }

    private func saveManualCheckpoint() {
        isSavingCheckpoint = true
        Task { @MainActor in
            do {
                _ = try await agent.checkpoint()
                isSavingCheckpoint = false
            } catch {
                isSavingCheckpoint = false
                errorMessage = "Failed to save checkpoint: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }

    private func copyConsoleOutput() {
        let logs = agent.timeline.map { "[\(formattedTime($0.timestamp))] [\($0.type.rawValue)] \($0.message)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logs, forType: .string)

        withAnimation {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }

    // MARK: - Computed Properties & Helpers

    private var completedSubtasksCount: Int {
        agent.subtasks.filter { $0.status == .completed || $0.status == .skipped }.count
    }

    private func filesModifiedCount(for subtask: Subtask) -> Int {
        if let task = agent.currentTask {
            let matching = task.checkpoints.filter { $0.subtaskId == subtask.id }
            if let last = matching.last {
                return last.filesModified.count
            }
        }
        return 0
    }

    private func filesModified(for subtask: Subtask) -> [String] {
        if let task = agent.currentTask {
            let matching = task.checkpoints.filter { $0.subtaskId == subtask.id }
            if let last = matching.last {
                return last.filesModified
            }
        }
        return []
    }

    private var filteredTimelineEvents: [TimelineEvent] {
        switch timelineFilter {
        case .all:
            return agent.timeline
        case .subtasks:
            return agent.timeline.filter { $0.type == .subtaskStarted || $0.type == .subtaskCompleted }
        case .checkpoints:
            return agent.timeline.filter { $0.type == .checkpoint }
        case .errors:
            return agent.timeline.filter { $0.type == .error }
        case .user:
            return agent.timeline.filter { $0.type == .userInput }
        }
    }

    private var filteredConsoleEvents: [TimelineEvent] {
        switch consoleFilter {
        case .all:
            return agent.timeline
        case .tools:
            return agent.timeline.filter { $0.message.contains("Result of") || $0.message.contains("Started subtask") }
        case .results:
            return agent.timeline.filter { $0.type == .subtaskCompleted || $0.type == .error }
        }
    }

    // MARK: - Status Badge & Icon Helpers

    @ViewBuilder
    private func taskStatusBadge(for status: HorizonTaskStatus) -> some View {
        switch status {
        case .inProgress:
            HStack(spacing: 4) {
                Circle().fill(Color.blue).frame(width: 6, height: 6)
                Text("RUNNING").font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.blue.opacity(0.15)).foregroundColor(.blue).cornerRadius(4)

        case .completed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                Text("COMPLETED").font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.green.opacity(0.15)).foregroundColor(.green).cornerRadius(4)

        case .paused:
            HStack(spacing: 4) {
                Image(systemName: "pause.fill").font(.system(size: 8))
                Text("PAUSED").font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.2)).foregroundColor(.secondary).cornerRadius(4)

        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                Text("FAILED").font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.red.opacity(0.15)).foregroundColor(.red).cornerRadius(4)

        case .cancelled:
            HStack(spacing: 4) {
                Text("CANCELLED").font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15)).foregroundColor(.secondary).cornerRadius(4)

        case .pending:
            HStack(spacing: 4) {
                Text("PENDING").font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15)).foregroundColor(.secondary).cornerRadius(4)
        }
    }

    @ViewBuilder
    private func subtaskStatusIcon(for status: Subtask.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

        case .inProgress:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.blue)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)

        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.red)

        case .skipped:
            Image(systemName: "forward.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func timelineIcon(for type: TimelineEvent.EventType) -> some View {
        switch type {
        case .subtaskStarted:
            Image(systemName: "play.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(.blue)
        case .subtaskCompleted:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(.green)
        case .checkpoint:
            Image(systemName: "bookmark.fill")
                .font(.system(size: 12))
                .foregroundColor(.primary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
        case .userInput:
            Image(systemName: "person.fill")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private func eventTag(for type: TimelineEvent.EventType) -> String {
        switch type {
        case .subtaskStarted: return "START"
        case .subtaskCompleted: return "DONE"
        case .checkpoint: return "CHECKPOINT"
        case .error: return "ERROR"
        case .userInput: return "USER"
        }
    }

    private func eventTagBackground(for type: TimelineEvent.EventType) -> Color {
        switch type {
        case .subtaskStarted: return Color.blue.opacity(0.15)
        case .subtaskCompleted: return Color.green.opacity(0.15)
        case .checkpoint: return Color.primary.opacity(0.12)
        case .error: return Color.red.opacity(0.15)
        case .userInput: return Color.secondary.opacity(0.15)
        }
    }

    private func eventTagForeground(for type: TimelineEvent.EventType) -> Color {
        switch type {
        case .subtaskStarted: return .blue
        case .subtaskCompleted: return .green
        case .checkpoint: return .primary
        case .error: return .red
        case .userInput: return .secondary
        }
    }

    // MARK: - Date & Duration Formatters

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total < 60 {
            return "\(total)s"
        } else if total < 3600 {
            let mins = total / 60
            let secs = total % 60
            return "\(mins)m \(secs)s"
        } else {
            let hours = total / 3600
            let mins = (total % 3600) / 60
            return "\(hours)h \(mins)m"
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func relativeTimeString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
