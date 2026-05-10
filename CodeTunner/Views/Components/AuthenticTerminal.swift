import SwiftUI
import SwiftTerm
import AppKit

struct AuthenticTerminal: NSViewRepresentable {
    var shell: String = "/bin/zsh"
    var fontName: String = "Menlo"
    var fontSize: CGFloat = 12
    var textColor: NSColor = .white
    var backgroundColor: NSColor = .black
    var isTransparent: Bool = false
    
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        
        // Configure appearance
        terminalView.configureNativeLook(fontName: fontName, fontSize: fontSize, textColor: textColor, backgroundColor: isTransparent ? .clear : backgroundColor)
        
        // Start shell
        terminalView.startProcess(executable: shell, args: ["-l"])
        
        return terminalView
    }
    
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        nsView.nativeBackgroundColor = isTransparent ? .clear : backgroundColor
        nsView.nativeForegroundColor = textColor
        nsView.font = NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
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
