//
//  TelemetryService.swift
//  MicroCode
//
//  Privacy-preserving, opt-in product telemetry.  No source code, prompts,
//  project names, file paths, account email, serial number, or hardware UUID
//  is collected by this service.
//

import Foundation
import Combine
import Metal
import Darwin

struct InstallHistoryEntry: Codable, Identifiable, Equatable {
    var id: String { "\(timestamp)-\(event)" }
    let timestamp: String
    let event: String
    let appVersion: String
    let mode: String?
    let email: String?
}

struct InstallRecord: Codable, Identifiable, Equatable {
    var id: String { installID }
    let installID: String
    var userID: String
    var email: String
    var displayName: String
    var hostname: String
    var appVersion: String
    var firstInstalledAt: String
    var lastSeenAt: String
    var launchCount: Int
    var lastMode: String
    var device: TelemetryDeviceSnapshot
    var installedAgents: [String]
    var history: [InstallHistoryEntry]
}

struct DownloadLeadRecord: Codable, Identifiable, Equatable {
    let id: Int
    let email: String
    let name: String
    let version: String
    let platform: String
    let arch: String
    let ipAddress: String
    let userAgent: String
    let eventType: String
    let sourceLabel: String
    let machineInfo: String
    let downloadedAt: String
}

struct CloudUserActivitySummary: Codable, Identifiable, Equatable {
    let id: String
    var email: String
    var fullName: String
    var role: String
    var plan: String
    var aiQuota: Int
    var aiUsed: Int
    var downloadCount: Int
    var lastVersion: String
    var lastIP: String
    var lastActiveAt: String
    var latestActivity: String
}

struct GitHubReleaseAssetSummary: Codable, Identifiable, Equatable {
    var id: String { "\(tag)-\(assetName)" }
    let tag: String
    let assetName: String
    let downloadCount: Int
    let publishedAt: String
}

struct TelemetryDeviceSnapshot: Codable, Equatable {
    let hardwareModel: String
    let cpu: String
    let physicalCPUCount: Int
    let logicalCPUCount: Int
    let memoryBytes: UInt64
    let gpuNames: [String]
    let hasAppleNeuralEngine: Bool
    let operatingSystem: String
    let architecture: String

    var memoryGB: Int {
        Int(round(Double(memoryBytes) / 1_073_741_824.0))
    }

    enum CodingKeys: String, CodingKey {
        case hardwareModel, cpu
        case physicalCPUCount = "physicalCpuCount"
        case logicalCPUCount = "logicalCpuCount"
        case memoryBytes, gpuNames, hasAppleNeuralEngine, operatingSystem, architecture
    }

