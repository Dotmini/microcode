//
//  CloudGPUService.swift
//  MicroCode
//
//  Managed, zero-config Cloud GPU. The user picks a GPU (Titan RTX / A100 /
//  B200), MicroCode's gateway (gpu.microcode.net) provisions it behind our
//  own reverse-proxy and returns a Jupyter WSS endpoint + short-lived token.
//  The user never sees SSH / IP / provider / token. Pay-as-you-go from a
//  Wallet that is SEPARATE from the Pro subscription.
//
//  ── CLIENT ⇄ GATEWAY API CONTRACT (backend implements this; deployed
//     separately at https://gpu.microcode.net/v1, NOT in this repo) ──────────
//
//   All requests: Authorization: Bearer <user JWT>.  All money in integer
//   minor units (satang/cents) to avoid float drift.
//
//   GET  /catalog
//        → { "gpus": [ { "id":"a100", "label":"NVIDIA A100 80GB",
//                         "vramGB":80, "pricePerMinute": 1200,
//                         "available": true } , … ] }
//
//   GET  /wallet
//        → { "balance": 53000, "currency":"THB" }       // wallet only
//
//   POST /sessions            body: { "gpuId":"a100" }
//        → { "sessionId":"sess_…", "wssURL":"wss://gpu.microcode.net/s/<id>",
//            "jupyterToken":"<short-lived>", "gpuLabel":"NVIDIA A100 80GB",
//            "pricePerMinute": 1200 }
//        409 if wallet balance < pricePerMinute (body: {"error":"insufficient"})
//
//   GET    /sessions/{id}  → { "status":"running|starting|stopped|error",
//                              "elapsedSeconds":123, "costSoFar": 240 }
//   DELETE /sessions/{id}  → { "finalCost": 240, "balance": 52760 }
//
//   POST /wallet/topup        body: { "packageId":"credit_500" }
//        → { "checkoutURL":"https://checkout.stripe.com/…" }
//
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import Foundation
import Combine

@MainActor
final class CloudGPUService: ObservableObject {
    static let shared = CloudGPUService()

