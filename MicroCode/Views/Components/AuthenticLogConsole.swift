//
//  AuthenticLogConsole.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2026 AIPRENEUR. All rights reserved.
//

import SwiftUI
import AppKit

struct AuthenticLogConsole: NSViewRepresentable {
    @Binding var text: String
    var isReadOnly: Bool = true
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        // Disable elasticity for log performance
        scrollView.verticalScrollElasticity = .none
        
        let textView = NSTextView()
        textView.minSize = NSSize(width: 0.0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        
        // Performance
        textView.isRichText = false
        textView.isEditable = !isReadOnly
        textView.isSelectable = true
        textView.font = font
        textView.textColor = .labelColor
        textView.backgroundColor = .controlBackgroundColor
        
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        
        scrollView.documentView = textView
        
        // Initial set
        textView.string = text
        context.coordinator.lastText = text
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        // Optimization: Append only if possible
        let currentText = context.coordinator.lastText
        
        if text != currentText {
            // Check if it's an append
            if text.hasPrefix(currentText) {
                let newPart = String(text.dropFirst(currentText.count))
                // Append efficiently
                let endRange = NSRange(location: textView.string.utf16.count, length: 0)
                textView.replaceCharacters(in: endRange, with: newPart)
                
                // Auto scroll
                textView.scrollToEndOfDocument(nil)
            } else {
                // Full replacement
                textView.string = text
            }
            context.coordinator.lastText = text
        }
    }
    
    class Coordinator: NSObject {
        var parent: AuthenticLogConsole
        var lastText: String = ""
        
        init(_ parent: AuthenticLogConsole) {
            self.parent = parent
        }
    }
}
