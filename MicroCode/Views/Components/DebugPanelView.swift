// Copyright © 2025 Dotmini Software. All rights reserved.

import Foundation
import SwiftUI
import Combine
import AppKit
import ObjectiveC

// MARK: - Severity Enum

public enum ErrorSeverity: String, CaseIterable, Identifiable {
    case error = "Error"
    case warning = "Warning"
    case info = "Info"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .error:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }
    
    public var color: Color {
        switch self {
        case .error:
            return .red
        case .warning:
            return .yellow
        case .info:
            return .blue
        }
    }
    
    public var backgroundColor: Color {
        switch self {
        case .error:
            return Color.red.opacity(0.15)
        case .warning:
            return Color.yellow.opacity(0.15)
        case .info:
            return Color.blue.opacity(0.15)
        }
    }
    
    public var borderColor: Color {
        switch self {
        case .error:
            return Color.red.opacity(0.3)
        case .warning:
            return Color.yellow.opacity(0.3)
        case .info:
            return Color.blue.opacity(0.3)
        }
    }
}

// MARK: - Severity Filter

public enum SeverityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case error = "Errors"
    case warning = "Warnings"
    case info = "Info"
    
    public var id: String { rawValue }
    
    public var iconName: String? {
        switch self {
        case .all:
            return "line.3.horizontal.decrease.circle"
        case .error:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }
}

// MARK: - RuntimeError & SuggestedFix Extensions

extension RuntimeError {
    public var filePath: String? {
        if let userFrame = stackTrace.first(where: { $0.isUserCode && $0.filePath != nil && !($0.filePath?.isEmpty ?? true) }) {
            return userFrame.filePath
        }
        return stackTrace.first(where: { $0.filePath != nil && !($0.filePath?.isEmpty ?? true) })?.filePath
    }
    
    public var line: Int? {
        if let userFrame = stackTrace.first(where: { $0.isUserCode && $0.lineNumber != nil }) {
            return userFrame.lineNumber
        }
        return stackTrace.first(where: { $0.lineNumber != nil })?.lineNumber
    }
    
    public var column: Int? {
        if let userFrame = stackTrace.first(where: { $0.isUserCode && $0.columnNumber != nil }) {
            return userFrame.columnNumber
        }
        return stackTrace.first(where: { $0.columnNumber != nil })?.columnNumber
    }
    
    public var severity: ErrorSeverity {
        let lowerType = errorType.lowercased()
        let lowerMsg = message.lowercased()
        if lowerType.contains("warning") || lowerMsg.contains("warning") || lowerType.contains("warn") {
            return .warning
        } else if lowerType.contains("info") || lowerType.contains("notice") || lowerType.contains("debug") || lowerMsg.contains("info:") {
            return .info
        } else {
            return .error
        }
    }
}

extension SuggestedFix {
    public var originalCode: String { oldCode }
    public var fixedCode: String { newCode }
    public var explanation: String { description }
}

private var isMonitoringKey: UInt8 = 0

extension DebugService {
    public var activeErrors: [RuntimeError] {
        get {
            errors.filter { $0.status != .dismissed }
        }
        set {
            errors = newValue
        }
    }
    
