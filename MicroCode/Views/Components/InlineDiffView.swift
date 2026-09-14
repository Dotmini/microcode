// Copyright © 2025 Dotmini Software. All rights reserved.

import SwiftUI
import Foundation

public struct InlineDiffView: View {
    @Binding var diffResult: DiffResult
    let filePath: String
    let onClose: () -> Void
    
    @State private var currentHunkIndex: Int = 0
    @State private var hoveredHunkId: UUID? = nil
    
    public init(diffResult: Binding<DiffResult>, filePath: String, onClose: @escaping () -> Void) {
        self._diffResult = diffResult
        self.filePath = filePath
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            DiffToolbar(
                diffResult: $diffResult,
                filePath: filePath,
                currentIndex: $currentHunkIndex,
                onClose: onClose
            )
            
            Divider()
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach($diffResult.hunks) { $hunk in
                            DiffHunkRow(hunk: $hunk, isHovered: hoveredHunkId == hunk.id)
                                .id(hunk.id)
                                .onHover { isHovered in
                                    if isHovered {
                                        hoveredHunkId = hunk.id
                                    } else if hoveredHunkId == hunk.id {
                                        hoveredHunkId = nil
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: currentHunkIndex) { newValue in
                    if newValue >= 0 && newValue < diffResult.hunks.count {
                        withAnimation {
                            proxy.scrollTo(diffResult.hunks[newValue].id, anchor: .top)
                        }
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.02))
    }
}

struct DiffToolbar: View {
    @Binding var diffResult: DiffResult
    let filePath: String
    @Binding var currentIndex: Int
    let onClose: () -> Void
    
    var pendingHunksCount: Int {
        diffResult.hunks.filter { $0.status == .pending }.count
    }
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(filePath)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.primary)
                
                DiffSummaryBadge(additions: diffResult.additions, deletions: diffResult.deletions, hunksCount: diffResult.hunks.count)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Text("\(diffResult.hunks.isEmpty ? 0 : currentIndex + 1) of \(diffResult.hunks.count) changes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button(action: {
                    if currentIndex > 0 { currentIndex -= 1 }
                }) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(currentIndex <= 0)
                
                Button(action: {
                    if currentIndex < diffResult.hunks.count - 1 { currentIndex += 1 }
                }) {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.plain)
                .disabled(currentIndex >= diffResult.hunks.count - 1)
                
                Divider().frame(height: 16)
                
                Button(action: acceptAll) {
                    Text("Accept All")
                        .font(.subheadline.bold())
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                
                Button(action: rejectAll) {
                    Text("Reject All")
                        .font(.subheadline.bold())
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                
                Divider().frame(height: 16)
                
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
    }
    
    private func acceptAll() {
        for i in 0..<diffResult.hunks.count {
            if diffResult.hunks[i].status == .pending {
                diffResult.hunks[i].status = .accepted
            }
        }
    }
    
    private func rejectAll() {
        for i in 0..<diffResult.hunks.count {
            if diffResult.hunks[i].status == .pending {
                diffResult.hunks[i].status = .rejected
            }
        }
    }
}

struct DiffSummaryBadge: View {
    let additions: Int
    let deletions: Int
    let hunksCount: Int
    
    var body: some View {
        HStack(spacing: 6) {
            Text("+\(additions)")
                .foregroundColor(.green)
            Text("-\(deletions)")
                .foregroundColor(.red)
            Text("lines • \(hunksCount) hunks")
                .foregroundColor(.secondary)
        }
        .font(.caption)
    }
}

struct DiffHunkRow: View {
    @Binding var hunk: DiffHunk
    let isHovered: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(hunkHeaderTitle)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if isHovered || hunk.status != .pending {
                    HStack(spacing: 8) {
                        if hunk.status == .accepted {
                            Text("Accepted")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(4)
                        } else if hunk.status == .rejected {
                            Text("Rejected")
                                .font(.caption.bold())
                                .foregroundColor(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.2))
                                .cornerRadius(4)
                        } else {
                            Button(action: { hunk.status = .accepted }) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { hunk.status = .rejected }) {
                                Image(systemName: "xmark")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("Pending")
                        .font(.caption.bold())
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05))
            
            // Content
            VStack(spacing: 0) {
                // Deletions
                ForEach(Array(hunk.oldLines.enumerated()), id: \.offset) { index, line in
                    DiffLineView(
                        lineNumber: hunk.oldRange.lowerBound + index,
                        prefix: "-",
                        content: line,
                        type: .deletion,
                        status: hunk.status
                    )
                }
                
                // Additions
                ForEach(Array(hunk.newLines.enumerated()), id: \.offset) { index, line in
                    DiffLineView(
                        lineNumber: hunk.newRange.lowerBound + index,
                        prefix: "+",
                        content: line,
                        type: .addition,
                        status: hunk.status
                    )
                }
            }
            .background(Color.primary.opacity(0.02))
        }
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }
    
    private var hunkHeaderTitle: String {
        "@@ -\(hunk.oldRange.lowerBound),\(hunk.oldRange.count) +\(hunk.newRange.lowerBound),\(hunk.newRange.count) @@"
    }
    
    private var borderColor: Color {
        switch hunk.status {
        case .accepted: return Color.green.opacity(0.3)
        case .rejected: return Color.red.opacity(0.3)
        case .pending: return isHovered ? Color.primary.opacity(0.2) : Color.primary.opacity(0.1)
        }
    }
}

enum DiffLineType {
    case addition
    case deletion
    case context
}

struct DiffLineView: View {
    let lineNumber: Int?
    let prefix: String
    let content: String
    let type: DiffLineType
    let status: HunkStatus
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Gutter
            HStack(spacing: 4) {
                Text(lineNumber.map { String($0) } ?? " ")
                    .frame(width: 40, alignment: .trailing)
                    .foregroundColor(.secondary)
                
                Text(prefix)
                    .frame(width: 16, alignment: .center)
                    .foregroundColor(prefixColor)
            }
            .font(.system(.body, design: .monospaced))
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(Color.primary.opacity(0.03))
            
            // Code
            Text(content.isEmpty ? " " : content)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(textColor)
                .padding(.vertical, 2)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(lineBackgroundColor)
        }
    }
    
    private var prefixColor: Color {
        switch type {
        case .addition: return .green
        case .deletion: return .red
        case .context: return .secondary
        }
    }
    
    private var textColor: Color {
        if status == .rejected && type == .addition { return .secondary.opacity(0.5) }
        if status == .accepted && type == .deletion { return .secondary.opacity(0.5) }
        return .primary
    }
    
    private var lineBackgroundColor: Color {
        switch type {
        case .addition: return Color.green.opacity(0.08)
        case .deletion: return Color.red.opacity(0.08)
        case .context: return .clear
        }
    }
}
