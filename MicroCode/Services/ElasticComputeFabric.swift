import Foundation
import Combine
import Metal

// MARK: - Elastic Compute Fabric
// P3: Unified GPU orchestration — Colab, RunPod, Local GPU, and SSH remotes
// in a single dropdown. Cost guard + VRAM HUD.

// MARK: - Compute Provider

enum ComputeProviderType: String, CaseIterable, Codable {
    case local = "Local GPU"
    case colab = "Google Colab"
    case runpod = "RunPod"
    case sshRemote = "SSH Remote"
    case lambdaLabs = "Lambda Labs"
    case vastAI = "Vast.ai"
}

struct ComputeInstance: Identifiable, Equatable, Codable {
    let id: UUID
    let provider: ComputeProviderType
    let name: String
    let gpuModel: String           // "RTX 4090", "A100 80GB", "H100"
    let gpuMemoryGB: Double        // 24, 40, 80
    let cpuCores: Int
    let ramGB: Double
    let costPerHourUSD: Double     // 0.0 for local
    let status: InstanceStatus
    let endpoint: String           // SSH host, API endpoint, or "local"
    let region: String             // "us-east-1", "eu-west", "local"
    
    enum InstanceStatus: String, Codable {
        case available = "Available"
        case running = "Running"
        case starting = "Starting"
        case stopping = "Stopping"
        case terminated = "Terminated"
        case error = "Error"
    }
}

// MARK: - GPU Memory Stats

struct GPUMemoryStats: Equatable {
    let totalMB: Int
    let usedMB: Int
    let freeMB: Int
    let utilizationPercent: Double
    let temperatureCelsius: Int
    let gpuName: String
    let driverVersion: String
    
    var usagePercent: Double {
        totalMB > 0 ? (Double(usedMB) / Double(totalMB)) * 100.0 : 0.0
    }
    
    var formattedUsed: String {
        if usedMB >= 1024 { return String(format: "%.1fGB", Double(usedMB) / 1024.0) }
        return "\(usedMB)MB"
    }
    
    var formattedTotal: String {
        if totalMB >= 1024 { return String(format: "%.0fGB", Double(totalMB) / 1024.0) }
        return "\(totalMB)MB"
    }
}

// MARK: - Compute Session

struct ComputeSession: Identifiable, Equatable {
    let id: UUID
    let instance: ComputeInstance
    let startTime: Date
    var endTime: Date?
    var totalCostUSD: Double
    var status: SessionStatus
    
    enum SessionStatus: String {
        case active = "Active"
        case paused = "Paused"
        case completed = "Completed"
        case failed = "Failed"
    }
    
    var elapsedMinutes: Double {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime) / 60.0
    }
    
    var elapsedFormatted: String {
        let mins = Int(elapsedMinutes)
        if mins >= 60 { return "\(mins / 60)h \(mins % 60)m" }
        return "\(mins)m"
    }
}

// MARK: - Cost Guard

struct CostGuardConfig: Codable, Equatable {
    var maxSessionCostUSD: Double        // Max cost per single session
    var maxDailyCostUSD: Double          // Max total daily spend
    var maxMonthlyCostUSD: Double        // Max total monthly spend
    var autoShutdownOnBudget: Bool       // Auto-terminate when budget hit
    var warningThresholdPercent: Double   // Warn at this % of budget
    
    static let `default` = CostGuardConfig(
        maxSessionCostUSD: 10.0,
        maxDailyCostUSD: 50.0,
        maxMonthlyCostUSD: 500.0,
        autoShutdownOnBudget: true,
        warningThresholdPercent: 80.0
    )
}

// MARK: - Elastic Compute Fabric Service

@MainActor
final class ElasticComputeFabric: ObservableObject {
    static let shared = ElasticComputeFabric()
    
    // MARK: - Published State
    
    /// All registered compute instances across providers
    @Published private(set) var instances: [ComputeInstance] = []
    
    /// Active compute session (if any)
    @Published private(set) var activeSession: ComputeSession?
    
    /// Local GPU memory stats (updated periodically)
    @Published private(set) var localGPUStats: GPUMemoryStats?
    
    /// Cost tracking
    @Published private(set) var todayCostUSD: Double = 0.0
    @Published private(set) var monthCostUSD: Double = 0.0
    
    /// Cost guard configuration
    @Published var costGuard: CostGuardConfig = .default {
        didSet { persistCostGuard() }
    }
    
    /// Budget alerts
    @Published private(set) var budgetWarning: String?
    @Published private(set) var budgetExceeded: Bool = false
    
