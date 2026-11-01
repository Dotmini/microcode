//
//  AIAgentMessageRowsAndDiffCards.swift
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

// MARK: - A4 Paper Reading Mode

struct A4PaperView: View {
    let messages: [AgentMessageModel]
    @Binding var currentPage: Int
    
    // A4 Paper dimensions at 72dpi (scaled for display)
    private let paperWidth: CGFloat = 595 * 0.9
    private let paperHeight: CGFloat = 842 * 0.9
    private let paperMargin: CGFloat = 48
    
    // Combine all message content into pages
    private var allContent: String {
        messages.map { $0.content }.joined(separator: "\n\n---\n\n")
    }
    
    // Rough estimate: ~60 chars per line, ~45 lines per page
    private var totalPages: Int {
        max(1, (allContent.count / 2700) + 1)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Paper Container
            ScrollView {
                VStack(spacing: 24) {
                    // The Paper
                    ZStack {
                        // Paper Shadow
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.3))
                            .offset(x: 4, y: 4)
                            .blur(radius: 8)
                        
                        // Paper Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                        
                        // Paper Content
                        VStack(alignment: .leading, spacing: 16) {
                            // Header
                            if currentPage == 0 {
                                VStack(alignment: .center, spacing: 8) {
                                    Text("MicroCode Agent")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.black)
                                    Text("Generated Report")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                    Text(Date().formatted(date: .long, time: .shortened))
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 16)
                                
                                Divider().background(Color.gray.opacity(0.3))
                            }
                            
                            // Content
                            PaperContentView(content: allContent, page: currentPage)
                            
                            Spacer()
                            
                            // Footer
                            HStack {
                                Spacer()
                                Text("Page \(currentPage + 1) of \(totalPages)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(paperMargin)
                    }
                    .frame(width: paperWidth, height: paperHeight)
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            
            // Page Navigation Bar
            HStack(spacing: 16) {
                Button(action: { if currentPage > 0 { currentPage -= 1 }}) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(currentPage == 0)
                .foregroundColor(currentPage > 0 ? .accentColor : .secondary.opacity(0.5))
                
                // Page Dots
                HStack(spacing: 6) {
                    ForEach(0..<min(totalPages, 10), id: \.self) { page in
                        Circle()
                            .fill(page == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .onTapGesture { currentPage = page }
                    }
                    if totalPages > 10 {
                        Text("...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: { if currentPage < totalPages - 1 { currentPage += 1 }}) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(currentPage >= totalPages - 1)
                .foregroundColor(currentPage < totalPages - 1 ? .accentColor : .secondary.opacity(0.5))
                
                Spacer()
                
                // Export Button
                Button(action: {
                    // TODO: Export to PDF
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 10))
                        Text("Export PDF")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

// MARK: - Paper Content Renderer

struct PaperContentView: View {
    let content: String
    let page: Int
    
    private let charsPerPage = 2700
    
    private var pageContent: String {
        let startIndex = page * charsPerPage
        guard startIndex < content.count else { return "" }
        
        let start = content.index(content.startIndex, offsetBy: startIndex)
        let endOffset = min(startIndex + charsPerPage, content.count)
        let end = content.index(content.startIndex, offsetBy: endOffset)
        
        return String(content[start..<end])
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Parse and render content blocks
            let blocks = MessageContentParser.parse(pageContent)
            
            ForEach(blocks) { block in
                switch block {
                case .thought:
                    EmptyView()
                case .text(let text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        PaperTextView(text: text)
                    }
                    
                case .code(let lang, let code):
                    PaperCodeBlockView(language: lang, code: code)
                    
                case .heading(let level, let heading):
                    Text(heading)
                        .font(.system(size: paperHeadingSize(level), weight: .bold))
                        .foregroundColor(.black)
                        .padding(.top, level <= 2 ? 12 : 6)
                    
                case .list(let items, let isOrdered):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items.indices, id: \.self) { i in
                            HStack(alignment: .top, spacing: 8) {
                                Text(isOrdered ? "\(i + 1)." : "•")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                                Text(items[i])
                                    .font(.system(size: 11))
                                    .foregroundColor(.black)
                            }
                        }
                    }
                    
                case .table(let headers, let rows):
                    TableBlockView(headers: headers, rows: rows)
                    
                case .blockquote(let quote):
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: 2)
                        Text(quote)
                            .font(.system(size: 11))
                            .italic()
                            .foregroundColor(.gray)
                            .padding(.leading, 8)
                    }
                    
                case .latex(let expr, let isBlock):
                    // Show LaTeX as styled text with formula indicators
                    PaperLaTeXView(expression: expr, isBlock: isBlock)
                    
                case .html(let html):
                    Text(html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                        .font(.system(size: 11))
                        .foregroundColor(.black)
                    
                case .media(let kind, let title, let target):
                    ChatMediaBlockView(kind: kind, title: title, target: target)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func paperHeadingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 18
        case 2: return 15
        case 3: return 13
        default: return 11
        }
    }
}

// MARK: - Paper Text View (Print-friendly)

struct PaperTextView: View {
    let text: String
    
    var body: some View {
        Text(parsedText)
            .font(.system(size: 11))
            .foregroundColor(.black)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var parsedText: AttributedString {
        var str = AttributedString(text)
        let nsText = text as NSString
        
        // Bold
        if let regex = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: []) {
            for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
                let matched = nsText.substring(with: match.range)
                if let range = str.range(of: matched) {
                    str[range].font = .system(size: 11, weight: .bold)
                }
            }
        }
        
        // Italic
        if let regex = try? NSRegularExpression(pattern: "(?<![*])\\*([^*]+)\\*(?![*])", options: []) {
            for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
                let matched = nsText.substring(with: match.range)
                if let range = str.range(of: matched) {
                    str[range].font = .system(size: 11).italic()
                }
            }
        }
        
        // Inline code
        if let regex = try? NSRegularExpression(pattern: "`([^`]+)`", options: []) {
            for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
                let matched = nsText.substring(with: match.range)
                if let range = str.range(of: matched) {
                    str[range].font = .system(size: 10, design: .monospaced)
                    str[range].backgroundColor = Color.gray.opacity(0.15)
                }
            }
        }
        
        // Inline LaTeX ($...$)
        if let regex = try? NSRegularExpression(pattern: "\\$([^$]+)\\$", options: []) {
            for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
                let matched = nsText.substring(with: match.range)
                if let range = str.range(of: matched) {
                    str[range].font = .system(size: 11).italic()
                    str[range].foregroundColor = .blue
                }
            }
        }
        
        return str
    }
}

// MARK: - Paper Code Block View

struct PaperCodeBlockView: View {
    let language: String
    let code: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Re-use the native code block view but force light mode for paper aesthetic
            NativeCodeBlockView(language: language, code: code)
                .colorScheme(.light) // Force light mode for "Print/Paper" look
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

// MARK: - Paper LaTeX View

struct PaperLaTeXView: View {
    let expression: String
    let isBlock: Bool
    
    var body: some View {
        LaTeXBlockView(expression: expression, isBlock: isBlock)
            .colorScheme(.light)
            .padding(.vertical, 4)
    }
}

// MARK: - Rich Message Row

struct RichMessageRow: View, Equatable {
    let message: AgentMessageModel
    var isStreaming: Bool = false
    var onApplyChange: ((PendingChangeModel) -> Void)? = nil
    var onRejectChange: ((PendingChangeModel) -> Void)? = nil
    var onRevert: (() -> Void)? = nil
    var onEditAndResend: ((String) -> Void)? = nil
    var onRetry: (() -> Void)? = nil
    var onDelete: ((Bool) -> Void)? = nil
    @EnvironmentObject var appState: AppState
    
    @State private var isEditing: Bool = false
    @State private var editedText: String = ""
    @State private var isCopied: Bool = false
    @State private var isUserMessageExpanded: Bool = false
    @State private var isHoveringMessage: Bool = false
    
    static func == (lhs: RichMessageRow, rhs: RichMessageRow) -> Bool {
        return lhs.message.id == rhs.message.id &&
               lhs.message.content == rhs.message.content &&
               lhs.message.toolResults.count == rhs.message.toolResults.count &&
               lhs.message.pendingChanges == rhs.message.pendingChanges &&
               lhs.message.role == rhs.message.role &&
               lhs.isStreaming == rhs.isStreaming
    }
    
    private var isUser: Bool { message.role == .user }
    
    var body: some View {
        if isUser {
            // AGY-style editorial prompt card: clean full-width rounded container
            // with hover-only action toolbar so the canvas stays minimal.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    if isEditing {
                        userInlineEditCard
                    } else {
                        userBubbleText
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contextMenu {
                                userMessageContextMenu
                            }
                        userActionToolbar
                            .opacity((isHoveringMessage || isCopied) ? 0.92 : 0)
                            .allowsHitTesting(isHoveringMessage || isCopied)
                    }
                }
                .frame(maxWidth: 880, alignment: .leading)
                .onHover { hovering in
                    if isHoveringMessage != hovering {
                        isHoveringMessage = hovering
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        } else {
            // A readable editorial column, inspired by the comfortable line
            // lengths used in Codex and AGY. It stays fluid in narrow splits,
            // but never turns a wide editor into one long line of prose.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    AICellContentHost(
                        message: message,
                        isStreaming: isStreaming,
                        onApplyChange: onApplyChange,
                        onRejectChange: onRejectChange
                    )
                    .equatable()
                    .contextMenu {
                        assistantMessageContextMenu
                    }
                    if !isStreaming && (!message.content.isEmpty || !message.toolResults.isEmpty) {
                        assistantActionToolbar
                            .opacity((isHoveringMessage || isCopied) ? 0.92 : 0)
                            .allowsHitTesting(isHoveringMessage || isCopied)
                    }
                }
                .frame(maxWidth: 880, alignment: .leading)
                .onHover { hovering in
                    if isHoveringMessage != hovering {
                        isHoveringMessage = hovering
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var isLongUserMessage: Bool {
        guard message.content.count > 750 else {
            var newlineCount = 0
            for ch in message.content where ch == "\n" {
                newlineCount += 1
                if newlineCount > 14 { return true }
            }
            return false
        }
        return true
    }

    private var collapsedUserPreviewText: String {
        let lines = message.content.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 14 {
            let joined = lines.prefix(12).joined(separator: "\n")
            return (joined.count > 750 ? String(joined.prefix(750)) : joined) + "\n…"
        }
        if message.content.count > 750 {
            return String(message.content.prefix(750)) + "…"
        }
        return message.content
    }

    private var userBubbleText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isLongUserMessage && !isUserMessageExpanded ? collapsedUserPreviewText : message.content)
                .font(Font.custom(appState.agentFontName, size: appState.agentFontSize))
                .foregroundColor(.primary.opacity(0.92))
                .multilineTextAlignment(.leading)
                .lineLimit(isLongUserMessage && !isUserMessageExpanded ? 14 : nil)
                .fixedSize(horizontal: false, vertical: true)
            
            if isLongUserMessage {
                Divider()
                    .opacity(0.25)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isUserMessageExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: isUserMessageExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(isUserMessageExpanded ? "ย่อข้อความ (Collapse)" : "แสดงข้อความทั้งหมด (\(message.content.count.formatted()) ตัวอักษร)")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(.accentColor)
                    .padding(.top, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
    
    private var userInlineEditCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("แก้ไขข้อความ (จะย้อนกลับข้อความหลังจากจุดนี้และส่งใหม่)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            if #available(macOS 13.0, *) {
                TextField("แก้ไขข้อความของคุณ...", text: $editedText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Font.custom(appState.agentFontName, size: appState.agentFontSize))
                    .lineLimit(2...10)
                    .padding(10)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                    )
            } else {
                TextEditor(text: $editedText)
                    .font(Font.custom(appState.agentFontName, size: appState.agentFontSize))
                    .frame(minHeight: 60, maxHeight: 160)
                    .padding(6)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                    )
            }
            
            HStack(spacing: 8) {
                Spacer()
                
                Button(action: {
                    isEditing = false
                }) {
                    Text("ยกเลิก (Cancel)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    isEditing = false
                    onEditAndResend?(trimmed)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10))
                        Text("บันทึกและส่งใหม่ (Resend)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.4) : Color.accentColor)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(maxWidth: 620)
        .background(Color(nsColor: appState.appTheme.elevatedBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
        )
    }
    
    private var userActionToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                messageActionButton(
                    icon: "arrow.uturn.backward",
                    label: "ย้อนกลับ",
                    tooltip: "Restore Checkpoint — ย้อนกลับข้อความและการแก้ไขไฟล์มาที่จุดนี้ (Revert to this checkpoint)"
                ) {
                    onRevert?()
                }
                
                messageActionButton(
                    icon: "pencil",
                    label: "แก้ไข",
                    tooltip: "แก้ไขข้อความและส่งใหม่ (Edit & Resend)"
                ) {
                    editedText = AgentService.cleanUserPromptText(message.content)
                    isEditing = true
                }
                
                messageActionButton(
                    icon: "bookmark",
                    label: "บันทึกกฎ",
                    tooltip: "บันทึกคำสั่งนี้เป็นกฎของโปรเจกต์ใน .microcode/rules.md (Save as Project Rule)"
                ) {
                    let clean = AgentService.cleanUserPromptText(message.content)
                    let ws = AgentService.shared.currentWorkspace ?? appState.workspaceFolder?.path ?? FileManager.default.currentDirectoryPath
                    ProjectMemoryService.shared.appendLearnedRule(clean, workspace: ws)
                }
                
                messageActionButton(
                    icon: isCopied ? "checkmark" : "doc.on.doc",
                    label: isCopied ? "คัดลอกแล้ว" : "คัดลอก",
                    tooltip: "คัดลอกข้อความ (Copy message)",
                    tint: isCopied ? .green : nil
                ) {
                    copyTextToClipboard(AgentService.cleanUserPromptText(message.content))
                }
                
                messageActionButton(
                    icon: "trash",
                    label: "ลบ",
                    tooltip: "ลบข้อความนี้ (Delete message)",
                    isDestructive: true
                ) {
                    onDelete?(false)
                }
            }
        }
        .opacity(0.85)
    }
    
    private var assistantActionToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                messageActionButton(
                    icon: isCopied ? "checkmark" : "doc.on.doc",
                    label: isCopied ? "คัดลอกแล้ว" : "คัดลอก",
                    tooltip: "คัดลอกคำตอบ (Copy response)",
                    tint: isCopied ? .green : nil
                ) {
                    let clean = AIStructuredTurnCodec.stripThoughtTags(message.content)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    copyTextToClipboard(clean.isEmpty ? message.content : clean)
                }
                
                messageActionButton(
                    icon: "arrow.clockwise",
                    label: "ลองใหม่",
                    tooltip: "สร้างคำตอบใหม่อีกครั้ง (Regenerate response)"
                ) {
                    onRetry?()
                }
                
                let revertableFileCount = Set(
                    message.pendingChanges
                        .filter { !AgentExecutionEvidence.isInternalAgentArtifactPath($0.filePath) }
                        .map(\.filePath)
                ).count
                messageActionButton(
                    icon: "arrow.uturn.backward",
                    label: revertableFileCount == 0 ? "ย้อนกลับ" : "ย้อนกลับ (\(revertableFileCount) ไฟล์)",
                    tooltip: "Restore Checkpoint — ย้อนกลับคำตอบนี้และคืนค่าไฟล์ที่ถูกแก้ไข (Revert turn & restore files)"
                ) {
                    onRevert?()
                }
                
                messageActionButton(
                    icon: "trash",
                    label: "ลบ",
                    tooltip: "ลบข้อความนี้ (Delete message)",
                    isDestructive: true
                ) {
                    onDelete?(true)
                }
                
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 2)
        .opacity(0.85)
    }
    
    @ViewBuilder
    private var userMessageContextMenu: some View {
        Button {
            editedText = AgentService.cleanUserPromptText(message.content)
            isEditing = true
        } label: {
            Label("แก้ไขข้อความและส่งใหม่ (Edit & Resend)", systemImage: "pencil")
        }
        
        Button {
            onRevert?()
        } label: {
            Label("ย้อนกลับข้อความและไฟล์มาที่จุดนี้ (Revert to Here)", systemImage: "arrow.uturn.backward")
        }
        
        Button {
            copyTextToClipboard(AgentService.cleanUserPromptText(message.content))
        } label: {
            Label("คัดลอกข้อความ (Copy)", systemImage: "doc.on.doc")
        }
        
        Divider()
        
        Button(role: .destructive) {
            onDelete?(false)
        } label: {
            Label("ลบข้อความนี้ (Delete Message)", systemImage: "trash")
        }
    }
    
    @ViewBuilder
    private var assistantMessageContextMenu: some View {
        Button {
            let clean = AIStructuredTurnCodec.stripThoughtTags(message.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            copyTextToClipboard(clean.isEmpty ? message.content : clean)
        } label: {
            Label("คัดลอกคำตอบ (Copy Response)", systemImage: "doc.on.doc")
        }
        
        Button {
            onRetry?()
        } label: {
            Label("ลองใหม่ / สร้างคำตอบใหม่ (Regenerate)", systemImage: "arrow.clockwise")
        }
        
        Button {
            onRevert?()
        } label: {
            Label("ย้อนกลับคำตอบนี้และคืนค่าไฟล์ (Revert Turn & Files)", systemImage: "arrow.uturn.backward")
        }
        
        Divider()
        
        Button(role: .destructive) {
            onDelete?(true)
        } label: {
            Label("ลบข้อความนี้ (Delete Message)", systemImage: "trash")
        }
    }
    
    private func messageActionButton(
        icon: String,
        label: String,
        tooltip: String,
        tint: Color? = nil,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3.5) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(tint ?? (isDestructive ? .red.opacity(0.85) : .secondary))
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color.primary.opacity(0.045))
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
    
    private func copyTextToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            isCopied = false
        }
    }
}

