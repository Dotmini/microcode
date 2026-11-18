//
//  ArdiumRunner.swift
//  MicroCode
//
//  Runs Arc code (Arc 3.x, formerly Ardium) with the toolchain chosen by ArcToolchain.
//  Copyright © 2025 Dotmini Software | Dotmini Company Limited. All rights reserved.
//

import Foundation

/// Runs Arc (formerly Ardium) code with the `arc` CLI resolved by `ArcToolchain`.
class ArdiumRunner {

    enum RunnerError: Error {
        case arcNotFound
        case executionFailed(String)
        case fileWriteFailed
    }

    /// A program still running after this is stopped (with everything it started), so the agent's `ardium_run`
    /// and MCP runs cannot hang forever on a server or an endless loop.
    static let defaultTimeout: TimeInterval = 120
    static let timeoutExitCode: Int32 = 124

    /// The Arc compiler / runner binary (newest Arc ≥ 3; Ardium 2 only when no Arc 3 is installed).
    static func findBinary() -> String? {
        ArcToolchain.shared.current()?.path
    }

    /// Checks if an Arc (or legacy Ardium) toolchain is installed.
    static var isArcInstalled: Bool {
        return findBinary() != nil
    }

    private static var notFoundMessage: String {
        "❌ Error: \(ArcToolchain.shared.statusDescription)"
    }

    /// Direct async execution returning stdout, stderr, and exit code.
    static func execute(code: String, arguments: [String] = [], timeout: TimeInterval = defaultTimeout) async -> (stdout: String, stderr: String, exitCode: Int32) {
        guard let binaryPath = findBinary() else {
            return ("", notFoundMessage, 1)
        }

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("ardium_\(UUID().uuidString).ar")

        do {
            try code.write(to: tempFile, atomically: true, encoding: .utf8)
        } catch {
            return ("", "❌ Error: Failed to write temp file: \(error.localizedDescription)", 1)
        }

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        var execArgs = ["run", tempFile.path]
        execArgs.append(contentsOf: arguments)

        return await runProcess(executable: binaryPath, arguments: execArgs, timeout: timeout)
    }

    /// Compiles an Arc source file to a standalone binary.
    static func compile(code: String, outputPath: String, flags: [String] = []) async -> (stdout: String, stderr: String, exitCode: Int32) {
        guard let binaryPath = findBinary() else {
            return ("", notFoundMessage, 1)
        }

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("ardium_build_\(UUID().uuidString).ar")

        do {
            try code.write(to: tempFile, atomically: true, encoding: .utf8)
        } catch {
            return ("", "❌ Error: Failed to write temp file: \(error.localizedDescription)", 1)
        }

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        var execArgs = ["build", tempFile.path, "-o", outputPath]
        execArgs.append(contentsOf: flags)

        return await runProcess(executable: binaryPath, arguments: execArgs, timeout: defaultTimeout)
    }

    /// Executes the provided Arc code and streams the output line by line.
    func run(code: String) -> AsyncStream<String> {
        return AsyncStream { continuation in
            let _ = Task {
                // 1. Validate Environment
                guard let binaryPath = Self.findBinary() else {
                    continuation.yield(Self.notFoundMessage)
                    continuation.finish()
                    return
                }

                // 2. Prepare Temporary File
                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent("StartUp_\(UUID().uuidString.prefix(8)).ar")

                do {
                    try code.write(to: fileURL, atomically: true, encoding: .utf8)
                } catch {
                    continuation.yield("❌ Error: Failed to write output file: \(error.localizedDescription)")
                    continuation.finish()
                    return
                }

                defer {
                    try? FileManager.default.removeItem(at: fileURL)
                }

                // 3. Configure Process
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binaryPath)
                process.arguments = ["run", fileURL.path]
                process.environment = ArcToolchain.shared.environment()

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                // 4. Stream Output
                let fileHandle = pipe.fileHandleForReading

                do {
                    try process.run()

                    for try await line in fileHandle.bytes.lines {
                        if line.contains("Target Triple") { continue }
                        continuation.yield(line)
                    }

                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        continuation.yield("\n[Process exited with code \(process.terminationStatus)]")
                    } else {
                        continuation.yield("\n✅ Execution Finished.")
                    }

                    continuation.finish()

                } catch {
                    continuation.yield("❌ Error: Failed to launch Arc runner: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }

    /// Runs the toolchain, reading stdout/stderr while it runs (reading only after exit deadlocked once a pipe
    /// filled up) and stopping the whole process tree after `timeout`.
    private static func runProcess(executable: String, arguments: [String], timeout: TimeInterval) async -> (stdout: String, stderr: String, exitCode: Int32) {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = ArcToolchain.shared.environment()
            process.standardInput = FileHandle.nullDevice

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            let stdoutData = LockedData()
            let stderrData = LockedData()
            stdoutPipe.fileHandleForReading.readabilityHandler = { stdoutData.append($0.availableData) }
            stderrPipe.fileHandleForReading.readabilityHandler = { stderrData.append($0.availableData) }

            let state = ArdiumRunState()
            let timeoutWork = DispatchWorkItem {
                guard process.isRunning else { return }
                state.markTimedOut()
                ProcessTree.terminate(root: process.processIdentifier)
            }

            process.terminationHandler = { finished in
                timeoutWork.cancel()
                // Let the last chunks arrive; never block on the pipes (a child may still hold them open).
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    var stderr = String(decoding: stderrData.data, as: UTF8.self)
                    var code = finished.terminationStatus
                    if state.timedOut {
                        code = timeoutExitCode
                        stderr += (stderr.isEmpty ? "" : "\n") + "⏱ Stopped after \(Int(timeout)) s: the program was still running. Long-running programs (servers, watchers) should be started in the Terminal instead."
                    }
                    if state.claimResume() {
                        continuation.resume(returning: (String(decoding: stdoutData.data, as: UTF8.self), stderr, code))
                    }
                }
            }

            do {
                try process.run()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if state.claimResume() {
                    continuation.resume(returning: ("", "Execution error: \(error.localizedDescription)", 1))
                }
            }
        }
    }
}

/// Timeout flag + exactly-once continuation guard for `runProcess`.
private final class ArdiumRunState: @unchecked Sendable {
    private let lock = NSLock()
    private var didTimeOut = false
    private var resumed = false

    func markTimedOut() {
        lock.lock(); didTimeOut = true; lock.unlock()
    }

    var timedOut: Bool {
        lock.lock(); defer { lock.unlock() }
        return didTimeOut
    }

    func claimResume() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }
}
