// Copyright © 2025 Dotmini Software. All rights reserved.

import Foundation
import SwiftUI
import Combine

// MARK: - Conflict Resolution Status

public enum ConflictResolution: String, Codable, CaseIterable, Equatable {
    case unresolved
    case ours
    case theirs
    case aiMerged
    case manual
}

// MARK: - Models

public struct ConflictHunk: Identifiable, Equatable, Codable {
    public let id: UUID
    public var startLine: Int
    public var endLine: Int
    public var oursContent: String
    public var theirsContent: String
    public var baseContent: String?
    public var resolvedContent: String?
    public var resolution: ConflictResolution
    
    public var isResolved: Bool {
        resolution != .unresolved
    }
    
    public init(
        id: UUID = UUID(),
        startLine: Int,
        endLine: Int,
        oursContent: String,
        theirsContent: String,
        baseContent: String? = nil,
        resolvedContent: String? = nil,
        resolution: ConflictResolution = .unresolved
    ) {
        self.id = id
        self.startLine = startLine
        self.endLine = endLine
        self.oursContent = oursContent
        self.theirsContent = theirsContent
        self.baseContent = baseContent
        self.resolvedContent = resolvedContent
        self.resolution = resolution
    }
}

public struct MergeConflict: Identifiable, Equatable, Codable {
    public let id: UUID
    public var filePath: String
    public var hunks: [ConflictHunk]
    
    public var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
    
    public var isResolved: Bool {
        !hunks.isEmpty && hunks.allSatisfy { $0.isResolved }
    }
    
    public var unresolvedCount: Int {
        hunks.filter { !$0.isResolved }.count
    }
    
    public init(
        id: UUID = UUID(),
        filePath: String,
        hunks: [ConflictHunk]
    ) {
        self.id = id
        self.filePath = filePath
        self.hunks = hunks
    }
}

// MARK: - Errors

public enum MergeConflictError: LocalizedError, Equatable {
    case invalidProjectPath
    case fileNotFound(String)
    case gitCommandFailed(String)
    case conflictNotFound(UUID)
    case hunkNotFound(UUID)
    case noConflictMarkersFound(String)
    case parseError(String)
    case aiResolutionFailed(String)
    case writeFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidProjectPath:
            return "Invalid project path provided."
        case .fileNotFound(let path):
            return "File not found at path: \(path)"
        case .gitCommandFailed(let reason):
            return "Git command failed: \(reason)"
        case .conflictNotFound(let id):
            return "Merge conflict not found with ID: \(id)"
        case .hunkNotFound(let id):
            return "Conflict hunk not found with ID: \(id)"
        case .noConflictMarkersFound(let path):
            return "No conflict markers found in: \(path)"
        case .parseError(let reason):
            return "Failed to parse conflict: \(reason)"
        case .aiResolutionFailed(let reason):
            return "AI resolution failed: \(reason)"
        case .writeFailed(let reason):
            return "Failed to write resolved file: \(reason)"
        }
    }
}

// MARK: - MergeConflictService

@MainActor
public class MergeConflictService: ObservableObject {
    public static let shared = MergeConflictService()
    
    @Published public var conflicts: [MergeConflict] = []
    @Published public var isResolving: Bool = false
    @Published public var currentFile: String? = nil
    @Published public var errorMessage: String? = nil
    
    public var workspaceRoot: String? = nil
    
    private init() {}
    
    // MARK: - Scan for Conflicts
    
