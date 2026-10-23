import Foundation
import Combine

/// Resolve the existing parent before appending a not-yet-created destination.
/// Foundation alone leaves symlinks unresolved when the leaf does not exist.
enum WorkspacePathPolicy {
    static func contains(_ path: String, in root: String) -> Bool {
        guard !path.isEmpty, !root.isEmpty,
              !(path as NSString).pathComponents.contains(".."),
              let base = canonical(root), let target = canonical(path) else { return false }
        return target.pathComponents.starts(with: base.pathComponents)
    }

    static func canonicalPath(_ path: String) -> String {
        canonical(path)?.path ?? URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func canonical(_ path: String) -> URL? {
        var ancestor = URL(fileURLWithPath: path).standardizedFileURL
        var suffix: [String] = []
        let files = FileManager.default
        while !files.fileExists(atPath: ancestor.path) {
            // Do not treat a dangling symlink as a creatable plain directory.
            if (try? files.destinationOfSymbolicLink(atPath: ancestor.path)) != nil { return nil }
            guard ancestor.path != "/" else { return nil }
            suffix.insert(ancestor.lastPathComponent, at: 0)
            ancestor.deleteLastPathComponent()
        }
        var resolved = ancestor.resolvingSymlinksInPath()
        for component in suffix { resolved.appendPathComponent(component) }
        return resolved.standardizedFileURL
    }
}

// MARK: - Feature #4: Scope Lock & Protected Files Guard

@MainActor
final class WorkspaceScopeGuard: ObservableObject {
    static let shared = WorkspaceScopeGuard()

    /// Canonical file paths locked against AI modification in the current workspace.
    @Published var lockedPaths: Set<String> = []
    /// When enabled, the AI may only mutate files explicitly @mentioned by the user (or active editor file).
    @Published var strictMentionOnlyScope: Bool = false {
        didSet { saveCurrentWorkspaceState() }
    }
    /// Files explicitly @mentioned in the current session/turn.
    @Published var sessionMentionedPaths: Set<String> = []

    private var activeWorkspaceRoot: String = ""

    private init() {}

    func syncWorkspace(_ workspaceRoot: String?) {
        let root = workspaceRoot ?? ""
        guard root != activeWorkspaceRoot else { return }
        activeWorkspaceRoot = root
        guard !root.isEmpty else {
            lockedPaths = []
            strictMentionOnlyScope = false
            sessionMentionedPaths = []
            return
        }
        let keyPrefix = storageKeyPrefix(for: root)
        let savedLocks = UserDefaults.standard.stringArray(forKey: "\(keyPrefix).lockedPaths") ?? []
        lockedPaths = Set(savedLocks.map { WorkspacePathPolicy.canonicalPath($0) })
        strictMentionOnlyScope = UserDefaults.standard.bool(forKey: "\(keyPrefix).strictScope")
    }

    func isLocked(_ path: String, workspaceRoot: String? = nil) -> Bool {
        if let ws = workspaceRoot { syncWorkspace(ws) }
        let canon = WorkspacePathPolicy.canonicalPath(path)
        return lockedPaths.contains(canon)
    }

    func toggleLock(_ path: String, workspaceRoot: String? = nil) {
        if let ws = workspaceRoot { syncWorkspace(ws) }
        let canon = WorkspacePathPolicy.canonicalPath(path)
        if lockedPaths.contains(canon) {
            lockedPaths.remove(canon)
        } else {
            lockedPaths.insert(canon)
        }
        saveCurrentWorkspaceState()
    }

    func unlockAll(workspaceRoot: String? = nil) {
        if let ws = workspaceRoot { syncWorkspace(ws) }
        lockedPaths.removeAll()
        saveCurrentWorkspaceState()
    }

    /// Locks common sensitive/config files in the workspace root (.env, package.json, Cargo.toml, etc.).
    func lockCoreConfigFiles(in workspaceRoot: String) -> Int {
        syncWorkspace(workspaceRoot)
        let candidates = [
            ".env", ".env.local", ".env.production", ".env.development",
            "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock",
            "Cargo.toml", "Cargo.lock", "Podfile.lock", "Package.resolved",
            "Secrets.plist", "Info.plist", "docker-compose.yml", "Dockerfile"
        ]
        var added = 0
        let fm = FileManager.default
        for name in candidates {
            let fullPath = (workspaceRoot as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: fullPath) {
                let canon = WorkspacePathPolicy.canonicalPath(fullPath)
                if !lockedPaths.contains(canon) {
                    lockedPaths.insert(canon)
                    added += 1
                }
            }
        }
        saveCurrentWorkspaceState()
        return added
    }

    func registerMentionedFiles(_ paths: [String], activeEditorFile: String? = nil, workspaceRoot: String?) {
        syncWorkspace(workspaceRoot)
        guard let root = workspaceRoot, !root.isEmpty else { return }
        for raw in paths {
            let full = raw.hasPrefix("/") ? raw : (root as NSString).appendingPathComponent(raw)
            sessionMentionedPaths.insert(WorkspacePathPolicy.canonicalPath(full))
        }
        if let active = activeEditorFile, !active.isEmpty {
            sessionMentionedPaths.insert(WorkspacePathPolicy.canonicalPath(active))
        }
    }

    /// Validates whether the AI is allowed to mutate the given file path.
    /// Returns a human- & LLM-readable block reason if disallowed, or `nil` if allowed.
    func validateMutationAllowed(path: String, workspaceRoot: String?) -> String? {
        syncWorkspace(workspaceRoot)
        let canon = WorkspacePathPolicy.canonicalPath(path)
        // Always allow internal .microcode state files (task.md, agent.md, AI.arx)
        if canon.contains("/.microcode/") {
            return nil
        }
        let fileName = URL(fileURLWithPath: canon).lastPathComponent
        if lockedPaths.contains(canon) {
            return "🔒 Scope Lock Policy: '\(fileName)' (\(canon)) is locked by the user as a Protected File. You are strictly prohibited from modifying or deleting this file. Complete the user's request by modifying only unlocked files."
        }
        if strictMentionOnlyScope {
            if sessionMentionedPaths.isEmpty {
                return "🎯 Strict Scope Policy Active: No files have been @mentioned or unlocked for editing in this session. Ask the user to @mention the target file or unlock Strict Scope."
            }
            if !sessionMentionedPaths.contains(canon) {
                let allowedList = sessionMentionedPaths.map { URL(fileURLWithPath: $0).lastPathComponent }.sorted().joined(separator: ", ")
                return "🎯 Strict Scope Policy: '\(fileName)' is outside the allowed editing scope. You may ONLY modify explicitly @mentioned/active files: [\(allowedList)]."
            }
        }
        return nil
    }

    private func storageKeyPrefix(for root: String) -> String {
        let canon = WorkspacePathPolicy.canonicalPath(root)
        return "MicroCode.ScopeGuard.\(canon)"
    }

    private func saveCurrentWorkspaceState() {
        guard !activeWorkspaceRoot.isEmpty else { return }
        let keyPrefix = storageKeyPrefix(for: activeWorkspaceRoot)
        UserDefaults.standard.set(Array(lockedPaths), forKey: "\(keyPrefix).lockedPaths")
        UserDefaults.standard.set(strictMentionOnlyScope, forKey: "\(keyPrefix).strictScope")
    }
}

