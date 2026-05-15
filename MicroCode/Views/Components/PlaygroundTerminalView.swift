//
//  PlaygroundTerminalView.swift
//  MicroCode
//
//  Created by SPU AI CLUB on 2026-01-19.
//  Copyright © 2026 SPU AI CLUB. All rights reserved.
//

import SwiftUI
import SwiftTerm

struct PlaygroundTerminalView: NSViewRepresentable {
    @Binding var text: String
    @Binding var fontSize: CGFloat
    var theme: AppTheme
    
    func makeNSView(context: Context) -> TerminalView {
        let terminal = TerminalView(frame: .zero)
        terminal.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminal.nativeBackgroundColor = theme.editorBackground
        terminal.nativeForegroundColor = theme.editorText
        
        // Configure terminal checks
        terminal.feed(text: text)
        
        return terminal
    }
    
    func updateNSView(_ nsView: TerminalView, context: Context) {
        // Update font if changed
        if nsView.font.pointSize != fontSize {
            nsView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        
        // Update colors
        if nsView.nativeBackgroundColor != theme.editorBackground {
            nsView.nativeBackgroundColor = theme.editorBackground
            nsView.nativeForegroundColor = theme.editorText
        }
        
        // Feed new text (diffing)
        let currentText = context.coordinator.cachedText
        if text.isEmpty {
            if !currentText.isEmpty {
                 nsView.feed(text: "\u{001B}[2J\u{001B}[H") // Clear screen
                 context.coordinator.cachedText = ""
            }
        } else {
            if text.hasPrefix(currentText) {
                let newPart = String(text.dropFirst(currentText.count))
                // Convert newlines to CRLF for terminal
                let formatted = newPart.replacingOccurrences(of: "\n", with: "\r\n")
                nsView.feed(text: formatted)
                context.coordinator.cachedText = text
            } else {
                // Text changed completely or reset
                nsView.feed(text: "\u{001B}[2J\u{001B}[H") // Clear
                let formatted = text.replacingOccurrences(of: "\n", with: "\r\n")
                nsView.feed(text: formatted)
                context.coordinator.cachedText = text
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var cachedText: String = ""
    }
}
