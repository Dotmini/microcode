import SwiftUI
import SwiftTerm
import AppKit

// MARK: - Subclassed Native PTY Terminal View (Keyboard, Ring Buffer & Lifecycle)

final class MicroCodePTYTerminalView: LocalProcessTerminalView {
    private let outputLock = NSLock()
    private var outputRingBuffer: String = ""
    private let maxRingBufferChars = 8_192
    var onFontZoom: ((CGFloat) -> Void)?
    var onOutputErrorDetected: ((String) -> Void)?

    private static let errorPatterns: [String] = [
        "error:", "Error:", "ERROR:",
        "Traceback (most recent call last)",
        "npm ERR!", "ERR_PNPM", "yarn error",
        "fatal:", "FATAL:",
        "command not found",
        "panicked at",
        "Build Failed", "BUILD FAILED",
        "SyntaxError:", "TypeError:", "ReferenceError:",
        "Exception:", "AssertionError"
    ]

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        if let chunk = String(bytes: slice, encoding: .utf8), !chunk.isEmpty {
            outputLock.lock()
            outputRingBuffer.append(chunk)
            if outputRingBuffer.count > maxRingBufferChars {
                outputRingBuffer = String(outputRingBuffer.suffix(maxRingBufferChars))
            }
            outputLock.unlock()

            // Strip ANSI codes from the incoming chunk to check for error signatures
            let strippedChunk = chunk.replacingOccurrences(
                of: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\))"#,
                with: "",
                options: .regularExpression
            )
            for line in strippedChunk.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 6 else { continue }
                if Self.errorPatterns.contains(where: { trimmed.contains($0) }) {
                    let summary = String(trimmed.prefix(90))
                    onOutputErrorDetected?(summary)
                    break
                }
            }
        }
    }

    func recentPlainTextOutput(maxChars: Int = 4_000) -> String {
        outputLock.lock()
        let raw = outputRingBuffer
        outputLock.unlock()
        // Strip ANSI escape sequences for clean AI analysis
        let stripped = raw.replacingOccurrences(
            of: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\))"#,
            with: "",
            options: .regularExpression
        )
        return String(stripped.suffix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clearBufferAndScreen() {
        outputLock.lock()
        outputRingBuffer.removeAll(keepingCapacity: false)
        outputLock.unlock()
        feed(text: "\u{001B}[2J\u{001B}[3J\u{001B}[H")
        send(txt: "\u{000C}") // Ctrl-L to redraw prompt
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        // Only handle shortcuts when this terminal is the active first responder
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        switch chars {
        case "k":
            clearBufferAndScreen()
            return true
        case "v":
            paste(self)
            return true
        case "c":
            copy(self)
            return true
        case "=", "+":
            onFontZoom?(1)
            return true
        case "-":
            onFontZoom?(-1)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

// MARK: - Persistent Terminal Tab Session

@MainActor
final class TerminalTabSession: NSObject, ObservableObject, Identifiable, LocalProcessTerminalViewDelegate {
    let id = UUID()
    @Published var title: String
    @Published var workingDirectory: String
    @Published var isRunning: Bool = false
    @Published var exitCode: Int32? = nil
    @Published var lastDetectedErrorSummary: String? = nil
    let executable: String
    let args: [String]
    let terminalView: MicroCodePTYTerminalView

    private static let cwdLock = NSLock()

    init(
        title: String = "zsh",
        executable: String = "/bin/zsh",
        args: [String] = ["-l"],
        workingDirectory: String,
        fontName: String = "SF Mono",
        fontSize: CGFloat = 12.5,
        textColor: NSColor = .white,
        backgroundColor: NSColor = .black,
        isTransparent: Bool = false
    ) {
        self.title = title
        self.executable = executable
        self.args = args
        self.workingDirectory = workingDirectory
        self.terminalView = MicroCodePTYTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 260))
        super.init()

        self.terminalView.processDelegate = self
        self.terminalView.configureNativeLook(
            fontName: fontName,
            fontSize: fontSize,
            textColor: textColor,
            backgroundColor: isTransparent ? .clear : backgroundColor
        )
        self.terminalView.onFontZoom = { [weak self] delta in
            guard let self else { return }
            let nextSize = max(10, min(24, self.terminalView.font.pointSize + delta))
            self.terminalView.font = NSFont(name: fontName, size: nextSize)
                ?? NSFont.monospacedSystemFont(ofSize: nextSize, weight: .regular)
        }
        self.terminalView.onOutputErrorDetected = { [weak self] summary in
            Task { @MainActor [weak self] in
                self?.lastDetectedErrorSummary = summary
            }
        }
        startShellProcess()
    }

    func dispatchFixWithAIToAgent(fallbackWorkingDir: String? = nil) {
        let cwd = workingDirectory.isEmpty ? (fallbackWorkingDir ?? "") : workingDirectory
        let recent = terminalView.recentPlainTextOutput(maxChars: 3800)
        lastDetectedErrorSummary = nil
        let folderName = cwd.isEmpty ? "workspace" : URL(fileURLWithPath: cwd).lastPathComponent
        let promptText = recent.isEmpty
            ? "Help me diagnose the current terminal state in `\(cwd)`."
            : "Analyze and fix this terminal error / failure from `\(folderName)` (`\(cwd)`):\n```\n\(recent)\n```"

        AppState.shared?.aiChatVisible = true
        if let appState = AppState.shared {
            Task { @MainActor in
                if AgentService.shared.isLoading {
                    AgentService.shared.stopGeneration(autoProcessQueue: false)
                }
                await AgentService.shared.sendMessage(
                    promptText,
                    provider: appState.aiProvider,
                    model: appState.aiModel,
                    apiKey: appState.apiKeys[appState.aiProvider] ?? ""
                )
            }
        } else {
            NotificationCenter.default.post(
                name: NSNotification.Name("MicroCodeInsertAgentPrompt"),
                object: nil,
                userInfo: ["prompt": promptText, "autoSend": true]
            )
        }
    }

    func startShellProcess() {
        let env = Self.buildTerminalEnvironment(workingDirectory: workingDirectory)
        Self.cwdLock.lock()
        let previousDir = FileManager.default.currentDirectoryPath
        if !workingDirectory.isEmpty, FileManager.default.fileExists(atPath: workingDirectory) {
            FileManager.default.changeCurrentDirectoryPath(workingDirectory)
        }
        terminalView.startProcess(executable: executable, args: args, environment: env)
        if !previousDir.isEmpty {
            FileManager.default.changeCurrentDirectoryPath(previousDir)
        }
        Self.cwdLock.unlock()
        isRunning = true
        exitCode = nil
    }

    func restart() {
        terminateShell()
        terminalView.feed(text: "\r\n\u{001B}[36m⟳ Restarting shell in \(workingDirectory)...\u{001B}[0m\r\n")
        startShellProcess()
    }

    func terminateShell() {
        if isRunning {
            // Send EOT / HUP sequence to close active shell cleanly
            terminalView.send(data: [0x03, 0x04][...])
            isRunning = false
        }
    }

    func changeDirectory(_ newDir: String) {
        guard !newDir.isEmpty, newDir != workingDirectory,
              FileManager.default.fileExists(atPath: newDir) else { return }
        workingDirectory = newDir
        let escaped = newDir.replacingOccurrences(of: "'", with: "'\\''")
        terminalView.send(txt: "cd '\(escaped)' && clear\n")
    }

    static func buildTerminalEnvironment(workingDirectory: String) -> [String] {
        var envDict = ProcessInfo.processInfo.environment
        envDict.removeValue(forKey: "MICROCODE_LOCAL_API_TOKEN")
        envDict["TERM"] = "xterm-256color"
        envDict["COLORTERM"] = "truecolor"
        envDict["TERM_PROGRAM"] = "MicroCode"
        envDict["TERM_PROGRAM_VERSION"] = "3.0"
        if envDict["LANG"] == nil {
            envDict["LANG"] = "en_US.UTF-8"
        }
        envDict["LC_CTYPE"] = "UTF-8"
        if !workingDirectory.isEmpty {
            envDict["PWD"] = workingDirectory
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let runtimeBins = RuntimeManager.shared.allRuntimeBinDirectories()
        let standardBins = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "\(home)/.cargo/bin",
            "\(home)/.local/bin",
            "\(home)/.bun/bin"
        ]
        let existingPath = envDict["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var pathParts: [String] = []
        for p in runtimeBins + standardBins + existingPath.components(separatedBy: ":") where !p.isEmpty {
            if !pathParts.contains(p) {
                pathParts.append(p)
            }
        }
        envDict["PATH"] = pathParts.joined(separator: ":")
        return envDict.map { "\($0.key)=\($0.value)" }
    }

    // MARK: - LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Keep tab title concise (e.g. process name or last path component)
            let short = trimmed.components(separatedBy: " — ").last ?? trimmed
            self.title = String(short.prefix(28))
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let raw = directory, !raw.isEmpty else { return }
        let resolved: String
        if let url = URL(string: raw), url.scheme == "file" {
            resolved = url.path
        } else {
            resolved = raw
        }
        guard !resolved.isEmpty else { return }
        Task { @MainActor [weak self] in
            self?.workingDirectory = resolved
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.exitCode = exitCode
            let code = exitCode ?? 0
            self.terminalView.feed(text: "\r\n\u{001B}[90m[Process completed with exit code \(code)]\u{001B}[0m\r\n")
        }
    }
}

// MARK: - Multi-Tab & Split Terminal Session Manager

@MainActor
final class TerminalSessionManager: ObservableObject {
    static let shared = TerminalSessionManager()

    @Published var sessions: [TerminalTabSession] = []
    @Published var activeSessionID: UUID? = nil
    @Published var splitSessionID: UUID? = nil

    private var agentCommandObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?

    private init() {
        agentCommandObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("MicroCodeAgentTerminalCommand"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAgentTerminalCommand(notification)
            }
        }
        workspaceObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("MicroCodeWorkspaceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let path = notification.userInfo?["path"] as? String, !path.isEmpty else { return }
            Task { @MainActor in
                self?.syncWorkspaceDirectory(path)
            }
        }
    }

    var activeSession: TerminalTabSession? {
        if let id = activeSessionID, let match = sessions.first(where: { $0.id == id }) {
            return match
        }
        return sessions.first
    }

    var splitSession: TerminalTabSession? {
        guard let id = splitSessionID, id != activeSession?.id else { return nil }
        return sessions.first(where: { $0.id == id })
    }

    @discardableResult
    func ensureDefaultSession(
        workingDirectory: String?,
        fontName: String = "SF Mono",
        fontSize: CGFloat = 13,
        textColor: NSColor = .white,
        backgroundColor: NSColor = .black,
        isTransparent: Bool = false
    ) -> TerminalTabSession {
        if let existing = activeSession {
            if let dir = workingDirectory, !dir.isEmpty,
               existing.workingDirectory == FileManager.default.homeDirectoryForCurrentUser.path,
               dir != existing.workingDirectory {
                existing.changeDirectory(dir)
            }
            return existing
        }
        return createSession(
            workingDirectory: workingDirectory,
            fontName: fontName,
            fontSize: fontSize,
            textColor: textColor,
            backgroundColor: backgroundColor,
            isTransparent: isTransparent
        )
    }

    @discardableResult
    func createSession(
        title: String? = nil,
        executable: String? = nil,
        workingDirectory: String? = nil,
        fontName: String = "SF Mono",
        fontSize: CGFloat = 13,
        textColor: NSColor = .white,
        backgroundColor: NSColor = .black,
        isTransparent: Bool = false
    ) -> TerminalTabSession {
        let shell = executable ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = URL(fileURLWithPath: shell).lastPathComponent
        let resolvedDir: String = {
            if let dir = workingDirectory, !dir.isEmpty, FileManager.default.fileExists(atPath: dir) {
                return dir
            }
            if let current = activeSession?.workingDirectory, !current.isEmpty, FileManager.default.fileExists(atPath: current) {
                return current
            }
            return FileManager.default.homeDirectoryForCurrentUser.path
        }()
        let index = sessions.count + 1
        let session = TerminalTabSession(
            title: title ?? "\(shellName) \(index)",
            executable: shell,
            args: ["-l"],
            workingDirectory: resolvedDir,
            fontName: fontName,
            fontSize: fontSize,
            textColor: textColor,
            backgroundColor: backgroundColor,
            isTransparent: isTransparent
        )
        sessions.append(session)
        activeSessionID = session.id
        return session
    }

    func toggleSplit(
        workingDirectory: String?,
        fontName: String = "SF Mono",
        fontSize: CGFloat = 13,
        textColor: NSColor = .white,
        backgroundColor: NSColor = .black,
        isTransparent: Bool = false
    ) {
        if splitSessionID != nil {
            splitSessionID = nil
            return
        }
        let primaryID = activeSession?.id
        if let secondary = sessions.first(where: { $0.id != primaryID }) {
            splitSessionID = secondary.id
        } else {
            let created = createSession(
                workingDirectory: workingDirectory,
                fontName: fontName,
                fontSize: fontSize,
                textColor: textColor,
                backgroundColor: backgroundColor,
                isTransparent: isTransparent
            )
            if let primaryID {
                activeSessionID = primaryID
                splitSessionID = created.id
            }
        }
    }

    func closeSession(_ id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let removed = sessions.remove(at: idx)
        removed.terminateShell()

        if splitSessionID == id {
            splitSessionID = nil
        }
        if activeSessionID == id {
            activeSessionID = sessions.last?.id
        }
    }

    func clearActiveSession() {
        activeSession?.terminalView.clearBufferAndScreen()
    }

    func restartActiveSession() {
        activeSession?.restart()
    }

    func syncWorkspaceDirectory(_ path: String) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        if sessions.count == 1, let first = sessions.first, first.workingDirectory != path {
            first.changeDirectory(path)
        }
    }

    private func handleAgentTerminalCommand(_ notification: Notification) {
        guard let session = activeSession,
              let info = notification.userInfo,
              let command = info["command"] as? String else { return }
        let phase = (info["phase"] as? String) ?? "completed"
        let cwd = (info["cwd"] as? String) ?? session.workingDirectory

        if phase == "started" {
            let label = URL(fileURLWithPath: cwd).lastPathComponent
            session.terminalView.feed(text: "\r\n\u{001B}[35m🤖 Agent · \(label.isEmpty ? cwd : label)\u{001B}[0m\r\n\u{001B}[1m$ \(command)\u{001B}[0m\r\n")
        } else {
            let output = (info["output"] as? String) ?? ""
            let formatted = output.replacingOccurrences(of: "\n", with: "\r\n")
            session.terminalView.feed(text: formatted + "\r\n\u{001B}[90m[Agent command finished]\u{001B}[0m\r\n")
        }
    }
}

