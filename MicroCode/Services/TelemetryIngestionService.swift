import Foundation

// MARK: - Telemetry-in-the-Loop Debugging (Phase 3)
// Ingests runtime telemetry from Docker, Kubernetes, and OpenTelemetry
// to provide Agent with live runtime context for debugging.

// MARK: - Telemetry Source

enum TelemetrySourceType: String, CaseIterable, Codable {
    case docker = "Docker"
    case kubernetes = "Kubernetes"
    case opentelemetry = "OpenTelemetry"
    case processLog = "Process Log"
    case crashReport = "Crash Report"
}

struct RuntimeTelemetryEvent: Identifiable, Equatable {
    let id: UUID
    let source: TelemetrySourceType
    let timestamp: Date
    let level: TelemetryLevel
    let service: String        // Container/pod/service name
    let message: String
    let stackTrace: String?
    let metadata: [String: String]
    
    enum TelemetryLevel: String, Comparable, CaseIterable {
        case trace = "TRACE"
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
        case fatal = "FATAL"
        
        static func < (lhs: TelemetryLevel, rhs: TelemetryLevel) -> Bool {
            let order: [TelemetryLevel] = [.trace, .debug, .info, .warn, .error, .fatal]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }
}

// MARK: - Crash Context

struct CrashContext: Identifiable, Equatable {
    let id: UUID
    let service: String
    let timestamp: Date
    let stackTrace: String
    let exitCode: Int?
    let signal: String?           // SIGSEGV, SIGABRT, etc.
    let lastLogs: [String]        // Last N log lines before crash
    let memoryUsageMB: Int?
    let cpuUsagePercent: Double?
    let containerImage: String?
    let environment: [String: String]
    
    /// Generate a complete context string for the AI agent
    var agentContext: String {
        var ctx = """
        ## Crash Report
        - **Service:** \(service)
        - **Time:** \(ISO8601DateFormatter().string(from: timestamp))
        """
        if let code = exitCode { ctx += "\n- **Exit Code:** \(code)" }
        if let sig = signal { ctx += "\n- **Signal:** \(sig)" }
        if let mem = memoryUsageMB { ctx += "\n- **Memory:** \(mem) MB" }
        if let cpu = cpuUsagePercent { ctx += "\n- **CPU:** \(String(format: "%.1f", cpu))%" }
        if let img = containerImage { ctx += "\n- **Image:** \(img)" }
        
        ctx += "\n\n### Stack Trace\n```\n\(stackTrace)\n```"
        
        if !lastLogs.isEmpty {
            ctx += "\n\n### Last \(lastLogs.count) Log Lines\n```\n"
            ctx += lastLogs.joined(separator: "\n")
            ctx += "\n```"
        }
        
        if !environment.isEmpty {
            ctx += "\n\n### Environment\n"
            for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
                ctx += "- `\(key)`: `\(value)`\n"
            }
        }
        
        return ctx
    }
}

// MARK: - Telemetry Ingestion Service

@MainActor
final class TelemetryIngestionService: ObservableObject {
    static let shared = TelemetryIngestionService()
    
    // MARK: - Published State
    @Published private(set) var events: [RuntimeTelemetryEvent] = []
    @Published private(set) var crashes: [CrashContext] = []
    @Published private(set) var connectedSources: [TelemetrySourceType] = []
    @Published var isIngesting = false
    @Published var autoFeedToAgent: Bool = true {
        didSet { UserDefaults.standard.set(autoFeedToAgent, forKey: "telemetry_auto_feed") }
    }
    
    private let maxEvents = 5000
    private var dockerPoller: Task<Void, Never>?
    
    private init() {
        autoFeedToAgent = UserDefaults.standard.object(forKey: "telemetry_auto_feed") as? Bool ?? true
    }
    
    // MARK: - Docker Integration
    
    /// Start polling Docker container logs
    func connectDocker() {
        guard !connectedSources.contains(.docker) else { return }
        connectedSources.append(.docker)
        isIngesting = true
        
        dockerPoller = Task {
            while !Task.isCancelled {
                await pollDockerContainers()
                try? await Task.sleep(nanoseconds: 5_000_000_000) // Poll every 5s
            }
        }
    }
    