    public var isMonitoring: Bool {
        get {
            (objc_getAssociatedObject(self, &isMonitoringKey) as? Bool) ?? true
        }
        set {
            objectWillChange.send()
            objc_setAssociatedObject(self, &isMonitoringKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

// MARK: - DebugPanelView

public struct DebugPanelView: View {
    @ObservedObject var debugService: DebugService
    @EnvironmentObject var appState: AppState
    
    @State private var selectedFilter: SeverityFilter = .all
    @State private var expandedErrorIds: Set<UUID> = []
    @State private var autoFixEnabled: Bool = false
    @State private var searchQuery: String = ""
    @State private var copiedErrorId: UUID? = nil
    
    init(debugService: DebugService) {
        self.debugService = debugService
    }
    
    private var filteredErrors: [RuntimeError] {
        let baseList = debugService.activeErrors
        let severityFiltered: [RuntimeError]
        switch selectedFilter {
        case .all:
            severityFiltered = baseList
        case .error:
            severityFiltered = baseList.filter { $0.severity == .error }
        case .warning:
            severityFiltered = baseList.filter { $0.severity == .warning }
        case .info:
            severityFiltered = baseList.filter { $0.severity == .info }
        }
        
        let trimmedSearch = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmedSearch.isEmpty {
            return severityFiltered
        } else {
            return severityFiltered.filter { error in
                error.errorType.lowercased().contains(trimmedSearch) ||
                error.message.lowercased().contains(trimmedSearch) ||
                (error.filePath?.lowercased().contains(trimmedSearch) ?? false) ||
                error.language.lowercased().contains(trimmedSearch)
            }
        }
    }
    
    private var errorCount: Int {
        debugService.activeErrors.filter { $0.severity == .error }.count
    }
    
    private var warningCount: Int {
        debugService.activeErrors.filter { $0.severity == .warning }.count
    }
    
    private var infoCount: Int {
        debugService.activeErrors.filter { $0.severity == .info }.count
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            toolbarView
            
            Divider()
            
            if filteredErrors.isEmpty {
                emptyStateView
            } else {
                errorListView
            }
        }
        .background(Color.black.opacity(0.3))
        .onChange(of: debugService.errors) { _ in
            if autoFixEnabled {
                triggerAutoFixIfNeeded()
            }
        }
    }
    
    // MARK: - Toolbar
    
    private var toolbarView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                // Title and Monitoring Status
                HStack(spacing: 6) {
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Debugger")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    
                    // Monitoring indicator
                    Button(action: {
                        debugService.isMonitoring.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(debugService.isMonitoring ? Color.green : Color.secondary)
                                .frame(width: 7, height: 7)
                            
                            Text(debugService.isMonitoring ? "Monitoring" : "Paused")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help(debugService.isMonitoring ? "Console output monitoring is active (click to pause)" : "Monitoring paused (click to resume)")
                }
                
                Spacer()
                
                // Auto-Fix Toggle
                Button(action: {
                    autoFixEnabled.toggle()
                    if autoFixEnabled {
                        triggerAutoFixIfNeeded()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 11))
                        Text("Auto-Fix")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(autoFixEnabled ? Color.primary.opacity(0.18) : Color.primary.opacity(0.06))
                    .foregroundColor(autoFixEnabled ? .primary : .secondary)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Automatically apply high-confidence AI fixes to runtime errors")
                
                // Clear All Button
                Button(action: {
                    withAnimation {
                        debugService.clearAll()
                        expandedErrorIds.removeAll()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("Clear All")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .foregroundColor(debugService.activeErrors.isEmpty ? .secondary.opacity(0.5) : .primary)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(debugService.activeErrors.isEmpty)
                .help("Clear all detected runtime errors")
            }
            
            // Filter Pills & Search Bar
            HStack(spacing: 8) {
                // Filter chips
                HStack(spacing: 4) {
                    filterChip(for: .all, count: debugService.activeErrors.count, icon: "list.bullet")
                    filterChip(for: .error, count: errorCount, icon: ErrorSeverity.error.iconName, tintColor: ErrorSeverity.error.color)
                    filterChip(for: .warning, count: warningCount, icon: ErrorSeverity.warning.iconName, tintColor: ErrorSeverity.warning.color)
                    filterChip(for: .info, count: infoCount, icon: ErrorSeverity.info.iconName, tintColor: ErrorSeverity.info.color)
                }
                
                Spacer()
                
                // Search box
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    TextField("Filter errors...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    
                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(5)
                .frame(maxWidth: 180)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.15))
    }
    
    private func filterChip(for filter: SeverityFilter, count: Int, icon: String, tintColor: Color? = nil) -> some View {
        let isSelected = selectedFilter == filter
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedFilter = filter
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(tintColor ?? (isSelected ? .primary : .secondary))
                
                Text(filter.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.primary.opacity(0.2) : Color.primary.opacity(0.08))
                    .cornerRadius(8)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.primary.opacity(0.12) : Color.clear)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            
            if debugService.activeErrors.isEmpty {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.8))
                
                Text("No Runtime Errors Detected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(debugService.isMonitoring ? "Console output is actively being monitored for exceptions, panics, and traces." : "Console monitoring is paused. Click 'Paused' in the toolbar to resume.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            } else {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                
                Text("No matching issues found")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Try adjusting your severity filter or search query.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Button("Reset Filters") {
                    selectedFilter = .all
                    searchQuery = ""
                }
                .font(.system(size: 11))
                .buttonStyle(.link)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
    
    // MARK: - Error List
    
    private var errorListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredErrors) { error in
                    errorRow(error: error)
                        .id(error.id)
                }
            }
            .padding(10)
        }
    }
    
    // MARK: - Error Row
    
    private func errorRow(error: RuntimeError) -> some View {
        let isExpanded = expandedErrorIds.contains(error.id)
        let severity = error.severity
        
        return VStack(alignment: .leading, spacing: 0) {
            // Row Header (Clickable to toggle expansion)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedErrorIds.remove(error.id)
                    } else {
                        expandedErrorIds.insert(error.id)
                        debugService.currentError = error
                    }
                }
            }) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        // Severity Icon
                        Image(systemName: severity.iconName)
                            .font(.system(size: 13))
                            .foregroundColor(severity.color)
                        
                        // Error Type Badge
                        Text(error.errorType)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.1))
                            .cornerRadius(4)
                        
                        // Language Badge
                        Text(error.language)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(3)
                        
                        // Error Status
                        statusBadge(for: error.status)
                        
                        Spacer()
                        
                        // Timestamp
                        Text(timeString(from: error.timestamp))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        // Row Actions
                        HStack(spacing: 6) {
                            // Copy button
                            Button(action: {
                                copyErrorDetails(error)
                            }) {
                                Image(systemName: copiedErrorId == error.id ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(copiedErrorId == error.id ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Copy error details to clipboard")
                            
                            // AI Analyze action button
                            if error.status == .new {
                                Button(action: {
                                    Task {
                                        await debugService.analyzeError(error)
                                    }
                                }) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11))
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(.plain)
                                .help("Analyze with AI")
                            }
                            
                            // Dismiss button
                            Button(action: {
                                withAnimation {
                                    debugService.dismissError(error)
                                    expandedErrorIds.remove(error.id)
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Dismiss error")
                            
                            // Expand/Collapse Chevron
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Message
                    Text(error.message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // File path + Line number (Clickable)
                    if let path = error.filePath {
                        Button(action: {
                            openFileLocation(path: path, line: error.line)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                
                                SyntaxHighlightedPathView(
                                    filePath: path,
                                    lineNumber: error.line,
                                    columnNumber: error.column
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Click to open file in editor")
                    }
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expandable Detail
            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)
                
                VStack(alignment: .leading, spacing: 12) {
                    // AI Analysis Section
                    aiAnalysisSection(for: error)
                    
                    // Suggested Fix Card
                    if let fix = error.suggestedFix {
                        SuggestedFixCard(
                            fix: fix,
                            onApply: {
                                applySuggestedFix(fix, for: error)
                            },
                            onReject: {
                                rejectSuggestedFix(for: error)
                            }
                        )
                    }
                    
                    // Stack Trace View
                    if !error.stackTrace.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Stack Trace (\(error.stackTrace.count) frames)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            StackTraceView(frames: error.stackTrace) { frame in
                                if let path = frame.filePath {
                                    openFileLocation(path: path, line: frame.lineNumber)
                                }
                            }
                        }
                    }
                    
                    // Raw Output Disclosure
                    if !error.rawOutput.isEmpty {
                        DisclosureGroup {
                            ScrollView(.horizontal, showsIndicators: true) {
                                Text(error.rawOutput)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(8)
                                    .textSelection(.enabled)
                            }
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(5)
                        } label: {
                            Text("Raw Console Output")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
            }
        }
        .background(severity.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(severity.borderColor, lineWidth: 1)
        )
        .cornerRadius(6)
    }
    
    // MARK: - AI Analysis Section
    
    @ViewBuilder
    private func aiAnalysisSection(for error: RuntimeError) -> some View {
        if error.status == .analyzing {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("AI is diagnosing root cause and formulating a fix...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(5)
        } else if let explanation = error.aiExplanation, !explanation.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                    Text("AI Diagnosis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
                
                Text(explanation)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        } else {
            HStack {
                Button(action: {
                    Task {
                        await debugService.analyzeError(error)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                        Text("Analyze Root Cause with AI")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.1))
                    .foregroundColor(.primary)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
        }
    }
    
    // MARK: - Status Badge
    
    private func statusBadge(for status: ErrorStatus) -> some View {
        HStack(spacing: 3) {
            switch status {
            case .new:
                Text("NEW")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            case .analyzing:
                ProgressView().scaleEffect(0.5)
                Text("ANALYZING")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            case .explained:
                Image(systemName: "sparkles")
                    .font(.system(size: 8))
                Text("DIAGNOSED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.primary)
            case .fixed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.green)
                Text("FIXED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.green)
            case .dismissed:
                Text("DISMISSED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Color.primary.opacity(0.06))
        .cornerRadius(3)
    }
    
    // MARK: - Actions
    
    private func openFileLocation(path: String, line: Int?) {
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        
        PreviewDockService.shared.openFile(url: url, makeActive: true)
        Task { @MainActor in
            await appState.loadFile(url: url)
        }
    }
    
    private func copyErrorDetails(_ error: RuntimeError) {
        let text = """
        [\(error.severity.rawValue.uppercased())] \(error.errorType): \(error.message)
        Language: \(error.language)
        Location: \(error.filePath ?? "unknown"):\(error.line ?? 0)
        
        Stack Trace:
        \(error.stackTrace.map { "  at \($0.functionName) (\($0.filePath ?? "?"):\($0.lineNumber ?? 0))" }.joined(separator: "\n"))
        
        Raw Output:
        \(error.rawOutput)
        """
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        copiedErrorId = error.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedErrorId == error.id {
                copiedErrorId = nil
            }
        }
    }
    
    private func applySuggestedFix(_ fix: SuggestedFix, for error: RuntimeError) {
        Task { @MainActor in
            await debugService.applyFix(fix)
            
            // Apply code modification to local file on disk if available
            let path = fix.filePath
            if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                do {
                    let originalText = try String(contentsOfFile: path, encoding: .utf8)
                    let updatedText: String
                    if !fix.oldCode.isEmpty && originalText.contains(fix.oldCode) {
                        updatedText = originalText.replacingOccurrences(of: fix.oldCode, with: fix.newCode)
                    } else {
                        updatedText = fix.newCode
                    }
                    try updatedText.write(toFile: path, atomically: true, encoding: .utf8)
                    
                    // Synchronize in-memory representation in AppState
                    if let index = appState.openFiles.firstIndex(where: { $0.path == path }) {
                        appState.openFiles[index].content = updatedText
                    }
                    if appState.currentFile?.path == path {
                        appState.currentFile?.content = updatedText
                    }
                } catch {
                    print("Failed to persist fix to \(path): \(error)")
                }
            }
            
            // Mark error status as fixed
            if let idx = debugService.errors.firstIndex(where: { $0.id == error.id }) {
                debugService.errors[idx].status = .fixed
            }
            if debugService.currentError?.id == error.id {
                debugService.currentError?.status = .fixed
            }
        }
    }
    
    private func rejectSuggestedFix(for error: RuntimeError) {
        if let idx = debugService.errors.firstIndex(where: { $0.id == error.id }) {
            debugService.errors[idx].suggestedFix = nil
        }
        if debugService.currentError?.id == error.id {
            debugService.currentError?.suggestedFix = nil
        }
    }
    
    private func triggerAutoFixIfNeeded() {
        for error in debugService.activeErrors {
            if let fix = error.suggestedFix, fix.confidence >= 0.85, error.status != .fixed {
                applySuggestedFix(fix, for: error)
            }
        }
    }
    
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - StackTraceView

public struct StackTraceView: View {
    let frames: [StackFrame]
    var onSelectFrame: ((StackFrame) -> Void)? = nil
    
    @State private var filterUserCodeOnly: Bool = false
    @State private var hoveredFrameId: UUID? = nil
    
    init(frames: [StackFrame], onSelectFrame: ((StackFrame) -> Void)? = nil) {
        self.frames = frames
        self.onSelectFrame = onSelectFrame
    }
    
    private var displayedFrames: [StackFrame] {
        if filterUserCodeOnly {
            let userOnly = frames.filter { $0.isUserCode }
            return userOnly.isEmpty ? frames : userOnly
        }
        return frames
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Filter Bar
            HStack {
                Text("\(displayedFrames.count) frame\(displayedFrames.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    filterUserCodeOnly.toggle()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: filterUserCodeOnly ? "person.fill" : "person")
                            .font(.system(size: 9))
                        Text("User Code Only")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(filterUserCodeOnly ? Color.primary.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .foregroundColor(filterUserCodeOnly ? .primary : .secondary)
            }
            .padding(.bottom, 2)
            
            // Frame Rows
            VStack(spacing: 2) {
                ForEach(Array(displayedFrames.enumerated()), id: \.element.id) { index, frame in
                    frameRow(index: index, frame: frame)
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.2))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func frameRow(index: Int, frame: StackFrame) -> some View {
        let isHovered = hoveredFrameId == frame.id
        
        return Button(action: {
            onSelectFrame?(frame)
        }) {
            HStack(alignment: .center, spacing: 6) {
                // Frame number
                Text("#\(index)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 24, alignment: .leading)
                
                // Code scope badge
                Text(frame.isUserCode ? "USER" : "LIB")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(frame.isUserCode ? .primary : .secondary.opacity(0.6))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(frame.isUserCode ? Color.primary.opacity(0.12) : Color.clear)
                    .cornerRadius(2)
                
                // Function name
                Text(frame.functionName)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(frame.isUserCode ? .semibold : .regular)
                    .foregroundColor(frame.isUserCode ? .primary : .secondary)
                    .lineLimit(1)
                
                Spacer()
                
                // File Path and Line
                if let filePath = frame.filePath {
                    SyntaxHighlightedPathView(
                        filePath: filePath,
                        lineNumber: frame.lineNumber,
                        columnNumber: frame.columnNumber
                    )
                } else {
                    Text("<native code>")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(frame.filePath == nil)
        .onHover { hovering in
            hoveredFrameId = hovering ? frame.id : nil
        }
    }
}

// MARK: - SyntaxHighlightedPathView

public struct SyntaxHighlightedPathView: View {
    public let filePath: String
    public let lineNumber: Int?
    public let columnNumber: Int?
    
    public init(filePath: String, lineNumber: Int?, columnNumber: Int?) {
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.columnNumber = columnNumber
    }
    
    private var directoryPath: String {
        let url = URL(fileURLWithPath: filePath)
        let dir = url.deletingLastPathComponent().path
        if dir.isEmpty || dir == "/" {
            return ""
        }
        // Truncate long absolute path for clean display
        let components = dir.split(separator: "/")
        if components.count > 3 {
            return "…/" + components.suffix(2).joined(separator: "/") + "/"
        }
        return dir + "/"
    }
    
    private var fileName: String {
        let url = URL(fileURLWithPath: filePath)
        return url.lastPathComponent.isEmpty ? filePath : url.lastPathComponent
    }
    
    public var body: some View {
        HStack(spacing: 1) {
            if !directoryPath.isEmpty {
                Text(directoryPath)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Text(fileName)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            if let line = lineNumber {
                Text(":\(line)")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            if let col = columnNumber {
                Text(":\(col)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - SuggestedFixCard

public struct SuggestedFixCard: View {
    let fix: SuggestedFix
    public let onApply: () -> Void
    public let onReject: () -> Void
    
    @State private var isApplied: Bool = false
    @State private var isCopied: Bool = false
    
    init(fix: SuggestedFix, onApply: @escaping () -> Void, onReject: @escaping () -> Void) {
        self.fix = fix
        self.onApply = onApply
        self.onReject = onReject
    }
    
    private var confidencePercent: Int {
        Int(min(max(fix.confidence, 0.0), 1.0) * 100)
    }
    
    private var confidenceColor: Color {
        if fix.confidence >= 0.8 {
            return .green
        } else if fix.confidence >= 0.5 {
            return .yellow
        } else {
            return .secondary
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Card Header
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    
                    Text("AI Suggested Fix")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                // Confidence Badge
                HStack(spacing: 3) {
                    Circle()
                        .fill(confidenceColor)
                        .frame(width: 6, height: 6)
                    
                    Text("\(confidencePercent)% confidence")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08))
                .cornerRadius(4)
                
                Spacer()
                
                // Reject Button
                Button(action: onReject) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                        Text("Dismiss")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .foregroundColor(.secondary)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Dismiss suggested fix")
                
                // Apply Button
                Button(action: {
                    withAnimation {
                        isApplied = true
                    }
                    onApply()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isApplied ? "checkmark" : "bolt.fill")
                            .font(.system(size: 10))
                        Text(isApplied ? "Applied" : "Apply Fix")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(isApplied ? Color.green.opacity(0.2) : Color.primary)
                    .foregroundColor(isApplied ? .green : Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(isApplied)
                .help("Apply this change directly to the file")
            }
            
            // Fix Description
            if !fix.description.isEmpty {
                Text(fix.description)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Affected File
            if !fix.filePath.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text(fix.filePath)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Copy Fixed Code
                    Button(action: {
                        copyFixedCode()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9))
                            Text(isCopied ? "Copied" : "Copy Fix")
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .foregroundColor(isCopied ? .green : .secondary)
                        .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Diff Preview Box
            diffPreviewBox
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
    
    // MARK: - Diff Preview Box
    
    private var diffPreviewBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Original Code (Old)
            if !fix.oldCode.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(fix.oldCode.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 6) {
                            Text("-")
                                .font(.system(.caption2, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                            
                            Text(line.isEmpty ? " " : line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.75))
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.15))
                    }
                }
            }
            
            if !fix.oldCode.isEmpty && !fix.newCode.isEmpty {
                Divider()
            }
            
            // Fixed Code (New)
            if !fix.newCode.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(fix.newCode.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 6) {
                            Text("+")
                                .font(.system(.caption2, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            
                            Text(line.isEmpty ? " " : line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.12))
                    }
                }
            }
        }
        .background(Color.black.opacity(0.35))
        .cornerRadius(5)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func copyFixedCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fix.newCode, forType: .string)
        
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }
}
