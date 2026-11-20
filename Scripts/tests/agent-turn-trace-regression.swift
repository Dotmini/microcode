import Foundation

// AgentTurnTrace (AgentTurnTrace.swift): counts harness interventions and survives a JSON round trip.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition { failures += 1; print("FAIL: \(message)") }
}

var trace = AgentTurnTrace(provider: "aipass", model: "claude-sonnet-5-5", followUp: "operate")
trace.note("nag.files_missing"); trace.note("nag.files_missing"); trace.note("fallback.build")
trace.failovers.append("openai/gpt-5")
trace.iterations = 6
trace.end("verified"); trace.end("no_tool_answer")
check(trace.endReason == "verified", "first end reason wins")
check(trace.interventions == ["nag.files_missing": 2, "fallback.build": 1] && trace.totalInterventions == 3, "counts")
check(trace.summary == "aipass/claude-sonnet-5-5 · 6 steps · fallback.build×1 nag.files_missing×2 · end=verified", trace.summary)

let data = try! JSONEncoder().encode(trace)
let back = try! JSONDecoder().decode(AgentTurnTrace.self, from: data)
check(back == trace, "round trip")

// Persisted messages written before the field existed decode with nil (the field is optional in AgentMessageData).
struct Persisted: Codable { let id: String; var harnessTrace: AgentTurnTrace? = nil }
let old = try! JSONDecoder().decode(Persisted.self, from: Data(#"{"id":"m1"}"#.utf8))
check(old.harnessTrace == nil, "old transcripts still decode")

if failures == 0 { print("AGENT TURN TRACE REGRESSION: PASS") } else { print("AGENT TURN TRACE REGRESSION: \(failures) FAILURE(S)"); exit(1) }
