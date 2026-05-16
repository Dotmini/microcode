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
    
    @available(macOS 13.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TerminalView, context: Context) -> CGSize? {
        // Never report a degenerate size — a zero/near-zero terminal makes
        // SwiftTerm compute 0 cols/rows and feeds an empty grid.
        let s = proposal.replacingUnspecifiedDimensions()
        return CGSize(width: max(120, s.width), height: max(60, s.height))
    }

    func makeNSView(context: Context) -> TerminalView {
        CrashReporter.shared.breadcrumb("PlaygroundTerminalView.makeNSView")
        // A non-zero initial frame avoids SwiftTerm initializing with a 0x0
        // grid (Int(0/cell)=0) before the first real layout pass.
        let terminal = TerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 320))
        terminal.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminal.nativeBackgroundColor = theme.editorBackground
        terminal.nativeForegroundColor = theme.editorText

        if !text.isEmpty {
            terminal.feed(text: text)
        }
        context.coordinator.cachedText = text
        CrashReporter.shared.breadcrumb("PlaygroundTerminalView.makeNSView done")
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
