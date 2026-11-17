import AppKit
import Foundation

/// App-side glue for MCP authorization: credentials go to KeychainManager's sealed integration-secret
/// store (never plaintext UserDefaults or mcp.json), and sign-in opens the user's default browser.
@MainActor
final class MCPAuthCenter {
    static let shared = MCPAuthCenter()

    private final class KeychainSecretStorage: MCPSecretStorage {
        /// KeychainManager is main-actor only. Callers are main-actor isolated (MCPCredentialStore), but never
        /// trap if that ever changes: hop to the main thread instead of asserting isolation.
        private func onMain<T: Sendable>(_ work: @MainActor () -> T) -> T {
            if Thread.isMainThread { return MainActor.assumeIsolated(work) }
            return DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
        }

        func readSecret(account: String) -> String? {
            onMain { KeychainManager.shared.readIntegrationSecret(account: account) }
        }

        func writeSecret(_ value: String?, account: String) {
            onMain {
                if let value, !value.isEmpty {
                    _ = KeychainManager.shared.saveIntegrationSecret(value, account: account)
                } else {
                    _ = KeychainManager.shared.deleteIntegrationSecret(account: account)
                }
            }
        }
    }

    let store: MCPCredentialStore
    let oauth: MCPOAuthClient

    private init() {
        store = MCPCredentialStore(storage: KeychainSecretStorage())
        oauth = MCPOAuthClient(store: store) { url in
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        // Optional hosted Client ID Metadata Document (preferred over dynamic registration when servers support it).
        if let cimd = UserDefaults.standard.string(forKey: "MicroCode.MCP.ClientIDMetadataURL"), cimd.hasPrefix("https://") {
            oauth.clientIdMetadataDocumentURL = cimd
        }
    }

    /// Authorization header for a remote MCP server, in precedence order:
    /// OAuth access token for its canonical resource → static bearer bound to its origin →
    /// (one-time migration) the legacy name-keyed token, only for user-level servers.
    func authorizationHeader(serverURL: URL, serverName: String, allowLegacyMigration: Bool) async -> String? {
        if let token = await oauth.validAccessToken(for: serverURL) {
            return "Bearer \(token)"
        }
        guard let origin = MCPAuthSupport.origin(of: serverURL) else { return nil }
        if let bearer = store.bearerToken(forOrigin: origin), !bearer.isEmpty {
            return bearer.lowercased().hasPrefix("bearer ") ? bearer : "Bearer \(bearer)"
        }
        let legacyKey = "microcode.mcp.bearer.\(serverName.lowercased())"
        if allowLegacyMigration, let legacy = UserDefaults.standard.string(forKey: legacyKey), !legacy.isEmpty {
            // Bind the old name-keyed token to this (user-level) server's origin and drop the plaintext copy.
            store.saveBearerToken(legacy, forOrigin: origin)
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return legacy.lowercased().hasPrefix("bearer ") ? legacy : "Bearer \(legacy)"
        }
        return nil
    }

    func saveStaticBearer(_ token: String, serverURL: URL) {
        guard let origin = MCPAuthSupport.origin(of: serverURL) else { return }
        store.saveBearerToken(token, forOrigin: origin)
    }

    func signOut(serverURL: URL) {
        store.deleteTokens(forResource: MCPAuthSupport.canonicalResource(serverURL))
        if let origin = MCPAuthSupport.origin(of: serverURL) {
            store.saveBearerToken(nil, forOrigin: origin)
        }
    }
}
