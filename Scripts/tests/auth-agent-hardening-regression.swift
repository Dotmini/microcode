import Foundation
import Combine

// Compile only the services under test. No real Keychain, account or GPU access.
@MainActor final class KeychainManager {
    static let shared = KeychainManager()
    var values: [String: String] = [:]
    func readIntegrationSecret(account: String) -> String? { values[account] }
    func saveIntegrationSecret(_ value: String, account: String) -> Bool { values[account] = value; return true }
    func deleteIntegrationSecret(account: String) { values.removeValue(forKey: account) }
}
@MainActor final class DotminiPlatformKeyService {
    static let shared = DotminiPlatformKeyService()
    var authorizationToken: String? = "synthetic-platform-credential"
}
enum JupyterCredentialStore { static var token = "" }
final class CrashReporter {
    static let shared = CrashReporter()
    func breadcrumb(_ message: String) {}
}
final class JupyterKernel {
    init(endpoint: String, token: String) {}
    func execute(code: String, language: String, progress: @escaping (String) -> Void) async throws -> String { "unused" }
}

final class MockHTTP: URLProtocol {
    static let lock = NSLock()
    static var refreshes = 0
    static var provisions = 0
    static var stopStatus = 500
    static var topupBody: [String: Any] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        var status = 200
        var payload: [String: Any] = [:]
        Self.lock.lock()
        if url.path.hasSuffix("/token") {
            if url.query?.contains("refresh_token") == true { Self.refreshes += 1 }
            payload = ["access_token": "synthetic-access", "refresh_token": "synthetic-refresh", "expires_in": 3600,
                       "user": ["id": "test-user", "email": "test@example.invalid"]]
        } else if url.path.hasSuffix("/users") {
            payload = ["role": "admin", "plan": "advanced", "ai_quota": 12000, "ai_used": 100]
        } else if url.path.hasSuffix("/wallet/topup") {
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count > 0 { body = Data(buffer.prefix(count)) }
            }
            Self.topupBody = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            payload = ["checkoutURL": "https://checkout.example.invalid/session"]
        } else if request.httpMethod == "DELETE" {
            status = Self.stopStatus
        } else if url.path.hasSuffix("/sessions"), request.httpMethod == "POST" {
            Self.provisions += 1
            payload = ["sessionId": "gpu-test", "wssURL": "wss://example.invalid/kernel", "jupyterToken": "fake-jupyter",
                       "gpuLabel": "Test GPU", "pricePerMinute": 1]
        }
        Self.lock.unlock()
        let data = url.path.hasSuffix("/users")
            ? try! JSONSerialization.data(withJSONObject: [payload])
            : try! JSONSerialization.data(withJSONObject: payload)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.04) { [self] in
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@main struct HardeningRegressionTests {
    @MainActor static func main() async throws {
        let suiteName = "microcode.tests.hardening.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockHTTP.self]
        let network = URLSession(configuration: config)
        defer { network.invalidateAndCancel() }
        let configuration = SupabaseAuthService.Configuration(baseURL: URL(string: "https://auth.example.invalid")!, anonKey: "public-test", redirectURL: "microcode://auth/callback")
        defaults.set("direct", forKey: "aiKeyMode")
        defaults.set("old-refresh", forKey: "cloudGPURefreshToken")
        let auth = SupabaseAuthService(defaults: defaults, network: network, configuration: { configuration })
        precondition(defaults.string(forKey: "cloudGPURefreshToken") == nil)
        let unsolicited = await auth.handleCallback(URL(string: "microcode://auth/callback#access_token=fake&email=x")!)
        precondition(!unsolicited && auth.session == nil)
        let authorize = try auth.makeOAuthURL(provider: "google")
        let authItems = URLComponents(url: authorize, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(authItems.contains { $0.name == "code_challenge_method" && $0.value == "s256" })
        let redirect = URL(string: authItems.first { $0.name == "redirect_to" }!.value!)!
        let bad = await auth.handleCallback(URL(string: "microcode://auth/callback?state=wrong&code=x")!)
        precondition(!bad)
        let callback = redirect.appending(queryItems: [URLQueryItem(name: "code", value: "server-code")])
        let accepted = await auth.handleCallback(callback)
        precondition(accepted && auth.session?.userID == "test-user")
        precondition(auth.entitlement.role == "admin" && auth.entitlement.plan == "advanced")
        precondition(auth.entitlement.tokensRemaining == 11900 && auth.entitlement.isLoaded)
        let replay = await auth.handleCallback(callback)
        precondition(!replay)
        precondition(defaults.string(forKey: "aiKeyMode") == "direct")
        for key in ["cloudGPUAuthToken", "microRentToken", "cloudGPURefreshToken"] { precondition(defaults.object(forKey: key) == nil) }
        print("PASS: PKCE callback correlation, replay rejection, Keychain-only session, mode preservation")

        async let first = auth.refreshAccessTokenIfNeeded(force: true)
        async let second = auth.refreshAccessTokenIfNeeded(force: true)
        let tokens = await (first, second)
        precondition(tokens.0 == "synthetic-access" && tokens.1 == tokens.0)
        precondition(MockHTTP.refreshes == 1)
        let refresh = Task { await auth.refreshAccessTokenIfNeeded(force: true) }
        try await Task.sleep(nanoseconds: 10_000_000)
        auth.signOut()
        _ = await refresh.value
        precondition(auth.session == nil)
        print("PASS: concurrent refresh is single-flight; logout cannot resurrect session")

        let manager = ToolApprovalManager()
        manager.mode = .safe
        let a = Task { await manager.requestApproval(toolName: "shell", arguments: [:], description: "A") }
        while manager.pendingRequest == nil { await Task.yield() }
        let b = Task { await manager.requestApproval(toolName: "file_write", arguments: [:], description: "B") }
        for _ in 0..<10 { await Task.yield() }
        precondition(manager.pendingRequest?.description == "A")
        manager.approve()
        let aResult = await a.value
        precondition(aResult && manager.pendingRequest?.description == "B")
        b.cancel()
        let bResult = await b.value
        precondition(!bResult && manager.pendingRequest == nil)
        print("PASS: concurrent approvals preserve both continuations; cancellation resolves queued work")

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let workspace = temp.appendingPathComponent("app")
        let sibling = temp.appendingPathComponent("app-private")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: workspace.appendingPathComponent("escape"), withDestinationURL: sibling)
        precondition(WorkspacePathPolicy.contains(workspace.appendingPathComponent("new.txt").path, in: workspace.path))
        precondition(!WorkspacePathPolicy.contains(sibling.path, in: workspace.path))
        precondition(!WorkspacePathPolicy.contains(workspace.appendingPathComponent("../app-private").path, in: workspace.path))
        precondition(!WorkspacePathPolicy.contains(workspace.appendingPathComponent("escape/new.txt").path, in: workspace.path))
        precondition(LocalBackendAuth.request(url: URL(string: "http://127.0.0.1:3000/api/files/read")!).value(forHTTPHeaderField: "X-MicroCode-Token") != nil)
        precondition(LocalBackendAuth.request(url: URL(string: "https://example.invalid")!).value(forHTTPHeaderField: "X-MicroCode-Token") == nil)
        print("PASS: sibling/traversal/symlink paths rejected; local capability never attached to remote requests")

        KeychainManager.shared.values.removeAll()
        DotminiPlatformKeyService.shared.authorizationToken = "mci-live-synthetic"
        let gpu = CloudGPUService(network: network, defaults: defaults)
        let topup = await gpu.topUpCustom(amountTHB: 300)
        precondition(topup.url != nil && MockHTTP.topupBody["amountBaht"] as? Int == 300)
        precondition(MockHTTP.topupBody["amount"] == nil)
        gpu.walletBalance = 100
        let type = CloudGPUService.GPUType(id: "test", label: "Test", vramGB: 1, pricePerMinute: 1, available: true)
        async let c1: Void = gpu.connect(gpu: type, onNeedTopUp: {})
        async let c2: Void = gpu.connect(gpu: type, onNeedTopUp: {})
        _ = await (c1, c2)
        precondition(MockHTTP.provisions == 1 && gpu.activeSession?.sessionId == "gpu-test")
        await gpu.stop()
        precondition(gpu.activeSession?.sessionId == "gpu-test" && gpu.status != .stopped)
        MockHTTP.stopStatus = 202
        await gpu.stop()
        precondition(gpu.activeSession != nil)
        MockHTTP.stopStatus = 204
        await gpu.stop()
        precondition(gpu.activeSession == nil && gpu.status == .stopped)
        print("PASS: GPU provision is single-flight; failed/unconfirmed stop preserves session; confirmed stop clears it")
    }
}
