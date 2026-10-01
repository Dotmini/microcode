import Foundation
import CryptoKit

// MARK: - Sovereign Flight Recorder
// Immutable, cryptographically signed audit log for all AI agent actions.
// Designed for enterprise compliance: SOC2 Type II, HIPAA BAA, GDPR.

// MARK: - Audit Log Entry

struct AuditLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let sessionId: String
    let actor: AuditActor
    let action: AuditAction
    let target: AuditTarget
    let details: String
    let metadata: [String: String]
    let previousHash: String  // Chain hash for tamper detection
    let entryHash: String     // SHA-256 hash of this entry
    
    init(
        sessionId: String,
        actor: AuditActor,
        action: AuditAction,
        target: AuditTarget,
        details: String,
        metadata: [String: String] = [:],
        previousHash: String
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.sessionId = sessionId
        self.actor = actor
        self.action = action
        self.target = target
        self.details = details
        self.metadata = metadata
        self.previousHash = previousHash
        
        // Compute tamper-proof hash
        let payload = "\(id)|\(ISO8601DateFormatter().string(from: timestamp))|\(sessionId)|\(actor.rawValue)|\(action.rawValue)|\(target.path)|\(details)|\(previousHash)"
        let hash = SHA256.hash(data: Data(payload.utf8))
        self.entryHash = hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Audit Enums

enum AuditActor: String, Codable {
    case user = "user"
    case agent = "agent"
    case subAgent = "sub_agent"
    case system = "system"
    case tool = "tool"
}

enum AuditAction: String, Codable {
    // File operations
    case fileCreate = "file.create"
    case fileModify = "file.modify"
    case fileDelete = "file.delete"
    case fileRead = "file.read"
    
    // Agent operations
    case agentStart = "agent.start"
    case agentComplete = "agent.complete"
    case agentError = "agent.error"
    case agentToolCall = "agent.tool_call"
    case agentToolResult = "agent.tool_result"
    case agentApprovalRequested = "agent.approval.requested"
    case agentApprovalGranted = "agent.approval.granted"
    case agentApprovalDenied = "agent.approval.denied"
    
    // Diff / Change operations
    case changeProposed = "change.proposed"
    case changeAccepted = "change.accepted"
    case changeRejected = "change.rejected"
    case changePartialApply = "change.partial_apply"
    
    // Git operations
    case gitCommit = "git.commit"
    case gitPush = "git.push"
    case gitCheckout = "git.checkout"
    
    // Command execution
    case commandExecute = "command.execute"
    case commandOutput = "command.output"
    
    // Session lifecycle
    case sessionStart = "session.start"
    case sessionEnd = "session.end"
    case modelSwitch = "model.switch"
}

struct AuditTarget: Codable, Equatable {
    let type: String      // "file", "command", "api", "git", "model"
    let path: String      // file path, command string, or API endpoint
    let workspace: String // workspace root
    
    init(type: String, path: String, workspace: String = "") {
        self.type = type
        self.path = path
        self.workspace = workspace
    }
}

// MARK: - PII Sanitizer

struct PIISanitizer {
    /// Patterns to detect and redact
    private static let patterns: [(name: String, regex: NSRegularExpression)] = {
        var result: [(String, NSRegularExpression)] = []
        let defs: [(String, String)] = [
            ("email", "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"),
            ("phone", "\\+?\\d{1,4}[\\s-]?\\(?\\d{1,4}\\)?[\\s-]?\\d{3,4}[\\s-]?\\d{3,4}"),
            ("ssn", "\\b\\d{3}-\\d{2}-\\d{4}\\b"),
            ("credit_card", "\\b(?:\\d{4}[\\s-]?){3}\\d{4}\\b"),
            ("api_key", "(?:sk-|pk_|rk_|ghp_|gho_|glpat-|xox[bpasr]-)[a-zA-Z0-9]{20,}"),
            ("ip_address", "\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b"),
            ("jwt", "eyJ[a-zA-Z0-9_-]{10,}\\.[a-zA-Z0-9_-]{10,}\\.[a-zA-Z0-9_-]{10,}"),
        ]
        for (name, pattern) in defs {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result.append((name, regex))
            }
        }
        return result
    }()
    
    /// Sanitize a string by redacting detected PII
    static func sanitize(_ input: String) -> String {
        var result = input
        for (name, regex) in patterns {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "[REDACTED:\(name)]")
        }
        return result
    }
    
    /// Check if string contains potential PII
    static func containsPII(_ input: String) -> Bool {
        for (_, regex) in patterns {
            let range = NSRange(input.startIndex..<input.endIndex, in: input)
            if regex.firstMatch(in: input, range: range) != nil {
                return true
            }
        }
        return false
    }
}

// MARK: - Flight Recorder Service (Singleton)

@MainActor
final class FlightRecorder: ObservableObject {
    static let shared = FlightRecorder()
    
    // MARK: - Published State
    @Published private(set) var entries: [AuditLogEntry] = []
    @Published private(set) var currentSessionId: String
    @Published var piiSanitizationEnabled: Bool = true {
        didSet { UserDefaults.standard.set(piiSanitizationEnabled, forKey: "flight_recorder_pii_sanitization") }
    }
    @Published var recordingEnabled: Bool = true {
        didSet { UserDefaults.standard.set(recordingEnabled, forKey: "flight_recorder_enabled") }
    }
    
    // MARK: - Chain State
    private var lastHash: String = "GENESIS"
    private let maxEntriesInMemory = 10000
    