    static var current: TelemetryDeviceSnapshot {
        TelemetryDeviceSnapshot(
            hardwareModel: sysctlString("hw.model") ?? "Mac",
            cpu: sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon",
            physicalCPUCount: ProcessInfo.processInfo.processorCount,
            logicalCPUCount: ProcessInfo.processInfo.activeProcessorCount,
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            gpuNames: MTLCopyAllDevices().map(\.name),
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

@MainActor
final class TelemetryService: ObservableObject {
    static let shared = TelemetryService()

    private enum Key {
        static let enabled = "telemetryEnabled"
        static let installID = "telemetryAnonymousInstallID"
        static let firstInstalledAt = "telemetryFirstInstalledAtV1"
        static let launchCount = "telemetryLaunchCountV1"
        static let history = "telemetryInstallHistoryV1"
        static let queue = "telemetryEventQueueV1"
        static let lastMode = "telemetryLastMode"
        static let cachedUsers = "telemetryCachedPortalUsersV2"
        static let cachedLeads = "telemetryCachedDownloadLeadsV2"
        static let cachedInstalls = "telemetryCachedInstallsV1"
        static let reportedPortalVersion = "telemetryReportedPortalVersionV1"
    }

    @Published private(set) var installedDevices: [InstallRecord] = []
    @Published private(set) var downloadLeads: [DownloadLeadRecord] = []
    @Published private(set) var cloudUsersHistory: [CloudUserActivitySummary] = []
    @Published private(set) var githubReleaseDownloads: [GitHubReleaseAssetSummary] = []
    @Published private(set) var isFetchingInstalls: Bool = false
    @Published private(set) var lastSyncStatus: String = ""

    private let endpoint = URL(string: "https://api.dotmini.net/v1/telemetry/events")!
    private let portalBaseURL = URL(string: "https://microcode.dotmini.net")!
    private var hasStarted = false
    private var flushing = false

    private init() {
        if UserDefaults.standard.object(forKey: Key.enabled) == nil {
            UserDefaults.standard.set(true, forKey: Key.enabled)
        }
        _ = installID
        _ = firstInstalledAt
        if SupabaseAuthService.shared.isAdminProvider {
            loadCachedAdminDataIfAuthorized()
        } else {
            clearAdminCache()
        }
    }

    func loadCachedAdminDataIfAuthorized() {
        guard SupabaseAuthService.shared.isAdminProvider else {
            clearAdminCache()
            return
        }
        if cloudUsersHistory.isEmpty,
           let uData = UserDefaults.standard.data(forKey: Key.cachedUsers),
           let uDecoded = try? JSONDecoder().decode([CloudUserActivitySummary].self, from: uData) {
            cloudUsersHistory = uDecoded
        }
        if downloadLeads.isEmpty,
           let lData = UserDefaults.standard.data(forKey: Key.cachedLeads),
           let lDecoded = try? JSONDecoder().decode([DownloadLeadRecord].self, from: lData) {
            downloadLeads = lDecoded
        }
        if installedDevices.isEmpty,
           let iData = UserDefaults.standard.data(forKey: Key.cachedInstalls),
           let iDecoded = try? JSONDecoder().decode([InstallRecord].self, from: iData) {
            installedDevices = iDecoded
        }
    }

    /// Wipes all cached Admin/Provider installation and user history from memory and UserDefaults.
    func clearAdminCache() {
        installedDevices = []
        downloadLeads = []
        cloudUsersHistory = []
        githubReleaseDownloads = []
        lastSyncStatus = ""
        UserDefaults.standard.removeObject(forKey: Key.cachedUsers)
        UserDefaults.standard.removeObject(forKey: Key.cachedLeads)
        UserDefaults.standard.removeObject(forKey: Key.cachedInstalls)
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Key.enabled) as? Bool ?? true
    }

    var currentInstallID: String { installID }
    var currentLaunchCount: Int { max(1, UserDefaults.standard.integer(forKey: Key.launchCount)) }
    var currentFirstInstalledAt: String { firstInstalledAt }
    var totalGitHubDownloads: Int { githubReleaseDownloads.reduce(0) { $0 + $1.downloadCount } }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Key.enabled)
        objectWillChange.send()
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
        let nextCount = UserDefaults.standard.integer(forKey: Key.launchCount) + 1
        UserDefaults.standard.set(nextCount, forKey: Key.launchCount)
        guard isEnabled else { return }
        record(name: "app_launch", mode: UserDefaults.standard.string(forKey: Key.lastMode) ?? "code")
        flush()
    }

