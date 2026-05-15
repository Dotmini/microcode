//
//  ThemePickerView.swift
//  MicroCode
//
//  Created for MicroCode Dotmini.
//

import SwiftUI

struct ThemePickerView: View {
    @Binding var selectedTheme: AppTheme
    
    // Group themes by category
    private let modernThemes: [AppTheme] = [.vscodeDefault, .xcodeDark, .githubDark, .dracula, .navy, .doki, .monokaiPro, .oneDarkPro, .nord, .tokyoNight, .catppuccin]
    private let classicThemes: [AppTheme] = [.light, .dark, .xcodeLight, .visualStudio, .githubLight, .lightBlue, .solarizedDark, .solarizedLight, .gruvboxDark]
    private let retroThemes: [AppTheme] = [.cyberPunk, .synthWave, .powershell]
    private let festiveThemes: [AppTheme] = [.happyNewYear2026, .happyNewYear2026Light, .christmas, .christmasLight]
    private let specialThemes: [AppTheme] = [.transparent, .crystalClear, .obsidianGlass, .extraClear, .wwdc, .wwdcLight, .keynote, .keynoteLight, .xnuDark]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ThemeSection(title: "Festive Season 🎆", themes: festiveThemes, selection: $selectedTheme)
            ThemeSection(title: "Modern & Sleek", themes: modernThemes, selection: $selectedTheme)
            ThemeSection(title: "Classic & Familiar", themes: classicThemes, selection: $selectedTheme)
            ThemeSection(title: "Retro & Synthwave", themes: retroThemes, selection: $selectedTheme)
            ThemeSection(title: "Transparency & Special", themes: specialThemes, selection: $selectedTheme)
            
            HStack {
                Text("System Default")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                
                Button(action: { selectedTheme = .system }) {
                    HStack {
                        Image(systemName: "desktopcomputer")
                        Text("Follow macOS Appearance")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selectedTheme == .system ? Color.accentColor : Color.secondary.opacity(0.1))
                    .foregroundColor(selectedTheme == .system ? .white : .primary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }
    }
}

struct ThemeSection: View {
    let title: String
    let themes: [AppTheme]
    @Binding var selection: AppTheme
    
    let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 160), spacing: 12)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(themes, id: \.self) { theme in
                    ThemeCard(theme: theme, isSelected: selection == theme) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selection = theme
                        }
                    }
                }
            }
        }
    }
}

struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                // Preview Box
                ZStack {
                    Group {
                        if theme == .transparent {
                            // Glossy gradient background for Transparent preview
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue.opacity(0.4), Color.purple.opacity(0.4), Color.pink.opacity(0.4)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            )
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: theme.editorBackground))
                                .frame(height: 70)
                        }
                    }
                    .overlay(
                            VStack(alignment: .leading, spacing: 2) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color(nsColor: theme.keywordColor))
                                    .frame(width: 30, height: 4)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color(nsColor: theme.editorText))
                                    .frame(width: 50, height: 4)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color(nsColor: theme.stringColor))
                                    .frame(width: 40, height: 4)
                            }
                            .padding(8),
                            alignment: .topLeading
                        )
                    
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor, lineWidth: 3)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .background(Circle().fill(Color.white))
                            .position(x: 135, y: 10)
                    } else if isHovering {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    }
                }
                .shadow(color: .black.opacity(isSelected ? 0.2 : 0.1), radius: isSelected ? 4 : 2)
                .scaleEffect(isHovering ? 1.05 : 1.0)
                
                Text(theme.displayName)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}
