//
//  GitAuthService.swift
//  MicroCode
//
//  Git hosting authentication via the vendors' own secure CLI flows.
//  Tokens are owned by gh/glab and their credential store, never UserDefaults.
//

import AppKit
import Foundation
import SwiftUI

enum GitHostingProvider: String, CaseIterable, Identifiable {
    case github = "GitHub"
    case gitlab = "GitLab"
    case gitkraken = "GitKraken"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .gitlab: return "point.3.connected.trianglepath.dotted"
        case .gitkraken: return "arrow.triangle.branch"
        }
    }
}

struct GitHostingConnection: Equatable {
    enum State: Equatable {
        case connected(String)
        case disconnected
        case unavailable(String)
        case managedByGit
    }

    let provider: GitHostingProvider
    var state: State
}

private struct GitCLIResult: Sendable {
    let output: String
    let exitCode: Int32
}

@MainActor
final class GitAuthService: ObservableObject {
    static let shared = GitAuthService()

    @Published private(set) var connections: [GitHostingConnection] = []
    @Published private(set) var authenticatingProvider: GitHostingProvider?
    @Published private(set) var message = ""

    private init() {
        connections = GitHostingProvider.allCases.map { GitHostingConnection(provider: $0, state: .disconnected) }
    }

    func refresh() {
        Task {
            var refreshed: [GitHostingConnection] = []
            for provider in GitHostingProvider.allCases {
                refreshed.append(await connection(for: provider))
            }
            connections = refreshed
        }
    }

    func connection(for provider: GitHostingProvider) -> GitHostingConnection {
        connections.first(where: { $0.provider == provider })
            ?? GitHostingConnection(provider: provider, state: .disconnected)
    }

