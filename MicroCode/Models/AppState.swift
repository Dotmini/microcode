//
//  AppState.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2024 Dotmini Company Limited. All rights reserved.
//

import SwiftUI
import Combine
import Foundation
import MicroCodeSupport
import MicroCodeKernel
import AppKit
import CryptoKit

private struct SafeFileLoadResult: Sendable {
    let content: String
    let originalByteSize: Int
    let isReadOnly: Bool
    let isTruncated: Bool
    let shouldUsePlainTextMode: Bool
    let errorMessage: String?
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    var content: String
    let timestamp: Date
    var codeBlocks: [CodeBlock] = []
    var toolCalls: [AgentToolCall] = []
    var toolResults: [AgentToolResult] = []
    var isThinking: Bool = false
    
    enum ChatRole {
        case user
        case assistant
        case system
    }
}

struct CodeBlock: Identifiable {
    let id = UUID()
    let language: String
    let code: String
    let filePath: String?
}

struct AgentAction: Identifiable {
    let id = UUID()
    let actionType: ActionType
    let description: String
    let filePath: String
    let oldCode: String
    let newCode: String
    var isApproved: Bool = false
    var isRejected: Bool = false
    
    enum ActionType {
        case createFile
        case editFile
        case deleteFile
        case createProject
    }
}

public enum AgenticInspectorTab: String, CaseIterable, Codable {
    case context = "Context"
    case preview = "Preview"
    case plan = "Plan"
    case tasks = "Tasks"
}

// MARK: - App Theme System

enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case navy = "navy"
    case lightBlue = "lightBlue"
    case xcodeLight = "xcodeLight" // Classic Light
    case xcodeDark = "xcodeDark"   // Modern Dark
    case vscodeDefault = "vscode"
    case visualStudio = "visualStudio"
    case wwdc = "wwdc"
    case wwdcLight = "wwdcLight"
    case keynote = "keynote"
    case keynoteLight = "keynoteLight"
    case christmas = "christmas"
    case christmasLight = "christmasLight"
    case powershell = "powershell"
    case dracula = "dracula"
    case draculaLight = "draculaLight"
    case githubDark = "githubDark"
    case githubLight = "githubLight"
    case doki = "doki"
    case happyNewYear2026 = "happyNewYear2026"
    case happyNewYear2026Light = "happyNewYear2026Light"
    case transparent = "transparent"
    case extraClear = "extraClear"
    case xnuDark = "xnuDark"
    case microCodeTheme = "microCodeTheme" // Apple Presentation Style
    
    // Modern
    case monokaiPro = "monokaiPro"
    case oneDarkPro = "oneDarkPro"
    case nightOwl = "nightOwl"
    case nord = "nord"
    case tokyoNight = "tokyoNight"
    case catppuccin = "catppuccin"
    case cyberPunk = "cyberPunk"
    case synthWave = "synthWave"
    
    // Classic
    case solarizedDark = "solarizedDark"
    case solarizedLight = "solarizedLight"
    case gruvboxDark = "gruvboxDark"
    
    // Transparent
    case crystalClear = "crystalClear"
    case obsidianGlass = "obsidianGlass"

    var isGlass: Bool {
        switch self {
        case .transparent, .extraClear, .crystalClear, .obsidianGlass:
            return true
        default:
            return false
        }
    }

    /// Opaque workspace colors used by native panes. Only glass themes are
    /// allowed to expose the desktop through the app window.
    var workspaceBackground: NSColor {
        if isGlass { return editorBackground }
        if self == .dark || self == .xcodeDark { return NSColor.black }
        return editorBackground.withAlphaComponent(1.0)
    }

    var panelBackground: NSColor {
        if isGlass { return editorBackground }
        if self == .dark || self == .xcodeDark { return NSColor(white: 0.06, alpha: 1.0) }
        let target: NSColor = isDark ? .white : .black
        return (editorBackground.blended(withFraction: isDark ? 0.035 : 0.025, of: target) ?? editorBackground)
            .withAlphaComponent(1.0)
    }

    var elevatedBackground: NSColor {
        if isGlass { return editorBackground }
        if self == .dark || self == .xcodeDark { return NSColor(white: 0.10, alpha: 1.0) }
        let target: NSColor = isDark ? .white : .black
        return (editorBackground.blended(withFraction: isDark ? 0.07 : 0.045, of: target) ?? editorBackground)
            .withAlphaComponent(1.0)
    }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark (Near Black)"
        case .navy: return "Navy"
        case .lightBlue: return "Light Blue"
        case .xcodeLight: return "Xcode (Light)"
        case .xcodeDark: return "Xcode (Dark)"
        case .vscodeDefault: return "VS Code"
        case .visualStudio: return "Visual Studio"
        case .wwdc: return "WWDC (Dark)"
        case .wwdcLight: return "WWDC (Light)"
        case .keynote: return "Keynote (Dark)"
        case .keynoteLight: return "Keynote (Light)"
        case .christmas: return "Christmas (Dark) 🎄"
        case .christmasLight: return "Christmas (Light) 🎄"
        case .powershell: return "PowerShell"
        case .dracula: return "Dracula"
        case .draculaLight: return "Dracula (Light)"
        case .githubDark: return "GitHub (Dark)"
        case .githubLight: return "GitHub (Light)"
        case .doki: return "Doki (Monika)"
        case .happyNewYear2026: return "Happy New Year 2026 🎆"
        case .happyNewYear2026Light: return "Happy New Year 2026 (Light) 🎈"
        case .transparent: return "Glass Transparent 💎"
        case .extraClear: return "Extra Clear (Transparent) ✨"
        case .xnuDark: return "XNU Dark (Kernel) 🍏"
        case .microCodeTheme: return "MicroCode Theme (Presentation) "
        case .monokaiPro: return "Monokai Pro 🎨"
        case .oneDarkPro: return "One Dark Pro ⚛️"
        case .nightOwl: return "Night Owl 🦉"
        case .nord: return "Nord ❄️"
        case .tokyoNight: return "Tokyo Night 🌃"
        case .catppuccin: return "Catppuccin Mocha ☕️"
        case .cyberPunk: return "Cyberpunk 2077 🤖"
        case .synthWave: return "Synthwave '84 🌅"
        case .solarizedDark: return "Solarized Dark ☀️"
        case .solarizedLight: return "Solarized Light ☀️"
        case .gruvboxDark: return "Gruvbox Dark 📦"
        case .crystalClear: return "Crystal Clear (Glass) 💎"
        case .obsidianGlass: return "Obsidian Glass (Dark) 🔮"
        }
    }
    
    var isDark: Bool {
        switch self {
        case .light, .lightBlue, .xcodeLight, .christmasLight, .wwdcLight, .keynoteLight, .draculaLight, .githubLight, .happyNewYear2026Light, .solarizedLight, .crystalClear, .microCodeTheme:
            return false
        case .system:
            return NSApp?.effectiveAppearance.name.rawValue.contains("Dark") ?? true
        default:
            return true
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light, .lightBlue, .xcodeLight, .christmasLight, .wwdcLight, .keynoteLight, .draculaLight, .githubLight, .happyNewYear2026Light, .solarizedLight, .crystalClear, .microCodeTheme:
            return .light
        default:
            return .dark
        }
    }
    
    // Editor Colors
    var editorBackground: NSColor {
        switch self {
        case .system: 
            return NSApp?.effectiveAppearance.name == .darkAqua ? NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1.0) : NSColor(white: 1.0, alpha: 1.0)
        case .light, .xcodeLight: return NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        case .navy: return NSColor(red: 0.051, green: 0.106, blue: 0.165, alpha: 1.0) // #0D1B2A
        case .lightBlue: return NSColor(red: 0.890, green: 0.949, blue: 0.992, alpha: 1.0) // #E3F2FD
        case .dark, .xcodeDark: return NSColor.black // Pure Pitch Black #000000 (Xcode Pro Dark)
        case .vscodeDefault: return NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1.0) // #1E1E1E
        case .visualStudio: return NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1.0) // #1E1E1E
        case .wwdc: return NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0) // Deep Midnight Blue
        case .wwdcLight: return NSColor(white: 1.0, alpha: 1.0) // Pure White
        case .keynote: return NSColor(white: 0.0, alpha: 1.0) // Pure Black
        case .keynoteLight: return NSColor(white: 1.0, alpha: 1.0) // Pure White
        case .christmas: return NSColor(red: 0.02, green: 0.15, blue: 0.05, alpha: 1.0) // Deep Christmas Green
        case .christmasLight: return NSColor(red: 0.98, green: 1.0, blue: 0.98, alpha: 1.0) // Snowy White
        case .powershell: return NSColor(red: 0.004, green: 0.141, blue: 0.337, alpha: 1.0) // #012456
        case .dracula: return NSColor(red: 0.157, green: 0.165, blue: 0.212, alpha: 1.0) // #282a36
        case .draculaLight: return NSColor(red: 0.980, green: 0.980, blue: 0.980, alpha: 1.0) // #fafafa
        case .githubDark: return NSColor(red: 0.051, green: 0.067, blue: 0.090, alpha: 1.0) // #0d1117
        case .githubLight: return NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0) // #ffffff
        case .doki: return NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0) // Dark Doki
        case .happyNewYear2026: return NSColor(red: 0.039, green: 0.055, blue: 0.09, alpha: 1.0) // Midnight Blue #0A0E17
        case .happyNewYear2026Light: return NSColor(red: 1.0, green: 0.976, blue: 0.898, alpha: 1.0) // Festive White #FFF9E5
        case .transparent: return NSColor(white: 0.0, alpha: 0.1) // Low Alpha Black for Glass effect
        case .extraClear: return NSColor(white: 0.0, alpha: 0.02) // Near fully transparent
        case .xnuDark: return NSColor(red: 0.071, green: 0.071, blue: 0.071, alpha: 1.0) // #121212
        case .microCodeTheme: return NSColor(white: 1.0, alpha: 1.0) // Pure White
        case .monokaiPro: return NSColor(red: 0.173, green: 0.169, blue: 0.196, alpha: 1.0) // #2D2A32
        case .oneDarkPro: return NSColor(red: 0.157, green: 0.165, blue: 0.184, alpha: 1.0) // #282C34
        case .nightOwl: return NSColor(red: 0.004, green: 0.086, blue: 0.153, alpha: 1.0) // #011627
        case .nord: return NSColor(red: 0.180, green: 0.204, blue: 0.251, alpha: 1.0) // #2E3440
        case .tokyoNight: return NSColor(red: 0.102, green: 0.106, blue: 0.169, alpha: 1.0) // #1A1B26
        case .catppuccin: return NSColor(red: 0.118, green: 0.118, blue: 0.180, alpha: 1.0) // #1E1E2E
        case .cyberPunk: return NSColor(red: 0.012, green: 0.008, blue: 0.094, alpha: 1.0) // #030218
        case .synthWave: return NSColor(red: 0.161, green: 0.090, blue: 0.231, alpha: 1.0) // #29173B
        case .solarizedDark: return NSColor(red: 0.000, green: 0.169, blue: 0.212, alpha: 1.0) // #002B36
        case .solarizedLight: return NSColor(red: 0.992, green: 0.965, blue: 0.890, alpha: 1.0) // #FDF6E3
        case .gruvboxDark: return NSColor(red: 0.157, green: 0.157, blue: 0.157, alpha: 1.0) // #282828 (Hard)
        case .crystalClear: return NSColor(white: 1.0, alpha: 0.15) // Glass Light
        case .obsidianGlass: return NSColor(white: 0.0, alpha: 0.35) // Glass Dark
        }
    }
    
    var editorText: NSColor {
        switch self {
        case .system: 
            return NSApp?.effectiveAppearance.name == .darkAqua ? NSColor(red: 0.831, green: 0.831, blue: 0.831, alpha: 1.0) : NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        case .light, .xcodeLight: return NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        case .dark, .xcodeDark: return NSColor.white // Pure Crisp White #FFFFFF (Xcode Pro Dark)
        case .navy: return NSColor(red: 0.878, green: 0.882, blue: 0.867, alpha: 1.0) // #E0E1DD
        case .lightBlue: return NSColor(red: 0.102, green: 0.137, blue: 0.494, alpha: 1.0) // #1A237E
        case .vscodeDefault: return NSColor(red: 0.831, green: 0.831, blue: 0.831, alpha: 1.0) // #D4D4D4
        case .visualStudio: return NSColor(red: 0.863, green: 0.863, blue: 0.863, alpha: 1.0) // #DCDCDC
        case .wwdc: return NSColor(white: 1.0, alpha: 1.0) // Pure White for Presentation
        case .wwdcLight: return NSColor(white: 0.0, alpha: 1.0) // Black for Presentation
        case .keynote: return NSColor(white: 1.0, alpha: 1.0) // Pure White
        case .keynoteLight: return NSColor(white: 0.0, alpha: 1.0) // Black
        case .christmas: return NSColor(red: 0.9, green: 0.9, blue: 0.8, alpha: 1.0) // Warm White (Snow)
        case .christmasLight: return NSColor(red: 0.05, green: 0.2, blue: 0.1, alpha: 1.0) // Dark Green Text
        case .powershell: return NSColor(red: 0.933, green: 0.933, blue: 0.933, alpha: 1.0) // #eeeeee
        case .dracula: return NSColor(red: 0.973, green: 0.973, blue: 0.949, alpha: 1.0) // #f8f8f2
        case .draculaLight: return NSColor(red: 0.157, green: 0.165, blue: 0.212, alpha: 1.0) // #282a36
        case .githubDark: return NSColor(red: 0.788, green: 0.820, blue: 0.851, alpha: 1.0) // #c9d1d9
        case .githubLight: return NSColor(red: 0.141, green: 0.161, blue: 0.180, alpha: 1.0) // #24292e
        case .doki: return NSColor(red: 0.957, green: 0.957, blue: 0.957, alpha: 1.0) // #f4f4f4
        case .happyNewYear2026: return NSColor(white: 0.95, alpha: 1.0)
        case .happyNewYear2026Light: return NSColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0)
        case .transparent: return .white
        case .extraClear: return .white
        case .xnuDark: return NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0) // #CCCCCC
        case .microCodeTheme: return NSColor(red: 0.1, green: 0.15, blue: 0.25, alpha: 1.0) // Deep Navy Text
        case .monokaiPro: return NSColor(red: 0.988, green: 0.988, blue: 0.941, alpha: 1.0) // #FCFCF0
        case .oneDarkPro: return NSColor(red: 0.675, green: 0.745, blue: 0.804, alpha: 1.0) // #ABB2BF
        case .nightOwl: return NSColor(red: 0.839, green: 0.871, blue: 0.922, alpha: 1.0) // #D6DEEB
        case .nord: return NSColor(red: 0.847, green: 0.871, blue: 0.914, alpha: 1.0) // #D8DEE9
        case .tokyoNight: return NSColor(red: 0.780, green: 0.792, blue: 0.910, alpha: 1.0) // #C0CAF5
        case .catppuccin: return NSColor(red: 0.804, green: 0.839, blue: 0.957, alpha: 1.0) // #CDD6F4
        case .cyberPunk: return NSColor(red: 0.075, green: 0.933, blue: 1.0, alpha: 1.0) // #13EFFF
        case .synthWave: return NSColor(red: 1.0, green: 0.0, blue: 0.824, alpha: 1.0) // #FF00D2
        case .solarizedDark: return NSColor(red: 0.514, green: 0.580, blue: 0.588, alpha: 1.0) // #839496
        case .solarizedLight: return NSColor(red: 0.396, green: 0.482, blue: 0.514, alpha: 1.0) // #657B83
        case .gruvboxDark: return NSColor(red: 0.922, green: 0.859, blue: 0.698, alpha: 1.0) // #EBDBB2
        case .crystalClear: return NSColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0) // Dark Text on Light Glass
        case .obsidianGlass: return NSColor(red: 0.9, green: 0.95, blue: 1.0, alpha: 1.0) // Light Text on Dark Glass
        }
    }
    
    // Syntax Highlighting Colors
    var keywordColor: NSColor {
        switch self {
        case .system: return NSApp?.effectiveAppearance.name == .darkAqua ? AppTheme.dark.keywordColor : AppTheme.light.keywordColor
        case .dark, .xcodeDark: return NSColor(red: 0.988, green: 0.373, blue: 0.639, alpha: 1.0) // Xcode Pink #FC5FA3
        case .light: return NSColor(red: 0.608, green: 0.165, blue: 0.639, alpha: 1.0) // Purple
        case .navy: return NSColor(red: 0.0, green: 0.851, blue: 1.0, alpha: 1.0) // #00D9FF
        case .lightBlue: return NSColor(red: 0.486, green: 0.302, blue: 1.0, alpha: 1.0) // #7C4DFF
        case .xcodeLight: return NSColor(red: 0.608, green: 0.165, blue: 0.639, alpha: 1.0) // Purple (Classic Xcode)
        case .vscodeDefault: return NSColor(red: 0.337, green: 0.612, blue: 0.839, alpha: 1.0) // #569CD6
        case .visualStudio: return NSColor(red: 0.337, green: 0.612, blue: 0.839, alpha: 1.0) // #569CD6
        case .wwdc: return NSColor(red: 1.0, green: 0.176, blue: 0.333, alpha: 1.0) // Neon Pink/Red (#FF2D55)
        case .wwdcLight: return NSColor(red: 0.8, green: 0.0, blue: 0.2, alpha: 1.0) // Darker Pink/Red
        case .keynote: return NSColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0) // Orange
        case .keynoteLight: return NSColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0) // Darker Orange
        case .christmas: return NSColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0) // Bright Red
        case .christmasLight: return NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0) // Darker Red
        case .powershell: return NSColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0) // Yellow
        case .dracula, .draculaLight: return NSColor(red: 1.0, green: 0.475, blue: 0.776, alpha: 1.0) // #ff79c6
        case .githubDark, .githubLight: return NSColor(red: 1.0, green: 0.475, blue: 0.435, alpha: 1.0) // #ff7b72
        case .doki: return NSColor(red: 1.0, green: 0.4, blue: 0.6, alpha: 1.0) // Hot Pink
        case .happyNewYear2026: return NSColor(red: 1.0, green: 0.843, blue: 0.0, alpha: 1.0) // Gold #FFD700
        case .happyNewYear2026Light: return NSColor(red: 0.827, green: 0.184, blue: 0.184, alpha: 1.0) // Red
        case .transparent: return NSColor(red: 0.73, green: 0.47, blue: 1.0, alpha: 1.0) // Glowing Purple
        case .extraClear: return NSColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 1.0) // Sky Glow
        case .xnuDark: return NSColor(red: 1.0, green: 0.25, blue: 0.506, alpha: 1.0) // #FF4081 (Pink)
        case .microCodeTheme: return NSColor(red: 0.608, green: 0.165, blue: 0.639, alpha: 1.0) // Apple Purple (Xcode)
        case .monokaiPro: return NSColor(red: 1.0, green: 0.380, blue: 0.412, alpha: 1.0) // #FF6188 (Red/Pink)
        case .oneDarkPro: return NSColor(red: 0.796, green: 0.467, blue: 0.898, alpha: 1.0) // #CB77E5 (Purple)
        case .nightOwl: return NSColor(red: 0.780, green: 0.573, blue: 0.918, alpha: 1.0) // #C792EA (Purple)
        case .nord: return NSColor(red: 0.506, green: 0.631, blue: 0.757, alpha: 1.0) // #81A1C1 (Blue)
        case .tokyoNight: return NSColor(red: 0.729, green: 0.506, blue: 0.886, alpha: 1.0) // #BB9AF7 (Purple)
        case .catppuccin: return NSColor(red: 0.796, green: 0.651, blue: 0.969, alpha: 1.0) // #CBA6F7 (Mauve)
        case .cyberPunk: return NSColor(red: 1.0, green: 0.0, blue: 0.463, alpha: 1.0) // #FF0076 (Neon Red)
        case .synthWave: return NSColor(red: 0.992, green: 0.882, blue: 0.153, alpha: 1.0) // #FDE127 (Yellow)
        case .solarizedDark: return NSColor(red: 0.514, green: 0.580, blue: 0.000, alpha: 1.0) // #859900 (Green)
        case .solarizedLight: return NSColor(red: 0.514, green: 0.580, blue: 0.000, alpha: 1.0) // #859900 (Green)
        case .gruvboxDark: return NSColor(red: 0.984, green: 0.286, blue: 0.204, alpha: 1.0) // #FB4934 (Red)
        case .crystalClear: return NSColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 1.0) // Deep Blue
        case .obsidianGlass: return NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1.0) // Cyan
        }
    }
    
    var stringColor: NSColor {
        switch self {
        case .system: return NSApp?.effectiveAppearance.name == .darkAqua ? AppTheme.dark.stringColor : AppTheme.light.stringColor
        case .dark, .xcodeDark: return NSColor(red: 0.988, green: 0.416, blue: 0.365, alpha: 1.0) // Xcode Coral #FC6A5D
        case .light: return NSColor(red: 0.761, green: 0.196, blue: 0.169, alpha: 1.0) // Red
        case .navy: return NSColor(red: 1.0, green: 0.718, blue: 0.012, alpha: 1.0) // #FFB703
        case .lightBlue: return NSColor(red: 0.827, green: 0.184, blue: 0.184, alpha: 1.0) // #D32F2F
        case .xcodeLight: return NSColor(red: 0.761, green: 0.196, blue: 0.169, alpha: 1.0) // Red
        case .vscodeDefault: return NSColor(red: 0.808, green: 0.569, blue: 0.471, alpha: 1.0) // #CE9178
        case .visualStudio: return NSColor(red: 0.839, green: 0.616, blue: 0.522, alpha: 1.0) // #D69D85
        case .wwdc: return NSColor(red: 1.0, green: 0.839, blue: 0.04, alpha: 1.0) // Gold/Yellow
        case .wwdcLight: return NSColor(red: 0.8, green: 0.6, blue: 0.0, alpha: 1.0) // Darker Gold
        case .keynote: return NSColor(red: 0.188, green: 0.819, blue: 0.345, alpha: 1.0) // Green
        case .keynoteLight: return NSColor(red: 0.1, green: 0.6, blue: 0.2, alpha: 1.0) // Darker Green
        case .christmas: return NSColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0) // Gold
        case .christmasLight: return NSColor(red: 0.8, green: 0.6, blue: 0.0, alpha: 1.0) // Darker Gold
        case .powershell: return NSColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1.0) // Cyan
        case .dracula, .draculaLight: return NSColor(red: 0.945, green: 1.0, blue: 0.494, alpha: 1.0) // #f1fa8c
        case .githubDark, .githubLight: return NSColor(red: 0.639, green: 0.812, blue: 1.0, alpha: 1.0) // #a5d6ff
        case .doki: return NSColor(red: 0.4, green: 0.8, blue: 0.4, alpha: 1.0) // Green
        case .happyNewYear2026: return NSColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1.0) // Cyan
        case .happyNewYear2026Light: return NSColor(red: 0.188, green: 0.819, blue: 0.345, alpha: 1.0) // Green
        case .transparent: return NSColor(red: 0.0, green: 1.0, blue: 0.8, alpha: 1.0) // Neon Teal
        case .extraClear: return NSColor(red: 1.0, green: 0.5, blue: 1.0, alpha: 1.0) // Vivid Emrald
        case .xnuDark: return NSColor(red: 1.0, green: 0.54, blue: 0.4, alpha: 1.0) // #FF8A65 (Orange)
        case .microCodeTheme: return NSColor(red: 0.761, green: 0.196, blue: 0.169, alpha: 1.0) // Apple Red
        case .monokaiPro: return NSColor(red: 1.0, green: 0.847, blue: 0.361, alpha: 1.0) // #FFD866 (Yellow)
        case .oneDarkPro: return NSColor(red: 0.596, green: 0.765, blue: 0.455, alpha: 1.0) // #98C379 (Green)
        case .nightOwl: return NSColor(red: 0.925, green: 0.769, blue: 0.553, alpha: 1.0) // #ECC48D (Peach)
        case .nord: return NSColor(red: 0.643, green: 0.741, blue: 0.549, alpha: 1.0) // #A3BE8C (Green)
        case .tokyoNight: return NSColor(red: 0.608, green: 0.796, blue: 0.655, alpha: 1.0) // #9ECE6A (Green)
        case .catppuccin: return NSColor(red: 0.651, green: 0.890, blue: 0.631, alpha: 1.0) // #A6E3A1 (Green)
        case .cyberPunk: return NSColor(red: 0.004, green: 1.0, blue: 0.631, alpha: 1.0) // #01FF9F (Neon Green)
        case .synthWave: return NSColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1.0) // #00FFFF (Cyan)
        case .solarizedDark: return NSColor(red: 0.165, green: 0.631, blue: 0.596, alpha: 1.0) // #2AA198 (Cyan)
        case .solarizedLight: return NSColor(red: 0.165, green: 0.631, blue: 0.596, alpha: 1.0) // #2AA198 (Cyan)
        case .gruvboxDark: return NSColor(red: 0.722, green: 0.733, blue: 0.149, alpha: 1.0) // #B8BB26 (Green)
        case .crystalClear: return NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.8) // Dark Grey
        case .obsidianGlass: return NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.8) // Light Grey
        }
    }
    
    var commentColor: NSColor {
        switch self {
        case .system: return NSApp?.effectiveAppearance.name == .darkAqua ? AppTheme.dark.commentColor : AppTheme.light.commentColor
        case .dark, .xcodeDark: return NSColor(red: 0.424, green: 0.475, blue: 0.525, alpha: 1.0) // Xcode Slate Gray #6C7986
        case .light, .xcodeLight: return NSColor(red: 0.373, green: 0.514, blue: 0.349, alpha: 1.0) // Green-gray
        case .navy: return NSColor(red: 0.424, green: 0.459, blue: 0.490, alpha: 1.0) // #6C757D
        case .lightBlue: return NSColor(red: 0.333, green: 0.545, blue: 0.184, alpha: 1.0) // #558B2F
        case .vscodeDefault: return NSColor(red: 0.416, green: 0.600, blue: 0.333, alpha: 1.0) // #6A9955
        case .visualStudio: return NSColor(red: 0.341, green: 0.651, blue: 0.290, alpha: 1.0) // #57A64A
        case .wwdc: return NSColor(white: 0.5, alpha: 1.0) // Grey
        case .wwdcLight: return NSColor(white: 0.4, alpha: 1.0) // Darker Grey
        case .keynote: return NSColor(white: 0.5, alpha: 1.0) // Grey
        case .keynoteLight: return NSColor(white: 0.4, alpha: 1.0) // Darker Grey
        case .christmas: return NSColor(red: 0.8, green: 1.0, blue: 0.8, alpha: 1.0) // Light Mint
        case .christmasLight: return NSColor(red: 0.1, green: 0.4, blue: 0.1, alpha: 1.0) // Deep Green
        case .powershell: return NSColor(red: 0.0, green: 0.7, blue: 0.0, alpha: 1.0) // Dark Green
        case .dracula, .draculaLight: return NSColor(red: 0.384, green: 0.447, blue: 0.643, alpha: 1.0) // #6272a4
        case .githubDark: return NSColor(red: 0.549, green: 0.58, blue: 0.624, alpha: 1.0) // #8b949e
        case .githubLight: return NSColor(red: 0.42, green: 0.459, blue: 0.49, alpha: 1.0) // #6a737d
        case .doki: return NSColor(red: 0.6, green: 0.6, blue: 0.7, alpha: 1.0) // Slate
        case .happyNewYear2026: return NSColor(red: 0.4, green: 0.4, blue: 0.6, alpha: 1.0) // Muted Blue Gray
        case .happyNewYear2026Light: return NSColor(red: 0.5, green: 0.5, blue: 0.6, alpha: 1.0)
        case .transparent: return NSColor(white: 0.7, alpha: 1.0)
        case .extraClear: return NSColor(white: 0.8, alpha: 0.6)
        case .xnuDark: return NSColor(red: 0.3, green: 0.69, blue: 0.31, alpha: 1.0) // #4CAF50 (Green)
        case .microCodeTheme: return NSColor(red: 0.33, green: 0.38, blue: 0.44, alpha: 1.0) // Apple Gray
        case .monokaiPro: return NSColor(red: 0.447, green: 0.439, blue: 0.412, alpha: 1.0) // #727069
        case .oneDarkPro: return NSColor(red: 0.365, green: 0.392, blue: 0.439, alpha: 1.0) // #5C6370
        case .nightOwl: return NSColor(red: 0.388, green: 0.467, blue: 0.467, alpha: 1.0) // #637777
        case .nord: return NSColor(red: 0.369, green: 0.416, blue: 0.482, alpha: 1.0) // #4C566A
        case .tokyoNight: return NSColor(red: 0.345, green: 0.369, blue: 0.494, alpha: 1.0) // #565F89
        case .catppuccin: return NSColor(red: 0.424, green: 0.447, blue: 0.522, alpha: 1.0) // #6C7086 (Overlay0)
        case .cyberPunk: return NSColor(red: 0.439, green: 0.439, blue: 0.490, alpha: 1.0) // #70707D
        case .synthWave: return NSColor(red: 0.306, green: 0.247, blue: 0.404, alpha: 1.0) // #493F67
        case .solarizedDark: return NSColor(red: 0.345, green: 0.431, blue: 0.459, alpha: 1.0) // #586E75
        case .solarizedLight: return NSColor(red: 0.576, green: 0.631, blue: 0.631, alpha: 1.0) // #93A1A1
        case .gruvboxDark: return NSColor(red: 0.573, green: 0.514, blue: 0.451, alpha: 1.0) // #928374
        case .crystalClear: return NSColor(red: 0.2, green: 0.4, blue: 0.2, alpha: 0.6) // Glassy Green
        case .obsidianGlass: return NSColor(red: 0.4, green: 0.6, blue: 0.4, alpha: 0.6) // Glassy Green
        }
    }
    
    var numberColor: NSColor {
        switch self {
        case .system: return NSApp?.effectiveAppearance.name == .darkAqua ? AppTheme.dark.numberColor : AppTheme.light.numberColor
        case .dark, .xcodeDark: return NSColor(red: 0.816, green: 0.749, blue: 0.412, alpha: 1.0) // Xcode Gold #D0BF69
        case .light, .xcodeLight: return NSColor(red: 0.071, green: 0.408, blue: 0.616, alpha: 1.0) // Blue
        case .navy: return NSColor(red: 0.549, green: 0.906, blue: 0.992, alpha: 1.0) // Light cyan
        case .lightBlue: return NSColor(red: 0.071, green: 0.408, blue: 0.616, alpha: 1.0)
        case .vscodeDefault: return NSColor(red: 0.710, green: 0.808, blue: 0.659, alpha: 1.0) // #B5CEA8
        case .visualStudio: return NSColor(red: 0.710, green: 0.808, blue: 0.659, alpha: 1.0)
        case .wwdc: return NSColor(red: 0.686, green: 0.321, blue: 0.87, alpha: 1.0) // Purple
        case .wwdcLight: return NSColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1.0) // Darker Purple
        case .keynote: return NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0) // Blue
        case .keynoteLight: return NSColor(red: 0.0, green: 0.3, blue: 0.8, alpha: 1.0) // Darker Blue
        case .christmas: return NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0) // Christmas Green
        case .christmasLight: return NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0) // Green
        case .powershell: return NSColor(red: 0.8, green: 0.4, blue: 0.8, alpha: 1.0) // Magenta
        case .dracula, .draculaLight: return NSColor(red: 0.741, green: 0.576, blue: 0.976, alpha: 1.0) // #bd93f9
        case .githubDark, .githubLight: return NSColor(red: 0.475, green: 0.651, blue: 0.961, alpha: 1.0) // #79c0ff
        case .doki: return NSColor(red: 0.6, green: 0.6, blue: 1.0, alpha: 1.0) // Blueish
        case .happyNewYear2026: return NSColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0) // Orange
        case .happyNewYear2026Light: return NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0) // Blue
        case .transparent: return NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0) // Neon Yellow
        case .extraClear: return NSColor(red: 1.0, green: 0.5, blue: 1.0, alpha: 1.0) // Neon Pink
        case .xnuDark: return NSColor(red: 1.0, green: 0.84, blue: 0.31, alpha: 1.0) // #FFD54F (Yellow)
        case .microCodeTheme: return NSColor(red: 0.071, green: 0.408, blue: 0.616, alpha: 1.0) // Apple Blue
        case .monokaiPro: return NSColor(red: 0.671, green: 0.553, blue: 1.0, alpha: 1.0) // #AB8DFF (Purple)
        case .oneDarkPro: return NSColor(red: 0.898, green: 0.725, blue: 0.369, alpha: 1.0) // #E5C07B (Gold)
        case .nightOwl: return NSColor(red: 0.969, green: 0.549, blue: 0.424, alpha: 1.0) // #F78C6C (Orange)
        case .nord: return NSColor(red: 0.733, green: 0.580, blue: 0.835, alpha: 1.0) // #B48EAD (Purple)
        case .tokyoNight: return NSColor(red: 1.0, green: 0.608, blue: 0.404, alpha: 1.0) // #FF9E64 (Orange)
        case .catppuccin: return NSColor(red: 0.980, green: 0.702, blue: 0.529, alpha: 1.0) // #FAB387 (Peach)
        case .cyberPunk: return NSColor(red: 1.0, green: 0.522, blue: 0.059, alpha: 1.0) // #FF850F (Orange)
        case .synthWave: return NSColor(red: 1.0, green: 0.569, blue: 0.176, alpha: 1.0) // #FF912D (Orange)
        case .solarizedDark: return NSColor(red: 0.827, green: 0.294, blue: 0.196, alpha: 1.0) // #D33692 (Magenta) - Used for numbers/constants often
        case .solarizedLight: return NSColor(red: 0.827, green: 0.294, blue: 0.196, alpha: 1.0) // #D33692 (Magenta)
        case .gruvboxDark: return NSColor(red: 0.831, green: 0.612, blue: 0.780, alpha: 1.0) // #D3869B (Purple)
        case .crystalClear: return NSColor(red: 0.6, green: 0.2, blue: 0.8, alpha: 1.0) // Purple
        case .obsidianGlass: return NSColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 1.0) // Lilac
        }
    }
    
    var typeColor: NSColor {
        switch self {
        case .system: return NSApp?.effectiveAppearance.name == .darkAqua ? AppTheme.dark.typeColor : AppTheme.light.typeColor
        case .dark, .xcodeDark: return NSColor(red: 0.365, green: 0.847, blue: 0.808, alpha: 1.0) // Xcode Teal #5DD8CE
        case .light, .xcodeLight: return NSColor(red: 0.110, green: 0.404, blue: 0.576, alpha: 1.0) // Teal
        case .navy: return NSColor(red: 0.498, green: 0.859, blue: 0.702, alpha: 1.0) // Mint
        case .lightBlue: return NSColor(red: 0.082, green: 0.396, blue: 0.753, alpha: 1.0) // #1565C0 (Darker Blue for better contrast)
        case .vscodeDefault: return NSColor(red: 0.306, green: 0.788, blue: 0.690, alpha: 1.0) // #4EC9B0
        case .visualStudio: return NSColor(red: 0.306, green: 0.788, blue: 0.690, alpha: 1.0)
        case .wwdc: return NSColor(red: 0.353, green: 0.784, blue: 0.98, alpha: 1.0) // Cyan
        case .wwdcLight: return NSColor(red: 0.0, green: 0.6, blue: 0.8, alpha: 1.0) // Darker Cyan
        case .keynote: return NSColor(red: 1.0, green: 0.176, blue: 0.333, alpha: 1.0) // Pink
        case .keynoteLight: return NSColor(red: 0.8, green: 0.0, blue: 0.2, alpha: 1.0) // Darker Pink
        case .christmas: return NSColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0) // Light Red
        case .christmasLight: return NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0) // Red
        case .powershell: return NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0) // White
        case .dracula, .draculaLight: return NSColor(red: 0.545, green: 0.914, blue: 0.992, alpha: 1.0) // #8be9fd
        case .githubDark: return NSColor(red: 0.839, green: 0.639, blue: 0.490, alpha: 1.0) // #d2a87d
        case .githubLight: return NSColor(red: 0.439, green: 0.259, blue: 0.643, alpha: 1.0) // #6f42c1
        case .doki: return NSColor(red: 0.9, green: 0.6, blue: 0.9, alpha: 1.0) // Soft Purple
        case .happyNewYear2026: return NSColor(red: 0.5, green: 0.9, blue: 1.0, alpha: 1.0) // Light Cyan
        case .happyNewYear2026Light: return NSColor(red: 0.4, green: 0.2, blue: 0.8, alpha: 1.0) // Purple
        case .transparent: return NSColor(red: 1.0, green: 0.2, blue: 0.6, alpha: 1.0) // Hot Pink
        case .extraClear: return NSColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1.0) // Lime
        case .xnuDark: return NSColor(red: 0.31, green: 0.76, blue: 0.97, alpha: 1.0) // #4FC3F7 (Light Blue)
        case .microCodeTheme: return NSColor(red: 0.05, green: 0.45, blue: 0.55, alpha: 1.0) // Deep Apple Teal
        case .monokaiPro: return NSColor(red: 0.412, green: 0.847, blue: 0.988, alpha: 1.0) // #69D9FC (Blue)
        case .oneDarkPro: return NSColor(red: 0.349, green: 0.718, blue: 0.773, alpha: 1.0) // #56B6C2 (Cyan)
        case .nightOwl: return NSColor(red: 0.510, green: 0.667, blue: 1.0, alpha: 1.0) // #82AAFF (Blue)
        case .nord: return NSColor(red: 0.561, green: 0.737, blue: 0.733, alpha: 1.0) // #8FBCBB (Teal)
        case .tokyoNight: return NSColor(red: 0.165, green: 0.796, blue: 0.902, alpha: 1.0) // #2AC3DE (Cyan)
        case .catppuccin: return NSColor(red: 0.533, green: 0.753, blue: 0.933, alpha: 1.0) // #89B4FA (Blue)
        case .cyberPunk: return NSColor(red: 0.612, green: 0.153, blue: 0.957, alpha: 1.0) // #9C27F4 (Purple)
        case .synthWave: return NSColor(red: 0.224, green: 0.863, blue: 1.0, alpha: 1.0) // #39DCFF (Cyan)
        case .solarizedDark: return NSColor(red: 0.796, green: 0.545, blue: 0.0, alpha: 1.0) // #CB4B16 (Orange) - Types often mapped here or Yellow
        case .solarizedLight: return NSColor(red: 0.796, green: 0.545, blue: 0.0, alpha: 1.0) // #CB4B16 (Orange)
        case .gruvboxDark: return NSColor(red: 0.980, green: 0.741, blue: 0.184, alpha: 1.0) // #FABD2F (Yellow)
        case .crystalClear: return NSColor(red: 0.0, green: 0.5, blue: 0.5, alpha: 1.0) // Cyan
        case .obsidianGlass: return NSColor(red: 0.2, green: 0.9, blue: 0.9, alpha: 1.0) // Bright Cyan
        }
    }
    
    var functionColor: NSColor {
        switch self {
        case .system: return NSApp?.effectiveAppearance.name == .darkAqua ? AppTheme.dark.functionColor : AppTheme.light.functionColor
        case .dark, .xcodeDark: return NSColor(red: 0.255, green: 0.655, blue: 0.988, alpha: 1.0) // Xcode Vibrant Blue #41A7FC
        case .light: return NSColor(red: 0.067, green: 0.376, blue: 0.537, alpha: 1.0)
        case .navy: return NSColor(red: 0.984, green: 0.769, blue: 0.353, alpha: 1.0) // Gold
        case .lightBlue: return NSColor(red: 0.506, green: 0.298, blue: 0.757, alpha: 1.0) // Purple
        case .xcodeLight: return NSColor(red: 0.067, green: 0.376, blue: 0.537, alpha: 1.0) // Navy
        case .vscodeDefault: return NSColor(red: 0.863, green: 0.863, blue: 0.667, alpha: 1.0) // #DCDCAA
        case .visualStudio: return NSColor(red: 0.863, green: 0.863, blue: 0.667, alpha: 1.0)
        case .wwdc: return NSColor(red: 0.0, green: 0.98, blue: 0.6, alpha: 1.0) // Mint Green
        case .wwdcLight: return NSColor(red: 0.0, green: 0.7, blue: 0.4, alpha: 1.0) // Darker Mint
        case .keynote: return NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0) // Yellow
        case .keynoteLight: return NSColor(red: 0.8, green: 0.6, blue: 0.0, alpha: 1.0) // Darker Yellow
        case .christmas: return NSColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0) // Gold
        case .christmasLight: return NSColor(red: 0.8, green: 0.6, blue: 0.0, alpha: 1.0) // Darker Gold
        case .powershell: return NSColor(red: 1.0, green: 1.0, blue: 0.8, alpha: 1.0) // Light Yellow
        case .dracula, .draculaLight: return NSColor(red: 0.314, green: 0.980, blue: 0.482, alpha: 1.0) // #50fa7b
        case .githubDark: return NSColor(red: 0.839, green: 0.639, blue: 0.490, alpha: 1.0) // #d2a87d
        case .githubLight: return NSColor(red: 0.439, green: 0.259, blue: 0.643, alpha: 1.0) // #6f42c1
        case .doki: return NSColor(red: 1.0, green: 0.7, blue: 0.4, alpha: 1.0) // Peach
        case .happyNewYear2026: return NSColor(red: 0.9, green: 0.4, blue: 0.9, alpha: 1.0) // Festive Magenta
        case .happyNewYear2026Light: return NSColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0) // Warm Orange
        case .transparent: return NSColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1.0) // Cyan
        case .extraClear: return NSColor(red: 1.0, green: 0.4, blue: 0.2, alpha: 1.0) // Sunset
        case .xnuDark: return NSColor(red: 0.31, green: 0.76, blue: 0.97, alpha: 1.0) // #4FC3F7
        case .microCodeTheme: return NSColor(red: 0.0, green: 0.22, blue: 0.38, alpha: 1.0) // Deep Navy (Focus)
        case .monokaiPro: return NSColor(red: 0.639, green: 0.863, blue: 0.353, alpha: 1.0) // #A9DC5A (Green)
        case .oneDarkPro: return NSColor(red: 0.380, green: 0.655, blue: 0.871, alpha: 1.0) // #61AFEF (Blue)
        case .nightOwl: return NSColor(red: 0.510, green: 0.667, blue: 1.0, alpha: 1.0) // #82AAFF (Blue)
        case .nord: return NSColor(red: 0.533, green: 0.655, blue: 0.812, alpha: 1.0) // #88C0D0 (Blue)
        case .tokyoNight: return NSColor(red: 0.490, green: 0.690, blue: 0.941, alpha: 1.0) // #7DCFFF (Blue)
        case .catppuccin: return NSColor(red: 0.537, green: 0.706, blue: 0.980, alpha: 1.0) // #89B4FA (Blue)
        case .cyberPunk: return NSColor(red: 1.0, green: 0.0, blue: 0.886, alpha: 1.0) // #FF00E2 (Pink)
        case .synthWave: return NSColor(red: 1.0, green: 0.082, blue: 0.435, alpha: 1.0) // #FF156F (Pink)
        case .solarizedDark: return NSColor(red: 0.149, green: 0.545, blue: 0.824, alpha: 1.0) // #268BD2 (Blue)
        case .solarizedLight: return NSColor(red: 0.149, green: 0.545, blue: 0.824, alpha: 1.0) // #268BD2 (Blue)
        case .gruvboxDark: return NSColor(red: 0.514, green: 0.780, blue: 0.769, alpha: 1.0) // #83A598 (Blue)
        case .crystalClear: return NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0) // Blue
        case .obsidianGlass: return NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0) // Light Blue
        }
    }
    
    // Editor UI Colors (Harmonized)
    
    var selectionColor: NSColor {
        switch self {
        case .system: return NSApp?.effectiveAppearance.name == .darkAqua ? AppTheme.dark.selectionColor : AppTheme.light.selectionColor
        case .dark: return NSColor(red: 0.16, green: 0.24, blue: 0.36, alpha: 1.0) // #2A3D5D
        case .light: return NSColor(red: 1.0, green: 0.92, blue: 0.65, alpha: 1.0) // #FFEAA7
        case .navy: return NSColor(red: 0.15, green: 0.2, blue: 0.4, alpha: 1.0)
        case .lightBlue: return NSColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 1.0)
        case .xcodeLight: return NSColor(red: 0.70, green: 0.84, blue: 1.0, alpha: 1.0) // Xcode Selection
        case .xcodeDark: return NSColor(red: 0.25, green: 0.30, blue: 0.40, alpha: 1.0)
        case .vscodeDefault: return NSColor(red: 0.16, green: 0.24, blue: 0.36, alpha: 1.0)
        case .visualStudio: return NSColor(red: 0.16, green: 0.24, blue: 0.36, alpha: 1.0)
        case .wwdc: return NSColor(red: 0.3, green: 0.1, blue: 0.2, alpha: 1.0)
        case .wwdcLight: return NSColor(red: 1.0, green: 0.9, blue: 0.9, alpha: 1.0)
        case .keynote: return NSColor(white: 0.2, alpha: 1.0)
        case .keynoteLight: return NSColor(white: 0.9, alpha: 1.0)
        case .christmas: return NSColor(red: 0.1, green: 0.3, blue: 0.1, alpha: 1.0)
        case .christmasLight: return NSColor(red: 0.9, green: 1.0, blue: 0.9, alpha: 1.0)
        case .powershell: return NSColor(red: 0.0, green: 0.3, blue: 0.6, alpha: 1.0)
        case .dracula, .draculaLight: return NSColor(red: 0.275, green: 0.286, blue: 0.353, alpha: 1.0) // #44475a
        case .githubDark: return NSColor(red: 0.2, green: 0.25, blue: 0.35, alpha: 1.0)
        case .githubLight: return NSColor(red: 0.8, green: 0.88, blue: 1.0, alpha: 1.0)
        case .doki: return NSColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 1.0)
        case .happyNewYear2026: return NSColor(red: 0.2, green: 0.1, blue: 0.3, alpha: 1.0) // Deep Purple
        case .happyNewYear2026Light: return NSColor(red: 1.0, green: 0.9, blue: 0.8, alpha: 1.0) // Warm
        case .transparent: return NSColor(white: 1.0, alpha: 0.2) // Glassy White
        case .extraClear: return NSColor(white: 1.0, alpha: 0.1) // Subtle Highlight
        case .xnuDark: return NSColor(red: 0.173, green: 0.243, blue: 0.314, alpha: 1.0) // #2C3E50
        case .microCodeTheme: return NSColor(red: 0.70, green: 0.84, blue: 1.0, alpha: 1.0) // Apple Highlight Blue
        case .monokaiPro: return NSColor(red: 0.251, green: 0.243, blue: 0.282, alpha: 1.0) // #403E48
        case .oneDarkPro: return NSColor(red: 0.235, green: 0.251, blue: 0.306, alpha: 1.0) // #3D414D
        case .nightOwl: return NSColor(red: 0.114, green: 0.231, blue: 0.325, alpha: 1.0) // #1D3B53
        case .nord: return NSColor(red: 0.263, green: 0.298, blue: 0.369, alpha: 1.0) // #434C5E
        case .tokyoNight: return NSColor(red: 0.204, green: 0.227, blue: 0.314, alpha: 1.0) // #343A50
        case .catppuccin: return NSColor(red: 0.275, green: 0.275, blue: 0.369, alpha: 1.0) // #45475A
        case .cyberPunk: return NSColor(red: 0.2, green: 0.05, blue: 0.3, alpha: 1.0) // #330D4D
        case .synthWave: return NSColor(red: 0.271, green: 0.149, blue: 0.361, alpha: 1.0) // #45265C
        case .solarizedDark: return NSColor(red: 0.027, green: 0.212, blue: 0.259, alpha: 1.0) // #073642
        case .solarizedLight: return NSColor(red: 0.933, green: 0.910, blue: 0.835, alpha: 1.0) // #EEE8D5
        case .gruvboxDark: return NSColor(red: 0.314, green: 0.286, blue: 0.263, alpha: 1.0) // #504945
        case .crystalClear: return NSColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 0.2) // Blue Tint
        case .obsidianGlass: return NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 0.2) // Cyan Tint
        }
    }
    
    var lineHighlightColor: NSColor {
        switch self {
        case .system: return NSApp?.effectiveAppearance.name == .darkAqua ? AppTheme.dark.lineHighlightColor : AppTheme.light.lineHighlightColor
        case .dark: return NSColor(red: 0.07, green: 0.09, blue: 0.15, alpha: 1.0) // #111827
        case .light: return NSColor(red: 1.0, green: 0.96, blue: 0.8, alpha: 1.0) // #FFF4CC
        case .navy: return NSColor(red: 0.05, green: 0.08, blue: 0.2, alpha: 1.0)
        case .lightBlue: return NSColor(red: 0.9, green: 0.95, blue: 1.0, alpha: 1.0)
        case .xcodeLight: return NSColor(red: 0.92, green: 0.96, blue: 1.0, alpha: 1.0)
        case .xcodeDark: return NSColor(red: 0.15, green: 0.18, blue: 0.22, alpha: 1.0)
        case .vscodeDefault: return NSColor(red: 0.07, green: 0.09, blue: 0.15, alpha: 1.0)
        case .visualStudio: return NSColor(red: 0.07, green: 0.09, blue: 0.15, alpha: 1.0)
        case .wwdc: return NSColor(red: 0.15, green: 0.05, blue: 0.1, alpha: 1.0)
        case .wwdcLight: return NSColor(red: 1.0, green: 0.95, blue: 0.95, alpha: 1.0)
        case .keynote: return NSColor(white: 0.1, alpha: 1.0)
        case .keynoteLight: return NSColor(white: 0.95, alpha: 1.0)
        case .christmas: return NSColor(red: 0.05, green: 0.1, blue: 0.05, alpha: 1.0)
        case .christmasLight: return NSColor(red: 0.95, green: 1.0, blue: 0.95, alpha: 1.0)
        case .powershell: return NSColor(red: 0.0, green: 0.1, blue: 0.4, alpha: 1.0)
        case .dracula, .draculaLight: return NSColor(red: 0.275, green: 0.286, blue: 0.353, alpha: 0.5) // #44475a
        case .githubDark: return NSColor(red: 0.1, green: 0.12, blue: 0.18, alpha: 1.0)
        case .githubLight: return NSColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1.0)
        case .doki: return NSColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0)
        case .happyNewYear2026: return NSColor(red: 0.1, green: 0.05, blue: 0.2, alpha: 1.0)
        case .happyNewYear2026Light: return NSColor(red: 1.0, green: 0.95, blue: 0.9, alpha: 1.0)
        case .transparent: return NSColor(white: 1.0, alpha: 0.1)
        case .extraClear: return NSColor(white: 1.0, alpha: 0.05)
        case .xnuDark: return NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1.0) // #1E1E1E
        case .microCodeTheme: return NSColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1.0) // Very Light Blue-Grey
        case .monokaiPro: return NSColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0)
        case .oneDarkPro: return NSColor(red: 0.18, green: 0.20, blue: 0.23, alpha: 1.0)
        case .nightOwl: return NSColor(red: 0.004, green: 0.071, blue: 0.122, alpha: 1.0) // #01121F
        case .nord: return NSColor(red: 0.23, green: 0.26, blue: 0.32, alpha: 1.0)
        case .tokyoNight: return NSColor(red: 0.13, green: 0.13, blue: 0.22, alpha: 1.0)
        case .catppuccin: return NSColor(red: 0.15, green: 0.15, blue: 0.22, alpha: 1.0)
        case .cyberPunk: return NSColor(red: 0.1, green: 0.05, blue: 0.2, alpha: 1.0)
        case .synthWave: return NSColor(red: 0.2, green: 0.12, blue: 0.3, alpha: 1.0)
        case .solarizedDark: return NSColor(red: 0.02, green: 0.18, blue: 0.23, alpha: 1.0)
        case .solarizedLight: return NSColor(red: 0.96, green: 0.94, blue: 0.88, alpha: 1.0)
        case .gruvboxDark: return NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        case .crystalClear: return NSColor(white: 1.0, alpha: 0.1)
        case .obsidianGlass: return NSColor(white: 0.2, alpha: 0.2)
        }
    }
    
    /// Convert AppTheme to Theme for the syntax engine
    func toTheme() -> Theme {
        // Dark & Xcode Dark map directly to MicroCode Pro Dark (Xcode Dark Aesthetic)
        if self == .dark || self == .xcodeDark {
            return ThemeManager.createDefaultDarkTheme()
        }

        // Fallback colors for properties not explicitly in AppTheme
        let selectionHex = selectionColor.hexString
        let lineHighlightHex = lineHighlightColor.hexString
        let cursorHex = isDark ? "#FFFFFF" : "#000000"
        let gutterHex = editorBackground.hexString
        let gutterTextHex = isDark ? "#4A4A50" : "#B2BEC3"

        return Theme(
            name: self.rawValue,
            displayName: self.displayName,
            isDark: self.isDark,
            editorBackground: editorBackground.hexString,
            editorForeground: editorText.hexString,
            editorSelection: selectionHex,
            editorLineHighlight: lineHighlightHex,
            editorCursor: cursorHex,
            editorGutter: gutterHex,
            editorGutterText: gutterTextHex,
            tokenColors: [
                "keyword": TokenStyleConfig(foreground: keywordColor.hexString),
                "keywordControl": TokenStyleConfig(foreground: keywordColor.hexString),
                "keywordDeclaration": TokenStyleConfig(foreground: keywordColor.hexString),
                "keywordModifier": TokenStyleConfig(foreground: keywordColor.hexString),
                "keywordOperator": TokenStyleConfig(foreground: keywordColor.hexString),
                "string": TokenStyleConfig(foreground: stringColor.hexString),
                "comment": TokenStyleConfig(foreground: commentColor.hexString),
                "commentDoc": TokenStyleConfig(foreground: commentColor.hexString),
                "commentBlock": TokenStyleConfig(foreground: commentColor.hexString),
                "number": TokenStyleConfig(foreground: numberColor.hexString),
                "type": TokenStyleConfig(foreground: typeColor.hexString),
                "function": TokenStyleConfig(foreground: functionColor.hexString),
                "identifier": TokenStyleConfig(foreground: editorText.hexString),
                "variable": TokenStyleConfig(foreground: editorText.hexString),
                "property": TokenStyleConfig(foreground: typeColor.hexString),
                "parameter": TokenStyleConfig(foreground: editorText.hexString),
                "boolean": TokenStyleConfig(foreground: keywordColor.hexString),
                "null": TokenStyleConfig(foreground: keywordColor.hexString),
                "operator": TokenStyleConfig(foreground: editorText.hexString),
                "punctuation": TokenStyleConfig(foreground: editorText.hexString),
                "delimiter": TokenStyleConfig(foreground: editorText.hexString),
                "annotation": TokenStyleConfig(foreground: "#FD8F3F"),
                "preprocessor": TokenStyleConfig(foreground: "#FD8F3F"),
                "escape": TokenStyleConfig(foreground: numberColor.hexString)
            ]
        )
    }
}

