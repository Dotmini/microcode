//
//  ServeSimService.swift
//  MicroCode
//
//  Fast interactive iOS Simulator preview powered by the Apache-2.0
//  EvanBacon/serve-sim runtime. The helper is bundled at build time, never
//  downloaded when a user presses Preview.
//

import Foundation
import Combine

enum ServeSimConnectionState: Equatable {
    case idle
    case connecting
    case ready
    case failed
}

enum IPhoneDuoDisplayMode: String, CaseIterable, Identifiable {
    case outer = "outer"
    case inner = "inner"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .outer: return "จอนอก (Outer)"
        case .inner: return "จอใน (Inner)"
        }
    }

    var compactBadge: String {
        switch self {
        case .outer: return "จอนอก"
        case .inner: return "จอใน"
        }
    }

    var icon: String {
        switch self {
        case .outer: return "iphone"
        case .inner: return "book.pages"
        }
    }

    var resolutionLabel: String {
        switch self {
        case .outer: return "466×678 pt · Cover"
        case .inner: return "951×669 pt · Unfolded"
        }
    }

    static func modeFilePath(for simulatorID: String) -> String {
        "/tmp/microcode-serve-sim-display-\(simulatorID).mode"
    }

    func persist(for simulatorID: String) {
        try? rawValue.write(toFile: Self.modeFilePath(for: simulatorID), atomically: true, encoding: .utf8)
    }
}

@MainActor
final class ServeSimService: ObservableObject {
    static let shared = ServeSimService()

    @Published private(set) var isActive = false
    @Published private(set) var statusMessage = "Fast iOS Preview is idle."
    @Published private(set) var previewURL: URL?
    @Published private(set) var connectionState: ServeSimConnectionState = .idle
    @Published private(set) var displayMode: IPhoneDuoDisplayMode = .outer

    private let port = 3200
    private(set) var activeDeviceID: String?
    private var activeSimulatorName: String?
    private var commandURL: URL?
    private var nodeURL: URL?
    private var activeProcess: Process?
    private var connectionGeneration = 0

    private init() {}

    func start(
        simulatorID: String,
        simulatorName: String,
        displayMode: IPhoneDuoDisplayMode = .outer
    ) async {
        displayMode.persist(for: simulatorID)
        let modeChanged = (self.displayMode != displayMode)
        self.displayMode = displayMode

        // Preview is long-lived. Recreating the local stream for an already
        // selected simulator is both slow and makes WKWebView briefly discard
        // the real Apple frame, so first attach to the healthy existing one
        // unless the foldable outer/inner display mode changed.
        if activeDeviceID == simulatorID {
            if !modeChanged, isActive, let url = previewURL, await isReachable(url, simulatorID: simulatorID) {
                connectionState = .ready
                statusMessage = "Interactive preview · 60 FPS target"
                return
            }
            if !modeChanged, connectionState == .connecting { return }
            await stopHelper(keepPresentation: !modeChanged)
        } else if activeDeviceID != nil {
            await stop()
            self.displayMode = displayMode
            displayMode.persist(for: simulatorID)
        }

        guard let runtime = locateRuntime() else {
            connectionState = .failed
            statusMessage = "Fast iOS Preview runtime is missing. Rebuild MicroCode so its pinned serve-sim helper is bundled."
            return
        }
        guard let node = locateNode() else {
            connectionState = .failed
            statusMessage = "Fast iOS Preview requires the bundled Node runtime (or Node 20+ on this Mac)."
            return
        }

        connectionGeneration &+= 1
        let generation = connectionGeneration
        commandURL = runtime
        nodeURL = node
        activeDeviceID = simulatorID
        activeSimulatorName = simulatorName
        connectionState = .connecting
        statusMessage = "Starting fast iOS Preview for \(simulatorName)…"
        do {
            let output = try await run(node, [
                runtime.path,
                "--detach", "--quiet", "--port", "\(port)",
                "--fit", "--panes", "none", "--codec", "auto", simulatorID
            ])
            guard generation == connectionGeneration else { return }
            let url = URL(string: "http://127.0.0.1:\(port)")!
            guard await waitUntilReachable(url, simulatorID: simulatorID, generation: generation) else {
                guard generation == connectionGeneration else { return }
                isActive = false
                connectionState = .failed
                statusMessage = output.isEmpty
                    ? "Preview did not connect in 15 seconds. Check the simulator, then Retry."
                    : "Preview did not connect. \(output)"
                return
            }
            guard generation == connectionGeneration else { return }
            previewURL = sessionURL(for: url, simulatorID: simulatorID, generation: generation)
            isActive = true
            connectionState = .ready
            statusMessage = "Interactive preview · 60 FPS target"
        } catch {
            guard generation == connectionGeneration else { return }
            isActive = false
            connectionState = .failed
            statusMessage = "Fast iOS Preview could not start: \(error.localizedDescription)"
        }
    }