// MARK: - Host View Wrapper for a Persistent TerminalTabSession

struct PersistentTerminalSessionHostView: NSViewRepresentable {
    @ObservedObject var session: TerminalTabSession
    var fontName: String
    var fontSize: CGFloat
    var textColor: NSColor
    var backgroundColor: NSColor
    var isTransparent: Bool

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        attachTerminal(into: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let tv = session.terminalView
        if tv.superview !== nsView {
            attachTerminal(into: nsView)
        }
        tv.nativeBackgroundColor = isTransparent ? .clear : backgroundColor
        tv.nativeForegroundColor = textColor
        let desiredFont = NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if tv.font.fontName != desiredFont.fontName {
            tv.font = desiredFont
        }
    }

    private func attachTerminal(into container: NSView) {
        let tv = session.terminalView
        tv.removeFromSuperview()
        tv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tv)
        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tv.topAnchor.constraint(equalTo: container.topAnchor),
            tv.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}

// MARK: - Backward-Compatible AuthenticTerminal Wrapper

struct AuthenticTerminal: View {
    var executable: String = "/bin/zsh"
    var args: [String] = ["-l"]
    var workingDirectory: String? = nil
    var fontName: String = "SF Mono"
    var fontSize: CGFloat = 12.5
    var textColor: NSColor = .white
    var backgroundColor: NSColor = .black
    var isTransparent: Bool = false
    var onSessionTerminated: ((Int32) -> Void)? = nil

