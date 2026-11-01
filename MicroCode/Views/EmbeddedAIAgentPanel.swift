//
//  EmbeddedAIAgentPanel.swift
//  MicroCode
//
//  Autonomous Hardware-in-the-Loop (HIL) AI Agent for Embed & IoT Studio.
//  Supports All Providers (Subscription, BYOK, Local LLM, ACP Harnesses, Sovereign Omni),
//  [Agent | Ask] mode toggle, live HIL tool timeline (embedded_list_hardware, embedded_compile,
//  embedded_flash, embedded_serial_capture, embedded_serial_send, embedded_decode_crash),
//  and responsive width-constrained layout with AppKit Enter-to-send composer.
//
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import SwiftUI
import AppKit
import Combine

// MARK: - Models for Embedded HIL AI

struct EmbeddedAIMessage: Identifiable, Equatable {
    let id: String
    let role: Role
    var content: String
    var thought: String
    var toolSteps: [CellAgentToolStep]
    var modelBadge: String
    var isAgentTurn: Bool
    let timestamp: Date

    enum Role: String {
        case user
        case assistant
        case system
    }

    init(
        id: String = UUID().uuidString,
        role: Role,
        content: String,
        thought: String = "",
        toolSteps: [CellAgentToolStep] = [],
        modelBadge: String = "",
        isAgentTurn: Bool = true,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thought = thought
        self.toolSteps = toolSteps
        self.modelBadge = modelBadge
        self.isAgentTurn = isAgentTurn
        self.timestamp = timestamp
    }
}

struct EmbeddedAISuggestion: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let prompt: String
}

// MARK: - Embedded HIL AI ViewModel

@MainActor
final class EmbeddedAIAgentViewModel: ObservableObject {
    @Published var messages: [EmbeddedAIMessage] = []
    @Published var isLoading: Bool = false
    @Published var currentStatus: String = ""
    @Published var lastAppliedNotice: String? = nil

    private let sessionId = "embedded-hil-agent-\(UUID().uuidString.prefix(8))"

    func cancelStream() {
        CellAgentCoordinator.shared.stop(sessionId: sessionId)
        AIClient.shared.cancelStream()
        isLoading = false
        currentStatus = ""
    }

    func clearMessages() {
        cancelStream()
        messages.removeAll()
    }

    func deleteMessage(id: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        if isLoading && idx == messages.count - 1 {
            cancelStream()
        }
        messages.remove(at: idx)
    }

    @discardableResult
    func revertToMessage(id: String) -> String? {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return nil }
        if isLoading {
            cancelStream()
        }
        let target = messages[idx]
        messages.removeSubrange(idx..<messages.count)
        return target.role == .user ? target.content : nil
    }

    func triggerNotice(_ text: String) {
        lastAppliedNotice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.lastAppliedNotice == text {
                self?.lastAppliedNotice = nil
            }
        }
    }

    func sendPrompt(
        text: String,
        selection: CellAISelection,
        isAgentMode: Bool,
        appState: AppState,
        hardwareContext: String,
        workspaceRoot: String
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(EmbeddedAIMessage(role: .user, content: trimmed))

        let responseId = UUID().uuidString
        let badge = selection.conciseModelTitle(appState: appState)
        messages.append(EmbeddedAIMessage(
            id: responseId,
            role: .assistant,
            content: "",
            thought: "",
            toolSteps: [],
            modelBadge: badge,
            isAgentTurn: isAgentMode
        ))

        let priorHistory: [(role: String, content: String)] = messages.dropLast(2).map {
            (role: $0.role.rawValue, content: $0.content)
        }

        isLoading = true
        currentStatus = isAgentMode ? "Probing hardware & firmware context…" : "Synthesizing firmware…"

        var hilSelection = selection
        hilSelection.subAgentRole = CellSubAgentRole.embeddedHardware.rawValue

        CellAgentCoordinator.shared.startExecution(
            sessionId: sessionId,
            prompt: trimmed,
            selection: hilSelection,
            isAgentMode: isAgentMode,
            appState: appState,
            notebookContext: hardwareContext,
            workspaceRoot: workspaceRoot,
            conversationHistory: priorHistory,
            maxAgentTurns: 12,
            onStatus: { [weak self] status in
                self?.currentStatus = status
            },
            onThought: { [weak self] thought in
                guard let self, let idx = self.messages.firstIndex(where: { $0.id == responseId }) else { return }
                self.messages[idx].thought = thought
            },
            onText: { [weak self] visible in
                guard let self, let idx = self.messages.firstIndex(where: { $0.id == responseId }) else { return }
                self.messages[idx].content = visible
            },
            onToolSteps: { [weak self] steps in
                guard let self, let idx = self.messages.firstIndex(where: { $0.id == responseId }) else { return }
                self.messages[idx].toolSteps = steps
            },
            onComplete: { [weak self] finalText in
                guard let self else { return }
                if let idx = self.messages.firstIndex(where: { $0.id == responseId }),
                   !finalText.isEmpty {
                    self.messages[idx].content = finalText
                }
                self.isLoading = false
                self.currentStatus = ""
            },
            onError: { [weak self] err in
                guard let self else { return }
                if let idx = self.messages.firstIndex(where: { $0.id == responseId }) {
                    let prefix = self.messages[idx].content.isEmpty ? "" : self.messages[idx].content + "\n\n"
                    self.messages[idx].content = prefix + "AI Error: \(err)"
                }
                self.isLoading = false
                self.currentStatus = ""
            }
        )
    }
}