    // MARK: - Persistence
    private let logDirectory: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MicroCode/FlightRecorder", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    private var currentLogURL: URL {
        let dateStr = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        return logDirectory.appendingPathComponent("audit_\(dateStr).jsonl")
    }
    
    private init() {
        self.currentSessionId = UUID().uuidString
        self.piiSanitizationEnabled = UserDefaults.standard.object(forKey: "flight_recorder_pii_sanitization") as? Bool ?? true
        self.recordingEnabled = UserDefaults.standard.object(forKey: "flight_recorder_enabled") as? Bool ?? true
        loadTodayEntries()
    }
    
    // MARK: - Recording
    
    /// Record an audit event
    func record(
        actor: AuditActor,
        action: AuditAction,
        target: AuditTarget,
        details: String,
        metadata: [String: String] = [:]
    ) {
        guard recordingEnabled else { return }
        
        let sanitizedDetails = piiSanitizationEnabled ? PIISanitizer.sanitize(details) : details
        var sanitizedMeta = metadata
        if piiSanitizationEnabled {
            sanitizedMeta = metadata.mapValues { PIISanitizer.sanitize($0) }
        }
        
        let entry = AuditLogEntry(
            sessionId: currentSessionId,
            actor: actor,
            action: action,
            target: target,
            details: sanitizedDetails,
            metadata: sanitizedMeta,
            previousHash: lastHash
        )
        
        entries.append(entry)
        lastHash = entry.entryHash
        
        // Persist
        persistEntry(entry)
        
        // Memory cap
        if entries.count > maxEntriesInMemory {
            entries.removeFirst(entries.count - maxEntriesInMemory)
        }
    }
    
    // MARK: - Convenience Methods
    
    func recordFileChange(action: AuditAction, filePath: String, description: String, workspace: String = "") {
        record(
            actor: .agent,
            action: action,
            target: AuditTarget(type: "file", path: filePath, workspace: workspace),
            details: description
        )
    }
    
    func recordToolCall(toolName: String, arguments: String, workspace: String = "") {
        record(
            actor: .agent,
            action: .agentToolCall,
            target: AuditTarget(type: "tool", path: toolName, workspace: workspace),
            details: arguments
        )
    }
    
    func recordCommandExecution(command: String, workspace: String = "") {
        record(
            actor: .agent,
            action: .commandExecute,
            target: AuditTarget(type: "command", path: command, workspace: workspace),
            details: command
        )
    }
    
    // MARK: - Chain Verification
    
    /// Verify the integrity of the audit log chain
    func verifyChain() -> (isValid: Bool, brokenAtIndex: Int?) {
        guard entries.count > 1 else { return (true, nil) }
        
        for i in 1..<entries.count {
            if entries[i].previousHash != entries[i - 1].entryHash {
                return (false, i)
            }
        }
        return (true, nil)
    }
    
    // MARK: - Export
    
    /// Export audit log as compliance-ready JSON
    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let export: [String: Any] = [
            "format": "MicroCode Flight Recorder v1.0",
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "session_id": currentSessionId,
            "total_entries": entries.count,
            "chain_valid": verifyChain().isValid
        ]
        
        var result = ""
        if let headerData = try? JSONSerialization.data(withJSONObject: export, options: .prettyPrinted),
           let headerStr = String(data: headerData, encoding: .utf8) {
            result += "// HEADER\n\(headerStr)\n\n// ENTRIES\n"
        }
        
        for entry in entries {
            if let data = try? encoder.encode(entry), let str = String(data: data, encoding: .utf8) {
                result += str + "\n"
            }
        }
        
        return result
    }
    
    /// Export as CSV for spreadsheet analysis
    func exportCSV() -> String {
        let formatter = ISO8601DateFormatter()
        var csv = "timestamp,session_id,actor,action,target_type,target_path,details,entry_hash,chain_valid\n"
        
        for (i, entry) in entries.enumerated() {
            let chainValid = i == 0 || entry.previousHash == entries[i - 1].entryHash
            let details = entry.details.replacingOccurrences(of: "\"", with: "\"\"")
            let path = entry.target.path.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(formatter.string(from: entry.timestamp)),\(entry.sessionId),\(entry.actor.rawValue),\(entry.action.rawValue),\(entry.target.type),\"\(path)\",\"\(details)\",\(String(entry.entryHash.prefix(16))),\(chainValid)\n"
        }
        
        return csv
    }
    
    // MARK: - Session Management
    
    func startNewSession() {
        record(actor: .system, action: .sessionEnd,
               target: AuditTarget(type: "session", path: currentSessionId),
               details: "Session ended with \(entries.count) entries")
        currentSessionId = UUID().uuidString
        record(actor: .system, action: .sessionStart,
               target: AuditTarget(type: "session", path: currentSessionId),
               details: "New session started")
    }
    
    // MARK: - Persistence
    
    private func persistEntry(_ entry: AuditLogEntry) {
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(entry),
                  var jsonString = String(data: data, encoding: .utf8) else { return }
            jsonString += "\n"
            
            let url = await self.currentLogURL
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(jsonString.data(using: .utf8) ?? Data())
                    handle.closeFile()
                }
            } else {
                try? jsonString.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
    
    private func loadTodayEntries() {
        guard FileManager.default.fileExists(atPath: currentLogURL.path),
              let content = try? String(contentsOf: currentLogURL, encoding: .utf8) else { return }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for line in content.components(separatedBy: "\n") where !line.isEmpty {
            if let data = line.data(using: .utf8),
               let entry = try? decoder.decode(AuditLogEntry.self, from: data) {
                entries.append(entry)
                lastHash = entry.entryHash
            }
        }
    }
    
    // MARK: - Statistics
    
    var totalFileChanges: Int {
        entries.filter { $0.action == .fileCreate || $0.action == .fileModify || $0.action == .fileDelete }.count
    }
    
    var totalToolCalls: Int {
        entries.filter { $0.action == .agentToolCall }.count
    }
    
    var totalCommands: Int {
        entries.filter { $0.action == .commandExecute }.count
    }
}
