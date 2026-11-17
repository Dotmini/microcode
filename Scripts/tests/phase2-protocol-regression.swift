import Foundation

// Phase 2 protocol regression (MCP 2025-11-25 / 2026-07-28 rules and ACP host behaviour).
// Compiled with the real MCPProtocolSupport.swift and ACPProtocol.swift by `run-phase2-protocol.sh`.

@main struct Phase2ProtocolRegression {
    static func main() throws {
        try requestIds()
        versions()
        messages()
        toolList()
        httpFraming()
        acpDetection()
        print("PHASE2 PROTOCOL REGRESSION: PASS")
    }

    static func requestIds() throws {
        struct Envelope: Codable { let id: MCPRequestID? }
        let decoder = JSONDecoder()
        func id(_ json: String) throws -> MCPRequestID? { try decoder.decode(Envelope.self, from: Data(json.utf8)).id }
        let intId = try id(#"{"id": 7}"#)
        let stringId = try id(#"{"id": "req-1"}"#)
        let floatId = try id(#"{"id": 3.0}"#)
        let missingId = try id(#"{}"#)
        precondition(intId == .int(7))
        precondition(stringId == .string("req-1"))
        precondition(floatId == .int(3))
        precondition(missingId == nil)
        let encoded = String(decoding: try JSONEncoder().encode(Envelope(id: .string("a"))), as: UTF8.self)
        precondition(encoded.contains(#""id":"a""#), "string ids must round-trip as strings: \(encoded)")
    }

    static func versions() {
        precondition(MCPProtocolSupport.negotiateHandshakeVersion("2025-11-25") == "2025-11-25")
        precondition(MCPProtocolSupport.negotiateHandshakeVersion("2024-11-05") == "2024-11-05")
        precondition(MCPProtocolSupport.negotiateHandshakeVersion("2099-01-01") == MCPProtocolSupport.latestHandshakeVersion)
        precondition(MCPProtocolSupport.negotiateHandshakeVersion(nil) == MCPProtocolSupport.latestHandshakeVersion)
        // 2026-07-28 has no initialize handshake; an initialize call gets the newest handshake revision.
        precondition(MCPProtocolSupport.negotiateHandshakeVersion("2026-07-28") == MCPProtocolSupport.latestHandshakeVersion)

        let discover = MCPProtocolSupport.discoverResult
        precondition((discover["supportedVersions"] as? [String])?.first == "2026-07-28")
        let caps = MCPProtocolSupport.serverCapabilities
        precondition(caps["logging"] == nil, "logging is not implemented, so it must not be advertised")
        precondition(((caps["tools"] as? [String: Any])?["listChanged"] as? Bool) == false)
    }

    static func messages() {
        precondition(MCPProtocolSupport.isNotification(["jsonrpc": "2.0", "method": "notifications/initialized"]))
        precondition(!MCPProtocolSupport.isNotification(["jsonrpc": "2.0", "id": 1, "method": "ping"]))
        precondition(!MCPProtocolSupport.isNotification(["jsonrpc": "2.0", "id": 1, "result": [:] as [String: Any]]))

        let params: [String: Any] = ["_meta": ["io.modelcontextprotocol/protocolVersion": "2026-07-28"]]
        precondition(MCPProtocolSupport.declaredProtocolVersion(params: params) == "2026-07-28")
        precondition(MCPProtocolSupport.declaredProtocolVersion(params: [:]) == nil)

        let stateless = MCPProtocolSupport.decorateResult(["tools": []], protocolVersion: "2026-07-28")
        precondition(stateless["resultType"] as? String == "complete")
        precondition(((stateless["_meta"] as? [String: Any])?["io.modelcontextprotocol/serverInfo"]) != nil)
        let legacy = MCPProtocolSupport.decorateResult(["tools": []], protocolVersion: "2025-11-25")
        precondition(legacy["resultType"] == nil, "older revisions keep the original result shape")
    }

    static func toolList() {
        let tools: [[String: Any]] = [
            ["name": "write_file", "description": "w", "inputSchema": ["type": "object"]],
            ["name": "read_file", "description": "r", "inputSchema": ["type": "object"]],
            ["name": "computer_use", "description": "c", "inputSchema": ["type": "object"]]
        ]
        let final = MCPProtocolSupport.finalizeToolList(tools)
        precondition(final.compactMap { $0["name"] as? String } == ["computer_use", "read_file", "write_file"], "deterministic order")
        let read = final.first { $0["name"] as? String == "read_file" }?["annotations"] as? [String: Any]
        precondition(read?["readOnlyHint"] as? Bool == true && read?["destructiveHint"] == nil)
        let write = final.first { $0["name"] as? String == "write_file" }?["annotations"] as? [String: Any]
        precondition(write?["readOnlyHint"] as? Bool == false && write?["destructiveHint"] as? Bool == true)
        let cu = final.first { $0["name"] as? String == "computer_use" }?["annotations"] as? [String: Any]
        precondition(cu?["openWorldHint"] as? Bool == true)
    }

    static func httpFraming() {
        let body = String(repeating: "x", count: 200_000) // larger than one 64 KB socket read
        let head = "POST /v1/mcp HTTP/1.1\r\nHost: 127.0.0.1:18888\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
        let full = Data((head + body).utf8)
        precondition(MCPProtocolSupport.expectedHTTPRequestLength(Data("POST /v1/mcp HTTP/1.1\r\nHost: x".utf8)) == nil)
        precondition(MCPProtocolSupport.expectedHTTPRequestLength(full.prefix(65_536)) == full.count,
                     "a partial read must report the full expected length so the bridge keeps reading")
        let noBody = Data("GET /v1/health HTTP/1.1\r\nHost: x\r\n\r\n".utf8)
        precondition(MCPProtocolSupport.expectedHTTPRequestLength(noBody) == noBody.count)
    }

    static func acpDetection() {
        precondition(ACPAgentDetection.isACP(command: "/usr/local/bin/npx", arguments: ["-y", "@zed-industries/claude-code-acp@0.10.2"]))
        precondition(ACPAgentDetection.isACP(command: "npx", arguments: ["@zed-industries/codex-acp"]))
        precondition(ACPAgentDetection.isACP(command: "/opt/homebrew/bin/claude-agent-acp", arguments: []))
        precondition(ACPAgentDetection.isACP(command: "gemini", arguments: ["--experimental-acp"]))
        precondition(ACPAgentDetection.isACP(command: "goose", arguments: ["acp"]))
        precondition(!ACPAgentDetection.isACP(command: "claude", arguments: ["-p", "--output-format", "stream-json"]))
        precondition(!ACPAgentDetection.isACP(command: "codex", arguments: ["exec", "--json"]))
        precondition(!ACPAgentDetection.isACP(command: "acpi-tool", arguments: []))

        precondition(ACPStreamEvent.error("x").endsACPTurn)
        precondition(!ACPStreamEvent.text("x").endsACPTurn)
    }
}
