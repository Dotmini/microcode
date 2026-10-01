import Foundation
import Combine

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
    let id: UUID
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
    @Published private(set) var pendingRequest: ToolApprovalRequest?
    @Published var approvalHistory: [ToolApprovalHistoryEntry] = []
    @Published var alwaysAllowedTools: Set<String> = ["file_read", "get_diagnostics", "list_directory"]
    
    private var queue: [ToolApprovalRequest] = []
    private var timeouts: [UUID: Task<Void, Never>] = [:]

    func requestApproval(toolName: String, arguments: [String: String], description: String) async -> Bool {
        guard !Task.isCancelled else { return false }
        if mode == .yolo { return true }
        let risk = classifyRisk(toolName: toolName, arguments: arguments)
        if mode != .safe && (alwaysAllowedTools.contains(toolName) || (mode == .smart && risk == .safe)) { return true }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: false); return }
                queue.append(ToolApprovalRequest(id: id, toolName: toolName, arguments: arguments,
                    riskLevel: risk, description: description, timestamp: Date(), continuation: continuation))
                presentNext()
            }
        } onCancel: {
            Task { @MainActor in self.resolve(id: id, approved: false) }
        }
    }

    private func presentNext() {
        guard pendingRequest == nil, !queue.isEmpty else { return }
        let request = queue.removeFirst()
        pendingRequest = request
        timeouts[request.id] = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
            self.resolve(id: request.id, approved: false)
        }
    }

    private func resolve(id: UUID, approved: Bool) {
        let request: ToolApprovalRequest
        if pendingRequest?.id == id {
            request = pendingRequest!
            pendingRequest = nil
        } else if let index = queue.firstIndex(where: { $0.id == id }) {
            request = queue.remove(at: index)
        } else { return }
        timeouts.removeValue(forKey: id)?.cancel()
        request.continuation?.resume(returning: approved)
        approvalHistory.append(ToolApprovalHistoryEntry(toolName: request.toolName, approved: approved, timestamp: Date()))
        if approvalHistory.count > 300 { approvalHistory.removeFirst(approvalHistory.count - 300) }
        presentNext()
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
    
    func cancelAll() {
        let ids = queue.map(\.id) + (pendingRequest.map { [$0.id] } ?? [])
        for id in ids { resolve(id: id, approved: false) }
    }

    func approve() {
        if let id = pendingRequest?.id { resolve(id: id, approved: true) }
    }

    func reject() {
        if let id = pendingRequest?.id { resolve(id: id, approved: false) }
    }

    func alwaysAllow(toolName: String) {
        guard let request = pendingRequest else { return }
        alwaysAllowedTools.insert(request.toolName)
        approve()
    }
}
