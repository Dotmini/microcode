import Foundation

// Arc toolchain resolution regression (ArcToolchain.swift). Machine layout of 2026-11-18 that broke the agent:
// ~/.cargo/bin/arc -> ~/.local/bin/arc (Arc 3.1.0), /usr/local/bin/ardium (Ardium 2.x, prints only usage),
// /usr/local/ardium/bin/arc (Ardium wrapper 2.0.0). The agent's shell found `ardium` first and every Arc 3 program
// failed to parse; the runner also injected Ardium 2 library paths into Arc 3 runs.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}

// MARK: version parsing
check(ArcVersion.parse("arc 3.1.0") == ArcVersion(major: 3, minor: 1, patch: 0), "arc 3.1.0")
check(ArcVersion.parse("Dotmini Software | SPU AI CLUB\nArdium Compiler v2.0.0") == ArcVersion(major: 2, minor: 0, patch: 0), "legacy wrapper banner")
check(ArcVersion.parse("❌ Usage: ardium <build|run|test> <file.ar> [options]") == nil, "usage text has no version")
check(ArcVersion.parse("arc 3.2") == ArcVersion(major: 3, minor: 2, patch: 0), "two-part version")
check(ArcVersion(major: 3, minor: 10, patch: 0) > ArcVersion(major: 3, minor: 9, patch: 9), "numeric, not lexical, ordering")

// MARK: resolution with a fake filesystem
let home = "/Users/u"
let managed = "/Users/u/Library/Application Support/MicroCode/Runtimes/arc/current/bin/arc"

struct FakeMachine {
    var versions: [String: String]          // executable path -> `--version` output
    var links: [String: String] = [:]       // symlink -> target
    var environment: [String: String] = ["PATH": "/usr/local/bin:/usr/bin:/bin"]

    func resolve() -> ArcToolchainResolution? {
        ArcToolchainResolver.resolve(
            home: home,
            environment: environment,
            managedBinary: managed,
            isExecutable: { versions[$0] != nil || links[$0] != nil },
            realPath: { links[$0] ?? $0 },
            versionOutput: { versions[links[$0] ?? $0] }
        )
    }
}

let thisMachine = FakeMachine(
    versions: [
        "\(home)/.local/bin/arc": "arc 3.1.0",
        "/usr/local/bin/ardium": "❌ Usage: ardium <build|run|test> <file.ar> [options]",
        "/usr/local/ardium/bin/arc": "Ardium Compiler v2.0.0"
    ],
    links: ["\(home)/.cargo/bin/arc": "\(home)/.local/bin/arc"]
)
let resolved = thisMachine.resolve()
check(resolved?.path == "\(home)/.local/bin/arc", "Arc 3.1 in ~/.local/bin is used: \(String(describing: resolved))")
check(resolved?.version == ArcVersion(major: 3, minor: 1, patch: 0) && resolved?.isLegacy == false, "modern toolchain, not legacy")

let legacyOnly = FakeMachine(versions: [
    "/usr/local/bin/ardium": "❌ Usage: ardium <build|run|test> <file.ar> [options]",
    "/usr/local/ardium/bin/arc": "Ardium Compiler v2.0.0"
])
let legacy = legacyOnly.resolve()
check(legacy?.isLegacy == true && legacy?.path == "/usr/local/ardium/bin/arc", "machines with only Ardium 2 keep working (legacy): \(String(describing: legacy))")

let v2NamedArc = FakeMachine(versions: [
    "/usr/local/bin/arc": "Ardium Compiler v2.0.0",
    "/opt/homebrew/bin/arc": "arc 3.0.1"
])
check(v2NamedArc.resolve()?.path == "/opt/homebrew/bin/arc", "an Ardium 2 binary named `arc` is skipped for a real Arc 3")

let newestWins = FakeMachine(versions: [
    managed: "arc 3.1.0",
    "\(home)/.local/bin/arc": "arc 3.3.0"
])
check(newestWins.resolve()?.path == "\(home)/.local/bin/arc", "the newest Arc 3 install wins")
let managedNewer = FakeMachine(versions: [
    managed: "arc 3.2.0",
    "\(home)/.local/bin/arc": "arc 3.1.0"
])
check(managedNewer.resolve()?.path == managed, "MicroCode-managed install wins when newer")
let tie = FakeMachine(versions: [
    managed: "arc 3.1.0",
    "\(home)/.local/bin/arc": "arc 3.1.0"
])
check(tie.resolve()?.path == managed, "equal versions: earlier candidate (managed) wins")

