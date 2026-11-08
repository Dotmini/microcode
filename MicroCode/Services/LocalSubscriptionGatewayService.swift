//
//  LocalSubscriptionGatewayService.swift
//  MicroCode
//
//  Built-in Sovereign 3-Tier Smart Proxy (127.0.0.1:20128)
//  Exposes MicroCode's Unified 22-Provider Subscription Pool & CLI Bridges
//  as both an OpenAI-compatible (`/v1/chat/completions`, `/v1/models`) and
//  Anthropic-compatible (`/v1/messages`) local gateway for Claude Code, Codex,
//  OpenCode, Aider, Cline, Goose, Cursor, and local scripts — zero external install required.
//

import Foundation
import Network
import Combine

@MainActor
public final class LocalSubscriptionGatewayService: ObservableObject {
    public static let shared = LocalSubscriptionGatewayService()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var externalGatewayDetected: Bool = false
    @Published public private(set) var modeDescription: String = "Standby"
    @Published public private(set) var routedRequestCount: Int = 0
    @Published public private(set) var lastRoutedBadge: String = ""

    private var listener: NWListener?
    private let port: UInt16 = 20128
    private let listenerQueue = DispatchQueue(label: "com.dotmini.microcode.subscription-gateway", qos: .userInitiated)
    private var isStarting: Bool = false

    private init() {}