// MARK: - Embedded HIL AI Agent Panel

struct EmbeddedAIAgentPanel: View {
    @Binding var isShowing: Bool
    @Binding var editorSourceCode: String
    let selectedBoard: HardwareBoardTarget
    let selectedPort: RealSerialPort?
    let editorLanguage: EmbeddedSourceLanguage
    let buildLogOutput: String
    let consoleEntries: [SerialConsoleEntry]
    @ObservedObject var envManager: EmbeddedEnvManager

    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = EmbeddedAIAgentViewModel()
    @ObservedObject private var elfService = ELFMemoryAndDwarfService.shared

    @State private var inputText: String = ""
    @State private var isAgentMode: Bool = true
    @State private var aiSelection: CellAISelection = {
        var s = CellAISelection.inherit
        s.subAgentRole = CellSubAgentRole.embeddedHardware.rawValue
        return s
    }()
    @State private var attachHardwareContext: Bool = true
    @State private var isComposerFocused: Bool = false

    private var isDark: Bool { appState.appTheme.isDark }
    private var panelBg: Color { isDark ? Color.black : Color(white: 0.98) }
    private var headerBg: Color { isDark ? Color(white: 0.05) : Color(white: 0.93) }
    private var stripBg: Color { isDark ? Color(white: 0.03) : Color(white: 0.95) }
    private var cardBg: Color { isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.04) }
    private var cardBorderColor: Color { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.10) }
    private var dividerLineColor: Color { isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08) }

    private var liveDRC: PinDRCReport {
        PinConflictDRCAnalyzer.analyze(code: editorSourceCode, board: selectedBoard)
    }

    private var suggestions: [EmbeddedAISuggestion] {
        var list: [EmbeddedAISuggestion] = []

        let hasBuildError = buildLogOutput.contains("error:") || buildLogOutput.contains("[ERROR]") || buildLogOutput.contains("[FAILED]")
        let hasGuruMeditation = consoleEntries.contains(where: {
            $0.content.contains("Guru Meditation") || $0.content.contains("Backtrace:") || $0.content.contains("HardFault")
        })

        if hasBuildError {
            list.append(EmbeddedAISuggestion(
                icon: "wrench.and.screwdriver.fill",
                text: "Auto-Fix & Recompile",
                prompt: "Analyze the compiler errors in my current firmware, patch the sketch, and run `embedded_compile` until it compiles cleanly with zero errors."
            ))
        }

        if hasGuruMeditation {
            list.append(EmbeddedAISuggestion(
                icon: "ladybug.fill",
                text: "Decode Crash & Fix",
                prompt: "Use `embedded_decode_crash` on the recent crash backtrace from serial, pinpoint the exact faulting C++ line, fix the sketch, and verify with `embedded_compile`."
            ))
        }

        if !liveDRC.warnings.isEmpty {
            list.append(EmbeddedAISuggestion(
                icon: "bolt.trianglebadge.exclamationmark.fill",
                text: "Resolve Pin DRC (\(liveDRC.warnings.count))",
                prompt: "My current sketch has GPIO electrical DRC warnings (\(liveDRC.warnings.map(\.message).joined(separator: "; "))). Reassign the conflicting pins safely for \(selectedBoard.rawValue) and verify compilation."
            ))
        }

        if selectedPort != nil {
            list.append(EmbeddedAISuggestion(
                icon: "bolt.horizontal.circle.fill",
                text: "Compile, Flash & Verify UART",
                prompt: "Cross-compile the current firmware with `embedded_compile`, flash it to the connected board via `embedded_flash`, and capture 3 seconds of live UART telemetry with `embedded_serial_capture` to confirm boot."
            ))
        }

        list.append(EmbeddedAISuggestion(
            icon: "cpu.fill",
            text: "FreeRTOS Dual-Core Pipeline",
            prompt: "Write and compile a production \(editorLanguage.rawValue) FreeRTOS firmware for \(selectedBoard.rawValue) with non-blocking sensor sampling and `>sensor:value` plotter telemetry."
        ))

        list.append(EmbeddedAISuggestion(
            icon: "memorychip",
            text: "Optimize ELF Flash & RAM",
            prompt: "Compile the current sketch with `embedded_compile`, inspect the real ELF Flash/SRAM byte usage, and optimize static buffers and string literals."
        ))

        return list
    }

    var body: some View {
        GeometryReader { geo in
            mainPanelLayout(geoSize: geo.size)
        }
    }

    private func mainPanelLayout(geoSize: CGSize) -> some View {
        let contentWidth = max(220, geoSize.width - 24)
        return VStack(spacing: 0) {
            panelHeader
            Rectangle().fill(dividerLineColor).frame(height: 1)

            hardwareContextStrip
            Rectangle().fill(dividerLineColor).frame(height: 1)

            if let notice = viewModel.lastAppliedNotice {
                appliedNoticeBanner(notice)
            }

            messagesScrollStage(geoWidth: geoSize.width, contentWidth: contentWidth)

            if !viewModel.messages.isEmpty {
                quickSuggestionsBar
                Rectangle().fill(dividerLineColor).frame(height: 1)
            }

            promptInputBar
        }
        .frame(width: geoSize.width, height: geoSize.height)
        .background(panelBg)
        .clipped()
    }

    private func appliedNoticeBanner(_ notice: String) -> some View {
        let fg: Color = isDark ? .white : .black
        let bg: Color = isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
        return HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(fg)
            Text(notice)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(fg)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(bg)
    }

    private func messagesScrollStage(geoWidth: CGFloat, contentWidth: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                messageListContent(contentWidth: contentWidth)
                    .padding(12)
                    .frame(width: geoWidth)
            }
            .onChange(of: viewModel.messages.count) { count in
                let target = count == 0 ? "TOP_AI_ANCHOR" : "BOTTOM_AI_ANCHOR"
                let anchor: UnitPoint = count == 0 ? .top : .bottom
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(target, anchor: anchor)
                }
            }
            .onChange(of: viewModel.messages.last?.content) { _ in
                proxy.scrollTo("BOTTOM_AI_ANCHOR", anchor: .bottom)
            }
            .onChange(of: viewModel.messages.last?.toolSteps.count) { _ in
                proxy.scrollTo("BOTTOM_AI_ANCHOR", anchor: .bottom)
            }
        }
    }

    private func messageListContent(contentWidth: CGFloat) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            Color.clear.frame(height: 1).id("TOP_AI_ANCHOR")

            if viewModel.messages.isEmpty {
                emptyStateView
                    .frame(width: contentWidth)
            } else {
                ForEach(viewModel.messages) { msg in
                    messageRowView(msg, contentWidth: contentWidth)
                }
            }

            Color.clear.frame(height: 1).id("BOTTOM_AI_ANCHOR")
        }
    }

    private func messageRowView(_ msg: EmbeddedAIMessage, contentWidth: CGFloat) -> some View {
        let isLastLoading = viewModel.isLoading && viewModel.messages.last?.id == msg.id
        let rowAlignment: Alignment = msg.role == .user ? .trailing : .leading
        return EmbeddedAIMessageRow(
            message: msg,
            isLoading: isLastLoading,
            statusText: viewModel.currentStatus,
            isDark: isDark,
            availableWidth: contentWidth,
            onReplaceSketch: { code in
                editorSourceCode = code
                envManager.analyzeIncludes(code: code)
                envManager.autoResolveAndInstallDependencies(code: code)
                viewModel.triggerNotice("Code applied directly to Sketch")
            },
            onAppendSketch: { code in
                editorSourceCode += "\n\n" + code
                envManager.analyzeIncludes(code: editorSourceCode)
                envManager.autoResolveAndInstallDependencies(code: editorSourceCode)
                viewModel.triggerNotice("Code appended to Sketch")
            },
            onRevert: {
                if let text = viewModel.revertToMessage(id: msg.id) {
                    inputText = text
                }
            },
            onEditAndResend: { newText in
                _ = viewModel.revertToMessage(id: msg.id)
                inputText = newText
                sendMessage()
            },
            onDelete: {
                viewModel.deleteMessage(id: msg.id)
            }
        )
        .frame(width: contentWidth, alignment: rowAlignment)
        .id(msg.id)
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 11.5))
                .foregroundColor(isDark ? .white : .black)

            Text("HIL AGENT")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isDark ? .white : .black)
                .lineLimit(1)

            Spacer(minLength: 4)

            CellModeTogglePill(isAgentMode: $isAgentMode, compact: true)

            Button(action: {
                withAnimation {
                    viewModel.clearMessages()
                    inputText = ""
                }
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Clear HIL Session")

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isShowing = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Close HIL Agent Panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(headerBg)
    }

    // MARK: - Live Hardware Context Strip

    private var hardwareContextStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                contextPill(icon: "cpu", text: selectedBoard.rawValue, highlight: true)

                if let port = selectedPort {
                    contextPill(icon: "cable.connector", text: port.name, highlight: true)
                } else {
                    contextPill(icon: "cable.connector.slash", text: "No USB Port", highlight: false)
                }

                if let rep = elfService.latestReport {
                    contextPill(
                        icon: "memorychip",
                        text: String(format: "Flash %.0f%% · RAM %.0f%%", rep.flashPercent, rep.ramPercent),
                        highlight: false
                    )
                }

                if !liveDRC.warnings.isEmpty {
                    contextPill(
                        icon: "bolt.trianglebadge.exclamationmark.fill",
                        text: "\(liveDRC.warnings.count) Pin DRC",
                        highlight: true
                    )
                }

                if buildLogOutput.contains("error:") || buildLogOutput.contains("[ERROR]") {
                    contextPill(icon: "exclamationmark.triangle.fill", text: "Build Error", highlight: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(stripBg)
    }

    private func contextPill(icon: String, text: String, highlight: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(highlight ? (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)) : cardBg)
        .foregroundColor(highlight ? (isDark ? .white : .black) : .secondary)
        .cornerRadius(3)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(cardBorderColor, lineWidth: 1))
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 14)

            ZStack {
                Circle()
                    .fill(cardBg)
                    .frame(width: 48, height: 48)
                Image(systemName: "memorychip.fill")
                    .font(.system(size: 21))
                    .foregroundColor(isDark ? Color(white: 0.78) : Color(white: 0.25))
            }

            VStack(spacing: 4) {
                Text("Hardware-in-the-Loop (HIL) Agent")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundColor(isDark ? .white : .black)

                Text("Autonomous cross-compilation, USB flashing, live POSIX UART capture, Pin DRC, and DWARF crash symbolication for \(selectedBoard.rawValue).")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("AUTONOMOUS HIL WORKFLOWS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                ForEach(suggestions.prefix(4)) { sug in
                    Button(action: {
                        inputText = sug.prompt
                        sendMessage()
                    }) {
                        HStack(spacing: 7) {
                            Image(systemName: sug.icon)
                                .font(.system(size: 9.5))
                                .foregroundColor(isDark ? .white : .black)
                            Text(sug.text)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(isDark ? Color(white: 0.88) : Color(white: 0.14))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(cardBg)
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(cardBorderColor, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .padding(8)
    }

    // MARK: - Quick Suggestions Bar

    private var quickSuggestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suggestions) { sug in
                    Button(action: {
                        inputText = sug.prompt
                        sendMessage()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: sug.icon)
                                .font(.system(size: 8))
                            Text(sug.text)
                                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(cardBg)
                        .foregroundColor(isDark ? Color(white: 0.85) : Color(white: 0.15))
                        .cornerRadius(3)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(cardBorderColor, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(stripBg)
    }

    // MARK: - Composer Bar (AppKit Enter-to-Send + Multi-Provider AI Selector)

    private var promptInputBar: some View {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                CellPromptInputView(
                    text: $inputText,
                    placeholder: isAgentMode
                        ? "สั่ง HIL Agent ให้เขียน คอมไพล์ แฟลชบอร์ด หรือจับ Serial..."
                        : "ถามเรื่อง Firmware, FreeRTOS, Pinout หรือ Crash...",
                    isDark: isDark,
                    minHeight: 30,
                    maxHeight: 110,
                    fontSize: 11.5,
                    onFocus: { focused in isComposerFocused = focused },
                    onSubmit: {
                        if !viewModel.isLoading {
                            sendMessage()
                        }
                    }
                )
                .padding(.horizontal, 6)
                .padding(.top, 6)

                HStack(spacing: 6) {
                    CellAIModelSelectorPill(
                        selection: $aiSelection,
                        showRoleSelector: false,
                        maxWidth: 165,
                        compact: true,
                        minimalChrome: true
                    )

                    Button(action: { attachHardwareContext.toggle() }) {
                        HStack(spacing: 3) {
                            Image(systemName: attachHardwareContext ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 8))
                            Text("Context")
                                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(attachHardwareContext ? (isDark ? .white : .black) : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(attachHardwareContext ? (isDark ? Color.white.opacity(0.11) : Color.black.opacity(0.08)) : cardBg)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Attach live target board, active USB port, ELF report, DRC warnings, sketch code, and serial logs")

                    Spacer(minLength: 4)

                    if viewModel.isLoading {
                        Button(action: { viewModel.cancelStream() }) {
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(0.88))
                                    .frame(width: 22, height: 22)
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.white)
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Stop HIL Agent")
                    } else {
                        Button(action: { sendMessage() }) {
                            ZStack {
                                Circle()
                                    .fill(hasText ? (isDark ? Color.white : Color.black) : Color.primary.opacity(0.10))
                                    .frame(width: 22, height: 22)
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(hasText ? (isDark ? .black : .white) : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasText)
                        .help("Send (Enter) · Newline (Shift+Enter)")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 7)
            }
            .background(isDark ? Color(white: 0.07) : Color.white)
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isComposerFocused ? Color.primary.opacity(0.32) : cardBorderColor, lineWidth: 1)
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(stripBg)
    }

    // MARK: - Dispatch

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        let wsRoot = appState.workspaceFolder?.path
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/MicroCodeEmbedded").path

        viewModel.sendPrompt(
            text: text,
            selection: aiSelection,
            isAgentMode: isAgentMode,
            appState: appState,
            hardwareContext: buildHardwareContextSnapshot(),
            workspaceRoot: wsRoot
        )
    }

    private func buildHardwareContextSnapshot() -> String {
        var ctx = """
        ## Active Embedded Studio Hardware Snapshot
        - Target Board: \(selectedBoard.rawValue) (\(selectedBoard.mcuSummary))
        - Memory Specs: \(selectedBoard.memorySpecs)
        - Bus/Peripherals: \(selectedBoard.busSummary)
        - Firmware Language: \(editorLanguage.rawValue)
        - Connected USB Serial Port: \(selectedPort?.path ?? "None") (\(selectedPort?.driverDescription ?? "No physical USB MCU"))
        """

        if let rep = elfService.latestReport {
            ctx += "\n- Latest Compiled ELF: `\(rep.elfPath)` (Flash: \(rep.flashUsedBytes)/\(rep.flashCapacityBytes) B [\(String(format: "%.1f%%", rep.flashPercent))], Static SRAM: \(rep.ramUsedBytes)/\(rep.ramCapacityBytes) B [\(String(format: "%.1f%%", rep.ramPercent))])"
        }

        let drc = liveDRC
        if !drc.warnings.isEmpty {
            ctx += "\n\n## Active GPIO Pin Electrical DRC Warnings\n"
            for w in drc.warnings {
                ctx += "- [\(w.severity)] GPIO \(w.gpio): \(w.message)\n"
            }
        }

        if attachHardwareContext {
            let clippedCode = editorSourceCode.count > 5000
                ? String(editorSourceCode.prefix(5000)) + "\n// ... [truncated]"
                : editorSourceCode
            ctx += "\n\n## Current Editor Firmware Source Code\n```\(editorLanguage.syntaxLanguageId)\n\(clippedCode)\n```\n"

            if !buildLogOutput.isEmpty {
                ctx += "\n## Recent Compiler / Flash Output\n```\n\(String(buildLogOutput.suffix(1800)))\n```\n"
            }

            if !consoleEntries.isEmpty {
                let tail = consoleEntries.suffix(25).map { "[\($0.tag)] \($0.content)" }.joined(separator: "\n")
                ctx += "\n## Recent Live Serial Console Lines\n```\n\(tail)\n```\n"
            }
        }
        return ctx
    }
}

// MARK: - HIL Message Row (Responsive Width-Constrained + Thought + Tool Timeline)

struct EmbeddedAIMessageRow: View {
    let message: EmbeddedAIMessage
    var isLoading: Bool = false
    var statusText: String = ""
    var isDark: Bool = true
    var availableWidth: CGFloat = 320
    let onReplaceSketch: (String) -> Void
    let onAppendSketch: (String) -> Void
    var onRevert: (() -> Void)? = nil
    var onEditAndResend: ((String) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isEditing: Bool = false
    @State private var editedText: String = ""
    @State private var isCopied: Bool = false

    var body: some View {
        if message.role == .user {
            userMessageView
        } else {
            assistantMessageView
        }
    }

    private var userMessageView: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if isEditing {
                userEditingCard
            } else {
                userStaticCard
            }
        }
    }

    private var userEditingCard: some View {
        let fg: Color = isDark ? .white : .black
        let fieldBg: Color = isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        let cardBg: Color = isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
        let sendBg: Color = isDark ? Color.white : Color.black
        let sendFg: Color = isDark ? .black : .white

        return VStack(alignment: .leading, spacing: 6) {
            TextField("แก้ไขคำสั่ง...", text: $editedText)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(fg)
                .padding(8)
                .background(fieldBg)
                .cornerRadius(5)

            HStack(spacing: 6) {
                Spacer()
                Button("ยกเลิก") { isEditing = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                Button("ส่งใหม่") {
                    let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    isEditing = false
                    onEditAndResend?(trimmed)
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(sendBg)
                .foregroundColor(sendFg)
                .cornerRadius(4)
            }
        }
        .padding(8)
        .background(cardBg)
        .cornerRadius(6)
    }

    @ViewBuilder
    private var userStaticCard: some View {
        let fg: Color = isDark ? .white : .black
        let bg: Color = isDark ? Color.white.opacity(0.13) : Color.black.opacity(0.07)
        let border: Color = isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)

        Text(message.content)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(fg)
            .textSelection(.enabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(bg)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1))
            .frame(maxWidth: max(180, availableWidth * 0.88), alignment: .trailing)

        HStack(spacing: 4) {
            actionPill(icon: "arrow.uturn.backward", label: "ย้อนกลับ") { onRevert?() }
            actionPill(icon: "pencil", label: "แก้ไข") {
                editedText = message.content
                isEditing = true
            }
            actionPill(icon: isCopied ? "checkmark" : "doc.on.doc", label: isCopied ? "คัดลอกแล้ว" : "คัดลอก") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
                isCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isCopied = false }
            }
            actionPill(icon: "trash", label: "ลบ", destructive: true) { onDelete?() }
        }
    }

    private var assistantMessageView: some View {
        let cardBg: Color = isDark ? Color.white.opacity(0.035) : Color.black.opacity(0.03)
        let border: Color = isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)

        return VStack(alignment: .leading, spacing: 8) {
            assistantHeader

            if !message.thought.isEmpty {
                AntigravityThoughtBlockView(content: message.thought, durationSeconds: nil)
            }

            if !message.toolSteps.isEmpty {
                CellAgentToolStepsTimeline(steps: message.toolSteps)
            }

            assistantContentBody
        }
        .padding(10)
        .frame(maxWidth: availableWidth, alignment: .leading)
        .background(cardBg)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1))
    }

    private var assistantHeader: some View {
        let iconFg: Color = isDark ? .white : .black
        let hilFg: Color = isDark ? .black : .white
        let hilBg: Color = isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.85)
        let title = message.modelBadge.isEmpty ? "EMBEDDED HIL AGENT" : message.modelBadge.uppercased()

        return HStack(spacing: 5) {
            Image(systemName: message.isAgentTurn ? "cpu.fill" : "bubble.left.fill")
                .font(.system(size: 9.5))
                .foregroundColor(iconFg)
            Text(title)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
            if message.isAgentTurn {
                Text("HIL")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundColor(hilFg)
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 1)
                    .background(hilBg)
                    .cornerRadius(3)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var assistantContentBody: some View {
        if message.content.isEmpty {
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                    Text(statusText.isEmpty ? "Executing HIL step…" : statusText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 3)
            }
        } else {
            let blocks = MessageContentParser.parse(message.content)
            let bodyFg: Color = isDark ? Color(white: 0.92) : Color(white: 0.10)
            if blocks.isEmpty {
                Text(message.content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(bodyFg)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(blocks) { block in
                    assistantParsedBlockView(block)
                }
            }

            if isLoading && !statusText.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.68)
                    Text(statusText)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            if !isLoading {
                assistantFooterActions
            }
        }
    }

    @ViewBuilder
    private func assistantParsedBlockView(_ block: MessageBlock) -> some View {
        switch block {
        case .thought(let content, let duration):
            AntigravityThoughtBlockView(content: content, durationSeconds: duration)
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let bodyFg: Color = isDark ? Color(white: 0.92) : Color(white: 0.10)
                Text(trimmed)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(bodyFg)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .code(let lang, let code):
            EmbeddedAICodeBlockView(
                language: lang,
                code: code,
                isDark: isDark,
                maxWidth: max(180, availableWidth - 20),
                onReplace: { onReplaceSketch(code) },
                onAppend: { onAppendSketch(code) }
            )
        case .heading(let level, let content):
            let headingFg: Color = isDark ? .white : .black
            let size: CGFloat = level <= 2 ? 12 : 11
            Text(content)
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundColor(headingFg)
                .fixedSize(horizontal: false, vertical: true)
        case .list(let items, _):
            let itemFg: Color = isDark ? Color(white: 0.88) : Color(white: 0.14)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 5) {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(item)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(itemFg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .media(let kind, let title, let target):
            ChatMediaBlockView(kind: kind, title: title, target: target)
        default:
            EmptyView()
        }
    }

    private var assistantFooterActions: some View {
        HStack(spacing: 4) {
            actionPill(icon: isCopied ? "checkmark" : "doc.on.doc", label: isCopied ? "คัดลอกแล้ว" : "คัดลอก") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
                isCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isCopied = false }
            }
            actionPill(icon: "arrow.uturn.backward", label: "ย้อนกลับ") { onRevert?() }
            actionPill(icon: "trash", label: "ลบ", destructive: true) { onDelete?() }
            Spacer()
        }
        .padding(.top, 2)
    }

    private func actionPill(icon: String, label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8.5))
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
            }
            .foregroundColor(destructive ? .red.opacity(0.85) : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.045))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Responsive Width-Constrained Code Block with 1-Click Replace / Append

