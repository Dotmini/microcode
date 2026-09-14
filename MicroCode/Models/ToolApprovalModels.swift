import Foundation

enum ToolApprovalMode: String, Codable, CaseIterable {
    case safe = "safe"           // Ask before every tool execution
    case smart = "smart"         // Ask only for dangerous operations
    case yolo = "yolo"           // Never ask, auto-approve everything
    
    var displayName: String {
        switch self {
        case .safe: return "Safe"
        case .smart: return "Smart"
        case .yolo: return "YOLO"
        }
    }
    
    var icon: String {
        switch self {
        case .safe: return "lock.shield"
        case .smart: return "brain.head.profile"
        case .yolo: return "flame.fill"
        }
    }
    
    var description: String {
        switch self {
        case .safe: return "Ask before every tool execution"
        case .smart: return "Ask only for dangerous operations"
        case .yolo: return "Never ask, auto-approve everything"
        }
    }
}

enum ToolRiskLevel: String {
    case safe = "safe"           // file_read, get_diagnostics
    case moderate = "moderate"   // file_write, patch_file
    case dangerous = "dangerous" // shell, delete operations
    case critical = "critical"   // rm -rf, DROP TABLE, etc.
}

struct ToolApprovalRequest: Identifiable {
    let id = UUID()
    let toolName: String
    let arguments: [String: String]
    let riskLevel: ToolRiskLevel
    let description: String
    let timestamp: Date
    var continuation: CheckedContinuation<Bool, Never>?
}

struct ToolApprovalHistoryEntry: Identifiable {
    let id = UUID()
    let toolName: String
    let approved: Bool
    let timestamp: Date
}

@MainActor
class ToolApprovalManager: ObservableObject {
    static let shared = ToolApprovalManager()
    
    @Published var mode: ToolApprovalMode = .smart
    @Published var pendingRequest: ToolApprovalRequest?
    @Published var approvalHistory: [ToolApprovalHistoryEntry] = []
    @Published var alwaysAllowedTools: Set<String> = ["file_read", "get_diagnostics", "list_directory"]
    
    func requestApproval(toolName: String, arguments: [String: String], description: String) async -> Bool {
        if mode == .yolo { return true }
        if alwaysAllowedTools.contains(toolName) { return true }
        
        let risk = classifyRisk(toolName: toolName, arguments: arguments)
        
        if mode == .smart && risk == .safe {
            return true
        }
        
        return await withCheckedContinuation { continuation in
            let request = ToolApprovalRequest(
                toolName: toolName,
                arguments: arguments,
                riskLevel: risk,
                description: description,
                timestamp: Date(),
                continuation: continuation
            )
            self.pendingRequest = request
            
            // Auto timeout after 60s
            Task {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if self.pendingRequest?.id == request.id {
                    self.reject()
                }
            }
        }
    }
    
    func classifyRisk(toolName: String, arguments: [String: String]) -> ToolRiskLevel {
        switch toolName {
        case "shell", "adb_shell", "delete_file", "drop_table":
            if let cmd = arguments["command"] ?? arguments["CommandLine"] {
                if cmd.contains("rm -rf") || cmd.contains("drop") {
                    return .critical
                }
            }
            return .dangerous
        case "file_write", "patch_file", "replace_in_file", "execute_sql":
            return .moderate
        case "file_read", "get_diagnostics", "list_directory_tree", "grep_search", "find_symbol":
            return .safe
        default:
            return .moderate
        }
    }
    
    func approve() {
        guard let request = pendingRequest else { return }
        request.continuation?.resume(returning: true)
        approvalHistory.append(ToolApprovalHistoryEntry(toolName: request.toolName, approved: true, timestamp: Date()))
        pendingRequest = nil
    }
    
    func reject() {
        guard let request = pendingRequest else { return }
        request.continuation?.resume(returning: false)
        approvalHistory.append(ToolApprovalHistoryEntry(toolName: request.toolName, approved: false, timestamp: Date()))
        pendingRequest = nil
    }
    
    func alwaysAllow(toolName: String) {
        guard let request = pendingRequest else { return }
        alwaysAllowedTools.insert(request.toolName)
        approve()
    }
}
