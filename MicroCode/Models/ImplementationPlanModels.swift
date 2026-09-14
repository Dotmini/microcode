import Foundation
import SwiftUI

// MARK: - Plan Step Status

enum PlanStepStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case inProgress = "in_progress"
    case completed = "completed"
    case failed = "failed"
    case skipped = "skipped"
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        }
    }
    
    var statusIcon: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "bolt.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .skipped: return "arrow.right.circle"
        }
    }
    
    var statusColor: Color {
        switch self {
        case .pending: return .secondary
        case .inProgress: return .primary
        case .completed: return .primary.opacity(0.6)
        case .failed: return .primary.opacity(0.4)
        case .skipped: return .secondary.opacity(0.5)
        }
    }
}

// MARK: - Plan Step

struct PlanStep: Identifiable, Codable, Equatable {
    let id: String
    var description: String
    var status: PlanStepStatus
    var fileLink: String?
    var detail: String?
    var action: String? // "NEW", "MODIFY", "DELETE"
    
    init(
        id: String = UUID().uuidString,
        description: String,
        status: PlanStepStatus = .pending,
        fileLink: String? = nil,
        detail: String? = nil,
        action: String? = nil
    ) {
        self.id = id
        self.description = description
        self.status = status
        self.fileLink = fileLink
        self.detail = detail
        self.action = action
    }
}

// MARK: - Plan Section

struct PlanSection: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var steps: [PlanStep]
    
    init(
        id: String = UUID().uuidString,
        title: String,
        steps: [PlanStep] = []
    ) {
        self.id = id
        self.title = title
        self.steps = steps
    }
}

// MARK: - Plan Approval State

enum PlanApprovalState: String, Codable, CaseIterable, Equatable {
    case pending = "pending"
    case approved = "approved"
    case rejected = "rejected"
    case modified = "modified"
    
    var displayName: String {
        switch self {
        case .pending: return "Pending Review"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .modified: return "Modified"
        }
    }
    
    var icon: String {
        switch self {
        case .pending: return "clock.fill"
        case .approved: return "checkmark.seal.fill"
        case .rejected: return "xmark.seal.fill"
        case .modified: return "pencil.circle.fill"
        }
    }
}

// MARK: - Implementation Plan

struct ImplementationPlan: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    var summary: String
    var sections: [PlanSection]
    var openQuestions: [String]
    var verificationSteps: [String]
    var rawMarkdown: String
    var approvalState: PlanApprovalState
    var createdAt: Date
    
    init(
        id: String = UUID().uuidString,
        title: String,
        summary: String = "",
        sections: [PlanSection] = [],
        openQuestions: [String] = [],
        verificationSteps: [String] = [],
        rawMarkdown: String = "",
        approvalState: PlanApprovalState = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.sections = sections
        self.openQuestions = openQuestions
        self.verificationSteps = verificationSteps
        self.rawMarkdown = rawMarkdown
        self.approvalState = approvalState
        self.createdAt = createdAt
    }
    
    var totalSteps: Int {
        sections.reduce(0) { $0 + $1.steps.count }
    }
    
    var completedSteps: Int {
        sections.reduce(0) { total, section in
            total + section.steps.filter { $0.status == .completed }.count
        }
    }
    
    var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(completedSteps) / Double(totalSteps)
    }
}

// MARK: - SubAgent Event (for inline chat display)

public struct SubAgentEvent: Identifiable, Codable {
    public let id: String
    public let type: EventType
    public let subagentId: String
    public let role: String
    public let typeName: String
    public let timestamp: Date
    public var detail: String?
    
    public enum EventType: String, Codable {
        case invoked = "invoked"
        case completed = "completed"
        case errored = "errored"
        case killed = "killed"
    }
    
    init(
        id: String = UUID().uuidString,
        type: EventType,
        subagentId: String,
        role: String,
        typeName: String,
        timestamp: Date = Date(),
        detail: String? = nil
    ) {
        self.id = id
        self.type = type
        self.subagentId = subagentId
        self.role = role
        self.typeName = typeName
        self.timestamp = timestamp
        self.detail = detail
    }
}

// MARK: - Implementation Plan Manager

@MainActor
class ImplementationPlanManager: ObservableObject {
    static let shared = ImplementationPlanManager()
    
    @Published var currentPlan: ImplementationPlan?
    @Published var isPlanVisible: Bool = false
    @Published var planHistory: [ImplementationPlan] = []
    
    private var approvalContinuation: CheckedContinuation<Bool, Never>?
    
    private init() {}
    
