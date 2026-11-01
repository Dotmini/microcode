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

// MARK: - Universal Per-User Storage & Workspace State Isolation

/// Centralizes default project directories (`~/Documents/MicroCodeProjects` / `~/MicroCodeProjects`)
/// and per-workspace IDE runtime state (`~/.microcode/workspaces/<slug>-<hash>/`) so MicroCode
/// works identically for every macOS user and never dumps auto-generated folders or `.microcode/`
/// metadata inside user source-code repositories.
enum WorkspaceStoragePaths {
    /// Dynamic home directory for the currently logged-in macOS user (never hardcoded).
    static var userHomeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    /// Global `~/.microcode` root directory under the current user's Home folder.
    static var microcodeHomeDirectory: URL {
        let dir = userHomeDirectory.appendingPathComponent(".microcode", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Universal default parent directory for QuickStart and newly created projects:
    /// 1. Honors an explicit user setting (`MicroCode.DefaultProjectsDirectory`) if configured and writable.
    /// 2. Defaults to `~/Documents/MicroCodeProjects` for every macOS user.
    /// 3. Falls back to `~/MicroCodeProjects` under the user's Home directory if `~/Documents` is unavailable.
    static func defaultProjectsRootDirectory() -> URL {
        let fm = FileManager.default

        if let customPath = UserDefaults.standard.string(forKey: "MicroCode.DefaultProjectsDirectory")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !customPath.isEmpty {
            let expanded = (customPath as NSString).expandingTildeInPath
            let customURL = URL(fileURLWithPath: expanded, isDirectory: true)
            if (try? fm.createDirectory(at: customURL, withIntermediateDirectories: true)) != nil,
               fm.isWritableFile(atPath: customURL.path) {
                return customURL
            }
        }

        let documentsBase = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? userHomeDirectory.appendingPathComponent("Documents", isDirectory: true)
        let documentsProjects = documentsBase.appendingPathComponent("MicroCodeProjects", isDirectory: true)
        if (try? fm.createDirectory(at: documentsProjects, withIntermediateDirectories: true)) != nil,
           fm.isWritableFile(atPath: documentsProjects.path) {
            return documentsProjects
        }

        let homeProjects = userHomeDirectory.appendingPathComponent("MicroCodeProjects", isDirectory: true)
        try? fm.createDirectory(at: homeProjects, withIntermediateDirectories: true)
        return homeProjects
    }

    /// Deterministic 64-bit FNV-1a hex digest (16 hex chars) for collision-free workspace state directories.
    private static func stableHashHex(_ input: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }

    /// Isolated per-workspace state directory inside `~/.microcode/workspaces/<name>-<hash>/`.
    /// Never creates or touches `<workspace>/.microcode/` inside the user's source code folder.
    static func workspaceStateDirectory(for workspacePath: String?) -> URL {
        let fm = FileManager.default
        let workspacesRoot = microcodeHomeDirectory.appendingPathComponent("workspaces", isDirectory: true)
        guard let raw = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            let globalDir = workspacesRoot.appendingPathComponent("_global", isDirectory: true)
            try? fm.createDirectory(at: globalDir, withIntermediateDirectories: true)
            return globalDir
        }

        let canonical = WorkspacePathPolicy.canonicalPath(raw)
        let rawName = URL(fileURLWithPath: canonical).lastPathComponent
        let sanitizedName = rawName
            .replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        let prefix = sanitizedName.isEmpty ? "workspace" : String(sanitizedName.prefix(40))
        let shortHash = String(stableHashHex(canonical).prefix(12))
        let dir = workspacesRoot.appendingPathComponent("\(prefix)-\(shortHash)", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Returns a URL inside `~/.microcode/workspaces/<id>/<relativePath>` for MicroCode-managed runtime files
    /// (`AI.arx`, `task.md`, `walkthrough.md`, managed `agent.md`, `checkpoints`, `vectors`, `scenarios`, etc.).
    static func managedStateFile(named relativePath: String, workspacePath: String?) -> URL {
        let cleanRel = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = workspaceStateDirectory(for: workspacePath)
        guard !cleanRel.isEmpty else { return base }
        return base.appendingPathComponent(cleanRel)
    }

    /// Resolves a readable state/config file: prefers `~/.microcode/workspaces/<id>/<relativePath>` if it exists,
    /// falls back to `<workspace>/.microcode/<relativePath>` ONLY if the user explicitly created/committed it in the repo,
    /// otherwise returns the managed `~/.microcode/workspaces/<id>/<relativePath>` URL (never creating `<workspace>/.microcode`).
    static func readableWorkspaceOrStateFile(named relativePath: String, workspacePath: String?) -> URL {
        let fm = FileManager.default
        let managedURL = managedStateFile(named: relativePath, workspacePath: workspacePath)
        if fm.fileExists(atPath: managedURL.path) {
            return managedURL
        }
        if let ws = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !ws.isEmpty {
            let cleanRel = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let legacyRepoURL = URL(fileURLWithPath: ws, isDirectory: true)
                .appendingPathComponent(".microcode", isDirectory: true)
                .appendingPathComponent(cleanRel)
            if fm.fileExists(atPath: legacyRepoURL.path) {
                return legacyRepoURL
            }
        }
        return managedURL
    }

    /// Transparently redirects tool file paths targeting `<workspace>/.microcode/...` into
    /// `~/.microcode/workspaces/<id>/...` unless the target file was explicitly committed/present in `<workspace>/.microcode/`.
    static func redirectWorkspaceDotMicrocodePathIfNeeded(_ resolvedPath: String, workspaceRoot: String?) -> String {
        guard let root = workspaceRoot?.trimmingCharacters(in: .whitespacesAndNewlines), !root.isEmpty else {
            return resolvedPath
        }
        let cleanRoot = root.hasSuffix("/") ? String(root.dropLast()) : root
        let dotMicrocodePrefix = cleanRoot + "/.microcode"
        if resolvedPath == dotMicrocodePrefix || resolvedPath == dotMicrocodePrefix + "/" {
            return workspaceStateDirectory(for: cleanRoot).path
        }
        guard resolvedPath.hasPrefix(dotMicrocodePrefix + "/") else {
            return resolvedPath
        }
        let subpath = String(resolvedPath.dropFirst((dotMicrocodePrefix + "/").count))
        let alwaysManagedTopLevel: Set<String> = [
            "task.md", "walkthrough.md", "AI.arx", "team-tasks.json", "checkpoints", "vectors"
        ]
        let firstComponent = subpath.components(separatedBy: "/").first ?? subpath
        if alwaysManagedTopLevel.contains(firstComponent) || !FileManager.default.fileExists(atPath: resolvedPath) {
            return managedStateFile(named: subpath, workspacePath: cleanRoot).path
        }
        return resolvedPath
    }

    /// Relocates stray auto-generated `QuickStart-XX` folders (containing only `.microcode` metadata or empty)
    /// out of source-code parent directories into `~/Documents/MicroCodeProjects/QuickStart-XX`, moving internal
    /// `.microcode/` runtime files into `~/.microcode/workspaces/<id>/`. Works dynamically for every macOS user.
    static func migrateMisplacedQuickStartIfNeeded(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawPath }
        let sourceURL = URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL
        let folderName = sourceURL.lastPathComponent
        guard folderName.hasPrefix("QuickStart-") else { return rawPath }

        let fm = FileManager.default
        let properRoot = defaultProjectsRootDirectory().standardizedFileURL
        let targetURL = properRoot.appendingPathComponent(folderName, isDirectory: true).standardizedFileURL

        func relocateDotMicrocodeToHome(from workspaceDir: URL, destinationWorkspacePath: String) {
            let legacyDotDir = workspaceDir.appendingPathComponent(".microcode", isDirectory: true)
            guard fm.fileExists(atPath: legacyDotDir.path),
                  let items = try? fm.contentsOfDirectory(atPath: legacyDotDir.path) else { return }
            let stateDir = workspaceStateDirectory(for: destinationWorkspacePath)
            try? fm.createDirectory(at: stateDir, withIntermediateDirectories: true)
            for item in items where item != ".DS_Store" {
                let srcItem = legacyDotDir.appendingPathComponent(item)
                let dstItem = stateDir.appendingPathComponent(item)
                if !fm.fileExists(atPath: dstItem.path) {
                    try? fm.moveItem(at: srcItem, to: dstItem)
                } else {
                    try? fm.removeItem(at: srcItem)
                }
            }
            try? fm.removeItem(at: legacyDotDir)
        }

        if sourceURL.path == targetURL.path {
            relocateDotMicrocodeToHome(from: targetURL, destinationWorkspacePath: targetURL.path)
            return targetURL.path
        }

        if fm.fileExists(atPath: sourceURL.path) {
            let entries = (try? fm.contentsOfDirectory(atPath: sourceURL.path))?
                .filter { $0 != ".DS_Store" } ?? []
            if entries.isEmpty || Set(entries).isSubset(of: [".microcode"]) {
                try? fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
                relocateDotMicrocodeToHome(from: sourceURL, destinationWorkspacePath: targetURL.path)
                try? fm.removeItem(at: sourceURL)
                return targetURL.path
            }
            return rawPath
        } else if fm.fileExists(atPath: targetURL.path) {
            return targetURL.path
        }

        return rawPath
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

