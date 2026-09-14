//
//  FileTabBar.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import SwiftUI

struct FileTabBar: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        fileTabsView
    }
    
    private var fileTabsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(appState.openFiles) { file in
                    FileTab(
                        file: file,
                        isActive: file.id == appState.currentFile?.id,
                        onSelect: { self.selectFile(file) },
                        onClose: { self.closeFile(file) }
                    )
                }
            }
        }
        .frame(height: 36)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func selectFile(_ file: CodeFile) {
        appState.selectFile(file)
    }
    
    private func closeFile(_ file: CodeFile) {
        appState.closeFile(file)
    }
}

struct FileTab: View {
    let file: CodeFile
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 6) {
            // File icon
            Image(systemName: fileIcon(for: file.language))
                .font(.system(size: 11))
                .foregroundColor(languageColor(file.language))
            
            // File name
            Text(file.name)
                .font(.system(size: 12))
                .lineLimit(1)
            
            // Unsaved indicator
            if file.isUnsaved {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }
            
            // Close button
            if isHovering || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
                .help("Close Tab (⌘W)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isActive ? Color(nsColor: .textBackgroundColor) : (isHovering ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
    
    private func fileIcon(for language: String) -> String {
        switch language.lowercased() {
        case "swift": return "swift"
        case "python": return "doc.text"
        case "javascript", "typescript": return "doc.text"
        case "rust": return "gearshape"
        case "go": return "doc.text"
        default: return "doc"
        }
    }
    
    private func languageColor(_ lang: String) -> Color {
        switch lang.lowercased() {
        case "swift": return .orange
        case "python": return .blue
        case "javascript", "typescript": return .yellow
        case "rust": return .orange
        case "go": return .cyan
        default: return .gray
        }
    }
}
