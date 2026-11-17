import Foundation

/// Snapshot of untracked (not ignored) files for agent checkpoints.
///
/// `git stash create` only records tracked files, so a file the user never committed and the agent then
/// overwrote or deleted could not be restored by "undo". This captures those files into a commit under
/// `refs/microcode-checkpoints/<id>-untracked` using a temporary index — the real index and working tree are
/// never touched — and restores exactly those paths (working tree only) on rollback.
/// Synchronous plumbing: call from a background task.
enum GitUntrackedSnapshot {
    struct Limits {
        var maxFiles = 200
        var maxFileBytes: Int64 = 2_000_000
        var maxTotalBytes: Int64 = 20_000_000
        static let `default` = Limits()
    }

    @discardableResult
    static func git(_ args: [String], in directory: String, env extra: [String: String] = [:]) -> (output: String, code: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        var env = ProcessInfo.processInfo.environment
        for (key, value) in extra { env[key] = value }
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return ("", -1) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }

    /// Keeps small files only (stray build output / binaries must not bloat `.git`), in a stable order.
    static func select(_ candidates: [(path: String, size: Int64)], limits: Limits = .default) -> [String] {
        var chosen: [String] = []
        var total: Int64 = 0
        for candidate in candidates.sorted(by: { $0.path < $1.path }) {
            guard chosen.count < limits.maxFiles else { break }
            guard candidate.size >= 0, candidate.size <= limits.maxFileBytes,
                  total + candidate.size <= limits.maxTotalBytes else { continue }
            chosen.append(candidate.path)
            total += candidate.size
        }
        return chosen
    }

    /// Captures untracked files; returns the ref, or nil when there is nothing (within limits) to capture.
    static func capture(root: String, checkpointId: String, limits: Limits = .default) -> String? {
        let listing = git(["ls-files", "--others", "--exclude-standard", "-z"], in: root)
        guard listing.code == 0 else { return nil }
        let rootURL = URL(fileURLWithPath: root)
        let candidates: [(path: String, size: Int64)] = listing.output
            .split(separator: "\0")
            .map(String.init)
            .compactMap { relative in
                let attrs = try? FileManager.default.attributesOfItem(atPath: rootURL.appendingPathComponent(relative).path)
                guard (attrs?[.type] as? FileAttributeType) == .typeRegular else { return nil }
                return (relative, (attrs?[.size] as? NSNumber)?.int64Value ?? -1)
            }
        let files = select(candidates, limits: limits)
        guard !files.isEmpty else { return nil }

        let tempIndex = (NSTemporaryDirectory() as NSString).appendingPathComponent("microcode-ckpt-\(UUID().uuidString).index")
        defer { try? FileManager.default.removeItem(atPath: tempIndex) }
        let indexEnv = ["GIT_INDEX_FILE": tempIndex]
        guard git(["add", "--"] + files, in: root, env: indexEnv).code == 0 else { return nil }
        let tree = git(["write-tree"], in: root, env: indexEnv)
        let treeSHA = tree.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tree.code == 0, !treeSHA.isEmpty else { return nil }
        // Explicit identity: works even when the user has no git user.name/email configured.
        let identity = [
            "GIT_AUTHOR_NAME": "MicroCode Checkpoint", "GIT_AUTHOR_EMAIL": "checkpoint@microcode.local",
            "GIT_COMMITTER_NAME": "MicroCode Checkpoint", "GIT_COMMITTER_EMAIL": "checkpoint@microcode.local"
        ]
        let commit = git(["commit-tree", treeSHA, "-m", "[microcode-checkpoint] \(checkpointId) untracked files"], in: root, env: identity)
        let commitSHA = commit.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard commit.code == 0, !commitSHA.isEmpty else { return nil }
        let ref = "refs/microcode-checkpoints/\(checkpointId)-untracked"
        guard git(["update-ref", ref, commitSHA], in: root).code == 0 else { return nil }
        return ref
    }

    /// Restores the captured files into the working tree (index untouched). Returns how many were restored.
    @discardableResult
    static func restore(root: String, ref: String) -> Int {
        let listing = git(["ls-tree", "-r", "--name-only", "-z", ref], in: root)
        guard listing.code == 0 else { return 0 }
        let paths = listing.output.split(separator: "\0").map(String.init)
        guard !paths.isEmpty else { return 0 }
        // Exact paths only: `git restore` with a broad pathspec would delete files absent from this snapshot.
        let result = git(["restore", "--source=\(ref)", "--worktree", "--"] + paths, in: root)
        return result.code == 0 ? paths.count : 0
    }

    static func delete(root: String, ref: String) {
        git(["update-ref", "-d", ref], in: root)
    }
}
