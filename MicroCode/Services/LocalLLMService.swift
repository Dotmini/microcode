//
//  LocalLLMService.swift
//  MicroCode
//
//  Smart Multi-Layer Local & LAN LLM Discovery, Best-Perf Auto-Benchmarking,
//  and Worldwide QR Code Pairing Client (LM Studio, Ollama, Apple MLX, vLLM,
//  llama.cpp, Jan, LiteLLM, 9Router, LocalAI, and MicroCode LLM Nodes).
//
//  Created & Designed by Dotmini Software
//  Founder & CEO: Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation
import Combine
import Network
import AppKit
import CoreImage
import Darwin

// MARK: - Discovery Scope

enum LocalLLMDiscoverySource: String, Codable, Equatable {
    case thisMac = "THIS MAC"
    case lan = "LAN"
    case tailscale = "TAILSCALE"
    case worldwideQR = "WORLDWIDE QR"
    case custom = "CUSTOM"

    var badgeColor: String {
        switch self {
        case .thisMac: return "green"
        case .lan: return "blue"
        case .tailscale: return "indigo"
        case .worldwideQR: return "purple"
        case .custom: return "orange"
        }
    }
}

// MARK: - Persisted Paired Endpoint (LAN / Worldwide QR / Custom)

struct PairedLLMEndpoint: Codable, Identifiable, Equatable {
    var id: String { normalizedKey }
    var label: String
    var scheme: String
    var host: String
    var port: Int
    var apiPath: String
    var apiKey: String?
    var isWorldwideTunnel: Bool
    var addedAt: Date

    var normalizedKey: String {
        "\(scheme.lowercased())://\(host.lowercased()):\(port)\(apiPath)"
    }

    var baseURLString: String {
        let omitPort = (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
        let cleanPath = apiPath.hasPrefix("/") ? apiPath : "/\(apiPath)"
        if omitPort {
            return "\(scheme)://\(host)\(cleanPath)"
        }
        return "\(scheme)://\(host):\(port)\(cleanPath)"
    }
}

// MARK: - Local LLM Server Type

enum LocalLLMServerType: String, CaseIterable, Identifiable {
    case nineRouter = "9Router"
    case liteLLM = "LiteLLM"
    case mlx = "Apple MLX"
    case lmStudio = "LM Studio"
    case ollama = "Ollama"
    case vllm = "vLLM / SGLang"
    case llamaCpp = "llama.cpp"
    case jan = "Jan"
    case microcodeNode = "MicroCode LLM"
    case textGenWebUI = "Text Gen WebUI"
    case localAI = "LocalAI"
    case custom = "Custom"

    var id: String { rawValue }

    var defaultPorts: [Int] {
        switch self {
        case .nineRouter: return [20128]
        case .liteLLM: return [4000]
        case .mlx: return [8080, 8081, 10240]
        case .lmStudio: return [1234, 1235, 1236]
        case .ollama: return [11434, 11435]
        case .vllm: return [8000, 30000]
        case .llamaCpp: return [8080, 8081, 8082]
        case .jan: return [1337, 1338]
        case .microcodeNode: return [8475, 8476]
        case .textGenWebUI: return [5000, 5001, 7860]
        case .localAI: return [8080, 8081]
        case .custom: return [8080]
        }
    }

    var defaultPort: Int { defaultPorts.first ?? 8080 }
    var defaultHost: String { "127.0.0.1" }
    var apiPath: String { "/v1" }

    var modelsPath: String {
        switch self {
        case .ollama: return "/api/tags"
        default: return "/v1/models"
        }
    }

    var brandKey: String {
        switch self {
        case .nineRouter: return "9router"
        case .liteLLM: return "litellm"
        case .lmStudio: return "lmstudio"
        case .ollama, .mlx, .llamaCpp, .jan, .microcodeNode: return "local"
        case .vllm, .textGenWebUI, .localAI, .custom: return "vllm"
        }
    }

    var icon: String {
        switch self {
        case .nineRouter: return "point.3.connected.trianglepath.dotted"
        case .liteLLM: return "network"
        case .mlx: return "applelogo"
        case .lmStudio: return "desktopcomputer"
        case .ollama: return "terminal"
        case .vllm: return "bolt.horizontal.circle"
        case .llamaCpp: return "memorychip"
        case .jan: return "sparkles.rectangle.stack"
        case .microcodeNode: return "qrcode.viewfinder"
        case .textGenWebUI: return "globe"
        case .localAI: return "cpu"
        case .custom: return "link"
        }
    }

    var color: String {
        switch self {
        case .nineRouter: return "orange"
        case .liteLLM: return "indigo"
        case .mlx: return "gray"
        case .lmStudio: return "blue"
        case .ollama: return "green"
        case .vllm: return "cyan"
        case .llamaCpp: return "mint"
        case .jan: return "teal"
        case .microcodeNode: return "purple"
        case .textGenWebUI: return "orange"
        case .localAI: return "purple"
        case .custom: return "gray"
        }
    }

    /// Intrinsic inference engine efficiency weight for Best-Perf scoring on Apple Silicon / GPU nodes
    var enginePerfBonus: Int {
        switch self {
        case .mlx: return 14
        case .llamaCpp: return 12
        case .vllm: return 13
        case .lmStudio: return 11
        case .ollama: return 11
        case .microcodeNode: return 10
        case .jan: return 9
        case .liteLLM, .nineRouter: return 8
        case .localAI, .textGenWebUI, .custom: return 7
        }
    }
}

// MARK: - Detected Server

struct DetectedLLMServer: Identifiable {
    let id: UUID
    var type: LocalLLMServerType
    var scheme: String
    var host: String
    var port: Int
    var apiPathOverride: String?
    var apiKey: String?
    var sourceKind: LocalLLMDiscoverySource
    var nodeName: String?
    var requiresAuthToUnlock: Bool
    var models: [LocalLLMModel]
    var warmModelIds: Set<String>
    var isOnline: Bool
    var latency: TimeInterval
    var tokensPerSecond: Double?
    var ttftMs: Int?
    var perfScore: Int
    var isBestPerf: Bool

    init(
        id: UUID = UUID(),
        type: LocalLLMServerType,
        scheme: String = "http",
        host: String,
        port: Int,
        apiPathOverride: String? = nil,
        apiKey: String? = nil,
        sourceKind: LocalLLMDiscoverySource = .thisMac,
        nodeName: String? = nil,
        requiresAuthToUnlock: Bool = false,
        models: [LocalLLMModel] = [],
        warmModelIds: Set<String> = [],
        isOnline: Bool = false,
        latency: TimeInterval = 0,
        tokensPerSecond: Double? = nil,
        ttftMs: Int? = nil,
        perfScore: Int = 0,
        isBestPerf: Bool = false
    ) {
        self.id = id
        self.type = type
        self.scheme = scheme
        self.host = host
        self.port = port
        self.apiPathOverride = apiPathOverride
        self.apiKey = apiKey
        self.sourceKind = sourceKind
        self.nodeName = nodeName
        self.requiresAuthToUnlock = requiresAuthToUnlock
        self.models = models
        self.warmModelIds = warmModelIds
        self.isOnline = isOnline
        self.latency = latency
        self.tokensPerSecond = tokensPerSecond
        self.ttftMs = ttftMs
        self.perfScore = perfScore
        self.isBestPerf = isBestPerf
    }

    var effectiveApiPath: String {
        let raw = apiPathOverride ?? type.apiPath
        if raw.isEmpty { return "/v1" }
        return raw.hasPrefix("/") ? raw : "/\(raw)"
    }

    var hostPortLabel: String {
        let omitPort = (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
        return omitPort ? host : "\(host):\(port)"
    }

    var endpoint: String {
        let omitPort = (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
        let base = omitPort ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"
        let cleanPath = effectiveApiPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return cleanPath.isEmpty ? base : "\(base)/\(cleanPath)"
    }

    var latencyMs: Int {
        max(1, Int((latency * 1000.0).rounded()))
    }

    var displayName: String {
        if let nodeName, !nodeName.isEmpty {
            return "\(nodeName) · \(type.rawValue)"
        }
        return "\(type.rawValue) (\(hostPortLabel))"
    }

    var deduplicationKey: String {
        let normHost = (host == "localhost" || host == "::1") ? "127.0.0.1" : host.lowercased()
        return "\(scheme.lowercased())://\(normHost):\(port)"
    }
}

struct LocalLLMModel: Identifiable, Hashable {
    let id: String
    let name: String
    var size: String?
    var quantization: String?
    var parameterSize: String?
    var family: String?
    var isWarmLoaded: Bool = false
    var contextLength: Int? = nil
    var isDownloading: Bool = false
    var downloadProgress: Double = 0

    var displayName: String {
        if let q = quantization { return "\(name) [\(q)]" }
        return name
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: LocalLLMModel, rhs: LocalLLMModel) -> Bool { lhs.id == rhs.id }
}

// MARK: - Live Model Hub Data Models

enum ModelHubSource: String, CaseIterable, Identifiable {
    case mlx = "Apple MLX"
    case ollama = "Ollama"
    case gguf = "GGUF"
    case installed = "Installed"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .mlx: return "Hugging Face · Native Apple Silicon"
        case .ollama: return "ollama.com · Official Library"
        case .gguf: return "Hugging Face · LM Studio / Ollama"
        case .installed: return "This Mac & LAN Servers"
        }
    }

    var iconName: String {
        switch self {
        case .mlx: return "apple.logo"
        case .ollama: return "shippingbox"
        case .gguf: return "cube"
        case .installed: return "checkmark.circle"
        }
    }
}

enum ModelRAMFitStatus: Equatable {
    case fits
    case tight
    case tooLarge
    case unknown
}

struct HubModelVariant: Identifiable, Equatable {
    let id: String
    let label: String
    var filenames: [String]
    var sizeBytes: Int64
    var quantization: String?
    var contextWindow: String?
    var isDownloadedOnDisk: Bool = false

    var primaryFilename: String? { filenames.first }

    var sizeLabel: String {
        guard sizeBytes > 0 else { return "Auto" }
        let gb = Double(sizeBytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(sizeBytes) / (1024 * 1024)
        return String(format: "%.0f MB", max(1, mb))
    }

    func ramFit(totalRAMBytes: UInt64) -> ModelRAMFitStatus {
        guard sizeBytes > 0, totalRAMBytes > 0 else { return .unknown }
        let ratio = Double(sizeBytes) / Double(totalRAMBytes)
        if ratio <= 0.72 { return .fits }
        if ratio <= 0.92 { return .tight }
        return .tooLarge
    }
}

struct HubModelItem: Identifiable, Equatable {
    let id: String
    let source: ModelHubSource
    let repoOrSlug: String
    let displayName: String
    let author: String
    var summary: String
    var downloadsCount: Int
    var likesCount: Int
    var updatedLabel: String
    var capabilities: [String]
    var parameterSizes: [String]
    var estimatedSizeBytes: Int64
    var variants: [HubModelVariant]
    var detailsLoaded: Bool
    var installedServerEndpoint: String? = nil
    var installedServerName: String? = nil
    var installedModelID: String? = nil
    var localDiskPath: String? = nil

    var formattedDownloads: String? {
        guard downloadsCount > 0 else { return nil }
        if downloadsCount >= 1_000_000 {
            return String(format: "%.1fM", Double(downloadsCount) / 1_000_000.0)
        } else if downloadsCount >= 1_000 {
            return String(format: "%.1fK", Double(downloadsCount) / 1_000.0)
        }
        return String(downloadsCount)
    }

    var webURL: URL? {
        switch source {
        case .mlx, .gguf:
            return URL(string: "https://huggingface.co/\(repoOrSlug)")
        case .ollama:
            return URL(string: "https://ollama.com/library/\(repoOrSlug)")
        case .installed:
            return nil
        }
    }
}

struct ActiveModelDownloadState: Equatable {
    var modelID: String
    var variantID: String
    var title: String
    var statusText: String
    var fractionCompleted: Double
    var completedBytes: Int64
    var totalBytes: Int64
    var speedBytesPerSec: Double
    var isIndeterminate: Bool

    var progressSummary: String {
        if totalBytes > 0 {
            let doneStr = ByteCountFormatter.string(fromByteCount: completedBytes, countStyle: .file)
            let totalStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            if speedBytesPerSec > 1024 {
                let speedStr = ByteCountFormatter.string(fromByteCount: Int64(speedBytesPerSec), countStyle: .file)
                return "\(doneStr) / \(totalStr) · \(speedStr)/s"
            }
            return "\(doneStr) / \(totalStr)"
        }
        return statusText
    }
}

// MARK: - Downloadable Model Catalog (Legacy Compatibility)

struct DownloadableModel: Identifiable {
    let id: String
    let name: String
    let provider: String
    let description: String
    let params: String
    let sizeGB: Double
    let capabilities: [String]
    let ollamaTag: String

    var sizeLabel: String {
        sizeGB >= 1 ? String(format: "%.1f GB", sizeGB) : String(format: "%.0f MB", sizeGB * 1024)
    }
}

// MARK: - Parsed Flexible Endpoint

struct FlexibleLLMEndpointSpec: Equatable {
    var scheme: String
    var host: String
    var port: Int
    var apiPath: String
    var apiKey: String?
    var label: String?
}

// MARK: - Local LLM Service

@MainActor
class LocalLLMService: ObservableObject {
    static let shared = LocalLLMService()

    @Published var detectedServers: [DetectedLLMServer] = []
    @Published var isScanning = false
    @Published var isBenchmarking = false
    @Published var benchmarkingServerID: UUID? = nil
    @Published var selectedServerIndex: Int = 0
    @Published var selectedModelId: String = ""
    @Published var customHost: String = "127.0.0.1"
    @Published var customPort: String = "1234"
    @Published var quickConnectInput: String = ""
    @Published var quickConnectAPIKey: String = ""
    @Published var pairingStatusMessage: String? = nil
    @Published var lastScanTime: Date?
    @Published var downloadingModels: [String: Double] = [:]
    @Published var scanLog: [String] = []
    @Published var pairedRemoteEndpoints: [PairedLLMEndpoint] = []
    @Published var lanRadarSummary: String = ""
    @Published var activeLANPeerCount: Int = 0

    // Live Model Hub & Real Download / Runtime State
    @Published var hubModels: [HubModelItem] = []
    @Published var isFetchingHub: Bool = false
    @Published var isFetchingHubDetail: Bool = false
    @Published var hubErrorMessage: String? = nil
    @Published var hubActionMessage: String? = nil
    @Published var activeHubDownload: ActiveModelDownloadState? = nil

    private var hubFetchGeneration: Int = 0
    private var activeHubDownloadTask: Task<Void, Never>? = nil
    private var managedMLXProcess: Process? = nil
    private var managedMLXPort: Int? = nil
    private var managedOllamaProcess: Process? = nil

    let physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory

    var physicalMemoryGBLabel: String {
        let gb = Int(round(Double(physicalMemoryBytes) / (1024.0 * 1024.0 * 1024.0)))
        return "\(String(gb)) GB"
    }

