//
//  AIAgentChatStageAndCells.swift
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

// MARK: - Agent Cell Mode View

struct AgentCellModeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var agent = AgentService.shared
    @AppStorage("agentCellMode.defaultAgentMode") private var defaultAgentMode: Bool = true
    @AppStorage("agentCellMode.defaultRole") private var defaultRole: String = CellSubAgentRole.mainAgent.rawValue

    @State private var cells: [AgentCell] = [
        AgentCell(type: .ai, input: "", isAgentMode: true)
    ]
    @State private var focusedCellId: UUID? = nil

    private var workspaceBg: Color {
        appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.workspaceBackground)
    }

    private var panelBg: Color {
        appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground)
    }

    private var elevatedBg: Color {
        appState.appTheme.isGlass
            ? Color.primary.opacity(0.06)
            : Color(nsColor: appState.appTheme.elevatedBackground)
    }

    private var subtleBorder: Color {
        Color.primary.opacity(appState.appTheme.isDark ? 0.11 : 0.09)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Theme-Harmonized Context & Model Bar
            cellContextBar

            Divider().opacity(0.6)

            // Cells
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if cells.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "rectangle.grid.1x2")
                                    .font(.system(size: 32))
                                    .foregroundColor(.accentColor.opacity(0.35))
                                Text("No cells yet")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("Add an AI Agent, Code, or Markdown cell below")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 44)
                        } else {
                            ForEach($cells) { $cell in
                                AgentCellRow(
                                    cell: $cell,
                                    isFocused: focusedCellId == cell.id,
                                    onFocus: { focusedCellId = cell.id },
                                    onRun: { toggleRunOrStopCell(cell) },
                                    onDelete: { deleteCell(cell.id) },
                                    onInsertBelow: { insertCell(below: cell.id) }
                                )
                                .id(cell.id)
                            }
                        }

                        addCellButton
                    }
                    .padding(.vertical, 12)
                    .padding(.bottom, 84)
                }
                .background(workspaceBg)
                .onChange(of: cells.count) { _ in
                    if let lastId = cells.last?.id {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(workspaceBg)
    }

    // MARK: - Context & Unified AI Selector Bar

    private var cellContextBar: some View {
        HStack(spacing: 7) {
            Text("Notebook Cells")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary.opacity(0.88))
                .lineLimit(1)
                .fixedSize()

            CellModeTogglePill(isAgentMode: $defaultAgentMode, compact: true)
                .fixedSize()

            if let workspace = appState.workspaceFolder {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        Text("·")
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(workspace.lastPathComponent)
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .fixedSize()
                    EmptyView()
                }
            }

            Spacer(minLength: 4)

            CellAIModelSelectorPill(
                selection: nil,
                showRoleSelector: defaultAgentMode,
                roleBinding: $defaultRole,
                maxWidth: 215,
                compact: true,
                minimalChrome: true
            )

            Button(action: runAllCells) {
                HStack(spacing: 3.5) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8.5))
                    Text("Run All")
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.primary.opacity(0.88))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(subtleBorder, lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Execute all cells sequentially")
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(panelBg)
    }

    // MARK: - Add Cell Bar

    private var addCellButton: some View {
        HStack(spacing: 10) {
            addPill(icon: "brain.head.profile", label: "AI Agent", tint: .accentColor) {
                var sel = CellAISelection.inherit
                sel.subAgentRole = defaultRole
                cells.append(AgentCell(type: .ai, isAgentMode: defaultAgentMode, aiSelection: sel))
            }
            addPill(icon: "chevron.left.forwardslash.chevron.right", label: "Code", tint: .blue) {
                cells.append(AgentCell(type: .code))
            }
            addPill(icon: "doc.richtext", label: "Markdown", tint: .orange) {
                cells.append(AgentCell(type: .markdown))
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func addPill(icon: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.primary.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(elevatedBg)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(subtleBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cell Execution & Cancellation

    private func runAllCells() {
        for cell in cells where !cell.isRunning {
            runCell(cell)
        }
    }

    private func toggleRunOrStopCell(_ cell: AgentCell) {
        if cell.isRunning {
            stopCell(cell.id)
        } else {
            runCell(cell)
        }
    }

    private func stopCell(_ cellId: UUID) {
        CellAgentCoordinator.shared.stop(sessionId: "ws-agent-cell-\(cellId.uuidString)")
        if let idx = cells.firstIndex(where: { $0.id == cellId }) {
            cells[idx].isRunning = false
            cells[idx].statusText = ""
        }
    }

    private func runCell(_ cell: AgentCell) {
        guard let idx = cells.firstIndex(where: { $0.id == cell.id }) else { return }
        let cellId = cell.id

        if cell.type == .markdown {
            cells[idx].isRunning = false
            cells[idx].output = cell.input
            return
        }

        let trimmedInput = cell.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        cells[idx].isRunning = true
        cells[idx].output = ""
        cells[idx].thought = ""
        cells[idx].toolSteps = []
        cells[idx].isError = false

        // Real multi-language execution for Code Cells
        if cell.type == .code {
            cells[idx].statusText = "Executing \(cell.language)…"
            let lang = cell.language
            Task {
                do {
                    let result = try await PlaygroundRunTool().execute(params: [
                        "code": trimmedInput,
                        "language": lang
                    ])
                    await MainActor.run {
                        if let i = self.cells.firstIndex(where: { $0.id == cellId }) {
                            self.cells[i].output = result
                            self.cells[i].statusText = ""
                            self.cells[i].isRunning = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        if let i = self.cells.firstIndex(where: { $0.id == cellId }) {
                            self.cells[i].output = "⚠️ Execution error: \(error.localizedDescription)"
                            self.cells[i].isError = true
                            self.cells[i].statusText = ""
                            self.cells[i].isRunning = false
                        }
                    }
                }
            }
            return
        }

        // Unified Multi-Provider AI & Autonomous Agent Execution for AI Cells
        var context = "## Workspace & Preceding Cells Context\n"
        let workspaceRoot = appState.workspaceFolder?.path ?? FileManager.default.currentDirectoryPath
        context += "- Workspace: `\(workspaceRoot)`\n"
        if let file = appState.currentFile {
            context += "- Active Editor File: `\(file.name)` (\(file.language))\n```\(file.language)\n\(file.content.prefix(2500))\n```\n\n"
        }
        for (pIdx, prevCell) in cells.enumerated() where prevCell.id != cellId {
            if !prevCell.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                context += "### Cell #\(pIdx + 1) (\(prevCell.type.label) - \(prevCell.language))\n"
                context += "```\n\(prevCell.input.prefix(800))\n```\n"
                if !prevCell.output.isEmpty {
                    context += "Output:\n```\n\(prevCell.output.prefix(800))\n```\n"
                }
            }
        }

        var effectiveSel = cell.aiSelection
        if effectiveSel.useGlobal && effectiveSel.subAgentRole == CellSubAgentRole.dataScientist.rawValue {
            effectiveSel.subAgentRole = defaultRole
        }
        let sessionId = "ws-agent-cell-\(cellId.uuidString)"
        cells[idx].statusText = cell.isAgentMode ? "Agent working…" : "Generating…"

        CellAgentCoordinator.shared.startExecution(
            sessionId: sessionId,
            prompt: trimmedInput,
            selection: effectiveSel,
            isAgentMode: cell.isAgentMode,
            appState: appState,
            notebookContext: context,
            workspaceRoot: workspaceRoot,
            onStatus: { status in
                if let i = self.cells.firstIndex(where: { $0.id == cellId }) {
                    self.cells[i].statusText = status
                }
            },
            onThought: { thought in
                if let i = self.cells.firstIndex(where: { $0.id == cellId }) {
                    self.cells[i].thought = thought
                }
            },
            onText: { liveText in
                if let i = self.cells.firstIndex(where: { $0.id == cellId }) {
                    self.cells[i].output = liveText
                }
            },
            onToolSteps: { steps in
                if let i = self.cells.firstIndex(where: { $0.id == cellId }) {
                    self.cells[i].toolSteps = steps
                }
            },
            onComplete: { finalText in
                if let i = self.cells.firstIndex(where: { $0.id == cellId }) {
                    if self.cells[i].output.isEmpty && !finalText.isEmpty {
                        self.cells[i].output = finalText
                    } else if self.cells[i].output.isEmpty && !self.cells[i].toolSteps.isEmpty {
                        self.cells[i].output = "ดำเนินการเสร็จเรียบร้อย (\(self.cells[i].toolSteps.count) tool steps)"
                    }
                    self.cells[i].statusText = ""
                    self.cells[i].isRunning = false
                }
            },
            onError: { err in
                if let i = self.cells.firstIndex(where: { $0.id == cellId }) {
                    let prefix = self.cells[i].output.isEmpty ? "" : self.cells[i].output + "\n\n"
                    self.cells[i].output = prefix + "⚠️ \(err)"
                    self.cells[i].isError = true
                    self.cells[i].statusText = ""
                    self.cells[i].isRunning = false
                }
            }
        )
    }

    private func deleteCell(_ id: UUID) {
        stopCell(id)
        guard let idx = cells.firstIndex(where: { $0.id == id }) else { return }
        cells.remove(at: idx)
        if focusedCellId == id {
            focusedCellId = cells.first?.id
        }
    }

    private func insertCell(below id: UUID) {
        if let idx = cells.firstIndex(where: { $0.id == id }) {
            var sel = CellAISelection.inherit
            sel.subAgentRole = defaultRole
            cells.insert(AgentCell(type: .ai, isAgentMode: defaultAgentMode, aiSelection: sel), at: idx + 1)
        }
    }
}

// MARK: - Agent Cell Model

struct AgentCell: Identifiable {
    let id = UUID()
    var type: CellType
    var input: String = ""
    var output: String = ""
    var thought: String = ""
    var toolSteps: [CellAgentToolStep] = []
    var statusText: String = ""
    var isRunning: Bool = false
    var isError: Bool = false
    var language: String = "python"
    var isAgentMode: Bool = true
    var aiSelection: CellAISelection = .inherit

    enum CellType: String {
        case code = "code"
        case markdown = "markdown"
        case ai = "ai"

        var icon: String {
            switch self {
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .markdown: return "doc.richtext"
            case .ai: return "brain.head.profile"
            }
        }

        var color: Color {
            switch self {
            case .code: return .blue
            case .markdown: return .orange
            case .ai: return .accentColor
            }
        }

        var label: String {
            switch self {
            case .code: return "Code"
            case .markdown: return "Markdown"
            case .ai: return "Agent"
            }
        }
    }
}

// MARK: - Theme-Native Agent Cell Row

struct AgentCellRow: View {
    @Binding var cell: AgentCell
    let isFocused: Bool
    let onFocus: () -> Void
    let onRun: () -> Void
    let onDelete: () -> Void
    let onInsertBelow: () -> Void

    @EnvironmentObject var appState: AppState
    @State private var isHovering = false

    private var cardBg: Color {
        appState.appTheme.isGlass
            ? Color.primary.opacity(0.045)
            : Color(nsColor: appState.appTheme.elevatedBackground)
    }

    private var headerBg: Color {
        appState.appTheme.isGlass
            ? Color.primary.opacity(0.06)
            : Color(nsColor: appState.appTheme.panelBackground)
    }

    private var borderColor: Color {
        if isFocused { return Color.accentColor }
        return Color.primary.opacity(appState.appTheme.isDark ? 0.12 : 0.09)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cellHeader

            Divider().opacity(0.45)

            cellInput

            if !cell.output.isEmpty || !cell.thought.isEmpty || !cell.toolSteps.isEmpty || cell.isRunning {
                Divider().opacity(0.45)
                cellOutput
            }
        }
        .background(cardBg)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
        .onHover { isHovering = $0 }
        .transaction { $0.animation = nil }
    }

    private var cellHeader: some View {
        HStack(spacing: 6) {
            // Cell Type Menu (Switchable per cell)
            Menu {
                Button { cell.type = .ai } label: { Label("AI Agent Cell", systemImage: "brain.head.profile") }
                Button { cell.type = .code } label: { Label("Code Cell", systemImage: "chevron.left.forwardslash.chevron.right") }
                Button { cell.type = .markdown } label: { Label("Markdown Cell", systemImage: "doc.richtext") }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: cell.type.icon)
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(cell.type == .ai ? (cell.isAgentMode ? "Agent" : "Ask") : cell.type.label)
                        .font(.system(size: 9.5, weight: .bold))
                }
                .foregroundColor(cell.type.color)
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2.5)
                .background(cell.type.color.opacity(0.13))
                .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if cell.type == .code {
                Menu {
                    ForEach(["python", "swift", "ardium", "javascript", "typescript", "rust", "go", "cpp", "r", "julia", "bash", "sql"], id: \.self) { lang in
                        Button(lang) { cell.language = lang }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(cell.language)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else if cell.type == .ai {
                CellModeTogglePill(isAgentMode: $cell.isAgentMode, compact: true)
                    .fixedSize()

                CellAIModelSelectorPill(
                    selection: $cell.aiSelection,
                    showRoleSelector: cell.isAgentMode,
                    maxWidth: 215,
                    compact: true,
                    minimalChrome: true
                )
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Button(action: onRun) {
                    HStack(spacing: 3) {
                        Image(systemName: cell.isRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 8.5))
                        Text(cell.isRunning ? "Stop" : "Run")
                            .font(.system(size: 9.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(.primary.opacity(0.88))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.primary.opacity(0.07))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(cell.isRunning ? "Stop Execution" : "Run Cell")

                HStack(spacing: 4) {
                    Button(action: onInsertBelow) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Insert Cell Below")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Delete Cell")
                }
                .opacity(isHovering || isFocused ? 1 : 0)
                .allowsHitTesting(isHovering || isFocused)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(headerBg)
    }

    private var cellInput: some View {
        ZStack(alignment: .topLeading) {
            if cell.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(cell.type == .ai
                     ? (cell.isAgentMode ? "สั่ง Agent ให้ตรวจสอบ แก้ไขโค้ด หรือรันเครื่องมือ…" : "ถามคำถามหรือให้ AI สร้างโค้ด…")
                     : (cell.type == .code ? "พิมพ์โค้ด \(cell.language) แล้วกด Run…" : "พิมพ์บันทึก Markdown…"))
                    .font(.system(size: 12, design: cell.type == .code ? .monospaced : .default))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $cell.input)
                .font(.system(size: 12.5, design: cell.type == .code ? .monospaced : .default))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 50, maxHeight: 260)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var cellOutput: some View {
        VStack(alignment: .leading, spacing: 8) {
            if cell.isRunning {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.75)
                    Text(cell.statusText.isEmpty ? "Working…" : cell.statusText)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
            }

            if !cell.thought.isEmpty {
                AntigravityThoughtBlockView(content: cell.thought, durationSeconds: nil)
            }

            if !cell.toolSteps.isEmpty {
                CellAgentToolStepsTimeline(steps: cell.toolSteps)
            }

            if !cell.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if cell.type == .ai {
                    CellAIRichContentView(content: cell.output, isError: cell.isError)
                } else {
                    ScrollView {
                        Text(cell.output)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(cell.isError ? .red : .primary.opacity(0.9))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 280)
                }
            }
        }
        .padding(10)
        .background(
            appState.appTheme.isGlass
                ? Color.primary.opacity(0.03)
                : Color(nsColor: appState.appTheme.workspaceBackground).opacity(0.55)
        )
    }
}

// MARK: - Header Button (Reusable)

struct HeaderIconButton: View {
    let icon: String
    let label: String?
    var isActive: Bool = false
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isActive {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                
                if let text = label {
                    Text(text)
                        .font(.system(size: 11))
                }
            }
            .foregroundColor(isHovering || isActive ? .primary : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isHovering ? Color.white.opacity(0.1) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Rich Message Renderer

enum GeneratedMediaKind: String, Equatable {
    case image
    case video
    case audio
}

enum MessageBlock: Identifiable {
    case thought(String, Int?) // Content, duration in seconds
    case text(String)
    case code(String, String) // Language, Content
    case heading(Int, String) // Level (1-6), Content
    case list([String], Bool) // Items, isOrdered
    case table([String], [[String]]) // Headers, Rows
    case blockquote(String)
    case latex(String, Bool) // Expression, isBlock ($$...$$ vs $...$)
    case html(String)
    case media(GeneratedMediaKind, String, String) // Kind, Title/Alt, URL or Path
    
    var id: String {
        switch self {
        case .thought(let c, let d):
            if d == nil { return "thought-streaming" }
            return "thought-\(c.hashValue)"
        case .text(let c): return "text-\(c.hashValue)"
        case .code(let l, let c): return "code-\(l)-\(c.hashValue)"
        case .heading(let lv, let c): return "h\(lv)-\(c.hashValue)"
        case .list(let items, _): return "list-\(items.hashValue)"
        case .table(let h, let r): return "table-\(h.joined())-\(r.count)"
        case .blockquote(let c): return "quote-\(c.hashValue)"
        case .latex(let e, _): return "latex-\(e.hashValue)"
        case .html(let c): return "html-\(c.hashValue)"
        case .media(let k, let t, let u): return "media-\(k.rawValue)-\(t.hashValue)-\(u.hashValue)"
        }
    }
}

struct MessageContentParser {
    private static var parseCache: [String: [MessageBlock]] = [:]
    private static var parseOrder: [String] = []
    private static let lock = NSLock()
    // Large tool payloads are already retained by the transcript store. Keeping a
    // second copy as a String dictionary key causes avoidable memory growth and
    // makes scrolling a long conversation progressively more expensive.
    private static let maximumCachedContentCharacters = 120_000
    
    // Pre-compiled static regexes to eliminate repeated allocations and compilation on every streamed token
    private static let thoughtRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<thought>([\\s\\S]*?)</thought>|<thinking>([\\s\\S]*?)</thinking>|<think>([\\s\\S]*?)</think>",
        options: [.caseInsensitive]
    )
    private static let latexRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "\\$\\$([\\s\\S]*?)\\$\\$|\\\\\\[([\\s\\S]*?)\\\\\\]|\\\\begin\\{(equation\\*?|align\\*?|aligned|gather\\*?|multline\\*?|math|displaymath)\\}([\\s\\S]*?)\\\\end\\{\\3\\}",
        options: []
    )
    private static let codeRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "```([^\\r\\n`]*?)\\r?\\n([\\s\\S]*?)```",
        options: []
    )
    private static let orderedListRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^\\d+\\.\\s+",
        options: []
    )
    
    static func parse(_ content: String) -> [MessageBlock] {
        let shouldCache = content.count <= maximumCachedContentCharacters
        guard shouldCache else {
            return doParse(content)
        }

        lock.lock()
        if let cached = parseCache[content] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        let blocks = doParse(content)
        
        lock.lock()
        if parseCache.count > 500 {
            if let first = parseOrder.first {
                parseCache.removeValue(forKey: first)
                parseOrder.removeFirst()
            }
        }
        parseCache[content] = blocks
        parseOrder.append(content)
        lock.unlock()
        
        return blocks
    }
    
    private static func findUnclosedThought(in text: String) -> (before: String, thought: String)? {
        let tags: [(open: String, close: String)] = [
            ("<thought>", "</thought>"),
            ("<thinking>", "</thinking>"),
            ("<think>", "</think>")
        ]
        
        for (openTag, closeTag) in tags {
            if let openRange = text.range(of: openTag, options: .caseInsensitive) {
                let afterTag = text[openRange.upperBound...]
                if afterTag.range(of: closeTag, options: .caseInsensitive) != nil {
                    return nil // Full match handled by regex
                }
                let before = String(text[..<openRange.lowerBound])
                let thought = String(afterTag).trimmingCharacters(in: .whitespacesAndNewlines)
                return (before: before, thought: thought)
            }
        }
        return nil
    }
    
    private static func findOrphanClosingThought(in text: String) -> (thought: String, after: String)? {
        let closingTags = ["</thought>", "</thinking>", "</think>"]
        for closeTag in closingTags {
            if let closeRange = text.range(of: closeTag, options: .caseInsensitive) {
                let beforeTag = text[..<closeRange.lowerBound]
                let openTags = ["<thought>", "<thinking>", "<think>"]
                let hasOpen = openTags.contains(where: { beforeTag.range(of: $0, options: .caseInsensitive) != nil })
                if !hasOpen {
                    let thought = String(beforeTag).trimmingCharacters(in: .whitespacesAndNewlines)
                    let after = String(text[closeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (thought: thought, after: after)
                }
            }
        }
        return nil
    }
    
    private static var thoughtStartTimes: [String: Date] = [:]
    private static var completedThoughtDurations: [Int: Int] = [:]
    private static var activeUnclosedStartTime: Date?
    private static let durationLock = NSLock()

    private static func recordStreamingThought(_ rawThought: String) {
        durationLock.lock()
        defer { durationLock.unlock() }
        let now = Date()
        if activeUnclosedStartTime == nil {
            activeUnclosedStartTime = now
        }
        let clean = rawThought.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count >= 40 {
            let key = String(clean.prefix(40))
            if thoughtStartTimes[key] == nil {
                thoughtStartTimes[key] = activeUnclosedStartTime ?? now
            }
        }
    }

    private static func resolveThoughtDuration(for clean: String) -> Int {
        durationLock.lock()
        defer { durationLock.unlock() }
        let hash = clean.hashValue
        if let cached = completedThoughtDurations[hash] {
            return cached
        }
        let key = String(clean.prefix(40))
        if let start = thoughtStartTimes[key] ?? activeUnclosedStartTime {
            let elapsed = max(1, Int(Date().timeIntervalSince(start).rounded()))
            completedThoughtDurations[hash] = elapsed
            activeUnclosedStartTime = nil
            return elapsed
        }
        // Fallback for historical persisted messages loaded from disk (~850 chars/sec for modern reasoning models)
        let fallback = max(1, min(120, clean.count / 850))
        completedThoughtDurations[hash] = fallback
        return fallback
    }

    private static func doParse(_ content: String) -> [MessageBlock] {
        let remaining = AIStructuredTurnCodec.stripToolCallArtifacts(content)
        let hasClosingThoughtTag =
            remaining.range(of: "</think", options: .caseInsensitive) != nil ||
            remaining.range(of: "</thought", options: .caseInsensitive) != nil
        
        // 0. Extract <thought>...</thought>, <thinking>...</thinking>, or <think>...</think>
        if hasClosingThoughtTag, let thoughtRegex = thoughtRegex {
            let nsContent = remaining as NSString
            let thoughtMatches = thoughtRegex.matches(in: remaining, options: [], range: NSRange(location: 0, length: nsContent.length))
            
            if !thoughtMatches.isEmpty {
                var lastEnd = 0
                var parsedList: [MessageBlock] = []
                
                for match in thoughtMatches {
                    if match.range.location > lastEnd {
                        let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                        let beforeText = nsContent.substring(with: beforeRange)
                        if !beforeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            parsedList.append(contentsOf: parseLatexAndCode(beforeText))
                        }
                    }
                    
                    var thoughtBody = ""
                    if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                        thoughtBody = nsContent.substring(with: match.range(at: 1))
                    } else if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                        thoughtBody = nsContent.substring(with: match.range(at: 2))
                    } else if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound {
                        thoughtBody = nsContent.substring(with: match.range(at: 3))
                    }
                    
                    let clean = thoughtBody.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty {
                        let durationSec = resolveThoughtDuration(for: clean)
                        parsedList.append(.thought(clean, durationSec))
                    }
                    
                    lastEnd = match.range.location + match.range.length
                }
                
                if lastEnd < nsContent.length {
                    let afterText = nsContent.substring(from: lastEnd)
                    if let unclosed = findUnclosedThought(in: afterText) {
                        if !unclosed.before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            parsedList.append(contentsOf: parseLatexAndCode(unclosed.before))
                        }
                        recordStreamingThought(unclosed.thought)
                        parsedList.append(.thought(unclosed.thought, nil))
                    } else if let orphan = findOrphanClosingThought(in: afterText) {
                        if !orphan.thought.isEmpty {
                            parsedList.append(.thought(orphan.thought, resolveThoughtDuration(for: orphan.thought)))
                        }
                        if !orphan.after.isEmpty {
                            parsedList.append(contentsOf: parseLatexAndCode(orphan.after))
                        }
                    } else if !afterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        parsedList.append(contentsOf: parseLatexAndCode(afterText))
                    }
                }
                
                return parsedList
            }
        }
        
        // Check for orphan closing tag without opening tag (e.g. "Let me start.</thought>")
        if hasClosingThoughtTag, let orphan = findOrphanClosingThought(in: remaining) {
            var parsedList: [MessageBlock] = []
            if !orphan.thought.isEmpty {
                parsedList.append(.thought(orphan.thought, resolveThoughtDuration(for: orphan.thought)))
            }
            if !orphan.after.isEmpty {
                parsedList.append(contentsOf: parseLatexAndCode(orphan.after))
            }
            return parsedList
        }
        
        // Check for streaming / unclosed thought without closing tag
        if let unclosed = findUnclosedThought(in: remaining) {
            var parsedList: [MessageBlock] = []
            if !unclosed.before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parsedList.append(contentsOf: parseLatexAndCode(unclosed.before))
            }
            recordStreamingThought(unclosed.thought)
            parsedList.append(.thought(unclosed.thought, nil))
            return parsedList
        }
        
        return parseLatexAndCode(remaining)
    }
    
    private static func parseLatexAndCode(_ content: String) -> [MessageBlock] {
        var remaining = content
        
        // Sanitize any stray/residual reasoning tags to prevent leaking raw XML into prose
        let strayTags = ["</thought>", "</thinking>", "</think>", "<thought>", "<thinking>", "<think>"]
        for tag in strayTags {
            remaining = remaining.replacingOccurrences(of: tag, with: "")
        }
        
        // Extract fenced code blocks FIRST so `$$` or `\[...\]` inside code blocks are never misparsed as LaTeX
        return parseCodeBlocks(remaining)
    }
    
    private static func parseMathAndTextContent(_ text: String) -> [MessageBlock] {
        if let latexRegex = latexRegex {
            let nsContent = text as NSString
            let latexMatches = latexRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsContent.length))
            if !latexMatches.isEmpty {
                var blocks: [MessageBlock] = []
                var lastEnd = 0
                for match in latexMatches {
                    if match.range.location > lastEnd {
                        let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                        let beforeText = nsContent.substring(with: beforeRange)
                        blocks.append(contentsOf: parseTextContent(beforeText))
                    }
                    var latexContent = ""
                    if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                        latexContent = nsContent.substring(with: match.range(at: 1))
                    } else if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                        latexContent = nsContent.substring(with: match.range(at: 2))
                    } else if match.numberOfRanges > 4, match.range(at: 4).location != NSNotFound {
                        let envName = match.range(at: 3).location != NSNotFound ? nsContent.substring(with: match.range(at: 3)) : "aligned"
                        let inner = nsContent.substring(with: match.range(at: 4))
                        latexContent = "\\begin{\(envName)}\(inner)\\end{\(envName)}"
                    }
                    blocks.append(.latex(latexContent.trimmingCharacters(in: .whitespacesAndNewlines), true))
                    lastEnd = match.range.location + match.range.length
                }
                if lastEnd < nsContent.length {
                    let afterText = nsContent.substring(from: lastEnd)
                    blocks.append(contentsOf: parseTextContent(afterText))
                }
                return blocks
            }
        }
        return parseTextContent(text)
    }
    
    private static func normalizeBlockquoteCodeFences(_ raw: String) -> String {
        guard raw.contains("```") && raw.contains(">") else { return raw }
        let lines = raw.components(separatedBy: "\n")
        var out: [String] = []
        out.reserveCapacity(lines.count)
        var insideQuotedFence = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") {
                let afterArrow = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if afterArrow.hasPrefix("```") {
                    insideQuotedFence.toggle()
                    out.append(afterArrow)
                    continue
                } else if insideQuotedFence {
                    let stripped = line.replacingOccurrences(of: "^\\s*>\\s?", with: "", options: .regularExpression)
                    out.append(stripped)
                    continue
                }
            } else if trimmed.hasPrefix("```") && insideQuotedFence {
                insideQuotedFence = false
            }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    private static func parseCodeBlocks(_ rawContent: String) -> [MessageBlock] {
        let content = normalizeBlockquoteCodeFences(rawContent)
        var blocks: [MessageBlock] = []
        
        // Extract code blocks, converting latex/math to LaTeX blocks
        if let regex = codeRegex {
            let nsContent = content as NSString
            let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))
            
            var lastEnd = 0
            for match in matches {
                // Text before code block
                if match.range.location > lastEnd {
                    let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                    let beforeText = nsContent.substring(with: beforeRange)
                    blocks.append(contentsOf: parseMathAndTextContent(beforeText))
                }
                
                // Code block
                let langRange = match.range(at: 1)
                let codeRange = match.range(at: 2)
                let lang = langRange.location != NSNotFound ? nsContent.substring(with: langRange) : ""
                let code = codeRange.location != NSNotFound ? nsContent.substring(with: codeRange) : ""
                let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Check if this is a LaTeX/math code block - render as LaTeX
                let lowerLang = lang.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if lowerLang == "latex" || lowerLang == "math" || lowerLang == "tex" {
                    blocks.append(.latex(trimmedCode, true))
                } else if lowerLang == "markdown" || lowerLang == "md" || lowerLang.hasSuffix(".md") {
                    blocks.append(contentsOf: parseMathAndTextContent(trimmedCode))
                } else {
                    blocks.append(.code(lang, trimmedCode))
                }
                
                lastEnd = match.range.location + match.range.length
            }
            
            // Remaining text after last code block (including unclosed streaming code fence)
            if lastEnd < nsContent.length {
                let afterText = nsContent.substring(from: lastEnd)
                if let fenceRange = afterText.range(of: "```") {
                    let prefixText = String(afterText[..<fenceRange.lowerBound])
                    if !prefixText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        blocks.append(contentsOf: parseMathAndTextContent(prefixText))
                    }
                    let fenceBody = String(afterText[fenceRange.upperBound...])
                    let firstNewline = fenceBody.firstIndex(of: "\n")
                    let lang = firstNewline != nil ? String(fenceBody[..<firstNewline!]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                    let code = firstNewline != nil ? String(fenceBody[fenceBody.index(after: firstNewline!)...]) : fenceBody
                    blocks.append(.code(lang, code.trimmingCharacters(in: .newlines)))
                } else {
                    blocks.append(contentsOf: parseMathAndTextContent(afterText))
                }
            }
        } else {
            // Fallback: simple split
            blocks.append(contentsOf: parseMathAndTextContent(content))
        }
        
        return blocks
    }
    
    private static func parseTextContent(_ text: String) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        let lines = text.components(separatedBy: "\n")
        var currentText: [String] = []
        var listItems: [String] = []
        var isOrderedList = false
        var lineIndex = 0
        
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check for Markdown Table (| col1 | col2 |)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.contains("|") && lineIndex + 1 < lines.count {
                let nextLine = lines[lineIndex + 1].trimmingCharacters(in: .whitespaces)
                if nextLine.hasPrefix("|") && (nextLine.contains("---") || nextLine.contains("-|-") || nextLine.contains(":--") || nextLine.contains("--:")) {
                    // Flush current text
                    if !currentText.isEmpty {
                        blocks.append(.text(currentText.joined(separator: "\n")))
                        currentText = []
                    }
                    // Flush list
                    if !listItems.isEmpty {
                        blocks.append(.list(listItems, isOrderedList))
                        listItems = []
                    }
                    
                    // Parse headers from current line
                    let headers = trimmed.split(separator: "|", omittingEmptySubsequences: true).map { String($0).trimmingCharacters(in: .whitespaces) }
                    
                    var tableRows: [[String]] = []
                    lineIndex += 2 // Skip header line and separator line
                    
                    while lineIndex < lines.count {
                        let rowLine = lines[lineIndex].trimmingCharacters(in: .whitespaces)
                        if rowLine.hasPrefix("|") && rowLine.hasSuffix("|") {
                            let cells = rowLine.split(separator: "|", omittingEmptySubsequences: true).map { String($0).trimmingCharacters(in: .whitespaces) }
                            if !cells.isEmpty {
                                tableRows.append(cells)
                            }
                            lineIndex += 1
                        } else {
                            break
                        }
                    }
                    
                    if !headers.isEmpty {
                        blocks.append(.table(headers, tableRows))
                    }
                    continue
                }
            }
            
            // Check for headings (# H1, ## H2, etc.)
            if let match = trimmed.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.joined(separator: "\n")))
                    currentText = []
                }
                if !listItems.isEmpty {
                    blocks.append(.list(listItems, isOrderedList))
                    listItems = []
                }
                
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let heading = String(trimmed[match.upperBound...])
                blocks.append(.heading(level, heading))
                lineIndex += 1
                continue
            }
            
            // Check for block LaTeX ($$...$$)
            if trimmed.hasPrefix("$$") && trimmed.hasSuffix("$$") && trimmed.count > 4 {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.joined(separator: "\n")))
                    currentText = []
                }
                let latex = String(trimmed.dropFirst(2).dropLast(2))
                blocks.append(.latex(latex, true))
                lineIndex += 1
                continue
            }
            
            // Check for blockquote (> ...)
            if trimmed.hasPrefix("> ") {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.joined(separator: "\n")))
                    currentText = []
                }
                if !listItems.isEmpty {
                    blocks.append(.list(listItems, isOrderedList))
                    listItems = []
                }
                blocks.append(.blockquote(String(trimmed.dropFirst(2))))
                lineIndex += 1
                continue
            }
            
            // Check for horizontal divider line (--- or ***)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.joined(separator: "\n")))
                    currentText = []
                }
                if !listItems.isEmpty {
                    blocks.append(.list(listItems, isOrderedList))
                    listItems = []
                }
                blocks.append(.html("<hr/>"))
                lineIndex += 1
                continue
            }
            
            // Check for unordered list (- or * item)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.joined(separator: "\n")))
                    currentText = []
                }
                isOrderedList = false
                listItems.append(String(trimmed.dropFirst(2)))
                lineIndex += 1
                continue
            }
            
            // Check for ordered list (1. item)
            if let _ = trimmed.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.joined(separator: "\n")))
                    currentText = []
                }
                isOrderedList = true
                listItems.append(String(trimmed.drop(while: { $0.isNumber || $0 == "." || $0 == " " })))
                lineIndex += 1
                continue
            }
            
            // Flush list if we hit non-list line
            if !listItems.isEmpty && !trimmed.isEmpty {
                blocks.append(.list(listItems, isOrderedList))
                listItems = []
            }
            
            // Skip legacy emoji wrapper lines around media cards
            if trimmed.hasPrefix("🖼️ **Generated") ||
               trimmed.hasPrefix("🎬 **Generated") ||
               trimmed.hasPrefix("🎵 **Generated") ||
               trimmed.hasPrefix("📁 Saved to:") {
                lineIndex += 1
                continue
            }
            
            // Check for Markdown Media ![alt](url_or_path)
            if let mediaMatch = extractMarkdownMedia(from: trimmed) {
                if !currentText.isEmpty {
                    let joined = currentText.joined(separator: "\n")
                    if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        blocks.append(.text(joined))
                    }
                    currentText = []
                }
                blocks.append(.media(mediaMatch.kind, mediaMatch.alt, mediaMatch.target))
                lineIndex += 1
                continue
            }
            
            // Regular text
            currentText.append(line)
            lineIndex += 1
        }
        
        // Flush remaining
        if !listItems.isEmpty {
            blocks.append(.list(listItems, isOrderedList))
        }
        if !currentText.isEmpty {
            let joined = currentText.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(joined))
            }
        }
        
        return blocks
    }
    
    private static func extractMarkdownMedia(from line: String) -> (kind: GeneratedMediaKind, alt: String, target: String)? {
        guard let bangIdx = line.range(of: "![") else { return nil }
        let afterBang = line[bangIdx.upperBound...]
        guard let closeBracket = afterBang.range(of: "](") else { return nil }
        let alt = String(afterBang[..<closeBracket.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let afterParen = afterBang[closeBracket.upperBound...]
        guard let closeParen = afterParen.lastIndex(of: ")") else { return nil }
        let rawTarget = String(afterParen[..<closeParen]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTarget.isEmpty else { return nil }
        
        let lowerTarget = rawTarget.lowercased()
        let lowerAlt = alt.lowercased()
        let kind: GeneratedMediaKind
        if lowerTarget.hasSuffix(".mp4") || lowerTarget.hasSuffix(".mov") || lowerTarget.hasSuffix(".webm") || lowerTarget.hasSuffix(".m4v") || lowerTarget.contains("video/") || lowerAlt.contains("video") {
            kind = .video
        } else if lowerTarget.hasSuffix(".mp3") || lowerTarget.hasSuffix(".wav") || lowerTarget.hasSuffix(".m4a") || lowerTarget.hasSuffix(".ogg") || lowerTarget.hasSuffix(".aac") || lowerTarget.hasSuffix(".flac") || lowerTarget.contains("audio/") || lowerAlt.contains("music") || lowerAlt.contains("audio") {
            kind = .audio
        } else {
            kind = .image
        }
        return (kind, alt.isEmpty ? "Generated Media" : alt, rawTarget)
    }
}

// MARK: - Chat Stage

/// Non-reactive reference box so high-frequency 120Hz NSEvent.scrollWheel ticks
/// never trigger SwiftUI @State body re-evaluations on AgentChatStage.
private final class ChatScrollInteractionTracker {
    var lastUserScrollUpTime: Date = .distantPast
    var lastAutoScrollTime: Date = .distantPast
    var distanceFromBottom: CGFloat = 0
    var lastMessageCount: Int = 0
    var lastKnownLastMessageId: String? = nil
    weak var scrollView: NSScrollView? = nil
    var boundsObserver: NSObjectProtocol? = nil
    var monitor: Any? = nil

    deinit {
        if let obs = boundsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let mon = monitor {
            NSEvent.removeMonitor(mon)
        }
    }
}

private struct ChatScrollViewIntrospector: NSViewRepresentable {
    let tracker: ChatScrollInteractionTracker
    let onBottomStateChanged: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            attachIfNeeded(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if tracker.scrollView == nil {
            DispatchQueue.main.async {
                attachIfNeeded(from: nsView)
            }
        }
    }

    private func attachIfNeeded(from view: NSView) {
        guard let sv = view.enclosingScrollView else { return }
        guard tracker.scrollView !== sv else { return }
        tracker.scrollView = sv
        sv.contentView.postsBoundsChangedNotifications = true
        if let oldObs = tracker.boundsObserver {
            NotificationCenter.default.removeObserver(oldObs)
        }
        tracker.boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: sv.contentView,
            queue: .main
        ) { [weak sv, weak tracker] _ in
            guard let sv = sv, let tracker = tracker, let docView = sv.documentView else { return }
            let docHeight = docView.bounds.height
            let visibleMaxY = sv.contentView.bounds.maxY
            let dist = max(0, docHeight - visibleMaxY)
            tracker.distanceFromBottom = dist
            if dist <= 36 && Date().timeIntervalSince(tracker.lastUserScrollUpTime) > 0.16 {
                onBottomStateChanged(true)
            }
        }
    }
}

struct AgentChatStage: View, Equatable {
    @EnvironmentObject var appState: AppState
    let messages: [AgentMessageModel]
    let isLoading: Bool
    var domain: AgentDomain = .software
    var currentToolExecution: String? = nil
    var hasEarlierMessages: Bool = false
    var queuedMessages: [QueuedMessage] = []
    var activeChatId: String? = nil
    var onApplyChange: ((PendingChangeModel) -> Void)? = nil
    var onRejectChange: ((PendingChangeModel) -> Void)? = nil
    var onSuggestionTap: ((String) -> Void)? = nil
    var onViewPlan: (() -> Void)? = nil
    var onRevertToMessage: ((String) -> Void)? = nil
    var onEditAndResendMessage: ((String, String) -> Void)? = nil
    var onRetryAssistantMessage: ((String) -> Void)? = nil
    var onDeleteMessage: ((String, Bool) -> Void)? = nil
    
    @ObservedObject private var planManager = ImplementationPlanManager.shared
    @State private var userScrolledUp: Bool = false
    @State private var scrollTracker = ChatScrollInteractionTracker()
    
    static func == (lhs: AgentChatStage, rhs: AgentChatStage) -> Bool {
        lhs.isLoading == rhs.isLoading &&
        lhs.domain == rhs.domain &&
        lhs.currentToolExecution == rhs.currentToolExecution &&
        lhs.hasEarlierMessages == rhs.hasEarlierMessages &&
        lhs.queuedMessages.count == rhs.queuedMessages.count &&
        lhs.activeChatId == rhs.activeChatId &&
        lhs.messages.count == rhs.messages.count &&
        lhs.messages.first?.id == rhs.messages.first?.id &&
        lhs.messages.last?.id == rhs.messages.last?.id &&
        lhs.messages.last?.content == rhs.messages.last?.content &&
        lhs.messages.last?.toolResults.count == rhs.messages.last?.toolResults.count &&
        lhs.messages.last?.pendingChanges == rhs.messages.last?.pendingChanges
    }
    
    var body: some View {
        GeometryReader { stageGeo in
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                if messages.isEmpty && !isLoading && queuedMessages.isEmpty {
                                    VStack(spacing: 20) {
                                        Spacer().frame(height: 40)
                                        
                                        VStack(spacing: 6) {
                                            Text(domain == .science ? "Science Agent" : "AI Agent")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.primary.opacity(0.8))
                                            
                                            Text(domain == .science ? "Analyze evidence, structures, data, and scientific literature" : "Ask anything, write code, debug, or explore ideas")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                                .multilineTextAlignment(.center)
                                        }
                                        
                                        // Quick suggestions
                                        VStack(spacing: 8) {
                                            ForEach(domain == .science ? [
                                                "Analyze the scientific evidence in this project",
                                                "Compare wild-type and mutant structures",
                                                "Validate the AlphaFold workflow and confidence",
                                                "Draft a LaTeX research report from project evidence"
                                            ] : [
                                                "Explain this code",
                                                "Find bugs in my project",
                                                "Refactor for performance",
                                                "Write unit tests"
                                            ], id: \.self) { suggestion in
                                                Button(action: {
                                                    onSuggestionTap?(suggestion)
                                                }) {
                                                    HStack {
                                                        Text(suggestion)
                                                            .font(.system(size: 11))
                                                            .foregroundColor(.primary.opacity(0.7))
                                                        Spacer()
                                                    }
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 10)
                                                    .background(Color.primary.opacity(0.035))
                                                    .cornerRadius(5)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 5)
                                                            .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .frame(maxWidth: 720)
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 24)
                                        .padding(.top, 8)
                                        
                                        Spacer()
                                    }
                                } else {
                                    if hasEarlierMessages {
                                        Button("Load earlier messages") {
                                            AgentService.shared.loadEarlierMessages()
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 12)
                                    }
                                    let lastMessageId = messages.last?.id
                                    ForEach(messages) { message in
                                        RichMessageRow(
                                            message: message,
                                            isStreaming: isLoading && message.id == lastMessageId,
                                            onApplyChange: onApplyChange,
                                            onRejectChange: onRejectChange,
                                            onRevert: { onRevertToMessage?(message.id) },
                                            onEditAndResend: { editedText in onEditAndResendMessage?(message.id, editedText) },
                                            onRetry: { onRetryAssistantMessage?(message.id) },
                                            onDelete: { revertFiles in onDeleteMessage?(message.id, revertFiles) }
                                        )
                                        .equatable()
                                        .frame(width: max(0, stageGeo.size.width))
                                        .clipped()
                                        .id(message.id)
                                    }
                                    
                                    if messages.isEmpty && isLoading,
                                       let activeTool = currentToolExecution, !activeTool.isEmpty {
                                        HStack(spacing: 0) {
                                            Spacer(minLength: 0)
                                            HStack(spacing: 10) {
                                                ProgressView()
                                                    .controlSize(.small)
                                                Text(activeTool)
                                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                                Spacer()
                                            }
                                            .padding(14)
                                            .background(Color.primary.opacity(0.04))
                                            .cornerRadius(8)
                                            .frame(maxWidth: 880)
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 12)
                                    }
                                    
                                    // Render any queued user messages directly in the chat stream so they never appear to vanish
                                    ForEach(queuedMessages) { queued in
                                        HStack(spacing: 0) {
                                            Spacer(minLength: 0)
                                            VStack(alignment: .trailing, spacing: 6) {
                                                if !queued.attachments.isEmpty {
                                                    SentUserAttachmentsView(
                                                        items: queued.attachments.map { SentAttachmentItem.from($0) }
                                                    )
                                                    .environmentObject(appState)
                                                }
                                                let trimmedQueued = queued.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                                if !trimmedQueued.isEmpty || queued.attachments.isEmpty {
                                                    HStack(spacing: 0) {
                                                        Spacer(minLength: 88)
                                                        Text(queued.text.count > 500 ? String(queued.text.prefix(500)) + "…" : queued.text)
                                                            .font(Font.custom(appState.agentFontName, size: appState.agentFontSize))
                                                            .foregroundColor(.primary.opacity(0.9))
                                                            .multilineTextAlignment(.leading)
                                                            .lineLimit(6)
                                                            .padding(12)
                                                            .background(Color.orange.opacity(0.14))
                                                            .overlay(
                                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                                                            )
                                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                            .frame(maxWidth: 620, alignment: .trailing)
                                                    }
                                                }
                                                HStack(spacing: 8) {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "clock.fill")
                                                            .font(.system(size: 9))
                                                        Text("อยู่ในคิว (จะส่งต่ออัตโนมัติ)")
                                                            .font(.system(size: 10, weight: .medium))
                                                    }
                                                    .foregroundColor(.orange)
                                                    
                                                    Button(action: {
                                                        AgentService.shared.stopGeneration(autoProcessQueue: true)
                                                    }) {
                                                        Text("ส่งทันที (Send Now)")
                                                            .font(.system(size: 10, weight: .semibold))
                                                            .foregroundColor(.accentColor)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.accentColor.opacity(0.12))
                                                            .cornerRadius(4)
                                                    }
                                                    .buttonStyle(.plain)
                                                    
                                                    Button(action: {
                                                        AgentService.shared.cancelQueuedMessage(id: queued.id)
                                                    }) {
                                                        Text("ยกเลิก")
                                                            .font(.system(size: 10))
                                                            .foregroundColor(.secondary)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .frame(maxWidth: 880, alignment: .trailing)
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .id("queued_\(queued.id.uuidString)")
                                    }
                                    
                                    Color.clear
                                        .frame(height: 20)
                                        .id("BOTTOM_CHAT_ANCHOR")
                                        .background(
                                            ChatScrollViewIntrospector(tracker: scrollTracker) { reachedBottom in
                                                if reachedBottom && userScrolledUp {
                                                    userScrolledUp = false
                                                }
                                            }
                                        )
                                }
                            }
                            .textSelection(.enabled)
                            .frame(width: max(0, stageGeo.size.width))
                        }
                        
                        // Floating "Scroll to latest" button when user scrolls up
                        if userScrolledUp && !messages.isEmpty {
                            Button(action: {
                                userScrolledUp = false
                                scrollTracker.lastUserScrollUpTime = .distantPast
                                withAnimation(.easeOut(duration: 0.15)) {
                                    proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 9.5, weight: .bold))
                                    Text("Latest messages")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(nsColor: appState.appTheme.elevatedBackground))
                                .cornerRadius(14)
                                .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 10)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    
                    // Inline plan approval card docked cleanly below ScrollView so "Latest messages" never overlaps it
                    if let _ = planManager.currentPlan, !messages.isEmpty {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            PlanApprovalInlineCard(
                                planManager: planManager,
                                onViewPlan: onViewPlan
                            )
                            .environmentObject(appState)
                            .frame(maxWidth: 880)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
                .onChange(of: activeChatId) { _ in
                userScrolledUp = false
                scrollTracker.lastUserScrollUpTime = .distantPast
                scrollTracker.lastMessageCount = messages.count
                scrollTracker.lastKnownLastMessageId = messages.last?.id
                DispatchQueue.main.async {
                    proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                }
            }
            .onChange(of: messages.count) { newCount in
                let didAppend = newCount > scrollTracker.lastMessageCount
                scrollTracker.lastMessageCount = newCount
                scrollTracker.lastKnownLastMessageId = messages.last?.id
                let isNewUserTurn = didAppend && (
                    messages.last?.role == .user
                    || (messages.count >= 2 && messages[messages.count - 2].role == .user && messages.last?.id == "streaming")
                )
                if isNewUserTurn || !userScrolledUp {
                    if isNewUserTurn {
                        userScrolledUp = false
                        scrollTracker.lastUserScrollUpTime = .distantPast
                    }
                    DispatchQueue.main.async {
                        proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                    }
                }
            }
            .onChange(of: messages.last?.id) { newLastId in
                let changedId = newLastId != scrollTracker.lastKnownLastMessageId
                scrollTracker.lastKnownLastMessageId = newLastId
                let isNewUserTurn = changedId && messages.last?.role == .user
                if isNewUserTurn || !userScrolledUp {
                    if isNewUserTurn {
                        userScrolledUp = false
                        scrollTracker.lastUserScrollUpTime = .distantPast
                    }
                    DispatchQueue.main.async {
                        proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                    }
                }
            }
            .onChange(of: queuedMessages.count) { newCount in
                if newCount > 0 {
                    userScrolledUp = false
                    scrollTracker.lastUserScrollUpTime = .distantPast
                    DispatchQueue.main.async {
                        proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                    }
                }
            }
            .onChange(of: messages.last?.toolResults.count) { _ in
                if !userScrolledUp {
                    proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                }
            }
            .onChange(of: isLoading) { loading in
                if loading && !userScrolledUp {
                    proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                }
            }
            .onChange(of: messages.last?.content) { _ in
                if !userScrolledUp {
                    let now = Date()
                    if now.timeIntervalSince(scrollTracker.lastAutoScrollTime) >= 0.08 {
                        scrollTracker.lastAutoScrollTime = now
                        proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                    }
                }
            }
            .onAppear {
                scrollTracker.lastMessageCount = messages.count
                scrollTracker.lastKnownLastMessageId = messages.last?.id
                if !messages.isEmpty {
                    proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                }
                if scrollTracker.monitor == nil {
                    let tracker = scrollTracker
                    scrollTracker.monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
                        if let sv = tracker.scrollView {
                            guard event.window === sv.window else { return event }
                            let localPt = sv.convert(event.locationInWindow, from: nil)
                            guard sv.bounds.contains(localPt) else { return event }
                        }
                        // Ignore momentum/rubber-band bounce so scrolling to the bottom never trips userScrolledUp
                        let isDirectInput = (event.momentumPhase == [])
                        if isDirectInput && event.scrollingDeltaY > 0.4 {
                            tracker.lastUserScrollUpTime = Date()
                            if !userScrolledUp {
                                userScrolledUp = true
                            }
                        } else if event.scrollingDeltaY < -0.4 {
                            if tracker.distanceFromBottom <= 65 && userScrolledUp {
                                userScrolledUp = false
                            }
                        }
                        return event
                    }
                }
            }
            .onDisappear {
                if let monitor = scrollTracker.monitor {
                    NSEvent.removeMonitor(monitor)
                    scrollTracker.monitor = nil
                }
                if let obs = scrollTracker.boundsObserver {
                    NotificationCenter.default.removeObserver(obs)
                    scrollTracker.boundsObserver = nil
                }
            }
            .clipped()
            }
        }
    }
}

