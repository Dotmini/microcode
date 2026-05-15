//
//  UniversalFilePreview.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2026 AIPRENEUR. All rights reserved.
//

import SwiftUI
import AppKit
import MicroCodeSupport

struct UniversalFilePreview: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> NSView {
        // Delegate to Objective-C++ generator
        let view = AuthenticPreviewGenerator.createPreview(for: url)
        
        // Ensure proper resizing behavior
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(NSLayoutConstraint.Priority.defaultLow, for: NSLayoutConstraint.Orientation.horizontal)
        view.setContentHuggingPriority(NSLayoutConstraint.Priority.defaultLow, for: NSLayoutConstraint.Orientation.vertical)
        
        // Wrap in a container to handle layout constraints properly if the view itself doesn't
        // But for NSImageView/PDFView it should be fine if we manage it in update.
        // Actually, let's just return it and rely on SwiftUI layout frame.
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // No updates needed for static file preview unless URL changes
        // If URL changes, SwiftUI usually recreates the view or we could handle it here.
        // For simplicity, we assume this view is recreated for new files.
    }
}
