import Foundation
import Combine
#if canImport(Darwin)
import Darwin
#endif

// Keeps MicroCode's Arc toolchain on the newest commit of the user's Arc source repo.
//
// Source: a local checkout of the Arc repo (configured, or found in a common location). Arc does not publish usable
// release binaries yet (its release workflow still builds the old OCaml toolchain), so MicroCode builds the
// committed HEAD itself: `git archive <commit>` into a scratch folder (the user's working tree and build folder are
// never touched), `make OUT=…`, check `--version` and `arc doctor`, then install into
// `Runtimes/arc/<version>+<commit>/` and atomically repoint `current`. ArcToolchain prefers the newest Arc, so the
// new build is used everywhere within its 30 s cache. The previous install is kept for rollback.

struct ArcSourceInfo: Equatable {
    let path: String
    let version: ArcVersion
    let commit: String
}

/// Pure update decisions (regression-tested).
enum ArcUpdatePlan {
    static func installName(version: ArcVersion, commit: String) -> String {
        "\(version)+\(commit)"
    }

    static func parseInstallName(_ name: String) -> (version: ArcVersion, commit: String)? {
        let parts = name.split(separator: "+", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty, parts[1].allSatisfy(\.isHexDigit),
              let version = ArcVersion.parse(parts[0]), parts[0] == version.description else { return nil }
        return (version, parts[1])
    }

    /// Build when nothing is installed or HEAD moved — never for an older VERSION (no downgrade) or Ardium 2.
    static func needsUpdate(source: ArcSourceInfo, installed: (version: ArcVersion, commit: String)?) -> Bool {
        guard source.version.major >= ArcToolchainResolver.minimumMajor else { return false }
        guard let installed else { return true }
        if source.version < installed.version { return false }
        return source.commit != installed.commit
    }

    /// Automatic checks do not rebuild a commit that already failed; "Check now" does.
    static func shouldAttempt(source: ArcSourceInfo, lastFailedCommit: String?, manual: Bool) -> Bool {
        manual || lastFailedCommit != source.commit
    }

    static let sourceMarkers = ["VERSION", "Makefile", "src/compiler/driver.cpp", "src/runtime/arc_rt.c"]

    static func isArcSource(_ path: String, fileExists: (String) -> Bool) -> Bool {
        sourceMarkers.allSatisfy { fileExists((path as NSString).appendingPathComponent($0)) }
    }

    static func candidateSources(home: String, configured: String?) -> [String] {
        var paths: [String] = []
        if let configured, !configured.isEmpty { paths.append((configured as NSString).expandingTildeInPath) }
        for relative in ["Documents/ardium", "Developer/ardium", "Projects/ardium", "ardium",
                         "Documents/arc", "Developer/arc", "Projects/arc"] {
            let path = (home as NSString).appendingPathComponent(relative)
            if !paths.contains(path) { paths.append(path) }
        }
        return paths
    }

    /// Keep the active install and the most recently installed other one (rollback); remove the rest.
    static func installsToRemove(_ installs: [(name: String, installedAt: Date)], current: String?) -> [String] {
        guard let current else { return [] }
        let others = installs.filter { $0.name != current }.sorted { $0.installedAt > $1.installedAt }
        return others.dropFirst().map(\.name)
    }
}

/// Runs a command, reading its output while it runs, with a timeout that stops the whole process tree.
enum ArcProcess {
    struct Result {
        let status: Int32
        let output: String
        let timedOut: Bool
    }

    static func run(_ executable: String, _ arguments: [String], currentDirectory: String? = nil,
                    environment: [String: String]? = nil, timeout: TimeInterval) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory) }
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let collected = LockedData()
        pipe.fileHandleForReading.readabilityHandler = { collected.append($0.availableData) }
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return Result(status: -1, output: "failed to start \(executable): \(error.localizedDescription)", timedOut: false)
        }
        var timedOut = false
        if done.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            ProcessTree.terminate(root: process.processIdentifier)
            _ = done.wait(timeout: .now() + 5)
        }
        Thread.sleep(forTimeInterval: 0.05)
        pipe.fileHandleForReading.readabilityHandler = nil
        return Result(status: timedOut ? -1 : process.terminationStatus,
                      output: String(decoding: collected.data, as: UTF8.self), timedOut: timedOut)
    }
}

