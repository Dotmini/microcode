//
//  PNSOrchestrator.swift
//  MicroCode
//
//  PNS Central & Autonomic Nervous System Orchestrator + Out-of-Process 24/7 Headless Daemon (`pnsd`).
//  Coordinates Prefrontal Cortex planning, Hippocampal REM Memory Consolidation,
//  Reward-Modulated Hebbian Synaptic Myelination, Autonomic Homeostasis, and AgentToolBox integration.
//
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation
import Network
import Combine
import Darwin

// MARK: - Headless CLI Entry Runner (`MicroCode --pns-daemon`)

public enum PNSDaemonRunner {
    /// Boots MicroCode in pure headless 24/7 background daemon mode without NSApplication windows or Dock icon.
    public static func runHeadlessDaemon(arguments: [String]) -> Never {
        // Ignore SIGHUP/SIGPIPE so terminal/parent closure never kills the 24/7 daemon
        Darwin.signal(SIGHUP, SIG_IGN)
        Darwin.signal(SIGPIPE, SIG_IGN)

        var port: UInt16 = 18890
        if let idx = arguments.firstIndex(of: "--pns-port"), idx + 1 < arguments.count,
           let parsed = UInt16(arguments[idx + 1]) {
            port = parsed
        }

        Task { @MainActor in
            PNSOrchestrator.shared.startAsHeadlessDaemonServer(port: port)
        }

        RunLoop.main.run()
        Darwin.exit(0)
    }
}

// MARK: - PNS Central & Autonomic Orchestrator

@MainActor
public final class PNSOrchestrator: ObservableObject {
    public static let shared = PNSOrchestrator()

    nonisolated public static let defaultDaemonPort: UInt16 = 18890
    nonisolated public static let launchAgentLabel = "com.dotmini.microcode.pnsd"

    // MARK: - Published Live State
    @Published public var autonomicMode: PNSAutonomicMode = .autoHomeostasis {
        didSet { persistAutonomicConfig() }
    }
    @Published public private(set) var effectiveAutonomicMode: PNSAutonomicMode = .sympathetic
    @Published public private(set) var metabolicBudgetIndex: Double = 0.94
    @Published public private(set) var thermalStateLabel: String = "Nominal"

    @Published public private(set) var synapses: [String: PNSSynapseEdge] = [:]
    @Published public private(set) var proceduralPlaybooks: [PNSProceduralPlaybook] = []
    @Published public private(set) var semanticInvariants: [PNSSemanticInvariant] = []
    @Published public private(set) var missions: [PNSMarathonMission] = []
    @Published public private(set) var recentSpikes: [PNSEpisodicSpike] = []
    @Published public private(set) var remConsolidationCycles: Int = 0

    // Out-of-Process Daemon Link State
    @Published public private(set) var isRunningAsHeadlessDaemon: Bool = false
    @Published public private(set) var remoteDaemonOnline: Bool = false
    @Published public private(set) var remoteDaemonPID: Int32 = 0
    @Published public private(set) var isLaunchAgentInstalled: Bool = false

    private let daemonStartedAt = Date()
    private var daemonPort: UInt16 = PNSOrchestrator.defaultDaemonPort
    private var nwListener: NWListener?
    private var autonomicHeartbeatTask: Task<Void, Never>?
    private var runningMissionTasks: [String: Task<Void, Never>] = [:]
    private var rateLimitPressure: Double = 0.0
    private var pendingPersistenceTask: Task<Void, Never>?

    // MARK: - Durable PNS Storage Paths (`~/.microcode/pns/`)

    public var pnsDirectoryURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".microcode/pns", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var synapsesURL: URL { pnsDirectoryURL.appendingPathComponent("synaptic_weights.json") }
    private var playbooksURL: URL { pnsDirectoryURL.appendingPathComponent("procedural_playbooks.json") }
    private var invariantsURL: URL { pnsDirectoryURL.appendingPathComponent("semantic_invariants.json") }
    private var missionsURL: URL { pnsDirectoryURL.appendingPathComponent("missions.json") }
    private var walURL: URL { pnsDirectoryURL.appendingPathComponent("synaptic_wal.jsonl") }
    private var configURL: URL { pnsDirectoryURL.appendingPathComponent("autonomic_config.json") }
    private var tokenURL: URL { pnsDirectoryURL.appendingPathComponent("daemon.token") }
    private var pidURL: URL { pnsDirectoryURL.appendingPathComponent("daemon.pid") }

