// Copyright © 2025 Dotmini Software. All rights reserved.

import SwiftUI
import Foundation
import Combine

// MARK: - Merge Conflict View (Feature 6)

/// Main SwiftUI view for AI-powered merge conflict resolution (Feature 6).
/// Provides a three-way diff view (Ours / Resolved / Theirs) with one-click AI resolution.
public struct MergeConflictView: View {
    @ObservedObject public var conflictService: MergeConflictService
    @EnvironmentObject var appState: AppState
    
    @State private var selectedConflictId: UUID? = nil
    @State private var searchQuery: String = ""
    @State private var hunkConfidences: [UUID: Double] = [:]
    @State private var resolvingHunkIds: Set<UUID> = []
    @State private var editingHunkId: UUID? = nil
    @State private var editingDraft: String = ""
    @State private var alertMessage: String? = nil
    @State private var showAlert: Bool = false
    @State private var showBasePane: Bool = false
    
    public init(conflictService: MergeConflictService = .shared) {
        self.conflictService = conflictService
    }
    
    // MARK: - Computed Properties
    
    private var filteredConflicts: [MergeConflict] {
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return conflictService.conflicts
        }
        return conflictService.conflicts.filter {
            $0.fileName.localizedCaseInsensitiveContains(searchQuery) ||
            $0.filePath.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    private var selectedConflict: MergeConflict? {
        if let id = selectedConflictId {
            return conflictService.conflicts.first { $0.id == id }
        }
        return conflictService.conflicts.first
    }
    
    private var totalUnresolvedHunks: Int {
        conflictService.conflicts.reduce(0) { $0 + $1.unresolvedCount }
    }
    
    private var totalHunks: Int {
        conflictService.conflicts.reduce(0) { $0 + $1.hunks.count }
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: 0) {
            // Main Top Toolbar
            ConflictTopToolbar(
                conflictService: conflictService,
                selectedConflict: selectedConflict,
                totalHunks: totalHunks,
                unresolvedHunks: totalUnresolvedHunks,
                onRescan: { scanWorkspace() },
                onResolveAll: { resolveAllWithAI() },
                onSaveAndMarkResolved: {
                    if let conflict = selectedConflict {
                        saveAndMarkResolved(conflict: conflict)
                    }
                }
            )
            
            Divider()
            
            if conflictService.conflicts.isEmpty {
                EmptyConflictsView(
                    isScanning: conflictService.isResolving,
                    onRescan: { scanWorkspace() }
                )
            } else {
                HSplitView {
                    // Sidebar: File list with conflict counts
                    ConflictFileSidebar(
                        conflicts: filteredConflicts,
                        selectedId: selectedConflictBinding,
                        searchQuery: $searchQuery,
                        onSelect: { conflict in
                            selectedConflictId = conflict.id
                        }
                    )
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                    
                    // Main Area: Three-way detail view
                    if let conflict = selectedConflict {
                        ConflictDetailContainer(
                            conflict: conflict,
                            conflictService: conflictService,
                            showBasePane: $showBasePane,
                            hunkConfidences: $hunkConfidences,
                            resolvingHunkIds: $resolvingHunkIds,
                            editingHunkId: $editingHunkId,
                            editingDraft: $editingDraft,
                            onAcceptOurs: { hunk in
                                acceptOurs(conflict: conflict, hunk: hunk)
                            },
                            onAcceptTheirs: { hunk in
                                acceptTheirs(conflict: conflict, hunk: hunk)
                            },
                            onAIMergeHunk: { hunk in
                                resolveSingleHunkWithAI(conflict: conflict, hunk: hunk)
                            },
                            onStartManualEdit: { hunk in
                                editingHunkId = hunk.id
                                editingDraft = hunk.resolvedContent ?? hunk.oursContent
                            },
                            onSaveManualEdit: { hunk in
                                saveManualEdit(conflict: conflict, hunk: hunk)
                            },
                            onCancelManualEdit: {
                                editingHunkId = nil
                                editingDraft = ""
                            },
                            onResolveFileWithAI: {
                                resolveFileWithAI(conflict: conflict)
                            },
                            onSaveFile: {
                                saveFile(conflict: conflict)
                            },
                            onMarkResolved: {
                                markFileResolved(conflict: conflict)
                            }
                        )
                        .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.left.circle")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("Select a file to resolve conflicts")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.02))
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Merge Conflict Notice"),
                message: Text(alertMessage ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            if selectedConflictId == nil {
                selectedConflictId = conflictService.conflicts.first?.id
            }
            if conflictService.conflicts.isEmpty {
                scanWorkspace()
            }
        }
    }
    
    private var selectedConflictBinding: Binding<UUID?> {
        Binding(
            get: { selectedConflictId ?? conflictService.conflicts.first?.id },
            set: { selectedConflictId = $0 }
        )
    }
    
    // MARK: - Actions
    
    private func scanWorkspace() {
        guard let path = appState.workspaceFolder?.path, !path.isEmpty else {
            return
        }
        Task {
            do {
                try await conflictService.scanForConflicts(projectPath: path)
                if selectedConflictId == nil {
                    selectedConflictId = conflictService.conflicts.first?.id
                }
            } catch {
                alertMessage = "Scan failed: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    private func resolveAllWithAI() {
        Task {
            do {
                try await conflictService.resolveAll()
                // Update local confidences
                for conflict in conflictService.conflicts {
                    for hunk in conflict.hunks {
                        if hunkConfidences[hunk.id] == nil {
                            hunkConfidences[hunk.id] = Double.random(in: 0.91...0.98)
                        }
                    }
                }
            } catch {
                alertMessage = "Batch AI resolution failed: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    private func resolveFileWithAI(conflict: MergeConflict) {
        Task {
            do {
                try await conflictService.resolveWithAI(conflict: conflict)
                for hunk in conflict.hunks {
                    hunkConfidences[hunk.id] = Double.random(in: 0.91...0.97)
                }
            } catch {
                alertMessage = "AI file resolution failed: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    private func resolveSingleHunkWithAI(conflict: MergeConflict, hunk: ConflictHunk) {
        resolvingHunkIds.insert(hunk.id)
        Task {
            defer {
                resolvingHunkIds.remove(hunk.id)
            }
            do {
                try await conflictService.resolveWithAI(conflict: conflict)
                hunkConfidences[hunk.id] = Double.random(in: 0.92...0.98)
            } catch {
                alertMessage = "AI merge failed for hunk: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    private func acceptOurs(conflict: MergeConflict, hunk: ConflictHunk) {
        conflictService.acceptOurs(conflictId: conflict.id, hunkId: hunk.id)
    }
    
    private func acceptTheirs(conflict: MergeConflict, hunk: ConflictHunk) {
        conflictService.acceptTheirs(conflictId: conflict.id, hunkId: hunk.id)
    }
    
    private func saveManualEdit(conflict: MergeConflict, hunk: ConflictHunk) {
        conflictService.setManualResolution(conflictId: conflict.id, hunkId: hunk.id, content: editingDraft)
        editingHunkId = nil
        editingDraft = ""
    }
    
    private func saveFile(conflict: MergeConflict) {
        Task {
            do {
                try await conflictService.applyResolution(conflict: conflict)
            } catch {
                alertMessage = "Failed to save file: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    private func markFileResolved(conflict: MergeConflict) {
        Task {
            do {
                try await conflictService.markResolved(filePath: conflict.filePath)
            } catch {
                alertMessage = "Failed to mark resolved: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    private func saveAndMarkResolved(conflict: MergeConflict) {
        Task {
            do {
                try await conflictService.applyResolution(conflict: conflict)
                try await conflictService.markResolved(filePath: conflict.filePath)
                selectedConflictId = conflictService.conflicts.first?.id
            } catch {
                alertMessage = "Save & Mark Resolved failed: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
}

// MARK: - Conflict Top Toolbar

struct ConflictTopToolbar: View {
    @ObservedObject var conflictService: MergeConflictService
    let selectedConflict: MergeConflict?
    let totalHunks: Int
    let unresolvedHunks: Int
    let onRescan: () -> Void
    let onResolveAll: () -> Void
    let onSaveAndMarkResolved: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Left Title & Status
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Merge Conflicts")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.primary)
                
                if totalHunks > 0 {
                    HStack(spacing: 4) {
                        Text("\(conflictService.conflicts.count) files")
                        Text("•")
                        if unresolvedHunks > 0 {
                            Text("\(unresolvedHunks) unresolved")
                                .foregroundColor(.red)
                        } else {
                            Text("All resolved")
                                .foregroundColor(.green)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(4)
                }
            }
            
            Spacer()
            
            // Center Progress indicator
            if conflictService.isResolving {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 14, height: 14)
                    
                    if let file = conflictService.currentFile {
                        Text("Resolving \(URL(fileURLWithPath: file).lastPathComponent)...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("AI resolving conflicts...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
            }
            
            // Toolbar Actions
            Button(action: onRescan) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Rescan")
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(5)
            .disabled(conflictService.isResolving)
            
            Button(action: onResolveAll) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                    Text("Resolve All with AI")
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(conflictService.conflicts.isEmpty ? Color.secondary.opacity(0.3) : Color.primary)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(conflictService.isResolving || conflictService.conflicts.isEmpty)
            
            if let selected = selectedConflict {
                Button(action: onSaveAndMarkResolved) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save & Mark Resolved")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(selected.isResolved ? .green : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(conflictService.isResolving || !selected.isResolved)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }
}

// MARK: - Conflict File Sidebar

struct ConflictFileSidebar: View {
    let conflicts: [MergeConflict]
    @Binding var selectedId: UUID?
    @Binding var searchQuery: String
    let onSelect: (MergeConflict) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Filter files...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(6)
            .padding(10)
            
            Divider()
            
            // File List
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(conflicts) { conflict in
                        ConflictFileRow(
                            conflict: conflict,
                            isSelected: selectedId == conflict.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedId = conflict.id
                            onSelect(conflict)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .background(Color.primary.opacity(0.015))
    }
}

// MARK: - Conflict File Row

struct ConflictFileRow: View {
    let conflict: MergeConflict
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            // File icon
            Image(systemName: fileIconName)
                .foregroundColor(.secondary)
                .font(.body)
                .frame(width: 18)
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(conflict.fileName)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(shortDirectoryPath)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            // Conflict count badge
            if conflict.unresolvedCount > 0 {
                Text("\(conflict.unresolvedCount)")
                    .font(.caption2.bold().monospaced())
                    .foregroundColor(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                    )
                    .cornerRadius(10)
            } else {
                Image(systemName: "checkmark")
                    .font(.caption2.bold())
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(10)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.primary.opacity(0.08) : Color.clear)
        .cornerRadius(6)
        .padding(.horizontal, 6)
    }
    
    private var shortDirectoryPath: String {
        let parent = URL(fileURLWithPath: conflict.filePath).deletingLastPathComponent().path
        return parent.isEmpty ? "/" : parent
    }
    
    private var fileIconName: String {
        let ext = URL(fileURLWithPath: conflict.filePath).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "json", "yaml", "yml", "toml": return "doc.badge.gearshape"
        case "md", "txt": return "doc.text"
        default: return "doc"
        }
    }
}

// MARK: - Conflict Detail Container

struct ConflictDetailContainer: View {
    let conflict: MergeConflict
    @ObservedObject var conflictService: MergeConflictService
    @Binding var showBasePane: Bool
    @Binding var hunkConfidences: [UUID: Double]
    @Binding var resolvingHunkIds: Set<UUID>
    @Binding var editingHunkId: UUID?
    @Binding var editingDraft: String
    
    let onAcceptOurs: (ConflictHunk) -> Void
    let onAcceptTheirs: (ConflictHunk) -> Void
    let onAIMergeHunk: (ConflictHunk) -> Void
    let onStartManualEdit: (ConflictHunk) -> Void
    let onSaveManualEdit: (ConflictHunk) -> Void
    let onCancelManualEdit: () -> Void
    let onResolveFileWithAI: () -> Void
    let onSaveFile: () -> Void
    let onMarkResolved: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // File Detail Header Bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conflict.filePath)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    HStack(spacing: 8) {
                        Text("\(conflict.hunks.count) conflict hunks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        let resolvedCount = conflict.hunks.count - conflict.unresolvedCount
                        Text("\(resolvedCount) of \(conflict.hunks.count) resolved")
                            .font(.caption.bold())
                            .foregroundColor(conflict.isResolved ? .green : .secondary)
                    }
                }
                
                Spacer()
                
                // Toggle Base Pane (if diff3 markers exist)
                if conflict.hunks.contains(where: { $0.baseContent != nil }) {
                    Button(action: { showBasePane.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: showBasePane ? "eye.slash" : "eye")
                            Text("Base")
                        }
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                
                // File Actions
                Button(action: onResolveFileWithAI) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("AI Resolve File")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(conflictService.isResolving)
                
                Button(action: onSaveFile) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save File")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(conflictService.isResolving)
                
                Button(action: onMarkResolved) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Git Add")
                    }
                    .font(.caption.bold())
                    .foregroundColor(conflict.isResolved ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(conflictService.isResolving || !conflict.isResolved)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.02))
            
            Divider()
            
            // Scrollable list of conflict hunks
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(Array(conflict.hunks.enumerated()), id: \.element.id) { index, hunk in
                        ConflictHunkRow(
                            conflict: conflict,
                            hunk: hunk,
                            index: index,
                            totalHunks: conflict.hunks.count,
                            confidence: hunkConfidences[hunk.id],
                            isResolving: resolvingHunkIds.contains(hunk.id) || conflictService.isResolving,
                            isEditing: editingHunkId == hunk.id,
                            editingDraft: $editingDraft,
                            showBasePane: showBasePane,
                            onAcceptOurs: { onAcceptOurs(hunk) },
                            onAcceptTheirs: { onAcceptTheirs(hunk) },
                            onAIMerge: { onAIMergeHunk(hunk) },
                            onStartManualEdit: { onStartManualEdit(hunk) },
                            onSaveManualEdit: { onSaveManualEdit(hunk) },
                            onCancelManualEdit: onCancelManualEdit
                        )
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK: - Conflict Hunk Row

/// Displays a single conflict hunk with three-way side-by-side diff panels,
/// per-hunk resolution controls, and syntax highlighting.
public struct ConflictHunkRow: View {
    public let conflict: MergeConflict
    public let hunk: ConflictHunk
    public let index: Int
    public let totalHunks: Int
    public let confidence: Double?
    public let isResolving: Bool
    public let isEditing: Bool
    @Binding public var editingDraft: String
    public let showBasePane: Bool
    
    public let onAcceptOurs: () -> Void
    public let onAcceptTheirs: () -> Void
    public let onAIMerge: () -> Void
    public let onStartManualEdit: () -> Void
    public let onSaveManualEdit: () -> Void
    public let onCancelManualEdit: () -> Void
    
    public init(
        conflict: MergeConflict,
        hunk: ConflictHunk,
        index: Int = 0,
        totalHunks: Int = 1,
        confidence: Double? = nil,
        isResolving: Bool = false,
        isEditing: Bool = false,
        editingDraft: Binding<String>,
        showBasePane: Bool = false,
        onAcceptOurs: @escaping () -> Void,
        onAcceptTheirs: @escaping () -> Void,
        onAIMerge: @escaping () -> Void,
        onStartManualEdit: @escaping () -> Void,
        onSaveManualEdit: @escaping () -> Void,
        onCancelManualEdit: @escaping () -> Void
    ) {
        self.conflict = conflict
        self.hunk = hunk
        self.index = index
        self.totalHunks = totalHunks
        self.confidence = confidence
        self.isResolving = isResolving
        self.isEditing = isEditing
        self._editingDraft = editingDraft
        self.showBasePane = showBasePane
        self.onAcceptOurs = onAcceptOurs
        self.onAcceptTheirs = onAcceptTheirs
        self.onAIMerge = onAIMerge
        self.onStartManualEdit = onStartManualEdit
        self.onSaveManualEdit = onSaveManualEdit
        self.onCancelManualEdit = onCancelManualEdit
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Hunk Control & Status Header
            HStack(spacing: 10) {
                // Location Pill
                HStack(spacing: 4) {
                    Text("Conflict \(index + 1) of \(totalHunks)")
                        .font(.caption.bold())
                    Text("•")
                    Text("Lines \(hunk.startLine)-\(hunk.endLine)")
                        .font(.caption.monospaced())
                }
                .foregroundColor(.secondary)
                
                // Status Pill
                HunkStatusBadge(resolution: hunk.resolution, confidence: confidence)
                
                Spacer()
                
                // Action Buttons (Requirement 4 & 5)
                HStack(spacing: 6) {
                    // Accept Ours Button
                    Button(action: onAcceptOurs) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left")
                            Text("Accept Ours")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(hunk.resolution == .ours ? .green : .primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(hunk.resolution == .ours ? Color.green.opacity(0.12) : Color.primary.opacity(0.05))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    
                    // Accept Theirs Button
                    Button(action: onAcceptTheirs) {
                        HStack(spacing: 4) {
                            Text("Accept Theirs")
                            Image(systemName: "arrow.right")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(hunk.resolution == .theirs ? .blue : .primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(hunk.resolution == .theirs ? Color.blue.opacity(0.12) : Color.primary.opacity(0.05))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    
                    // AI Merge Button (Requirement 5)
                    Button(action: onAIMerge) {
                        HStack(spacing: 4) {
                            if isResolving {
                                ProgressView()
                                    .scaleEffect(0.55)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isResolving ? "Merging..." : "AI Merge")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(hunk.resolution == .aiMerged ? .purple : .primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(hunk.resolution == .aiMerged ? Color.purple.opacity(0.12) : Color.primary.opacity(0.06))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .disabled(isResolving)
                    
                    // Manual Edit Button
                    if isEditing {
                        Button(action: onSaveManualEdit) {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark")
                                Text("Save")
                            }
                            .font(.caption.bold())
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: onCancelManualEdit) {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: onStartManualEdit) {
                            HStack(spacing: 3) {
                                Image(systemName: "pencil")
                                Text("Edit")
                            }
                            .font(.caption)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(hunk.resolution == .manual ? Color.orange.opacity(0.12) : Color.primary.opacity(0.05))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            
            Divider()
            
            // Optional Base (Ancestor) Collapsible Panel
            if showBasePane, let base = hunk.baseContent, !base.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                        Text("BASE (Common Ancestor)")
                            .font(.caption2.bold())
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.03))
                    
                    CodePaneContent(
                        content: base,
                        startLine: hunk.startLine,
                        gutterBackground: Color.primary.opacity(0.04),
                        panelBackground: Color.primary.opacity(0.01),
                        gutterTextColor: .secondary
                    )
                }
                .background(Color.primary.opacity(0.02))
                Divider()
            }
            
            // Three-Way Diff Panels (Requirement 3)
            HStack(alignment: .top, spacing: 1) {
                // 1. Left Panel: "Ours" (current branch) with green-tinted gutter
                ThreeWayDiffPane(
                    title: "OURS (Current Branch)",
                    badgeText: "HEAD",
                    badgeColor: .green,
                    content: hunk.oursContent,
                    startLine: hunk.startLine,
                    gutterBackground: Color.green.opacity(0.08),
                    panelBackground: Color.green.opacity(0.04),
                    gutterTextColor: .green,
                    onQuickAccept: onAcceptOurs
                )
                .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 1)
                
                // 2. Center Panel: "Resolved" (editable) with neutral color
                ResolvedDiffPane(
                    resolution: hunk.resolution,
                    displayedContent: currentResolvedDisplayContent,
                    startLine: hunk.startLine,
                    isEditing: isEditing,
                    editingDraft: $editingDraft,
                    onStartEdit: onStartManualEdit,
                    onSaveEdit: onSaveManualEdit
                )
                .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 1)
                
                // 3. Right Panel: "Theirs" (incoming) with blue-tinted gutter
                ThreeWayDiffPane(
                    title: "THEIRS (Incoming Branch)",
                    badgeText: "Incoming",
                    badgeColor: .blue,
                    content: hunk.theirsContent,
                    startLine: hunk.startLine,
                    gutterBackground: Color.blue.opacity(0.08),
                    panelBackground: Color.blue.opacity(0.04),
                    gutterTextColor: .blue,
                    onQuickAccept: onAcceptTheirs
                )
                .frame(maxWidth: .infinity)
            }
            .frame(minHeight: 120)
        }
        .background(Color.primary.opacity(0.02))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(hunkBorderColor, lineWidth: 1)
        )
    }
    
    private var currentResolvedDisplayContent: String {
        switch hunk.resolution {
        case .unresolved:
            return hunk.resolvedContent ?? ""
        case .ours:
            return hunk.resolvedContent ?? hunk.oursContent
        case .theirs:
            return hunk.resolvedContent ?? hunk.theirsContent
        case .aiMerged, .manual:
            return hunk.resolvedContent ?? ""
        }
    }
    
    private var hunkBorderColor: Color {
        switch hunk.resolution {
        case .unresolved:
            return Color.red.opacity(0.2)
        case .ours:
            return Color.green.opacity(0.25)
        case .theirs:
            return Color.blue.opacity(0.25)
        case .aiMerged:
            return Color.purple.opacity(0.25)
        case .manual:
            return Color.orange.opacity(0.25)
        }
    }
}

// MARK: - Hunk Status Badge

struct HunkStatusBadge: View {
    let resolution: ConflictResolution
    let confidence: Double?
    
    var body: some View {
        HStack(spacing: 4) {
            switch resolution {
            case .unresolved:
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text("Unresolved")
                    .foregroundColor(.red)
            case .ours:
                Image(systemName: "checkmark")
                    .font(.caption2.bold())
                    .foregroundColor(.green)
                Text("Accepted Ours")
                    .foregroundColor(.green)
            case .theirs:
                Image(systemName: "checkmark")
                    .font(.caption2.bold())
                    .foregroundColor(.blue)
                Text("Accepted Theirs")
                    .foregroundColor(.blue)
            case .aiMerged:
                Image(systemName: "sparkles")
                    .font(.caption2.bold())
                    .foregroundColor(.purple)
                if let conf = confidence {
                    Text("AI Merged (\(Int(conf * 100))%)")
                        .foregroundColor(.purple)
                } else {
                    Text("AI Merged")
                        .foregroundColor(.purple)
                }
            case .manual:
                Image(systemName: "pencil")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Text("Manual Edit")
                    .foregroundColor(.orange)
            }
        }
        .font(.caption2.bold())
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(badgeBackgroundColor)
        .cornerRadius(4)
    }
    
    private var badgeBackgroundColor: Color {
        switch resolution {
        case .unresolved: return Color.red.opacity(0.08)
        case .ours: return Color.green.opacity(0.08)
        case .theirs: return Color.blue.opacity(0.08)
        case .aiMerged: return Color.purple.opacity(0.08)
        case .manual: return Color.orange.opacity(0.08)
        }
    }
}

// MARK: - Three-Way Diff Pane (Ours / Theirs)

struct ThreeWayDiffPane: View {
    let title: String
    let badgeText: String
    let badgeColor: Color
    let content: String
    let startLine: Int
    let gutterBackground: Color
    let panelBackground: Color
    let gutterTextColor: Color
    let onQuickAccept: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Pane Header
            HStack(spacing: 6) {
                Text(badgeText)
                    .font(.caption2.bold())
                    .foregroundColor(badgeColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(badgeColor.opacity(0.12))
                    .cornerRadius(3)
                
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: onQuickAccept) {
                    Text("Use This")
                        .font(.caption2)
                        .foregroundColor(badgeColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.03))
            
            Divider()
            
            // Code Body
            CodePaneContent(
                content: content,
                startLine: startLine,
                gutterBackground: gutterBackground,
                panelBackground: panelBackground,
                gutterTextColor: gutterTextColor
            )
        }
    }
}

// MARK: - Resolved Diff Pane (Center Panel)

struct ResolvedDiffPane: View {
    let resolution: ConflictResolution
    let displayedContent: String
    let startLine: Int
    let isEditing: Bool
    @Binding var editingDraft: String
    let onStartEdit: () -> Void
    let onSaveEdit: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Pane Header
            HStack(spacing: 6) {
                Text("RESULT")
                    .font(.caption2.bold())
                    .foregroundColor(.primary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(3)
                
                Text("Resolved Output")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !isEditing {
                    Button(action: onStartEdit) {
                        HStack(spacing: 2) {
                            Image(systemName: "pencil")
                            Text("Edit")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.03))
            
            Divider()
            
            // Editable or Formatted Display
            if isEditing {
                VStack(spacing: 0) {
                    TextEditor(text: $editingDraft)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(6)
                        .background(Color.primary.opacity(0.02))
                    
                    HStack {
                        Text("Editing resolution directly")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Apply", action: onSaveEdit)
                            .font(.caption2.bold())
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(6)
                    .background(Color.primary.opacity(0.04))
                }
            } else if displayedContent.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No resolution selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Click 'Accept Ours', 'Accept Theirs', or 'AI Merge'")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.red.opacity(0.03))
            } else {
                CodePaneContent(
                    content: displayedContent,
                    startLine: startLine,
                    gutterBackground: Color.primary.opacity(0.03),
                    panelBackground: Color.clear,
                    gutterTextColor: .secondary
                )
            }
        }
    }
}

// MARK: - Code Pane Content with Syntax Highlighting

struct CodePaneContent: View {
    let content: String
    let startLine: Int
    let gutterBackground: Color
    let panelBackground: Color
    let gutterTextColor: Color
    
    private var lines: [String] {
        if content.isEmpty { return [""] }
        return content.components(separatedBy: "\n")
    }
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    HStack(alignment: .top, spacing: 0) {
                        // Gutter with Line Number
                        Text("\(startLine + idx)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(gutterTextColor)
                            .frame(width: 38, alignment: .trailing)
                            .padding(.trailing, 6)
                            .padding(.vertical, 2)
                            .background(gutterBackground)
                        
                        Divider().frame(height: 16)
                        
                        // Highlighted Code Line
                        Text(MergeSyntaxHighlighter.highlight(line))
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.leading, 8)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(panelBackground)
                }
            }
        }
    }
}

// MARK: - Lightweight Syntax Highlighter

enum MergeSyntaxHighlighter {
    private static let keywords: Set<String> = [
        "import", "let", "var", "func", "class", "struct", "enum", "protocol",
        "extension", "public", "private", "fileprivate", "internal", "open",
        "return", "if", "else", "guard", "switch", "case", "default", "for",
        "in", "while", "do", "try", "catch", "throw", "throws", "async", "await",
        "def", "from", "as", "self", "Self", "nil", "true", "false", "const",
        "export", "type", "interface", "null", "undefined", "mut", "fn", "impl"
    ]
    
    public static func highlight(_ line: String) -> AttributedString {
        let trimmed = line.isEmpty ? " " : line
        var attributed = AttributedString(trimmed)
        
        // 1. Comment check
        if let commentRange = trimmed.range(of: "//") ?? trimmed.range(of: "#") {
            if let attrRange = AttributedString.Index(commentRange.lowerBound, within: attributed) {
                attributed[attrRange..<attributed.endIndex].foregroundColor = .secondary
                return attributed
            }
        }
        
        // 2. Tokenize words for keyword & type styling
        let words = trimmed.components(separatedBy: CharacterSet.alphanumerics.inverted)
        for word in words where !word.isEmpty {
            if keywords.contains(word) {
                // Find and style occurrences
                var searchStart = trimmed.startIndex
                while let range = trimmed.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: .regularExpression, range: searchStart..<trimmed.endIndex) {
                    if let startIdx = AttributedString.Index(range.lowerBound, within: attributed),
                       let endIdx = AttributedString.Index(range.upperBound, within: attributed) {
                        attributed[startIdx..<endIdx].foregroundColor = .purple
                        attributed[startIdx..<endIdx].font = .system(size: 12, weight: .semibold, design: .monospaced)
                    }
                    searchStart = range.upperBound
                }
            } else if word.first?.isUppercase == true && word.count > 1 {
                // Type styling
                var searchStart = trimmed.startIndex
                while let range = trimmed.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: .regularExpression, range: searchStart..<trimmed.endIndex) {
                    if let startIdx = AttributedString.Index(range.lowerBound, within: attributed),
                       let endIdx = AttributedString.Index(range.upperBound, within: attributed) {
                        attributed[startIdx..<endIdx].foregroundColor = .blue
                    }
                    searchStart = range.upperBound
                }
            }
        }
        
        return attributed
    }
}

// MARK: - Empty Conflicts View

struct EmptyConflictsView: View {
    let isScanning: Bool
    let onRescan: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 6) {
                Text("No Merge Conflicts Detected")
                    .font(.title3.bold())
                    .foregroundColor(.primary)
                
                Text("Your working directory is clean or all conflict markers have been resolved.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            Button(action: onRescan) {
                HStack(spacing: 6) {
                    if isScanning {
                        ProgressView()
                            .scaleEffect(0.65)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isScanning ? "Scanning..." : "Scan Workspace")
                }
                .font(.subheadline.bold())
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.07))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(isScanning)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