    func retryLastSimulator() async {
        if let activeDeviceID, let activeSimulatorName {
            await start(simulatorID: activeDeviceID, simulatorName: activeSimulatorName, displayMode: displayMode)
        } else {
            await DeviceRuntimeService.shared.startEmbeddedAppleSimulator()
        }
    }

    func reportPreflightFailure(_ message: String) {
        isActive = false
        connectionState = .failed
        statusMessage = message
    }

    func isShowing(simulatorID: String, displayMode: IPhoneDuoDisplayMode? = nil) -> Bool {
        let modeMatches = displayMode == nil || self.displayMode == displayMode
        return activeDeviceID == simulatorID && modeMatches && isActive && connectionState == .ready
    }

    func stop() async {
        connectionGeneration &+= 1
        if let proc = activeProcess, proc.isRunning {
            proc.terminate()
            kill(proc.processIdentifier, SIGKILL)
        }
        activeProcess = nil
        await stopHelper(keepPresentation: false)
        activeDeviceID = nil
        activeSimulatorName = nil
        commandURL = nil
        nodeURL = nil
        previewURL = nil
        isActive = false
        connectionState = .idle
        statusMessage = "Fast iOS Preview is idle."
    }

    private func locateRuntime() -> URL? {
        let bundle = Bundle.main.resourceURL
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates: [URL?] = [
            bundle?.appendingPathComponent("serve-sim/serve-sim.js"),
            bundle?.appendingPathComponent("serve-sim/dist/serve-sim.js"),
            bundle?.appendingPathComponent("serve-sim/0.1.46/dist/serve-sim.js"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Vendor/serve-sim/0.1.46/dist/serve-sim.js"),
            sourceRoot.appendingPathComponent("Vendor/serve-sim/0.1.46/dist/serve-sim.js")
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) || FileManager.default.fileExists(atPath: $0.path) }
    }

    private func locateNode() -> URL? {
        let bundle = Bundle.main.resourceURL
        let candidates: [URL] = [
            bundle?.appendingPathComponent("RuntimeLib/nodejs/bin/node"),
            bundle?.appendingPathComponent("bin/node"),
            URL(fileURLWithPath: "/opt/homebrew/bin/node"),
            URL(fileURLWithPath: "/usr/local/bin/node")
        ].compactMap { $0 }
        guard let node = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { return nil }
        return node
    }

    private func stopHelper(keepPresentation: Bool) async {
        if let device = activeDeviceID, let commandURL = commandURL ?? locateRuntime(), let nodeURL = nodeURL ?? locateNode() {
            _ = try? await run(nodeURL, [commandURL.path, "--kill", device])
        }
        // Always ensure any detached serve-sim daemon on port 3200 is reaped so it cannot consume CPU in background
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", "serve-sim"]
        pkill.standardOutput = FileHandle.nullDevice
        pkill.standardError = FileHandle.nullDevice
        try? pkill.run()

        isActive = false
        if !keepPresentation {
            previewURL = nil
        }
    }

    private func sessionURL(for url: URL, simulatorID: String, generation: Int) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "device", value: simulatorID),
            URLQueryItem(name: "microcodeSession", value: String(generation)),
            URLQueryItem(name: "duoDisplay", value: displayMode.rawValue)
        ]
        return components?.url ?? url
    }

    private func isReachable(_ url: URL, simulatorID: String) async -> Bool {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "device", value: simulatorID)]
        guard let checkURL = components?.url else { return false }
        var request = URLRequest(url: checkURL, timeoutInterval: 0.8)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return false }
        let html = String(decoding: data, as: UTF8.self)
        return html.contains("\"streamUrl\"") && html.localizedCaseInsensitiveContains(simulatorID)
    }

    private func waitUntilReachable(_ url: URL, simulatorID: String, generation: Int) async -> Bool {
        for attempt in 0..<100 {
            guard generation == connectionGeneration else { return false }
            if await isReachable(url, simulatorID: simulatorID) { return true }
            if attempt == 20 {
                statusMessage = "Waiting for the iOS Simulator display…"
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return false
    }

    private func run(_ executable: URL, _ arguments: [String]) async throws -> String {
        let currentMode = self.displayMode.rawValue
        let runtimeBinDir: String? = (commandURL ?? locateRuntime()).map { runtimeScript in
            let parent = runtimeScript.deletingLastPathComponent()
            let root = parent.lastPathComponent == "dist" ? parent.deletingLastPathComponent() : parent
            return root.appendingPathComponent("bin").path
        }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            env["SERVE_SIM_DISPLAY_MODE"] = currentMode
            if let binDir = runtimeBinDir, FileManager.default.fileExists(atPath: binDir) {
                let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
                env["PATH"] = "\(binDir):\(existingPath)"
            }
            process.environment = env
            process.standardOutput = output
            process.standardError = output
            self.activeProcess = process
            process.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    if self?.activeProcess === process {
                        self?.activeProcess = nil
                    }
                }
                let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "MicroCode.ServeSim",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "serve-sim exited with status \(process.terminationStatus)." : text]
                    ))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}
