//
//  TelemetryService.swift
//  MicroCode
//
//  Privacy-preserving, opt-in product telemetry.  No source code, prompts,
//  project names, file paths, account email, serial number, or hardware UUID
//  is collected by this service.
//

import Foundation
import Metal
import Darwin

@MainActor
final class TelemetryService {
    static let shared = TelemetryService()

    private enum Key {
        static let enabled = "telemetryEnabled"
        static let installID = "telemetryAnonymousInstallID"
        static let queue = "telemetryEventQueueV1"
        static let lastMode = "telemetryLastMode"
    }

    private let endpoint = URL(string: "https://api.dotmini.net/v1/telemetry/events")!
    private var hasStarted = false
    private var flushing = false

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.enabled)
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Key.enabled)
        guard enabled else {
            UserDefaults.standard.removeObject(forKey: Key.queue)
            return
        }
        record(name: "telemetry_consent_granted")
        flush()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        guard isEnabled else { return }
        record(name: "app_launch")
        flush()
    }

    func recordMode(_ mode: EditorMode) {
        guard isEnabled else { return }
        // Mode changes may occur repeatedly while a view redraws; report only
        // actual transitions, never document or project information.
        guard UserDefaults.standard.string(forKey: Key.lastMode) != mode.rawValue else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: Key.lastMode)
        record(name: "mode_opened", mode: mode.rawValue)
        flush()
    }

    func record(name: String, mode: String? = nil) {
        guard isEnabled else { return }
        var queue = queuedEvents()
        queue.append(TelemetryEvent(
            eventID: UUID().uuidString,
            installID: installID,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            name: name,
            mode: mode,
            appVersion: appVersion,
            device: DeviceSnapshot.current
        ))
        // Keep a bounded retry queue if the device is offline.
        if queue.count > 100 { queue.removeFirst(queue.count - 100) }
        save(queue)
    }

    func flush() {
        guard isEnabled, !flushing else { return }
        let events = queuedEvents()
        guard !events.isEmpty else { return }
        flushing = true

        Task {
            defer { flushing = false }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "X-MicroCode-Telemetry-Schema")
            if let token = cloudToken, !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            do {
                request.httpBody = try JSONEncoder().encode(TelemetryEnvelope(events: events))
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    save([])
                }
            } catch {
                // Retain the bounded queue for the next launch; telemetry must
                // never interrupt editor work or surface an error to the user.
            }
        }
    }

    private var installID: String {
        if let existing = UserDefaults.standard.string(forKey: Key.installID) { return existing }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: Key.installID)
        return value
    }

    private var cloudToken: String? {
        return DotminiPlatformKeyService.shared.authorizationToken ?? SupabaseAuthService.shared.accessToken
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }

    private func queuedEvents() -> [TelemetryEvent] {
        guard let data = UserDefaults.standard.data(forKey: Key.queue) else { return [] }
        return (try? JSONDecoder().decode([TelemetryEvent].self, from: data)) ?? []
    }

    private func save(_ events: [TelemetryEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: Key.queue)
    }
}

private struct TelemetryEnvelope: Encodable {
    let schemaVersion = 1
    let events: [TelemetryEvent]
}

private struct TelemetryEvent: Codable {
    let eventID: String
    let installID: String
    let timestamp: String
    let name: String
    let mode: String?
    let appVersion: String
    let device: DeviceSnapshot

    enum CodingKeys: String, CodingKey {
        case eventID = "eventId"
        case installID = "installId"
        case timestamp, name, mode, appVersion, device
    }
}

private struct DeviceSnapshot: Codable {
    let hardwareModel: String
    let cpu: String
    let physicalCPUCount: Int
    let logicalCPUCount: Int
    let memoryBytes: UInt64
    let gpuNames: [String]
    let hasAppleNeuralEngine: Bool
    let operatingSystem: String
    let architecture: String

    enum CodingKeys: String, CodingKey {
        case hardwareModel, cpu
        case physicalCPUCount = "physicalCpuCount"
        case logicalCPUCount = "logicalCpuCount"
        case memoryBytes, gpuNames, hasAppleNeuralEngine, operatingSystem, architecture
    }

    static var current: DeviceSnapshot {
        DeviceSnapshot(
            hardwareModel: sysctlString("hw.model") ?? "unknown",
            cpu: sysctlString("machdep.cpu.brand_string") ?? "unknown CPU",
            physicalCPUCount: ProcessInfo.processInfo.processorCount,
            logicalCPUCount: ProcessInfo.processInfo.activeProcessorCount,
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            gpuNames: MTLCopyAllDevices().map(\.name),
            // Apple does not expose a public Neural Engine core-count API.
            hasAppleNeuralEngine: isAppleSilicon,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: isAppleSilicon ? "arm64" : "x86_64"
        )
    }

    private static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &value, &size, nil, 0) != 0 ||
            sysctlString("hw.optional.arm64") == "1" ||
            sysctlString("hw.machine")?.contains("arm64") == true
    }

    private static func sysctlString(_ name: String) -> String? {
        var size: size_t = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var bytes = [CChar](repeating: 0, count: Int(size))
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }
}
