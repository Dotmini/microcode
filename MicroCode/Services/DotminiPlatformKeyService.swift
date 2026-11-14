//
//  DotminiPlatformKeyService.swift
//  MicroCode
//
//  A Platform API key is a developer credential, distinct from a Supabase
//  login session. It is created by Dotmini Platform (https://platform.dotmini.net),
//  hashed with SHA-256 at rest on the server, and kept locally only in macOS Keychain.
//

import Foundation
import Combine

@MainActor
final class DotminiPlatformKeyService: ObservableObject {
    static let shared = DotminiPlatformKeyService()

    static let keychainAccount = "dotmini.platform.api-key.v1"
    static let platformOrigin = "https://platform.dotmini.net"
    private static let fallbackOrigins = [
        "https://platform.dotmini.net",
        "https://api.dotmini.net",
        "https://microcode.dotmini.net"
    ]

    @Published private(set) var apiKey: String = ""
    @Published private(set) var validationMessage = ""
    @Published private(set) var isValidating = false
    @Published private(set) var isProvisioning = false

    // Unified real-time entitlement & shared credit pool state from /api/v1/platform/me
    @Published private(set) var connectedEmail: String = ""
    @Published private(set) var keyID: String = ""
    @Published private(set) var omniAIPlan: String = ""
    @Published private(set) var microCodePlan: String = ""
    @Published private(set) var availableTHB: Double?
    @Published private(set) var creditBalanceUSD: Double?
    @Published private(set) var dailyUsed: Int?
    @Published private(set) var dailyLimit: Int?

    private init() {
        apiKey = KeychainManager.shared.readIntegrationSecret(account: Self.keychainAccount) ?? ""
    }

    var isConfigured: Bool { !apiKey.isEmpty }
    var maskedKey: String {
        guard apiKey.count > 14 else { return apiKey.isEmpty ? "Not connected" : "••••••••" }
        return "\(apiKey.prefix(16))••••\(apiKey.suffix(4))"
    }

    private static var clientHeaderValue: String {
        AppEdition.isStandaloneAI ? "microcode-ai" : "microcode"
    }

    private static var currentDeviceName: String {
        if let name = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return "Mac"
    }

    /// Platform enforces strict prefix allowlisting (`sk-dotmini-live-`, `sk-dotmini-ent-`, `mci-live-`).
    func save(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("sk-dotmini-live-") || value.hasPrefix("sk-dotmini-ent-") || value.hasPrefix("mci-live-") else {
            validationMessage = "Use an official Dotmini Platform key (sk-dotmini-live-… / sk-dotmini-ent-… / mci-live-…)."
            return false
        }
        guard KeychainManager.shared.saveIntegrationSecret(value, account: Self.keychainAccount) else {
            validationMessage = "Could not save the key to macOS Keychain."
            return false
        }
        apiKey = value
        if value.hasPrefix("sk-dotmini-ent-") {
            EnterpriseAIAuthService.shared.dotminiEnterpriseKey = value
            EnterpriseAIAuthService.shared.mode = .dotminiEnterprise
            validationMessage = "Dotmini Enterprise key saved securely in Keychain (ZDR & Governance active)."
        } else {
            validationMessage = "Dotmini Platform key saved securely in macOS Keychain."
        }
        return true
    }

    func remove() {
        KeychainManager.shared.deleteIntegrationSecret(account: Self.keychainAccount)
        apiKey = ""
        connectedEmail = ""
        keyID = ""
        omniAIPlan = ""
        microCodePlan = ""
        availableTHB = nil
        creditBalanceUSD = nil
        dailyUsed = nil
        dailyLimit = nil
        validationMessage = "Platform key removed from this Mac."
    }

    /// Prefer a Platform key whenever one exists. This keeps one developer
    /// credential valid across Omni AI, MicroCode Cloud Runtime, and model discovery.
    var authorizationToken: String? {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Validates the active Platform key against `/api/v1/platform/me`, populating
    /// unified Omni AI + MicroCode plans and shared AI credit balances.
    func validate() async -> Bool {
        guard let key = authorizationToken else {
            validationMessage = "Add or auto-connect a Dotmini Platform key first."
            return false
        }
        isValidating = true
        defer { isValidating = false }

        var lastStatusCode: Int?
        var lastError: Error?

        for origin in Self.fallbackOrigins {
            guard let url = URL(string: "\(origin)/api/v1/platform/me") else { continue }
            var request = URLRequest(url: url, timeoutInterval: 12)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(Self.clientHeaderValue, forHTTPHeaderField: "X-Dotmini-Client")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                lastStatusCode = http.statusCode

                if (200..<300).contains(http.statusCode),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    applyUnifiedMePayload(json)
                    return true
                }
                if http.statusCode == 401 || http.statusCode == 403 {
                    validationMessage = "Dotmini Platform rejected this key. Use 1-Click Auto-Connect or create a new key on platform.dotmini.net."
                    return false
                }
            } catch {
                lastError = error
            }
        }

