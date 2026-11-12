//
//  DotminiCloudProbe.swift
//  MicroCode
//
//  End-to-end health check for the Dotmini Cloud purchase & inference chain, using the app's own session:
//  sign-in / token refresh -> entitlement -> Beam checkout links (sub + top-ups) -> payment watch & verify ->
//  metered sync & streaming chat across live cloud models -> post-turn credit sync.
//  No real payment is submitted. Reports hold redacted status only (never tokens or secrets).
//

import Foundation

struct CloudProbeStep: Codable {
    let step: String
    let ok: Bool
    let detail: String
}

@MainActor
enum DotminiCloudProbe {

    static func run() async -> [CloudProbeStep] {
        var steps: [CloudProbeStep] = []
        func add(_ name: String, _ ok: Bool, _ detail: String) {
            steps.append(CloudProbeStep(step: name, ok: ok, detail: SubscriptionHealthProbe.redact(detail)))
        }

        let env = ProcessInfo.processInfo.environment
        let auth = SupabaseAuthService.shared
        let platformKey = DotminiPlatformKeyService.shared

        // 0. Public gateway endpoints (`api.dotmini.net` & `microcode.dotmini.net`)
        var liveModelIDs: [String] = []
        for host in ["https://api.dotmini.net/v1/models", "https://microcode.dotmini.net/v1/models"] {
            if let url = URL(string: host),
               let (data, resp) = try? await URLSession.shared.data(from: url),
               let http = resp as? HTTPURLResponse {
                let items = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [[String: Any]]) ?? []
                if liveModelIDs.isEmpty {
                    liveModelIDs = items.compactMap { $0["id"] as? String }
                }
                add("gateway \(url.host ?? host) /v1/models", http.statusCode == 200 && !items.isEmpty, "HTTP \(http.statusCode), \(items.count) models (\(liveModelIDs.joined(separator: ", ")))")
            } else {
                add("gateway \(host)", false, "unreachable")
            }
        }

        // 1. Bootstrap auth config & optional ephemeral sign-in / platform key test
        let cfgOK = await auth.bootstrapConfiguration()
        add("auth-config bootstrap", cfgOK, cfgOK ? "supabase-ai.dotmini.net ready" : "failed")

        let shouldRestoreSignout = (env["MICROCODE_CLOUD_PROBE_SIGNOUT_AFTER"] == "1")
        defer {
            if shouldRestoreSignout {
                auth.signOut()
            }
        }

        if let probeEmail = env["MICROCODE_CLOUD_PROBE_EMAIL"], !probeEmail.isEmpty,
           let probePass = env["MICROCODE_CLOUD_PROBE_PASSWORD"], !probePass.isEmpty {
            do {
                let signed = try await auth.signIn(email: probeEmail, password: probePass)
                let masked = maskEmail(signed.email)
                add("signIn(email:password:)", true, "signed in as \(masked)")
            } catch {
                add("signIn(email:password:)", false, error.localizedDescription)
            }
        }

        if let testPlatformKey = env["MICROCODE_CLOUD_PROBE_PLATFORM_KEY"], !testPlatformKey.isEmpty {
            let saved = platformKey.save(testPlatformKey)
            let valid = saved ? await platformKey.validate() : false
            add("platform key save+validate", saved && valid, platformKey.validationMessage)
            if env["MICROCODE_CLOUD_PROBE_REMOVE_PLATFORM_KEY_AFTER"] == "1" {
                platformKey.remove()
            }
        }

        // 2. Verify active session & GoTrue token refresh
        let refreshedToken = await auth.refreshAccessTokenIfNeeded(force: true)
        if let session = auth.session {
            let masked = maskEmail(session.email)
            let tokenValid = !(refreshedToken ?? "").isEmpty
            add("session & token refresh", tokenValid, "account=\(masked) refreshed=\(tokenValid) expired=\(session.isExpired)")
        } else if platformKey.authorizationToken != nil {
            let valid = await platformKey.validate()
            add("platform key session", valid, platformKey.validationMessage)
        } else {
            let reason = auth.reauthReason.isEmpty
                ? "No active Dotmini account session in this app. Sign in via Settings → Account & License."
                : "Expired session cleared cleanly: \(auth.reauthReason)"
            add("signed in", false, reason)
            return steps
        }

        // 3. Entitlement sync (`/api/subscription/status`)
        await auth.refreshEntitlement()
        let beforeEnt = auth.entitlement
        add(
            "entitlement /api/subscription/status",
            beforeEnt.isLoaded,
            beforeEnt.isLoaded
                ? "plan=\(beforeEnt.plan.isEmpty ? "free" : beforeEnt.plan) role=\(beforeEnt.role) available=\(beforeEnt.formattedAvailableCredit) planPool=\(beforeEnt.formattedPlanCreditSummary) topup=฿\(String(format: "%.2f", beforeEnt.aiTopupBalanceTHB)) tokens=\(beforeEnt.totalTokensUsed)"
                : "could not load /api/subscription/status"
        )

