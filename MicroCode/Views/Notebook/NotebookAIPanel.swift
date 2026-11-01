//
//  NotebookAIPanel.swift
//  MicroCode
//
//  Formal, Responsive Autonomous AI Agent & Assistant Panel for Cell Mode.
//  Aligned with MicroCode's main AIAgentView design language:
//  - Single 28pt executive top bar aligned with NotebookView toolbar
//  - Borderless Antigravity-style conversation stream & collapsible left-rail action timeline
//  - Unified multi-row composer card with responsive ViewThatFits controls
//
//  Created by Dotmini Software
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import SwiftUI
import AppKit
import Combine

// MARK: - Notebook AI Panel

struct NotebookAIPanel: View {
    @ObservedObject var viewModel: NotebookViewModel
    @Binding var isShowing: Bool
    @EnvironmentObject var appState: AppState

    @AppStorage("cellMode.agentModeActive") private var isAgentMode: Bool = true
    @AppStorage("cellMode.subAgentRole") private var selectedRole: String = CellSubAgentRole.dataScientist.rawValue

    @State private var inputText = ""
    @State private var messages: [CellAIMessage] = []
    @State private var isLoading = false
    @State private var currentStatus = ""
    @State private var focusSelectedCellOnly = false
    @State private var hoveredHeaderBtn: String? = nil
    @State private var isComposerFocused: Bool = false

    private let panelSessionId = "notebook-ai-panel-main"
    private let headerHeight: CGFloat = 28

    // MARK: - Theme Tokens

    private var isDark: Bool {
        appState.appTheme.isDark
    }

