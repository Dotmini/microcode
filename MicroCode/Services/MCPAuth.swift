import Foundation
import CryptoKit
import Network

// MCP authorization for remote (Streamable HTTP) servers — OAuth 2.1 per the MCP authorization spec:
//   • RFC 9728 Protected Resource Metadata discovery (WWW-Authenticate `resource_metadata`, then well-known)
//   • RFC 8414 / OIDC authorization-server metadata discovery
//   • PKCE S256, RFC 8707 `resource` indicator, RFC 9207 `iss` validation
//   • Client ID Metadata Documents when configured, else RFC 7591 Dynamic Client Registration (native app)
//   • RFC 8252 loopback redirect, refresh tokens, credentials keyed by issuer / canonical resource
// Dependency-free (no app types) so it is exercised end-to-end by Scripts/tests/run-phase2b-mcp-auth.sh.

enum MCPAuthError: LocalizedError, Equatable {
    case invalidServerURL
    case discoveryFailed(String)
    case pkceUnsupported
    case registrationUnavailable(String)
    case stateMismatch
    case issuerMismatch(expected: String, received: String?)
    case authorizationDenied(String)
    case callbackTimeout
    case tokenRequestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: return "Invalid MCP server URL"
        case .discoveryFailed(let detail): return "OAuth discovery failed: \(detail)"
        case .pkceUnsupported: return "Authorization server does not support PKCE S256 (required by MCP)"
        case .registrationUnavailable(let detail): return "No way to register MicroCode as an OAuth client: \(detail)"
        case .stateMismatch: return "OAuth callback state mismatch (possible CSRF); sign-in aborted"
        case .issuerMismatch(let expected, let received):
            return "OAuth callback issuer mismatch (expected \(expected), got \(received ?? "none")); sign-in aborted"
        case .authorizationDenied(let detail): return "Authorization denied: \(detail)"
        case .callbackTimeout: return "Timed out waiting for the browser sign-in to finish"
        case .tokenRequestFailed(let detail): return "Token request failed: \(detail)"
        }
    }
}

// MARK: - Metadata & credential models

struct MCPProtectedResourceMetadata: Codable {
    let resource: String?
    let authorization_servers: [String]?
    let scopes_supported: [String]?
}

struct MCPAuthorizationServerMetadata: Codable {
    let issuer: String
    let authorization_endpoint: String
    let token_endpoint: String
    let registration_endpoint: String?
    let code_challenge_methods_supported: [String]?
    let client_id_metadata_document_supported: Bool?
    let authorization_response_iss_parameter_supported: Bool?
    let scopes_supported: [String]?
}

struct MCPOAuthClientRegistration: Codable, Equatable {
    let issuer: String
    let clientId: String
    let redirectURI: String
}

struct MCPOAuthTokenSet: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var scope: String?
    let issuer: String
    let clientId: String
    let resource: String
    let tokenEndpoint: String

    func isExpired(now: Date = Date(), skew: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(skew) >= expiresAt
    }
}

// MARK: - Pure protocol helpers

