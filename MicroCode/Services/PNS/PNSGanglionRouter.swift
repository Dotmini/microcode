//
//  PNSGanglionRouter.swift
//  MicroCode
//
//  PNS Efferent MCP Ganglion Router, Spinal Cord Reflex Engine (<50ms, Zero-LLM),
//  and Thalamic Sensory Attention Gate.
//  Scales MCP_1 ... MCP_xx (1,000+ tools) via two-stage nerve tract activation,
//  Hebbian synaptic weighting, and zero-RAM idle MCP hibernation with cached manifests.
//
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation
import CryptoKit
import Darwin

// MARK: - Spinal Cord Reflex Decision (<50ms Deterministic Recovery)

public enum PNSSpinalReflexAction: Equatable {
    case none
    case switchProviderEndpoint(reason: String, cooldownMs: UInt64)
    case restartMCPConnection(serverName: String, replayIdempotent: Bool)
    case remapCollidedPort(detectedPort: Int?, suggestedPort: Int)
    case circuitBreakBehavioralFixation(fingerprint: String, inhibitionRule: String)
}

public struct PNSSpinalReflexOutcome: Equatable {
    public let action: PNSSpinalReflexAction
    public let latencyMs: Int
    public let summary: String
}

// MARK: - Ganglion Router & Spinal/Thalamic Subsystem

@MainActor
public final class PNSGanglionRouter: ObservableObject {
    public static let shared = PNSGanglionRouter()

    /// Cached MCP tool manifests preserved across idle process hibernation so 100+ MCP servers
    /// remain 100% routable at 0 MB child-process RAM cost while hibernated.
    @Published private(set) var cachedServerManifests: [String: [MCPClient.MCPToolSchema]] = [:]
    @Published public private(set) var serverTractAssignments: [String: PNSNerveTractKind] = [:]
    @Published public private(set) var hibernatedServers: Set<String> = []
    @Published public private(set) var lastActiveSynapticToolsCount: Int = 0
    @Published public private(set) var spinalReflexSavesCount: Int = 0

    private var serverLastImpulseAt: [String: Date] = [:]
    private var tractImpulseCounts: [PNSNerveTractKind: Int] = [:]
    private var rollingFailureFingerprints: [String] = []
    private let maxFingerprintWindow = 16
    private let fixationThreshold = 3

    private init() {}

    // MARK: - 1. Task Signature & Nerve Tract Classification

    nonisolated public static func classifyTaskCategory(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("sql") || lower.contains("query") || lower.contains("bigquery") || lower.contains("postgres") || lower.contains("database") || lower.contains("schema") || lower.contains("migration") {
            return "data_engineering"
        }
        if lower.contains("ios") || lower.contains("simulator") || lower.contains("simctl") || lower.contains("android") || lower.contains("adb") || lower.contains("apk") || lower.contains("device") {
            return "mobile_device"
        }
        if lower.contains("browser") || lower.contains("css") || lower.contains("dom") || lower.contains("devtools") || lower.contains("ui") || lower.contains("layout") || lower.contains("preview") {
            return "ui_visual"
        }
        if lower.contains("test") || lower.contains("fix") || lower.contains("bug") || lower.contains("crash") || lower.contains("error") || lower.contains("diagnostic") {
            return "debug_verification"
        }
        if lower.contains("paper") || lower.contains("arxiv") || lower.contains("protein") || lower.contains("alphafold") || lower.contains("docs") || lower.contains("research") {
            return "research_science"
        }
        if lower.contains("architect") || lower.contains("design") || lower.contains("refactor") || lower.contains("plan") {
            return "architecture_refactor"
        }
        return "code_implementation"
    }

