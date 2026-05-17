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

    /// Override for staging via UserDefaults("cloudGPUBaseURL").
    private var baseURL: String {
        UserDefaults.standard.string(forKey: "cloudGPUBaseURL") ?? "https://gpu.microcode.net/v1"
    }

    struct GPUType: Identifiable, Decodable, Equatable {
        let id: String
        let label: String
        let vramGB: Int
        let pricePerMinute: Int      // minor units (satang)
        let available: Bool
    }

    struct Session: Equatable {
        let sessionId: String
        let wssURL: String
        let jupyterToken: String
        let gpuLabel: String
        let pricePerMinute: Int
    }

    enum Status: Equatable { case idle, loading, connecting, running, stopped, failed(String) }

    @Published var catalog: [GPUType] = []
    @Published var walletBalance: Int = 0          // minor units
    @Published var currency: String = "THB"
    @Published var status: Status = .idle
    @Published var activeSession: Session?
    @Published var lastError: String = ""

    private var pollTask: Task<Void, Never>?

    // MARK: - Auth (set from the same place BillingService gets the JWT)

    private var authToken: String? {
        UserDefaults.standard.string(forKey: "authToken")
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
                lastError = "Cloud GPU service unavailable."; return
            }
            struct Wrap: Decodable { let gpus: [GPUType] }
            catalog = (try? JSONDecoder().decode(Wrap.self, from: data))?.gpus ?? []
            if catalog.isEmpty { lastError = "No GPUs offered right now." }
        } catch {
            lastError = "Can't reach gpu.microcode.net (\(error.localizedDescription)). Cloud GPU is coming soon."
        }
    }

    func loadWallet() async {
        guard let req = request("/wallet") else { return }
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            walletBalance = (j["balance"] as? Int) ?? walletBalance
            currency = (j["currency"] as? String) ?? currency
        }
    }

    // MARK: - Session lifecycle (zero-config connect)

    func connect(gpu: GPUType, onNeedTopUp: @escaping () -> Void) async {
        guard authToken?.isEmpty == false else {
            status = .failed("Sign in first to use Cloud GPU."); return
        }
        if walletBalance < gpu.pricePerMinute { onNeedTopUp(); return }
        status = .connecting
        lastError = ""
        guard let req = request("/sessions", method: "POST", body: ["gpuId": gpu.id]) else {
            status = .failed("Bad request"); return
        }
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

    func topUp(packageId: String) async -> URL? {
        guard let req = request("/wallet/topup", method: "POST", body: ["packageId": packageId]),
              let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let s = j["checkoutURL"] as? String, let u = URL(string: s) else { return nil }
        return u
    }
}