    /// Dedicated Cloud GPU gateway — its OWN Railway service/host, separate
    /// from the AI proxy at api.dotmini.net. Override via UserDefaults
    /// ("cloudGPUBaseURL") — exposed in Settings → Connections.
    private var baseURL: String {
        let configured = (UserDefaults.standard.string(forKey: "cloudGPUBaseURL") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let value = configured.isEmpty ? "https://gpu.dotmini.net/gpu/v1" : configured
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    struct GPUType: Identifiable, Decodable, Equatable {
        let id: String
        let label: String
        let vramGB: Int
        let pricePerMinute: Int      // minor units (satang) e.g. 48 = ฿0.48/min
        let available: Bool
        
        var pricePerHourText: String {
            let perHour = Double(pricePerMinute * 60) / 100.0
            return String(format: "฿%.2f/hr", perHour)
        }
    }

    struct TopupPackage: Identifiable {
        let id: String
        let name: String
        let amountTHB: Int
        let bonusTHB: Int
        let badge: String?
    }

    static let defaultTopupPackages: [TopupPackage] = [
        TopupPackage(id: "gpu_150", name: "Starter", amountTHB: 150, bonusTHB: 0, badge: nil),
        TopupPackage(id: "gpu_500", name: "Data Scientist", amountTHB: 500, bonusTHB: 25, badge: "Popular"),
        TopupPackage(id: "gpu_1500", name: "AI Pro Researcher", amountTHB: 1500, bonusTHB: 100, badge: "Best Value"),
        TopupPackage(id: "gpu_5000", name: "Enterprise Cluster", amountTHB: 5000, bonusTHB: 500, badge: "Team")
    ]

    static let defaultCatalog: [GPUType] = [
        GPUType(id: "rtx4090", label: "NVIDIA RTX 4090 24GB", vramGB: 24, pricePerMinute: 48, available: true),
        GPUType(id: "rtxa6000", label: "NVIDIA RTX A6000 48GB", vramGB: 48, pricePerMinute: 63, available: true),
        GPUType(id: "a100", label: "NVIDIA A100 SXM4 80GB", vramGB: 80, pricePerMinute: 152, available: true),
        GPUType(id: "h100", label: "NVIDIA H100 SXM 80GB", vramGB: 80, pricePerMinute: 263, available: true),
        GPUType(id: "b200", label: "NVIDIA B200 192GB", vramGB: 192, pricePerMinute: 480, available: true)
    ]

    struct Session: Equatable {
        let sessionId: String
        let wssURL: String
        let jupyterToken: String
        let gpuLabel: String
        let pricePerMinute: Int
    }

    /// Supports the documented response as well as snake_case aliases so a
    /// gateway rollout cannot leave the desktop client stuck connecting.
    private struct SessionResponse {
        let sessionID: String
        let endpoint: String
        let token: String
        let gpuLabel: String?
        let pricePerMinute: Int?

        init?(json: [String: Any]) {
            func string(_ keys: [String]) -> String? {
                for key in keys {
                    if let value = json[key] as? String,
                       !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return value.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                return nil
            }
            func integer(_ keys: [String]) -> Int? {
                for key in keys {
                    if let value = json[key] as? Int { return value }
                    if let value = json[key] as? NSNumber { return value.intValue }
                    if let value = json[key] as? String, let parsed = Int(value) { return parsed }
                }
                return nil
            }

            guard let sessionID = string(["sessionId", "session_id", "id"]),
                  let endpoint = string(["jupyterURL", "jupyterUrl", "wssURL", "wssUrl", "wsURL", "wsUrl", "endpoint"]),
                  let token = string(["jupyterToken", "jupyter_token", "token"]) else {
                return nil
            }

            self.sessionID = sessionID
            self.endpoint = endpoint
            self.token = token
            self.gpuLabel = string(["gpuLabel", "gpu_label"])
            self.pricePerMinute = integer(["pricePerMinute", "price_per_minute"])
        }
    }

    enum Status: Equatable { case idle, loading, connecting, running, stopped, failed(String) }

    @Published var catalog: [GPUType] = CloudGPUService.defaultCatalog
    @Published var walletBalance: Int = 0          // minor units (satang)
    @Published var currency: String = "THB"
    @Published var status: Status = .idle
    @Published var activeSession: Session?
    @Published var lastError: String = ""
    @Published var activeSessionElapsedSeconds: Int = 0
    @Published var activeSessionCostSatang: Int = 0
    @Published var gatewayMessage: String = ""

    private var pollTask: Task<Void, Never>?
    private var sessionTimerTask: Task<Void, Never>?

    // MARK: - Auth (the same app identity token used by AIClient / Billing /
    // ComputeKernel to call api.dotmini.net — NOT a separate "authToken").

    private var authToken: String? {
        if let platformKey = DotminiPlatformKeyService.shared.authorizationToken {
            return platformKey
        }
        let d = UserDefaults.standard
        // The managed gateway verifies an account JWT. A human-readable
        // mc_live_* license is deliberately not sent as a bearer credential.
        for k in ["cloudGPUAuthToken", "microRentToken"] {
            if let v = d.string(forKey: k)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !v.isEmpty { return v }
        }
        return nil
    }

    /// Supabase access tokens are refreshed through the app's single account
    /// service. No Firebase endpoint or manually pasted GPU credential is
    /// involved in starting a managed GPU session.
    private func refreshCloudIdentityIfPossible() async {
        _ = await SupabaseAuthService.shared.refreshAccessTokenIfNeeded()
    }

    private func request(_ path: String, method: String = "GET",
                         body: [String: Any]? = nil) -> URLRequest? {
        guard let url = URL(string: baseURL + path) else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.timeoutInterval = 20
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = authToken, !t.isEmpty { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        if let b = body { r.httpBody = try? JSONSerialization.data(withJSONObject: b) }
        return r
    }

    private func money(_ minor: Int) -> String {
        let v = Double(minor) / 100.0
        return String(format: "%@%.2f", currency == "THB" ? "฿" : "$", v)
    }
    func priceText(_ minor: Int) -> String { money(minor) + "/min" }
    var balanceText: String { money(walletBalance) }

    private func restoreInitialBalance() {
        let saved = UserDefaults.standard.integer(forKey: "gpuWalletBalanceSatang")
        if saved > 0 {
            walletBalance = saved
        }
    }

    private init() {
        restoreInitialBalance()
    }

    // MARK: - Catalog & Wallet

    func refresh() async {
        gatewayMessage = "Refreshing Cloud GPU catalog and wallet…"
        await loadCatalog()
        await loadWallet()
        if lastError.isEmpty { gatewayMessage = "Cloud GPU gateway reachable." }
    }

    private func serverMessage(data: Data, response: URLResponse?, fallback: String) -> String {
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["error", "message", "detail", "reason"] {
                if let value = json[key] as? String, !value.isEmpty {
                    return "\(fallback) (HTTP \(code)): \(value)"
                }
            }
        }
        return code > 0 ? "\(fallback) (HTTP \(code))." : fallback
    }

    private func integer(_ json: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = json[key] as? Int { return value }
            if let value = json[key] as? NSNumber { return value.intValue }
            if let value = json[key] as? String, let parsed = Int(value) { return parsed }
        }
        return nil
    }

    /// Provisioning returns a Jupyter proxy as wss://. The Jupyter REST base
    /// must be http(s); JupyterClient adds its own /channels WebSocket.
    private func jupyterHTTPBase(from endpoint: String) -> String {
        var value = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("wss://") {
            value = "https://" + value.dropFirst(6)
        } else if value.hasPrefix("ws://") {
            value = "http://" + value.dropFirst(5)
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func loadCatalog() async {
        guard let req = request("/catalog") else {
            lastError = "Cloud GPU gateway URL is invalid."
            return
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                lastError = serverMessage(data: data, response: resp, fallback: "Couldn't load Cloud GPU catalog")
                if catalog.isEmpty { catalog = CloudGPUService.defaultCatalog }
                return
            }
            struct Wrap: Decodable { let gpus: [GPUType] }
            let loaded = (try? JSONDecoder().decode(Wrap.self, from: data))?.gpus ?? []
            if !loaded.isEmpty {
                catalog = loaded
                lastError = ""
            } else {
                lastError = "Cloud GPU gateway returned an empty catalog."
                if catalog.isEmpty { catalog = CloudGPUService.defaultCatalog }
            }
        } catch {
            lastError = "Couldn't reach Cloud GPU gateway: \(error.localizedDescription)"
            if catalog.isEmpty { catalog = CloudGPUService.defaultCatalog }
        }
    }

    func loadWallet() async {
        await refreshCloudIdentityIfPossible()
        guard authToken != nil else {
            lastError = "Sign in first. Cloud GPU needs a valid account token, not only a local license label."
            return
        }
        guard let req = request("/wallet") else {
            lastError = "Cloud GPU gateway URL is invalid."
            return
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let balance = integer(json, keys: ["balance"]) else {
                lastError = serverMessage(data: data, response: resp, fallback: "Couldn't load GPU wallet")
                return
            }
            // Zero is a real wallet balance and must replace stale cache.
            walletBalance = max(0, balance)
            currency = (json["currency"] as? String) ?? currency
            UserDefaults.standard.set(walletBalance, forKey: "gpuWalletBalanceSatang")
            lastError = ""
            return
        } catch {
            lastError = "Couldn't reach GPU wallet: \(error.localizedDescription)"
            return
        }
        
    }

    // MARK: - Session lifecycle (zero-config connect)

    /// The IDE provisions a managed session on first cloud-cell run. Users
    /// never need to paste an SSH command, Jupyter URL, or token.
    func ensureManagedSession() async throws {
        if activeSession != nil, status == .running { return }
        await refresh()
        guard authToken?.isEmpty == false else {
            throw NSError(domain: "CloudGPUService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Sign in to MicroCode once, then run the cell again. Cloud GPU is configured automatically after sign-in."])
        }
        guard let gpu = catalog
            .filter(\.available)
            .sorted(by: { $0.pricePerMinute < $1.pricePerMinute })
            .first(where: { walletBalance >= $0.pricePerMinute }) else {
            throw NSError(domain: "CloudGPUService", code: 402, userInfo: [NSLocalizedDescriptionKey: "GPU Wallet balance is \(balanceText). Add GPU credit to run a cloud cell; MicroCode will choose and configure the lowest-cost available GPU automatically."])
        }
        await connect(gpu: gpu, onNeedTopUp: {})
        guard activeSession != nil, status == .running else {
            throw NSError(domain: "CloudGPUService", code: 503, userInfo: [NSLocalizedDescriptionKey: lastError.isEmpty ? "Cloud GPU session did not become ready." : lastError])
        }
    }

    func connect(gpu: GPUType, onNeedTopUp: @escaping () -> Void) async {
        await refreshCloudIdentityIfPossible()
        guard authToken?.isEmpty == false else {
            let message = "Sign in first to use Cloud GPU. Your account token is missing."
            lastError = message
            status = .failed(message)
            return
        }
        if walletBalance < gpu.pricePerMinute {
            lastError = "GPU wallet balance is too low for \(gpu.label). Add credits, then launch again."
            onNeedTopUp()
            return
        }
        status = .connecting
        lastError = ""
        gatewayMessage = "Requesting \(gpu.label) from the Cloud GPU gateway…"
        guard var req = request("/sessions", method: "POST", body: ["gpuId": gpu.id]) else {
            let message = "Cloud GPU gateway URL is invalid."
            lastError = message
            status = .failed(message)
            return
        }
        // Provisioning waits for the pod + Jupyter to actually be ready
        // (2-4 min). 20s default would time out → bump for this call only.
        req.timeoutInterval = 360
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if code == 409 {
                lastError = serverMessage(data: data, response: resp, fallback: "GPU wallet has insufficient credit")
                status = .idle
                onNeedTopUp()
                return
            }
            guard (200...201).contains(code),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let response = SessionResponse(json: json) else {
                let message = serverMessage(data: data, response: resp, fallback: "Could not start a GPU session")
                lastError = message
                status = .failed(message)
                return
            }
            let s = Session(sessionId: response.sessionID, wssURL: response.endpoint, jupyterToken: response.token,
                            gpuLabel: response.gpuLabel ?? gpu.label,
                            pricePerMinute: response.pricePerMinute ?? gpu.pricePerMinute)
            activeSession = s
            activeSessionElapsedSeconds = 0
            activeSessionCostSatang = 0
            // Reuse the hardened Jupyter kernel path using its HTTP base.
            let jupyterBase = jupyterHTTPBase(from: s.wssURL)
            UserDefaults.standard.set(jupyterBase, forKey: "hpcEndpoint")
            UserDefaults.standard.set(s.jupyterToken, forKey: "hpcToken")
            status = .running
            gatewayMessage = "\(s.gpuLabel) is ready. Notebook cells now use its Jupyter kernel."
            CrashReporter.shared.breadcrumb("CloudGPU.session \(s.sessionId) \(s.gpuLabel) → \(jupyterBase)")
            startPolling(s.sessionId)
            startSessionTimer()
        } catch {
            let message = "Connect failed: \(error.localizedDescription)"
            lastError = message
            status = .failed(message)
        }
    }

    private func startPolling(_ sid: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, let req = self.request("/sessions/\(sid)") else { return }
                if let (data, response) = try? await URLSession.shared.data(for: req),
                   let http = response as? HTTPURLResponse,
                   let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    guard (200...299).contains(http.statusCode) else {
                        let message = self.serverMessage(data: data, response: response, fallback: "Lost Cloud GPU session status")
                        self.lastError = message
                        self.status = .failed(message)
                        self.clearManagedSession()
                        return
                    }
                    let st = (j["status"] as? String) ?? "running"
                    if let elapsed = self.integer(j, keys: ["elapsedSeconds", "elapsed_seconds"]) {
                        self.activeSessionElapsedSeconds = max(0, elapsed)
                    }
                    if let cost = self.integer(j, keys: ["costSoFar", "cost_so_far", "cost"]) {
                        self.activeSessionCostSatang = max(0, cost)
                    }
                    if st == "stopped" || st == "error" {
                        let message = st == "error"
                            ? ((j["error"] as? String) ?? "Cloud GPU session ended on the server.")
                            : "Cloud GPU session stopped."
                        self.lastError = st == "error" ? message : ""
                        self.status = st == "error" ? .failed(message) : .stopped
                        self.clearManagedSession()
                        await self.loadWallet()
                        return
                    }
                }
            }
        }
    }

    private func startSessionTimer() {
        sessionTimerTask?.cancel()
        sessionTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.activeSession != nil, self.status == .running else { return }
                self.activeSessionElapsedSeconds += 1
                if let price = self.activeSession?.pricePerMinute {
                    self.activeSessionCostSatang = max(
                        self.activeSessionCostSatang,
                        Int((Double(self.activeSessionElapsedSeconds) / 60.0 * Double(price)).rounded(.down))
                    )
                }
            }
        }
    }

    private func clearManagedSession() {
        pollTask?.cancel()
        sessionTimerTask?.cancel()
        if let session = activeSession,
           UserDefaults.standard.string(forKey: "hpcToken") == session.jupyterToken {
            UserDefaults.standard.removeObject(forKey: "hpcEndpoint")
            UserDefaults.standard.removeObject(forKey: "hpcToken")
        }
        activeSession = nil
        activeSessionElapsedSeconds = 0
        activeSessionCostSatang = 0
    }

    // MARK: - Data transfer (Jupyter Contents API through the secure proxy)
    //
    // The session's wss URL is itself a reverse-proxy to the pod's Jupyter,
    // so the same authenticated endpoint serves /api/contents for file I/O
    // — no SSH, no S3, no extra plumbing.

    private func jupyterBase() -> (url: String, token: String)? {
        guard let s = activeSession else { return nil }
        return (jupyterHTTPBase(from: s.wssURL), s.jupyterToken)
    }

    private func contentsURL(_ remotePath: String) -> URL? {
        guard let b = jupyterBase() else { return nil }
        let p = remotePath.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        return URL(string: "\(b.url)/api/contents/\(p)")
    }

    /// Upload a local file to the connected GPU pod via Jupyter Contents API.
    /// Returns nil on success, an error message otherwise.
    func uploadFile(_ local: URL, to remotePath: String) async -> String? {
        guard let url = contentsURL(remotePath), let base = jupyterBase() else {
            return "No active GPU session."
        }
        guard let data = try? Data(contentsOf: local) else { return "Couldn't read file." }
        if data.count > 100 * 1024 * 1024 { return "File too large (>100 MB) — split or use object storage." }
        var r = URLRequest(url: url)
        r.httpMethod = "PUT"
        r.timeoutInterval = 120
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("token \(base.token)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "type": "file", "format": "base64",
            "content": data.base64EncodedString()
        ]
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, resp) = try? await URLSession.shared.data(for: r),
              let code = (resp as? HTTPURLResponse)?.statusCode else {
            return "Network error during upload."
        }
        return (200...299).contains(code) ? nil : "Upload failed (HTTP \(code))."
    }

    /// Download a file from the pod to a local URL.
    func downloadFile(_ remotePath: String, to local: URL) async -> String? {
        guard let url = contentsURL(remotePath), let base = jupyterBase() else {
            return "No active GPU session."
        }
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.queryItems = [URLQueryItem(name: "content", value: "1")]
        guard let qURL = c?.url else { return "Bad URL." }
        var r = URLRequest(url: qURL)
        r.timeoutInterval = 120
        r.setValue("token \(base.token)", forHTTPHeaderField: "Authorization")
        guard let (d, resp) = try? await URLSession.shared.data(for: r),
              let code = (resp as? HTTPURLResponse)?.statusCode else {
            return "Network error during download."
        }
        guard (200...299).contains(code) else { return "Download failed (HTTP \(code))." }
        guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return "Bad response from server."
        }
        let format = (j["format"] as? String) ?? "text"
        let content = (j["content"] as? String) ?? ""
        let bytes: Data
        if format == "base64" {
            bytes = Data(base64Encoded: content) ?? Data()
        } else {
            bytes = content.data(using: .utf8) ?? Data()
        }
        do { try bytes.write(to: local); return nil }
        catch { return "Couldn't save locally: \(error.localizedDescription)" }
    }

    func stop() async {
        let session = activeSession
        pollTask?.cancel()
        sessionTimerTask?.cancel()
        if let sid = activeSession?.sessionId, let req = request("/sessions/\(sid)", method: "DELETE") {
            if let (data, response) = try? await URLSession.shared.data(for: req),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let balance = integer(json, keys: ["balance"]) {
                    walletBalance = max(0, balance)
                    UserDefaults.standard.set(walletBalance, forKey: "gpuWalletBalanceSatang")
                } else if !(200...299).contains((response as? HTTPURLResponse)?.statusCode ?? -1) {
                    lastError = serverMessage(data: data, response: response, fallback: "Couldn't stop Cloud GPU session")
                }
            }
        }
        if let session, UserDefaults.standard.string(forKey: "hpcToken") == session.jupyterToken {
            UserDefaults.standard.removeObject(forKey: "hpcEndpoint")
            UserDefaults.standard.removeObject(forKey: "hpcToken")
        }
        activeSession = nil
        activeSessionElapsedSeconds = 0
        activeSessionCostSatang = 0
        status = .stopped
        gatewayMessage = "Cloud GPU disconnected."
        await loadWallet()
    }

    // MARK: - Wallet top-up (separate from subscription)

    func topUp(packageId: String) async -> (url: URL?, error: String?) {
        guard let req = request("/wallet/topup", method: "POST", body: ["packageId": packageId]) else {
            return (nil, "Could not build request.")
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            return (nil, "Can't reach the Cloud GPU service. Check your connection.")
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if code == 200, let s = j?["checkoutURL"] as? String, let u = URL(string: s) {
            return (u, nil)
        }
        if code == 401 {
            return (nil, "Sign in to MicroCode first (Settings → License), then try again.")
        }
        return (nil, (j?["error"] as? String) ?? "Top-up unavailable (HTTP \(code)).")
    }

    func topUpCustom(amountTHB: Int) async -> (url: URL?, error: String?) {
        guard let req = request("/wallet/topup", method: "POST", body: ["amount": amountTHB * 100]) else {
            return (nil, "Could not build request.")
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            return (nil, "Can't reach the Cloud GPU service. Check your connection.")
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if code == 200, let s = j?["checkoutURL"] as? String, let u = URL(string: s) {
            return (u, nil)
        }
        return (nil, (j?["error"] as? String) ?? "Top-up unavailable (HTTP \(code)).")
    }

    // MARK: - Direct Cloud Git Ingestion (10 Gbps Direct Clone to Cloud Volume)

    /// Ingests a Git repository (GitHub / GitLab / HuggingFace) directly into the Cloud GPU Pod's
    /// persistent storage (/workspace/data/ or /workspace/...) without routing through local internet.
    func cloneGitRepository(repoURL: String,
                            branch: String = "main",
                            token: String? = nil,
                            destination: String = "data",
                            progress: @escaping (String) -> Void) async throws -> String {
        guard let s = activeSession else {
            throw NSError(domain: "CloudGPUService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No active Cloud GPU session. Connect to a GPU first."])
        }

        var authURL = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = token, !t.isEmpty {
            if authURL.hasPrefix("https://github.com/") {
                authURL = authURL.replacingOccurrences(of: "https://github.com/", with: "https://oauth2:\(t)@github.com/")
            } else if authURL.hasPrefix("https://gitlab.com/") {
                authURL = authURL.replacingOccurrences(of: "https://gitlab.com/", with: "https://oauth2:\(t)@gitlab.com/")
            }
        }

        let targetDir = destination.hasPrefix("/") ? destination : "/workspace/\(destination)"
        let cloneScript = """
        import os
        import subprocess

        target_dir = "\(targetDir)"
        repo_url = "\(authURL)"
        branch = "\(branch.isEmpty ? "main" : branch)"

        os.makedirs("/workspace", exist_ok=True)
        print(f"🚀 [Dotmini Cloud 10Gbps Ingest] Cloning {repo_url.split('@')[-1]} into {target_dir}...")

        cmd = ["git", "clone", "--depth", "1", "-b", branch, repo_url, target_dir]
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in proc.stdout:
            print(line, end="")
        proc.wait()

        if proc.returncode == 0:
            print(f"✅ Ingestion successful! Dataset ready at {target_dir}")
            # Try pulling Git LFS if present
            subprocess.run(["git", "-C", target_dir, "lfs", "pull"], capture_output=True)
        else:
            print(f"❌ Git clone failed with exit code {proc.returncode}")
        """

        let kernel = JupyterKernel(endpoint: jupyterHTTPBase(from: s.wssURL), token: s.jupyterToken)
        return try await kernel.execute(code: cloneScript, language: "python", progress: progress)
    }

    /// List dataset files inside the Cloud GPU volume
    func listCloudFiles(remotePath: String = "") async -> [String] {
        guard let url = contentsURL(remotePath), let base = jupyterBase() else { return [] }
        var r = URLRequest(url: url)
        r.setValue("token \(base.token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else { return [] }
        return content.compactMap { $0["name"] as? String }
    }
}