    func signIn(_ provider: GitHostingProvider) {
        guard authenticatingProvider == nil else { return }
        switch provider {
        case .github, .gitlab:
            guard let executable = executable(for: provider) else {
                message = provider == .gitlab
                    ? "Install GitLab CLI (glab) to sign in securely."
                    : "GitHub CLI (gh) was not found."
                refresh()
                return
            }
            authenticatingProvider = provider
            message = "Opening (provider.rawValue) in your browser. Complete the secure sign-in there."
            Task {
                let arguments: [String]
                if provider == .github {
                    // gh writes its OAuth token to macOS Keychain when available. The
                    // requested scopes are only those needed for repository + Actions work.
                    arguments = ["auth", "login", "--hostname", "github.com", "--web", "--clipboard", "--git-protocol", "https", "--skip-ssh-key", "--scopes", "repo,read:org,workflow"]
                } else {
                    arguments = ["auth", "login", "--hostname", "gitlab.com", "--web"]
                }
                let result = await Self.execute(executable: executable, arguments: arguments)
                if provider == .github, result.exitCode == 0 {
                    _ = await Self.execute(executable: executable, arguments: ["auth", "setup-git"])
                }
                authenticatingProvider = nil
                message = result.exitCode == 0
                    ? "(provider.rawValue) connected. Git credentials are managed by its secure credential store."
                    : Self.userFacingError(result.output, fallback: "(provider.rawValue) sign-in did not finish.")
                refresh()
            }

        case .gitkraken:
            message = "GitKraken uses the same Git remotes and macOS Keychain/SSH credentials. Connect the account in GitKraken, then return here."
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.axosoft.GitKraken") {
                NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
            } else if let url = URL(string: "https://www.gitkraken.com/download") {
                NSWorkspace.shared.open(url)
            }
            refresh()
        }
    }

    func signOut(_ provider: GitHostingProvider) {
        guard let executable = executable(for: provider) else { return }
        Task {
            let arguments = provider == .github
                ? ["auth", "logout", "--hostname", "github.com"]
                : ["auth", "logout", "--hostname", "gitlab.com"]
            let result = await Self.execute(executable: executable, arguments: arguments)
            message = result.exitCode == 0 ? "(provider.rawValue) disconnected." : Self.userFacingError(result.output, fallback: "Could not disconnect (provider.rawValue).")
            refresh()
        }
    }

    private func connection(for provider: GitHostingProvider) async -> GitHostingConnection {
        guard provider != .gitkraken else {
            return GitHostingConnection(provider: provider, state: .managedByGit)
        }
        guard let executable = executable(for: provider) else {
            let name = provider == .github ? "GitHub CLI (gh)" : "GitLab CLI (glab)"
            return GitHostingConnection(provider: provider, state: .unavailable("Install (name) to connect."))
        }
        let arguments = provider == .github
            ? ["auth", "status", "--hostname", "github.com"]
            : ["auth", "status", "--hostname", "gitlab.com"]
        let result = await Self.execute(executable: executable, arguments: arguments)
        guard result.exitCode == 0 else {
            return GitHostingConnection(provider: provider, state: .disconnected)
        }
        let account = Self.accountName(from: result.output) ?? "connected"
        return GitHostingConnection(provider: provider, state: .connected(account))
    }

    private func executable(for provider: GitHostingProvider) -> URL? {
        let names: [String]
        switch provider {
        case .github: names = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        case .gitlab: names = ["/opt/homebrew/bin/glab", "/usr/local/bin/glab", "/usr/bin/glab"]
        case .gitkraken: return nil
        }
        return names.map(URL.init(fileURLWithPath:)).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    private static func execute(executable: URL, arguments: [String]) async -> GitCLIResult {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = error
            do {
                try process.run()
                process.waitUntilExit()
                let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return GitCLIResult(output: (stdout + stderr).trimmingCharacters(in: .whitespacesAndNewlines), exitCode: process.terminationStatus)
            } catch {
                return GitCLIResult(output: error.localizedDescription, exitCode: -1)
            }
        }.value
    }

    private static func accountName(from output: String) -> String? {
        // `gh auth status` and `glab auth status` both include the account after
        // "account" or "Logged in to". Keep this display-only and best-effort.
        let line = output.split(separator: "\n").first(where: { $0.localizedCaseInsensitiveContains("account") || $0.localizedCaseInsensitiveContains("logged in") })
        guard let line else { return nil }
        return String(line).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func userFacingError(_ output: String, fallback: String) -> String {
        let compact = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? fallback : compact
    }
}

struct GitHostingAccountsView: View {
    @ObservedObject private var auth = GitAuthService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(GitHostingProvider.allCases) { provider in
                let connection = auth.connection(for: provider)
                HStack(spacing: 10) {
                    Image(systemName: provider.icon).frame(width: 18).foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.rawValue).font(.system(size: 12, weight: .semibold))
                        Text(statusText(connection.state)).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    }
                    Spacer()
                    accountAction(provider, state: connection.state)
                }
                if provider != .gitkraken { Divider() }
            }
            if !auth.message.isEmpty {
                Text(auth.message).font(.caption).foregroundColor(.secondary)
            }
        }
        .onAppear { auth.refresh() }
    }

    @ViewBuilder
    private func accountAction(_ provider: GitHostingProvider, state: GitHostingConnection.State) -> some View {
        switch state {
        case .connected:
            Button("Sign out") { auth.signOut(provider) }.buttonStyle(.bordered).controlSize(.small)
        case .managedByGit:
            Button("Open") { auth.signIn(provider) }.buttonStyle(.bordered).controlSize(.small)
        case .disconnected, .unavailable:
            if auth.authenticatingProvider == provider {
                ProgressView().controlSize(.small)
            } else {
                Button("Connect") { auth.signIn(provider) }.buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
    }

    private func statusText(_ state: GitHostingConnection.State) -> String {
        switch state {
        case .connected(let account): return account
        case .disconnected: return "Not connected"
        case .unavailable(let detail): return detail
        case .managedByGit: return "Uses standard Git remotes and system credentials"
        }
    }
}