    /// Uses `git diff --check` and scans for `<<<<<<<` markers across the repository.
    public func scanForConflicts(projectPath: String) async throws {
        guard !projectPath.isEmpty else {
            throw MergeConflictError.invalidProjectPath
        }
        
        self.workspaceRoot = projectPath
        self.errorMessage = nil
        var candidatePaths = Set<String>()
        
        // 1. Run `git diff --check` to identify files with conflict markers
        let diffCheckResult = await runGit(["diff", "--check"], in: projectPath)
        if !diffCheckResult.output.isEmpty {
            let lines = diffCheckResult.output.components(separatedBy: "\n")
            for line in lines where line.contains("conflict marker") {
                let parts = line.components(separatedBy: ":")
                if let relOrAbsPath = parts.first?.trimmingCharacters(in: .whitespaces), !relOrAbsPath.isEmpty {
                    let fullPath = relOrAbsPath.hasPrefix("/")
                        ? relOrAbsPath
                        : URL(fileURLWithPath: projectPath).appendingPathComponent(relOrAbsPath).path
                    candidatePaths.insert(fullPath)
                }
            }
        }
        
        // 2. Also check unmerged files via `git diff --name-only --diff-filter=U`
        let unmergedResult = await runGit(["diff", "--name-only", "--diff-filter=U"], in: projectPath)
        if unmergedResult.exitCode == 0 {
            let files = unmergedResult.output.components(separatedBy: "\n")
            for file in files {
                let trimmed = file.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let fullPath = trimmed.hasPrefix("/")
                        ? trimmed
                        : URL(fileURLWithPath: projectPath).appendingPathComponent(trimmed).path
                    candidatePaths.insert(fullPath)
                }
            }
        }
        
