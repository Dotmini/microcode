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
                // Main autocomplete listing
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(0..<appState.lspCompletions.count, id: \.self) { index in
                                let item = appState.lspCompletions[index]
                                AutocompleteRow(
                                    item: item,
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
                    .frame(maxHeight: 200)
                    .onChange(of: appState.selectedCompletionIndex) { newIndex in
                        withAnimation(.easeInOut(duration: 0.08)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
                
                // Documentation/Detail view if selected item has details
                if let detail = currentItemDetail {
                    Divider()
                        .background(Color.secondary.opacity(0.2))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detail)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .background(Color.black.opacity(0.15))
                }
            }
            .frame(width: 320)
            .background(
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
        }
    }
    
    private var currentItemDetail: String? {
        guard appState.selectedCompletionIndex < appState.lspCompletions.count else { return nil }
        let item = appState.lspCompletions[appState.selectedCompletionIndex]
        return item.detail ?? item.documentation
    }
}

struct AutocompleteRow: View {
    let item: CompletionItem
    let isSelected: Bool
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Kind icon and badge
            Image(systemName: iconName(for: item.kind))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(iconColor(for: item.kind))
                .frame(width: 18, height: 18)
                .background(iconColor(for: item.kind).opacity(0.15))
                .cornerRadius(4)
            
            // Label
            Text(item.label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .monospaced))
                .foregroundColor(isSelected ? .white : .primary)
                .lineLimit(1)
            
            Spacer()
            
            // Kind Description (e.g. Method, Function)
            if let detail = item.detail, !detail.isEmpty && detail.count < 15 {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
            } else {
                Text(item.kindDescription)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            isSelected ? Color.accentColor : (isHovering ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { hovering in
            isHovering = hovering
        }
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