    nonisolated public static func classifyMCPTract(
        serverName: String,
        toolName: String = "",
        description: String = ""
    ) -> PNSNerveTractKind {
        let hay = "\(serverName) \(toolName) \(description)".lowercased()

        let dataKeywords = ["postgres", "mysql", "sqlite", "sql", "bigquery", "alloydb", "spanner", "bigtable", "cloudsql", "gcs", "s3", "redis", "supabase", "firebase", "firestore", "mongo", "dak", "database", "bucket", "dataset"]
        if dataKeywords.contains(where: { hay.contains($0) }) {
            return .mcpDataCloud
        }

        let deviceKeywords = ["android", "adb", "ios", "simctl", "simulator", "device", "ssh", "runpod", "gpu", "docker", "k8s", "kubernetes", "release", "play_bundle", "testflight", "serial", "iot", "hardware"]
        if deviceKeywords.contains(where: { hay.contains($0) }) {
            return .mcpDeviceHardware
        }

        let visualKeywords = ["chrome", "devtools", "playwright", "puppeteer", "browser", "selenium", "canva", "figma", "flutterflow", "preview", "screenshot", "lcp", "dom", "a11y", "canvas"]
        if visualKeywords.contains(where: { hay.contains($0) }) {
            return .mcpBrowserVisual
        }

        let scienceDocsKeywords = ["arxiv", "pubmed", "alphafold", "biomolecular", "pdb", "chembl", "uniprot", "clinvar", "gnomad", "gemini-api-docs", "search_docs", "slack", "notion", "gsheets", "gslides", "gdocs", "literature"]
        if scienceDocsKeywords.contains(where: { hay.contains($0) }) {
            return .mcpKnowledgeScience
        }

        return .mcpCodeAST
    }

    nonisolated public static func preferredMCPTractsForSubAgent(archetype: String) -> Set<PNSNerveTractKind> {
        switch archetype.lowercased() {
        case "architect":
            return [.mcpCodeAST, .mcpKnowledgeScience, .mcpDataCloud]
        case "frontend_engineer":
            return [.mcpBrowserVisual, .mcpCodeAST]
        case "backend_engineer":
            return [.mcpDataCloud, .mcpCodeAST, .mcpDeviceHardware]
        case "mobile_device_controller":
            return [.mcpDeviceHardware, .mcpBrowserVisual, .mcpCodeAST]
        case "bug_hunter", "test_runner", "autonomous_loop":
            return [.mcpCodeAST, .mcpBrowserVisual, .mcpDeviceHardware, .mcpDataCloud]
        case "security_auditor":
            return [.mcpCodeAST, .mcpDataCloud]
        default:
            return Set(PNSNerveTractKind.allCases.filter(\.isMCPTract))
        }
    }

    nonisolated public static func motorTractForSubAgent(archetype: String) -> PNSNerveTractKind {
        switch archetype.lowercased() {
        case "architect":
            return .motorArchitecture
        case "bug_hunter", "test_runner", "security_auditor", "mobile_device_controller":
            return .motorVerification
        default:
            return .motorImplementation
        }
    }

    // MARK: - 2. Manifest Synchronization & Idle MCP Hibernation

    public func syncManifestsFromExternalMCP() {
        let manager = ExternalMCPManager.shared
        for (name, conn) in manager.connections {
            if !conn.availableTools.isEmpty {
                cachedServerManifests[name] = conn.availableTools
            }
            if conn.isConnected {
                hibernatedServers.remove(name)
                if serverLastImpulseAt[name] == nil {
                    serverLastImpulseAt[name] = Date()
                }
            }
            let sampleDesc = (cachedServerManifests[name] ?? conn.availableTools)
                .prefix(5)
                .map { "\($0.name) \($0.description)" }
                .joined(separator: " ")
            serverTractAssignments[name] = Self.classifyMCPTract(
                serverName: name,
                description: sampleDesc
            )
        }
    }

    public func recordMCPImpulse(serverName: String, tract: PNSNerveTractKind? = nil) {
        serverLastImpulseAt[serverName] = Date()
        hibernatedServers.remove(serverName)
        let resolvedTract = tract ?? serverTractAssignments[serverName] ?? Self.classifyMCPTract(serverName: serverName)
        tractImpulseCounts[resolvedTract, default: 0] += 1
    }

