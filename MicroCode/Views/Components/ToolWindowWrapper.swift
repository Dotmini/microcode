//
//  ToolWindowWrapper.swift
//  MicroCode
//
//  Shared window wrapper for all Code Tools to ensure consistent UX/UI.
//  Enforces uniform size, header style, and behavior.
//

import SwiftUI

struct ToolWindowWrapper<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    
    @Environment(\.dismiss) var dismiss
    
    let content: Content
    let footer: Footer
    
    init(title: String, 
         subtitle: String = "",
         icon: String, 
         iconColor: Color = .blue,
         @ViewBuilder content: () -> Content, 
         @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
        self.footer = footer()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Standard Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content Area
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            
            // Optional Footer
            if !(footer is EmptyView) {
                Divider()
                footer
                    .padding(16)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        // Unified Size Requirement
        .frame(width: 800, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
}
