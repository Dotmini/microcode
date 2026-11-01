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
        let theme = AppState.shared?.appTheme ?? .dark
        let editorCanvas = theme.isGlass ? Color.clear : Color(nsColor: theme.editorBackground)

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
                    LazyVStack(alignment: .leading, spacing: 12) {
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
        .background(editorCanvas)
    }
}

struct DiffToolbar: View {
    @Binding var diffResult: DiffResult
    let filePath: String
    @Binding var currentIndex: Int
    let onClose: () -> Void
    @State private var isHoveringClose: Bool = false
    
    var pendingHunksCount: Int {
        diffResult.hunks.filter { $0.status == .pending }.count
    }
    
    var body: some View {
        let theme = AppState.shared?.appTheme ?? .dark
        let panelBg = theme.isGlass ? Color.primary.opacity(0.05) : Color(nsColor: theme.panelBackground)

        HStack(spacing: 10) {
            ProgrammingLanguageIconView(
                fileName: URL(fileURLWithPath: filePath).lastPathComponent,
                size: 15
            )
            
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: filePath).lastPathComponent)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.primary)
                
                DiffSummaryBadge(additions: diffResult.additions, deletions: diffResult.deletions, hunksCount: diffResult.hunks.count)
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                Text("\(diffResult.hunks.isEmpty ? 0 : currentIndex + 1) / \(diffResult.hunks.count)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Button(action: {
                    if currentIndex > 0 { currentIndex -= 1 }
                }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(currentIndex <= 0)
                
                Button(action: {
                    if currentIndex < diffResult.hunks.count - 1 { currentIndex += 1 }
                }) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(currentIndex >= diffResult.hunks.count - 1)
                
                Divider().frame(height: 14)
                
                Button(action: acceptAll) {
                    Text("Accept All")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.14))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                
                Button(action: rejectAll) {
                    Text("Reject All")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.14))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                
                Divider().frame(height: 14)
                
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isHoveringClose ? .white : .secondary)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isHoveringClose ? Color.red.opacity(0.85) : Color.primary.opacity(0.07))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHoveringClose = $0 }
                .help("Close Hunk Review")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(panelBg)
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
        HStack(spacing: 5) {
            Text("+\(additions)")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(.green)
            Text("-\(deletions)")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(.red)
            Text("• \(hunksCount) hunks")
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
        }
    }
}

struct DiffHunkRow: View {
    @Binding var hunk: DiffHunk
    let isHovered: Bool
    @State private var hunkViewportWidth: CGFloat = 0
    
    var body: some View {
        let theme = AppState.shared?.appTheme ?? .dark
        let headerBg = theme.isGlass ? Color.primary.opacity(0.05) : Color(nsColor: theme.panelBackground)
        let editorCanvas = theme.isGlass ? Color.clear : Color(nsColor: theme.editorBackground)
        let maxChars = max(
            hunk.oldLines.reduce(0) { max($0, $1.replacingOccurrences(of: "\t", with: "    ").count) },
            hunk.newLines.reduce(0) { max($0, $1.replacingOccurrences(of: "\t", with: "    ").count) }
        )
        let minRowWidth = max(hunkViewportWidth, CGFloat(min(maxChars, 320)) * 7.2 + 96)

        VStack(spacing: 0) {
            // Header
            HStack {
                Text(hunkHeaderTitle)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.9))
                
                Spacer()
                
                if isHovered || hunk.status != .pending {
                    HStack(spacing: 8) {
                        if hunk.status == .accepted {
                            Text("Accepted")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.18))
                                .cornerRadius(4)
                        } else if hunk.status == .rejected {
                            Text("Rejected")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.18))
                                .cornerRadius(4)
                        } else {
                            Button(action: { hunk.status = .accepted }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark")
                                    Text("Accept")
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.14))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { hunk.status = .rejected }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "xmark")
                                    Text("Reject")
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.14))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("Pending")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.16))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(headerBg)
            
            Divider().opacity(0.35)

            // Content (Horizontal Scroll with Edge-to-Edge Row Backgrounds)
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    // Deletions
                    ForEach(Array(hunk.oldLines.enumerated()), id: \.offset) { index, line in
                        DiffLineView(
                            lineNumber: hunk.oldRange.lowerBound + index,
                            prefix: "-",
                            content: line,
                            type: .deletion,
                            status: hunk.status,
                            minRowWidth: minRowWidth,
                            theme: theme
                        )
                    }
                    
                    // Additions
                    ForEach(Array(hunk.newLines.enumerated()), id: \.offset) { index, line in
                        DiffLineView(
                            lineNumber: hunk.newRange.lowerBound + index,
                            prefix: "+",
                            content: line,
                            type: .addition,
                            status: hunk.status,
                            minRowWidth: minRowWidth,
                            theme: theme
                        )
                    }
                }
                .frame(minWidth: minRowWidth, alignment: .leading)
                .padding(.vertical, 2)
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { hunkViewportWidth = geo.size.width }
                        .onChange(of: geo.size.width) { newW in hunkViewportWidth = newW }
                }
            )
            .background(editorCanvas)
        }
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 1)
        )
        .padding(.horizontal, 10)
    }
    
    private var hunkHeaderTitle: String {
        "@@ -\(hunk.oldRange.lowerBound),\(hunk.oldRange.count) +\(hunk.newRange.lowerBound),\(hunk.newRange.count) @@"
    }
    
    private var borderColor: Color {
        switch hunk.status {
        case .accepted: return Color.green.opacity(0.35)
        case .rejected: return Color.red.opacity(0.35)
        case .pending: return isHovered ? Color.primary.opacity(0.22) : Color.primary.opacity(0.13)
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
    let minRowWidth: CGFloat
    let theme: AppTheme
    
    var body: some View {
        let expanded = content
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "    ")
        let lineNumColor = Color(nsColor: theme.commentColor).opacity(0.75)

        HStack(spacing: 0) {
            Rectangle()
                .fill(accentStripColor)
                .frame(width: 2.5, height: 19)

            Text(lineNumber.map { String($0) } ?? "")
                .font(.system(size: 10.5, design: .monospaced))
                .frame(width: 38, alignment: .trailing)
                .padding(.trailing, 5)
                .foregroundColor(lineNumColor)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1, height: 19)
            
            Text(prefix)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .frame(width: 18, alignment: .center)
                .foregroundColor(prefixColor)
            
            Text(expanded.isEmpty ? " " : expanded)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(textColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, 20)

            Spacer(minLength: 0)
        }
        .frame(minWidth: minRowWidth, minHeight: 19, maxHeight: 19, alignment: .leading)
        .background(lineBackgroundColor)
    }

    private var accentStripColor: Color {
        switch type {
        case .addition: return .green
        case .deletion: return .red
        case .context: return .clear
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
        let base = Color(nsColor: theme.editorText)
        if status == .rejected && type == .addition { return base.opacity(0.45) }
        if status == .accepted && type == .deletion { return base.opacity(0.45) }
        if type == .deletion { return base.opacity(0.76) }
        return base
    }
    
    private var lineBackgroundColor: Color {
        switch type {
        case .addition: return Color.green.opacity(theme.isDark ? 0.15 : 0.12)
        case .deletion: return Color.red.opacity(theme.isDark ? 0.14 : 0.10)
        case .context: return .clear
        }
    }
}
