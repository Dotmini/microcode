//
//  ExpandCodeWindow.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import SwiftUI

struct ExpandCodeWindow: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var addErrorHandling: Bool = true
    @State private var addDocumentation: Bool = true
    @State private var addTypeAnnotations: Bool = true
    @State private var expandVariableNames: Bool = true
    @State private var addBestPractices: Bool = true
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        ToolWindowWrapper(
            title: "Expand Code",
            subtitle: "Make your code production-ready",
            icon: "arrow.up.left.and.arrow.down.right",
            iconColor: .blue
        ) {
            // Content
            VStack(alignment: .leading, spacing: 20) {
                Text("Select expansion options to make your code production-ready:")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 16) {
                    OptionToggle(
                        isOn: $addErrorHandling,
                        icon: "exclamationmark.shield",
                        title: "Add Error Handling",
                        description: "Add try-catch blocks and error handling"
                    )
                    
                    OptionToggle(
                        isOn: $addDocumentation,
                        icon: "doc.text",
                        title: "Add Documentation",
                        description: "Add comprehensive documentation comments"
                    )
                    
                    OptionToggle(
                        isOn: $addTypeAnnotations,
                        icon: "textformat",
                        title: "Add Type Annotations",
                        description: "Add type hints where missing"
                    )
                    
                    OptionToggle(
                        isOn: $expandVariableNames,
                        icon: "textformat.abc",
                        title: "Expand Variable Names",
                        description: "Convert abbreviated names to descriptive ones"
                    )
                    
                    OptionToggle(
                        isOn: $addBestPractices,
                        icon: "star",
                        title: "Apply Best Practices",
                        description: "Add logging, validation, and best practices"
                    )
                }
                
                if !errorMessage.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }
                
                Spacer()
            }
            .padding()
        } footer: {
            HStack {
                Text(appState.currentFile?.name ?? "No file selected")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 8)
                    Text("Expanding code...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Button("Expand") {
                    expandCode()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || !anyOptionSelected)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    private var anyOptionSelected: Bool {
        addErrorHandling || addDocumentation || addTypeAnnotations || expandVariableNames || addBestPractices
    }
    
    private func expandCode() {
        guard let file = appState.currentFile else { return }
        
        var instructions = "Expand this code with the following enhancements:\n"
        if addErrorHandling { instructions += "- Add proper error handling\n" }
        if addDocumentation { instructions += "- Add documentation comments\n" }
        if addTypeAnnotations { instructions += "- Add type annotations where missing\n" }
        if expandVariableNames { instructions += "- Expand abbreviated variable names to be more descriptive\n" }
        if addBestPractices { instructions += "- Add any missing best practices\n" }
        instructions += "Keep the same functionality but make it production-ready."
        
        isProcessing = true
        errorMessage = ""
        
        Task {
            do {
                let expanded = try await BackendService.shared.refactorCode(
                    code: file.content,
                    instructions: instructions,
                    provider: appState.aiProvider,
                    model: appState.aiModel,
                    apiKey: appState.apiKeys[appState.aiProvider] ?? ""
                )
                await MainActor.run {
                    appState.updateFileContent(expanded, for: file.id)
                    isProcessing = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to expand code: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }
}

struct OptionToggle: View {
    @Binding var isOn: Bool
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
    }
}
