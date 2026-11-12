//
//  AIClient+Enterprise.swift
//  MicroCode
//
//  Unified Enterprise API Execution Drivers:
//  - OpenAI-Compatible Gateways (LiteLLM / Kong / Apigee / Cloudflare AI Gateway / vLLM / VPC)
//  - Azure OpenAI & Microsoft AI Foundry (Deployment URL + Entra ID SSO / api-key)
//  - Google Cloud Vertex AI (Gemini :streamGenerateContent + Claude :streamRawPredict)
//  - Google Gemini Enterprise / Agentspace (Discovery Engine :streamAssist)
//  - AWS Bedrock Runtime Converse API (Bedrock API Key ABSK… + Pure-Swift SigV4 / AWS SSO)
//  - Anthropic Enterprise Gateways (/v1/messages)
//  - Dotmini Sovereign Cloud Enterprise (ZDR)
//

import Foundation

extension AIClient {

    private static var discoveryEngineSessionByChatId: [String: String] = [:]

    func streamEnterpriseProfile(
        profile: EnterpriseAPIProfile,
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        tools: [[String: Any]]?,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        let ent = EnterpriseAIAuthService.shared
        let session = ent.urlSession(for: profile)
        let effectiveModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? profile.defaultModel
            : model.trimmingCharacters(in: .whitespacesAndNewlines)

        switch profile.dialect {
        case .openaiGateway, .dotminiEnterprise:
            let cleanBase = EnterpriseSmartPasteParser.normalizeOpenAIBaseURL(profile.baseURL)
            guard !cleanBase.isEmpty, let endpoint = URL(string: "\(cleanBase)/chat/completions") else {
                throw NSError(domain: "EnterpriseAI", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid Enterprise Gateway Base URL for '\(profile.name)'."
                ])
            }
            var prebuiltReq = URLRequest(url: endpoint)
            try await ent.applyStandardGatewayAuth(profile: profile, to: &prebuiltReq)
            let headerSnapshot = prebuiltReq.allHTTPHeaderFields ?? [:]

            try await streamOpenAI(
                prompt: prompt,
                attachments: attachments,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                model: effectiveModel,
                apiKey: "",
                baseURL: cleanBase,
                tools: tools,
                customEndpointURL: endpoint,
                customSession: session,
                customHeadersHook: { req in
                    for (k, v) in headerSnapshot { req.setValue(v, forHTTPHeaderField: k) }
                },
                onToken: onToken,
                onToolCall: onToolCall
            )

        case .azureOpenAI:
            guard let endpoint = ent.buildAzureChatCompletionsURL(profile: profile, modelOrDeployment: effectiveModel) else {
                throw NSError(domain: "EnterpriseAI", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Azure OpenAI Resource Name and Deployment Name are required for '\(profile.name)'."
                ])
            }
            var prebuiltReq = URLRequest(url: endpoint)
            try await ent.applyStandardGatewayAuth(profile: profile, to: &prebuiltReq)
            let headerSnapshot = prebuiltReq.allHTTPHeaderFields ?? [:]
            let baseHost = endpoint.host.map { "https://\($0)" } ?? "https://openai.azure.com"

            try await streamOpenAI(
                prompt: prompt,
                attachments: attachments,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                model: effectiveModel,
                apiKey: "",
                baseURL: baseHost,
                tools: tools,
                customEndpointURL: endpoint,
                customSession: session,
                customHeadersHook: { req in
                    for (k, v) in headerSnapshot { req.setValue(v, forHTTPHeaderField: k) }
                },
                onToken: onToken,
                onToolCall: onToolCall
            )

