//
//  TaskLogsView.swift
//  MicroCode
//
//  Professional Agent Task Logs Console for MicroCode.
//  Real-time inspection of AI thoughts, tool executions, subagent orchestration,
//  file changes, and durable audit logs.
//  Strictly Apple HIG Monochrome matching MicroCode native theme engine.
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import SwiftUI
import AppKit

// MARK: - Filter Enums

enum TaskLogCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case tools = "Tools"
    case files = "Files"
    case thinking = "Thinking"
    case errors = "Errors"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "line.3.horizontal.decrease.circle"
        case .tools: return "wrench.and.screwdriver"
        case .files: return "doc.badge.arrow.up"
        case .thinking: return "brain"
        case .errors: return "exclamationmark.triangle"
        }
    }
}

enum TaskLogSource: String, CaseIterable, Identifiable {
    case liveActivity = "Agent Activities"
    case subagents = "SubAgent Processes"
    case diskAudit = "Durable Audit Logs"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .liveActivity: return "bolt.horizontal.fill"
        case .subagents: return "cpu"
        case .diskAudit: return "externaldrive"
        }
    }
}

// MARK: - Task Logs View

struct TaskLogsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var agent = AgentService.shared
    @ObservedObject var subagentHarness = SubAgentHarness.shared
    
    @State private var selectedSource: TaskLogSource = .liveActivity
    @State private var selectedCategory: TaskLogCategory = .all
    @State private var searchQuery: String = ""
    @State private var autoScroll: Bool = true
    @State private var expandedLogIds: Set<UUID> = []
    @State private var showCopiedAlert: Bool = false
    @State private var showClearConfirm: Bool = false
    @State private var selectedSubagentId: String? = nil
    @State private var diskLogText: String = ""
    @State private var isDiskLogLoading: Bool = false
    
    // Theme-Aware Dynamic Backgrounds
    private var windowBg: Color {
        appState.appTheme.isGlass ? Color.clear : Color(nsColor: .windowBackgroundColor)
    }
    
    private var panelBg: Color {
        if appState.appTheme.isGlass {
            return Color.white.opacity(appState.appTheme.isDark ? 0.06 : 0.35)
        }
        return Color(nsColor: .controlBackgroundColor)
    }
    
    private var subtleBorderColor: Color {
        Color.primary.opacity(appState.appTheme.isDark ? 0.12 : 0.08)
    }
    
    // Filtered logs
    private var filteredActivities: [AgentActivity] {
        let base = agent.activityLog
        let categoryFiltered: [AgentActivity]
        switch selectedCategory {
        case .all:
            categoryFiltered = base
        case .tools:
            categoryFiltered = base.filter { $0.type == .tool || ($0.type == .success && $0.message.contains("✓")) }
        case .files:
            categoryFiltered = base.filter { $0.type == .fileChange }
        case .thinking:
            categoryFiltered = base.filter { $0.type == .thinking }
        case .errors:
            categoryFiltered = base.filter { $0.type == .error }
        }
        
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return categoryFiltered
        }
        let q = searchQuery.lowercased()
        return categoryFiltered.filter {
            $0.message.lowercased().contains(q) ||
            ($0.detail?.lowercased().contains(q) ?? false) ||
            ($0.output?.lowercased().contains(q) ?? false)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. Top Source Selector & Telemetry Bar
            topControlBar
            
            Divider().opacity(0.3)
            
            // 2. Secondary Filter & Search Bar
            filterAndSearchBar
            
            Divider().opacity(0.3)
            
            // 3. Main Content
            switch selectedSource {
            case .liveActivity:
                liveActivitiesContent
            case .subagents:
                subagentsContent
            case .diskAudit:
                diskAuditContent
            }
        }
        .background(panelBg)
        .overlay(
            // Toast notification on copy
            Group {
                if showCopiedAlert {
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Logs copied to clipboard")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                        .cornerRadius(20)
                        .overlay(Capsule().stroke(subtleBorderColor, lineWidth: 0.8))
                        .shadow(radius: 6)
                        .padding(.bottom, 20)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        )
    }
    
    // MARK: - Top Control Bar
    
    private var topControlBar: some View {
        HStack(spacing: 8) {
            // Source Segmented Control (Scrollable on narrow viewports)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(TaskLogSource.allCases) { src in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedSource = src
                                if src == .diskAudit { loadDiskLog() }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: src.icon)
                                    .font(.system(size: 9.5))
                                Text(src.rawValue)
                                    .font(.system(size: 10.5, weight: selectedSource == src ? .semibold : .regular))
                                    .lineLimit(1)
                                    .fixedSize()
                                if src == .liveActivity && !agent.activityLog.isEmpty {
                                    Text("\(agent.activityLog.count)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.primary.opacity(selectedSource == src ? 0.15 : 0.08))
                                        .cornerRadius(3)
                                }
                                if src == .subagents && !subagentHarness.activeSubagents.isEmpty {
                                    Text("\(subagentHarness.activeSubagents.count)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.primary.opacity(selectedSource == src ? 0.15 : 0.08))
                                        .cornerRadius(3)
                                }
                            }
                            .foregroundColor(selectedSource == src ? .primary : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedSource == src ? Color.primary.opacity(0.09) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    }
                }
                .padding(2)
            }
            .background(Color.primary.opacity(0.04))
            .cornerRadius(5)
            
            Spacer()
            
            // Phase indicator badge
            HStack(spacing: 5) {
                if agent.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                    Text(agentPhaseLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text("Idle / Completed")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(subtleBorderColor, lineWidth: 0.5))
            
            // Auto-Scroll Toggle
            if selectedSource == .liveActivity {
                Toggle(isOn: $autoScroll) {
                    Text("Auto-Scroll")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .toggleStyle(.checkbox)
                .controlSize(.mini)
            }
            
            // Copy All Button
            Button(action: copyFilteredLogs) {
                HStack(spacing: 3) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9.5))
                    Text("Copy")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Copy currently visible logs to clipboard")
            
            // Export Button
            Button(action: exportLogsToFile) {
                HStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 9.5))
                    Text("Export")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Export task logs to text file")
            
            // Clear Button
            Button(action: { showClearConfirm = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Clear execution activity logs")
            .confirmationDialog("Clear Task Activity Logs?", isPresented: $showClearConfirm) {
                Button("Clear Logs", role: .destructive) {
                    agent.clearActivityLog()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will clear the current in-memory task activity logs. Durable audit logs on disk remain preserved.")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    private var agentPhaseLabel: String {
        switch agent.agentPhase {
        case .idle: return "Ready"
        case .thinking: return "Thinking…"
        case .executing(let tool): return "Executing: \(tool)"
        case .validating: return "Validating…"
        case .done: return "Done"
        }
    }
    
    // MARK: - Secondary Filter & Search Bar
    
    private var filterAndSearchBar: some View {
        HStack(spacing: 8) {
            if selectedSource == .liveActivity {
                // Category Pills (Scrollable on narrow viewports)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(TaskLogCategory.allCases) { cat in
                            let count = countForCategory(cat)
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedCategory = cat
                                }
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 8.5))
                                    Text(cat.rawValue)
                                        .font(.system(size: 9.5, weight: selectedCategory == cat ? .semibold : .regular))
                                        .lineLimit(1)
                                        .fixedSize()
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                            .opacity(0.7)
                                    }
                                }
                                .foregroundColor(selectedCategory == cat ? .primary : .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(selectedCategory == cat ? Color.primary.opacity(0.1) : Color.clear)
                                .cornerRadius(3)
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                        }
                    }
                }
            } else if selectedSource == .subagents {
                Text("SubAgent Domain Specialists & Swarm Instances")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                Text("Local Persistent Daily Log: ~/Documents/MicroCode/Logs/")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Search Input
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                TextField("Filter logs…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5))
                    .frame(width: 140)
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(subtleBorderColor, lineWidth: 0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
    
    private func countForCategory(_ cat: TaskLogCategory) -> Int {
        switch cat {
        case .all: return agent.activityLog.count
        case .tools: return agent.activityLog.filter { $0.type == .tool || ($0.type == .success && $0.message.contains("✓")) }.count
        case .files: return agent.activityLog.filter { $0.type == .fileChange }.count
        case .thinking: return agent.activityLog.filter { $0.type == .thinking }.count
        case .errors: return agent.activityLog.filter { $0.type == .error }.count
        }
    }
    
    // MARK: - Live Activities Content
    
    private var liveActivitiesContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if filteredActivities.isEmpty {
                    emptyLiveActivitiesView
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredActivities) { item in
                            activityRow(item)
                                .id(item.id)
                        }
                    }
                    .padding(10)
                }
            }
            .onChange(of: agent.activityLog.count) { _ in
                if autoScroll, let last = filteredActivities.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private func activityRow(_ item: AgentActivity) -> some View {
        let isExpanded = expandedLogIds.contains(item.id)
        let hasPayload = item.output != nil && !(item.output?.isEmpty ?? true)
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                // Timestamp
                Text(item.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.8))
                    .frame(width: 60, alignment: .leading)
                
                // Category Tag
                HStack(spacing: 3) {
                    Image(systemName: item.type.icon)
                        .font(.system(size: 8))
                    Text(item.type.rawValue.uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                }
                .foregroundColor(item.type.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(item.type.color.opacity(0.12))
                .cornerRadius(3)
                
                // Message Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.message)
                        .font(.system(size: 11, weight: item.type == .error ? .semibold : .regular))
                        .foregroundColor(item.type == .error ? Color(red: 0.92, green: 0.50, blue: 0.50) : .primary)
                        .textSelection(.enabled)
                    
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                            .textSelection(.enabled)
                    }
                }
                
                Spacer()
                
                // Expand / Collapse payload if output exists
                if hasPayload {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if isExpanded {
                                expandedLogIds.remove(item.id)
                            } else {
                                expandedLogIds.insert(item.id)
                            }
                        }
                    }) {
                        HStack(spacing: 2) {
                            Text(isExpanded ? "Hide Output" : "Output")
                                .font(.system(size: 9, weight: .medium))
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.08))
                        .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Expanded Output Box
            if isExpanded, let output = item.output, !output.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Output Payload:")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(output, forType: .string)
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 8))
                                Text("Copy Output")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    ScrollView([.horizontal, .vertical]) {
                        Text(output)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.9))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 160)
                    .background(Color.black.opacity(appState.appTheme.isDark ? 0.35 : 0.08))
                    .cornerRadius(4)
                }
                .padding(.top, 4)
                .padding(.leading, 66)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(item.type == .error ? Color.red.opacity(0.3) : subtleBorderColor, lineWidth: 0.5)
        )
    }
    
    private var emptyLiveActivitiesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.3))
            
            Text("No Task Activities Logged")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("When you ask the AI Agent to execute tasks, search code, edit files, or deploy subagents, real-time activity steps will stream here.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            
            if !searchQuery.isEmpty {
                Button("Clear Search Filter") {
                    searchQuery = ""
                    selectedCategory = .all
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
    
    // MARK: - SubAgents Content
    
    private var subagentsContent: some View {
        HSplitView {
            // Left list of subagents
            VStack(spacing: 0) {
                if subagentHarness.activeSubagents.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 26))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("No SubAgents currently invoked")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(subagentHarness.activeSubagents) { sub in
                                SubAgentCard(
                                    subagent: sub,
                                    isSelected: selectedSubagentId == sub.id,
                                    onKill: { subagentHarness.killSubagent(id: sub.id) },
                                    onInspect: {
                                        selectedSubagentId = (selectedSubagentId == sub.id ? nil : sub.id)
                                    }
                                )
                            }
                        }
                        .padding(10)
                    }
                }
            }
            .frame(minWidth: 260)
            
            // Right detail inspector
            if let subId = selectedSubagentId,
               let sub = subagentHarness.activeSubagents.first(where: { $0.id == subId }) {
                SubAgentDetailInlineView(subagent: sub, onClose: { selectedSubagentId = nil })
                    .frame(minWidth: 320, maxWidth: .infinity)
            } else {
                VStack(spacing: 6) {
                    Text("Select a SubAgent to inspect its execution transcript.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Disk Audit Content
    
    private var diskAuditContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Persistent Disk Log Audit")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Button(action: loadDiskLog) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: openLogsFolder) {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                        Text("Open in Finder")
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.03))
            
            Divider().opacity(0.3)
            
            if isDiskLogLoading {
                VStack {
                    ProgressView("Loading audit log…")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if diskLogText.isEmpty {
                VStack(spacing: 6) {
                    Text("No audit log found for today.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(diskLogText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    private func loadDiskLog() {
        isDiskLogLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            let today = df.string(from: Date())
            
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let logURL = docs.appendingPathComponent("MicroCode/Logs/Log_\(today).txt")
                let content = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                DispatchQueue.main.async {
                    self.diskLogText = content
                    self.isDiskLogLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isDiskLogLoading = false
                }
            }
        }
    }
    
    private func openLogsFolder() {
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let logsDir = docs.appendingPathComponent("MicroCode/Logs")
            NSWorkspace.shared.open(logsDir)
        }
    }
    
    // MARK: - Actions
    
    private func copyFilteredLogs() {
        var lines: [String] = []
        lines.append("=== MicroCode AI Agent Task Logs ===")
        lines.append("Generated: \(Date().formatted())")
        lines.append("Items: \(filteredActivities.count)\n")
        
        for item in filteredActivities {
            let time = item.timestamp.formatted(date: .omitted, time: .standard)
            var line = "[\(time)] [\(item.type.rawValue.uppercased())] \(item.message)"
            if let d = item.detail, !d.isEmpty { line += " | \(d)" }
            if let out = item.output, !out.isEmpty { line += "\n  Output: \(out)" }
            lines.append(line)
        }
        
        let fullText = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullText, forType: .string)
        
        withAnimation {
            showCopiedAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                showCopiedAlert = false
            }
        }
    }
    
    private func exportLogsToFile() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Task Logs"
        savePanel.nameFieldStringValue = "Agent_TaskLogs_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).txt"
        savePanel.allowedContentTypes = [.plainText]
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                var lines: [String] = []
                lines.append("=== MicroCode AI Agent Task Logs ===")
                lines.append("Generated: \(Date().formatted())")
                lines.append("Items: \(self.filteredActivities.count)\n")
                
                for item in self.filteredActivities {
                    let time = item.timestamp.formatted(date: .omitted, time: .standard)
                    var line = "[\(time)] [\(item.type.rawValue.uppercased())] \(item.message)"
                    if let d = item.detail, !d.isEmpty { line += " | \(d)" }
                    if let out = item.output, !out.isEmpty { line += "\n  Output: \(out)" }
                    lines.append(line)
                }
                
                let text = lines.joined(separator: "\n")
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
