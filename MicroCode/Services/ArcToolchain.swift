import Foundation
#if canImport(Darwin)
import Darwin
#endif

// The Arc toolchain (Arc 3.x, formerly Ardium) used by every part of MicroCode: Playground, Cell mode, the agent's
// `ardium_run` tool and `shell`, the Terminal and Arc projects.
//
// Before this, several resolvers searched different paths with no version check. The agent's shell put
// /usr/local/bin first and ran the old `ardium` 2.x, so every Arc 3 program failed to parse, and the runner injected
// Ardium 2 library paths into Arc 3 runs. Now one resolver picks the newest Arc ≥ 3 (an explicit $ARC_BIN /
// $ARDIUM_BIN always wins), falls back to Ardium 2 only when no Arc 3 exists, and a one-file shim directory
// (`arc` → the resolved binary) goes first on PATH so shells and terminals use the same compiler without pulling
// any other tool forward. Embedded firmware builds still use Ardium 2 on purpose (Arc 3 has no cross targets).

/// Version printed by `arc --version` ("arc 3.1.0") or a legacy banner ("Ardium Compiler v2.0.0").
struct ArcVersion: Comparable, Equatable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: ArcVersion, rhs: ArcVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// First `N.N[.N]` in the text.
    static func parse(_ text: String) -> ArcVersion? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\.(\d+)(?:\.(\d+))?"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ i: Int) -> Int? {
            guard let range = Range(match.range(at: i), in: text) else { return nil }
            return Int(text[range])
        }
        guard let major = group(1), let minor = group(2) else { return nil }
        return ArcVersion(major: major, minor: minor, patch: group(3) ?? 0)
    }
}

struct ArcToolchainResolution: Equatable {
    let path: String
    let version: ArcVersion?
    /// Ardium 2.x: needs its library paths and has a different language.
    let isLegacy: Bool
    /// Where it was found ("ARC_BIN", "managed", "~/.local/bin", "PATH", "legacy" …), for diagnostics.
    let source: String
}

enum ArcToolchainResolver {
    static let minimumMajor = 3

    struct Candidate: Equatable {
        let path: String
        let source: String
        let explicit: Bool
    }

    /// Arc candidates in preference order (explicit overrides first), then Ardium 2 fallbacks.
    static func candidates(home: String, environment: [String: String], managedBinary: String) -> (arc: [Candidate], legacy: [Candidate]) {
        var arc: [Candidate] = []
        if let pinned = environment["ARC_BIN"], !pinned.isEmpty {
            arc.append(Candidate(path: pinned, source: "ARC_BIN", explicit: true))
        }
        if let pinned = environment["ARDIUM_BIN"], !pinned.isEmpty {
            arc.append(Candidate(path: pinned, source: "ARDIUM_BIN", explicit: true))
        }
        arc.append(Candidate(path: managedBinary, source: "managed", explicit: false))
        arc.append(Candidate(path: "\(home)/.local/bin/arc", source: "~/.local/bin", explicit: false))
        arc.append(Candidate(path: "\(home)/.cargo/bin/arc", source: "~/.cargo/bin", explicit: false))
        arc.append(Candidate(path: "/opt/homebrew/bin/arc", source: "homebrew", explicit: false))
        arc.append(Candidate(path: "/usr/local/bin/arc", source: "/usr/local/bin", explicit: false))
        let pathDirs = (environment["PATH"] ?? "").split(separator: ":").map(String.init).filter { !$0.isEmpty }
        arc += pathDirs.map { Candidate(path: "\($0)/arc", source: "PATH", explicit: false) }

        var legacy = [
            "/usr/local/ardium/bin/arc", "/usr/local/bin/ardium", "/usr/local/ardium/ardium",
            "/opt/homebrew/bin/ardium", "\(home)/.cargo/bin/TitanScript"
        ].map { Candidate(path: $0, source: "legacy", explicit: false) }
        legacy += pathDirs.map { Candidate(path: "\($0)/ardium", source: "legacy", explicit: false) }
        return (arc, legacy)
    }

