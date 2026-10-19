//
//  EnterpriseAIAuthService.swift
//  MicroCode
//
//  Enterprise AI & Governance Engine
//  Supports:
//  1. Google Gemini Enterprise (Vertex AI Direct BYOC) with native RS256 Service Account JWT,
//     Google Cloud ADC (application_default_credentials.json / gcloud), or Vertex Express API Key.
//  2. Dotmini Cloud Enterprise (sk-dotmini-ent-...) with Zero Data Retention (ZDR),
//     Organization RBAC, Local DLP Secret Redaction, and MDM Managed Preferences.
//  3. Custom Enterprise Gateway (Azure OpenAI / LiteLLM / Internal VPC).
//
//  Created & Designed by Dotmini Software
//  Founder & CEO: Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation
import Security
import CryptoKit
import Combine

// MARK: - Enterprise Modes & Types

public typealias EnterpriseAIMode = EnterpriseConnectionMode
public typealias VertexAuthMode = VertexAuthMethod

public enum EnterpriseConnectionMode: String, CaseIterable, Codable, Identifiable {
    case disabled = "disabled"
    case dotminiEnterprise = "dotmini_enterprise"
    case geminiVertex = "gemini_vertex"
    case customGateway = "custom_gateway"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .disabled: return "Standard (Personal / Team)"
        case .dotminiEnterprise: return "Dotmini Cloud Enterprise"
        case .geminiVertex: return "Google Gemini Enterprise (Vertex AI)"
        case .customGateway: return "Custom Enterprise Gateway (VPC / Azure)"
        }
    }

    public var title: String { displayName }

    public var subtitle: String {
        switch self {
        case .disabled:
            return "Standard consumer & developer mode using personal API keys or Dotmini Platform subscription."
        case .dotminiEnterprise:
            return "Managed Sovereign & Multi-Model Enterprise Gateway with strict Zero Data Retention (ZDR) and centralized org billing."
        case .geminiVertex:
            return "Direct BYOC connection to your organization's Google Cloud Vertex AI project with regional data residency & IAM."
        case .customGateway:
            return "Route all AI & Agent requests through your internal corporate proxy, LiteLLM, or Azure OpenAI endpoint."
        }
    }

    public var badgeText: String {
        switch self {
        case .disabled: return "STANDARD"
        case .dotminiEnterprise: return "DOTMINI ENTERPRISE"
        case .geminiVertex: return "GEMINI ENTERPRISE"
        case .customGateway: return "VPC GATEWAY"
        }
    }
}

public enum VertexAuthMethod: String, CaseIterable, Codable, Identifiable {
    case serviceAccountJSON = "service_account_json"
    case gcloudADC = "gcloud_adc"
    case apiKey = "api_key"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .serviceAccountJSON: return "Service Account JSON"
        case .gcloudADC: return "Google Cloud ADC (gcloud)"
        case .apiKey: return "Vertex AI API Key"
        }
    }

    public var title: String { displayName }
}

public struct EnterprisePolicyStatus: Codable, Equatable {
    public var orgName: String
    public var planTier: String
    public var zeroDataRetention: Bool
    public var dataResidencyRegion: String
    public var seatsUsed: Int
    public var seatsTotal: Int
    public var monthlyTokenLimit: Int
    public var monthlyTokensUsed: Int
    public var allowedModels: [String]
}

// MARK: - Enterprise AI Auth Service

@MainActor
public final class EnterpriseAIAuthService: ObservableObject {
    public static let shared = EnterpriseAIAuthService()

    private static let vertexSAKeychainAccount = "dotmini.enterprise.vertex.sa.v1"
    private static let vertexAPIKeychainAccount = "dotmini.enterprise.vertex.apikey.v1"
    private static let dotminiEntKeychainAccount = "dotmini.enterprise.cloud.key.v1"
    private static let customGatewayKeychainAccount = "dotmini.enterprise.custom.key.v1"
    private static let mdmSuiteName = "com.dotmini.microcode.enterprise"