struct EmbeddedAICodeBlockView: View {
    let language: String
    let code: String
    var isDark: Bool = true
    var maxWidth: CGFloat? = nil
    let onReplace: () -> Void
    let onAppend: () -> Void

    @State private var isCopied: Bool = false
    @State private var isReplaced: Bool = false
    @State private var isAppended: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(language.isEmpty ? "C++" : language.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07))
                    .cornerRadius(2)

                Spacer()

                Button(action: {
                    onReplace()
                    isReplaced = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isReplaced = false }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: isReplaced ? "checkmark" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 8))
                        Text(isReplaced ? "REPLACED" : "REPLACE SKETCH")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isReplaced ? (isDark ? Color.white : Color.black) : Color.primary.opacity(0.11))
                    .foregroundColor(isReplaced ? (isDark ? .black : .white) : .primary)
                    .cornerRadius(3)
                }
                .buttonStyle(.plain)

                Button(action: {
                    onAppend()
                    isAppended = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isAppended = false }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: isAppended ? "checkmark" : "plus.circle")
                            .font(.system(size: 8))
                        Text(isAppended ? "APPENDED" : "APPEND")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .foregroundColor(.primary.opacity(0.85))
                    .cornerRadius(3)
                }
                .buttonStyle(.plain)

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isCopied = false }
                }) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05))

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(isDark ? Color(white: 0.94) : Color(white: 0.10))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: maxWidth ?? .infinity, alignment: .leading)
        .background(isDark ? Color.black : Color(white: 0.96))
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.14), lineWidth: 1))
        .clipped()
    }
}