var explicitLegacy = FakeMachine(versions: [
    "/opt/ardium-old/ardium": "❌ Usage: ardium <build|run|test> <file.ar> [options]",
    "\(home)/.local/bin/arc": "arc 3.1.0"
])
explicitLegacy.environment["ARDIUM_BIN"] = "/opt/ardium-old/ardium"
let pinned = explicitLegacy.resolve()
check(pinned?.path == "/opt/ardium-old/ardium" && pinned?.isLegacy == true, "explicit $ARDIUM_BIN is honoured and treated as legacy")

var explicitArc = FakeMachine(versions: [
    "/opt/arc-dev/arc": "arc 3.2.0-dev",
    "\(home)/.local/bin/arc": "arc 3.9.0"
])
explicitArc.environment["ARC_BIN"] = "/opt/arc-dev/arc"
check(explicitArc.resolve()?.path == "/opt/arc-dev/arc", "explicit $ARC_BIN beats a newer auto-detected install")

var pathOnly = FakeMachine(versions: ["/custom/bin/arc": "arc 3.1.0"])
pathOnly.environment["PATH"] = "/custom/bin:/usr/bin"
check(pathOnly.resolve()?.path == "/custom/bin/arc", "arc found through PATH")

check(FakeMachine(versions: [:]).resolve() == nil, "no toolchain → nil")

// MARK: process environment
let modern = ArcToolchainResolution(path: "\(home)/.local/bin/arc", version: ArcVersion(major: 3, minor: 1, patch: 0), isLegacy: false, source: "~/.local/bin")
let modernEnv = ArcToolchainEnvironment.make(base: ["PATH": "/usr/local/bin:/usr/bin", "DYLD_LIBRARY_PATH": "/x"], resolution: modern, shimDirectory: "/shim")
check(modernEnv["PATH"]?.hasPrefix("/shim:") == true, "shim directory comes before /usr/local/bin: \(modernEnv["PATH"] ?? "")")
check(modernEnv["DYLD_LIBRARY_PATH"] == "/x" && modernEnv["ARDIUM_STDLIB"] == nil && modernEnv["ARDIUM_LIB_PATH"] == nil, "Arc 3 runs get no Ardium 2 library paths")
let legacyEnv = ArcToolchainEnvironment.make(base: ["PATH": "/usr/bin"], resolution: legacy!, shimDirectory: nil)
check(legacyEnv["ARDIUM_STDLIB"] == "/usr/local/ardium/stdlib" && legacyEnv["DYLD_LIBRARY_PATH"]?.hasPrefix("/usr/local/ardium/lib") == true, "legacy runs keep their library paths")
check(ArcToolchainEnvironment.make(base: ["PATH": "/shim:/usr/bin"], resolution: modern, shimDirectory: "/shim")["PATH"] == "/shim:/usr/bin", "shim is not duplicated")

// MARK: CLI capability (no `arc lsp` in Arc 3.1)
let help = """
arc 3.1.0 — the Arc programming language

COMMANDS:
    run [file] [args...]   Compile and run a program (cached, native speed)
    test [files...]        Run @test functions (default: tests/ and src/)
    doctor                 Check the toolchain
"""
check(ArcToolchainResolver.helpLists(command: "test", in: help), "test is listed")
check(!ArcToolchainResolver.helpLists(command: "lsp", in: help), "lsp is not listed")
check(!ArcToolchainResolver.helpLists(command: "programming", in: help), "only command names count")

// MARK: stopping a program and its children on timeout
let table: [(pid: Int32, ppid: Int32)] = [(10, 1), (11, 10), (12, 11), (13, 10), (20, 1), (21, 20)]
let tree = ProcessTree.descendants(of: 10, in: table)
check(Set(tree) == [11, 12, 13], "descendants of the runner: \(tree)")
check(tree.firstIndex(of: 12)! < tree.firstIndex(of: 11)!, "children are stopped before their parents")
check(ProcessTree.descendants(of: 99, in: table).isEmpty, "unknown pid has no descendants")

if failures == 0 {
    print("ARC TOOLCHAIN REGRESSION: PASS")
} else {
    print("ARC TOOLCHAIN REGRESSION: \(failures) FAILURE(S)")
    exit(1)
}
