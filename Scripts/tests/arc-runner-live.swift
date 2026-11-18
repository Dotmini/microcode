import Foundation

// Live check of ArdiumRunner + ArcToolchain against the `arc` installed on this Mac (skips when none).
let toolchain = ArcToolchain.shared
guard let resolution = toolchain.current(forceRefresh: true), !resolution.isLegacy else {
    print("ARC RUNNER LIVE: SKIPPED (\(toolchain.statusDescription))")
    exit(0)
}
var failures = 0
func check(_ condition: Bool, _ message: String) { if !condition { failures += 1; print("FAIL: \(message)") } }
print("toolchain:", toolchain.statusDescription)
print("PATH head:", (toolchain.environment()["PATH"] ?? "").split(separator: ":").prefix(2).joined(separator: ":"))
check(toolchain.supports(command: "test") && !toolchain.supports(command: "lsp"), "help parsing on the real CLI")
check(toolchain.environment()["ARDIUM_STDLIB"] == nil, "no Ardium 2 env for Arc 3")

let sem = DispatchSemaphore(value: 0)
Task {
    let hello = await ArdiumRunner.execute(code: "fn main() { println(\"hello arc\") }")
    check(hello.exitCode == 0 && hello.stdout.contains("hello arc"), "hello: \(hello)")

    let big = await ArdiumRunner.execute(code: "fn main() { for i in 0..200000 { println(f\"line {i} padding padding padding\") } }")
    check(big.exitCode == 0 && big.stdout.contains("line 199999"), "large output does not deadlock (exit \(big.exitCode), \(big.stdout.count) bytes)")

    let start = Date()
    let loop = await ArdiumRunner.execute(code: "fn main() { loop { sleep_ms(50) } }", timeout: 4)
    let elapsed = Date().timeIntervalSince(start)
    check(loop.exitCode == ArdiumRunner.timeoutExitCode && loop.stderr.contains("Stopped after"), "endless loop stopped: \(loop.exitCode) \(loop.stderr.suffix(120))")
    check(elapsed < 15, "timeout honoured (\(Int(elapsed)) s incl. compile)")
    // The compiled program (child of `arc run`) must be gone too.
    try? await Task.sleep(nanoseconds: 2_000_000_000)
    let ps = Process(); ps.executableURL = URL(fileURLWithPath: "/bin/sh")
    ps.arguments = ["-c", "ps -A -o command= | grep -c '[.]cache/arc' || true"]
    let pipe = Pipe(); ps.standardOutput = pipe; try? ps.run(); ps.waitUntilExit()
    let running = Int(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
    check(running == 0, "no compiled Arc program left running after the timeout (found \(running))")
    sem.signal()
}
sem.wait()
print(failures == 0 ? "ARC RUNNER LIVE: PASS" : "ARC RUNNER LIVE: \(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
