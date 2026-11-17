import Foundation

// Provider-neutral streaming primitives shared by AIClient and the agent loop.
// Kept dependency-free so they can be regression-tested outside the app target.

/// Provider-neutral reason a model turn ended.
enum AIStopReason: Equatable {
    case endTurn      // the model chose to finish (end_turn / stop / STOP)
    case toolUse      // the model is waiting for tool results
    case maxTokens    // cut off by the output token limit
    case refusal      // safety / content filter / refusal
    case other(String)

    static func normalize(_ raw: String?) -> AIStopReason? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        switch value.lowercased() {
        case "end_turn", "stop", "stop_sequence", "eos":
            return .endTurn
        case "tool_use", "tool_calls", "function_call":
            return .toolUse
        case "max_tokens", "length", "model_length", "max_output_tokens":
            return .maxTokens
        case "refusal", "content_filter", "safety", "recitation", "prohibited_content", "blocklist", "spii", "image_safety":
            return .refusal
        default:
            return .other(value)
        }
    }
}

/// Records whether a streaming attempt has already delivered output to the caller (thread-safe).
final class StreamEmissionTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var emitted = false

    func mark() {
        lock.lock(); emitted = true; lock.unlock()
    }

    var didEmit: Bool {
        lock.lock(); defer { lock.unlock() }
        return emitted
    }
}

/// Layout of the agent system prompt: a stable, cacheable prefix followed by per-message context.
enum AISystemPromptLayout {
    /// Separates the stable system-prompt prefix from per-message context (see AgentService.buildSystemPrompt).
    /// An HTML comment, so providers that receive the prompt verbatim simply ignore it.
    static let dynamicBoundary = "\n\n<!-- microcode:dynamic-context -->"

    /// Anthropic `system` blocks: the cache breakpoint goes on the stable prefix only, so changing memory /
    /// editor / skills context no longer invalidates the cached tools + core instructions. Same number of
    /// cache breakpoints as before (it replaces the old whole-system breakpoint).
    static func anthropicSystemBlocks(_ systemPrompt: String) -> [[String: Any]] {
        guard let boundary = systemPrompt.range(of: dynamicBoundary) else {
            return [["type": "text", "text": systemPrompt, "cache_control": ["type": "ephemeral"]]]
        }
        let stablePrefix = String(systemPrompt[..<boundary.lowerBound])
        let dynamicContext = String(systemPrompt[boundary.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        var blocks: [[String: Any]] = [["type": "text", "text": stablePrefix, "cache_control": ["type": "ephemeral"]]]
        if !dynamicContext.isEmpty {
            blocks.append(["type": "text", "text": dynamicContext])
        }
        return blocks
    }
}