    lazy var hardwareChipName: String = {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var buf = [CChar](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
            let name = String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel Mac"
        #endif
    }()

    var mlxServerBinaryPath: String? {
        let candidates = [
            "/opt/homebrew/bin/mlx_lm.server",
            "/usr/local/bin/mlx_lm.server",
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/mlx_lm.server")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var ollamaBinaryPath: String? {
        let candidates = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var hasLMStudioInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/LM Studio.app") ||
        FileManager.default.isExecutableFile(atPath: (NSHomeDirectory() as NSString).appendingPathComponent(".lmstudio/bin/lms"))
    }

    @Published var autoSelectBestPerf: Bool {
        didSet {
            UserDefaults.standard.set(autoSelectBestPerf, forKey: "microcode.localLLM.autoBestPerf")
            if autoSelectBestPerf {
                applyBestPerfSelectionIfAvailable()
            }
        }
    }

    @Published var scanLANEnabled: Bool {
        didSet {
            UserDefaults.standard.set(scanLANEnabled, forKey: "microcode.localLLM.scanLAN")
        }
    }

    nonisolated(unsafe) static var cachedEndpoint: String = "http://127.0.0.1:1234/v1"
    nonisolated(unsafe) static var cachedModel: String = "local-model"
    nonisolated(unsafe) static var cachedAPIKey: String = "local"

    nonisolated private static let authMapLock = NSLock()
    nonisolated(unsafe) private static var endpointAPIKeyMap: [String: String] = [:]

    /// Thread-safe API key resolution for `AIClient` even when callers only set `cachedEndpoint`.
    nonisolated static func resolveAPIKey(forEndpoint endpoint: String) -> String {
        let clean = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        authMapLock.lock()
        let mapped = endpointAPIKeyMap[clean]
        authMapLock.unlock()
        if let mapped, !mapped.isEmpty {
            return mapped
        }
        return cachedAPIKey.isEmpty ? "local" : cachedAPIKey
    }

    nonisolated private static func registerEndpointAPIKey(endpoint: String, apiKey: String?) {
        let clean = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        authMapLock.lock()
        if let apiKey, !apiKey.isEmpty {
            endpointAPIKeyMap[clean] = apiKey
        } else {
            endpointAPIKeyMap.removeValue(forKey: clean)
        }
        authMapLock.unlock()
    }

    /// Cached benchmark speeds across rescans keyed by server deduplicationKey
    private var measuredPerfCache: [String: (tps: Double, ttftMs: Int)] = [:]

    /// Reusable ephemeral URLSessions (avoids per-probe URLSession leaks)
    private lazy var fastLocalSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 1.3
        cfg.timeoutIntervalForResource = 2.2
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private lazy var lanAndRemoteSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3.5
        cfg.timeoutIntervalForResource = 6.0
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    // Bonjour / mDNS Browsers for zero-config LAN discovery
    private var bonjourBrowsers: [NWBrowser] = []
    private let bonjourQueue = DispatchQueue(label: "com.dotmini.microcode.localllm.bonjour", qos: .utility)
    private var bonjourDiscoveredEndpoints: Set<NWEndpoint> = []
    private var bonjourResolvedHosts: Set<String> = []
    private var bonjourPeerMachines: [String: String] = [:]

    private static let pairedEndpointsDefaultsKey = "microcode.localLLM.pairedEndpoints.v1"

    private init() {
        self.autoSelectBestPerf = (UserDefaults.standard.object(forKey: "microcode.localLLM.autoBestPerf") as? Bool) ?? true
        self.scanLANEnabled = (UserDefaults.standard.object(forKey: "microcode.localLLM.scanLAN") as? Bool) ?? true
        self.loadPairedEndpoints()
        self.startBonjourDiscovery()

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self?.scanForServers()
        }
    }

    let modelCatalog: [DownloadableModel] = [
        DownloadableModel(id: "mlx-qwen-coder", name: "Qwen 2.5 Coder", provider: "MLX Community", description: "Incredibly fast coding model natively optimized for Apple Silicon (MLX).", params: "7B", sizeGB: 4.2, capabilities: ["Code", "Reasoning", "MLX"], ollamaTag: "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit"),
        DownloadableModel(id: "mlx-llama-3", name: "Llama 3.1", provider: "MLX Community", description: "Meta's Llama 3.1 optimized for Mac M-Series chips.", params: "8B", sizeGB: 4.7, capabilities: ["Chat", "Reasoning", "MLX"], ollamaTag: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit"),
        DownloadableModel(id: "mlx-deepseek-r1", name: "DeepSeek R1", provider: "MLX Community", description: "DeepSeek R1 distilled model for Apple Silicon.", params: "8B", sizeGB: 4.9, capabilities: ["Reasoning", "Code", "MLX"], ollamaTag: "mlx-community/DeepSeek-R1-Distill-Llama-8B-4bit"),

        DownloadableModel(id: "gemma3", name: "Gemma 3", provider: "Google", description: "Google's efficient open model. Great for coding and reasoning.", params: "4B", sizeGB: 3.3, capabilities: ["Code", "Reasoning"], ollamaTag: "gemma3"),
        DownloadableModel(id: "gemma3-12b", name: "Gemma 3 12B", provider: "Google", description: "Larger Gemma with stronger performance.", params: "12B", sizeGB: 8.1, capabilities: ["Code", "Reasoning", "Vision"], ollamaTag: "gemma3:12b"),
        DownloadableModel(id: "qwen3", name: "Qwen 3", provider: "Alibaba", description: "Hybrid thinking. Strong multilingual and code.", params: "8B", sizeGB: 5.2, capabilities: ["Code", "Reasoning", "Tool Use"], ollamaTag: "qwen3"),
        DownloadableModel(id: "llama3.3", name: "Llama 3.3", provider: "Meta", description: "Meta's latest. Excellent for general and code tasks.", params: "70B", sizeGB: 43.0, capabilities: ["Code", "Reasoning"], ollamaTag: "llama3.3"),
        DownloadableModel(id: "llama3.2", name: "Llama 3.2", provider: "Meta", description: "Efficient small model. Fast local inference.", params: "3B", sizeGB: 2.0, capabilities: ["Code", "Chat"], ollamaTag: "llama3.2"),
        DownloadableModel(id: "deepseek-r1-ollama", name: "DeepSeek R1 (Ollama)", provider: "DeepSeek", description: "Reasoning-focused. Great for complex problem solving.", params: "8B", sizeGB: 5.0, capabilities: ["Reasoning", "Code"], ollamaTag: "deepseek-r1:8b"),
        DownloadableModel(id: "codellama", name: "Code Llama", provider: "Meta", description: "Specialized for code generation and debugging.", params: "7B", sizeGB: 3.8, capabilities: ["Code"], ollamaTag: "codellama"),
        DownloadableModel(id: "mistral", name: "Mistral", provider: "Mistral AI", description: "Fast, efficient model with strong reasoning.", params: "7B", sizeGB: 4.1, capabilities: ["Code", "Chat"], ollamaTag: "mistral"),
        DownloadableModel(id: "phi4", name: "Phi-4", provider: "Microsoft", description: "Compact but powerful reasoning model.", params: "14B", sizeGB: 9.1, capabilities: ["Code", "Reasoning"], ollamaTag: "phi4"),
        DownloadableModel(id: "nemotron", name: "Nemotron Mini", provider: "NVIDIA", description: "Compact model optimized for reasoning.", params: "4B", sizeGB: 2.7, capabilities: ["Reasoning", "Chat"], ollamaTag: "nemotron-mini"),
    ]

    var activeServer: DetectedLLMServer? {
        guard !detectedServers.isEmpty, selectedServerIndex >= 0, selectedServerIndex < detectedServers.count else { return nil }
        return detectedServers[selectedServerIndex]
    }

    var activeEndpoint: String {
        let value = activeServer?.endpoint ?? "http://127.0.0.1:1234/v1"
        LocalLLMService.cachedEndpoint = value
        LocalLLMService.cachedAPIKey = activeServer?.apiKey ?? "local"
        return value
    }

    var activeModel: String {
        let value = !selectedModelId.isEmpty ? selectedModelId : (activeServer?.models.first?.id ?? "local-model")
        LocalLLMService.cachedModel = value
        return value
    }

    var availableModels: [LocalLLMModel] { activeServer?.models ?? [] }

    func selectServer(at index: Int, preferredModelId: String? = nil) {
        guard index >= 0, index < detectedServers.count else { return }
        selectedServerIndex = index
        let srv = detectedServers[index]
        let chosenModel: String
        if let preferredModelId, srv.models.contains(where: { $0.id == preferredModelId }) {
            chosenModel = preferredModelId
        } else if srv.models.contains(where: { $0.id == selectedModelId }) {
            chosenModel = selectedModelId
        } else if let warm = srv.models.first(where: \.isWarmLoaded) {
            chosenModel = warm.id
        } else {
            chosenModel = srv.models.first?.id ?? "local-model"
        }
        selectedModelId = chosenModel
        LocalLLMService.cachedEndpoint = srv.endpoint
        LocalLLMService.cachedModel = chosenModel
        LocalLLMService.cachedAPIKey = srv.apiKey ?? "local"
        Self.registerEndpointAPIKey(endpoint: srv.endpoint, apiKey: srv.apiKey)
    }

    // MARK: - Bonjour / mDNS Zero-Config Discovery (LLM Services + LAN Computers)

    private func startBonjourDiscovery() {
        guard bonjourBrowsers.isEmpty else { return }
        let llmServiceTypes: Set<String> = ["_microcode-llm._tcp", "_ollama._tcp"]
        let workstationServiceTypes = [
            "_microcode-llm._tcp",
            "_ollama._tcp",
            "_smb._tcp",
            "_ssh._tcp",
            "_workstation._tcp",
            "_rfb._tcp",
            "_http._tcp",
            "_companion-link._tcp"
        ]
        let params = NWParameters()
        params.includePeerToPeer = true

        for serviceType in workstationServiceTypes {
            let isDirectLLMService = llmServiceTypes.contains(serviceType)
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    for result in results {
                        if !self.bonjourDiscoveredEndpoints.contains(result.endpoint) {
                            self.bonjourDiscoveredEndpoints.insert(result.endpoint)
                            self.resolveBonjourEndpoint(result.endpoint, isDirectLLMService: isDirectLLMService)
                        }
                    }
                }
            }
            browser.start(queue: bonjourQueue)
            bonjourBrowsers.append(browser)
        }
    }

