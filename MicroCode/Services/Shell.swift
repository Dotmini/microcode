import Foundation

/// Shared async subprocess runner.
///
/// Runs the child on a background queue so UI code paths never block the main
/// thread on `Process.waitUntilExit()`. stdout and stderr are drained
/// concurrently (two background reads) so a child that writes a lot to either
/// pipe can never deadlock against a full pipe buffer.
enum Shell {
    struct Result: Sendable {
        let status: Int32
        let out: String
        let err: String
    }

    /// Reference box so the non-Sendable `Process` can be touched from the
    /// timeout work item. Access is limited to `terminate()` / `isRunning`.
    private final class ProcessBox: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
    }

    /// Collects the output of one pipe from a background thread.
    private final class PipeReader: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func store(_ newData: Data) {
            lock.lock(); data = newData; lock.unlock()
        }
        func value() -> Data {
            lock.lock(); defer { lock.unlock() }
            return data
        }
    }

    /// Runs `exe` with `args` and returns its exit status and captured output.
    ///
    /// - Parameters:
    ///   - cwd: working directory (inherits the app's when `nil`).
    ///   - env: full environment for the child (inherits the app's when `nil`).
    ///   - timeout: when set, the process is terminated once it elapses; the
    ///     returned `status` is then the termination status of the killed process.
    /// - Throws: only when the process cannot be launched.
    static func run(
        _ exe: String,
        _ args: [String],
        cwd: URL? = nil,
        env: [String: String]? = nil,
        qos: DispatchQoS.QoSClass = .utility,
        timeout: TimeInterval? = nil
    ) async throws -> Shell.Result {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Shell.Result, Error>) in
            DispatchQueue.global(qos: qos).async {
                let process = Process()
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: exe)
                process.arguments = args
                process.currentDirectoryURL = cwd
                if let env { process.environment = env }
                process.standardOutput = outPipe
                process.standardError = errPipe
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    cont.resume(throwing: error)
                    return
                }

                var timeoutItem: DispatchWorkItem?
                if let timeout {
                    let box = ProcessBox(process)
                    let item = DispatchWorkItem {
                        if box.process.isRunning { box.process.terminate() }
                    }
                    timeoutItem = item
                    DispatchQueue.global(qos: qos).asyncAfter(deadline: .now() + timeout, execute: item)
                }

                // Drain both pipes concurrently before waiting for exit.
                let outReader = PipeReader()
                let errReader = PipeReader()
                let group = DispatchGroup()
                let outHandle = outPipe.fileHandleForReading
                let errHandle = errPipe.fileHandleForReading
                group.enter()
                DispatchQueue.global(qos: qos).async {
                    outReader.store(outHandle.readDataToEndOfFile())
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: qos).async {
                    errReader.store(errHandle.readDataToEndOfFile())
                    group.leave()
                }
                group.wait()
                process.waitUntilExit()
                timeoutItem?.cancel()

                cont.resume(returning: Shell.Result(
                    status: process.terminationStatus,
                    out: String(decoding: outReader.value(), as: UTF8.self),
                    err: String(decoding: errReader.value(), as: UTF8.self)
                ))
            }
        }
    }

    /// Convenience wrapper for `/usr/bin/git` in the given directory.
    static func git(_ args: [String], in dir: URL) async throws -> Shell.Result {
        try await run("/usr/bin/git", args, cwd: dir)
    }
}
