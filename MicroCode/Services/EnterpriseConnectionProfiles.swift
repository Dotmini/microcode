//
//  EnterpriseConnectionProfiles.swift
//  MicroCode
//
//  1-Click Enterprise API Hub: Multi-Profile Engine, Smart Paste Parser (URL / cURL / .env),
//  Zero-Key CLI SSO Auto-Detection (gcloud / az / aws), AWS SigV4 & Bedrock Converse Auth,
//  Azure OpenAI / Foundry Auth, Vertex AI + Discovery Engine (:streamAssist),
//  Custom Headers (Keychain-backed), Corporate Proxy, Live Model Discovery, & 1-Click Team Share.
//

import Foundation
import CryptoKit
import AppKit

// MARK: - Enterprise Provider Dialects & Auth Schemes

public enum EnterpriseProviderDialect: String, CaseIterable, Codable, Identifiable {
    case openaiGateway = "openai_gateway"
    case azureOpenAI = "azure_openai"
    case vertexGemini = "vertex_gemini"
    case geminiEnterpriseAgentspace = "gemini_enterprise_agentspace"
    case awsBedrock = "aws_bedrock"
    case anthropicGateway = "anthropic_gateway"
    case dotminiEnterprise = "dotmini_enterprise"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .openaiGateway: return "Enterprise AI Gateway (LiteLLM / Kong / VPC)"
        case .azureOpenAI: return "Azure OpenAI / Microsoft AI Foundry"
        case .vertexGemini: return "Google Cloud Vertex AI (Gemini & Claude)"
        case .geminiEnterpriseAgentspace: return "Google Gemini Enterprise (Agentspace / Search)"
        case .awsBedrock: return "AWS Bedrock (Converse API / Claude / Nova)"
        case .anthropicGateway: return "Anthropic Enterprise / Messages Proxy"
        case .dotminiEnterprise: return "Dotmini Sovereign Cloud Enterprise (ZDR)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .openaiGateway: return "AI Gateway"
        case .azureOpenAI: return "Azure OpenAI"
        case .vertexGemini: return "Vertex AI"
        case .geminiEnterpriseAgentspace: return "Gemini Enterprise"
        case .awsBedrock: return "AWS Bedrock"
        case .anthropicGateway: return "Anthropic Ent"
        case .dotminiEnterprise: return "Dotmini Ent"
        }
    }

    public var subtitle: String {
        switch self {
        case .openaiGateway:
            return "OpenAI-compatible corporate proxy: LiteLLM, Kong, Apigee, Portkey, Cloudflare AI Gateway, or internal vLLM/SGLang."
        case .azureOpenAI:
            return "Connect via Azure OpenAI deployment URL or Microsoft AI Foundry with API Key or Azure CLI Entra ID SSO."
        case .vertexGemini:
            return "Regional Google Cloud Vertex AI for Gemini 2.5/3.x and Claude on Vertex using gcloud SSO, Service Account JSON, or API Key."
        case .geminiEnterpriseAgentspace:
            return "Google Cloud Discovery Engine (:streamAssist) grounded on corporate Google Drive, SharePoint, Jira, and Confluence."
        case .awsBedrock:
            return "Amazon Bedrock Runtime Converse API using Bedrock API Key (ABSK…) or AWS SSO / ~/.aws profile (SigV4)."
        case .anthropicGateway:
            return "Anthropic Messages API (/v1/messages) through an enterprise gateway, Cloudflare Access, or direct corporate key."
        case .dotminiEnterprise:
            return "Managed Sovereign ZDR Multi-Model Gateway with centralized organization billing and data residency."
        }
    }

    public var systemIcon: String {
        switch self {
        case .openaiGateway: return "network.badge.shield.half.filled"
        case .azureOpenAI: return "cloud.bolt.fill"
        case .vertexGemini: return "sparkles.tv.fill"
        case .geminiEnterpriseAgentspace: return "magnifyingglass.circle.fill"
        case .awsBedrock: return "cube.transparent.fill"
        case .anthropicGateway: return "brain.head.profile"
        case .dotminiEnterprise: return "building.2.crop.circle.fill"
        }
    }

    public var brandIconKey: String {
        switch self {
        case .openaiGateway: return "openai"
        case .azureOpenAI: return "openai"
        case .vertexGemini, .geminiEnterpriseAgentspace: return "gemini"
        case .awsBedrock, .anthropicGateway: return "anthropic"
        case .dotminiEnterprise: return "microcode"
        }
    }

    public var supportedAuthSchemes: [EnterpriseAuthScheme] {
        switch self {
        case .openaiGateway:
            return [.bearerToken, .apiKeyHeader, .xApiKeyHeader, .ocpApimKey, .customHeadersOnly]
        case .azureOpenAI:
            return [.apiKeyHeader, .azureEntraCLI, .bearerToken]
        case .vertexGemini:
            return [.gcloudADC, .serviceAccountJSON, .apiKeyQueryOrBearer]
        case .geminiEnterpriseAgentspace:
            return [.gcloudADC, .serviceAccountJSON]
        case .awsBedrock:
            return [.awsBedrockAPIKey, .awsSigV4Profile, .awsSigV4AccessKey]
        case .anthropicGateway:
            return [.xApiKeyHeader, .bearerToken, .customHeadersOnly]
        case .dotminiEnterprise:
            return [.bearerToken]
        }
    }

    public var fallbackModels: [String] {
        switch self {
        case .openaiGateway:
            return ["gpt-4.1", "gpt-4o", "claude-sonnet-4-20250514", "gemini-2.5-pro", "deepseek-chat"]
        case .azureOpenAI:
            return ["gpt-4.1", "gpt-4o", "gpt-4o-mini", "o3-mini"]
        case .vertexGemini:
            return [
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.0-flash",
                "claude-sonnet-4@20250514",
                "claude-3-7-sonnet@20250219"
            ]
        case .geminiEnterpriseAgentspace:
            return ["default_assistant"]
        case .awsBedrock:
            return [
                "apac.anthropic.claude-sonnet-4-20250514-v1:0",
                "apac.anthropic.claude-3-7-sonnet-20250219-v1:0",
                "us.anthropic.claude-sonnet-4-20250514-v1:0",
                "us.anthropic.claude-3-7-sonnet-20250219-v1:0",
                "apac.amazon.nova-pro-v1:0",
                "us.amazon.nova-pro-v1:0"
            ]
        case .anthropicGateway:
            return ["claude-sonnet-4-20250514", "claude-3-7-sonnet-20250219", "claude-3-5-haiku-20241022"]
        case .dotminiEnterprise:
            return ["omni-o1x-pro", "gemini-2.5-pro", "gemini-2.5-flash", "claude-3-7-sonnet-20250219", "gpt-4o"]
        }
    }
}

public enum EnterpriseAuthScheme: String, CaseIterable, Codable, Identifiable {
    case bearerToken = "bearer_token"
    case apiKeyHeader = "api_key_header"
    case xApiKeyHeader = "x_api_key_header"
    case ocpApimKey = "ocp_apim_key"
    case apiKeyQueryOrBearer = "api_key_query"
    case gcloudADC = "gcloud_adc"
    case serviceAccountJSON = "service_account_json"
    case azureEntraCLI = "azure_entra_cli"
    case awsBedrockAPIKey = "aws_bedrock_api_key"
    case awsSigV4Profile = "aws_sigv4_profile"
    case awsSigV4AccessKey = "aws_sigv4_access_key"
    case customHeadersOnly = "custom_headers_only"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bearerToken: return "Bearer API Key (Authorization: Bearer …)"
        case .apiKeyHeader: return "Azure / Gateway api-key Header"
        case .xApiKeyHeader: return "x-api-key Header"
        case .ocpApimKey: return "Azure APIM (Ocp-Apim-Subscription-Key)"
        case .apiKeyQueryOrBearer: return "Vertex Express / Enterprise API Key"
        case .gcloudADC: return "1-Click Google Cloud SSO (gcloud / ADC)"
        case .serviceAccountJSON: return "Service Account JSON Key"
        case .azureEntraCLI: return "1-Click Microsoft Entra ID SSO (az login)"
        case .awsBedrockAPIKey: return "Bedrock API Key (ABSK…)"
        case .awsSigV4Profile: return "1-Click AWS SSO / CLI Profile (~/.aws)"
        case .awsSigV4AccessKey: return "AWS IAM Access Key + Secret (SigV4)"
        case .customHeadersOnly: return "Zero-Trust Custom Headers Only (CF-Access / mTLS)"
        }
    }

    public var requiresPrimarySecretField: Bool {
        switch self {
        case .bearerToken, .apiKeyHeader, .xApiKeyHeader, .ocpApimKey, .apiKeyQueryOrBearer, .awsBedrockAPIKey, .awsSigV4AccessKey:
            return true
        case .gcloudADC, .serviceAccountJSON, .azureEntraCLI, .awsSigV4Profile, .customHeadersOnly:
            return false
        }
    }
}

// MARK: - Custom Header & Profile Models

public struct EnterpriseHeaderItem: Codable, Equatable, Identifiable {
    public var id: String = UUID().uuidString
    public var key: String
    /// Plaintext value when `isSecret == false`; empty on disk when `isSecret == true` (stored in Keychain).
    public var value: String
    public var isSecret: Bool
    public var requiresUserSecret: Bool

    public init(
        id: String = UUID().uuidString,
        key: String,
        value: String = "",
        isSecret: Bool = false,
        requiresUserSecret: Bool = false
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.isSecret = isSecret
        self.requiresUserSecret = requiresUserSecret
    }
}

