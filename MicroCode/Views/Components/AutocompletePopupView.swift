//
//  AutocompletePopupView.swift
//  MicroCode
//
//  Created by Antigravity on 2026.
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import SwiftUI

struct AutocompletePopupView: View {
    @ObservedObject var appState: AppState
    let onItemSelected: (CompletionItem) -> Void
    
    var body: some View {
        if appState.showingCompletions && !appState.lspCompletions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Main autocomplete listing (LazyVStack for zero main-thread stutter)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<appState.lspCompletions.count, id: \.self) { index in
                                let item = appState.lspCompletions[index]
                                AutocompleteRow(
                                    item: item,
                                    prefix: appState.autocompletePrefix,
                                    isSelected: index == appState.selectedCompletionIndex
                                )
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onItemSelected(item)
                                }
                            }
                        }
                    }
                    .frame(height: min(CGFloat(max(1, appState.lspCompletions.count)) * 28, 224))
                    .onChange(of: appState.selectedCompletionIndex) { newIndex in
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
                
                // Documentation / Signature preview pane for the selected item
                if let selected = selectedItem, (selected.detail != nil || selected.documentation != nil) {
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if let detail = selected.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.9))
                                .lineLimit(2)
                        }
                        if let doc = selected.documentation, !doc.isEmpty, doc != selected.detail {
                            Text(doc)
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.18))
                }
                
                // Official IDE Status Bar (Active LSP Engine + Shortcut Hints)
                Divider()
                    .background(Color.white.opacity(0.08))
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green.opacity(0.85))
                        .frame(width: 5, height: 5)
                    Text(LSPManager.shared.activeSourceBadge)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text("⇥/↵ Insert  ·  ↑↓ Navigate  ·  ⎋ Esc")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.75))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.24))
            }
            .frame(width: 420)
            .background(
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.42), radius: 14, x: 0, y: 6)
        }
    }
    
    private var selectedItem: CompletionItem? {
        guard appState.selectedCompletionIndex < appState.lspCompletions.count else { return nil }
        return appState.lspCompletions[appState.selectedCompletionIndex]
    }
}

struct AutocompleteRow: View {
    let item: CompletionItem
    let prefix: String
    let isSelected: Bool
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Kind icon and badge
            Image(systemName: iconName(for: item.kind))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isSelected ? .white : iconColor(for: item.kind))
                .frame(width: 18, height: 18)
                .background(isSelected ? Color.white.opacity(0.22) : iconColor(for: item.kind).opacity(0.15))
                .cornerRadius(4)
            
            // Primary Symbol Name (with matched prefix highlighted) + Parameter Signature
            HStack(spacing: 0) {
                highlightedSymbolText
                if let sig = item.parameterSignature, !sig.isEmpty {
                    Text(sig)
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                        .foregroundColor(isSelected ? .white.opacity(0.78) : .secondary)
                        .lineLimit(1)
                }
            }
            .lineLimit(1)
            
            Spacer(minLength: 8)
            
            // Trailing Type / Kind Description
            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .trailing)
            } else {
                Text(item.kindDescription)
                    .font(.system(size: 9.5))
                    .foregroundColor(isSelected ? .white.opacity(0.75) : .secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(height: 28)
        .background(
            isSelected ? Color.accentColor : (isHovering ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var highlightedSymbolText: Text {
        let name = item.primarySymbolName
        let cleanPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrefix.isEmpty,
              let range = name.range(of: cleanPrefix, options: [.caseInsensitive]) else {
            return Text(name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .monospaced))
                .foregroundColor(isSelected ? .white : .primary)
        }
        let before = String(name[..<range.lowerBound])
        let matched = String(name[range])
        let after = String(name[range.upperBound...])
        return Text(before)
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundColor(isSelected ? .white.opacity(0.9) : .primary)
        + Text(matched)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(isSelected ? .white : .accentColor)
        + Text(after)
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .monospaced))
            .foregroundColor(isSelected ? .white.opacity(0.95) : .primary)
    }
    
    private func iconName(for kind: Int?) -> String {
        switch kind {
        case 1: return "doc.text"                       // Text
        case 2: return "f.square.fill"                 // Method
        case 3: return "f.circle"                      // Function
        case 4: return "hammer"                        // Constructor
        case 5: return "rectangle.split.2x1"           // Field
        case 6: return "v.square"                      // Variable
        case 7: return "c.square"                      // Class
        case 8: return "i.square"                      // Interface
        case 9: return "shippingbox"                   // Module
        case 10: return "slider.horizontal.3"          // Property
        case 11: return "scale"                        // Unit
        case 12: return "number"                       // Value
        case 13: return "e.square"                     // Enum
        case 14: return "key"                          // Keyword
        case 15: return "chevron.left.forwardslash.chevron.right" // Snippet
        case 16: return "paintpalette"                  // Color
        case 17: return "doc"                          // File
        case 18: return "link"                         // Reference
        case 19: return "folder"                       // Folder
        case 20: return "tag"                          // EnumMember
        case 21: return "c.circle"                     // Constant
        case 22: return "s.square"                     // Struct
        case 23: return "bolt"                         // Event
        case 24: return "plus.minus"                   // Operator
        case 25: return "t.square"                     // TypeParameter
        default: return "questionmark.square"
        }
    }
    
    private func iconColor(for kind: Int?) -> Color {
        switch kind {
        case 2, 3: return .purple                      // Methods, Functions
        case 5, 6, 10: return .blue                     // Fields, Variables, Properties
        case 7, 22: return .orange                      // Classes, Structs
        case 8, 13: return .green                       // Interfaces, Enums
        case 14: return .pink                           // Keywords
        case 15: return .yellow                         // Snippets
        default: return .secondary
        }
    }
}
