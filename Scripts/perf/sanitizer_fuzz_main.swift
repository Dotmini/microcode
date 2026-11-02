// Differential fuzz + perf budget for StreamingArtifactSanitizer vs AIStructuredTurnCodec.stripToolCallArtifacts.
// Built and run by scripts/perf/run_perf_gate.sh
import Foundation
var rng = SystemRandomNumberGenerator()
let pieces: [String] = [
  "Hello world ", "เอเจนต์กำลังแก้ไฟล์ ", "ผลลัพธ์ดังนี้\n", "\n", "\n\n", " ", "text ", "line one\n", "```swift\nlet a = 1\n```\n",
  "[Tool Call: file_write(", "{\"path\":\"a.txt\",\"content\":\"x\"}", ")]", ")] ", ")]\n", "[Tool Call:read_file (", "[Tool", "[", "]", "<", ">",
  "<tool_call>", "</tool_call>", "<tool_call name=\"x\">", "<function_call>", "</function_call>", "<function_calls>", "</function_calls>",
  "<invoke name=\"a\">", "</invoke>", "<parameter name=\"p\">", "</parameter>", "<｜DSML｜function_calls>", "</｜DSML｜function_calls>",
  "<|DSML|invoke name=\"z\">", "DSML", "```tool_call\n", "```function_call\n", "```", "``",
  "waiting for tool response...\n", "  *Waiting for tool response*\n", "Waiting for tool response", "waiting for tool", "\twaiting for tool response.\r\n",
  "<invoke", "<parameter", "<tool", "<function", "a < b > c ", "arr[0] ", "\r\n", "\u{E000}", "emoji 🙂 ", "ก็", "ที่นี่ "
]
func original(_ s: String) -> String { AIStructuredTurnCodec.stripToolCallArtifacts(s) }
var fails = 0, flushes = 0, streams = 0, commits = 0
let N = Int(CommandLine.arguments.dropFirst().first ?? "6000") ?? 6000
for _ in 0..<N {
    streams += 1
    var s = StreamingArtifactSanitizer()
    var full = ""
    let nPieces = Int.random(in: 1...60, using: &rng)
    for _ in 0..<nPieces {
        var p = pieces.randomElement(using: &rng)!
        // sometimes split a piece into token-like chunks at scalar boundaries
        while !p.isEmpty {
            let take = Int.random(in: 1...max(1, p.unicodeScalars.count), using: &rng)
            let idx = p.unicodeScalars.index(p.unicodeScalars.startIndex, offsetBy: min(take, p.unicodeScalars.count))
            full += String(p.unicodeScalars[..<idx])
            p = String(p.unicodeScalars[idx...])
            flushes += 1
            let got = s.sanitize(full), want = original(full)
            if got != want {
                fails += 1
                if fails <= 5 { print("MISMATCH\n--- raw:\n\(full.debugDescription)\n--- got:\n\(got.debugDescription)\n--- want:\n\(want.debugDescription)") }
            }
            if Bool.random(using: &rng) && Int.random(in: 0..<30, using: &rng) == 0 { break }
        }
    }
    // occasionally non-append replacement (final flush with different text)
    let alt = full + "\n\n" + "tail"
    if s.sanitize(alt) != original(alt) { fails += 1 }
    if s.sanitize("short") != original("short") { fails += 1 }   // shrink => reset
}
// ---- prose-dominant mode: commits happen constantly, partial openers and waiting-lines mixed in ----
let prose: [String] = ["Hello world ", "เอเจนต์กำลังแก้ไฟล์ ", "ผลลัพธ์ดังนี้\n", "\n", " ", "text ", "line one\n", "\r\n", "[", "<", "[Tool", "<tool", "```swift\nlet a = 1\n```\n",
  "waiting for tool response...\n", "  *Waiting for tool response*\n", "\twaiting for tool response.\r\n", "Waiting for tool response", "a < b > c ", "arr[0] ", "ที่นี่ ", "emoji 🙂 ", "* item\n", "_x_ "]
var proseFails = 0, proseFlushes = 0
for _ in 0..<(N / 2) {
    var s2 = StreamingArtifactSanitizer(); var full = ""
    for _ in 0..<Int.random(in: 5...120, using: &rng) {
        var p = prose.randomElement(using: &rng)!
        while !p.isEmpty {
            let take = Int.random(in: 1...max(1, p.unicodeScalars.count), using: &rng)
            let idx = p.unicodeScalars.index(p.unicodeScalars.startIndex, offsetBy: min(take, p.unicodeScalars.count))
            full += String(p.unicodeScalars[..<idx]); p = String(p.unicodeScalars[idx...]); proseFlushes += 1
            if s2.sanitize(full) != original(full) { proseFails += 1; if proseFails <= 3 { print("PROSE MISMATCH raw=\(full.debugDescription)") } }
        }
    }
}
fails += proseFails
print("prose: flushes=\(proseFlushes) mismatches=\(proseFails)")
// ---- timing on a 128 KB Thai/English prose stream ----
var big = ""; var t = StreamingArtifactSanitizer(); var tNew = 0.0, tOld = 0.0, n = 0
let unit = "เอเจนต์กำลังแก้ไฟล์ `file_write` และอธิบายผลลัพธ์ของ diff พร้อมตัวอย่างโค้ด Swift ให้ผู้ใช้ตรวจสอบ.\n"
while big.utf8.count < 128 * 1024 {
    big += unit; n += 1
    var t0 = DispatchTime.now().uptimeNanoseconds; _ = t.sanitize(big); tNew += Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
    t0 = DispatchTime.now().uptimeNanoseconds; _ = original(big); tOld += Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
}
print(String(format: "128KB prose stream, %d flushes: original %.1f ms total (last %.2f) vs incremental %.1f ms total", n, tOld, 0.0, tNew))
print("streams=\(streams) flushes=\(flushes) mismatches=\(fails)")
let budgetOK = tNew < 1000.0   // 128 KB prose stream, all flushes combined; the original function needs many seconds, so this only catches a regression to O(N) per flush
if !budgetOK { print("PERF BUDGET FAILED: incremental sanitizer took \(tNew) ms") }
exit(fails == 0 && budgetOK ? 0 : 1)