public struct EnterpriseAPIProfile: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var organizationId: String
    public var dialect: EnterpriseProviderDialect
    public var authScheme: EnterpriseAuthScheme

    // Gateway / OpenAI / Anthropic / Dotmini URL
    public var baseURL: String

    // Azure OpenAI / Foundry
    public var azureResourceName: String
    public var azureDeploymentName: String
    public var azureAPIVersion: String

    // Google Cloud Vertex AI & Gemini Enterprise (Discovery Engine)
    public var gcpProjectId: String
    public var gcpLocation: String
    public var discoveryEngineId: String
    public var discoveryCollectionId: String
    public var discoveryAssistantId: String

    // AWS Bedrock
    public var awsRegion: String
    public var awsProfileName: String
    public var awsAccessKeyId: String

    // Network & Headers
    public var customHeaders: [EnterpriseHeaderItem]
    public var proxyURL: String

    // Models
    public var discoveredModels: [String]
    public var customModels: [String]
    public var defaultModel: String

    // Governance overrides
    public var enforceZDR: Bool
    public var enforceDLP: Bool

    // Verification state
    public var isVerified: Bool
    public var toolCallingSupported: Bool
    public var lastVerifiedAt: Date?
    public var lastStatusMessage: String

    public init(
        id: String = UUID().uuidString,
        name: String,
        organizationId: String = "",
        dialect: EnterpriseProviderDialect,
        authScheme: EnterpriseAuthScheme? = nil,
        baseURL: String = "",
        azureResourceName: String = "",
        azureDeploymentName: String = "",
        azureAPIVersion: String = "2024-10-21",
        gcpProjectId: String = "",
        gcpLocation: String = "asia-southeast1",
        discoveryEngineId: String = "",
        discoveryCollectionId: String = "default_collection",
        discoveryAssistantId: String = "default_assistant",
        awsRegion: String = "ap-southeast-1",
        awsProfileName: String = "default",
        awsAccessKeyId: String = "",
        customHeaders: [EnterpriseHeaderItem] = [],
        proxyURL: String = "",
        discoveredModels: [String] = [],
        customModels: [String] = [],
        defaultModel: String = "",
        enforceZDR: Bool = true,
        enforceDLP: Bool = true,
        isVerified: Bool = false,
        toolCallingSupported: Bool = true,
        lastVerifiedAt: Date? = nil,
        lastStatusMessage: String = ""
    ) {
        self.id = id
        self.name = name
        self.organizationId = organizationId
        self.dialect = dialect
        self.authScheme = authScheme ?? (dialect.supportedAuthSchemes.first ?? .bearerToken)
        self.baseURL = baseURL
        self.azureResourceName = azureResourceName
        self.azureDeploymentName = azureDeploymentName
        self.azureAPIVersion = azureAPIVersion
        self.gcpProjectId = gcpProjectId
        self.gcpLocation = gcpLocation
        self.discoveryEngineId = discoveryEngineId
        self.discoveryCollectionId = discoveryCollectionId
        self.discoveryAssistantId = discoveryAssistantId
        self.awsRegion = awsRegion
        self.awsProfileName = awsProfileName
        self.awsAccessKeyId = awsAccessKeyId
        self.customHeaders = customHeaders
        self.proxyURL = proxyURL
        self.discoveredModels = discoveredModels
        self.customModels = customModels
        let initialDefault = !defaultModel.isEmpty
            ? defaultModel
            : (!azureDeploymentName.isEmpty ? azureDeploymentName : (dialect.fallbackModels.first ?? "gpt-4o"))
        self.defaultModel = initialDefault
        self.enforceZDR = enforceZDR
        self.enforceDLP = enforceDLP
        self.isVerified = isVerified
        self.toolCallingSupported = toolCallingSupported
        self.lastVerifiedAt = lastVerifiedAt
        self.lastStatusMessage = lastStatusMessage
    }

    /// Combined deduplicated list of models available for selection in the AI Agent picker
    public var availableModels: [String] {
        var seen = Set<String>()
        var result: [String] = []
        func appendUnique(_ item: String) {
            let clean = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seen.insert(clean).inserted else { return }
            result.append(clean)
        }
        if dialect == .azureOpenAI, !azureDeploymentName.isEmpty {
            appendUnique(azureDeploymentName)
        }
        for m in customModels { appendUnique(m) }
        for m in discoveredModels { appendUnique(m) }
        if !defaultModel.isEmpty { appendUnique(defaultModel) }
        if result.isEmpty {
            for m in dialect.fallbackModels { appendUnique(m) }
        }
        return result
    }

    public var endpointSummary: String {
        switch dialect {
        case .openaiGateway, .anthropicGateway, .dotminiEnterprise:
            return baseURL.isEmpty ? "Not configured" : baseURL
        case .azureOpenAI:
            if !baseURL.isEmpty { return baseURL }
            if !azureResourceName.isEmpty {
                let dep = azureDeploymentName.isEmpty ? "<deployment>" : azureDeploymentName
                return "https://\(azureResourceName).openai.azure.com/openai/deployments/\(dep)"
            }
            return "Azure OpenAI"
        case .vertexGemini:
            let proj = gcpProjectId.isEmpty ? "<project>" : gcpProjectId
            return "vertex://\(gcpLocation)/\(proj)"
        case .geminiEnterpriseAgentspace:
            let proj = gcpProjectId.isEmpty ? "<project>" : gcpProjectId
            let eng = discoveryEngineId.isEmpty ? "<engine>" : discoveryEngineId
            return "agentspace://\(gcpLocation)/\(proj)/\(eng)"
        case .awsBedrock:
            return "bedrock-runtime.\(awsRegion).amazonaws.com"
        }
    }
}

// MARK: - CLI SSO Auto-Detection Status

public struct EnterpriseCLIDetectionStatus: Equatable {
    public var gcloudPath: String? = nil
    public var gcloudAccount: String = ""
    public var gcloudProject: String = ""
    public var hasGcloudADCFile: Bool = false

    public var azPath: String? = nil
    public var azAccount: String = ""
    public var azTenantId: String = ""

    public var awsPath: String? = nil
    public var awsProfiles: [String] = []
    public var awsDefaultRegion: String = "ap-southeast-1"

    public var isScanning: Bool = false

    public init() {}

    public var isGcloudReady: Bool {
        hasGcloudADCFile || (!gcloudAccount.isEmpty && gcloudPath != nil)
    }

    public var isAzureReady: Bool {
        !azAccount.isEmpty && azPath != nil
    }

    public var isAWSReady: Bool {
        !awsProfiles.isEmpty
    }
}

// MARK: - 1-Click Team Share Package (.microcode-enterprise.json & microcode://enterprise)

public struct EnterpriseTeamShareBundle: Codable {
    public var schemaVersion: Int = 1
    public var exportedAt: String
    public var profile: EnterpriseAPIProfile
    public var workspacePolicy: WorkspaceEnterprisePolicy?
    public var instructions: String

    public init(
        profile: EnterpriseAPIProfile,
        workspacePolicy: WorkspaceEnterprisePolicy? = nil,
        instructions: String = "Open this file or link in MicroCode / MicroCode AI to configure your organization's Enterprise API in 1 click."
    ) {
        let fmt = ISO8601DateFormatter()
        self.exportedAt = fmt.string(from: Date())
        self.profile = profile
        self.workspacePolicy = workspacePolicy
        self.instructions = instructions
    }
}

// MARK: - Smart Paste Auto-Parser (URL / cURL / .env / JSON / Deep Link)

public struct EnterpriseSmartPasteParsedOutput {
    public var profile: EnterpriseAPIProfile
    public var primarySecret: String?
    public var secondarySecret: String? // e.g. AWS Secret Access Key or Service Account JSON
    public var headerSecrets: [String: String] // headerItem.id -> secret value
    public var summary: String
}

public enum EnterpriseSmartPasteParser {

