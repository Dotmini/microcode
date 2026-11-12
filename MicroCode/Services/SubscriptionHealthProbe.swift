//
//  SubscriptionHealthProbe.swift
//  MicroCode
//
//  Live per-provider health check for Web Subscription mode.
//  Sends a 1-line "Reply with exactly: OK" turn through the exact same route the chat uses
//  (`AIClient.sendSync` with `keyModeOverride: "subscription"`) and classifies the failure so the
//  Settings UI can tell the user *why* a Sub does not work (not connected / expired / no credit /
//  wrong endpoint / quota / provider down) instead of failing silently in the middle of a chat.
//
//  Credentials never leave the app: reports contain only status, HTTP code and a redacted message.
//

import Foundation

public enum SubProbeStatus: String, Codable {
    case ok
    case notConnected = "not_connected"
    case authExpired = "auth_expired"
    case noCredit = "no_credit"
    case quota
    case modelOrEndpoint = "model_or_endpoint"
    case providerDown = "provider_down"
    case emptyReply = "empty_reply"
    case error
}

public struct SubProbeResult: Codable, Identifiable {
    public var id: String { provider }
    public let provider: String
    public let status: SubProbeStatus
    public let httpCode: Int?
    public let model: String
    public let route: String
    public let latencyMs: Int
    public let message: String
    public let checkedAt: Date

    /// Short human hint shown under the provider row in Settings.
    public var hint: String {
        switch status {
        case .ok: return "พร้อมใช้งาน"
        case .notConnected: return "ยังไม่ได้เชื่อมต่อ — กด Connect"
        case .authExpired: return "เซสชันหมดอายุ/ไม่ถูกต้อง — เชื่อมต่อใหม่"
        case .noCredit: return "ไม่มีเครดิต หรือแพ็กเกจ/แผนหมดอายุ — ต่ออายุกับผู้ให้บริการ"
        case .quota: return "ติดโควตา/Rate limit — รอสักครู่"
        case .modelOrEndpoint: return "โมเดลหรือ Endpoint ไม่ถูกต้อง"
        case .providerDown: return "ฝั่งผู้ให้บริการล่ม/เข้าถึงไม่ได้"
        case .emptyReply: return "เชื่อมต่อได้แต่ไม่มีคำตอบกลับ"
        case .error: return "เกิดข้อผิดพลาด"
        }
    }
}

@MainActor
public final class SubscriptionHealthProbe: ObservableObject {
    public static let shared = SubscriptionHealthProbe()

    @Published public private(set) var results: [String: SubProbeResult] = [:]
    @Published public private(set) var isRunning = false

    private init() {}

    // MARK: - Public API