enum MCPAuthSupport {
    /// `scheme://host[:port]` (lowercased; default ports omitted).
    static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        let defaultPort = (scheme == "https" && url.port == 443) || (scheme == "http" && url.port == 80)
        if let port = url.port, !defaultPort { return "\(scheme)://\(host):\(port)" }
        return "\(scheme)://\(host)"
    }

    /// RFC 8707 canonical resource URI of an MCP server: lowercase scheme/host, no query/fragment, no trailing slash.
    static func canonicalResource(_ url: URL) -> String {
        guard let origin = origin(of: url) else { return url.absoluteString }
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return origin + path
    }

    /// Parses a `WWW-Authenticate: Bearer k="v", k2=v2` challenge. Keys are lowercased; `scheme` holds the scheme.
    static func parseWWWAuthenticate(_ header: String) -> [String: String] {
        var result: [String: String] = [:]
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(of: " ") else {
            if !trimmed.isEmpty { result["scheme"] = trimmed.lowercased() }
            return result
        }
        result["scheme"] = String(trimmed[..<space]).lowercased()
        var rest = Substring(trimmed[trimmed.index(after: space)...])
        while !rest.isEmpty {
            rest = rest.drop(while: { $0 == " " || $0 == "," })
            guard let eq = rest.firstIndex(of: "=") else { break }
            let key = rest[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            rest = rest[rest.index(after: eq)...]
            var value = ""
            if rest.first == "\"" {
                rest = rest.dropFirst()
                var escaped = false
                var consumed = 0
                for ch in rest {
                    consumed += 1
                    if escaped { value.append(ch); escaped = false; continue }
                    if ch == "\\" { escaped = true; continue }
                    if ch == "\"" { break }
                    value.append(ch)
                }
                rest = rest.dropFirst(consumed)
            } else {
                let end = rest.firstIndex(of: ",") ?? rest.endIndex
                value = rest[..<end].trimmingCharacters(in: .whitespaces)
                rest = rest[end...]
            }
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    /// RFC 9728 discovery order: `resource_metadata` from the challenge, then path-inserted and root well-known URLs.
    static func protectedResourceMetadataCandidates(serverURL: URL, wwwAuthenticate: String?) -> [URL] {
        var candidates: [URL] = []
        if let header = wwwAuthenticate,
           let advertised = parseWWWAuthenticate(header)["resource_metadata"],
           let url = URL(string: advertised) {
            candidates.append(url)
        }
        if let origin = origin(of: serverURL) {
            var path = serverURL.path
            while path.hasSuffix("/") { path.removeLast() }
            if !path.isEmpty, let url = URL(string: origin + "/.well-known/oauth-protected-resource" + path) {
                candidates.append(url)
            }
            if let url = URL(string: origin + "/.well-known/oauth-protected-resource") {
                candidates.append(url)
            }
        }
        return candidates
    }

    /// RFC 8414 (path insertion) then OpenID Connect discovery variants, in the order MCP clients must try them.
    static func authorizationServerMetadataCandidates(issuer: URL) -> [URL] {
        guard let origin = origin(of: issuer) else { return [] }
        var path = issuer.path
        while path.hasSuffix("/") { path.removeLast() }
        var urls: [String] = []
        if path.isEmpty {
            urls = [origin + "/.well-known/oauth-authorization-server", origin + "/.well-known/openid-configuration"]
        } else {
            urls = [
                origin + "/.well-known/oauth-authorization-server" + path,
                origin + "/.well-known/openid-configuration" + path,
                origin + path + "/.well-known/openid-configuration"
            ]
        }
        return urls.compactMap(URL.init(string:))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Cryptographically secure (SystemRandomNumberGenerator) URL-safe random string.
    static func randomURLSafe(byteCount: Int) -> String {
        base64URL(Data((0..<byteCount).map { _ in UInt8.random(in: .min ... .max) }))
    }

    /// PKCE code verifier (43–128 chars of unreserved characters).
    static func makeCodeVerifier() -> String { randomURLSafe(byteCount: 48) }

    static func codeChallengeS256(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func authorizationURL(
        metadata: MCPAuthorizationServerMetadata,
        clientId: String,
        redirectURI: String,
        codeChallenge: String,
        state: String,
        resource: String,
        scope: String?
    ) -> URL? {
        guard var components = URLComponents(string: metadata.authorization_endpoint) else { return nil }
        var items = components.queryItems ?? []
        items += [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "resource", value: resource)
        ]
        if let scope, !scope.isEmpty { items.append(URLQueryItem(name: "scope", value: scope)) }
        components.queryItems = items
        return components.url
    }

    /// Validates the redirect: state (CSRF), `error`, and RFC 9207 `iss` against the recorded issuer.
    static func validateCallback(
        _ query: [String: String],
        expectedState: String,
        expectedIssuer: String,
        issuerParameterRequired: Bool
    ) throws -> String {
        guard query["state"] == expectedState else { throw MCPAuthError.stateMismatch }
        if let error = query["error"] {
            throw MCPAuthError.authorizationDenied([error, query["error_description"]].compactMap { $0 }.joined(separator: ": "))
        }
        if let iss = query["iss"] {
            guard iss == expectedIssuer else { throw MCPAuthError.issuerMismatch(expected: expectedIssuer, received: iss) }
        } else if issuerParameterRequired {
            throw MCPAuthError.issuerMismatch(expected: expectedIssuer, received: nil)
        }
        guard let code = query["code"], !code.isEmpty else {
            throw MCPAuthError.authorizationDenied("no authorization code in callback")
        }
        return code
    }

    static func formBody(_ params: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = params.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }

    static func parseTokenResponse(
        _ data: Data,
        previous: MCPOAuthTokenSet?,
        issuer: String,
        clientId: String,
        resource: String,
        tokenEndpoint: String,
        now: Date = Date()
    ) throws -> MCPOAuthTokenSet {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPAuthError.tokenRequestFailed("token endpoint returned non-JSON")
        }
        if let error = json["error"] as? String {
            throw MCPAuthError.tokenRequestFailed([error, json["error_description"] as? String].compactMap { $0 }.joined(separator: ": "))
        }
        guard let access = json["access_token"] as? String, !access.isEmpty else {
            throw MCPAuthError.tokenRequestFailed("no access_token in response")
        }
        let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? Double(json["expires_in"] as? String ?? "")
        return MCPOAuthTokenSet(
            accessToken: access,
            refreshToken: (json["refresh_token"] as? String) ?? previous?.refreshToken,
            expiresAt: expiresIn.map { now.addingTimeInterval($0) },
            scope: (json["scope"] as? String) ?? previous?.scope,
            issuer: issuer,
            clientId: clientId,
            resource: resource,
            tokenEndpoint: tokenEndpoint
        )
    }
}

// MARK: - Credential storage

/// Backing store for secrets (the app supplies a Keychain-sealed implementation; tests use memory).
protocol MCPSecretStorage: AnyObject {
    func readSecret(account: String) -> String?
    func writeSecret(_ value: String?, account: String)
}

final class MCPInMemorySecretStorage: MCPSecretStorage {
    private var values: [String: String] = [:]
    func readSecret(account: String) -> String? { values[account] }
    func writeSecret(_ value: String?, account: String) { values[account] = value }
}

/// Credentials are bound to where they were issued: OAuth tokens to the canonical resource, client
/// registrations to the issuer (never reused across authorization servers), static bearer tokens to the
/// server origin — so a config that reuses a server *name* with another URL can never receive them.
/// Main-actor isolated: the app's secret store (KeychainManager) is main-actor only.
@MainActor
final class MCPCredentialStore {
    private let storage: MCPSecretStorage
    init(storage: MCPSecretStorage) { self.storage = storage }

    private static func key(_ kind: String, _ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return "mcp.\(kind).\(digest)"
    }

    private func decode<T: Decodable>(_ type: T.Type, account: String) -> T? {
        guard let text = storage.readSecret(account: account), let data = text.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, account: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(value) else { return }
        storage.writeSecret(String(decoding: data, as: UTF8.self), account: account)
    }

    func tokens(forResource resource: String) -> MCPOAuthTokenSet? {
        decode(MCPOAuthTokenSet.self, account: Self.key("oauth.tokens", resource))
    }

    func save(_ tokens: MCPOAuthTokenSet) {
        encode(tokens, account: Self.key("oauth.tokens", tokens.resource))
    }

    func deleteTokens(forResource resource: String) {
        storage.writeSecret(nil, account: Self.key("oauth.tokens", resource))
    }

    func registration(forIssuer issuer: String) -> MCPOAuthClientRegistration? {
        decode(MCPOAuthClientRegistration.self, account: Self.key("oauth.client", issuer))
    }

    func save(_ registration: MCPOAuthClientRegistration) {
        encode(registration, account: Self.key("oauth.client", registration.issuer))
    }

    func bearerToken(forOrigin origin: String) -> String? {
        storage.readSecret(account: Self.key("bearer", origin))
    }

    func saveBearerToken(_ token: String?, forOrigin origin: String) {
        storage.writeSecret(token, account: Self.key("bearer", origin))
    }
}

// MARK: - Loopback redirect receiver (RFC 8252 §7.3)

/// One-shot HTTP listener on 127.0.0.1 that captures the authorization redirect.
final class MCPLoopbackCallbackServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "microcode.mcp.oauth.loopback")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var delivered = false
    private(set) var port: UInt16 = 0

    /// Starts on `preferredPort` (stable redirect URI for registrations) or an ephemeral port if it is busy.
    func start(preferredPort: UInt16) async throws -> UInt16 {
        if let port = try? await startListener(port: NWEndpoint.Port(rawValue: preferredPort) ?? .any) { return port }
        return try await startListener(port: .any)
    }

    private func startListener(port: NWEndpoint.Port) async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        let boundPort: UInt16 = try await withCheckedThrowingContinuation { cont in
            let once = OnceFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { cont.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error):
                    if once.claim() { cont.resume(throwing: error) }
                    listener.cancel()
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        self.listener = listener
        self.port = boundPort
        return boundPort
    }

    func waitForCallback(timeout: TimeInterval) async throws -> [String: String] {
        try await withThrowingTaskGroup(of: [String: String].self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { cont in
                    self.lock.lock()
                    self.continuation = cont
                    self.lock.unlock()
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw MCPAuthError.callbackTimeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw MCPAuthError.callbackTimeout }
            return result
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        lock.lock()
        let pending = delivered ? nil : continuation
        continuation = nil
        delivered = true
        lock.unlock()
        pending?.resume(throwing: MCPAuthError.callbackTimeout)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let target = request.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            var query: [String: String] = [:]
            if let components = URLComponents(string: "http://127.0.0.1" + target), components.path == "/callback" {
                for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
            }
            let ok = !query.isEmpty
            let body = ok
                ? "<html><body style=\"font-family:-apple-system\"><h3>MicroCode sign-in complete</h3><p>You can close this tab and return to MicroCode.</p></body></html>"
                : "<html><body>Not found</body></html>"
            let response = "HTTP/1.1 \(ok ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            guard ok else { return }
            self.lock.lock()
            let cont = self.delivered ? nil : self.continuation
            if cont != nil { self.delivered = true; self.continuation = nil }
            self.lock.unlock()
            cont?.resume(returning: query)
        }
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

// MARK: - OAuth client

/// Main-actor isolated so every credential read/write happens on the main actor (network awaits still
/// suspend off-main). A nonisolated async client ran on the cooperative pool and trapped in the app's
/// main-actor-only secret store at launch.
@MainActor
final class MCPOAuthClient {
    let store: MCPCredentialStore
    private let session: URLSession
    /// Opens the authorization URL for the user (the app uses the default browser).
    private let openURL: (URL) -> Void
    var clientName = "MicroCode"
    /// HTTPS URL of a hosted Client ID Metadata Document, if MicroCode has one (preferred over DCR).
    var clientIdMetadataDocumentURL: String?
    /// Stable loopback port so a dynamically registered redirect URI keeps matching across sign-ins.
    var preferredLoopbackPort: UInt16 = 33418
    var callbackTimeout: TimeInterval = 300

    init(store: MCPCredentialStore, session: URLSession = .shared, openURL: @escaping (URL) -> Void) {
        self.store = store
        self.session = session
        self.openURL = openURL
    }

    // MARK: Discovery

    private func fetchJSON<T: Decodable>(_ type: T.Type, from url: URL) async -> T? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(MCPProtocolDefaults.latestVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func discover(serverURL: URL, wwwAuthenticate: String?) async throws
        -> (resource: String, metadata: MCPAuthorizationServerMetadata, scope: String?) {
        var prm: MCPProtectedResourceMetadata?
        for candidate in MCPAuthSupport.protectedResourceMetadataCandidates(serverURL: serverURL, wwwAuthenticate: wwwAuthenticate) {
            if let found = await fetchJSON(MCPProtectedResourceMetadata.self, from: candidate) { prm = found; break }
        }
        guard let prm, let issuerString = prm.authorization_servers?.first, let issuerURL = URL(string: issuerString) else {
            throw MCPAuthError.discoveryFailed("no protected resource metadata / authorization server for \(serverURL.absoluteString)")
        }
        var asMetadata: MCPAuthorizationServerMetadata?
        for candidate in MCPAuthSupport.authorizationServerMetadataCandidates(issuer: issuerURL) {
            if let found = await fetchJSON(MCPAuthorizationServerMetadata.self, from: candidate) { asMetadata = found; break }
        }
        guard let asMetadata else {
            throw MCPAuthError.discoveryFailed("no authorization server metadata for \(issuerString)")
        }
        // The metadata must describe the issuer we were pointed at (RFC 8414 §3.3).
        guard asMetadata.issuer.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ==
                issuerString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else {
            throw MCPAuthError.discoveryFailed("authorization server metadata issuer \(asMetadata.issuer) != \(issuerString)")
        }
        guard asMetadata.code_challenge_methods_supported?.contains("S256") == true else {
            throw MCPAuthError.pkceUnsupported
        }
        let resource = prm.resource ?? MCPAuthSupport.canonicalResource(serverURL)
        let challengeScope = wwwAuthenticate.flatMap { MCPAuthSupport.parseWWWAuthenticate($0)["scope"] }
        let scope = challengeScope ?? prm.scopes_supported?.joined(separator: " ")
        return (resource, asMetadata, scope)
    }

    // MARK: Client registration

    private func clientRegistration(for metadata: MCPAuthorizationServerMetadata, redirectURI: String) async throws -> MCPOAuthClientRegistration {
        if let existing = store.registration(forIssuer: metadata.issuer), existing.redirectURI == redirectURI {
            return existing
        }
        if let cimd = clientIdMetadataDocumentURL, metadata.client_id_metadata_document_supported == true {
            let registration = MCPOAuthClientRegistration(issuer: metadata.issuer, clientId: cimd, redirectURI: redirectURI)
            store.save(registration)
            return registration
        }
        guard let endpoint = metadata.registration_endpoint.flatMap(URL.init(string:)) else {
            throw MCPAuthError.registrationUnavailable("\(metadata.issuer) offers neither Client ID Metadata Documents nor dynamic registration; configure a pre-registered client")
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "client_name": clientName,
            "application_type": "native",
            "redirect_uris": [redirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientId = json["client_id"] as? String else {
            throw MCPAuthError.registrationUnavailable("dynamic client registration failed at \(endpoint.absoluteString)")
        }
        let registration = MCPOAuthClientRegistration(issuer: metadata.issuer, clientId: clientId, redirectURI: redirectURI)
        store.save(registration)
        return registration
    }

    // MARK: Authorization code flow

    /// Full interactive sign-in. Opens the browser once; returns stored tokens bound to the canonical resource.
    func authorize(serverURL: URL, wwwAuthenticate: String?) async throws -> MCPOAuthTokenSet {
        let (resource, metadata, scope) = try await discover(serverURL: serverURL, wwwAuthenticate: wwwAuthenticate)

        let receiver = MCPLoopbackCallbackServer()
        let port = try await receiver.start(preferredPort: preferredLoopbackPort)
        defer { receiver.stop() }
        let redirectURI = "http://127.0.0.1:\(port)/callback"
        let registration = try await clientRegistration(for: metadata, redirectURI: redirectURI)

        let verifier = MCPAuthSupport.makeCodeVerifier()
        let state = MCPAuthSupport.randomURLSafe(byteCount: 24)
        guard let authorizeURL = MCPAuthSupport.authorizationURL(
            metadata: metadata,
            clientId: registration.clientId,
            redirectURI: redirectURI,
            codeChallenge: MCPAuthSupport.codeChallengeS256(verifier),
            state: state,
            resource: resource,
            scope: scope
        ) else {
            throw MCPAuthError.discoveryFailed("invalid authorization_endpoint \(metadata.authorization_endpoint)")
        }
        openURL(authorizeURL)

        let query = try await receiver.waitForCallback(timeout: callbackTimeout)
        let code = try MCPAuthSupport.validateCallback(
            query,
            expectedState: state,
            expectedIssuer: metadata.issuer,
            issuerParameterRequired: metadata.authorization_response_iss_parameter_supported == true
        )

        let tokens = try await tokenRequest(
            endpoint: metadata.token_endpoint,
            params: [
                ("grant_type", "authorization_code"),
                ("code", code),
                ("redirect_uri", redirectURI),
                ("client_id", registration.clientId),
                ("code_verifier", verifier),
                ("resource", resource)
            ],
            previous: nil,
            issuer: metadata.issuer,
            clientId: registration.clientId,
            resource: resource
        )
        store.save(tokens)
        return tokens
    }

    private func tokenRequest(
        endpoint: String,
        params: [(String, String)],
        previous: MCPOAuthTokenSet?,
        issuer: String,
        clientId: String,
        resource: String
    ) async throws -> MCPOAuthTokenSet {
        guard let url = URL(string: endpoint) else { throw MCPAuthError.tokenRequestFailed("invalid token_endpoint") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = MCPAuthSupport.formBody(params)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = String(decoding: data.prefix(300), as: UTF8.self)
            throw MCPAuthError.tokenRequestFailed("HTTP \(http.statusCode): \(detail)")
        }
        return try MCPAuthSupport.parseTokenResponse(
            data, previous: previous, issuer: issuer, clientId: clientId, resource: resource, tokenEndpoint: endpoint
        )
    }

    // MARK: Token use

    func refresh(_ tokens: MCPOAuthTokenSet) async throws -> MCPOAuthTokenSet {
        guard let refreshToken = tokens.refreshToken else {
            throw MCPAuthError.tokenRequestFailed("no refresh token; sign in again")
        }
        let refreshed = try await tokenRequest(
            endpoint: tokens.tokenEndpoint,
            params: [
                ("grant_type", "refresh_token"),
                ("refresh_token", refreshToken),
                ("client_id", tokens.clientId),
                ("resource", tokens.resource)
            ],
            previous: tokens,
            issuer: tokens.issuer,
            clientId: tokens.clientId,
            resource: tokens.resource
        )
        store.save(refreshed)
        return refreshed
    }

    /// Access token for `serverURL` if signed in, refreshing it when expired. Never opens a browser.
    func validAccessToken(for serverURL: URL, forceRefresh: Bool = false) async -> String? {
        let resource = MCPAuthSupport.canonicalResource(serverURL)
        guard let tokens = store.tokens(forResource: resource) else { return nil }
        if !forceRefresh && !tokens.isExpired() { return tokens.accessToken }
        guard let refreshed = try? await refresh(tokens) else {
            store.deleteTokens(forResource: resource)
            return nil
        }
        return refreshed.accessToken
    }
}

/// Protocol constants this file needs without depending on the app's MCP server types.
enum MCPProtocolDefaults {
    static let latestVersion = "2025-11-25"
}
