//
//  KeyboardShortcutsCheatSheetView.swift
//  MicroCode
//
//  Created by Antigravity on 2026-09-14.
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import SwiftUI
import AppKit

struct ShortcutItem: Identifiable {
    let id = UUID()
    let title: String
    let category: ShortcutCategory
    let keys: [String] // e.g. ["⌃", "1"] or ["⌘", "B"]
    let description: String?
    let action: ((AppState) -> Void)?

    init(title: String, category: ShortcutCategory, keys: [String], description: String? = nil, action: ((AppState) -> Void)? = nil) {
        self.title = title
        self.category = category
        self.keys = keys
        self.description = description
        self.action = action
    }
}

enum ShortcutCategory: String, CaseIterable, Identifiable {
    case modes = "Modes"
    case panels = "Panels & Views"
    case files = "Files & Tabs"
    case code = "Code & Execution"
    case ai = "AI Agent & Copilot"
    case git = "Git & Tools"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .modes: return "square.grid.2x2"
        case .panels: return "sidebar.left"
        case .files: return "doc.on.doc"
        case .code: return "play.circle"
        case .ai: return "sparkles"
        case .git: return "shippingbox"
        }
    }
}

struct KeyboardShortcutsCheatSheetView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: ShortcutCategory? = nil

    private var allShortcuts: [ShortcutItem] {
        [
            // MARK: - Modes
            ShortcutItem(title: "Code Editor Mode", category: .modes, keys: ["⌃", "1"], description: "Standard high-performance code editor") { $0.switchToMode(.code) },
            ShortcutItem(title: "AI Agent Workspace", category: .modes, keys: ["⌃", "2"], description: "Full autonomous ACP / AGY agent canvas") { $0.switchToMode(.aiAgent) },
            ShortcutItem(title: "Cell Mode (Notebook)", category: .modes, keys: ["⌃", "3"], description: "Interactive Jupyter-compatible notebook cells") { $0.switchToMode(.notebook) },
            ShortcutItem(title: "Playground Mode", category: .modes, keys: ["⌃", "4"], description: "Instant multi-language scratchpad & REPL") { $0.switchToMode(.playground) },
            ShortcutItem(title: "Science Mode", category: .modes, keys: ["⌃", "5"], description: "STEM, Biomolecular, and Science workflows") { $0.switchToMode(.science) },
            ShortcutItem(title: "IDE Web Browser", category: .modes, keys: ["⌃", "6"], description: "Built-in web preview & developer browser") { $0.switchToMode(.browser) },
            ShortcutItem(title: "Remote Explorer (SSH)", category: .modes, keys: ["⌃", "7"], description: "SSH, Cloud GPU, and remote servers") { $0.switchToMode(.remoteX) },
            ShortcutItem(title: "Embed & IoT Studio", category: .modes, keys: ["⌃", "8"], description: "Arduino, ESP32, and hardware microcontroller hub") { $0.switchToMode(.embedded) },
            ShortcutItem(title: "API Studio", category: .modes, keys: ["⌃", "9"], description: "REST, GraphQL & HTTP test studio") { $0.openAPIStudio() },
            ShortcutItem(title: "Extension Studio", category: .modes, keys: ["⌃", "E"], description: "Community extensions & feature canvas") { $0.openExtensionStudio() },
            ShortcutItem(title: "Welcome / Dashboard", category: .modes, keys: ["⌃", "0"], description: "MicroCode home welcome dashboard") { $0.showingWelcomeHome = true },

            // MARK: - Panels & Layout
            ShortcutItem(title: "Toggle Left Sidebar", category: .panels, keys: ["⌘", "B"], description: "Show or hide file tree & navigation sidebar") { $0.toggleSidebar() },
            ShortcutItem(title: "Toggle Preview & Context Inspector", category: .panels, keys: ["⌘", "I"], description: "Show or hide right inspector dock") { $0.toggleAgenticContext() },
            ShortcutItem(title: "Toggle Terminal / Console", category: .panels, keys: ["⌘", "J"], description: "Show or hide bottom console & terminal") { $0.toggleConsole() },
            ShortcutItem(title: "Toggle Git Panel", category: .panels, keys: ["⌘", "⌥", "G"], description: "Show or hide source control panel") { $0.toggleGitPanel() },
            ShortcutItem(title: "Toggle Device Preview Dock", category: .panels, keys: ["⌘", "⌥", "P"], description: "Show or hide iOS Simulator / Android device preview") { $0.showingPreviewView.toggle() },
            ShortcutItem(title: "Zoom In (Font Size)", category: .panels, keys: ["⌘", "+"], description: "Increase editor font size") { $0.increaseFontSize() },
            ShortcutItem(title: "Zoom Out (Font Size)", category: .panels, keys: ["⌘", "-"], description: "Decrease editor font size") { $0.decreaseFontSize() },
            ShortcutItem(title: "Reset Zoom", category: .panels, keys: ["⌘", "0"], description: "Reset editor font size to default") { $0.resetFontSize() },

            // MARK: - Files & Tabs
            ShortcutItem(title: "New File", category: .files, keys: ["⌘", "N"], description: "Create a new file in workspace") { $0.createNewFile() },
            ShortcutItem(title: "New AI Chat Conversation", category: .files, keys: ["⌘", "⇧", "N"], description: "Start a fresh agent session") { _ in },
            ShortcutItem(title: "Open File...", category: .files, keys: ["⌘", "O"], description: "Open an individual file from disk") { $0.openFile() },
            ShortcutItem(title: "Open Folder / Project...", category: .files, keys: ["⌘", "⇧", "O"], description: "Open a folder as active workspace") { $0.openFolder() },
            ShortcutItem(title: "Save Current File", category: .files, keys: ["⌘", "S"], description: "Save changes to active document") { $0.saveCurrentFile() },
            ShortcutItem(title: "Save As...", category: .files, keys: ["⌘", "⇧", "S"], description: "Save active file under new name") { $0.saveFileAs() },
            ShortcutItem(title: "Close Active Tab", category: .files, keys: ["⌘", "W"], description: "Close currently active editor tab") { app in
                if let cur = app.currentFile { app.closeFile(cur) }
            },
            ShortcutItem(title: "Close Other Tabs", category: .files, keys: ["⌘", "⌥", "W"], description: "Keep only current file open") { $0.closeOtherTabs() },
            ShortcutItem(title: "Close Workspace", category: .files, keys: ["⌘", "⇧", "W"], description: "Close active project workspace") { $0.closeWorkspace() },
            ShortcutItem(title: "Next Tab", category: .files, keys: ["⌘", "]"], description: "Cycle forward to next open file tab") { $0.selectNextTab() },
            ShortcutItem(title: "Previous Tab", category: .files, keys: ["⌘", "["], description: "Cycle backward to previous file tab") { $0.selectPreviousTab() },

            // MARK: - Code & Execution
            ShortcutItem(title: "Run Code / Active File", category: .code, keys: ["⌘", "R"], description: "Execute code with active language runner") { $0.runCode() },
            ShortcutItem(title: "Build Project", category: .code, keys: ["⌘", "⇧", "B"], description: "Compile / build project with native toolchain") { $0.buildProject() },
            ShortcutItem(title: "Stop Execution", category: .code, keys: ["⌘", "."], description: "Terminate currently running process") { $0.stopExecution() },
            ShortcutItem(title: "Format Code", category: .code, keys: ["⌘", "⌥", "F"], description: "Auto-format document code") { $0.formatCode() },
            ShortcutItem(title: "Explain Code with AI", category: .code, keys: ["⌘", "⌥", "E"], description: "Get AI explanation of highlighted code") { $0.explainCode() },
            ShortcutItem(title: "Refactor with AI", category: .code, keys: ["⌘", "⌥", "R"], description: "AI guided code refactoring") { $0.showRefactorDialog() },
            ShortcutItem(title: "Execute Cell", category: .code, keys: ["⌘", "↩"], description: "Run current notebook / cell mode block"),
            ShortcutItem(title: "Insert Cell Below", category: .code, keys: ["⌥", "↩"], description: "Add new executable cell block"),

            // MARK: - AI Agent & Copilot
            ShortcutItem(title: "Toggle / Focus AI Chat", category: .ai, keys: ["⌘", "L"], description: "Jump directly to AI Agent prompt box") { app in
                withAnimation { app.aiChatVisible.toggle() }
            },
            ShortcutItem(title: "Inline AI Edit / Quick Refactor", category: .ai, keys: ["⌘", "K"], description: "Invoke floating inline AI code modification") { $0.showRefactorDialog() },
            ShortcutItem(title: "AI Code Analysis", category: .ai, keys: ["⌘", "⌥", "A"], description: "Deep architectural diagnostic scan") { $0.showingCodeAnalysis = true },
            ShortcutItem(title: "Sub-Agent Monitor", category: .ai, keys: ["⌘", "⇧", "A"], description: "Inspect active background sub-agents") { $0.showingSubAgentMonitor = true },

            // MARK: - Git & Tools
            ShortcutItem(title: "Git Commit Changes", category: .git, keys: ["⌘", "K"], description: "Open commit staging window") { $0.showCommitDialog() },
            ShortcutItem(title: "Git Push", category: .git, keys: ["⌘", "⇧", "P"], description: "Push commits to remote branch") { $0.gitPush() },
            ShortcutItem(title: "Git Pull", category: .git, keys: ["⌘", "⌥", "P"], description: "Pull latest changes from remote") { $0.gitPull() },
            ShortcutItem(title: "Git Refresh Status", category: .git, keys: ["⌘", "⌃", "R"], description: "Rescan Git repository status") { $0.gitRefresh() },
            ShortcutItem(title: "Runtime Manager", category: .git, keys: ["⌘", "⇧", "M"], description: "Manage Node, Python, Go, Rust runtimes") { $0.showingRuntimeManager = true },
            ShortcutItem(title: "Settings Dialog", category: .git, keys: ["⌘", ","], description: "Configure MicroCode settings & keys") { $0.showingSettingsDialog = true },
            ShortcutItem(title: "Keyboard Shortcuts Cheat Sheet", category: .git, keys: ["⌘", "/"], description: "Show this cheat sheet HUD")
        ]
    }

    private var filteredShortcuts: [ShortcutItem] {
        allShortcuts.filter { item in
            let matchesCategory = selectedCategory == nil || item.category == selectedCategory
            if !matchesCategory { return false }
            if searchText.isEmpty { return true }
            let query = searchText.lowercased()
            return item.title.lowercased().contains(query) ||
                (item.description?.lowercased().contains(query) ?? false) ||
                item.keys.joined().lowercased().contains(query) ||
                item.category.rawValue.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "command.square.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Keyboard Shortcuts")
                        .font(.system(size: 16, weight: .bold))
                    Text("Complete power shortcuts for every Mode and feature in MicroCode")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Esc to close button
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Text("esc")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(4)
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            // Search and Category Filter Bar
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))

                    TextField("Search shortcuts by name, key, or category...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(7)

                // Category Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        CategoryPill(title: "All", count: allShortcuts.count, isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }

                        ForEach(ShortcutCategory.allCases) { cat in
                            let count = allShortcuts.filter { $0.category == cat }.count
                            CategoryPill(title: cat.rawValue, icon: cat.icon, count: count, isSelected: selectedCategory == cat) {
                                selectedCategory = cat
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            // Shortcuts List
            ScrollView {
                LazyVStack(spacing: 16) {
                    let grouped = Dictionary(grouping: filteredShortcuts, by: { $0.category })
                    let sortedCategories = ShortcutCategory.allCases.filter { grouped[$0] != nil }

                    ForEach(sortedCategories) { cat in
                        if let items = grouped[cat], !items.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.accentColor)
                                    Text(cat.rawValue.uppercased())
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 4)

                                VStack(spacing: 2) {
                                    ForEach(items) { item in
                                        ShortcutRow(item: item) {
                                            if let action = item.action {
                                                action(appState)
                                                dismiss()
                                            }
                                        }
                                    }
                                }
                                .background(Color.primary.opacity(0.02))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                                )
                            }
                        }
                    }

                    if filteredShortcuts.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                            Text("No shortcuts found for \"\(searchText)\"")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 40)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 680, height: 560)
        .background(
            appState.appTheme.isGlass
                ? AnyView(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
                : AnyView(Color(nsColor: appState.appTheme.workspaceBackground))
        )
    }
}

// MARK: - Shortcut Row

private struct ShortcutRow: View {
    let item: ShortcutItem
    let onTrigger: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                if let desc = item.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Keycaps
            HStack(spacing: 3) {
                ForEach(Array(item.keys.enumerated()), id: \.offset) { _, key in
                    KeyCapView(key: key)
                }
            }

            if item.action != nil {
                Button(action: onTrigger) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(isHovering ? .accentColor : .clear)
                }
                .buttonStyle(.plain)
                .help("Run action now")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            onTrigger()
        }
    }
}

// MARK: - KeyCap View

private struct KeyCapView: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.primary.opacity(0.9))
            .padding(.horizontal, key.count > 1 ? 6 : 5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Category Pill

private struct CategoryPill: View {
    let title: String
    var icon: String? = nil
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.06))
                    .cornerRadius(8)
            }
            .foregroundColor(isSelected ? .white : .primary.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
}
