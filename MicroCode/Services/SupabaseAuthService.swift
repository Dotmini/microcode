//
//  SupabaseAuthService.swift
//  MicroCode
//
//  The single source of truth for MicroCode account sessions.  The desktop
//  client talks only to the self-hosted Supabase Auth/PostgREST endpoints;
//  it never creates a local license or relies on Firebase tokens.
//

import Foundation
import AppKit
import Combine

@MainActor
final class SupabaseAuthService: ObservableObject {
    static let shared = SupabaseAuthService()

    struct Configuration {
        let baseURL: URL
        let anonKey: String
        let redirectURL: String

        static func load() -> Configuration? {
            var values: [String: Any] = [:]
            if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
               let secrets = NSDictionary(contentsOf: url) as? [String: Any] {
                values = secrets
            } else {
                let supportSecrets = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                    .first?.appendingPathComponent("MicroCode/Secrets.plist")
                if let supportSecrets,
                   let secrets = NSDictionary(contentsOf: supportSecrets) as? [String: Any] {
                    values = secrets
                }
                let developmentSecrets = URL(fileURLWithPath: #file)
                    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("Secrets.plist")
                if values.isEmpty {
                    values = (NSDictionary(contentsOf: developmentSecrets) as? [String: Any]) ?? [:]
                }
            }

            func value(_ key: String) -> String {
                let plist = (values[key] as? String) ?? ""
                if !plist.isEmpty { return plist }
                if let environment = ProcessInfo.processInfo.environment[key], !environment.isEmpty { return environment }
                let cachedKey: String
                switch key {
                case "SUPABASE_URL": cachedKey = "microcode.supabase.url"
                case "SUPABASE_ANON_KEY": cachedKey = "microcode.supabase.anon-key"
                case "SUPABASE_AUTH_REDIRECT_URL": cachedKey = "microcode.supabase.redirect-url"
                default: return ""
                }
                let cached = UserDefaults.standard.string(forKey: cachedKey) ?? ""
                if !cached.isEmpty { return cached }
                switch key {
                case "SUPABASE_URL": return "https://supabase-ai.dotmini.net"
                case "SUPABASE_ANON_KEY": return "[REDACTED_SUPABASE_ANON_KEY]"
                case "SUPABASE_AUTH_REDIRECT_URL": return "microcode://auth/callback"
                default: return ""
                }
            }

            let urlString = value("SUPABASE_URL").trimmingCharacters(in: .whitespacesAndNewlines)
            let anonKey = value("SUPABASE_ANON_KEY").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let baseURL = URL(string: urlString), !anonKey.isEmpty else { return nil }
            let redirect = value("SUPABASE_AUTH_REDIRECT_URL")
            return Configuration(
                baseURL: baseURL,
                anonKey: anonKey,
                redirectURL: redirect.isEmpty ? "microcode://auth/callback" : redirect
            )
        }

        static let remoteConfigurationURL = URL(string: "https://microcode.dotmini.net/api/microcode/auth-config")!

        static func cache(_ configuration: Configuration) {
            let defaults = UserDefaults.standard
            defaults.set(configuration.baseURL.absoluteString, forKey: "microcode.supabase.url")
            defaults.set(configuration.anonKey, forKey: "microcode.supabase.anon-key")
            defaults.set(configuration.redirectURL, forKey: "microcode.supabase.redirect-url")
        }

        static func cached() -> Configuration? {
            let defaults = UserDefaults.standard
            guard let urlString = defaults.string(forKey: "microcode.supabase.url"),
                  let baseURL = URL(string: urlString),
                  let anonKey = defaults.string(forKey: "microcode.supabase.anon-key"), !anonKey.isEmpty else { return nil }
            return Configuration(baseURL: baseURL, anonKey: anonKey,
                                 redirectURL: defaults.string(forKey: "microcode.supabase.redirect-url") ?? "microcode://auth/callback")
        }
    }

    struct Session: Codable, Equatable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date?
        let userID: String
        let email: String

        var isExpired: Bool {
            guard let expiresAt else { return true }
            return expiresAt <= Date().addingTimeInterval(60)
        }
    }

    struct Entitlement: Equatable {
        let plan: String
        let freeTokensRemaining: Int
        let monthlyTokensUsed: Int

        static let unknown = Entitlement(plan: "free", freeTokensRemaining: 0, monthlyTokensUsed: 0)
    }