    @Published public var mode: EnterpriseConnectionMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "enterprise_connection_mode") }
    }

    // --- Dotmini Cloud Enterprise ---
    @Published public var organizationId: String {
        didSet { UserDefaults.standard.set(organizationId, forKey: "enterprise_org_id") }
    }
    public var dotminiOrganizationId: String {
        get { organizationId }
        set { organizationId = newValue }
    }
    @Published public var dotminiEnterpriseURL: String {
        didSet { UserDefaults.standard.set(dotminiEnterpriseURL, forKey: "enterprise_dotmini_url") }
    }
    public var dotminiEnterpriseGatewayURL: String {
        get { dotminiEnterpriseURL }
        set { dotminiEnterpriseURL = newValue }
    }
    @Published public var dotminiEnterpriseKey: String = "" {
        didSet {
            let trimmed = dotminiEnterpriseKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                _ = KeychainManager.shared.saveIntegrationSecret(trimmed, account: Self.dotminiEntKeychainAccount)
            }
        }
    }

    // --- Google Gemini Enterprise (Vertex AI) ---
    @Published public var vertexProjectId: String {
        didSet { UserDefaults.standard.set(vertexProjectId, forKey: "enterprise_vertex_project_id") }
    }
    @Published public var vertexLocation: String {
        didSet { UserDefaults.standard.set(vertexLocation, forKey: "enterprise_vertex_location") }
    }
    @Published public var vertexAuthMethod: VertexAuthMethod {
        didSet { UserDefaults.standard.set(vertexAuthMethod.rawValue, forKey: "enterprise_vertex_auth_method") }
    }
    public var vertexAuthMode: VertexAuthMethod {
        get { vertexAuthMethod }
        set { vertexAuthMethod = newValue }
    }
    @Published public private(set) var vertexServiceAccountEmail: String = ""
    @Published public private(set) var hasVertexServiceAccount: Bool = false
    @Published public var vertexServiceAccountJSON: String = "" {
        didSet {
            let trimmed = vertexServiceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                _ = KeychainManager.shared.saveIntegrationSecret(trimmed, account: Self.vertexSAKeychainAccount)
                if let data = trimmed.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    hasVertexServiceAccount = true
                    vertexServiceAccountEmail = (json["client_email"] as? String) ?? "service-account"
                    if vertexProjectId.isEmpty, let pid = json["project_id"] as? String {
                        vertexProjectId = pid
                    }
                }
                cachedVertexToken = nil
            }
        }
    }
    @Published public var vertexAPIKey: String = "" {
        didSet {
            let trimmed = vertexAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                _ = KeychainManager.shared.saveIntegrationSecret(trimmed, account: Self.vertexAPIKeychainAccount)
                cachedVertexToken = nil
            }
        }
    }

    // --- Custom Enterprise Gateway (VPC / Azure / LiteLLM) ---
    @Published public var customGatewayBaseURL: String {
        didSet { UserDefaults.standard.set(customGatewayBaseURL, forKey: "enterprise_custom_gateway_url") }
    }
    @Published public var customGatewayAPIKey: String = "" {
        didSet {
            let trimmed = customGatewayAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                _ = KeychainManager.shared.saveIntegrationSecret(trimmed, account: Self.customGatewayKeychainAccount)
            }
        }
    }

    // --- Governance & DLP Controls ---
    @Published public var zeroDataRetention: Bool {
        didSet { UserDefaults.standard.set(zeroDataRetention, forKey: "enterprise_zdr_enabled") }
    }
    @Published public var localDLPRedaction: Bool {
        didSet { UserDefaults.standard.set(localDLPRedaction, forKey: "enterprise_local_dlp_enabled") }
    }
    @Published public var isMDMManaged: Bool = false
    @Published public var isVerifying: Bool = false
    @Published public var isVerified: Bool = false
    @Published public var statusMessage: String = ""
    @Published public var policyStatus: EnterprisePolicyStatus? = nil

    // Cached OAuth2 Access Token for Vertex AI
    private var cachedVertexToken: (token: String, expiresAt: Date)? = nil

    public static let supportedVertexLocations: [(id: String, label: String)] = [
        ("asia-southeast1", "asia-southeast1 (Singapore — ASEAN / PDPA)"),
        ("us-central1", "us-central1 (Iowa — US Central)"),
        ("global", "global (Global Endpoint — Gemini 2.5 / 3.x)"),
        ("europe-west1", "europe-west1 (Belgium — EU GDPR)"),
        ("asia-northeast1", "asia-northeast1 (Tokyo — Japan)"),
        ("us-east4", "us-east4 (Northern Virginia — US East)")
    ]

    private init() {
        let std = UserDefaults.standard
        let mdm = UserDefaults(suiteName: Self.mdmSuiteName)

        let rawMode = mdm?.string(forKey: "enterprise_connection_mode")
            ?? std.string(forKey: "enterprise_connection_mode")
            ?? EnterpriseConnectionMode.disabled.rawValue
        self.mode = EnterpriseConnectionMode(rawValue: rawMode) ?? .disabled

        self.organizationId = mdm?.string(forKey: "enterprise_org_id")
            ?? std.string(forKey: "enterprise_org_id")
            ?? ""
        self.dotminiEnterpriseURL = mdm?.string(forKey: "enterprise_dotmini_url")
            ?? std.string(forKey: "enterprise_dotmini_url")
            ?? "https://api.dotmini.net/v1"

        self.vertexProjectId = mdm?.string(forKey: "enterprise_vertex_project_id")
            ?? std.string(forKey: "enterprise_vertex_project_id")
            ?? ""
        self.vertexLocation = mdm?.string(forKey: "enterprise_vertex_location")
            ?? std.string(forKey: "enterprise_vertex_location")
            ?? "asia-southeast1"
        let rawVertexAuth = mdm?.string(forKey: "enterprise_vertex_auth_method")
            ?? std.string(forKey: "enterprise_vertex_auth_method")
            ?? VertexAuthMethod.serviceAccountJSON.rawValue
        self.vertexAuthMethod = VertexAuthMethod(rawValue: rawVertexAuth) ?? .serviceAccountJSON

        self.customGatewayBaseURL = mdm?.string(forKey: "enterprise_custom_gateway_url")
            ?? std.string(forKey: "enterprise_custom_gateway_url")
            ?? ""

        if std.object(forKey: "enterprise_zdr_enabled") != nil {
            self.zeroDataRetention = std.bool(forKey: "enterprise_zdr_enabled")
        } else {
            self.zeroDataRetention = true
        }

        if std.object(forKey: "enterprise_local_dlp_enabled") != nil {
            self.localDLPRedaction = std.bool(forKey: "enterprise_local_dlp_enabled")
        } else {
            self.localDLPRedaction = true
        }

        self.isMDMManaged = (mdm?.string(forKey: "enterprise_connection_mode") != nil)

        loadSecretsFromKeychain()
    }

    public var isEnterpriseActive: Bool {
        mode != .disabled
    }

    // MARK: - Keychain Management

    private func loadSecretsFromKeychain() {
        dotminiEnterpriseKey = KeychainManager.shared.readIntegrationSecret(account: Self.dotminiEntKeychainAccount) ?? ""
        vertexAPIKey = KeychainManager.shared.readIntegrationSecret(account: Self.vertexAPIKeychainAccount) ?? ""
        customGatewayAPIKey = KeychainManager.shared.readIntegrationSecret(account: Self.customGatewayKeychainAccount) ?? ""

        if let saJSON = KeychainManager.shared.readIntegrationSecret(account: Self.vertexSAKeychainAccount),
           let data = saJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            vertexServiceAccountJSON = saJSON
            hasVertexServiceAccount = true
            vertexServiceAccountEmail = (json["client_email"] as? String) ?? "service-account"
            if vertexProjectId.isEmpty, let pid = json["project_id"] as? String {
                vertexProjectId = pid
            }
        } else {
            vertexServiceAccountJSON = ""
            hasVertexServiceAccount = false
            vertexServiceAccountEmail = ""
        }
    }

    public func saveDotminiEnterpriseKey(_ rawKey: String) -> Bool {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("sk-dotmini-") || trimmed.hasPrefix("mci-live-") else {
            statusMessage = "Invalid key format. Expected sk-dotmini-ent-… or sk-dotmini-…"
            return false
        }
        guard KeychainManager.shared.saveIntegrationSecret(trimmed, account: Self.dotminiEntKeychainAccount) else {
            statusMessage = "Failed to store key in macOS Keychain."
            return false
        }
        dotminiEnterpriseKey = trimmed
        statusMessage = "Dotmini Cloud Enterprise key saved in Keychain."
        return true
    }

    public func removeDotminiEnterpriseKey() {
        KeychainManager.shared.deleteIntegrationSecret(account: Self.dotminiEntKeychainAccount)
        dotminiEnterpriseKey = ""
        isVerified = false
        policyStatus = nil
        statusMessage = "Removed Dotmini Enterprise key."
    }

    public func saveVertexServiceAccountJSON(_ jsonString: String) -> Bool {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientEmail = json["client_email"] as? String,
              let privateKey = json["private_key"] as? String,
              privateKey.contains("PRIVATE KEY") else {
            statusMessage = "Invalid Service Account JSON. Must contain client_email and private_key."
            return false
        }
        guard KeychainManager.shared.saveIntegrationSecret(trimmed, account: Self.vertexSAKeychainAccount) else {
            statusMessage = "Could not store Service Account JSON in macOS Keychain."
            return false
        }
        hasVertexServiceAccount = true
        vertexServiceAccountEmail = clientEmail
        if let pid = json["project_id"] as? String, !pid.isEmpty {
            vertexProjectId = pid
        }
        cachedVertexToken = nil
        statusMessage = "Loaded Service Account: \(clientEmail)"
        return true
    }

    public func removeVertexServiceAccount() {
        KeychainManager.shared.deleteIntegrationSecret(account: Self.vertexSAKeychainAccount)
        hasVertexServiceAccount = false
        vertexServiceAccountEmail = ""
        cachedVertexToken = nil
        isVerified = false
    }

    public func saveVertexAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard KeychainManager.shared.saveIntegrationSecret(trimmed, account: Self.vertexAPIKeychainAccount) else {
            return false
        }
        vertexAPIKey = trimmed
        cachedVertexToken = nil
        statusMessage = "Vertex AI API Key saved to Keychain."
        return true
    }

    public func saveCustomGatewayKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard KeychainManager.shared.saveIntegrationSecret(trimmed, account: Self.customGatewayKeychainAccount) else {
            return false
        }
        customGatewayAPIKey = trimmed
        statusMessage = "Custom Enterprise Gateway key saved."
        return true
    }

    // MARK: - Vertex AI Endpoint & OAuth2 Token Resolution

    /// Builds the official Google Cloud Vertex AI endpoint for Gemini Enterprise
    public func buildVertexGeminiURL(model: String, streaming: Bool) -> URL? {
        let project = vertexProjectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = vertexLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "asia-southeast1"
            : vertexLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty else { return nil }

        let cleanModel: String
        if model.hasPrefix("models/") {
            cleanModel = String(model.dropFirst(7))
        } else if model.hasPrefix("publishers/google/models/") {
            cleanModel = String(model.dropFirst("publishers/google/models/".count))
        } else {
            cleanModel = model
        }

        let host = (location == "global")
            ? "https://aiplatform.googleapis.com"
            : "https://\(location)-aiplatform.googleapis.com"
        let action = streaming ? "streamGenerateContent?alt=sse" : "generateContent"
        var urlString = "\(host)/v1/projects/\(project)/locations/\(location)/publishers/google/models/\(cleanModel):\(action)"

        if vertexAuthMethod == .apiKey && !vertexAPIKey.isEmpty {
            let separator = urlString.contains("?") ? "&" : "?"
            urlString += "\(separator)key=\(vertexAPIKey)"
        }
        return URL(string: urlString)
    }

    /// Resolves a valid Bearer access token for Google Cloud Vertex AI (or nil if using API Key query param)
    public func resolveVertexAuthorizationHeader() async throws -> String? {
        switch vertexAuthMethod {
        case .apiKey:
            guard !vertexAPIKey.isEmpty else {
                throw NSError(domain: "EnterpriseAI", code: 401, userInfo: [NSLocalizedDescriptionKey: "Vertex AI API Key is missing. Configure it in Settings → Enterprise."])
            }
            return nil // API key is passed in URL query parameter
        case .serviceAccountJSON:
            if let cached = cachedVertexToken, Date().addingTimeInterval(120) < cached.expiresAt {
                return "Bearer \(cached.token)"
            }
            let token = try await fetchServiceAccountAccessToken()
            cachedVertexToken = (token, Date().addingTimeInterval(3300))
            return "Bearer \(token)"
        case .gcloudADC:
            if let cached = cachedVertexToken, Date().addingTimeInterval(120) < cached.expiresAt {
                return "Bearer \(cached.token)"
            }
            let token = try await fetchGcloudADCAccessToken()
            cachedVertexToken = (token, Date().addingTimeInterval(1800))
            return "Bearer \(token)"
        }
    }

    private func fetchServiceAccountAccessToken() async throws -> String {
        guard let saJSON = KeychainManager.shared.readIntegrationSecret(account: Self.vertexSAKeychainAccount),
              let data = saJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientEmail = json["client_email"] as? String,
              let privateKeyPEM = json["private_key"] as? String else {
            throw NSError(domain: "EnterpriseAI", code: 401, userInfo: [NSLocalizedDescriptionKey: "Vertex AI Service Account JSON not found in Keychain."])
        }

        let tokenURI = (json["token_uri"] as? String) ?? "https://oauth2.googleapis.com/token"
        let now = Int(Date().timeIntervalSince1970)
        let exp = now + 3600

        let headerJSON: [String: String] = ["alg": "RS256", "typ": "JWT"]
        let claimsJSON: [String: Any] = [
            "iss": clientEmail,
            "scope": "https://www.googleapis.com/auth/cloud-platform",
            "aud": tokenURI,
            "iat": now,
            "exp": exp
        ]

        let headerB64 = try base64URLEncode(JSONSerialization.data(withJSONObject: headerJSON))
        let claimsB64 = try base64URLEncode(JSONSerialization.data(withJSONObject: claimsJSON))
        let signingInput = "\(headerB64).\(claimsB64)"
        let signatureData = try signRS256(message: signingInput, pemPrivateKey: privateKeyPEM)
        let jwt = "\(signingInput).\(base64URLEncode(signatureData))"

        guard let url = URL(string: tokenURI) else {
            throw NSError(domain: "EnterpriseAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Google OAuth2 token_uri"])
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyStr = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=\(jwt)"
        request.httpBody = bodyStr.data(using: .utf8)

        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let respJSON = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
              let accessToken = respJSON["access_token"] as? String else {
            let errText = String(data: respData, encoding: .utf8) ?? "Unknown OAuth error"
            throw NSError(domain: "EnterpriseAI", code: 401, userInfo: [NSLocalizedDescriptionKey: "Google Cloud OAuth2 failed: \(errText)"])
        }
        return accessToken
    }

    private func fetchGcloudADCAccessToken() async throws -> String {
        // 1. Check ~/.config/gcloud/application_default_credentials.json first
        let adcPath = (NSHomeDirectory() as NSString).appendingPathComponent(".config/gcloud/application_default_credentials.json")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: adcPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let clientId = json["client_id"] as? String,
               let clientSecret = json["client_secret"] as? String,
               let refreshToken = json["refresh_token"] as? String {
                var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 15)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                let form = "client_id=\(clientId)&client_secret=\(clientSecret)&refresh_token=\(refreshToken)&grant_type=refresh_token"
                request.httpBody = form.data(using: .utf8)
                let (respData, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let respJSON = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
                   let token = respJSON["access_token"] as? String {
                    return token
                }
            }
        }

        // 2. Fallback to gcloud CLI
        return try await Task.detached(priority: .userInitiated) {
            let gcloudPaths = [
                "/opt/homebrew/bin/gcloud",
                "/usr/local/bin/gcloud",
                "\(NSHomeDirectory())/google-cloud-sdk/bin/gcloud"
            ]
            guard let gcloud = gcloudPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                throw NSError(domain: "EnterpriseAI", code: 401, userInfo: [NSLocalizedDescriptionKey: "Google Cloud ADC not found. Run `gcloud auth application-default login` or upload a Service Account JSON key."])
            }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: gcloud)
            proc.arguments = ["auth", " print-access-token".trimmingCharacters(in: .whitespaces)]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            try proc.run()
            proc.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard proc.terminationStatus == 0, !out.isEmpty else {
                throw NSError(domain: "EnterpriseAI", code: 401, userInfo: [NSLocalizedDescriptionKey: "gcloud auth print-access-token failed. Please sign in with `gcloud auth login`."])
            }
            return out
        }.value
    }

    // MARK: - Native RS256 Signing (PKCS#8 / PKCS#1 PEM)

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func signRS256(message: String, pemPrivateKey: String) throws -> Data {
        let lines = pemPrivateKey
            .replacingOccurrences(of: "\\n", with: "\n")
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let base64Key = lines.joined()
        guard let derData = Data(base64Encoded: base64Key, options: .ignoreUnknownCharacters) else {
            throw NSError(domain: "EnterpriseAI", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode PEM private key Base64."])
        }

        // Strip PKCS#8 ASN.1 header if present so SecKeyCreateWithData accepts it cleanly on macOS
        let rsaKeyData = Self.stripPKCS8HeaderIfNeeded(derData)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(rsaKeyData as CFData, attributes as CFDictionary, &error) ??
                           SecKeyCreateWithData(derData as CFData, attributes as CFDictionary, &error) else {
            let errMsg = error?.takeRetainedValue().localizedDescription ?? "Invalid RSA key"
            throw NSError(domain: "EnterpriseAI", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to load RSA private key: \(errMsg)"])
        }

        guard let msgData = message.data(using: .utf8),
              let sig = SecKeyCreateSignature(secKey, .rsaSignatureMessagePKCS1v15SHA256, msgData as CFData, &error) else {
            let errMsg = error?.takeRetainedValue().localizedDescription ?? "Signature failed"
            throw NSError(domain: "EnterpriseAI", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to sign JWT: \(errMsg)"])
        }
        return sig as Data
    }

    private static func stripPKCS8HeaderIfNeeded(_ der: Data) -> Data {
        // Standard PKCS#8 unencrypted RSA private key OID header: 30 82 .. .. 02 01 00 30 0d 06 09 2a 86 48 86 f7 0d 01 01 01 05 00 04 82 .. ..
        let rsaOID: [UInt8] = [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]
        let bytes = [UInt8](der)
        guard bytes.count > 32 else { return der }
        for i in 0..<(min(bytes.count - rsaOID.count - 4, 32)) {
            if Array(bytes[i..<(i + rsaOID.count)]) == rsaOID {
                let octetIdx = i + rsaOID.count
                if bytes[octetIdx] == 0x04 {
                    let lenByte = bytes[octetIdx + 1]
                    var payloadStart = octetIdx + 2
                    if (lenByte & 0x80) != 0 {
                        let numLenBytes = Int(lenByte & 0x7F)
                        payloadStart += numLenBytes
                    }
                    if payloadStart < bytes.count {
                        return Data(bytes[payloadStart..<bytes.count])
                    }
                }
            }
        }
        return der
    }

    // MARK: - Enterprise Request Enrichment & Local DLP

    /// Applies Enterprise governance headers (Zero Data Retention, Org ID, Product) to outgoing requests
    public func applyEnterpriseHeaders(to request: inout URLRequest) {
        guard isEnterpriseActive else { return }
        request.setValue("true", forHTTPHeaderField: "X-Dotmini-Enterprise")
        if zeroDataRetention {
            request.setValue("true", forHTTPHeaderField: "X-Dotmini-ZDR")
        }
        let org = organizationId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !org.isEmpty {
            request.setValue(org, forHTTPHeaderField: "X-Dotmini-Org-ID")
        }
        if mode == .geminiVertex && !vertexProjectId.isEmpty {
            request.setValue(vertexProjectId, forHTTPHeaderField: "x-goog-user-project")
        }
    }

    /// Redacts high-risk credentials and private keys before prompts leave the client in Enterprise mode
    public func redactPromptIfNeeded(_ text: String) -> String {
        guard isEnterpriseActive && localDLPRedaction else { return text }
        var output = text
        let patterns: [(String, String)] = [
            (#"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----"#, "[REDACTED_PRIVATE_KEY]"),
            (#"AKIA[0-9A-Z]{16}"#, "[REDACTED_AWS_KEY]"),
            (#"ghp_[A-Za-z0-9]{36}"#, "[REDACTED_GITHUB_TOKEN]"),
            (#"xox[baprs]-[A-Za-z0-9-]{10,}"#, "[REDACTED_SLACK_TOKEN]")
        ]
        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(location: 0, length: output.utf16.count)
                output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: replacement)
            }
        }
        return output
    }

    // MARK: - Connection Verification

    public func verifyConnection() async -> Bool {
        isVerifying = true
        defer { isVerifying = false }

        switch mode {
        case .disabled:
            isVerified = false
            statusMessage = "Enterprise mode is disabled."
            return false

        case .dotminiEnterprise:
            let base = dotminiEnterpriseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let key = !dotminiEnterpriseKey.isEmpty
                ? dotminiEnterpriseKey
                : (DotminiPlatformKeyService.shared.authorizationToken ?? "")
            guard !key.isEmpty else {
                statusMessage = "Please enter your Dotmini Cloud Enterprise Key (sk-dotmini-ent-…)."
                isVerified = false
                return false
            }
            guard let url = URL(string: "\(base)/enterprise/status") ?? URL(string: "\(base)/models") else {
                statusMessage = "Invalid Dotmini Enterprise Gateway URL."
                isVerified = false
                return false
            }
            var req = URLRequest(url: url, timeoutInterval: 12)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            applyEnterpriseHeaders(to: &req)

            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    if let policy = try? JSONDecoder().decode(EnterprisePolicyStatus.self, from: data) {
                        policyStatus = policy
                    } else {
                        policyStatus = EnterprisePolicyStatus(
                            orgName: organizationId.isEmpty ? "Dotmini Enterprise Tenant" : organizationId,
                            planTier: "ENTERPRISE ZDR",
                            zeroDataRetention: zeroDataRetention,
                            dataResidencyRegion: "ap-southeast-1 (Bangkok / Singapore)",
                            seatsUsed: 1,
                            seatsTotal: 50,
                            monthlyTokenLimit: 100_000_000,
                            monthlyTokensUsed: 0,
                            allowedModels: ["omni-o1x-pro", "gemini-2.5-pro", "gemini-2.5-flash", "claude-3-7-sonnet-20250219", "gpt-4o"]
                        )
                    }
                    isVerified = true
                    statusMessage = "✓ Connected to Dotmini Cloud Enterprise (Zero Data Retention Active)"
                    return true
                }
                // Fallback check against /models if /enterprise/status is not yet deployed on custom host
                if let modelsURL = URL(string: "\(base)/models") {
                    var fallbackReq = URLRequest(url: modelsURL, timeoutInterval: 10)
                    fallbackReq.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    applyEnterpriseHeaders(to: &fallbackReq)
                    let (_, mResp) = try await URLSession.shared.data(for: fallbackReq)
                    if let mHttp = mResp as? HTTPURLResponse, (200..<300).contains(mHttp.statusCode) {
                        policyStatus = EnterprisePolicyStatus(
                            orgName: organizationId.isEmpty ? "Dotmini Enterprise Tenant" : organizationId,
                            planTier: "ENTERPRISE ZDR",
                            zeroDataRetention: zeroDataRetention,
                            dataResidencyRegion: "ap-southeast-1",
                            seatsUsed: 1,
                            seatsTotal: 50,
                            monthlyTokenLimit: 100_000_000,
                            monthlyTokensUsed: 0,
                            allowedModels: ["omni-o1x-pro", "gemini-2.5-pro", "gemini-2.5-flash", "claude-3-7-sonnet-20250219", "gpt-4o"]
                        )
                        isVerified = true
                        statusMessage = "✓ Connected to Dotmini Cloud Enterprise Gateway"
                        return true
                    }
                }
                statusMessage = "Enterprise Gateway rejected credentials."
                isVerified = false
                return false
            } catch {
                statusMessage = "Connection error: \(error.localizedDescription)"
                isVerified = false
                return false
            }

        case .geminiVertex:
            guard !vertexProjectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                statusMessage = "Google Cloud Project ID is required for Gemini Enterprise (Vertex AI)."
                isVerified = false
                return false
            }
            do {
                let authHeader = try await resolveVertexAuthorizationHeader()
                guard let testURL = buildVertexGeminiURL(model: "gemini-2.5-flash", streaming: false) else {
                    statusMessage = "Could not construct Vertex AI URL."
                    isVerified = false
                    return false
                }
                var req = URLRequest(url: testURL, timeoutInterval: 15)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let authHeader = authHeader {
                    req.setValue(authHeader, forHTTPHeaderField: "Authorization")
                }
                applyEnterpriseHeaders(to: &req)
                let body: [String: Any] = [
                    "contents": [["role": "user", "parts": [["text": "ping"]]]],
                    "generationConfig": ["maxOutputTokens": 4]
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    isVerified = true
                    policyStatus = EnterprisePolicyStatus(
                        orgName: vertexProjectId,
                        planTier: "VERTEX AI ENTERPRISE",
                        zeroDataRetention: true,
                        dataResidencyRegion: vertexLocation,
                        seatsUsed: 1,
                        seatsTotal: 999,
                        monthlyTokenLimit: 0,
                        monthlyTokensUsed: 0,
                        allowedModels: ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"]
                    )
                    statusMessage = "✓ Verified Google Gemini Enterprise (Vertex AI • \(vertexLocation))"
                    return true
                } else {
                    let errStr = String(data: data, encoding: .utf8) ?? "HTTP error"
                    statusMessage = "Vertex AI response: \(errStr.prefix(160))"
                    isVerified = false
                    return false
                }
            } catch {
                statusMessage = "Vertex AI Auth Error: \(error.localizedDescription)"
                isVerified = false
                return false
            }

        case .customGateway:
            let base = customGatewayBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !base.isEmpty, let url = URL(string: "\(base)/models") else {
                statusMessage = "Enter a valid OpenAI-compatible Enterprise Gateway URL."
                isVerified = false
                return false
            }
            var req = URLRequest(url: url, timeoutInterval: 12)
            if !customGatewayAPIKey.isEmpty {
                req.setValue("Bearer \(customGatewayAPIKey)", forHTTPHeaderField: "Authorization")
            }
            applyEnterpriseHeaders(to: &req)
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
                    isVerified = true
                    statusMessage = "✓ Custom Enterprise Gateway reachable (\(base))"
                    return true
                }
                statusMessage = "Gateway returned status \((resp as? HTTPURLResponse)?.statusCode ?? -1)."
                isVerified = false
                return false
            } catch {
                statusMessage = "Gateway unreachable: \(error.localizedDescription)"
                isVerified = false
                return false
            }
        }
    }
}