    /// Hibernates external stdio MCP servers that have been idle longer than `idleThresholdSeconds`,
    /// preserving their full tool schemas in `cachedServerManifests` so they consume 0 MB RAM until needed.
    @discardableResult
    public func hibernateIdleMCPServers(idleThresholdSeconds: TimeInterval = 300) -> [String] {
        syncManifestsFromExternalMCP()
        let now = Date()
        var newlyHibernated: [String] = []
        let manager = ExternalMCPManager.shared

        for (name, conn) in manager.connections where conn.isConnected {
            // Never hibernate remote HTTP endpoints (they have no local child process RAM cost)
            if conn.remoteURL != nil { continue }
            let lastUsed = serverLastImpulseAt[name] ?? .distantPast
            if now.timeIntervalSince(lastUsed) >= idleThresholdSeconds {
                if !conn.availableTools.isEmpty {
                    cachedServerManifests[name] = conn.availableTools
                }
                conn.stop()
                hibernatedServers.insert(name)
                newlyHibernated.append(name)
            }
        }
        return newlyHibernated
    }

    // MARK: - 3. Two-Stage Hierarchical Ganglion Tool Routing (1,000+ Tools -> Top-K Active Synapses)

    public func computeTractActivations(for prompt: String) -> [PNSNerveTractKind: Double] {
        let lower = prompt.lowercased()
        var activations: [PNSNerveTractKind: Double] = [
            .mcpCodeAST: 0.45, // Baseline software development tract
            .mcpDataCloud: 0.10,
            .mcpBrowserVisual: 0.10,
            .mcpDeviceHardware: 0.10,
            .mcpKnowledgeScience: 0.12
        ]

        let rules: [(PNSNerveTractKind, [String], Double)] = [
            (.mcpCodeAST, ["file", "code", "git", "commit", "symbol", "refactor", "build", "compile", "swift", "rust", "ast", "lsp"], 0.22),
            (.mcpDataCloud, ["sql", "postgres", "bigquery", "database", "table", "query", "schema", "gcs", "bucket", "firebase", "supabase", "migration", "redis"], 0.35),
            (.mcpBrowserVisual, ["browser", "chrome", "ui", "css", "html", "preview", "screenshot", "canva", "figma", "flutterflow", "dom", "cookie", "lcp", "web"], 0.35),
            (.mcpDeviceHardware, ["ios", "android", "simulator", "simctl", "adb", "device", "phone", "ipa", "apk", "aab", "ssh", "runpod", "gpu", "deploy"], 0.38),
            (.mcpKnowledgeScience, ["docs", "documentation", "gemini", "api", "paper", "arxiv", "pubmed", "protein", "alphafold", "pdb", "slack", "sheet", "slide", "research"], 0.34)
        ]

        for (tract, keywords, boost) in rules {
            let hits = keywords.filter { lower.contains($0) }.count
            if hits > 0 {
                activations[tract, default: 0.1] = min(1.0, (activations[tract] ?? 0.1) + boost * min(2.2, Double(hits)))
            }
        }
        return activations
    }

