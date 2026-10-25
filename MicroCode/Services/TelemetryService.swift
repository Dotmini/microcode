//
//  TelemetryService.swift
//  MicroCode
//
//  Privacy-preserving, opt-in product telemetry.  No source code, prompts,
//  project names, file paths, serial number, or hardware UUID
//  is collected by this service.
//

import Foundation
import AppKit
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
    var feature: String? = nil
    var aiProvider: String? = nil
    var aiModel: String? = nil
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
    var activeFeature: String
    var featuresUsed: [String]
    var aiProvider: String
    var aiModel: String
    var aiRequests: Int
    var aiTokens: Int
    var device: TelemetryDeviceSnapshot
    var installedAgents: [String]
    var history: [InstallHistoryEntry]

    init(
        installID: String,
        userID: String,
        email: String,
        displayName: String,
        hostname: String,
        appVersion: String,
        firstInstalledAt: String,
        lastSeenAt: String,
        launchCount: Int,
        lastMode: String,
        activeFeature: String = "",
        featuresUsed: [String] = [],
        aiProvider: String = "",
        aiModel: String = "",
        aiRequests: Int = 0,
        aiTokens: Int = 0,
        device: TelemetryDeviceSnapshot,
        installedAgents: [String],
        history: [InstallHistoryEntry]
    ) {
        self.installID = installID
        self.userID = userID
        self.email = email
        self.displayName = displayName
        self.hostname = hostname
        self.appVersion = appVersion
        self.firstInstalledAt = firstInstalledAt
        self.lastSeenAt = lastSeenAt
        self.launchCount = launchCount
        self.lastMode = lastMode
        self.activeFeature = activeFeature
        self.featuresUsed = featuresUsed
        self.aiProvider = aiProvider
        self.aiModel = aiModel
        self.aiRequests = aiRequests
        self.aiTokens = aiTokens
        self.device = device
        self.installedAgents = installedAgents
        self.history = history
    }

    enum CodingKeys: String, CodingKey {
        case installID, userID, email, displayName, hostname, appVersion
        case firstInstalledAt, lastSeenAt, launchCount, lastMode
        case activeFeature, featuresUsed, aiProvider, aiModel, aiRequests, aiTokens
        case device, installedAgents, history
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        installID = try c.decode(String.self, forKey: .installID)
        userID = (try? c.decode(String.self, forKey: .userID)) ?? "anonymous"
        email = (try? c.decode(String.self, forKey: .email)) ?? ""
        displayName = (try? c.decode(String.self, forKey: .displayName)) ?? ""
        hostname = (try? c.decode(String.self, forKey: .hostname)) ?? ""
        appVersion = (try? c.decode(String.self, forKey: .appVersion)) ?? ""
        firstInstalledAt = (try? c.decode(String.self, forKey: .firstInstalledAt)) ?? ""
        lastSeenAt = (try? c.decode(String.self, forKey: .lastSeenAt)) ?? ""
        launchCount = (try? c.decode(Int.self, forKey: .launchCount)) ?? 1
        lastMode = (try? c.decode(String.self, forKey: .lastMode)) ?? "code"
        activeFeature = (try? c.decode(String.self, forKey: .activeFeature)) ?? ""
        featuresUsed = (try? c.decode([String].self, forKey: .featuresUsed)) ?? []
        aiProvider = (try? c.decode(String.self, forKey: .aiProvider)) ?? ""
        aiModel = (try? c.decode(String.self, forKey: .aiModel)) ?? ""
        aiRequests = (try? c.decode(Int.self, forKey: .aiRequests)) ?? 0
        aiTokens = (try? c.decode(Int.self, forKey: .aiTokens)) ?? 0
        device = (try? c.decode(TelemetryDeviceSnapshot.self, forKey: .device)) ?? .current
        installedAgents = (try? c.decode([String].self, forKey: .installedAgents)) ?? []
        history = (try? c.decode([InstallHistoryEntry].self, forKey: .history)) ?? []
    }
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
    let installID: String
    let hostname: String
    let activeFeature: String
    let featuresUsed: [String]
    let aiProvider: String
    let aiModel: String
    let aiRequests: Int
    let aiTokens: Int
    let launchCount: Int
    let installedAgents: [String]
    let downloadedAt: String

    init(
        id: Int,
        email: String,
        name: String,
        version: String,
        platform: String,
        arch: String,
        ipAddress: String,
        userAgent: String,
        eventType: String,
        sourceLabel: String,
        machineInfo: String,
        installID: String = "",
        hostname: String = "",
        activeFeature: String = "",
        featuresUsed: [String] = [],
        aiProvider: String = "",
        aiModel: String = "",
        aiRequests: Int = 0,
        aiTokens: Int = 0,
        launchCount: Int = 1,
        installedAgents: [String] = [],
        downloadedAt: String
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.version = version
        self.platform = platform
        self.arch = arch
        self.ipAddress = ipAddress
        self.userAgent = userAgent
        self.eventType = eventType
        self.sourceLabel = sourceLabel
        self.machineInfo = machineInfo
        self.installID = installID
        self.hostname = hostname
        self.activeFeature = activeFeature
        self.featuresUsed = featuresUsed
        self.aiProvider = aiProvider
        self.aiModel = aiModel
        self.aiRequests = aiRequests
        self.aiTokens = aiTokens
        self.launchCount = launchCount
        self.installedAgents = installedAgents
        self.downloadedAt = downloadedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, email, name, version, platform, arch, ipAddress, userAgent
        case eventType, sourceLabel, machineInfo, installID, hostname
        case activeFeature, featuresUsed, aiProvider, aiModel, aiRequests, aiTokens
        case launchCount, installedAgents, downloadedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        email = (try? c.decode(String.self, forKey: .email)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        version = (try? c.decode(String.self, forKey: .version)) ?? ""
        platform = (try? c.decode(String.self, forKey: .platform)) ?? "macOS"
        arch = (try? c.decode(String.self, forKey: .arch)) ?? "universal"
        ipAddress = (try? c.decode(String.self, forKey: .ipAddress)) ?? ""
        userAgent = (try? c.decode(String.self, forKey: .userAgent)) ?? ""
        eventType = (try? c.decode(String.self, forKey: .eventType)) ?? "web_download"
        sourceLabel = (try? c.decode(String.self, forKey: .sourceLabel)) ?? ""
        machineInfo = (try? c.decode(String.self, forKey: .machineInfo)) ?? ""
        installID = (try? c.decode(String.self, forKey: .installID)) ?? ""
        hostname = (try? c.decode(String.self, forKey: .hostname)) ?? ""
        activeFeature = (try? c.decode(String.self, forKey: .activeFeature)) ?? ""
        featuresUsed = (try? c.decode([String].self, forKey: .featuresUsed)) ?? []
        aiProvider = (try? c.decode(String.self, forKey: .aiProvider)) ?? ""
        aiModel = (try? c.decode(String.self, forKey: .aiModel)) ?? ""
        aiRequests = (try? c.decode(Int.self, forKey: .aiRequests)) ?? 0
        aiTokens = (try? c.decode(Int.self, forKey: .aiTokens)) ?? 0
        launchCount = (try? c.decode(Int.self, forKey: .launchCount)) ?? 1
        installedAgents = (try? c.decode([String].self, forKey: .installedAgents)) ?? []
        downloadedAt = (try? c.decode(String.self, forKey: .downloadedAt)) ?? ""
    }
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
        static let activeFeature = "telemetryActiveFeatureV1"
        static let featuresUsed = "telemetryFeaturesUsedV1"
        static let lastAIProvider = "telemetryLastAIProviderV1"
        static let lastAIModel = "telemetryLastAIModelV1"
        static let totalAIRequests = "telemetryTotalAIRequestsV1"
        static let totalAITokens = "telemetryTotalAITokensV1"
        static let cachedGitEmail = "telemetryCachedGitEmailV1"
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
    private var portalReportTask: Task<Void, Never>?
    private var heartbeatTimer: Timer?
    private var lastReportedPortalEventType: String = "macapp_active"

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
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
            return
        }
        record(name: "telemetry_consent_granted")
        startHeartbeatTimerIfNeeded()
        flush()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let nextCount = UserDefaults.standard.integer(forKey: Key.launchCount) + 1
        UserDefaults.standard.set(nextCount, forKey: Key.launchCount)
        warmGitEmailCacheIfNeeded()
        guard isEnabled else { return }

        let currentMode = UserDefaults.standard.string(forKey: Key.lastMode) ?? "code"
        let modeFeature = Self.displayFeatureName(forModeRaw: currentMode)
        markFeatureUsed(modeFeature)
        lastReportedPortalEventType = "macapp_launch"
        record(name: "app_launch", mode: currentMode, feature: modeFeature)
        startHeartbeatTimerIfNeeded()
        flush(immediatePortalSync: true)
    }

    private func startHeartbeatTimerIfNeeded() {
        heartbeatTimer?.invalidate()
        guard isEnabled else { return }
        // Send a live activity heartbeat every 2 minutes while the user is actively using MicroCode
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isEnabled else { return }
                self.lastReportedPortalEventType = "macapp_heartbeat"
                await self.syncInstallRecordToSupabase()
                await self.reportActiveMacAppToPortal(eventType: "macapp_heartbeat")
            }
        }
    }

    func recordMode(_ mode: EditorMode) {
        guard isEnabled else { return }
        let featureLabel = mode == .notebook ? "Notebook (Cell Mode)" : mode.displayName
        markFeatureUsed(featureLabel)
        let previousMode = UserDefaults.standard.string(forKey: Key.lastMode)
        UserDefaults.standard.set(mode.rawValue, forKey: Key.lastMode)
        lastReportedPortalEventType = "macapp_mode_change"
        if previousMode != mode.rawValue {
            record(name: "mode_opened", mode: mode.rawValue, feature: featureLabel)
        }
        scheduleDebouncedPortalSync(eventType: "macapp_mode_change")
        flush()
    }

    /// Records a specific feature or function used inside MicroCode (e.g. "Run Code (swift)", "Git Source Control", "Smart Refactor", "AI Agent").
    func recordFeature(_ feature: String) {
        guard isEnabled else { return }
        let trimmed = feature.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let prevFeature = UserDefaults.standard.string(forKey: Key.activeFeature)
        markFeatureUsed(trimmed)
        lastReportedPortalEventType = "macapp_feature_used"
        if prevFeature != trimmed {
            record(
                name: "feature_used",
                mode: UserDefaults.standard.string(forKey: Key.lastMode) ?? "code",
                feature: trimmed
            )
        }
        scheduleDebouncedPortalSync(eventType: "macapp_feature_used")
        flush()
    }

    /// Records when the user switches AI provider or AI model in the UI selector.
    func recordAIConfiguration(provider: String, model: String) {
        guard isEnabled else { return }
        let resolved = resolveCurrentAIState(overrideProvider: provider, overrideModel: model)
        let prevProv = UserDefaults.standard.string(forKey: Key.lastAIProvider) ?? ""
        let prevModel = UserDefaults.standard.string(forKey: Key.lastAIModel) ?? ""
        guard resolved.provider != prevProv || resolved.model != prevModel else { return }
        UserDefaults.standard.set(resolved.provider, forKey: Key.lastAIProvider)
        UserDefaults.standard.set(resolved.model, forKey: Key.lastAIModel)
        lastReportedPortalEventType = "macapp_ai_used"
        scheduleDebouncedPortalSync(eventType: "macapp_ai_used")
    }

    /// Records an active AI request (Agent Chat, ACP CLI Agent, Inline Edit, Refactor, Autocomplete, etc.) along with provider, model, and tokens.
    func recordAIUsage(provider: String, model: String, taskLabel: String = "AI Agent", tokens: Int = 0) {
        guard isEnabled else { return }
        let resolved = resolveCurrentAIState(overrideProvider: provider, overrideModel: model)
        UserDefaults.standard.set(resolved.provider, forKey: Key.lastAIProvider)
        UserDefaults.standard.set(resolved.model, forKey: Key.lastAIModel)

        let nextRequests = UserDefaults.standard.integer(forKey: Key.totalAIRequests) + 1
        UserDefaults.standard.set(nextRequests, forKey: Key.totalAIRequests)
        if tokens > 0 {
            let nextTokens = UserDefaults.standard.integer(forKey: Key.totalAITokens) + tokens
            UserDefaults.standard.set(nextTokens, forKey: Key.totalAITokens)
        }

        let cleanTask = taskLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let featureLabel = cleanTask.isEmpty ? "AI Agent" : cleanTask
        markFeatureUsed(featureLabel)
        lastReportedPortalEventType = "macapp_ai_used"
        record(
            name: "ai_request",
            mode: UserDefaults.standard.string(forKey: Key.lastMode) ?? "code",
            feature: featureLabel,
            aiProvider: resolved.provider,
            aiModel: resolved.model
        )
        scheduleDebouncedPortalSync(eventType: "macapp_ai_used")
        flush()
    }

    func record(
        name: String,
        mode: String? = nil,
        feature: String? = nil,
        aiProvider: String? = nil,
        aiModel: String? = nil
    ) {
        guard isEnabled else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let aiState = resolveCurrentAIState(overrideProvider: aiProvider, overrideModel: aiModel)
        let activeFeat = feature ?? currentActiveFeature
        let effectiveEmail = resolvedUserEmail
        let fullName = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
        let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

        var queue = queuedEvents()
        queue.append(TelemetryEvent(
            eventID: UUID().uuidString,
            installID: installID,
            timestamp: now,
            name: name,
            mode: mode ?? (UserDefaults.standard.string(forKey: Key.lastMode) ?? "code"),
            feature: activeFeat,
            featuresUsed: currentFeaturesUsed,
            aiProvider: aiState.provider,
            aiModel: aiState.model,
            aiRequests: currentAIRequests,
            aiTokens: currentAITokens,
            email: effectiveEmail,
            displayName: fullName,
            hostname: host,
            launchCount: currentLaunchCount,
            installedAgents: LocalEcosystemDiscovery.shared.engines.filter(\.isInstalled).map(\.id),
            appVersion: appVersion,
            device: TelemetryDeviceSnapshot.current
        ))
        if queue.count > 100 { queue.removeFirst(queue.count - 100) }
        save(queue)

        var hist = localHistory()
        hist.insert(InstallHistoryEntry(
            timestamp: now,
            event: name,
            appVersion: appVersion,
            mode: mode ?? UserDefaults.standard.string(forKey: Key.lastMode),
            email: effectiveEmail.isEmpty ? nil : effectiveEmail,
            feature: activeFeat,
            aiProvider: aiState.provider,
            aiModel: aiState.model
        ), at: 0)
        if hist.count > 40 { hist = Array(hist.prefix(40)) }
        saveLocalHistory(hist)
    }

    /// Resolves the active AI Execution Mode + Provider and Model currently selected or in use.
    func resolveCurrentAIState(overrideProvider: String? = nil, overrideModel: String? = nil) -> (provider: String, model: String) {
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "acp"
        let rawAppProvider = AppState.shared?.aiProvider ?? UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"
        let rawAppModel = AppState.shared?.aiModel ?? UserDefaults.standard.string(forKey: "aiModel") ?? "gemini-2.5-flash"

        let chosenModel: String = {
            if let m = overrideModel?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
                return m
            }
            if keyMode == "acp" {
                if let activeId = ACPHostService.shared.activeAgentId,
                   let session = ACPHostService.shared.sessions[activeId],
                   let sModel = session.model, !sModel.isEmpty {
                    return sModel
                }
                if let savedModel = UserDefaults.standard.string(forKey: Key.lastAIModel), !savedModel.isEmpty {
                    return savedModel
                }
                if let activeId = ACPHostService.shared.activeAgentId,
                   let cfg = ACPHostService.shared.registeredConfigs.first(where: { $0.id == activeId }) {
                    switch cfg.type {
                    case .claudeCode: return "claude-sonnet-4-6"
                    case .agy: return "gemini-3.8-pro"
                    case .codexEngine: return "gpt-5.4"
                    case .geminiCLI: return "gemini-2.5-pro"
                    case .cursorAgent: return "claude-sonnet-4-6"
                    case .githubCopilot: return "claude-sonnet-4.6"
                    case .goose: return "claude-sonnet-4-6"
                    case .cline: return "claude-sonnet-4-6"
                    case .qwenCode: return "qwen3-coder-plus"
                    case .aider: return "sonnet"
                    case .openCode: return rawAppModel
                    case .zedEngine: return "claude-sonnet-4-6"
                    default: return rawAppModel
                    }
                }
            }
            return rawAppModel
        }()

        let chosenProvider: String = {
            if let p = overrideProvider?.trimmingCharacters(in: .whitespacesAndNewlines),
               !p.isEmpty,
               p.contains("·") || p.lowercased().hasPrefix("acp") || p.lowercased().hasPrefix("subscription") {
                return p
            }
            if EnterpriseAIAuthService.shared.isEnterpriseActive {
                return "Enterprise · \(EnterpriseAIAuthService.shared.mode.title)"
            }
            switch keyMode {
            case "acp":
                if let activeId = ACPHostService.shared.activeAgentId,
                   let cfg = ACPHostService.shared.registeredConfigs.first(where: { $0.id == activeId }) {
                    return "ACP · \(cfg.type.displayName)"
                }
                if let firstDetected = ACPHostService.shared.detectedAgents.keys.first {
                    return "ACP · \(firstDetected.displayName)"
                }
                return "ACP · External Agent"
            case "subscription":
                let sub = SubscriptionAuthManager.shared.activeProvider
                return "Subscription · \(sub.rawValue.capitalized)"
            case "cloud":
                let prov = (overrideProvider?.isEmpty == false ? overrideProvider! : rawAppProvider)
                return "Dotmini Cloud · \(Self.prettyProviderName(prov))"
            case "local":
                let prov = (overrideProvider?.isEmpty == false ? overrideProvider! : rawAppProvider)
                return "Local LLM · \(Self.prettyProviderName(prov))"
            default:
                let prov = (overrideProvider?.isEmpty == false ? overrideProvider! : rawAppProvider)
                return "BYOK · \(Self.prettyProviderName(prov))"
            }
        }()

        return (chosenProvider, chosenModel)
    }

    private static func prettyProviderName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "gemini", "google": return "Google Gemini"
        case "anthropic", "claude": return "Anthropic Claude"
        case "openai", "gpt": return "OpenAI"
        case "deepseek": return "DeepSeek"
        case "qwen": return "Alibaba Qwen"
        case "grok", "xai": return "xAI Grok"
        case "glm", "zhipu": return "Zhipu GLM"
        case "omni", "dotmini": return "Dotmini Omni AI"
        case "ollama": return "Ollama"
        case "mlx": return "Apple MLX"
        case "lmstudio": return "LM Studio"
        default: return raw.capitalized
        }
    }

    private static func displayFeatureName(forModeRaw raw: String) -> String {
        if let mode = EditorMode(rawValue: raw) {
            return mode == .notebook ? "Notebook (Cell Mode)" : mode.displayName
        }
        switch raw.lowercased() {
        case "code": return "Code Editor"
        case "notebook": return "Notebook (Cell Mode)"
        case "playground": return "Playground"
        case "science": return "Science Mode"
        case "ai agent", "aiagent": return "AI Agent"
        case "apiclient": return "API Studio"
        default: return raw
        }
    }

    private func markFeatureUsed(_ feature: String) {
        let trimmed = feature.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: Key.activeFeature)
        var list = currentFeaturesUsed
        list.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        list.insert(trimmed, at: 0)
        if list.count > 20 {
            list = Array(list.prefix(20))
        }
        UserDefaults.standard.set(list, forKey: Key.featuresUsed)
    }

    var currentActiveFeature: String {
        if let saved = UserDefaults.standard.string(forKey: Key.activeFeature), !saved.isEmpty {
            return saved
        }
        let modeRaw = UserDefaults.standard.string(forKey: Key.lastMode) ?? "code"
        return Self.displayFeatureName(forModeRaw: modeRaw)
    }

    var currentFeaturesUsed: [String] {
        if let saved = UserDefaults.standard.stringArray(forKey: Key.featuresUsed), !saved.isEmpty {
            return saved
        }
        return [currentActiveFeature]
    }

    var currentAIRequests: Int {
        max(UserDefaults.standard.integer(forKey: Key.totalAIRequests), AIUsageTracker.shared.sessionRequests)
    }

    var currentAITokens: Int {
        max(UserDefaults.standard.integer(forKey: Key.totalAITokens), AIUsageTracker.shared.sessionTokens)
    }

    private var resolvedUserEmail: String {
        let supa = SupabaseAuthService.shared.currentEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !supa.isEmpty { return supa }
        if let persisted = UserDefaults.standard.string(forKey: "microcode_account_email")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !persisted.isEmpty {
            return persisted
        }
        if let gitEmail = UserDefaults.standard.string(forKey: Key.cachedGitEmail)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !gitEmail.isEmpty {
            return gitEmail
        }
        let user = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        let host = (Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "\(user.isEmpty ? "macuser" : user)@\(host.isEmpty ? "mac" : host).local"
    }

    private func warmGitEmailCacheIfNeeded() {
        if let cached = UserDefaults.standard.string(forKey: Key.cachedGitEmail), !cached.isEmpty {
            return
        }
        Task.detached(priority: .utility) {
            guard let data = Self.runProcessOutput(executable: "/usr/bin/git", arguments: ["config", "--global", "user.email"]),
                  let email = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  email.contains("@") else {
                return
            }
            UserDefaults.standard.set(email, forKey: Key.cachedGitEmail)
        }
    }

    func buildCurrentInstallRecord() -> InstallRecord {
        let now = ISO8601DateFormatter().string(from: Date())
        let session = SupabaseAuthService.shared.session
        let installedTools = LocalEcosystemDiscovery.shared.engines
            .filter(\.isInstalled)
            .map(\.id)
        let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let fullName = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
        let aiState = resolveCurrentAIState()

        return InstallRecord(
            installID: installID,
            userID: session?.userID ?? "anonymous",
            email: resolvedUserEmail,
            displayName: fullName,
            hostname: host,
            appVersion: appVersion,
            firstInstalledAt: firstInstalledAt,
            lastSeenAt: now,
            launchCount: currentLaunchCount,
            lastMode: UserDefaults.standard.string(forKey: Key.lastMode) ?? "code",
            activeFeature: currentActiveFeature,
            featuresUsed: currentFeaturesUsed,
            aiProvider: aiState.provider,
            aiModel: aiState.model,
            aiRequests: currentAIRequests,
            aiTokens: currentAITokens,
            device: TelemetryDeviceSnapshot.current,
            installedAgents: installedTools,
            history: localHistory()
        )
    }

    private func scheduleDebouncedPortalSync(eventType: String) {
        lastReportedPortalEventType = eventType
        portalReportTask?.cancel()
        portalReportTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await self.reportActiveMacAppToPortal(eventType: self.lastReportedPortalEventType)
        }
    }

    func flush(immediatePortalSync: Bool = false) {
        guard isEnabled, !flushing else { return }
        flushing = true

        Task {
            defer { flushing = false }
            await syncInstallRecordToSupabase()
            if immediatePortalSync {
                await reportActiveMacAppToPortal(eventType: lastReportedPortalEventType)
            }

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

    /// Reports live Mac telemetry (`macapp_launch`, `macapp_active`, `macapp_mode_change`, `macapp_feature_used`, `macapp_ai_used`, `macapp_heartbeat`)
    /// to `https://microcode.dotmini.net/api/telemetry/install`, matching `Dotmini/microcode-web/main.go`.
    private func reportActiveMacAppToPortal(eventType: String = "macapp_active") async {
        let record = buildCurrentInstallRecord()

        let url = portalBaseURL.appending(path: "api/telemetry/install")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "email": record.email,
            "name": record.displayName,
            "version": record.appVersion,
            "platform": "macOS",
            "arch": record.device.architecture,
            "event_type": eventType,
            "machine_info": "\(record.device.hardwareModel) · \(record.device.cpu) · \(record.device.memoryGB)GB RAM · \(record.device.operatingSystem)",
            "install_id": record.installID,
            "hostname": record.hostname,
            "active_feature": record.activeFeature,
            "features_used": record.featuresUsed,
            "ai_provider": record.aiProvider,
            "ai_model": record.aiModel,
            "ai_requests": record.aiRequests,
            "ai_tokens": record.aiTokens,
            "launch_count": record.launchCount,
            "installed_agents": record.installedAgents
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
            await reportActiveMacAppToPortal(eventType: lastReportedPortalEventType)
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
                let sourceLabel = item["source_label"] as? String ?? (eventType.hasPrefix("macapp_") ? "MicroCode.app (macOS Active)" : "Web Portal Download")
                let machineInfo = item["machine_info"] as? String ?? ""
                let leadInstallID = item["install_id"] as? String ?? ""
                let leadHostname = item["hostname"] as? String ?? ""
                let activeFeature = item["active_feature"] as? String ?? ""
                let featuresUsed = item["features_used"] as? [String] ?? []
                let aiProvider = item["ai_provider"] as? String ?? ""
                let aiModel = item["ai_model"] as? String ?? ""
                let aiRequests = item["ai_requests"] as? Int ?? 0
                let aiTokens = item["ai_tokens"] as? Int ?? 0
                let launchCount = item["launch_count"] as? Int ?? 1
                let installedAgents = item["installed_agents"] as? [String] ?? []
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
                    installID: leadInstallID,
                    hostname: leadHostname,
                    activeFeature: activeFeature,
                    featuresUsed: featuresUsed,
                    aiProvider: aiProvider,
                    aiModel: aiModel,
                    aiRequests: aiRequests,
                    aiTokens: aiTokens,
                    launchCount: launchCount,
                    installedAgents: installedAgents,
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

        // Also enrich discoveredInstalls from portal leads that have installID or macapp_* eventType
        for lead in downloadLeads where lead.eventType.hasPrefix("macapp_") || !lead.installID.isEmpty {
            let synthID = lead.installID.isEmpty ? "portal-\(lead.ipAddress)-\(lead.hostname)" : lead.installID
            if let idx = discoveredInstalls.firstIndex(where: { $0.installID == synthID }) {
                if lead.downloadedAt > discoveredInstalls[idx].lastSeenAt {
                    discoveredInstalls[idx].lastSeenAt = lead.downloadedAt
                }
                if !lead.activeFeature.isEmpty { discoveredInstalls[idx].activeFeature = lead.activeFeature }
                if !lead.featuresUsed.isEmpty { discoveredInstalls[idx].featuresUsed = lead.featuresUsed }
                if !lead.aiProvider.isEmpty { discoveredInstalls[idx].aiProvider = lead.aiProvider }
                if !lead.aiModel.isEmpty { discoveredInstalls[idx].aiModel = lead.aiModel }
                if lead.aiRequests > discoveredInstalls[idx].aiRequests { discoveredInstalls[idx].aiRequests = lead.aiRequests }
                if lead.aiTokens > discoveredInstalls[idx].aiTokens { discoveredInstalls[idx].aiTokens = lead.aiTokens }
            } else {
                discoveredInstalls.append(InstallRecord(
                    installID: synthID,
                    userID: lead.email,
                    email: lead.email,
                    displayName: lead.name.isEmpty ? "MicroCode User" : lead.name,
                    hostname: lead.hostname.isEmpty ? lead.ipAddress : lead.hostname,
                    appVersion: lead.version,
                    firstInstalledAt: lead.downloadedAt,
                    lastSeenAt: lead.downloadedAt,
                    launchCount: max(1, lead.launchCount),
                    lastMode: lead.activeFeature.isEmpty ? "code" : lead.activeFeature,
                    activeFeature: lead.activeFeature,
                    featuresUsed: lead.featuresUsed,
                    aiProvider: lead.aiProvider,
                    aiModel: lead.aiModel,
                    aiRequests: lead.aiRequests,
                    aiTokens: lead.aiTokens,
                    device: .current,
                    installedAgents: lead.installedAgents,
                    history: []
                ))
            }
        }

        installedDevices = discoveredInstalls.sorted { $0.lastSeenAt > $1.lastSeenAt }
        if let encodedInstalls = try? JSONEncoder().encode(installedDevices) {
            UserDefaults.standard.set(encodedInstalls, forKey: Key.cachedInstalls)
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
                        let featInfo = activeMac.activeFeature.isEmpty ? "" : " · Feature: \(activeMac.activeFeature)"
                        let aiInfo = activeMac.aiModel.isEmpty ? "" : " · AI: \(activeMac.aiProvider) (\(activeMac.aiModel))"
                        return "Active on \(activeMac.hostname) (\(activeMac.launchCount) launches)\(featInfo)\(aiInfo)"
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
    var feature: String? = nil
    var featuresUsed: [String]? = nil
    var aiProvider: String? = nil
    var aiModel: String? = nil
    var aiRequests: Int? = nil
    var aiTokens: Int? = nil
    var email: String? = nil
    var displayName: String? = nil
    var hostname: String? = nil
    var launchCount: Int? = nil
    var installedAgents: [String]? = nil
    let appVersion: String
    let device: TelemetryDeviceSnapshot

    enum CodingKeys: String, CodingKey {
        case eventID = "eventId"
        case installID = "installId"
        case timestamp, name, mode, feature, featuresUsed
        case aiProvider, aiModel, aiRequests, aiTokens
        case email, displayName, hostname, launchCount, installedAgents
        case appVersion, device
    }
}