    public func startIfNeeded() {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        Task {
            let hasExternal = await Self.probeExistingGateway(port: self.port)
            if hasExternal {
                self.externalGatewayDetected = true
                self.isRunning = true
                self.isStarting = false
                self.modeDescription = "External 9Router Active (127.0.0.1:\(self.port))"
                return
            }
            self.startEmbeddedListener()
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        isStarting = false
        externalGatewayDetected = false
        modeDescription = "Stopped"
    }

    private static func probeExistingGateway(port: UInt16) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/models") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 0.35)
        req.httpMethod = "GET"
        if let (_, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse,
           (200...499).contains(http.statusCode) {
            return true
        }
        return false
    }

    private func startEmbeddedListener() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: NWEndpoint.Port(rawValue: port)!
            )
            let nwListener = try NWListener(using: params)
            nwListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.isStarting = false
                        self.externalGatewayDetected = false
                        self.modeDescription = "Built-in Subscription Pool Active (127.0.0.1:\(self.port))"
                    case .failed:
                        self.listener?.cancel()
                        self.listener = nil
                        self.isRunning = false
                        self.isStarting = false
                        self.modeDescription = "Port \(self.port) unavailable"
                    case .cancelled:
                        self.isRunning = false
                        self.isStarting = false
                    default:
                        break
                    }
                }
            }
            nwListener.newConnectionHandler = { [weak self] connection in
                self?.acceptConnection(connection)
            }
            self.listener = nwListener
            nwListener.start(queue: listenerQueue)
        } catch {
            isStarting = false
            isRunning = false
            modeDescription = "Gateway init failed: \(error.localizedDescription)"
        }
    }

    // MARK: - HTTP Connection Handling

    private nonisolated func acceptConnection(_ connection: NWConnection) {
        connection.start(queue: listenerQueue)
        receiveFullHTTPRequest(on: connection, accumulated: Data())
    }

    private nonisolated func receiveFullHTTPRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }
            var buffer = accumulated
            if let content, !content.isEmpty {
                buffer.append(content)
            }
            if buffer.count > 8_000_000 {
                self.sendJSONResponse(on: connection, status: "413 Payload Too Large", payload: ["error": ["message": "Request body exceeds 8MB limit"]])
                return
            }
            if let parsed = Self.parseHTTPRequest(buffer) {
                Task {
                    await self.dispatchHTTPRequest(parsed, on: connection)
                }
                return
            }
            if isComplete {
                connection.cancel()
                return
            }
            self.receiveFullHTTPRequest(on: connection, accumulated: buffer)
        }
    }

    private struct ParsedHTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private nonisolated static func parseHTTPRequest(_ data: Data) -> ParsedHTTPRequest? {
        let delimiter = Data([13, 10, 13, 10]) // \r\n\r\n
        guard let range = data.range(of: delimiter) else { return nil }
        let headerData = data.subdata(in: 0..<range.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0]).uppercased()
        let rawPath = String(parts[1])
        let path = rawPath.split(separator: "?").first.map(String.init) ?? rawPath

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }
        let expectedLen = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = range.upperBound
        let availableBody = data.count - bodyStart
        if availableBody < expectedLen {
            return nil // Wait for remaining body bytes
        }
        let body = expectedLen > 0
            ? data.subdata(in: bodyStart..<(bodyStart + expectedLen))
            : data.subdata(in: bodyStart..<data.count)
        return ParsedHTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    // MARK: - Route Dispatcher

    private func dispatchHTTPRequest(_ req: ParsedHTTPRequest, on connection: NWConnection) async {
        if req.method == "OPTIONS" {
            sendRawHTTP(
                on: connection,
                status: "204 No Content",
                contentType: "text/plain",
                body: Data(),
                closeAfter: true
            )
            return
        }

        switch (req.method, req.path) {
        case ("GET", "/health"), ("GET", "/v1/health"):
            let connected = SubscriptionAuthManager.shared.connectedProviders().map(\.rawValue)
            sendJSONResponse(on: connection, status: "200 OK", payload: [
                "status": "ok",
                "gateway": "MicroCode Sovereign Subscription Router",
                "connected_subscriptions": connected,
                "routed_requests": routedRequestCount
            ])

        case ("GET", "/v1/models"), ("GET", "/models"):
            let subModels = SubscriptionAuthManager.shared.connectedModelInfos()
            var seen = Set<String>()
            var items: [[String: Any]] = []
            for m in subModels where seen.insert(m.modelID).inserted {
                items.append([
                    "id": m.modelID,
                    "object": "model",
                    "created": 1_740_000_000,
                    "owned_by": m.provider.rawValue
                ])
            }
            for alias in ["claude-sonnet-4-6", "claude-opus-4-6", "gpt-5.4", "gemini-2.5-pro", "deepseek-chat"] where seen.insert(alias).inserted {
                items.append([
                    "id": alias,
                    "object": "model",
                    "created": 1_740_000_000,
                    "owned_by": "microcode-pool"
                ])
            }
            sendJSONResponse(on: connection, status: "200 OK", payload: [
                "object": "list",
                "data": items
            ])

        case ("POST", "/v1/chat/completions"), ("POST", "/chat/completions"):
            await handleOpenAIChatCompletions(body: req.body, on: connection)

        case ("POST", "/v1/messages"), ("POST", "/messages"):
            await handleAnthropicMessages(body: req.body, on: connection)

        default:
            sendJSONResponse(on: connection, status: "404 Not Found", payload: [
                "error": ["message": "Endpoint \(req.path) not found on MicroCode Local Gateway", "type": "invalid_request_error"]
            ])
        }
    }

    // MARK: - 3-Tier Smart Pool Execution

    private func executeOnUnifiedPool(
        requestedModel: String,
        messages: [[(String, Any)]],
        systemPrompt: String?,
        tools: [[String: Any]]?
    ) async throws -> (text: String, toolCalls: [AIToolCall], badge: String) {
        routedRequestCount += 1

        struct PoolRoute {
            let provider: StreamableAIProvider
            let model: String
            let apiKey: String
            let keyMode: String
            let label: String
        }

        var routes: [PoolRoute] = []
        let detectedProv = StreamableAIProvider.detect(from: requestedModel)

        // Tier 1: Exact matching healthy Subscription or CLI Bridge
        if let subType = AIClient.mapToSubscriptionProvider(detectedProv),
           SubscriptionAuthManager.shared.hasHealthyRoute(subType) {
            let tok = SubscriptionAuthManager.shared.token(for: subType) ?? "cli_bridge"
            routes.append(PoolRoute(provider: detectedProv, model: requestedModel, apiKey: tok, keyMode: "subscription", label: "\(subType.shortLabel) • \(requestedModel)"))
        }

        // Tier 2: Multi-Vendor Subscription Pool Failover (AiPass, Copilot, TokenMe, Claude, ChatGPT, Gemini, Cerebras, Groq, OpenRouter)
        var triedSet = Set<String>()
        for _ in 0..<6 {
            if let cand = AgentService.shared.resolveFailoverCandidate(
                currentProvider: detectedProv,
                currentModel: requestedModel,
                triedModels: triedSet
            ) {
                let sig = "\(cand.provider.rawValue)/\(cand.model)"
                triedSet.insert(sig)
                routes.append(PoolRoute(provider: cand.provider, model: cand.model, apiKey: cand.apiKey, keyMode: "subscription", label: cand.label))
            } else {
                break
            }
        }

        // Tier 3: Direct BYOK fallback
        let byokKey = AIModelCatalog.resolveKey(detectedProv.rawValue)
        if !byokKey.isEmpty {
            routes.append(PoolRoute(provider: detectedProv, model: requestedModel, apiKey: byokKey, keyMode: "direct", label: "BYOK • \(detectedProv.rawValue)"))
        }

        var lastError: Error?
        for route in routes {
            do {
                let res = try await AIClient.shared.sendSync(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    provider: route.provider,
                    model: route.model,
                    apiKey: route.apiKey,
                    tools: tools,
                    keyModeOverride: route.keyMode
                )
                let cleanedText = AIStructuredTurnCodec.stripThoughtTags(res.text)
                self.lastRoutedBadge = route.label
                return (cleanedText, res.toolCalls, route.label)
            } catch let err as NSError {
                lastError = err
                if err.code == 429 || err.code == 529,
                   let subType = AIClient.mapToSubscriptionProvider(route.provider) {
                    SubscriptionAuthManager.shared.markRateLimited(provider: subType, tokenOrAccountId: route.apiKey)
                }
                continue
            }
        }

        throw lastError ?? NSError(
            domain: "LocalSubscriptionGateway",
            code: 503,
            userInfo: [NSLocalizedDescriptionKey: "No active Subscription or BYOK route available in MicroCode Pool. Connect an account in Settings → AI Provider → Subscription."]
        )
    }

    // MARK: - OpenAI `/v1/chat/completions` Handler

    private func handleOpenAIChatCompletions(body: Data, on connection: NWConnection) async {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            sendJSONResponse(on: connection, status: "400 Bad Request", payload: ["error": ["message": "Invalid JSON payload"]])
            return
        }
        let requestedModel = (json["model"] as? String) ?? "claude-sonnet-4-6"
        let isStream = (json["stream"] as? Bool) ?? false
        let rawMessages = (json["messages"] as? [[String: Any]]) ?? []
        let tools = json["tools"] as? [[String: Any]]

        var sysParts: [String] = []
        var convertedMessages: [[(String, Any)]] = []
        for m in rawMessages {
            let role = (m["role"] as? String ?? "user").lowercased()
            let text = Self.extractTextContent(from: m["content"])
            if role == "system" || role == "developer" {
                if !text.isEmpty { sysParts.append(text) }
            } else if role == "tool" {
                let toolId = (m["tool_call_id"] as? String) ?? "tool"
                convertedMessages.append([("_role", "user"), ("text", "[Tool Result \(toolId)]:\n\(text)")])
            } else {
                convertedMessages.append([("_role", role), ("text", text)])
            }
        }
        if convertedMessages.isEmpty {
            convertedMessages.append([("_role", "user"), ("text", "Hello")])
        }
        let systemPrompt = sysParts.isEmpty ? nil : sysParts.joined(separator: "\n\n")

        do {
            let out = try await executeOnUnifiedPool(
                requestedModel: requestedModel,
                messages: convertedMessages,
                systemPrompt: systemPrompt,
                tools: tools
            )
            let completionId = "chatcmpl_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
            let created = Int(Date().timeIntervalSince1970)

            let formattedToolCalls: [[String: Any]] = out.toolCalls.enumerated().map { idx, tc in
                let argsData = (try? JSONSerialization.data(withJSONObject: tc.arguments)) ?? Data("{}".utf8)
                let argsStr = String(data: argsData, encoding: .utf8) ?? "{}"
                return [
                    "index": idx,
                    "id": tc.id,
                    "type": "function",
                    "function": [
                        "name": tc.name,
                        "arguments": argsStr
                    ]
                ]
            }

            if isStream {
                var sse = ""
                if !out.text.isEmpty {
                    let chunkObj: [String: Any] = [
                        "id": completionId,
                        "object": "chat.completion.chunk",
                        "created": created,
                        "model": requestedModel,
                        "choices": [[
                            "index": 0,
                            "delta": ["role": "assistant", "content": out.text],
                            "finish_reason": NSNull()
                        ]]
                    ]
                    if let d = try? JSONSerialization.data(withJSONObject: chunkObj),
                       let s = String(data: d, encoding: .utf8) {
                        sse += "data: \(s)\n\n"
                    }
                }
                if !formattedToolCalls.isEmpty {
                    let tcChunk: [String: Any] = [
                        "id": completionId,
                        "object": "chat.completion.chunk",
                        "created": created,
                        "model": requestedModel,
                        "choices": [[
                            "index": 0,
                            "delta": ["tool_calls": formattedToolCalls],
                            "finish_reason": NSNull()
                        ]]
                    ]
                    if let d = try? JSONSerialization.data(withJSONObject: tcChunk),
                       let s = String(data: d, encoding: .utf8) {
                        sse += "data: \(s)\n\n"
                    }
                }
                let stopObj: [String: Any] = [
                    "id": completionId,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": requestedModel,
                    "choices": [[
                        "index": 0,
                        "delta": [:] as [String: Any],
                        "finish_reason": formattedToolCalls.isEmpty ? "stop" : "tool_calls"
                    ]]
                ]
                if let d = try? JSONSerialization.data(withJSONObject: stopObj),
                   let s = String(data: d, encoding: .utf8) {
                    sse += "data: \(s)\n\n"
                }
                sse += "data: [DONE]\n\n"
                sendRawHTTP(on: connection, status: "200 OK", contentType: "text/event-stream; charset=utf-8", body: Data(sse.utf8), closeAfter: true)
            } else {
                var msgDict: [String: Any] = [
                    "role": "assistant",
                    "content": out.text
                ]
                if !formattedToolCalls.isEmpty {
                    msgDict["tool_calls"] = formattedToolCalls
                }
                sendJSONResponse(on: connection, status: "200 OK", payload: [
                    "id": completionId,
                    "object": "chat.completion",
                    "created": created,
                    "model": requestedModel,
                    "choices": [[
                        "index": 0,
                        "message": msgDict,
                        "finish_reason": formattedToolCalls.isEmpty ? "stop" : "tool_calls"
                    ]],
                    "usage": [
                        "prompt_tokens": 128,
                        "completion_tokens": max(1, out.text.count / 4),
                        "total_tokens": 128 + max(1, out.text.count / 4)
                    ]
                ])
            }
        } catch {
            sendJSONResponse(on: connection, status: "502 Bad Gateway", payload: [
                "error": ["message": error.localizedDescription, "type": "upstream_error"]
            ])
        }
    }

    // MARK: - Anthropic `/v1/messages` Handler (Powers Claude Code, Aider, Cline, OpenCode)

    private func handleAnthropicMessages(body: Data, on connection: NWConnection) async {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            sendJSONResponse(on: connection, status: "400 Bad Request", payload: ["type": "error", "error": ["type": "invalid_request_error", "message": "Invalid JSON"]])
            return
        }
        let requestedModel = (json["model"] as? String) ?? "claude-sonnet-4-6"
        let isStream = (json["stream"] as? Bool) ?? false
        let systemPromptText = Self.extractTextContent(from: json["system"])
        let rawMessages = (json["messages"] as? [[String: Any]]) ?? []

        // Convert Anthropic tools (`input_schema`) to OpenAI/MicroCode schema (`parameters`)
        var convertedTools: [[String: Any]]? = nil
        if let anthTools = json["tools"] as? [[String: Any]], !anthTools.isEmpty {
            convertedTools = anthTools.compactMap { t in
                guard let name = t["name"] as? String else { return nil }
                return [
                    "name": name,
                    "description": (t["description"] as? String) ?? "",
                    "parameters": (t["input_schema"] as? [String: Any]) ?? ["type": "object", "properties": [:] as [String: Any]]
                ]
            }
        }

        var convertedMessages: [[(String, Any)]] = []
        for m in rawMessages {
            let role = (m["role"] as? String ?? "user").lowercased()
            let text = Self.extractTextContent(from: m["content"])
            convertedMessages.append([("_role", role), ("text", text)])
        }
        if convertedMessages.isEmpty {
            convertedMessages.append([("_role", "user"), ("text", "Hello")])
        }

        do {
            let out = try await executeOnUnifiedPool(
                requestedModel: requestedModel,
                messages: convertedMessages,
                systemPrompt: systemPromptText.isEmpty ? nil : systemPromptText,
                tools: convertedTools
            )
            let msgId = "msg_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
            var contentBlocks: [[String: Any]] = []
            if !out.text.isEmpty || out.toolCalls.isEmpty {
                contentBlocks.append(["type": "text", "text": out.text])
            }
            for tc in out.toolCalls {
                contentBlocks.append([
                    "type": "tool_use",
                    "id": tc.id,
                    "name": tc.name,
                    "input": tc.arguments
                ])
            }
            let stopReason = out.toolCalls.isEmpty ? "end_turn" : "tool_use"

            if isStream {
                var sse = ""
                func emitEvent(_ name: String, _ obj: [String: Any]) {
                    if let d = try? JSONSerialization.data(withJSONObject: obj),
                       let s = String(data: d, encoding: .utf8) {
                        sse += "event: \(name)\ndata: \(s)\n\n"
                    }
                }
                emitEvent("message_start", [
                    "type": "message_start",
                    "message": [
                        "id": msgId,
                        "type": "message",
                        "role": "assistant",
                        "model": requestedModel,
                        "content": [] as [[String: Any]],
                        "stop_reason": NSNull(),
                        "usage": ["input_tokens": 128, "output_tokens": 1]
                    ]
                ])
                for (idx, block) in contentBlocks.enumerated() {
                    let bType = block["type"] as? String ?? "text"
                    if bType == "text" {
                        emitEvent("content_block_start", ["type": "content_block_start", "index": idx, "content_block": ["type": "text", "text": ""]])
                        emitEvent("content_block_delta", ["type": "content_block_delta", "index": idx, "delta": ["type": "text_delta", "text": block["text"] as? String ?? ""]])
                        emitEvent("content_block_stop", ["type": "content_block_stop", "index": idx])
                    } else if bType == "tool_use" {
                        let inputObj = (block["input"] as? [String: Any]) ?? [:]
                        let inputStr = (try? JSONSerialization.data(withJSONObject: inputObj)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                        emitEvent("content_block_start", [
                            "type": "content_block_start",
                            "index": idx,
                            "content_block": [
                                "type": "tool_use",
                                "id": block["id"] as? String ?? "toolu_1",
                                "name": block["name"] as? String ?? "tool",
                                "input": [:] as [String: Any]
                            ]
                        ])
                        emitEvent("content_block_delta", [
                            "type": "content_block_delta",
                            "index": idx,
                            "delta": ["type": "input_json_delta", "partial_json": inputStr]
                        ])
                        emitEvent("content_block_stop", ["type": "content_block_stop", "index": idx])
                    }
                }
                emitEvent("message_delta", [
                    "type": "message_delta",
                    "delta": ["stop_reason": stopReason, "stop_sequence": NSNull()],
                    "usage": ["output_tokens": max(1, out.text.count / 4)]
                ])
                emitEvent("message_stop", ["type": "message_stop"])
                sendRawHTTP(on: connection, status: "200 OK", contentType: "text/event-stream; charset=utf-8", body: Data(sse.utf8), closeAfter: true)
            } else {
                sendJSONResponse(on: connection, status: "200 OK", payload: [
                    "id": msgId,
                    "type": "message",
                    "role": "assistant",
                    "model": requestedModel,
                    "content": contentBlocks,
                    "stop_reason": stopReason,
                    "stop_sequence": NSNull(),
                    "usage": [
                        "input_tokens": 128,
                        "output_tokens": max(1, out.text.count / 4)
                    ]
                ])
            }
        } catch {
            sendJSONResponse(on: connection, status: "502 Bad Gateway", payload: [
                "type": "error",
                "error": ["type": "api_error", "message": error.localizedDescription]
            ])
        }
    }

    // MARK: - Content & Wire Helpers

    private nonisolated static func extractTextContent(from raw: Any?) -> String {
        if let str = raw as? String {
            return str
        }
        if let arr = raw as? [[String: Any]] {
            var parts: [String] = []
            for block in arr {
                let bType = (block["type"] as? String) ?? ""
                if let t = block["text"] as? String {
                    parts.append(t)
                } else if bType == "tool_result" {
                    let tid = (block["tool_use_id"] as? String) ?? "tool"
                    let inner = extractTextContent(from: block["content"])
                    parts.append("[Tool Result \(tid)]:\n\(inner)")
                } else if bType == "tool_use" {
                    let name = (block["name"] as? String) ?? "tool"
                    parts.append("[Called tool: \(name)]")
                }
            }
            return parts.joined(separator: "\n")
        }
        return ""
    }

    private nonisolated func sendJSONResponse(on connection: NWConnection, status: String, payload: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        sendRawHTTP(on: connection, status: status, contentType: "application/json; charset=utf-8", body: body, closeAfter: true)
    }

    private nonisolated func sendRawHTTP(
        on connection: NWConnection,
        status: String,
        contentType: String,
        body: Data,
        closeAfter: Bool
    ) {
        let header = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Headers: Authorization, Content-Type, x-api-key, anthropic-version",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var packet = Data(header.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { _ in
            if closeAfter {
                connection.cancel()
            }
        })
    }
}
