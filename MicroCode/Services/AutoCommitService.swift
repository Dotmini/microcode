//
//  AutoCommitService.swift
//  MicroCode
//
//  Auto-commit Safety Net — creates git checkpoints before agent file modifications
//  allowing one-click rollback of any AI-generated changes.
//

import Foundation

// MARK: - Auto-Commit Safety Net

@MainActor
class AutoCommitService: ObservableObject {
    static let shared = AutoCommitService()
    
    /// Whether the safety net is enabled
    @Published var isEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "MicroCode.AutoCommitEnabled") }
    }
    
    /// History of checkpoints created during this session
    @Published var checkpoints: [AgentCheckpoint] = []
    
    /// Whether a checkpoint operation is in progress
    @Published var isCreatingCheckpoint: Bool = false
    
    /// Maximum checkpoints to keep (older ones are pruned)
    let maxCheckpoints: Int = 50
    
    /// Debounce: minimum seconds between checkpoints
    private let debounceInterval: TimeInterval = 5.0
    private var lastCheckpointTime: Date = .distantPast
    
    /// Track which files the agent has modified in the current session
    @Published var modifiedFiles: Set<String> = []
    
    /// The workspace root for git operations
    var workspaceRoot: String? = nil
    
    init() {
        isEnabled = UserDefaults.standard.object(forKey: "MicroCode.AutoCommitEnabled") as? Bool ?? true
    }
    
    // MARK: - Checkpoint Creation
    
    /// Create a safety checkpoint before agent modifies files.
    /// Uses a lightweight git stash approach to avoid polluting commit history.
    /// Returns the checkpoint ID if successful, nil otherwise.
    @discardableResult
    func createCheckpoint(toolName: String, targetPath: String?) async -> String? {
        guard isEnabled else { return nil }
        guard let root = workspaceRoot, !root.isEmpty else { return nil }
        
        // Debounce: skip if we just created one
        let now = Date()
        if now.timeIntervalSince(lastCheckpointTime) < debounceInterval {
            return nil
        }
        
        // Check if this is a git repository
        let isGitRepo = await runGit(["rev-parse", "--is-inside-work-tree"], in: root)
        guard isGitRepo.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            return nil
        }
        
        // Check if there are any changes to checkpoint
        let status = await runGit(["status", "--porcelain"], in: root)
        guard !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Nothing to checkpoint — working tree is clean
            return nil
        }
        
        isCreatingCheckpoint = true
        defer { isCreatingCheckpoint = false }
        
        let checkpointId = UUID().uuidString.prefix(8).lowercased()
        let timestamp = ISO8601DateFormatter().string(from: now)
        let description = targetPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? toolName
        let commitMessage = "[microcode-checkpoint] \(checkpointId) before \(toolName): \(description)"
        
        // Strategy: Create a checkpoint commit object without modifying the working tree or index on disk.
        // Using `git stash create` + `git update-ref` avoids temporarily reverting files on disk
        // (which previously triggered file-watcher storms and dev-server hot-reload loops).
        let stashSha = await runGit(["stash", "create", commitMessage], in: root)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !stashSha.isEmpty {
            let refName = "refs/microcode-checkpoints/\(checkpointId)"
            let refResult = await runGitExec(["update-ref", "-m", commitMessage, refName, stashSha], in: root)
            
            if refResult.exitCode == 0 {
                let checkpoint = AgentCheckpoint(
                    id: String(checkpointId),
                    timestamp: now,
                    toolName: toolName,
                    targetPath: targetPath,
                    stashMessage: commitMessage,
                    filesSummary: parseStatusSummary(status),
                    isTagBased: false,
                    tagName: refName
                )
                
                checkpoints.append(checkpoint)
                lastCheckpointTime = now
                
                // Track modified file
                if let path = targetPath {
                    modifiedFiles.insert(path)
                }
                
                // Prune old checkpoints
                if checkpoints.count > maxCheckpoints {
                    let removed = checkpoints.prefix(checkpoints.count - maxCheckpoints)
                    for old in removed {
                        if let oldRef = old.tagName, oldRef.hasPrefix("refs/microcode-checkpoints/") {
                            _ = await runGitExec(["update-ref", "-d", oldRef], in: root)
                        }
                    }
                    checkpoints.removeFirst(checkpoints.count - maxCheckpoints)
                }
                
                return checkpoint.id
            }
        }
        
        // Alternative: if stash approach fails, try creating a lightweight tag
        // on the current HEAD as a rollback marker
        let headSha = await runGit(["rev-parse", "--short", "HEAD"], in: root)
        if !headSha.isEmpty {
            let tagName = "microcode-checkpoint/\(checkpointId)"
            let tagResult = await runGitExec(
                ["tag", "-a", tagName, "-m", commitMessage, headSha.trimmingCharacters(in: .whitespacesAndNewlines)],
                in: root
            )
            
            if tagResult.exitCode == 0 {
                let checkpoint = AgentCheckpoint(
                    id: String(checkpointId),
                    timestamp: now,
                    toolName: toolName,
                    targetPath: targetPath,
                    stashMessage: commitMessage,
                    filesSummary: parseStatusSummary(status),
                    isTagBased: true,
                    tagName: tagName
                )
                
                checkpoints.append(checkpoint)
                lastCheckpointTime = now
                
                if let path = targetPath {
                    modifiedFiles.insert(path)
                }
                
                return checkpoint.id
            }
        }
        
        return nil
    }
    
    // MARK: - Rollback
    
    /// Rollback all changes to a specific checkpoint
    func rollbackToCheckpoint(_ checkpoint: AgentCheckpoint) async -> Bool {
        guard let root = workspaceRoot, !root.isEmpty else { return false }
        
        if checkpoint.isTagBased, let tagName = checkpoint.tagName {
            // Tag-based: restore tracked files to the tagged commit
            let result = await runGitExec(["checkout", tagName, "--", "."], in: root)
            if result.exitCode == 0 {
                if let index = checkpoints.firstIndex(where: { $0.id == checkpoint.id }) {
                    checkpoints.removeSubrange((index + 1)...)
                }
                return true
            }
        } else {
            // 1. Prefer the persistent checkpoint ref created before `git stash pop`
            let refCandidates = [checkpoint.tagName, "refs/microcode-checkpoints/\(checkpoint.id)"].compactMap { $0 }
            for ref in refCandidates {
                let verify = await runGitExec(["rev-parse", "--verify", ref], in: root)
                if verify.exitCode == 0 {
                    _ = await runGitExec(["checkout", "--", "."], in: root)
                    let applyResult = await runGitExec(["stash", "apply", "--index", ref], in: root)
                    let fallbackApply = applyResult.exitCode == 0
                        ? applyResult
                        : await runGitExec(["stash", "apply", ref], in: root)
                    if fallbackApply.exitCode == 0 {
                        if let index = checkpoints.firstIndex(where: { $0.id == checkpoint.id }) {
                            checkpoints.removeSubrange((index + 1)...)
                        }
                        return true
                    }
                }
            }

            // 2. Fallback: Check `git stash list` by message
            let stashList = await runGit(["stash", "list"], in: root)
            let lines = stashList.components(separatedBy: "\n")
            for line in lines where line.contains(checkpoint.stashMessage) {
                if let stashRef = line.components(separatedBy: ":").first {
                    let result = await runGitExec(["stash", "apply", stashRef.trimmingCharacters(in: .whitespaces)], in: root)
                    if result.exitCode == 0 {
                        if let index = checkpoints.firstIndex(where: { $0.id == checkpoint.id }) {
                            checkpoints.removeSubrange((index + 1)...)
                        }
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    /// Rollback only a specific file to its state at HEAD
    func rollbackFile(_ filePath: String) async -> Bool {
        guard let root = workspaceRoot, !root.isEmpty else { return false }
        
        let relativePath = filePath.hasPrefix(root)
            ? String(filePath.dropFirst(root.count + 1))
            : filePath
        
        let result = await runGitExec(["checkout", "HEAD", "--", relativePath], in: root)
        if result.exitCode == 0 {
            modifiedFiles.remove(filePath)
            return true
        }
        return false
    }
    
    /// Discard all agent modifications in the current session
    func rollbackAllAgentChanges() async -> Bool {
        guard let root = workspaceRoot, !root.isEmpty else { return false }
        guard let firstCheckpoint = checkpoints.first else { return false }
        
        return await rollbackToCheckpoint(firstCheckpoint)
    }
    
    // MARK: - Cleanup
    
    /// Remove checkpoint tags and refs (call on app quit or session end)
    func cleanupCheckpointTags() async {
        guard let root = workspaceRoot, !root.isEmpty else { return }
        
        for checkpoint in checkpoints {
            if let tagName = checkpoint.tagName {
                if checkpoint.isTagBased {
                    let _ = await runGitExec(["tag", "-d", tagName], in: root)
                } else if tagName.hasPrefix("refs/microcode-checkpoints/") {
                    let _ = await runGitExec(["update-ref", "-d", tagName], in: root)
                }
            }
        }
    }
    
    /// Clear session tracking
    func clearSession() {
        checkpoints.removeAll()
        modifiedFiles.removeAll()
        lastCheckpointTime = .distantPast
    }
    
    // MARK: - File Modification Tracking
    
    /// Check if a file was modified by the agent in this session
    func isAgentModified(_ filePath: String) -> Bool {
        modifiedFiles.contains(filePath)
    }
    
    /// Get the diff for agent-modified files
    func getAgentChangesDiff() async -> String? {
        guard let root = workspaceRoot, !root.isEmpty else { return nil }
        guard !modifiedFiles.isEmpty else { return nil }
        
        let paths = modifiedFiles.map { path -> String in
            path.hasPrefix(root) ? String(path.dropFirst(root.count + 1)) : path
        }
        
        var args = ["diff", "--no-ext-diff", "--"]
        args.append(contentsOf: paths)
        
        let diff = await runGit(args, in: root)
        return diff.isEmpty ? nil : diff
    }
    
    // MARK: - Private Helpers
    
    private func runGit(_ args: [String], in directory: String) async -> String {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                while process.isRunning {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } catch {
                return ""
            }
        }.value
    }
    
    private func runGitExec(_ args: [String], in directory: String) async -> (output: String, exitCode: Int32) {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = outPipe
            process.standardError = errPipe
            do {
                try process.run()
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                while process.isRunning {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                return (out + err, process.terminationStatus)
            } catch {
                return (error.localizedDescription, -1)
            }
        }.value
    }
    
    private func parseStatusSummary(_ status: String) -> String {
        let lines = status.components(separatedBy: "\n").filter { !$0.isEmpty }
        let modified = lines.filter { $0.hasPrefix(" M") || $0.hasPrefix("M ") }.count
        let added = lines.filter { $0.hasPrefix("A ") || $0.hasPrefix("??") }.count
        let deleted = lines.filter { $0.hasPrefix("D ") || $0.hasPrefix(" D") }.count
        
        var parts: [String] = []
        if modified > 0 { parts.append("\(modified) modified") }
        if added > 0 { parts.append("\(added) added") }
        if deleted > 0 { parts.append("\(deleted) deleted") }
        
        return parts.isEmpty ? "no changes" : parts.joined(separator: ", ")
    }
}

// MARK: - Checkpoint Model

struct AgentCheckpoint: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let toolName: String
    let targetPath: String?
    let stashMessage: String
    let filesSummary: String
    var isTagBased: Bool = false
    var tagName: String? = nil
    
    var displayName: String {
        let file = targetPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "multiple files"
        return "\(toolName) → \(file)"
    }
    
    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }
}