/// Builds and installs Arc from a source checkout into a managed root (`<root>/<version>+<commit>`, `<root>/current`).
struct ArcToolchainInstaller {
    struct InstallError: Error, CustomStringConvertible {
        let description: String
    }

    let root: URL

    /// Bumped when the build procedure changes, so a failure caused by an older installer is retried.
    static let revision = 2

    /// Scratch folder for one build. Make cannot handle spaces in OUT=, and the managed root lives under
    /// "Application Support", so the build happens in the temp directory and the result is moved in afterwards.
    static func scratchDirectory(base: URL = FileManager.default.temporaryDirectory, id: String = UUID().uuidString) -> URL {
        let name = "microcode-arc-build-\(id)"
        let candidate = base.appendingPathComponent(name, isDirectory: true)
        return candidate.path.contains(" ") ? URL(fileURLWithPath: "/tmp", isDirectory: true).appendingPathComponent(name, isDirectory: true) : candidate
    }

    /// Tools the Arc Makefile needs (clang++, make, xxd, git) without the user's shell setup.
    static var buildEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        return env
    }

    var currentLink: URL { root.appendingPathComponent("current") }
    var logsDirectory: URL { root.appendingPathComponent("logs", isDirectory: true) }

    /// Committed VERSION and HEAD of the source checkout.
    func sourceInfo(at path: String) -> ArcSourceInfo? {
        let env = Self.buildEnvironment
        let head = ArcProcess.run("/usr/bin/git", ["-C", path, "rev-parse", "--short=12", "HEAD"], environment: env, timeout: 30)
        let commit = head.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard head.status == 0, !commit.isEmpty, commit.allSatisfy(\.isHexDigit) else { return nil }
        let versionFile = ArcProcess.run("/usr/bin/git", ["-C", path, "show", "\(commit):VERSION"], environment: env, timeout: 30)
        guard versionFile.status == 0, let version = ArcVersion.parse(versionFile.output) else { return nil }
        return ArcSourceInfo(path: path, version: version, commit: commit)
    }

    func currentInstall() -> (name: String, version: ArcVersion, commit: String)? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: currentLink.path) else { return nil }
        let name = (target as NSString).lastPathComponent
        guard let parsed = ArcUpdatePlan.parseInstallName(name) else { return nil }
        return (name, parsed.version, parsed.commit)
    }

    func installs() -> [(name: String, installedAt: Date)] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        return names.compactMap { name in
            guard ArcUpdatePlan.parseInstallName(name) != nil else { return nil }
            let attrs = try? fm.attributesOfItem(atPath: root.appendingPathComponent(name).path)
            return (name, (attrs?[.creationDate] as? Date) ?? .distantPast)
        }
    }

    /// Builds `source.commit` and makes it current. Returns the install name. Holds a file lock so two MicroCode
    /// processes never build at once (returns nil when another build is in progress).
    func install(_ source: ArcSourceInfo) throws -> String? {
        let fm = FileManager.default
        try fm.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let lockFD = open(root.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o644)
        guard lockFD >= 0 else { throw InstallError(description: "cannot create \(root.path)/.lock") }
        defer { close(lockFD) }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { return nil }
        defer { flock(lockFD, LOCK_UN) }

        let name = ArcUpdatePlan.installName(version: source.version, commit: source.commit)
        // Leftovers from a build interrupted by quitting the app.
        for stale in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] where stale.hasPrefix(".build-") || stale.hasPrefix(".current-") {
            try? fm.removeItem(at: root.appendingPathComponent(stale))
        }
        let work = Self.scratchDirectory()
        defer { try? fm.removeItem(at: work) }
        let sourceDir = work.appendingPathComponent("src", isDirectory: true)
        let outDir = work.appendingPathComponent("out", isDirectory: true)
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        var log = "Arc \(name) from \(source.path)\n"
        let logURL = logsDirectory.appendingPathComponent("\(name).log")
        defer { try? log.write(to: logURL, atomically: true, encoding: .utf8) }

        func step(_ label: String, _ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> ArcProcess.Result {
            log += "\n$ \(([executable] + arguments).joined(separator: " "))\n"
            let result = ArcProcess.run(executable, arguments, environment: Self.buildEnvironment, timeout: timeout)
            log += result.output
            guard result.status == 0 else {
                let tail = result.output.split(whereSeparator: \.isNewline).suffix(6).joined(separator: "\n")
                throw InstallError(description: "\(label) failed\(result.timedOut ? " (timed out)" : ""): \(tail)")
            }
            return result
        }

        let tarball = work.appendingPathComponent("src.tar").path
        _ = try step("git archive", "/usr/bin/git", ["-C", source.path, "archive", "--format=tar", "-o", tarball, source.commit], timeout: 120)
        _ = try step("extract", "/usr/bin/tar", ["-xf", tarball, "-C", sourceDir.path], timeout: 120)
        _ = try step("build", "/usr/bin/make", ["-C", sourceDir.path, "OUT=\(outDir.path)", "build"], timeout: 900)

        let built = outDir.appendingPathComponent("arc").path
        let reported = try step("version check", built, ["--version"], timeout: 30)
        guard ArcVersion.parse(reported.output) == source.version else {
            throw InstallError(description: "built compiler reports '\(reported.output.trimmingCharacters(in: .whitespacesAndNewlines))', expected \(source.version)")
        }
        _ = try step("arc doctor", built, ["doctor"], timeout: 180)

        let dest = root.appendingPathComponent(name, isDirectory: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.createDirectory(at: dest.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dest.appendingPathComponent("share"), withIntermediateDirectories: true)
        try fm.moveItem(atPath: built, toPath: dest.appendingPathComponent("bin/arc").path)
        let reference = sourceDir.appendingPathComponent("LANGUAGE_REFERENCE.md")
        if fm.fileExists(atPath: reference.path) {
            try? fm.copyItem(at: reference, to: dest.appendingPathComponent("share/LANGUAGE_REFERENCE.md"))
        }

        try switchCurrent(to: name)
        for stale in ArcUpdatePlan.installsToRemove(installs(), current: name) {
            try? fm.removeItem(at: root.appendingPathComponent(stale))
        }
        log += "\n✅ installed \(name)\n"
        return name
    }

    /// Repoints `current` atomically (relative link, so the root can move).
    func switchCurrent(to name: String) throws {
        let temp = root.appendingPathComponent(".current-\(UUID().uuidString)").path
        guard symlink(name, temp) == 0 else { throw InstallError(description: "cannot create link for \(name)") }
        guard rename(temp, currentLink.path) == 0 else {
            unlink(temp)
            throw InstallError(description: "cannot switch current to \(name)")
        }
    }
}