    /// Explicit override if set; otherwise the newest Arc ≥ 3 (earlier candidate on a tie); otherwise the first
    /// Ardium 2 binary (legacy). Symlinked duplicates (e.g. ~/.cargo/bin/arc → ~/.local/bin/arc) are probed once.
    static func resolve(
        home: String,
        environment: [String: String],
        managedBinary: String,
        isExecutable: (String) -> Bool,
        realPath: (String) -> String,
        versionOutput: (String) -> String?
    ) -> ArcToolchainResolution? {
        let (arc, legacy) = candidates(home: home, environment: environment, managedBinary: managedBinary)
        var probed: Set<String> = []
        var best: (candidate: Candidate, version: ArcVersion)?

        for candidate in arc where isExecutable(candidate.path) {
            let real = realPath(candidate.path)
            let version = versionOutput(candidate.path).flatMap(ArcVersion.parse)
            if candidate.explicit {
                let isLegacy = version.map { $0.major < minimumMajor } ?? (candidate.source == "ARDIUM_BIN")
                return ArcToolchainResolution(path: candidate.path, version: version, isLegacy: isLegacy, source: candidate.source)
            }
            guard probed.insert(real).inserted, let version, version.major >= minimumMajor else { continue }
            if best == nil || version > best!.version {
                best = (candidate, version)
            }
        }
        if let best {
            return ArcToolchainResolution(path: best.candidate.path, version: best.version, isLegacy: false, source: best.candidate.source)
        }
        for candidate in legacy where isExecutable(candidate.path) {
            let version = versionOutput(candidate.path).flatMap(ArcVersion.parse)
            return ArcToolchainResolution(path: candidate.path, version: version, isLegacy: true, source: candidate.source)
        }
        return nil
    }

    /// Whether `arc --help` lists `command` as a command (first word of a help line).
    static func helpLists(command: String, in help: String) -> Bool {
        help.split(whereSeparator: \.isNewline).contains { line in
            line.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) == command
        }
    }
}

enum ArcToolchainEnvironment {
    static let legacyLibraryPath = "/usr/local/ardium/lib"
    static let legacyStdlibPath = "/usr/local/ardium/stdlib"

