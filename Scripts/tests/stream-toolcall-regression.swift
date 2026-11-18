import Foundation

// Regression for streamed OpenAI-style `tool_calls` assembly (AIStreamPrimitives.swift).
// Real failure (DeepSeek via Dotmini Cloud, 2026-11-18): two parallel calls arrived without distinct `index`
// values and were merged into one call named after the second, with arguments
// `{"path":"…/examples"}{"query":"ardium-lang","action":"read"}` — so the skill was never read.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}

func fn(_ name: String? = nil, _ arguments: String? = nil) -> [String: Any] {
    var function: [String: Any] = [:]
    if let name { function["name"] = name }
    if let arguments { function["arguments"] = arguments }
    return function
}

func delta(index: Int? = nil, id: String? = nil, _ function: [String: Any]) -> [String: Any] {
    var d: [String: Any] = ["type": "function", "function": function]
    if let index { d["index"] = index }
    if let id { d["id"] = id }
    return d
}

func assemble(_ deltas: [[String: Any]]) -> [StreamedToolCallAccumulator.Call] {
    var counter = 0
    var accumulator = StreamedToolCallAccumulator(makeId: { counter += 1; return "synthetic-\(counter)" })
    for d in deltas { accumulator.add(delta: d) }
    return accumulator.drain()
}

func summary(_ calls: [StreamedToolCallAccumulator.Call]) -> String {
    calls.map { "\($0.id):\($0.name)(\($0.arguments))" }.joined(separator: " | ")
}

// 1. OpenAI: index on every delta, id + name on the first only, arguments chunked.
let openAISingle = assemble([
    delta(index: 0, id: "call_1", fn("file_read", "")),
    delta(index: 0, fn(nil, "{\"pa")),
    delta(index: 0, fn(nil, "th\":\"a.txt\"}"))
])
check(openAISingle == [.init(id: "call_1", name: "file_read", arguments: "{\"path\":\"a.txt\"}")], "OpenAI single call: \(summary(openAISingle))")

// 2. OpenAI parallel calls, interleaved by index.
let openAIParallel = assemble([
    delta(index: 0, id: "a", fn("list_directory_tree", "")),
    delta(index: 1, id: "b", fn("skill_engine", "")),
    delta(index: 0, fn(nil, "{\"path\":\"/x\"}")),
    delta(index: 1, fn(nil, "{\"action\":\"read\",\"query\":\"ardium-lang\"}"))
])
check(openAIParallel.map(\.name) == ["list_directory_tree", "skill_engine"], "OpenAI parallel names: \(summary(openAIParallel))")
check(openAIParallel.map(\.arguments) == ["{\"path\":\"/x\"}", "{\"action\":\"read\",\"query\":\"ardium-lang\"}"], "OpenAI parallel arguments: \(summary(openAIParallel))")

// 3. The observed failure: parallel calls with their own ids but no index.
let noIndex = assemble([
    delta(id: "function-call-1", fn("list_directory_tree", "{\"path\":\"/Users/x/examples\"}")),
    delta(id: "function-call-2", fn("skill_engine", "{\"query\":\"ardium-lang\",\"action\":\"read\"}"))
])
check(noIndex.count == 2, "parallel calls without index stay separate: \(summary(noIndex))")
check(noIndex.map(\.name) == ["list_directory_tree", "skill_engine"], "names preserved: \(summary(noIndex))")
check(noIndex.last?.arguments == "{\"query\":\"ardium-lang\",\"action\":\"read\"}", "skill_engine keeps only its own arguments: \(summary(noIndex))")

// 4. Same index reused for parallel calls with different ids.
let sameIndex = assemble([
    delta(index: 0, id: "a", fn("x", "{}")),
    delta(index: 0, id: "b", fn("y", "{\"k\":1}")),
    delta(index: 0, fn(nil, ""))
])
check(sameIndex == [.init(id: "a", name: "x", arguments: "{}"), .init(id: "b", name: "y", arguments: "{\"k\":1}")], "reused index 0 with new id starts a new call: \(summary(sameIndex))")

