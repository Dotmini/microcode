import Foundation

/// Thin native bridge to the embedded Rust agent_kernel. The Rust service is
/// the durable source of truth; this client never invents completion when the
/// backend is temporarily unavailable.
@MainActor
final class AgentKernelClient {
    static let shared = AgentKernelClient()

    private let baseURL = URL(string: "http://127.0.0.1:3000/api/agent-kernel")!
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func createOrResume(
        runID: String,
        parentRunID: String? = nil,
        objective: String,
        workspace: String,
        provider: String,
        model: String,
        tools: [String],
        skills: [String],
        mcpServers: [String]
    ) async -> AgentKernelResponse? {
        let request = AgentKernelCreateRequest(
            runId: runID,
            parentRunId: parentRunID,
            objective: objective,
            workspace: workspace,
            provider: provider,
            model: model,
            tools: tools,
            skills: skills,
            mcpServers: mcpServers
        )
        return try? await post(path: "/runs", body: request)
    }

    func observe(
        runID: String,
        kind: String,
        nodeID: String? = nil,
        toolName: String? = nil,
        arguments: [String: Any] = [:],
        success: Bool? = nil,
        output: String = "",
        error: String = "",
        madeProgress: Bool = false,
        transient: Bool = false
    ) async -> AgentKernelResponse? {
        let request = AgentKernelObserveRequest(
            kind: kind,
            nodeId: nodeID,
            toolName: toolName,
            arguments: JSONValue.object(arguments),
            success: success,
            output: output,
            error: error,
            madeProgress: madeProgress,
            transient: transient
        )
        return try? await post(path: "/runs/\(runID)/observe", body: request)
    }

    func setPlan(runID: String, nodes: [AgentKernelPlanNode]) async -> AgentKernelResponse? {
        let request = AgentKernelSetPlanRequest(nodes: nodes)
        return try? await post(path: "/runs/\(runID)/plan", body: request)
    }

    func cancel(runID: String) async {
        let empty = AgentKernelEmptyRequest()
        let _: AgentKernelResponse? = try? await post(path: "/runs/\(runID)/cancel", body: empty)
    }

    private func post<Body: Encodable, Response: Decodable>(path: String, body: Body) async throws -> Response {
        let relativePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = baseURL.appendingPathComponent(relativePath)
        var request = LocalBackendAuth.request(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.microCodeKernel.encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AgentKernelClientError.invalidResponse
        }
        return try JSONDecoder.microCodeKernel.decode(Response.self, from: data)
    }
}

enum AgentKernelClientError: Error {
    case invalidURL
    case invalidResponse
}

private struct AgentKernelEmptyRequest: Codable {}

private struct AgentKernelCreateRequest: Codable {
    let runId: String
    let parentRunId: String?
    let objective: String
    let workspace: String
    let provider: String
    let model: String
    let tools: [String]
    let skills: [String]
    let mcpServers: [String]
}

private struct AgentKernelObserveRequest: Codable {
    let kind: String
    let nodeId: String?
    let toolName: String?
    let arguments: JSONValue
    let success: Bool?
    let output: String
    let error: String
    let madeProgress: Bool
    let transient: Bool
}

private struct AgentKernelSetPlanRequest: Codable {
    let nodes: [AgentKernelPlanNode]
}

struct AgentKernelPlanNode: Codable {
    let id: String
    let title: String
    let description: String
    let dependencies: [String]
    let verification: String
    let requiredTools: [String]
    let owner: String?
    let state: String
    let attempts: UInt32

    init(
        id: String,
        title: String,
        description: String = "",
        dependencies: [String] = [],
        verification: String = "",
        requiredTools: [String] = [],
        owner: String? = nil,
        state: String = "pending",
        attempts: UInt32 = 0
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.dependencies = dependencies
        self.verification = verification
        self.requiredTools = requiredTools
        self.owner = owner
        self.state = state
        self.attempts = attempts
    }
}

struct AgentKernelResponse: Codable {
    let run: AgentKernelRun
    let directive: AgentKernelDirective
}

struct AgentKernelRun: Codable {
    let id: String
    let state: String
    let sequence: UInt64
    let plan: [AgentKernelPlanNode]
    let retryAttempt: UInt32
    let noProgressStreak: UInt32
    let terminalReason: String?
}

struct AgentKernelDirective: Codable {
    let action: String
    let reason: String
    let state: String
    let retryAfterMs: UInt64?
    let readyNodes: [String]
    let suggestedPrompt: String?
}

private enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    static func object(_ dictionary: [String: Any]) -> JSONValue {
        .object(dictionary.mapValues(fromAny))
    }

    private static func fromAny(_ value: Any) -> JSONValue {
        switch value {
        case let value as String: return .string(value)
        case let value as Bool: return .bool(value)
        case let value as Int: return .number(Double(value))
        case let value as UInt: return .number(Double(value))
        case let value as Double: return .number(value)
        case let value as Float: return .number(Double(value))
        case let value as [String: Any]: return .object(value.mapValues(fromAny))
        case let value as [Any]: return .array(value.map(fromAny))
        default: return .string(String(describing: value))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

private extension JSONEncoder {
    static var microCodeKernel: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

private extension JSONDecoder {
    static var microCodeKernel: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