    /// Selects the Top-K external MCP tool names (`mcp__<server>__<tool>`) via Two-Stage Nerve Tract Routing
    /// modulated by Hebbian Synaptic Weights W_e. Also lazy-awakens hibernated MCP servers if selected!
    public func selectActiveSynapticTools(
        forPrompt prompt: String,
        workspacePath: String? = nil,
        allowedTracts: Set<PNSNerveTractKind>? = nil,
        maxTools: Int = 12,
        synapseLookup: ((String, PNSNerveTractKind, String, String?) -> PNSSynapseEdge?)? = nil
    ) -> Set<String> {
        syncManifestsFromExternalMCP()
        let manager = ExternalMCPManager.shared

        // Collect union of live tools + cached hibernated server manifests
        var candidatePool: [(serverName: String, tool: MCPClient.MCPToolSchema, tract: PNSNerveTractKind, isHibernated: Bool)] = []
        var seenServers = Set<String>()

        for (serverName, conn) in manager.connections {
            seenServers.insert(serverName)
            let tools = !conn.availableTools.isEmpty ? conn.availableTools : (cachedServerManifests[serverName] ?? [])
            for tool in tools {
                let tract = Self.classifyMCPTract(serverName: serverName, toolName: tool.name, description: tool.description)
                if let allowed = allowedTracts, !allowed.contains(tract) { continue }
                candidatePool.append((serverName, tool, tract, !conn.isConnected))
            }
        }
        for (serverName, tools) in cachedServerManifests where !seenServers.contains(serverName) {
            for tool in tools {
                let tract = Self.classifyMCPTract(serverName: serverName, toolName: tool.name, description: tool.description)
                if let allowed = allowedTracts, !allowed.contains(tract) { continue }
                candidatePool.append((serverName, tool, tract, true))
            }
        }

        if candidatePool.isEmpty {
            lastActiveSynapticToolsCount = 0
            return []
        }

        if candidatePool.count <= maxTools && candidatePool.allSatisfy({ !$0.isHibernated }) {
            let allSet = Set(candidatePool.map { "mcp__\($0.serverName)__\($0.tool.name)" })
            lastActiveSynapticToolsCount = allSet.count
            return allSet
        }

        // Stage 1: Nerve Tract Activation Gate
        let tractPotentials = computeTractActivations(for: prompt)
        let activeTracts = Set(tractPotentials.filter { $0.value >= 0.28 }.map(\.key))
            .union([tractPotentials.max(by: { $0.value < $1.value })?.key ?? .mcpCodeAST])

        let taskCategory = Self.classifyTaskCategory(prompt)
        let queryTokens = prompt.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }

        // Stage 2: Ganglion Intra-Tract Synaptic Scoring
        var scored: [(fullName: String, serverName: String, tract: PNSNerveTractKind, isHibernated: Bool, score: Double)] = []

        for entry in candidatePool {
            let fullName = "mcp__\(entry.serverName)__\(entry.tool.name)"
            let tractGain = activeTracts.contains(entry.tract) ? (tractPotentials[entry.tract] ?? 0.5) : 0.15

            var lexical: Double = 1.0
            let sLower = entry.serverName.lowercased()
            let tLower = entry.tool.name.lowercased()
            let dLower = entry.tool.description.lowercased()
            for tok in queryTokens {
                if sLower.contains(tok) { lexical += 16.0 }
                if tLower.contains(tok) { lexical += 13.0 }
                if dLower.contains(tok) { lexical += 4.5 }
            }

            // Modulate by Hebbian Synaptic Weight W_e (Myelination boost / LTD inhibition)
            var synapticMultiplier = 1.0
            if let lookup = synapseLookup,
               let edge = lookup(taskCategory, entry.tract, fullName, workspacePath) {
                if edge.isInhibited {
                    synapticMultiplier = 0.20 // Strong LTD inhibition against repeatedly failing tool
                } else if edge.isMyelinated {
                    synapticMultiplier = 1.45 // Myelinated fast-path boost
                } else {
                    synapticMultiplier = 0.65 + 0.70 * edge.weight
                }
            }

            let finalScore = lexical * (0.55 + tractGain) * synapticMultiplier
            scored.append((fullName, entry.serverName, entry.tract, entry.isHibernated, finalScore))
        }

        scored.sort { $0.score > $1.score }
        let winners = Array(scored.prefix(maxTools))

        // Lazy-awaken any hibernated MCP server whose tool won synaptic activation
        for winner in winners where winner.isHibernated {
            if let conn = manager.connections[winner.serverName], !conn.isConnected, lexicalHitStrongEnough(winner.score) {
                conn.start()
                recordMCPImpulse(serverName: winner.serverName, tract: winner.tract)
            }
        }

