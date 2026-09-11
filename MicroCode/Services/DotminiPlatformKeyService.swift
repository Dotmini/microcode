//
//  DotminiPlatformKeyService.swift
//  MicroCode
//
//  A Platform API key is a developer credential, distinct from a Supabase
//  login session. It is created by Dotmini Platform and kept only in Keychain.
//

import Foundation
import Combine

@MainActor
final class DotminiPlatformKeyService: ObservableObject {
    static let shared = DotminiPlatformKeyService()

    static let keychainAccount = "dotmini.platform.api-key.v1"

    @Published private(set) var apiKey: String = ""
    @Published private(set) var validationMessage = ""
    @Published private(set) var isValidating = false

    private init() {
        apiKey = KeychainManager.shared.readIntegrationSecret(account: Self.keychainAccount) ?? ""
    }

    var isConfigured: Bool { !apiKey.isEmpty }
    var maskedKey: String {
        guard apiKey.count > 12 else { return apiKey.isEmpty ? "Not connected" : "••••••••" }
        return "\(apiKey.prefix(10))••••\(apiKey.suffix(4))"
    }

    /// Platform accepts the current OpenAI-compatible key plus the older
    /// MicroCode prefix during migration. The server remains authoritative.
    func save(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("sk-dotmini-") || value.hasPrefix("mci-live-") else {
            validationMessage = "Use a Dotmini Platform key (sk-dotmini-… or mci-live-…)."
            return false
        }
        guard KeychainManager.shared.saveIntegrationSecret(value, account: Self.keychainAccount) else {
            validationMessage = "Could not save the key to macOS Keychain."
            return false
        }
        apiKey = value
        validationMessage = "Platform key saved securely on this Mac."
        return true
    }

    func remove() {
        KeychainManager.shared.deleteIntegrationSecret(account: Self.keychainAccount)
        apiKey = ""
        validationMessage = "Platform key removed from this Mac."
    }

    /// Prefer a Platform key whenever one exists. This keeps one developer
    /// credential valid across Omni, Cloud Runtime and model discovery.
    var authorizationToken: String? {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func validate() async -> Bool {
        guard let key = authorizationToken else {
            validationMessage = "Add a Platform key first."
            return false
        }
        isValidating = true
        defer { isValidating = false }

        let base = StreamableAIProvider.cloudProxyURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/models") else {
            validationMessage = "The Platform endpoint is invalid."
            return false
        }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if (200..<300).contains(http.statusCode) {
                // The production catalog is public, including when an invalid
                // Bearer token is supplied. It cannot attest to key validity.
                validationMessage = "Model catalog reachable. Key permissions are not verified by this public endpoint."
                return false
            }
            validationMessage = http.statusCode == 401 || http.statusCode == 403
                ? "The Platform rejected this key. Create or rotate it in Dotmini Platform."
                : "Platform validation failed (HTTP \(http.statusCode))."
        } catch {
            validationMessage = "Could not reach Platform: \(error.localizedDescription)"
        }
        return false
    }
}
