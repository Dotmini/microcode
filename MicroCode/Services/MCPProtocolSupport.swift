import Foundation

// Protocol-level rules for MicroCode's MCP server, kept dependency-free so they can be
// regression-tested outside the app target (Scripts/tests/run-phase2-protocol.sh).
//
// Spec references: MCP 2025-11-25 (initialize handshake) and 2026-07-28 (stateless: protocol version
// and client capabilities travel in each request's `_meta`, `server/discover`, required `resultType`).

/// JSON-RPC request id: the spec allows strings and integers (numbers), never only Int.
enum MCPRequestID: Codable, Equatable, Hashable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self), doubleValue.rounded() == doubleValue,
                  abs(doubleValue) < 9.0e15 {
            self = .int(Int(doubleValue))
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

enum MCPProtocolSupport {
    /// Newest first. 2026-07-28 is stateless (no initialize); older revisions use the handshake.
    static let statelessVersion = "2026-07-28"
    static let latestHandshakeVersion = "2025-11-25"
    static let supportedVersions = [statelessVersion, latestHandshakeVersion, "2025-06-18", "2025-03-26", "2024-11-05"]

    static let metaProtocolVersionKey = "io.modelcontextprotocol/protocolVersion"
    static let metaServerInfoKey = "io.modelcontextprotocol/serverInfo"
    /// Error code allocated by 2026-07-28 (renumbered from the draft's -32004).
    static let unsupportedProtocolVersionCode = -32022

    static let serverName = "MicroCode MCP"
    static let serverVersion = "3.1.0"

    /// initialize: echo a supported requested version, otherwise offer our latest handshake version.
    static func negotiateHandshakeVersion(_ requested: String?) -> String {
        guard let requested, supportedVersions.contains(requested), requested != statelessVersion else {
            return latestHandshakeVersion
        }
        return requested
    }

    /// Capabilities we actually implement (no list_changed notifications or logging/setLevel are emitted).
    static var serverCapabilities: [String: Any] {
        [
            "tools": ["listChanged": false],
            "resources": ["subscribe": false, "listChanged": false],
            "prompts": ["listChanged": false]
        ]
    }

    static var serverInfo: [String: Any] {
        ["name": serverName, "version": serverVersion]
    }

    /// `server/discover` (required by 2026-07-28; harmless for older clients).
    static var discoverResult: [String: Any] {
        [
            "supportedVersions": supportedVersions,
            "capabilities": serverCapabilities,
            "serverInfo": serverInfo
        ]
    }

    /// A JSON-RPC message with a `method` and no `id` member is a notification and must never be answered.
    static func isNotification(_ json: [String: Any]) -> Bool {
        json["method"] is String && json["id"] == nil
    }

    /// Protocol version a stateless (2026-07-28) request declares in `params._meta`, if any.
    static func declaredProtocolVersion(params: [String: Any]?) -> String? {
        (params?["_meta"] as? [String: Any])?[metaProtocolVersionKey] as? String
    }

    /// Stateless results carry `resultType` and identify the server in `_meta`.
    static func decorateResult(_ result: [String: Any], protocolVersion: String?) -> [String: Any] {
        guard protocolVersion == statelessVersion else { return result }
        var decorated = result
        decorated["resultType"] = "complete"
        var meta = decorated["_meta"] as? [String: Any] ?? [:]
        meta[metaServerInfoKey] = serverInfo
        decorated["_meta"] = meta
        return decorated
    }

    // MARK: - Tool annotations

    private static let readOnlyTools: Set<String> = [
        "read_file", "search_files", "list_files", "git_status", "get_diagnostics", "lsp_intelligence",
        "grep_search", "list_directory_tree", "find_symbol", "multi_file_read", "openthai_ocr"
    ]
    private static let destructiveTools: Set<String> = [
        "write_file", "edit_file", "run_terminal", "execute_code", "microcode_run_playground", "microcode_run_cell",
        "computer_use", "agent_desktop", "device_runtime", "database_studio", "replace_in_file", "patch_file",
        "microcode_swarm_dispatch", "microcode_sync_account"
    ]
    private static let openWorldTools: Set<String> = [
        "computer_use", "agent_desktop", "ide_browser", "api_studio", "device_runtime", "microcode_swarm_dispatch"
    ]

    /// MCP tool annotations (hints for clients deciding what needs user confirmation).
    static func annotations(forTool name: String) -> [String: Any] {
        let readOnly = readOnlyTools.contains(name)
        var hints: [String: Any] = [
            "readOnlyHint": readOnly,
            "openWorldHint": openWorldTools.contains(name)
        ]
        if !readOnly {
            hints["destructiveHint"] = destructiveTools.contains(name)
            hints["idempotentHint"] = false
        }
        return hints
    }

    /// Adds annotations and a deterministic order (stable lists improve client and prompt-cache hit rates).
    static func finalizeToolList(_ tools: [[String: Any]]) -> [[String: Any]] {
        tools
            .map { tool -> [String: Any] in
                var annotated = tool
                if annotated["annotations"] == nil, let name = tool["name"] as? String {
                    annotated["annotations"] = annotations(forTool: name)
                }
                return annotated
            }
            .sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
    }

    // MARK: - HTTP framing

    /// Total bytes (headers + body) the request needs, once the header block is complete; nil until then.
    /// Lets the loopback bridge keep reading instead of truncating bodies larger than one TCP read.
    static func expectedHTTPRequestLength(_ data: Data) -> Int? {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else { return nil }
        let headerText = String(decoding: data[..<range.lowerBound], as: UTF8.self)
        var contentLength = 0
        for line in headerText.components(separatedBy: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return range.upperBound + max(0, contentLength)
    }
}