    public static func parse(_ rawInput: String) -> EnterpriseSmartPasteParsedOutput? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Check microcode://enterprise?config=... deep link
        if trimmed.lowercased().hasPrefix("microcode://enterprise") || trimmed.lowercased().hasPrefix("codetuner://enterprise"),
           let url = URL(string: trimmed),
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: true),
           let b64 = comps.queryItems?.first(where: { $0.name == "config" })?.value,
           let decoded = decodeBase64URL(b64),
           let bundle = try? JSONDecoder().decode(EnterpriseTeamShareBundle.self, from: decoded) {
            return EnterpriseSmartPasteParsedOutput(
                profile: bundle.profile,
                primarySecret: nil,
                secondarySecret: nil,
                headerSecrets: [:],
                summary: "Imported Team Enterprise Profile: \(bundle.profile.name)"
            )
        }

        // 2. Check JSON: either EnterpriseTeamShareBundle or Google Service Account JSON
        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) {
            if let bundle = try? JSONDecoder().decode(EnterpriseTeamShareBundle.self, from: data) {
                return EnterpriseSmartPasteParsedOutput(
                    profile: bundle.profile,
                    primarySecret: nil,
                    secondarySecret: nil,
                    headerSecrets: [:],
                    summary: "Imported Team Enterprise Profile: \(bundle.profile.name)"
                )
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (json["type"] as? String) == "service_account",
               let projectId = json["project_id"] as? String,
               let privateKey = json["private_key"] as? String,
               privateKey.contains("PRIVATE KEY") {
                let profile = EnterpriseAPIProfile(
                    name: "Vertex AI (\(projectId))",
                    organizationId: projectId,
                    dialect: .vertexGemini,
                    authScheme: .serviceAccountJSON,
                    gcpProjectId: projectId,
                    gcpLocation: "asia-southeast1",
                    defaultModel: "gemini-2.5-pro"
                )
                return EnterpriseSmartPasteParsedOutput(
                    profile: profile,
                    primarySecret: nil,
                    secondarySecret: trimmed,
                    headerSecrets: [:],
                    summary: "Detected Google Cloud Service Account JSON for project '\(projectId)'"
                )
            }
        }

        // 3. Check AWS Bedrock ABSK standalone key
        if trimmed.hasPrefix("ABSK") && !trimmed.contains(" ") && !trimmed.contains("\n") {
            let profile = EnterpriseAPIProfile(
                name: "AWS Bedrock Enterprise",
                dialect: .awsBedrock,
                authScheme: .awsBedrockAPIKey,
                awsRegion: "ap-southeast-1",
                defaultModel: "apac.anthropic.claude-sonnet-4-20250514-v1:0"
            )
            return EnterpriseSmartPasteParsedOutput(
                profile: profile,
                primarySecret: trimmed,
                secondarySecret: nil,
                headerSecrets: [:],
                summary: "Detected AWS Bedrock API Key (ABSK…)"
            )
        }

        // 4. Check Dotmini Enterprise standalone key
        if (trimmed.hasPrefix("sk-dotmini-ent-") || trimmed.hasPrefix("sk-dotmini-")) && !trimmed.contains("\n") {
            let profile = EnterpriseAPIProfile(
                name: "Dotmini Sovereign Enterprise",
                dialect: .dotminiEnterprise,
                authScheme: .bearerToken,
                baseURL: "https://api.dotmini.net/v1",
                defaultModel: "omni-o1x-pro"
            )
            return EnterpriseSmartPasteParsedOutput(
                profile: profile,
                primarySecret: trimmed,
                secondarySecret: nil,
                headerSecrets: [:],
                summary: "Detected Dotmini Cloud Enterprise Key"
            )
        }

        // 5. Check .env / shell export key=value blocks
        if trimmed.contains("=") && (
            trimmed.contains("OPENAI_") ||
            trimmed.contains("AZURE_") ||
            trimmed.contains("ANTHROPIC_") ||
            trimmed.contains("VERTEX") ||
            trimmed.contains("GOOGLE_CLOUD_PROJECT") ||
            trimmed.contains("AWS_") ||
            trimmed.contains("LITELLM") ||
            trimmed.contains("CF_ACCESS_")
        ) {
            if let envResult = parseEnvBlock(trimmed) {
                return envResult
            }
        }

        // 6. Check cURL command or direct HTTP(S) URL
        return parseCurlOrURL(trimmed)
    }

    private static func parseEnvBlock(_ text: String) -> EnterpriseSmartPasteParsedOutput? {
        var env: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            var val = String(line[line.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
            if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                val = String(val.dropFirst().dropLast())
            }
            if !key.isEmpty { env[key.uppercased()] = val }
        }
        guard !env.isEmpty else { return nil }

        var extraHeaders: [EnterpriseHeaderItem] = []
        var headerSecrets: [String: String] = [:]
        if let cfId = env["CF_ACCESS_CLIENT_ID"], !cfId.isEmpty {
            extraHeaders.append(EnterpriseHeaderItem(key: "CF-Access-Client-Id", value: cfId, isSecret: false))
        }
        if let cfSecret = env["CF_ACCESS_CLIENT_SECRET"], !cfSecret.isEmpty {
            let item = EnterpriseHeaderItem(key: "CF-Access-Client-Secret", value: "", isSecret: true)
            extraHeaders.append(item)
            headerSecrets[item.id] = cfSecret
        }

        let proxy = env["HTTPS_PROXY"] ?? env["HTTP_PROXY"] ?? ""

        // Azure OpenAI
        if let azEndpoint = env["AZURE_OPENAI_ENDPOINT"] ?? env["AZURE_AI_ENDPOINT"], !azEndpoint.isEmpty {
            var parsed = parseCurlOrURL(azEndpoint)?.profile ?? EnterpriseAPIProfile(
                name: "Azure OpenAI Enterprise",
                dialect: .azureOpenAI,
                authScheme: .apiKeyHeader
            )
            if let dep = env["AZURE_OPENAI_DEPLOYMENT"] ?? env["AZURE_OPENAI_DEPLOYMENT_NAME"] ?? env["AZURE_OPENAI_MODEL"], !dep.isEmpty {
                parsed.azureDeploymentName = dep
                parsed.defaultModel = dep
            }
            if let ver = env["AZURE_OPENAI_API_VERSION"] ?? env["OPENAI_API_VERSION"], !ver.isEmpty {
                parsed.azureAPIVersion = ver
            }
            parsed.customHeaders.append(contentsOf: extraHeaders)
            if !proxy.isEmpty { parsed.proxyURL = proxy }
            let key = env["AZURE_OPENAI_API_KEY"] ?? env["AZURE_API_KEY"] ?? env["OPENAI_API_KEY"]
            if key == nil || key?.isEmpty == true {
                parsed.authScheme = .azureEntraCLI
            }
            return EnterpriseSmartPasteParsedOutput(
                profile: parsed,
                primarySecret: key,
                secondarySecret: nil,
                headerSecrets: headerSecrets,
                summary: "Configured Azure OpenAI from .env variables"
            )
        }

        // Vertex AI / Anthropic on Vertex
        if let gcpProj = env["GOOGLE_CLOUD_PROJECT"] ?? env["ANTHROPIC_VERTEX_PROJECT_ID"] ?? env["GCLOUD_PROJECT"] ?? env["VERTEX_PROJECT_ID"], !gcpProj.isEmpty {
            let loc = env["GOOGLE_CLOUD_LOCATION"] ?? env["CLOUD_ML_REGION"] ?? env["VERTEX_LOCATION"] ?? "asia-southeast1"
            let isClaude = env["ANTHROPIC_VERTEX_PROJECT_ID"] != nil
            let model = env["ANTHROPIC_MODEL"] ?? env["VERTEX_MODEL"] ?? (isClaude ? "claude-sonnet-4@20250514" : "gemini-2.5-pro")
            let profile = EnterpriseAPIProfile(
                name: "Vertex AI (\(gcpProj))",
                organizationId: gcpProj,
                dialect: .vertexGemini,
                authScheme: env["VERTEX_API_KEY"] != nil ? .apiKeyQueryOrBearer : .gcloudADC,
                gcpProjectId: gcpProj,
                gcpLocation: loc,
                customHeaders: extraHeaders,
                proxyURL: proxy,
                defaultModel: model
            )
            return EnterpriseSmartPasteParsedOutput(
                profile: profile,
                primarySecret: env["VERTEX_API_KEY"] ?? env["GOOGLE_API_KEY"],
                secondarySecret: nil,
                headerSecrets: headerSecrets,
                summary: "Configured Google Cloud Vertex AI (\(gcpProj) • \(loc)) from .env"
            )
        }

        // AWS Bedrock
        if env["AWS_BEARER_TOKEN_BEDROCK"] != nil || env["AWS_ACCESS_KEY_ID"] != nil || env["AWS_PROFILE"] != nil {
            let region = env["AWS_REGION"] ?? env["AWS_DEFAULT_REGION"] ?? "ap-southeast-1"
            let model = env["BEDROCK_MODEL_ID"] ?? env["ANTHROPIC_MODEL"] ?? "apac.anthropic.claude-sonnet-4-20250514-v1:0"
            if let bearer = env["AWS_BEARER_TOKEN_BEDROCK"], !bearer.isEmpty {
                let profile = EnterpriseAPIProfile(
                    name: "AWS Bedrock (\(region))",
                    dialect: .awsBedrock,
                    authScheme: .awsBedrockAPIKey,
                    awsRegion: region,
                    customHeaders: extraHeaders,
                    proxyURL: proxy,
                    defaultModel: model
                )
                return EnterpriseSmartPasteParsedOutput(
                    profile: profile,
                    primarySecret: bearer,
                    secondarySecret: nil,
                    headerSecrets: headerSecrets,
                    summary: "Configured AWS Bedrock API Key (\(region)) from .env"
                )
            } else if let ak = env["AWS_ACCESS_KEY_ID"], !ak.isEmpty {
                let profile = EnterpriseAPIProfile(
                    name: "AWS Bedrock IAM (\(region))",
                    dialect: .awsBedrock,
                    authScheme: .awsSigV4AccessKey,
                    awsRegion: region,
                    awsAccessKeyId: ak,
                    customHeaders: extraHeaders,
                    proxyURL: proxy,
                    defaultModel: model
                )
                return EnterpriseSmartPasteParsedOutput(
                    profile: profile,
                    primarySecret: env["AWS_SECRET_ACCESS_KEY"],
                    secondarySecret: env["AWS_SESSION_TOKEN"],
                    headerSecrets: headerSecrets,
                    summary: "Configured AWS Bedrock IAM SigV4 (\(region)) from .env"
                )
            } else if let awsProf = env["AWS_PROFILE"], !awsProf.isEmpty {
                let profile = EnterpriseAPIProfile(
                    name: "AWS Bedrock SSO (\(awsProf))",
                    dialect: .awsBedrock,
                    authScheme: .awsSigV4Profile,
                    awsRegion: region,
                    awsProfileName: awsProf,
                    customHeaders: extraHeaders,
                    proxyURL: proxy,
                    defaultModel: model
                )
                return EnterpriseSmartPasteParsedOutput(
                    profile: profile,
                    primarySecret: nil,
                    secondarySecret: nil,
                    headerSecrets: headerSecrets,
                    summary: "Configured AWS Bedrock CLI Profile '\(awsProf)' (\(region))"
                )
            }
        }

        // Anthropic Enterprise Gateway
        if let anthBase = env["ANTHROPIC_BASE_URL"], !anthBase.isEmpty {
            let normalizedBase = normalizeAnthropicBaseURL(anthBase)
            let key = env["ANTHROPIC_API_KEY"] ?? env["ANTHROPIC_AUTH_TOKEN"]
            let scheme: EnterpriseAuthScheme = (env["ANTHROPIC_AUTH_TOKEN"] != nil && env["ANTHROPIC_API_KEY"] == nil)
                ? .bearerToken
                : .xApiKeyHeader
            let profile = EnterpriseAPIProfile(
                name: hostDisplayName(from: normalizedBase, fallback: "Anthropic Gateway"),
                dialect: .anthropicGateway,
                authScheme: scheme,
                baseURL: normalizedBase,
                customHeaders: extraHeaders,
                proxyURL: proxy,
                defaultModel: env["ANTHROPIC_MODEL"] ?? "claude-sonnet-4-20250514"
            )
            return EnterpriseSmartPasteParsedOutput(
                profile: profile,
                primarySecret: key,
                secondarySecret: nil,
                headerSecrets: headerSecrets,
                summary: "Configured Anthropic Enterprise Gateway (\(normalizedBase))"
            )
        }

        // Generic OpenAI / LiteLLM / Corporate Gateway
        if let oaiBase = env["OPENAI_BASE_URL"] ?? env["OPENAI_API_BASE"] ?? env["LITELLM_BASE_URL"], !oaiBase.isEmpty {
            let normalizedBase = normalizeOpenAIBaseURL(oaiBase)
            let key = env["OPENAI_API_KEY"] ?? env["LITELLM_API_KEY"]
            let profile = EnterpriseAPIProfile(
                name: hostDisplayName(from: normalizedBase, fallback: "Enterprise AI Gateway"),
                dialect: .openaiGateway,
                authScheme: (key?.isEmpty == false) ? .bearerToken : (extraHeaders.isEmpty ? .bearerToken : .customHeadersOnly),
                baseURL: normalizedBase,
                customHeaders: extraHeaders,
                proxyURL: proxy,
                defaultModel: env["OPENAI_MODEL"] ?? "gpt-4.1"
            )
            return EnterpriseSmartPasteParsedOutput(
                profile: profile,
                primarySecret: key,
                secondarySecret: nil,
                headerSecrets: headerSecrets,
                summary: "Configured Enterprise AI Gateway (\(normalizedBase))"
            )
        }

        return nil
    }

    private static func parseCurlOrURL(_ text: String) -> EnterpriseSmartPasteParsedOutput? {
        // Join line continuations from multi-line cURL commands
        let joined = text.replacingOccurrences(of: "\\\n", with: " ")
            .replacingOccurrences(of: "\\\r\n", with: " ")

        // Extract first https?:// URL
        guard let urlRange = joined.range(of: #"https?://[^\s"'`]+"#, options: .regularExpression) else {
            return nil
        }
        let rawURLStr = String(joined[urlRange])
        guard let url = URL(string: rawURLStr) else { return nil }

        // Extract -H / --header pairs if cURL
        var extractedHeaders: [(String, String)] = []
        let headerPattern = #"(?:-H|--header)\s+["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: headerPattern) {
            let ns = joined as NSString
            for match in regex.matches(in: joined, range: NSRange(location: 0, length: ns.length)) {
                if match.numberOfRanges > 1 {
                    let rawH = ns.substring(with: match.range(at: 1))
                    if let colon = rawH.firstIndex(of: ":") {
                        let hk = String(rawH[..<colon]).trimmingCharacters(in: .whitespaces)
                        let hv = String(rawH[rawH.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        extractedHeaders.append((hk, hv))
                    }
                }
            }
        }

        // Extract model from JSON body if present (`"model": "..."`)
        var bodyModel: String? = nil
        if let mRegex = try? NSRegularExpression(pattern: #""model"\s*:\s*"([^"]+)""#),
           let match = mRegex.firstMatch(in: joined, range: NSRange(location: 0, length: (joined as NSString).length)),
           match.numberOfRanges > 1 {
            bodyModel = (joined as NSString).substring(with: match.range(at: 1))
        }

        var primarySecret: String? = nil
        var detectedScheme: EnterpriseAuthScheme? = nil
        var customHeaders: [EnterpriseHeaderItem] = []
        var headerSecrets: [String: String] = [:]
        var gcpProjectHeader: String? = nil

        for (hk, hv) in extractedHeaders {
            let lower = hk.lowercased()
            if lower == "content-type" || lower == "accept" || lower == "anthropic-version" { continue }
            if lower == "x-goog-user-project" {
                gcpProjectHeader = hv
                continue
            }
            if lower == "authorization" {
                if hv.lowercased().hasPrefix("bearer ") {
                    let tok = String(hv.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                    if !tok.contains("$(") && !tok.hasPrefix("$") && tok != "YOUR_API_KEY" {
                        primarySecret = tok
                    }
                    detectedScheme = tok.hasPrefix("ABSK") ? .awsBedrockAPIKey : .bearerToken
                }
                continue
            }
            if lower == "api-key" {
                if !hv.hasPrefix("$") { primarySecret = hv }
                detectedScheme = .apiKeyHeader
                continue
            }
            if lower == "x-api-key" {
                if !hv.hasPrefix("$") { primarySecret = hv }
                detectedScheme = .xApiKeyHeader
                continue
            }
            if lower == "ocp-apim-subscription-key" {
                if !hv.hasPrefix("$") { primarySecret = hv }
                detectedScheme = .ocpApimKey
                continue
            }
            let looksSecret = lower.contains("secret") || lower.contains("token") || lower.contains("key") || lower.contains("auth")
            if looksSecret {
                let item = EnterpriseHeaderItem(key: hk, value: "", isSecret: true)
                customHeaders.append(item)
                headerSecrets[item.id] = hv
            } else {
                customHeaders.append(EnterpriseHeaderItem(key: hk, value: hv, isSecret: false))
            }
        }

        let host = (url.host ?? "").lowercased()
        let path = url.path

        // Case A: Google Vertex AI Search / Gemini Enterprise Web URL (`vertexaisearch.cloud.google/.../cid/<engine>`)
        if host.contains("vertexaisearch.cloud.google") {
            var loc = "global"
            var engineId = ""
            let parts = path.split(separator: "/").map(String.init)
            if let first = parts.first, ["us", "eu", "global"].contains(first.lowercased()) {
                loc = first.lowercased()
            }
            if let cidIdx = parts.firstIndex(of: "cid"), cidIdx + 1 < parts.count {
                engineId = parts[cidIdx + 1]
            }
            let profile = EnterpriseAPIProfile(
                name: "Gemini Enterprise (\(engineId.isEmpty ? "Agentspace" : String(engineId.prefix(8))))",
                dialect: .geminiEnterpriseAgentspace,
                authScheme: .gcloudADC,
                gcpProjectId: gcpProjectHeader ?? "",
                gcpLocation: loc,
                discoveryEngineId: engineId,
                customHeaders: customHeaders,
                defaultModel: "default_assistant"
            )
            return EnterpriseSmartPasteParsedOutput(
                profile: profile,
                primarySecret: nil,
                secondarySecret: nil,
                headerSecrets: headerSecrets,
                summary: "Detected Gemini Enterprise Agentspace (Engine: \(engineId.isEmpty ? "auto" : engineId), Location: \(loc))"
            )
        }

        // Case B: Google Discovery Engine API (`*discoveryengine.googleapis.com/.../projects/<p>/locations/<l>/.../engines/<e>...`)
        if host.contains("discoveryengine.googleapis.com") {
            let parts = path.split(separator: "/").map(String.init)
            let proj = valueAfter("projects", in: parts) ?? gcpProjectHeader ?? ""
            let loc = valueAfter("locations", in: parts) ?? "global"
            let col = valueAfter("collections", in: parts) ?? "default_collection"
            var eng = valueAfter("engines", in: parts) ?? ""
            if let colon = eng.firstIndex(of: ":") { eng = String(eng[..<colon]) }
            var asst = valueAfter("assistants", in: parts) ?? "default_assistant"
            if let colon = asst.firstIndex(of: ":") { asst = String(asst[..<colon]) }

            let profile = EnterpriseAPIProfile(
                name: "Gemini Enterprise (\(proj.isEmpty ? eng : proj))",
                organizationId: proj,
                dialect: .geminiEnterpriseAgentspace,
                authScheme: .gcloudADC,
                gcpProjectId: proj,
                gcpLocation: loc,
                discoveryEngineId: eng,
                discoveryCollectionId: col,
                discoveryAssistantId: asst,
                customHeaders: customHeaders,
                defaultModel: asst
            )
            return EnterpriseSmartPasteParsedOutput(
                profile: profile,
                primarySecret: nil,
                secondarySecret: nil,
                headerSecrets: headerSecrets,
                summary: "Configured Google Discovery Engine (:streamAssist) for project '\(proj)'"
            )
        }

        // Case C: Google Cloud Vertex AI (`*aiplatform.googleapis.com/...`)
        if host.contains("aiplatform.googleapis.com") {
            let parts = path.split(separator: "/").map(String.init)
            let proj = valueAfter("projects", in: parts) ?? gcpProjectHeader ?? ""
            let loc = valueAfter("locations", in: parts) ?? "asia-southeast1"
            var model = valueAfter("models", in: parts) ?? bodyModel ?? "gemini-2.5-pro"
            if let colon = model.firstIndex(of: ":") { model = String(model[..<colon]) }
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let urlKey = queryItems.first(where: { $0.name == "key" })?.value

            let profile = EnterpriseAPIProfile(
                name: "Vertex AI (\(proj.isEmpty ? loc : proj))",
                organizationId: proj,
                dialect: .vertexGemini,
                authScheme: urlKey != nil ? .apiKeyQueryOrBearer : .gcloudADC,
                gcpProjectId: proj,
                gcpLocation: loc,
                customHeaders: customHeaders,
                customModels: [model],
                defaultModel: model
            )
            return EnterpriseSmartPasteParsedOutput(
                profile: profile,
                primarySecret: urlKey ?? primarySecret,
                secondarySecret: nil,
                headerSecrets: headerSecrets,
                summary: "Configured Google Cloud Vertex AI (\(proj) • \(loc))"
            )
        }

        // Case D: Azure OpenAI / Microsoft AI Foundry (`*.openai.azure.com`, `*.cognitiveservices.azure.com`, `*.services.ai.azure.com`)
        if host.contains(".openai.azure.com") || host.contains(".cognitiveservices.azure.com") || host.contains(".services.ai.azure.com") {
            let resource = host.components(separatedBy: ".").first ?? "azure"
            let parts = path.split(separator: "/").map(String.init)
            let deployment = valueAfter("deployments", in: parts) ?? bodyModel ?? ""
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let apiVer = queryItems.first(where: { $0.name == "api-version" })?.value ?? "2024-10-21"

            let isV1OrFoundry = path.contains("/openai/v1") || host.contains(".services.ai.azure.com")
            let cleanBase: String = {
                if isV1OrFoundry {
                    return normalizeOpenAIBaseURL(rawURLStr)
                }
                return "https://\(host)"
            }()

            let scheme: EnterpriseAuthScheme = detectedScheme ?? (primarySecret != nil ? .apiKeyHeader : .azureEntraCLI)
            let profile = EnterpriseAPIProfile(
                name: "Azure OpenAI (\(resource))",
                dialect: .azureOpenAI,
                authScheme: scheme,
                baseURL: isV1OrFoundry ? cleanBase : "",
                azureResourceName: resource,
                azureDeploymentName: deployment,
                azureAPIVersion: apiVer,
                customHeaders: customHeaders,
                customModels: deployment.isEmpty ? [] : [deployment],
                defaultModel: deployment.isEmpty ? (bodyModel ?? "gpt-4o") : deployment
            )
            return EnterpriseSmartPasteParsedOutput(
                profile: profile,
                primarySecret: primarySecret,
                secondarySecret: nil,
                headerSecrets: headerSecrets,
                summary: "Configured Azure OpenAI (\(resource)\(deployment.isEmpty ? "" : " • \(deployment)"))"
            )
        }

        // Case E: AWS Bedrock (`bedrock-runtime.<region>.amazonaws.com`)
        if host.contains("bedrock-runtime.") && host.contains(".amazonaws.com") {
            let hostParts = host.components(separatedBy: ".")
            let region = (hostParts.count >= 3) ? hostParts[1] : "ap-southeast-1"
            let parts = path.split(separator: "/").map(String.init)
            let rawModel = valueAfter("model", in: parts)?.removingPercentEncoding ?? bodyModel ?? "apac.anthropic.claude-sonnet-4-20250514-v1:0"
            let scheme: EnterpriseAuthScheme = (primarySecret?.hasPrefix("ABSK") == true || detectedScheme == .awsBedrockAPIKey)
                ? .awsBedrockAPIKey
                : .awsSigV4Profile

            let profile = EnterpriseAPIProfile(
                name: "AWS Bedrock (\(region))",
                dialect: .awsBedrock,
                authScheme: scheme,
                awsRegion: region,
                customHeaders: customHeaders,
                customModels: [rawModel],
                defaultModel: rawModel
            )
            return EnterpriseSmartPasteParsedOutput(
                profile: profile,
                primarySecret: primarySecret,
                secondarySecret: nil,
                headerSecrets: headerSecrets,
                summary: "Configured AWS Bedrock (\(region) • \(rawModel))"
            )
        }

        // Case F: Anthropic Messages endpoint (`/v1/messages` or `/messages`)
        if path.hasSuffix("/messages") || host.contains("anthropic.com") {
            let cleanBase = normalizeAnthropicBaseURL(rawURLStr)
            let profile = EnterpriseAPIProfile(
                name: hostDisplayName(from: cleanBase, fallback: "Anthropic Enterprise"),
                dialect: .anthropicGateway,
                authScheme: detectedScheme ?? .xApiKeyHeader,
                baseURL: cleanBase,
                customHeaders: customHeaders,
                customModels: bodyModel.map { [$0] } ?? [],
                defaultModel: bodyModel ?? "claude-sonnet-4-20250514"
            )
            return EnterpriseSmartPasteParsedOutput(
                profile: profile,
                primarySecret: primarySecret,
                secondarySecret: nil,
                headerSecrets: headerSecrets,
                summary: "Configured Anthropic Enterprise Endpoint (\(cleanBase))"
            )
        }

        // Case G: Default OpenAI-compatible Enterprise Gateway (LiteLLM / Kong / Apigee / Cloudflare / vLLM)
        let cleanBase = normalizeOpenAIBaseURL(rawURLStr)
        let defaultScheme: EnterpriseAuthScheme = detectedScheme
            ?? ((primarySecret == nil && !customHeaders.isEmpty) ? .customHeadersOnly : .bearerToken)
        let profile = EnterpriseAPIProfile(
            name: hostDisplayName(from: cleanBase, fallback: "Enterprise AI Gateway"),
            dialect: .openaiGateway,
            authScheme: defaultScheme,
            baseURL: cleanBase,
            customHeaders: customHeaders,
            customModels: bodyModel.map { [$0] } ?? [],
            defaultModel: bodyModel ?? "gpt-4.1"
        )
        return EnterpriseSmartPasteParsedOutput(
            profile: profile,
            primarySecret: primarySecret,
            secondarySecret: nil,
            headerSecrets: headerSecrets,
            summary: "Configured Enterprise AI Gateway (\(cleanBase))"
        )
    }

    // MARK: - Helpers

    private static func valueAfter(_ segment: String, in parts: [String]) -> String? {
        guard let idx = parts.firstIndex(of: segment), idx + 1 < parts.count else { return nil }
        return parts[idx + 1]
    }

    public static func normalizeOpenAIBaseURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        while s.hasSuffix("/") { s.removeLast() }
        for suffix in ["/chat/completions", "/completions", "/responses", "/models"] {
            if s.lowercased().hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count))
            }
        }
        while s.hasSuffix("/") { s.removeLast() }
        if let url = URL(string: s), (url.path.isEmpty || url.path == "/") {
            s += "/v1"
        }
        return s
    }

    public static func normalizeAnthropicBaseURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        while s.hasSuffix("/") { s.removeLast() }
        if s.lowercased().hasSuffix("/messages") {
            s = String(s.dropLast("/messages".count))
        }
        while s.hasSuffix("/") { s.removeLast() }
        if let url = URL(string: s), (url.path.isEmpty || url.path == "/") {
            s += "/v1"
        }
        return s
    }

    private static func hostDisplayName(from urlString: String, fallback: String) -> String {
        guard let host = URL(string: urlString)?.host, !host.isEmpty else { return fallback }
        return "Gateway (\(host))"
    }

    public static func encodeBase64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decodeBase64URL(_ str: String) -> Data? {
        var b64 = str.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
        return Data(base64Encoded: b64)
    }
}