        // 3. Scan with git grep for any conflict opening markers
        let grepResult = await runGit(["grep", "-l", "-E", "^<{7}( |$)"], in: projectPath)
        if grepResult.exitCode == 0 {
            let files = grepResult.output.components(separatedBy: "\n")
            for file in files {
                let trimmed = file.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let fullPath = trimmed.hasPrefix("/")
                        ? trimmed
                        : URL(fileURLWithPath: projectPath).appendingPathComponent(trimmed).path
                    candidatePaths.insert(fullPath)
                }
            }
        }
        
        // 4. Parse conflict markers for each candidate file
        var detectedConflicts: [MergeConflict] = []
        for path in candidatePaths.sorted() {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                guard content.contains("<<<<<<<") else { continue }
                
                let hunks = try parseConflictFile(path: path)
                if !hunks.isEmpty {
                    let conflict = MergeConflict(
                        id: UUID(),
                        filePath: path,
                        hunks: hunks
                    )
                    detectedConflicts.append(conflict)
                }
            } catch {
                NSLog("⚠️ [MergeConflictService] Failed to parse file %@: %@", path, error.localizedDescription)
            }
        }
        
        self.conflicts = detectedConflicts
    }
    
    // MARK: - Parse Conflict File
    
    /// Parses standard git conflict markers (including diff3 style with `|||||||`).
    public func parseConflictFile(path: String) throws -> [ConflictHunk] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw MergeConflictError.fileNotFound(path)
        }
        
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")
        
        var hunks: [ConflictHunk] = []
        
        enum ParserState {
            case outside
            case inOurs(startLine: Int, ours: [String])
            case inBase(startLine: Int, ours: [String], base: [String])
            case inTheirs(startLine: Int, ours: [String], base: [String]?, theirs: [String])
        }
        
        var state: ParserState = .outside
        
        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            
            switch state {
            case .outside:
                if line.hasPrefix("<<<<<<<") {
                    state = .inOurs(startLine: lineNumber, ours: [])
                }
                
            case .inOurs(let startLine, var ours):
                if line.hasPrefix("|||||||") {
                    state = .inBase(startLine: startLine, ours: ours, base: [])
                } else if line.hasPrefix("=======") {
                    state = .inTheirs(startLine: startLine, ours: ours, base: nil, theirs: [])
                } else if line.hasPrefix("<<<<<<<") {
                    state = .inOurs(startLine: lineNumber, ours: [])
                } else {
                    ours.append(line)
                    state = .inOurs(startLine: startLine, ours: ours)
                }
                
            case .inBase(let startLine, let ours, var base):
                if line.hasPrefix("=======") {
                    state = .inTheirs(startLine: startLine, ours: ours, base: base, theirs: [])
                } else if line.hasPrefix("<<<<<<<") {
                    state = .inOurs(startLine: lineNumber, ours: [])
                } else {
                    base.append(line)
                    state = .inBase(startLine: startLine, ours: ours, base: base)
                }
                
            case .inTheirs(let startLine, let ours, let base, var theirs):
                if line.hasPrefix(">>>>>>>") {
                    let hunk = ConflictHunk(
                        id: UUID(),
                        startLine: startLine,
                        endLine: lineNumber,
                        oursContent: ours.joined(separator: "\n"),
                        theirsContent: theirs.joined(separator: "\n"),
                        baseContent: base.map { $0.joined(separator: "\n") },
                        resolvedContent: nil,
                        resolution: .unresolved
                    )
                    hunks.append(hunk)
                    state = .outside
                } else if line.hasPrefix("<<<<<<<") {
                    state = .inOurs(startLine: lineNumber, ours: [])
                } else {
                    theirs.append(line)
                    state = .inTheirs(startLine: startLine, ours: ours, base: base, theirs: theirs)
                }
            }
        }
        
        return hunks
    }
    
    // MARK: - AI Resolution
    
    /// Sends both sides + context to AI for intelligent merge
    public func resolveWithAI(conflict: MergeConflict) async throws {
        isResolving = true
        currentFile = conflict.filePath
        defer {
            isResolving = false
            currentFile = nil
        }
        
        guard FileManager.default.fileExists(atPath: conflict.filePath) else {
            throw MergeConflictError.fileNotFound(conflict.filePath)
        }
        
        let content = try String(contentsOfFile: conflict.filePath, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")
        let fileName = URL(fileURLWithPath: conflict.filePath).lastPathComponent
        
        guard let conflictIndex = conflicts.firstIndex(where: { $0.id == conflict.id || $0.filePath == conflict.filePath }) else {
            throw MergeConflictError.conflictNotFound(conflict.id)
        }
        
        for hunkIndex in conflicts[conflictIndex].hunks.indices {
            var hunk = conflicts[conflictIndex].hunks[hunkIndex]
            if hunk.resolution != .unresolved {
                continue
            }
            
            let (contextBefore, contextAfter) = getContext(
                lines: lines,
                startLine: hunk.startLine,
                endLine: hunk.endLine,
                maxContextLines: 50
            )
            
            let systemPrompt = "You are a git merge conflict resolver. Analyze both versions, understand intent, produce merged result."
            
            var userPrompt = """
            Resolve this git merge conflict in file `\(fileName)`:
            
            Context before conflict (up to 50 lines):
            ```
            \(contextBefore)
            ```
            
            <<<<<<< OURS (current branch)
            \(hunk.oursContent)
            """
            
            if let base = hunk.baseContent, !base.isEmpty {
                userPrompt += """
                
                ||||||| BASE (common ancestor)
                \(base)
                """
            }
            
            userPrompt += """
            
            =======
            \(hunk.theirsContent)
            >>>>>>> THEIRS (incoming branch)
            
            Context after conflict (up to 50 lines):
            ```
            \(contextAfter)
            ```
            
            Instructions:
            1. Understand the intent of both the "OURS" and "THEIRS" changes in context.
            2. Produce cleanly merged code that harmoniously retains modifications from both sides without syntax errors or duplication.
            3. Output ONLY the resolved code block replacement.
            4. Do NOT output conflict markers (<<<<<<<, |||||||, =======, >>>>>>>).
            5. Do NOT include Markdown fences or explanations — output only the exact merged lines.
            """
            
            let messages: [(role: String, content: String)] = [
                (role: "system", content: systemPrompt),
                (role: "user", content: userPrompt)
            ]
            
            let provider = LocalLLMService.shared.activeEndpoint ?? "anthropic"
            let model = LocalLLMService.shared.activeModel
            
            let stream = try await AIClient.shared.streamCompletion(
                messages: messages,
                model: model,
                provider: provider,
                tools: nil,
                stream: false
            )
            
            var aiMergedText = ""
            for try await chunk in stream {
                aiMergedText += chunk
            }
            
            var cleanedCode = aiMergedText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Clean up code fences if model wrapped them
            if cleanedCode.hasPrefix("```") {
                if let firstNewline = cleanedCode.firstIndex(of: "\n") {
                    cleanedCode = String(cleanedCode[cleanedCode.index(after: firstNewline)...])
                }
                if cleanedCode.hasSuffix("```") {
                    cleanedCode = String(cleanedCode.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            
            // Remove any accidental conflict marker lines emitted by AI
            let strippedLines = cleanedCode.components(separatedBy: "\n").filter { line in
                !line.hasPrefix("<<<<<<<") && !line.hasPrefix("|||||||") && !line.hasPrefix("=======") && !line.hasPrefix(">>>>>>>")
            }
            cleanedCode = strippedLines.joined(separator: "\n")
            
            hunk.resolvedContent = cleanedCode
            hunk.resolution = .aiMerged
            conflicts[conflictIndex].hunks[hunkIndex] = hunk
        }
    }
    
    // MARK: - Apply Resolution
    
    /// Writes resolved content back to file.
    public func applyResolution(conflict: MergeConflict) async throws {
        guard FileManager.default.fileExists(atPath: conflict.filePath) else {
            throw MergeConflictError.fileNotFound(conflict.filePath)
        }
        
        let content = try String(contentsOfFile: conflict.filePath, encoding: .utf8)
        var fileLines = content.components(separatedBy: "\n")
        
        // Find latest conflict data from local state
        let currentConflict = conflicts.first(where: { $0.id == conflict.id || $0.filePath == conflict.filePath }) ?? conflict
        
        // Replace from bottom to top so that earlier line numbers remain unaffected
        let sortedHunks = currentConflict.hunks.sorted { $0.startLine > $1.startLine }
        
        for hunk in sortedHunks {
            guard hunk.resolution != .unresolved else { continue }
            
            let replacementText: String
            switch hunk.resolution {
            case .ours:
                replacementText = hunk.oursContent
            case .theirs:
                replacementText = hunk.theirsContent
            case .aiMerged, .manual:
                replacementText = hunk.resolvedContent ?? hunk.oursContent
            case .unresolved:
                continue
            }
            
            var start = hunk.startLine - 1
            var end = hunk.endLine - 1
            
            // Marker boundary verification and search fallback
            if start >= 0 && start < fileLines.count && !fileLines[start].hasPrefix("<<<<<<<") {
                let searchRange = max(0, start - 15)...min(fileLines.count - 1, start + 15)
                if let foundStart = searchRange.first(where: { fileLines[$0].hasPrefix("<<<<<<<") }) {
                    start = foundStart
                }
            }
            
            if end >= start && end < fileLines.count && !fileLines[end].hasPrefix(">>>>>>>") {
                let searchRange = start..<min(fileLines.count, start + 600)
                if let foundEnd = searchRange.first(where: { fileLines[$0].hasPrefix(">>>>>>>") }) {
                    end = foundEnd
                }
            }
            
            if start >= 0 && end < fileLines.count && start <= end {
                let replacementLines = replacementText.isEmpty ? [] : replacementText.components(separatedBy: "\n")
                fileLines.replaceSubrange(start...end, with: replacementLines)
            }
        }
        
        let newContent = fileLines.joined(separator: "\n")
        do {
            try newContent.write(to: URL(fileURLWithPath: currentConflict.filePath), atomically: true, encoding: .utf8)
        } catch {
            throw MergeConflictError.writeFailed(error.localizedDescription)
        }
        
        // Refresh hunks from disk
        let remainingHunks = (try? parseConflictFile(path: currentConflict.filePath)) ?? []
        if remainingHunks.isEmpty {
            conflicts.removeAll { $0.id == currentConflict.id || $0.filePath == currentConflict.filePath }
        } else {
            if let idx = conflicts.firstIndex(where: { $0.id == currentConflict.id || $0.filePath == currentConflict.filePath }) {
                conflicts[idx].hunks = remainingHunks
            }
        }
    }
    
    // MARK: - Resolve All
    
    /// Resolves all conflicts in sequence
    public func resolveAll() async throws {
        guard !conflicts.isEmpty else { return }
        
        isResolving = true
        defer {
            isResolving = false
            currentFile = nil
        }
        
        let conflictsSnapshot = conflicts
        for conflict in conflictsSnapshot {
            currentFile = conflict.filePath
            try await resolveWithAI(conflict: conflict)
            if let updated = conflicts.first(where: { $0.id == conflict.id || $0.filePath == conflict.filePath }) {
                try await applyResolution(conflict: updated)
                try await markResolved(filePath: conflict.filePath)
            }
        }
    }
    
    // MARK: - Mark Resolved
    
    /// Runs `git add` on resolved file
    public func markResolved(filePath: String) async throws {
        let workingDir: String
        if let root = workspaceRoot, !root.isEmpty {
            workingDir = root
        } else {
            workingDir = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        }
        
        let result = await runGit(["add", "--", filePath], in: workingDir)
        if result.exitCode != 0 {
            throw MergeConflictError.gitCommandFailed("git add failed: \(result.output)")
        }
        
        let remainingHunks = (try? parseConflictFile(path: filePath)) ?? []
        if remainingHunks.isEmpty {
            conflicts.removeAll { $0.filePath == filePath }
        }
    }
    
    // MARK: - Manual Selection Actions
    
    public func acceptOurs(conflictId: UUID, hunkId: UUID) {
        guard let cIdx = conflicts.firstIndex(where: { $0.id == conflictId }) else { return }
        guard let hIdx = conflicts[cIdx].hunks.firstIndex(where: { $0.id == hunkId }) else { return }
        
        conflicts[cIdx].hunks[hIdx].resolution = .ours
        conflicts[cIdx].hunks[hIdx].resolvedContent = conflicts[cIdx].hunks[hIdx].oursContent
    }
    
    public func acceptTheirs(conflictId: UUID, hunkId: UUID) {
        guard let cIdx = conflicts.firstIndex(where: { $0.id == conflictId }) else { return }
        guard let hIdx = conflicts[cIdx].hunks.firstIndex(where: { $0.id == hunkId }) else { return }
        
        conflicts[cIdx].hunks[hIdx].resolution = .theirs
        conflicts[cIdx].hunks[hIdx].resolvedContent = conflicts[cIdx].hunks[hIdx].theirsContent
    }
    
    public func acceptBoth(conflictId: UUID, hunkId: UUID) {
        guard let cIdx = conflicts.firstIndex(where: { $0.id == conflictId }) else { return }
        guard let hIdx = conflicts[cIdx].hunks.firstIndex(where: { $0.id == hunkId }) else { return }
        
        let ours = conflicts[cIdx].hunks[hIdx].oursContent
        let theirs = conflicts[cIdx].hunks[hIdx].theirsContent
        let combined = ours + "\n" + theirs
        
        conflicts[cIdx].hunks[hIdx].resolution = .manual
        conflicts[cIdx].hunks[hIdx].resolvedContent = combined
    }
    
    public func setManualResolution(conflictId: UUID, hunkId: UUID, content: String) {
        guard let cIdx = conflicts.firstIndex(where: { $0.id == conflictId }) else { return }
        guard let hIdx = conflicts[cIdx].hunks.firstIndex(where: { $0.id == hunkId }) else { return }
        
        conflicts[cIdx].hunks[hIdx].resolution = .manual
        conflicts[cIdx].hunks[hIdx].resolvedContent = content
    }
    
    // MARK: - Helpers
    
    private func getContext(lines: [String], startLine: Int, endLine: Int, maxContextLines: Int = 50) -> (before: String, after: String) {
        let beforeStartIndex = max(0, startLine - 1 - maxContextLines)
        let beforeEndIndex = max(0, startLine - 1)
        let beforeSlice = beforeStartIndex < beforeEndIndex ? lines[beforeStartIndex..<beforeEndIndex] : []
        
        let afterStartIndex = min(lines.count, endLine)
        let afterEndIndex = min(lines.count, endLine + maxContextLines)
        let afterSlice = afterStartIndex < afterEndIndex ? lines[afterStartIndex..<afterEndIndex] : []
        
        return (
            beforeSlice.joined(separator: "\n"),
            afterSlice.joined(separator: "\n")
        )
    }
    
    private func runGit(_ args: [String], in directory: String) async -> (output: String, exitCode: Int32) {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outPipe = Pipe()
            let errPipe = Pipe()
            
            let candidatePaths = ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"]
            let gitPath = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? "/usr/bin/git"
            
            process.executableURL = URL(fileURLWithPath: gitPath)
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
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
}


