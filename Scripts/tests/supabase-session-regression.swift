import Foundation

// Compile with SupabaseAuthService.swift only. Never access the real Keychain.
@MainActor
final class KeychainManager {
    static let shared = KeychainManager()
    var values: [String: String] = [:]
    func readIntegrationSecret(account: String) -> String? { values[account] }
    func saveIntegrationSecret(_ value: String, account: String) -> Bool {
        values[account] = value
        return true
    }
    func deleteIntegrationSecret(account: String) { values.removeValue(forKey: account) }
}

@main
struct SessionRegressionTests {
    @MainActor
    static func main() throws {
        typealias Session = SupabaseAuthService.Session
        let unknown = Session(accessToken: "test", refreshToken: "test-refresh",
                              expiresAt: nil, userID: "test-user", email: "test@example.invalid")
        precondition(unknown.isExpired, "Legacy sessions must refresh when expiry is unknown")
        let expired = Session(accessToken: "test", refreshToken: "test-refresh",
                              expiresAt: Date().addingTimeInterval(-120),
                              userID: "test-user", email: "test@example.invalid")
        precondition(expired.isExpired)
        let valid = Session(accessToken: "test", refreshToken: "test-refresh",
                            expiresAt: Date().addingTimeInterval(3600),
                            userID: "test-user", email: "test@example.invalid")
        precondition(!valid.isExpired)
        let encoded = String(data: try JSONEncoder().encode(valid), encoding: .utf8)!
        KeychainManager.shared.values["supabase.session.v1"] = encoded
        let restored = SupabaseAuthService.shared.session
        precondition(restored == valid, "Restore must retain expiry, user ID, and refresh token")
        print("PASS: unknown expiry, expired session, valid session, complete session restore")
    }
}
