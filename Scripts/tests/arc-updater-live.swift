import Foundation

// Live: build the Arc source repo at HEAD into a temporary managed root, exactly as the app's updater does.
// Usage (via run-arc-updater.sh --live <repo>): arc-updater-live <arc-source-repo> <temporary-managed-root>

var failures = 0
func check(_ condition: Bool, _ message: String) { if !condition { failures += 1; print("FAIL: \(message)") } }

let arguments = CommandLine.arguments
guard arguments.count == 3 else { print("usage: arc-updater-live <repo> <root>"); exit(2) }
let repo = arguments[1]
let root = URL(fileURLWithPath: arguments[2], isDirectory: true)
let installer = ArcToolchainInstaller(root: root)

check(ArcUpdatePlan.isArcSource(repo, fileExists: FileManager.default.fileExists(atPath:)), "\(repo) is an Arc source checkout")
let statusBefore = ArcProcess.run("/usr/bin/git", ["-C", repo, "status", "--porcelain"], timeout: 30).output

guard let source = installer.sourceInfo(at: repo) else { print("FAIL: cannot read VERSION/HEAD"); exit(1) }
print("source:", source.version, source.commit)
check(ArcUpdatePlan.needsUpdate(source: source, installed: installer.currentInstall().map { ($0.version, $0.commit) }), "fresh root needs a build")

let start = Date()
do {
    let name = try installer.install(source)
    print("installed:", name ?? "nil", "in", Int(Date().timeIntervalSince(start)), "s")
    check(name == ArcUpdatePlan.installName(version: source.version, commit: source.commit), "install name")
    check(installer.currentInstall()?.name == name, "current points at the new install")
    let arc = root.appendingPathComponent("current/bin/arc").path
    let version = ArcProcess.run(arc, ["--version"], timeout: 10).output
    check(ArcVersion.parse(version) == source.version, "installed compiler runs: \(version)")
    check(FileManager.default.fileExists(atPath: root.appendingPathComponent("current/share/LANGUAGE_REFERENCE.md").path), "reference doc installed with the compiler")
    check(!ArcUpdatePlan.needsUpdate(source: source, installed: installer.currentInstall().map { ($0.version, $0.commit) }), "same HEAD → no rebuild")

    // The resolver picks the managed build (it is at least as new as any other install).
    let resolution = ArcToolchainResolver.resolve(
        home: FileManager.default.homeDirectoryForCurrentUser.path,
        environment: ProcessInfo.processInfo.environment,
        managedBinary: arc,
        isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
        realPath: { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
        versionOutput: { ArcProcess.run($0, ["--version"], timeout: 5).output }
    )
    check(resolution?.path == arc || (resolution?.version ?? source.version) > source.version, "resolver uses the managed build: \(String(describing: resolution))")
} catch {
    failures += 1
    print("FAIL: install threw \(error)")
}

let tempEntries = (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? []
let leftovers = ((try? FileManager.default.contentsOfDirectory(atPath: root.path))?.filter { $0.hasPrefix(".build-") } ?? [])
    + tempEntries.filter { $0.hasPrefix("microcode-arc-build-") }
check(leftovers.isEmpty, "scratch build folders are removed: \(leftovers)")
let statusAfter = ArcProcess.run("/usr/bin/git", ["-C", repo, "status", "--porcelain"], timeout: 30).output
check(statusBefore == statusAfter, "the source repo's working tree is untouched")

print(failures == 0 ? "ARC UPDATER LIVE: PASS" : "ARC UPDATER LIVE: \(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
