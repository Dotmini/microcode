import Foundation

/// What happened inside one agent turn, saved with the assistant message (transcripts used to record neither the
/// model nor any harness intervention, so a bad answer could not be traced to "weak model" vs "harness pushed it").
///
/// `interventions` counts every time the harness overrode or steered the model instead of just returning tool
/// results: forced fallback tool calls, follow-through nags, per-batch instructions, retries, failovers, breakers.
struct AgentTurnTrace: Codable, Equatable {
    var provider: String
    var model: String
    var followUp: String?
    var iterations: Int = 0
    var interventions: [String: Int] = [:]
    /// Provider/model pairs switched to by failover, in order.
    var failovers: [String] = []
    /// Why the loop ended: verified, kernel_complete, repetition, stall_guard, kernel_stalled, iteration_limit,
    /// context_limit, error, cancelled, media, local_synthesis, no_tool_answer.
    var endReason: String?

    init(provider: String, model: String, followUp: String? = nil) {
        self.provider = provider
        self.model = model
        self.followUp = followUp
    }

    mutating func note(_ intervention: String) {
        interventions[intervention, default: 0] += 1
    }

    mutating func end(_ reason: String) {
        if endReason == nil { endReason = reason }
    }

    var totalInterventions: Int { interventions.values.reduce(0, +) }

    /// One-line summary for logs: "openai/gpt-5 · 6 steps · nag.files_missing×2 fallback.build×1 · end=verified".
    var summary: String {
        let parts = interventions.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
        return "\(provider)/\(model) · \(iterations) steps" + (parts.isEmpty ? "" : " · \(parts)") + " · end=\(endReason ?? "unknown")"
    }
}