// 5. Providers that repeat the id on every delta.
let repeatedId = assemble([
    delta(index: 0, id: "a", fn("x", "{\"k\"")),
    delta(index: 0, id: "a", fn(nil, ":1}"))
])
check(repeatedId == [.init(id: "a", name: "x", arguments: "{\"k\":1}")], "repeated id continues the same call: \(summary(repeatedId))")

// 6. No index; continuation deltas carry neither id nor index.
let continuation = assemble([
    delta(id: "a", fn("x", "{\"k\"")),
    delta(fn(nil, ":1}"))
])
check(continuation == [.init(id: "a", name: "x", arguments: "{\"k\":1}")], "id-less continuation appends to the latest call: \(summary(continuation))")

// 7. Neither id nor index, two complete calls: a new name after complete arguments starts a new call.
let anonymous = assemble([
    delta(fn("x", "{}")),
    delta(fn("y", "{\"k\":1}"))
])
check(anonymous.map(\.name) == ["x", "y"] && Set(anonymous.map(\.id)).count == 2, "anonymous complete calls stay separate: \(summary(anonymous))")

// 8. A repeated name mid-call (arguments still incomplete) does not split the call.
let repeatedName = assemble([
    delta(fn("x", "{\"k\"")),
    delta(fn("x", ":1}"))
])
check(repeatedName.count == 1 && repeatedName.first?.arguments == "{\"k\":1}", "repeated name mid-call: \(summary(repeatedName))")

// 9. First delta without id, real id arrives later at the same index.
let lateId = assemble([
    delta(index: 0, fn("x", "")),
    delta(index: 0, id: "real", fn(nil, "{}"))
])
check(lateId == [.init(id: "real", name: "x", arguments: "{}")], "late id is adopted by the open call: \(summary(lateId))")

// 10. Nameless fragments are dropped; drain empties the accumulator.
var accumulator = StreamedToolCallAccumulator()
accumulator.add(delta: delta(index: 3, fn(nil, "{\"orphan\":1}")))
accumulator.add(delta: delta(index: 0, id: "ok", fn("git_status", "{}")))
check(!accumulator.isEmpty, "accumulator holds buffered calls")
let drained = accumulator.drain()
check(drained.map(\.id) == ["ok"], "only named calls are emitted: \(summary(drained))")
check(accumulator.isEmpty && accumulator.drain().isEmpty, "drain empties the accumulator")

// Diagnosis of unparseable arguments
let merged = "{\"path\":\"/x/examples\"}{\"query\":\"ardium-lang\",\"action\":\"read\"}"
check(ToolArgumentDiagnosis.topLevelObjectCount(merged) == 2, "two concatenated objects are detected")
check(ToolArgumentDiagnosis.topLevelObjectCount("{\"content\":\"a}{b\"}") == 1, "braces inside strings are ignored")
check(ToolArgumentDiagnosis.topLevelObjectCount("{\"content\":\"abc") == 0, "a cut-off object is not complete")
let mergedMessage = ToolArgumentDiagnosis.invalidArgumentsMessage(toolName: "skill_engine", raw: merged)
check(mergedMessage.contains("merged") && !mergedMessage.contains("output token limit"), "merged calls are not blamed on the token limit: \(mergedMessage)")
let cutMessage = ToolArgumentDiagnosis.invalidArgumentsMessage(toolName: "file_write", raw: "{\"path\":\"a\",\"content\":\"abc")
check(cutMessage.contains("cut off"), "truncated arguments still explain the token limit: \(cutMessage)")

if failures == 0 {
    print("STREAM TOOL-CALL REGRESSION: PASS")
} else {
    print("STREAM TOOL-CALL REGRESSION: \(failures) FAILURE(S)")
    exit(1)
}
