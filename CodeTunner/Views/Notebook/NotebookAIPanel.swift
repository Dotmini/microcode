//
//  NotebookAIPanel.swift
//  CodeTunner
//
//  Smart AI Agent Panel for Cell Mode
//  Context-aware: understands all cells, languages, and outputs
//
//  Created by MicroCode Agent
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import SwiftUI
import Combine

// MARK: - Notebook AI Panel

struct NotebookAIPanel: View {
    @ObservedObject var viewModel: NotebookViewModel
    @Binding var isShowing: Bool
    @EnvironmentObject var appState: AppState
    
    @State private var inputText = ""
    @State private var messages: [CellAIMessage] = []
    @State private var isLoading = false
    @State private var currentStatus = ""
    @FocusState private var isInputFocused: Bool
    
    // Quick action suggestions
    private var suggestions: [CellAISuggestion] {
        guard let notebook = viewModel.activeNotebook else { return [] }
        var items: [CellAISuggestion] = []
        
        let languages = Set(notebook.cells.filter { $0.type == .code }.map { $0.language })
        
        if languages.contains(.python) {
            items.append(.init(icon: "chart.bar.fill", text: "สร้าง Visualization", color: .blue))
        }
        if languages.count > 1 {
            items.append(.init(icon: "arrow.triangle.merge", text: "รวม Output ทุก Cell", color: .purple))
        }
        items.append(.init(icon: "ladybug.fill", text: "Debug Cell ที่ Error", color: .red))
        items.append(.init(icon: "wand.and.stars", text: "Optimize Code", color: .orange))
        
        return items
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            panelHeader
            
            Divider()
            
            // Context Badge
            cellContextBadge
            
            Divider().opacity(0.5)
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if messages.isEmpty {
                            emptyState
                        } else {
                            ForEach(messages) { msg in
                                CellAIMessageRow(message: msg)
                                    .id(msg.id)
                            }
                        }
                        
                        if isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.45)
                                    .frame(width: 14, height: 14)
                                Text(currentStatus.isEmpty ? "Thinking..." : currentStatus)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.accentColor)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.bottom, 80)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            // Input
            inputBar
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Header
    
    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.fill")
                .font(.system(size: 13))
                .foregroundColor(.accentColor)
            
            Text("AI AGENT")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            
            Spacer()
            
            // Clear
            Button(action: { messages.removeAll() }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear Chat")
            
            // Close
            Button(action: { withAnimation { isShowing = false } }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close AI Panel")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Cell Context Badge
    
    private var cellContextBadge: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let notebook = viewModel.activeNotebook {
                    // Cell count
                    ContextChip(
                        icon: "square.grid.2x2",
                        text: "\(notebook.cells.count) cells",
                        color: .secondary
                    )
                    
                    // Languages used
                    let languages = Set(notebook.cells.filter { $0.type == .code }.map { $0.language })
                    ForEach(Array(languages), id: \.self) { lang in
                        ContextChip(icon: lang.icon, text: lang.rawValue, color: lang.color)
                    }
                    
                    // Selected cell
                    if let selectedId = viewModel.selectedCellId,
                       let cell = notebook.cells.first(where: { $0.id == selectedId }) {
                        ContextChip(
                            icon: "scope",
                            text: "Cell \(notebook.cells.firstIndex(where: { $0.id == selectedId }).map { $0 + 1 } ?? 0)",
                            color: .accentColor
                        )
                        
                        if cell.isExecuting {
                            ContextChip(icon: "bolt.fill", text: "Running", color: .green)
                        }
                        
                        if !cell.output.isEmpty {
                            ContextChip(icon: "text.alignleft", text: "Has Output", color: .cyan)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Color.primary.opacity(0.02))
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)
            
            Image(systemName: "brain.head.profile.fill")
                .font(.system(size: 40))
                .foregroundColor(.accentColor.opacity(0.3))
            
            VStack(spacing: 6) {
                Text("Cell Mode AI")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Ask me to write, debug, or optimize your cells")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Quick Suggestions
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.text) { suggestion in
                    Button(action: { sendSuggestion(suggestion) }) {
                        HStack(spacing: 8) {
                            Image(systemName: suggestion.icon)
                                .font(.system(size: 11))
                                .foregroundColor(suggestion.color)
                                .frame(width: 16)
                            
                            Text(suggestion.text)
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Input Bar
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(alignment: .bottom, spacing: 8) {
                // Context inject button
                Button(action: {}) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Attach context")
                
                // Text input
                if #available(macOS 13.0, *) {
                    TextField("Ask about your cells...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .lineLimit(1...4)
                        .focused($isInputFocused)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isInputFocused ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .onSubmit { sendMessage() }
                } else {
                    TextField("Ask about your cells...", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isInputFocused)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                        .onSubmit { sendMessage() }
                }
                
                // Send
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Build Cell Context
    
    private func buildCellContext() -> String {
        guard let notebook = viewModel.activeNotebook else { return "" }
        
        var context = "## Notebook: \(notebook.name)\n"
        context += "Total cells: \(notebook.cells.count)\n\n"
        
        for (i, cell) in notebook.cells.enumerated() {
            let isSelected = cell.id == viewModel.selectedCellId
            let marker = isSelected ? " ← SELECTED" : ""
            
            context += "### Cell [\(i + 1)] (\(cell.language.rawValue) - \(cell.type.rawValue))\(marker)\n"
            
            // Code content (truncate if too long)
            let code = cell.content
            if code.count > 2000 {
                context += "```\(cell.language.fileExtension)\n\(String(code.prefix(2000)))\n... (truncated)\n```\n"
            } else {
                context += "```\(cell.language.fileExtension)\n\(code)\n```\n"
            }
            
            // Output
            if !cell.output.isEmpty {
                let output = cell.output.count > 1000 ? String(cell.output.prefix(1000)) + "..." : cell.output
                context += "Output:\n```\n\(output)\n```\n"
            }
            
            if cell.isExecuting {
                context += "⚡ Currently executing\n"
            }
            
            context += "\n"
        }
        
        return context
    }
    
    // MARK: - Send Message
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        inputText = ""
        
        // Add user message
        messages.append(CellAIMessage(role: .user, content: text))
        
        // Send to AI with cell context
        isLoading = true
        currentStatus = "Reading cells..."
        
        let cellContext = buildCellContext()
        let provider = StreamableAIProvider(rawValue: appState.aiProvider) ?? .gemini
        let model = appState.aiModel.isEmpty ? provider.defaultModel : appState.aiModel
        let apiKey = appState.apiKeys[appState.aiProvider] ?? ""
        
        let systemPrompt = """
        You are MicroCode Notebook AI — an expert data science and programming assistant embedded in a multi-language notebook IDE.
        
        ## Your Capabilities
        - You can see ALL cells in the notebook (code, output, languages)
        - You understand Python, R, Julia, SQL, Rust, Go, C++, Objective-C, R Markdown, and LaTeX
        - You can write code that works across cells and languages
        - You understand data flow between cells
        
        ## Rules
        1. When writing code, wrap it in proper code blocks with the language identifier
        2. Be concise — notebook users want quick answers
        3. If you suggest code changes, specify which cell number to modify
        4. Consider outputs from previous cells when suggesting code
        5. If user asks to fix an error, look at the cell output for error messages
        6. Use Thai or English based on the user's language
        
        ## Current Notebook State
        \(cellContext)
        """
        
        let responseId = UUID().uuidString
        messages.append(CellAIMessage(id: responseId, role: .assistant, content: ""))
        
        let history: [(role: String, content: String)] = messages.dropLast(2)
            .map { (role: $0.role.rawValue, content: $0.content) }
        
        currentStatus = "Generating..."
        
        AIClient.shared.sendMessage(
            prompt: text,
            attachments: [],
            systemPrompt: systemPrompt,
            conversationHistory: history,
            provider: provider,
            model: model,
            apiKey: apiKey,
            onToken: { token in
                if let idx = self.messages.firstIndex(where: { $0.id == responseId }) {
                    let current = self.messages[idx].content
                    self.messages[idx] = CellAIMessage(
                        id: responseId,
                        role: .assistant,
                        content: current + token
                    )
                }
            },
            onComplete: { _ in
                self.isLoading = false
                self.currentStatus = ""
                // Auto-apply code if response contains cell modifications
                self.tryAutoApply(responseId: responseId)
            },
            onError: { error in
                if let idx = self.messages.firstIndex(where: { $0.id == responseId }) {
                    self.messages[idx] = CellAIMessage(
                        id: responseId,
                        role: .assistant,
                        content: "❌ Error: \(error)"
                    )
                }
                self.isLoading = false
                self.currentStatus = ""
            }
        )
    }
    
    private func sendSuggestion(_ suggestion: CellAISuggestion) {
        inputText = suggestion.text
        sendMessage()
    }
    
    // MARK: - Auto Apply Code to Cells
    
    private func tryAutoApply(responseId: String) {
        guard let msg = messages.first(where: { $0.id == responseId }) else { return }
        
        // Extract code blocks from response
        let pattern = "```([a-zA-Z0-9+#]*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        
        let nsContent = msg.content as NSString
        let matches = regex.matches(in: msg.content, range: NSRange(location: 0, length: nsContent.length))
        
        guard !matches.isEmpty else { return }
        
        // Add apply buttons to message
        // The code blocks are rendered with apply buttons in CellAIMessageRow
    }
}

// MARK: - Models

struct CellAIMessage: Identifiable {
    let id: String
    let role: Role
    var content: String
    let timestamp: Date
    
    enum Role: String {
        case user, assistant
    }
    
    init(id: String = UUID().uuidString, role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

struct CellAISuggestion {
    let icon: String
    let text: String
    let color: Color
}

// MARK: - Context Chip

struct ContextChip: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }
}

// MARK: - Message Row

struct CellAIMessageRow: View {
    let message: CellAIMessage
    
    var body: some View {
        if message.role == .user {
            // User bubble
            HStack {
                Spacer(minLength: 40)
                
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.accentColor)
                    .cornerRadius(12, corners: [.topLeft, .topRight, .bottomLeft])
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        } else {
            // AI response
            VStack(alignment: .leading, spacing: 8) {
                // Parse content into blocks
                let blocks = MessageContentParser.parse(message.content)
                
                ForEach(blocks) { block in
                    switch block {
                    case .text(let text):
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            CellAITextView(text: text)
                        }
                    case .code(let lang, let code):
                        CellAICodeBlockView(language: lang, code: code)
                    case .heading(let level, let content):
                        Text(content)
                            .font(.system(size: level <= 2 ? 15 : 13, weight: .bold))
                            .foregroundColor(.primary)
                    case .list(let items, _):
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(items, id: \.self) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text(item)
                                        .font(.system(size: 12))
                                }
                            }
                        }
                    default:
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Cell AI Text View (Inline Markdown)

struct CellAITextView: View {
    let text: String
    
    var body: some View {
        Text(parseInlineMarkdown(text))
            .font(.system(size: 12.5))
            .foregroundColor(.primary.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
    
    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        // Try to parse as markdown
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        }
        return AttributedString(text)
    }
}

// MARK: - Code Block with Apply Button

struct CellAICodeBlockView: View {
    let language: String
    let code: String
    
    @State private var isCopied = false
    @State private var isApplied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                // Language badge
                if !language.isEmpty {
                    Text(language.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(3)
                }
                
                Spacer()
                
                // Apply to Cell
                Button(action: applyToCell) {
                    HStack(spacing: 4) {
                        Image(systemName: isApplied ? "checkmark.circle.fill" : "arrow.down.doc.fill")
                            .font(.system(size: 10))
                        Text(isApplied ? "Applied" : "Apply to Cell")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(isApplied ? .green : .accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isApplied ? Color.green.opacity(0.1) : Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                
                // Copy
                Button(action: copyCode) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.15))
            
            // Code
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
        .background(Color.black.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isCopied = false }
    }
    
    private func applyToCell() {
        // Send notification to apply code to the selected cell
        NotificationCenter.default.post(
            name: Notification.Name("ApplyCodeToCell"),
            object: nil,
            userInfo: ["code": code, "language": language]
        )
        isApplied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { isApplied = false }
    }
}