    /// Present a plan and wait for user approval. Returns true if approved, false if rejected.
    func presentPlan(_ plan: ImplementationPlan) async -> Bool {
        // Safely cancel any pre-existing waiting continuation
        if let existing = self.approvalContinuation {
            existing.resume(returning: false)
            self.approvalContinuation = nil
        }
        
        self.currentPlan = plan
        self.isPlanVisible = true
        NotificationCenter.default.post(name: NSNotification.Name("MicroCodePlanUpdated"), object: plan)
        
        return await withCheckedContinuation { continuation in
            self.approvalContinuation = continuation
            
            // Auto-timeout after 5 minutes for plans (longer than tool approval)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                if let self = self, self.currentPlan?.id == plan.id, self.currentPlan?.approvalState == .pending {
                    self.reject()
                }
            }
        }
    }
    
    /// Present a plan from raw markdown content
    func presentMarkdownPlan(_ markdown: String, title: String = "Implementation Plan") async -> Bool {
        let plan = parseMarkdownPlan(markdown, title: title)
        return await presentPlan(plan)
    }
    
    /// Load plan from workspace's .microcode/task.md
    @discardableResult
    func loadFromTaskMarkdown(workspacePath: String) -> Bool {
        let taskURL = URL(fileURLWithPath: workspacePath).appendingPathComponent(".microcode/task.md")
        guard let content = try? String(contentsOf: taskURL, encoding: .utf8), !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        // If this is merely the default placeholder scaffold generated by the workspace template,
        // do NOT treat it as a concrete user-reviewed implementation plan.
        if content.contains("<!-- microcode:managed-task -->") &&
           (content.contains("Phase 1: Inspection & Baseline Analysis") ||
            content.contains("Inspect workspace files, dependencies, and existing architectural patterns") ||
            content.contains("Workspace Autonomous Task")) {
            return false
        }
        let plan = parseMarkdownPlan(content, title: "Implementation Plan")
        if !plan.sections.isEmpty || !plan.openQuestions.isEmpty || !plan.verificationSteps.isEmpty {
            self.currentPlan = plan
            NotificationCenter.default.post(name: NSNotification.Name("MicroCodePlanUpdated"), object: plan)
            return true
        }
        return false
    }
    
    func approve() {
        guard var plan = currentPlan else { return }
        plan.approvalState = .approved
        currentPlan = plan
        planHistory.append(plan)
        NotificationCenter.default.post(name: NSNotification.Name("MicroCodePlanUpdated"), object: plan)
        approvalContinuation?.resume(returning: true)
        approvalContinuation = nil
    }
    
    func reject() {
        guard var plan = currentPlan else { return }
        plan.approvalState = .rejected
        currentPlan = plan
        planHistory.append(plan)
        NotificationCenter.default.post(name: NSNotification.Name("MicroCodePlanUpdated"), object: plan)
        approvalContinuation?.resume(returning: false)
        approvalContinuation = nil
    }
    
    func clearPlan() {
        self.currentPlan = nil
        self.isPlanVisible = false
        if let existing = self.approvalContinuation {
            existing.resume(returning: false)
            self.approvalContinuation = nil
        }
        NotificationCenter.default.post(name: NSNotification.Name("MicroCodePlanUpdated"), object: nil)
    }
    
    func dismissPlan() {
        isPlanVisible = false
    }
    
    func updateStepStatus(sectionId: String, stepId: String, status: PlanStepStatus) {
        guard var plan = currentPlan else { return }
        for sIdx in plan.sections.indices {
            if plan.sections[sIdx].id == sectionId {
                for stIdx in plan.sections[sIdx].steps.indices {
                    if plan.sections[sIdx].steps[stIdx].id == stepId {
                        plan.sections[sIdx].steps[stIdx].status = status
                    }
                }
            }
        }
        currentPlan = plan
    }
    
    // MARK: - Markdown Parser
    
    func parseMarkdownPlan(_ markdown: String, title: String = "Implementation Plan") -> ImplementationPlan {
        let lines = markdown.components(separatedBy: "\n")
        
        var planTitle = title
        var summary = ""
        var sections: [PlanSection] = []
        var openQuestions: [String] = []
        var verificationSteps: [String] = []
        
        var currentSection: PlanSection?
        var currentSteps: [PlanStep] = []
        var inOpenQuestions = false
        var inVerification = false
        var inSummary = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // Parse title from # heading
            if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") {
                planTitle = String(trimmed.dropFirst(2))
                inSummary = true
                continue
            }
            
            // Parse section headers (### or Phase headers)
            if trimmed.hasPrefix("### ") {
                if let section = currentSection {
                    var s = section
                    s.steps = currentSteps
                    sections.append(s)
                }
                
                let sectionTitle = String(trimmed.dropFirst(4))
                currentSection = PlanSection(title: sectionTitle)
                currentSteps = []
                inOpenQuestions = false
                inVerification = false
                inSummary = false
                continue
            }
            
            // Detect open questions section
            if trimmed.hasPrefix("## Open Questions") || trimmed.hasPrefix("## User Review") || trimmed.hasPrefix("## Questions") {
                inOpenQuestions = true
                inVerification = false
                inSummary = false
                continue
            }
            
            // Detect verification section
            if trimmed.hasPrefix("## Verification") || trimmed.hasPrefix("## Testing") {
                inVerification = true
                inOpenQuestions = false
                inSummary = false
                continue
            }
            
            // Detect Proposed Changes ## header without ###
            if trimmed.hasPrefix("## Proposed Changes") || trimmed.hasPrefix("## Implementation Steps") || trimmed.hasPrefix("## Plan") {
                if currentSection == nil {
                    currentSection = PlanSection(title: "Proposed Changes")
                    currentSteps = []
                }
                inSummary = false
                inOpenQuestions = false
                inVerification = false
                continue
            }
            
            // Detect any other ## section
            if trimmed.hasPrefix("## ") {
                inSummary = false
                inOpenQuestions = false
                inVerification = false
                continue
            }
            
            // Collect summary text
            if inSummary && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("---") && !trimmed.hasPrefix("<!--") {
                if summary.isEmpty {
                    summary = trimmed
                } else {
                    summary += " " + trimmed
                }
                continue
            }
            
            // Parse list items (- or * or numbers)
            let isBullet = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
            let isNumbered = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil
            
            if isBullet || isNumbered {
                var content: String
                if isBullet {
                    content = String(trimmed.dropFirst(2))
                } else if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                    content = String(trimmed[match.upperBound...])
                } else {
                    content = trimmed
                }
                
                // Detect checkbox status
                var stepStatus: PlanStepStatus = .pending
                if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
                    stepStatus = .completed
                    content = String(content.dropFirst(4))
                } else if content.hasPrefix("[ ] ") {
                    stepStatus = .pending
                    content = String(content.dropFirst(4))
                }
                
                if inOpenQuestions {
                    openQuestions.append(content)
                } else if inVerification {
                    verificationSteps.append(content)
                } else {
                    if currentSection == nil {
                        currentSection = PlanSection(title: "Tasks")
                        currentSteps = []
                    }
                    
                    // Detect action type
                    var action: String? = nil
                    if content.contains("[NEW]") { action = "NEW" }
                    else if content.contains("[MODIFY]") { action = "MODIFY" }
                    else if content.contains("[DELETE]") { action = "DELETE" }
                    
                    // Extract fileLink from markdown link if present
                    var fileLink: String? = nil
                    if let linkStart = content.range(of: "file://"),
                       let linkEnd = content[linkStart.lowerBound...].firstIndex(of: ")") {
                        fileLink = String(content[linkStart.lowerBound..<linkEnd])
                    }
                    
                    currentSteps.append(PlanStep(
                        description: content,
                        status: stepStatus,
                        fileLink: fileLink,
                        action: action
                    ))
                }
                continue
            }
            
            // Parse #### file entries as steps
            if trimmed.hasPrefix("#### ") {
                var content = String(trimmed.dropFirst(5))
                var action: String? = nil
                if content.contains("[NEW]") { action = "NEW" }
                else if content.contains("[MODIFY]") { action = "MODIFY" }
                else if content.contains("[DELETE]") { action = "DELETE" }
                
                var fileLink: String? = nil
                if let linkStart = content.range(of: "file://"),
                   let linkEnd = content[linkStart.lowerBound...].firstIndex(of: ")") {
                    fileLink = String(content[linkStart.lowerBound..<linkEnd])
                }
                
                if currentSection == nil {
                    currentSection = PlanSection(title: "Files")
                    currentSteps = []
                }
                
                currentSteps.append(PlanStep(
                    description: content,
                    fileLink: fileLink,
                    action: action
                ))
            }
        }
        
        // Save last section
        if let section = currentSection {
            var s = section
            s.steps = currentSteps
            sections.append(s)
        }
        
        return ImplementationPlan(
            title: planTitle,
            summary: summary,
            sections: sections,
            openQuestions: openQuestions,
            verificationSteps: verificationSteps,
            rawMarkdown: markdown
        )
    }
}
