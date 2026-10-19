import SwiftUI
import SwiftTerm
import AppKit

struct AuthenticTerminal: NSViewRepresentable {
    var executable: String = "/bin/zsh"
    var args: [String] = ["-l"]
    var workingDirectory: String? = nil
    var fontName: String = "Menlo"
    var fontSize: CGFloat = 12
    var textColor: NSColor = .white
    var backgroundColor: NSColor = .black
    var isTransparent: Bool = false
    var onSessionTerminated: ((Int32) -> Void)? = nil

    init(
        executable: String = "/bin/zsh",
        args: [String] = ["-l"],
        workingDirectory: String? = nil,
        fontName: String = "Menlo",
        fontSize: CGFloat = 12,
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
        fontName: String = "Menlo",
        fontSize: CGFloat = 12,
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

    func makeCoordinator() -> Coordinator {
        Coordinator(onSessionTerminated: onSessionTerminated)
    }
    
    private static let cwdLock = NSLock()

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        
        // Configure appearance
        terminalView.configureNativeLook(fontName: fontName, fontSize: fontSize, textColor: textColor, backgroundColor: isTransparent ? .clear : backgroundColor)
        terminalView.processDelegate = context.coordinator
        
        // Safely scope working directory during forkpty and immediately restore host process CWD
        Self.cwdLock.lock()
        let previousDir = FileManager.default.currentDirectoryPath
        if let dir = workingDirectory, !dir.isEmpty, FileManager.default.fileExists(atPath: dir) {
            FileManager.default.changeCurrentDirectoryPath(dir)
        }
        terminalView.startProcess(executable: executable, args: args)
        if !previousDir.isEmpty {
            FileManager.default.changeCurrentDirectoryPath(previousDir)
        }
        Self.cwdLock.unlock()

        context.coordinator.attach(terminalView, initialDirectory: workingDirectory)
        
        return terminalView
    }
    
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        nsView.nativeBackgroundColor = isTransparent ? .clear : backgroundColor
        nsView.nativeForegroundColor = textColor
        nsView.font = NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        context.coordinator.updateWorkingDirectoryIfNeeded(workingDirectory)
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// The interactive terminal remains a real PTY-backed zsh session. Agent
    /// commands are executed by the native runner and mirrored here as they
    /// start and finish, giving the user one trustworthy terminal timeline
    /// without spawning a fake canvas or hiding a command behind the chat.
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private weak var terminalView: LocalProcessTerminalView?
        private var observer: NSObjectProtocol?
        private var currentDirectory: String?
        var onSessionTerminated: ((Int32) -> Void)?

        init(onSessionTerminated: ((Int32) -> Void)? = nil) {
            self.onSessionTerminated = onSessionTerminated
            super.init()
            observer = NotificationCenter.default.addObserver(
                forName: Notification.Name("MicroCodeAgentTerminalCommand"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.renderAgentCommand(notification)
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attach(_ terminal: LocalProcessTerminalView, initialDirectory: String?) {
            terminalView = terminal
            currentDirectory = initialDirectory
        }

        func updateWorkingDirectoryIfNeeded(_ newDirectory: String?) {
            guard let dir = newDirectory, !dir.isEmpty, dir != currentDirectory,
                  FileManager.default.fileExists(atPath: dir) else { return }
            currentDirectory = dir
            let escaped = dir.replacingOccurrences(of: "'", with: "'\\''")
            terminalView?.send(txt: "cd '\(escaped)'\n")
        }

        func detach() {
            terminalView = nil
        }

        private func renderAgentCommand(_ notification: Notification) {
            guard let terminalView,
                  let info = notification.userInfo,
                  let command = info["command"] as? String else { return }
            let phase = (info["phase"] as? String) ?? "completed"
            let cwd = (info["cwd"] as? String) ?? ""

            if phase == "started" {
                let label = URL(fileURLWithPath: cwd).lastPathComponent
                terminalView.feed(text: "\r\n🤖 Agent · \(label.isEmpty ? cwd : label)\r\n$ \(command)\r\n")
            } else {
                let output = (info["output"] as? String) ?? ""
                terminalView.feed(text: output + "\r\n[Agent command finished]\r\n")
            }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [weak self] in
                self?.onSessionTerminated?(exitCode ?? 0)
            }
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}

extension LocalProcessTerminalView {
    func configureNativeLook(fontName: String, fontSize: CGFloat, textColor: NSColor, backgroundColor: NSColor) {
        // Get font from system or use a nice monospaced one
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        
        // SwiftTerm configuration
        self.font = font
        self.nativeBackgroundColor = backgroundColor
        self.nativeForegroundColor = textColor
        
        // Support transparency if backgroundColor is clear
        if backgroundColor == .clear {
            self.wantsLayer = true
            self.layer?.isOpaque = false
        }
        
        // Enable mouse reporting for vim/htop
        // SwiftTerm usually handles this by default but good to verify
    }
}
