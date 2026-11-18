import Foundation

// Arc auto-updater decisions (ArcToolchainUpdater.swift): when to rebuild, how installs are named, what is kept.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}

let v310 = ArcVersion(major: 3, minor: 1, patch: 0)
let v311 = ArcVersion(major: 3, minor: 1, patch: 1)
let v300 = ArcVersion(major: 3, minor: 0, patch: 0)

// MARK: install folder names: "<version>+<commit>"
check(ArcUpdatePlan.installName(version: v310, commit: "990189d") == "3.1.0+990189d", "install name")
let parsed = ArcUpdatePlan.parseInstallName("3.1.0+990189d")
check(parsed?.version == v310 && parsed?.commit == "990189d", "parse install name")
check(ArcUpdatePlan.parseInstallName("current") == nil && ArcUpdatePlan.parseInstallName("3.1.0") == nil && ArcUpdatePlan.parseInstallName(".build-x") == nil, "non-install entries are ignored")

// MARK: when to build
let source = ArcSourceInfo(path: "/src/arc", version: v310, commit: "990189d")
check(ArcUpdatePlan.needsUpdate(source: source, installed: nil), "nothing installed → build")
check(!ArcUpdatePlan.needsUpdate(source: source, installed: (v310, "990189d")), "same commit → up to date")
check(ArcUpdatePlan.needsUpdate(source: ArcSourceInfo(path: "/src/arc", version: v310, commit: "abc1234"), installed: (v310, "990189d")), "new commit, same VERSION → rebuild (always newest)")
check(ArcUpdatePlan.needsUpdate(source: ArcSourceInfo(path: "/src/arc", version: v311, commit: "abc1234"), installed: (v310, "990189d")), "newer VERSION → rebuild")
check(!ArcUpdatePlan.needsUpdate(source: ArcSourceInfo(path: "/src/arc", version: v300, commit: "0ld0000"), installed: (v310, "990189d")), "older checkout never downgrades")
check(!ArcUpdatePlan.needsUpdate(source: ArcSourceInfo(path: "/src/arc", version: ArcVersion(major: 2, minor: 7, patch: 1), commit: "aaa"), installed: nil), "Ardium 2 sources are never installed as Arc")

// MARK: do not retry a commit that already failed to build, unless the user asks
check(ArcUpdatePlan.shouldAttempt(source: source, lastFailedCommit: "990189d", manual: false) == false, "automatic check skips a known-bad commit")
check(ArcUpdatePlan.shouldAttempt(source: source, lastFailedCommit: "990189d", manual: true), "Check now retries it")
check(ArcUpdatePlan.shouldAttempt(source: source, lastFailedCommit: "other", manual: false), "a different commit is attempted")

// MARK: source detection
let files: Set<String> = ["/home/u/Documents/ardium/VERSION", "/home/u/Documents/ardium/Makefile",
                          "/home/u/Documents/ardium/src/compiler/driver.cpp", "/home/u/Documents/ardium/src/runtime/arc_rt.c",
                          "/home/u/old-ardium/VERSION", "/home/u/old-ardium/Makefile"]
let exists: (String) -> Bool = { files.contains($0) }
check(ArcUpdatePlan.isArcSource("/home/u/Documents/ardium", fileExists: exists), "Arc 3 source layout recognised")
check(!ArcUpdatePlan.isArcSource("/home/u/old-ardium", fileExists: exists), "a folder without the Arc 3 compiler is not a source")
let candidates = ArcUpdatePlan.candidateSources(home: "/home/u", configured: "/custom/arc")
check(candidates.first == "/custom/arc" && candidates.contains("/home/u/Documents/ardium"), "configured source first, then common locations: \(candidates)")
check(ArcUpdatePlan.candidateSources(home: "/home/u", configured: "/home/u/Documents/ardium").filter { $0 == "/home/u/Documents/ardium" }.count == 1, "no duplicates")

// MARK: build scratch folder never contains spaces (Make breaks on them; 2026-11-18 first in-app build failed)
let spaced = ArcToolchainInstaller.scratchDirectory(base: URL(fileURLWithPath: "/Users/u/Library/Application Support/X"), id: "1")
check(!spaced.path.contains(" ") && spaced.lastPathComponent == "microcode-arc-build-1", "spaced base falls back to /tmp: \(spaced.path)")
check(ArcToolchainInstaller.scratchDirectory(base: URL(fileURLWithPath: "/var/folders/ab/T"), id: "2").path == "/var/folders/ab/T/microcode-arc-build-2", "normal temp dir is used as is")

// MARK: pruning keeps the active install and the most recent previous one (rollback)
let now = Date()
let installs: [(name: String, installedAt: Date)] = [
    ("3.0.9+aaa", now.addingTimeInterval(-400)),
    ("3.1.0+bbb", now.addingTimeInterval(-300)),
    ("3.1.0+ccc", now.addingTimeInterval(-200)),
    ("3.1.1+ddd", now.addingTimeInterval(-100))
]
let doomed = ArcUpdatePlan.installsToRemove(installs, current: "3.1.1+ddd")
check(Set(doomed) == ["3.0.9+aaa", "3.1.0+bbb"], "keeps current + latest previous: \(doomed)")
check(ArcUpdatePlan.installsToRemove(installs, current: nil).isEmpty, "never prunes without a known current install")

if failures == 0 {
    print("ARC UPDATER REGRESSION: PASS")
} else {
    print("ARC UPDATER REGRESSION: \(failures) FAILURE(S)")
    exit(1)
}