    // MARK: - Timer
    private var gpuPollTimer: Timer?
    private var costTimer: Timer?
    
    private init() {
        loadCostGuard()
        discoverLocalGPU()
        startGPUPolling()
        startCostTracking()
    }
    
    // MARK: - Local GPU Discovery
    
    /// Detect local GPU via system_profiler (macOS)
    func discoverLocalGPU() {
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPDisplaysDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let displays = json["SPDisplaysDataType"] as? [[String: Any]] {
                    for display in displays {
                        let name = display["sppci_model"] as? String ?? "Unknown GPU"
                        let vramStr = display["spdisplays_vram"] as? String ?? "0"
                        let vramMB = parseVRAM(vramStr)
                        
                        let instance = ComputeInstance(
                            id: UUID(),
                            provider: .local,
                            name: name,
                            gpuModel: name,
                            gpuMemoryGB: Double(vramMB) / 1024.0,
                            cpuCores: ProcessInfo.processInfo.activeProcessorCount,
                            ramGB: Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024),
                            costPerHourUSD: 0.0,
                            status: .available,
                            endpoint: "local",
                            region: "local"
                        )
                        
                        // Remove existing local instances first
                        instances.removeAll { $0.provider == .local }
                        instances.insert(instance, at: 0)
                    }
                }
            } catch {
                NSLog("⚠️ [ComputeFabric] Failed to discover local GPU: \(error)")
            }
        }
    }
    
    // MARK: - GPU Memory Polling (VRAM HUD)
    
    private func startGPUPolling() {
        gpuPollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollGPUStats()
            }
        }
    }
    
    private func pollGPUStats() {
        // On macOS, use Metal to query GPU memory
        #if canImport(Metal)
        if let device = MTLCreateSystemDefaultDevice() {
            let totalMB: Int
            let usedMB: Int
            
            // Apple Silicon reports unified memory
            let totalBytes = device.recommendedMaxWorkingSetSize
            let allocatedBytes = device.currentAllocatedSize
            totalMB = Int(totalBytes / (1024 * 1024))
            usedMB = Int(allocatedBytes / (1024 * 1024))
            
            localGPUStats = GPUMemoryStats(
                totalMB: totalMB,
                usedMB: usedMB,
                freeMB: totalMB - usedMB,
                utilizationPercent: 0, // Not available via Metal API
                temperatureCelsius: 0, // Not available on macOS
                gpuName: device.name,
                driverVersion: "Metal \(device.supportsFamily(.apple9) ? "3" : "2")"
            )
        }
        #endif
    }
    
    // MARK: - Cost Tracking
    
    private func startCostTracking() {
        costTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCosts()
            }
        }
    }
    
    private func updateCosts() {
        guard let session = activeSession, session.status == .active else { return }
        
        let elapsedHours = session.elapsedMinutes / 60.0
        let cost = elapsedHours * session.instance.costPerHourUSD
        
        // Update active session cost
        if var updated = activeSession {
            updated.totalCostUSD = cost
            activeSession = updated
        }
        
        todayCostUSD += cost - (activeSession?.totalCostUSD ?? 0)
        
        // Check budget
        checkBudget(currentCost: cost)
    }
    
    private func checkBudget(currentCost: Double) {
        let config = costGuard
        
        // Session budget
        if currentCost >= config.maxSessionCostUSD {
            budgetExceeded = true
            budgetWarning = "Session budget exceeded (\(String(format: "$%.2f", currentCost)) / \(String(format: "$%.2f", config.maxSessionCostUSD)))"
            if config.autoShutdownOnBudget {
                stopSession()
            }
            return
        }
        
        // Daily budget
        if todayCostUSD >= config.maxDailyCostUSD {
            budgetExceeded = true
            budgetWarning = "Daily budget exceeded (\(String(format: "$%.2f", todayCostUSD)) / \(String(format: "$%.2f", config.maxDailyCostUSD)))"
            if config.autoShutdownOnBudget {
                stopSession()
            }
            return
        }
        
        // Warning threshold
        let sessionPercent = config.maxSessionCostUSD > 0 ? (currentCost / config.maxSessionCostUSD) * 100 : 0
        let dailyPercent = config.maxDailyCostUSD > 0 ? (todayCostUSD / config.maxDailyCostUSD) * 100 : 0
        
        if sessionPercent >= config.warningThresholdPercent || dailyPercent >= config.warningThresholdPercent {
            budgetWarning = "Approaching budget limit (\(Int(max(sessionPercent, dailyPercent)))%)"
        } else {
            budgetWarning = nil
        }
        
        budgetExceeded = false
    }
    
    // MARK: - Session Management
    
    func startSession(instance: ComputeInstance) {
        let session = ComputeSession(
            id: UUID(),
            instance: instance,
            startTime: Date(),
            totalCostUSD: 0,
            status: .active
        )
        activeSession = session
        
        // Update instance status
        if let idx = instances.firstIndex(where: { $0.id == instance.id }) {
            var updated = instances[idx]
            updated = ComputeInstance(
                id: updated.id, provider: updated.provider, name: updated.name,
                gpuModel: updated.gpuModel, gpuMemoryGB: updated.gpuMemoryGB,
                cpuCores: updated.cpuCores, ramGB: updated.ramGB,
                costPerHourUSD: updated.costPerHourUSD, status: .running,
                endpoint: updated.endpoint, region: updated.region
            )
            instances[idx] = updated
        }
        
        // Record in flight recorder
        FlightRecorder.shared.record(
            actor: .user,
            action: .sessionStart,
            target: AuditTarget(type: "compute", path: instance.name),
            details: "Started \(instance.gpuModel) session on \(instance.provider.rawValue)",
            metadata: ["cost_per_hour": String(format: "%.2f", instance.costPerHourUSD)]
        )
    }
    
    func stopSession() {
        guard var session = activeSession else { return }
        session.endTime = Date()
        session.status = .completed
        
        let finalCost = (session.elapsedMinutes / 60.0) * session.instance.costPerHourUSD
        session.totalCostUSD = finalCost
        todayCostUSD += finalCost
        
        activeSession = nil
        
        // Record in flight recorder
        FlightRecorder.shared.record(
            actor: .system,
            action: .sessionEnd,
            target: AuditTarget(type: "compute", path: session.instance.name),
            details: "Session ended: \(session.elapsedFormatted), cost: \(String(format: "$%.4f", finalCost))"
        )
    }
    
    // MARK: - Instance Registration
    
    func addInstance(_ instance: ComputeInstance) {
        instances.append(instance)
    }
    
    func removeInstance(id: UUID) {
        instances.removeAll { $0.id == id }
    }
    
    // MARK: - Provider Quick-Connect
    
    func addRunPodInstance(apiKey: String, podId: String) {
        let instance = ComputeInstance(
            id: UUID(),
            provider: .runpod,
            name: "RunPod \(podId.prefix(8))",
            gpuModel: "GPU (fetching...)",
            gpuMemoryGB: 0,
            cpuCores: 0,
            ramGB: 0,
            costPerHourUSD: 0,
            status: .available,
            endpoint: "https://api.runpod.io/v2/\(podId)",
            region: "us"
        )
        instances.append(instance)
    }
    
    func addSSHRemote(host: String, user: String, port: Int = 22, gpuModel: String = "Unknown") {
        let instance = ComputeInstance(
            id: UUID(),
            provider: .sshRemote,
            name: "\(user)@\(host)",
            gpuModel: gpuModel,
            gpuMemoryGB: 0,
            cpuCores: 0,
            ramGB: 0,
            costPerHourUSD: 0,
            status: .available,
            endpoint: "\(user)@\(host):\(port)",
            region: "remote"
        )
        instances.append(instance)
    }
    
    // MARK: - Helpers
    
    private func parseVRAM(_ str: String) -> Int {
        // Parse strings like "16 GB", "8192 MB", etc.
        let cleaned = str.lowercased()
            .replacingOccurrences(of: " ", with: "")
        
        if cleaned.hasSuffix("gb") {
            let num = Int(cleaned.dropLast(2)) ?? 0
            return num * 1024
        }
        if cleaned.hasSuffix("mb") {
            return Int(cleaned.dropLast(2)) ?? 0
        }
        return Int(cleaned) ?? 0
    }
    
    // MARK: - Persistence
    
    private func persistCostGuard() {
        if let data = try? JSONEncoder().encode(costGuard) {
            UserDefaults.standard.set(data, forKey: "compute_fabric_cost_guard")
        }
    }
    
    private func loadCostGuard() {
        if let data = UserDefaults.standard.data(forKey: "compute_fabric_cost_guard"),
           let config = try? JSONDecoder().decode(CostGuardConfig.self, from: data) {
            costGuard = config
        }
    }
    
    deinit {
        gpuPollTimer?.invalidate()
        costTimer?.invalidate()
    }
}