        // 4. Beam Checkout link creation + HTTP 200 reachability (Subscriptions + Fixed & Custom AI Top-Ups)
        if auth.session != nil {
            let checkoutCases: [(label: String, plan: String, customTHB: Double?)] = [
                ("subscription microai_lite (฿179)", "microai_lite", nil),
                ("subscription microai_pro (฿529)", "microai_pro", nil),
                ("topup ai_topup_100 (฿100)", "ai_topup_100", nil),
                ("topup ai_topup_custom (฿20)", "ai_topup_custom", 20)
            ]
            for item in checkoutCases {
                do {
                    let r: SupabaseAuthService.CheckoutSessionResult
                    if item.plan.hasPrefix("ai_topup") {
                        r = try await auth.createAICreditTopupCheckout(planKey: item.plan, customAmountTHB: item.customTHB)
                    } else {
                        r = try await auth.createSubscriptionCheckout(plan: item.plan)
                    }
                    let host = r.checkoutURL.host ?? "?"
                    add("checkout create: \(item.label)", !r.orderRef.isEmpty && r.amountTHB > 0, "host=\(host) amount=฿\(Int(r.amountTHB)) orderRef=present linkID=\(r.paymentLinkID.isEmpty ? "none" : "present")")
                    var req = URLRequest(url: r.checkoutURL, timeoutInterval: 15)
                    req.httpMethod = "GET"
                    if let (_, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse {
                        add("checkout reachable: \(item.label)", (200..<400).contains(http.statusCode), "HTTP \(http.statusCode) @ \(host)")
                    } else {
                        add("checkout reachable: \(item.label)", false, "no response from \(host)")
                    }
                } catch {
                    add("checkout create: \(item.label)", false, error.localizedDescription)
                }
            }

            // 5. Payment auto-watch & unpaid verify check
            auth.beginPaymentWatch()
            let watchStarted = auth.isWatchingPayment
            auth.cancelPaymentWatch()
            let watchStopped = !auth.isWatchingPayment
            add("payment auto-watch lifecycle", watchStarted && watchStopped, "started=\(watchStarted) cancelled=\(watchStopped)")

            let v = await auth.verifyLatestPayment()
            add("verify unpaid order", !v.verified, "verified=\(v.verified) msg=\(v.message.prefix(120))")
        }

        // 6. Metered Cloud Chat (`sendSync` across all live models + `sendMessage` SSE streaming)
        let modelsToTest = liveModelIDs.isEmpty
            ? ["deepseek-flash", "deepseek-v4-pro", "omni-o1x-pro", "omni-o1x-lite"]
            : liveModelIDs

        for modelID in modelsToTest {
            let prov: StreamableAIProvider = modelID.hasPrefix("omni") ? .omni : .deepseek
            do {
                let reply = try await AIClient.shared.sendSync(
                    messages: [[("_role", "user"), ("text", "Reply with the single word: OK")]],
                    systemPrompt: "You are a connectivity probe. Reply with the single word OK.",
                    provider: prov,
                    model: modelID,
                    apiKey: "",
                    tools: nil,
                    keyModeOverride: "cloud"
                )
                let clean = reply.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                add("cloud sendSync: \(modelID)", !clean.isEmpty, "reply=\(clean.prefix(60))")
            } catch {
                let ns = error as NSError
                add("cloud sendSync: \(modelID)", false, "code=\(ns.code) \(ns.localizedDescription.prefix(200))")
            }
        }

        // Streaming SSE check on `deepseek-flash`
        let previousKeyMode = UserDefaults.standard.string(forKey: "aiKeyMode")
        UserDefaults.standard.set("cloud", forKey: "aiKeyMode")
        let streamResult: (ok: Bool, detail: String) = await withCheckedContinuation { cont in
            var resumed = false
            var collected = ""
            AIClient.shared.sendMessage(
                prompt: "Reply with the single word: READY",
                systemPrompt: "Reply with the single word READY.",
                provider: .deepseek,
                model: "deepseek-flash",
                apiKey: "",
                onToken: { tok in collected += tok },
                onComplete: { full in
                    guard !resumed else { return }
                    resumed = true
                    let text = (full.isEmpty ? collected : full).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(returning: (!text.isEmpty, "streamed=\(text.prefix(60))"))
                },
                onError: { err in
                    guard !resumed else { return }
                    resumed = true
                    cont.resume(returning: (false, String(err.prefix(200))))
                }
            )
        }
        if let previousKeyMode {
            UserDefaults.standard.set(previousKeyMode, forKey: "aiKeyMode")
        } else {
            UserDefaults.standard.removeObject(forKey: "aiKeyMode")
        }
        add("cloud stream SSE: deepseek-flash", streamResult.ok, streamResult.detail)

        // 7. Post-turn entitlement sync check
        await auth.refreshEntitlement()
        let afterEnt = auth.entitlement
        add(
            "post-turn entitlement sync",
            afterEnt.isLoaded,
            "available=\(afterEnt.formattedAvailableCredit) topup=฿\(String(format: "%.2f", afterEnt.aiTopupBalanceTHB)) tokens=\(beforeEnt.totalTokensUsed)->\(afterEnt.totalTokensUsed)"
        )

        return steps
    }

    private static func maskEmail(_ email: String) -> String {
        guard !email.isEmpty else { return "unknown" }
        let domain = email.split(separator: "@").last.map(String.init) ?? ""
        return "\(email.prefix(2))***@\(domain)"
    }

    static func runAndWrite(to path: String) async {
        let steps = await run()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(steps) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
}