    private func resolveBonjourEndpoint(_ endpoint: NWEndpoint, isDirectLLMService: Bool) {
        var serviceDisplayName: String? = nil
        if case .service(let name, _, _, _) = endpoint {
            let clean = name.components(separatedBy: " [").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? name
            if !clean.isEmpty {
                serviceDisplayName = clean
            }
        }

        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                if let remote = conn.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = remote {
                    let rawHost: String
                    switch host {
                    case .ipv4(let v4):
                        rawHost = "\(v4)".components(separatedBy: "%").first ?? ""
                    case .name(let name, _):
                        rawHost = name
                    case .ipv6:
                        rawHost = ""
                    @unknown default:
                        rawHost = ""
                    }
                    let cleanPort = Int(port.rawValue)
                    if !rawHost.isEmpty {
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            if let label = serviceDisplayName, self.bonjourPeerMachines[rawHost] == nil {
                                self.bonjourPeerMachines[rawHost] = label
                            }
                            if isDirectLLMService && cleanPort > 0 {
                                self.bonjourResolvedHosts.insert("\(rawHost):\(cleanPort)")
                            }
                        }
                    }
                }
                conn.cancel()
            } else if case .failed = state {
                conn.cancel()
            }
        }
        conn.start(queue: bonjourQueue)
    }

    // MARK: - Flexible Endpoint & QR Payload Parser

    /// Parses any user input format:
    /// - Host `127.0.0.1` + Port `1235/v1` (fixes trailing path in port field!)
    /// - Full URL `http://mac-studio.local:1234/v1` or `https://xxx.trycloudflare.com/?token=sk-mc-...`
    /// - Deep Link `microcode://llm-connect?endpoint=https://...&token=sk-mc-...&name=MacStudio`
    nonisolated static func parseFlexibleEndpoint(
        hostInput: String,
        portInput: String = "",
        explicitAPIKey: String? = nil
    ) -> FlexibleLLMEndpointSpec? {
        let trimmedHost = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = portInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExplicitKey = explicitAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }

        // 1. Deep Link: microcode://llm-connect?endpoint=...&token=...
        if trimmedHost.lowercased().hasPrefix("microcode://") || trimmedHost.lowercased().hasPrefix("codetuner://"),
           let comps = URLComponents(string: trimmedHost) {
            let items = comps.queryItems ?? []
            let targetURL = items.first(where: { ["endpoint", "url", "base"].contains($0.name.lowercased()) })?.value ?? ""
            let token = items.first(where: { ["token", "key", "apikey", "api_key"].contains($0.name.lowercased()) })?.value
            let name = items.first(where: { $0.name.lowercased() == "name" })?.value
            if var nested = parseFlexibleEndpoint(hostInput: targetURL, explicitAPIKey: token ?? cleanExplicitKey) {
                if let name, !name.isEmpty { nested.label = name }
                return nested
            }
            return nil
        }

        // 2. Full URL (http:// or https://) or domain with slash/query
        if trimmedHost.contains("://") || trimmedHost.contains("?token=") || trimmedHost.hasSuffix(".trycloudflare.com") || trimmedHost.hasSuffix(".lhr.life") {
            let urlCandidate = trimmedHost.contains("://") ? trimmedHost : "https://\(trimmedHost)"
            if let comps = URLComponents(string: urlCandidate), let host = comps.host, !host.isEmpty {
                let scheme = (comps.scheme ?? "http").lowercased()
                let defaultPort = (scheme == "https") ? 443 : 80
                let port = comps.port ?? defaultPort
                let queryToken = comps.queryItems?.first(where: {
                    ["token", "key", "apikey", "api_key"].contains($0.name.lowercased())
                })?.value
                let rawPath = comps.path.trimmingCharacters(in: .whitespacesAndNewlines)
                let apiPath: String
                if rawPath.isEmpty || rawPath == "/" {
                    apiPath = "/v1"
                } else if rawPath.hasSuffix("/models") {
                    let stripped = String(rawPath.dropLast("/models".count))
                    apiPath = stripped.isEmpty ? "/v1" : stripped
                } else if rawPath.hasSuffix("/chat/completions") {
                    let stripped = String(rawPath.dropLast("/chat/completions".count))
                    apiPath = stripped.isEmpty ? "/v1" : stripped
                } else {
                    apiPath = rawPath
                }
                let finalKey = (cleanExplicitKey?.isEmpty == false) ? cleanExplicitKey : queryToken
                return FlexibleLLMEndpointSpec(
                    scheme: scheme,
                    host: host,
                    port: port,
                    apiPath: apiPath,
                    apiKey: finalKey,
                    label: comps.queryItems?.first(where: { $0.name.lowercased() == "name" })?.value
                )
            }
        }

        // 3. Host containing inline `:port[/path]` (e.g. `192.168.1.50:1235/v1`)
        if trimmedHost.contains(":") && !trimmedHost.hasPrefix("[") {
            return parseFlexibleEndpoint(
                hostInput: "http://\(trimmedHost)",
                portInput: "",
                explicitAPIKey: cleanExplicitKey
            )
        }

        // 4. Separate Host + Port fields where Port may contain `/v1` (e.g. `127.0.0.1` + `1235/v1`)
        let digitsPrefix = trimmedPort.prefix(while: { $0.isNumber })
        let remainderPath = String(trimmedPort.dropFirst(digitsPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let portNum = Int(digitsPrefix), portNum > 0, portNum <= 65535 else {
            return nil
        }
        let apiPath: String
        if remainderPath.isEmpty || remainderPath == "/" {
            apiPath = "/v1"
        } else {
            apiPath = remainderPath.hasPrefix("/") ? remainderPath : "/\(remainderPath)"
        }
        return FlexibleLLMEndpointSpec(
            scheme: "http",
            host: trimmedHost,
            port: portNum,
            apiPath: apiPath,
            apiKey: (cleanExplicitKey?.isEmpty == false) ? cleanExplicitKey : nil,
            label: nil
        )
    }

    // MARK: - Smart Multi-Layer Concurrent Scanner (Local + Listening Sockets + LAN + Tailscale + Paired QR)

    private struct ProbeCandidate: Hashable {
        let scheme: String
        let host: String
        let port: Int
        let apiPath: String?
        let apiKey: String?
        let sourceKind: LocalLLMDiscoverySource
        let labelHint: String?

        var hostPortKey: String {
            let normHost = (host == "localhost" || host == "::1") ? "127.0.0.1" : host.lowercased()
            return "\(scheme)://\(normHost):\(port)"
        }
    }

    func scanForServers() async {
        guard !isScanning else { return }
        isScanning = true
        let previouslySelectedEndpoint = activeServer?.endpoint
        let previouslySelectedModel = selectedModelId
        scanLog = ["🔍 Scanning This Mac, LAN, Bonjour & Paired Worldwide Endpoints…"]

        let ownGatewayPort: Int = LocalLLMGatewayService.shared.isServerRunning
            ? Int(LocalLLMGatewayService.shared.listeningPort)
            : -1
        let localInterfaceSnapshot = await Task.detached(priority: .userInitiated) {
            Self.discoverNetworkTopology()
        }.value
        let ownIPs = Set(localInterfaceSnapshot.ownIPs + ["127.0.0.1", "localhost", "::1"])

        var candidatesByKey: [String: ProbeCandidate] = [:]
        func addCandidate(_ c: ProbeCandidate) {
            // Never loop back into this Mac's own LocalLLMGatewayService proxy port
            if ownGatewayPort > 0 && c.port == ownGatewayPort && ownIPs.contains(c.host) {
                return
            }
            if candidatesByKey[c.hostPortKey] == nil || c.apiKey != nil {
                candidatesByKey[c.hostPortKey] = c
            }
        }

        // 1. Standard Localhost LLM Engine Ports (deduplicated per port — fingerprinted dynamically!)
        let standardLocalPorts = [11434, 1234, 1235, 1236, 8080, 8081, 8000, 10240, 1337, 4000, 20128, 30000, 5001, 7860]
        for port in standardLocalPorts {
            addCandidate(ProbeCandidate(
                scheme: "http",
                host: "127.0.0.1",
                port: port,
                apiPath: nil,
                apiKey: nil,
                sourceKind: .thisMac,
                labelHint: nil
            ))
        }

        // 2. Dynamic Listening TCP Socket Introspection on This Mac (catches custom LM Studio / MLX / llama-server ports!)
        let dynamicLocalPorts = await Task.detached(priority: .userInitiated) {
            Self.discoverCandidateLocalListeningPorts(excludingPort: ownGatewayPort)
        }.value
        for port in dynamicLocalPorts {
            addCandidate(ProbeCandidate(
                scheme: "http",
                host: "127.0.0.1",
                port: port,
                apiPath: nil,
                apiKey: nil,
                sourceKind: .thisMac,
                labelHint: nil
            ))
        }

        // 3. Smart Custom Host / Port field (handles `1235/v1` and full URLs!)
        if let customSpec = Self.parseFlexibleEndpoint(hostInput: customHost, portInput: customPort) {
            let isLocal = ownIPs.contains(customSpec.host)
            addCandidate(ProbeCandidate(
                scheme: customSpec.scheme,
                host: customSpec.host,
                port: customSpec.port,
                apiPath: customSpec.apiPath,
                apiKey: customSpec.apiKey,
                sourceKind: isLocal ? .thisMac : (customSpec.scheme == "https" ? .worldwideQR : .custom),
                labelHint: customSpec.label
            ))
        }

        // 4. Persisted Paired Remote / QR / Custom Endpoints
        for paired in pairedRemoteEndpoints {
            addCandidate(ProbeCandidate(
                scheme: paired.scheme,
                host: paired.host,
                port: paired.port,
                apiPath: paired.apiPath,
                apiKey: paired.apiKey,
                sourceKind: paired.isWorldwideTunnel ? .worldwideQR : (ownIPs.contains(paired.host) ? .thisMac : .lan),
                labelHint: paired.label
            ))
        }

        // 5. Bonjour / mDNS Discovered LAN Peers
        let bonjourLabelsSnapshot = bonjourPeerMachines
        for entry in bonjourResolvedHosts {
            let parts = entry.split(separator: ":")
            if parts.count == 2, let port = Int(parts[1]) {
                let host = String(parts[0])
                if !ownIPs.contains(host) {
                    addCandidate(ProbeCandidate(
                        scheme: "http",
                        host: host,
                        port: port,
                        apiPath: nil,
                        apiKey: nil,
                        sourceKind: .lan,
                        labelHint: bonjourLabelsSnapshot[host]
                    ))
                }
            }
        }

        // 6. Smart LAN / Thunderbolt Bridge / Hotspot / Tailscale / Bonjour Workstation Discovery
        if scanLANEnabled {
            let priorityLANPorts = [1234, 1235, 1236, 1237, 11434, 11435, 8000, 8001, 8080, 8081, 8088, 8475, 8476, 3000, 4000, 5000, 1337, 7860, 10240, 20128, 30000]
            let subnetSweepPorts = [1234, 1235, 1236, 11434, 8000, 8080, 8475, 4000, 1337]

            var neighborHosts = localInterfaceSnapshot.arpNeighbors.subtracting(ownIPs)
            neighborHosts.formUnion(localInterfaceSnapshot.tailscalePeers.subtracting(ownIPs))
            neighborHosts.formUnion(Set(bonjourLabelsSnapshot.keys).subtracting(ownIPs))

            let subnetBases = localInterfaceSnapshot.lanSubnetPrefixes
            activeLANPeerCount = neighborHosts.count
            if let primary = localInterfaceSnapshot.primaryLANDisplay {
                lanRadarSummary = "\(primary) · \(max(1, neighborHosts.count)) LAN device(s)"
            } else {
                lanRadarSummary = "\(neighborHosts.count) LAN peer(s) scanned"
            }

            // Fast Wi-Fi ARP-safe non-blocking TCP pre-filter across ARP/Bonjour peers + primary physical /24 Wi-Fi subnet
            let openLANEndpoints = await Task.detached(priority: .userInitiated) {
                Self.sweepOpenLANEndpoints(
                    priorityHosts: Array(neighborHosts),
                    priorityPorts: priorityLANPorts,
                    subnetPrefixes: Array(subnetBases.prefix(1)),
                    subnetPorts: subnetSweepPorts,
                    excludingHosts: ownIPs
                )
            }.value

            if !openLANEndpoints.isEmpty {
                scanLog.append("  📡 Found \(openLANEndpoints.count) open LAN candidate socket(s)")
            }
            for hit in openLANEndpoints {
                let source: LocalLLMDiscoverySource = hit.host.hasPrefix("100.") ? .tailscale : .lan
                addCandidate(ProbeCandidate(
                    scheme: "http",
                    host: hit.host,
                    port: hit.port,
                    apiPath: nil,
                    apiKey: nil,
                    sourceKind: source,
                    labelHint: bonjourLabelsSnapshot[hit.host]
                ))
            }
        } else {
            lanRadarSummary = "LAN Scan paused (This Mac only)"
        }

        // 7. Concurrent HTTP Fingerprinting & Model Inspection across all candidates
        let allCandidates = Array(candidatesByKey.values)
        var discovered: [DetectedLLMServer] = []

        await withTaskGroup(of: DetectedLLMServer?.self) { group in
            for candidate in allCandidates {
                group.addTask { [weak self] in
                    await self?.probeSmartCandidate(candidate)
                }
            }
            for await result in group {
                if var srv = result {
                    if let cachedPerf = measuredPerfCache[srv.deduplicationKey] {
                        srv.tokensPerSecond = cachedPerf.tps
                        srv.ttftMs = cachedPerf.ttftMs
                    }
                    srv.perfScore = Self.computePerformanceScore(for: srv)
                    Self.registerEndpointAPIKey(endpoint: srv.endpoint, apiKey: srv.apiKey)
                    discovered.append(srv)
                }
            }
        }

        // 8. Sort by Best Perf Score descending (online with models first, then lowest latency)
        discovered.sort { a, b in
            if a.isOnline != b.isOnline { return a.isOnline && !b.isOnline }
            if a.requiresAuthToUnlock != b.requiresAuthToUnlock { return !a.requiresAuthToUnlock }
            if a.perfScore != b.perfScore { return a.perfScore > b.perfScore }
            return a.latency < b.latency
        }

        // Mark #1 Best Perf server
        if let bestIdx = discovered.firstIndex(where: { $0.isOnline && !$0.requiresAuthToUnlock }) {
            discovered[bestIdx].isBestPerf = true
        }

        detectedServers = discovered

        // 9. Preserve user choice or Auto-Select Best Perf
        if autoSelectBestPerf, let bestIdx = detectedServers.firstIndex(where: \.isBestPerf) {
            selectServer(at: bestIdx, preferredModelId: previouslySelectedModel)
        } else if let prevEndpoint = previouslySelectedEndpoint,
                  let prevIdx = detectedServers.firstIndex(where: { $0.endpoint == prevEndpoint && $0.isOnline }) {
            selectServer(at: prevIdx, preferredModelId: previouslySelectedModel)
        } else if let firstReady = detectedServers.firstIndex(where: { $0.isOnline && !$0.requiresAuthToUnlock }) {
            selectServer(at: firstReady, preferredModelId: previouslySelectedModel)
        }

        lastScanTime = Date()
        isScanning = false
        let onlineCount = detectedServers.filter(\.isOnline).count
        scanLog.append("✅ Smart scan complete: \(onlineCount) server(s) detected")
        AIModelCatalog.shared.integrateLocalModels()
    }

    private func applyBestPerfSelectionIfAvailable() {
        if let bestIdx = detectedServers.firstIndex(where: \.isBestPerf) {
            selectServer(at: bestIdx)
        }
    }

    // MARK: - Smart Fingerprinting Probe

    private func probeSmartCandidate(_ candidate: ProbeCandidate) async -> DetectedLLMServer? {
        let isLocal = (candidate.sourceKind == .thisMac)
        // Quick TCP pre-check for plain HTTP local/LAN hosts so closed ports fail in <2ms instead of full HTTP overhead
        if candidate.scheme == "http" {
            let tcpTimeoutMs: Int32 = isLocal ? 150 : 750
            let isOpen = await Task.detached(priority: .userInitiated) {
                Self.isTCPPortOpen(host: candidate.host, port: candidate.port, timeoutMs: tcpTimeoutMs)
            }.value
            guard isOpen else { return nil }
        }

        let session = isLocal ? fastLocalSession : lanAndRemoteSession
        let omitPort = (candidate.scheme == "https" && candidate.port == 443) || (candidate.scheme == "http" && candidate.port == 80)
        let origin = omitPort ? "\(candidate.scheme)://\(candidate.host)" : "\(candidate.scheme)://\(candidate.host):\(candidate.port)"
        let customPath = candidate.apiPath?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "v1"

        func makeRequest(_ urlString: String) -> URLRequest? {
            guard let url = URL(string: urlString) else { return nil }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = isLocal ? 1.3 : 3.5
            if let key = candidate.apiKey, !key.isEmpty {
                req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
            return req
        }

        let startTime = Date()

        // A. Check Ollama `/api/tags` first when port is 11434/11435 (or in parallel fallback)
        if candidate.port == 11434 || candidate.port == 11435 {
            if let ollamaServer = await tryProbeOllama(origin: origin, candidate: candidate, session: session, startTime: startTime) {
                return ollamaServer
            }
        }

        // B. Probe OpenAI-compatible `/v1/models` (or custom `<apiPath>/models`)
        let modelsURLString = "\(origin)/\(customPath)/models"
        if let req = makeRequest(modelsURLString),
           let (data, response) = try? await session.data(for: req),
           let http = response as? HTTPURLResponse {
            let latency = Date().timeIntervalSince(startTime)
            let isMicroCodeNode = http.value(forHTTPHeaderField: "X-MicroCode-LLM") == "1"
            let resolvedPeerLabel: String? = {
                if let explicitHeader = http.value(forHTTPHeaderField: "X-MicroCode-Node"), !explicitHeader.isEmpty {
                    return explicitHeader
                }
                if let hint = candidate.labelHint, !hint.isEmpty {
                    return hint
                }
                if candidate.sourceKind == .lan || candidate.sourceKind == .tailscale {
                    return Self.resolveReverseHostLabel(for: candidate.host)
                }
                return nil
            }()

            if (200...299).contains(http.statusCode) {
                var parsedModels = parseOpenAIModels(data)
                let bodyText = String(data: data.prefix(2048), encoding: .utf8)?.lowercased() ?? ""
                let serverHeader = (http.value(forHTTPHeaderField: "Server") ?? "").lowercased()

                // Must actually look like an OpenAI `/v1/models` JSON response (prevents static `python -m http.server` false positives!)
                let isGenuineModelsPayload = !parsedModels.isEmpty || bodyText.contains("\"object\"") || bodyText.contains("\"data\"")
                if isGenuineModelsPayload {
                    var detectedType = Self.fingerprintServerType(
                        port: candidate.port,
                        isMicroCodeNode: isMicroCodeNode,
                        serverHeader: serverHeader,
                        bodyPreview: bodyText,
                        models: parsedModels
                    )
                    var warmIds = Set<String>()

                    // Enrich LM Studio (even on custom ports or when 0 models are pre-loaded into RAM!) via `/api/v0/models`
                    if detectedType == .lmStudio || detectedType == .custom || parsedModels.isEmpty,
                       let lmsReq = makeRequest("\(origin)/api/v0/models"),
                       let (lmsData, lmsRes) = try? await session.data(for: lmsReq),
                       (lmsRes as? HTTPURLResponse)?.statusCode == 200 {
                        let enriched = parseLMStudioV0Models(lmsData)
                        detectedType = .lmStudio
                        if !enriched.models.isEmpty {
                            parsedModels = enriched.models
                            warmIds = enriched.warmIds
                        }
                    }

                    // Enrich Ollama warm-loaded state if Ollama responded via `/v1/models`
                    if detectedType == .ollama {
                        warmIds = await fetchOllamaWarmModels(origin: origin, apiKey: candidate.apiKey, session: session)
                        for i in parsedModels.indices where warmIds.contains(parsedModels[i].id) {
                            parsedModels[i].isWarmLoaded = true
                        }
                    }

                    return DetectedLLMServer(
                        type: detectedType,
                        scheme: candidate.scheme,
                        host: candidate.host,
                        port: candidate.port,
                        apiPathOverride: "/\(customPath)",
                        apiKey: candidate.apiKey,
                        sourceKind: candidate.sourceKind,
                        nodeName: resolvedPeerLabel,
                        requiresAuthToUnlock: false,
                        models: parsedModels,
                        warmModelIds: warmIds,
                        isOnline: true,
                        latency: latency
                    )
                }
            } else if http.statusCode == 401 || http.statusCode == 403 {
                // Surface password/token-protected LAN LM Studio, LiteLLM, vLLM, or MicroCode LLM servers so the user sees them and can pair!
                let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                let bodyText = String(data: data.prefix(1024), encoding: .utf8)?.lowercased() ?? ""
                let knownAuthLLMPorts: Set<Int> = [1234, 1235, 1236, 4000, 8000, 8475, 8476, 11434, 20128]
                if isMicroCodeNode || contentType.contains("application/json") || knownAuthLLMPorts.contains(candidate.port) {
                    let guessedType = Self.fingerprintServerType(
                        port: candidate.port,
                        isMicroCodeNode: isMicroCodeNode,
                        serverHeader: (http.value(forHTTPHeaderField: "Server") ?? "").lowercased(),
                        bodyPreview: bodyText,
                        models: []
                    )
                    return DetectedLLMServer(
                        type: guessedType,
                        scheme: candidate.scheme,
                        host: candidate.host,
                        port: candidate.port,
                        apiPathOverride: "/\(customPath)",
                        apiKey: nil,
                        sourceKind: candidate.sourceKind,
                        nodeName: resolvedPeerLabel ?? (isMicroCodeNode ? "MicroCode Peer" : nil),
                        requiresAuthToUnlock: true,
                        models: [],
                        warmModelIds: [],
                        isOnline: true,
                        latency: latency
                    )
                }
            }
        }

        // C. Fallback: check if non-standard port is actually an Ollama instance (`/api/tags`)
        if candidate.port != 11434 && candidate.port != 11435 {
            if let ollamaServer = await tryProbeOllama(origin: origin, candidate: candidate, session: session, startTime: startTime) {
                return ollamaServer
            }
        }

        // D. Check MicroCode LLM Gateway discovery endpoint (`/v1/gateway-info`)
        if let infoReq = makeRequest("\(origin)/v1/gateway-info"),
           let (infoData, infoRes) = try? await session.data(for: infoReq),
           let http = infoRes as? HTTPURLResponse,
           http.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: infoData) as? [String: Any],
           (json["ok"] as? Bool) == true {
            let node = (json["node"] as? String) ?? candidate.labelHint ?? "MicroCode Node"
            return DetectedLLMServer(
                type: .microcodeNode,
                scheme: candidate.scheme,
                host: candidate.host,
                port: candidate.port,
                apiPathOverride: "/v1",
                apiKey: candidate.apiKey,
                sourceKind: candidate.sourceKind,
                nodeName: node,
                requiresAuthToUnlock: (json["requiresAuth"] as? Bool) ?? true,
                models: [],
                warmModelIds: [],
                isOnline: true,
                latency: Date().timeIntervalSince(startTime)
            )
        }

        return nil
    }

    private func tryProbeOllama(
        origin: String,
        candidate: ProbeCandidate,
        session: URLSession,
        startTime: Date
    ) async -> DetectedLLMServer? {
        guard let url = URL(string: "\(origin)/api/tags") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = (candidate.sourceKind == .thisMac) ? 1.3 : 3.0
        if let key = candidate.apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["models"] != nil else {
            return nil
        }

        let latency = Date().timeIntervalSince(startTime)
        var models = parseOllamaModels(data)
        let warmIds = await fetchOllamaWarmModels(origin: origin, apiKey: candidate.apiKey, session: session)
        for idx in models.indices where warmIds.contains(models[idx].id) {
            models[idx].isWarmLoaded = true
        }
        // Float warm models to the top
        models.sort { a, b in
            if a.isWarmLoaded != b.isWarmLoaded { return a.isWarmLoaded }
            return false
        }

        let isMicroCodeNode = http.value(forHTTPHeaderField: "X-MicroCode-LLM") == "1"
        let remoteNodeName = http.value(forHTTPHeaderField: "X-MicroCode-Node") ?? candidate.labelHint
        return DetectedLLMServer(
            type: isMicroCodeNode ? .microcodeNode : .ollama,
            scheme: candidate.scheme,
            host: candidate.host,
            port: candidate.port,
            apiPathOverride: "/v1",
            apiKey: candidate.apiKey,
            sourceKind: candidate.sourceKind,
            nodeName: remoteNodeName,
            requiresAuthToUnlock: false,
            models: models,
            warmModelIds: warmIds,
            isOnline: true,
            latency: latency
        )
    }

    private func fetchOllamaWarmModels(origin: String, apiKey: String?, session: URLSession) async -> Set<String> {
        guard let url = URL(string: "\(origin)/api/ps") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.0
        if let key = apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, res) = try? await session.data(for: req),
              (res as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["models"] as? [[String: Any]] else {
            return []
        }
        var warm = Set<String>()
        for item in arr {
            if let name = item["name"] as? String { warm.insert(name) }
            if let model = item["model"] as? String { warm.insert(model) }
        }
        return warm
    }

    nonisolated private static func fingerprintServerType(
        port: Int,
        isMicroCodeNode: Bool,
        serverHeader: String,
        bodyPreview: String,
        models: [LocalLLMModel]
    ) -> LocalLLMServerType {
        if isMicroCodeNode || port == 8475 || port == 8476 { return .microcodeNode }
        if port == 20128 || bodyPreview.contains("9router") { return .nineRouter }
        if port == 4000 || serverHeader.contains("litellm") || bodyPreview.contains("litellm") { return .liteLLM }
        if port == 11434 || port == 11435 || serverHeader.contains("ollama") || bodyPreview.contains("\"owned_by\":\"library\"") { return .ollama }
        if serverHeader.contains("llama.cpp") || bodyPreview.contains("llama.cpp") || bodyPreview.contains("llamacpp") { return .llamaCpp }
        if bodyPreview.contains("\"owned_by\":\"vllm\"") || port == 30000 || (port == 8000 && serverHeader.contains("uvicorn")) { return .vllm }
        if models.contains(where: { $0.id.lowercased().contains("mlx-community") || $0.id.lowercased().contains("mlx") }) || port == 10240 {
            return .mlx
        }
        if port == 1234 || port == 1235 || port == 1236 || bodyPreview.contains("organization_owner") || bodyPreview.contains("lmstudio") {
            return .lmStudio
        }
        if port == 1337 || port == 1338 || bodyPreview.contains("jan") { return .jan }
        if port == 7860 || port == 5000 || port == 5001 { return .textGenWebUI }
        if bodyPreview.contains("localai") { return .localAI }
        if port == 8080 || port == 8081 { return .llamaCpp }
        return .custom
    }

    // MARK: - Best Perf Scoring & Real Streaming `tok/s` Benchmark

    nonisolated static func computePerformanceScore(for server: DetectedLLMServer) -> Int {
        guard server.isOnline, !server.requiresAuthToUnlock else { return 0 }
        var score = 40

        // 1. Measured real throughput (`tok/s`) dominates when benchmarked!
        if let tps = server.tokensPerSecond, tps > 0 {
            score += min(38, Int((tps * 0.55).rounded()))
        } else {
            score += server.type.enginePerfBonus
        }

        // 2. Network / Memory bus latency score (up to +18)
        let ms = server.latency * 1000.0
        if ms <= 4 { score += 18 }
        else if ms <= 12 { score += 15 }
        else if ms <= 30 { score += 12 }
        else if ms <= 80 { score += 8 }
        else if ms <= 200 { score += 4 }

        // 3. Warm VRAM-loaded model readiness (+8) & non-empty model catalog (+6)
        if !server.warmModelIds.isEmpty || server.models.contains(where: \.isWarmLoaded) {
            score += 8
        }
        if !server.models.isEmpty {
            score += 6
        }

        return min(100, max(1, score))
    }

    func benchmarkAllServers() async {
        guard !isBenchmarking else { return }
        isBenchmarking = true
        defer {
            isBenchmarking = false
            benchmarkingServerID = nil
        }

        let targetIDs = detectedServers
            .filter { $0.isOnline && !$0.requiresAuthToUnlock && !$0.models.isEmpty }
            .map(\.id)

        for id in targetIDs {
            await performSingleBenchmark(serverID: id)
        }

        recomputeBestPerfRankings()
    }

    func benchmarkServer(_ serverID: UUID) async {
        guard !isBenchmarking else { return }
        isBenchmarking = true
        defer {
            isBenchmarking = false
            benchmarkingServerID = nil
        }
        await performSingleBenchmark(serverID: serverID)
        recomputeBestPerfRankings()
    }

    private func performSingleBenchmark(serverID: UUID) async {
        guard let idx = detectedServers.firstIndex(where: { $0.id == serverID }) else { return }
        let server = detectedServers[idx]
        guard let modelToTest = server.models.first(where: \.isWarmLoaded)?.id ?? server.models.first?.id else { return }

        benchmarkingServerID = serverID
        guard let chatURL = URL(string: "\(server.endpoint)/chat/completions") else { return }

        var req = URLRequest(url: chatURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = server.apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "model": modelToTest,
            "messages": [["role": "user", "content": "Count from 1 to 12 separated by spaces only."]],
            "max_tokens": 20,
            "temperature": 0.0,
            "stream": true
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let t0 = CFAbsoluteTimeGetCurrent()
        var firstTokenTime: CFAbsoluteTime? = nil
        var chunkCount = 0
        var generatedChars = 0

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }

            for try await line in bytes.lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("data:") else { continue }
                let jsonStr = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if jsonStr == "[DONE]" { break }
                guard let data = jsonStr.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = obj["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any] else { continue }

                let content = (delta["content"] as? String) ?? (delta["reasoning_content"] as? String) ?? ""
                if !content.isEmpty {
                    if firstTokenTime == nil {
                        firstTokenTime = CFAbsoluteTimeGetCurrent()
                    }
                    chunkCount += 1
                    generatedChars += content.count
                }
            }

            let tEnd = CFAbsoluteTimeGetCurrent()
            if let tFirst = firstTokenTime {
                let ttft = max(1, Int(((tFirst - t0) * 1000.0).rounded()))
                let genDuration = max(0.015, tEnd - tFirst)
                let approxTokens = max(Double(chunkCount), Double(generatedChars) / 3.8)
                let tps = (approxTokens / genDuration * 10.0).rounded() / 10.0

                if let liveIdx = detectedServers.firstIndex(where: { $0.id == serverID }) {
                    detectedServers[liveIdx].ttftMs = ttft
                    detectedServers[liveIdx].tokensPerSecond = tps
                    detectedServers[liveIdx].perfScore = Self.computePerformanceScore(for: detectedServers[liveIdx])
                    measuredPerfCache[detectedServers[liveIdx].deduplicationKey] = (tps: tps, ttftMs: ttft)
                    scanLog.append("⚡ \(detectedServers[liveIdx].displayName): \(tps) tok/s (TTFT \(ttft) ms)")
                }
            }
        } catch {
            scanLog.append("⚠️ Benchmark skipped for \(server.displayName): \(error.localizedDescription)")
        }
    }

    private func recomputeBestPerfRankings() {
        let currentEndpoint = activeServer?.endpoint
        for i in detectedServers.indices {
            detectedServers[i].isBestPerf = false
            detectedServers[i].perfScore = Self.computePerformanceScore(for: detectedServers[i])
        }
        detectedServers.sort { a, b in
            if a.isOnline != b.isOnline { return a.isOnline && !b.isOnline }
            if a.requiresAuthToUnlock != b.requiresAuthToUnlock { return !a.requiresAuthToUnlock }
            if a.perfScore != b.perfScore { return a.perfScore > b.perfScore }
            return a.latency < b.latency
        }
        if let bestIdx = detectedServers.firstIndex(where: { $0.isOnline && !$0.requiresAuthToUnlock }) {
            detectedServers[bestIdx].isBestPerf = true
            if autoSelectBestPerf {
                selectServer(at: bestIdx)
                return
            }
        }
        if let currentEndpoint, let preserved = detectedServers.firstIndex(where: { $0.endpoint == currentEndpoint }) {
            selectedServerIndex = preserved
        }
    }

    // MARK: - Worldwide QR Code & Smart Human Input Pairing Client

    /// Accepts ANY human input without forcing rigid syntax:
    /// - Port only (`1235`, `:1235`, `1235/v1`) -> `127.0.0.1:1235`
    /// - Bare IP or hostname (`192.168.1.50`, `mac-studio.local`) -> auto-probes all LLM ports on that machine!
    /// - `Host:Port` (`192.168.1.50:1234`, `127.0.0.1:1235/v1`)
    /// - Full URL or QR Pairing Link (`https://xxx.trycloudflare.com/?token=sk-mc-...`, `microcode://llm-connect?...`)
    @discardableResult
    func connectOrPairEndpoint(_ rawInput: String, explicitAPIKey: String? = nil) async -> Bool {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Case A: Bare port or `:port[/path]` (e.g. "1235", ":1235", "1235/v1")
        // -> Check 127.0.0.1:<port> first; if not local, sweep the entire Wi-Fi LAN for `<any-LAN-IP>:<port>`!
        let strippedLeadingColon = trimmed.hasPrefix(":") ? String(trimmed.dropFirst()) : trimmed
        let portDigits = strippedLeadingColon.prefix(while: { $0.isNumber })
        let afterDigits = strippedLeadingColon.dropFirst(portDigits.count)
        if !portDigits.isEmpty,
           (afterDigits.isEmpty || afterDigits.hasPrefix("/")),
           let p = Int(portDigits), p > 0, p <= 65535 {
            let apiPath = afterDigits.isEmpty ? "/v1" : String(afterDigits)
            let cleanKey = (explicitAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? explicitAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil

            // 1) Try This Mac first
            let localSpec = FlexibleLLMEndpointSpec(
                scheme: "http",
                host: "127.0.0.1",
                port: p,
                apiPath: apiPath,
                apiKey: cleanKey,
                label: nil
            )
            if await connectSingleResolvedSpec(localSpec) {
                return true
            }

            // 2) Sweep entire Wi-Fi LAN + ARP/Tailscale peers for port `p`!
            pairingStatusMessage = "Scanning Wi-Fi LAN for port \(String(p))…"
            let topology = await Task.detached(priority: .userInitiated) { Self.discoverNetworkTopology() }.value
            let ownIPs = Set(topology.ownIPs + ["127.0.0.1", "localhost", "::1"])
            var neighbors = topology.arpNeighbors.subtracting(ownIPs)
            neighbors.formUnion(topology.tailscalePeers.subtracting(ownIPs))

            let openLANHosts = await Task.detached(priority: .userInitiated) {
                Self.sweepOpenLANEndpoints(
                    priorityHosts: Array(neighbors),
                    priorityPorts: [p],
                    subnetPrefixes: Array(topology.lanSubnetPrefixes.prefix(1)),
                    subnetPorts: [p],
                    excludingHosts: ownIPs
                )
            }.value

            for hit in openLANHosts {
                let lanSpec = FlexibleLLMEndpointSpec(
                    scheme: "http",
                    host: hit.host,
                    port: p,
                    apiPath: apiPath,
                    apiKey: cleanKey,
                    label: bonjourPeerMachines[hit.host]
                )
                if await connectSingleResolvedSpec(lanSpec) {
                    return true
                }
            }

            let subnetHint = topology.lanSubnetPrefixes.first.map { "\($0).x" } ?? "LAN"
            pairingStatusMessage = "Port \(String(p)) is closed/blocked on This Mac and \(subnetHint) — turn ON 'Serve on Local Network' & allow Firewall on that laptop."
            return false
        }

        // Case B: Explicit URL, Deep Link, or Host:Port
        if let spec = Self.parseFlexibleEndpoint(hostInput: trimmed, explicitAPIKey: explicitAPIKey) {
            return await connectSingleResolvedSpec(spec)
        }

        // Case C: Bare IP address or Hostname without port (e.g. `192.168.1.50` or `mac-studio.local` or `192.168.1.50/v1`)
        let cleanHostOnly = trimmed
            .components(separatedBy: "/").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let looksLikeHost = !cleanHostOnly.isEmpty && !cleanHostOnly.contains(" ") && (cleanHostOnly.contains(".") || cleanHostOnly.lowercased() == "localhost" || cleanHostOnly.contains("-"))
        guard looksLikeHost else {
            pairingStatusMessage = "Enter an IP (e.g. 192.168.1.50), port (1234), or QR link."
            return false
        }

        pairingStatusMessage = "Scanning \(cleanHostOnly)…"
        let ownGatewayPort: Int = LocalLLMGatewayService.shared.isServerRunning
            ? Int(LocalLLMGatewayService.shared.listeningPort)
            : -1
        let topology = await Task.detached(priority: .userInitiated) { Self.discoverNetworkTopology() }.value
        let ownIPs = Set(topology.ownIPs + ["127.0.0.1", "localhost", "::1"])
        let isThisMac = ownIPs.contains(cleanHostOnly)
        let candidatePorts = [1234, 1235, 1236, 11434, 11435, 8000, 8080, 8081, 8475, 8476, 4000, 1337, 5000, 7860, 10240, 20128, 30000]
            .filter { !(isThisMac && ownGatewayPort > 0 && $0 == ownGatewayPort) }
        let cleanKey = (explicitAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? explicitAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let labelHint = bonjourPeerMachines[cleanHostOnly]

        var foundOnHost: [DetectedLLMServer] = []
        await withTaskGroup(of: DetectedLLMServer?.self) { group in
            for port in candidatePorts {
                let cand = ProbeCandidate(
                    scheme: "http",
                    host: cleanHostOnly,
                    port: port,
                    apiPath: "/v1",
                    apiKey: cleanKey,
                    sourceKind: isThisMac ? .thisMac : (cleanHostOnly.hasPrefix("100.") ? .tailscale : .lan),
                    labelHint: labelHint
                )
                group.addTask { [weak self] in
                    await self?.probeSmartCandidate(cand)
                }
            }
            for await res in group {
                if var srv = res {
                    srv.perfScore = Self.computePerformanceScore(for: srv)
                    foundOnHost.append(srv)
                }
            }
        }

        guard !foundOnHost.isEmpty else {
            pairingStatusMessage = isThisMac
                ? "No running LLM server on this Mac (\(cleanHostOnly)). Start LM Studio or Ollama first."
                : "No LLM server responding at \(cleanHostOnly). Enable \"Serve on Local Network\" on that machine."
            return false
        }

        foundOnHost.sort { $0.perfScore > $1.perfScore }
        for srv in foundOnHost {
            Self.registerEndpointAPIKey(endpoint: srv.endpoint, apiKey: srv.apiKey)
            if !isThisMac && !srv.requiresAuthToUnlock {
                let entry = PairedLLMEndpoint(
                    label: srv.displayName,
                    scheme: srv.scheme,
                    host: srv.host,
                    port: srv.port,
                    apiPath: srv.effectiveApiPath,
                    apiKey: srv.apiKey,
                    isWorldwideTunnel: false,
                    addedAt: Date()
                )
                pairedRemoteEndpoints.removeAll { $0.normalizedKey == entry.normalizedKey }
                pairedRemoteEndpoints.insert(entry, at: 0)
            }
            if let existingIdx = detectedServers.firstIndex(where: { $0.deduplicationKey == srv.deduplicationKey }) {
                detectedServers[existingIdx] = srv
            } else {
                detectedServers.insert(srv, at: 0)
            }
        }
        savePairedEndpoints()
        recomputeBestPerfRankings()
        if let best = foundOnHost.first,
           let activeIdx = detectedServers.firstIndex(where: { $0.deduplicationKey == best.deduplicationKey }) {
            selectServer(at: activeIdx)
        }
        AIModelCatalog.shared.integrateLocalModels()
        let primary = foundOnHost.first!
        if primary.requiresAuthToUnlock {
            pairingStatusMessage = "Found \(primary.displayName) — token required to unlock."
            return false
        }
        pairingStatusMessage = "Connected to \(primary.displayName)"
        return true
    }

    private func connectSingleResolvedSpec(_ spec: FlexibleLLMEndpointSpec) async -> Bool {
        let ownGatewayPort: Int = LocalLLMGatewayService.shared.isServerRunning
            ? Int(LocalLLMGatewayService.shared.listeningPort)
            : -1
        let topology = await Task.detached(priority: .userInitiated) { Self.discoverNetworkTopology() }.value
        let ownIPs = Set(topology.ownIPs + ["127.0.0.1", "localhost", "::1"])
        if ownGatewayPort > 0 && spec.port == ownGatewayPort && ownIPs.contains(spec.host) {
            pairingStatusMessage = "Port \(String(spec.port)) is this Mac's own Remote QR Access port."
            return false
        }

        pairingStatusMessage = "Connecting to \(spec.host):\(String(spec.port))…"
        let isTunnel = spec.scheme == "https" || spec.host.contains(".trycloudflare.com") || spec.host.contains(".lhr.life")
        let isThisMac = ownIPs.contains(spec.host)
        let candidate = ProbeCandidate(
            scheme: spec.scheme,
            host: spec.host,
            port: spec.port,
            apiPath: spec.apiPath,
            apiKey: spec.apiKey,
            sourceKind: isTunnel ? .worldwideQR : (isThisMac ? .thisMac : .lan),
            labelHint: spec.label ?? bonjourPeerMachines[spec.host]
        )

        guard var probed = await probeSmartCandidate(candidate) else {
            pairingStatusMessage = "No LLM server responding at \(spec.host):\(String(spec.port))"
            return false
        }
        if probed.requiresAuthToUnlock {
            if let existingIdx = detectedServers.firstIndex(where: { $0.deduplicationKey == probed.deduplicationKey }) {
                detectedServers[existingIdx] = probed
            } else {
                detectedServers.insert(probed, at: 0)
            }
            pairingStatusMessage = "Token required for \(probed.displayName)"
            return false
        }

        probed.perfScore = Self.computePerformanceScore(for: probed)
        Self.registerEndpointAPIKey(endpoint: probed.endpoint, apiKey: probed.apiKey)

        if !isThisMac {
            let entry = PairedLLMEndpoint(
                label: spec.label ?? probed.displayName,
                scheme: spec.scheme,
                host: spec.host,
                port: spec.port,
                apiPath: spec.apiPath,
                apiKey: spec.apiKey,
                isWorldwideTunnel: isTunnel,
                addedAt: Date()
            )
            pairedRemoteEndpoints.removeAll { $0.normalizedKey == entry.normalizedKey }
            pairedRemoteEndpoints.insert(entry, at: 0)
            savePairedEndpoints()
        } else {
            customHost = spec.host
            customPort = String(spec.port)
        }

        if let existingIdx = detectedServers.firstIndex(where: { $0.deduplicationKey == probed.deduplicationKey }) {
            detectedServers[existingIdx] = probed
            selectServer(at: existingIdx)
        } else {
            detectedServers.insert(probed, at: 0)
            selectServer(at: 0)
        }

        recomputeBestPerfRankings()
        if let activeIdx = detectedServers.firstIndex(where: { $0.deduplicationKey == probed.deduplicationKey }) {
            selectServer(at: activeIdx)
        }
        AIModelCatalog.shared.integrateLocalModels()
        pairingStatusMessage = "Connected to \(probed.displayName)"
        return true
    }

    @discardableResult
    func pairFromQRImage(_ image: NSImage) async -> Bool {
        guard let decoded = Self.decodeQRCodeString(from: image) else {
            pairingStatusMessage = "ไม่พบ QR Code ในรูปภาพนี้"
            return false
        }
        quickConnectInput = decoded
        return await connectOrPairEndpoint(decoded)
    }

    @discardableResult
    func pairFromClipboard() async -> Bool {
        let pb = NSPasteboard.general
        if let img = NSImage(pasteboard: pb), let qrText = Self.decodeQRCodeString(from: img) {
            quickConnectInput = qrText
            return await connectOrPairEndpoint(qrText)
        }
        if let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
            quickConnectInput = str
            return await connectOrPairEndpoint(str, explicitAPIKey: quickConnectAPIKey)
        }
        pairingStatusMessage = "ไม่พบลิงก์หรือรูป QR Code ใน Clipboard"
        return false
    }

    func removePairedEndpoint(_ key: String) {
        let lowerKey = key.lowercased()
        pairedRemoteEndpoints.removeAll { item in
            let dedup = "\(item.scheme.lowercased())://\(item.host.lowercased()):\(item.port)"
            return item.normalizedKey.lowercased() == lowerKey || dedup == lowerKey
        }
        savePairedEndpoints()
        detectedServers.removeAll { $0.deduplicationKey.lowercased() == lowerKey }
        if selectedServerIndex >= detectedServers.count {
            selectedServerIndex = max(0, detectedServers.count - 1)
        }
    }

    nonisolated static func decodeQRCodeString(from image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let ciImage = CIImage(data: tiff) else { return nil }
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: ciImage) ?? []
        for feature in features {
            if let qr = feature as? CIQRCodeFeature, let msg = qr.messageString, !msg.isEmpty {
                return msg.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func loadPairedEndpoints() {
        guard let data = UserDefaults.standard.data(forKey: Self.pairedEndpointsDefaultsKey),
              let decoded = try? JSONDecoder().decode([PairedLLMEndpoint].self, from: data) else { return }
        pairedRemoteEndpoints = decoded
        for item in decoded {
            Self.registerEndpointAPIKey(endpoint: item.baseURLString, apiKey: item.apiKey)
        }
    }

    private func savePairedEndpoints() {
        if let data = try? JSONEncoder().encode(pairedRemoteEndpoints) {
            UserDefaults.standard.set(data, forKey: Self.pairedEndpointsDefaultsKey)
        }
    }

    // MARK: - Low-Level Network & Local Socket Topology Discovery

    private struct NetworkTopologySnapshot {
        var ownIPs: [String]
        var lanSubnetPrefixes: [String]
        var primaryLANDisplay: String?
        var arpNeighbors: Set<String>
        var tailscalePeers: Set<String>
    }

    nonisolated private static func resolveReverseHostLabel(for ip: String) -> String? {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        guard ip.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else { return nil }
        var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let res = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &hostBuf, socklen_t(hostBuf.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard res == 0 else { return nil }
        let name = String(cString: hostBuf)
            .replacingOccurrences(of: ".local", with: "")
            .replacingOccurrences(of: ".lan", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ip else { return nil }
        return name
    }

    nonisolated private static func discoverNetworkTopology() -> NetworkTopologySnapshot {
        var ownIPs: [String] = []
        var rankedSubnets: [(rank: Int, prefix: String, display: String)] = []
        var tailscalePeers = Set<String>()

        func interfacePriority(_ name: String) -> Int {
            if name == "en0" { return 0 }
            if name == "en1" { return 1 }
            if name.hasPrefix("en") { return 2 }
            if name.hasPrefix("bridge") { return 10 }
            return 20
        }

        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        if getifaddrs(&ifaddr) == 0, let first = ifaddr {
            var ptr: UnsafeMutablePointer<ifaddrs>? = first
            while let current = ptr {
                let flags = Int32(current.pointee.ifa_flags)
                let isUp = (flags & IFF_UP) != 0
                let isLoopback = (flags & IFF_LOOPBACK) != 0
                if isUp && !isLoopback, let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                    let name = String(cString: current.pointee.ifa_name)
                    var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostBuf, socklen_t(hostBuf.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostBuf)
                        if !ip.isEmpty {
                            ownIPs.append(ip)
                            let octets = ip.split(separator: ".")
                            if octets.count == 4,
                               name.hasPrefix("en"),
                               (ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.")) {
                                let prefix = "\(octets[0]).\(octets[1]).\(octets[2])"
                                rankedSubnets.append((
                                    rank: interfacePriority(name),
                                    prefix: prefix,
                                    display: "\(ip)/24 (\(name))"
                                ))
                            }
                        }
                    }
                }
                ptr = current.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }

        rankedSubnets.sort { $0.rank < $1.rank }
        var subnetPrefixes: [String] = []
        for item in rankedSubnets where !subnetPrefixes.contains(item.prefix) {
            subnetPrefixes.append(item.prefix)
        }
        let primaryLANDisplay = rankedSubnets.first?.display

        // Read live ARP table (`/usr/sbin/arp -an`) for instant Wi-Fi, Ethernet, Hotspot & Thunderbolt Bridge neighbors
        var arpNeighbors = Set<String>()
        if let arpOutput = runQuickProcess("/usr/sbin/arp", ["-an"]) {
            let pattern = #"\((\d{1,3}(?:\.\d{1,3}){3})\)\s+at\s+([0-9a-fA-F:]+)"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let ns = arpOutput as NSString
                for m in regex.matches(in: arpOutput, range: NSRange(location: 0, length: ns.length)) {
                    let ip = ns.substring(with: m.range(at: 1))
                    if !ip.hasPrefix("224.") && !ip.hasPrefix("239.") && !ip.hasSuffix(".255") && ip != "169.254.169.254" {
                        arpNeighbors.insert(ip)
                    }
                }
            }
        }

        // Optional Tailscale peer IPs if Tailscale CLI is installed
        for tsBin in ["/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale", "/Applications/Tailscale.app/Contents/MacOS/Tailscale"] {
            if FileManager.default.isExecutableFile(atPath: tsBin),
               let tsOut = runQuickProcess(tsBin, ["status", "--json"]),
               let data = tsOut.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let peers = json["Peer"] as? [String: [String: Any]] {
                for (_, peerInfo) in peers {
                    if (peerInfo["Online"] as? Bool) == true,
                       let ips = peerInfo["TailscaleIPs"] as? [String] {
                        for ip in ips where ip.contains(".") {
                            tailscalePeers.insert(ip)
                        }
                    }
                }
                break
            }
        }

        return NetworkTopologySnapshot(
            ownIPs: ownIPs,
            lanSubnetPrefixes: subnetPrefixes,
            primaryLANDisplay: primaryLANDisplay,
            arpNeighbors: arpNeighbors,
            tailscalePeers: tailscalePeers
        )
    }

    /// Inspects active listening TCP sockets on this Mac so custom LM Studio / MLX / llama.cpp / vLLM ports are auto-detected.
    nonisolated private static func discoverCandidateLocalListeningPorts(excludingPort: Int) -> [Int] {
        guard let out = runQuickProcess("/usr/sbin/lsof", ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "-F", "cn"]) else {
            return []
        }
        let ignoredCommands: Set<String> = [
            "microcode", "controlce", "rapportd", "ardagent", "mongod", "redis-ser",
            "postgres", "adb", "qemu-syst", "netsimd", "antigravi", "language_",
            "cloudflar", "mdnsrespo", "cupsd", "Dropbox", "spotify"
        ]
        let likelyLLMCommands = [
            "ollama", "lm studio", "lms", "llama", "mlx", "vllm", "python", "python3",
            "uvicorn", "litellm", "jan", "local-ai", "kobold", "9router", "sglang", "tabby"
        ]

        var currentCommand = ""
        var discoveredPorts = Set<Int>()
        for line in out.split(separator: "\n") {
            if line.hasPrefix("c") {
                currentCommand = String(line.dropFirst()).lowercased()
            } else if line.hasPrefix("n") {
                if ignoredCommands.contains(where: { currentCommand.hasPrefix($0) }) { continue }
                guard likelyLLMCommands.contains(where: { currentCommand.contains($0) }) else { continue }
                if let colonIdx = line.lastIndex(of: ":") {
                    let portStr = line[line.index(after: colonIdx)...]
                    if let port = Int(portStr), port >= 1024, port <= 65535, port != excludingPort {
                        discoveredPorts.insert(port)
                    }
                }
            }
        }
        return Array(discoveredPorts).sorted()
    }

    nonisolated private static func runQuickProcess(_ path: String, _ args: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Ultra-fast non-blocking POSIX TCP connect check (zero URLSession overhead, zero leaked FDs).
    nonisolated private static func isTCPPortOpen(host: String, port: Int, timeoutMs: Int32) -> Bool {
        let resolvedHost = (host == "localhost") ? "127.0.0.1" : host
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        guard resolvedHost.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else {
            // Hostname (e.g. Bonjour .local) — let HTTP layer handle DNS resolution
            return true
        }

        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        let flags = Darwin.fcntl(fd, F_GETFL, 0)
        _ = Darwin.fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let connectRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connectRes == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let pollRes = Darwin.poll(&pfd, 1, timeoutMs)
        guard pollRes > 0, (pfd.revents & Int16(POLLOUT)) != 0 else { return false }

        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        guard Darwin.getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len) == 0 else { return false }
        return soError == 0
    }

    nonisolated private static func sweepOpenLANEndpoints(
        priorityHosts: [String],
        priorityPorts: [Int],
        subnetPrefixes: [String],
        subnetPorts: [Int],
        excludingHosts: Set<String>
    ) -> [(host: String, port: Int)] {
        var targets: [(host: String, port: Int, timeoutMs: Int32)] = []
        var seen = Set<String>()

        for host in priorityHosts where !excludingHosts.contains(host) {
            for port in priorityPorts {
                let key = "\(host):\(port)"
                if seen.insert(key).inserted {
                    targets.append((host, port, 900))
                }
            }
        }

        for prefix in subnetPrefixes {
            for lastOctet in 1...254 {
                let ip = "\(prefix).\(lastOctet)"
                if excludingHosts.contains(ip) { continue }
                for port in subnetPorts {
                    let key = "\(ip):\(port)"
                    if seen.insert(key).inserted {
                        targets.append((ip, port, 320))
                    }
                }
            }
        }

        guard !targets.isEmpty else { return [] }

        let lock = NSLock()
        var openHits: [(host: String, port: Int)] = []
        let queue = OperationQueue()
        queue.name = "com.dotmini.microcode.lan-llm-sweep"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 190

        for item in targets {
            queue.addOperation {
                if isTCPPortOpen(host: item.host, port: item.port, timeoutMs: item.timeoutMs) {
                    lock.lock()
                    openHits.append((item.host, item.port))
                    lock.unlock()
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        return openHits
    }

    // MARK: - Live Model Hub Fetching (Hugging Face API + Ollama Library + Installed)

    func fetchHubModels(source: ModelHubSource, query: String = "", category: String = "All") async {
        hubFetchGeneration += 1
        let gen = hubFetchGeneration
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if source == .installed {
            isFetchingHub = true
            hubErrorMessage = nil
            let items = await buildInstalledHubModels(filterQuery: trimmedQuery)
            guard gen == hubFetchGeneration else { return }
            hubModels = items
            isFetchingHub = false
            return
        }

        isFetchingHub = true
        hubErrorMessage = nil

        do {
            let fetched: [HubModelItem]
            switch source {
            case .mlx:
                fetched = try await fetchHuggingFaceHubModels(source: .mlx, query: trimmedQuery, category: category)
            case .gguf:
                fetched = try await fetchHuggingFaceHubModels(source: .gguf, query: trimmedQuery, category: category)
            case .ollama:
                fetched = try await fetchOllamaLibraryModels(query: trimmedQuery, category: category)
            case .installed:
                fetched = []
            }
            guard gen == hubFetchGeneration else { return }
            hubModels = fetched
            isFetchingHub = false
        } catch {
            guard gen == hubFetchGeneration else { return }
            isFetchingHub = false
            hubErrorMessage = "Failed to fetch live catalog: \(error.localizedDescription)"
        }
    }

    private func fetchHuggingFaceHubModels(source: ModelHubSource, query: String, category: String) async throws -> [HubModelItem] {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        let filterTag = (source == .mlx) ? "mlx" : "gguf"

        var searchTerms: [String] = []
        if !query.isEmpty { searchTerms.append(query) }
        switch category {
        case "Code": searchTerms.append("coder")
        case "Reasoning": searchTerms.append("r1")
        case "Vision": searchTerms.append("vl")
        case "Tools": searchTerms.append("instruct")
        default: break
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "filter", value: filterTag),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "45")
        ]
        if !searchTerms.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: searchTerms.joined(separator: " ")))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("MicroCode/2.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.badServerResponse)
        }

        let excludedPipelines: Set<String> = [
            "automatic-speech-recognition", "text-to-speech", "text-to-image",
            "audio-to-audio", "voice-activity-detection", "zero-shot-image-classification",
            "image-to-image", "text-to-audio", "text-to-video"
        ]
        let excludedSubstrings = [
            "whisper", "kokoro", "parakeet", "flux", "sdxl", "stable-diffusion",
            "-tts", "tts-", "bark", "encodec", "cosyvoice", "f5-tts", "yue"
        ]

        var results: [HubModelItem] = []
        for obj in arr {
            guard let repoId = obj["id"] as? String else { continue }
            let lowerId = repoId.lowercased()
            let pipeline = (obj["pipeline_tag"] as? String)?.lowercased() ?? ""

            if query.isEmpty {
                if excludedPipelines.contains(pipeline) { continue }
                if excludedSubstrings.contains(where: { lowerId.contains($0) }) { continue }
            }

            let parts = repoId.split(separator: "/", maxSplits: 1).map(String.init)
            let author = parts.count > 1 ? parts[0] : (source == .mlx ? "mlx-community" : "huggingface")
            let rawName = parts.count > 1 ? parts[1] : repoId

            let downloads = (obj["downloads"] as? Int) ?? 0
            let likes = (obj["likes"] as? Int) ?? 0
            let tags = (obj["tags"] as? [String]) ?? []
            let createdOrMod = (obj["lastModified"] as? String) ?? (obj["createdAt"] as? String) ?? ""

            var caps: [String] = []
            if lowerId.contains("coder") || lowerId.contains("code") || lowerId.contains("devstral") || lowerId.contains("starcoder") {
                caps.append("Code")
            }
            if lowerId.contains("r1") || lowerId.contains("qwq") || lowerId.contains("thinking") || lowerId.contains("qwen3") || lowerId.contains("reason") {
                caps.append("Thinking")
            }
            if pipeline == "image-text-to-text" || lowerId.contains("-vl") || lowerId.contains("vision") || tags.contains("image-text-to-text") {
                caps.append("Vision")
            }
            if lowerId.contains("instruct") || lowerId.contains("qwen") || lowerId.contains("llama") || lowerId.contains("gemma") || lowerId.contains("mistral") {
                caps.append("Tools")
            }
            if category == "Vision" && !caps.contains("Vision") { continue }
            if category == "Code" && !caps.contains("Code") { continue }
            if category == "Reasoning" && !caps.contains("Thinking") { continue }

            var paramSizes: [String] = []
            if let p = extractSize(from: rawName) {
                paramSizes.append(p)
            }
            let quant = extractQuantization(from: rawName)
            let estBytes = estimateBytesFromParamsAndQuant(paramString: paramSizes.first, quant: quant, isMLX: source == .mlx)

            let localMLXDir = mlxLocalDirectory(for: repoId)
            let isMLXOnDisk = (source == .mlx) && FileManager.default.fileExists(atPath: localMLXDir.appendingPathComponent("config.json").path)

            let defaultVariant = HubModelVariant(
                id: repoId,
                label: quant.map { "\(rawName) (\($0))" } ?? rawName,
                filenames: [],
                sizeBytes: estBytes,
                quantization: quant ?? (source == .mlx ? "MLX" : "GGUF"),
                contextWindow: nil,
                isDownloadedOnDisk: isMLXOnDisk
            )

            let summaryText: String
            if source == .mlx {
                summaryText = "Apple Silicon MLX model from \(author). Runs natively on Metal Unified Memory via mlx_lm.server with OpenAI-compatible /v1 API."
            } else {
                summaryText = "GGUF quantized weights published by \(author). Compatible with LM Studio, Ollama, and llama.cpp."
            }

            results.append(
                HubModelItem(
                    id: "\(source.rawValue):\(repoId)",
                    source: source,
                    repoOrSlug: repoId,
                    displayName: rawName,
                    author: author,
                    summary: summaryText,
                    downloadsCount: downloads,
                    likesCount: likes,
                    updatedLabel: relativeDateLabel(fromISO: createdOrMod),
                    capabilities: caps,
                    parameterSizes: paramSizes,
                    estimatedSizeBytes: estBytes,
                    variants: [defaultVariant],
                    detailsLoaded: false,
                    localDiskPath: isMLXOnDisk ? localMLXDir.path : nil
                )
            )
        }
        return results
    }

    private func fetchOllamaLibraryModels(query: String, category: String) async throws -> [HubModelItem] {
        var urlsToFetch: [URL] = []
        let catParam: String? = {
            switch category {
            case "Tools": return "tools"
            case "Reasoning": return "thinking"
            case "Vision": return "vision"
            default: return nil
            }
        }()

        let effectiveQuery = (category == "Code" && query.isEmpty) ? "coder" : query
        var primary = URLComponents(string: "https://ollama.com/search")!
        var qItems: [URLQueryItem] = []
        if !effectiveQuery.isEmpty { qItems.append(URLQueryItem(name: "q", value: effectiveQuery)) }
        if let catParam { qItems.append(URLQueryItem(name: "c", value: catParam)) }
        if !qItems.isEmpty { primary.queryItems = qItems }
        if let u = primary.url { urlsToFetch.append(u) }

        // Also fetch tools-capable popular local models when browsing default root so local models outrank cloud-only headers
        if effectiveQuery.isEmpty && catParam == nil,
           let toolsURL = URL(string: "https://ollama.com/search?c=tools") {
            urlsToFetch.append(toolsURL)
        }

        var mergedBySlug: [String: HubModelItem] = [:]
        var orderedSlugs: [String] = []

        for url in urlsToFetch {
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0)", forHTTPHeaderField: "User-Agent")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) else { continue }

            let parsed = parseOllamaSearchHTML(html)
            for item in parsed {
                if mergedBySlug[item.repoOrSlug] == nil {
                    mergedBySlug[item.repoOrSlug] = item
                    orderedSlugs.append(item.repoOrSlug)
                }
            }
        }

        var items = orderedSlugs.compactMap { mergedBySlug[$0] }
        if effectiveQuery.isEmpty {
            items.sort { $0.downloadsCount > $1.downloadsCount }
        }
        return items
    }

    private func parseOllamaSearchHTML(_ html: String) -> [HubModelItem] {
        let chunks = html.components(separatedBy: "<a href=\"/library/")
        guard chunks.count > 1 else { return [] }

        var items: [HubModelItem] = []
        var seen = Set<String>()

        for rawChunk in chunks.dropFirst() {
            guard let quoteEnd = rawChunk.firstIndex(of: "\"") else { continue }
            let slug = String(rawChunk[..<quoteEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if slug.isEmpty || slug.contains("/") || slug.contains(":") || slug.contains("?") { continue }
            if seen.contains(slug) { continue }

            let cardSlice: String
            if let closeAnchor = rawChunk.range(of: "</a>") {
                cardSlice = String(rawChunk[..<closeAnchor.lowerBound])
            } else {
                cardSlice = String(rawChunk.prefix(3200))
            }

            // Capabilities
            var caps: [String] = []
            let lowerCard = cardSlice.lowercased()
            let isCloudBadgePresent = lowerCard.contains(">cloud</span>")
            if lowerCard.contains(">tools</span>") { caps.append("Tools") }
            if lowerCard.contains(">thinking</span>") { caps.append("Thinking") }
            if lowerCard.contains(">vision</span>") { caps.append("Vision") }
            if lowerCard.contains(">embedding</span>") { caps.append("Embedding") }
            if slug.lowercased().contains("coder") || slug.lowercased().contains("code") || slug.lowercased().contains("devstral") {
                if !caps.contains("Code") { caps.insert("Code", at: 0) }
            }

            // Downloads count: title="41,882,676 downloads"
            var downloads = 0
            if let dlRange = cardSlice.range(of: "title=\"([0-9,]+) downloads\"", options: .regularExpression) {
                let matched = String(cardSlice[dlRange])
                let digits = matched.filter { $0.isNumber }
                downloads = Int(digits) ?? 0
            }

            // Skip Ollama Cloud-only models (no local downloadable weights)
            if isCloudBadgePresent && downloads == 0 {
                continue
            }

            // Description: <p class="mt-1 line-clamp-2 ...">...</p>
            var summary = ""
            if let pStart = cardSlice.range(of: "<p class=\"mt-1 line-clamp-2"),
               let gt = cardSlice[pStart.upperBound...].firstIndex(of: ">"),
               let pEnd = cardSlice[gt...].range(of: "</p>") {
                let rawDesc = String(cardSlice[cardSlice.index(after: gt)..<pEnd.lowerBound])
                summary = decodeHTMLEntities(stripHTMLTags(rawDesc)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if summary.isEmpty {
                summary = "Official \(slug) model from the Ollama Library."
            }

            // Parameter pills like >0.6b<, >4b<, >8b<, >14b<, >32b<, >70b<
            var paramSizes: [String] = []
            let paramRegex = try? NSRegularExpression(pattern: ">([0-9]+(?:\\.[0-9]+)?x?[0-9]*[bBmM])</span>")
            if let paramRegex {
                let ns = cardSlice as NSString
                for m in paramRegex.matches(in: cardSlice, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges > 1 {
                    let val = ns.substring(with: m.range(at: 1)).uppercased()
                    if !paramSizes.contains(val) { paramSizes.append(val) }
                }
            }

            // Updated relative age: title="Updated ...">1w</span>
            var updated = ""
            if let upRange = cardSlice.range(of: "title=\"Updated [^\"]+\">([^<]+)</span>", options: .regularExpression) {
                let sub = String(cardSlice[upRange])
                if let gt = sub.firstIndex(of: ">"), let lt = sub.lastIndex(of: "<"), gt < lt {
                    updated = String(sub[sub.index(after: gt)..<lt]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            seen.insert(slug)

            var initialVariants: [HubModelVariant] = []
            if paramSizes.isEmpty {
                initialVariants.append(
                    HubModelVariant(
                        id: "\(slug):latest",
                        label: "\(slug):latest",
                        filenames: [],
                        sizeBytes: 0,
                        quantization: nil,
                        contextWindow: nil,
                        isDownloadedOnDisk: isOllamaTagInstalled("\(slug):latest")
                    )
                )
            } else {
                for p in paramSizes.prefix(8) {
                    let tag = "\(slug):\(p.lowercased())"
                    let est = estimateBytesFromParamsAndQuant(paramString: p, quant: "Q4_K_M", isMLX: false)
                    initialVariants.append(
                        HubModelVariant(
                            id: tag,
                            label: tag,
                            filenames: [],
                            sizeBytes: est,
                            quantization: "Q4",
                            contextWindow: nil,
                            isDownloadedOnDisk: isOllamaTagInstalled(tag)
                        )
                    )
                }
            }

            let primaryEst = initialVariants.first?.sizeBytes ?? 0
            items.append(
                HubModelItem(
                    id: "ollama:\(slug)",
                    source: .ollama,
                    repoOrSlug: slug,
                    displayName: slug,
                    author: "Ollama Library",
                    summary: summary,
                    downloadsCount: downloads,
                    likesCount: 0,
                    updatedLabel: updated,
                    capabilities: caps,
                    parameterSizes: paramSizes,
                    estimatedSizeBytes: primaryEst,
                    variants: initialVariants,
                    detailsLoaded: false
                )
            )
        }
        return items
    }

    // MARK: - Live Detail & Exact Variant File Sizes

    func fetchHubModelDetails(itemID: String) async {
        guard let idx = hubModels.firstIndex(where: { $0.id == itemID }) else { return }
        if hubModels[idx].detailsLoaded || hubModels[idx].source == .installed { return }

        let item = hubModels[idx]
        isFetchingHubDetail = true
        defer { isFetchingHubDetail = false }

        switch item.source {
        case .mlx, .gguf:
            await fetchHuggingFaceRepoDetails(item: item)
        case .ollama:
            await fetchOllamaRepoVariants(item: item)
        case .installed:
            break
        }
    }

    private func fetchHuggingFaceRepoDetails(item: HubModelItem) async {
        let encodedSegments = item.repoOrSlug
            .split(separator: "/")
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
            .joined(separator: "/")
        guard let url = URL(string: "https://huggingface.co/api/models/\(encodedSegments)?blobs=true") else { return }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("MicroCode/2.0", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let siblings = (json["siblings"] as? [[String: Any]]) ?? []
        let usedStorage = (json["usedStorage"] as? NSNumber)?.int64Value ?? 0

        guard let currentIdx = hubModels.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = hubModels[currentIdx]

        if item.source == .mlx {
            var essentialFiles: [String] = []
            var totalBytes: Int64 = 0
            for sib in siblings {
                guard let fname = sib["rfilename"] as? String else { continue }
                if isEssentialMLXFile(fname) {
                    essentialFiles.append(fname)
                    totalBytes += (sib["size"] as? NSNumber)?.int64Value ?? 0
                }
            }
            if totalBytes == 0 { totalBytes = usedStorage }

            let localDir = mlxLocalDirectory(for: item.repoOrSlug)
            let onDisk = !essentialFiles.isEmpty && essentialFiles.allSatisfy {
                FileManager.default.fileExists(atPath: localDir.appendingPathComponent($0).path)
            }
            let quant = extractQuantization(from: item.displayName) ?? "MLX"
            let variant = HubModelVariant(
                id: item.repoOrSlug,
                label: "\(item.displayName) (\(essentialFiles.count) files)",
                filenames: essentialFiles,
                sizeBytes: totalBytes,
                quantization: quant,
                contextWindow: nil,
                isDownloadedOnDisk: onDisk
            )
            updated.variants = [variant]
            updated.estimatedSizeBytes = totalBytes
            if onDisk { updated.localDiskPath = localDir.path }
            updated.detailsLoaded = true
            hubModels[currentIdx] = updated
        } else if item.source == .gguf {
            struct ShardGroup {
                var key: String
                var files: [String]
                var bytes: Int64
                var quant: String?
            }
            var groups: [String: ShardGroup] = [:]
            let shardPattern = try? NSRegularExpression(pattern: "-0000\\d+-of-0000\\d+(?=\\.gguf$)", options: .caseInsensitive)

            for sib in siblings {
                guard let fname = sib["rfilename"] as? String else { continue }
                let lower = fname.lowercased()
                guard lower.hasSuffix(".gguf"), !lower.contains("mmproj"), !lower.contains("imatrix") else { continue }
                let size = (sib["size"] as? NSNumber)?.int64Value ?? 0

                var groupKey = fname
                if let shardPattern {
                    let ns = fname as NSString
                    groupKey = shardPattern.stringByReplacingMatches(in: fname, range: NSRange(location: 0, length: ns.length), withTemplate: "")
                }
                var existing = groups[groupKey] ?? ShardGroup(
                    key: groupKey,
                    files: [],
                    bytes: 0,
                    quant: extractQuantization(from: groupKey)
                )
                existing.files.append(fname)
                existing.bytes += size
                groups[groupKey] = existing
            }

            let lmsRepoDir = lmStudioRepoDirectory(for: item.repoOrSlug)
            var variants: [HubModelVariant] = groups.values.map { grp in
                let sortedFiles = grp.files.sorted()
                let baseName = (grp.key as NSString).lastPathComponent
                let onDisk = !sortedFiles.isEmpty && sortedFiles.allSatisfy {
                    FileManager.default.fileExists(atPath: lmsRepoDir.appendingPathComponent(($0 as NSString).lastPathComponent).path)
                }
                return HubModelVariant(
                    id: "\(item.repoOrSlug)::\(baseName)",
                    label: baseName,
                    filenames: sortedFiles,
                    sizeBytes: grp.bytes,
                    quantization: grp.quant ?? "GGUF",
                    contextWindow: nil,
                    isDownloadedOnDisk: onDisk
                )
            }

            variants.sort { a, b in
                let fitA = a.ramFit(totalRAMBytes: physicalMemoryBytes) == .fits
                let fitB = b.ramFit(totalRAMBytes: physicalMemoryBytes) == .fits
                if fitA != fitB { return fitA }
                return quantPriorityScore(a.quantization) > quantPriorityScore(b.quantization)
            }

            if !variants.isEmpty {
                updated.variants = variants
                updated.estimatedSizeBytes = variants[0].sizeBytes
            }
            updated.detailsLoaded = true
            hubModels[currentIdx] = updated
        }
    }

    private func fetchOllamaRepoVariants(item: HubModelItem) async {
        guard let url = URL(string: "https://ollama.com/library/\(item.repoOrSlug)") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0)", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else { return }

        let prefix = "<a href=\"/library/\(item.repoOrSlug):"
        let chunks = html.components(separatedBy: prefix)
        var variants: [HubModelVariant] = []
        var seenTags = Set<String>()

        for chunk in chunks.dropFirst() {
            guard let qEnd = chunk.firstIndex(of: "\"") else { continue }
            let suffix = String(chunk[..<qEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if suffix.isEmpty || suffix.contains("/") || suffix.contains("?") || suffix.lowercased().contains("cloud") { continue }
            let fullTag = "\(item.repoOrSlug):\(suffix)"
            if seenTags.contains(fullTag) { continue }

            let slice: String
            if let endA = chunk.range(of: "</a>") {
                slice = String(chunk[..<endA.lowerBound])
            } else {
                slice = String(chunk.prefix(900))
            }

            // Look for metadata line e.g. "5.2GB · 40K context window · Text · 1 year ago"
            var bytes: Int64 = 0
            var ctx: String? = nil
            if let metaRange = slice.range(of: "([0-9]+(?:\\.[0-9]+)?)\\s*(GB|MB)", options: [.regularExpression, .caseInsensitive]) {
                let sizeToken = String(slice[metaRange]).uppercased()
                let numPart = sizeToken.replacingOccurrences(of: "GB", with: "").replacingOccurrences(of: "MB", with: "").trimmingCharacters(in: .whitespaces)
                if let val = Double(numPart) {
                    if sizeToken.contains("GB") {
                        bytes = Int64(val * 1024 * 1024 * 1024)
                    } else {
                        bytes = Int64(val * 1024 * 1024)
                    }
                }
            }
            if let ctxRange = slice.range(of: "([0-9]+K|[0-9]+M)\\s+context", options: [.regularExpression, .caseInsensitive]) {
                ctx = String(slice[ctxRange]).components(separatedBy: .whitespaces).first?.uppercased()
            }

            // Only accept anchor blocks that carried the size metadata (or first occurrence)
            if bytes > 0 {
                seenTags.insert(fullTag)
                variants.append(
                    HubModelVariant(
                        id: fullTag,
                        label: fullTag,
                        filenames: [],
                        sizeBytes: bytes,
                        quantization: extractQuantization(from: suffix),
                        contextWindow: ctx,
                        isDownloadedOnDisk: isOllamaTagInstalled(fullTag)
                    )
                )
            }
        }

        guard let currentIdx = hubModels.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = hubModels[currentIdx]
        if !variants.isEmpty {
            // Put :latest or best RAM-fitting tag at top
            variants.sort { a, b in
                let aLatest = a.id.hasSuffix(":latest")
                let bLatest = b.id.hasSuffix(":latest")
                let aFits = a.ramFit(totalRAMBytes: physicalMemoryBytes) == .fits
                let bFits = b.ramFit(totalRAMBytes: physicalMemoryBytes) == .fits
                if aFits != bFits { return aFits }
                if aLatest != bLatest { return aLatest }
                return a.sizeBytes < b.sizeBytes
            }
            updated.variants = variants
            updated.estimatedSizeBytes = variants[0].sizeBytes
        }
        updated.detailsLoaded = true
        hubModels[currentIdx] = updated
    }

    // MARK: - Build Installed Models Catalog (Online Local/LAN Servers + Disk Caches)

    private func buildInstalledHubModels(filterQuery: String) async -> [HubModelItem] {
        var results: [HubModelItem] = []
        var seenKeys = Set<String>()

        // 1. Live models across all detected Local & LAN servers
        for server in detectedServers where server.isOnline {
            for m in server.models {
                let key = "\(server.endpoint)|\(m.id)"
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)

                var caps: [String] = []
                if server.sourceKind == .thisMac { caps.append("This Mac") } else { caps.append("LAN") }
                if m.isWarmLoaded { caps.append("Loaded") }

                let variant = HubModelVariant(
                    id: m.id,
                    label: m.name,
                    filenames: [],
                    sizeBytes: 0,
                    quantization: m.quantization,
                    contextWindow: m.contextLength.map { "\($0 / 1024)K" },
                    isDownloadedOnDisk: true
                )

                results.append(
                    HubModelItem(
                        id: "installed:\(key)",
                        source: .installed,
                        repoOrSlug: m.id,
                        displayName: m.name,
                        author: "\(server.type.rawValue) · \(server.host):\(String(server.port))",
                        summary: "Ready on \(server.displayName) (\(server.endpoint)). Click Use in Chat to connect immediately.",
                        downloadsCount: 0,
                        likesCount: 0,
                        updatedLabel: "Online",
                        capabilities: caps,
                        parameterSizes: [m.parameterSize, m.size].compactMap { $0 },
                        estimatedSizeBytes: 0,
                        variants: [variant],
                        detailsLoaded: true,
                        installedServerEndpoint: server.endpoint,
                        installedServerName: server.displayName,
                        installedModelID: m.id
                    )
                )
            }
        }

        // 2. Local MLX weights cached in ~/.microcode/models/mlx/*
        let mlxRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".microcode/models/mlx")
        if let dirs = try? FileManager.default.contentsOfDirectory(at: mlxRoot, includingPropertiesForKeys: nil) {
            for dir in dirs where FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json").path) {
                let repoName = dir.lastPathComponent.replacingOccurrences(of: "--", with: "/")
                let bytes = directoryByteSize(dir)
                let variant = HubModelVariant(
                    id: repoName,
                    label: dir.lastPathComponent,
                    filenames: [],
                    sizeBytes: bytes,
                    quantization: "MLX",
                    contextWindow: nil,
                    isDownloadedOnDisk: true
                )
                results.append(
                    HubModelItem(
                        id: "installed:mlx:\(dir.path)",
                        source: .installed,
                        repoOrSlug: repoName,
                        displayName: (repoName as NSString).lastPathComponent,
                        author: "Apple MLX · On Disk",
                        summary: "Downloaded MLX weights at \(dir.path). Click Start & Use to launch mlx_lm.server.",
                        downloadsCount: 0,
                        likesCount: 0,
                        updatedLabel: "On Disk",
                        capabilities: ["MLX", "This Mac"],
                        parameterSizes: [],
                        estimatedSizeBytes: bytes,
                        variants: [variant],
                        detailsLoaded: true,
                        localDiskPath: dir.path
                    )
                )
            }
        }

        // 3. Local GGUF weights in ~/.lmstudio/models/**/*.gguf
        let lmsRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".lmstudio/models")
        if let enumerator = FileManager.default.enumerator(at: lmsRoot, includingPropertiesForKeys: [.fileSizeKey]) {
            while let fileURL = enumerator.nextObject() as? URL {
                guard fileURL.pathExtension.lowercased() == "gguf",
                      !fileURL.lastPathComponent.lowercased().contains("mmproj") else { continue }
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
                let fname = fileURL.lastPathComponent
                let variant = HubModelVariant(
                    id: fname,
                    label: fname,
                    filenames: [fname],
                    sizeBytes: size,
                    quantization: extractQuantization(from: fname) ?? "GGUF",
                    contextWindow: nil,
                    isDownloadedOnDisk: true
                )
                results.append(
                    HubModelItem(
                        id: "installed:gguf:\(fileURL.path)",
                        source: .installed,
                        repoOrSlug: fname,
                        displayName: fname,
                        author: "GGUF · ~/.lmstudio/models",
                        summary: "Local GGUF weights on disk (\(fileURL.path)). Ready to run via Ollama or LM Studio.",
                        downloadsCount: 0,
                        likesCount: 0,
                        updatedLabel: "On Disk",
                        capabilities: ["GGUF", "This Mac"],
                        parameterSizes: [extractSize(from: fname)].compactMap { $0 },
                        estimatedSizeBytes: size,
                        variants: [variant],
                        detailsLoaded: true,
                        localDiskPath: fileURL.path
                    )
                )
            }
        }

        if !filterQuery.isEmpty {
            return results.filter {
                $0.displayName.localizedCaseInsensitiveContains(filterQuery) ||
                $0.author.localizedCaseInsensitiveContains(filterQuery)
            }
        }
        return results
    }

    // MARK: - Real End-to-End Download, Server Launch & Chat Activation

    func cancelActiveHubDownload() {
        activeHubDownloadTask?.cancel()
        activeHubDownloadTask = nil
        activeHubDownload = nil
        hubActionMessage = "Download cancelled."
    }

    func installAndConnectHubModel(
        item: HubModelItem,
        variant: HubModelVariant?,
        onActivated: ((String) -> Void)? = nil
    ) {
        activeHubDownloadTask?.cancel()
        hubErrorMessage = nil
        hubActionMessage = nil

        activeHubDownloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let chosenVariant = variant ?? item.variants.first
            switch item.source {
            case .installed:
                await self.activateInstalledHubItem(item, onActivated: onActivated)
            case .ollama:
                let tag = chosenVariant?.id ?? "\(item.repoOrSlug):latest"
                await self.pullAndConnectOllamaTag(item: item, tag: tag, onActivated: onActivated)
            case .mlx:
                await self.downloadAndStartMLXRepo(item: item, variant: chosenVariant, onActivated: onActivated)
            case .gguf:
                guard let chosenVariant else {
                    self.hubErrorMessage = "No GGUF quantization file found in this repository."
                    return
                }
                await self.downloadAndConnectGGUFVariant(item: item, variant: chosenVariant, onActivated: onActivated)
            }
        }
    }

    private func activateInstalledHubItem(_ item: HubModelItem, onActivated: ((String) -> Void)?) async {
        // Case 1: Already served on an online Local or LAN server
        if let endpoint = item.installedServerEndpoint,
           let modelID = item.installedModelID,
           let sIdx = detectedServers.firstIndex(where: { $0.endpoint == endpoint && $0.isOnline }) {
            selectServer(at: sIdx)
            selectedModelId = modelID
            LocalLLMService.cachedEndpoint = detectedServers[sIdx].endpoint
            LocalLLMService.cachedModel = modelID
            LocalLLMService.cachedAPIKey = detectedServers[sIdx].apiKey ?? "local"
            hubActionMessage = "Connected to \(modelID) on \(detectedServers[sIdx].displayName)"
            onActivated?(modelID)
            return
        }

        // Case 2: Local MLX directory on disk -> boot mlx_lm.server immediately
        if let diskPath = item.localDiskPath,
           FileManager.default.fileExists(atPath: (diskPath as NSString).appendingPathComponent("config.json")) {
            await launchLocalMLXServer(modelDirectory: URL(fileURLWithPath: diskPath), modelIDLabel: item.displayName, itemID: item.id, onActivated: onActivated)
            return
        }

        // Case 3: Local GGUF file on disk -> import & run via Ollama (or open in LM Studio)
        if let diskPath = item.localDiskPath, diskPath.lowercased().hasSuffix(".gguf") {
            await importAndRunGGUFFile(ggufURL: URL(fileURLWithPath: diskPath), itemID: item.id, displayName: item.displayName, onActivated: onActivated)
            return
        }
    }

    // MARK: 1) Ollama Auto-Start + Real Byte-Streaming Pull + Connect

    private func ensureLocalOllamaRunning() async -> DetectedLLMServer? {
        if let existing = detectedServers.first(where: { $0.type == .ollama && $0.isOnline }) {
            return existing
        }
        let localOllamaCand = ProbeCandidate(
            scheme: "http",
            host: "127.0.0.1",
            port: 11434,
            apiPath: "/v1",
            apiKey: nil,
            sourceKind: .thisMac,
            labelHint: nil
        )
        if let probed = await probeSmartCandidate(localOllamaCand), probed.isOnline {
            await scanForServers()
            return detectedServers.first(where: { $0.type == .ollama && $0.isOnline }) ?? probed
        }

        guard let ollamaBin = ollamaBinaryPath else {
            return nil
        }

        // Auto-start `ollama serve`
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ollamaBin)
        proc.arguments = ["serve"]
        var env = ProcessInfo.processInfo.environment
        env["OLLAMA_HOST"] = "0.0.0.0:11434"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        proc.environment = env
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try? proc.run()
        managedOllamaProcess = proc

        for _ in 0..<14 {
            if Task.isCancelled { return nil }
            try? await Task.sleep(nanoseconds: 450_000_000)
            if let probed = await probeSmartCandidate(localOllamaCand), probed.isOnline {
                await scanForServers()
                return detectedServers.first(where: { $0.type == .ollama && $0.isOnline }) ?? probed
            }
        }
        return nil
    }

    private func pullAndConnectOllamaTag(item: HubModelItem, tag: String, onActivated: ((String) -> Void)?) async {
        activeHubDownload = ActiveModelDownloadState(
            modelID: item.id,
            variantID: tag,
            title: tag,
            statusText: "Starting Ollama runtime...",
            fractionCompleted: 0,
            completedBytes: 0,
            totalBytes: 0,
            speedBytesPerSec: 0,
            isIndeterminate: true
        )

        guard let ollamaServer = await ensureLocalOllamaRunning(),
              let pullURL = URL(string: "\(ollamaServer.scheme)://\(ollamaServer.host):\(String(ollamaServer.port))/api/pull") else {
            activeHubDownload = nil
            hubErrorMessage = "Ollama is not installed or running. Install Ollama (`brew install ollama`) or switch to the Apple MLX tab."
            return
        }

        // Fast-path if already pulled on this Ollama server
        if ollamaServer.models.contains(where: { $0.id.lowercased() == tag.lowercased() }) {
            activeHubDownload = nil
            activateServerAndModel(serverEndpoint: ollamaServer.endpoint, modelID: tag, onActivated: onActivated)
            return
        }

        var request = URLRequest(url: pullURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 3600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": tag, "stream": true])

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            var lastUIUpdate = CFAbsoluteTimeGetCurrent()
            var lastSpeedCheckTime = lastUIUpdate
            var lastSpeedBytes: Int64 = 0
            var measuredSpeed: Double = 0

            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                if let err = json["error"] as? String {
                    activeHubDownload = nil
                    hubErrorMessage = "Ollama error: \(err)"
                    return
                }

                let status = (json["status"] as? String) ?? "Pulling..."
                let total = (json["total"] as? NSNumber)?.int64Value ?? 0
                let completed = (json["completed"] as? NSNumber)?.int64Value ?? 0

                let now = CFAbsoluteTimeGetCurrent()
                if now - lastSpeedCheckTime >= 0.5 && completed >= lastSpeedBytes {
                    measuredSpeed = Double(completed - lastSpeedBytes) / (now - lastSpeedCheckTime)
                    lastSpeedCheckTime = now
                    lastSpeedBytes = completed
                }

                if status == "success" {
                    break
                }

                if now - lastUIUpdate >= 0.08 {
                    lastUIUpdate = now
                    let frac = total > 0 ? min(1.0, Double(completed) / Double(total)) : 0
                    activeHubDownload = ActiveModelDownloadState(
                        modelID: item.id,
                        variantID: tag,
                        title: tag,
                        statusText: status,
                        fractionCompleted: frac,
                        completedBytes: completed,
                        totalBytes: total,
                        speedBytesPerSec: measuredSpeed,
                        isIndeterminate: total == 0
                    )
                }
            }

            activeHubDownload?.statusText = "Activating \(tag)..."
            await scanForServers()
            activeHubDownload = nil
            markVariantDownloadedInMemory(itemID: item.id, variantID: tag)
            activateServerAndModel(serverEndpoint: ollamaServer.endpoint, modelID: tag, onActivated: onActivated)
        } catch is CancellationError {
            activeHubDownload = nil
        } catch {
            activeHubDownload = nil
            hubErrorMessage = "Pull failed: \(error.localizedDescription)"
        }
    }

    // MARK: 2) Apple MLX Real HuggingFace File Streaming + Native mlx_lm.server Boot

    private func downloadAndStartMLXRepo(item: HubModelItem, variant: HubModelVariant?, onActivated: ((String) -> Void)?) async {
        guard mlxServerBinaryPath != nil || FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/python3") else {
            hubErrorMessage = "mlx-lm is not installed. Run `brew install mlx-lm` or `pip install mlx-lm`."
            return
        }

        // Ensure exact file manifest is loaded
        if !item.detailsLoaded || (variant?.filenames.isEmpty ?? true) {
            activeHubDownload = ActiveModelDownloadState(
                modelID: item.id,
                variantID: item.repoOrSlug,
                title: item.displayName,
                statusText: "Fetching Hugging Face file manifest...",
                fractionCompleted: 0,
                completedBytes: 0,
                totalBytes: 0,
                speedBytesPerSec: 0,
                isIndeterminate: true
            )
            await fetchHubModelDetails(itemID: item.id)
        }

        let refreshedItem = hubModels.first(where: { $0.id == item.id }) ?? item
        let refreshedVariant = refreshedItem.variants.first
        let filesToDownload = refreshedVariant?.filenames ?? []
        let expectedTotal = refreshedVariant?.sizeBytes ?? 0

        guard !filesToDownload.isEmpty else {
            activeHubDownload = nil
            hubErrorMessage = "Could not resolve MLX safetensors files for \(item.repoOrSlug)."
            return
        }

        let targetDir = mlxLocalDirectory(for: item.repoOrSlug)
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            try await streamHuggingFaceFiles(
                repoID: item.repoOrSlug,
                filenames: filesToDownload,
                destinationDir: targetDir,
                preserveSubpaths: true,
                expectedTotalBytes: expectedTotal,
                modelID: item.id,
                variantID: item.repoOrSlug,
                title: item.displayName
            )
        } catch is CancellationError {
            activeHubDownload = nil
            return
        } catch {
            activeHubDownload = nil
            hubErrorMessage = "Download failed: \(error.localizedDescription)"
            return
        }

        markVariantDownloadedInMemory(itemID: item.id, variantID: item.repoOrSlug, localPath: targetDir.path)
        await launchLocalMLXServer(
            modelDirectory: targetDir,
            modelIDLabel: item.displayName,
            itemID: item.id,
            onActivated: onActivated
        )
    }

    private func launchLocalMLXServer(
        modelDirectory: URL,
        modelIDLabel: String,
        itemID: String,
        onActivated: ((String) -> Void)?
    ) async {
        activeHubDownload = ActiveModelDownloadState(
            modelID: itemID,
            variantID: modelDirectory.path,
            title: modelIDLabel,
            statusText: "Loading weights into Apple Metal Unified Memory...",
            fractionCompleted: 1.0,
            completedBytes: 0,
            totalBytes: 0,
            speedBytesPerSec: 0,
            isIndeterminate: true
        )

        if let oldProc = managedMLXProcess, oldProc.isRunning {
            oldProc.terminate()
            try? await Task.sleep(nanoseconds: 350_000_000)
        }

        let port = findFreeLocalPort(preferred: [8088, 8080, 8089, 1236])
        let proc = Process()
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        proc.environment = env

        if let mlxBin = mlxServerBinaryPath {
            proc.executableURL = URL(fileURLWithPath: mlxBin)
            proc.arguments = ["--model", modelDirectory.path, "--host", "0.0.0.0", "--port", String(port)]
        } else {
            proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/python3")
            proc.arguments = ["-m", "mlx_lm.server", "--model", modelDirectory.path, "--host", "0.0.0.0", "--port", String(port)]
        }

        let errPipe = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = errPipe

        do {
            try proc.run()
            managedMLXProcess = proc
            managedMLXPort = port
        } catch {
            activeHubDownload = nil
            hubErrorMessage = "Could not launch mlx_lm.server: \(error.localizedDescription)"
            return
        }

        let endpointURL = "http://127.0.0.1:\(String(port))/v1"
        for _ in 0..<40 {
            if Task.isCancelled {
                activeHubDownload = nil
                return
            }
            if !proc.isRunning {
                let errData = errPipe.fileHandleForReading.availableData
                let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Process exited."
                activeHubDownload = nil
                hubErrorMessage = "MLX Server exited: \(String(errText.suffix(220)))"
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let modelsURL = URL(string: "\(endpointURL)/models"),
               let (_, res) = try? await fastLocalSession.data(from: modelsURL),
               (res as? HTTPURLResponse)?.statusCode == 200 {
                let connected = await connectOrPairEndpoint(endpointURL)
                activeHubDownload = nil
                if connected {
                    let chosenModel = activeModel
                    hubActionMessage = "MLX Server active on port \(String(port)) · Connected to \(chosenModel)"
                    onActivated?(chosenModel)
                } else {
                    hubErrorMessage = "MLX Server started on port \(String(port)) but /v1/models returned no models."
                }
                return
            }
        }

        activeHubDownload = nil
        hubErrorMessage = "MLX Server is taking longer than expected to load weights into RAM."
    }

    // MARK: 3) GGUF Real Streaming Download -> ~/.lmstudio/models + Immediate Local Activation

    private func downloadAndConnectGGUFVariant(item: HubModelItem, variant: HubModelVariant, onActivated: ((String) -> Void)?) async {
        let files = variant.filenames
        guard !files.isEmpty else {
            hubErrorMessage = "Select a GGUF quantization file first."
            return
        }

        let destDir = lmStudioRepoDirectory(for: item.repoOrSlug)
        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            try await streamHuggingFaceFiles(
                repoID: item.repoOrSlug,
                filenames: files,
                destinationDir: destDir,
                preserveSubpaths: false,
                expectedTotalBytes: variant.sizeBytes,
                modelID: item.id,
                variantID: variant.id,
                title: variant.label
            )
        } catch is CancellationError {
            activeHubDownload = nil
            return
        } catch {
            activeHubDownload = nil
            hubErrorMessage = "GGUF download failed: \(error.localizedDescription)"
            return
        }

        markVariantDownloadedInMemory(itemID: item.id, variantID: variant.id, localPath: destDir.path)
        let primaryLocalFile = destDir.appendingPathComponent((files[0] as NSString).lastPathComponent)

        // Automatically import & run via Ollama if available so user chats immediately
        if ollamaBinaryPath != nil || detectedServers.contains(where: { $0.type == .ollama && $0.isOnline }) {
            await importAndRunGGUFFile(
                ggufURL: primaryLocalFile,
                itemID: item.id,
                displayName: variant.label,
                onActivated: onActivated
            )
        } else {
            activeHubDownload = nil
            hubActionMessage = "Saved to \(primaryLocalFile.path) (Ready in LM Studio)."
        }
    }

    private func importAndRunGGUFFile(
        ggufURL: URL,
        itemID: String,
        displayName: String,
        onActivated: ((String) -> Void)?
    ) async {
        guard let ollamaBin = ollamaBinaryPath else {
            activeHubDownload = nil
            hubErrorMessage = "Saved GGUF at \(ggufURL.path). Start LM Studio or install Ollama to serve it."
            return
        }

        let rawBase = ggufURL.deletingPathExtension().lastPathComponent.lowercased()
        let sanitizedTag = rawBase
            .replacingOccurrences(of: "[^a-z0-9._-]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        let modelTag = sanitizedTag.isEmpty ? "local-gguf" : sanitizedTag

        activeHubDownload = ActiveModelDownloadState(
            modelID: itemID,
            variantID: displayName,
            title: displayName,
            statusText: "Registering GGUF weights with local Ollama runtime...",
            fractionCompleted: 1.0,
            completedBytes: 0,
            totalBytes: 0,
            speedBytesPerSec: 0,
            isIndeterminate: true
        )

        guard let ollamaServer = await ensureLocalOllamaRunning() else {
            activeHubDownload = nil
            hubErrorMessage = "Saved GGUF to \(ggufURL.path), but could not start local Ollama daemon."
            return
        }

        let modelfileURL = FileManager.default.temporaryDirectory.appendingPathComponent("MicroCode-\(UUID().uuidString).Modelfile")
        let escapedPath = ggufURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let modelfileContent = "FROM \"\(escapedPath)\"\n"
        try? modelfileContent.write(to: modelfileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: modelfileURL) }

        let createSuccess = await Task.detached(priority: .userInitiated) { () -> Bool in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ollamaBin)
            p.arguments = ["create", modelTag, "-f", modelfileURL.path]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            p.environment = env
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            do {
                try p.run()
                p.waitUntilExit()
                return p.terminationStatus == 0
            } catch {
                return false
            }
        }.value

        activeHubDownload = nil
        if createSuccess {
            await scanForServers()
            let resolvedTag = detectedServers
                .first(where: { $0.endpoint == ollamaServer.endpoint })?
                .models.first(where: { $0.id.hasPrefix(modelTag) })?.id ?? "\(modelTag):latest"
            activateServerAndModel(serverEndpoint: ollamaServer.endpoint, modelID: resolvedTag, onActivated: onActivated)
        } else {
            hubActionMessage = "Downloaded GGUF to \(ggufURL.path). Open LM Studio to load it."
        }
    }

    func openInLMStudio(repoID: String, filename: String?) {
        var comps = URLComponents(string: "lmstudio://open_from_hf")!
        var q = [URLQueryItem(name: "model", value: repoID)]
        if let filename, !filename.isEmpty {
            q.append(URLQueryItem(name: "file", value: filename))
        }
        comps.queryItems = q
        if let url = comps.url {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Resumable / Cached Byte-Streaming Hugging Face Downloader

    private func streamHuggingFaceFiles(
        repoID: String,
        filenames: [String],
        destinationDir: URL,
        preserveSubpaths: Bool,
        expectedTotalBytes: Int64,
        modelID: String,
        variantID: String,
        title: String
    ) async throws {
        let encodedRepo = repoID
            .split(separator: "/")
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
            .joined(separator: "/")

        var cumulativeCompleted: Int64 = 0
        var dynamicTotalBytes: Int64 = max(0, expectedTotalBytes)
        var lastUIUpdate = CFAbsoluteTimeGetCurrent()
        var lastSpeedTime = lastUIUpdate
        var bytesSinceSpeedCheck: Int64 = 0
        var measuredSpeed: Double = 0

        for (fileIndex, rfilename) in filenames.enumerated() {
            try Task.checkCancellation()
            let relativePath = preserveSubpaths ? rfilename : (rfilename as NSString).lastPathComponent
            let finalURL = destinationDir.appendingPathComponent(relativePath)
            let parentDir = finalURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: finalURL.path),
               let existingSize = (try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map({ Int64($0) }),
               existingSize > 0 {
                cumulativeCompleted += existingSize
                continue
            }

            let encodedFile = rfilename
                .split(separator: "/")
                .compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
                .joined(separator: "/")
            guard let downloadURL = URL(string: "https://huggingface.co/\(encodedRepo)/resolve/main/\(encodedFile)") else {
                continue
            }

            var req = URLRequest(url: downloadURL)
            req.timeoutInterval = 3600
            req.setValue("MicroCode/2.0", forHTTPHeaderField: "User-Agent")

            let (byteStream, response) = try await URLSession.shared.bytes(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            if dynamicTotalBytes == 0 && response.expectedContentLength > 0 {
                dynamicTotalBytes = response.expectedContentLength
            }

            let partURL = finalURL.appendingPathExtension("part")
            FileManager.default.createFile(atPath: partURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: partURL)
            defer { try? handle.close() }

            var buffer = Data()
            buffer.reserveCapacity(262_144) // 256 KB write chunks

            let shortFile = (rfilename as NSString).lastPathComponent
            let stepPrefix = filenames.count > 1 ? "[\(fileIndex + 1)/\(filenames.count)] " : ""

            for try await byte in byteStream {
                buffer.append(byte)
                if buffer.count >= 262_144 {
                    try Task.checkCancellation()
                    try handle.write(contentsOf: buffer)
                    let chunkLen = Int64(buffer.count)
                    cumulativeCompleted += chunkLen
                    bytesSinceSpeedCheck += chunkLen
                    buffer.removeAll(keepingCapacity: true)

                    let now = CFAbsoluteTimeGetCurrent()
                    if now - lastSpeedTime >= 0.5 {
                        measuredSpeed = Double(bytesSinceSpeedCheck) / (now - lastSpeedTime)
                        bytesSinceSpeedCheck = 0
                        lastSpeedTime = now
                    }
                    if now - lastUIUpdate >= 0.08 {
                        lastUIUpdate = now
                        let total = max(dynamicTotalBytes, cumulativeCompleted)
                        let frac = total > 0 ? min(1.0, Double(cumulativeCompleted) / Double(total)) : 0
                        activeHubDownload = ActiveModelDownloadState(
                            modelID: modelID,
                            variantID: variantID,
                            title: title,
                            statusText: "\(stepPrefix)\(shortFile)",
                            fractionCompleted: frac,
                            completedBytes: cumulativeCompleted,
                            totalBytes: total,
                            speedBytesPerSec: measuredSpeed,
                            isIndeterminate: total == 0
                        )
                    }
                }
            }

            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                cumulativeCompleted += Int64(buffer.count)
                buffer.removeAll()
            }
            try handle.close()

            if FileManager.default.fileExists(atPath: finalURL.path) {
                try? FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: partURL, to: finalURL)
        }
    }

    // MARK: - Hub Helper Utilities

    private func activateServerAndModel(serverEndpoint: String, modelID: String, onActivated: ((String) -> Void)?) {
        if let idx = detectedServers.firstIndex(where: { $0.endpoint == serverEndpoint }) {
            selectServer(at: idx)
            let matchedModel = detectedServers[idx].models.first(where: {
                $0.id.lowercased() == modelID.lowercased() || $0.id.lowercased().hasPrefix(modelID.lowercased())
            })?.id ?? modelID
            selectedModelId = matchedModel
            LocalLLMService.cachedEndpoint = detectedServers[idx].endpoint
            LocalLLMService.cachedModel = matchedModel
            LocalLLMService.cachedAPIKey = detectedServers[idx].apiKey ?? "local"
            hubActionMessage = "Active in Chat: \(matchedModel)"
            onActivated?(matchedModel)
        } else {
            selectedModelId = modelID
            LocalLLMService.cachedModel = modelID
            hubActionMessage = "Active in Chat: \(modelID)"
            onActivated?(modelID)
        }
    }

    private func markVariantDownloadedInMemory(itemID: String, variantID: String, localPath: String? = nil) {
        guard let idx = hubModels.firstIndex(where: { $0.id == itemID }) else { return }
        var item = hubModels[idx]
        if let localPath { item.localDiskPath = localPath }
        for vIdx in item.variants.indices where item.variants[vIdx].id == variantID {
            item.variants[vIdx].isDownloadedOnDisk = true
        }
        hubModels[idx] = item
    }

    private func mlxLocalDirectory(for repoID: String) -> URL {
        let sanitized = repoID.replacingOccurrences(of: "/", with: "--")
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".microcode/models/mlx")
            .appendingPathComponent(sanitized)
    }

    private func lmStudioRepoDirectory(for repoID: String) -> URL {
        let parts = repoID.split(separator: "/", maxSplits: 1).map(String.init)
        let author = parts.count > 1 ? parts[0] : "huggingface"
        let repo = parts.count > 1 ? parts[1] : repoID
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".lmstudio/models")
            .appendingPathComponent(author)
            .appendingPathComponent(repo)
    }

    private func isEssentialMLXFile(_ filename: String) -> Bool {
        let lower = filename.lowercased()
        if lower == "readme.md" || lower.hasPrefix(".") || lower.contains("/.") { return false }
        let allowedExts = [".json", ".safetensors", ".tiktoken", ".model", ".txt", ".py", ".jinja", ".spm"]
        return allowedExts.contains(where: { lower.hasSuffix($0) })
    }

    private func isOllamaTagInstalled(_ tag: String) -> Bool {
        let lower = tag.lowercased()
        let base = lower.components(separatedBy: ":").first ?? lower
        for srv in detectedServers where srv.type == .ollama && srv.isOnline {
            for m in srv.models {
                let mLow = m.id.lowercased()
                if mLow == lower || (lower.hasSuffix(":latest") && mLow.components(separatedBy: ":").first == base) {
                    return true
                }
            }
        }
        return false
    }

    private func findFreeLocalPort(preferred: [Int]) -> Int {
        for p in preferred where !isLocalTCPPortBound(p) {
            return p
        }
        return 18088
    }

    private func isLocalTCPPortBound(_ port: Int) -> Bool {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        return connected
    }

    private func quantPriorityScore(_ quant: String?) -> Int {
        guard let q = quant?.uppercased() else { return 10 }
        if q.contains("Q4_K_M") { return 100 }
        if q.contains("4BIT") { return 98 }
        if q.contains("Q4_K_S") || q.contains("IQ4") { return 90 }
        if q.contains("Q5_K_M") { return 85 }
        if q.contains("Q5_K_S") { return 80 }
        if q.contains("Q6_K") { return 75 }
        if q.contains("Q8_0") || q.contains("8BIT") { return 70 }
        if q.contains("Q3_K") { return 60 }
        if q.contains("Q2_K") { return 45 }
        if q.contains("BF16") || q.contains("F16") { return 30 }
        return 50
    }

    private func estimateBytesFromParamsAndQuant(paramString: String?, quant: String?, isMLX: Bool) -> Int64 {
        guard let pStr = paramString?.uppercased() else { return 0 }
        let cleaned = pStr.replacingOccurrences(of: "B", with: "").replacingOccurrences(of: "M", with: "")
        guard let num = Double(cleaned) else { return 0 }
        let paramsBillions = pStr.contains("M") ? (num / 1000.0) : num

        let q = quant?.uppercased() ?? (isMLX ? "4BIT" : "Q4_K_M")
        let bytesPerBillion: Double
        if q.contains("8") { bytesPerBillion = 1.08 }
        else if q.contains("6") { bytesPerBillion = 0.82 }
        else if q.contains("5") { bytesPerBillion = 0.72 }
        else if q.contains("16") { bytesPerBillion = 2.05 }
        else if q.contains("3") { bytesPerBillion = 0.48 }
        else if q.contains("2") { bytesPerBillion = 0.38 }
        else { bytesPerBillion = 0.62 } // 4-bit / Q4_K_M

        return Int64(paramsBillions * bytesPerBillion * 1024 * 1024 * 1024)
    }

    private func relativeDateLabel(fromISO iso: String) -> String {
        guard !iso.isEmpty else { return "" }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "" }
        let days = max(0, Int(Date().timeIntervalSince(date) / 86400))
        if days == 0 { return "today" }
        if days < 7 { return "\(days)d" }
        if days < 30 { return "\(days / 7)w" }
        if days < 365 { return "\(days / 30)mo" }
        return "\(days / 365)y"
    }

    private func directoryByteSize(_ dir: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var sum: Int64 = 0
        while let f = enumerator.nextObject() as? URL {
            sum += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return sum
    }

    private func stripHTMLTags(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private func decodeHTMLEntities(_ raw: String) -> String {
        raw.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    func deleteModel(_ modelName: String) async {
        guard let ollamaServer = detectedServers.first(where: { $0.type == .ollama && $0.isOnline }),
              let url = URL(string: "\(ollamaServer.scheme)://\(ollamaServer.host):\(String(ollamaServer.port))/api/delete") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": modelName])

        _ = try? await URLSession.shared.data(for: request)
        scanLog.append("🗑 Deleted \(modelName)")
        await scanForServers()
    }

    // MARK: - Parse Models

    private func parseOpenAIModels(_ data: Data) -> [LocalLLMModel] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsArray = json["data"] as? [[String: Any]] else { return [] }

        return modelsArray.compactMap { modelDict -> LocalLLMModel? in
            guard let id = modelDict["id"] as? String else { return nil }
            let name = id.components(separatedBy: "/").last ?? id
            return LocalLLMModel(
                id: id,
                name: name,
                size: extractSize(from: name),
                quantization: extractQuantization(from: name)
            )
        }
    }

    private func parseLMStudioV0Models(_ data: Data) -> (models: [LocalLLMModel], warmIds: Set<String>) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else { return ([], []) }

        var warm = Set<String>()
        var list: [LocalLLMModel] = []
        for item in arr {
            guard let id = item["id"] as? String else { continue }
            let name = id.components(separatedBy: "/").last ?? id
            let state = (item["state"] as? String)?.lowercased() ?? ""
            let isLoaded = (state == "loaded")
            if isLoaded { warm.insert(id) }
            let quant = (item["quantization"] as? String) ?? extractQuantization(from: name)
            let arch = item["arch"] as? String
            let ctx = item["max_context_length"] as? Int
            let model = LocalLLMModel(
                id: id,
                name: name,
                size: extractSize(from: name),
                quantization: quant,
                parameterSize: extractSize(from: id),
                family: arch,
                isWarmLoaded: isLoaded,
                contextLength: ctx
            )
            list.append(model)
        }
        list.sort { a, b in
            if a.isWarmLoaded != b.isWarmLoaded { return a.isWarmLoaded }
            return false
        }
        return (list, warm)
    }

    private func parseOllamaModels(_ data: Data) -> [LocalLLMModel] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsArray = json["models"] as? [[String: Any]] else { return [] }

        return modelsArray.compactMap { modelDict -> LocalLLMModel? in
            guard let name = modelDict["name"] as? String else { return nil }

            let size: String?
            if let sizeBytes = modelDict["size"] as? Int64 { size = formatBytes(sizeBytes) }
            else if let sizeBytes = modelDict["size"] as? Int { size = formatBytes(Int64(sizeBytes)) }
            else { size = extractSize(from: name) }

            var model = LocalLLMModel(
                id: name,
                name: name,
                size: size,
                quantization: extractQuantization(from: name)
            )
            if let details = modelDict["details"] as? [String: Any] {
                model.parameterSize = details["parameter_size"] as? String
                model.family = details["family"] as? String
                if model.quantization == nil, let qLevel = details["quantization_level"] as? String {
                    model.quantization = qLevel
                }
            }
            return model
        }
    }

    // MARK: - Helpers

    private func extractQuantization(from name: String) -> String? {
        let patterns = [
            "Q2_K", "Q3_K", "Q4_K_M", "Q4_K_S", "Q4_0", "Q4_1",
            "Q5_K_M", "Q5_K_S", "Q5_0", "Q5_1",
            "Q6_K", "Q8_0", "F16", "BF16", "F32", "IQ2_M", "IQ3_M", "IQ4_NL",
            "4BIT", "8BIT", "FP8", "AWQ", "GPTQ"
        ]
        let upper = name.uppercased()
        return patterns.first { upper.contains($0) }
    }

    private func extractSize(from name: String) -> String? {
        if let range = name.range(of: "\\d+(?:\\.\\d+)?x?\\d*[bB]", options: .regularExpression) {
            return String(name[range]).uppercased()
        }
        return nil
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        return gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", Double(bytes) / (1024 * 1024))
    }

    func quickCheck() async -> Bool {
        guard let server = activeServer,
              let url = URL(string: "\(server.endpoint)/models") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        if let key = server.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, response) = try await lanAndRemoteSession.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }
}