// MARK: - Editor Mode Enum

enum EditorMode: String, CaseIterable, Identifiable {
    case code = "code"
    case science = "science"
    case playground = "playground"
    case notebook = "notebook"
    case scenario = "scenario"
    case design = "design"
    case remoteX = "Remote X"
    case embedded = "Embedded Studio"
    case aiAgent = "AI Agent"
    case browser = "Browser"
    case apiClient = "apiClient"
    case extensions = "extensions"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .code: return "Code Editor"
        case .science: return "Science Mode"
        case .playground: return "Playground"
        case .remoteX: return "Remote Explorer"
        case .notebook: return "Notebook"
        case .scenario: return "Scenario"
        case .design: return "Design"
        case .embedded: return "Embed & IoT Studio"
        case .aiAgent: return "AI Agent"
        case .browser: return "Browser"
        case .apiClient: return "API Studio"
        case .extensions: return "Extension Studio"
        }
    }
    
    var icon: String {
        switch self {
        case .code: return "doc.text"
        case .science: return "atom"
        case .playground: return "play.rectangle"
        case .remoteX: return "server.rack"
        case .notebook: return "book.pages"
        case .scenario: return "flowchart"
        case .design: return "paintbrush.pointed" // Penpot style icon
        case .embedded: return "cpu.fill" // Chip icon
        case .aiAgent: return "brain.head.profile" // AI brain icon
        case .browser: return "globe" // Browser icon
        case .apiClient: return "network" // API Studio icon
        case .extensions: return "puzzlepiece.extension" // Extension Studio icon
        }
    }
}

// MARK: - Python Version Info

struct PythonVersionInfo: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let version: String
    let displayName: String
    
    var isSystem: Bool {
        path.hasPrefix("/usr/") || path.hasPrefix("/System/")
    }
}

// MARK: - Project Type (Moved to ProjectManager.swift)

@MainActor
class AppState: ObservableObject {
    static weak var shared: AppState? = nil

    // MARK: - Published Properties

    @Published var openFiles: [CodeFile] = []
    @Published var currentFileIndex: Int = 0
    @Published var currentFile: CodeFile?
    @Published var microCodeService: MicroCodeService? // AI Core

    @Published var sidebarVisible: Bool = true
    @Published var consoleVisible: Bool = true
    @Published var gitPanelVisible: Bool = false
    @Published var agenticContextVisible: Bool = true
    @Published var selectedInspectorTab: AgenticInspectorTab = .context

    @Published var consoleOutput: String = ""
    @Published var isExecuting: Bool = false

    @Published var workspaceFolder: URL?
    @Published var showingFirstLaunchWelcome: Bool = true
    @Published var showingWelcomeHome: Bool = false

    func closeWorkspace() {
        workspaceFolder = nil
        openFiles.removeAll()
        currentFile = nil
        editorMode = .code
        UserDefaults.standard.removeObject(forKey: "lastWorkspacePath")
    }

    func showWelcomeScreen() {
        closeWorkspace()
        showingWelcomeHome = true
    }

    func showFirstLaunchOnboarding() {
        showingFirstLaunchWelcome = true
    }
    @Published var fileTree: [FileNode] = []
    @Published private(set) var fileTreeRevision: UInt64 = 0
    @Published var fileTreeLimitWarning: String?
    
    /// Always returns the active project directory for Terminal and tools, following the currently opened workspace.
    var activeTerminalDirectory: String {
        if let folder = workspaceFolder?.path, !folder.isEmpty, FileManager.default.fileExists(atPath: folder) {
            return folder
        }
        if let last = UserDefaults.standard.string(forKey: "lastWorkspacePath"), !last.isEmpty, FileManager.default.fileExists(atPath: last) {
            return last
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    @Published var gitStatus: GitStatus?
    @Published var gitCommits: [GitCommit] = []
    @Published var gitBranches: [String] = []
    @Published var gitStashList: [String] = []
    @Published var gitRemoteURL: String = ""
    @Published var gitDiff: String = ""
    @Published var gitDiffFile: String = ""
    @Published var gitOperationMessage: String = ""
    @Published var gitIsWorking: Bool = false
    @Published var gitIsGeneratingCommitMessage: Bool = false
    /// Kept separate from `gitStatus`: a repository can be valid even before
    /// it has its first commit or any tracked files.
    @Published private(set) var gitRepositoryAvailable: Bool = false
    @Published var cicdRuns: [WorkflowRun] = []
    @Published var cicdLoading: Bool = false
    
    // Browser
    @Published var browserURL: String = "https://www.google.com"
    @Published var browserTitle: String = ""
    @Published var browserIsLoading: Bool = false
    @Published var browserCanGoBack: Bool = false
    @Published var browserCanGoForward: Bool = false
    @Published var browserHistory: [BrowserHistoryEntry] = []
    @Published var browserBookmarks: [BrowserBookmark] = []
    @Published var browserTabs: [BrowserTab] = [BrowserTab(url: "https://www.google.com", title: "New Tab")]
    @Published var browserActiveTab: Int = 0

    @Published var hasUnsavedChanges: Bool = false
    
    // MARK: - Compute & Billing State
    @Published var currentComputeTarget: ComputeTarget = .localCPU
    @Published var userTokenBalance: Int = 0
    @Published var isPremiumSubscriber: Bool = false
    @Published var selectedSSHComputeServer: RemoteConnectionConfig?
    
    // Custom HPC Configuration
    @AppStorage("hpcEndpoint") var hpcEndpoint: String = "ws://127.0.0.1:8080/v1/agent"
    @AppStorage("hpcToken") var hpcToken: String = ""

    @Published var fontSize: CGFloat = 16
    @Published var fontFamily: String = "SF Mono"
    @Published var appTheme: AppTheme = .dark
    /// Disabled by default. The editor uses a non-ruler overlay when enabled
    /// so this preference never changes NSScrollView's intrinsic layout.
    @Published var showLineNumbers: Bool = false
    
    // AI Agent Chat Font Settings
    @Published var agentFontName: String = "SF Pro"
    @Published var agentFontSize: CGFloat = 16.0
    
    // Playground Font Settings
    @Published var playgroundFontName: String = "SF Mono"
    @Published var playgroundFontSize: CGFloat = 16.0
    @Published var playgroundFontWeight: Int = 2 // 0: Thin, 1: Light, 2: Regular, 3: Medium, 4: Semibold, 5: Bold
    
    // Notebook Cell Font Settings
    @Published var cellFontName: String = "SF Mono"
    @Published var cellFontSize: CGFloat = 16.0
    @Published var cellFontWeight: Int = 2 // Regular
    @Published var selectedLanguage: String = "python"
    
    // AI Code Export - used to pass code from AI Agent to Playground/Notebook
    @Published var aiExportedCode: String? = nil

    @Published var showingRefactorDialog: Bool = false
    @Published var showingRefactorProWindow: Bool = false
    @Published var showingExpandCodeWindow: Bool = false
    @Published var showingFormatCodeWindow: Bool = false
    @Published var showingCodeAnalysisWindow: Bool = false
    // Removed showingExportWindow
    @Published var showingCommitDialog: Bool = false
    @Published var showingSettingsDialog: Bool = false
    @Published var settingsSelectedTab: Int = 2
    @Published var showingSimulatorDialog: Bool = false
    @Published var showingNewFileDialog: Bool = false
    @Published var showingNewConversationDialog: Bool = false
    @Published var showingNodeManager: Bool = false
    @Published var showingDatabaseStudio: Bool = false
    @Published var showingAPIClient: Bool = false {
        didSet {
            if showingAPIClient {
                openAPIStudio()
                showingAPIClient = false
            }
        }
    }
    @Published var showingCICDView: Bool = false
    @Published var showingProjectRuntime: Bool = false
    @Published var showingSubAgentMonitor: Bool = false
    
    // Project Detection
    @Published var currentProjectType: ProjectType = .unknown
    
    // Editor Mode - exclusive selection
    @Published var editorMode: EditorMode = .code
    
    // Python Version Selection
    @Published var selectedPythonVersion: String = "python3"
    @Published var availablePythonVersions: [PythonVersionInfo] = []
    
    // Legacy mode flags (computed for backwards compatibility)
    var playgroundMode: Bool {
        get { editorMode == .playground }
        set { if newValue { setEditorMode(.playground) } else if editorMode == .playground { setEditorMode(.code) } }
    }
    
    var notebookMode: Bool {
        get { editorMode == .notebook }
        set { if newValue { setEditorMode(.notebook) } else if editorMode == .notebook { setEditorMode(.code) } }
    }
    
    var scenarioMode: Bool {
        get { editorMode == .scenario }
        set { if newValue { setEditorMode(.scenario) } else if editorMode == .scenario { setEditorMode(.code) } }
    }
    
    @Published var showingDotnetProject: Bool = false
    @Published var showingAITrainer: Bool = false
    @Published var showingPythonEnv: Bool = false
    @Published var showingRuntimeManager: Bool = false
    @Published var showingCodeAnalysis: Bool = false
    @Published var showingGitSettings: Bool = false
    @Published var showingAuthView: Bool = false

    @Published var showingCollaborationView: Bool = false
    @Published var showingUserProfile: Bool = false
    @Published var showingContainerView: Bool = false
    @Published var showingPreviewView: Bool = false
    @Published var showingEmbeddedTools: Bool = false
    @Published var showingKeyboardShortcuts: Bool = false

    
    // Build Configuration
    @Published var buildConfiguration: String = "Debug"  // Debug or Release
    @Published var selectedScheme: String = ""
    @Published var buildTarget: String = ""

    // AI Settings
    @Published var aiProvider: String = "gemini"
    @Published var aiModel: String = "gemini-2.5-flash"
    @Published var mixMode: Bool = false  // Use multiple AI providers
    @Published var autoFormatOnSave: Bool = false
    @Published var apiKeys: [String: String] = [:]
    
    @Published var simulatorManager = SimulatorManager.shared
    @Published var runtimeManager = RuntimeManager.shared
    @Published var terminalService = TerminalService()
    
    // LSP Integration
    @Published var lspManager = LSPManager.shared
    @Published var lspCompletions: [CompletionItem] = []
    @Published var lspHoverText: String?
    @Published var showingCompletions: Bool = false
    @Published var showingHover: Bool = false
    @Published var selectedCompletionIndex: Int = 0
    @Published var autocompleteRect: CGRect = .zero
    
    // DerivedData Cache Control
    @Published var derivedDataInfo: DerivedDataInfo?
    @Published var isCheckingCache: Bool = false
    
    // User Cache Settings (stored in UserDefaults)
    @Published var derivedDataQuotaLimitGB: Double = 10.0
    @Published var enableDerivedDataAutoPurge: Bool = false
    @Published var enableDerivedDataAlert: Bool = true
    
    // AI Chat & Agent
    @Published var aiChatVisible: Bool = false
    @Published var aiChatMessages: [ChatMessage] = []
    @Published var agentMode: Bool = true
    @Published var agentAutoApproveTools: Bool = false
    @Published var agentCustomInstructions: String = ""
    @Published var agentMaxIterations: Int = 0 // 0 = Unlimited (∞)
    @Published var pendingActions: [AgentAction] = []
    @Published var projectContext: String = ""  // Loaded from project.md
    
    // GitHub CI/CD Settings (Persistent)
    @Published var githubOwner: String = ""
    @Published var githubRepo: String = ""
    @Published var githubToken: String = ""
    @Published var agentSessionId: String? = nil
    
    // Remote Sync State
    @Published var activeRemoteSync: RemoteConnectionConfig? = nil
    @Published var remoteSyncEnabled: Bool = false
    
    // Remote Workspace State
    @Published var remoteWorkspaceManager = RemoteWorkspaceManager.shared
    var isRemoteProject: Bool {
        remoteWorkspaceManager.currentWorkspace != nil
    }
    
    @Published var agentStatus: String = "Idle"
    
    struct AIConfig {
        let provider: String
        let model: String
        let apiKey: String
    }
    
    var aiConfig: AIConfig {
        AIConfig(
            provider: aiProvider,
            model: aiModel,
            apiKey: apiKeys[aiProvider] ?? ""
        )
    }

    @Published var alertMessage: String?
    @Published var isLoading: Bool = false

    // MARK: - Services

    private let backend = BackendService.shared
    private var cancellables = Set<AnyCancellable>()
    private var workspaceLoadGeneration = UUID()
    private var rootScanGeneration = UUID()
    private var activeFileLoadGeneration = UUID()
    private var loadingDirectoryPaths = Set<String>()
    private var loadedDirectoryPaths = Set<String>()

    nonisolated private static let maximumDirectoryEntries = 2_000
    nonisolated private static let maximumEditableFileBytes = 2 * 1_024 * 1_024
    nonisolated private static let maximumLargeFilePreviewBytes = 1 * 1_024 * 1_024
    nonisolated private static let syntaxHighlightByteLimit = 512 * 1_024
    nonisolated private static let lspContentByteLimit = 512 * 1_024

    // MARK: - Initialization

    init() {
        AppState.shared = self
        // Let SwiftUI commit the first window before restoring settings and a
        // previous workspace. This keeps cold-launch first paint responsive.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setupSubscriptions()
            self.loadSettings()
        }
    }

    private func setupSubscriptions() {
        // Zero-config: when the user connects a MicroCode Cloud GPU
        // session, switch the active compute target automatically so
        // cell runs route through the cloud Jupyter kernel without
        // forcing the user to pick from a dropdown.
        CloudGPUService.shared.$activeSession
            .receive(on: RunLoop.main)
            .sink { [weak self] session in
                guard let self = self else { return }
                if session != nil && self.currentComputeTarget != .customHPC {
                    self.currentComputeTarget = .customHPC
                }
            }
            .store(in: &cancellables)

        // Monitor current file changes
        $currentFileIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] index in
                guard let self = self else { return }
                guard index >= 0, index < self.openFiles.count else {
                    self.currentFile = nil
                    return
                }
                self.currentFile = self.openFiles[index]
            }
            .store(in: &cancellables)
            
        // Theme & Presentation Mode Auto-Scaling
        $appTheme
            .sink { [weak self] theme in
                guard let self = self else { return }
                ThemeManager.shared.setActiveTheme(theme.rawValue)
                NotificationCenter.default.post(name: NSNotification.Name("MicroCodeThemeChanged"), object: theme)
                if theme == .wwdc || theme == .keynote || theme == .wwdcLight || theme == .keynoteLight {
                    self.fontSize = 24
                    self.fontFamily = "SF Mono"
                }
            }
            .store(in: &cancellables)
        