    private var panelBg: Color {
        appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground)
    }

    private var workspaceBg: Color {
        appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.workspaceBackground)
    }

    private var composerCardBg: Color {
        if appState.appTheme.isGlass {
            return Color.primary.opacity(0.055)
        }
        return isDark
            ? Color.white.opacity(0.04)
            : Color.black.opacity(0.03)
    }

    private var subtleBorder: Color {
        Color.primary.opacity(isDark ? 0.11 : 0.08)
    }

    private var activeSelection: CellAISelection {
        var sel = CellAISelection.inherit
        sel.subAgentRole = selectedRole
        return sel
    }

    private var selectedCellContext: (number: Int, cell: NotebookCellModel)? {
        guard let nb = viewModel.activeNotebook,
              let selId = viewModel.selectedCellId,
              let idx = nb.cells.firstIndex(where: { $0.id == selId }) else {
            return nil
        }
        return (idx + 1, nb.cells[idx])
    }

    private var firstErrorCellInfo: (number: Int, cell: NotebookCellModel)? {
        guard let nb = viewModel.activeNotebook else { return nil }
        for (idx, c) in nb.cells.enumerated() where c.type == .code && !c.output.isEmpty {
            if c.output.contains("Error") || c.output.contains("Traceback") || c.output.contains("Exception") {
                return (idx + 1, c)
            }
        }
        return nil
    }

    private var suggestions: [CellAISuggestion] {
        guard let notebook = viewModel.activeNotebook else { return [] }
        var items: [CellAISuggestion] = []
        let languages = Set(notebook.cells.filter { $0.type == .code }.map { $0.language })

        if let errInfo = firstErrorCellInfo {
            items.append(.init(
                icon: "wrench.and.screwdriver",
                text: "วิเคราะห์และแก้ Error ใน Cell #\(errInfo.number) แล้วรันทดสอบให้ผ่าน"
            ))
        }
        if isAgentMode {
            items.append(.init(
                icon: "sparkles.rectangle.stack",
                text: "สร้าง Pipeline วิเคราะห์ข้อมูลและพล็อตกราฟเป็น Cell ใหม่พร้อมรันผลลัพธ์"
            ))
        }
        if languages.contains(.python) {
            items.append(.init(
                icon: "chart.xyaxis.line",
                text: "สร้าง Visualization สรุปข้อมูลจาก Cell ก่อนหน้า"
            ))
        }
        if languages.count > 1 {
            items.append(.init(
                icon: "arrow.triangle.branch",
                text: "เชื่อมผลลัพธ์ข้ามภาษา (\(languages.map(\.rawValue).sorted().joined(separator: " + ")))"
            ))
        }
        items.append(.init(
            icon: "slider.horizontal.3",
            text: "ปรับโครงสร้างและประสิทธิภาพโค้ดใน Notebook นี้"
        ))
        return items
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let panelWidth = max(240, geo.size.width)
            VStack(spacing: 0) {
                panelHeader

                Divider()

                if let errInfo = firstErrorCellInfo, !isLoading {
                    errorDiagnosticStrip(errInfo: errInfo)
                    Divider().opacity(0.6)
                }

                // Conversation Stage — strictly width-locked to panelWidth so long code blocks never overflow
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if messages.isEmpty {
                                emptyState
                            } else {
                                ForEach(messages) { msg in
                                    CellAIMessageRow(
                                        message: msg,
                                        availableWidth: panelWidth,
                                        onRetry: { retryMessage(msg) }
                                    )
                                    .id(msg.id)
                                }
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("cell-ai-bottom-anchor")
                        }
                        .padding(.vertical, 10)
                        .frame(width: panelWidth, alignment: .leading)
                    }
                    .frame(width: panelWidth)
                    .background(workspaceBg)
                    .onChange(of: messages.count) { _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: messages.last?.toolSteps.count) { _ in
                        if isLoading { scrollToBottom(proxy) }
                    }
                    .onChange(of: messages.last?.content) { _ in
                        if isLoading { scrollToBottom(proxy, animated: false) }
                    }
                }

                composerArea
                    .frame(width: panelWidth)
            }
            .frame(width: panelWidth, height: geo.size.height)
            .background(panelBg)
            .clipped()
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InsertNotebookAgentMention"))) { notification in
                if let mention = notification.userInfo?["mention"] as? String, !mention.isEmpty {
                    let sep = (inputText.isEmpty || inputText.hasSuffix(" ") || inputText.hasSuffix("\n")) ? "" : " "
                    inputText += "\(sep)\(mention) "
                    isComposerFocused = true
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.16)) {
                proxy.scrollTo("cell-ai-bottom-anchor", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("cell-ai-bottom-anchor", anchor: .bottom)
        }
    }

    // MARK: - Single 28pt Formal Header Bar (Aligned with Notebook Toolbar)

    private var panelHeader: some View {
        HStack(spacing: 5) {
            Text("Agent")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(.primary.opacity(0.92))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            if let notebook = viewModel.activeNotebook {
                Button(action: { presentScopeMenu(notebook: notebook) }) {
                    HStack(spacing: 3.5) {
                        Text("·")
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(scopeSummaryLabel(notebook: notebook))
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundColor(focusSelectedCellOnly ? .accentColor : .secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.75))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help("Configure Notebook Context Scope")
            }

            Spacer(minLength: 4)

            // New Chat / Clear Session
            headerIconAction(
                id: "new",
                icon: "plus",
                tooltip: "New Session"
            ) {
                if isLoading { stopExecution() }
                messages.removeAll()
            }

            // Insert Inline Agent Cell
            headerIconAction(
                id: "insert_cell",
                icon: "plus.rectangle.on.rectangle",
                tooltip: "Insert Inline Agent Cell"
            ) {
                viewModel.addCell(type: .agent)
            }

            // Close Panel
            headerIconAction(
                id: "close",
                icon: "xmark",
                tooltip: "Close Agent Panel"
            ) {
                withAnimation(.easeInOut(duration: 0.16)) { isShowing = false }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: headerHeight)
        .background(panelBg)
    }

    private func presentScopeMenu(notebook: NotebookModel) {
        let menu = NSMenu(title: "Context Scope")
        menu.autoenablesItems = false

        func addItem(_ title: String, checked: Bool = false, icon: String? = nil, action: @escaping () -> Void) {
            let item = NSMenuItem(
                title: title,
                action: #selector(ClosureMenuActionHandler.performMenuAction(_:)),
                keyEquivalent: ""
            )
            item.target = ClosureMenuActionHandler.shared
            item.representedObject = action
            item.state = checked ? .on : .off
            if let icon, let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
                item.image = img
            }
            menu.addItem(item)
        }

        addItem("Entire Sheet (\(notebook.cells.count) cells)", checked: !focusSelectedCellOnly, icon: "rectangle.grid.1x2") {
            self.focusSelectedCellOnly = false
        }
        if let sel = selectedCellContext {
            addItem(
                "Focused Cell Only (#\(sel.number) · \(sel.cell.type == .agent ? "Agent" : sel.cell.language.rawValue))",
                checked: focusSelectedCellOnly,
                icon: "scope"
            ) {
                self.focusSelectedCellOnly = true
            }
        }
        menu.addItem(.separator())
        addItem("Quote Selected Cell Code", icon: "curlybraces") {
            self.insertSelectedCellSnippet(includeOutput: false)
        }
        addItem("Quote Cell + Output", icon: "doc.plaintext") {
            self.insertSelectedCellSnippet(includeOutput: true)
        }

        let loc = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: loc, in: nil)
    }

    private func scopeSummaryLabel(notebook: NotebookModel) -> String {
        if focusSelectedCellOnly, let sel = selectedCellContext {
            return "Cell #\(sel.number)"
        }
        if let sel = selectedCellContext {
            return "\(notebook.cells.count) cells · #\(sel.number)"
        }
        return "\(notebook.cells.count) cells"
    }

    @ViewBuilder
    private func headerIconAction(id: String, icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(hoveredHeaderBtn == id ? .primary : .secondary)
                .frame(width: 22, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hoveredHeaderBtn == id ? Color.primary.opacity(0.07) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering in
            hoveredHeaderBtn = hovering ? id : (hoveredHeaderBtn == id ? nil : hoveredHeaderBtn)
        }
        .help(tooltip)
    }

    // MARK: - Slim Formal Diagnostic Strip

    @ViewBuilder
    private func errorDiagnosticStrip(errInfo: (number: Int, cell: NotebookCellModel)) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Color.orange.opacity(0.9))
                .fixedSize()

            Text("Cell #\(errInfo.number) reported an error")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Button(action: {
                inputText = "วิเคราะห์และซ่อม Error ใน Cell #\(errInfo.number) แล้วรันทดสอบจนผ่าน"
                if !isAgentMode { isAgentMode = true }
                sendMessage()
            }) {
                Text("Auto-Fix")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary.opacity(0.88))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(isDark ? 0.08 : 0.06))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(subtleBorder, lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Have the Agent inspect, patch, and re-run Cell #\(errInfo.number)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(isDark ? 0.025 : 0.018))
    }

    // MARK: - Formal Minimalist Empty State

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer().frame(height: 18)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(isAgentMode ? "Notebook Agent" : "Notebook Assistant")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Text(isAgentMode
                     ? "Inspects, edits, creates, and executes cells across languages with full workspace and MCP tool access."
                     : "Answers questions and drafts code blocks ready to insert into any cell.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 5) {
                ForEach(suggestions, id: \.text) { suggestion in
                    Button(action: { sendSuggestion(suggestion) }) {
                        HStack(spacing: 8) {
                            Image(systemName: suggestion.icon)
                                .font(.system(size: 10.5, weight: .regular))
                                .foregroundColor(.secondary)
                                .frame(width: 15)
                                .fixedSize()

                            Text(suggestion.text)
                                .font(.system(size: 11.5))
                                .foregroundColor(.primary.opacity(0.86))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.6))
                                .fixedSize()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(isDark ? 0.035 : 0.025))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(subtleBorder, lineWidth: 0.8)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Unified Multi-Row Formal Composer Area (Matching AIAgentView.inputCardView)

    private var composerArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isLoading {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.75)
                        .frame(width: 12, height: 12)

                    Text(currentStatus.isEmpty ? (isAgentMode ? "Working…" : "Generating…") : currentStatus)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 6) {
                // AppKit-backed Multiline Prompt Input (Enter = Send, Shift+Enter = Newline, IME-safe)
                CellPromptInputView(
                    text: $inputText,
                    placeholder: isAgentMode
                        ? "สั่ง Agent ให้สร้าง แก้ไข หรือรัน Cell… (Enter เพื่อส่ง)"
                        : "ถามคำถามหรือให้ AI เขียนโค้ด… (Enter เพื่อส่ง)",
                    isDark: isDark,
                    minHeight: 30,
                    maxHeight: 132,
                    fontSize: 12.5,
                    onFocus: { focused in
                        isComposerFocused = focused
                    },
                    onSubmit: {
                        if !isLoading {
                            sendMessage()
                        }
                    }
                )
                .padding(.horizontal, 2)

                // Clean single-row composer footer
                HStack(spacing: 5) {
                    Button(action: presentAttachmentMenu) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.045))
                            .cornerRadius(5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Quote cell code, attach dataset, or insert inline Agent cell")

                    Button(action: presentMentionMenu) {
                        Image(systemName: "at")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.045))
                            .cornerRadius(5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Mention live kernel variable (@df) or cell (@Cell#1) with full schema & stats")

                    CellModeTogglePill(isAgentMode: $isAgentMode, compact: true)
                        .fixedSize()

                    CellAIModelSelectorPill(
                        selection: nil,
                        showRoleSelector: isAgentMode,
                        roleBinding: $selectedRole,
                        maxWidth: .infinity,
                        compact: true,
                        minimalChrome: true,
                        roleIconOnly: true
                    )

                    Spacer(minLength: 2)

                    if isLoading {
                        Button(action: stopExecution) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 25, height: 25)
                                .background(Color.red.opacity(0.85))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help("Stop Generation")
                    } else {
                        let canSend = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(canSend ? .white : .secondary.opacity(0.55))
                                .frame(width: 25, height: 25)
                                .background(
                                    canSend
                                        ? Color.accentColor
                                        : Color.primary.opacity(0.07)
                                )
                                .clipShape(Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .fixedSize()
                        .help(isAgentMode ? "Run Agent (Enter)" : "Send (Enter)")
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(composerCardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isComposerFocused ? Color.accentColor.opacity(0.55) : subtleBorder,
                        lineWidth: isComposerFocused ? 1.1 : 0.9
                    )
            )
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(panelBg)
    }

    private func presentAttachmentMenu() {
        let menu = NSMenu(title: "Attach Context")
        menu.autoenablesItems = false

        func addItem(_ title: String, icon: String, enabled: Bool = true, action: @escaping () -> Void) {
            let item = NSMenuItem(
                title: title,
                action: enabled ? #selector(ClosureMenuActionHandler.performMenuAction(_:)) : nil,
                keyEquivalent: ""
            )
            if enabled {
                item.target = ClosureMenuActionHandler.shared
                item.representedObject = action
            }
            item.isEnabled = enabled
            if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
                item.image = img
            }
            menu.addItem(item)
        }

        let hasSel = selectedCellContext != nil
        addItem("Quote Selected Cell Code", icon: "curlybraces", enabled: hasSel) {
            self.insertSelectedCellSnippet(includeOutput: false)
        }
        addItem("Quote Cell + Output / Traceback", icon: "exclamationmark.bubble", enabled: hasSel) {
            self.insertSelectedCellSnippet(includeOutput: true)
        }
        menu.addItem(.separator())
        addItem("Attach Dataset File…", icon: "tablecells.badge.ellipsis") {
            self.viewModel.showingDataFilePicker = true
        }
        addItem("Insert Inline Agent Cell", icon: "plus.rectangle.on.rectangle") {
            self.viewModel.addCell(type: .agent)
        }

        let loc = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: loc, in: nil)
    }

    private func presentMentionMenu() {
        let menu = NSMenu(title: "Mention Context")
        menu.autoenablesItems = false

        func addHeader(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        func addAction(_ title: String, icon: String, action: @escaping () -> Void) {
            let item = NSMenuItem(
                title: title,
                action: #selector(ClosureMenuActionHandler.performMenuAction(_:)),
                keyEquivalent: ""
            )
            item.target = ClosureMenuActionHandler.shared
            item.representedObject = action
            if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
                item.image = img
            }
            menu.addItem(item)
        }

        let liveVars = SharedMemoryService.shared.activeVariables(for: viewModel.activeNotebookId)
        addHeader("Live Kernel Variables")
        if liveVars.isEmpty {
            let emptyItem = NSMenuItem(title: "No active RAM variables yet (run a Python cell)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for v in liveVars.prefix(18) {
                let shapePart = v.shape.isEmpty ? "" : " (\(v.shape))"
                addAction("@\(v.name) · \(v.typeName)\(shapePart)", icon: "memorychip") {
                    let sep = (self.inputText.isEmpty || self.inputText.hasSuffix(" ") || self.inputText.hasSuffix("\n")) ? "" : " "
                    self.inputText += "\(sep)@\(v.name) "
                    self.isComposerFocused = true
                }
            }
        }

        if let nb = viewModel.activeNotebook, !nb.cells.isEmpty {
            menu.addItem(.separator())
            addHeader("Notebook Cells")
            for (idx, c) in nb.cells.prefix(20).enumerated() {
                let label = c.type == .agent ? "Agent" : (c.type == .markdown ? "Markdown" : c.language.rawValue)
                let preview = c.content.replacingOccurrences(of: "\n", with: " ").prefix(28)
                addAction("@Cell#\(idx + 1) · \(label) — \(preview)", icon: "number.square") {
                    let sep = (self.inputText.isEmpty || self.inputText.hasSuffix(" ") || self.inputText.hasSuffix("\n")) ? "" : " "
                    self.inputText += "\(sep)@Cell#\(idx + 1) "
                    self.isComposerFocused = true
                }
            }
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: - Context Builders & Actions

    private func buildNotebookContext(userPrompt: String = "") -> String {
        var baseContext: String
        if focusSelectedCellOnly,
           let nb = viewModel.activeNotebook,
           let sel = selectedCellContext {
            let cell = sel.cell
            var ctx = "## Active Notebook: \(nb.name) (Focused on Cell #\(sel.number) of \(nb.cells.count))\n"
            ctx += "- Working Directory: `\(viewModel.workingDirectory.path)`\n"
            ctx += "### Focused Cell #\(sel.number) (id: `\(cell.id.uuidString)`, type: \(cell.type.rawValue), lang: \(cell.language.rawValue))\n"
            ctx += "```\(cell.language.fileExtension)\n\(cell.content)\n```\n"
            if !cell.output.isEmpty {
                ctx += "Output:\n```\n\(cell.output.prefix(2000))\n```\n"
            }
            baseContext = ctx
        } else {
            baseContext = CellAgentCoordinator.shared.buildNotebookContextSnapshot(viewModel: viewModel)
        }

        // Inject Live Kernel Variables overview + expanded `@var` & `@Cell#N` mentions
        let liveVars = SharedMemoryService.shared.activeVariables(for: viewModel.activeNotebookId)
        if !liveVars.isEmpty {
            baseContext += "\n### Live Kernel RAM Variables (\(liveVars.count)):\n"
            for v in liveVars.prefix(24) {
                let shapeInfo = v.shape.isEmpty ? "" : " shape=\(v.shape)"
                let colInfo = v.columns.isEmpty ? "" : " cols=[\(v.columns.prefix(12).joined(separator: ", "))]"
                baseContext += "- `\(v.name)` (\(v.typeName)\(shapeInfo), \(v.formattedMemory))\(colInfo)\n"
            }
            for v in liveVars where userPrompt.contains("@\(v.name)") {
                baseContext += SharedMemoryService.shared.variableMentionSnapshot(
                    variableName: v.name,
                    notebookId: viewModel.activeNotebookId
                ) + "\n"
            }
        }

        if let nb = viewModel.activeNotebook, userPrompt.contains("@Cell#") {
            for (idx, c) in nb.cells.enumerated() where userPrompt.contains("@Cell#\(idx + 1)") {
                baseContext += "\n### Explicitly Mentioned @Cell#\(idx + 1) (\(c.language.rawValue)):\n"
                baseContext += "```\(c.language.fileExtension)\n\(c.content)\n```\n"
                if !c.output.isEmpty {
                    baseContext += "Output:\n```\n\(c.output.prefix(2000))\n```\n"
                }
            }
        }

        return baseContext
    }

    private func insertSelectedCellSnippet(includeOutput: Bool) {
        guard let sel = selectedCellContext else { return }
        let cell = sel.cell
        var snippet = "\n[Cell #\(sel.number) (\(cell.language.rawValue))]:\n```\(cell.language.fileExtension)\n\(cell.content)\n```"
        if includeOutput && !cell.output.isEmpty {
            snippet += "\n[Output]:\n```\n\(cell.output.prefix(1200))\n```"
        }
        inputText += (inputText.isEmpty ? "" : "\n") + snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        isComposerFocused = true
    }

    private func stopExecution() {
        CellAgentCoordinator.shared.stop(sessionId: panelSessionId)
        isLoading = false
        currentStatus = ""
    }

    private func retryMessage(_ msg: CellAIMessage) {
        guard !isLoading else { return }
        if msg.role == .user {
            inputText = msg.content
            sendMessage()
        } else if let idx = messages.firstIndex(where: { $0.id == msg.id }), idx > 0 {
            let prev = messages[idx - 1]
            if prev.role == .user {
                messages.remove(at: idx)
                inputText = prev.content
                messages.remove(at: idx - 1)
                sendMessage()
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        let sel = activeSelection
        let modelTitle = sel.conciseModelTitle(appState: appState)
        let brandKey = sel.brandIconKey(appState: appState)
        let agentTurn = isAgentMode

        messages.append(CellAIMessage(role: .user, content: text))

        let responseId = UUID().uuidString
        messages.append(CellAIMessage(
            id: responseId,
            role: .assistant,
            content: "",
            thought: "",
            toolSteps: [],
            modelLabel: modelTitle,
            brandKey: brandKey,
            isAgentTurn: agentTurn
        ))

        let priorHistory: [(role: String, content: String)] = messages.dropLast(2)
            .filter { !$0.content.isEmpty && !$0.isError }
            .map { (role: $0.role.rawValue, content: $0.content) }

        let notebookContext = buildNotebookContext(userPrompt: text)
        let workspaceRoot = appState.workspaceFolder?.path ?? viewModel.workingDirectory.path

        isLoading = true
        currentStatus = agentTurn ? "Inspecting notebook…" : "Generating…"

        CellAgentCoordinator.shared.startExecution(
            sessionId: panelSessionId,
            prompt: text,
            selection: sel,
            isAgentMode: agentTurn,
            appState: appState,
            notebookContext: notebookContext,
            workspaceRoot: workspaceRoot,
            conversationHistory: priorHistory,
            onStatus: { status in
                self.currentStatus = status
            },
            onThought: { thought in
                if let idx = self.messages.firstIndex(where: { $0.id == responseId }) {
                    self.messages[idx].thought = thought
                }
            },
            onText: { liveText in
                if let idx = self.messages.firstIndex(where: { $0.id == responseId }) {
                    self.messages[idx].content = liveText
                }
            },
            onToolSteps: { steps in
                if let idx = self.messages.firstIndex(where: { $0.id == responseId }) {
                    self.messages[idx].toolSteps = steps
                }
            },
            onComplete: { finalText in
                if let idx = self.messages.firstIndex(where: { $0.id == responseId }) {
                    if self.messages[idx].content.isEmpty && !finalText.isEmpty {
                        self.messages[idx].content = finalText
                    } else if self.messages[idx].content.isEmpty && !self.messages[idx].toolSteps.isEmpty {
                        self.messages[idx].content = "Completed \(self.messages[idx].toolSteps.count) notebook actions."
                    }
                }
                self.isLoading = false
                self.currentStatus = ""
            },
            onError: { error in
                if let idx = self.messages.firstIndex(where: { $0.id == responseId }) {
                    let prefix = self.messages[idx].content.isEmpty ? "" : self.messages[idx].content + "\n\n"
                    self.messages[idx].content = prefix + "Error: \(error)"
                    self.messages[idx].isError = true
                }
                self.isLoading = false
                self.currentStatus = ""
            }
        )
    }

    private func sendSuggestion(_ suggestion: CellAISuggestion) {
        inputText = suggestion.text
        sendMessage()
    }
}

// MARK: - Models

struct CellAIMessage: Identifiable {
    let id: String
    let role: Role
    var content: String
    var thought: String
    var toolSteps: [CellAgentToolStep]
    var modelLabel: String
    var brandKey: String
    var isAgentTurn: Bool
    var isError: Bool
    let timestamp: Date

    enum Role: String {
        case user, assistant
    }

    init(
        id: String = UUID().uuidString,
        role: Role,
        content: String,
        thought: String = "",
        toolSteps: [CellAgentToolStep] = [],
        modelLabel: String = "",
        brandKey: String = "microcode",
        isAgentTurn: Bool = true,
        isError: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thought = thought
        self.toolSteps = toolSteps
        self.modelLabel = modelLabel
        self.brandKey = brandKey
        self.isAgentTurn = isAgentTurn
        self.isError = isError
        self.timestamp = Date()
    }
}

struct CellAISuggestion {
    let icon: String
    let text: String
}

// MARK: - Formal IDE Message Row (User Prompt Card & Borderless Assistant Turn)

struct CellAIMessageRow: View {
    let message: CellAIMessage
    var availableWidth: CGFloat? = nil
    var onRetry: (() -> Void)? = nil
    @EnvironmentObject var appState: AppState
    @State private var isCopied = false
    @State private var isHovered = false

    private var isDark: Bool {
        appState.appTheme.isDark
    }

    var body: some View {
        Group {
            if message.role == .user {
                // Formal left-aligned IDE prompt block (no bright blue chat bubble)
                Text(message.content)
                    .font(.system(size: 12.5))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(isDark ? 0.065 : 0.045))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(isDark ? 0.11 : 0.08), lineWidth: 0.8)
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
            } else {
                // Flat, borderless executive assistant turn (zero boxes-inside-boxes)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        AIProviderBrandIcon(provider: message.brandKey, size: 11.5)
                            .fixedSize()

                        Text(message.modelLabel.isEmpty ? "Assistant" : message.modelLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text("· \(message.isAgentTurn ? "Agent" : "Ask")")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary.opacity(0.65))
                            .fixedSize()

                        Spacer(minLength: 4)

                        if !message.content.isEmpty && (isHovered || isCopied) {
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                                isCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { isCopied = false }
                            }) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(isCopied ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                            .help("Copy Response")
                        }

                        if message.isError, let onRetry {
                            Button(action: onRetry) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 9))
                                    Text("Retry")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.primary.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.07))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                        }
                    }

                    // 1. Collapsible Reasoning Trace
                    if !message.thought.isEmpty {
                        AntigravityThoughtBlockView(content: message.thought, durationSeconds: nil)
                    }

                    // 2. Formal Borderless Collapsible Tool Timeline
                    if !message.toolSteps.isEmpty {
                        CellAgentToolStepsTimeline(steps: message.toolSteps)
                    }

                    // 3. Rich Markdown & Code Content
                    if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        CellAIRichContentView(
                            content: message.content,
                            isError: message.isError,
                            maxCodeBlockWidth: availableWidth != nil ? max(180, availableWidth! - 28) : nil
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
            }
        }
        .frame(width: availableWidth, alignment: .leading)
    }
}