    @ObservedObject private var manager = TerminalSessionManager.shared

    init(
        executable: String = "/bin/zsh",
        args: [String] = ["-l"],
        workingDirectory: String? = nil,
        fontName: String = "SF Mono",
        fontSize: CGFloat = 12.5,
        textColor: NSColor = .white,
        backgroundColor: NSColor = .black,
        isTransparent: Bool = false,
        onSessionTerminated: ((Int32) -> Void)? = nil
    ) {
        self.executable = executable
        self.args = args
        self.workingDirectory = workingDirectory
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.isTransparent = isTransparent
        self.onSessionTerminated = onSessionTerminated
    }

    init(
        shell: String,
        workingDirectory: String? = nil,
        fontName: String = "SF Mono",
        fontSize: CGFloat = 12.5,
        textColor: NSColor = .white,
        backgroundColor: NSColor = .black,
        isTransparent: Bool = false
    ) {
        self.init(
            executable: shell,
            args: ["-l"],
            workingDirectory: workingDirectory,
            fontName: fontName,
            fontSize: fontSize,
            textColor: textColor,
            backgroundColor: backgroundColor,
            isTransparent: isTransparent,
            onSessionTerminated: nil
        )
    }

    var body: some View {
        Group {
            if let primary = manager.activeSession {
                ZStack(alignment: .bottomTrailing) {
                    HStack(spacing: 0) {
                        PersistentTerminalSessionHostView(
                            session: primary,
                            fontName: fontName,
                            fontSize: fontSize,
                            textColor: textColor,
                            backgroundColor: backgroundColor,
                            isTransparent: isTransparent
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if let secondary = manager.splitSession {
                            Divider()
                            PersistentTerminalSessionHostView(
                                session: secondary,
                                fontName: fontName,
                                fontSize: fontSize,
                                textColor: textColor,
                                backgroundColor: backgroundColor,
                                isTransparent: isTransparent
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }

                    if let errSummary = primary.lastDetectedErrorSummary {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.orange)
                            Text(errSummary)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: 320, alignment: .leading)
                            Button {
                                primary.dispatchFixWithAIToAgent(fallbackWorkingDir: workingDirectory)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Fix with AI")
                                        .font(.system(size: 10.5, weight: .semibold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(5)
                            }
                            .buttonStyle(.plain)

                            Button {
                                primary.lastDetectedErrorSummary = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.45), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
                        .padding(12)
                    }
                }
            } else {
                Color.clear
            }
        }
        .onAppear {
            manager.ensureDefaultSession(
                workingDirectory: workingDirectory,
                fontName: fontName,
                fontSize: fontSize,
                textColor: textColor,
                backgroundColor: backgroundColor,
                isTransparent: isTransparent
            )
        }
    }
}

extension LocalProcessTerminalView {
    func configureNativeLook(fontName: String, fontSize: CGFloat, textColor: NSColor, backgroundColor: NSColor) {
        let font = NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        self.font = font
        self.nativeBackgroundColor = backgroundColor
        self.nativeForegroundColor = textColor

        if backgroundColor == .clear {
            self.wantsLayer = true
            self.layer?.isOpaque = false
        }
    }
}
