import Foundation

// CurlSecretArguments: tokens and bodies leave curl's argv (visible in `ps`) and reach curl via `--config -`.
// The live part runs /usr/bin/curl against a local `nc` listener, so no network is needed.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition { failures += 1; print("FAIL: \(message)") }
}

let token = "eyJhbGciOiJIUzI1NiJ9.secret-payload.sig"
let body = #"{"refresh_token":"r-\"quoted\"","note":"a\\b"}"#
let (argv, config) = CurlSecretArguments.split([
    "-X", "POST", "https://example.invalid/auth/v1/token?grant_type=refresh_token",
    "-H", "apikey: anon", "-H", "Authorization: Bearer \(token)", "-H", "Content-Type: application/json",
    "--data", body
])
check(!argv.joined(separator: " ").contains(token) && !argv.joined(separator: " ").contains("refresh_token\""), "no secret left in argv: \(argv)")
check(argv == ["-X", "POST", "https://example.invalid/auth/v1/token?grant_type=refresh_token", "--config", "-"], "argv keeps method + URL: \(argv)")
check(config.contains("header = \"Authorization: Bearer \(token)\""), "header moved")
check(config.contains(#"data = "{\"refresh_token\":\"r-\\\"quoted\\\"\",\"note\":\"a\\\\b\"}""#), "body escaped: \(config)")
let untouched = CurlSecretArguments.split(["https://example.invalid/v1/models"])
check(untouched.argv == ["https://example.invalid/v1/models"] && untouched.config.isEmpty, "nothing to move → unchanged")

// Live: a local `nc` listener records the exact request curl sends after reading the config from stdin.
let port = 47000 + Int.random(in: 0..<2000)
let listener = Process()
listener.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
listener.arguments = ["-l", "127.0.0.1", "\(port)"]
let captured = Pipe()
listener.standardOutput = captured
listener.standardError = FileHandle.nullDevice
try! listener.run()
Thread.sleep(forTimeInterval: 0.4)
let live = CurlSecretArguments.split(["-sS", "--max-time", "2", "-H", "X-Test: \(token)", "--data", body, "http://127.0.0.1:\(port)/t"])
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
proc.arguments = live.argv
let stdin = Pipe()
proc.standardInput = stdin
proc.standardOutput = FileHandle.nullDevice
proc.standardError = FileHandle.nullDevice
try! proc.run()
stdin.fileHandleForWriting.write(Data(live.config.utf8))
try? stdin.fileHandleForWriting.close()
proc.waitUntilExit()   // times out after 2 s: nc never answers
listener.terminate()
let request = String(data: captured.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
check(request.contains("POST /t HTTP/1.1"), "curl sent the request: \(request.prefix(80))")
check(request.contains("X-Test: \(token)"), "header arrived intact")
check(request.contains(body), "body arrived byte-for-byte")

if failures == 0 { print("CURL SECRET ARGUMENTS REGRESSION: PASS") } else { print("CURL SECRET ARGUMENTS REGRESSION: \(failures) FAILURE(S)"); exit(1) }