        if let code = lastStatusCode {
            validationMessage = "Platform validation failed (HTTP \(code))."
        } else if let err = lastError {
            validationMessage = "Could not reach platform.dotmini.net: \(err.localizedDescription)"
        } else {
            validationMessage = "Could not validate Platform key."
        }
        return false
    }

    /// Redeems a 90-second single-use CSPRNG code (`otc_...`) launched from `https://platform.dotmini.net`
    /// via `microcode://platform-connect?code=otc_...` without ever exposing raw keys in URLs.
    func redeemConnectCode(_ rawCode: String) async -> Bool {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.hasPrefix("otc_"), code.count >= 20 else {
            validationMessage = "Invalid 1-Click Connect code."
            return false
        }

        isProvisioning = true
        validationMessage = "Completing secure 1-Click Connect with platform.dotmini.net…"
        defer { isProvisioning = false }

        let payload: [String: String] = [
            "code": code,
            "device_name": Self.currentDeviceName,
            "app_name": AppEdition.displayName
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            validationMessage = "Failed to encode connect request."
            return false
        }

        for origin in Self.fallbackOrigins {
            guard let url = URL(string: "\(origin)/api/platform/connect/exchange") else { continue }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(Self.clientHeaderValue, forHTTPHeaderField: "X-Dotmini-Client")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

                if (200..<300).contains(http.statusCode),
                   let provisionedKey = json["api_key"] as? String,
                   save(provisionedKey) {
                    if let email = json["email"] as? String, !email.isEmpty {
                        connectedEmail = email
                    }
                    if let kid = json["key_id"] as? String {
                        keyID = kid
                    }
                    _ = await validate()
                    return true
                }

                if http.statusCode == 400 || http.statusCode == 401 || http.statusCode == 404 || http.statusCode == 410 {
                    let serverErr = (json["error"] as? String) ?? "Connect code expired or already used."
                    validationMessage = "1-Click Connect failed: \(serverErr)"
                    return false
                }
            } catch {
                continue
            }
        }

        validationMessage = "Could not exchange 1-Click Connect code with platform.dotmini.net."
        return false
    }

    /// Provisions a dedicated SHA-256 hashed Platform API key directly from the user's
    /// active Supabase account in MicroCode (1-click, zero browser round-trip, zero copy-paste).
    func autoConnectFromSignedInAccount() async -> Bool {
        guard let accessToken = await SupabaseAuthService.shared.refreshAccessTokenIfNeeded(),
              !accessToken.isEmpty else {
            validationMessage = "Sign in to your Dotmini account above first, or click Connect on platform.dotmini.net."
            return false
        }

        isProvisioning = true
        validationMessage = "Provisioning encrypted Platform key for \(Self.currentDeviceName)…"
        defer { isProvisioning = false }

        let keyLabel = "\(AppEdition.displayName) · \(Self.currentDeviceName)"
        let payload: [String: String] = [
            "name": keyLabel,
            "prefix": "sk-dotmini-live"
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            validationMessage = "Failed to prepare key provisioning request."
            return false
        }

        for origin in Self.fallbackOrigins {
            guard let url = URL(string: "\(origin)/api/platform/keys/create") else { continue }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.httpBody = bodyData
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(Self.clientHeaderValue, forHTTPHeaderField: "X-Dotmini-Client")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

                if (200..<300).contains(http.statusCode),
                   let createdKey = (json["api_key"] as? String) ?? (json["key"] as? String),
                   save(createdKey) {
                    if let kid = json["key_id"] as? String {
                        keyID = kid
                    }
                    _ = await validate()
                    return true
                }

                if http.statusCode == 401 || http.statusCode == 403 {
                    let errMsg = (json["error"] as? String) ?? "Session unauthorized."
                    validationMessage = "Could not create Platform key: \(errMsg)"
                    return false
                }
            } catch {
                continue
            }
        }

        validationMessage = "Could not reach platform.dotmini.net to auto-provision key."
        return false
    }

    private func applyUnifiedMePayload(_ json: [String: Any]) {
        if let user = json["user"] as? [String: Any],
           let email = user["email"] as? String {
            connectedEmail = email
        }
        if let kid = json["key_id"] as? String {
            keyID = kid
        }
        if let omni = json["omni_ai"] as? [String: Any],
           let p = omni["plan"] as? String {
            omniAIPlan = p.uppercased()
        }
        if let mc = json["microcode"] as? [String: Any],
           let p = mc["plan"] as? String {
            microCodePlan = p.uppercased()
        }
        if let credits = json["credits"] as? [String: Any] {
            availableTHB = (credits["available_thb"] as? Double)
                ?? (credits["available_thb"] as? NSNumber)?.doubleValue
            creditBalanceUSD = (credits["balance_usd"] as? Double)
                ?? (credits["balance_usd"] as? NSNumber)?.doubleValue
        }
        if let quotas = json["quotas"] as? [String: Any] {
            dailyUsed = (quotas["daily_used"] as? Int) ?? (quotas["daily_used"] as? NSNumber)?.intValue
            dailyLimit = (quotas["daily_limit"] as? Int) ?? (quotas["daily_limit"] as? NSNumber)?.intValue
        }

        let mcLabel = microCodePlan.isEmpty ? "FREE" : microCodePlan
        let omniLabel = omniAIPlan.isEmpty ? "FREE" : omniAIPlan
        if let thb = availableTHB {
            validationMessage = String(
                format: "Connected to Dotmini Platform (MicroCode: %@ · Omni AI: %@ · Shared Credit: ฿%.2f).",
                mcLabel, omniLabel, thb
            )
        } else {
            validationMessage = "Connected to Dotmini Platform (MicroCode: \(mcLabel) · Omni AI: \(omniLabel))."
        }
    }
}