// MARK: - Reusable Rich Markdown & Code Block Renderer for Both Panel & Inline Agent Cells

struct CellAIRichContentView: View {
    let content: String
    var isError: Bool = false
    var maxCodeBlockWidth: CGFloat? = nil

    var body: some View {
        let blocks = MessageContentParser.parse(content)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block {
                case .thought(let thoughtText, let duration):
                    AntigravityThoughtBlockView(content: thoughtText, durationSeconds: duration)
                case .text(let text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        CellAITextView(text: text, isError: isError)
                    }
                case .code(let lang, let code):
                    CellAICodeBlockView(language: lang, code: code, maxWidth: maxCodeBlockWidth)
                case .heading(let level, let title):
                    Text(title)
                        .font(.system(size: level <= 2 ? 14 : 12.5, weight: .semibold))
                        .foregroundColor(.primary)
                case .list(let items, _):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundColor(.secondary)
                                CellAITextView(text: item)
                            }
                        }
                    }
                case .media(let kind, let title, let target):
                    ChatMediaBlockView(kind: kind, title: title, target: target)
                default:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Cell AI Text View (Inline Markdown)

struct CellAITextView: View {
    let text: String
    var isError: Bool = false

    var body: some View {
        Text(parseInlineMarkdown(text))
            .font(.system(size: 12.5))
            .lineSpacing(2)
            .foregroundColor(isError ? Color.red.opacity(0.9) : .primary.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        }
        return AttributedString(text)
    }
}