/// Schedules update checks and publishes their status for Settings → Runtime Manager.
@MainActor
final class ArcToolchainUpdater: ObservableObject {
    static let shared = ArcToolchainUpdater()

    /// A check is two `git` commands; a build only happens when the source moved.
    static let checkInterval: TimeInterval = 3600
    static let didInstallNotification = Notification.Name("MicroCodeArcToolchainDidInstall")

    enum Status: Equatable {
        case idle
        case checking
        case building(String)
        case upToDate(String)
        case installed(String)
        case failed(String)
        case noSource
    }

    private enum Keys {
        static let autoUpdate = "microcode.arc.autoUpdate"
        static let sourceRepo = "microcode.arc.sourceRepo"
        static let lastFailedCommit = "microcode.arc.lastFailedCommit"
        static let lastChecked = "microcode.arc.lastChecked"
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?
    @Published private(set) var sourcePath: String?
    @Published var autoUpdate: Bool {
        didSet {
            UserDefaults.standard.set(autoUpdate, forKey: Keys.autoUpdate)
            if autoUpdate { start() } else { timer?.invalidate(); timer = nil }
        }
    }

    private var timer: Timer?
    private var isWorking = false

    private init() {
        autoUpdate = UserDefaults.standard.object(forKey: Keys.autoUpdate) as? Bool ?? true
        lastChecked = UserDefaults.standard.object(forKey: Keys.lastChecked) as? Date
    }

    var isBusy: Bool {
        switch status {
        case .checking, .building: return true
        default: return false
        }
    }