// MARK: - Equatable AI Cell Content Host (Isolates Hover State from Markdown/Tool Tree)

private struct AICellContentHost: View, Equatable {
    let message: AgentMessageModel
    let isStreaming: Bool
    var onApplyChange: ((PendingChangeModel) -> Void)?
    var onRejectChange: ((PendingChangeModel) -> Void)?

    static func == (lhs: AICellContentHost, rhs: AICellContentHost) -> Bool {
        lhs.message.id == rhs.message.id &&
        lhs.message.content == rhs.message.content &&
        lhs.message.toolResults.count == rhs.message.toolResults.count &&
        lhs.message.pendingChanges == rhs.message.pendingChanges &&
        lhs.isStreaming == rhs.isStreaming
    }

    var body: some View {
        let blocks = MessageContentParser.parse(message.content)
        let lastThoughtIdx = blocks.lastIndex(where: {
            if case .thought = $0 { return true }
            return false
        })
        let preToolBlocks: [MessageBlock] = {
            guard !message.toolResults.isEmpty else { return blocks }
            guard let idx = lastThoughtIdx else { return [] }
            return Array(blocks[0...idx])
        }()
        let postToolBlocks: [MessageBlock] = {
            guard !message.toolResults.isEmpty else { return [] }
            guard let idx = lastThoughtIdx else { return blocks }
            guard idx + 1 < blocks.count else { return [] }
            return Array(blocks[(idx + 1)...])
        }()
        let harness = SubAgentHarness.shared
        let isLatestStreaming = isStreaming || (AgentService.shared.isLoading && AgentService.shared.messages.last?.id == message.id)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(preToolBlocks.enumerated()), id: \.offset) { _, block in
                aiBlockView(block, isLatestStreaming: isLatestStreaming)
            }
            