        // AI Code Export Handlers
        // NOTE: Code is passed via aiExportedCode property for views to consume
        NotificationCenter.default.publisher(for: Notification.Name("OpenInPlayground"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let code = notification.userInfo?["code"] as? String ?? ""
                let language = notification.userInfo?["language"] as? String ?? "python"
                self.aiExportedCode = code
                self.selectedLanguage = language.isEmpty ? "python" : language.lowercased()
                // Defer mode switch to next run loop to avoid re-entrant SwiftUI updates
                DispatchQueue.main.async {
                    self.editorMode = .playground
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: Notification.Name("OpenInCellMode"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let code = notification.userInfo?["code"] as? String ?? ""
                let language = notification.userInfo?["language"] as? String ?? "python"
                self.aiExportedCode = code
                self.selectedLanguage = language.isEmpty ? "python" : language.lowercased()
                // Defer mode switch to next run loop to avoid re-entrant SwiftUI updates
                DispatchQueue.main.async {
                    self.editorMode = .notebook
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: Notification.Name("OpenFileInEditor"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let url = notification.userInfo?["url"] as? URL else { return }
                Task { @MainActor in
                    await self.loadFile(url: url)
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: Notification.Name("MicroCodeAgentTerminalCommand"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let info = notification.userInfo,
                      let cmd = info["command"] as? String else { return }
                let output = (info["output"] as? String) ?? ""
                let cwd = (info["cwd"] as? String) ?? ""
                let cwdName = URL(fileURLWithPath: cwd).lastPathComponent
                let phase = (info["phase"] as? String) ?? "completed"
                if phase == "started" {
                    self.consoleOutput += "\n🤖 [Agent Terminal: \(cwdName.isEmpty ? cwd : cwdName)]\n$ \(cmd)\n"
                } else {
                    self.consoleOutput += "\(output)\n[Agent command finished]\n"
                }
            }
            .store(in: &cancellables)
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        fontSize = CGFloat(defaults.double(forKey: "fontSize")) == 0 ? 16 : CGFloat(defaults.double(forKey: "fontSize"))
        fontFamily = defaults.string(forKey: "fontFamily") ?? "SF Mono"
        
        agentFontName = defaults.string(forKey: "agentFontName") ?? "SF Pro"
        agentFontSize = CGFloat(defaults.double(forKey: "agentFontSize")) == 0 ? 16.0 : CGFloat(defaults.double(forKey: "agentFontSize"))
        
        playgroundFontName = defaults.string(forKey: "playgroundFontName") ?? "SF Mono"
        playgroundFontSize = CGFloat(defaults.double(forKey: "playgroundFontSize")) == 0 ? 16.0 : CGFloat(defaults.double(forKey: "playgroundFontSize"))
        playgroundFontWeight = defaults.object(forKey: "playgroundFontWeight") == nil ? 2 : defaults.integer(forKey: "playgroundFontWeight")
        
        cellFontName = defaults.string(forKey: "cellFontName") ?? "SF Mono"
        cellFontSize = CGFloat(defaults.double(forKey: "cellFontSize")) == 0 ? 16.0 : CGFloat(defaults.double(forKey: "cellFontSize"))
        cellFontWeight = defaults.object(forKey: "cellFontWeight") == nil ? 2 : defaults.integer(forKey: "cellFontWeight")
        // One-time migration: older Settings UI displayed a hard-coded ON
        // checkbox even though line numbers were disabled internally. Do not
        // treat that stale preference as a real user choice.
        let lineNumberMigrationKey = "lineNumbersOverlayPreferenceInitialized"
        if defaults.bool(forKey: lineNumberMigrationKey) {
            showLineNumbers = defaults.bool(forKey: "showLineNumbers")
        } else {
            showLineNumbers = false
            defaults.set(false, forKey: "showLineNumbers")
            defaults.set(true, forKey: lineNumberMigrationKey)
        }
        let opaqueDefaultMigrationKey = "opaqueDarkThemeDefaultMigrationV1"
        let savedTheme = defaults.string(forKey: "appTheme").flatMap(AppTheme.init(rawValue:))
        if !defaults.bool(forKey: opaqueDefaultMigrationKey), savedTheme == .transparent {
            // Transparent used to be the implicit default. Migrate that legacy
            // default once so existing installs receive the new opaque Dark UI.
            appTheme = .dark
            defaults.set(AppTheme.dark.rawValue, forKey: "appTheme")
            defaults.set(true, forKey: opaqueDefaultMigrationKey)
        } else {
            appTheme = savedTheme ?? .dark
            defaults.set(true, forKey: opaqueDefaultMigrationKey)
        }
        
        // Auto-detect and migrate credentials from existing local developer setups across macOS
        autoDetectAndMigrateCredentials(defaults: defaults)

        // Load API Keys
        let providers = ["gemini", "openai", "anthropic", "glm", "deepseek", "qwen", "grok"]
        for provider in providers {
            if let key = defaults.string(forKey: "\(provider)_api_key"), !key.isEmpty {
                apiKeys[provider] = key
            }
        }
        if let legacyKey = defaults.string(forKey: "apiKey"), !legacyKey.isEmpty {
            if apiKeys["openai"] == nil || apiKeys["openai"]?.isEmpty == true {
                apiKeys["openai"] = legacyKey
            }
        }

        // Intelligently select active provider and model based on working credentials
        let hasGemini = !(apiKeys["gemini"]?.isEmpty ?? true)
        let hasDeepSeek = !(apiKeys["deepseek"]?.isEmpty ?? true)
        let hasOpenAI = !(apiKeys["openai"]?.isEmpty ?? true)
        let hasAnthropic = !(apiKeys["anthropic"]?.isEmpty ?? true)

        let savedProvider = defaults.string(forKey: "aiProvider") ?? defaults.string(forKey: "provider")?.lowercased()
        let savedModel = defaults.string(forKey: "aiModel") ?? defaults.string(forKey: "model")

        if let savedProvider = savedProvider, !(apiKeys[savedProvider]?.isEmpty ?? true) {
            aiProvider = savedProvider
            aiModel = savedModel ?? "gemini-2.5-flash"
        } else if hasGemini {
            aiProvider = "gemini"
            aiModel = (savedModel?.contains("gemini") == true) ? savedModel! : "gemini-2.5-flash"
            defaults.set("gemini", forKey: "aiProvider")
            defaults.set(aiModel, forKey: "aiModel")
        } else if hasDeepSeek {
            aiProvider = "deepseek"
            aiModel = (savedModel?.contains("deepseek") == true) ? savedModel! : "deepseek-v4-flash"
            defaults.set("deepseek", forKey: "aiProvider")
            defaults.set(aiModel, forKey: "aiModel")
        } else if hasOpenAI {
            aiProvider = "openai"
            aiModel = (savedModel?.contains("gpt") == true || savedModel?.contains("o1") == true || savedModel?.contains("o3") == true) ? savedModel! : "gpt-6-astra"
            defaults.set("openai", forKey: "aiProvider")
            defaults.set(aiModel, forKey: "aiModel")
        } else if hasAnthropic {
            aiProvider = "anthropic"
            aiModel = "claude-3-7-sonnet"
            defaults.set("anthropic", forKey: "aiProvider")
            defaults.set(aiModel, forKey: "aiModel")
        } else {
            aiProvider = savedProvider ?? "gemini"
            aiModel = savedModel ?? "gemini-2.5-flash"
        }

        let normalizedAI = AIModelCatalog.shared.normalizedSelection(provider: aiProvider, model: aiModel)
        aiProvider = normalizedAI.provider
        aiModel = normalizedAI.model
        defaults.set(aiProvider, forKey: "aiProvider")
        defaults.set(aiModel, forKey: "aiModel")

        // Set default aiKeyMode only when not previously configured
        let savedKeyMode = defaults.string(forKey: "aiKeyMode")
        if savedKeyMode == nil {
            if SubscriptionAuthManager.shared.hasAnyConnected {
                defaults.set("subscription", forKey: "aiKeyMode")
            } else if hasGemini || hasDeepSeek || hasOpenAI || hasAnthropic {
                defaults.set("direct", forKey: "aiKeyMode")
            } else {
                defaults.set("cloud", forKey: "aiKeyMode")
            }
        }

        // MicroRent AI Proxy setup
        let microToken = defaults.string(forKey: "microRentToken") ?? ""
        if !microToken.isEmpty {
            setenv("MICRORENT_TOKEN", microToken, 1)
            setenv("USE_MICRORENT_PROXY", "1", 1)
        } else {
            unsetenv("MICRORENT_TOKEN")
            setenv("USE_MICRORENT_PROXY", "0", 1)
        }

        // Load GitHub Settings
        githubOwner = defaults.string(forKey: "githubOwner") ?? ""
        githubRepo = defaults.string(forKey: "githubRepo") ?? ""
        githubToken = defaults.string(forKey: "githubToken") ?? ""

        // Use object check to properly default booleans
        sidebarVisible = defaults.object(forKey: "sidebarVisible") == nil ? true : defaults.bool(forKey: "sidebarVisible")
        consoleVisible = defaults.object(forKey: "consoleVisible") == nil ? true : defaults.bool(forKey: "consoleVisible")
        agenticContextVisible = defaults.object(forKey: "agenticContextVisible") == nil ? true : defaults.bool(forKey: "agenticContextVisible")
        
        derivedDataQuotaLimitGB = defaults.object(forKey: "derivedDataQuotaLimitGB") == nil ? 10.0 : defaults.double(forKey: "derivedDataQuotaLimitGB")
        enableDerivedDataAutoPurge = defaults.bool(forKey: "enableDerivedDataAutoPurge")
        enableDerivedDataAlert = defaults.object(forKey: "enableDerivedDataAlert") == nil ? true : defaults.bool(forKey: "enableDerivedDataAlert")
        
        // Agent Settings
        agentMode = defaults.object(forKey: "agentMode") == nil ? true : defaults.bool(forKey: "agentMode")
        agentAutoApproveTools = defaults.bool(forKey: "agentAutoApproveTools")
        agentCustomInstructions = defaults.string(forKey: "agentCustomInstructions") ?? ""
        let savedAgentMaxIterations = defaults.object(forKey: "agentMaxIterations") == nil
            ? 0
            : defaults.integer(forKey: "agentMaxIterations")
        // Versions before 2.0.1 persisted `3` as a hidden default despite
        // presenting Unlimited as the default in Settings. Migrate that legacy
        // value so existing users are not silently cut off mid-task.
        agentMaxIterations = (1...4).contains(savedAgentMaxIterations) ? 0 : savedAgentMaxIterations
        if agentMaxIterations != savedAgentMaxIterations {
            defaults.set(agentMaxIterations, forKey: "agentMaxIterations")
        }
        
        // Restore last opened workspace folder
        if let lastPath = defaults.string(forKey: "lastWorkspacePath"),
           !lastPath.isEmpty,
           FileManager.default.fileExists(atPath: lastPath) {
            let url = URL(fileURLWithPath: lastPath)
            // External workspaces can be expensive to enumerate. Restore only
            // after the editor shell has become interactive.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                Task { @MainActor in await self.openWorkspace(url: url) }
            }
        }
        
        // Start the backend server automatically
        Task {
            await AIModelCatalog.shared.refreshLiveProviderModels()
            let refreshedAI = AIModelCatalog.shared.normalizedSelection(provider: aiProvider, model: aiModel)
            if refreshedAI.provider != aiProvider || refreshedAI.model != aiModel {
                aiProvider = refreshedAI.provider
                aiModel = refreshedAI.model
                saveSettings()
            }
            do {
                print("🚀 Starting backend server...")
                try await BackendService.shared.startBackend()
                ArdiumLSPService.shared.start() // Start Ardium LSP
                print("✅ Backend server started successfully on port 3000")
                checkDerivedDataSize() // Initial check
            } catch {
                print("⚠️ Failed to start backend server: \(error.localizedDescription)")
                print("   Some features (.NET, ML Training) will not be available.")
                // Continue even if backend fails - some features will work without it
            }
        }
    }

    private func autoDetectAndMigrateCredentials(defaults: UserDefaults) {
        let providers = ["gemini", "openai", "anthropic", "glm", "deepseek", "qwen", "grok"]
        
        // 1. Scan candidate preference suites and plists for existing developer credentials
        let candidateSuites = [
            "com.dotmini.codetunner",
            "com.dotmini.microcode",
            "com.arsenal.codetunner",
            "com.spuaiclub.microcode-oss",
            "com.spuaiclub.codetunner"
        ]
        var discoveredKeys: [String: String] = [:]
        
        for suite in candidateSuites {
            if let suiteDefaults = UserDefaults(suiteName: suite) {
                for p in providers {
                    if let k = suiteDefaults.string(forKey: "\(p)_api_key"), !k.isEmpty, discoveredKeys[p] == nil {
                        discoveredKeys[p] = k
                    }
                    if let k = suiteDefaults.string(forKey: "api_key_\(p)"), !k.isEmpty, discoveredKeys[p] == nil {
                        discoveredKeys[p] = k
                    }
                }
                if let lic = suiteDefaults.string(forKey: "dotminiLicenseKey"), !lic.isEmpty, defaults.string(forKey: "dotminiLicenseKey")?.isEmpty ?? true {
                    defaults.set(lic, forKey: "dotminiLicenseKey")
                }
                if let mail = suiteDefaults.string(forKey: "dotminiUserEmail"), !mail.isEmpty, defaults.string(forKey: "dotminiUserEmail")?.isEmpty ?? true {
                    defaults.set(mail, forKey: "dotminiUserEmail")
                }
                if let rent = suiteDefaults.string(forKey: "microRentToken"), !rent.isEmpty, defaults.string(forKey: "microRentToken")?.isEmpty ?? true {
                    defaults.set(rent, forKey: "microRentToken")
                }
            }
            
            // Directly read plist file on disk in case suite wasn't registered in sandbox
            let plistPath = ("~/Library/Preferences/\(suite).plist" as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: plistPath),
               let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
               let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] {
                for p in providers {
                    if let k = (plist["\(p)_api_key"] ?? plist["api_key_\(p)"]) as? String, !k.isEmpty, discoveredKeys[p] == nil {
                        discoveredKeys[p] = k
                    }
                    if p == "gemini", let k = (plist["api_key_Gemini"] ?? plist["gemini_api_key"]) as? String, !k.isEmpty, discoveredKeys[p] == nil {
                        discoveredKeys[p] = k
                    }
                    if p == "openai", let k = (plist["api_key_ChatGPT"] ?? plist["openai_api_key"]) as? String, !k.isEmpty, discoveredKeys[p] == nil {
                        discoveredKeys[p] = k
                    }
                }
                if let lic = plist["dotminiLicenseKey"] as? String, !lic.isEmpty, defaults.string(forKey: "dotminiLicenseKey")?.isEmpty ?? true {
                    defaults.set(lic, forKey: "dotminiLicenseKey")
                }
                if let mail = plist["dotminiUserEmail"] as? String, !mail.isEmpty, defaults.string(forKey: "dotminiUserEmail")?.isEmpty ?? true {
                    defaults.set(mail, forKey: "dotminiUserEmail")
                }
                if let rent = plist["microRentToken"] as? String, !rent.isEmpty, defaults.string(forKey: "microRentToken")?.isEmpty ?? true {
                    defaults.set(rent, forKey: "microRentToken")
                }
            }
        }
        
        // 2. Check process environment variables
        let env = ProcessInfo.processInfo.environment
        for p in providers {
            let envKey = "\(p.uppercased())_API_KEY"
            if let val = env[envKey], !val.isEmpty, discoveredKeys[p] == nil {
                discoveredKeys[p] = val
            }
        }
        
        // 3. Populate defaults with discovered keys if current defaults lacks them
        for (prov, key) in discoveredKeys {
            let current = defaults.string(forKey: "\(prov)_api_key")
            if current == nil || current?.isEmpty == true {
                defaults.set(key, forKey: "\(prov)_api_key")
            }
        }
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(Double(fontSize), forKey: "fontSize")
        defaults.set(fontFamily, forKey: "fontFamily")
        defaults.set(agentFontName, forKey: "agentFontName")
        defaults.set(Double(agentFontSize), forKey: "agentFontSize")
        defaults.set(playgroundFontName, forKey: "playgroundFontName")
        defaults.set(Double(playgroundFontSize), forKey: "playgroundFontSize")
        defaults.set(playgroundFontWeight, forKey: "playgroundFontWeight")
        defaults.set(cellFontName, forKey: "cellFontName")
        defaults.set(Double(cellFontSize), forKey: "cellFontSize")
        defaults.set(cellFontWeight, forKey: "cellFontWeight")
        defaults.set(appTheme.rawValue, forKey: "appTheme")
        defaults.set(showLineNumbers, forKey: "showLineNumbers")
        defaults.set(aiProvider, forKey: "aiProvider")
        defaults.set(aiModel, forKey: "aiModel")
        defaults.set(agentMode, forKey: "agentMode")
        defaults.set(agentAutoApproveTools, forKey: "agentAutoApproveTools")
        defaults.set(agentCustomInstructions, forKey: "agentCustomInstructions")
        defaults.set(agentMaxIterations, forKey: "agentMaxIterations")
        
        // Save API Keys
        for (provider, key) in apiKeys {
            defaults.set(key, forKey: "\(provider)_api_key")
        }
        defaults.set(sidebarVisible, forKey: "sidebarVisible")
        defaults.set(consoleVisible, forKey: "consoleVisible")
        defaults.set(agenticContextVisible, forKey: "agenticContextVisible")
        defaults.set(derivedDataQuotaLimitGB, forKey: "derivedDataQuotaLimitGB")
        defaults.set(enableDerivedDataAutoPurge, forKey: "enableDerivedDataAutoPurge")
        defaults.set(enableDerivedDataAlert, forKey: "enableDerivedDataAlert")
        
        // Save GitHub Settings
        defaults.set(githubOwner, forKey: "githubOwner")
        defaults.set(githubRepo, forKey: "githubRepo")
        defaults.set(githubToken, forKey: "githubToken")
    }

    // MARK: - File Operations

    func createNewFile() {
        showingNewFileDialog = true
    }
    
    func createNewFileWithLanguage(name: String, language: String) {
        let ext = extensionForLanguage(language)
        var filename = name.isEmpty ? "Untitled.\(ext)" : (name.hasSuffix(".\(ext)") ? name : "\(name).\(ext)")
        
        let content = templateForLanguage(language)
        var filePath = ""
        var isUnsaved = true
        
        // AUTO-SAVE: If workspace is open, create the file on disk immediately
        if let workspace = workspaceFolder {
            let fm = FileManager.default
            var targetURL = workspace.appendingPathComponent(filename)
            
            // Collision handling: check if exists
            if fm.fileExists(atPath: targetURL.path) {
                let basename = (filename as NSString).deletingPathExtension
                var counter = 1
                while fm.fileExists(atPath: workspace.appendingPathComponent("\(basename) \(counter).\(ext)").path) {
                    counter += 1
                }
                filename = "\(basename) \(counter).\(ext)"
                targetURL = workspace.appendingPathComponent(filename)
            }

            do {
                try content.write(to: targetURL, atomically: true, encoding: .utf8)
                filePath = targetURL.path
                isUnsaved = false
                
                // Refresh file tree to show the new file
                Task {
                    await refreshFileTree()
                }
            } catch {
                print("Failed to auto-save new file: \(error)")
            }
        }
        
        let newFile = CodeFile(
            id: UUID(),
            name: filename,
            path: filePath,
            content: content,
            language: language,
            isUnsaved: isUnsaved
        )
        openFiles.append(newFile)
        currentFileIndex = openFiles.count - 1
        currentFile = newFile
        
        showingNewFileDialog = false
    }
    
    func createFolder(at path: String, name: String) async {
        let url = URL(fileURLWithPath: path).appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            // Refresh parent?? Or just refresh tree?
            // Since we have lazy load, we might need to refresh specific node.
            // But refreshing whole tree is safer for now (recursive refresh is gone).
            await refreshFileTree() // This only refreshes ROOT. 
            // If deeper, we need to refresh that node.
            // Find parent node ID? 
            if let parent = findNode(byPath: path, in: fileTree) {
                await loadChildren(for: parent.id)
            } else {
                 await refreshFileTree()
            }
        } catch {
            alertMessage = "Failed to create folder: \(error.localizedDescription)"
        }
    }
    
    private func findNode(byPath path: String, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.path == path { return node }
            if let found = findNode(byPath: path, in: node.children) {
                return found
            }
        }
        return nil
    }
    
    private func extensionForLanguage(_ language: String) -> String {
        switch language.lowercased() {
        case "swift": return "swift"
        case "python": return "py"
        case "javascript": return "js"
        case "typescript": return "ts"
        case "rust": return "rs"
        case "go": return "go"
        case "java": return "java"
        case "c": return "c"
        case "cpp", "c++": return "cpp"
        case "objective-c", "objc": return "m"
        case "objective-cpp", "objcpp": return "mm"
        case "php": return "php"
        case "svelte": return "svelte"
        case "html": return "html"
        case "css": return "css"
        case "less": return "less"
        case "sass": return "sass"
        case "scss": return "scss"
        case "kotlin": return "kt"
        case "scala": return "scala"
        case "ruby": return "rb"
        case "json": return "json"
        case "markdown": return "md"
        default: return "txt"
        }
    }
    
    private func templateForLanguage(_ language: String) -> String {
        switch language.lowercased() {
        case "swift":
            return "import Foundation\n\n// MARK: - Main\n\nfunc main() {\n    print(\"Hello, World!\")\n}\n\nmain()\n"
        case "python":
            return "#!/usr/bin/env python3\n\"\"\"Module description.\"\"\"\n\n\ndef main():\n    \"\"\"Main entry point.\"\"\"\n    print(\"Hello, World!\")\n\n\nif __name__ == \"__main__\":\n    main()\n"
        case "javascript":
            return "// @ts-check\n\"use strict\";\n\n/**\n * Main function\n */\nfunction main() {\n    console.log(\"Hello, World!\");\n}\n\nmain();\n"
        case "rust":
            return "//! Module documentation\n\nfn main() {\n    println!(\"Hello, World!\");\n}\n"
        case "go":
            return "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(\"Hello, World!\")\n}\n"
        case "c":
            return "#include <stdio.h>\n\nint main() {\n    printf(\"Hello, World!\\n\");\n    return 0;\n}\n"
        case "cpp", "c++":
            return "#include <iostream>\n\nint main() {\n    std::cout << \"Hello, World!\" << std::endl;\n    return 0;\n}\n"
        case "objective-c", "objc":
            return "#import <Foundation/Foundation.h>\n#include <stdio.h>\n\nint main(int argc, const char * argv[]) {\n    @autoreleasepool {\n        printf(\"Hello, World!\\n\");\n    }\n    return 0;\n}\n"
        case "objective-cpp", "objcpp":
            return "#import <Foundation/Foundation.h>\n#include <iostream>\n#include <stdio.h>\n\nint main(int argc, const char * argv[]) {\n    @autoreleasepool {\n        printf(\"Hello from Obj-C++!\\n\");\n    }\n    return 0;\n}\n"
        case "php":
            return "<?php\n\necho \"Hello, World!\\n\";\n"
        case "html":
            return "<!DOCTYPE html>\n<html>\n<head>\n    <title>Hello World</title>\n</head>\n<body>\n    <h1>Hello, World!</h1>\n</body>\n</html>\n"
        case "css":
            return "body {\n    margin: 0;\n    padding: 0;\n    font-family: sans-serif;\n}\n"
        case "svelte":
            return "<script>\n  let name = 'world';\n</script>\n\n<h1>Hello {name}!</h1>\n"
        default:
            return ""
        }
    }

    func newFile() {
        let untitledFile = CodeFile(
            id: UUID(),
            name: "Untitled.swift",
            path: "",
            content: "//\n//  Untitled.swift\n//\n\nimport SwiftUI\n\nstruct UntitledView: View {\n    var body: some View {\n        Text(\"Hello from MicroCode!\")\n            .padding()\n    }\n}\n",
            language: "swift",
            isUnsaved: true
        )
        openFiles.append(untitledFile)
        currentFileIndex = openFiles.count - 1
        editorMode = .code
    }

    static func recordRecentWorkspace(url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        var paths = UserDefaults.standard.stringArray(forKey: "microcode_recent_workspaces") ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        if paths.count > 20 { paths = Array(paths.prefix(20)) }
        UserDefaults.standard.set(paths, forKey: "microcode_recent_workspaces")
    }

    static func recordRecentFile(url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        var paths = UserDefaults.standard.stringArray(forKey: "microcode_recent_files") ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        if paths.count > 25 { paths = Array(paths.prefix(25)) }
        UserDefaults.standard.set(paths, forKey: "microcode_recent_files")
    }

    static func getRecentWorkspaces() -> [URL] {
        var paths = UserDefaults.standard.stringArray(forKey: "microcode_recent_workspaces") ?? []
        if let last = UserDefaults.standard.string(forKey: "lastWorkspacePath"), !last.isEmpty, !paths.contains(last) {
            paths.insert(last, at: 0)
        }
        
        // Also merge any directory URLs from system recent documents
        for docURL in NSDocumentController.shared.recentDocumentURLs {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: docURL.path, isDirectory: &isDir), isDir.boolValue {
                if !paths.contains(docURL.path) {
                    paths.append(docURL.path)
                }
            }
        }
        
        // Discover current active/development project if list is small or empty
        let discoveryCandidates = [
            FileManager.default.currentDirectoryPath
        ]
        for candidate in discoveryCandidates {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                if !paths.contains(candidate) && !candidate.contains("/.build") && candidate != "/" {
                    paths.append(candidate)
                }
            }
        }
        
        let validURLs = paths.compactMap { path -> URL? in
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: path)
            }
            return nil
        }
        
        // Update back to UserDefaults
        let validPaths = validURLs.map { $0.path }
        UserDefaults.standard.set(validPaths, forKey: "microcode_recent_workspaces")
        return validURLs
    }

    static func getRecentFiles() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: "microcode_recent_files") ?? []
        return paths.compactMap { path in
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
                return URL(fileURLWithPath: path)
            }
            return nil
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.text, .sourceCode, .data]
        panel.title = "Open File"
        
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self = self, response == .OK, let url = panel.url else { return }
                Self.recordRecentFile(url: url)
                Task { @MainActor in
                    await self.loadFile(url: url)
                }
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                Self.recordRecentFile(url: url)
                Task { @MainActor in
                    await self.loadFile(url: url)
                }
            }
        }
    }

    @MainActor
    func openInPreviewDock(url: URL) {
        PreviewDockService.shared.openFile(url: url, makeActive: true)
        DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
    }

    @MainActor
    func openFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = "Open Folder"
        panel.message = "Select a project folder to open"
        panel.prompt = "Open"
        
        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self.loadFolderOptimized(url: url)
            }
        }
    }
    
    /// Public async method to open a workspace from path / URL
    func openWorkspace(url: URL) async {
        await loadFolderOptimized(url: url)
    }
    
    /// Optimized folder loading with lazy background services
    private func loadFolderOptimized(url: URL) async {
        // Invalidate every in-flight folder/file result from the previous
        // workspace before publishing the new root. This prevents a slow scan
        // from an old folder replacing the new folder's UI later.
        let loadGeneration = UUID()
        workspaceLoadGeneration = loadGeneration
        rootScanGeneration = UUID()
        activeFileLoadGeneration = UUID()
        loadingDirectoryPaths.removeAll(keepingCapacity: true)
        loadedDirectoryPaths.removeAll(keepingCapacity: true)
        fileTreeLimitWarning = nil
        fileTree = []
        fileTreeRevision &+= 1

        fileMonitorSource?.cancel()
        fileMonitorSource = nil
        fileRefreshTimer?.invalidate()
        fileRefreshTimer = nil

        // SECURITY SCOPED ACCESS (Critical for Sandboxed App)
        let isSecured = url.startAccessingSecurityScopedResource()
        print("🔐 Security Scoped Access for \(url.path): \(isSecured)")
        
        // Step 1: Immediate UI update (no CPU cost)
        self.workspaceFolder = url
        UserDefaults.standard.set(url.path, forKey: "lastWorkspacePath")
        Self.recordRecentWorkspace(url: url)
        AgentService.shared.setWorkspace(url.path)
        
        // Initialize MicroCode AI Core
        self.microCodeService = MicroCodeService(workspacePath: url.path)
        
        // Auto-start MCP Server
        Task { @MainActor in
            MCPServer.shared.start(workspace: url.path)
        }
        
        // Sync AI Provider Auth keys to AppState
        Task { @MainActor in
            AIProviderAuthService.shared.syncToAppState(self)
        }
        
        // Step 2: Load file tree (main operation, already optimized)
        await self.refreshFileTree()

        guard workspaceLoadGeneration == loadGeneration,
              workspaceFolder?.standardizedFileURL == url.standardizedFileURL else { return }
        
        // Step 3: Lazy-load background services with delays to prevent CPU spike
        
        // Project Type Detection (background, low priority)
        Task.detached(priority: .utility) {
            let type = ProjectManager.shared.detectProjectType(at: url)
            await MainActor.run {
                guard self.workspaceLoadGeneration == loadGeneration else { return }
                self.currentProjectType = type
            }
        }
        
        // File Watcher (start after 1 second)
        Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            await MainActor.run {
                guard self.workspaceLoadGeneration == loadGeneration else { return }
                self.startFileWatcher()
            }
        }
        
        // Git Status (lazy load after 3 seconds)
        Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 second delay
            await MainActor.run {
                guard self.workspaceLoadGeneration == loadGeneration else { return }
                self.gitRefresh()
            }
        }
        
        // LSP Workspace (set root for language servers)
        lspManager.setWorkspace(url)
        
        // Terminal (lazy, only set working dir without restart)
        Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
            await MainActor.run {
                guard self.workspaceLoadGeneration == loadGeneration else { return }
                // Only change directory if terminal is already running
                if self.terminalService.isRunning {
                    self.terminalService.sendCommand("cd '\(url.path)'")
                }
            }
        }
    }
    
    func openProjectFolder(url: URL) {
        Task { @MainActor in
            // Use the same optimized loading pattern
            await self.loadFolderOptimized(url: url)
            
            // Auto-Switch to Editor/Files
            self.editorMode = .code
            self.sidebarVisible = true
        }
    }
    
    func renameFile(at oldPath: String, to newName: String) async {
        let oldURL = URL(fileURLWithPath: oldPath)
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)
        let newPath = newURL.path
        
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            
            // Sync internal state: Update open files
            await MainActor.run {
                for i in 0..<openFiles.count {
                    let file = openFiles[i]
                    if file.path == oldPath {
                        // Exact file match
                        openFiles[i].path = newPath
                        openFiles[i].name = newName
                        openFiles[i].language = detectLanguage(from: newURL)
                    } else if file.path.hasPrefix(oldPath + "/") {
                        // File inside a renamed directory
                        let relativeSubPath = String(file.path.dropFirst(oldPath.count))
                        let updatedSubPath = newPath + relativeSubPath
                        openFiles[i].path = updatedSubPath
                        // Name stays same unless it was the root folder itself being renamed (handled by hasPrefix)
                    }
                }
                
                // Update current file reference if it was changed
                if let current = currentFile {
                    if let updated = openFiles.first(where: { $0.id == current.id }) {
                        currentFile = updated
                    }
                }
            }
            
            await refreshFileTree()
        } catch {
            print("❌ Rename Error: \(error)")
        }
    }
    
    /// Auto-detect GitHub Owner/Repo from .git config
    func detectGitRemote(for folder: URL) {
        // Run git remote get-url origin
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["remote", "get-url", "origin"]
        process.currentDirectoryURL = folder
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                parseGitRemote(output)
            }
        } catch {
            print("Failed to detect git remote: \(error)")
        }
    }
    
    private func parseGitRemote(_ url: String) {
        // Handle HTTPS: https://github.com/owner/repo.git
        // Handle SSH: git@github.com:owner/repo.git
        
        var cleanUrl = url
        if cleanUrl.hasSuffix(".git") {
            cleanUrl = String(cleanUrl.dropLast(4))
        }
        
        let components = cleanUrl.split(separator: "/")
        if components.count >= 2 {
            guard let lastComponent = components.last else { return }
            let repoName = String(lastComponent)
            var ownerName = String(components[components.count - 2])
            
            // Handle SSH colon separation (git@github.com:owner)
            if ownerName.contains(":") {
                guard let lastPart = ownerName.split(separator: ":").last else { return }
                ownerName = String(lastPart)
            }
            
            print("🔍 Detected Git Remote: \(ownerName)/\(repoName)")
            
            // Update State (Main Actor)
            DispatchQueue.main.async {
                if self.githubOwner.isEmpty { self.githubOwner = ownerName }
                if self.githubRepo.isEmpty { self.githubRepo = repoName }
                self.saveSettings()
            }
        }
    }
    
    /// Public method for views to persist GitHub/CI settings
    func saveGitHubSettings() {
        saveSettings()
    }

    func loadFile(url: URL) async {
        let normalizedURL = url.standardizedFileURL

        // Selecting an already-open tab must be instant and must not start a
        // second disk read, lexer, or LSP request.
        if let existingIndex = openFiles.firstIndex(where: { $0.path == normalizedURL.path }) {
            selectFile(at: existingIndex)
            return
        }

        let loadGeneration = UUID()
        activeFileLoadGeneration = loadGeneration
        isLoading = true
        defer {
            if activeFileLoadGeneration == loadGeneration { isLoading = false }
        }

        let ext = normalizedURL.pathExtension.lowercased()
        let previewExtensions = Set(["png", "jpg", "jpeg", "pdf", "gif", "bmp", "tiff", "webp"])
        let scienceExtensions = Set(["pdb", "ent", "cif", "mmcif", "fasta", "fa", "faa", "fna", "a3m", "json", "csv", "tsv", "png", "jpg", "jpeg", "gif", "webp", "svg", "html", "htm", "pdf", "tex", "bib", "md"])
        let result: SafeFileLoadResult

        if previewExtensions.contains(ext) {
            result = SafeFileLoadResult(
                content: "[Binary File]",
                originalByteSize: 0,
                isReadOnly: true,
                isTruncated: false,
                shouldUsePlainTextMode: true,
                errorMessage: nil
            )
        } else {
            result = await Task.detached(priority: .userInitiated) {
                Self.readFileSafely(at: normalizedURL)
            }.value
        }

        guard activeFileLoadGeneration == loadGeneration else { return }
        if let errorMessage = result.errorMessage {
            alertMessage = errorMessage
            return
        }

        let language = detectLanguage(from: normalizedURL)
        let file = CodeFile(
            id: UUID(),
            name: normalizedURL.lastPathComponent,
            path: normalizedURL.path,
            content: result.content,
            language: language,
            isUnsaved: false,
            isReadOnly: result.isReadOnly,
            usesPlainTextMode: result.shouldUsePlainTextMode,
            originalByteSize: result.originalByteSize,
            isTruncated: result.isTruncated
        )

        openFiles.append(file)
        selectFile(at: openFiles.count - 1)
        // Keep Science Mode active when opening a scientific artifact from its
        // navigator. Other file types retain the editor's established behavior.
        if !(editorMode == .science && scienceExtensions.contains(ext)) {
            editorMode = .code
        }
        sidebarVisible = true

        // Large/minified files deliberately skip LSP. Sending megabytes to a
        // language server can duplicate memory several times and stall both
        // processes even though the editor itself remains responsive.
        if !result.isReadOnly,
           !result.shouldUsePlainTextMode,
           result.originalByteSize <= Self.lspContentByteLimit {
            let content = result.content
            let fileUri = normalizedURL.absoluteString
            Task.detached(priority: .utility) {
                let lspTask = Task.detached(priority: .utility) {
                    await LSPManager.shared.documentOpened(uri: fileUri, language: language, content: content)
                }
                let timeoutTask = Task.detached(priority: .utility) {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    lspTask.cancel()
                }
                await lspTask.value
                timeoutTask.cancel()
            }
        }
    }

    public func reloadFileFromDisk(path: String) {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        if let index = openFiles.firstIndex(where: { $0.path == normalizedPath }) {
            let url = URL(fileURLWithPath: normalizedPath)
            let result = Self.readFileSafely(at: url)
            guard result.errorMessage == nil else { return }
            openFiles[index].content = result.content
            openFiles[index].isUnsaved = false
            openFiles[index].originalByteSize = result.originalByteSize
            openFiles[index].isTruncated = result.isTruncated
            if currentFileIndex == index || currentFile?.path == normalizedPath {
                currentFile = openFiles[index]
            }
        }
    }

    nonisolated private static func readFileSafely(at url: URL) -> SafeFileLoadResult {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile != false else {
                return SafeFileLoadResult(
                    content: "", originalByteSize: 0, isReadOnly: true,
                    isTruncated: false, shouldUsePlainTextMode: true,
                    errorMessage: "Cannot open a non-regular file."
                )
            }

            let reportedSize = max(0, values.fileSize ?? 0)
            let isReportedLarge = reportedSize > maximumEditableFileBytes
            let readLimit = isReportedLarge ? maximumLargeFilePreviewBytes : maximumEditableFileBytes + 1
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: readLimit) ?? Data()

            let isLarge = isReportedLarge || data.count > maximumEditableFileBytes
            let visibleData = isLarge ? data.prefix(maximumLargeFilePreviewBytes) : data[...]
            let hasNullByte = visibleData.prefix(8_192).contains(0)

            if hasNullByte {
                return SafeFileLoadResult(
                    content: "[Binary file — preview unavailable]",
                    originalByteSize: reportedSize,
                    isReadOnly: true,
                    isTruncated: false,
                    shouldUsePlainTextMode: true,
                    errorMessage: nil
                )
            }

            let visible = Data(visibleData)
            let decoded = String(data: visible, encoding: .utf8)
                ?? String(data: visible, encoding: .isoLatin1)
                ?? "[Unable to decode file — unsupported encoding]"
            let content = isLarge
                ? decoded + "\n\n[Large-file preview truncated. The original file is read-only in MicroCode.]"
                : decoded
            let longUnbrokenLine = content.count > 50_000 && !content.prefix(50_000).contains("\n")
            let plainMode = isLarge || visible.count > syntaxHighlightByteLimit || longUnbrokenLine

            return SafeFileLoadResult(
                content: content,
                originalByteSize: max(reportedSize, data.count),
                isReadOnly: isLarge,
                isTruncated: isLarge,
                shouldUsePlainTextMode: plainMode,
                errorMessage: nil
            )
        } catch {
            return SafeFileLoadResult(
                content: "", originalByteSize: 0, isReadOnly: true,
                isTruncated: false, shouldUsePlainTextMode: true,
                errorMessage: "Failed to open file: \(error.localizedDescription)"
            )
        }
    }

    func buildProject() {
        guard let folder = workspaceFolder else {
            consoleOutput = "Error: No project folder open.\n"
            consoleVisible = true
            return
        }
        
        consoleVisible = true
        consoleOutput = "🚀 Starting Build...\n"
        isExecuting = true
        
        // Use ProjectManager for universal project detection
        let projectManager = ProjectManager.shared
        let projectType = projectManager.detectProjectType(at: folder)
        
        if projectType == .unknown {
            consoleOutput += "⚠️ No recognized build system found.\n"
            consoleOutput += "Supported: Package.swift, package.json, build.gradle, Cargo.toml,\n"
            consoleOutput += "           *.xcodeproj, *.csproj, pom.xml, Makefile, CMakeLists.txt,\n"
            consoleOutput += "           pubspec.yaml, go.mod, requirements.txt, Gemfile\n"
            isExecuting = false
            return
        }
        
        consoleOutput += "📦 Detected: \(projectType.rawValue) project\n"
        consoleOutput += "⚙️ Configuration: \(projectManager.buildConfiguration.name)\n\n"
        
        // Execute build using ProjectManager
        projectManager.execute(action: .build, projectPath: folder) { [weak self] success, output in
            DispatchQueue.main.async {
                self?.consoleOutput = output
                self?.isExecuting = false
                if success {
                    self?.checkDerivedDataSize()
                }
            }
        }
    }
    
    func runProject() {
        guard let folder = workspaceFolder else {
            consoleOutput = "Error: No project folder open.\n"
            consoleVisible = true
            return
        }
        
        consoleVisible = true
        consoleOutput = "▶️ Running Project...\n"
        isExecuting = true
        
        let projectManager = ProjectManager.shared
        let projectType = projectManager.detectProjectType(at: folder)
        
        if projectType == .unknown {
            consoleOutput += "⚠️ No recognized project type.\n"
            isExecuting = false
            return
        }
        
        consoleOutput += "📦 Running: \(projectType.rawValue) project\n\n"
        
        projectManager.execute(action: .run, projectPath: folder) { [weak self] success, output in
            DispatchQueue.main.async {
                self?.consoleOutput = output
                self?.isExecuting = false
            }
        }
    }
    
    func cleanProject() {
        guard let folder = workspaceFolder else { return }
        
        consoleVisible = true
        consoleOutput = "🧹 Cleaning Project...\n"
        
        let projectManager = ProjectManager.shared
        projectManager.execute(action: .clean, projectPath: folder) { [weak self] success, output in
            DispatchQueue.main.async {
                self?.consoleOutput = output
            }
        }
    }
    
    func testProject() {
        guard let folder = workspaceFolder else { return }
        
        consoleVisible = true
        consoleOutput = "🧪 Running Tests...\n"
        isExecuting = true
        
        let projectManager = ProjectManager.shared
        projectManager.execute(action: .test, projectPath: folder) { [weak self] success, output in
            DispatchQueue.main.async {
                self?.consoleOutput = output
                self?.isExecuting = false
            }
        }
    }

    func saveCurrentFile() {
        guard let file = currentFile else { return }

        // If file has no path (new file), prompt for save location
        if file.path.isEmpty {
            saveFileAs()
            return
        }

        Task {
            await saveFile(file)
        }
    }

    func saveFileAs() {
        guard let file = currentFile else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        
        // Set initial directory to workspace folder if available
        if let workspace = workspaceFolder {
            panel.directoryURL = workspace
        }
        
        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            var updatedFile = file
            updatedFile.path = url.path
            updatedFile.name = url.lastPathComponent
            
            // Update file in the list
            if let index = self.openFiles.firstIndex(where: { $0.id == file.id }) {
                self.openFiles[index] = updatedFile
                if self.currentFileIndex == index {
                    self.currentFile = updatedFile
                }
            }
            
            Task { @MainActor in
                await self.saveFile(updatedFile)
            }
        }
    }

    private func saveFile(_ file: CodeFile) async {
        // Validate path before saving
        guard !file.path.isEmpty else {
            alertMessage = "Cannot save file: No file path specified. Use Save As instead."
            return
        }
        
        isLoading = true
        defer { isLoading = false }

        do {
            var fileContentToSave = file.content
            
            // Auto-format if enabled
            if autoFormatOnSave {
                // Determine language based on file extension if not set
                var language = file.language
                if language.isEmpty || language == "Text" {
                    let ext = (file.path as NSString).pathExtension
                    if !ext.isEmpty {
                        switch ext.lowercased() {
                        case "swift": language = "swift"
                        case "py": language = "python"
                        case "js": language = "javascript"
                        case "ts": language = "typescript"
                        case "json": language = "json"
                        case "ar": language = "ardium"
                        default: break
                        }
                    }
                }
                
                // Only format if we have a valid language
                if !language.isEmpty && language != "Text" {
                    fileContentToSave = try await BackendService.shared.formatCode(
                        code: fileContentToSave,
                        language: language
                    )
                }
            }

            // Use native Swift file writing for reliability
            let url = URL(fileURLWithPath: file.path)
            try fileContentToSave.write(to: url, atomically: true, encoding: .utf8)

            // Realtime Sync for Remote Projects (Full Workspace or Single File)
            if isRemoteProject {
                Task {
                    await remoteWorkspaceManager.syncFile(localURL: url)
                }
            } else {
                Task {
                    if remoteWorkspaceManager.isTempFile(url: url) {
                        await remoteWorkspaceManager.syncTempFile(localURL: url)
                    }
                }
            }

            if let index = openFiles.firstIndex(where: { $0.id == file.id }) {
                var updatedFile = file
                updatedFile.content = fileContentToSave // Update content in memory too
                updatedFile.isUnsaved = false
                openFiles[index] = updatedFile
                if currentFileIndex == index {
                    currentFile = updatedFile
                }
            }

            hasUnsavedChanges = openFiles.contains { $0.isUnsaved }
            
            // Remote sync if enabled
            if remoteSyncEnabled, let syncServer = activeRemoteSync {
                Task {
                    await syncFileToRemote(file, to: syncServer)
                }
            }
            
            // Remote workspace sync
            if isRemoteProject {
                let localURL = URL(fileURLWithPath: file.path)
                await remoteWorkspaceManager.syncFile(localURL: localURL)
            }
        } catch {
            alertMessage = "Failed to save file: \(error.localizedDescription)"
        }
    }
    
    private func syncFileToRemote(_ file: CodeFile, to server: RemoteConnectionConfig) async {
        guard let workspace = workspaceFolder else { return }
        
        let localURL = URL(fileURLWithPath: file.path)
        let relativePath = localURL.path.replacingOccurrences(of: workspace.path, with: "")
        let remotePath = relativePath.hasPrefix("/") ? relativePath : "/" + relativePath
        
        print("📡 Syncing to remote: \(remotePath) on \(server.name)")
        
        do {
            let data = file.content.data(using: .utf8) ?? Data()
            try await BackendService.shared.uploadRemoteFile(id: server.id.uuidString, path: remotePath, content: data)
            print("🚀 Successfully synced \(file.name) to remote")
        } catch {
            print("❌ Sync failed for \(file.name): \(error.localizedDescription)")
        }
    }

    func selectFile(at index: Int) {
        guard index >= 0 && index < openFiles.count else { return }
        currentFileIndex = index
        currentFile = openFiles[index]
    }

    func selectFile(_ file: CodeFile) {
        if let index = openFiles.firstIndex(where: { $0.id == file.id }) {
            selectFile(at: index)
        }
    }

    func closeFile(_ file: CodeFile) {
        if let index = openFiles.firstIndex(where: { $0.id == file.id }) {
            closeFile(at: index)
        }
    }

    func closeFile(at index: Int) {
        guard index >= 0 && index < openFiles.count else { return }

        let file = openFiles[index]
        if file.isUnsaved {
            // Show confirmation dialog
            let alert = NSAlert()
            alert.messageText = "Save changes?"
            alert.informativeText = "The file \"\(file.name)\" has unsaved changes."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()

            switch response {
            case .alertFirstButtonReturn:
                Task {
                    await saveFile(file)
                    openFiles.remove(at: index)
                    updateCurrentFileIndex(after: index)
                }
            case .alertSecondButtonReturn:
                openFiles.remove(at: index)
                updateCurrentFileIndex(after: index)
            default:
                return
            }
        } else {
            openFiles.remove(at: index)
            updateCurrentFileIndex(after: index)
        }
    }

    private func updateCurrentFileIndex(after removedIndex: Int) {
        if openFiles.isEmpty {
            currentFileIndex = 0
            currentFile = nil
        } else {
            if currentFileIndex >= openFiles.count {
                currentFileIndex = max(0, openFiles.count - 1)
            }
            currentFile = openFiles[currentFileIndex]
        }
    }

    func selectNextTab() {
        guard openFiles.count > 1 else { return }
        let nextIndex = (currentFileIndex + 1) % openFiles.count
        selectFile(openFiles[nextIndex])
    }

    func selectPreviousTab() {
        guard openFiles.count > 1 else { return }
        let prevIndex = (currentFileIndex - 1 + openFiles.count) % openFiles.count
        selectFile(openFiles[prevIndex])
    }

    func closeOtherTabs() {
        guard let current = currentFile else { return }
        openFiles = [current]
        currentFileIndex = 0
    }

    func updateFileContent(_ content: String, for fileId: UUID) {
        if let index = openFiles.firstIndex(where: { $0.id == fileId }) {
            openFiles[index].content = content
            openFiles[index].isUnsaved = true
            hasUnsavedChanges = true
            
            // Sync with currentFile if it's the one being edited
            if currentFile?.id == fileId {
                currentFile?.content = content
                currentFile?.isUnsaved = true
            }
        }
    }
    
    func updateFileLanguage(_ language: String, for fileId: UUID) {
        if let index = openFiles.firstIndex(where: { $0.id == fileId }) {
            openFiles[index].language = language
            // objectWillChange.send() // Might be needed if published property doesn't trigger deep change
        }
    }

    // MARK: - Omni AI & Direct Execution Bridge

    func openSnippetFromOmniAI(code: String, language: String, shouldRun: Bool = true) {
        let cleanLang = language.isEmpty ? "python" : language.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let ext: String
        switch cleanLang {
        case "swift": ext = "swift"
        case "python", "py": ext = "py"
        case "javascript", "js": ext = "js"
        case "typescript", "ts": ext = "ts"
        case "go", "golang": ext = "go"
        case "rust", "rs": ext = "rs"
        case "cpp", "c++": ext = "cpp"
        case "c": ext = "c"
        case "java": ext = "java"
        case "kotlin", "kt": ext = "kt"
        case "sql": ext = "sql"
        case "html": ext = "html"
        case "css": ext = "css"
        default: ext = "txt"
        }
        
        let fileName = "OmniAI_Snippet.\(ext)"
        let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent(fileName).path
        
        let newFile = CodeFile(
            id: UUID(),
            name: fileName,
            path: tempPath,
            content: code,
            language: cleanLang,
            isUnsaved: true,
            isReadOnly: false,
            usesPlainTextMode: false,
            originalByteSize: code.utf8.count,
            isTruncated: false
        )
        
        if let existingIdx = openFiles.firstIndex(where: { $0.name == fileName }) {
            openFiles[existingIdx] = newFile
            currentFileIndex = existingIdx
        } else {
            openFiles.append(newFile)
            currentFileIndex = openFiles.count - 1
        }
        currentFile = newFile
        
        // Bring editor and console to focus
        consoleVisible = true
        
        if shouldRun {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.runCode()
            }
        }
    }

    func syncGoogleOrDotminiAccount(email: String, token: String = "", displayName: String = "") {
        AuthService.shared.syncWithWebSession(email: email, token: token, displayName: displayName)
        ReportLogManager.shared.log("Omni AI Sync: Account authenticated as \(email)", type: .info)
    }

    // MARK: - Code Execution

    func runCode() {
        guard let file = currentFile else { return }

        isExecuting = true
        consoleOutput = "Running \(file.name)...\n"
        consoleVisible = true

        Task {
            // Auto-save before running to ensure consistency
            if file.isUnsaved {
                await saveFile(file)
            }
            
            // Try backend first, fallback to local execution
            do {
                let result = try await backend.executeCode(code: file.content, language: file.language)
                await handleExecutionResult(file: file, result: result)
            } catch {
                // Backend unavailable - use local execution
                consoleOutput += "📍 Running locally...\n"
                await runCodeLocally(file: file)
            }
        }
    }
    
    /// Handle execution result from backend
    private func handleExecutionResult(file: CodeFile, result: ExecutionOutput) async {
        var stdout = result.stdout
        var stderr = result.stderr
        
        // Clean NSLog for Obj-C
        if file.language == "objective-c" || file.language == "objective-cpp" {
            stderr = cleanNSLog(stderr)
        }
        
        consoleOutput += stdout
        if !stderr.isEmpty {
            consoleOutput += "\n\(stderr)"
        }
        consoleOutput += "\n\nExited with code \(result.exitCode) in \(String(format: "%.2f", result.executionTime))s\n"
        isExecuting = false
    }
    
    /// Run code locally using Process
    private func runCodeLocally(file: CodeFile) async {
        let startTime = Date()
        
        // Get file path for compiled languages
        let tempDir = FileManager.default.temporaryDirectory
        let sourceFile = tempDir.appendingPathComponent(file.name)
        
        // Write source file
        do {
            try file.content.write(to: sourceFile, atomically: true, encoding: .utf8)
        } catch {
            consoleOutput += "Error: Failed to write temp file: \(error.localizedDescription)\n"
            isExecuting = false
            return
        }
        
        let result = await executeLocalCommand(language: file.language, sourcePath: sourceFile.path, tempDir: tempDir)
        
        let elapsed = Date().timeIntervalSince(startTime)
        consoleOutput += result.stdout
        if !result.stderr.isEmpty {
            consoleOutput += "\n\(result.stderr)"
        }
        consoleOutput += "\n\nExited with code \(result.exitCode) in \(String(format: "%.2f", elapsed))s\n"
        isExecuting = false
        
        // Cleanup
        try? FileManager.default.removeItem(at: sourceFile)
    }
    
    /// Execute script content directly (Public helper for Playground)
    @MainActor
    public func executeScript(code: String, language: String) async -> (stdout: String, stderr: String, exitCode: Int32) {
        let tempDir = FileManager.default.temporaryDirectory
        let ext = fileExtension(for: language)
        
        // Fast hashing for intelligent execution cache
        let data = Data(code.utf8)
        let hash = SHA256.hash(data: data)
        let codeHash = hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16)
        
        let sourceFile: URL
        if language.lowercased() == "java" {
            // Java requires public class name to match file name (conventionally Main.java)
            let javaDir = tempDir.appendingPathComponent("java_\(codeHash)", isDirectory: true)
            try? FileManager.default.createDirectory(at: javaDir, withIntermediateDirectories: true, attributes: nil)
            sourceFile = javaDir.appendingPathComponent("Main.java")
        } else {
            let filename = "script_\(codeHash).\(ext)"
            sourceFile = tempDir.appendingPathComponent(filename)
        }
        
        do {
            if !FileManager.default.fileExists(atPath: sourceFile.path) {
                try code.write(to: sourceFile, atomically: true, encoding: .utf8)
            }
            let result = await executeLocalCommand(language: language, sourcePath: sourceFile.path, tempDir: tempDir, codeHash: String(codeHash))
            // Do not remove source file to allow caching for same code runs
            return result
        } catch {
            return ("", "Error: Failed to write temp file: \(error.localizedDescription)", 1)
        }
    }

    func fileExtension(for language: String) -> String {
        switch language.lowercased() {
        case "python": return "py"
        case "javascript": return "js"
        case "typescript": return "ts"
        case "swift": return "swift"
        case "java": return "java"
        case "kotlin": return "kt"
        case "rust": return "rs"
        case "go": return "go"
        case "c": return "c"
        case "cpp", "c++": return "cpp"
        case "ruby": return "rb"
        case "lua": return "lua"
        case "perl": return "pl"
        case "php": return "php"
        case "shell", "bash": return "sh"
        case "r": return "r"
        case "julia": return "jl"
        case "zig": return "zig"
        case "nim": return "nim"
        case "d": return "d"
        case "fortran": return "f90"
        case "pascal": return "pas"
        case "elixir": return "ex"
        case "clojure": return "clj"
        case "groovy": return "groovy"
        case "haxe": return "hx"
        case "scala": return "scala"
        case "fsharp": return "fs"
        case "vala": return "vala"
        case "assembly": return "s"
        case "solidity": return "sol"
        case "powershell": return "ps1"
        case "csharp": return "cs"
        case "objective-c", "objc": return "m"
        case "objective-c++", "objective-cpp", "objcpp", "objc++": return "mm"
        case "ocaml": return "ml"
        case "haskell": return "hs"
        case "ardium", "ar": return "ar"
        default: return "txt"
        }
    }

    /// Execute command for specific language
    func executeLocalCommand(language: String, sourcePath: String, tempDir: URL, codeHash: String = "") async -> (stdout: String, stderr: String, exitCode: Int32) {
        let lang = language.lowercased()
        var args: [String] = []
        var executable = "/usr/bin/env"
        
        let hashSuffix = codeHash.isEmpty ? UUID().uuidString : codeHash
        
        switch lang {
        case "python", "py", "python3":
            args = ["python3", sourcePath]
            
        case "javascript", "js":
            args = ["node", sourcePath]
            
        case "typescript", "ts":
            let jsPath = tempDir.appendingPathComponent("output_\(hashSuffix).js").path
            if !FileManager.default.fileExists(atPath: jsPath) {
                let compileResult = await runProcess(executable: "/usr/bin/env", arguments: ["npx", "tsc", "--outFile", jsPath, sourcePath])
                if compileResult.exitCode != 0 { return compileResult }
            }
            args = ["node", jsPath]
            
        case "swift":
            let outputPath = tempDir.appendingPathComponent("output_swift_\(hashSuffix)").path
            if !FileManager.default.fileExists(atPath: outputPath) {
                let compileResult = await runProcess(executable: "/usr/bin/env", arguments: ["swiftc", "-O", "-o", outputPath, sourcePath])
                if compileResult.exitCode != 0 { return await runProcess(executable: "/usr/bin/env", arguments: ["swift", sourcePath]) }
            }
            return await runProcess(executable: outputPath, arguments: [])
            
        case "java":
            let className = (sourcePath as NSString).lastPathComponent.replacingOccurrences(of: ".java", with: "")
            let classDir = tempDir.appendingPathComponent("class_\(hashSuffix)").path
            let classFilePath = (classDir as NSString).appendingPathComponent("\(className).class")
            
            if !FileManager.default.fileExists(atPath: classFilePath) {
                try? FileManager.default.createDirectory(atPath: classDir, withIntermediateDirectories: true, attributes: nil)
                let compileResult = await runProcess(executable: "/usr/bin/env", arguments: ["javac", "-d", classDir, sourcePath])
                if compileResult.exitCode != 0 { return compileResult }
            }
            return await runProcess(executable: "/usr/bin/env", arguments: ["java", "-cp", classDir, className])
            
        case "kotlin", "kt":
            let jarPath = tempDir.appendingPathComponent("output_\(hashSuffix).jar").path
            if !FileManager.default.fileExists(atPath: jarPath) {
                let compileResult = await runProcess(executable: "/usr/bin/env", arguments: ["kotlinc", sourcePath, "-include-runtime", "-d", jarPath])
                if compileResult.exitCode != 0 {
                    if compileResult.stderr.contains("not found") || compileResult.stderr.contains("No such file") {
                        return ("", "❌ Error: Kotlin compiler (kotlinc) not found in PATH.\nPlease install Kotlin via: brew install kotlin", 1)
                    }
                    return compileResult
                }
            }
            return await runProcess(executable: "/usr/bin/env", arguments: ["java", "-jar", jarPath])
            
        case "go", "golang":
            let outputPath = tempDir.appendingPathComponent("output_go_\(hashSuffix)").path
            if !FileManager.default.fileExists(atPath: outputPath) {
                let compileResult = await runProcess(executable: "/usr/bin/env", arguments: ["go", "build", "-o", outputPath, sourcePath])
                if compileResult.exitCode != 0 { return await runProcess(executable: "/usr/bin/env", arguments: ["go", "run", sourcePath]) }
            }
            return await runProcess(executable: outputPath, arguments: [])
            
        // Systems
        case "rust", "rs":
            let outputPath = tempDir.appendingPathComponent("output_rs_\(hashSuffix)").path
            if !FileManager.default.fileExists(atPath: outputPath) {
                let compileResult = await runProcess(executable: "/usr/bin/env", arguments: ["rustc", "-o", outputPath, sourcePath])
                if compileResult.exitCode != 0 { return compileResult }
            }
            return await runProcess(executable: outputPath, arguments: [])
            
        case "c":
            let outputPath = tempDir.appendingPathComponent("output_c_\(hashSuffix)").path
            if !FileManager.default.fileExists(atPath: outputPath) {
                let compileResult = await runProcess(executable: "/usr/bin/env", arguments: ["clang", "-o", outputPath, sourcePath])
                if compileResult.exitCode != 0 { return compileResult }
            }
            return await runProcess(executable: outputPath, arguments: [])
            
        case "cpp", "c++", "cxx", "cc":
            let outputPath = tempDir.appendingPathComponent("output_cpp_\(hashSuffix)").path
            if !FileManager.default.fileExists(atPath: outputPath) {
                let compileResult = await runProcess(executable: "/usr/bin/env", arguments: ["clang++", "-std=c++20", "-o", outputPath, sourcePath])
                if compileResult.exitCode != 0 { return compileResult }
            }
            return await runProcess(executable: outputPath, arguments: [])
            
        case "objective-c", "objc", "m":
            let outputPath = tempDir.appendingPathComponent("output_objc_\(hashSuffix)").path
            if !FileManager.default.fileExists(atPath: outputPath) {
                let compileResult = await runProcess(executable: "/usr/bin/env", arguments: ["clang", "-framework", "Foundation", "-o", outputPath, sourcePath])
                if compileResult.exitCode != 0 {
                    return (compileResult.stdout, cleanObjcOutput(compileResult.stderr), compileResult.exitCode)
                }
            }
            let runResult = await runProcess(executable: outputPath, arguments: [])
            return (cleanObjcOutput(runResult.stdout), cleanObjcOutput(runResult.stderr), runResult.exitCode)
            
        case "objective-c++", "objective-cpp", "objcpp", "objc++", "mm":
            let outputPath = tempDir.appendingPathComponent("output_objcpp_\(hashSuffix)").path
            if !FileManager.default.fileExists(atPath: outputPath) {
                let compileResult = await runProcess(executable: "/usr/bin/env", arguments: ["clang++", "-framework", "Foundation", "-o", outputPath, sourcePath])
                if compileResult.exitCode != 0 {
                    return (compileResult.stdout, cleanObjcOutput(compileResult.stderr), compileResult.exitCode)
                }
            }
            let runResult = await runProcess(executable: outputPath, arguments: [])
            return (cleanObjcOutput(runResult.stdout), cleanObjcOutput(runResult.stderr), runResult.exitCode)
            
        // .NET / C#
        case "csharp", "cs":
            // Try mono mcs first for single file
            let binPath = tempDir.appendingPathComponent("out_\(hashSuffix).exe").path
            if !FileManager.default.fileExists(atPath: binPath) {
                let compileResult = await runProcess(executable: "/usr/bin/env", arguments: ["mcs", sourcePath, "-out:" + binPath])
                if compileResult.exitCode != 0 { return compileResult }
            }
            return await runProcess(executable: "/usr/bin/env", arguments: ["mono", binPath])
            
        // Scripting
        case "ruby", "rb": args = ["ruby", sourcePath]
        case "lua": args = ["lua", sourcePath]
        case "perl", "pl": args = ["perl", sourcePath]
        case "php": args = ["php", sourcePath]
        case "shell", "bash", "sh": args = ["bash", sourcePath]
        case "powershell", "ps1": args = ["pwsh", sourcePath]
        
        // Data Science
        case "r":
            if let rPath = RuntimeManager.shared.selectedExecutable(for: .r) {
                // R itself and Rscript accept different argument forms. The
                // runtime manager tracks `R`, while a user may explicitly
                // select `Rscript` in Manage Environments.
                if URL(fileURLWithPath: rPath).lastPathComponent.lowercased().contains("rscript") {
                    return await runProcess(executable: rPath, arguments: [sourcePath])
                }
                return await runProcess(executable: rPath, arguments: ["--vanilla", "--slave", "-f", sourcePath])
            }
            args = ["Rscript", sourcePath]
        case "julia", "jl":
            if let juliaPath = RuntimeManager.shared.selectedExecutable(for: .julia) {
                return await runProcess(executable: juliaPath, arguments: [sourcePath])
            }
            args = ["julia", sourcePath]
        case "matlab": args = ["matlab", "-batch", "run('" + sourcePath + "')"]
            
        // Functional / Others
        case "ocaml", "ml": args = ["ocaml", sourcePath]
        case "haskell", "hs": args = ["runghc", sourcePath]
        case "dart": args = ["dart", "run", sourcePath]
        case "scala":
            let scalaResult = await runProcess(executable: "/usr/bin/env", arguments: ["scala", sourcePath])
            if scalaResult.exitCode != 0 && (scalaResult.stderr.contains("not found") || scalaResult.stderr.contains("No such file")) {
                return ("", "❌ Error: Scala runner not found in PATH.\nPlease install Scala via: brew install scala", 1)
            }
            return scalaResult
        case "groovy": args = ["groovy", sourcePath]
        case "elixir", "ex", "exs": args = ["elixir", sourcePath]
        case "clojure", "clj": args = ["clojure", "-M", sourcePath]
        
        // Systems (Modern)
        case "zig": args = ["zig", "run", sourcePath]
        case "nim": args = ["nim", "compile", "--run", sourcePath]
        case "d", "dlang": args = ["rdmd", sourcePath]
        case "v": args = ["v", "run", sourcePath]
        
        // Legacy / Low Level
        case "fortran", "f90", "f95":
            let outputPath = tempDir.appendingPathComponent("output_f90_\(hashSuffix)").path
            if !FileManager.default.fileExists(atPath: outputPath) {
                let compileResult = await runProcess(executable: "/usr/bin/env", arguments: ["gfortran", "-o", outputPath, sourcePath])
                if compileResult.exitCode != 0 { return compileResult }
            }
            return await runProcess(executable: outputPath, arguments: [])
            
        case "pascal", "pas":
            let binaryPath = tempDir.appendingPathComponent("output_pas_\(hashSuffix)").path
            if !FileManager.default.fileExists(atPath: binaryPath) {
                let compileResult = await runProcess(executable: "/usr/bin/env", arguments: ["fpc", "-o" + binaryPath, sourcePath])
                if compileResult.exitCode != 0 { return compileResult }
            }
            return await runProcess(executable: binaryPath, arguments: [])
            
        case "assembly", "asm", "s":
             let binPath = tempDir.appendingPathComponent("out_\(hashSuffix)").path
             if !FileManager.default.fileExists(atPath: binPath) {
                 let objPath = tempDir.appendingPathComponent("out_\(hashSuffix).o").path
                 let asResult = await runProcess(executable: "/usr/bin/env", arguments: ["as", "-o", objPath, sourcePath])
                 if asResult.exitCode != 0 { return asResult }
                 let sdkPath = await runProcess(executable: "/usr/bin/env", arguments: ["xcrun", "-sdk", "macosx", "--show-sdk-path"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                 let ldResult = await runProcess(executable: "/usr/bin/env", arguments: ["ld", "-o", binPath, objPath, "-lSystem", "-syslibroot", sdkPath, "-e", "_main", "-arch", "arm64"])
                 if ldResult.exitCode != 0 { return ldResult }
             }
             return await runProcess(executable: binPath, arguments: [])
             
        case "metal":
            let irPath = tempDir.appendingPathComponent("output.air").path
            let compileResult = await runProcess(executable: "/usr/bin/env", arguments: ["xcrun", "-sdk", "macosx", "metal", "-c", sourcePath, "-o", irPath])
            return (compileResult.stdout + "\n✅ Metal Compiled", compileResult.stderr, compileResult.exitCode)
            
        case "solidity", "sol":
            return await runProcess(executable: "/usr/bin/env", arguments: ["solc", sourcePath, "--bin"])
            
        case "sql", "sqlite":
             // Run against in-memory db by default
             args = ["sqlite3", ":memory:", ".read \(sourcePath)"]
             
        case "haxe", "hx": // New: Haxe
            // Haxe --interp requires a Main class. We assume the user wrote a class named 'Main'.
            args = ["haxe", "--main", "Main", "--interp"]
            
        case "ardium", "ar":
            if let bin = ArdiumRunner.findBinary() {
                return await runProcess(executable: bin, arguments: ["run", sourcePath])
            } else {
                return ("", "❌ Error: Ardium toolchain not found. Please install Ardium at /usr/local/ardium.", 1)
            }
            
        default:
            return ("", "Error: Language '\(language)' not supported yet.", 1)
        }
        
        if executable == "/usr/bin/env" && !args.isEmpty {
             return await runProcess(executable: "/usr/bin/env", arguments: args)
        }
        
        return await runProcess(executable: executable, arguments: args)
    }

    /// Clean Objective-C NSLog headers and temp paths from process output
    public func cleanObjcOutput(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        // Filter NSLog timestamp and process name prefix:
        // "2026-09-06 06:02:12.285 output_objc_1234567890[19949:1470682] Hello from Objective-C!" -> "Hello from Objective-C!"
        let nslogPattern = #"^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3}\s+[^\s\[]+\[\d+:\d+\]\s+"#
        var cleanedLines: [String] = []
        for line in raw.components(separatedBy: "\n") {
            if let regex = try? NSRegularExpression(pattern: nslogPattern, options: []) {
                let range = NSRange(location: 0, length: (line as NSString).length)
                let cleaned = regex.stringByReplacingMatches(in: line, options: [], range: range, withTemplate: "")
                cleanedLines.append(cleaned)
            } else {
                cleanedLines.append(line)
            }
        }
        var result = cleanedLines.joined(separator: "\n")
        // Strip long temp directory references like /var/folders/.../T/MicroCode_.../
        let tempDirPattern = #"/var/folders/[^\s:]+/([A-Za-z0-9_\-\.]+)"#
        if let regex = try? NSRegularExpression(pattern: tempDirPattern, options: []) {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        return result
    }
    
    /// Run a process and capture output with comprehensive PATH injection
    private func runProcess(executable: String, arguments: [String]) async -> (stdout: String, stderr: String, exitCode: Int32) {
        return await withCheckedContinuation { continuation in
            let process = Process()
            
            if executable == "/usr/bin/env" {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = arguments
            } else {
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
            }
            
            // Build rich PATH environment covering cargo, swiftly, homebrew, openjdk, dotnet, etc.
            var env = ProcessInfo.processInfo.environment
            let home = NSHomeDirectory()
            let additionalPaths = [
                "/opt/homebrew/bin",
                "/opt/homebrew/sbin",
                "/usr/local/bin",
                "\(home)/.cargo/bin",
                "\(home)/.swiftly/bin",
                "/opt/homebrew/opt/openjdk@21/bin",
                "/opt/homebrew/opt/openjdk@17/bin",
                "/opt/homebrew/opt/openjdk/bin",
                "/Library/Frameworks/Python.framework/Versions/3.11/bin",
                "/Library/Frameworks/Python.framework/Versions/Current/bin",
                "\(home)/Library/Android/sdk/cmdline-tools/latest/bin",
                "\(home)/Library/Android/sdk/platform-tools",
                "/Library/TeX/texbin",
                "\(home)/Library/TinyTeX/bin/universal-darwin"
            ]
            let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            let completePath = (additionalPaths + [existingPath]).joined(separator: ":")
            env["PATH"] = completePath
            if env["JAVA_HOME"] == nil {
                if FileManager.default.fileExists(atPath: "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home") {
                    env["JAVA_HOME"] = "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
                } else if FileManager.default.fileExists(atPath: "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home") {
                    env["JAVA_HOME"] = "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home"
                }
            }
            process.environment = env
            
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            process.terminationHandler = { process in
                // Read data safely
                let stdoutData = try? stdoutPipe.fileHandleForReading.readToEnd()
                let stderrData = try? stderrPipe.fileHandleForReading.readToEnd()
                
                let stdout = String(data: stdoutData ?? Data(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrData ?? Data(), encoding: .utf8) ?? ""
                
                continuation.resume(returning: (stdout, stderr, process.terminationStatus))
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(returning: ("", "Error: \(error.localizedDescription)\n", 1))
            }
        }
    }

    /// Strips NSLog metadata (timestamps, process IDs, etc) from stderr
    private func cleanNSLog(_ input: String) -> String {
        // Pattern: 2025-12-25 23:19:09.013 bin[6248:6488860] Hello, World!
        let pattern = #"^\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}\.\d{3}\s.*?\[\d+:\d+\]\s(.*)$"#
        
        var cleaned = ""
        let lines = input.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
                let stripped = regex.stringByReplacingMatches(in: line, options: [], range: nsRange, withTemplate: "$1")
                cleaned += stripped
            } else {
                cleaned += line
            }
            if index < lines.count - 1 {
                cleaned += "\n"
            }
        }
        
        return cleaned
    }

    func stopExecution() {
        isExecuting = false
        consoleOutput += "\n--- Execution stopped ---\n"
    }

    // MARK: - AI Chat

    func toggleAIChat() {
        aiChatVisible.toggle()
        if aiChatVisible && aiChatMessages.isEmpty {
            // Add welcome message
            aiChatMessages.append(ChatMessage(
                role: .system,
                content: "👋 Hi! I'm your AI coding assistant. I can help you:\n• Write and edit code\n• Explain code concepts\n• Create project architecture\n• Refactor and improve code\n\nToggle **Agent Mode** to let me directly suggest code changes!",
                timestamp: Date()
            ))
            loadProjectContext()
        }
    }

    func sendChatMessage(_ message: String) {
        guard !message.isEmpty else { return }
        
        // Add user message
        aiChatMessages.append(ChatMessage(
            role: .user,
            content: message,
            timestamp: Date()
        ))
        
        isLoading = true
        
        Task {
            if agentMode {
                // Agent Streaming Mode
                let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "cloud"
                let agentAPIKey: String?
                if keyMode == "cloud" {
                    // The local agent backend forwards model calls through the
                    // Dotmini proxy, so it needs the same cloud credential as
                    // AIClient (not the provider's direct API key).
                    agentAPIKey = UserDefaults.standard.string(forKey: "dotminiLicenseKey")
                        ?? UserDefaults.standard.string(forKey: "microRentToken")
                } else {
                    agentAPIKey = apiKeys[aiProvider]
                }

                let request = AgentChatRequest(
                    session_id: agentSessionId ?? "default-session",
                    message: message,
                    editor_context: ActiveEditorContext(
                        active_file: currentFile?.path,
                        active_content: currentFile?.content,
                        cursor_line: 0, // Should get from editor
                        selected_text: "",
                        open_files: openFiles.map { $0.path }
                    ),
                    provider: aiProvider,
                    model: aiModel,
                    api_key: agentAPIKey,
                    auto_execute: true
                )
                
                var assistantMessage = ChatMessage(
                    role: .assistant,
                    content: "",
                    timestamp: Date(),
                    isThinking: true
                )
                
                let msgID = assistantMessage.id
                aiChatMessages.append(assistantMessage)
                
                do {
                    for try await event in backend.agentEnhancedChatStream(request: request) {
                        DispatchQueue.main.async {
                            if let idx = self.aiChatMessages.firstIndex(where: { $0.id == msgID }) {
                                switch event {
                                case .token(let token):
                                    self.aiChatMessages[idx].content += token
                                    self.aiChatMessages[idx].isThinking = false
                                case .toolStart(let name, let id):
                                    let tc = AgentToolCall(id: id, name: name, arguments: "")
                                    self.aiChatMessages[idx].toolCalls.append(tc)
                                    self.aiChatMessages[idx].isThinking = false // Stop thinking when tool starts
                                case .toolEnd(let tcID, let success, let output, let error):
                                    let result = AgentToolResult(tool_call_id: tcID, success: success, output: output, error: error)
                                    self.aiChatMessages[idx].toolResults.append(result)
                                case .pendingChange(let change):
                                    let action = AgentAction(
                                        actionType: .editFile,
                                        description: "Apply changes to \(change.file_path)",
                                        filePath: change.file_path,
                                        oldCode: change.original_content,
                                        newCode: change.modified_content
                                    )
                                    self.pendingActions.append(action)
                                case .error(let err):
                                    self.aiChatMessages[idx].content += "\n❌ Error: \(err)"
                                case .done:
                                    self.aiChatMessages[idx].isThinking = false
                                }
                            }
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        if let idx = self.aiChatMessages.firstIndex(where: { $0.id == msgID }) {
                            self.aiChatMessages[idx].content += "\n❌ Connection Error: \(error.localizedDescription)"
                        }
                    }
                }
                isLoading = false
            } else {
                // Standard Non-Streaming Node
                do {
                    // Build context
                    var context = ""
                    if !projectContext.isEmpty {
                        context += "Project Context:\n\(projectContext)\n\n"
                    }
                    if let file = currentFile {
                        context += "Current File: \(file.name) (\(file.language))\n```\(file.language)\n\(file.content)\n```\n\n"
                    }
                    
                    let response = try await backend.explainCode(
                        code: context + "\n\nUser: " + message,
                        provider: aiProvider,
                        model: aiModel,
                        apiKey: apiKeys[aiProvider] ?? ""
                    )
                    
                    let assistantMessage = ChatMessage(
                        role: .assistant,
                        content: response,
                        timestamp: Date()
                    )
                    
                    aiChatMessages.append(assistantMessage)
                    isLoading = false
                } catch {
                    aiChatMessages.append(ChatMessage(
                        role: .assistant,
                        content: "❌ Error: \(error.localizedDescription)",
                        timestamp: Date()
                    ))
                    isLoading = false
                }
            }
        }
    }

    private func parseCodeBlocks(from text: String) -> [CodeBlock] {
        var blocks: [CodeBlock] = []
        let pattern = "```(\\w+)?(?::([^\\n]+))?\\n([\\s\\S]*?)```"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return blocks }
        let range = NSRange(text.startIndex..., in: text)
        
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match = match else { return }
            
            let langRange = Range(match.range(at: 1), in: text)
            let pathRange = Range(match.range(at: 2), in: text)
            let codeRange = Range(match.range(at: 3), in: text)
            
            let language = langRange.map { String(text[$0]) } ?? "text"
            let filePath = pathRange.map { String(text[$0]) }
            let code = codeRange.map { String(text[$0]) } ?? ""
            
            blocks.append(CodeBlock(language: language, code: code, filePath: filePath))
        }
        
        return blocks
    }

    func approveAction(_ action: AgentAction) {
        if let index = pendingActions.firstIndex(where: { $0.id == action.id }) {
            pendingActions[index].isApproved = true
            
            // Apply the action
            switch action.actionType {
            case .editFile:
                if let fileIndex = openFiles.firstIndex(where: { $0.path == action.filePath || $0.name == URL(fileURLWithPath: action.filePath).lastPathComponent }) {
                    var file = openFiles[fileIndex]
                    file.content = action.newCode
                    file.isUnsaved = true
                    openFiles[fileIndex] = file
                    if currentFileIndex == fileIndex {
                        currentFile = file
                    }
                } else if let current = currentFile {
                    updateFileContent(action.newCode, for: current.id)
                }
            case .createFile:
                createNewFileWithLanguage(name: URL(fileURLWithPath: action.filePath).lastPathComponent, language: detectLanguage(from: URL(fileURLWithPath: action.filePath)))
                if var file = currentFile {
                    file.content = action.newCode
                    updateFileContent(action.newCode, for: file.id)
                }
            default:
                break
            }
            
            aiChatMessages.append(ChatMessage(
                role: .system,
                content: "✅ Applied changes to \(action.filePath)",
                timestamp: Date()
            ))
        }
    }

    func refreshArtifacts() {
        // No-op: Task dashboard removed
    }

    func rejectAction(_ action: AgentAction) {
        if let index = pendingActions.firstIndex(where: { $0.id == action.id }) {
            pendingActions[index].isRejected = true
            aiChatMessages.append(ChatMessage(
                role: .system,
                content: "❌ Rejected changes to \(action.filePath)",
                timestamp: Date()
            ))
        }
    }

    func loadProjectContext() {
        guard let folder = workspaceFolder else { return }
        let projectMdPath = folder.appendingPathComponent("project.md")
        
        if let content = try? String(contentsOf: projectMdPath, encoding: .utf8) {
            projectContext = content
        }
    }

    func saveProjectContext(_ context: String) {
        guard let folder = workspaceFolder else { return }
        let projectMdPath = folder.appendingPathComponent("project.md")
        
        do {
            try context.write(to: projectMdPath, atomically: true, encoding: .utf8)
            projectContext = context
            aiChatMessages.append(ChatMessage(
                role: .system,
                content: "📝 Updated project.md with project architecture",
                timestamp: Date()
            ))
        } catch {
            alertMessage = "Failed to save project.md: \(error.localizedDescription)"
        }
    }

    // MARK: - Code Operations

    func formatCode() {
        guard let file = currentFile else { return }

        Task {
            do {
                let formatted = try await backend.formatCode(code: file.content, language: file.language)
                updateFileContent(formatted, for: file.id)
            } catch {
                alertMessage = "Failed to format code: \(error.localizedDescription)"
            }
        }
    }

    func expandCode() {
        guard let file = currentFile else { return }
        
        isLoading = true
        Task {
            do {
                let expanded = try await backend.refactorCode(
                    code: file.content,
                    instructions: "Expand this code: add proper error handling, add documentation comments, add type annotations where missing, expand any abbreviated variable names to be more descriptive, and add any missing best practices. Keep the same functionality but make it production-ready.",
                    provider: aiProvider,
                    model: aiModel,
                    apiKey: apiKeys[aiProvider] ?? ""
                )
                updateFileContent(expanded, for: file.id)
                isLoading = false
            } catch {
                isLoading = false
                alertMessage = "Failed to expand code: \(error.localizedDescription)"
            }
        }
    }

    func showRefactorDialog() {
        showingRefactorDialog = true
    }

    func refactorCode(instructions: String) async {
        guard let file = currentFile else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let refactored = try await backend.refactorCode(
                code: file.content,
                instructions: instructions,
                provider: aiProvider,
                model: aiModel,
                apiKey: apiKeys[aiProvider] ?? ""
            )
            updateFileContent(refactored, for: file.id)
        } catch {
            alertMessage = "Failed to refactor code: \(error.localizedDescription)"
        }
    }

    func explainCode() {
        guard let file = currentFile else { return }

        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                let explanation = try await backend.explainCode(
                    code: file.content,
                    provider: aiProvider,
                    model: aiModel,
                    apiKey: apiKeys[aiProvider] ?? ""
                )
                consoleOutput = "--- Code Explanation ---\n\n\(explanation)\n"
                consoleVisible = true
            } catch {
                alertMessage = "Failed to explain code: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - LSP Operations
    
    /// Request completions at the current cursor position
    func requestCompletions(line: Int, character: Int, cursorRect: CGRect = .zero) async {
        guard let file = currentFile else { return }
        let uri = URL(fileURLWithPath: file.path).absoluteString
        
        let completions = await lspManager.getCompletions(
            uri: uri,
            language: file.language,
            line: line,
            character: character
        )
        
        self.lspCompletions = completions
        self.selectedCompletionIndex = 0
        self.autocompleteRect = cursorRect
        self.showingCompletions = !completions.isEmpty
    }
    
    /// Request hover info at a position
    func requestHover(line: Int, character: Int) async {
        guard let file = currentFile else { return }
        let uri = URL(fileURLWithPath: file.path).absoluteString
        
        if let hoverText = await lspManager.getHover(
            uri: uri,
            language: file.language,
            line: line,
            character: character
        ) {
            self.lspHoverText = hoverText
            self.showingHover = true
        } else {
            self.showingHover = false
        }
    }
    
    /// Go to definition of symbol at position
    func goToDefinition(line: Int, character: Int) async {
        guard let file = currentFile else { return }
        let uri = URL(fileURLWithPath: file.path).absoluteString
        
        let locations = await lspManager.getDefinition(
            uri: uri,
            language: file.language,
            line: line,
            character: character
        )
        
        if let first = locations.first {
            // Navigate to the definition
            if let defUrl = URL(string: first.uri) {
                await loadFile(url: defUrl)
                // TODO: Scroll to first.range.start.line
            }
        }
    }
    
    /// Notify LSP that document content changed
    func notifyDocumentChanged() async {
        guard let file = currentFile else { return }
        let uri = URL(fileURLWithPath: file.path).absoluteString
        
        await lspManager.documentChanged(uri: uri, language: file.language, content: file.content)
    }
    
    /// Dismiss completions popup
    func dismissCompletions() {
        showingCompletions = false
        lspCompletions = []
        selectedCompletionIndex = 0
    }
    
    func selectNextCompletion() {
        guard !lspCompletions.isEmpty else { return }
        selectedCompletionIndex = (selectedCompletionIndex + 1) % lspCompletions.count
    }
    
    func selectPreviousCompletion() {
        guard !lspCompletions.isEmpty else { return }
        selectedCompletionIndex = (selectedCompletionIndex - 1 + lspCompletions.count) % lspCompletions.count
    }
    
    var selectedCompletionItem: CompletionItem? {
        guard !lspCompletions.isEmpty && selectedCompletionIndex < lspCompletions.count else { return nil }
        return lspCompletions[selectedCompletionIndex]
    }
    
    /// Apply a completion item
    func applyCompletion(_ item: CompletionItem) {
        guard var file = currentFile else { return }
        
        // Insert the completion text at cursor
        let insertText = item.insertText ?? item.label
        file.content += insertText
        
        // Update file
        if let index = openFiles.firstIndex(where: { $0.id == file.id }) {
            openFiles[index] = file
            currentFile = file
        }
        
        dismissCompletions()
    }

    // MARK: - Git Operations

    func gitRefresh() {
        guard let folder = workspaceFolder else { return }

        Task {
            print("📂 [FreezeDebug] gitRefresh started for \(folder.path)")
            let start = Date()

            guard await checkGitRepository() else {
                clearGitRepositoryState()
                print("📂 [FreezeDebug] gitRefresh skipped non-repository in \(Date().timeIntervalSince(start))s")
                return
            }
            
            do {
                let status = try await backend.getGitStatus(repoPath: folder.path)
                self.gitRepositoryAvailable = true
                self.gitStatus = status

                let commits = try await backend.getGitLog(repoPath: folder.path, limit: 50)
                self.gitCommits = commits
                
                // Also load extended git info
                gitLoadBranches()
                gitLoadStashList()
                gitLoadRemoteURL()
                
                print("📂 [FreezeDebug] gitRefresh finished in \(Date().timeIntervalSince(start))s")
            } catch {
                // Repository might not be a git repo
                clearGitRepositoryState()
                print("📂 [FreezeDebug] gitRefresh failed/skipped in \(Date().timeIntervalSince(start))s")
            }
        }
    }

    /// Initializes only the currently opened workspace. This is an explicit
    /// user action; MicroCode never creates a repository implicitly.
    @discardableResult
    func gitInitializeRepository() async -> Bool {
        guard workspaceFolder != nil else {
            gitOperationMessage = "Open a folder before initializing Git."
            return false
        }
        if await checkGitRepository() {
            gitRepositoryAvailable = true
            gitOperationMessage = "This workspace is already a Git repository."
            return true
        }

        gitIsWorking = true
        defer { gitIsWorking = false }
        let result = await runGitExec(["init"])
        guard result.exitCode == 0 else {
            gitOperationMessage = "Could not initialize this repository."
            alertMessage = "Git initialization failed:\n\(result.output)"
            return false
        }
        gitRepositoryAvailable = true
        gitOperationMessage = "Git repository initialized. Review files, then make the first commit."
        gitRefresh()
        return true
    }

    func showCommitDialog() {
        showingCommitDialog = true
    }

    @discardableResult
    func commitChanges(message: String) async -> Bool {
        guard workspaceFolder != nil else { return false }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard await requireGitRepository(for: "commit") else { return false }
        gitIsWorking = true
        defer { gitIsWorking = false }
        let result = await runGitExec(["commit", "-m", trimmed])
        guard result.exitCode == 0 else {
            alertMessage = "Commit failed:\n\(result.output)"
            return false
        }
        gitOperationMessage = "Committed changes."
        gitRefresh()
        return true
    }

    /// Single-click workflow for users who explicitly choose "Stage all" in
    /// the commit sheet. `git add -A` includes deletions and nested files, but
    /// respects .gitignore and never force-adds ignored content.
    @discardableResult
    func gitCommitAllChanges(message: String, pushAfterCommit: Bool) async -> Bool {
        guard workspaceFolder != nil else { return false }
        guard await requireGitRepository(for: "stage and commit") else { return false }
        let stage = await runGitExec(["add", "-A"])
        guard stage.exitCode == 0 else {
            alertMessage = "Could not stage changes:\n\(stage.output)"
            return false
        }
        guard await commitChanges(message: message) else { return false }
        if pushAfterCommit {
            return await gitPushAndWait()
        }
        return true
    }

    func gitPush() {
        guard workspaceFolder != nil else { return }

        Task {
            guard await requireGitRepository(for: "push") else { return }
            gitIsWorking = true
            defer { gitIsWorking = false }
            var result = await runGitExec(["push"])
            // A new local branch often has no upstream. Make the first push a
            // one-click publish while still requiring an existing origin remote.
            if result.exitCode != 0,
               let branch = gitStatus?.branch,
               !branch.isEmpty,
               !(await runGit(["remote", "get-url", "origin"])).isEmpty {
                result = await runGitExec(["push", "--set-upstream", "origin", branch])
            }
            guard result.exitCode == 0 else {
                alertMessage = "Push failed:\n\(result.output)"
                return
            }
            gitOperationMessage = "Pushed to remote."
            gitRefresh()
        }
    }

    private func gitPushAndWait() async -> Bool {
        guard await requireGitRepository(for: "push") else { return false }
        gitIsWorking = true
        defer { gitIsWorking = false }
        var result = await runGitExec(["push"])
        if result.exitCode != 0,
           let branch = gitStatus?.branch,
           !branch.isEmpty,
           !(await runGit(["remote", "get-url", "origin"])).isEmpty {
            result = await runGitExec(["push", "--set-upstream", "origin", branch])
        }
        guard result.exitCode == 0 else {
            alertMessage = "Push failed:\n\(result.output)"
            return false
        }
        gitOperationMessage = "Committed and pushed changes."
        gitRefresh()
        return true
    }

    func gitPull() {
        guard workspaceFolder != nil else { return }

        Task {
            guard await requireGitRepository(for: "pull") else { return }
            gitIsWorking = true
            defer { gitIsWorking = false }
            // Fast-forward only keeps a one-click pull predictable: no implicit
            // merge commit and no overwrite if branches have diverged.
            let result = await runGitExec(["pull", "--ff-only"])
            guard result.exitCode == 0 else {
                alertMessage = "Pull needs review:\n\(result.output)"
                return
            }
            gitOperationMessage = "Pulled latest changes."
            gitRefresh()
            // Reload all open files after a successful fast-forward.
            for file in openFiles {
                if !file.path.isEmpty, FileManager.default.fileExists(atPath: file.path) {
                    let url = URL(fileURLWithPath: file.path)
                    if let content = try? String(contentsOf: url),
                       let index = openFiles.firstIndex(where: { $0.id == file.id }) {
                        openFiles[index].content = content
                    }
                }
            }
        }
    }

    // MARK: - Git Extended Operations

    /// Prevent Git's low-level "not a repository" error from reaching users.
    /// The Source Control panel will immediately render its Initialize action.
    private func requireGitRepository(for operation: String) async -> Bool {
        guard workspaceFolder != nil else {
            gitOperationMessage = "Open a folder before trying to \(operation)."
            return false
        }
        guard await checkGitRepository() else {
            clearGitRepositoryState()
            gitPanelVisible = true
            gitOperationMessage = "This folder is not a Git repository. Open Source Control and choose Initialize Repository."
            return false
        }
        gitRepositoryAvailable = true
        return true
    }

    private func checkGitRepository() async -> Bool {
        let result = await runGitExec(["rev-parse", "--is-inside-work-tree"])
        return result.exitCode == 0 && result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    private func clearGitRepositoryState() {
        gitRepositoryAvailable = false
        gitStatus = nil
        gitCommits = []
        gitBranches = []
        gitStashList = []
        gitRemoteURL = ""
        gitDiff = ""
        gitDiffFile = ""
    }
    
    /// Run a git command and return stdout
    private func runGit(_ args: [String]) async -> String {
        guard let folder = workspaceFolder else { return "" }
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = folder
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } catch {
                return ""
            }
        }.value
    }
    
    /// Run git command, return exit code
    private func runGitExec(_ args: [String]) async -> (output: String, exitCode: Int32) {
        guard let folder = workspaceFolder else { return ("", -1) }
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = folder
            process.standardOutput = outPipe
            process.standardError = errPipe
            do {
                try process.run()
                process.waitUntilExit()
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return (out + err, process.terminationStatus)
            } catch {
                return (error.localizedDescription, -1)
            }
        }.value
    }

    /// Ask the configured AI to describe the selected changes. This runs only
    /// after the user presses the button; no diff is sent automatically.
    func gitGenerateCommitMessage() async -> String? {
        guard workspaceFolder != nil else { return nil }
        gitIsGeneratingCommitMessage = true
        defer { gitIsGeneratingCommitMessage = false }
        let staged = await runGit(["diff", "--cached", "--no-ext-diff"])
        let working = staged.isEmpty ? await runGit(["diff", "--no-ext-diff"]) : staged
        let untracked = await runGit(["ls-files", "--others", "--exclude-standard"])
        let context = String((working + "\nUntracked files:\n" + untracked).prefix(48_000))
        guard !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "There are no changes to describe."
            return nil
        }
        do {
            let reply = try await backend.completeCode(
                code: context,
                context: "You generate one precise Conventional Commit message. Return exactly one line, using a type such as feat:, fix:, refactor:, docs:, test:, or chore:. Do not include markdown, quotes, explanation, credentials, or source code.",
                provider: aiProvider,
                model: aiModel,
                apiKey: apiKeys[aiProvider] ?? ""
            )
            let message = reply
                .split(separator: "\n")
                .map(String.init)
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let message, !message.isEmpty else {
                alertMessage = "AI did not return a commit message."
                return nil
            }
            gitOperationMessage = "AI commit message generated. Review it before committing."
            return String(message.prefix(160))
        } catch {
            alertMessage = "Could not generate a commit message: \(error.localizedDescription)"
            return nil
        }
    }

    /// Safe rollback: creates a new inverse commit and preserves shared history.
    func gitRevertCommit(_ hash: String) {
        Task {
            gitIsWorking = true
            defer { gitIsWorking = false }
            let result = await runGitExec(["revert", "--no-edit", hash])
            guard result.exitCode == 0 else {
                alertMessage = "Revert failed:\n\(result.output)"
                return
            }
            gitOperationMessage = "Created a revert commit for \(hash.prefix(7))."
            gitRefresh()
        }
    }

    /// Undo an unpushed commit while keeping all edits staged for correction.
    func gitUndoLastCommit() {
        Task {
            gitIsWorking = true
            defer { gitIsWorking = false }
            let result = await runGitExec(["reset", "--soft", "HEAD~1"])
            guard result.exitCode == 0 else {
                alertMessage = "Undo commit failed:\n\(result.output)"
                return
            }
            gitOperationMessage = "Last commit undone; changes remain staged."
            gitRefresh()
        }
    }
    
    // MARK: - Branch Management
    
    func gitLoadBranches() {
        Task {
            let raw = await runGit(["branch", "-a", "--no-color"])
            let branches = raw.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "* ", with: "") }
                .filter { !$0.isEmpty && !$0.contains("HEAD") }
            await MainActor.run { self.gitBranches = branches }
        }
    }
    
    func gitSwitchBranch(_ branch: String) {
        Task {
            let cleanBranch = branch
                .replacingOccurrences(of: "remotes/origin/", with: "")
                .trimmingCharacters(in: .whitespaces)
            let result = await runGitExec(["checkout", cleanBranch])
            if result.exitCode != 0 {
                // Try creating tracking branch for remote
                let _ = await runGitExec(["checkout", "-b", cleanBranch, "origin/\(cleanBranch)"])
            }
            await MainActor.run {
                gitRefresh()
                gitLoadBranches()
            }
        }
    }
    
    func gitCreateBranch(_ name: String, switchTo: Bool = true) {
        Task {
            if switchTo {
                let _ = await runGitExec(["checkout", "-b", name])
            } else {
                let _ = await runGitExec(["branch", name])
            }
            await MainActor.run {
                gitRefresh()
                gitLoadBranches()
            }
        }
    }
    
    func gitDeleteBranch(_ name: String, force: Bool = false) {
        Task {
            let flag = force ? "-D" : "-d"
            let _ = await runGitExec(["branch", flag, name])
            await MainActor.run { gitLoadBranches() }
        }
    }
    
    func gitMergeBranch(_ name: String) {
        Task {
            let result = await runGitExec(["merge", name])
            await MainActor.run {
                if result.exitCode != 0 {
                    alertMessage = "Merge conflict:\n\(result.output)"
                }
                gitRefresh()
            }
        }
    }
    
    // MARK: - Stage / Unstage Individual Files
    
    func gitStageFile(_ path: String) {
        Task {
            let _ = await runGitExec(["add", path])
            await MainActor.run { gitRefresh() }
        }
    }
    
    func gitUnstageFile(_ path: String) {
        Task {
            let _ = await runGitExec(["reset", "HEAD", path])
            await MainActor.run { gitRefresh() }
        }
    }
    
    func gitStageAll() {
        Task {
            let _ = await runGitExec(["add", "-A"])
            await MainActor.run { gitRefresh() }
        }
    }
    
    func gitDiscardFile(_ path: String) {
        Task {
            let _ = await runGitExec(["checkout", "--", path])
            await MainActor.run { gitRefresh() }
        }
    }
    
    // MARK: - Diff
    
    func gitShowDiff(for path: String) {
        Task {
            let diff = await runGit(["diff", "--", path])
            let cachedDiff = await runGit(["diff", "--cached", "--", path])
            await MainActor.run {
                gitDiffFile = path
                gitDiff = diff.isEmpty ? cachedDiff : diff
            }
        }
    }
    
    func gitShowFileDiff(_ path: String) -> String {
        // Synchronous wrapper for inline diff preview
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "--", path]
        process.currentDirectoryURL = workspaceFolder
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    // MARK: - Stash Management
    
    func gitLoadStashList() {
        Task {
            let raw = await runGit(["stash", "list"])
            let list = raw.components(separatedBy: "\n").filter { !$0.isEmpty }
            await MainActor.run { gitStashList = list }
        }
    }
    
    func gitStash(message: String? = nil) {
        Task {
            var args = ["stash", "push"]
            if let msg = message, !msg.isEmpty { args += ["-m", msg] }
            let _ = await runGitExec(args)
            await MainActor.run {
                gitRefresh()
                gitLoadStashList()
            }
        }
    }
    
    func gitStashPop(index: Int = 0) {
        Task {
            let _ = await runGitExec(["stash", "pop", "stash@{\(index)}"])
            await MainActor.run {
                gitRefresh()
                gitLoadStashList()
            }
        }
    }
    
    func gitStashDrop(index: Int) {
        Task {
            let _ = await runGitExec(["stash", "drop", "stash@{\(index)}"])
            await MainActor.run { gitLoadStashList() }
        }
    }
    
    // MARK: - Remote Info
    
    func gitLoadRemoteURL() {
        Task {
            let url = await runGit(["remote", "get-url", "origin"])
            await MainActor.run { gitRemoteURL = url }
        }
    }
    
    func gitFetch() {
        Task {
            let _ = await runGitExec(["fetch", "--all", "--prune"])
            await MainActor.run {
                gitRefresh()
                gitLoadBranches()
            }
        }
    }
    
    // MARK: - GitHub CI/CD Status
    
    func gitLoadCICDStatus() {
        guard !gitRemoteURL.isEmpty else { return }
        // Extract owner/repo from remote URL
        let url = gitRemoteURL
        var owner = ""
        var repo = ""
        if url.contains("github.com") {
            let parts = url
                .replacingOccurrences(of: "https://github.com/", with: "")
                .replacingOccurrences(of: "git@github.com:", with: "")
                .replacingOccurrences(of: ".git", with: "")
                .components(separatedBy: "/")
            if parts.count >= 2 {
                owner = parts[0]
                repo = parts[1]
            }
        }
        guard !owner.isEmpty, !repo.isEmpty else { return }
        
        cicdLoading = true
        CICDService.shared.fetchWorkflowRuns(owner: owner, repo: repo, token: "") { [weak self] result in
            DispatchQueue.main.async {
                self?.cicdLoading = false
                if case .success(let runs) = result {
                    self?.cicdRuns = runs
                }
            }
        }
    }

    // MARK: - File Tree

    /// Alias for reloadFileTree for backward compatibility
    @MainActor
    public func refreshFileTree() async {
        await reloadFileTree()
    }
    
    @MainActor
    public func reloadFileTree() async {
        guard let folder = workspaceFolder else { return }

        let folderURL = folder.standardizedFileURL
        let loadGeneration = workspaceLoadGeneration
        let scanGeneration = UUID()
        rootScanGeneration = scanGeneration
        let result = await Task.detached(priority: .userInitiated) {
            Self.scanDirectoryBounded(at: folderURL, limit: Self.maximumDirectoryEntries)
        }.value

        guard workspaceLoadGeneration == loadGeneration,
              rootScanGeneration == scanGeneration,
              workspaceFolder?.standardizedFileURL == folderURL else { return }

        loadingDirectoryPaths.removeAll(keepingCapacity: true)
        loadedDirectoryPaths.removeAll(keepingCapacity: true)
        fileTree = result.nodes
        fileTreeRevision &+= 1
        fileTreeLimitWarning = result.wasTruncated
            ? "Showing the first \(Self.maximumDirectoryEntries) items in \(folderURL.lastPathComponent)."
            : nil
    }
    
    @MainActor
    func loadChildren(for nodeId: String) async {
        let path = URL(fileURLWithPath: nodeId).standardizedFileURL.path
        guard !loadedDirectoryPaths.contains(path),
              !loadingDirectoryPaths.contains(path),
              let workspacePath = workspaceFolder?.standardizedFileURL.path,
              path == workspacePath || path.hasPrefix(workspacePath + "/") else { return }

        let loadGeneration = workspaceLoadGeneration
        loadingDirectoryPaths.insert(path)

        let result = await Task.detached(priority: .userInitiated) {
            Self.scanDirectoryBounded(
                at: URL(fileURLWithPath: path, isDirectory: true),
                limit: Self.maximumDirectoryEntries
            )
        }.value

        loadingDirectoryPaths.remove(path)
        guard workspaceLoadGeneration == loadGeneration,
              workspaceFolder?.standardizedFileURL.path == workspacePath else { return }

        updateNode(id: nodeId) { node in
            node.children = result.nodes
            node.hasLoadedChildren = true
        }
        loadedDirectoryPaths.insert(path)

        if result.wasTruncated {
            fileTreeLimitWarning = "Showing the first \(Self.maximumDirectoryEntries) items in \(URL(fileURLWithPath: path).lastPathComponent)."
        }
    }
    
    @MainActor
    private func updateNode(id: String, transform: (inout FileNode) -> Void) {
        // Optimization: Removed MicroVM.executeSafe as it introduced significant overhead
        // resulting in UI freezes during folder expansion. Standard Swift mutation is sufficient.
        if self.updateNodeRecursive(nodes: &self.fileTree, id: id, transform: transform) {
            fileTreeRevision &+= 1
        }
    }

    /// Stream one directory level and stop at a hard limit. Unlike
    /// `contentsOfDirectory`, this does not first allocate an array containing
    /// every entry in directories with hundreds of thousands of files.
    nonisolated private static func scanDirectoryBounded(at url: URL, limit: Int) -> (nodes: [FileNode], wasTruncated: Bool) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        let fm = FileManager.default
        
        var urlsToProcess: [URL] = []
        if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            urlsToProcess = contents
        } else if let pathContents = try? fm.contentsOfDirectory(atPath: url.path) {
            urlsToProcess = pathContents.filter { !$0.hasPrefix(".") }.map { url.appendingPathComponent($0) }
        }
        
        var nodes: [FileNode] = []
        nodes.reserveCapacity(min(limit, urlsToProcess.count))
        var wasTruncated = false

        for child in urlsToProcess {
            guard child.lastPathComponent.hasPrefix("._") == false,
                  child.lastPathComponent.hasPrefix(".") == false else { continue }
            if nodes.count >= limit {
                wasTruncated = true
                break
            }

            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: child.path, isDirectory: &isDir)
            guard exists else { continue }

            nodes.append(FileNode(
                name: child.lastPathComponent,
                path: child.standardizedFileURL.path,
                isDirectory: isDir.boolValue,
                children: [],
                hasLoadedChildren: false
            ))
        }

        nodes.sort {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return (nodes, wasTruncated)
    }
    
    // Recursive is fine for standard usage, but if we want "Advanced Fix",
    // we should ensure it doesn't crash.
    @MainActor
    private func updateNodeRecursive(nodes: inout [FileNode], id: String, transform: (inout FileNode) -> Void) -> Bool {
        for i in 0..<nodes.count {
            if nodes[i].id == id {
                transform(&nodes[i])
                return true
            }
            // Optimization: Only check children if it IS a directory
            if nodes[i].isDirectory {
                 if updateNodeRecursive(nodes: &nodes[i].children, id: id, transform: transform) {
                    return true
                }
            }
        }
        return false
    }
    
    // Convert findNode to Iterative
    private func findNode(id: String, in nodes: [FileNode]) -> FileNode? {
        var stack = nodes
        while !stack.isEmpty {
            let node = stack.removeLast()
            if node.id == id { return node }
            if node.isDirectory {
                stack.append(contentsOf: node.children)
            }
        }
        return nil
    }
    
    private func loadChildren(at url: URL) -> [FileNode] {
        let fileManager = FileManager.default
        var nodes: [FileNode] = []
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        for childURL in contents {
            let isDirectory = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let node = FileNode(
                name: childURL.lastPathComponent,
                path: childURL.path,
                isDirectory: isDirectory,
                children: [],
                hasLoadedChildren: false
            )
            nodes.append(node)
        }
        
        return nodes.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory
            }
            return $0.name.lowercased() < $1.name.lowercased()
        }
    }

    private func buildFileTree(from files: [FileInfo], basePath: String) -> [FileNode] {
        var nodes: [String: FileNode] = [:]

        for file in files {
            let relativePath = file.path.replacingOccurrences(of: basePath + "/", with: "")
            let components = relativePath.split(separator: "/").map(String.init)

            var currentPath = ""
            for (index, component) in components.enumerated() {
                currentPath = currentPath.isEmpty ? component : currentPath + "/" + component

                if nodes[currentPath] == nil {
                    let isDirectory = index < components.count - 1 || file.isDirectory
                    nodes[currentPath] = FileNode(
                        name: component,
                        path: basePath + "/" + currentPath,
                        isDirectory: isDirectory,
                        children: []
                    )
                }
            }
        }

        // Build tree structure
        var rootNodes: [FileNode] = []
        let sortedPaths = nodes.keys.sorted()

        for path in sortedPaths {
            if !path.contains("/") {
                rootNodes.append(nodes[path]!)
            }
        }

        return rootNodes.sorted { $0.name < $1.name }
    }

    // MARK: - View Toggles

    @Published var selectedConsoleTab: Int = 0

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.22)) {
            sidebarVisible.toggle()
        }
        saveSettings()
    }

    func toggleConsole(tab: Int? = nil) {
        if let tab = tab {
            selectedConsoleTab = tab
            consoleVisible = true
        } else {
            consoleVisible.toggle()
        }
        saveSettings()
    }

    func toggleGitPanel() {
        gitPanelVisible.toggle()
    }

    func toggleAgenticContext() {
        agenticContextVisible.toggle()
        saveSettings()
    }

    func showPreviewInspector(tab: String? = nil) {
        agenticContextVisible = true
        selectedInspectorTab = .preview
        showingPreviewView = true
        DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
        PreviewDockService.shared.isDockVisible = true
        if let tab = tab {
            PreviewDockService.shared.selectTab(id: tab)
        } else {
            let autoTab = detectBestPreviewTab()
            PreviewDockService.shared.selectTab(id: autoTab)
        }
        saveSettings()
    }

    func hidePreviewInspector() {
        agenticContextVisible = false
        showingPreviewView = false
        DeviceRuntimeService.shared.showingEmbeddedDeviceDock = false
        DeviceRuntimeService.shared.stopEmbeddedAndroid()
        AppleSimulatorCaptureService.shared.stop()
        PreviewDockService.shared.isDockVisible = false
        saveSettings()
    }

    /// Intelligently detect the best preview platform for the current workspace (defaulting to Web)
    func detectBestPreviewTab() -> String {
        guard let folder = workspaceFolder else {
            return PreviewDockService.shared.activeTabId
        }
        let fm = FileManager.default
        let folderPath = folder.path
        
        // 1. WebApp indicators (HTML, Vite, Next, React, Vue, Svelte, static web)
        let webFiles = ["index.html", "package.json", "vite.config.ts", "vite.config.js", "next.config.js", "next.config.mjs", "nuxt.config.ts", "svelte.config.js", "astro.config.mjs", "public/index.html", "dist/index.html"]
        for rel in webFiles {
            if fm.fileExists(atPath: folder.appendingPathComponent(rel).path) {
                return "web"
            }
        }
        
        // 2. iOS indicators (Xcode project, xcworkspace, Podfile)
        if let items = try? fm.contentsOfDirectory(atPath: folderPath) {
            if items.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") || $0 == "Podfile" }) {
                return "ios"
            }
            // 3. Android indicators (Gradle, AndroidManifest)
            if items.contains(where: { $0 == "build.gradle" || $0 == "build.gradle.kts" || $0 == "settings.gradle" || $0 == "settings.gradle.kts" }) {
                return "android"
            }
        }
        
        return "web"
    }
    
    // MARK: - Editor Mode
    
    func setEditorMode(_ mode: EditorMode) {
        // Mutual exclusion: Close inline agent panel when entering full agent mode
        if mode == .aiAgent {
            aiChatVisible = false
        }
        
        // Update published property
        editorMode = mode
        NotificationCenter.default.post(name: NSNotification.Name("MicroCodeEditorModeChanged"), object: mode)
    }
    
    func toggleEditorMode(_ mode: EditorMode) {
        if editorMode == mode {
            setEditorMode(.code)
        } else {
            setEditorMode(mode)
        }
    }

    func switchToMode(_ mode: EditorMode) {
        showingWelcomeHome = false
        setEditorMode(mode)
    }
    
    func openAPIStudio() {
        showingWelcomeHome = false
        showingAPIClient = false
        setEditorMode(.apiClient)
    }
    
    func openExtensionStudio() {
        showingWelcomeHome = false
        setEditorMode(.extensions)
    }
    
    // MARK: - File Watcher
    
    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var fileRefreshTimer: Timer?

    
    func startFileWatcher() {
        // Cancel existing watcher if any
        fileMonitorSource?.cancel()
        fileMonitorSource = nil
        fileRefreshTimer?.invalidate()
        fileRefreshTimer = nil
        
        guard let folder = workspaceFolder else { return }
        
        // Only monitor for structural changes (add/remove/rename)
        // Monitoring .write on a directory usually only triggers if directory metadata changes
        // But some editors/OS operations might trigger it frequently.
        let descriptor = open(folder.path, O_EVTONLY)
        if descriptor == -1 { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .link, .rename, .delete, .extend], 
            queue: DispatchQueue.global()
        )
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            // Debounce logic: Coalesce rapid events into a single refresh
            DispatchQueue.main.async {
                self.fileRefreshTimer?.invalidate()
                self.fileRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                    Task {
                        // Only refresh if we are not already refreshing/loading?
                        // refreshFileTree is usually fast enough if debounced.
                        await self.refreshFileTree()
                    }
                }
            }
        }
        
        source.setCancelHandler {
            close(descriptor)
        }
        
        source.resume()
        fileMonitorSource = source
    }
    
    // MARK: - Python Version Detection
    
    @MainActor
    public func detectPythonVersions() {
        // Capture workspace folder on Main Thread to avoid actor isolation issues
        let currentFolder = workspaceFolder
        
        Task.detached(priority: .userInitiated) {
            var versions: [PythonVersionInfo] = []
            
            // Common Python paths to check
            let pythonPaths = [
                "/opt/homebrew/bin/python3",
                "/opt/homebrew/bin/python3.12",
                "/opt/homebrew/bin/python3.11",
                "/opt/homebrew/bin/python3.10",
                "/usr/local/bin/python3",
                "/usr/local/bin/python3.12",
                "/usr/local/bin/python3.11",
                "/usr/local/bin/python3.10",
                "/usr/bin/python3",
                "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
                "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
                "/Library/Frameworks/Python.framework/Versions/3.10/bin/python3",
            ]
            
            let fileManager = FileManager.default
            
            for path in pythonPaths {
                guard DeveloperToolsGuard.isSafeToExecute(path) else { continue }
                if fileManager.fileExists(atPath: path) {
                    // Get version
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: path)
                    process.arguments = ["--version"]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    do {
                        try process.run()
                        process.waitUntilExit()
                        
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                            let version = output.replacingOccurrences(of: "Python ", with: "")
                            let displayName = "Python \(version)"
                            
                            // Avoid duplicates
                            if !versions.contains(where: { $0.version == version }) {
                                versions.append(PythonVersionInfo(path: path, version: version, displayName: displayName))
                            }
                        }
                    } catch {
                        // Ignore errors
                    }
                }
            }
            
            // Also check virtual environments in current workspace
            if let folder = currentFolder {
                let venvPaths = [
                    folder.appendingPathComponent("venv/bin/python3"),
                    folder.appendingPathComponent(".venv/bin/python3"),
                    folder.appendingPathComponent("env/bin/python3"),
                ]
                
                for url in venvPaths {
                    if fileManager.fileExists(atPath: url.path) {
                        let process = Process()
                        process.executableURL = url
                        process.arguments = ["--version"]
                        
                        let pipe = Pipe()
                        process.standardOutput = pipe
                        process.standardError = pipe
                        
                        do {
                            try process.run()
                            process.waitUntilExit()
                            
                            let data = pipe.fileHandleForReading.readDataToEndOfFile()
                            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                                let version = output.replacingOccurrences(of: "Python ", with: "")
                                let displayName = "venv: Python \(version)"
                                versions.insert(PythonVersionInfo(path: url.path, version: version, displayName: displayName), at: 0)
                            }
                        } catch {
                            // Ignore
                        }
                    }
                }
            }
            
            // Sort by version (newest first)
            versions.sort { $0.version > $1.version }
            
            // Update State (Main Actor)
            await MainActor.run { [versions] in
                self.availablePythonVersions = versions
                
                // Set default if not set
                if self.selectedPythonVersion == "python3" && !versions.isEmpty {
                    self.selectedPythonVersion = versions.first?.path ?? "python3"
                }
            }
        }
    }

    // MARK: - Font Size

    func increaseFontSize() {
        fontSize = min(fontSize + 1, 36)
        saveSettings()
    }

    func decreaseFontSize() {
        fontSize = max(fontSize - 1, 8)
        saveSettings()
    }

    func resetFontSize() {
        fontSize = 13
        saveSettings()
    }

    // MARK: - Utilities
    
    func detectLanguage(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "py": return "python"
        case "js": return "javascript"
        case "ts": return "typescript"
        case "rs": return "rust"
        case "swift": return "swift"
        case "go": return "go"
        case "rb": return "ruby"
        case "java": return "java"
        case "kt", "kts": return "kotlin" // ADDED: Kotlin
        case "cpp", "cc", "cxx", "c++": return "cpp"
        case "m": return "objective-c"
        case "mm": return "objective-cpp"
        case "c": return "c"
        case "h", "hpp": return "cpp"
        case "json": return "json"
        case "xml": return "xml"
        case "html": return "html"
        case "css": return "css"
        case "md": return "markdown"
        case "sh", "zsh", "bash": return "shell"
        case "yaml", "yml": return "yaml"
        case "ar": return "ardium"
        case "dart": return "dart"
        case "php": return "php"
        case "cs": return "csharp"
        case "lua": return "lua"
        case "pl", "pm": return "perl"
        case "r": return "r"
        case "jl": return "julia"
        case "sql": return "sql"
        case "ml", "mli": return "ocaml"
        case "hs": return "haskell"
        case "zig": return "zig"
        case "nim": return "nim"
        case "d": return "d"
        case "f90", "f95", "f03": return "fortran"
        case "pas", "pp": return "pascal"
        case "ex", "exs": return "elixir"
        case "clj", "cljs": return "clojure"
        case "groovy": return "groovy"
        case "hx": return "haxe"
        case "scala", "sc": return "scala"
        case "fs", "fsi", "fsx": return "fsharp"
        case "vala": return "vala"
        case "ps1": return "powershell"
        case "asm", "s": return "assembly"
        case "sol": return "solidity"
        default: return "text"
        }
    }
    
    // MARK: - Derived Data Cache Control
    
    func checkDerivedDataSize() {
        guard !isCheckingCache else { return }
        isCheckingCache = true
        
        Task {
            do {
                let info = try await BackendService.shared.getDerivedDataInfo()
                DispatchQueue.main.async {
                    self.derivedDataInfo = info
                    self.isCheckingCache = false
                    self.evaluateQuota(info: info)
                }
            } catch {
                print("⚠️ Failed to check DerivedData: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isCheckingCache = false
                }
            }
        }
    }
    
    func clearDerivedData(projectPattern: String? = nil) {
        Task {
            do {
                let info = try await BackendService.shared.clearDerivedData(projectPattern: projectPattern)
                DispatchQueue.main.async {
                    self.derivedDataInfo = info
                    self.checkDerivedDataSize() // Update the UI state with new size
                }
            } catch {
                print("⚠️ Failed to clear DerivedData: \(error.localizedDescription)")
            }
        }
    }
    
    private func evaluateQuota(info: DerivedDataInfo) {
        guard derivedDataQuotaLimitGB > 0 else { return } // 0 means Unlimited
        
        let sizeGB = Double(info.size_bytes) / 1_000_000_000.0
        if sizeGB > derivedDataQuotaLimitGB {
            if enableDerivedDataAutoPurge {
                print("🧹 DerivedData size (\(sizeGB) GB) exceeds quota (\(derivedDataQuotaLimitGB) GB). Auto-purging...")
                clearDerivedData(projectPattern: nil)
            } else if enableDerivedDataAlert {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "DerivedData Quota Exceeded"
                    alert.informativeText = String(format: "DerivedData size (%.2f GB) exceeds your quota limit (%.1f GB).\nWould you like to clear it to free up disk space?", sizeGB, self.derivedDataQuotaLimitGB)
                    alert.addButton(withTitle: "Clean Now")
                    alert.addButton(withTitle: "Cancel")
                    alert.alertStyle = .warning
                    
                    if alert.runModal() == .alertFirstButtonReturn {
                        self.clearDerivedData(projectPattern: nil)
                    }
                }
            }
        }
    }
}

