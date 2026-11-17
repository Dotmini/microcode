import Foundation

// Phase 2b: MCP OAuth 2.1 end-to-end against Scripts/tests/fixtures/mcp_oauth_mock.py.
// Compiled with the real MicroCode/Services/MCPAuth.swift by `run-phase2b-mcp-auth.sh`.

@main struct Phase2bMCPAuthRegression {
    static let port = Int(ProcessInfo.processInfo.environment["MOCK_PORT"] ?? "18999")!
    static var base: String { "http://127.0.0.1:\(port)" }
    static var serverURL: URL { URL(string: "\(base)/mcp")! }

    /// Mirrors the app's KeychainManager-backed storage, which is main-actor only: any credential access
    /// from a background executor must fail this test (it crashed the app at launch on 2026-11-18).
    final class MainThreadOnlySecretStorage: MCPSecretStorage {
        private let inner = MCPInMemorySecretStorage()
        func readSecret(account: String) -> String? {
            precondition(Thread.isMainThread, "credential storage read off the main thread")
            return inner.readSecret(account: account)
        }
        func writeSecret(_ value: String?, account: String) {
            precondition(Thread.isMainThread, "credential storage write off the main thread")
            inner.writeSecret(value, account: account)
        }
    }

    @MainActor
    static func main() async throws {
        pureHelpers()
        let storage = MainThreadOnlySecretStorage()
        let store = MCPCredentialStore(storage: storage)
        let client = MCPOAuthClient(store: store) { url in
            // Stand-in for the user's browser: follow the authorization redirect back to the loopback receiver.
            Task { _ = try? await URLSession.shared.data(from: url) }
        }
        client.callbackTimeout = 20

        // 1. Unauthenticated call → 401 challenge → interactive sign-in → authenticated call.
        let (status401, challenge) = try await callMCP(token: nil)
        precondition(status401 == 401 && challenge?.contains("resource_metadata") == true, "expected 401 challenge")
        let tokens = try await client.authorize(serverURL: serverURL, wwwAuthenticate: challenge)
        precondition(tokens.resource == "\(base)/mcp" && tokens.issuer == "\(base)/as")
        let authorizedStatus = try await callMCP(token: tokens.accessToken).0
        precondition(authorizedStatus == 200, "token must authorize the MCP call")

        // 2. Tokens are bound to the canonical resource: another path / origin never gets them.
        precondition(store.tokens(forResource: "\(base)/other") == nil)
        precondition(store.tokens(forResource: "http://localhost:\(port)/mcp") == nil)

        // 3. Expired token is refreshed transparently (RFC 8707 resource on refresh too).
        var expired = tokens
        expired.expiresAt = Date(timeIntervalSinceNow: -10)
        store.save(expired)
        guard let refreshedToken = await client.validAccessToken(for: serverURL) else { preconditionFailure("refresh failed") }
        precondition(refreshedToken != tokens.accessToken)
        let refreshedStatus = try await callMCP(token: refreshedToken).0
        precondition(refreshedStatus == 200)

        // 4. Second sign-in reuses the dynamic client registration for the same issuer + redirect.
        _ = try await client.authorize(serverURL: serverURL, wwwAuthenticate: challenge)
        let stats = try await getJSON("/stats")
        precondition(stats["registrations"] as? Int == 1, "client registration must be reused: \(stats)")
        precondition((stats["token_requests"] as? [String])?.contains("refresh_token") == true)

        // 5. RFC 9207 / CSRF defences.
        try await expect(.issuerMismatch(expected: "\(base)/as", received: "http://evil.example/as"), mode: "bad_iss", client: client, challenge: challenge)
        try await expect(.issuerMismatch(expected: "\(base)/as", received: nil), mode: "no_iss", client: client, challenge: challenge)
        try await expect(.stateMismatch, mode: "bad_state", client: client, challenge: challenge)
        try await setMode("normal")

        // 6. Static bearer tokens are keyed by origin, not by server name.
        store.saveBearerToken("secret", forOrigin: "https://mcp.github.com")
        precondition(store.bearerToken(forOrigin: "https://mcp.github.com") == "secret")
        precondition(store.bearerToken(forOrigin: "https://evil.example") == nil)

        print("PHASE2B MCP AUTH REGRESSION: PASS")
    }

    static func pureHelpers() {
        // RFC 7636 Appendix B test vector.
        precondition(MCPAuthSupport.codeChallengeS256("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let verifier = MCPAuthSupport.makeCodeVerifier()
        precondition((43...128).contains(verifier.count))

        let parsed = MCPAuthSupport.parseWWWAuthenticate(#"Bearer resource_metadata="https://a.example/.well-known/oauth-protected-resource", scope="files:read files:write", error=invalid_token"#)
        precondition(parsed["scheme"] == "bearer")
        precondition(parsed["resource_metadata"] == "https://a.example/.well-known/oauth-protected-resource")
        precondition(parsed["scope"] == "files:read files:write")
        precondition(parsed["error"] == "invalid_token")

        precondition(MCPAuthSupport.canonicalResource(URL(string: "HTTPS://MCP.Example.com:443/mcp/")!) == "https://mcp.example.com/mcp")
        precondition(MCPAuthSupport.canonicalResource(URL(string: "http://127.0.0.1:8080/mcp?x=1")!) == "http://127.0.0.1:8080/mcp")

        let prm = MCPAuthSupport.protectedResourceMetadataCandidates(serverURL: URL(string: "https://a.example/public/mcp")!, wwwAuthenticate: nil)
        precondition(prm.map(\.absoluteString) == [
            "https://a.example/.well-known/oauth-protected-resource/public/mcp",
            "https://a.example/.well-known/oauth-protected-resource"
        ])
        let asm = MCPAuthSupport.authorizationServerMetadataCandidates(issuer: URL(string: "https://auth.example/tenant1")!)
        precondition(asm.map(\.absoluteString) == [
            "https://auth.example/.well-known/oauth-authorization-server/tenant1",
            "https://auth.example/.well-known/openid-configuration/tenant1",
            "https://auth.example/tenant1/.well-known/openid-configuration"
        ])
    }

    static func expect(_ error: MCPAuthError, mode: String, client: MCPOAuthClient, challenge: String?) async throws {
        try await setMode(mode)
        do {
            _ = try await client.authorize(serverURL: serverURL, wwwAuthenticate: challenge)
            preconditionFailure("mode \(mode) must fail")
        } catch let caught as MCPAuthError {
            precondition(caught == error, "mode \(mode): expected \(error), got \(caught)")
        }
    }

    static func callMCP(token: String?) async throws -> (Int, String?) {
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        let http = response as! HTTPURLResponse
        return (http.statusCode, http.value(forHTTPHeaderField: "WWW-Authenticate"))
    }

    static func setMode(_ mode: String) async throws {
        var request = URLRequest(url: URL(string: "\(base)/control")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"mode":"\#(mode)"}"#.utf8)
        _ = try await URLSession.shared.data(for: request)
    }

    static func getJSON(_ path: String) async throws -> [String: Any] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: base + path)!)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}