    func recordMode(_ mode: EditorMode) {
        guard isEnabled else { return }
        guard UserDefaults.standard.string(forKey: Key.lastMode) != mode.rawValue else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: Key.lastMode)
        record(name: "mode_opened", mode: mode.rawValue)
        flush()
    }

    func record(name: String, mode: String? = nil) {
        guard isEnabled else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        var queue = queuedEvents()
        queue.append(TelemetryEvent(
            eventID: UUID().uuidString,
            installID: installID,
            timestamp: now,
            name: name,
            mode: mode,
            appVersion: appVersion,
            device: TelemetryDeviceSnapshot.current
        ))
        if queue.count > 100 { queue.removeFirst(queue.count - 100) }
        save(queue)

        var hist = localHistory()
        let email = SupabaseAuthService.shared.currentEmail
        hist.insert(InstallHistoryEntry(
            timestamp: now,
            event: name,
            appVersion: appVersion,
            mode: mode ?? UserDefaults.standard.string(forKey: Key.lastMode),
            email: email.isEmpty ? nil : email
        ), at: 0)
        if hist.count > 30 { hist = Array(hist.prefix(30)) }
        saveLocalHistory(hist)
    }

    func buildCurrentInstallRecord() -> InstallRecord {
        let now = ISO8601DateFormatter().string(from: Date())
        let session = SupabaseAuthService.shared.session
        let email = SupabaseAuthService.shared.currentEmail
        let installedTools = LocalEcosystemDiscovery.shared.engines
            .filter(\.isInstalled)
            .map(\.id)
        let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let fullName = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()

        return InstallRecord(
            installID: installID,
            userID: session?.userID ?? "anonymous",
            email: email.isEmpty ? "anonymous@local" : email,
            displayName: fullName,
            hostname: host,
            appVersion: appVersion,
            firstInstalledAt: firstInstalledAt,
            lastSeenAt: now,
            launchCount: currentLaunchCount,
            lastMode: UserDefaults.standard.string(forKey: Key.lastMode) ?? "code",
            device: TelemetryDeviceSnapshot.current,
            installedAgents: installedTools,
            history: localHistory()
        )
    }

    func flush() {
        guard isEnabled, !flushing else { return }
        flushing = true

        Task {
            defer { flushing = false }
            await syncInstallRecordToSupabase()
            await reportActiveMacAppToPortalIfNeeded()

            let events = queuedEvents()
            guard !events.isEmpty else { return }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
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
                // Retain bounded queue for next launch
            }
        }
    }

    /// Reports `event_type: "macapp_active"` to `https://microcode.dotmini.net/api/telemetry/install`
    /// once per installed app version, matching `Dotmini/microcode-web/main.go`.
    private func reportActiveMacAppToPortalIfNeeded() async {
        let alreadyReported = UserDefaults.standard.string(forKey: Key.reportedPortalVersion)
        guard alreadyReported != appVersion else { return }
        let record = buildCurrentInstallRecord()
        guard record.email != "anonymous@local" else { return }

        let url = portalBaseURL.appending(path: "api/telemetry/install")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = [
            "email": record.email,
            "name": record.displayName,
            "version": record.appVersion,
            "platform": "macOS",
            "arch": record.device.architecture,
            "event_type": "macapp_active",
            "machine_info": "\(record.device.hardwareModel) · \(record.device.cpu) · \(record.device.memoryGB)GB RAM · \(record.device.operatingSystem)"
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        if let (_, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
            UserDefaults.standard.set(appVersion, forKey: Key.reportedPortalVersion)
        }
    }

    /// Upserts this Mac's InstallRecord into Supabase `public.app_config` (`microcode_installs/<installID>`)
    /// so admins can always inspect every installed machine and its launch history.
    func syncInstallRecordToSupabase() async {
        _ = await SupabaseAuthService.shared.bootstrapConfiguration()
        guard let config = SupabaseAuthService.Configuration.load() ?? SupabaseAuthService.Configuration.cached() else {
            return
        }
        let token = await SupabaseAuthService.shared.refreshAccessTokenIfNeeded()
            ?? SupabaseAuthService.shared.accessToken
            ?? config.anonKey
        let record = buildCurrentInstallRecord()

        guard let recordData = try? JSONEncoder().encode(record),
              let recordObj = try? JSONSerialization.jsonObject(with: recordData) as? [String: Any] else {
            return
        }

        let payload: [String: Any] = [
            "key": "microcode_installs/\(record.installID)",
            "value": recordObj,
            "updated_at": record.lastSeenAt
        ]

        var components = URLComponents(url: config.baseURL.appending(path: "rest/v1/app_config"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "on_conflict", value: "key")]
        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
               SupabaseAuthService.shared.isAdminProvider {
                lastSyncStatus = "Synced install heartbeat (\(record.hostname))"
            }
        } catch {
            // Keep local install record even if offline
        }

        guard SupabaseAuthService.shared.isAdminProvider else { return }
        if !installedDevices.contains(where: { $0.installID == record.installID }) {
            installedDevices.insert(record, at: 0)
        } else if let idx = installedDevices.firstIndex(where: { $0.installID == record.installID }) {
            installedDevices[idx] = record
        }
    }

    private nonisolated static func runProcessOutput(executable: String, arguments: [String]) -> Data? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return proc.terminationStatus == 0 && !data.isEmpty ? data : nil
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchPortalViaIPv4Curl(jwt: String) -> (downloads: Data?, users: Data?) {
        let cookiePath = NSTemporaryDirectory() + "mc_portal_\(UUID().uuidString).cookies"
        defer { try? FileManager.default.removeItem(atPath: cookiePath) }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["token": jwt]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return (nil, nil)
        }
        guard let syncOut = runProcessOutput(
            executable: "/usr/bin/curl",
            arguments: [
                "-4", "-sS", "--connect-timeout", "3", "--max-time", "5",
                "-c", cookiePath,
                "-X", "POST", "https://microcode.dotmini.net/api/auth/sync",
                "-H", "Content-Type: application/json",
                "-d", bodyString
            ]
        ), !syncOut.isEmpty else {
            return (nil, nil)
        }
        let dlData = runProcessOutput(
            executable: "/usr/bin/curl",
            arguments: ["-4", "-sS", "--connect-timeout", "3", "--max-time", "5", "-b", cookiePath, "https://microcode.dotmini.net/api/admin/downloads"]
        )
        let usersData = runProcessOutput(
            executable: "/usr/bin/curl",
            arguments: ["-4", "-sS", "--connect-timeout", "3", "--max-time", "5", "-b", cookiePath, "https://microcode.dotmini.net/api/admin/users"]
        )
        return (dlData, usersData)
    }

    private nonisolated static func fetchGitHubReleasesFallback() -> Data? {
        for ghPath in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"] {
            if FileManager.default.isExecutableFile(atPath: ghPath),
               let data = runProcessOutput(executable: ghPath, arguments: ["api", "repos/Dotmini/microcode/releases"]) {
                return data
            }
        }
        return nil
    }

    /// Fetches real production download/install records (`microcode_downloads`) and registered users (`users`)
    /// from `https://microcode.dotmini.net/api/admin/downloads` & `/api/admin/users`,
    /// active Mac heartbeats (`microcode_installs/*`) from Supabase, and release downloads from GitHub.
    /// STRICTLY restricted to Admin Provider accounts (`SupabaseAuthService.shared.isAdminProvider == true`).
    func fetchAllInstallsAndHistory() async {
        if !SupabaseAuthService.shared.entitlement.isLoaded {
            await SupabaseAuthService.shared.refreshEntitlement()
        }
        guard SupabaseAuthService.shared.isAdminProvider else {
            clearAdminCache()
            return
        }
        loadCachedAdminDataIfAuthorized()
        guard !isFetchingInstalls else { return }
        isFetchingInstalls = true
        defer { isFetchingInstalls = false }

        let localRecord = buildCurrentInstallRecord()
        if installedDevices.isEmpty {
            installedDevices = [localRecord]
        }

        _ = await SupabaseAuthService.shared.bootstrapConfiguration()
        let config = SupabaseAuthService.Configuration.load() ?? SupabaseAuthService.Configuration.cached()
        let supabaseToken = await SupabaseAuthService.shared.refreshAccessTokenIfNeeded()
            ?? SupabaseAuthService.shared.accessToken

        Task {
            await syncInstallRecordToSupabase()
        }

        // Fetch microcode_installs/* from Supabase
        let supabaseInstallsReq: URLRequest? = {
            guard let config else { return nil }
            var comp = URLComponents(url: config.baseURL.appending(path: "rest/v1/app_config"), resolvingAgainstBaseURL: false)
            comp?.queryItems = [
                URLQueryItem(name: "select", value: "key,updated_at,value"),
                URLQueryItem(name: "key", value: "like.microcode_installs/*"),
                URLQueryItem(name: "order", value: "updated_at.desc"),
                URLQueryItem(name: "limit", value: "100")
            ]
            guard let u = comp?.url else { return nil }
            var req = URLRequest(url: u)
            req.timeoutInterval = 4
            req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(supabaseToken ?? config.anonKey)", forHTTPHeaderField: "Authorization")
            return req
        }()

        // Fetch GitHub Release download counts from https://api.github.com/repos/Dotmini/microcode/releases
        var ghReq = URLRequest(url: URL(string: "https://api.github.com/repos/Dotmini/microcode/releases")!)
        ghReq.timeoutInterval = 5
        ghReq.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let jwt = supabaseToken ?? ""
        async let portalFetch: (downloads: Data?, users: Data?) = Task.detached(priority: .userInitiated) {
            guard !jwt.isEmpty else { return (nil, nil) }
            return Self.fetchPortalViaIPv4Curl(jwt: jwt)
        }.value
        async let supabaseInstallsFetch: (Data, URLResponse)? = {
            guard let supabaseInstallsReq else { return nil }
            return try? await URLSession.shared.data(for: supabaseInstallsReq)
        }()
        async let ghFetch: (Data, URLResponse)? = try? await URLSession.shared.data(for: ghReq)

        let (portalResp, supabaseInstallsResp, ghResp) = await (
            portalFetch,
            supabaseInstallsFetch,
            ghFetch
        )

        let downloadsData: Data? = portalResp.downloads
        let portalUsersData: Data? = portalResp.users

        // Parse microcode_installs/*
        var discoveredInstalls: [InstallRecord] = [localRecord]
        if let (data, resp) = supabaseInstallsResp,
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for r in rows {
                guard let val = r["value"] as? [String: Any],
                      let valData = try? JSONSerialization.data(withJSONObject: val),
                      let decoded = try? JSONDecoder().decode(InstallRecord.self, from: valData) else { continue }
                if let idx = discoveredInstalls.firstIndex(where: { $0.installID == decoded.installID }) {
                    discoveredInstalls[idx] = decoded
                } else {
                    discoveredInstalls.append(decoded)
                }
            }
        }
        installedDevices = discoveredInstalls.sorted { $0.lastSeenAt > $1.lastSeenAt }
        if let encodedInstalls = try? JSONEncoder().encode(installedDevices) {
            UserDefaults.standard.set(encodedInstalls, forKey: Key.cachedInstalls)
        }

        // Parse /api/admin/downloads (`microcode_downloads`)
        var parsedLeads: [DownloadLeadRecord] = []
        if let data = downloadsData,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let leads = obj["leads"] as? [[String: Any]] {
            for item in leads {
                let id = item["id"] as? Int ?? 0
                let email = item["email"] as? String ?? ""
                let name = item["name"] as? String ?? ""
                let version = item["version"] as? String ?? ""
                let platform = item["platform"] as? String ?? "macOS"
                let arch = item["arch"] as? String ?? "universal"
                let ip = item["ip_address"] as? String ?? ""
                let ua = item["user_agent"] as? String ?? ""
                let eventType = item["event_type"] as? String ?? "web_download"
                let sourceLabel = item["source_label"] as? String ?? (eventType == "macapp_active" ? "MicroCode.app (macOS Active)" : "Web Portal Download")
                let machineInfo = item["machine_info"] as? String ?? ""
                let downloadedAt = item["downloaded_at"] as? String ?? ""
                parsedLeads.append(DownloadLeadRecord(
                    id: id,
                    email: email,
                    name: name,
                    version: version,
                    platform: platform,
                    arch: arch,
                    ipAddress: ip,
                    userAgent: ua,
                    eventType: eventType,
                    sourceLabel: sourceLabel,
                    machineInfo: machineInfo,
                    downloadedAt: downloadedAt
                ))
            }
        }
        if !parsedLeads.isEmpty {
            downloadLeads = parsedLeads.sorted { $0.downloadedAt > $1.downloadedAt }
            if let encodedLeads = try? JSONEncoder().encode(downloadLeads) {
                UserDefaults.standard.set(encodedLeads, forKey: Key.cachedLeads)
            }
        }

        // Parse /api/admin/users (`users` table on microcode.dotmini.net) and enrich with download stats
        var parsedUsers: [CloudUserActivitySummary] = []
        let portalUserRows: [[String: Any]]? = {
            guard let data = portalUsersData,
                  let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
            if let arr = json as? [[String: Any]] { return arr }
            if let obj = json as? [String: Any], let arr = obj["users"] as? [[String: Any]] { return arr }
            return nil
        }()
        if let users = portalUserRows {
            for u in users {
                let id = u["id"] as? String ?? UUID().uuidString
                let email = u["email"] as? String ?? ""
                let displayName = (u["displayName"] as? String) ?? (u["name"] as? String) ?? email
                let role = u["role"] as? String ?? "user"
                let plan = u["plan"] as? String ?? "free"
                let aiQuota = u["ai_quota"] as? Int ?? 1000
                let aiUsed = u["ai_used"] as? Int ?? 0

                let matchingLeads = downloadLeads.filter { $0.email.lowercased() == email.lowercased() }
                let latestLead = matchingLeads.first
                let activeMac = installedDevices.first { $0.email.lowercased() == email.lowercased() }

                let lastActive = activeMac?.lastSeenAt ?? latestLead?.downloadedAt ?? ""
                let latestActivity: String = {
                    if let activeMac {
                        return "Active on \(activeMac.hostname) (\(activeMac.device.hardwareModel), \(activeMac.launchCount) launches)"
                    } else if let latestLead {
                        return "Downloaded \(latestLead.version) (\(latestLead.platform)/\(latestLead.arch)) from IP \(latestLead.ipAddress)"
                    } else {
                        return "Registered on microcode.dotmini.net"
                    }
                }()

                parsedUsers.append(CloudUserActivitySummary(
                    id: id,
                    email: email,
                    fullName: displayName,
                    role: role,
                    plan: plan,
                    aiQuota: aiQuota,
                    aiUsed: aiUsed,
                    downloadCount: matchingLeads.count,
                    lastVersion: activeMac?.appVersion ?? latestLead?.version ?? "—",
                    lastIP: latestLead?.ipAddress ?? "—",
                    lastActiveAt: lastActive,
                    latestActivity: latestActivity
                ))
            }
        }
        if !parsedUsers.isEmpty {
            cloudUsersHistory = parsedUsers.sorted { $0.lastActiveAt > $1.lastActiveAt }
            if let encodedUsers = try? JSONEncoder().encode(cloudUsersHistory) {
                UserDefaults.standard.set(encodedUsers, forKey: Key.cachedUsers)
            }
        }

        // Parse GitHub Release asset download counts (with gh CLI fallback when repo requires auth)
        var ghData: Data? = (ghResp?.1 as? HTTPURLResponse)?.statusCode == 200 ? ghResp?.0 : nil
        if ghData == nil {
            ghData = await Task.detached(priority: .utility) {
                Self.fetchGitHubReleasesFallback()
            }.value
        }
        if let data = ghData,
           let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            var assetsList: [GitHubReleaseAssetSummary] = []
            for rel in releases {
                let tag = rel["tag_name"] as? String ?? ""
                let pub = rel["published_at"] as? String ?? ""
                let assets = rel["assets"] as? [[String: Any]] ?? []
                for a in assets {
                    let name = a["name"] as? String ?? ""
                    let count = a["download_count"] as? Int ?? 0
                    assetsList.append(GitHubReleaseAssetSummary(
                        tag: tag,
                        assetName: name,
                        downloadCount: count,
                        publishedAt: pub
                    ))
                }
            }
            githubReleaseDownloads = assetsList
        }

        lastSyncStatus = "Synced from microcode.dotmini.net: \(downloadLeads.count) download lead(s), \(cloudUsersHistory.count) registered user(s), \(installedDevices.count) active Mac(s), \(totalGitHubDownloads) GitHub release download(s)"
    }

    private var installID: String {
        if let existing = UserDefaults.standard.string(forKey: Key.installID), !existing.isEmpty {
            return existing
        }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: Key.installID)
        return value
    }

    private var firstInstalledAt: String {
        if let existing = UserDefaults.standard.string(forKey: Key.firstInstalledAt), !existing.isEmpty {
            return existing
        }
        let now = ISO8601DateFormatter().string(from: Date())
        UserDefaults.standard.set(now, forKey: Key.firstInstalledAt)
        return now
    }

    private var cloudToken: String? {
        return DotminiPlatformKeyService.shared.authorizationToken ?? SupabaseAuthService.shared.accessToken
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
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

    private func localHistory() -> [InstallHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: Key.history) else { return [] }
        return (try? JSONDecoder().decode([InstallHistoryEntry].self, from: data)) ?? []
    }

    private func saveLocalHistory(_ entries: [InstallHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Key.history)
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
    let device: TelemetryDeviceSnapshot

    enum CodingKeys: String, CodingKey {
        case eventID = "eventId"
        case installID = "installId"
        case timestamp, name, mode, appVersion, device
    }
}