// MARK: - Responsive Formal Code Block with 1-Click Cell Actions

struct CellAICodeBlockView: View {
    let language: String
    let code: String
    var maxWidth: CGFloat? = nil
    @EnvironmentObject var appState: AppState

    @State private var isCopied = false
    @State private var actionFeedback: String? = nil

    private var isDark: Bool {
        appState.appTheme.isDark
    }

    private var codeCardBg: Color {
        appState.appTheme.isGlass
            ? Color.primary.opacity(0.045)
            : Color(nsColor: appState.appTheme.editorBackground)
    }

    private var headerBg: Color {
        Color.primary.opacity(isDark ? 0.055 : 0.035)
    }

    private var cardBorder: Color {
        Color.primary.opacity(isDark ? 0.12 : 0.09)
    }

    private var lineCount: Int {
        max(1, code.utf8.reduce(1) { $0 + ($1 == 0x0A ? 1 : 0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                codeHeader(showButtonLabels: true)
                codeHeader(showButtonLabels: false)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(headerBg)

            Divider().opacity(0.45)

            if lineCount > 14 {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Text(code)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.9))
                        .fixedSize(horizontal: true, vertical: true)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(maxWidth: .infinity, maxHeight: 250, alignment: .topLeading)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(code)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.9))
                        .fixedSize(horizontal: true, vertical: true)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: maxWidth ?? .infinity, alignment: .leading)
        .background(codeCardBg)
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(cardBorder, lineWidth: 0.8)
        )
        .clipped()
    }

    @ViewBuilder
    private func codeHeader(showButtonLabels: Bool) -> some View {
        HStack(spacing: 5) {
            Text(language.isEmpty ? "code" : language.lowercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize()

            if let fb = actionFeedback {
                Text(fb)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            Spacer(minLength: 4)

            codeActionBtn(
                icon: "plus.rectangle",
                label: showButtonLabels ? "Insert" : nil,
                tooltip: "Insert as a new cell below"
            ) {
                postCellAction(mode: "insert", autoRun: false, feedback: "Inserted")
            }

            codeActionBtn(
                icon: "arrow.down.doc",
                label: showButtonLabels ? "Apply" : nil,
                tooltip: "Apply to selected cell"
            ) {
                postCellAction(mode: "replace_selected", autoRun: false, feedback: "Applied")
            }

            codeActionBtn(
                icon: "play.fill",
                label: showButtonLabels ? "Run" : nil,
                tooltip: "Insert as new cell and run"
            ) {
                postCellAction(mode: "insert", autoRun: true, feedback: "Running")
            }

            Button(action: copyCode) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9.5))
                    .foregroundColor(isCopied ? .green : .secondary)
                    .frame(width: 20, height: 18)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Copy Code")
        }
    }

    @ViewBuilder
    private func codeActionBtn(icon: String, label: String?, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                if let label {
                    Text(label)
                        .font(.system(size: 9.5, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundColor(.primary.opacity(0.82))
            .padding(.horizontal, label != nil ? 6 : 5)
            .padding(.vertical, 2.5)
            .background(Color.primary.opacity(isDark ? 0.07 : 0.05))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(tooltip)
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isCopied = false }
    }

    private func postCellAction(mode: String, autoRun: Bool, feedback: String) {
        NotificationCenter.default.post(
            name: Notification.Name("ApplyCodeToCell"),
            object: nil,
            userInfo: [
                "code": code,
                "language": language,
                "mode": mode,
                "autoRun": autoRun
            ]
        )
        actionFeedback = "· \(feedback)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { actionFeedback = nil }
    }
}
