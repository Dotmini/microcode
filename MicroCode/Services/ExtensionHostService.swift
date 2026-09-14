//
//  ExtensionHostService.swift
//  MicroCode
//
//  A separate extension process keeps community code out of the SwiftUI
//  process. The first adapter is a deliberately scoped VS Code/Node shim;
//  WASM and process adapters use the same JSON-RPC transport.
//

import Foundation
import Combine

@MainActor
final class ExtensionHostService: ObservableObject {
    static let shared = ExtensionHostService()

    @Published private(set) var statusMessage = "Extension host is idle."
    @Published private(set) var lastEvent: String?

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var nextRequestID = 1

    private init() {}

    func activate(_ installedExtension: InstalledExtension) async throws {
        guard installedExtension.manifest.runtime == .javascript else {
            // This is intentionally explicit. A manifest can describe a WASM
            // or process extension today, but it must not receive implicit
            // full process privileges until its adapter is available.
            throw ExtensionHostError.unsupportedRuntime(installedExtension.manifest.runtime.rawValue)
        }
        let entry = installedExtension.path.appendingPathComponent(installedExtension.manifest.main)
        guard FileManager.default.isReadableFile(atPath: entry.path) else {
            throw ExtensionHostError.missingEntry(entry.path)
        }
        try startIfNeeded()
        let id = nextRequestID
        nextRequestID &+= 1
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "ext/load",
            "params": [
                "id": installedExtension.id,
                "path": entry.path,
                "root": installedExtension.path.path
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        input?.write(data)
        input?.write(Data("\n".utf8))
        statusMessage = "Activating \(installedExtension.manifest.name)…"
    }

    func deactivateAll() {
        output?.readabilityHandler = nil
        try? input?.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil
        input = nil
        output = nil
        statusMessage = "Extension host is idle."
    }

    func reportFailure(_ message: String) {
        statusMessage = message
    }

    func executeCommand(_ command: String, args: [Any] = []) {
        do {
            try startIfNeeded()
            let id = nextRequestID
            nextRequestID &+= 1
            let payload: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id,
                "method": "command/execute",
                "params": [
                    "command": command,
                    "args": args
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            input?.write(data)
            input?.write(Data("\n".utf8))
            statusMessage = "Dispatched command: \(command)"
        } catch {
            statusMessage = "Failed to run command: \(error.localizedDescription)"
        }
    }

    private func startIfNeeded() throws {
        guard process?.isRunning != true else { return }
        guard let node = locateNode(), let host = locateCompatHost() else {
            throw ExtensionHostError.hostUnavailable
        }
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        process.executableURL = node
        process.arguments = [host.path]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment.merging([
            "MICROCODE_EXTENSION_HOST": "1"
        ]) { _, new in new }
        try process.run()
        self.process = process
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let lines = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
            Task { @MainActor [weak self] in
                for line in lines { self?.consumeHostEvent(String(line)) }
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.process = nil
                self?.input = nil
                self?.output = nil
                self?.statusMessage = "Extension host stopped."
            }
        }
        statusMessage = "Extension host is ready."
    }

    private func consumeHostEvent(_ line: String) {
        guard let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let error = message["error"] as? [String: Any], let text = error["message"] as? String {
            statusMessage = text
        } else if let event = message["method"] as? String {
            lastEvent = event
        } else if message["result"] != nil {
            statusMessage = "Extension activated."
        }
    }

    private func locateNode() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("RuntimeLib/nodejs/bin/node"),
            Bundle.main.resourceURL?.appendingPathComponent("bin/node"),
            URL(fileURLWithPath: "/opt/homebrew/bin/node"),
            URL(fileURLWithPath: "/usr/local/bin/node")
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func locateCompatHost() -> URL? {
        let appSupportHost = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MicroCode/vscode-compat-host/src/index.js")
        let devRepoHost = URL(fileURLWithPath: "/Users/dotmini/Documents/SX/codetunner-native/vscode-compat-host/src/index.js")
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("vscode-compat-host/src/index.js"),
            Bundle.main.resourceURL?.appendingPathComponent("vscode-compat/index.js"),
            appSupportHost,
            devRepoHost,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("vscode-compat-host/src/index.js")
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }
}

private enum ExtensionHostError: LocalizedError {
    case hostUnavailable
    case missingEntry(String)
    case unsupportedRuntime(String)

    var errorDescription: String? {
        switch self {
        case .hostUnavailable: return "MicroCode's extension host is unavailable. Reinstall the app or configure a supported Node runtime."
        case .missingEntry(let path): return "Extension entry file was not found: \(path)"
        case .unsupportedRuntime(let runtime): return "The \(runtime) adapter is not installed in this MicroCode build yet."
        }
    }
}