    /// Process environment for running the toolchain: the shim first on PATH (Arc 3), and the Ardium 2 library
    /// paths only for a legacy toolchain.
    static func make(base: [String: String], resolution: ArcToolchainResolution, shimDirectory: String?) -> [String: String] {
        var env = base
        if let shim = shimDirectory {
            let parts = (env["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init).filter { $0 != shim }
            env["PATH"] = ([shim] + parts).joined(separator: ":")
        }
        if resolution.isLegacy {
            env["DYLD_LIBRARY_PATH"] = legacyLibraryPath + ":" + (env["DYLD_LIBRARY_PATH"] ?? "")
            env["ARDIUM_LIB_PATH"] = legacyLibraryPath
            env["ARDIUM_STDLIB"] = legacyStdlibPath
        }
        return env
    }
}

/// Stops a program together with everything it started: `arc run` launches the compiled program through
/// `system()`, so terminating only `arc` would leave e.g. an HTTP server running.
enum ProcessTree {
    /// Descendants of `root`, deepest first (children are stopped before their parents).
    static func descendants(of root: Int32, in table: [(pid: Int32, ppid: Int32)]) -> [Int32] {
        var children: [Int32: [Int32]] = [:]
        for entry in table { children[entry.ppid, default: []].append(entry.pid) }
        var ordered: [Int32] = []
        var seen: Set<Int32> = [root]
        func visit(_ pid: Int32) {
            for child in children[pid] ?? [] where seen.insert(child).inserted {
                visit(child)
                ordered.append(child)
            }
        }
        visit(root)
        return ordered
    }

    static func processTable() -> [(pid: Int32, ppid: Int32)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-A", "-o", "pid=,ppid="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: " ").compactMap { Int32($0) }
            return fields.count == 2 ? (fields[0], fields[1]) : nil
        }
    }

    /// SIGTERM to the whole tree, then SIGKILL to anything still alive after `grace` seconds.
    static func terminate(root: Int32, grace: TimeInterval = 1.5) {
        let targets = descendants(of: root, in: processTable()) + [root]
        for pid in targets { kill(pid, SIGTERM) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + grace) {
            for pid in targets where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }
}

/// Shared, cached resolution of the Arc toolchain (thread-safe; probing runs `--version` once per binary).
final class ArcToolchain: @unchecked Sendable {
    static let shared = ArcToolchain()

    /// Re-probe at most this often, so an updated or newly installed toolchain is picked up without a restart.
    static let cacheLifetime: TimeInterval = 30

    private let lock = NSLock()
    private var cached: (resolution: ArcToolchainResolution?, at: Date)?
    private var helpCache: [String: String] = [:]

    private var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    }

    /// Where a MicroCode-installed toolchain lives (`<root>/<version>/…`, `current` → active version).
    var managedRoot: URL { applicationSupport.appendingPathComponent("MicroCode/Runtimes/arc", isDirectory: true) }
    var managedBinary: String { managedRoot.appendingPathComponent("current/bin/arc").path }
    /// Holds only an `arc` symlink to the resolved compiler; prepended to PATH.
    var shimDirectory: URL { applicationSupport.appendingPathComponent("MicroCode/Toolchains/arc/bin", isDirectory: true) }

    func current(forceRefresh: Bool = false) -> ArcToolchainResolution? {
        lock.lock()
        defer { lock.unlock() }
        if !forceRefresh, let cached, Date().timeIntervalSince(cached.at) < Self.cacheLifetime,
           cached.resolution.map({ FileManager.default.isExecutableFile(atPath: $0.path) }) ?? true {
            return cached.resolution
        }
        let fm = FileManager.default
        let resolution = ArcToolchainResolver.resolve(
            home: fm.homeDirectoryForCurrentUser.path,
            environment: ProcessInfo.processInfo.environment,
            managedBinary: managedBinary,
            isExecutable: { fm.isExecutableFile(atPath: $0) },
            realPath: { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
            versionOutput: { Self.capture($0, ["--version"], timeout: 3) }
        )
        if resolution != cached?.resolution {
            helpCache.removeAll()
            if let resolution, !resolution.isLegacy { updateShim(to: resolution.path) }
        }
        cached = (resolution, Date())
        return resolution
    }

    func invalidate() {
        lock.lock()
        cached = nil
        lock.unlock()
    }

    /// Directories to put first on PATH for shells, terminals and runners: the shim when an Arc 3 toolchain exists.
    func pathDirectories() -> [String] {
        guard let resolution = current(), !resolution.isLegacy else { return [] }
        let shim = shimDirectory.path
        return FileManager.default.isExecutableFile(atPath: shimDirectory.appendingPathComponent("arc").path) ? [shim] : []
    }

    func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        guard let resolution = current() else { return base }
        return ArcToolchainEnvironment.make(base: base, resolution: resolution, shimDirectory: pathDirectories().first)
    }

    /// Whether the resolved toolchain has a CLI command (e.g. `lsp`, which Arc 3.1 does not have yet).
    func supports(command: String) -> Bool {
        guard let path = current()?.path else { return false }
        lock.lock()
        let cachedHelp = helpCache[path]
        lock.unlock()
        let help = cachedHelp ?? (Self.capture(path, ["--help"], timeout: 3) ?? "")
        if cachedHelp == nil {
            lock.lock()
            helpCache[path] = help
            lock.unlock()
        }
        return ArcToolchainResolver.helpLists(command: command, in: help)
    }

    /// LANGUAGE_REFERENCE.md of the resolved toolchain when it is a MicroCode-managed install.
    var referencePath: String? {
        guard let resolution = current() else { return nil }
        let managedBin = URL(fileURLWithPath: managedBinary).resolvingSymlinksInPath().path
        guard URL(fileURLWithPath: resolution.path).resolvingSymlinksInPath().path == managedBin else { return nil }
        let reference = URL(fileURLWithPath: managedBin).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("share/LANGUAGE_REFERENCE.md").path
        return FileManager.default.fileExists(atPath: reference) ? reference : nil
    }

    /// One-line status for diagnostics and error messages.
    var statusDescription: String {
        guard let resolution = current() else {
            return "Arc toolchain not found. Install Arc 3 (the `arc` CLI) or set ARC_BIN."
        }
        let version = resolution.version?.description ?? "unknown version"
        return resolution.isLegacy
            ? "Legacy Ardium toolchain \(version) at \(resolution.path) (Arc 3 not found)"
            : "Arc \(version) at \(resolution.path)"
    }

    private func updateShim(to target: String) {
        let fm = FileManager.default
        let link = shimDirectory.appendingPathComponent("arc").path
        if (try? fm.destinationOfSymbolicLink(atPath: link)) == target { return }
        try? fm.createDirectory(at: shimDirectory, withIntermediateDirectories: true)
        let temp = shimDirectory.appendingPathComponent(".arc-\(UUID().uuidString)").path
        guard symlink(target, temp) == 0 else { return }
        if rename(temp, link) != 0 { unlink(temp) } // atomic replace
    }

    /// Runs a short command and returns stdout + stderr (nil if it cannot start or exceeds `timeout`).
    static func capture(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        let collected = LockedData()
        pipe.fileHandleForReading.readabilityHandler = { handle in collected.append(handle.availableData) }
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        guard (try? process.run()) != nil else {
            pipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        let finished = done.wait(timeout: .now() + timeout) == .success
        if !finished { ProcessTree.terminate(root: process.processIdentifier, grace: 0.5) }
        Thread.sleep(forTimeInterval: 0.02) // let the last chunk arrive
        pipe.fileHandleForReading.readabilityHandler = nil
        return finished ? String(decoding: collected.data, as: UTF8.self) : nil
    }
}

/// Thread-safe byte buffer for pipe readability handlers.
final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock(); storage.append(chunk); lock.unlock()
    }

    var data: Data {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
