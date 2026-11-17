import Foundation

// Phase 1 agent-loop regression (2026-11-17 review). Compiled with the real
// MicroCode/Services/AIStreamPrimitives.swift by `run-phase1-loop.sh`.

@main struct Phase1LoopRegression {
    static func main() {
        stopReasons()
        emissionTracker()
        systemPromptLayout()
        print("PHASE1 LOOP REGRESSION: PASS")
    }

    static func stopReasons() {
        // Anthropic
        precondition(AIStopReason.normalize("end_turn") == .endTurn)
        precondition(AIStopReason.normalize("tool_use") == .toolUse)
        precondition(AIStopReason.normalize("max_tokens") == .maxTokens)
        precondition(AIStopReason.normalize("refusal") == .refusal)
        // OpenAI-compatible
        precondition(AIStopReason.normalize("stop") == .endTurn)
        precondition(AIStopReason.normalize("tool_calls") == .toolUse)
        precondition(AIStopReason.normalize("length") == .maxTokens)
        precondition(AIStopReason.normalize("content_filter") == .refusal)
        // Gemini
        precondition(AIStopReason.normalize("STOP") == .endTurn)
        precondition(AIStopReason.normalize("MAX_TOKENS") == .maxTokens)
        precondition(AIStopReason.normalize("SAFETY") == .refusal)
        precondition(AIStopReason.normalize("MALFORMED_FUNCTION_CALL") == .other("MALFORMED_FUNCTION_CALL"))
        // Streams send `null` / empty until the final chunk: those must not overwrite a recorded reason.
        precondition(AIStopReason.normalize(nil) == nil)
        precondition(AIStopReason.normalize("  ") == nil)
    }

    static func emissionTracker() {
        let tracker = StreamEmissionTracker()
        precondition(!tracker.didEmit)
        DispatchQueue.concurrentPerform(iterations: 64) { _ in tracker.mark() }
        precondition(tracker.didEmit)
    }

    static func systemPromptLayout() {
        let stable = "## Core rules\nAlways verify.\n\n## Provider Harness Contract\nClaude / x"
        let dynamic = "## Editor\nFile: a.swift L12\n\n## Memory\nfoo"
        let prompt = stable + AISystemPromptLayout.dynamicBoundary + "\n\n" + dynamic

        let blocks = AISystemPromptLayout.anthropicSystemBlocks(prompt)
        precondition(blocks.count == 2, "stable + dynamic blocks")
        precondition(blocks[0]["text"] as? String == stable, "stable prefix must be byte-identical across turns")
        precondition(blocks[0]["cache_control"] != nil, "cache breakpoint on the stable prefix")
        precondition(blocks[1]["cache_control"] == nil, "dynamic context must not carry a breakpoint (4-breakpoint limit)")
        precondition(blocks[1]["text"] as? String == dynamic)
        precondition(!(blocks.compactMap { $0["text"] as? String }.joined().contains("microcode:dynamic-context")),
                     "boundary marker is never sent to Anthropic")

        // Changing only per-message context keeps the cached prefix identical.
        let other = AISystemPromptLayout.anthropicSystemBlocks(stable + AISystemPromptLayout.dynamicBoundary + "\n\n## Editor\nFile: b.swift")
        precondition(other[0]["text"] as? String == blocks[0]["text"] as? String)

        let legacy = AISystemPromptLayout.anthropicSystemBlocks("no boundary here")
        precondition(legacy.count == 1 && legacy[0]["cache_control"] != nil)
        let emptyDynamic = AISystemPromptLayout.anthropicSystemBlocks(stable + AISystemPromptLayout.dynamicBoundary + "\n   ")
        precondition(emptyDynamic.count == 1)
    }
}
