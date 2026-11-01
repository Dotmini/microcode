//
//  AIAgentTimelineAndMenus.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2024 Dotmini Company Limited. All rights reserved.
//

import SwiftUI
import Combine
import MicroCodeSupport
import AppKit
import WebKit
import UniformTypeIdentifiers
import PDFKit
import AVKit
import AVFoundation

// MARK: - Chat List Row

struct ChatListRow: View {
    let chat: ChatSession
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.name)
                        .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? .primary : .secondary)
                        .lineLimit(1)
                    
                    Text((chat.messageCount ?? chat.messages.count) == 0 ? "Empty" : "\(chat.messageCount ?? chat.messages.count) messages")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                
                Spacer()
                
                if isHovering {
                    Button(action: onDelete) {
                        Text("Delete")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color.primary.opacity(0.09) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Delete Chat", role: .destructive) {
                onDelete()
            }
        }
    }
}

// MARK: - Antigravity-Style Thinking & Reasoning Block

struct AntigravityThoughtBlockView: View {
    let content: String
    let durationSeconds: Int?
    var isActivelyStreaming: Bool = false
    
    @State private var isExpanded: Bool = false
    @State private var userToggled: Bool = false
    @State private var liveElapsedSeconds: Int = 1
    @State private var liveTimer: Timer? = nil
    
    private var isStreaming: Bool {
        isActivelyStreaming && durationSeconds == nil
    }
    
    private var durationText: String {
        if isStreaming {
            return "Thinking for \(liveElapsedSeconds)s"
        }
        if let d = durationSeconds, d > 0 {
            return "Thought for \(d)s"
        }
        return "Thought for \(max(1, liveElapsedSeconds))s"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // AGY-Style Minimalist Collapsible Thought Header ("Thought for 5s ›")
            Button(action: {
                userToggled = true
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    Text(durationText)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(.secondary.opacity(isStreaming ? 0.88 : 0.78))
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expanded Thought Body
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanContent.isEmpty && isStreaming {
                        Text("Formulating reasoning steps…")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.75))
                            .padding(.vertical, 2)
                    } else {
                        let visibleContent: String = {
                            guard isStreaming, cleanContent.count > 2200 else { return cleanContent }
                            let tail = String(cleanContent.suffix(2200))
                            if let nl = tail.firstIndex(of: "\n") {
                                return "…\n" + String(tail[tail.index(after: nl)...])
                            }
                            return "…" + tail
                        }()
                        let sections = parseThoughtSections(visibleContent)
                        ForEach(sections) { sec in
                            VStack(alignment: .leading, spacing: 4) {
                                if let title = sec.title, !title.isEmpty {
                                    Text(title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.primary.opacity(0.88))
                                }
                                
                                Text(sec.body)
                                    .font(.system(size: 12, design: .default))
                                    .foregroundColor(.secondary.opacity(0.82))
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 4)
                .overlay(
                    HStack {
                        Rectangle()
                            .fill(Color.primary.opacity(0.14))
                            .frame(width: 1.5)
                        Spacer()
                    }
                )
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            if isStreaming {
                startLiveTimer()
            } else {
                if !userToggled { isExpanded = false }
            }
        }
        .onChange(of: isStreaming) { streaming in
            if streaming {
                startLiveTimer()
            } else {
                liveTimer?.invalidate()
                liveTimer = nil
                if !userToggled {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isExpanded = false
                    }
                }
            }
        }
        .onDisappear {
            liveTimer?.invalidate()
            liveTimer = nil
        }
    }
    
    private func startLiveTimer() {
        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                self.liveElapsedSeconds += 1
            }
        }
    }
    
    private struct ThoughtSection: Identifiable {
        let id: Int
        let title: String?
        let body: String
    }
    
    private func parseThoughtSections(_ text: String) -> [ThoughtSection] {
        let paragraphs = text.components(separatedBy: "\n\n")
        var result: [ThoughtSection] = []
        var sectionIndex = 0
        
        for para in paragraphs {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            // Check for markdown bold heading at start: **Title**\nBody or **Title** Body
            if trimmed.hasPrefix("**") {
                let parts = trimmed.components(separatedBy: "**")
                if parts.count >= 3 {
                    let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    let remainingBody = parts.dropFirst(2).joined(separator: "**").trimmingCharacters(in: .whitespacesAndNewlines)
                    result.append(ThoughtSection(id: sectionIndex, title: title, body: remainingBody.isEmpty ? trimmed : remainingBody))
                    sectionIndex += 1
                    continue
                }
            } else if trimmed.hasPrefix("### ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("# ") {
                let lines = trimmed.components(separatedBy: .newlines)
                let title = lines.first?.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
                let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(ThoughtSection(id: sectionIndex, title: title, body: body.isEmpty ? trimmed : body))
                sectionIndex += 1
                continue
            }
            
            result.append(ThoughtSection(id: sectionIndex, title: nil, body: trimmed))
            sectionIndex += 1
        }
        
        return result.isEmpty ? [ThoughtSection(id: 0, title: nil, body: text)] : result
    }
}

// MARK: - Antigravity-Style Live Agent Thinking & Activity Tree

struct AgentThinkingView: View {
    let currentTool: String?
    let phase: AgentPhase
    
    @State private var elapsedSeconds: Int = 1
    @State private var isExpanded: Bool = true
    @State private var dotCount: Int = 1
    @State private var isPulsing: Bool = false
    @State private var rotationAngle: Double = 0
    @State private var elapsedTimer: Timer? = nil
    @State private var dotAnimTimer: Timer? = nil
    
    private var workingText: String {
        let dots = String(repeating: ".", count: dotCount)
        if let tool = currentTool, !tool.isEmpty {
            return "\(tool)\(dots)"
        }
        return "Autonomous agent executing\(dots)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Spinning active gear/ring indicator
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .rotationEffect(.degrees(rotationAngle))
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: rotationAngle)
                
