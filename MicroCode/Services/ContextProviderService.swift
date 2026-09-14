import Foundation
import Combine
import SwiftUI

enum ContextProviderType: String, CaseIterable, Identifiable {
    case file = "file"
    case folder = "folder"
    case symbol = "symbol"
    case error = "error"
    case terminal = "terminal"
    case git = "git"
    case selection = "selection"
    case web = "web"
    case docs = "docs"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .file: return "Files"
        case .folder: return "Folders"
        case .symbol: return "Symbols"
        case .error: return "Errors"
        case .terminal: return "Terminal Output"
        case .git: return "Git Changes"
        case .selection: return "Selection"
        case .web: return "Web Search"
        case .docs: return "Documentation"
        }
    }
    
    var icon: String {
        switch self {
        case .file: return "doc"
        case .folder: return "folder"
        case .symbol: return "function"
        case .error: return "exclamationmark.triangle"
        case .terminal: return "terminal"
        case .git: return "arrow.triangle.branch"
        case .selection: return "selection.pin.in.out"
        case .web: return "network"
        case .docs: return "book"
        }
    }
    
    var description: String {
        switch self {
        case .file: return "Include file content"
        case .folder: return "Include folder structure"
        case .symbol: return "Search for functions or classes"
        case .error: return "Include current compiler errors"
        case .terminal: return "Include console output"
        case .git: return "Include git status and diff"
        case .selection: return "Include selected code"
        case .web: return "Search the web"
        case .docs: return "Search documentation"
        }
    }
}

struct ContextItem: Identifiable, Equatable {
    let id = UUID()
    let provider: ContextProviderType
    let title: String
    let subtitle: String?
    let content: String
    let tokenEstimate: Int
    
    static func == (lhs: ContextItem, rhs: ContextItem) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class ContextProviderService: ObservableObject {
    static let shared = ContextProviderService()
    
    @Published var suggestions: [ContextProviderType] = []
    @Published var isShowingSuggestions: Bool = false
    @Published var secondLevelItems: [ContextItem] = []
    @Published var isShowingSecondLevel: Bool = false
    @Published var selectedProviderType: ContextProviderType?
    @Published var attachedContexts: [ContextItem] = []
    
    func getSuggestions(for prefix: String) -> [ContextProviderType] {
        let cleanPrefix = prefix.replacingOccurrences(of: "@", with: "").lowercased()
        if cleanPrefix.isEmpty {
            return ContextProviderType.allCases
        } else {
            return ContextProviderType.allCases.filter {
                $0.rawValue.lowercased().hasPrefix(cleanPrefix) ||
                $0.displayName.lowercased().hasPrefix(cleanPrefix)
            }
        }
    }
    
    func loadSecondLevel(for provider: ContextProviderType, query: String, appState: AppState) -> [ContextItem] {
        var items: [ContextItem] = []
        
        switch provider {
        case .file:
            // List files in workspace (mock implementation for demonstration, should list actual files)
            let openFiles = appState.openFiles
            items = openFiles.map { file in
                ContextItem(
                    provider: .file,
                    title: file.name,
                    subtitle: file.path,
                    content: file.content,
                    tokenEstimate: file.content.count / 4
                )
            }
            if !query.isEmpty {
                items = items.filter { $0.title.lowercased().contains(query.lowercased()) }
            }
            
        case .folder:
            if let root = appState.workspaceFolder {
                items.append(
                    ContextItem(
                        provider: .folder,
                        title: root.lastPathComponent,
                        subtitle: root.path,
                        content: "Folder structure of \(root.lastPathComponent)",
                        tokenEstimate: 50
                    )
                )
            }
            
        case .symbol:
            // Placeholder for symbol search
            items.append(
                ContextItem(
                    provider: .symbol,
                    title: "Symbol Search",
                    subtitle: "Search for '\(query)'",
                    content: "Symbol results for \(query)",
                    tokenEstimate: 100
                )
            )
            
        case .error:
            items.append(
                ContextItem(
                    provider: .error,
                    title: "Current Errors",
                    subtitle: "Compiler diagnostics",
                    content: "No active errors.", // Should fetch real errors
                    tokenEstimate: 20
                )
            )
            
        case .terminal:
            let output = appState.consoleOutput
            items.append(
                ContextItem(
                    provider: .terminal,
                    title: "Terminal Output",
                    subtitle: "Recent console logs",
                    content: output,
                    tokenEstimate: output.count / 4
                )
            )
            
        case .git:
            items.append(
                ContextItem(
                    provider: .git,
                    title: "Git Status",
                    subtitle: "Current diffs and status",
                    content: "Git diff output here...", // Needs actual shell call
                    tokenEstimate: 150
                )
            )
            
        case .selection:
            items.append(
                ContextItem(
                    provider: .selection,
                    title: "Selected Code",
                    subtitle: "Active editor selection",
                    content: "/* Selected text not found */",
                    tokenEstimate: 10
                )
            )
            
        case .web, .docs:
            items.append(
                ContextItem(
                    provider: provider,
                    title: "Search '\(query)'",
                    subtitle: provider == .web ? "Search the web" : "Search documentation",
                    content: "Search results for \(query)",
                    tokenEstimate: 500
                )
            )
        }
        
        return items
    }
    
    func resolveContext(provider: ContextProviderType, query: String, appState: AppState) -> ContextItem? {
        let items = loadSecondLevel(for: provider, query: query, appState: appState)
        return items.first
    }
    
    func buildContextPrompt() -> String {
        guard !attachedContexts.isEmpty else { return "" }
        
        var prompt = "Here is the provided context:\n\n"
        for item in attachedContexts {
            prompt += "--- \(item.title) (\(item.provider.displayName)) ---\n"
            prompt += item.content
            prompt += "\n\n"
        }
        return prompt
    }
    
    func selectProvider(_ provider: ContextProviderType) {
        selectedProviderType = provider
        isShowingSuggestions = false
        isShowingSecondLevel = true
    }
    
    func removeContext(_ item: ContextItem) {
        attachedContexts.removeAll { $0.id == item.id }
    }
    
    func clearAll() {
        attachedContexts.removeAll()
        suggestions.removeAll()
        secondLevelItems.removeAll()
        isShowingSuggestions = false
        isShowingSecondLevel = false
        selectedProviderType = nil
    }
}
