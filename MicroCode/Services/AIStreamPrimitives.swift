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

/// Assembles OpenAI-style streamed `tool_calls` deltas into whole calls.
///
/// Providers differ: OpenAI sends `index` on every delta and `id` only on the first; some gateways omit `index`
/// or reuse index 0 for parallel calls while giving each call its own `id`; others repeat `id` on every delta.
/// Keying by `index` alone merged parallel calls into one call carrying the last call's name and both argument
/// strings (`{"path":…}{"query":…,"action":"read"}`), so it failed and neither call ran. Here a new provider id
/// always starts a new call, and a delta with neither id nor index continues the latest call.
struct StreamedToolCallAccumulator {
    struct Call: Equatable {
        var id: String
        var name: String
        var arguments: String
    }

    private var calls: [Call] = []
    private var hasProviderId: [Bool] = []
    private var positionByIndex: [Int: Int] = [:]
    private var positionById: [String: Int] = [:]
    private var lastPosition: Int?
    private let makeId: () -> String

    init(makeId: @escaping () -> String = { UUID().uuidString }) {
        self.makeId = makeId
    }

    var isEmpty: Bool { calls.isEmpty }

    mutating func add(delta: [String: Any]) {
        let index = delta["index"] as? Int
        let providerId = (delta["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let function = delta["function"] as? [String: Any]
        let name = (function?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let chunk = function?["arguments"] as? String ?? ""

        var position: Int?
        if let providerId {
            if let known = positionById[providerId] {
                position = known
            } else if let index, let open = positionByIndex[index], !hasProviderId[open] {
                // The call already open at this index receives its real id late.
                position = open
                calls[open].id = providerId
                hasProviderId[open] = true
                positionById[providerId] = open
            }
            // Otherwise an unseen id starts a new call, even when the provider reused the same index.
        } else if let index, let open = positionByIndex[index] {
            position = open
        } else if index == nil, let last = lastPosition {
            position = last
        }

        // Without an id: a function name arriving after the current call's arguments are complete JSON means the
        // provider started another call without saying so (a repeated name mid-call does not split it).
        if providerId == nil, let current = position, let name, !calls[current].name.isEmpty,
           name != calls[current].name || !chunk.isEmpty,
           Self.isCompleteJSONObject(calls[current].arguments) {
            position = nil
        }

        let target: Int
        if let position {
            target = position
        } else {
            calls.append(Call(id: providerId ?? makeId(), name: "", arguments: ""))
            hasProviderId.append(providerId != nil)
            target = calls.count - 1
            if let providerId { positionById[providerId] = target }
        }
        if let name, calls[target].name.isEmpty {
            calls[target].name = name
        }
        calls[target].arguments += chunk
        if let index { positionByIndex[index] = target }
        lastPosition = target
    }

    /// Completed calls in arrival order (nameless fragments dropped); empties the accumulator.
    mutating func drain() -> [Call] {
        let named = calls.filter { !$0.name.isEmpty }
        calls = []
        hasProviderId = []
        positionByIndex = [:]
        positionById = [:]
        lastPosition = nil
        return named
    }

    static func isCompleteJSONObject(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) is [String: Any]
    }
}

/// Explains tool-call arguments that could not be parsed, so the model gets the right recovery advice.
enum ToolArgumentDiagnosis {
    /// Number of complete top-level JSON objects in `text` (braces inside strings are ignored).
    static func topLevelObjectCount(_ text: String) -> Int {
        var depth = 0
        var count = 0
        var inString = false
        var escaped = false
        for scalar in text.unicodeScalars {
            if inString {
                if escaped {
                    escaped = false
                } else if scalar == "\\" {
                    escaped = true
                } else if scalar == "\"" {
                    inString = false
                }
                continue
            }
            switch scalar {
            case "\"":
                inString = true
            case "{":
                depth += 1
            case "}":
                if depth > 0 {
                    depth -= 1
                    if depth == 0 { count += 1 }
                }
            default:
                break
            }
        }
        return count
    }

    static func invalidArgumentsMessage(toolName: String, raw: String) -> String {
        let preview = String(raw.prefix(120))
        if topLevelObjectCount(raw) >= 2 {
            return "the arguments for `\(toolName)` held several JSON objects back to back (parallel tool calls were merged in the stream), so nothing was executed. Re-issue each call separately with only its own arguments. Received: \(preview)…"
        }
        return "the arguments for `\(toolName)` were not valid JSON (usually cut off by the output token limit), so nothing was executed. Re-issue the call with complete arguments; for large content split it into several smaller calls (e.g. write the file in parts). Received: \(preview)…"
    }
}
