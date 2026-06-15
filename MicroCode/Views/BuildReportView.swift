//
//  BuildReportView.swift
//  MicroCode
//
//  Created by Antigravity on 2026.
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import SwiftUI

struct BuildReportView: View {
    @ObservedObject var parser: XcodeBuildParser
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    var isEmbedded: Bool = false
    @State private var selectedFilter: Int = 0 // 0: All, 1: Errors, 2: Warnings
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (Only show if not embedded)
            if !isEmbedded {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Xcode Build Report")
                            .font(.headline)
                        
                        if !parser.currentTarget.isEmpty {
                            Text("Target: \(parser.currentTarget)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Status Badges
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("\(parser.totalErrorsCount) Errors")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(6)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text("\(parser.totalWarningsCount) Warnings")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.15))
                        .cornerRadius(6)
                    }
                    
                    Spacer().frame(width: 20)
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()
            }
            
            // Filter Bar
            HStack {
                Picker("", selection: $selectedFilter) {
                    Text("All (\(parser.issues.count))").tag(0)
                    Text("Errors Only (\(parser.totalErrorsCount))").tag(1)
                    Text("Warnings Only (\(parser.totalWarningsCount))").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                
                Spacer()
                
                if !parser.currentFileCompiling.isEmpty {
                    Text("Compiling: \(parser.currentFileCompiling)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Issues List
            if filteredIssues.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("No Build Issues Found")
                        .font(.headline)
                    Text("Your project compiled successfully without any errors or warnings.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                List {
                    ForEach(filteredIssues) { issue in
                        BuildIssueRow(issue: issue) {
                            selectIssue(issue)
                        }
                    }
                }
                .listStyle(.inset)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .frame(width: 750, height: 500)
    }
    
    private var filteredIssues: [XcodeBuildIssue] {
        switch selectedFilter {
        case 1:
            return parser.issues.filter { $0.isError }
        case 2:
            return parser.issues.filter { !$0.isError }
        default:
            return parser.issues
        }
    }
    
    private func selectIssue(_ issue: XcodeBuildIssue) {
        let fileURL = URL(fileURLWithPath: issue.filePath)
        
        Task {
            // 1. Open the file in the editor
            await appState.loadFile(url: fileURL)
            
            // 2. Give SwiftUI / NSTextView a brief moment to instantiate before navigating
            try? await Task.sleep(nanoseconds: 150_000_000)
            
            // 3. Post notification to jump to the specific line
            NotificationCenter.default.post(
                name: Notification.Name("JumpToLineNotification"),
                object: nil,
                userInfo: [
                    "line": issue.line,
                    "column": issue.column
                ]
            )
            
            // 4. Close the build report popup
            dismiss()
        }
    }
}

struct BuildIssueRow: View {
    let issue: XcodeBuildIssue
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                // Indicator Icon
                Image(systemName: issue.isError ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(issue.isError ? .red : .yellow)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Message
                    Text(issue.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    // Location info
                    HStack(spacing: 6) {
                        Text(issue.fileName)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Text("Line \(issue.line), Col \(issue.column)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                        
                        Spacer()
                        
                        // Relative folder/path
                        Text(relativeDirectory(for: issue.filePath))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.secondary.opacity(0.08) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private func relativeDirectory(for filePath: String) -> String {
        let url = URL(fileURLWithPath: filePath)
        let directory = url.deletingLastPathComponent().path
        
        // Return last 2 components of path for clarity
        let components = directory.components(separatedBy: "/")
        if components.count >= 2 {
            return ".../" + components.suffix(2).joined(separator: "/")
        }
        return directory
    }
}
