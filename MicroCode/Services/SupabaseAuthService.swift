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

        static let defaultPublicAnonKey = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc4NDExODEyMCwiZXhwIjo0OTM5NzkxNzIwLCJyb2xlIjoiYW5vbiJ9.mYIkNUopKdGqKfEnzV68pXTni670PFd-nuWXjCx174M"

        static func load() -> Configuration? {
            var values: [String: Any] = [:]
            if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
               let secrets = NSDictionary(contentsOf: url) as? [String: Any] {
                values = secrets
            } else {
                let supportSecrets = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                    .first?.appendingPathComponent("MicroCode/Secrets.plist")
                if let supportSecrets,
                   FileManager.default.fileExists(atPath: supportSecrets.path),
                   let secrets = NSDictionary(contentsOf: supportSecrets) as? [String: Any] {
                    values = secrets
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
                case "SUPABASE_ANON_KEY": return defaultPublicAnonKey
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
        let creditLimitTHB: Double
        let creditUsedTHB: Double
        let creditRemainingTHB: Double
        let aiTopupBalanceTHB: Double
        let totalAvailableTHB: Double
        let marginPct: Double
        let totalTokensUsed: Int64
        let isLoaded: Bool

        var formattedAvailableCredit: String {
            if role.lowercased() == "admin" && totalAvailableTHB <= 0 {
                return "ADMIN"
            }
            return String(format: "฿%.2f", totalAvailableTHB)
        }

        var formattedPlanCreditSummary: String {
            if creditLimitTHB > 0 {
                return String(format: "฿%.2f / ฿%.0f", creditRemainingTHB, creditLimitTHB)
            }
            return String(format: "฿%.2f", creditRemainingTHB)
        }

        static let unknown = Entitlement(
            plan: "",
            role: "",
            tokensRemaining: 0,
            tokensUsed: 0,
            creditLimitTHB: 0,
            creditUsedTHB: 0,
            creditRemainingTHB: 0,
            aiTopupBalanceTHB: 0,
            totalAvailableTHB: 0,
            marginPct: 20,
            totalTokensUsed: 0,
            isLoaded: false
        )
    }

    private struct PersistedEntitlement: Codable {
        let userID: String
        let plan: String
        let role: String
        let tokensRemaining: Int
        let tokensUsed: Int
        let creditLimitTHB: Double?
        let creditUsedTHB: Double?
        let creditRemainingTHB: Double?
        let aiTopupBalanceTHB: Double?
        let totalAvailableTHB: Double?
        let marginPct: Double?
        let totalTokensUsed: Int64?
    }

    private static func defaultMonthlyPlanCreditTHB(for rawPlan: String) -> Double {
        let clean = rawPlan.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "microai_", with: "")
        switch clean {
        case "starter": return 70
        case "lite": return 179
        case "pro": return 529
        case "advanced": return 990
        case "professional": return 1015
        case "bundle_pro", "bundle", "microcode_ai_bundle": return 1365
        case "business": return 1690
        case "team": return 3465
        default: return 0
        }
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
    @Published private(set) var reauthReason: String = ""

    private let accessTokenAccount = "supabase.access-token"
    private let refreshTokenAccount = "supabase.refresh-token"
    private let sessionAccount = "supabase.session.v1"
    private let entitlementAccount = "supabase.entitlement.v1"

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

    /// Strictly true ONLY when an active session has server-verified Admin/Provider role.
    var isAdminProvider: Bool {
        guard session != nil, entitlement.isLoaded else { return false }
        let role = entitlement.role.lowercased()
        return role == "admin" || role == "provider" || role == "owner"
    }

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
            let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let detail = (body["msg"] as? String) ?? (body["message"] as? String) ?? (body["error_description"] as? String) ?? ""
            let lower = detail.lowercased()
            if lower.contains("password") {
                throw AuthError.rejected("รหัสผ่านไม่ผ่านเกณฑ์ความปลอดภัย กรุณาใช้อย่างน้อย 8 ตัวอักษร ผสมตัวอักษรและตัวเลข")
            }
            if lower.contains("already") || lower.contains("registered") {
                throw AuthError.rejected("อีเมลนี้มีบัญชีอยู่แล้ว กรุณาเข้าสู่ระบบ หรือกด “ลืมรหัสผ่าน”")
            }
            if lower.contains("rate limit") || (response as? HTTPURLResponse)?.statusCode == 429 {
                throw AuthError.rejected("ส่งคำขอบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่")
            }
            throw AuthError.rejected(detail.isEmpty ? "สร้างบัญชีไม่สำเร็จ กรุณาตรวจสอบอีเมลและรหัสผ่านแล้วลองใหม่" : "สร้างบัญชีไม่สำเร็จ: \(detail)")
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AuthError.invalidResponse }
        guard generation == sessionGeneration else { throw CancellationError() }
        guard raw["access_token"] as? String != nil else { return nil }
        return try await consumeSessionPayload(raw)
    }

    /// Sends a GoTrue password-recovery email. The response never reveals whether the address has an account.
    func sendPasswordReset(email: String) async throws {
        guard await bootstrapConfiguration() else { throw AuthError.unconfigured }
        guard let configuration = configurationProvider() else { throw AuthError.unconfigured }
        var request = URLRequest(url: configuration.baseURL.appending(path: "auth/v1/recover"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
        let (_, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.rejected("ส่งอีเมลรีเซ็ตรหัสผ่านไม่สำเร็จ กรุณารอสักครู่แล้วลองใหม่")
        }
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
        if let pending = pendingOAuth, pending.expires > Date(),
           url.scheme == pending.redirect.scheme, url.host == pending.redirect.host,
           url.path == pending.redirect.path, url.fragment == nil,
           url.port == pending.redirect.port, url.user == nil, url.password == nil,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let configuration = configurationProvider() {
            let items = components.queryItems ?? []
            let states = items.filter { $0.name == "state" }
            let codes = items.filter { $0.name == "code" }
            if states.count == 1, states.first?.value == pending.state,
               codes.count == 1, let code = codes.first?.value, !code.isEmpty {
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
                    await CloudGPUService.shared.refresh()
                    return true
                } catch { return false }
            }
        }

        // Seamless WebApp -> Desktop IDE deep-link fallback (`microcode://auth?token=...&refresh_token=...` or `#access_token=...`)
        guard url.scheme?.lowercased() == "microcode",
              url.host?.lowercased() == "auth" else { return false }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var params: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            if let v = item.value, !v.isEmpty { params[item.name] = v }
        }
        if let fragment = components?.fragment, !fragment.isEmpty {
            var fragComp = URLComponents()
            fragComp.query = fragment
            for item in fragComp.queryItems ?? [] {
                if let v = item.value, !v.isEmpty { params[item.name] = v }
            }
        }
        let accessToken = (params["access_token"] ?? params["token"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else { return false }
        let refreshToken = (params["refresh_token"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (params["name"] ?? params["display_name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let expiresAtEpoch = params["expires_at"].flatMap(TimeInterval.init)
        return await ingestWebSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAtEpoch: expiresAtEpoch,
            displayName: displayName
        )
    }

    /// Verifies a browser-synced Supabase JWT directly with the self-hosted Supabase Auth server (`auth/v1/user`),
    /// persists the verified session into Keychain, and refreshes subscription entitlement + Cloud GPU wallet silently.
    @discardableResult
    func ingestWebSession(
        accessToken: String,
        refreshToken: String = "",
        expiresAtEpoch: TimeInterval? = nil,
        displayName: String = ""
    ) async -> Bool {
        let cleanAccess = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanAccess.split(separator: ".").count >= 3 else { return false }

        // Skip redundant network round-trip if exact same valid token & loaded entitlement are already active
        if let current = session,
           current.accessToken == cleanAccess,
           !current.userID.isEmpty,
           (refreshToken.isEmpty || current.refreshToken == refreshToken),
           entitlement.isLoaded {
            return true
        }

        _ = await bootstrapConfiguration()
        guard let configuration = configurationProvider() ?? Configuration.cached() else { return false }

        var userReq = URLRequest(url: configuration.baseURL.appending(path: "auth/v1/user"))
        userReq.httpMethod = "GET"
        userReq.timeoutInterval = 8
        userReq.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        userReq.setValue("Bearer \(cleanAccess)", forHTTPHeaderField: "Authorization")

        var verifiedUser: [String: Any]?
        if let (data, response) = try? await network.data(for: userReq),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = obj["id"] as? String, !id.isEmpty {
            verifiedUser = obj
        }

        if verifiedUser == nil {
            let userURL = userReq.url?.absoluteString ?? "https://supabase-ai.dotmini.net/auth/v1/user"
            let anonKey = configuration.anonKey
            let fallbackData = await Task.detached(priority: .userInitiated) {
                Self.curlIPv4JSON(arguments: [
                    userURL,
                    "-H", "apikey: \(anonKey)",
                    "-H", "Authorization: Bearer \(cleanAccess)"
                ])
            }.value
            if let fallbackData,
               let obj = try? JSONSerialization.jsonObject(with: fallbackData) as? [String: Any],
               let id = obj["id"] as? String, !id.isEmpty {
                verifiedUser = obj
            }
        }

        guard let verifiedUser,
              let verifiedUID = verifiedUser["id"] as? String, !verifiedUID.isEmpty else {
            return false
        }

        let verifiedEmail = (verifiedUser["email"] as? String) ?? ""
        let meta = verifiedUser["user_metadata"] as? [String: Any]
        let resolvedName: String = {
            if !displayName.isEmpty { return displayName }
            if let full = meta?["full_name"] as? String, !full.isEmpty { return full }
            if let name = meta?["name"] as? String, !name.isEmpty { return name }
            return verifiedEmail.components(separatedBy: "@").first ?? "Developer"
        }()

        let cleanRefresh: String = {
            let trimmed = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            if let existing = session, existing.userID == verifiedUID, !existing.refreshToken.isEmpty {
                return existing.refreshToken
            }
            return ""
        }()

        let resolvedExpiry: Date = {
            if let expiresAtEpoch, expiresAtEpoch > 1_000_000_000 {
                return Date(timeIntervalSince1970: expiresAtEpoch)
            }
            if let jwtExp = Self.decodeJWTExpiry(cleanAccess) {
                return jwtExp
            }
            return Date().addingTimeInterval(3600)
        }()

        let newSession = Session(
            accessToken: cleanAccess,
            refreshToken: cleanRefresh,
            expiresAt: resolvedExpiry,
            userID: verifiedUID,
            email: verifiedEmail
        )

        do {
            sessionGeneration = UUID()
            refreshTask?.cancel()
            refreshTask = nil
            try persist(newSession)
            await refreshEntitlement()
            AuthService.shared.syncWithWebSession(
                email: verifiedEmail,
                token: cleanAccess,
                displayName: resolvedName
            )
            AppState.shared?.syncGoogleOrDotminiAccount(
                email: verifiedEmail,
                token: cleanAccess,
                displayName: resolvedName
            )
            await CloudGPUService.shared.refresh()
            NotificationCenter.default.post(name: NSNotification.Name("MicroCodeAccountLoggedIn"), object: nil)
            return true
        } catch {
            return false
        }
    }

    private static func decodeJWTExpiry(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = (json["exp"] as? TimeInterval) ?? (json["exp"] as? NSNumber)?.doubleValue else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    /// Builds a secure zero-click WebApp portal URL. When signed in on the Mac, passes session tokens in the URL hash
    /// fragment (`#mc_handoff=1...`, never sent over HTTP headers or server logs) so the browser signs in automatically.
    func authenticatedPortalURL(path: String = "/dashboard") -> URL {
        let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
        let baseStr = "https://microcode.dotmini.net\(cleanPath)"
        guard let current = session, !current.accessToken.isEmpty else {
            return URL(string: baseStr) ?? URL(string: "https://microcode.dotmini.net/dashboard")!
        }
        var frag = URLComponents()
        var items = [
            URLQueryItem(name: "mc_handoff", value: "1"),
            URLQueryItem(name: "access_token", value: current.accessToken)
        ]
        if !current.refreshToken.isEmpty {
            items.append(URLQueryItem(name: "refresh_token", value: current.refreshToken))
        }
        frag.queryItems = items
        if let encodedFrag = frag.percentEncodedQuery,
           let handoffURL = URL(string: "\(baseStr)#\(encodedFrag)") {
            return handoffURL
        }
        return URL(string: baseStr) ?? URL(string: "https://microcode.dotmini.net/dashboard")!
    }

    private enum RefreshOutcome {
        case success(String)
        case transientFailure
        case terminalInvalid
    }

    @discardableResult
    func refreshAccessTokenIfNeeded(force: Bool = false) async -> String? {
        if let refreshTask { return await refreshTask.value }
        if session == nil {
            restorePersistedSession()
        }
        guard let existing = session else { return nil }
        if !force && !existing.isExpired { return existing.accessToken }
        _ = await bootstrapConfiguration()
        guard let configuration = configurationProvider() ?? Configuration.cached() else {
            return existing.isExpired ? nil : existing.accessToken
        }

        // Web-synced sessions without a refresh token: verify whether the JWT is still accepted by GoTrue
        if existing.refreshToken.isEmpty {
            let status = await verifyAccessTokenStatus(existing.accessToken, configuration: configuration)
            if status == 200 {
                return existing.accessToken
            }
            if status == 401 || status == 403 {
                expireDeadSession(reason: "เซสชัน Dotmini Cloud หมดอายุแล้ว กรุณาเข้าสู่ระบบใหม่อีกครั้ง")
                return nil
            }
            return existing.isExpired ? nil : existing.accessToken
        }

        let generation = sessionGeneration
        let task = Task { @MainActor () -> String? in
            let outcome = await self.performRefreshRequest(refreshToken: existing.refreshToken, configuration: configuration, expectedUserID: existing.userID, generation: generation)
            switch outcome {
            case .success(let freshAccess):
                return freshAccess
            case .transientFailure:
                return existing.isExpired ? nil : existing.accessToken
            case .terminalInvalid:
                // Check if the companion app (`MicroCode` <-> `MicroCode AI`) already rotated the single-use GoTrue refresh token
                if let diskEncoded = KeychainManager.shared.reloadIntegrationSecretFromDisk(account: self.sessionAccount),
                   let diskData = diskEncoded.data(using: .utf8),
                   let diskSession = try? JSONDecoder().decode(Session.self, from: diskData),
                   diskSession.userID == existing.userID,
                   (diskSession.accessToken != existing.accessToken || diskSession.refreshToken != existing.refreshToken) {
                    self.session = diskSession
                    self.reauthReason = ""
                    if !diskSession.isExpired {
                        return diskSession.accessToken
                    }
                    if !diskSession.refreshToken.isEmpty {
                        if case .success(let rotatedAccess) = await self.performRefreshRequest(
                            refreshToken: diskSession.refreshToken,
                            configuration: configuration,
                            expectedUserID: diskSession.userID,
                            generation: generation
                        ) {
                            return rotatedAccess
                        }
                    }
                }
                // Confirm whether existing accessToken is also dead before clearing the session
                let userStatus = await self.verifyAccessTokenStatus(existing.accessToken, configuration: configuration)
                if userStatus == 200 {
                    return existing.accessToken
                }
                if generation == self.sessionGeneration {
                    self.expireDeadSession(reason: "เซสชัน Dotmini Cloud หมดอายุแล้ว กรุณาเข้าสู่ระบบใหม่อีกครั้ง")
                }
                return nil
            }
        }
        refreshTask = task
        let value = await task.value
        if generation == sessionGeneration { refreshTask = nil }
        return value
    }

    private func performRefreshRequest(
        refreshToken: String,
        configuration: Configuration,
        expectedUserID: String,
        generation: UUID
    ) async -> RefreshOutcome {
        var request = URLRequest(url: configuration.baseURL.appending(path: "auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")]))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        var responseData: Data?
        var statusCode: Int?

        if let (data, response) = try? await network.data(for: request),
           let http = response as? HTTPURLResponse {
            responseData = data
            statusCode = http.statusCode
        } else if let urlStr = request.url?.absoluteString {
            let anonKey = configuration.anonKey
            let bodyStr = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let fallback = await Task.detached(priority: .userInitiated) {
                Self.curlIPv4Response(arguments: [
                    "-X", "POST", urlStr,
                    "-H", "apikey: \(anonKey)",
                    "-H", "Content-Type: application/json",
                    "-d", bodyStr
                ])
            }.value
            responseData = fallback?.data
            statusCode = fallback?.statusCode
        }

        guard let statusCode, let responseData else { return .transientFailure }
        if (200..<300).contains(statusCode) {
            guard let raw = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                  let saved = try? decodeSession(raw),
                  !Task.isCancelled,
                  generation == sessionGeneration,
                  expectedUserID.isEmpty || saved.userID == expectedUserID else {
                return .transientFailure
            }
            try? persist(saved)
            return .success(saved.accessToken)
        }
        if statusCode == 400 || statusCode == 401 || statusCode == 403 {
            return .terminalInvalid
        }
        return .transientFailure
    }

    private func verifyAccessTokenStatus(_ jwt: String, configuration: Configuration) async -> Int? {
        guard !jwt.isEmpty else { return 401 }
        var req = URLRequest(url: configuration.baseURL.appending(path: "auth/v1/user"), timeoutInterval: 6)
        req.httpMethod = "GET"
        req.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        if let (_, resp) = try? await network.data(for: req),
           let http = resp as? HTTPURLResponse {
            return http.statusCode
        }
        let urlStr = req.url?.absoluteString ?? "https://supabase-ai.dotmini.net/auth/v1/user"
        let anonKey = configuration.anonKey
        let fallback = await Task.detached(priority: .userInitiated) {
            Self.curlIPv4Response(arguments: [
                urlStr,
                "-H", "apikey: \(anonKey)",
                "-H", "Authorization: Bearer \(jwt)"
            ])
        }.value
        return fallback?.statusCode
    }

    private func expireDeadSession(reason: String) {
        let savedEmail = session?.email ?? defaults.string(forKey: "dotminiUserEmail") ?? ""
        cancelPaymentWatch()
        sessionGeneration = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        KeychainManager.shared.deleteIntegrationSecret(account: sessionAccount)
        KeychainManager.shared.deleteIntegrationSecret(account: accessTokenAccount)
        KeychainManager.shared.deleteIntegrationSecret(account: refreshTokenAccount)
        KeychainManager.shared.deleteIntegrationSecret(account: entitlementAccount)
        session = nil
        entitlement = .unknown
        reauthReason = reason
        if !savedEmail.isEmpty {
            defaults.set(savedEmail, forKey: "dotminiUserEmail")
        }
        TelemetryService.shared.clearAdminCache()
    }

    private nonisolated static func curlIPv4Response(arguments: [String]) -> (data: Data, statusCode: Int)? {
        let marker = "\n__MC_HTTP_STATUS__:"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        proc.arguments = ["-4", "-sS", "--connect-timeout", "4", "--max-time", "12", "-w", "\(marker)%{http_code}"] + arguments
        let out = Pipe()
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let rawData = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0,
                  let markerData = marker.data(using: .utf8),
                  let range = rawData.range(of: markerData, options: .backwards) else {
                return nil
            }
            let body = rawData.subdata(in: 0..<range.lowerBound)
            let codeStr = String(data: rawData.subdata(in: range.upperBound..<rawData.count), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let code = Int(codeStr), code > 0 else { return nil }
            return (body, code)
        } catch {
            return nil
        }
    }

    private nonisolated static func curlIPv4JSON(arguments: [String]) -> Data? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        proc.arguments = ["-4", "-sS", "--connect-timeout", "4", "--max-time", "12"] + arguments
        let out = Pipe()
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return proc.terminationStatus == 0 && !data.isEmpty ? data : nil
        } catch {
            return nil
        }
    }

    func refreshEntitlement() async {
        _ = await bootstrapConfiguration()
        guard let configuration = configurationProvider() ?? Configuration.cached(),
              let userID = session?.userID, !userID.isEmpty else { return }
        let refreshedJWT = await refreshAccessTokenIfNeeded()
        guard let userID = session?.userID, !userID.isEmpty else { return }
        let token = refreshedJWT ?? session?.accessToken ?? configuration.anonKey

        var profile: [String: Any]?

        // 1. Primary canonical ledger: Dotmini Cloud subscription & Beam payment gateway (`/api/subscription/status`)
        if let jwt = refreshedJWT ?? session?.accessToken, !jwt.isEmpty {
            let emailParam = (session?.email ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let uidParam = userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let statusURLString = "https://microcode.dotmini.net/api/subscription/status?uid=\(uidParam)&email=\(emailParam)"

            var statusObj: [String: Any]?
            if let statusURL = URL(string: statusURLString) {
                var statusReq = URLRequest(url: statusURL, timeoutInterval: 5)
                statusReq.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
                statusReq.setValue("application/json", forHTTPHeaderField: "Accept")
                if let (data, resp) = try? await network.data(for: statusReq),
                   (resp as? HTTPURLResponse)?.statusCode == 200,
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    statusObj = obj
                }
            }
            if statusObj == nil {
                let fallbackStatus = await Task.detached(priority: .userInitiated) {
                    Self.curlIPv4JSON(arguments: [
                        statusURLString,
                        "-H", "Authorization: Bearer \(jwt)"
                    ])
                }.value
                if let fallbackStatus,
                   let obj = try? JSONSerialization.jsonObject(with: fallbackStatus) as? [String: Any] {
                    statusObj = obj
                }
            }
            if let statusObj, let statusPlan = statusObj["plan"] as? String {
                let statusRole = (statusObj["role"] as? String) ?? "user"
                let statusQuota = (statusObj["ai_quota"] as? Int) ?? (statusObj["ai_quota"] as? NSNumber)?.intValue ?? 0
                let statusUsed = (statusObj["ai_used"] as? Int) ?? (statusObj["ai_used"] as? NSNumber)?.intValue ?? 0
                var merged: [String: Any] = [
                    "role": statusRole,
                    "plan": statusPlan,
                    "ai_quota": statusQuota,
                    "ai_used": statusUsed
                ]
                for key in [
                    "ai_credit_limit_thb",
                    "ai_credit_used_thb",
                    "ai_credit_remaining_thb",
                    "ai_topup_balance_thb",
                    "ai_total_available_thb",
                    "ai_margin_pct",
                    "ai_total_tokens",
                    "billing_mode"
                ] {
                    if let val = statusObj[key] {
                        merged[key] = val
                    }
                }
                profile = merged
            }
        }

        // 2. Secondary fallback / merge: Self-hosted Supabase `public.users`
        var components = URLComponents(url: configuration.baseURL.appending(path: "rest/v1/users"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "role,plan,ai_quota,ai_used"),
            URLQueryItem(name: "id", value: "eq.\(userID)")
        ]
        if let url = components.url {
            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            var supaRow: [String: Any]?
            if let (data, response) = try? await network.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = rows.first {
                supaRow = first
            } else if profile == nil {
                let urlStr = url.absoluteString
                let anonKey = configuration.anonKey
                let fallbackData = await Task.detached(priority: .userInitiated) {
                    Self.curlIPv4JSON(arguments: [
                        urlStr,
                        "-H", "apikey: \(anonKey)",
                        "-H", "Authorization: Bearer \(token)"
                    ])
                }.value
                if let fallbackData,
                   let rows = try? JSONSerialization.jsonObject(with: fallbackData) as? [[String: Any]],
                   let first = rows.first {
                    supaRow = first
                }
            }

            if let supaRow {
                if var existing = profile {
                    let existingPlan = ((existing["plan"] as? String) ?? "").lowercased()
                    let supaPlan = ((supaRow["plan"] as? String) ?? "").lowercased()
                    if (existingPlan.isEmpty || existingPlan == "free") && !supaPlan.isEmpty && supaPlan != "free" {
                        existing["plan"] = supaRow["plan"]
                    }
                    let existingRole = ((existing["role"] as? String) ?? "").lowercased()
                    let supaRole = ((supaRow["role"] as? String) ?? "").lowercased()
                    if existingRole != "admin" && supaRole == "admin" {
                        existing["role"] = supaRow["role"]
                    }
                    let existingQuota = (existing["ai_quota"] as? Int) ?? (existing["ai_quota"] as? NSNumber)?.intValue ?? 0
                    let supaQuota = (supaRow["ai_quota"] as? Int) ?? (supaRow["ai_quota"] as? NSNumber)?.intValue ?? 0
                    if supaQuota > existingQuota {
                        existing["ai_quota"] = supaQuota
                    }
                    let existingUsed = (existing["ai_used"] as? Int) ?? (existing["ai_used"] as? NSNumber)?.intValue ?? 0
                    let supaUsed = (supaRow["ai_used"] as? Int) ?? (supaRow["ai_used"] as? NSNumber)?.intValue ?? 0
                    existing["ai_used"] = max(existingUsed, supaUsed)
                    profile = existing
                } else {
                    profile = supaRow
                }
            }
        }

        if profile == nil, let jwt = session?.accessToken, !jwt.isEmpty,
           let bodyData = try? JSONSerialization.data(withJSONObject: ["token": jwt]),
           let bodyStr = String(data: bodyData, encoding: .utf8) {
            let syncData = await Task.detached(priority: .userInitiated) {
                Self.curlIPv4JSON(arguments: [
                    "-X", "POST", "https://microcode.dotmini.net/api/auth/sync",
                    "-H", "Content-Type: application/json",
                    "-d", bodyStr
                ])
            }.value
            if let syncData,
               let obj = try? JSONSerialization.jsonObject(with: syncData) as? [String: Any],
               (obj["status"] as? String) == "success",
               let dataObj = obj["data"] as? [String: Any],
               let verifiedRole = dataObj["role"] as? String {
                let syncedPlan = (dataObj["plan"] as? String) ?? (verifiedRole == "admin" ? "advanced" : "free")
                let syncedQuota = (dataObj["ai_quota"] as? Int) ?? (dataObj["ai_quota"] as? NSNumber)?.intValue ?? (verifiedRole == "admin" ? 12000 : 50)
                let syncedUsed = (dataObj["ai_used"] as? Int) ?? (dataObj["ai_used"] as? NSNumber)?.intValue ?? 0
                var syncedProfile: [String: Any] = [
                    "role": verifiedRole,
                    "plan": syncedPlan,
                    "ai_quota": syncedQuota,
                    "ai_used": syncedUsed
                ]
                for key in [
                    "ai_credit_limit_thb",
                    "ai_credit_used_thb",
                    "ai_credit_remaining_thb",
                    "ai_topup_balance_thb",
                    "ai_total_available_thb",
                    "ai_total_tokens"
                ] {
                    if let val = dataObj[key] {
                        syncedProfile[key] = val
                    }
                }
                profile = syncedProfile
            }
        }

        guard let profile else {
            if session?.userID == userID, !entitlement.isLoaded {
                entitlement = .unknown
            }
            return
        }
        guard session?.userID == userID, session != nil else { return }
        let resolvedPlanStr = (profile["plan"] as? String) ?? ""
        let resolvedRoleStr = (profile["role"] as? String) ?? ""
        let quota = max(0, (profile["ai_quota"] as? Int) ?? (profile["ai_quota"] as? NSNumber)?.intValue ?? 0)
        let used = max(0, (profile["ai_used"] as? Int) ?? (profile["ai_used"] as? NSNumber)?.intValue ?? 0)

        func doubleVal(_ key: String) -> Double? {
            if let d = profile[key] as? Double { return d }
            if let n = profile[key] as? NSNumber { return n.doubleValue }
            return nil
        }

        let hasServerMetered = (profile["billing_mode"] as? String) == "metered_credit_pool"
            || profile["ai_credit_limit_thb"] != nil
            || profile["ai_total_available_thb"] != nil

        var creditLimit = max(0, doubleVal("ai_credit_limit_thb") ?? 0)
        var creditUsed = max(0, doubleVal("ai_credit_used_thb") ?? 0)
        var creditRemaining = max(0, doubleVal("ai_credit_remaining_thb") ?? max(0, creditLimit - creditUsed))
        let topupBalance = max(0, doubleVal("ai_topup_balance_thb") ?? 0)
        let marginPct = doubleVal("ai_margin_pct") ?? 20.0
        let totalTokens = (profile["ai_total_tokens"] as? Int64)
            ?? (profile["ai_total_tokens"] as? NSNumber)?.int64Value
            ?? 0

        if !hasServerMetered && creditLimit == 0 {
            let fallbackPool = Self.defaultMonthlyPlanCreditTHB(for: resolvedPlanStr)
            if fallbackPool > 0 {
                creditLimit = fallbackPool
                if quota > 0 && quota < 900_000 && used > 0 {
                    let ratio = min(1.0, Double(used) / Double(quota))
                    creditUsed = (fallbackPool * ratio * 100).rounded() / 100
                }
                creditRemaining = max(0, creditLimit - creditUsed)
            }
        }

        let totalAvailable = max(0, doubleVal("ai_total_available_thb") ?? (creditRemaining + topupBalance))

        let newEntitlement = Entitlement(
            plan: resolvedPlanStr,
            role: resolvedRoleStr,
            tokensRemaining: max(0, quota - used),
            tokensUsed: used,
            creditLimitTHB: creditLimit,
            creditUsedTHB: creditUsed,
            creditRemainingTHB: creditRemaining,
            aiTopupBalanceTHB: topupBalance,
            totalAvailableTHB: totalAvailable,
            marginPct: marginPct,
            totalTokensUsed: totalTokens,
            isLoaded: true
        )
        entitlement = newEntitlement
        let persisted = PersistedEntitlement(
            userID: userID,
            plan: newEntitlement.plan,
            role: newEntitlement.role,
            tokensRemaining: newEntitlement.tokensRemaining,
            tokensUsed: newEntitlement.tokensUsed,
            creditLimitTHB: newEntitlement.creditLimitTHB,
            creditUsedTHB: newEntitlement.creditUsedTHB,
            creditRemainingTHB: newEntitlement.creditRemainingTHB,
            aiTopupBalanceTHB: newEntitlement.aiTopupBalanceTHB,
            totalAvailableTHB: newEntitlement.totalAvailableTHB,
            marginPct: newEntitlement.marginPct,
            totalTokensUsed: newEntitlement.totalTokensUsed
        )
        if let data = try? JSONEncoder().encode(persisted),
           let encoded = String(data: data, encoding: .utf8) {
            _ = KeychainManager.shared.saveIntegrationSecret(encoded, account: entitlementAccount)
        }
        if !isAdminProvider {
            TelemetryService.shared.clearAdminCache()
        }
    }

    struct CheckoutSessionResult {
        let checkoutURL: URL
        let orderRef: String
        let paymentLinkID: String
        let amountTHB: Double
    }

    func createSubscriptionCheckout(
        plan: String,
        billingInterval: String = "monthly",
        paymentMethod: String = "promptpay",
        customAmountTHB: Double? = nil
    ) async throws -> CheckoutSessionResult {
        guard let currentSession = session else {
            throw AuthError.rejected("กรุณาเข้าสู่ระบบบัญชี MicroCode ก่อนทำการสมัครแพ็กเกจหรือเติมเครดิต")
        }
        let jwt = await refreshAccessTokenIfNeeded() ?? currentSession.accessToken
        var payload: [String: Any] = [
            "plan": plan,
            "uid": currentSession.userID,
            "email": currentSession.email,
            "fullName": currentSession.email.components(separatedBy: "@").first ?? "MicroCode User",
            "billingInterval": billingInterval,
            "paymentMethod": paymentMethod,
            "seats": 1
        ]
        if let customAmountTHB, customAmountTHB > 0 {
            payload["amountTHB"] = customAmountTHB
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let bodyStr = String(data: bodyData, encoding: .utf8) ?? "{}"

        let responseData = await Task.detached(priority: .userInitiated) {
            Self.curlIPv4JSON(arguments: [
                "-X", "POST", "https://microcode.dotmini.net/api/payment/beam-checkout",
                "-H", "Content-Type: application/json",
                "-H", "Authorization: Bearer \(jwt)",
                "-d", bodyStr
            ])
        }.value

        guard let responseData,
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw AuthError.rejected("ไม่สามารถติดต่อเซิร์ฟเวอร์ชำระเงินได้ กรุณาลองใหม่อีกครั้ง")
        }
        if let errMsg = json["message"] as? String ?? json["error"] as? String, json["url"] == nil {
            throw AuthError.rejected(errMsg)
        }
        guard let urlStr = json["url"] as? String, let checkoutURL = URL(string: urlStr) else {
            throw AuthError.rejected("ไม่ได้รับลิงก์ชำระเงินจาก Beam Gateway")
        }
        let orderRef = (json["orderRef"] as? String) ?? ""
        let paymentLinkID = (json["paymentLinkId"] as? String) ?? (json["sessionId"] as? String) ?? ""
        let amountTHB = (json["amountTHB"] as? Double) ?? (json["amountTHB"] as? NSNumber)?.doubleValue ?? 0

        if !orderRef.isEmpty {
            defaults.set(orderRef, forKey: "microcode.lastOrderRef")
        }
        if !paymentLinkID.isEmpty {
            defaults.set(paymentLinkID, forKey: "microcode.lastPaymentLinkID")
        }
        return CheckoutSessionResult(
            checkoutURL: checkoutURL,
            orderRef: orderRef,
            paymentLinkID: paymentLinkID,
            amountTHB: amountTHB
        )
    }

    /// Creates an isolated Cloud AI Credit Top-Up session (`ai_topup_100`..`ai_topup_2000` or `ai_topup_custom`).
    /// Strictly separated from the Cloud GPU Compute Wallet (`gpu_wallets`).
    func createAICreditTopupCheckout(
        planKey: String,
        customAmountTHB: Double? = nil,
        paymentMethod: String = "promptpay"
    ) async throws -> CheckoutSessionResult {
        try await createSubscriptionCheckout(
            plan: planKey,
            billingInterval: "monthly",
            paymentMethod: paymentMethod,
            customAmountTHB: customAmountTHB
        )
    }

    func verifyLatestPayment() async -> (verified: Bool, message: String, checkoutURL: URL?) {
        let orderRef = defaults.string(forKey: "microcode.lastOrderRef") ?? ""
        let paymentLinkID = defaults.string(forKey: "microcode.lastPaymentLinkID") ?? ""
        if orderRef.isEmpty && paymentLinkID.isEmpty {
            await refreshEntitlement()
            return (false, "ซิงค์สิทธิ์แพ็กเกจและเครดิต Cloud AI เรียบร้อยแล้ว (Plan: \(entitlement.plan.isEmpty ? "FREE" : entitlement.plan.uppercased()) · พร้อมใช้ \(entitlement.formattedAvailableCredit))", nil)
        }
        let jwt = await refreshAccessTokenIfNeeded() ?? session?.accessToken ?? ""
        let payload: [String: Any] = [
            "orderRef": orderRef,
            "paymentLinkId": paymentLinkID,
            "uid": session?.userID ?? "",
            "email": session?.email ?? ""
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload),
              let bodyStr = String(data: bodyData, encoding: .utf8) else {
            return (false, "ไม่สามารถสร้างคำขอตรวจสอบการชำระเงินได้", nil)
        }
        let responseData = await Task.detached(priority: .userInitiated) {
            Self.curlIPv4JSON(arguments: [
                "-X", "POST", "https://microcode.dotmini.net/api/payment/verify",
                "-H", "Content-Type: application/json",
                "-H", "Authorization: Bearer \(jwt)",
                "-d", bodyStr
            ])
        }.value

        guard let responseData,
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            await refreshEntitlement()
            return (false, "ไม่สามารถตรวจสอบสถานะการชำระเงินได้ในขณะนี้", nil)
        }
        let isVerified = (json["verified"] as? Bool) ?? false
        if isVerified {
            defaults.removeObject(forKey: "microcode.lastOrderRef")
            defaults.removeObject(forKey: "microcode.lastPaymentLinkID")
            await refreshEntitlement()
            let isAITopup = (json["isAICreditTopup"] as? Bool) ?? ((json["plan"] as? String) == "ai_credit_topup")
            if isAITopup {
                return (true, "เติมเครดิต Cloud AI สำเร็จ! เครดิตพร้อมใช้งานรวม \(entitlement.formattedAvailableCredit) (AI Top-Up: \(String(format: "฿%.2f", entitlement.aiTopupBalanceTHB)))", nil)
            }
            let planName = (json["displayName"] as? String) ?? (json["plan"] as? String) ?? entitlement.plan
            return (true, "ชำระเงินสำเร็จ! เปิดใช้งาน \(planName) เรียบร้อยแล้ว (เครดิตพร้อมใช้ \(entitlement.formattedAvailableCredit))", nil)
        } else {
            let msg = (json["message"] as? String) ?? "รายการชำระเงินยังรอดำเนินการ (สถานะ: \((json["status"] as? String) ?? "PENDING"))"
            let resumeURL = (json["checkoutUrl"] as? String).flatMap { URL(string: $0) }
            await refreshEntitlement()
            return (false, msg, resumeURL)
        }
    }


    // MARK: - Automatic payment confirmation

    @Published private(set) var paymentWatchMessage = ""
    @Published private(set) var paymentWatchVerified = false
    @Published private(set) var isWatchingPayment = false
    private var paymentWatchTask: Task<Void, Never>?

    /// After the customer opens a Beam checkout link, poll the server for that order until it is paid
    /// (about 15 minutes), so nobody has to come back and press "Verify" after paying.
    func beginPaymentWatch() {
        paymentWatchTask?.cancel()
        paymentWatchVerified = false
        let hasOrder = !(defaults.string(forKey: "microcode.lastOrderRef") ?? "").isEmpty
            || !(defaults.string(forKey: "microcode.lastPaymentLinkID") ?? "").isEmpty
        guard hasOrder else {
            isWatchingPayment = false
            paymentWatchMessage = "กดปุ่ม Verify Payment & Sync Credit หลังชำระเงินเพื่ออัปเดตสิทธิ์"
            return
        }
        isWatchingPayment = true
        paymentWatchMessage = "รอการชำระเงิน… สิทธิ์จะเปิดใช้งานให้อัตโนมัติเมื่อชำระสำเร็จ"
        paymentWatchTask = Task { [weak self] in
            let started = Date()
            while !Task.isCancelled, Date().timeIntervalSince(started) < 15 * 60 {
                let waitSeconds: UInt64 = Date().timeIntervalSince(started) < 180 ? 4 : 10
                try? await Task.sleep(nanoseconds: waitSeconds * 1_000_000_000)
                guard let self, !Task.isCancelled, self.session != nil else { return }
                let result = await self.verifyLatestPayment()
                if result.verified {
                    self.paymentWatchVerified = true
                    self.paymentWatchMessage = result.message
                    self.isWatchingPayment = false
                    return
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.isWatchingPayment = false
            self.paymentWatchMessage = "ยังไม่พบการชำระเงิน — หากชำระแล้วให้กด Verify Payment & Sync Credit"
        }
    }

    func cancelPaymentWatch() {
        paymentWatchTask?.cancel()
        paymentWatchTask = nil
        isWatchingPayment = false
    }

    func signOut() {
        cancelPaymentWatch()
        paymentWatchMessage = ""
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
        KeychainManager.shared.deleteIntegrationSecret(account: entitlementAccount)
        let defaults = defaults
        ["cloudGPUAuthToken", "cloudGPURefreshToken", "microRentToken", "dotminiLicenseKey", "dotminiUserEmail"].forEach {
            defaults.removeObject(forKey: $0)
        }
        for suiteName in ["com.dotmini.microcode", "com.dotmini.microcode.ai"] {
            UserDefaults(suiteName: suiteName)?.removeObject(forKey: "dotminiUserEmail")
        }
        session = nil
        entitlement = .unknown
        reauthReason = ""
        TelemetryService.shared.clearAdminCache()
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
        if let (data, response) = try? await network.data(for: request),
           let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw AuthError.rejected("Authentication failed (HTTP \(http.statusCode)). Please sign in again.")
            }
            guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AuthError.invalidResponse }
            return try decodeSession(raw)
        }
        guard let urlStr = request.url?.absoluteString else { throw AuthError.invalidResponse }
        let method = request.httpMethod ?? "POST"
        let headers = request.allHTTPHeaderFields ?? [:]
        let bodyStr = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        let fallbackData = await Task.detached(priority: .userInitiated) { () -> Data? in
            var args = ["-X", method, urlStr]
            for (k, v) in headers {
                args.append(contentsOf: ["-H", "\(k): \(v)"])
            }
            if let bodyStr {
                args.append(contentsOf: ["-d", bodyStr])
            }
            return Self.curlIPv4JSON(arguments: args)
        }.value
        guard let fallbackData,
              let raw = try? JSONSerialization.jsonObject(with: fallbackData) as? [String: Any] else {
            throw AuthError.invalidResponse
        }
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
        if session?.userID != newSession.userID {
            entitlement = .unknown
            KeychainManager.shared.deleteIntegrationSecret(account: entitlementAccount)
        }
        session = newSession
        reauthReason = ""
        KeychainManager.shared.deleteIntegrationSecret(account: accessTokenAccount)
        KeychainManager.shared.deleteIntegrationSecret(account: refreshTokenAccount)
        clearLegacyCredentials()
        if !newSession.email.isEmpty {
            defaults.set(newSession.email, forKey: "dotminiUserEmail")
            for suiteName in ["com.dotmini.microcode", "com.dotmini.microcode.ai"] {
                UserDefaults(suiteName: suiteName)?.set(newSession.email, forKey: "dotminiUserEmail")
            }
        }
        // Identity refresh must never change the user's selected inference mode.
    }

    private func restorePersistedSession() {
        if let encoded = KeychainManager.shared.readIntegrationSecret(account: sessionAccount),
           let data = encoded.data(using: .utf8),
           let restored = try? JSONDecoder().decode(Session.self, from: data) {
            session = restored
            if !restored.userID.isEmpty,
               let entEncoded = KeychainManager.shared.readIntegrationSecret(account: entitlementAccount),
               let entData = entEncoded.data(using: .utf8),
               let persisted = try? JSONDecoder().decode(PersistedEntitlement.self, from: entData),
               persisted.userID == restored.userID {
                let fallbackLimit = Self.defaultMonthlyPlanCreditTHB(for: persisted.plan)
                let lim = persisted.creditLimitTHB ?? fallbackLimit
                let usedTHB = persisted.creditUsedTHB ?? 0
                let remTHB = persisted.creditRemainingTHB ?? max(0, lim - usedTHB)
                let topupTHB = persisted.aiTopupBalanceTHB ?? 0
                let availTHB = persisted.totalAvailableTHB ?? (remTHB + topupTHB)
                entitlement = Entitlement(
                    plan: persisted.plan,
                    role: persisted.role,
                    tokensRemaining: persisted.tokensRemaining,
                    tokensUsed: persisted.tokensUsed,
                    creditLimitTHB: lim,
                    creditUsedTHB: usedTHB,
                    creditRemainingTHB: remTHB,
                    aiTopupBalanceTHB: topupTHB,
                    totalAvailableTHB: availTHB,
                    marginPct: persisted.marginPct ?? 20,
                    totalTokensUsed: persisted.totalTokensUsed ?? 0,
                    isLoaded: true
                )
            }
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