// MARK: - Pure-Swift AWS SigV4 Signer (CryptoKit)

public enum EnterpriseAWSSigV4Signer {
    public struct Credentials {
        public let accessKeyId: String
        public let secretAccessKey: String
        public let sessionToken: String?
    }

    public static func sign(
        request: inout URLRequest,
        bodyData: Data,
        credentials: Credentials,
        region: String,
        service: String = "bedrock"
    ) {
        guard let url = request.url, let host = url.host else { return }
        let now = Date()
        let amzFormatter = DateFormatter()
        amzFormatter.locale = Locale(identifier: "en_US_POSIX")
        amzFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        amzFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = amzFormatter.string(from: now)

        let dateStamp = String(amzDate.prefix(8))
        let payloadHash = sha256Hex(bodyData)

        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        request.setValue(payloadHash, forHTTPHeaderField: "X-Amz-Content-Sha256")
        if let token = credentials.sessionToken, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Amz-Security-Token")
        }

        // Build canonical URI (AWS requires RFC3986 encoding of each path segment; Bedrock model colons are %3A)
        let canonicalURI: String = {
            let rawPath = url.path.isEmpty ? "/" : url.path
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            let encodedSegments = rawPath.split(separator: "/", omittingEmptySubsequences: false).map { seg in
                String(seg).addingPercentEncoding(withAllowedCharacters: allowed) ?? String(seg)
            }
            let joined = encodedSegments.joined(separator: "/")
            return joined.hasPrefix("/") ? joined : "/" + joined
        }()

