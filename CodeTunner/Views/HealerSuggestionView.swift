//
//  HealerSuggestionView.swift
//  CodeTunner
//
//  Created by SPU AI CLUB
//  Copyright © 2024 AIPRENEUR. All rights reserved.
//

import SwiftUI

struct HealerSuggestionView: View {
    let suggestion: HealerSuggestion
    let onApply: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top) {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .modifier(SymbolEffectModifier(value: true))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-Healer Fix Available")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(suggestion.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Explanation
            if !suggestion.explanation.isEmpty {
                Text(suggestion.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
            
            // Code Preview
            ScrollView(.horizontal) {
                Text(suggestion.proposedCode)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .frame(maxHeight: 150)
            
            // Actions
            HStack {
                Button(action: onDismiss) {
                    Text("Dismiss")
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button(action: onApply) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Apply Fix")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding()
        .frame(width: 400)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.5), lineWidth: 1)
        )
    }
}