    private func pollDockerContainers() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["docker", "ps", "--format", "{{.Names}}"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let containers = output.components(separatedBy: "\n").filter { !$0.isEmpty }
            
            for container in containers {
                await fetchDockerLogs(container: container, tail: 5)
            }
        } catch {
            // Docker not available
        }
    }
    
    private func fetchDockerLogs(container: String, tail: Int) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["docker", "logs", "--tail", "\(tail)", "--since", "10s", container]
        let pipe = Pipe()
        process.standardOutput = pipe
        let errPipe = Pipe()
        process.standardError = errPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let stdout = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let combined = stdout + stderr
            
            for line in combined.components(separatedBy: "\n") where !line.isEmpty {
                let level = detectLogLevel(line)
                let event = RuntimeTelemetryEvent(
                    id: UUID(),
                    source: .docker,
                    timestamp: Date(),
                    level: level,
                    service: container,
                    message: line,
                    stackTrace: nil,
                    metadata: ["container": container]
                )
                
                addEvent(event)
                
                // Auto-detect crashes
                if level == .fatal || level == .error {
                    if line.contains("panic") || line.contains("SIGSEGV") || line.contains("Segmentation fault") ||
                       line.contains("OutOfMemoryError") || line.contains("killed") {
                        await captureDockerCrash(container: container, errorLine: line)
                    }
                }
            }
        } catch { }
    }
    
    private func captureDockerCrash(container: String, errorLine: String) async {
        // Get full logs for crash context
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["docker", "logs", "--tail", "50", container]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let lines = output.components(separatedBy: "\n")
            
            // Extract stack trace (lines starting with "at " or containing file:line patterns)
            let stackLines = lines.filter { line in
                line.trimmingCharacters(in: .whitespaces).hasPrefix("at ") ||
                line.contains("File \"") || // Python
                line.contains(".go:") ||     // Go
                line.contains(".rs:") ||     // Rust
                line.contains(".java:") ||   // Java
                line.contains(".js:") ||     // JavaScript
                line.contains(".swift:")     // Swift
            }
            
            let crash = CrashContext(
                id: UUID(),
                service: container,
                timestamp: Date(),
                stackTrace: stackLines.isEmpty ? errorLine : stackLines.joined(separator: "\n"),
                exitCode: nil,
                signal: errorLine.contains("SIGSEGV") ? "SIGSEGV" :
                        errorLine.contains("SIGABRT") ? "SIGABRT" :
                        errorLine.contains("SIGKILL") ? "SIGKILL" : nil,
                lastLogs: Array(lines.suffix(20)),
                memoryUsageMB: nil,
                cpuUsagePercent: nil,
                containerImage: nil,
                environment: [:]
            )
            
            crashes.append(crash)
            
            // Record in Flight Recorder
            FlightRecorder.shared.record(
                actor: .system,
                action: .agentError,
                target: AuditTarget(type: "telemetry", path: container),
                details: "Crash detected: \(String(errorLine.prefix(200)))",
                metadata: ["source": "docker", "container": container]
            )
        } catch { }
    }
    
    // MARK: - OpenTelemetry HTTP Endpoint
    
    /// Parse OTLP JSON log/trace data
    func ingestOTLP(jsonData: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return }
        
        // Parse resource logs
        if let resourceLogs = json["resourceLogs"] as? [[String: Any]] {
            for resource in resourceLogs {
                let serviceName = extractServiceName(from: resource)
                if let scopeLogs = resource["scopeLogs"] as? [[String: Any]] {
                    for scopeLog in scopeLogs {
                        if let logRecords = scopeLog["logRecords"] as? [[String: Any]] {
                            for record in logRecords {
                                let body = record["body"] as? [String: Any]
                                let message = body?["stringValue"] as? String ?? ""
                                let severityText = record["severityText"] as? String ?? "INFO"
                                
                                let event = RuntimeTelemetryEvent(
                                    id: UUID(),
                                    source: .opentelemetry,
                                    timestamp: Date(),
                                    level: parseOTLPLevel(severityText),
                                    service: serviceName,
                                    message: message,
                                    stackTrace: record["attributes"] as? String,
                                    metadata: ["severity": severityText]
                                )
                                addEvent(event)
                            }
                        }
                    }
                }
            }
        }
        
        if !connectedSources.contains(.opentelemetry) {
            connectedSources.append(.opentelemetry)
        }
    }
    
    // MARK: - Agent Context Generation
    
    /// Build a context string from recent errors/crashes for the AI agent
    func buildAgentContext(maxEvents: Int = 20) -> String {
        var context = "## Runtime Telemetry\n"
        
        // Recent crashes
        if !crashes.isEmpty {
            let recentCrash = crashes.last!
            context += "\n### Latest Crash\n"
            context += recentCrash.agentContext
        }
        
        // Recent errors
        let errors = events.filter { $0.level >= .error }.suffix(maxEvents)
        if !errors.isEmpty {
            context += "\n\n### Recent Errors (\(errors.count))\n"
            for event in errors {
                context += "- [\(event.source.rawValue)/\(event.service)] \(event.message.prefix(200))\n"
            }
        }
        
        return context
    }
    
    // MARK: - Helpers
    
    private func addEvent(_ event: RuntimeTelemetryEvent) {
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }
    
    private func detectLogLevel(_ line: String) -> RuntimeTelemetryEvent.TelemetryLevel {
        let upper = line.uppercased()
        if upper.contains("FATAL") || upper.contains("PANIC") { return .fatal }
        if upper.contains("ERROR") || upper.contains("ERR ") { return .error }
        if upper.contains("WARN") || upper.contains("WARNING") { return .warn }
        if upper.contains("DEBUG") { return .debug }
        if upper.contains("TRACE") { return .trace }
        return .info
    }
    
    private func parseOTLPLevel(_ severity: String) -> RuntimeTelemetryEvent.TelemetryLevel {
        switch severity.uppercased() {
        case "FATAL", "FATAL4": return .fatal
        case "ERROR", "ERROR4": return .error
        case "WARN", "WARN4": return .warn
        case "DEBUG", "DEBUG4": return .debug
        case "TRACE", "TRACE4": return .trace
        default: return .info
        }
    }
    
    private func extractServiceName(from resource: [String: Any]) -> String {
        if let attrs = (resource["resource"] as? [String: Any])?["attributes"] as? [[String: Any]] {
            for attr in attrs {
                if attr["key"] as? String == "service.name",
                   let value = (attr["value"] as? [String: Any])?["stringValue"] as? String {
                    return value
                }
            }
        }
        return "unknown"
    }
    
    func disconnect() {
        dockerPoller?.cancel()
        dockerPoller = nil
        connectedSources.removeAll()
        isIngesting = false
    }
}
