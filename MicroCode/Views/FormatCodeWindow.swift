//
//  FormatCodeWindow.swift
//  MicroCode
//
//  Code formatting with style selection
//

import SwiftUI

struct FormatCodeWindow: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedStyle: FormatStyle = .standard
    @State private var indentSize: Int = 4
    @State private var useSpaces: Bool = true
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String = ""
    
    // AI Ultra Memory
    @AppStorage("aiFormatInstructions") private var aiInstructions: String = "Sort imports, use 4 spaces indentation, and fix linting issues."
    
    enum FormatStyle: String, CaseIterable {
        case standard = "Standard"
        case google = "Google Style"
        case airbnb = "Airbnb Style"
        case prettier = "Prettier"
        case black = "Black (Python)"
        case swiftformat = "SwiftFormat"
        case aiUltra = "AI Ultra"

        
        var description: String {
            switch self {
            case .standard: return "Language default formatting"
            case .google: return "Google's style guide"
            case .airbnb: return "Airbnb JavaScript guide"
            case .prettier: return "Prettier default config"
            case .black: return "Black formatter for Python"
            case .swiftformat: return "SwiftFormat defaults"
            case .aiUltra: return "AI-powered formatting with memory"
            }

        }
        
        var icon: String {
            switch self {
            case .standard: return "text.alignleft"
            case .google: return "g.circle"
            case .airbnb: return "airplane"
            case .prettier: return "sparkles"
            case .black: return "paintbrush.fill"
            case .swiftformat: return "swift"
            case .aiUltra: return "brain.head.profile"
            }

        }
    }
    
    var body: some View {
        ToolWindowWrapper(
            title: "Format Code",
            subtitle: "Language-specific code formatting",
            icon: "paintbrush.fill",
            iconColor: .green
        ) {
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Style Selection
                    styleSection
                    
                    // AI Ultra Instructions (Memory)
                    if selectedStyle == .aiUltra {
                        aiUltraSection
                    }

                    
                    // Indentation Settings
                    indentationSection
                    
                    // Options
                    optionsSection
                    
                    // Error Message
                    if !errorMessage.isEmpty {
                        errorView
                    }
                }
                .padding(20)
            }
        } footer: {
            HStack {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Formatting...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Format") {
                    formatCode()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || appState.currentFile == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    // MARK: - Style Section
    
    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Formatting Style", systemImage: "wand.and.stars")
                .font(.subheadline.weight(.semibold))
            
            // Style Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                ForEach(FormatStyle.allCases, id: \.self) { style in
                    StyleCard(
                        style: style,
                        isSelected: selectedStyle == style
                    ) {
                        selectedStyle = style
                    }
                }
            }
        }
    }
    
    // MARK: - AI Ultra Section (Memory)
    
    private var aiUltraSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("AI Instructions (Memory)", systemImage: "brain.head.profile")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.purple)
                
                Text("Instructions are saved automatically for future use.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $aiInstructions)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(height: 80)
                    .padding(4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Indentation Section
    
    private var indentationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Indentation & Auto-Save", systemImage: "increase.indent")
                    .font(.subheadline.weight(.semibold))
                
                HStack {
                    Text("Indent Size")
                        .font(.system(size: 13))
                    
                    Spacer()
                    
                    Stepper("\(indentSize) spaces", value: $indentSize, in: 2...8)
                        .font(.system(size: 13))
                }
                
                Toggle("Use Spaces (instead of tabs)", isOn: $useSpaces)
                    .font(.system(size: 13))
                
                Divider()
                
                Toggle("Auto-format on Save", isOn: $appState.autoFormatOnSave)
                    .font(.system(size: 13))
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Options Section
    
    private var optionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Options", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                
                ForEach([
                    ("checkmark.circle.fill", "Remove trailing whitespace", Color.green),
                    ("checkmark.circle.fill", "Ensure final newline", Color.green),
                    ("checkmark.circle.fill", "Normalize line endings", Color.green)
                ], id: \.1) { icon, text, color in
                    HStack {
                        Image(systemName: icon)
                            .foregroundColor(color)
                            .font(.system(size: 12))
                        Text(text)
                            .font(.system(size: 13))
                        Spacer()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Error View
    
    private var errorView: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(errorMessage)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Formatting...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            
            Button("Format") {
                formatCode()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing || appState.currentFile == nil)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func formatCode() {
        guard let file = appState.currentFile else { return }
        
        isProcessing = true
        errorMessage = ""
        
        Task {
            do {
                let formatted: String
                if selectedStyle == .aiUltra {
                    formatted = try await BackendService.shared.formatCodeAI(
                        code: file.content,
                        language: file.language,
                        instructions: aiInstructions
                    )
                } else {
                    formatted = try await BackendService.shared.formatCode(
                        code: file.content,
                        language: file.language
                    )
                }

                await MainActor.run {
                    appState.updateFileContent(formatted, for: file.id)
                    isProcessing = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to format: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - Style Card

struct StyleCard: View {
    let style: FormatCodeWindow.FormatStyle
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: style.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .white : .accentColor)
                
                Text(style.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