        case .anthropicGateway:
            let cleanBase = EnterpriseSmartPasteParser.normalizeAnthropicBaseURL(profile.baseURL)
            guard !cleanBase.isEmpty, let endpoint = URL(string: "\(cleanBase)/messages") else {
                throw NSError(domain: "EnterpriseAI", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid Anthropic Enterprise Base URL for '\(profile.name)'."
                ])
            }
            var prebuiltReq = URLRequest(url: endpoint)
            try await ent.applyStandardGatewayAuth(profile: profile, to: &prebuiltReq)
            let headerSnapshot = prebuiltReq.allHTTPHeaderFields ?? [:]

            try await streamAnthropic(
                prompt: prompt,
                attachments: attachments,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                model: effectiveModel,
                apiKey: "",
                tools: tools,
                customEndpointURL: endpoint,
                customSession: session,
                vertexAnthropicMode: false,
                customHeadersHook: { req in
                    for (k, v) in headerSnapshot { req.setValue(v, forHTTPHeaderField: k) }
                },
                onToken: onToken,
                onToolCall: onToolCall
            )

        case .vertexGemini:
            guard let endpoint = ent.buildVertexEndpointURL(profile: profile, model: effectiveModel, streaming: true) else {
                throw NSError(domain: "EnterpriseAI", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Google Cloud Project ID is required for Vertex AI profile '\(profile.name)'."
                ])
            }
            let bearer = try await ent.resolveGCPBearerToken(for: profile)
            var prebuiltReq = URLRequest(url: endpoint)
            if let bearer { prebuiltReq.setValue(bearer, forHTTPHeaderField: "Authorization") }
            if !profile.gcpProjectId.isEmpty {
                prebuiltReq.setValue(profile.gcpProjectId, forHTTPHeaderField: "x-goog-user-project")
            }
            ent.applyProfileHeaders(profile: profile, to: &prebuiltReq)
            let headerSnapshot = prebuiltReq.allHTTPHeaderFields ?? [:]

            var cleanVertexModel = effectiveModel
            for prefix in ["models/", "publishers/google/models/", "publishers/anthropic/models/"] {
                if cleanVertexModel.hasPrefix(prefix) {
                    cleanVertexModel = String(cleanVertexModel.dropFirst(prefix.count))
                }
            }

            if cleanVertexModel.lowercased().hasPrefix("claude-") {
                try await streamAnthropic(
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: cleanVertexModel,
                    apiKey: "",
                    tools: tools,
                    customEndpointURL: endpoint,
                    customSession: session,
                    vertexAnthropicMode: true,
                    customHeadersHook: { req in
                        for (k, v) in headerSnapshot { req.setValue(v, forHTTPHeaderField: k) }
                    },
                    onToken: onToken,
                    onToolCall: onToolCall
                )
            } else {
                try await streamGemini(
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: cleanVertexModel,
                    apiKey: "",
                    tools: tools,
                    customEndpointURL: endpoint,
                    customSession: session,
                    customHeadersHook: { req in
                        for (k, v) in headerSnapshot { req.setValue(v, forHTTPHeaderField: k) }
                    },
                    onToken: onToken,
                    onToolCall: onToolCall
                )
            }

        case .geminiEnterpriseAgentspace:
            try await streamDiscoveryEngineAgentspace(
                profile: profile,
                session: session,
                prompt: prompt,
                attachments: attachments,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                tools: tools,
                onToken: onToken,
                onToolCall: onToolCall
            )

        case .awsBedrock:
            try await streamAWSBedrockConverse(
                profile: profile,
                session: session,
                prompt: prompt,
                attachments: attachments,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                model: effectiveModel,
                tools: tools,
                onToken: onToken,
                onToolCall: onToolCall
            )
        }
    }

    func syncEnterpriseProfile(
        profile: EnterpriseAPIProfile,
        messages: [[(String, Any)]],
        systemPrompt: String?,
        model: String,
        tools: [[String: Any]]?
    ) async throws -> (text: String, toolCalls: [AIToolCall]) {
        var history: [(role: String, content: String)] = []
        for msg in messages {
            let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
            let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
            if !content.isEmpty { history.append((role: role, content: content)) }
        }
        let prompt = history.popLast()?.content ?? "Continue."
        var fullText = ""
        var calls: [AIToolCall] = []
        pendingStreamTokens = ""

        try await streamEnterpriseProfile(
            profile: profile,
            prompt: prompt,
            attachments: [],
            systemPrompt: systemPrompt,
            conversationHistory: history,
            model: model,
            tools: tools,
            onToken: { fullText += $0 },
            onToolCall: { calls.append($0) }
        )
        flushPendingStreamTokens(onToken: { fullText += $0 })
        return (text: fullText, toolCalls: calls)
    }

    // MARK: - Google Gemini Enterprise / Discovery Engine (:streamAssist)

    private func streamDiscoveryEngineAgentspace(
        profile: EnterpriseAPIProfile,
        session: URLSession,
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        tools: [[String: Any]]?,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        let ent = EnterpriseAIAuthService.shared
        guard let url = ent.buildDiscoveryEngineStreamAssistURL(profile: profile) else {
            throw NSError(domain: "EnterpriseAI", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "GCP Project ID and Discovery Engine App ID are required for Gemini Enterprise Agentspace."
            ])
        }

        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer = try await ent.resolveGCPBearerToken(for: profile) {
            request.setValue(bearer, forHTTPHeaderField: "Authorization")
        }
        if !profile.gcpProjectId.isEmpty {
            request.setValue(profile.gcpProjectId, forHTTPHeaderField: "X-Goog-User-Project")
        }
        ent.applyProfileHeaders(profile: profile, to: &request)

        let chatKey = "\(profile.id)::\(AgentExecutionContext.chatId ?? "default")"
        let existingSession = conversationHistory.isEmpty ? nil : Self.discoveryEngineSessionByChatId[chatKey]

        // Compose query text (incorporating attachments & lightweight tool bridge if tools are active)
        var querySections: [String] = []
        if existingSession == nil, let sys = systemPrompt, !sys.isEmpty {
            querySections.append("[System Context]\n\(String(sys.prefix(4000)))")
        }
        if let tools, !tools.isEmpty {
            let names = tools.compactMap { $0["name"] as? String }.prefix(24).joined(separator: ", ")
            querySections.append("""
            [Tool Calling Protocol]
            If you need to invoke a workspace tool (\(names)), output a fenced JSON block:
            ```tool_call
            {"name": "<tool_name>", "arguments": { ... }}
            ```
            Otherwise respond directly in Markdown.
            """)
        }
        for att in attachments {
            if case .pdf = att.type {
                let txt = att.pdfExtractedText
                if !txt.isEmpty {
                    querySections.append("[Attached PDF: \(att.name)]\n\(String(txt.prefix(16000)))")
                }
            } else if let str = String(data: att.data, encoding: .utf8), !str.isEmpty {
                querySections.append("[Attached File: \(att.name)]\n\(String(str.prefix(16000)))")
            }
        }
        querySections.append(prompt)
        let fullQueryText = querySections.joined(separator: "\n\n")

        let bodyObj: [String: Any] = [
            "query": ["text": fullQueryText],
            "session": existingSession ?? "-"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyObj)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "EnterpriseAI", code: code, userInfo: [
                NSLocalizedDescriptionKey: "Gemini Enterprise Agentspace HTTP \(code): \(String(raw.prefix(320)))"
            ])
        }

        // `streamAssist` returns a JSON array of StreamAssistResponse chunks (or single JSON object)
        let parsedAny = try? JSONSerialization.jsonObject(with: data)
        let chunks: [[String: Any]]
        if let arr = parsedAny as? [[String: Any]] {
            chunks = arr
        } else if let single = parsedAny as? [String: Any] {
            chunks = [single]
        } else {
            chunks = []
        }

        var combinedAnswer = ""
        for chunk in chunks {
            if let sessionInfo = chunk["sessionInfo"] as? [String: Any],
               let sessionName = sessionInfo["session"] as? String,
               !sessionName.isEmpty {
                Self.discoveryEngineSessionByChatId[chatKey] = sessionName
            }
            if let answer = chunk["answer"] as? [String: Any],
               let replies = answer["replies"] as? [[String: Any]] {
                for reply in replies {
                    if let gc = reply["groundedContent"] as? [String: Any],
                       let content = gc["content"] as? [String: Any],
                       let text = content["text"] as? String,
                       (content["thought"] as? Bool) != true {
                        combinedAnswer += text
                    }
                }
            }
        }

        // Extract any ```tool_call blocks if emitted
        let (cleanVisible, extractedCalls) = Self.extractFencedToolCalls(from: combinedAnswer)
        if !cleanVisible.isEmpty {
            appendStreamToken(cleanVisible, onToken: onToken)
        }
        for tc in extractedCalls {
            onToolCall?(tc)
        }
    }

    private static func extractFencedToolCalls(from text: String) -> (String, [AIToolCall]) {
        guard text.contains("```tool_call") else { return (text, []) }
        var calls: [AIToolCall] = []
        let pattern = #"```tool_call\s*([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (text, []) }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.numberOfRanges > 1 {
                let rawJSON = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = rawJSON.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let name = obj["name"] as? String {
                    let args = (obj["arguments"] as? [String: Any]) ?? [:]
                    calls.append(AIToolCall(id: UUID().uuidString, name: name, arguments: args))
                }
            }
        }
        let cleaned = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, calls)
    }

    // MARK: - AWS Bedrock Runtime Converse API (ABSK Bearer Key & Pure-Swift SigV4)

    private func streamAWSBedrockConverse(
        profile: EnterpriseAPIProfile,
        session: URLSession,
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        tools: [[String: Any]]?,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        let ent = EnterpriseAIAuthService.shared
        guard let url = ent.buildBedrockConverseURL(profile: profile, modelId: model) else {
            throw NSError(domain: "EnterpriseAI", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid AWS Region or Bedrock Model ID (\(model))."
            ])
        }

        // Build Bedrock Converse `messages` array (strictly alternating user / assistant roles)
        var bedrockMessages: [[String: Any]] = []
        var activeToolUseIds = Set<String>()

        func appendBedrockBlocks(role: String, blocks: [[String: Any]]) {
            guard !blocks.isEmpty else { return }
            if let last = bedrockMessages.last, (last["role"] as? String) == role,
               var existing = last["content"] as? [[String: Any]] {
                existing.append(contentsOf: blocks)
                bedrockMessages[bedrockMessages.count - 1] = ["role": role, "content": existing]
            } else {
                bedrockMessages.append(["role": role, "content": blocks])
            }
        }

        for turn in conversationHistory {
            let trimmed = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let role = (turn.role == "assistant") ? "assistant" : "user"
            if let structured = AIStructuredTurnCodec.decode(trimmed) {
                switch structured {
                case .assistantToolCalls(let text, let toolCalls):
                    var blocks: [[String: Any]] = []
                    let cleanText = AIStructuredTurnCodec.stripThoughtTags(text)
                    if !cleanText.isEmpty {
                        blocks.append(["text": cleanText])
                    }
                    for tc in toolCalls {
                        blocks.append([
                            "toolUse": [
                                "toolUseId": tc.id,
                                "name": AgentToolBox.normalizeToolName(tc.name),
                                "input": tc.arguments
                            ]
                        ])
                    }
                    appendBedrockBlocks(role: "assistant", blocks: blocks)
                    activeToolUseIds = Set(toolCalls.map(\.id))

                case .toolResults(let results, let directive):
                    var blocks: [[String: Any]] = []
                    for res in results {
                        if activeToolUseIds.contains(res.toolCallId) {
                            blocks.append([
                                "toolResult": [
                                    "toolUseId": res.toolCallId,
                                    "content": [["text": res.output.isEmpty ? "(empty)" : res.output]],
                                    "status": res.success ? "success" : "error"
                                ]
                            ])
                        } else {
                            blocks.append(["text": "[\(res.name)]: \(res.output)"])
                        }
                    }
                    if !directive.isEmpty {
                        blocks.append(["text": directive])
                    }
                    appendBedrockBlocks(role: "user", blocks: blocks)
                    activeToolUseIds.removeAll()
                }
            } else {
                appendBedrockBlocks(role: role, blocks: [["text": trimmed]])
            }
        }

        // Current user turn + attachments
        var currentUserBlocks: [[String: Any]] = []
        for att in attachments {
            switch att.type {
            case .image(let mime):
                let fmt: String = {
                    let l = mime.lowercased()
                    if l.contains("png") { return "png" }
                    if l.contains("webp") { return "webp" }
                    if l.contains("gif") { return "gif" }
                    return "jpeg"
                }()
                if !att.data.isEmpty {
                    currentUserBlocks.append([
                        "image": [
                            "format": fmt,
                            "source": ["bytes": att.data.base64EncodedString()]
                        ]
                    ])
                }
            case .pdf:
                let txt = att.pdfExtractedText
                if !txt.isEmpty {
                    currentUserBlocks.append(["text": "[PDF: \(att.name)]\n\(txt)"])
                }
            default:
                if let s = String(data: att.data, encoding: .utf8), !s.isEmpty {
                    currentUserBlocks.append(["text": "[File: \(att.name)]\n\(s)"])
                }
            }
        }
        let finalPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Continue." : prompt
        currentUserBlocks.append(["text": finalPrompt])
        appendBedrockBlocks(role: "user", blocks: currentUserBlocks)

        // Bedrock requires the first message to be `user`
        if let first = bedrockMessages.first, (first["role"] as? String) != "user" {
            bedrockMessages.insert(["role": "user", "content": [["text": "Continue."]]], at: 0)
        }

        var bodyObj: [String: Any] = [
            "messages": bedrockMessages,
            "inferenceConfig": [
                "maxTokens": min(maxOutputTokens(for: model), 32768),
                "temperature": 0.7
            ]
        ]
        if let sys = systemPrompt, !sys.isEmpty {
            bodyObj["system"] = [["text": sys]]
        }
        if let tools, !tools.isEmpty {
            let specs: [[String: Any]] = tools.map { rawTool in
                let sanitized = sanitizeToolSchemaForStandardJSONSchema(rawTool)
                return [
                    "toolSpec": [
                        "name": sanitized["name"] ?? "",
                        "description": sanitized["description"] ?? "",
                        "inputSchema": [
                            "json": sanitized["parameters"] ?? ["type": "object", "properties": [String: Any]()]
                        ]
                    ]
                ]
            }
            bodyObj["toolConfig"] = ["tools": specs]
        }

        let bodyData = try JSONSerialization.data(withJSONObject: bodyObj, options: [.sortedKeys])
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        ent.applyProfileHeaders(profile: profile, to: &request)

        if profile.authScheme == .awsBedrockAPIKey {
            let key = ent.readPrimarySecret(for: profile.id)
            guard !key.isEmpty else {
                throw NSError(domain: "EnterpriseAI", code: 401, userInfo: [
                    NSLocalizedDescriptionKey: "Bedrock API Key (ABSK…) is missing for profile '\(profile.name)'."
                ])
            }
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        } else {
            let creds = try await ent.resolveAWSSigV4Credentials(for: profile)
            EnterpriseAWSSigV4Signer.sign(
                request: &request,
                bodyData: bodyData,
                credentials: creds,
                region: profile.awsRegion,
                service: "bedrock"
            )
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "EnterpriseAI", code: code, userInfo: [
                NSLocalizedDescriptionKey: "AWS Bedrock HTTP \(code): \(String(raw.prefix(320)))"
            ])
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let output = root["output"] as? [String: Any],
           let message = output["message"] as? [String: Any],
           let contents = message["content"] as? [[String: Any]] {
            for block in contents {
                if let text = block["text"] as? String, !text.isEmpty {
                    appendStreamToken(text, onToken: onToken)
                }
                if let toolUse = block["toolUse"] as? [String: Any],
                   let name = toolUse["name"] as? String {
                    let id = (toolUse["toolUseId"] as? String) ?? UUID().uuidString
                    let args = (toolUse["input"] as? [String: Any]) ?? [:]
                    onToolCall?(AIToolCall(id: id, name: name, arguments: args))
                }
            }
        }
        if let usage = root["usage"] as? [String: Any] {
            let inTok = usage["inputTokens"] as? Int ?? 0
            let outTok = usage["outputTokens"] as? Int ?? 0
            Task { @MainActor in
                AIUsageTracker.shared.record(
                    provider: "bedrock",
                    model: model,
                    promptTokens: inTok,
                    completionTokens: outTok,
                    cachedTokens: 0,
                    taskLabel: "Enterprise"
                )
            }
        }
    }
}
