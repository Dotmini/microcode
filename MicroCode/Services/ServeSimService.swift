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

@MainActor
final class ServeSimService: ObservableObject {
    static let shared = ServeSimService()

    @Published private(set) var isActive = false
    @Published private(set) var statusMessage = "Fast iOS Preview is idle."
    @Published private(set) var previewURL: URL?
    @Published private(set) var connectionState: ServeSimConnectionState = .idle

    private let port = 3200
    private var activeDeviceID: String?
    private var activeSimulatorName: String?
    private var commandURL: URL?
    private var nodeURL: URL?
    private var connectionGeneration = 0

    private init() {}

    func start(simulatorID: String, simulatorName: String) async {
        // Preview is long-lived. Recreating the local stream for an already
        // selected simulator is both slow and makes WKWebView briefly discard
        // the real Apple frame, so first attach to the healthy existing one.
        if activeDeviceID == simulatorID {
            if isActive, let url = previewURL, await isReachable(url) {
                connectionState = .ready
                statusMessage = "Interactive preview · 60 FPS target"
                return
            }
            if connectionState == .connecting { return }
            await stopHelper(keepPresentation: true)
        } else if activeDeviceID != nil {
            await stop()
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
        connectionState = .connecting
        statusMessage = "Starting fast iOS Preview for \(simulatorName)…"
        do {
            let output = try await run(node, [
                runtime.path,
                "--detach", "--quiet", "--port", "\(port)",
                "--fit", "--panes", "none", "--codec", "auto", simulatorID
            ])
            commandURL = runtime
            nodeURL = node
            activeDeviceID = simulatorID
            activeSimulatorName = simulatorName
            let url = URL(string: "http://127.0.0.1:\(port)")!
            guard await waitUntilReachable(url, generation: generation) else {
                guard generation == connectionGeneration else { return }
                isActive = false
                connectionState = .failed
                // Keep previewURL intact. If this is a reconnect, the last
                // valid device frame remains visible under the retry overlay
                // rather than being replaced by a blank canvas.
                statusMessage = output.isEmpty
                    ? "Preview did not connect in 12 seconds. Check the simulator, then Retry."
                    : "Preview did not connect. \(output)"
                return
            }
            guard generation == connectionGeneration else { return }
            previewURL = sessionURL(for: url, generation: generation)
            isActive = true
            connectionState = .ready
            // Keep implementation details out of the product UI.  The preview
            // itself still uses the local H.264/WebSocket helper, but users only
            // need the device and its performance state.
            statusMessage = "Interactive preview · 60 FPS target"
        } catch {
            guard generation == connectionGeneration else { return }
            isActive = false
            connectionState = .failed
            statusMessage = "Fast iOS Preview could not start: \(error.localizedDescription)"
        }
    }

    func retryLastSimulator() async {
        guard let activeDeviceID, let activeSimulatorName else { return }
        await start(simulatorID: activeDeviceID, simulatorName: activeSimulatorName)
    }

    func isShowing(simulatorID: String) -> Bool {
        activeDeviceID == simulatorID && isActive && connectionState == .ready
    }

    func stop() async {
        connectionGeneration &+= 1
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
        let candidates: [URL?] = [
            bundle?.appendingPathComponent("serve-sim/serve-sim.js"),
            bundle?.appendingPathComponent("serve-sim/dist/serve-sim.js"),
            bundle?.appendingPathComponent("serve-sim/0.1.46/dist/serve-sim.js"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Vendor/serve-sim/0.1.46/dist/serve-sim.js")
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
        guard let device = activeDeviceID, let commandURL, let nodeURL else { return }
        _ = try? await run(nodeURL, [commandURL.path, "--kill", device])
        isActive = false
        if !keepPresentation {
            previewURL = nil
        }
    }

    private func sessionURL(for url: URL, generation: Int) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "microcodeSession", value: String(generation))]
        return components?.url ?? url
    }

    private func isReachable(_ url: URL) async -> Bool {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        guard let baseURL = components?.url else { return false }
        var request = URLRequest(url: baseURL, timeoutInterval: 0.5)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<500).contains(http.statusCode)
    }

    private func waitUntilReachable(_ url: URL, generation: Int) async -> Bool {
        // A warm simulator is normally ready within a second. A cold Apple
        // boot can take longer, but this is deliberately bounded so Preview
        // can never sit at “connecting” indefinitely.
        for attempt in 0..<80 {
            guard generation == connectionGeneration else { return false }
            if await isReachable(url) { return true }
            if attempt == 20 {
                statusMessage = "Waiting for the iOS Simulator display…"
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return false
    }

    private func run(_ executable: URL, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            process.terminationHandler = { process in
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