            if !message.toolResults.isEmpty {
                ToolExecutionStepsView(results: message.toolResults, isStreaming: isLatestStreaming)
            }
            
            ForEach(Array(postToolBlocks.enumerated()), id: \.offset) { _, block in
                aiBlockView(block, isLatestStreaming: isLatestStreaming)
            }
            
            // Immediate active progress indicator while agent is connecting/thinking and no content yet
            if blocks.isEmpty && message.toolResults.isEmpty && isLatestStreaming {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(AgentService.shared.currentToolExecution ?? "Agent is preparing response...")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
            }
            
            // CEO & Specialist Squad Live Boardroom + SubAgent activity cluster (shown on the latest assistant message only)
            if AgentService.shared.messages.last?.id == message.id {
                if !harness.interAgentDialogue.isEmpty || !harness.activeContracts.isEmpty {
                    CEOSquadBoardroomInlineView()
                }
                if !harness.activeSubagents.isEmpty {
                    SubAgentClusterView(subagents: harness.activeSubagents)
                }
            }
            
            if !visiblePendingChanges.isEmpty {
                pendingChangesSection
            }
            
            if !AgentService.shared.isLoading &&
               AgentService.shared.messages.last?.id == message.id &&
               message.content.contains("Reached maximum tool iteration safety limit") {
                Button(action: {
                    AgentService.shared.enqueueMessage("Continue executing the task from where you left off. Continue immediately with the next necessary step.")
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.primary)
                        Text("Continue Task")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.14), lineWidth: 1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            
            if !AgentService.shared.isLoading && (message.content.contains("⚠️ Rate limit reached") || message.content.contains("⚠️ Error: Rate limited")) {
                Button(action: {
                    AgentService.shared.enqueueMessage("Retry the previous step with pruned context. Proceed with the necessary action.")
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(.primary)
                        Text("Retry")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.14), lineWidth: 1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }
    
    @ViewBuilder
    private func aiBlockView(_ block: MessageBlock, isLatestStreaming: Bool) -> some View {
        switch block {
        case .thought(let content, let duration):
            AntigravityThoughtBlockView(
                content: content,
                durationSeconds: duration,
                isActivelyStreaming: isLatestStreaming && duration == nil
            )
        case .text(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MarkdownTextView(text: text)
            }
        case .code(let lang, let code):
            NativeCodeBlockView(language: lang, code: code)
        case .heading(let level, let content):
            HeadingView(level: level, content: content)
        case .list(let items, let isOrdered):
            ListView(items: items, isOrdered: isOrdered)
        case .table(let headers, let rows):
            TableBlockView(headers: headers, rows: rows)
        case .blockquote(let content):
            BlockquoteView(content: content)
        case .latex(let expression, let isBlock):
            LaTeXBlockView(expression: expression, isBlock: isBlock)
        case .html(let content):
            HTMLBlockView(content: content)
        case .media(let kind, let title, let target):
            ChatMediaBlockView(kind: kind, title: title, target: target)
        }
    }
    
    // MARK: - Pending Changes
    
    private var visiblePendingChanges: [PendingChangeModel] {
        var coalesced: [PendingChangeModel] = []
        for item in message.pendingChanges where !AgentExecutionEvidence.isInternalAgentArtifactPath(item.filePath) {
            if let idx = coalesced.firstIndex(where: { $0.filePath == item.filePath }) {
                let firstOld = coalesced[idx].oldContent
                coalesced[idx] = PendingChangeModel(
                    id: item.id,
                    filePath: item.filePath,
                    description: item.description,
                    additions: item.additions > 0 ? item.additions : coalesced[idx].additions,
                    deletions: item.deletions > 0 ? item.deletions : coalesced[idx].deletions,
                    oldContent: firstOld,
                    newContent: item.newContent,
                    status: item.status
                )
            } else {
                coalesced.append(item)
            }
        }
        return coalesced
    }
    
    private var pendingChangesSection: some View {
        let changes = visiblePendingChanges
        let hasPendingReview = changes.contains { $0.status == .pending }
        let sectionTitle = hasPendingReview
            ? "Proposed Changes (\(changes.count))"
            : "Edited Files (\(changes.count))"
        return VStack(spacing: 6) {
            Text(sectionTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(changes) { change in
                PendingChangeCard(
                    change: change,
                    onApply: onApplyChange,
                    onReject: onRejectChange,
                    onPartialApply: { change, reconstructedContent in
                        // P4: Write reconstructed file (with only accepted hunks) to disk
                        let url = URL(fileURLWithPath: change.filePath)
                        try? reconstructedContent.write(to: url, atomically: true, encoding: .utf8)
                        onApplyChange?(change)
                    }
                )
                .equatable()
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Pending Change Card (Modern Antigravity / Cursor Diff View)

private struct PendingChangeCard: View, Equatable {
    let change: PendingChangeModel
    var onApply: ((PendingChangeModel) -> Void)?
    var onReject: ((PendingChangeModel) -> Void)?
    var onPartialApply: ((PendingChangeModel, String) -> Void)?  // P4: partial hunk apply
    @State private var showDiffOverride: Bool? = nil
    @State private var showAllDiffLines = false
    @State private var showHunkReview = false  // P4: hunk-level review mode
    @State private var hunkDiffResult = DiffResult(oldContent: "", newContent: "", hunks: [], additions: 0, deletions: 0)
    @State private var diffViewportWidth: CGFloat = 0
    
    private let initialVisibleLineLimit = 64
    
    private var showDiff: Bool {
        showDiffOverride ?? (change.status == .pending)
    }

    private var activeTheme: AppTheme {
        AppState.shared?.appTheme ?? .dark
    }

    private var effectiveLineStats: (additions: Int, deletions: Int) {
        if change.additions > 0 || change.deletions > 0 {
            return (change.additions, change.deletions)
        }
        guard change.oldContent != change.newContent else {
            return (0, 0)
        }
        let cached = DiffCacheManager.getOrComputeDiffEntry(
            id: change.id,
            old: change.oldContent,
            new: change.newContent
        )
        var added = 0
        var removed = 0
        for line in cached.lines {
            if line.type == .addition { added += 1 }
            else if line.type == .deletion { removed += 1 }
        }
        return (added, removed)
    }
    
    static func == (lhs: PendingChangeCard, rhs: PendingChangeCard) -> Bool {
        return lhs.change == rhs.change
    }
    
    var body: some View {
        let theme = activeTheme
        let cardBg = theme.isGlass ? Color.primary.opacity(0.04) : Color(nsColor: theme.panelBackground)
        VStack(alignment: .leading, spacing: 0) {
            changeCardHeader
            
            if showHunkReview && change.status == .pending {
                // P4: Hunk-level review using InlineDiffView
                InlineDiffView(diffResult: $hunkDiffResult, filePath: change.filePath, onClose: {
                    withAnimation(.easeInOut(duration: 0.15)) { showHunkReview = false }
                })
                .frame(maxHeight: 400)
            } else if showDiff {
                if change.filePath.lowercased().hasSuffix(".md") && change.oldContent.isEmpty && !change.newContent.isEmpty {
                    ScrollView {
                        RenderedMarkdownDocumentView(markdown: change.newContent)
                            .padding(14)
                    }
                    .frame(maxHeight: 360)
                    .background(theme.isGlass ? Color.clear : Color(nsColor: theme.editorBackground))
                } else {
                    codeDiffSection
                }
            }
            
            if change.status == .pending {
                changeCardActions
            }
        }
        .background(cardBg)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    change.status == .rejected ? Color.primary.opacity(0.05) : Color.primary.opacity(0.09),
                    lineWidth: 1
                )
        )
    }
    
    private var changeCardHeader: some View {
        let theme = activeTheme
        let headerBg = theme.isGlass ? Color.primary.opacity(0.03) : Color(nsColor: theme.panelBackground)
        let fileName = URL(fileURLWithPath: change.filePath).lastPathComponent
        let stats = effectiveLineStats
        return HStack(spacing: 8) {
            Button(action: {
                let targetURL = URL(fileURLWithPath: change.filePath)
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    PreviewDockService.shared.openFile(url: targetURL, makeActive: true)
                } else {
                    PreviewDockService.shared.openFileFromReference(change.filePath)
                }
            }) {
                HStack(spacing: 8) {
                    ProgrammingLanguageIconView(
                        fileName: fileName,
                        size: 16
                    )
                    
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(fileName)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                            
                            // Additions / Deletions stats (Formal AGY / Cursor neutral typography, zero neon pills)
                            HStack(spacing: 5) {
                                if stats.additions > 0 {
                                    Text("+\(stats.additions)")
                                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                if stats.deletions > 0 {
                                    Text("-\(stats.deletions)")
                                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary.opacity(0.75))
                                }
                            }
                        }
                        
                        Text(change.description)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to preview file in Right Split Pane")
            
            Spacer()

            // Open Full Diff in Right Split Pane
            Button(action: {
                PreviewDockService.shared.openDiff(
                    id: "change:\(change.id)",
                    title: fileName,
                    oldContent: change.oldContent,
                    newContent: change.newContent,
                    makeActive: true
                )
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.left.and.right.square")
                        .font(.system(size: 9))
                    Text("Split Diff")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Open full side-by-side Diff in Right Split Pane")
            
            // Toggle diff
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { showDiffOverride = !showDiff } }) {
                HStack(spacing: 3) {
                    Text(showDiff ? "Hide Diff" : "Show Diff")
                        .font(.system(size: 10, weight: .medium))
                    Image(systemName: showDiff ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            
            changeCardStatusLabel
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(headerBg)
    }
    
    @ViewBuilder
    private var changeCardStatusLabel: some View {
        if change.status == .accepted {
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .semibold))
                Text("Applied")
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.045))
            .cornerRadius(4)
        } else if change.status == .rejected {
            Text("Reverted")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.secondary.opacity(0.75))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(4)
        }
    }
    
    // MARK: - Code Diff (Theme-Synchronized High-Contrast Unified Code Diff with Horizontal Scroll)
    
    private var codeDiffSection: some View {
        let theme = activeTheme
        let editorCanvas = theme.isGlass ? Color.clear : Color(nsColor: theme.editorBackground)
        let baseTextColor = Color(nsColor: theme.editorText)
        let lineNumColor = Color(nsColor: theme.commentColor).opacity(0.75)

        let cached = DiffCacheManager.getOrComputeDiffEntry(
            id: change.id,
            old: change.oldContent,
            new: change.newContent
        )
        let allLines = cached.lines
        let isTruncated = !showAllDiffLines && allLines.count > initialVisibleLineLimit
        let visibleLines: ArraySlice<UnifiedDiffLine> = isTruncated
            ? allLines.prefix(initialVisibleLineLimit)
            : allLines[...]
        let minRowWidth = max(diffViewportWidth, cached.minContentWidth)
        
        return VStack(spacing: 0) {
            Divider().opacity(0.4)
            
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleLines) { (diffLine: UnifiedDiffLine) in
                        if diffLine.type == .hunkHeader {
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.cyan.opacity(0.85))
                                    .frame(width: 2.5, height: 21)

                                Text("⋯")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.cyan.opacity(0.8))
                                    .frame(width: 70, alignment: .center)

                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(width: 1, height: 21)

                                Text(diffLine.text)
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(.cyan.opacity(0.9))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.leading, 10)
                                    .padding(.trailing, 20)

                                Spacer(minLength: 0)
                            }
                            .frame(minWidth: minRowWidth, minHeight: 21, maxHeight: 21, alignment: .leading)
                            .background(Color.cyan.opacity(theme.isDark ? 0.09 : 0.07))
                        } else {
                            let rowTextColor: Color = {
                                switch diffLine.type {
                                case .addition: return baseTextColor
                                case .deletion: return baseTextColor.opacity(0.76)
                                case .context: return baseTextColor.opacity(0.88)
                                case .hunkHeader: return .cyan
                                }
                            }()
                            let rowBg: Color = {
                                switch diffLine.type {
                                case .addition: return Color.green.opacity(theme.isDark ? 0.15 : 0.12)
                                case .deletion: return Color.red.opacity(theme.isDark ? 0.14 : 0.10)
                                case .context: return Color.clear
                                case .hunkHeader: return Color.cyan.opacity(0.08)
                                }
                            }()

                            HStack(spacing: 0) {
                                // Status accent strip (2.5pt)
                                Rectangle()
                                    .fill(diffLine.accentColor)
                                    .frame(width: 2.5, height: 19)
                                
                                // Pre-formatted monospaced gutter (oldNum + newNum)
                                Text(diffLine.gutterNumbers)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(lineNumColor)
                                    .frame(width: 64, alignment: .trailing)
                                    .padding(.trailing, 6)
                                
                                // Gutter divider line
                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(width: 1, height: 19)
                                
                                // Prefix (+/-) and code text
                                Text(diffLine.prefix)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(diffLine.prefixColor)
                                    .frame(width: 18, alignment: .center)
                                
                                Text(diffLine.displayText)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundColor(rowTextColor)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.trailing, 20)
                                
                                Spacer(minLength: 0)
                            }
                            .frame(minWidth: minRowWidth, minHeight: 19, maxHeight: 19, alignment: .leading)
                            .background(rowBg)
                        }
                    }
                }
                .frame(minWidth: minRowWidth, alignment: .leading)
                .padding(.vertical, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { diffViewportWidth = geo.size.width }
                        .onChange(of: geo.size.width) { newW in diffViewportWidth = newW }
                }
            )
            .background(editorCanvas)
            
            if allLines.count > initialVisibleLineLimit {
                Divider().opacity(0.3)
                Button(action: {
                    showAllDiffLines.toggle()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: showAllDiffLines ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                        Text(showAllDiffLines
                             ? "Collapse diff (\(initialVisibleLineLimit) of \(allLines.count) lines)"
                             : "Show all \(allLines.count) diff lines (+\(allLines.count - initialVisibleLineLimit) more)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.03))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var changeCardActions: some View {
        VStack(spacing: 0) {
            if showHunkReview {
                // Hunk-level review actions
                HStack(spacing: 8) {
                    let accepted = hunkDiffResult.hunks.filter { $0.status == .accepted }.count
                    let rejected = hunkDiffResult.hunks.filter { $0.status == .rejected }.count
                    let total = hunkDiffResult.hunks.count
                    let pending = total - accepted - rejected
                    
                    // Status
                    HStack(spacing: 4) {
                        if accepted > 0 {
                            Text("\(accepted)✓")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        if rejected > 0 {
                            Text("\(rejected)✗")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        if pending > 0 {
                            Text("\(pending) pending")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Apply Selected Hunks
                    if accepted > 0 || pending == 0 {
                        Button(action: {
                            let reconstructed = reconstructFileFromHunks(
                                oldContent: change.oldContent,
                                diff: hunkDiffResult
                            )
                            onPartialApply?(change, reconstructed)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9.5, weight: .bold))
                                Text(accepted == total ? "Apply All" : "Apply \(accepted) Hunks")
                            }
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.14), lineWidth: 0.5))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Back to simple view
                    Button(action: { withAnimation(.easeInOut(duration: 0.15)) { showHunkReview = false } }) {
                        Text("Simple View")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.02))
            } else {
                // Standard file-level actions
                HStack(spacing: 8) {
                    Button(action: { onApply?(change) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("Accept")
                        }
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.14), lineWidth: 0.5))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { onReject?(change) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9.5, weight: .medium))
                            Text("Reject")
                        }
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Hunk review toggle — the P4 feature
                    Button(action: {
                        // Compute hunk diff if not already done
                        if hunkDiffResult.hunks.isEmpty {
                            hunkDiffResult = DiffEngine.shared.computeDiff(
                                old: change.oldContent,
                                new: change.newContent
                            )
                        }
                        withAnimation(.easeInOut(duration: 0.15)) { showHunkReview = true }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "rectangle.split.3x1")
                            Text("Review Hunks")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.02))
            }
        }
    }
    
    // MARK: - P4: Reconstruct File from Accepted/Rejected Hunks
    
    /// Builds the final file by applying only accepted hunks.
    /// Rejected hunks keep the original lines. Pending hunks are treated as rejected.
    private func reconstructFileFromHunks(oldContent: String, diff: DiffResult) -> String {
        let oldLines = oldContent.components(separatedBy: "\n")
        var result: [String] = []
        var oldIndex = 0
        
        // Sort hunks by their position in the old file
        let sortedHunks = diff.hunks.sorted { $0.oldRange.lowerBound < $1.oldRange.lowerBound }
        
        for hunk in sortedHunks {
            let hunkStart = max(0, hunk.oldRange.lowerBound)
            
            // Copy unchanged lines before this hunk
            while oldIndex < hunkStart && oldIndex < oldLines.count {
                result.append(oldLines[oldIndex])
                oldIndex += 1
            }
            
            if hunk.status == .accepted {
                // Apply new lines
                result.append(contentsOf: hunk.newLines)
            } else {
                // Keep old lines (rejected or pending)
                result.append(contentsOf: hunk.oldLines)
            }
            
            // Skip past old lines covered by this hunk
            oldIndex = min(oldLines.count, hunk.oldRange.upperBound)
        }
        
        // Copy remaining lines after last hunk
        while oldIndex < oldLines.count {
            result.append(oldLines[oldIndex])
            oldIndex += 1
        }
        
        return result.joined(separator: "\n")
    }
}