    var statusText: String {
        switch status {
        case .idle: return autoUpdate ? "Auto-update on" : "Auto-update off"
        case .checking: return "Checking for a newer Arc…"
        case .building(let name): return "Building Arc \(name)…"
        case .upToDate(let name): return "Up to date (\(name))"
        case .installed(let name): return "Updated to Arc \(name)"
        case .failed(let message): return "Update failed: \(message)"
        case .noSource: return "No Arc source repo found (set one to enable updates)"
        }
    }

    /// Checks shortly after launch, then every `checkInterval` while auto-update is on.
    func start() {
        guard autoUpdate else { return }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { _ in
                Task { @MainActor in await ArcToolchainUpdater.shared.check(manual: false) }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 20_000_000_000) // let launch settle first
                await self.check(manual: false)
            }
        }
    }

    func setSourceRepo(_ path: String?) {
        UserDefaults.standard.set(path, forKey: Keys.sourceRepo)
        sourcePath = path
    }

    func check(manual: Bool) async {
        guard !isWorking, manual || autoUpdate else { return }
        isWorking = true
        defer { isWorking = false }
        status = .checking

        let root = ArcToolchain.shared.managedRoot
        let configured = UserDefaults.standard.string(forKey: Keys.sourceRepo)
        // Stored as "<commit>@r<installer revision>": failures from an older installer are retried.
        let failureSuffix = "@r\(ArcToolchainInstaller.revision)"
        let lastFailed = UserDefaults.standard.string(forKey: Keys.lastFailedCommit)
            .flatMap { $0.hasSuffix(failureSuffix) ? String($0.dropLast(failureSuffix.count)) : nil }

        enum Decision {
            case noSource
            case unreadable(String)
            case upToDate(path: String, name: String)
            case skipped(path: String, commit: String)
            case build(ArcSourceInfo)
        }
        let decision: Decision = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let candidates = ArcUpdatePlan.candidateSources(home: fm.homeDirectoryForCurrentUser.path, configured: configured)
            guard let path = candidates.first(where: { ArcUpdatePlan.isArcSource($0, fileExists: fm.fileExists(atPath:)) }) else {
                return .noSource
            }
            let installer = ArcToolchainInstaller(root: root)
            guard let source = installer.sourceInfo(at: path) else { return .unreadable(path) }
            let installed = installer.currentInstall()
            if !ArcUpdatePlan.needsUpdate(source: source, installed: installed.map { ($0.version, $0.commit) }) {
                return .upToDate(path: path, name: installed?.name ?? ArcUpdatePlan.installName(version: source.version, commit: source.commit))
            }
            guard ArcUpdatePlan.shouldAttempt(source: source, lastFailedCommit: lastFailed, manual: manual) else {
                return .skipped(path: path, commit: source.commit)
            }
            return .build(source)
        }.value

        defer {
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: Keys.lastChecked)
        }
        switch decision {
        case .noSource:
            sourcePath = nil
            status = .noSource
        case .unreadable(let path):
            sourcePath = path
            status = .failed("cannot read VERSION / HEAD in \(path)")
        case .upToDate(let path, let name):
            sourcePath = path
            status = .upToDate(name)
        case .skipped(let path, let commit):
            sourcePath = path
            status = .failed("commit \(commit) failed to build earlier; use Check now to retry")
        case .build(let source):
            sourcePath = source.path
            let name = ArcUpdatePlan.installName(version: source.version, commit: source.commit)
            status = .building(name)
            let result: Result<String?, Error> = await Task.detached(priority: .utility) {
                Result { try ArcToolchainInstaller(root: root).install(source) }
            }.value
            switch result {
            case .success(let installedName?):
                UserDefaults.standard.removeObject(forKey: Keys.lastFailedCommit)
                ArcToolchain.shared.invalidate()
                status = .installed(installedName)
                NotificationCenter.default.post(name: Self.didInstallNotification, object: installedName)
                print("[Arc] Installed \(installedName) from \(source.path)")
            case .success(nil):
                status = .idle // another MicroCode process is building
            case .failure(let error):
                UserDefaults.standard.set(source.commit + failureSuffix, forKey: Keys.lastFailedCommit)
                status = .failed(String(describing: error))
                print("[Arc] Update to \(name) failed: \(error) (log: \(root.path)/logs/\(name).log)")
            }
        }
    }
}