    public func runAll() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let auth = SubscriptionAuthManager.shared
        for provider in SubscriptionProviderType.allCases {
            let r = await probe(provider, auth: auth)
            results[provider.rawValue] = r
        }
    }

    public func run(_ provider: SubscriptionProviderType) async {
        let r = await probe(provider, auth: SubscriptionAuthManager.shared)
        results[provider.rawValue] = r
    }

    public func runAllAndWrite(to path: String) async {
        await runAll()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let ordered = SubscriptionProviderType.allCases.compactMap { results[$0.rawValue] }
        if let data = try? enc.encode(ordered) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    // MARK: - Probe

    private func probe(_ provider: SubscriptionProviderType, auth: SubscriptionAuthManager) async -> SubProbeResult {
        let model = provider.modelInfos.first?.modelID ?? provider.defaultModel
        let hasRoute = auth.isConnected(provider) || auth.cliBridgeBinaryPath(for: provider) != nil
        guard hasRoute else {
            return SubProbeResult(
                provider: provider.rawValue, status: .notConnected, httpCode: nil,
                model: model, route: "-", latencyMs: 0,
                message: "No Web Subscription credential or authenticated CLI found.",
                checkedAt: Date()
            )
        }
        guard let aiProvider = StreamableAIProvider(rawValue: provider.aiProviderID) else {
            return SubProbeResult(
                provider: provider.rawValue, status: .error, httpCode: nil,
                model: model, route: "-", latencyMs: 0,
                message: "Unknown AI provider id \(provider.aiProviderID)", checkedAt: Date()
            )
        }

        let started = Date()
        do {
            let reply = try await withTimeout(seconds: 60) {
                try await AIClient.shared.sendSync(
                    messages: [[("_role", "user"), ("text", "Reply with exactly: OK")]],
                    systemPrompt: "You are a connectivity probe. Reply with the single word OK.",
                    provider: aiProvider,
                    model: model,
                    apiKey: "",
                    tools: nil,
                    keyModeOverride: "subscription"
                )
            }
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let clean = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Some CLI/web bridges surface billing errors as plain text; never report those as healthy.
            let lower = clean.lowercased()
            if lower.contains("credit balance is too low") || lower.contains("insufficient balance") {
                return SubProbeResult(
                    provider: provider.rawValue, status: .noCredit, httpCode: 402,
                    model: model, route: "subscription", latencyMs: ms,
                    message: Self.redact(clean), checkedAt: Date()
                )
            }
            return SubProbeResult(
                provider: provider.rawValue,
                status: clean.isEmpty ? .emptyReply : .ok,
                httpCode: 200, model: model, route: "subscription", latencyMs: ms,
                message: Self.redact(String(clean.prefix(80))), checkedAt: Date()
            )
        } catch {
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let ns = error as NSError
            let msg = Self.redact(ns.localizedDescription)
            return SubProbeResult(
                provider: provider.rawValue, status: Self.classify(code: ns.code, message: msg, domain: ns.domain),
                httpCode: (100...599).contains(ns.code) ? ns.code : nil,
                model: model, route: "subscription", latencyMs: ms,
                message: msg, checkedAt: Date()
            )
        }
    }

    // MARK: - Helpers

    static func classify(code: Int, message: String, domain: String) -> SubProbeStatus {
        let m = message.lowercased()
        if code == 402 || m.contains("credit balance") || m.contains("insufficient balance") ||
            m.contains("insufficient_quota") || m.contains("no resource package") || m.contains("\"1113\"") ||
            m.contains("\"1309\"") || m.contains("package has expired") || m.contains("套餐已到期") || m.contains("余额") {
            return .noCredit
        }
        if code == 401 || code == 403 || m.contains("unauthorized") || m.contains("invalid api key") ||
            m.contains("authentication") || m.contains("no active web subscription") || m.contains("not connected") {
            return .authExpired
        }
        if code == 429 || m.contains("rate limit") || m.contains("quota") { return .quota }
        if code == 404 || code == 400 || code == 422 || m.contains("model") && m.contains("not") { return .modelOrEndpoint }
        if code >= 500 || domain == NSURLErrorDomain || m.contains("could not connect") || m.contains("timed out") ||
            m.contains("hostname could not be found") || m.contains("offline") {
            return .providerDown
        }
        return .error
    }

    /// Strips anything that looks like a credential before it can reach disk or UI.
    static func redact(_ text: String) -> String {
        var out = text
        let patterns = [
            "sk-[A-Za-z0-9_\\-]{12,}", "tm_[A-Za-z0-9_\\-]{12,}", "AIza[0-9A-Za-z_\\-]{20,}",
            "eyJ[A-Za-z0-9_\\-]{10,}\\.[A-Za-z0-9_\\-]{10,}\\.[A-Za-z0-9_\\-]{5,}",
            "Bearer\\s+[A-Za-z0-9._\\-]{12,}", "[A-Za-z0-9]{24,}\\.[A-Za-z0-9]{8,}",
            "__Secure-[A-Za-z0-9_.\\-]+=[^;\\s]+", "1//[A-Za-z0-9_\\-]{20,}"
        ]
        for p in patterns {
            out = out.replacingOccurrences(of: p, with: "‹redacted›", options: .regularExpression)
        }
        return String(out.prefix(300))
    }

    private func withTimeout<T: Sendable>(seconds: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                              userInfo: [NSLocalizedDescriptionKey: "Probe timed out after \(Int(seconds))s"])
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }
}