                Text(elapsedSeconds > 0 ? "Agent Working • \(elapsedSeconds)s" : "Agent Working")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                
                // Pulsing live badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                        .opacity(isPulsing ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
                    
                    Text("LIVE")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .cornerRadius(4)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if isExpanded {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                    
                    Text(workingText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(.leading, 4)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .onAppear {
            isPulsing = true
            rotationAngle = 360
            // Start timers ONLY when this view is actually on screen
            elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in elapsedSeconds += 1 }
            }
            dotAnimTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { _ in
                Task { @MainActor in dotCount = (dotCount % 3) + 1 }
            }
        }
        .onDisappear {
            // Kill timers immediately when view leaves the hierarchy
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            dotAnimTimer?.invalidate()
            dotAnimTimer = nil
        }
    }
}

// MARK: - Antigravity (AGY) Minimalist Agent Action Timeline

struct ToolExecutionStepsView: View {
    let results: [ToolResultModel]
    var isStreaming: Bool = false
    @State private var isExpandedOverride: Bool? = nil
    
    private var isExpanded: Bool {
        isExpandedOverride ?? (isStreaming || results.count <= 4)
    }
    
    private var headerTitle: String {
        if let last = results.last {
            let headline = ToolActivityItemRow.summaryHeadline(for: last)
            if !isExpanded && results.count > 1 {
                return "\(headline) · \(results.count) steps"
            }
            return headline
        }
        return isStreaming ? "Working…" : "Completed \(results.count) step\(results.count == 1 ? "" : "s")"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // AGY-Style Clean Borderless Collapsible Header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpandedOverride = !isExpanded
                }
            }) {
                HStack(spacing: 5) {
                    Text(headerTitle)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.88))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.65))
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(results.enumerated()), id: \.element.toolCallId) { _, result in
                        ToolActivityItemRow(result: result)
                    }
                    
                    if isStreaming {
                        Text("Working…")
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(.secondary.opacity(0.75))
                            .padding(.top, 2)
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ToolActivityItemRow: View {
    let result: ToolResultModel
    @State private var showDetails: Bool = false
    @State private var isHoveringFilePill: Bool = false
    
    enum RowStyle {
        case fileAnalyze(fileName: String, lineRange: String?)
        case fileEdit(verb: String, fileName: String, added: Int, removed: Int)
        case commandRun(summary: String, exitNote: String?)
        case generic(verb: String, detail: String)
    }

    @discardableResult
    private func openTargetFileInPreviewDock(fallbackFileName: String? = nil, lineRangeString: String? = nil) -> Bool {
        let params = AgentToolBox.normalizeToolParams(result.toolParams ?? [:])
        var startLine = (params["StartLine"] as? Int) ?? (params["start_line"] as? Int) ?? (params["startLine"] as? Int)
        var endLine = (params["EndLine"] as? Int) ?? (params["end_line"] as? Int) ?? (params["endLine"] as? Int)
        if startLine == nil, let lr = lineRangeString, let parsed = PreviewDockService.parseLineFragment(lr) {
            startLine = parsed.start
            endLine = parsed.end
        }

        let explicitPath = (params["path"] as? String)
            ?? (params["TargetFile"] as? String)
            ?? (params["AbsolutePath"] as? String)
            ?? (params["file_path"] as? String)
            ?? (params["Path"] as? String)
            ?? ((params["paths"] as? [String])?.first)

        if let explicitPath, !explicitPath.isEmpty {
            if PreviewDockService.shared.openFileFromReference(
                explicitPath,
                defaultStartLine: startLine,
                defaultEndLine: endLine
            ) {
                return true
            }
        }

        // Fallback: try extracting full path from output or resolving fallbackFileName in workspace
        if let range = result.output.range(of: #"/[^\s\n:"']+\.[a-zA-Z0-9]+"#, options: .regularExpression) {
            let candidate = String(result.output[range])
            if PreviewDockService.shared.openFileFromReference(
                candidate,
                defaultStartLine: startLine,
                defaultEndLine: endLine
            ) {
                return true
            }
        }

        if let fallbackFileName, !fallbackFileName.isEmpty {
            return PreviewDockService.shared.openFileFromReference(
                fallbackFileName,
                defaultStartLine: startLine,
                defaultEndLine: endLine
            )
        }
        return false
    }
    
    static func summaryHeadline(for result: ToolResultModel) -> String {
        let params = AgentToolBox.normalizeToolParams(result.toolParams ?? [:])
        let targetFile = (params["path"] as? String) ?? (params["TargetFile"] as? String) ?? (params["AbsolutePath"] as? String) ?? (params["file_path"] as? String)
        let fileName = targetFile.map {
            URL(fileURLWithPath: $0).lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: "{}\"'"))
        }
        
        if let summary = (params["toolSummary"] as? String) ?? (params["description"] as? String), !summary.isEmpty {
            return summary
        }
        switch result.toolName {
        case "file_read", "read_file", "view_file", "multi_file_read":
            return "Analyzed \(fileName ?? "source file")"
        case "file_write", "replace_in_file", "multi_replace_in_file", "write_to_file", "patch_file", "apply_patch":
            return "Edited \(fileName ?? "file")"
        case "shell", "run_command":
            if let cmd = (params["command"] as? String) ?? (params["CommandLine"] as? String) {
                let firstLine = cmd.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? cmd
                return "Ran \(String(firstLine.prefix(64)))"
            }
            return "Ran terminal command"
        case "grep_search", "file_search", "find_symbol":
            let q = (params["query"] as? String) ?? (params["pattern"] as? String) ?? (params["symbol"] as? String) ?? "codebase"
            return "Searched \(String(q.prefix(44)))"
        case "list_directory_tree", "list_dir":
            return "Listed \(fileName ?? "workspace")"
        case "preview_control", "ide_browser":
            let action = (params["action"] as? String) ?? "preview"
            return "Previewed \(action)"
        default:
            return "Executed \(result.toolName.replacingOccurrences(of: "_", with: " "))"
        }
    }
    
    private var rowStyle: RowStyle {
        let preview = result.outputPreview
        let params = AgentToolBox.normalizeToolParams(result.toolParams ?? [:])
        var lineInfo: String? = nil
        
        if let startLine = params["StartLine"] as? Int, let endLine = params["EndLine"] as? Int {
            lineInfo = "#L\(startLine)-\(endLine)"
        } else if let lineMatch = preview.range(of: #"#L\d+(-\d+)?"#, options: .regularExpression) {
            lineInfo = String(preview[lineMatch])
        }
        
        let targetFile = (params["path"] as? String) ?? (params["TargetFile"] as? String) ?? (params["AbsolutePath"] as? String) ?? (params["file_path"] as? String)
        let resolvedFileName = (targetFile != nil ? URL(fileURLWithPath: targetFile!).lastPathComponent : extractFileName(preview))?
            .trimmingCharacters(in: CharacterSet(charactersIn: "{}\"'"))
        
        switch result.toolName {
        case "file_read", "read_file", "view_file":
            let name = resolvedFileName ?? "source file"
            let lines = lineInfo ?? (result.outputLineCount > 1 ? "#L1-\(min(350, result.outputLineCount))" : nil)
            return .fileAnalyze(fileName: name, lineRange: lines)
            
        case "multi_file_read":
            if let paths = params["paths"] as? [String], let first = paths.first {
                let name = URL(fileURLWithPath: first).lastPathComponent
                let countStr = paths.count > 1 ? " (+\(paths.count - 1) more)" : ""
                return .fileAnalyze(fileName: "\(name)\(countStr)", lineRange: nil)
            }
            return .fileAnalyze(fileName: "project files", lineRange: nil)
            
        case "file_write", "replace_in_file", "multi_replace_in_file", "write_to_file", "patch_file", "apply_patch":
            let name = resolvedFileName ?? "file"
            let stats = computeDiffLineStats(params: params, output: preview)
            return .fileEdit(verb: "Edited", fileName: name, added: stats.added, removed: stats.removed)
            
        case "shell", "run_command":
            let summaryText: String = {
                if let summary = (params["toolSummary"] as? String) ?? (params["description"] as? String), !summary.isEmpty {
                    return summary.lowercased()
                }
                if let cmd = (params["command"] as? String) ?? (params["CommandLine"] as? String) {
                    let cleanCmd = cmd.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? cmd
                    return String(cleanCmd.prefix(68))
                }
                return "terminal command"
            }()
            let exitNote: String? = result.success ? nil : "Exited with code 1"
            return .commandRun(summary: summaryText, exitNote: exitNote)
            
        case "preview_control", "ide_browser":
            let action = (params["action"] as? String) ?? "open"
            let target = (params["url"] as? String) ?? (params["path"] as? String) ?? "live preview"
            return .generic(verb: "Previewed", detail: "\(target) (\(action))")
            
        case "device_runtime":
            let action = (params["action"] as? String) ?? "run"
            return .generic(verb: "Device", detail: action)
            
        case "grep_search", "file_search", "find_symbol":
            let query = (params["query"] as? String) ?? (params["pattern"] as? String) ?? (params["symbol"] as? String) ?? extractQuery(preview)
            return .generic(verb: "Searched", detail: String(query.prefix(48)))
            
        case "list_directory_tree", "list_dir":
            let dirName = resolvedFileName ?? "workspace"
            return .generic(verb: "Listed", detail: dirName)
            
        case "create_directory":
            let dirName = resolvedFileName ?? "directory"
            return .generic(verb: "Created", detail: dirName)
            
        case "rename_file":
            let oldName = (params["old_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? resolvedFileName ?? "file"
            let newName = (params["new_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
            let detail = newName != nil ? "\(oldName) → \(newName!)" : oldName
            return .generic(verb: "Renamed", detail: detail)
            
        case "delete_file":
            let name = resolvedFileName ?? "file"
            return .generic(verb: "Deleted", detail: name)
            
        case "git_status":
            return .generic(verb: "Inspected", detail: "git status")
            
        case "git_diff":
            return .generic(verb: "Inspected", detail: "git diff")
            
        default:
            let cleanName = result.toolName.replacingOccurrences(of: "_", with: " ")
            return .generic(verb: "Ran", detail: cleanName)
        }
    }
    
    private func computeDiffLineStats(params: [String: Any], output: String) -> (added: Int, removed: Int) {
        let oldStr = (params["old_text"] as? String)
            ?? (params["old_str"] as? String)
            ?? (params["Target"] as? String)
            ?? (params["target"] as? String)
            ?? (params["search"] as? String)
            ?? (params["TargetContent"] as? String)
        let newStr = (params["new_text"] as? String)
            ?? (params["new_str"] as? String)
            ?? (params["Replacement"] as? String)
            ?? (params["replacement"] as? String)
            ?? (params["replace"] as? String)
            ?? (params["ReplacementContent"] as? String)
        
        if let oldStr = oldStr, let newStr = newStr {
            let oldLines = oldStr.isEmpty ? [] : oldStr.components(separatedBy: .newlines)
            let newLines = newStr.isEmpty ? [] : newStr.components(separatedBy: .newlines)
            let oldSet = NSCountedSet(array: oldLines)
            var added = 0
            for line in newLines {
                if oldSet.count(for: line) > 0 {
                    oldSet.remove(line)
                } else {
                    added += 1
                }
            }
            var removed = 0
            for item in oldSet {
                removed += oldSet.count(for: item)
            }
            if added == 0 && removed == 0 && oldStr != newStr {
                return (max(1, newLines.count), max(1, oldLines.count))
            }
            return (added, removed)
        }
        
        if let content = (params["content"] as? String) ?? (params["CodeContent"] as? String) ?? (params["Content"] as? String) {
            let count = max(1, content.components(separatedBy: .newlines).count)
            return (count, 0)
        }
        
        if let match = output.range(of: #"\+(\d+)\s+-(\d+)"#, options: .regularExpression) {
            let sub = String(output[match])
            let nums = sub.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            if nums.count >= 2 {
                return (nums[0], nums[1])
            }
        }
        return (1, 1)
    }
    
    @ViewBuilder
    private func fileTypeBadge(for fileName: String) -> some View {
        ProgrammingLanguageIconView(fileName: fileName, size: 14)
    }
    
    private func extractFileName(_ text: String) -> String? {
        if let range = text.range(of: #"/[^\s\n:{}"']+\.[a-zA-Z0-9]+"#, options: .regularExpression) {
            let path = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)'\"{}"))
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let range = text.range(of: #"/[^\s\n:{}"']+"#, options: .regularExpression) {
            let path = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)'\"{}"))
            let last = URL(fileURLWithPath: path).lastPathComponent
            if !last.isEmpty && last != "/" {
                return last
            }
        }
        return nil
    }
    
    private func extractQuery(_ text: String) -> String {
        if let firstLine = text.components(separatedBy: .newlines).first, !firstLine.isEmpty {
            return String(firstLine.prefix(40))
        }
        return "codebase"
    }
    
    static func extractedScreenshotPaths(from result: ToolResultModel) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        let output = result.output
        let params = result.toolParams ?? [:]
        let wsRoot = AgentToolBox.shared.workspaceRoot ?? AppState.shared?.workspaceFolder?.path
        
        func recordIfValid(_ rawCandidate: String) {
            var cleaned = rawCandidate.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"'()[]<>.,;"))
            if cleaned.hasPrefix("file://") {
                cleaned = String(cleaned.dropFirst("file://".count))
                cleaned = cleaned.removingPercentEncoding ?? cleaned
            }
            guard !cleaned.isEmpty else { return }
            let lower = cleaned.lowercased()
            guard lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".webp") else { return }
            let resolved: String
            if cleaned.hasPrefix("/") {
                resolved = cleaned
            } else if cleaned.hasPrefix("~") {
                resolved = (cleaned as NSString).expandingTildeInPath
            } else if let ws = wsRoot, !ws.isEmpty {
                resolved = (ws as NSString).appendingPathComponent(cleaned)
            } else {
                return
            }
            guard !seen.contains(resolved), FileManager.default.fileExists(atPath: resolved) else { return }
            seen.insert(resolved)
            found.append(resolved)
        }
        
        // 1. Check explicit [SCREENSHOT_PATH: ...] marker
        if let range = output.range(of: #"\[SCREENSHOT_PATH:\s*([^\]]+)\]"#, options: .regularExpression) {
            let sub = String(output[range])
                .replacingOccurrences(of: "[SCREENSHOT_PATH:", with: "")
                .replacingOccurrences(of: "]", with: "")
            recordIfValid(sub)
        }
        
        // 2. Check snapshot saved to ...
        if let range = output.range(of: #"saved to\s+(/[^\s\(\)\n]+\.(?:png|jpg|jpeg|webp))"#, options: .regularExpression) {
            let sub = String(output[range]).replacingOccurrences(of: "saved to", with: "")
            recordIfValid(sub)
        }
        
        // 3. Check tool parameters (output_path / filePath / path for screenshot actions)
        let actionStr = ((params["action"] as? String) ?? (params["operation"] as? String) ?? "").lowercased()
        if actionStr == "screenshot" || actionStr == "snapshot" || result.toolName == "preview_control" || result.toolName == "ide_browser" {
            if let outParam = (params["output_path"] as? String) ?? (params["filePath"] as? String) ?? (params["path"] as? String) {
                recordIfValid(outParam)
            }
        }
        
        // 4. Check shell commands that generated preview_screenshot.png or similar
        if result.toolName == "shell" || result.toolName == "run_command" {
            let cmd = (params["command"] as? String) ?? (params["CommandLine"] as? String) ?? ""
            let combined = cmd + "\n" + output
            if let regex = try? NSRegularExpression(pattern: #"([/\w\-\._~]*(?:screenshot|snapshot|preview_cap|webapp_cap)[/\w\-\._]*\.(?:png|jpg|jpeg|webp))"#, options: [.caseInsensitive]) {
                let ns = combined as NSString
                for match in regex.matches(in: combined, options: [], range: NSRange(location: 0, length: ns.length)) {
                    recordIfValid(ns.substring(with: match.range))
                }
            }
        }
        
        return found
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                switch rowStyle {
                case .fileAnalyze(let fileName, let lineRange):
                    Text("Analyzed")
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.82))
                    
                    Button(action: {
                        if !openTargetFileInPreviewDock(fallbackFileName: fileName, lineRangeString: lineRange) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showDetails.toggle()
                            }
                        }
                    }) {
                        HStack(spacing: 5) {
                            fileTypeBadge(for: fileName)
                            
                            Text(fileName)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(isHoveringFilePill ? .accentColor : .primary.opacity(0.95))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            if let lines = lineRange {
                                Text(lines)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.secondary.opacity(0.72))
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isHoveringFilePill ? Color.primary.opacity(0.09) : Color.primary.opacity(0.035))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringFilePill = hovering
                    }
                    .help("Click to preview \(fileName) in Right Split Pane")
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDetails.toggle()
                        }
                    }) {
                        Image(systemName: showDetails ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.55))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(showDetails ? "Hide inline snippet" : "Show inline snippet")
                    
                case .fileEdit(let verb, let fileName, let added, let removed):
                    Text(verb)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.82))
                    
                    Button(action: {
                        if !openTargetFileInPreviewDock(fallbackFileName: fileName, lineRangeString: nil) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showDetails.toggle()
                            }
                        }
                    }) {
                        HStack(spacing: 5) {
                            fileTypeBadge(for: fileName)
                            
                            Text(fileName)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(isHoveringFilePill ? .accentColor : .primary.opacity(0.95))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isHoveringFilePill ? Color.primary.opacity(0.09) : Color.primary.opacity(0.035))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringFilePill = hovering
                    }
                    .help("Click to preview \(fileName) in Right Split Pane")

                    // Clickable +N -M Diff Badge -> Opens Diff directly in Right Split Pane
                    Button(action: {
                        if let pair = extractedEditDiffPair() {
                            PreviewDockService.shared.openDiff(
                                id: "tooldiff:\(result.toolCallId)",
                                title: fileName,
                                oldContent: pair.old,
                                newContent: pair.new,
                                makeActive: true
                            )
                        } else if !openTargetFileInPreviewDock(fallbackFileName: fileName, lineRangeString: nil) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showDetails.toggle()
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            if added > 0 || removed == 0 {
                                Text("+\(added)")
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.25, green: 0.78, blue: 0.38))
                            }
                            if removed > 0 {
                                Text("-\(removed)")
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.96, green: 0.33, blue: 0.31))
                            }
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Click to inspect Diff for \(fileName) in Right Split Pane")
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDetails.toggle()
                        }
                    }) {
                        Image(systemName: showDetails ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.55))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(showDetails ? "Hide inline diff" : "Show inline diff")
                    
                case .commandRun(let summary, let exitNote):
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDetails.toggle()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text("Ran \(summary)")
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundColor(.secondary.opacity(0.82))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            if let exitNote = exitNote {
                                Text("· \(exitNote)")
                                    .font(.system(size: 12.5, weight: .regular))
                                    .foregroundColor(.secondary.opacity(0.75))
                            }
                            
                            Image(systemName: showDetails ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                case .generic(let verb, let detail):
                    Button(action: {
                        if result.toolName == "preview_control" || result.toolName == "ide_browser" {
                            AppState.shared?.showPreviewInspector(tab: "web")
                        }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDetails.toggle()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text("\(verb) \(detail)")
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundColor(.secondary.opacity(0.82))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            Image(systemName: showDetails ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer(minLength: 0)
            }
            
            if showDetails {
                let theme = AppState.shared?.appTheme ?? .dark
                let detailCanvas = theme.isGlass ? Color.primary.opacity(0.04) : Color(nsColor: theme.editorBackground)
                if let pair = extractedEditDiffPair() {
                    let entry = DiffCacheManager.getOrComputeDiffEntry(
                        id: "inline-tool-diff:\(result.toolCallId)",
                        old: pair.old,
                        new: pair.new
                    )
                    let previewLines = entry.lines.prefix(28)
                    let baseTextColor = Color(nsColor: theme.editorText)
                    let lineNumColor = Color(nsColor: theme.commentColor).opacity(0.75)

                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(previewLines)) { diffLine in
                                if diffLine.type == .hunkHeader {
                                    HStack(spacing: 0) {
                                        Rectangle().fill(Color.cyan.opacity(0.85)).frame(width: 2.5, height: 19)
                                        Text(diffLine.text)
                                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                            .foregroundColor(.cyan.opacity(0.9))
                                            .padding(.horizontal, 10)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(minWidth: entry.minContentWidth, minHeight: 19, maxHeight: 19, alignment: .leading)
                                    .background(Color.cyan.opacity(theme.isDark ? 0.09 : 0.07))
                                } else {
                                    HStack(spacing: 0) {
                                        Rectangle().fill(diffLine.accentColor).frame(width: 2.5, height: 18)
                                        Text(diffLine.gutterNumbers)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(lineNumColor)
                                            .frame(width: 60, alignment: .trailing)
                                            .padding(.trailing, 5)
                                        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 18)
                                        Text(diffLine.prefix)
                                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                            .foregroundColor(diffLine.prefixColor)
                                            .frame(width: 16, alignment: .center)
                                        Text(diffLine.displayText)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(diffLine.type == .deletion ? baseTextColor.opacity(0.76) : baseTextColor)
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .padding(.trailing, 16)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(minWidth: entry.minContentWidth, minHeight: 18, maxHeight: 18, alignment: .leading)
                                    .background(
                                        diffLine.type == .addition ? Color.green.opacity(theme.isDark ? 0.15 : 0.12) :
                                        (diffLine.type == .deletion ? Color.red.opacity(theme.isDark ? 0.14 : 0.10) : Color.clear)
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .background(detailCanvas)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .padding(.leading, 12)
                } else {
                    let rawOutput = result.success ? result.output : (result.error ?? result.output)
                    let trimmedOutput = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(trimmedOutput.isEmpty ? "(Completed)" : String(trimmedOutput.prefix(1500)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(result.success ? Color(nsColor: theme.editorText).opacity(0.8) : .red.opacity(0.85))
                        .lineLimit(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(detailCanvas)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.10), lineWidth: 1))
                        .padding(.leading, 12)
                }
            }
        }
    }

    private func extractedEditDiffPair() -> (old: String, new: String)? {
        let params = AgentToolBox.normalizeToolParams(result.toolParams ?? [:])
        let oldStr = (params["old_str"] as? String)
            ?? (params["Target"] as? String)
            ?? (params["target"] as? String)
            ?? (params["search"] as? String)
            ?? (params["TargetContent"] as? String)
        let newStr = (params["new_str"] as? String)
            ?? (params["Replacement"] as? String)
            ?? (params["replacement"] as? String)
            ?? (params["replace"] as? String)
            ?? (params["ReplacementContent"] as? String)
        if let oldStr, let newStr {
            return (oldStr, newStr)
        }
        if ["file_write", "write_to_file"].contains(result.toolName),
           let content = (params["content"] as? String) ?? (params["CodeContent"] as? String) ?? (params["Content"] as? String) {
            return ("", content)
        }
        return nil
    }
}

// MARK: - Sleek Project Workspace Dropdown (Matching media_1787685893773.png)

struct ProjectWorkspaceSelectorMenu: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var agent = AgentService.shared
    @Binding var isPresented: Bool
    @State private var searchText = ""
    
    private var availableProjects: [(name: String, path: String)] {
        var list: [(name: String, path: String)] = []
        var seen = Set<String>()
        
        if let current = appState.workspaceFolder?.path, !current.isEmpty {
            list.append((URL(fileURLWithPath: current).lastPathComponent, current))
            seen.insert(current)
        }
        
        for g in agent.projectGroups {
            if let p = g.projectPath, !p.isEmpty, !seen.contains(p) {
                list.append((g.projectName, p))
                seen.insert(p)
            }
        }
        
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return list
        } else {
            let q = searchText.lowercased()
            return list.filter { $0.name.lowercased().contains(q) || $0.path.lowercased().contains(q) }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 8)
            .padding(.top, 8)
            
            // Projects List
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(availableProjects, id: \.path) { proj in
                        let isSelected = (appState.workspaceFolder?.path == proj.path)
                        Button(action: {
                            selectProject(proj.path)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text(proj.name)
                                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(.primary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.primary.opacity(0.08) : Color.clear)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
            }
            .frame(maxHeight: 180)
            
            Divider().padding(.horizontal, 4)
            
            // Actions matching user's screenshot
            VStack(alignment: .leading, spacing: 2) {
                Button(action: openNewProjectPicker) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("New Project")
                            .font(.system(size: 11.5))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                
                Button(action: quickStartAction) {
                    let generated = nextQuickStartFolderInfo()
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                        Text("Quick Start")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(generated.name)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(4)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Auto-generate a new project folder (\(nextQuickStartFolderInfo().name)) and start immediately")
                
                Button(action: noProjectAction) {
                    HStack(spacing: 8) {
                        Image(systemName: "slash.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("No Project")
                            .font(.system(size: 11.5))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .frame(width: 250)
        .background(Color(nsColor: appState.appTheme.panelBackground))
    }
    
    private func quickStartParentDirectory() -> URL {
        return WorkspaceStoragePaths.defaultProjectsRootDirectory()
    }
    
    private func nextQuickStartFolderInfo() -> (name: String, url: URL) {
        let parent = quickStartParentDirectory()
        let fm = FileManager.default
        let existingNames = Set(agent.projectGroups.map { $0.projectName.lowercased() })
        
        var index = 1
        while index < 1000 {
            let candidateName = String(format: "QuickStart-%02d", index)
            let candidateURL = parent.appendingPathComponent(candidateName, isDirectory: true)
            if !fm.fileExists(atPath: candidateURL.path) && !existingNames.contains(candidateName.lowercased()) {
                return (candidateName, candidateURL)
            }
            index += 1
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd-HHmmss"
        let fallbackName = "QuickStart-\(formatter.string(from: Date()))"
        return (fallbackName, parent.appendingPathComponent(fallbackName, isDirectory: true))
    }
    
    private func quickStartAction() {
        let info = nextQuickStartFolderInfo()
        do {
            try FileManager.default.createDirectory(at: info.url, withIntermediateDirectories: true)
        } catch {
            print("[QuickStart] Failed to create directory at \(info.url.path): \(error)")
        }
        AppState.recordRecentWorkspace(url: info.url)
        selectProject(info.url.path)
    }
    
    private func selectProject(_ path: String) {
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        Task { @MainActor in
            await appState.openWorkspace(url: url)
            agent.setWorkspace(path)
        }
        isPresented = false
    }
    
    private func openNewProjectPicker() {
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = WorkspaceStoragePaths.defaultProjectsRootDirectory()
            panel.prompt = "Select Project Folder"
            panel.message = "Select an existing folder or create a new project directory"
            
            if panel.runModal() == .OK, let url = panel.url {
                selectProject(url.path)
            }
        }
    }
    
    private func noProjectAction() {
        appState.workspaceFolder = nil
        agent.setWorkspace("")
        isPresented = false
    }
}

// MARK: - SubAgent Selector & Deployment Dropdown Menu

struct SubAgentSelectorMenu: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedType: String
    @Binding var isPresented: Bool
    @ObservedObject private var harness = SubAgentHarness.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Select Agent Mode")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                let activeCount = harness.activeSubagents.filter { $0.state == .running }.count
                if activeCount > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(Color.primary.opacity(0.8)).frame(width: 5, height: 5)
                        Text("\(activeCount) Running")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
                .opacity(0.4)
            
            ScrollView {
                VStack(spacing: 2) {
                    // Main Agent
                    agentOptionRow(
                        type: "main",
                        icon: "bolt.fill",
                        title: "Main Agent",
                        subtitle: "Autonomous orchestrator with multi-agent delegation"
                    )
                    
                    Divider()
                        .opacity(0.3)
                        .padding(.vertical, 4)
                    
                    HStack {
                        Text("MULTI-AGENT TEAMS")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.6))
                        Spacer()
                        Button {
                            isPresented = false
                            harness.showSquadBuilderSheet = true
                        } label: {
                            Text("+ Custom Team")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 2)
                    
                    ForEach(harness.squadPresets) { preset in
                        agentOptionRow(
                            type: "squad:\(preset.id)",
                            icon: preset.icon == "crown.fill" ? "square.stack.3d.up" : preset.icon,
                            title: preset.name.replacingOccurrences(of: "CEO ", with: ""),
                            subtitle: preset.subtitle
                        )
                    }
                    
                    Divider()
                        .opacity(0.3)
                        .padding(.vertical, 4)
                    
                    Text("SPECIALIZED SUBAGENTS")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.top, 2)
                        .padding(.bottom, 2)
                    
                    // Built-in & Registered SubAgents
                    ForEach(Array(harness.registeredDefinitions.values.sorted(by: { $0.name < $1.name }))) { def in
                        agentOptionRow(
                            type: def.name,
                            icon: subagentIcon(def.name),
                            title: def.role,
                            subtitle: def.description
                        )
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 330)
            
            Divider()
                .opacity(0.4)
            
            // Bottom Action Controls
            HStack {
                Button(action: {
                    isPresented = false
                    harness.showSquadBuilderSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10))
                        Text("Customize Squad")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                
                Text("•")
                    .foregroundColor(.secondary.opacity(0.4))
                
                Button(action: {
                    isPresented = false
                    harness.showSubAgentMonitor = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                        Text("Monitor HUD")
                            .font(.system(size: 10.5, weight: .regular))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                if !harness.activeSubagents.filter({ $0.state == .running }).isEmpty {
                    Button(action: {
                        harness.killAllSubagents()
                        isPresented = false
                    }) {
                        Text("Kill All")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.02))
        }
        .frame(width: 300)
        .background(Color(nsColor: appState.appTheme.panelBackground))
    }
    
    @ViewBuilder
    private func agentOptionRow(type: String, icon: String, title: String, subtitle: String) -> some View {
        let isSelected = selectedType == type
        Button(action: {
            selectedType = type
            isPresented = false
        }) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .primary : .secondary.opacity(0.8))
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.primary)
                        }
                    }
                    
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary.opacity(0.85))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.primary.opacity(0.07) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func subagentIcon(_ name: String) -> String {
        switch name {
        case "architect": return "square.stack.3d.up"
        case "frontend_engineer": return "macwindow"
        case "backend_engineer": return "server.rack"
        case "bug_hunter": return "wrench.and.screwdriver"
        case "test_runner": return "checkmark.seal"
        case "security_auditor": return "shield"
        default: return "cube"
        }
    }
}

// MARK: - Agent Target Environment Menu (Local vs Remote SSH / Cloud)

struct AgentTargetEnvironmentMenu: View {
    @ObservedObject private var toolBox = AgentToolBox.shared
    @ObservedObject private var remoteManager = RemoteConnectionManager.shared
    @Binding var showingAddServer: Bool
    
    var body: some View {
        Menu {
            // Local Mac
            Button {
                toolBox.executionTarget = .local
            } label: {
                HStack {
                    Label("Local Mac (Native)", systemImage: "desktopcomputer")
                    if toolBox.executionTarget.isLocal {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            Divider()
            
            // Remote Servers Header
            Text("REMOTE SERVERS / CLOUD")
            
            let servers = remoteManager.servers
            if servers.isEmpty {
                Text("No SSH servers configured")
            } else {
                ForEach(servers) { server in
                    Button {
                        toolBox.executionTarget = .remote(server)
                    } label: {
                        HStack {
                            let labelText = "\(server.name) (\(server.username)@\(server.host))"
                            Label(labelText, systemImage: server.provider.icon)
                            if toolBox.executionTarget.remoteServer?.id == server.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Add/Manage Server
            Button {
                showingAddServer = true
            } label: {
                Label("Add Remote Server...", systemImage: "plus.circle")
            }
        } label: {
            HStack(spacing: 4) {
                if let remote = toolBox.executionTarget.remoteServer {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Image(systemName: remote.provider.icon)
                        .font(.system(size: 9))
                    Text(remote.name)
                        .font(.system(size: 10, weight: .medium))
                } else {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 9))
                    Text("Local")
                        .font(.system(size: 10))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 7))
            }
            .foregroundColor(toolBox.executionTarget.isLocal ? .secondary.opacity(0.85) : .accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(toolBox.executionTarget.isLocal ? Color.clear : Color.accentColor.opacity(0.1))
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Rich Attachment Chip View

struct AttachmentChipView: View {
    let file: AIAttachment
    var onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            // Real Image thumbnail or category icon
            if let image = file.nsImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 24)
                    .cornerRadius(4)
                    .clipped()
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 12))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(3)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Remove attachment")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
    
    private var iconName: String {
        switch file.type {
        case .image: return "photo"
        case .pdf: return "doc.text.fill"
        case .text: return "doc.plaintext"
        }
    }
    
    private var iconColor: Color {
        switch file.type {
        case .image: return .cyan
        case .pdf: return .red.opacity(0.85)
        case .text: return .accentColor
        }
    }
    
    private var subtitle: String {
        switch file.type {
        case .image:
            return "Image • \(file.formattedSize)"
        case .pdf:
            let pages = file.pdfPageCount
            return "PDF • \(pages > 0 ? "\(pages) p • " : "")\(file.formattedSize)"
        case .text:
            return "File • \(file.formattedSize)"
        }
    }
}

// MARK: - Inline Generated Media Renderer (Image, Video, Music/Audio)

@MainActor
final class ChatAudioPlayerController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var loadedURL: URL?
    
    func loadIfNeeded(url: URL) {
        guard loadedURL != url else { return }
        stop()
        loadedURL = url
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player
            duration = max(player.duration, 0.1)
        }
    }
    
    func togglePlay(url: URL) {
        loadIfNeeded(url: url)
        guard let player = audioPlayer else {
            NSWorkspace.shared.open(url)
            return
        }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            player.play()
            isPlaying = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, let p = self.audioPlayer else { return }
                    self.currentTime = p.currentTime
                    if !p.isPlaying {
                        self.isPlaying = false
                        self.timer?.invalidate()
                    }
                }
            }
        }
    }
    
    func seek(to time: Double) {
        audioPlayer?.currentTime = time
        currentTime = time
    }
    
    func stop() {
        audioPlayer?.stop()
        isPlaying = false
        currentTime = 0
        timer?.invalidate()
        timer = nil
    }
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.timer?.invalidate()
        }
    }
}

/// Native AppKit `AVPlayerView` wrapper so `.mp4` / `.mov` videos always render their frames and playback controls reliably inside macOS `ScrollView`.
struct NativeAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

struct ChatMediaBlockView: View {
    let kind: GeneratedMediaKind
    let title: String
    let target: String
    
    @StateObject private var audioController = ChatAudioPlayerController()
    @State private var videoPlayer: AVPlayer? = nil
    @State private var copiedFeedback: Bool = false
    
    private var resolvedFileURL: URL? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file://") {
            let rawPath = String(trimmed.dropFirst("file://".count))
            let decoded = rawPath.removingPercentEncoding ?? rawPath
            return URL(fileURLWithPath: decoded)
        } else if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        } else if let u = URL(string: trimmed), u.isFileURL {
            return u
        }
        return nil
    }
    
    private var loadedNSImage: NSImage? {
        if let fileURL = resolvedFileURL, let img = NSImage(contentsOf: fileURL) {
            return img
        }
        if target.hasPrefix("data:image/"),
           let commaIdx = target.firstIndex(of: ",") {
            let b64 = String(target[target.index(after: commaIdx)...])
            if let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
               let img = NSImage(data: data) {
                return img
            }
        }
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Formal Monochrome Header Bar
            HStack(spacing: 8) {
                Image(systemName: headerIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(badgeLabel)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07))
                    .foregroundColor(.secondary)
                    .cornerRadius(3)
                
                Text(displaySubtitle)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.82))
                    .lineLimit(1)
                
                Spacer(minLength: 12)
                
                HStack(spacing: 10) {
                    if kind == .image, let img = loadedNSImage {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([img])
                            copiedFeedback = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedFeedback = false
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                                Text(copiedFeedback ? "Copied" : "Copy")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if let fileURL = resolvedFileURL {
                        Button {
                            saveMediaAs(from: fileURL)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Save As")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "folder")
                                Text("Finder")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            NSWorkspace.shared.open(fileURL)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Open")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.primary.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))
            
            Divider().opacity(0.25)
            
            // Media Content Body
            Group {
                switch kind {
                case .image:
                    imageBody
                case .video:
                    videoBody
                case .audio:
                    audioBody
                }
            }
            .padding(10)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .padding(.vertical, 4)
        .onDisappear {
            audioController.stop()
            videoPlayer?.pause()
        }
    }
    
    @ViewBuilder
    private var imageBody: some View {
        if let nsImage = loadedNSImage {
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 500, maxHeight: 400)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .onTapGesture {
                        if let fileURL = resolvedFileURL {
                            NSWorkspace.shared.open(fileURL)
                        }
                    }
                
                HStack(spacing: 8) {
                    Text("\(Int(nsImage.size.width)) × \(Int(nsImage.size.height)) px")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    if let fileURL = resolvedFileURL {
                        Text("· \(fileURL.lastPathComponent)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
                Text(resolvedFileURL?.lastPathComponent ?? target)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }
    
    @ViewBuilder
    private var videoBody: some View {
        if let fileURL = resolvedFileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            VStack(alignment: .leading, spacing: 8) {
                if let player = videoPlayer {
                    NativeAVPlayerView(player: player)
                        .frame(width: 500, height: 282)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 500, height: 282)
                        .overlay(
                            ProgressView()
                                .controlSize(.small)
                        )
                }
                
                HStack(spacing: 12) {
                    Button {
                        if let player = videoPlayer {
                            if player.rate == 0 {
                                player.seek(to: .zero)
                                player.play()
                            } else {
                                player.pause()
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9.5))
                            Text("Play / Replay")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundColor(.primary.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Color.primary.opacity(0.07))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    Text("1280 × 720 px · H.264 MP4 · \(fileURL.lastPathComponent)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .onAppear {
                if videoPlayer == nil {
                    let player = AVPlayer(url: fileURL)
                    videoPlayer = player
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "film")
                    .foregroundColor(.secondary)
                Text(resolvedFileURL?.lastPathComponent ?? target)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }
    
    @ViewBuilder
    private var audioBody: some View {
        if let fileURL = resolvedFileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button {
                        audioController.togglePlay(url: fileURL)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: 34, height: 34)
                            Image(systemName: audioController.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fileURL.lastPathComponent)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.9))
                            .lineLimit(1)
                        
                        Slider(
                            value: Binding(
                                get: { audioController.currentTime },
                                set: { audioController.seek(to: $0) }
                            ),
                            in: 0...max(audioController.duration, 1.0)
                        )
                        .tint(.primary)
                        
                        HStack {
                            Text(formatTime(audioController.currentTime))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatTime(audioController.duration))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onAppear {
                    audioController.loadIfNeeded(url: fileURL)
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundColor(.secondary)
                Text(resolvedFileURL?.lastPathComponent ?? target)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }
    
    private var headerIcon: String {
        switch kind {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        }
    }
    
    private var badgeLabel: String {
        switch kind {
        case .image: return "IMAGE"
        case .video: return "VIDEO"
        case .audio: return "AUDIO"
        }
    }
    
    private var displaySubtitle: String {
        if title.contains("·") {
            let parts = title.components(separatedBy: "·")
            if let modelPart = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines), !modelPart.isEmpty {
                return modelPart
            }
        }
        if let fileURL = resolvedFileURL {
            return fileURL.lastPathComponent
        }
        return title
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func saveMediaAs(from sourceURL: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let destURL = panel.url {
            try? FileManager.default.removeItem(at: destURL)
            try? FileManager.default.copyItem(at: sourceURL, to: destURL)
        }
    }
}

final class ClosureMenuActionHandler: NSObject {
    static let shared = ClosureMenuActionHandler()
    @objc func performMenuAction(_ sender: NSMenuItem) {
        if let action = sender.representedObject as? () -> Void {
            action()
        }
    }
}