// MARK: - Models

struct CodeFile: Identifiable, Equatable {
    let id: UUID
    var name: String
    var path: String
    var content: String
    var language: String
    var isUnsaved: Bool
    var isReadOnly: Bool = false
    var usesPlainTextMode: Bool = false
    var originalByteSize: Int = 0
    var isTruncated: Bool = false

    static func == (lhs: CodeFile, rhs: CodeFile) -> Bool {
        lhs.id == rhs.id
    }
}

struct FileNode: Identifiable, Equatable {
    var id: String { path }
    var name: String
    var path: String
    var isDirectory: Bool
    var children: [FileNode]
    var hasLoadedChildren: Bool = false
    
    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        return lhs.path == rhs.path &&
               lhs.isDirectory == rhs.isDirectory &&
               lhs.hasLoadedChildren == rhs.hasLoadedChildren &&
               lhs.children == rhs.children
    }
}

struct FileInfo: Codable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let modified: String?
    let `extension`: String?
    
    enum CodingKeys: String, CodingKey {
        case name, path, size, modified, `extension`
        case isDirectory = "is_directory"
    }
}

struct GitStatus: Codable {
    let branch: String
    let files: [GitFileStatus]
    let ahead: Int
    let behind: Int
}

struct GitFileStatus: Codable {
    let path: String
    let status: String
}