// MARK: - Memoized Diff Cache Manager

public struct UnifiedDiffLine: Identifiable, Equatable {
    public let id: String
    public let oldNum: String
    public let newNum: String
    public let gutterNumbers: String
    public let prefix: String
    public let text: String
    public let displayText: String
    public let type: DiffLineType
    
    public enum DiffLineType {
        case context, addition, deletion, hunkHeader
    }
    
    public init(id: String, oldNum: String, newNum: String, prefix: String, text: String, type: DiffLineType) {
        self.id = id
        self.oldNum = oldNum
        self.newNum = newNum
        let paddedOld = oldNum.count < 4 ? String(repeating: " ", count: 4 - oldNum.count) + oldNum : oldNum
        let paddedNew = newNum.count < 4 ? String(repeating: " ", count: 4 - newNum.count) + newNum : newNum
        self.gutterNumbers = "\(paddedOld) \(paddedNew)"
        self.prefix = prefix
        self.text = text
        let expanded = text.contains("\t") ? text.replacingOccurrences(of: "\t", with: "    ") : text
        self.displayText = expanded.isEmpty ? " " : expanded
        self.type = type
    }
    
    var accentColor: Color {
        switch type {
        case .addition: return .green
        case .deletion: return .red
        case .hunkHeader: return .cyan
        case .context: return .clear
        }
    }
    