    private var launchAgentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.launchAgentLabel).plist")
    }

    private init() {
        loadDurableStateFromDisk()
        refreshLaunchAgentStatus()
        updateHomeostasisMetrics()
        startUIOrDaemonHeartbeat()
    }

    // MARK: - 1. Localhost Authentication Token (`0600` POSIX Permissions)

    private func loadOrCreateDaemonToken() -> String {
        if let existing = try? String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           existing.count >= 24 {
            return existing
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "") +
                    UUID().uuidString.replacingOccurrences(of: "-", with: "")
        try? token.write(to: tokenURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
        return token
    }

    // MARK: - 2. Out-of-Process 24/7 Headless Daemon Server (`127.0.0.1:18890`)

    public func startAsHeadlessDaemonServer(port: UInt16 = PNSOrchestrator.defaultDaemonPort) {
        self.isRunningAsHeadlessDaemon = true
        self.daemonPort = port
        let pid = ProcessInfo.processInfo.processIdentifier
        self.remoteDaemonPID = pid
        self.remoteDaemonOnline = true
        try? "\(pid)".write(to: pidURL, atomically: true, encoding: .utf8)
        _ = loadOrCreateDaemonToken()

        startLocalhostIPCListener(port: port)

        recordSpike(
            kind: .homeostasisShift,
            tract: .spinalReflex,
            summary: "Out-of-process 24/7 daemon `microcode-pnsd` booted (PID \(pid), 127.0.0.1:\(port)).",
            salience: 0.9
        )

        // Automatically resume any incomplete marathon missions from durable WAL/checkpoint
        for index in missions.indices {
            if missions[index].status == .running || missions[index].status == .queued || missions[index].status == .consolidatingREM {
                let missionId = missions[index].id
                spawnMissionExecutionLoop(missionId: missionId)
            }
        }
    }

    private func startLocalhostIPCListener(port: UInt16) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)

        do {
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .global(qos: .userInitiated))
                self?.receiveHTTPRequest(on: conn)
            }
            listener.start(queue: .global(qos: .userInitiated))
            self.nwListener = listener
        } catch {
            print("[PNS Daemon] Failed to bind 127.0.0.1:\(port): \(error)")
        }
    }

    nonisolated private func receiveHTTPRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty else {
                connection.cancel()
                return
            }
            let rawReq = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                let responseData = await self.handleDaemonHTTPRequest(rawReq)
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func handleDaemonHTTPRequest(_ raw: String) async -> Data {
        let parts = raw.components(separatedBy: "\r\n\r\n")
        let headerBlock = parts.first ?? ""
        let bodyString = parts.dropFirst().joined(separator: "\r\n\r\n")
        let headerLines = headerBlock.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else {
            return Self.httpJSONResponse(status: 400, json: ["error": "Malformed request"])
        }
        let reqTokens = requestLine.split(separator: " ")
        let method = reqTokens.first.map(String.init) ?? "GET"
        let path = reqTokens.count > 1 ? String(reqTokens[1]) : "/"

        // Verify X-PNS-Token header
        let expectedToken = loadOrCreateDaemonToken()
        var suppliedToken = ""
        for line in headerLines.dropFirst() {
            if line.lowercased().hasPrefix("x-pns-token:") {
                suppliedToken = line.dropFirst("x-pns-token:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        guard suppliedToken == expectedToken else {
            return Self.httpJSONResponse(status: 401, json: ["error": "Unauthorized PNS token"])
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        switch (method, path) {
        case ("GET", "/pns/status"):
            let snap = buildStatusSnapshot()
            if let encoded = try? encoder.encode(snap) {
                return Self.httpRawJSONResponse(status: 200, body: encoded)
            }
            return Self.httpJSONResponse(status: 500, json: ["error": "Snapshot encode error"])

        case ("POST", "/pns/missions/start"):
            guard let bodyData = bodyString.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let objective = payload["objective"] as? String, !objective.isEmpty else {
                return Self.httpJSONResponse(status: 400, json: ["error": "Missing objective"])
            }
            let ws = payload["workspace_path"] as? String ?? FileManager.default.currentDirectoryPath
            let policyRaw = payload["branch_policy"] as? String ?? PNSBranchSafetyPolicy.isolatedWorktreeBranch.rawValue
            let policy = PNSBranchSafetyPolicy(rawValue: policyRaw) ?? .isolatedWorktreeBranch
            let verifyCmd = payload["verification_command"] as? String
            let mission = startLocalMission(
                objective: objective,
                workspacePath: ws,
                branchPolicy: policy,
                verificationCommand: verifyCmd
            )
            if let encoded = try? encoder.encode(mission) {
                return Self.httpRawJSONResponse(status: 200, body: encoded)
            }
            return Self.httpJSONResponse(status: 200, json: ["mission_id": mission.id])

        case ("POST", "/pns/missions/control"):
            guard let bodyData = bodyString.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let missionId = payload["mission_id"] as? String,
                  let action = payload["action"] as? String else {
                return Self.httpJSONResponse(status: 400, json: ["error": "Missing mission_id or action"])
            }
            controlLocalMission(missionId: missionId, action: action)
            return Self.httpJSONResponse(status: 200, json: ["ok": true, "mission_id": missionId, "action": action])

        case ("POST", "/pns/consolidate"):
            let bodyData = bodyString.data(using: .utf8) ?? Data()
            let payload = (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]) ?? [:]
            let ws = payload["workspace_path"] as? String
            let report = await runREMConsolidationCycle(projectPath: ws, missionId: nil)
            return Self.httpJSONResponse(status: 200, json: ["ok": true, "report": report])

        case ("POST", "/pns/mode"):
            if let bodyData = bodyString.data(using: .utf8),
               let payload = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let rawMode = payload["mode"] as? String,
               let parsed = PNSAutonomicMode(rawValue: rawMode) {
                self.autonomicMode = parsed
                updateHomeostasisMetrics()
            }
            return Self.httpJSONResponse(status: 200, json: ["ok": true, "mode": autonomicMode.rawValue])

        case ("POST", "/pns/shutdown"):
            saveDurableStateNow()
            Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                try? FileManager.default.removeItem(at: self.pidURL)
                Darwin.exit(0)
            }
            return Self.httpJSONResponse(status: 200, json: ["ok": true, "shutting_down": true])

        default:
            return Self.httpJSONResponse(status: 404, json: ["error": "Unknown PNS endpoint \(path)"])
        }
    }

    nonisolated private static func httpJSONResponse(status: Int, json: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        return httpRawJSONResponse(status: status, body: body)
    }

    nonisolated private static func httpRawJSONResponse(status: Int, body: Data) -> Data {
        let statusText = status == 200 ? "OK" : (status == 401 ? "Unauthorized" : "Error")
        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(body)
        return out
    }

    // MARK: - 3. Spawning & Attaching to Detached Out-of-Process `pnsd` + `launchd`

    /// Spawns `MicroCode --pns-daemon` in its own detached POSIX process group (`POSIX_SPAWN_SETPGROUP`)
    /// so `Cmd+Q` or termination of `MicroCode.app` NEVER terminates the 24/7 PNS daemon!
    @discardableResult
    public func ensureOutOfProcessDaemonRunning() async -> Bool {
        if isRunningAsHeadlessDaemon { return true }
        if await pollRemoteDaemonOnce() { return true }

        guard let execPath = Bundle.main.executableURL?.path,
              FileManager.default.isExecutableFile(atPath: execPath) else {
            return false
        }

        _ = loadOrCreateDaemonToken()
        let logPath = pnsDirectoryURL.appendingPathComponent("pnsd.log").path

        var pid: pid_t = 0
        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)

        var fileActions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, logPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, logPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)

        let cArgs: [UnsafeMutablePointer<CChar>?] = [
            strdup(execPath),
            strdup("--pns-daemon"),
            strdup("--pns-port"),
            strdup("\(daemonPort)"),
            nil
        ]
        defer {
            for ptr in cArgs { if let ptr { free(ptr) } }
            posix_spawnattr_destroy(&attr)
            posix_spawn_file_actions_destroy(&fileActions)
        }

        let spawnRes = cArgs.withUnsafeBufferPointer { argvBuf in
            posix_spawn(&pid, execPath, &fileActions, &attr, argvBuf.baseAddress, environ)
        }
        guard spawnRes == 0 else { return false }

        // Poll up to 2.5 seconds for localhost IPC handshake
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if await pollRemoteDaemonOnce() {
                return true
            }
        }
        return false
    }

    public func stopOutOfProcessDaemon() async {
        guard !isRunningAsHeadlessDaemon else { return }
        _ = try? await sendDaemonIPC(method: "POST", path: "/pns/shutdown", body: [:])
        remoteDaemonOnline = false
        remoteDaemonPID = 0
    }

    @discardableResult
    public func pollRemoteDaemonOnce() async -> Bool {
        if isRunningAsHeadlessDaemon { return true }
        guard let data = try? await sendDaemonIPC(method: "GET", path: "/pns/status", body: nil) else {
            remoteDaemonOnline = false
            remoteDaemonPID = 0
            return false
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snap = try? decoder.decode(PNSDaemonStatusSnapshot.self, from: data) else {
            remoteDaemonOnline = false
            return false
        }
        remoteDaemonOnline = true
        remoteDaemonPID = snap.daemonPID
        // Sync out-of-process mission & memory updates back into GUI observer seamlessly
        self.missions = snap.missions
        if !snap.recentSpikes.isEmpty {
            self.recentSpikes = snap.recentSpikes
        }
        self.remConsolidationCycles = max(self.remConsolidationCycles, snap.remConsolidationCycles)
        return true
    }

    private func sendDaemonIPC(method: String, path: String, body: [String: Any]?) async throws -> Data {
        guard let url = URL(string: "http://127.0.0.1:\(daemonPort)\(path)") else {
            throw URLError(.badURL)
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 3.0
        let session = URLSession(configuration: config)

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(loadOrCreateDaemonToken(), forHTTPHeaderField: "X-PNS-Token")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - macOS `launchd` 24/7 Keep-Alive Agent (`~/Library/LaunchAgents`)

    public func refreshLaunchAgentStatus() {
        isLaunchAgentInstalled = FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
    }

    @discardableResult
    public func setLaunchAgentEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            let appExec = FileManager.default.isExecutableFile(atPath: "/Applications/MicroCode.app/Contents/MacOS/MicroCode")
                ? "/Applications/MicroCode.app/Contents/MacOS/MicroCode"
                : (Bundle.main.executableURL?.path ?? "/Applications/MicroCode.app/Contents/MacOS/MicroCode")
            let logPath = pnsDirectoryURL.appendingPathComponent("pnsd.log").path

            let plistXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(Self.launchAgentLabel)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(appExec)</string>
                    <string>--pns-daemon</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <true/>
                <key>ProcessType</key>
                <string>Background</string>
                <key>StandardOutPath</key>
                <string>\(logPath)</string>
                <key>StandardErrorPath</key>
                <string>\(logPath)</string>
            </dict>
            </plist>
            """
            do {
                try FileManager.default.createDirectory(
                    at: launchAgentPlistURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try plistXML.write(to: launchAgentPlistURL, atomically: true, encoding: .utf8)
                _ = await PNSMotorWorktreePlexus.runShell(
                    command: "launchctl unload \"\(launchAgentPlistURL.path)\" 2>/dev/null; launchctl load -w \"\(launchAgentPlistURL.path)\"",
                    cwd: FileManager.default.homeDirectoryForCurrentUser.path
                )
                refreshLaunchAgentStatus()
                _ = await pollRemoteDaemonOnce()
                return isLaunchAgentInstalled
            } catch {
                return false
            }
        } else {
            _ = await PNSMotorWorktreePlexus.runShell(
                command: "launchctl unload -w \"\(launchAgentPlistURL.path)\" 2>/dev/null",
                cwd: FileManager.default.homeDirectoryForCurrentUser.path
            )
            try? FileManager.default.removeItem(at: launchAgentPlistURL)
            refreshLaunchAgentStatus()
            await stopOutOfProcessDaemon()
            return true
        }
    }

    // MARK: - 4. Autonomic Homeostasis & Metabolic Pacing Engine

    private func startUIOrDaemonHeartbeat() {
        autonomicHeartbeatTask?.cancel()
        autonomicHeartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000) // Every 6s
                guard let self else { return }
                self.updateHomeostasisMetrics()
                if self.isRunningAsHeadlessDaemon {
                    // In Parasympathetic mode, periodically hibernate idle MCP stdio processes (>5 min idle)
                    let idleCutoff: TimeInterval = self.effectiveAutonomicMode == .parasympathetic ? 180 : 420
                    let hibernated = PNSGanglionRouter.shared.hibernateIdleMCPServers(idleThresholdSeconds: idleCutoff)
                    if !hibernated.isEmpty {
                        self.recordSpike(
                            kind: .homeostasisShift,
                            tract: .spinalReflex,
                            summary: "Parasympathetic Homeostasis hibernated \(hibernated.count) idle MCP process(es) [\(hibernated.joined(separator: ", "))] to reclaim RAM.",
                            salience: 0.45
                        )
                    }
                } else {
                    _ = await self.pollRemoteDaemonOnce()
                }
            }
        }
    }

    public func updateHomeostasisMetrics() {
        let thermal = ProcessInfo.processInfo.thermalState
        let thermalFactor: Double
        switch thermal {
        case .nominal:
            thermalFactor = 1.0
            thermalStateLabel = "Nominal"
        case .fair:
            thermalFactor = 0.84
            thermalStateLabel = "Fair"
        case .serious:
            thermalFactor = 0.48
            thermalStateLabel = "Serious (Throttling)"
        case .critical:
            thermalFactor = 0.22
            thermalStateLabel = "Critical (Cool-Down)"
        @unknown default:
            thermalFactor = 0.90
            thermalStateLabel = "Nominal"
        }

        // Decay transient rate-limit pressure smoothly
        rateLimitPressure = max(0.0, rateLimitPressure * 0.88)
        let rawIndex = thermalFactor * (1.0 - min(0.65, rateLimitPressure))
        metabolicBudgetIndex = min(1.0, max(0.10, rawIndex))

        switch autonomicMode {
        case .sympathetic:
            effectiveAutonomicMode = thermal == .critical ? .parasympathetic : .sympathetic
        case .parasympathetic:
            effectiveAutonomicMode = .parasympathetic
        case .autoHomeostasis:
            effectiveAutonomicMode = (metabolicBudgetIndex >= 0.58) ? .sympathetic : .parasympathetic
        }
    }

    public var maxConcurrentMotorFibers: Int {
        switch effectiveAutonomicMode {
        case .sympathetic: return metabolicBudgetIndex > 0.80 ? 3 : 2
        case .parasympathetic: return 1
        case .autoHomeostasis: return 2
        }
    }

    // MARK: - 5. Synaptic Plasticity (Reward-Modulated Hebbian Myelination W_e)

    public func lookupSynapse(
        taskCategory: String,
        tract: PNSNerveTractKind,
        targetNodeId: String,
        projectPath: String?
    ) -> PNSSynapseEdge? {
        let key = PNSSynapseEdge.makeID(
            taskCategory: taskCategory,
            tract: tract,
            targetNodeId: targetNodeId,
            projectPath: projectPath
        )
        return synapses[key]
    }

    public func recordSynapticFeedback(
        taskPrompt: String,
        tract: PNSNerveTractKind,
        targetNodeId: String,
        projectPath: String?,
        succeeded: Bool,
        tokensUsed: Int,
        latencyMs: Int,
        regressionPenalty: Double = 1.0
    ) {
        let category = PNSGanglionRouter.classifyTaskCategory(taskPrompt)
        let key = PNSSynapseEdge.makeID(
            taskCategory: category,
            tract: tract,
            targetNodeId: targetNodeId,
            projectPath: projectPath
        )
        var edge = synapses[key] ?? PNSSynapseEdge(
            taskCategory: category,
            tract: tract,
            targetNodeId: targetNodeId,
            projectPath: projectPath
        )
        let wasMyelinated = edge.isMyelinated
        edge.applyHebbianImpulse(
            succeeded: succeeded,
            verifiedProgress: succeeded ? 1.0 : 0.0,
            tokensUsed: tokensUsed,
            latencyMs: latencyMs,
            regressionPenalty: regressionPenalty
        )
        synapses[key] = edge

        if !wasMyelinated && edge.isMyelinated {
            recordSpike(
                kind: .ganglionRoute,
                tract: tract,
                projectPath: projectPath,
                summary: "Synapse MYELINATED (W_e=\(String(format: "%.2f", edge.weight))): [\(category) -> \(targetNodeId)] promoted to Fast-Path!",
                salience: 0.88,
                latencyMs: latencyMs,
                succeeded: true
            )
        }
        scheduleDurableSave()
    }

    public var myelinatedSynapses: [PNSSynapseEdge] {
        synapses.values.filter(\.isMyelinated).sorted { $0.weight > $1.weight }
    }

    public var inhibitedSynapses: [PNSSynapseEdge] {
        synapses.values.filter(\.isInhibited).sorted { $0.weight < $1.weight }
    }

    // MARK: - 6. Hippocampal Replay & REM Sleep Consolidation (Anti-Context-Rot)

    @discardableResult
    public func runREMConsolidationCycle(projectPath: String?, missionId: String?) async -> String {
        let startMs = DispatchTime.now().uptimeNanoseconds
        let scopedSpikes = recentSpikes.filter { spike in
            if let mId = missionId, spike.missionId == mId { return true }
            if let ws = projectPath, !ws.isEmpty, spike.projectPath == ws { return true }
            return projectPath == nil && missionId == nil
        }

        let successfulSpikes = scopedSpikes.filter { $0.succeeded && $0.salience >= 0.45 }
        let failedSpikes = scopedSpikes.filter { !$0.succeeded }

        var newPlaybooks = 0
        var newInhibitions = 0

        // 1. Distill repeated high-salience winning trajectories into Tier-2 Procedural Playbooks
        let groupedByTract = Dictionary(grouping: successfulSpikes, by: \.tract)
        for (tract, spikes) in groupedByTract where spikes.count >= 2 {
            let sig = "\(tract.shortBadge):\(spikes.last?.summary.prefix(48) ?? "workflow")"
            if let idx = proceduralPlaybooks.firstIndex(where: { $0.tract == tract && $0.projectPath == projectPath }) {
                proceduralPlaybooks[idx].executionWins += 1
                proceduralPlaybooks[idx].confidenceWeight = min(0.99, proceduralPlaybooks[idx].confidenceWeight + 0.04)
                proceduralPlaybooks[idx].distilledStrategy = spikes.suffix(3).map(\.summary).joined(separator: " -> ")
                proceduralPlaybooks[idx].updatedAt = Date()
            } else {
                let playbook = PNSProceduralPlaybook(
                    triggerSignature: String(sig),
                    projectPath: projectPath,
                    tract: tract,
                    toolSequence: spikes.suffix(4).map { $0.kind.rawValue },
                    distilledStrategy: spikes.suffix(3).map(\.summary).joined(separator: " -> "),
                    verificationCheck: "Verify zero LSP errors & isolated worktree build/test pass"
                )
                proceduralPlaybooks.append(playbook)
                newPlaybooks += 1
            }
        }

        // 2. Distill dead-ends / spinal circuit breaks into Tier-3 Semantic Inhibition Warnings
        if let ws = projectPath, !ws.isEmpty {
            for fail in failedSpikes.suffix(3) where fail.kind == .nociceptivePain || fail.kind == .spinalReflex {
                let alreadyRecorded = semanticInvariants.contains {
                    $0.projectPath == ws && $0.ruleStatement == fail.summary
                }
                if !alreadyRecorded {
                    semanticInvariants.append(
                        PNSSemanticInvariant(
                            projectPath: ws,
                            moduleScope: fail.tract.shortBadge,
                            ruleStatement: fail.summary,
                            isInhibitionWarning: true
                        )
                    )
                    newInhibitions += 1
                }
            }
        }

        // 3. Prune raw episodic spike noise down to top-salience recent spikes (eliminates Context Rot)
        if recentSpikes.count > 48 {
            recentSpikes = Array(recentSpikes.suffix(48))
        }
        if proceduralPlaybooks.count > 64 {
            proceduralPlaybooks.sort { $0.confidenceWeight > $1.confidenceWeight }
            proceduralPlaybooks = Array(proceduralPlaybooks.prefix(64))
        }
        if semanticInvariants.count > 80 {
            semanticInvariants = Array(semanticInvariants.suffix(80))
        }

        remConsolidationCycles += 1
        let elapsedMs = max(1, Int((DispatchTime.now().uptimeNanoseconds - startMs) / 1_000_000))
        let summary = "REM Consolidation Cycle #\(remConsolidationCycles) (\(elapsedMs)ms): +\(newPlaybooks) Procedural Playbooks, +\(newInhibitions) Inhibition Guards, active episodic buffer pruned."

        recordSpike(
            kind: .remConsolidation,
            tract: .hippocampalREM,
            missionId: missionId,
            projectPath: projectPath,
            summary: summary,
            salience: 0.75,
            latencyMs: elapsedMs,
            succeeded: true
        )
        saveDurableStateNow()
        return summary
    }

    /// Builds a compact, project-isolated PNS Synaptic & Procedural Context augmentation block (<450 tokens)
    /// injected automatically into `AgentService.buildSystemPrompt`.
    public func promptMemoryAugmentation(for query: String, workspacePath: String?) -> String {
        var sections: [String] = []

        // 1. Efferent MCP Nerve Tract Directory
        let tractDir = PNSGanglionRouter.shared.buildCompactTractDirectorySnippet()
        if !tractDir.isEmpty {
            sections.append(tractDir)
        }

        // 2. Strict Project-Scoped Myelinated Procedural Playbooks
        let matchingPlaybooks = proceduralPlaybooks
            .filter { pb in
                guard let ws = workspacePath, !ws.isEmpty else { return pb.projectPath == nil }
                return pb.projectPath == ws
            }
            .sorted { $0.confidenceWeight > $1.confidenceWeight }
            .prefix(3)

        if !matchingPlaybooks.isEmpty {
            var lines = ["### PNS Myelinated Procedural Playbooks (Verified Fast-Paths)"]
            for pb in matchingPlaybooks {
                lines.append("- [\(pb.tract.shortBadge) • W=\(String(format: "%.2f", pb.confidenceWeight)) • \(pb.executionWins) wins]: \(pb.distilledStrategy)")
            }
            sections.append(lines.joined(separator: "\n"))
        }

        // 3. Strict Project-Scoped Semantic Invariants & LTD Inhibitions
        if let ws = workspacePath, !ws.isEmpty {
            let guards = semanticInvariants.filter { $0.projectPath == ws }.suffix(4)
            if !guards.isEmpty {
                var lines = ["### PNS Synaptic Invariants & LTD Inhibitions (Do Not Repeat Dead-Ends)"]
                for g in guards {
                    let prefix = g.isInhibitionWarning ? "⛔ INHIBITED" : "🔒 INVARIANT"
                    lines.append("- \(prefix) [\(g.moduleScope)]: \(g.ruleStatement)")
                }
                sections.append(lines.joined(separator: "\n"))
            }
        }

        guard !sections.isEmpty else { return "" }
        return "\n\n## PNS (Pseudo Neural System — Active Cognitive Architecture)\n" + sections.joined(separator: "\n\n")
    }

    // MARK: - 7. 24/7 Marathon Mission Dispatch & Execution Loop

    /// Dispatches a 24/7 Marathon Mission — automatically routing to the out-of-process `pnsd` daemon
    /// so execution survives `MicroCode.app` `Cmd+Q` / termination!
    @discardableResult
    public func dispatchMarathonMission(
        objective: String,
        workspacePath: String,
        branchPolicy: PNSBranchSafetyPolicy = .isolatedWorktreeBranch,
        verificationCommand: String? = nil,
        preferOutOfProcessDaemon: Bool = true
    ) async -> PNSMarathonMission {
        if preferOutOfProcessDaemon && !isRunningAsHeadlessDaemon {
            let daemonReady = await ensureOutOfProcessDaemonRunning()
            if daemonReady {
                var payload: [String: Any] = [
                    "objective": objective,
                    "workspace_path": workspacePath,
                    "branch_policy": branchPolicy.rawValue
                ]
                if let verificationCommand, !verificationCommand.isEmpty {
                    payload["verification_command"] = verificationCommand
                }
                if let respData = try? await sendDaemonIPC(method: "POST", path: "/pns/missions/start", body: payload) {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    if let remoteMission = try? decoder.decode(PNSMarathonMission.self, from: respData) {
                        if let idx = missions.firstIndex(where: { $0.id == remoteMission.id }) {
                            missions[idx] = remoteMission
                        } else {
                            missions.insert(remoteMission, at: 0)
                        }
                        return remoteMission
                    }
                }
            }
        }
        return startLocalMission(
            objective: objective,
            workspacePath: workspacePath,
            branchPolicy: branchPolicy,
            verificationCommand: verificationCommand
        )
    }

    public func controlMission(missionId: String, action: String) async {
        if !isRunningAsHeadlessDaemon && remoteDaemonOnline {
            _ = try? await sendDaemonIPC(
                method: "POST",
                path: "/pns/missions/control",
                body: ["mission_id": missionId, "action": action]
            )
            _ = await pollRemoteDaemonOnce()
            return
        }
        controlLocalMission(missionId: missionId, action: action)
    }

    @discardableResult
    public func startLocalMission(
        objective: String,
        workspacePath: String,
        branchPolicy: PNSBranchSafetyPolicy,
        verificationCommand: String?
    ) -> PNSMarathonMission {
        let titleLine = objective.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "24/7 PNS Mission"
        let mission = PNSMarathonMission(
            id: UUID().uuidString,
            title: String(titleLine.prefix(76)),
            objective: objective,
            workspacePath: workspacePath,
            branchPolicy: branchPolicy,
            verificationCommand: verificationCommand,
            status: .queued,
            subtasks: [],
            activeFibers: [],
            completedEpisodes: 0,
            remConsolidationsCount: 0,
            spinalReflexSavesCount: 0,
            distilledWorkingMemory: "GOAL ANCHOR: \(objective)",
            createdAt: Date(),
            updatedAt: Date(),
            lastError: nil
        )
        missions.insert(mission, at: 0)
        saveDurableStateNow()
        spawnMissionExecutionLoop(missionId: mission.id)
        return mission
    }

    private func controlLocalMission(missionId: String, action: String) {
        guard let idx = missions.firstIndex(where: { $0.id == missionId }) else { return }
        switch action.lowercased() {
        case "pause":
            runningMissionTasks[missionId]?.cancel()
            runningMissionTasks.removeValue(forKey: missionId)
            missions[idx].status = .paused
            missions[idx].updatedAt = Date()
        case "resume":
            missions[idx].status = .running
            missions[idx].updatedAt = Date()
            spawnMissionExecutionLoop(missionId: missionId)
        case "cancel":
            runningMissionTasks[missionId]?.cancel()
            runningMissionTasks.removeValue(forKey: missionId)
            missions[idx].status = .cancelled
            missions[idx].updatedAt = Date()
        default:
            break
        }
        saveDurableStateNow()
    }

    private func spawnMissionExecutionLoop(missionId: String) {
        runningMissionTasks[missionId]?.cancel()
        runningMissionTasks[missionId] = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.executeMissionLoop(missionId: missionId)
        }
    }

    private func executeMissionLoop(missionId: String) async {
        guard let mIdx = missions.firstIndex(where: { $0.id == missionId }) else { return }
        missions[mIdx].status = .running
        missions[mIdx].updatedAt = Date()
        saveDurableStateNow()

        let objective = missions[mIdx].objective
        let workspacePath = missions[mIdx].workspacePath

        // Step 1: Prefrontal Cortex Neural Decomposition (if subtasks empty)
        if missions[mIdx].subtasks.isEmpty {
            let planned = await planMissionSubtasks(objective: objective, workspacePath: workspacePath)
            guard let idx = missions.firstIndex(where: { $0.id == missionId }) else { return }
            missions[idx].subtasks = planned
            missions[idx].updatedAt = Date()
            saveDurableStateNow()
        }

        // Step 2: Iterative Parallel Motor Fiber Execution + REM Consolidation
        while !Task.isCancelled {
            guard let idx = missions.firstIndex(where: { $0.id == missionId }) else { return }
            if missions[idx].status == .paused || missions[idx].status == .cancelled { return }

            updateHomeostasisMetrics()
            let completedIds = Set(missions[idx].subtasks.filter { $0.status == .completed }.map(\.id))

            // Find all pending subtasks whose dependencies are satisfied
            let readyIndices = missions[idx].subtasks.indices.filter { sIdx in
                let st = missions[idx].subtasks[sIdx]
                guard st.status == .queued || (st.status == .failed && st.attempts < 2) else { return false }
                return st.dependencies.allSatisfy { completedIds.contains($0) }
            }

            if readyIndices.isEmpty {
                let allDone = missions[idx].subtasks.allSatisfy { $0.status == .completed }
                missions[idx].status = allDone ? .completed : .failed
                missions[idx].updatedAt = Date()
                _ = await runREMConsolidationCycle(projectPath: workspacePath, missionId: missionId)
                saveDurableStateNow()
                runningMissionTasks.removeValue(forKey: missionId)
                return
            }

            // Modulate concurrency by Autonomic Homeostasis
            let batchIndices = Array(readyIndices.prefix(maxConcurrentMotorFibers))
            var subtasksBatch: [PNSMissionSubtask] = []
            for sIdx in batchIndices {
                missions[idx].subtasks[sIdx].status = .running
                missions[idx].subtasks[sIdx].attempts += 1
                subtasksBatch.append(missions[idx].subtasks[sIdx])
            }
            saveDurableStateNow()

            // Dispatch parallel isolated Git-Worktree Motor Fibers
            await withTaskGroup(of: (String, Bool, String, String?).self) { group in
                for subtask in subtasksBatch {
                    let branchPolicy = missions[idx].branchPolicy
                    let verifyCmd = missions[idx].verificationCommand
                    let workingMem = missions[idx].distilledWorkingMemory

                    group.addTask { @MainActor in
                        await self.executeSingleMotorFiberSubtask(
                            missionId: missionId,
                            subtask: subtask,
                            workspacePath: workspacePath,
                            branchPolicy: branchPolicy,
                            verificationCommand: verifyCmd,
                            distilledWorkingMemory: workingMem
                        )
                    }
                }

                for await (subtaskId, passed, summary, branchName) in group {
                    guard let curIdx = self.missions.firstIndex(where: { $0.id == missionId }),
                          let sIdx = self.missions[curIdx].subtasks.firstIndex(where: { $0.id == subtaskId }) else {
                        continue
                    }
                    self.missions[curIdx].subtasks[sIdx].status = passed ? .completed : .failed
                    self.missions[curIdx].subtasks[sIdx].resultSummary = summary
                    self.missions[curIdx].subtasks[sIdx].worktreeBranch = branchName
                    self.missions[curIdx].completedEpisodes += 1
                    self.missions[curIdx].updatedAt = Date()
                }
            }

            // Step 3: Hippocampal REM Memory Consolidation every 3 episodes (prevents 24/7 Context Rot!)
            if let curIdx = missions.firstIndex(where: { $0.id == missionId }),
               missions[curIdx].completedEpisodes > 0,
               missions[curIdx].completedEpisodes % 3 == 0 {
                missions[curIdx].status = .consolidatingREM
                _ = await runREMConsolidationCycle(projectPath: workspacePath, missionId: missionId)
                if let postIdx = missions.firstIndex(where: { $0.id == missionId }) {
                    missions[postIdx].remConsolidationsCount += 1
                    let completedSummaries = missions[postIdx].subtasks
                        .filter { $0.status == .completed }
                        .map { "- [✓] \($0.title): \(($0.resultSummary ?? "verified").prefix(140))" }
                        .joined(separator: "\n")
                    missions[postIdx].distilledWorkingMemory = """
                    GOAL ANCHOR: \(objective)
                    VERIFIED PROGRESS LEDGER:
                    \(completedSummaries)
                    """
                    missions[postIdx].status = .running
                }
            }
            saveDurableStateNow()
        }
    }

    private func executeSingleMotorFiberSubtask(
        missionId: String,
        subtask: PNSMissionSubtask,
        workspacePath: String,
        branchPolicy: PNSBranchSafetyPolicy,
        verificationCommand: String?,
        distilledWorkingMemory: String
    ) async -> (subtaskId: String, passed: Bool, summary: String, branchName: String?) {
        let startNs = DispatchTime.now().uptimeNanoseconds

        do {
            let lease = try await PNSMotorWorktreePlexus.shared.allocateMotorFiber(
                missionId: missionId,
                agentArchetype: subtask.assignedArchetype,
                roleTitle: subtask.title,
                baseWorkspacePath: workspacePath,
                ownedPaths: subtask.ownedPaths
            )
            if let mIdx = missions.firstIndex(where: { $0.id == missionId }) {
                missions[mIdx].activeFibers.append(lease)
            }

            recordSpike(
                kind: .motorFiberSpawn,
                tract: lease.tract,
                missionId: missionId,
                projectPath: workspacePath,
                summary: "Spawned Motor Fiber [\(subtask.assignedArchetype)] on isolated worktree branch `\(lease.branchName)`.",
                salience: 0.65
            )

            let fiberPrompt = """
            \(distilledWorkingMemory)

            ## Current Scoped Motor Fiber Subtask
            Title: \(subtask.title)
            Instructions: \(subtask.description)
            Isolated Worktree Path: \(lease.isolatedWorktreePath)
            \(subtask.ownedPaths.isEmpty ? "" : "Owned File Scope: \(subtask.ownedPaths.joined(separator: ", "))")
            \(promptMemoryAugmentation(for: subtask.description, workspacePath: workspacePath))
            """

            let instance = AgentExecutionContext.$workspaceRoot.withValue(lease.isolatedWorktreePath) {
                SubAgentHarness.shared.invokeSubagent(
                    typeName: subtask.assignedArchetype,
                    role: subtask.title,
                    prompt: fiberPrompt,
                    workspacePath: lease.isolatedWorktreePath,
                    ownedPaths: subtask.ownedPaths
                )
            }

            let outcome = try await SubAgentHarness.shared.waitForSubagent(id: instance.id)
            let subagentSucceeded = (outcome?.instance.state == .completed)
            let rawReport = outcome?.instance.finalReport ?? outcome?.instance.stateDetail ?? "Subtask finished"

            let joinRes = await PNSMotorWorktreePlexus.shared.verifyAndJoinFiber(
                fiberId: lease.id,
                branchPolicy: branchPolicy,
                verificationCommand: verificationCommand,
                fiberSummary: rawReport
            )

            let finalSuccess = subagentSucceeded && joinRes.verificationPassed
            let elapsedMs = max(1, Int((DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000))
            let tokensUsed = outcome?.instance.tokensUsed ?? 800

            recordSynapticFeedback(
                taskPrompt: subtask.description,
                tract: lease.tract,
                targetNodeId: "agent:\(subtask.assignedArchetype)",
                projectPath: workspacePath,
                succeeded: finalSuccess,
                tokensUsed: tokensUsed,
                latencyMs: elapsedMs,
                regressionPenalty: joinRes.verificationPassed ? 0.8 : 1.5
            )

            if !finalSuccess {
                let reflex = PNSGanglionRouter.shared.evaluateSpinalReflex(
                    toolOrProviderName: "agent:\(subtask.assignedArchetype)",
                    targetHint: subtask.title,
                    errorMessage: joinRes.verificationSpike
                )
                if reflex.action != .none {
                    if case .switchProviderEndpoint(_, let cooldownMs) = reflex.action {
                        rateLimitPressure = min(0.85, rateLimitPressure + 0.30)
                        try? await Task.sleep(nanoseconds: cooldownMs * 1_000_000)
                    } else if case .circuitBreakBehavioralFixation(_, let rule) = reflex.action {
                        _ = await PNSMotorWorktreePlexus.shared.rollbackFiberToCleanCheckpoint(fiberId: lease.id)
                        semanticInvariants.append(
                            PNSSemanticInvariant(
                                projectPath: workspacePath,
                                moduleScope: subtask.title,
                                ruleStatement: rule,
                                isInhibitionWarning: true
                            )
                        )
                    }
                    if let mIdx = missions.firstIndex(where: { $0.id == missionId }) {
                        missions[mIdx].spinalReflexSavesCount += 1
                    }
                    recordSpike(
                        kind: .spinalReflex,
                        tract: .spinalReflex,
                        missionId: missionId,
                        projectPath: workspacePath,
                        summary: reflex.summary,
                        salience: 0.92,
                        latencyMs: reflex.latencyMs,
                        succeeded: true
                    )
                }
            } else {
                recordSpike(
                    kind: .motorFiberMerge,
                    tract: lease.tract,
                    missionId: missionId,
                    projectPath: workspacePath,
                    summary: "Motor Fiber [\(subtask.assignedArchetype)] verified (\(joinRes.modifiedFiles.count) file(s), merged=\(joinRes.mergedToTrunk), branch=\(joinRes.committedBranch ?? lease.branchName)).",
                    salience: 0.85,
                    latencyMs: elapsedMs,
                    succeeded: true
                )
            }

            return (subtask.id, finalSuccess, String(rawReport.prefix(400)), joinRes.committedBranch ?? lease.branchName)
        } catch {
            let reflex = PNSGanglionRouter.shared.evaluateSpinalReflex(
                toolOrProviderName: "agent:\(subtask.assignedArchetype)",
                targetHint: subtask.title,
                errorMessage: error.localizedDescription
            )
            if reflex.action != .none {
                recordSpike(
                    kind: .spinalReflex,
                    tract: .spinalReflex,
                    missionId: missionId,
                    projectPath: workspacePath,
                    summary: reflex.summary,
                    salience: 0.90,
                    latencyMs: reflex.latencyMs,
                    succeeded: true
                )
            }
            return (subtask.id, false, error.localizedDescription, nil)
        }
    }

    private func planMissionSubtasks(objective: String, workspacePath: String) async -> [PNSMissionSubtask] {
        let systemPrompt = """
        You are the Prefrontal Cortex of MicroCode PNS (Pseudo Neural System).
        Decompose the objective into 2 to 5 concrete, verifiable subtasks for specialized Motor Agent Fibers.
        Return ONLY a valid JSON array of objects with keys:
        [{"id":"step_1","title":"...","description":"...","archetype":"architect|frontend_engineer|backend_engineer|bug_hunter|test_runner|security_auditor","owned_paths":[],"dependencies":[]}]
        """
        let userPrompt = "WORKSPACE: \(workspacePath)\nOBJECTIVE:\n\(objective)"

        do {
            let stream = try await AIClient.shared.streamCompletion(
                messages: [(role: "system", content: systemPrompt), (role: "user", content: userPrompt)],
                tools: nil,
                stream: false
            )
            var raw = ""
            for try await chunk in stream { raw += chunk }
            if let start = raw.firstIndex(of: "["), let end = raw.lastIndex(of: "]") {
                let jsonSlice = String(raw[start...end])
                if let data = jsonSlice.data(using: .utf8),
                   let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   !arr.isEmpty {
                    return arr.enumerated().map { idx, item in
                        let id = item["id"] as? String ?? "step_\(idx + 1)"
                        let title = item["title"] as? String ?? "Subtask \(idx + 1)"
                        let desc = item["description"] as? String ?? objective
                        let arch = item["archetype"] as? String ?? "backend_engineer"
                        let owned = item["owned_paths"] as? [String] ?? []
                        let deps = item["dependencies"] as? [String] ?? []
                        return PNSMissionSubtask(
                            id: id,
                            title: title,
                            description: desc,
                            assignedArchetype: arch,
                            tract: PNSGanglionRouter.motorTractForSubAgent(archetype: arch),
                            ownedPaths: owned,
                            dependencies: deps,
                            status: .queued,
                            attempts: 0,
                            resultSummary: nil,
                            worktreeBranch: nil
                        )
                    }
                }
            }
        } catch {
            let reflex = PNSGanglionRouter.shared.evaluateSpinalReflex(
                toolOrProviderName: "cortex_planner",
                targetHint: "planMissionSubtasks",
                errorMessage: error.localizedDescription
            )
            if reflex.action != .none {
                recordSpike(kind: .spinalReflex, tract: .spinalReflex, projectPath: workspacePath, summary: reflex.summary, salience: 0.85, latencyMs: reflex.latencyMs)
            }
        }

        // Resilient 3-stage neuromorphic fallback plan (Architect -> Implementation -> Verification)
        return [
            PNSMissionSubtask(
                id: "step_1",
                title: "Architectural Analysis & Contract Scope",
                description: "Inspect repository symbols and establish implementation contracts for: \(objective)",
                assignedArchetype: "architect",
                tract: .motorArchitecture,
                ownedPaths: [],
                dependencies: [],
                status: .queued,
                attempts: 0,
                resultSummary: nil,
                worktreeBranch: nil
            ),
            PNSMissionSubtask(
                id: "step_2",
                title: "Scoped Implementation Fiber",
                description: "Implement the required changes cleanly inside the isolated worktree for: \(objective)",
                assignedArchetype: "autonomous_loop",
                tract: .motorImplementation,
                ownedPaths: [],
                dependencies: ["step_1"],
                status: .queued,
                attempts: 0,
                resultSummary: nil,
                worktreeBranch: nil
            ),
            PNSMissionSubtask(
                id: "step_3",
                title: "Adversarial QA & Verification Gate",
                description: "Audit changes, run diagnostics/tests, and verify regressions for: \(objective)",
                assignedArchetype: "test_runner",
                tract: .motorVerification,
                ownedPaths: [],
                dependencies: ["step_2"],
                status: .queued,
                attempts: 0,
                resultSummary: nil,
                worktreeBranch: nil
            )
        ]
    }

    // MARK: - 8. Episodic WAL & Snapshot Persistence

    public func recordSpike(
        kind: PNSSpikeKind,
        tract: PNSNerveTractKind,
        missionId: String? = nil,
        projectPath: String? = nil,
        summary: String,
        salience: Double = 0.7,
        latencyMs: Int = 0,
        succeeded: Bool = true
    ) {
        let spike = PNSEpisodicSpike(
            kind: kind,
            tract: tract,
            missionId: missionId,
            projectPath: projectPath,
            summary: summary,
            salience: salience,
            latencyMs: latencyMs,
            succeeded: succeeded
        )
        recentSpikes.append(spike)
        if recentSpikes.count > 80 {
            recentSpikes.removeFirst(recentSpikes.count - 80)
        }

        // Append immediately to durable JSONL WAL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let lineData = try? encoder.encode(spike) {
            var mutable = lineData
            mutable.append(0x0A)
            if FileManager.default.fileExists(atPath: walURL.path),
               let fh = try? FileHandle(forWritingTo: walURL) {
                defer { try? fh.close() }
                _ = try? fh.seekToEnd()
                try? fh.write(contentsOf: mutable)
            } else {
                try? mutable.write(to: walURL)
            }
        }
    }

    public func buildStatusSnapshot() -> PNSDaemonStatusSnapshot {
        let allEdges = Array(synapses.values)
        let mcpTracts = PNSGanglionRouter.shared.buildMCPTractTelemetry(myelinatedEdges: allEdges)
        let motorTracts = PNSMotorWorktreePlexus.shared.buildMotorTractTelemetry(myelinatedEdges: allEdges)
        let externalServersCount = max(
            ExternalMCPManager.shared.connections.count,
            PNSGanglionRouter.shared.cachedServerManifests.count
        )
        let externalToolsCount = PNSGanglionRouter.shared.cachedServerManifests.values.reduce(0) { $0 + $1.count }

        return PNSDaemonStatusSnapshot(
            daemonPID: isRunningAsHeadlessDaemon ? ProcessInfo.processInfo.processIdentifier : remoteDaemonPID,
            isOutOfProcessDaemon: isRunningAsHeadlessDaemon || remoteDaemonOnline,
            startedAt: daemonStartedAt,
            autonomicMode: autonomicMode,
            effectiveMode: effectiveAutonomicMode,
            metabolicBudgetIndex: metabolicBudgetIndex,
            thermalStateLabel: thermalStateLabel,
            totalExternalMCPServers: externalServersCount,
            totalExternalMCPTools: max(ExternalMCPManager.shared.totalToolCount, externalToolsCount),
            activeMountedSynapticTools: PNSGanglionRouter.shared.lastActiveSynapticToolsCount,
            hibernatedMCPServers: PNSGanglionRouter.shared.hibernatedServers.count,
            myelinatedSynapsesCount: myelinatedSynapses.count,
            inhibitedSynapsesCount: inhibitedSynapses.count,
            proceduralPlaybooksCount: proceduralPlaybooks.count,
            semanticInvariantsCount: semanticInvariants.count,
            spinalReflexSavesCount: PNSGanglionRouter.shared.spinalReflexSavesCount,
            remConsolidationCycles: remConsolidationCycles,
            tracts: mcpTracts + motorTracts,
            missions: missions,
            recentSpikes: Array(recentSpikes.suffix(30))
        )
    }

    private func scheduleDurableSave() {
        pendingPersistenceTask?.cancel()
        pendingPersistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.saveDurableStateNow()
        }
    }

    private func persistAutonomicConfig() {
        let dict = ["autonomic_mode": autonomicMode.rawValue]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    public func saveDurableStateNow() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(synapses) { try? data.write(to: synapsesURL, options: .atomic) }
        if let data = try? encoder.encode(proceduralPlaybooks) { try? data.write(to: playbooksURL, options: .atomic) }
        if let data = try? encoder.encode(semanticInvariants) { try? data.write(to: invariantsURL, options: .atomic) }
        if let data = try? encoder.encode(missions) { try? data.write(to: missionsURL, options: .atomic) }
    }

    private func loadDurableStateFromDisk() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let cfgData = try? Data(contentsOf: configURL),
           let dict = try? JSONSerialization.jsonObject(with: cfgData) as? [String: String],
           let rawMode = dict["autonomic_mode"],
           let mode = PNSAutonomicMode(rawValue: rawMode) {
            self.autonomicMode = mode
        }
        if let d = try? Data(contentsOf: synapsesURL),
           let loaded = try? decoder.decode([String: PNSSynapseEdge].self, from: d) {
            self.synapses = loaded
        }
        if let d = try? Data(contentsOf: playbooksURL),
           let loaded = try? decoder.decode([PNSProceduralPlaybook].self, from: d) {
            self.proceduralPlaybooks = loaded
        }
        if let d = try? Data(contentsOf: invariantsURL),
           let loaded = try? decoder.decode([PNSSemanticInvariant].self, from: d) {
            self.semanticInvariants = loaded
        }
        if let d = try? Data(contentsOf: missionsURL),
           let loaded = try? decoder.decode([PNSMarathonMission].self, from: d) {
            self.missions = loaded
        }
        if let walText = try? String(contentsOf: walURL, encoding: .utf8) {
            let lines = walText.components(separatedBy: .newlines).suffix(48)
            var loadedSpikes: [PNSEpisodicSpike] = []
            for line in lines where !line.isEmpty {
                if let d = line.data(using: .utf8),
                   let spike = try? decoder.decode(PNSEpisodicSpike.self, from: d) {
                    loadedSpikes.append(spike)
                }
            }
            self.recentSpikes = loadedSpikes
        }
    }
}

// MARK: - AgentToolBox Native Tool: `pns_nervous_system`

struct PNSNervousSystemTool: AgentTool {
    let name = "pns_nervous_system"
    let description = "PNS (Pseudo Neural System 24/7 Architecture): Inspect neural tracts, out-of-process `pnsd` daemon, and myelinated synapses ('status'); dispatch an autonomous 24/7 marathon mission surviving app quit on isolated Git Worktree fibers ('dispatch_marathon'); stimulate a specific MCP Nerve Tract ('stimulate_tract'); trigger Hippocampal REM Memory Consolidation ('consolidate_rem'); or hibernate idle MCP processes ('hibernate_idle_mcp')."

    let parameters: [ToolParameter] = [
        ToolParameter(name: "action", type: "string", description: "Action: 'status', 'dispatch_marathon', 'stimulate_tract', 'consolidate_rem', 'hibernate_idle_mcp', or 'set_mode'", required: true),
        ToolParameter(name: "objective", type: "string", description: "Objective for 'dispatch_marathon' or intent query for 'stimulate_tract'", required: false),
        ToolParameter(name: "tract", type: "string", description: "Optional tract ID: 'mcp_code_ast', 'mcp_data_cloud', 'mcp_browser_visual', 'mcp_device_hardware', 'mcp_knowledge_science'", required: false),
        ToolParameter(name: "branch_policy", type: "string", description: "For 'dispatch_marathon': 'isolated_worktree_branch' (safe default) or 'auto_three_way_merge_on_verify'", required: false),
        ToolParameter(name: "verification_command", type: "string", description: "Optional build/test verification shell command e.g. 'swift test' or 'cargo check'", required: false),
        ToolParameter(name: "mode", type: "string", description: "For 'set_mode': 'auto_homeostasis', 'sympathetic', or 'parasympathetic'", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        let action = (params["action"] as? String ?? "status").lowercased()
        let ws = await MainActor.run { AgentToolBox.shared.effectiveWorkspaceRoot ?? FileManager.default.currentDirectoryPath }

        switch action {
        case "status", "inspect":
            _ = await PNSOrchestrator.shared.pollRemoteDaemonOnce()
            return await MainActor.run {
                let snap = PNSOrchestrator.shared.buildStatusSnapshot()
                var lines: [String] = [
                    "## PNS — Pseudo Neural System Live Telemetry",
                    "- Out-of-Process 24/7 Daemon (`pnsd`): \(snap.isOutOfProcessDaemon ? "ONLINE (PID \(snap.daemonPID), survives Cmd+Q)" : "STANDBY (In-Process)")",
                    "- Autonomic Mode: \(snap.autonomicMode.displayName) -> Effective: \(snap.effectiveMode.rawValue) (Metabolic Index M_t = \(String(format: "%.2f", snap.metabolicBudgetIndex)), Thermal: \(snap.thermalStateLabel))",
                    "- Efferent MCP Plexus: \(snap.totalExternalMCPServers) servers (\(snap.totalExternalMCPTools) total tools -> \(snap.activeMountedSynapticTools) active mounted synapses, \(snap.hibernatedMCPServers) hibernated at 0 MB RAM)",
                    "- Synaptic Plasticity: \(snap.myelinatedSynapsesCount) Myelinated Fast-Paths | \(snap.inhibitedSynapsesCount) LTD Inhibited Dead-Ends",
                    "- Spinal Reflex Saves (<50ms): \(snap.spinalReflexSavesCount) | Hippocampal REM Consolidations: \(snap.remConsolidationCycles)",
                    "\n### Specialized Nerve Tracts"
                ]
                for t in snap.tracts {
                    lines.append("- **\(t.tract.title)**: active=\(t.activeCount), hibernated=\(t.hibernatedCount), myelinated=\(t.myelinatedEdgesCount), impulses=\(t.totalImpulses) | nodes=[\(t.attachedNodes.joined(separator: ", "))]")
                }
                if !snap.missions.isEmpty {
                    lines.append("\n### Active / Recent 24/7 Marathon Missions")
                    for m in snap.missions.prefix(5) {
                        lines.append("- `\(m.id.prefix(8))` [\(m.status.rawValue.uppercased())] **\(m.title)** (\(Int(m.progressFraction * 100))% • \(m.subtasks.count) fibers • policy=\(m.branchPolicy.rawValue))")
                    }
                }
                return lines.joined(separator: "\n")
            }

        case "dispatch_marathon", "start_mission", "marathon":
            guard let objective = params["objective"] as? String, !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ToolBoxError.invalidParams("Parameter 'objective' is required for dispatch_marathon")
            }
            let policyRaw = params["branch_policy"] as? String ?? PNSBranchSafetyPolicy.isolatedWorktreeBranch.rawValue
            let policy = PNSBranchSafetyPolicy(rawValue: policyRaw) ?? .isolatedWorktreeBranch
            let verifyCmd = params["verification_command"] as? String
            let mission = await PNSOrchestrator.shared.dispatchMarathonMission(
                objective: objective,
                workspacePath: ws,
                branchPolicy: policy,
                verificationCommand: verifyCmd,
                preferOutOfProcessDaemon: true
            )
            let daemonPID = await MainActor.run { PNSOrchestrator.shared.remoteDaemonPID }
            return """
            ✅ Dispatched 24/7 PNS Marathon Mission `\(mission.id.prefix(8))`
            - Title: \(mission.title)
            - Out-of-Process Daemon: \(daemonPID > 0 ? "Running on microcode-pnsd (PID \(daemonPID)) — safe to close MicroCode.app" : "Running in local PNS orchestrator")
            - Branch Safety Policy: \(mission.branchPolicy.displayName)
            - Workspace: \(mission.workspacePath)
            """

        case "stimulate_tract", "route_mcp":
            let query = params["objective"] as? String ?? ""
            let tractRaw = params["tract"] as? String
            let allowed: Set<PNSNerveTractKind>? = tractRaw.flatMap(PNSNerveTractKind.init(rawValue:)).map { [$0] }
            return await MainActor.run {
                let selected = PNSGanglionRouter.shared.selectActiveSynapticTools(
                    forPrompt: query,
                    workspacePath: ws,
                    allowedTracts: allowed,
                    maxTools: 14,
                    synapseLookup: { cat, tr, node, proj in
                        PNSOrchestrator.shared.lookupSynapse(taskCategory: cat, tract: tr, targetNodeId: node, projectPath: proj)
                    }
                )
                if selected.isEmpty {
                    return "No external MCP tools matched in tract \(tractRaw ?? "any") for query '\(query)'."
                }
                return "Activated \(selected.count) synaptic MCP tools:\n" + selected.sorted().map { "- `\($0)`" }.joined(separator: "\n")
            }

        case "consolidate_rem", "rem_sleep":
            return await PNSOrchestrator.shared.runREMConsolidationCycle(projectPath: ws, missionId: nil)

        case "hibernate_idle_mcp", "hibernate":
            return await MainActor.run {
                let hib = PNSGanglionRouter.shared.hibernateIdleMCPServers(idleThresholdSeconds: 0)
                return hib.isEmpty
                    ? "No active local stdio MCP processes required hibernation."
                    : "Hibernated \(hib.count) MCP server(s) at 0 MB RAM (tool manifests preserved in Ganglion cache): \(hib.joined(separator: ", "))"
            }

        case "set_mode":
            let raw = params["mode"] as? String ?? "auto_homeostasis"
            return await MainActor.run {
                guard let mode = PNSAutonomicMode(rawValue: raw) else {
                    return "Invalid mode '\(raw)'. Options: auto_homeostasis, sympathetic, parasympathetic"
                }
                PNSOrchestrator.shared.autonomicMode = mode
                PNSOrchestrator.shared.updateHomeostasisMetrics()
                return "PNS Autonomic Mode updated to \(mode.displayName)."
            }

        default:
            return "Unknown pns_nervous_system action '\(action)'. Supported: status, dispatch_marathon, stimulate_tract, consolidate_rem, hibernate_idle_mcp, set_mode."
        }
    }
}
