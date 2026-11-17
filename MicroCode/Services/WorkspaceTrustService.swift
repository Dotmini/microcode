import AppKit
import CryptoKit
import Foundation

/// Workspace Trust Gate.
///
/// Repo-controlled configuration that can execute code (MCP server commands, lifecycle hooks,
/// project skills with scripts) must never run just because a folder was opened. The user
/// approves each workspace's executable configuration once; the approval is pinned to a
/// SHA-256 fingerprint of the exact config contents, so any later change re-prompts.
@MainActor
final class WorkspaceTrustService {
    static let shared = WorkspaceTrustService()

    enum Kind: String {
        case executableConfig = "exec-config"   // MCP servers + lifecycle hooks
        case projectSkills = "project-skills"
    }

    struct Item: Hashable {
        let label: String     // e.g. "MCP server `github` (.mcp.json)"
        let detail: String    // e.g. the command line that will run
    }

    private let defaultsKey = "MicroCode.WorkspaceTrust.v1"
    /// Fingerprints the user declined during this app session (avoid re-prompting on every rescan).
    private var declinedThisSession: Set<String> = []
    private var promptInFlight: Set<String> = []

    private init() {}

    // MARK: - Fingerprinting

    /// Stable fingerprint over (relative path + contents) of every config file that contributed items.
    nonisolated static func fingerprint(files: [URL], workspaceRoot: String) -> String {
        var hasher = SHA256()
        let root = URL(fileURLWithPath: workspaceRoot).standardizedFileURL.path
        for url in files.map({ $0.standardizedFileURL }).sorted(by: { $0.path < $1.path }) {
            let rel = url.path.hasPrefix(root + "/") ? String(url.path.dropFirst(root.count + 1)) : url.path
            hasher.update(data: Data(rel.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: (try? Data(contentsOf: url)) ?? Data())
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// True when `path` lives inside `workspaceRoot` (repo-controlled), after symlink resolution.
    nonisolated static func isInsideWorkspace(_ path: String, workspaceRoot: String) -> Bool {
        guard !workspaceRoot.isEmpty else { return false }
        let root = URL(fileURLWithPath: workspaceRoot).resolvingSymlinksInPath().standardizedFileURL.path
        let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        return target == root || target.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    // MARK: - Persistence

    private func storageKey(workspace: String, kind: Kind) -> String {
        let canonical = URL(fileURLWithPath: workspace).resolvingSymlinksInPath().standardizedFileURL.path
        return "\(kind.rawValue)|\(canonical)"
    }

    private func loadStore() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    func isTrusted(workspace: String, kind: Kind, fingerprint: String) -> Bool {
        loadStore()[storageKey(workspace: workspace, kind: kind)] == fingerprint
    }

    func trust(workspace: String, kind: Kind, fingerprint: String) {
        var store = loadStore()
        store[storageKey(workspace: workspace, kind: kind)] = fingerprint
        UserDefaults.standard.set(store, forKey: defaultsKey)
        declinedThisSession.remove(fingerprint)
    }

    func revoke(workspace: String, kind: Kind) {
        var store = loadStore()
        store.removeValue(forKey: storageKey(workspace: workspace, kind: kind))
        UserDefaults.standard.set(store, forKey: defaultsKey)
    }

    // MARK: - Gate

    /// Returns true if the items may be used. Prompts the user at most once per fingerprint per
    /// session. Headless modes (ACP/PNS daemons, no NSApp) never prompt and fail closed.
    func requestTrust(workspace: String, kind: Kind, items: [Item], fingerprint: String) -> Bool {
        guard !items.isEmpty else { return true }
        if isTrusted(workspace: workspace, kind: kind, fingerprint: fingerprint) { return true }
        if declinedThisSession.contains(fingerprint) || promptInFlight.contains(fingerprint) { return false }

        let args = CommandLine.arguments
        let headless = args.contains("--acp-server") || args.contains("--pns-daemon") || NSApp == nil
        if headless {
            FlightRecorder.shared.record(action: .agentApprovalDenied, summary: "Workspace trust denied (headless) for \(kind.rawValue): \(workspace)")
            return false
        }

        promptInFlight.insert(fingerprint)
        defer { promptInFlight.remove(fingerprint) }

        let alert = NSAlert()
        alert.alertStyle = .warning
        let folderName = URL(fileURLWithPath: workspace).lastPathComponent
        switch kind {
        case .executableConfig:
            alert.messageText = "Trust commands from “\(folderName)”?"
            alert.informativeText = "This workspace ships configuration that runs programs on your Mac (MCP servers / agent hooks). They will stay disabled until you trust them. Only trust folders you created or fully reviewed.\n\n"
        case .projectSkills:
            alert.messageText = "Enable agent skills from “\(folderName)”?"
            alert.informativeText = "This workspace ships agent skills (instructions and scripts the AI agent can load and run). They will stay disabled until you enable them.\n\n"
        }
        let shown = items.prefix(12).map { "• \($0.label)\n   \($0.detail.prefix(160))" }.joined(separator: "\n")
        let more = items.count > 12 ? "\n…and \(items.count - 12) more" : ""
        alert.informativeText += shown + more
        alert.addButton(withTitle: "Keep Disabled")
        alert.addButton(withTitle: "Trust")

        let response = alert.runModal()
        let trusted = response == .alertSecondButtonReturn
        if trusted {
            trust(workspace: workspace, kind: kind, fingerprint: fingerprint)
            FlightRecorder.shared.record(action: .agentApprovalGranted, summary: "Workspace trust granted for \(kind.rawValue): \(workspace) [\(items.count) items]")
        } else {
            declinedThisSession.insert(fingerprint)
            FlightRecorder.shared.record(action: .agentApprovalDenied, summary: "Workspace trust declined for \(kind.rawValue): \(workspace)")
        }
        return trusted
    }
}