    enum AuthError: LocalizedError {
        case unconfigured
        case invalidResponse
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .unconfigured:
                return "Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to Secrets.plist."
            case .invalidResponse:
                return "Supabase returned an invalid authentication response."
            case .rejected(let message):
                return message
            }
        }
    }

    @Published private(set) var session: Session?
    @Published private(set) var entitlement: Entitlement = .unknown

    private let accessTokenAccount = "supabase.access-token"
    private let refreshTokenAccount = "supabase.refresh-token"
    private let sessionAccount = "supabase.session.v1"

    private init() {
        restorePersistedSession()
    }

    var isConfigured: Bool { Configuration.load() != nil }
    var accessToken: String? { session?.accessToken }
    var currentEmail: String { session?.email ?? UserDefaults.standard.string(forKey: "dotminiUserEmail") ?? "" }

    /// The public Supabase anon key is configuration, not a user credential.
    /// It is fetched from the MicroCode host on first launch so distributed
    /// builds never carry server keys or a developer's local Secrets.plist.
    func bootstrapConfiguration() async -> Bool {
        if Configuration.load() != nil { return true }
        if let cached = Configuration.cached() {
            Configuration.cache(cached)
            return true
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: Configuration.remoteConfigurationURL)
            if (response as? HTTPURLResponse)?.statusCode == 200,
               let raw = try JSONSerialization.jsonObject(with: data) as? [String: String],
               let urlString = raw["url"], let url = URL(string: urlString),
               let anonKey = raw["anon_key"], !anonKey.isEmpty {
                Configuration.cache(Configuration(baseURL: url, anonKey: anonKey,
                                                  redirectURL: raw["redirect_url"] ?? "microcode://auth/callback"))
                return true
            }
        } catch { }
        if let fallbackURL = URL(string: "https://supabase-ai.dotmini.net") {
            let prod = Configuration(
                baseURL: fallbackURL,
                anonKey: "[REDACTED_SUPABASE_ANON_KEY]",
                redirectURL: "microcode://auth/callback"
            )
            Configuration.cache(prod)
            return true
        }
        return false
    }

    func signIn(email: String, password: String) async throws -> Session {
        guard await bootstrapConfiguration() else { throw AuthError.unconfigured }
        guard let configuration = Configuration.load() else { throw AuthError.unconfigured }
        let url = configuration.baseURL.appending(path: "auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        return try await consumeSessionResponse(request)
    }

    /// Creates an account through GoTrue. If email confirmation is enabled,
    /// Supabase intentionally returns no session and the caller must ask the
    /// user to confirm their email before signing in.
    func signUp(email: String, password: String, displayName: String) async throws -> Session? {
        guard await bootstrapConfiguration() else { throw AuthError.unconfigured }
        guard let configuration = Configuration.load() else { throw AuthError.unconfigured }
        var request = URLRequest(url: configuration.baseURL.appending(path: "auth/v1/signup"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
            "data": ["display_name": displayName]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.rejected("Unable to create your account. Check the details and try again.")
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AuthError.invalidResponse }
        guard raw["access_token"] as? String != nil else { return nil }
        return try await consumeSessionPayload(raw)
    }

    func startOAuth(provider: String) async throws {
        guard await bootstrapConfiguration() else { throw AuthError.unconfigured }
        guard let configuration = Configuration.load() else { throw AuthError.unconfigured }
        let url = configuration.baseURL.appending(path: "auth/v1/authorize")
            .appending(queryItems: [
                URLQueryItem(name: "provider", value: provider),
                URLQueryItem(name: "redirect_to", value: configuration.redirectURL)
            ])
        NSWorkspace.shared.open(url)
    }

    /// Handles the implicit-flow callback sent to `microcode://auth/callback`.
    /// Browser fragments are deliberately parsed as well as query items because
    /// GoTrue places access tokens in the fragment for native redirects.
    func handleCallback(_ url: URL) async -> Bool {
        var items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment,
           let fragmentItems = URLComponents(string: "https://callback.invalid/?\(fragment)")?.queryItems {
            items.append(contentsOf: fragmentItems)
        }
        func item(_ name: String) -> String? {
            items.last(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value
        }
        guard let token = item("access_token"), !token.isEmpty else { return false }
        let refresh = item("refresh_token") ?? ""
        let email = item("email") ?? ""
        let userID = item("user_id") ?? item("sub") ?? ""
        persist(Session(accessToken: token, refreshToken: refresh, expiresAt: expiry(from: item("expires_in")), userID: userID, email: email))
        if session?.email.isEmpty ?? true { _ = try? await loadCurrentUser() }
        await refreshEntitlement()
        return true
    }

    @discardableResult
    func refreshAccessTokenIfNeeded(force: Bool = false) async -> String? {
        guard let existing = session else { return nil }
        if !force && !existing.isExpired { return existing.accessToken }
        guard let configuration = Configuration.load(), !existing.refreshToken.isEmpty else { return existing.accessToken }

        let url = configuration.baseURL.appending(path: "auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": existing.refreshToken])
        do {
            return try await consumeSessionResponse(request).accessToken
        } catch {
            // Network outages are not revocation. Keep the refresh credential
            // so the next request can recover without another Google login.
            return nil
        }
    }

    func refreshEntitlement() async {
        guard let configuration = Configuration.load(),
              let token = await refreshAccessTokenIfNeeded(),
              let userID = session?.userID, !userID.isEmpty else { return }
        var components = URLComponents(url: configuration.baseURL.appending(path: "rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "subscription_plan,free_tokens_remaining,ai_monthly_tokens_used"),
            URLQueryItem(name: "id", value: "eq.\(userID)")
        ]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let profile = rows.first else { return }
        entitlement = Entitlement(
            plan: profile["subscription_plan"] as? String ?? "free",
            freeTokensRemaining: profile["free_tokens_remaining"] as? Int ?? 0,
            monthlyTokensUsed: profile["ai_monthly_tokens_used"] as? Int ?? 0
        )
    }

    func signOut() {
        KeychainManager.shared.deleteIntegrationSecret(account: sessionAccount)
        KeychainManager.shared.deleteIntegrationSecret(account: accessTokenAccount)
        KeychainManager.shared.deleteIntegrationSecret(account: refreshTokenAccount)
        let defaults = UserDefaults.standard
        ["cloudGPUAuthToken", "cloudGPURefreshToken", "microRentToken", "dotminiLicenseKey", "dotminiUserEmail"].forEach { defaults.removeObject(forKey: $0) }
        session = nil
        entitlement = .unknown
    }

    private func consumeSessionResponse(_ request: URLRequest) async throws -> Session {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["msg"] as? String)
                ?? ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String)
                ?? "Sign-in failed. Check your email and password."
            throw AuthError.rejected(message)
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AuthError.invalidResponse }
        return try await consumeSessionPayload(raw)
    }

    private func consumeSessionPayload(_ raw: [String: Any]) async throws -> Session {
        guard let access = raw["access_token"] as? String,
              let refresh = raw["refresh_token"] as? String,
              let user = raw["user"] as? [String: Any] else { throw AuthError.invalidResponse }
        let expiresIn = (raw["expires_in"] as? NSNumber)?.doubleValue
        let saved = Session(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) },
            userID: user["id"] as? String ?? "",
            email: user["email"] as? String ?? ""
        )
        persist(saved)
        await refreshEntitlement()
        return saved
    }

    private func loadCurrentUser() async throws -> Session {
        guard let configuration = Configuration.load(), let existing = session else { throw AuthError.unconfigured }
        var request = URLRequest(url: configuration.baseURL.appending(path: "auth/v1/user"))
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(existing.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let user = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AuthError.invalidResponse }
        let updated = Session(accessToken: existing.accessToken, refreshToken: existing.refreshToken, expiresAt: existing.expiresAt, userID: user["id"] as? String ?? existing.userID, email: user["email"] as? String ?? existing.email)
        persist(updated)
        return updated
    }

    private func persist(_ newSession: Session) {
        session = newSession
        if let data = try? JSONEncoder().encode(newSession),
           let encoded = String(data: data, encoding: .utf8) {
            _ = KeychainManager.shared.saveIntegrationSecret(encoded, account: sessionAccount)
        }
        _ = KeychainManager.shared.saveIntegrationSecret(newSession.accessToken, account: accessTokenAccount)
        if !newSession.refreshToken.isEmpty {
            _ = KeychainManager.shared.saveIntegrationSecret(newSession.refreshToken, account: refreshTokenAccount)
        }
        let defaults = UserDefaults.standard
        // Compatibility bridge while service consumers transition. These values
        // are genuine Supabase JWTs, never a locally generated license string.
        defaults.set(newSession.accessToken, forKey: "cloudGPUAuthToken")
        defaults.set(newSession.accessToken, forKey: "microRentToken")
        if !newSession.refreshToken.isEmpty { defaults.set(newSession.refreshToken, forKey: "cloudGPURefreshToken") }
        if !newSession.email.isEmpty { defaults.set(newSession.email, forKey: "dotminiUserEmail") }
        defaults.removeObject(forKey: "dotminiLicenseKey")
        defaults.set("cloud", forKey: "aiKeyMode")
    }

    private func restorePersistedSession() {
        if let encoded = KeychainManager.shared.readIntegrationSecret(account: sessionAccount),
           let data = encoded.data(using: .utf8),
           let restored = try? JSONDecoder().decode(Session.self, from: data) {
            session = restored
            return
        }
        guard let access = KeychainManager.shared.readIntegrationSecret(account: accessTokenAccount), !access.isEmpty else { return }
        let refresh = KeychainManager.shared.readIntegrationSecret(account: refreshTokenAccount) ?? ""
        session = Session(accessToken: access, refreshToken: refresh, expiresAt: nil, userID: "", email: UserDefaults.standard.string(forKey: "dotminiUserEmail") ?? "")
    }

    private func expiry(from seconds: String?) -> Date? {
        guard let seconds, let interval = TimeInterval(seconds) else { return nil }
        return Date().addingTimeInterval(interval)
    }
}
