//
//  TeamTaskService.swift
//  MicroCode
//
//  Shared task contracts: a reviewable collaboration layer that intentionally
//  excludes private chat prompts and transcripts.
//

import Foundation
import Combine

enum TeamTaskStatus: String, Codable, CaseIterable {
    case planned, active, blocked, review, done

    var label: String {
        switch self {
        case .planned: return "Planned"
        case .active: return "In progress"
        case .blocked: return "Blocked"
        case .review: return "Review"
        case .done: return "Done"
        }
    }
}

struct TeamTaskDecision: Identifiable, Codable, Hashable {
    let id: String
    var text: String
    var author: String
    var createdAt: Date
}

struct TeamTask: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var objective: String
    var scope: String
    var status: TeamTaskStatus
    var owner: String
    var followers: [String]
    var decisions: [TeamTaskDecision]
    var sourceChatID: String?
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String
}

private struct TeamTaskDocument: Codable {
    var schemaVersion: Int = 1
    var updatedAt: Date
    var tasks: [TeamTask]
}

@MainActor
final class TeamTaskService: ObservableObject {
    static let shared = TeamTaskService()

    @Published private(set) var tasks: [TeamTask] = []
    @Published var selectedTaskID: String?
    @Published private(set) var workspacePath: String?
    @Published private(set) var lastError: String?

    var selectedTask: TeamTask? {
        selectedTaskID.flatMap { selectedID in tasks.first(where: { $0.id == selectedID }) }
    }

    func load(workspacePath: String?) {
        guard let workspacePath, !workspacePath.isEmpty else {
            self.workspacePath = nil
            tasks = []
            selectedTaskID = nil
            return
        }
        self.workspacePath = workspacePath
        lastError = nil
        let url = documentURL(for: workspacePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            tasks = []
            selectedTaskID = nil
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(TeamTaskDocument.self, from: Data(contentsOf: url))
            tasks = document.tasks.sorted { $0.updatedAt > $1.updatedAt }
            if selectedTaskID == nil || !tasks.contains(where: { $0.id == selectedTaskID }) {
                selectedTaskID = tasks.first?.id
            }
        } catch {
            lastError = "Unable to read shared tasks: \(error.localizedDescription)"
        }
    }

    func reload() { load(workspacePath: workspacePath) }

    @discardableResult
    func createTask(title: String, objective: String, scope: String, sourceChatID: String? = nil) -> TeamTask? {
        guard TeamIntegrationService.shared.teamTasksEnabled else { return nil }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let actor = currentActorName
        let task = TeamTask(
            id: UUID().uuidString,
            title: title,
            objective: objective.trimmingCharacters(in: .whitespacesAndNewlines),
            scope: scope.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .planned,
            owner: actor,
            followers: [actor],
            decisions: [],
            sourceChatID: sourceChatID,
            createdAt: Date(),
            updatedAt: Date(),
            updatedBy: actor
        )
        tasks.insert(task, at: 0)
        selectedTaskID = task.id
        persist()
        notify(.created, task: task)
        return task
    }

    func updateStatus(_ status: TeamTaskStatus, taskID: String) {
        guard TeamIntegrationService.shared.teamTasksEnabled else { return }
        update(taskID, event: .statusChanged) { $0.status = status }
    }

    func claim(taskID: String) {
        guard TeamIntegrationService.shared.teamTasksEnabled else { return }
        update(taskID, event: .claimed) { task in
            task.owner = currentActorName
            if !task.followers.contains(currentActorName) { task.followers.append(currentActorName) }
            if task.status == .planned { task.status = .active }
        }
    }

    func handoff(taskID: String, to owner: String) {
        guard TeamIntegrationService.shared.teamTasksEnabled else { return }
        let owner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else { return }
        update(taskID, event: .handedOff) { task in
            task.owner = owner
            task.decisions.append(TeamTaskDecision(id: UUID().uuidString, text: "Handed off to \(owner).", author: currentActorName, createdAt: Date()))
        }
    }

    func toggleFollowing(taskID: String) {
        guard TeamIntegrationService.shared.teamTasksEnabled else { return }
        update(taskID) { task in
            if let index = task.followers.firstIndex(of: currentActorName) {
                task.followers.remove(at: index)
            } else {
                task.followers.append(currentActorName)
            }
        }
    }

    func addDecision(_ text: String, taskID: String) {
        guard TeamIntegrationService.shared.teamTasksEnabled else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        update(taskID) { task in
            task.decisions.append(TeamTaskDecision(id: UUID().uuidString, text: text, author: currentActorName, createdAt: Date()))
            if task.decisions.count > 24 { task.decisions.removeFirst(task.decisions.count - 24) }
        }
    }

    func delete(taskID: String) {
        guard TeamIntegrationService.shared.teamTasksEnabled else { return }
        tasks.removeAll { $0.id == taskID }
        if selectedTaskID == taskID { selectedTaskID = tasks.first?.id }
        persist()
    }

    /// Only this structured, attributable contract is supplied to an agent.
    /// Full prompts and messages remain in their originating private chat.
    func contextForSelectedTask() -> String? {
        guard TeamIntegrationService.shared.teamTasksEnabled,
              TeamIntegrationService.shared.agentContextEnabled,
              let task = selectedTask else { return nil }
        var context = """
        ## Shared Team Task Contract
        Task: \(task.title)
        Status: \(task.status.label)
        Owner: \(task.owner)
        Objective: \(task.objective.isEmpty ? "Not specified" : task.objective)
        Scope: \(task.scope.isEmpty ? "Not specified" : task.scope)
        """
        if !task.decisions.isEmpty {
            context += "\nRecent decisions:\n" + task.decisions.suffix(4).map { "- \($0.text) (\($0.author))" }.joined(separator: "\n")
        }
        context += "\nUse this contract as the collaboration boundary. Do not infer or reveal private prompts from other chats. Report blockers and validation evidence clearly."
        return context
    }

    private var currentActorName: String { AuthService.shared.currentUser?.displayName ?? "Local user" }

    private func update(_ taskID: String, event: TeamTaskEvent? = nil, mutation: (inout TeamTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        mutation(&tasks[index])
        tasks[index].updatedAt = Date()
        tasks[index].updatedBy = currentActorName
        tasks.sort { $0.updatedAt > $1.updatedAt }
        persist()
        if let event, let task = tasks.first(where: { $0.id == taskID }) {
            notify(event, task: task)
        }
    }

    private func notify(_ event: TeamTaskEvent, task: TeamTask) {
        Task { await TeamIntegrationService.shared.publish(event: event, task: task) }
    }

    private func documentURL(for workspace: String) -> URL {
        URL(fileURLWithPath: workspace)
            .appendingPathComponent(".microcode", isDirectory: true)
            .appendingPathComponent("team-tasks.json")
    }

    private func persist() {
        guard let workspacePath else { return }
        let url = documentURL(for: workspacePath)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(TeamTaskDocument(updatedAt: Date(), tasks: tasks)).write(to: url, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Unable to save shared tasks: \(error.localizedDescription)"
        }
    }
}