        let canonicalQuery: String = {
            guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let items = comps.queryItems, !items.isEmpty else { return "" }
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            var pairs: [(String, String)] = []
            pairs.reserveCapacity(items.count)
            for item in items {
                let k: String = item.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? item.name
                let rawVal: String = item.value ?? ""
                let v: String = rawVal.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                pairs.append((k, v))
            }
            pairs.sort { lhs, rhs in
                if lhs.0 == rhs.0 { return lhs.1 < rhs.1 }
                return lhs.0 < rhs.0
            }
            return pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        }()

        var signHeaders: [(String, String)] = [
            ("host", host),
            ("x-amz-content-sha256", payloadHash),
            ("x-amz-date", amzDate)
        ]
        if let ct = request.value(forHTTPHeaderField: "Content-Type"), !ct.isEmpty {
            signHeaders.append(("content-type", ct.trimmingCharacters(in: .whitespaces)))
        }
        if let token = credentials.sessionToken, !token.isEmpty {
            signHeaders.append(("x-amz-security-token", token.trimmingCharacters(in: .whitespaces)))
        }
        signHeaders.sort { $0.0 < $1.0 }

        let canonicalHeaders = signHeaders.map { "\($0.0):\($0.1)\n" }.joined()
        let signedHeaders = signHeaders.map(\.0).joined(separator: ";")
        let method = request.httpMethod ?? "POST"

        let canonicalRequest = [
            method,
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        let kSecret = Data(("AWS4" + credentials.secretAccessKey).utf8)
        let kDate = hmacSHA256(key: kSecret, data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        let signature = hmacSHA256(key: kSigning, data: Data(stringToSign.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        let authHeader = "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmacSHA256(key: Data, data: Data) -> Data {
        let symKey = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: symKey)
        return Data(mac)
    }
}

// MARK: - EnterpriseAIAuthService Multi-Profile & CLI SSO Extensions

extension EnterpriseAIAuthService {

    private static let profilesDefaultsKey = "enterprise_api_profiles_v1"
    private static let activeProfileDefaultsKey = "enterprise_active_profile_id_v1"

    private func primarySecretAccount(for profileId: String) -> String {
        "dotmini.enterprise.profile.\(profileId).primary"
    }

    private func secondarySecretAccount(for profileId: String) -> String {
        "dotmini.enterprise.profile.\(profileId).secondary"
    }

    private func headerSecretAccount(profileId: String, headerId: String) -> String {
        "dotmini.enterprise.profile.\(profileId).hdr.\(headerId)"
    }

    // MARK: - Keychain Accessors per Profile

    public func readPrimarySecret(for profileId: String) -> String {
        KeychainManager.shared.readIntegrationSecret(account: primarySecretAccount(for: profileId)) ?? ""
    }

    public func savePrimarySecret(_ secret: String, for profileId: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainManager.shared.deleteIntegrationSecret(account: primarySecretAccount(for: profileId))
        } else {
            _ = KeychainManager.shared.saveIntegrationSecret(trimmed, account: primarySecretAccount(for: profileId))
        }
    }

    public func readSecondarySecret(for profileId: String) -> String {
        KeychainManager.shared.readIntegrationSecret(account: secondarySecretAccount(for: profileId)) ?? ""
    }

    public func saveSecondarySecret(_ secret: String, for profileId: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainManager.shared.deleteIntegrationSecret(account: secondarySecretAccount(for: profileId))
        } else {
            _ = KeychainManager.shared.saveIntegrationSecret(trimmed, account: secondarySecretAccount(for: profileId))
        }
    }

    public func readHeaderSecret(profileId: String, headerId: String) -> String {
        KeychainManager.shared.readIntegrationSecret(account: headerSecretAccount(profileId: profileId, headerId: headerId)) ?? ""
    }

