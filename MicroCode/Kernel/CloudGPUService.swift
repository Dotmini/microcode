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
        let s = UserDefaults.standard.string(forKey: "cloudGPUBaseURL") ?? ""
        return s.isEmpty ? "https://gpu.dotmini.net/gpu/v1" : s
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

    enum Status: Equatable { case idle, loading, connecting, running, stopped, failed(String) }

    @Published var catalog: [GPUType] = CloudGPUService.defaultCatalog
    @Published var walletBalance: Int = 0          // minor units (satang)
    @Published var currency: String = "THB"
    @Published var status: Status = .idle
    @Published var activeSession: Session?
    @Published var lastError: String = ""
    @Published var activeSessionElapsedSeconds: Int = 0
    @Published var activeSessionCostSatang: Int = 0

    private var pollTask: Task<Void, Never>?
    private var sessionTimerTask: Task<Void, Never>?

    // MARK: - Auth (the same app identity token used by AIClient / Billing /
    // ComputeKernel to call api.dotmini.net — NOT a separate "authToken").

    private var authToken: String? {
        let d = UserDefaults.standard
        for k in ["microRentToken", "dotminiLicenseKey"] {
            if let v = d.string(forKey: k)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !v.isEmpty { return v }
        }
        return nil
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

    var isAdmin: Bool {
        let email = (UserDefaults.standard.string(forKey: "dotminiUserEmail") ?? "").lowercased()
        let key = (UserDefaults.standard.string(forKey: "dotminiLicenseKey") ?? "").lowercased()
        return email == "tirawatnantamas@gmail.com" || key.contains("admin") || key.contains("tirawat")
    }

    private func restoreInitialBalance() {
        let saved = UserDefaults.standard.integer(forKey: "gpuWalletBalanceSatang")
        if saved > 0 {
            walletBalance = saved
        } else if isAdmin {
            walletBalance = 20000 // ฿200.00 default Admin credit
            UserDefaults.standard.set(20000, forKey: "gpuWalletBalanceSatang")
        }
    }

    private init() {
        restoreInitialBalance()
    }

    // MARK: - Catalog & Wallet

    func refresh() async {
        await loadCatalog()
        await loadWallet()
    }

    func loadCatalog() async {
        guard let req = request("/catalog") else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                if catalog.isEmpty { catalog = CloudGPUService.defaultCatalog }
                return
            }
            struct Wrap: Decodable { let gpus: [GPUType] }
            let loaded = (try? JSONDecoder().decode(Wrap.self, from: data))?.gpus ?? []
            if !loaded.isEmpty { catalog = loaded }
            else if catalog.isEmpty { catalog = CloudGPUService.defaultCatalog }
        } catch {
            if catalog.isEmpty { catalog = CloudGPUService.defaultCatalog }
        }
    }

    func loadWallet() async {
        // 1. Try fetching from GPU gateway
        if let req = request("/wallet"),
           let (data, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let bal = j["balance"] as? Int, bal > 0 {
                walletBalance = bal
            }
            currency = (j["currency"] as? String) ?? currency
        }
        
        // 2. Try fetching from Firebase RTDB if configured
        if let token = UserDefaults.standard.string(forKey: "microRentToken"), !token.isEmpty,
           let baseURL = UserDefaults.standard.string(forKey: "firebaseRTDBUrl"), !baseURL.isEmpty,
           let url = URL(string: "\(baseURL)/users/\(token)/walletBalance.json"),
           let (data, resp) = try? await URLSession.shared.data(from: url),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let str = String(data: data, encoding: .utf8),
           let bal = Int(str.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))), bal > 0 {
            walletBalance = max(walletBalance, bal)
        }
        
        // 3. For Master Admin (tirawatnantamas@gmail.com), guarantee at least ฿200.00 (20000 satang)
        if isAdmin && walletBalance < 20000 {
            walletBalance = 20000
        }
        
        UserDefaults.standard.set(walletBalance, forKey: "gpuWalletBalanceSatang")
    }

    // MARK: - Session lifecycle (zero-config connect)

    func connect(gpu: GPUType, onNeedTopUp: @escaping () -> Void) async {
        guard authToken?.isEmpty == false else {
            status = .failed("Sign in first to use Cloud GPU."); return
        }
        if walletBalance < gpu.pricePerMinute { onNeedTopUp(); return }
        status = .connecting
        lastError = ""
        guard var req = request("/sessions", method: "POST", body: ["gpuId": gpu.id]) else {
            status = .failed("Bad request"); return
        }
        // Provisioning waits for the pod + Jupyter to actually be ready
        // (2-4 min). 20s default would time out → bump for this call only.
        req.timeoutInterval = 360
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if code == 409 { status = .idle; onNeedTopUp(); return }
            guard code == 200 || code == 201,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sid = j["sessionId"] as? String,
                  let wss = j["wssURL"] as? String,
                  let tok = j["jupyterToken"] as? String else {
                status = .failed("Could not start a GPU session (HTTP \(code)).")
                return
            }
            let s = Session(sessionId: sid, wssURL: wss, jupyterToken: tok,
                            gpuLabel: (j["gpuLabel"] as? String) ?? gpu.label,
                            pricePerMinute: (j["pricePerMinute"] as? Int) ?? gpu.pricePerMinute)
            activeSession = s
            // Reuse the hardened Jupyter kernel path: it reads these.
            UserDefaults.standard.set(s.wssURL, forKey: "hpcEndpoint")
            UserDefaults.standard.set(s.jupyterToken, forKey: "hpcToken")
            status = .running
            CrashReporter.shared.breadcrumb("CloudGPU.session \(sid) \(s.gpuLabel) → \(wss)")
            startPolling(sid)
        } catch {
            status = .failed("Connect failed: \(error.localizedDescription)")
        }
    }

    private func startPolling(_ sid: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, let req = self.request("/sessions/\(sid)") else { return }
                if let (data, _) = try? await URLSession.shared.data(for: req),
                   let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let st = (j["status"] as? String) ?? "running"
                    if st == "stopped" || st == "error" {
                        self.status = st == "error" ? .failed("Session ended (server).") : .stopped
                        self.activeSession = nil
                        await self.loadWallet()
                        return
                    }
                }
            }
        }
    }

    // MARK: - Data transfer (Jupyter Contents API through the secure proxy)
    //
    // The session's wss URL is itself a reverse-proxy to the pod's Jupyter,
    // so the same authenticated endpoint serves /api/contents for file I/O
    // — no SSH, no S3, no extra plumbing.

    private func jupyterBase() -> (url: String, token: String)? {
        guard let s = activeSession else { return nil }
        var b = s.wssURL
        if b.hasPrefix("wss://") { b = "https://" + b.dropFirst(6) }
        else if b.hasPrefix("ws://") { b = "http://" + b.dropFirst(5) }
        return (b.trimmingCharacters(in: CharacterSet(charactersIn: "/")), s.jupyterToken)
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
        pollTask?.cancel()
        if let sid = activeSession?.sessionId, let req = request("/sessions/\(sid)", method: "DELETE") {
            _ = try? await URLSession.shared.data(for: req)
        }
        activeSession = nil
        status = .stopped
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

        let kernel = JupyterKernel(endpoint: s.wssURL, token: s.jupyterToken)
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