    var prefixColor: Color {
        switch type {
        case .addition: return .green
        case .deletion: return .red
        case .hunkHeader: return .cyan
        case .context: return .secondary.opacity(0.25)
        }
    }
    
    var textColor: Color {
        switch type {
        case .addition: return Color.primary
        case .deletion: return Color.primary.opacity(0.75)
        case .hunkHeader: return Color.cyan.opacity(0.9)
        case .context: return Color.primary.opacity(0.88)
        }
    }
    
    var bgColor: Color {
        switch type {
        case .addition: return Color.green.opacity(0.13)
        case .deletion: return Color.red.opacity(0.11)
        case .hunkHeader: return Color.cyan.opacity(0.08)
        case .context: return Color.clear
        }
    }
}

public struct CachedDiffEntry {
    public let lines: [UnifiedDiffLine]
    public let minContentWidth: CGFloat
}

public final class DiffCacheManager {
    private static var cache: [String: CachedDiffEntry] = [:]
    private static let lock = NSLock()
    
    public static func getOrComputeDiff(id: String, old: @autoclosure () -> String, new: @autoclosure () -> String) -> [UnifiedDiffLine] {
        return getOrComputeDiffEntry(id: id, old: old(), new: new()).lines
    }
    
    public static func getOrComputeDiffEntry(id: String, old: @autoclosure () -> String, new: @autoclosure () -> String) -> CachedDiffEntry {
        let oldStr = old()
        let newStr = new()
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(oldStr)
        hasher.combine(newStr)
        let cacheKey = "\(id)#\(oldStr.count):\(newStr.count):\(hasher.finalize())"

        lock.lock()
        if let found = cache[cacheKey] {
            lock.unlock()
            return found
        }
        lock.unlock()
        
        let lines = computeDiff(old: oldStr, new: newStr)
        let maxChars = lines.reduce(0) { max($0, min($1.displayText.count, 320)) }
        // Fast O(1) monospaced width calculation (11.5pt monospaced ≈ 7.1pt/char + 132pt gutter/padding)
        let minContentWidth = CGFloat(maxChars) * 7.1 + 132.0
        let entry = CachedDiffEntry(lines: lines, minContentWidth: minContentWidth)
        
        lock.lock()
        if cache.count > 96 { cache.removeAll(keepingCapacity: true) }
        cache[cacheKey] = entry
        lock.unlock()
        
        return entry
    }
    