    public func saveHeaderSecret(_ secret: String, profileId: String, headerId: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainManager.shared.deleteIntegrationSecret(account: headerSecretAccount(profileId: profileId, headerId: headerId))
        } else {
            _ = KeychainManager.shared.saveIntegrationSecret(trimmed, account: headerSecretAccount(profileId: profileId, headerId: headerId))
        }
    }

    // MARK: - Persistence & Legacy Migration

    public func loadProfilesFromDiskOrMigrate() {
        let std = UserDefaults.standard
        if let data = std.data(forKey: Self.profilesDefaultsKey),
           let decoded = try? JSONDecoder().decode([EnterpriseAPIProfile].self, from: data),
           !decoded.isEmpty {
            self.profiles = decoded
            let savedActive = std.string(forKey: Self.activeProfileDefaultsKey) ?? ""
            if decoded.contains(where: { $0.id == savedActive }) {
                self.activeProfileID = savedActive
            } else {
                self.activeProfileID = decoded[0].id
            }
            return
        }

        // Migrate any existing legacy single-mode settings into initial profiles
        var initial: [EnterpriseAPIProfile] = []
        if !vertexProjectId.isEmpty || mode == .geminiVertex {
            let p = EnterpriseAPIProfile(
                name: vertexProjectId.isEmpty ? "Google Cloud Vertex AI" : "Vertex AI (\(vertexProjectId))",
                organizationId: organizationId,
                dialect: .vertexGemini,
                authScheme: vertexAuthMethod == .apiKey ? .apiKeyQueryOrBearer : (vertexAuthMethod == .serviceAccountJSON ? .serviceAccountJSON : .gcloudADC),
                gcpProjectId: vertexProjectId,
                gcpLocation: vertexLocation,
                defaultModel: "gemini-2.5-pro",
                enforceZDR: zeroDataRetention,
                enforceDLP: localDLPRedaction
            )
            initial.append(p)
            if !vertexAPIKey.isEmpty { savePrimarySecret(vertexAPIKey, for: p.id) }
            if !vertexServiceAccountJSON.isEmpty { saveSecondarySecret(vertexServiceAccountJSON, for: p.id) }
        }
        if !customGatewayBaseURL.isEmpty || mode == .customGateway {
            let p = EnterpriseAPIProfile(
                name: "Corporate AI Gateway",
                organizationId: organizationId,
                dialect: .openaiGateway,
                authScheme: .bearerToken,
                baseURL: EnterpriseSmartPasteParser.normalizeOpenAIBaseURL(customGatewayBaseURL.isEmpty ? "https://llm-gateway.corp.internal/v1" : customGatewayBaseURL),
                defaultModel: "gpt-4.1",
                enforceZDR: zeroDataRetention,
                enforceDLP: localDLPRedaction
            )
            initial.append(p)
            if !customGatewayAPIKey.isEmpty { savePrimarySecret(customGatewayAPIKey, for: p.id) }
        }
        if mode == .dotminiEnterprise || !dotminiEnterpriseKey.isEmpty {
            let p = EnterpriseAPIProfile(
                name: "Dotmini Cloud Enterprise",
                organizationId: organizationId,
                dialect: .dotminiEnterprise,
                authScheme: .bearerToken,
                baseURL: dotminiEnterpriseURL,
                defaultModel: "omni-o1x-pro",
                enforceZDR: zeroDataRetention,
                enforceDLP: localDLPRedaction
            )
            initial.append(p)
            if !dotminiEnterpriseKey.isEmpty { savePrimarySecret(dotminiEnterpriseKey, for: p.id) }
        }
        if initial.isEmpty {
            initial.append(EnterpriseAPIProfile(
                name: "Google Cloud Vertex AI",
                dialect: .vertexGemini,
                authScheme: .gcloudADC,
                gcpLocation: "asia-southeast1",
                defaultModel: "gemini-2.5-pro"
            ))
        }
        self.profiles = initial
        self.activeProfileID = initial[0].id
        persistProfilesToDisk()
    }

    public func persistProfilesToDisk() {
        // Strip accidental inline values from secret headers before writing to UserDefaults
        let sanitized = profiles.map { prof -> EnterpriseAPIProfile in
            var copy = prof
            copy.customHeaders = prof.customHeaders.map { hdr in
                var h = hdr
                if h.isSecret && !h.value.isEmpty {
                    saveHeaderSecret(h.value, profileId: prof.id, headerId: h.id)
                    h.value = ""
                }
                return h
            }
            return copy
        }
        if let data = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(data, forKey: Self.profilesDefaultsKey)
        }
        UserDefaults.standard.set(activeProfileID, forKey: Self.activeProfileDefaultsKey)
        syncLegacyFieldsFromActiveProfile()
    }

    public var activeProfile: EnterpriseAPIProfile? {
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles.first
    }

    public func upsertProfile(_ profile: EnterpriseAPIProfile, makeActive: Bool = true) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        if makeActive {
            activeProfileID = profile.id
        }
        persistProfilesToDisk()
    }

    public func deleteProfile(id: String) {
        if let target = profiles.first(where: { $0.id == id }) {
            savePrimarySecret("", for: id)
            saveSecondarySecret("", for: id)
            for hdr in target.customHeaders {
                saveHeaderSecret("", profileId: id, headerId: hdr.id)
            }
        }
        profiles.removeAll { $0.id == id }
        if profiles.isEmpty {
            let fallback = EnterpriseAPIProfile(
                name: "Enterprise AI Gateway",
                dialect: .openaiGateway,
                authScheme: .bearerToken
            )
            profiles = [fallback]
        }
        if !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = profiles[0].id
        }
        persistProfilesToDisk()
    }

    public func createPresetProfile(dialect: EnterpriseProviderDialect) -> EnterpriseAPIProfile {
        var p = EnterpriseAPIProfile(
            name: dialect.shortTitle,
            dialect: dialect,
            authScheme: dialect.supportedAuthSchemes.first ?? .bearerToken
        )
        switch dialect {
        case .vertexGemini:
            if !cliStatus.gcloudProject.isEmpty { p.gcpProjectId = cliStatus.gcloudProject }
            p.name = p.gcpProjectId.isEmpty ? "Google Vertex AI" : "Vertex AI (\(p.gcpProjectId))"
        case .geminiEnterpriseAgentspace:
            if !cliStatus.gcloudProject.isEmpty { p.gcpProjectId = cliStatus.gcloudProject }
            p.gcpLocation = "global"
            p.name = "Gemini Enterprise (Agentspace)"
        case .azureOpenAI:
            p.authScheme = cliStatus.isAzureReady ? .azureEntraCLI : .apiKeyHeader
            p.name = "Azure OpenAI"
        case .awsBedrock:
            p.awsRegion = cliStatus.awsDefaultRegion
            if let firstProf = cliStatus.awsProfiles.first {
                p.awsProfileName = firstProf
                p.authScheme = .awsSigV4Profile
            } else {
                p.authScheme = .awsBedrockAPIKey
            }
            p.name = "AWS Bedrock (\(p.awsRegion))"
        case .openaiGateway:
            p.baseURL = "https://llm-gateway.corp.internal/v1"
            p.name = "Enterprise AI Gateway"
        case .anthropicGateway:
            p.baseURL = "https://api.anthropic.com/v1"
            p.name = "Anthropic Enterprise"
        case .dotminiEnterprise:
            p.baseURL = "https://api.dotmini.net/v1"
            p.name = "Dotmini Sovereign Cloud"
        }
        upsertProfile(p, makeActive: true)
        return p
    }

    public func activateEnterpriseSelection(profileId: String, modelId: String? = nil) {
        guard let prof = profiles.first(where: { $0.id == profileId }) else { return }
        activeProfileID = prof.id
        let chosenModel = modelId ?? (prof.defaultModel.isEmpty ? (prof.availableModels.first ?? "gpt-4o") : prof.defaultModel)
        if let idx = profiles.firstIndex(where: { $0.id == prof.id }), modelId != nil {
            profiles[idx].defaultModel = chosenModel
        }
        persistProfilesToDisk()

        UserDefaults.standard.set("enterprise", forKey: "aiKeyMode")
        ACPHostService.shared.activeAgentId = nil
        AppState.shared?.aiProvider = prof.dialect.brandIconKey
        AppState.shared?.aiModel = chosenModel
        AppState.shared?.saveSettings()
    }

    private func syncLegacyFieldsFromActiveProfile() {
        guard let prof = activeProfile else { return }
        if !prof.organizationId.isEmpty { organizationId = prof.organizationId }
        switch prof.dialect {
        case .vertexGemini, .geminiEnterpriseAgentspace:
            if mode == .disabled { mode = .geminiVertex }
            if !prof.gcpProjectId.isEmpty { vertexProjectId = prof.gcpProjectId }
            if !prof.gcpLocation.isEmpty { vertexLocation = prof.gcpLocation }
        case .dotminiEnterprise:
            if mode == .disabled { mode = .dotminiEnterprise }
            if !prof.baseURL.isEmpty { dotminiEnterpriseURL = prof.baseURL }
        case .openaiGateway, .azureOpenAI, .awsBedrock, .anthropicGateway:
            if mode == .disabled { mode = .customGateway }
            if !prof.baseURL.isEmpty { customGatewayBaseURL = prof.baseURL }
        }
    }

    // MARK: - 1-Click Smart Paste Application

    @discardableResult
    public func applySmartPaste(_ rawText: String) -> EnterpriseSmartPasteParsedOutput? {
        guard let parsed = EnterpriseSmartPasteParser.parse(rawText) else {
            statusMessage = "Could not detect a valid Enterprise URL, cURL command, .env block, or Service Account JSON."
            return nil
        }
        var prof = parsed.profile
        if (prof.dialect == .vertexGemini || prof.dialect == .geminiEnterpriseAgentspace),
           prof.gcpProjectId.isEmpty,
           !cliStatus.gcloudProject.isEmpty {
            prof.gcpProjectId = cliStatus.gcloudProject
        }
        upsertProfile(prof, makeActive: true)
        if let primary = parsed.primarySecret, !primary.isEmpty {
            savePrimarySecret(primary, for: prof.id)
        }
        if let secondary = parsed.secondarySecret, !secondary.isEmpty {
            saveSecondarySecret(secondary, for: prof.id)
            if prof.dialect == .vertexGemini && prof.authScheme == .serviceAccountJSON {
                _ = saveVertexServiceAccountJSON(secondary)
            }
        }
        for (hdrId, secretVal) in parsed.headerSecrets {
            saveHeaderSecret(secretVal, profileId: prof.id, headerId: hdrId)
        }
        activateEnterpriseSelection(profileId: prof.id, modelId: prof.defaultModel)
        statusMessage = "✓ \(parsed.summary)"
        return parsed
    }

    // MARK: - 1-Click Team Config Export & Import

    public func buildTeamShareBundle(for profileId: String) -> EnterpriseTeamShareBundle? {
        guard var prof = profiles.first(where: { $0.id == profileId }) else { return nil }
        prof.id = UUID().uuidString
        prof.isVerified = false
        prof.lastVerifiedAt = nil
        prof.lastStatusMessage = ""
        prof.awsAccessKeyId = "" // Never export personal IAM access keys
        prof.customHeaders = prof.customHeaders.map { hdr in
            if hdr.isSecret {
                return EnterpriseHeaderItem(
                    key: hdr.key,
                    value: "",
                    isSecret: true,
                    requiresUserSecret: true
                )
            }
            return hdr
        }
        return EnterpriseTeamShareBundle(profile: prof, workspacePolicy: activeWorkspacePolicy)
    }

    public func exportTeamShareLink(for profileId: String) -> String? {
        guard let bundle = buildTeamShareBundle(for: profileId) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(bundle) else { return nil }
        let b64 = EnterpriseSmartPasteParser.encodeBase64URL(data)
        return "microcode://enterprise?config=\(b64)"
    }

    public func exportTeamShareFileWithSavePanel(for profileId: String) -> URL? {
        guard let bundle = buildTeamShareBundle(for: profileId) else { return nil }
        let panel = NSSavePanel()
        let slug = bundle.profile.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        panel.nameFieldStringValue = "\(slug.isEmpty ? "company" : slug).microcode-enterprise.json"
        panel.canCreateDirectories = true
        panel.title = "Export 1-Click Team Enterprise Setup"
        panel.message = "Secrets and personal API keys are automatically stripped. Share this file with teammates to configure MicroCode in 1 click."
        guard panel.runModal() == .OK, let dest = panel.url else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(bundle) {
            try? data.write(to: dest, options: .atomic)
            statusMessage = "✓ Exported Team Enterprise Setup to \(dest.lastPathComponent)"
            return dest
        }
        return nil
    }

    @discardableResult
    public func importTeamShareFile(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8),
              let parsed = applySmartPaste(raw) else {
            statusMessage = "Failed to import Enterprise Setup from \(url.lastPathComponent)."
            return false
        }
        statusMessage = "✓ \(parsed.summary)"
        return true
    }

    // MARK: - Zero-Key Local CLI SSO Auto-Detection (gcloud / az / aws)

    public func detectLocalCLIs() async {
        cliStatus.isScanning = true
        let detected = await Task.detached(priority: .utility) { () -> EnterpriseCLIDetectionStatus in
            var status = EnterpriseCLIDetectionStatus()

            func findBin(_ name: String, extraPaths: [String]) -> String? {
                for p in extraPaths where FileManager.default.isExecutableFile(atPath: p) {
                    return p
                }
                let stdDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
                for d in stdDirs {
                    let full = "\(d)/\(name)"
                    if FileManager.default.isExecutableFile(atPath: full) { return full }
                }
                return nil
            }

            func runQuick(_ path: String, _ args: [String], timeout: TimeInterval = 3.5) -> String {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: path)
                proc.arguments = args
                var env = ProcessInfo.processInfo.environment
                env["CLOUDSDK_CORE_DISABLE_PROMPTS"] = "1"
                proc.environment = env
                let out = Pipe()
                proc.standardOutput = out
                proc.standardError = Pipe()
                do {
                    try proc.run()
                } catch {
                    return ""
                }
                let deadline = Date().addingTimeInterval(timeout)
                while proc.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if proc.isRunning {
                    proc.terminate()
                    return ""
                }
                guard proc.terminationStatus == 0 else { return "" }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let home = FileManager.default.homeDirectoryForCurrentUser.path
            status.hasGcloudADCFile = FileManager.default.fileExists(atPath: "\(home)/.config/gcloud/application_default_credentials.json")

            if let gcloud = findBin("gcloud", extraPaths: [
                "\(home)/google-cloud-sdk/bin/gcloud",
                "/opt/homebrew/share/google-cloud-sdk/bin/gcloud",
                "/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin/gcloud"
            ]) {
                status.gcloudPath = gcloud
                let acct = runQuick(gcloud, ["config", "get-value", "account", "--quiet"])
                if acct != "(unset)" { status.gcloudAccount = acct }
                let proj = runQuick(gcloud, ["config", "get-value", "project", "--quiet"])
                if proj != "(unset)" { status.gcloudProject = proj }
            }

            if let az = findBin("az", extraPaths: []) {
                status.azPath = az
                let rawJSON = runQuick(az, ["account", "show", "-o", "json"], timeout: 4.0)
                if let data = rawJSON.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let user = obj["user"] as? [String: Any], let name = user["name"] as? String {
                        status.azAccount = name
                    }
                    if let tid = obj["tenantId"] as? String {
                        status.azTenantId = tid
                    }
                }
            }

            status.awsPath = findBin("aws", extraPaths: [])
            var profilesSet = Set<String>()
            for file in ["\(home)/.aws/config", "\(home)/.aws/credentials"] {
                if let content = try? String(contentsOfFile: file, encoding: .utf8) {
                    for line in content.components(separatedBy: .newlines) {
                        let t = line.trimmingCharacters(in: .whitespaces)
                        if t.hasPrefix("[") && t.hasSuffix("]") {
                            var inner = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                            if inner.hasPrefix("profile ") {
                                inner = String(inner.dropFirst("profile ".count)).trimmingCharacters(in: .whitespaces)
                            }
                            if !inner.isEmpty && !inner.hasPrefix("sso-session") {
                                profilesSet.insert(inner)
                            }
                        } else if t.lowercased().hasPrefix("region"),
                                  let eq = t.firstIndex(of: "=") {
                            let r = String(t[t.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                            if !r.isEmpty { status.awsDefaultRegion = r }
                        }
                    }
                }
            }
            status.awsProfiles = profilesSet.sorted()
            return status
        }.value

        var finished = detected
        finished.isScanning = false
        self.cliStatus = finished

        // Auto-fill GCP Project ID on active Vertex/Agentspace profile if blank
        if let idx = profiles.firstIndex(where: { $0.id == activeProfileID }),
           (profiles[idx].dialect == .vertexGemini || profiles[idx].dialect == .geminiEnterpriseAgentspace),
           profiles[idx].gcpProjectId.isEmpty,
           !finished.gcloudProject.isEmpty {
            profiles[idx].gcpProjectId = finished.gcloudProject
            persistProfilesToDisk()
        }
    }

    public func triggerInteractiveCLILogin(command: String) {
        let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
    }

    // MARK: - Token & Credential Resolvers for Azure CLI, Vertex/GCP, and AWS

    private static var cachedAzureToken: (token: String, expiresAt: Date)?

    public func resolveAzureEntraToken() async throws -> String {
        if let cached = Self.cachedAzureToken, Date().addingTimeInterval(90) < cached.expiresAt {
            return cached.token
        }
        let azBin = cliStatus.azPath ?? "/opt/homebrew/bin/az"
        guard FileManager.default.isExecutableFile(atPath: azBin) else {
            throw NSError(domain: "EnterpriseAI", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Azure CLI (`az`) not found. Install Azure CLI (`brew install azure-cli`) and run `az login`, or switch authentication to API Key."
            ])
        }
        let token = try await Task.detached(priority: .userInitiated) { () throws -> String in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: azBin)
            proc.arguments = ["account", "get-access-token", "--resource", "https://cognitiveservices.azure.com", "--query", "accessToken", "-o", "tsv"]
            let out = Pipe()
            let err = Pipe()
            proc.standardOutput = out
            proc.standardError = err
            try proc.run()
            proc.waitUntilExit()
            let stdout = (String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard proc.terminationStatus == 0, !stdout.isEmpty else {
                let errMsg = (String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                throw NSError(domain: "EnterpriseAI", code: 401, userInfo: [
                    NSLocalizedDescriptionKey: "Azure SSO token failed. Run `az login` first. \(errMsg)"
                ])
            }
            return stdout
        }.value
        Self.cachedAzureToken = (token, Date().addingTimeInterval(1800))
        return token
    }

    public func resolveGCPBearerToken(for profile: EnterpriseAPIProfile) async throws -> String? {
        switch profile.authScheme {
        case .apiKeyQueryOrBearer:
            let k = readPrimarySecret(for: profile.id)
            guard !k.isEmpty else {
                throw NSError(domain: "EnterpriseAI", code: 401, userInfo: [NSLocalizedDescriptionKey: "Vertex AI API Key is missing for profile '\(profile.name)'."])
            }
            return nil
        case .serviceAccountJSON:
            let sa = readSecondarySecret(for: profile.id)
            if !sa.isEmpty && sa != vertexServiceAccountJSON {
                _ = saveVertexServiceAccountJSON(sa)
            }
            let savedMethod = vertexAuthMethod
            vertexAuthMethod = .serviceAccountJSON
            defer { vertexAuthMethod = savedMethod }
            return try await resolveVertexAuthorizationHeader()
        default:
            let savedMethod = vertexAuthMethod
            vertexAuthMethod = .gcloudADC
            defer { vertexAuthMethod = savedMethod }
            return try await resolveVertexAuthorizationHeader()
        }
    }

    public func resolveAWSSigV4Credentials(for profile: EnterpriseAPIProfile) async throws -> EnterpriseAWSSigV4Signer.Credentials {
        if profile.authScheme == .awsSigV4AccessKey {
            let ak = profile.awsAccessKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
            let sk = readPrimarySecret(for: profile.id)
            let st = readSecondarySecret(for: profile.id)
            guard !ak.isEmpty, !sk.isEmpty else {
                throw NSError(domain: "EnterpriseAI", code: 401, userInfo: [
                    NSLocalizedDescriptionKey: "AWS Access Key ID and Secret Access Key are required."
                ])
            }
            return .init(accessKeyId: ak, secretAccessKey: sk, sessionToken: st.isEmpty ? nil : st)
        }

        let profName = profile.awsProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "default"
            : profile.awsProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let awsBin = cliStatus.awsPath

        return try await Task.detached(priority: .userInitiated) {
            // 1. Prefer `aws configure export-credentials` (handles AWS SSO, AssumeRole, and static profiles seamlessly!)
            if let awsBin, FileManager.default.isExecutableFile(atPath: awsBin) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: awsBin)
                proc.arguments = ["configure", "export-credentials", "--profile", profName, "--format", "process"]
                let out = Pipe()
                proc.standardOutput = out
                proc.standardError = Pipe()
                if (try? proc.run()) != nil {
                    proc.waitUntilExit()
                    if proc.terminationStatus == 0,
                       let json = try? JSONSerialization.jsonObject(with: out.fileHandleForReading.readDataToEndOfFile()) as? [String: Any],
                       let ak = json["AccessKeyId"] as? String,
                       let sk = json["SecretAccessKey"] as? String {
                        let st = json["SessionToken"] as? String
                        return EnterpriseAWSSigV4Signer.Credentials(accessKeyId: ak, secretAccessKey: sk, sessionToken: st)
                    }
                }
            }

            // 2. Fallback: Parse ~/.aws/credentials directly
            let credsPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.aws/credentials"
            if let text = try? String(contentsOfFile: credsPath, encoding: .utf8) {
                var inSection = false
                var ak = ""
                var sk = ""
                var st: String? = nil
                for raw in text.components(separatedBy: .newlines) {
                    let line = raw.trimmingCharacters(in: .whitespaces)
                    if line.hasPrefix("[") && line.hasSuffix("]") {
                        let sec = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                        inSection = (sec == profName)
                        continue
                    }
                    guard inSection, let eq = line.firstIndex(of: "=") else { continue }
                    let k = String(line[..<eq]).trimmingCharacters(in: .whitespaces).lowercased()
                    let v = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                    if k == "aws_access_key_id" { ak = v }
                    else if k == "aws_secret_access_key" { sk = v }
                    else if k == "aws_session_token" { st = v }
                }
                if !ak.isEmpty && !sk.isEmpty {
                    return EnterpriseAWSSigV4Signer.Credentials(accessKeyId: ak, secretAccessKey: sk, sessionToken: st)
                }
            }

            throw NSError(domain: "EnterpriseAI", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "No active AWS credentials for profile '\(profName)'. Run `aws sso login --profile \(profName)` or paste a Bedrock API Key (ABSK…)."
            ])
        }.value
    }

    // MARK: - URLSession & Header Injection per Profile

    public func urlSession(for profile: EnterpriseAPIProfile) -> URLSession {
        let proxy = profile.proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proxy.isEmpty, let pURL = URL(string: proxy), let host = pURL.host else {
            return URLSession.shared
        }
        let cfg = URLSessionConfiguration.ephemeral
        let port = pURL.port ?? (pURL.scheme == "https" ? 443 : 8080)
        cfg.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: 1,
            kCFNetworkProxiesHTTPProxy as String: host,
            kCFNetworkProxiesHTTPPort as String: port,
            "HTTPSEnable": 1,
            "HTTPSProxy": host,
            "HTTPSPort": port
        ]
        return URLSession(configuration: cfg)
    }

    public func applyProfileHeaders(profile: EnterpriseAPIProfile, to request: inout URLRequest) {
        if profile.enforceZDR || zeroDataRetention {
            request.setValue("true", forHTTPHeaderField: "X-Dotmini-ZDR")
            request.setValue("no-store", forHTTPHeaderField: "X-Enterprise-Data-Retention")
        }
        if !profile.organizationId.isEmpty {
            request.setValue(profile.organizationId, forHTTPHeaderField: "X-Enterprise-Org")
        }
        for hdr in profile.customHeaders {
            let key = hdr.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            let val = hdr.isSecret
                ? readHeaderSecret(profileId: profile.id, headerId: hdr.id)
                : hdr.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !val.isEmpty {
                request.setValue(val, forHTTPHeaderField: key)
            }
        }
    }

    public func applyStandardGatewayAuth(profile: EnterpriseAPIProfile, to request: inout URLRequest) async throws {
        let secret = readPrimarySecret(for: profile.id)
        switch profile.authScheme {
        case .bearerToken, .awsBedrockAPIKey:
            if !secret.isEmpty {
                request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            } else if profile.dialect == .dotminiEnterprise,
                      let fallback = DotminiPlatformKeyService.shared.authorizationToken ?? SupabaseAuthService.shared.accessToken {
                request.setValue("Bearer \(fallback)", forHTTPHeaderField: "Authorization")
            }
        case .apiKeyHeader:
            if !secret.isEmpty {
                request.setValue(secret, forHTTPHeaderField: "api-key")
            }
        case .xApiKeyHeader:
            if !secret.isEmpty {
                request.setValue(secret, forHTTPHeaderField: "x-api-key")
            }
        case .ocpApimKey:
            if !secret.isEmpty {
                request.setValue(secret, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
            }
        case .azureEntraCLI:
            let token = try await resolveAzureEntraToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .customHeadersOnly:
            break
        default:
            if !secret.isEmpty {
                request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            }
        }
        applyProfileHeaders(profile: profile, to: &request)
    }

    // MARK: - Endpoint Builders

    public func buildAzureChatCompletionsURL(profile: EnterpriseAPIProfile, modelOrDeployment: String) -> URL? {
        let apiVer = profile.azureAPIVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "2024-10-21"
            : profile.azureAPIVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !profile.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let clean = EnterpriseSmartPasteParser.normalizeOpenAIBaseURL(profile.baseURL)
            if clean.contains("/openai/v1") {
                return URL(string: "\(clean)/chat/completions")
            }
            let sep = clean.contains("?") ? "&" : "?"
            return URL(string: "\(clean)/chat/completions\(sep)api-version=\(apiVer)")
        }
        let res = profile.azureResourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let dep = !profile.azureDeploymentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? profile.azureDeploymentName.trimmingCharacters(in: .whitespacesAndNewlines)
            : modelOrDeployment
        guard !res.isEmpty, !dep.isEmpty else { return nil }
        return URL(string: "https://\(res).openai.azure.com/openai/deployments/\(dep)/chat/completions?api-version=\(apiVer)")
    }

    public func buildVertexEndpointURL(profile: EnterpriseAPIProfile, model: String, streaming: Bool) -> URL? {
        let proj = profile.gcpProjectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let loc = profile.gcpLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "asia-southeast1"
            : profile.gcpLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proj.isEmpty else { return nil }
        let host = (loc == "global")
            ? "https://aiplatform.googleapis.com"
            : "https://\(loc)-aiplatform.googleapis.com"

        var cleanModel = model
        for prefix in ["models/", "publishers/google/models/", "publishers/anthropic/models/"] {
            if cleanModel.hasPrefix(prefix) { cleanModel = String(cleanModel.dropFirst(prefix.count)) }
        }

        if cleanModel.lowercased().hasPrefix("claude-") {
            let action = streaming ? "streamRawPredict" : "rawPredict"
            return URL(string: "\(host)/v1/projects/\(proj)/locations/\(loc)/publishers/anthropic/models/\(cleanModel):\(action)")
        }

        let action = streaming ? "streamGenerateContent?alt=sse" : "generateContent"
        var urlStr = "\(host)/v1/projects/\(proj)/locations/\(loc)/publishers/google/models/\(cleanModel):\(action)"
        if profile.authScheme == .apiKeyQueryOrBearer {
            let key = readPrimarySecret(for: profile.id)
            if !key.isEmpty {
                let sep = urlStr.contains("?") ? "&" : "?"
                urlStr += "\(sep)key=\(key)"
            }
        }
        return URL(string: urlStr)
    }

    public func buildDiscoveryEngineStreamAssistURL(profile: EnterpriseAPIProfile) -> URL? {
        let proj = profile.gcpProjectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let loc = profile.gcpLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "global"
            : profile.gcpLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let col = profile.discoveryCollectionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "default_collection"
            : profile.discoveryCollectionId.trimmingCharacters(in: .whitespacesAndNewlines)
        let eng = profile.discoveryEngineId.trimmingCharacters(in: .whitespacesAndNewlines)
        let asst = profile.discoveryAssistantId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "default_assistant"
            : profile.discoveryAssistantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proj.isEmpty, !eng.isEmpty else { return nil }
        let host = (loc == "global")
            ? "https://discoveryengine.googleapis.com"
            : "https://\(loc)-discoveryengine.googleapis.com"
        return URL(string: "\(host)/v1/projects/\(proj)/locations/\(loc)/collections/\(col)/engines/\(eng)/assistants/\(asst):streamAssist")
    }

    public func buildBedrockConverseURL(profile: EnterpriseAPIProfile, modelId: String) -> URL? {
        let region = profile.awsRegion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "ap-southeast-1"
            : profile.awsRegion.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encodedModel = modelId.addingPercentEncoding(withAllowedCharacters: allowed) ?? modelId
        return URL(string: "https://bedrock-runtime.\(region).amazonaws.com/model/\(encodedModel)/converse")
    }

    // MARK: - Live Model Discovery & Connection Verification

    @discardableResult
    public func discoverModelsAndVerify(profileId: String) async -> Bool {
        guard var prof = profiles.first(where: { $0.id == profileId }) else { return false }
        isVerifying = true
        defer { isVerifying = false }

        let session = urlSession(for: prof)

        do {
            switch prof.dialect {
            case .openaiGateway, .dotminiEnterprise, .anthropicGateway:
                let rawBase = prof.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawBase.isEmpty else {
                    prof.isVerified = false
                    prof.lastStatusMessage = "Enter a valid Gateway Base URL."
                    upsertProfile(prof, makeActive: false)
                    statusMessage = prof.lastStatusMessage
                    return false
                }
                let cleanBase = prof.dialect == .anthropicGateway
                    ? EnterpriseSmartPasteParser.normalizeAnthropicBaseURL(rawBase)
                    : EnterpriseSmartPasteParser.normalizeOpenAIBaseURL(rawBase)
                prof.baseURL = cleanBase

                if let modelsURL = URL(string: "\(cleanBase)/models") {
                    var req = URLRequest(url: modelsURL, timeoutInterval: 14)
                    if prof.dialect == .anthropicGateway {
                        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    }
                    try await applyStandardGatewayAuth(profile: prof, to: &req)
                    let (data, resp) = try await session.data(for: req)
                    if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                        let ids = Self.parseModelIDs(from: data)
                        if !ids.isEmpty {
                            prof.discoveredModels = ids
                            if !ids.contains(prof.defaultModel), let first = ids.first {
                                prof.defaultModel = first
                            }
                        }
                        prof.isVerified = true
                        prof.lastVerifiedAt = Date()
                        prof.lastStatusMessage = "✓ Connected (\(ids.isEmpty ? "Auth OK" : "\(ids.count) models discovered"))"
                        upsertProfile(prof, makeActive: false)
                        statusMessage = prof.lastStatusMessage
                        return true
                    } else if let http = resp as? HTTPURLResponse, http.statusCode == 404 {
                        // Some corporate proxies disable GET /models and only expose POST /chat/completions or /messages
                        prof.isVerified = true
                        prof.lastVerifiedAt = Date()
                        prof.lastStatusMessage = "✓ Gateway reachable (/models disabled by proxy — enter deployment/model ID manually)"
                        upsertProfile(prof, makeActive: false)
                        statusMessage = prof.lastStatusMessage
                        return true
                    } else {
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                        let raw = String(data: data, encoding: .utf8) ?? ""
                        prof.isVerified = false
                        prof.lastStatusMessage = "HTTP \(code): \(String(raw.prefix(160)))"
                        upsertProfile(prof, makeActive: false)
                        statusMessage = prof.lastStatusMessage
                        return false
                    }
                }

            case .azureOpenAI:
                let testModel = !prof.azureDeploymentName.isEmpty ? prof.azureDeploymentName : prof.defaultModel
                guard let chatURL = buildAzureChatCompletionsURL(profile: prof, modelOrDeployment: testModel) else {
                    prof.isVerified = false
                    prof.lastStatusMessage = "Enter Azure Resource Name & Deployment Name (or paste full endpoint URL)."
                    upsertProfile(prof, makeActive: false)
                    statusMessage = prof.lastStatusMessage
                    return false
                }
                var req = URLRequest(url: chatURL, timeoutInterval: 15)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                try await applyStandardGatewayAuth(profile: prof, to: &req)
                let body: [String: Any] = [
                    "model": testModel,
                    "messages": [["role": "user", "content": "ping"]],
                    "max_tokens": 4
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    if !testModel.isEmpty && !prof.discoveredModels.contains(testModel) {
                        prof.discoveredModels = [testModel]
                    }
                    prof.isVerified = true
                    prof.lastVerifiedAt = Date()
                    prof.lastStatusMessage = "✓ Verified Azure OpenAI deployment '\(testModel)'"
                    upsertProfile(prof, makeActive: false)
                    statusMessage = prof.lastStatusMessage
                    return true
                } else {
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    let raw = String(data: data, encoding: .utf8) ?? ""
                    prof.isVerified = false
                    prof.lastStatusMessage = "Azure HTTP \(code): \(String(raw.prefix(180)))"
                    upsertProfile(prof, makeActive: false)
                    statusMessage = prof.lastStatusMessage
                    return false
                }

            case .vertexGemini:
                let testModel = prof.defaultModel.isEmpty ? "gemini-2.5-flash" : prof.defaultModel
                guard let url = buildVertexEndpointURL(profile: prof, model: testModel, streaming: false) else {
                    prof.isVerified = false
                    prof.lastStatusMessage = "Google Cloud Project ID is required."
                    upsertProfile(prof, makeActive: false)
                    statusMessage = prof.lastStatusMessage
                    return false
                }
                var req = URLRequest(url: url, timeoutInterval: 16)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let bearer = try await resolveGCPBearerToken(for: prof) {
                    req.setValue(bearer, forHTTPHeaderField: "Authorization")
                }
                req.setValue(prof.gcpProjectId, forHTTPHeaderField: "x-goog-user-project")
                applyProfileHeaders(profile: prof, to: &req)

                if testModel.lowercased().hasPrefix("claude-") {
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "anthropic_version": "vertex-2023-10-16",
                        "max_tokens": 8,
                        "messages": [["role": "user", "content": "ping"]]
                    ])
                } else {
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "contents": [["role": "user", "parts": [["text": "ping"]]]],
                        "generationConfig": ["maxOutputTokens": 4]
                    ])
                }
                let (data, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    if prof.discoveredModels.isEmpty {
                        prof.discoveredModels = EnterpriseProviderDialect.vertexGemini.fallbackModels
                    }
                    prof.isVerified = true
                    prof.lastVerifiedAt = Date()
                    prof.lastStatusMessage = "✓ Verified Vertex AI (\(prof.gcpProjectId) • \(prof.gcpLocation))"
                    upsertProfile(prof, makeActive: false)
                    statusMessage = prof.lastStatusMessage
                    return true
                } else {
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    let raw = String(data: data, encoding: .utf8) ?? ""
                    prof.isVerified = false
                    prof.lastStatusMessage = "Vertex HTTP \(code): \(String(raw.prefix(180)))"
                    upsertProfile(prof, makeActive: false)
                    statusMessage = prof.lastStatusMessage
                    return false
                }

            case .geminiEnterpriseAgentspace:
                guard let url = buildDiscoveryEngineStreamAssistURL(profile: prof) else {
                    prof.isVerified = false
                    prof.lastStatusMessage = "GCP Project ID and Discovery Engine / App ID are required."
                    upsertProfile(prof, makeActive: false)
                    statusMessage = prof.lastStatusMessage
                    return false
                }
                var req = URLRequest(url: url, timeoutInterval: 18)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let bearer = try await resolveGCPBearerToken(for: prof) {
                    req.setValue(bearer, forHTTPHeaderField: "Authorization")
                }
                req.setValue(prof.gcpProjectId, forHTTPHeaderField: "X-Goog-User-Project")
                applyProfileHeaders(profile: prof, to: &req)
                req.httpBody = try JSONSerialization.data(withJSONObject: [
                    "query": ["text": "ping"],
                    "session": "-"
                ])
                let (data, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    prof.discoveredModels = [prof.discoveryAssistantId.isEmpty ? "default_assistant" : prof.discoveryAssistantId]
                    prof.isVerified = true
                    prof.lastVerifiedAt = Date()
                    prof.lastStatusMessage = "✓ Verified Gemini Enterprise Agentspace (\(prof.discoveryEngineId))"
                    upsertProfile(prof, makeActive: false)
                    statusMessage = prof.lastStatusMessage
                    return true
                } else {
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    let raw = String(data: data, encoding: .utf8) ?? ""
                    prof.isVerified = false
                    prof.lastStatusMessage = "Agentspace HTTP \(code): \(String(raw.prefix(180)))"
                    upsertProfile(prof, makeActive: false)
                    statusMessage = prof.lastStatusMessage
                    return false
                }

            case .awsBedrock:
                let testModel = prof.defaultModel.isEmpty
                    ? "apac.anthropic.claude-3-7-sonnet-20250219-v1:0"
                    : prof.defaultModel
                guard let url = buildBedrockConverseURL(profile: prof, modelId: testModel) else {
                    prof.isVerified = false
                    prof.lastStatusMessage = "Invalid AWS Region or Bedrock Model ID."
                    upsertProfile(prof, makeActive: false)
                    statusMessage = prof.lastStatusMessage
                    return false
                }
                var req = URLRequest(url: url, timeoutInterval: 16)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let bodyObj: [String: Any] = [
                    "messages": [["role": "user", "content": [["text": "ping"]]]],
                    "inferenceConfig": ["maxTokens": 8]
                ]
                let bodyData = try JSONSerialization.data(withJSONObject: bodyObj)
                req.httpBody = bodyData
                applyProfileHeaders(profile: prof, to: &req)

                if prof.authScheme == .awsBedrockAPIKey {
                    let key = readPrimarySecret(for: prof.id)
                    guard !key.isEmpty else {
                        prof.isVerified = false
                        prof.lastStatusMessage = "Paste your Bedrock API Key (ABSK…)."
                        upsertProfile(prof, makeActive: false)
                        statusMessage = prof.lastStatusMessage
                        return false
                    }
                    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                } else {
                    let creds = try await resolveAWSSigV4Credentials(for: prof)
                    EnterpriseAWSSigV4Signer.sign(
                        request: &req,
                        bodyData: bodyData,
                        credentials: creds,
                        region: prof.awsRegion,
                        service: "bedrock"
                    )
                }

                let (data, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    if prof.discoveredModels.isEmpty {
                        prof.discoveredModels = EnterpriseProviderDialect.awsBedrock.fallbackModels
                    }
                    prof.isVerified = true
                    prof.lastVerifiedAt = Date()
                    prof.lastStatusMessage = "✓ Verified AWS Bedrock (\(prof.awsRegion) • \(testModel))"
                    upsertProfile(prof, makeActive: false)
                    statusMessage = prof.lastStatusMessage
                    return true
                } else {
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    let raw = String(data: data, encoding: .utf8) ?? ""
                    prof.isVerified = false
                    prof.lastStatusMessage = "Bedrock HTTP \(code): \(String(raw.prefix(180)))"
                    upsertProfile(prof, makeActive: false)
                    statusMessage = prof.lastStatusMessage
                    return false
                }
            }
        } catch {
            prof.isVerified = false
            prof.lastStatusMessage = "Connection failed: \(error.localizedDescription)"
            upsertProfile(prof, makeActive: false)
            statusMessage = prof.lastStatusMessage
            return false
        }
        return false
    }

    private static func parseModelIDs(from data: Data) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var ids: [String] = []
        if let dict = obj as? [String: Any] {
            if let arr = dict["data"] as? [[String: Any]] {
                ids = arr.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) }
            } else if let arr = dict["models"] as? [[String: Any]] {
                ids = arr.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) }
            }
        } else if let arr = obj as? [[String: Any]] {
            ids = arr.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) }
        }
        return ids.filter { !$0.isEmpty }
    }
}