struct GitCommit: Codable, Identifiable {
    var id: String { hash }
    let hash: String
    let author: String
    let email: String
    let message: String
    let timestamp: String
}

struct ExecutionOutput: Codable {
    let stdout: String
    let stderr: String
    let exitCode: Int
    let executionTime: Double
    
    enum CodingKeys: String, CodingKey {
        case stdout
        case stderr
        case exitCode = "exit_code"
        case executionTime = "execution_time"
    }
}

// MARK: - Browser Models

struct BrowserTab: Identifiable {
    let id = UUID()
    var url: String
    var title: String
    var isLoading: Bool = false
    var canGoBack: Bool = false
    var canGoForward: Bool = false
}

struct BrowserHistoryEntry: Identifiable {
    let id = UUID()
    let url: String
    let title: String
    let visitedAt: Date
}

struct BrowserBookmark: Identifiable, Codable {
    var id = UUID()
    var url: String
    var title: String
    var favicon: String?
}

// MARK: - Debug Helper
@MainActor
class FolderFreezeDebugger {
    static let shared = FolderFreezeDebugger()
    
    var refreshCount = 0
    var lastRefreshTime: Date?
    
    func logRefreshStart() {
        refreshCount += 1
        lastRefreshTime = Date()
        print("📂 [FreezeDebug] Refresh #\(refreshCount) started at \(Date())")
    }
    
    func logRefreshEnd(nodeCount: Int) {
        guard let start = lastRefreshTime else { return }
        let duration = Date().timeIntervalSince(start)
        print("📂 [FreezeDebug] Refresh finished in \(String(format: "%.4f", duration))s. Nodes: \(nodeCount)")
        
        if duration > 1.0 {
            print("⚠️ [FreezeDebug] SLOW REFRESH DETECTED!")
        }
    }
    
    func checkRecursion(nodes: [FileNode], depth: Int = 0) {
        if depth > 50 {
            print("🚨 [FreezeDebug] POTENTIAL INFINITE RECURSION (Depth > 50)")
            return
        }
        for node in nodes {
            if node.hasLoadedChildren {
                checkRecursion(nodes: node.children, depth: depth + 1)
            }
        }
    }
}