    public static func clearAll() {
        lock.lock()
        cache.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    private static func splitNormalizedLines(_ raw: String) -> [String] {
        guard !raw.isEmpty else { return [] }
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var parts = normalized.components(separatedBy: "\n")
        if parts.count > 1 && parts.last == "" {
            parts.removeLast()
        }
        return parts
    }
    
    private static func computeDiff(old: String, new: String) -> [UnifiedDiffLine] {
        let oldLines = splitNormalizedLines(old)
        let newLines = splitNormalizedLines(new)
        
        // Fast path for identical content
        if oldLines == newLines {
            let previewCount = min(oldLines.count, 12)
            var lines = oldLines.prefix(previewCount).enumerated().map { idx, line in
                UnifiedDiffLine(id: "ctx-\(idx)", oldNum: "\(idx + 1)", newNum: "\(idx + 1)", prefix: " ", text: line, type: .context)
            }
            if oldLines.count > previewCount {
                lines.append(UnifiedDiffLine(
                    id: "ctx-more",
                    oldNum: "⋯",
                    newNum: "⋯",
                    prefix: "",
                    text: "@@ -1,\(oldLines.count) +1,\(newLines.count) @@  •  \(oldLines.count - previewCount) more unchanged lines",
                    type: .hunkHeader
                ))
            }
            return lines
        }
        
        // 1. Trim common unchanged prefix and suffix in O(N) so edits deep inside large files
        // are never cut off by DP matrix limits and LCS only runs on the changed middle region.
        var prefixCount = 0
        let minTotal = min(oldLines.count, newLines.count)
        while prefixCount < minTotal && oldLines[prefixCount] == newLines[prefixCount] {
            prefixCount += 1
        }
        
        var suffixCount = 0
        while suffixCount < (minTotal - prefixCount) &&
              oldLines[oldLines.count - 1 - suffixCount] == newLines[newLines.count - 1 - suffixCount] {
            suffixCount += 1
        }
        
        let midOld = Array(oldLines[prefixCount..<(oldLines.count - suffixCount)])
        let midNew = Array(newLines[prefixCount..<(newLines.count - suffixCount)])
        
        enum RawOp {
            case equal(String, Int, Int)
            case delete(String, Int)
            case insert(String, Int)
            
            var isChange: Bool {
                switch self {
                case .equal: return false
                case .delete, .insert: return true
                }
            }
        }
        
        var midOps: [RawOp] = []
        let dpCap = 350
        let m = min(midOld.count, dpCap)
        let n = min(midNew.count, dpCap)
        
        if m > 0 && n > 0 {
            var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
            for i in 1...m {
                for j in 1...n {
                    if midOld[i - 1] == midNew[j - 1] {
                        dp[i][j] = dp[i - 1][j - 1] + 1
                    } else {
                        dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                    }
                }
            }
            
            enum StepOp { case equal(String), delete(String), insert(String) }
            var steps: [StepOp] = []
            var i = m, j = n
            while i > 0 || j > 0 {
                if i > 0 && j > 0 && midOld[i - 1] == midNew[j - 1] {
                    steps.append(.equal(midOld[i - 1]))
                    i -= 1; j -= 1
                } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                    steps.append(.insert(midNew[j - 1]))
                    j -= 1
                } else if i > 0 {
                    steps.append(.delete(midOld[i - 1]))
                    i -= 1
                }
            }
            steps.reverse()
            
            var curOld = prefixCount + 1
            var curNew = prefixCount + 1
            for step in steps {
                switch step {
                case .equal(let t):
                    midOps.append(.equal(t, curOld, curNew))
                    curOld += 1; curNew += 1
                case .delete(let t):
                    midOps.append(.delete(t, curOld))
                    curOld += 1
                case .insert(let t):
                    midOps.append(.insert(t, curNew))
                    curNew += 1
                }
            }
            // Append any overflow beyond dpCap
            if midOld.count > m {
                for idx in m..<midOld.count {
                    midOps.append(.delete(midOld[idx], curOld))
                    curOld += 1
                }
            }
            if midNew.count > n {
                for idx in n..<midNew.count {
                    midOps.append(.insert(midNew[idx], curNew))
                    curNew += 1
                }
            }
        } else {
            var curOld = prefixCount + 1
            for line in midOld {
                midOps.append(.delete(line, curOld))
                curOld += 1
            }
            var curNew = prefixCount + 1
            for line in midNew {
                midOps.append(.insert(line, curNew))
                curNew += 1
            }
        }
        
        // 2. Build UnifiedDiffLines with ±3 context lines around changes and collapsed hunk headers
        let contextRadius = 3
        var result: [UnifiedDiffLine] = []
        var lineCounter = 0
        
        // Leading unchanged prefix: collapse if > contextRadius
        if prefixCount > 0 {
            let keepStart = max(0, prefixCount - contextRadius)
            if keepStart > 0 {
                result.append(UnifiedDiffLine(
                    id: "hunk-pre",
                    oldNum: "⋯",
                    newNum: "⋯",
                    prefix: "",
                    text: "@@ -1,\(keepStart) +1,\(keepStart) @@  •  \(keepStart) unchanged lines",
                    type: .hunkHeader
                ))
            }
            for idx in keepStart..<prefixCount {
                lineCounter += 1
                result.append(UnifiedDiffLine(
                    id: "pre-\(lineCounter)",
                    oldNum: "\(idx + 1)",
                    newNum: "\(idx + 1)",
                    prefix: " ",
                    text: oldLines[idx],
                    type: .context
                ))
            }
        }
        
        // Middle ops: collapse any unchanged run longer than 2 * contextRadius + 1
        var keepMid = Array(repeating: false, count: midOps.count)
        for idx in midOps.indices where midOps[idx].isChange {
            let lo = max(0, idx - contextRadius)
            let hi = min(midOps.count - 1, idx + contextRadius)
            for k in lo...hi {
                keepMid[k] = true
            }
        }
        
        var idx = 0
        while idx < midOps.count {
            if keepMid[idx] {
                lineCounter += 1
                switch midOps[idx] {
                case .equal(let text, let oNum, let nNum):
                    result.append(UnifiedDiffLine(
                        id: "eq-\(lineCounter)",
                        oldNum: "\(oNum)",
                        newNum: "\(nNum)",
                        prefix: " ",
                        text: text,
                        type: .context
                    ))
                case .delete(let text, let oNum):
                    result.append(UnifiedDiffLine(
                        id: "del-\(lineCounter)",
                        oldNum: "\(oNum)",
                        newNum: "",
                        prefix: "-",
                        text: text,
                        type: .deletion
                    ))
                case .insert(let text, let nNum):
                    result.append(UnifiedDiffLine(
                        id: "ins-\(lineCounter)",
                        oldNum: "",
                        newNum: "\(nNum)",
                        prefix: "+",
                        text: text,
                        type: .addition
                    ))
                }
                idx += 1
            } else {
                let runStart = idx
                while idx < midOps.count && !keepMid[idx] {
                    idx += 1
                }
                let skipped = idx - runStart
                if skipped == 1, case .equal(let text, let oNum, let nNum) = midOps[runStart] {
                    lineCounter += 1
                    result.append(UnifiedDiffLine(
                        id: "eq-\(lineCounter)",
                        oldNum: "\(oNum)",
                        newNum: "\(nNum)",
                        prefix: " ",
                        text: text,
                        type: .context
                    ))
                } else if case .equal(_, let firstOld, let firstNew) = midOps[runStart] {
                    result.append(UnifiedDiffLine(
                        id: "hunk-\(runStart)",
                        oldNum: "⋯",
                        newNum: "⋯",
                        prefix: "",
                        text: "@@ -\(firstOld),\(skipped) +\(firstNew),\(skipped) @@  •  \(skipped) unchanged lines",
                        type: .hunkHeader
                    ))
                }
            }
            if result.count >= 400 { break }
        }
        
        // Trailing unchanged suffix: keep up to contextRadius lines, collapse the rest
        if suffixCount > 0 && result.count < 400 {
            let keepCount = min(suffixCount, contextRadius)
            let oldSuffixStart = oldLines.count - suffixCount
            let newSuffixStart = newLines.count - suffixCount
            for k in 0..<keepCount {
                lineCounter += 1
                result.append(UnifiedDiffLine(
                    id: "suf-\(lineCounter)",
                    oldNum: "\(oldSuffixStart + k + 1)",
                    newNum: "\(newSuffixStart + k + 1)",
                    prefix: " ",
                    text: oldLines[oldSuffixStart + k],
                    type: .context
                ))
            }
            let remainingSuffix = suffixCount - keepCount
            if remainingSuffix > 0 {
                let startOld = oldSuffixStart + keepCount + 1
                let startNew = newSuffixStart + keepCount + 1
                result.append(UnifiedDiffLine(
                    id: "hunk-suf",
                    oldNum: "⋯",
                    newNum: "⋯",
                    prefix: "",
                    text: "@@ -\(startOld),\(remainingSuffix) +\(startNew),\(remainingSuffix) @@  •  \(remainingSuffix) unchanged lines",
                    type: .hunkHeader
                ))
            }
        }
        
        return result
    }
}

