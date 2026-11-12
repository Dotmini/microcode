//
//  DotminiCloudProbe.swift
//  MicroCode
//
//  End-to-end health check for the Dotmini Cloud purchase chain, using the app's own signed-in session:
//  sign-in state -> entitlement -> Beam checkout link creation -> checkout link reachability -> metered chat.
//  No payment is made. Reports hold status only (no tokens, no full URLs with credentials).
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
        func add(_ name: String, _ ok: Bool, _ detail: String) { steps.append(CloudProbeStep(step: name, ok: ok, detail: SubscriptionHealthProbe.redact(detail))) }

        // 0. Public gateway
        if let (data, resp) = try? await URLSession.shared.data(from: URL(string: "https://api.dotmini.net/v1/models")!),
           let http = resp as? HTTPURLResponse {
            let count = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [Any])?.count ?? 0
            add("gateway /v1/models", http.statusCode == 200 && count > 0, "HTTP \(http.statusCode), \(count) models")
        } else {
            add("gateway /v1/models", false, "unreachable")
        }

        // 1. Sign-in state
        let auth = SupabaseAuthService.shared
        _ = await auth.bootstrapConfiguration()
        guard let session = auth.session else {
            add("signed in", false, "No Dotmini account session in this app. Sign in first (Settings → Account & License).")
            return steps
        }
        let email = session.email
        let masked = email.isEmpty ? "unknown" : String(email.prefix(2)) + "***@" + (email.split(separator: "@").last.map(String.init) ?? "")
        add("signed in", true, masked)

        // 2. Entitlement
        await auth.refreshEntitlement()
        let e = auth.entitlement
        add("entitlement", e.isLoaded,
            e.isLoaded ? "plan=\(e.plan.isEmpty ? "free" : e.plan) role=\(e.role) available=\(e.formattedAvailableCredit) planPool=\(e.formattedPlanCreditSummary) topup=฿\(e.aiTopupBalanceTHB)"
                       : "could not load /api/subscription/status")

        // 3. Checkout creation (cheapest subscription + smallest top-up). Creates unpaid Beam links only.
        for (label, plan) in [("subscription microai_lite", "microai_lite"), ("topup ai_topup_100", "ai_topup_100")] {
            do {
                let r = plan.hasPrefix("ai_topup")
                    ? try await auth.createAICreditTopupCheckout(planKey: plan)
                    : try await auth.createSubscriptionCheckout(plan: plan)
                let host = r.checkoutURL.host ?? "?"
                add("checkout create: \(label)", true, "host=\(host) amount=฿\(Int(r.amountTHB)) orderRef=\(r.orderRef.isEmpty ? "missing" : "present")")
                var req = URLRequest(url: r.checkoutURL, timeoutInterval: 15)
                req.httpMethod = "GET"
                if let (_, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse {
                    add("checkout page reachable: \(label)", (200..<400).contains(http.statusCode), "HTTP \(http.statusCode) @ \(host)")
                } else {
                    add("checkout page reachable: \(label)", false, "no response from \(host)")
                }
            } catch {
                add("checkout create: \(label)", false, error.localizedDescription)
            }
        }

        // 4. Verify endpoint answers for an unpaid order (must say not verified, never crash)
        let v = await auth.verifyLatestPayment()
        add("verify unpaid order", !v.verified, "verified=\(v.verified) msg=\(v.message.prefix(120))")

        // 5. Metered cloud chat through the gateway with the account session
        do {
            let reply = try await AIClient.shared.sendSync(
                messages: [[("_role", "user"), ("text", "Reply with exactly: OK")]],
                systemPrompt: "You are a connectivity probe. Reply with the single word OK.",
                provider: .deepseek,
                model: "deepseek-flash",
                apiKey: "",
                tools: nil,
                keyModeOverride: "cloud"
            )
            add("cloud chat", !reply.text.isEmpty, "reply=\(reply.text.prefix(40))")
        } catch {
            let ns = error as NSError
            add("cloud chat", false, "code=\(ns.code) \(ns.localizedDescription.prefix(220))")
        }
        return steps
    }

    static func runAndWrite(to path: String) async {
        let steps = await run()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(steps) { try? data.write(to: URL(fileURLWithPath: path), options: .atomic) }
    }
}
