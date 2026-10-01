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
import CryptoKit
import AuthenticationServices

private final class OAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: NSWindow

    init(window: NSWindow) {
        self.window = window
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }
}

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
                case "SUPABASE_ANON_KEY": return ""
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
        let role: String
        let tokensRemaining: Int
        let tokensUsed: Int
        let isLoaded: Bool

        static let unknown = Entitlement(plan: "", role: "", tokensRemaining: 0, tokensUsed: 0, isLoaded: false)
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

    private let defaults: UserDefaults
    private let network: URLSession
    private let configurationProvider: () -> Configuration?
    private var pendingOAuth: (state: String, verifier: String, redirect: URL, expires: Date)?
    private var webAuthSession: ASWebAuthenticationSession?
    private var webAuthContext: OAuthPresentationContext?
    private var webAuthID: UUID?
    private var refreshTask: Task<String?, Never>?
    private var sessionGeneration = UUID()

    init(defaults: UserDefaults = .standard, network: URLSession = .shared,
         configuration: @escaping () -> Configuration? = { Configuration.load() }) {
        self.defaults = defaults
        self.network = network
        self.configurationProvider = configuration
        restorePersistedSession()
        clearLegacyCredentials()
    }

    private func clearLegacyCredentials() {
        ["cloudGPUAuthToken", "cloudGPURefreshToken", "microRentToken", "dotminiLicenseKey"].forEach {
            defaults.removeObject(forKey: $0)
        }
    }

    var isConfigured: Bool { configurationProvider() != nil }
    var accessToken: String? { session?.accessToken }
    var currentEmail: String { session?.email ?? defaults.string(forKey: "dotminiUserEmail") ?? "" }

    /// The public Supabase anon key is configuration, not a user credential.
    /// It is fetched from the MicroCode host on first launch so distributed
    /// builds never carry server keys or a developer's local Secrets.plist.
    func bootstrapConfiguration() async -> Bool {
        if configurationProvider() != nil { return true }
        if let cached = Configuration.cached() {
            Configuration.cache(cached)
            return true
        }
        do {
            let (data, response) = try await network.data(from: Configuration.remoteConfigurationURL)
            if (response as? HTTPURLResponse)?.statusCode == 200,
               let raw = try JSONSerialization.jsonObject(with: data) as? [String: String],
               let urlString = raw["url"], let url = URL(string: urlString),
               let anonKey = raw["anon_key"], !anonKey.isEmpty {
                Configuration.cache(Configuration(baseURL: url, anonKey: anonKey,
                                                  redirectURL: raw["redirect_url"] ?? "microcode://auth/callback"))
                return true
            }
        } catch { }
        return false
    }

    func signIn(email: String, password: String) async throws -> Session {
        guard await bootstrapConfiguration() else { throw AuthError.unconfigured }
        guard let configuration = configurationProvider() else { throw AuthError.unconfigured }
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
        let generation = sessionGeneration
        guard await bootstrapConfiguration() else { throw AuthError.unconfigured }
        guard let configuration = configurationProvider() else { throw AuthError.unconfigured }
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
        let (data, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.rejected("Unable to create your account. Check the details and try again.")
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AuthError.invalidResponse }
        guard generation == sessionGeneration else { throw CancellationError() }
        guard raw["access_token"] as? String != nil else { return nil }
        return try await consumeSessionPayload(raw)
    }

    /// GoTrue authorization-code flow. Only the matching in-memory PKCE attempt
    /// can consume the callback; bearer tokens in deep links are never accepted.
    func makeOAuthURL(provider: String) throws -> URL {
        guard let configuration = configurationProvider(),
              var redirect = URLComponents(string: configuration.redirectURL),
              redirect.scheme == "microcode", redirect.host == "auth", redirect.path == "/callback" else {
            throw AuthError.unconfigured
        }
        let state = UUID().uuidString
        let verifier = UUID().uuidString + UUID().uuidString
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        redirect.queryItems = [URLQueryItem(name: "state", value: state)]
        guard let callback = redirect.url else { throw AuthError.unconfigured }
        pendingOAuth = (state, verifier, callback, Date().addingTimeInterval(600))
        return configuration.baseURL.appending(path: "auth/v1/authorize").appending(queryItems: [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: callback.absoluteString),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256")
        ])
    }

    func startOAuth(provider: String) async throws {
        guard await bootstrapConfiguration() else { throw AuthError.unconfigured }
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else {
            throw AuthError.rejected("Open a MicroCode window before signing in.")
        }
        webAuthID = nil
        webAuthSession?.cancel()
        webAuthSession = nil
        webAuthContext = nil
        let authURL = try makeOAuthURL(provider: provider)
        let attemptID = UUID()
        webAuthID = attemptID
        let context = OAuthPresentationContext(window: window)
        let browserSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "microcode") { [weak self] callbackURL, _ in
            Task { @MainActor in
                guard let self, self.webAuthID == attemptID else { return }
                self.webAuthID = nil
                self.webAuthSession = nil
                self.webAuthContext = nil
                if let callbackURL {
                    NotificationCenter.default.post(name: Notification.Name("MicroCodeOAuthCallback"), object: callbackURL)
                } else {
                    self.pendingOAuth = nil
                }
            }
        }
        browserSession.presentationContextProvider = context
        webAuthContext = context
        webAuthSession = browserSession
        guard browserSession.start() else {
            webAuthID = nil
            webAuthSession = nil
            webAuthContext = nil
            pendingOAuth = nil
            throw AuthError.rejected("Could not open the sign-in browser. Please try again.")
        }
    }

    func handleCallback(_ url: URL) async -> Bool {
        guard let pending = pendingOAuth, pending.expires > Date(),
              url.scheme == pending.redirect.scheme, url.host == pending.redirect.host,
              url.path == pending.redirect.path, url.fragment == nil,
              url.port == pending.redirect.port, url.user == nil, url.password == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let configuration = configurationProvider() else { return false }
        let items = components.queryItems ?? []
        let states = items.filter { $0.name == "state" }
        let codes = items.filter { $0.name == "code" }
        guard states.count == 1, states.first?.value == pending.state,
              codes.count == 1, let code = codes.first?.value, !code.isEmpty else { return false }
        pendingOAuth = nil // one attempt, including failed/replayed exchanges
        let generation = sessionGeneration
        var request = URLRequest(url: configuration.baseURL.appending(path: "auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "pkce")]))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["auth_code": code, "code_verifier": pending.verifier])
        do {
            let saved = try await fetchSession(request)
            guard generation == sessionGeneration else { return false }
            sessionGeneration = UUID()
            refreshTask?.cancel()
            refreshTask = nil
            try persist(saved)
            await refreshEntitlement()
            return true
        } catch { return false }
    }

    @discardableResult
    func refreshAccessTokenIfNeeded(force: Bool = false) async -> String? {
        if let refreshTask { return await refreshTask.value }
        guard let existing = session else { return nil }
        if !force && !existing.isExpired { return existing.accessToken }
        guard let configuration = configurationProvider(), !existing.refreshToken.isEmpty else { return nil }
        let generation = sessionGeneration
        let task = Task { @MainActor () -> String? in
            var request = URLRequest(url: configuration.baseURL.appending(path: "auth/v1/token")
                .appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")]))
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": existing.refreshToken])
            do {
                let saved = try await self.fetchSession(request)
                guard !Task.isCancelled, generation == self.sessionGeneration,
                      existing.userID.isEmpty || saved.userID == existing.userID else { return nil }
                try self.persist(saved)
                return saved.accessToken
            } catch { return nil } // outages must not erase a recoverable refresh credential
        }
        refreshTask = task
        let value = await task.value
        if generation == sessionGeneration { refreshTask = nil }
        return value
    }

    func refreshEntitlement() async {
        guard let configuration = configurationProvider(),
              let token = await refreshAccessTokenIfNeeded(),
              let userID = session?.userID, !userID.isEmpty else { return }
        // Dotmini Cloud stores roles and plans in public.users. The old
        // profiles table does not exist in production, so a failed lookup
        // must never be presented as a verified Free entitlement.
        var components = URLComponents(url: configuration.baseURL.appending(path: "rest/v1/users"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "role,plan,ai_quota,ai_used"),
            URLQueryItem(name: "id", value: "eq.\(userID)")
        ]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await network.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let profile = rows.first else {
            if session?.userID == userID { entitlement = .unknown }
            return
        }
        guard session?.userID == userID, session != nil else { return }
        let quota = max(0, profile["ai_quota"] as? Int ?? 0)
        let used = max(0, profile["ai_used"] as? Int ?? 0)
        entitlement = Entitlement(
            plan: profile["plan"] as? String ?? "",
            role: profile["role"] as? String ?? "",
            tokensRemaining: max(0, quota - used),
            tokensUsed: used,
            isLoaded: true
        )
    }

    func signOut() {
        sessionGeneration = UUID()
        webAuthID = nil
        webAuthSession?.cancel()
        webAuthSession = nil
        webAuthContext = nil
        pendingOAuth = nil
        refreshTask?.cancel()
        refreshTask = nil
        KeychainManager.shared.deleteIntegrationSecret(account: sessionAccount)
        KeychainManager.shared.deleteIntegrationSecret(account: accessTokenAccount)
        KeychainManager.shared.deleteIntegrationSecret(account: refreshTokenAccount)
        let defaults = defaults
        ["cloudGPUAuthToken", "cloudGPURefreshToken", "microRentToken", "dotminiLicenseKey", "dotminiUserEmail"].forEach { defaults.removeObject(forKey: $0) }
        session = nil
        entitlement = .unknown
    }

    private func consumeSessionResponse(_ request: URLRequest) async throws -> Session {
        let generation = sessionGeneration
        let saved = try await fetchSession(request)
        guard generation == sessionGeneration else { throw CancellationError() }
        sessionGeneration = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        try persist(saved)
        await refreshEntitlement()
        return saved
    }

    private func fetchSession(_ request: URLRequest) async throws -> Session {
        let (data, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthError.rejected("Authentication failed (HTTP \(http.statusCode)). Please sign in again.")
        }
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AuthError.invalidResponse }
        return try decodeSession(raw)
    }

    private func decodeSession(_ raw: [String: Any]) throws -> Session {
        guard let access = raw["access_token"] as? String, !access.isEmpty,
              let refresh = raw["refresh_token"] as? String, !refresh.isEmpty,
              let user = raw["user"] as? [String: Any],
              let id = user["id"] as? String, !id.isEmpty,
              let expires = (raw["expires_in"] as? NSNumber)?.doubleValue, expires > 60 else {
            throw AuthError.invalidResponse
        }
        return Session(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expires),
                       userID: id, email: user["email"] as? String ?? "")
    }

    private func consumeSessionPayload(_ raw: [String: Any]) async throws -> Session {
        let saved = try decodeSession(raw)
        sessionGeneration = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        try persist(saved)
        await refreshEntitlement()
        return saved
    }

    private func persist(_ newSession: Session) throws {
        let encoded = String(decoding: try JSONEncoder().encode(newSession), as: UTF8.self)
        guard KeychainManager.shared.saveIntegrationSecret(encoded, account: sessionAccount) else {
            throw AuthError.rejected("Could not save your session to macOS Keychain.")
        }
        if session?.userID != newSession.userID { entitlement = .unknown }
        session = newSession
        KeychainManager.shared.deleteIntegrationSecret(account: accessTokenAccount)
        KeychainManager.shared.deleteIntegrationSecret(account: refreshTokenAccount)
        clearLegacyCredentials()
        if !newSession.email.isEmpty { defaults.set(newSession.email, forKey: "dotminiUserEmail") }
        // Identity refresh must never change the user's selected inference mode.
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
        session = Session(accessToken: access, refreshToken: refresh, expiresAt: nil, userID: "", email: defaults.string(forKey: "dotminiUserEmail") ?? "")
    }

    private func expiry(from seconds: String?) -> Date? {
        guard let seconds, let interval = TimeInterval(seconds) else { return nil }
        return Date().addingTimeInterval(interval)
    }
}