        let selectedNames = Set(winners.map(\.fullName))
        lastActiveSynapticToolsCount = selectedNames.count
        return selectedNames
    }

    private func lexicalHitStrongEnough(_ score: Double) -> Bool {
        score >= 6.0
    }

    /// Filters tool schema dictionary list for a SubAgent so it mounts only its role's MCP Nerve Tracts.
    public func filterMCPToolsForSubAgent(
        archetype: String,
        taskPrompt: String,
        workspacePath: String?,
        allSchemas: [[String: Any]],
        maxMCPTools: Int = 10,
        synapseLookup: ((String, PNSNerveTractKind, String, String?) -> PNSSynapseEdge?)? = nil
    ) -> [[String: Any]] {
        let allowedTracts = Self.preferredMCPTractsForSubAgent(archetype: archetype)
        let activeExternalMCP = selectActiveSynapticTools(
            forPrompt: taskPrompt,
            workspacePath: workspacePath,
            allowedTracts: allowedTracts,
            maxTools: maxMCPTools,
            synapseLookup: synapseLookup
        )
        return allSchemas.filter { schema in
            guard let name = schema["name"] as? String else { return true }
            if name.hasPrefix("mcp__") && !name.hasPrefix("mcp__local__") {
                return activeExternalMCP.contains(name)
            }
            return true
        }
    }

    /// Generates a compact (~120-token) Ganglion Tract Directory so the Cortex knows all off-context MCP tracts exist.
    public func buildCompactTractDirectorySnippet() -> String {
        syncManifestsFromExternalMCP()
        var byTract: [PNSNerveTractKind: [String]] = [:]
        for (server, tract) in serverTractAssignments {
            let count = cachedServerManifests[server]?.count ?? ExternalMCPManager.shared.connections[server]?.availableTools.count ?? 0
            let state = hibernatedServers.contains(server) ? "hibernated" : "ready"
            byTract[tract, default: []].append("\(server)(\(count) tools, \(state))")
        }
        guard !byTract.isEmpty else { return "" }
        var lines = ["### PNS Efferent MCP Nerve Tracts (Hierarchical Ganglion Routing)"]
        for tract in PNSNerveTractKind.allCases where tract.isMCPTract {
            if let servers = byTract[tract], !servers.isEmpty {
                lines.append("- **\(tract.shortBadge)**: \(servers.sorted().joined(separator: ", "))")
            }
        }
        lines.append("- Top-K relevant tools are dynamically mounted per impulse; use `mcp_orchestrator(action: 'search_tools')` or `pns_nervous_system` to stimulate dormant tracts.")
        return lines.joined(separator: "\n")
    }

    // MARK: - 4. Spinal Cord Reflex Arc (<50ms Deterministic Fault Interception)

    public func evaluateSpinalReflex(
        toolOrProviderName: String,
        targetHint: String = "",
        errorMessage: String
    ) -> PNSSpinalReflexOutcome {
        let startNs = DispatchTime.now().uptimeNanoseconds
        let lower = errorMessage.lowercased()

        func finish(_ action: PNSSpinalReflexAction, _ summary: String) -> PNSSpinalReflexOutcome {
            let elapsedMs = max(1, Int((DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000))
            if action != .none {
                spinalReflexSavesCount += 1
                tractImpulseCounts[.spinalReflex, default: 0] += 1
            }
            return PNSSpinalReflexOutcome(action: action, latencyMs: elapsedMs, summary: summary)
        }

        // Reflex 1: Rate-Limit / Quota / Upstream 5xx -> Instant Provider/Model Failover
        if lower.contains("429") ||
            lower.contains("rate limit") ||
            lower.contains("resource_exhausted") ||
            lower.contains("quota") ||
            lower.contains("overloaded") ||
            lower.contains("503 service unavailable") ||
            lower.contains("502 bad gateway") {
            let cooldown: UInt64 = lower.contains("quota") ? 8_000 : 2_000
            return finish(
                .switchProviderEndpoint(reason: "HTTP 429/5xx stimulus intercepted", cooldownMs: cooldown),
                "Spinal Reflex (<50ms): Intercepted rate-limit/5xx on '\(toolOrProviderName)' -> rotated endpoint & adjusted homeostasis pacing."
            )
        }

        // Reflex 2: Broken MCP Pipe / Transport Timeout -> Instant Child Respawn
        if toolOrProviderName.hasPrefix("mcp__") &&
            (lower.contains("connection closed") ||
             lower.contains("broken pipe") ||
             lower.contains("timed out") ||
             lower.contains("eof")) {
            let parts = toolOrProviderName.components(separatedBy: "__")
            if parts.count >= 3 {
                let serverName = parts[1]
                ExternalMCPManager.shared.restartServer(serverName)
                let isReadOnly = parts[2].hasPrefix("get_") || parts[2].hasPrefix("list_") || parts[2].hasPrefix("read_") || parts[2].hasPrefix("search_")
                return finish(
                    .restartMCPConnection(serverName: serverName, replayIdempotent: isReadOnly),
                    "Spinal Reflex (<50ms): Respawned crashed MCP fiber '\(serverName)' (replaySafe=\(isReadOnly))."
                )
            }
        }

        // Reflex 3: Port Collision (`EADDRINUSE`) -> Allocate Clean Ephemeral Port
        if lower.contains("eaddrinuse") || lower.contains("address already in use") {
            let detected = Self.extractPortNumber(from: errorMessage)
            let freePort = Self.allocateFreeLocalPort() ?? ((detected ?? 3000) + Int.random(in: 11...89))
            return finish(
                .remapCollidedPort(detectedPort: detected, suggestedPort: freePort),
                "Spinal Reflex (<50ms): Port collision (\(detected.map(String.init) ?? "unknown")) -> allocated clean port \(freePort)."
            )
        }

        // Reflex 4: Behavioral Fixation / Repeated Failure Fingerprint Circuit Breaker
        let normalizedErrorClass = String(lower.prefix(120))
            .replacingOccurrences(of: #"[0-9]+"#, with: "#", options: .regularExpression)
        let rawFingerprint = "\(toolOrProviderName)|\(targetHint)|\(normalizedErrorClass)"
        let fpHash = SHA256.hash(data: Data(rawFingerprint.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()

        rollingFailureFingerprints.append(fpHash)
        if rollingFailureFingerprints.count > maxFingerprintWindow {
            rollingFailureFingerprints.removeFirst(rollingFailureFingerprints.count - maxFingerprintWindow)
        }
        let repeatCount = rollingFailureFingerprints.filter { $0 == fpHash }.count
        if repeatCount >= fixationThreshold {
            rollingFailureFingerprints.removeAll { $0 == fpHash }
            let rule = "INHIBITION [\(fpHash)]: Repeatedly failed (\(repeatCount)x) calling '\(toolOrProviderName)' on '\(targetHint)'. Do NOT repeat this action; rollback dirty hunk and pivot strategy."
            return finish(
                .circuitBreakBehavioralFixation(fingerprint: fpHash, inhibitionRule: rule),
                "Spinal Reflex (<50ms): Tripped Behavioral Fixation circuit-breaker [\(fpHash)] after \(repeatCount) identical failures."
            )
        }

        return finish(.none, "Escalated to Cortex")
    }

    public func resetFixationWindow() {
        rollingFailureFingerprints.removeAll()
    }

    nonisolated private static func extractPortNumber(from text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:port|:)\s*([0-9]{2,5})"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[range])
    }

    nonisolated public static func allocateFreeLocalPort() -> Int? {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRes == 0 else { return nil }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameRes = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(sock, $0, &len)
            }
        }
        guard nameRes == 0 else { return nil }
        return Int(UInt16(bigEndian: addr.sin_port))
    }

    // MARK: - 5. Thalamic Sensory Attention Gate (Anti-Context-Rot Log Compressor)

    nonisolated public static func thalamicFilterSensoryStream(
        rawOutput: String,
        source: String,
        maxChars: Int = 2400
    ) -> (compressedSpike: String, salience: Double) {
        // Strip ANSI escape sequences
        let cleanANSI = rawOutput.replacingOccurrences(
            of: #"\u{001B}\[[0-9;]*[a-zA-Z]"#,
            with: "",
            options: .regularExpression
        )
        let lines = cleanANSI.components(separatedBy: .newlines)
        var highSalienceLines: [String] = []
        var seenNormalized = Set<String>()
        var errorHits = 0
        var warningHits = 0

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let lower = trimmed.lowercased()

            // Suppress low-salience compiler/bundler progress chatter
            if lower.hasPrefix("compiling ") ||
                lower.hasPrefix("downloading ") ||
                lower.hasPrefix("fetching ") ||
                lower.hasPrefix("linking ") && !lower.contains("error") {
                continue
            }

            let isHighSalience = lower.contains("error:") ||
                lower.contains("error[") ||
                lower.contains("fatal:") ||
                lower.contains("panic") ||
                lower.contains("failed") ||
                lower.contains("assertion") ||
                lower.contains("exception") ||
                lower.contains("warning:")

            if lower.contains("error") || lower.contains("panic") || lower.contains("fatal") || lower.contains("failed") {
                errorHits += 1
            } else if lower.contains("warning:") {
                warningHits += 1
            }

            if isHighSalience {
                let dedupKey = trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                if seenNormalized.insert(dedupKey).inserted {
                    highSalienceLines.append(trimmed)
                }
            }
        }

        let salience: Double
        if errorHits > 0 {
            salience = min(1.0, 0.72 + Double(min(10, errorHits)) * 0.028)
        } else if warningHits > 0 {
            salience = min(0.68, 0.35 + Double(min(10, warningHits)) * 0.03)
        } else {
            salience = 0.18
        }

        if cleanANSI.count <= maxChars && highSalienceLines.isEmpty {
            return (cleanANSI, salience)
        }

        var summaryParts: [String] = []
        summaryParts.append("[Thalamus Gate • \(source) • \(lines.count) lines -> Salience \(String(format: "%.2f", salience)) • Errors: \(errorHits), Warnings: \(warningHits)]")

        if !highSalienceLines.isEmpty {
            summaryParts.append(highSalienceLines.prefix(24).joined(separator: "\n"))
        }
        let tailLines = lines.suffix(12).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !tailLines.isEmpty {
            summaryParts.append("--- Tail ---\n" + tailLines.joined(separator: "\n"))
        }

        let joined = summaryParts.joined(separator: "\n")
        if joined.count <= maxChars {
            return (joined, salience)
        }
        return (String(joined.prefix(maxChars)) + "\n…[thalamic truncation]", salience)
    }

    // MARK: - 6. Telemetry Builder

    public func buildMCPTractTelemetry(myelinatedEdges: [PNSSynapseEdge]) -> [PNSTractTelemetry] {
        syncManifestsFromExternalMCP()
        let manager = ExternalMCPManager.shared
        return PNSNerveTractKind.allCases.filter(\.isMCPTract).map { tract in
            let servers = serverTractAssignments.filter { $0.value == tract }.map(\.key).sorted()
            var active = 0
            var hibernated = 0
            var latencies: [Int] = []
            for s in servers {
                if let conn = manager.connections[s], conn.isConnected {
                    active += 1
                    if conn.avgLatencyMs > 0 { latencies.append(conn.avgLatencyMs) }
                } else {
                    hibernated += 1
                }
            }
            let avgLat = latencies.isEmpty ? 0 : (latencies.reduce(0, +) / latencies.count)
            let myelinated = myelinatedEdges.filter { $0.tract == tract && $0.isMyelinated }.count
            return PNSTractTelemetry(
                tract: tract,
                attachedNodes: servers,
                activeCount: active,
                hibernatedCount: hibernated,
                myelinatedEdgesCount: myelinated,
                avgLatencyMs: avgLat,
                totalImpulses: tractImpulseCounts[tract] ?? 0
            )
        }
    }
}
