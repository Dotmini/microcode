//
//  TeamTasksView.swift
//  MicroCode
//

import SwiftUI

struct TeamTasksView: View {
    let workspacePath: String?
    let activeChatID: String?
    var onOpenInAgent: (() -> Void)? = nil

    @ObservedObject private var store = TeamTaskService.shared
    @ObservedObject private var integrations = TeamIntegrationService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isCreatingTask = false
    @State private var showingIntegrations = false
    @State private var handoffOwner = ""
    @State private var decisionText = ""

    var body: some View {
        Group {
            if integrations.teamTasksEnabled {
                HStack(spacing: 0) {
                    taskList.frame(width: 270)
                    Divider()
                    taskDetail
                }
            } else {
                teamTasksDisabledState
            }
        }
        .frame(minWidth: 760, minHeight: 510)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { store.load(workspacePath: workspacePath) }
        .sheet(isPresented: $isCreatingTask) {
            TeamTaskComposer(workspacePath: workspacePath, sourceChatID: activeChatID)
        }
        .sheet(isPresented: $showingIntegrations) {
            TeamIntegrationsSettings()
        }
    }

    private var teamTasksDisabledState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.secondary)
            Text("Team tasks are turned off").font(.system(size: 16, weight: .semibold))
            Text("Existing local task contracts are preserved. Enable the feature when this workspace needs collaboration.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 410)
            Button("Configure Team Collaboration") { showingIntegrations = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Team tasks").font(.system(size: 15, weight: .semibold))
                    Text("Shared contracts, not private prompts").font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer()
                Button { store.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Reload shared task board")
                Button { showingIntegrations = true } label: { Image(systemName: "bell") }
                    .buttonStyle(.plain).help("Slack and Microsoft Teams notifications")
                Button { isCreatingTask = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.bordered).help("Create shared task")
            }
            .padding(14)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if store.tasks.isEmpty {
                        TeamTasksEmptyState(
                            icon: "checklist",
                            title: "No shared tasks",
                            detail: "Create a task contract for the team or an agent."
                        )
                            .padding(.top, 80)
                    } else {
                        ForEach(store.tasks) { task in
                            Button { store.selectedTaskID = task.id } label: {
                                TeamTaskRow(task: task, selected: store.selectedTaskID == task.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private var taskDetail: some View {
        if let task = store.selectedTask {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title).font(.system(size: 19, weight: .semibold))
                        Text("Updated \(task.updatedAt.formatted(date: .abbreviated, time: .shortened)) by \(task.updatedBy)")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Menu(task.status.label) {
                        ForEach(TeamTaskStatus.allCases, id: \.self) { status in
                            Button(status.label) { store.updateStatus(status, taskID: task.id) }
                        }
                    }
                    .menuStyle(.borderedButton)
                }
                .padding(18)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        contractSection(title: "Objective", value: task.objective, empty: "No objective recorded")
                        contractSection(title: "Scope", value: task.scope, empty: "No scope recorded")
                        ownership(task)
                        decisionLog(task)
                    }
                    .padding(18)
                }
                Divider()
                HStack {
                    Text("The agent receives this contract only; chat transcripts remain private.")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                    Button("Use in Agent") { onOpenInAgent?(); dismiss() }
                        .buttonStyle(.borderedProminent)
                    Button(role: .destructive) { store.delete(taskID: task.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.bordered)
                }
                .padding(12)
            }
        } else {
            TeamTasksEmptyState(
                icon: "person.2",
                title: "Select a team task",
                detail: "Task contracts make handoff, review, and agent context explicit."
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func contractSection(title: String, value: String, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            Text(value.isEmpty ? empty : value)
                .font(.system(size: 13))
                .foregroundColor(value.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
        }
    }

    private func ownership(_ task: TeamTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ownership").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            HStack {
                Label(task.owner, systemImage: "person").font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Claim me") { store.claim(taskID: task.id) }.buttonStyle(.bordered)
                Button(task.followers.contains(AuthService.shared.currentUser?.displayName ?? "Local user") ? "Watching" : "Join") {
                    store.toggleFollowing(taskID: task.id)
                }
                .buttonStyle(.bordered)
            }
            HStack(spacing: 8) {
                TextField("Handoff to teammate", text: $handoffOwner).textFieldStyle(.roundedBorder)
                Button("Handoff") { store.handoff(taskID: task.id, to: handoffOwner); handoffOwner = "" }
                    .buttonStyle(.bordered)
                    .disabled(handoffOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("\(task.followers.count) collaborator\(task.followers.count == 1 ? "" : "s") following this task")
                .font(.system(size: 10)).foregroundColor(.secondary)
        }
    }

    private func decisionLog(_ task: TeamTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Decision log").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            if task.decisions.isEmpty {
                Text("Record decisions and blockers so the next person or agent can continue safely.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                ForEach(task.decisions.reversed()) { decision in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(decision.text).font(.system(size: 12))
                        Text("\(decision.author) · \(decision.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 9)).foregroundColor(.secondary)
                    }
                    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.035)).cornerRadius(5)
                }
            }
            HStack(spacing: 8) {
                TextField("Record a decision or blocker", text: $decisionText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveDecision(task) }
                Button("Add") { saveDecision(task) }.buttonStyle(.bordered)
                    .disabled(decisionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func saveDecision(_ task: TeamTask) {
        store.addDecision(decisionText, taskID: task.id)
        decisionText = ""
    }
}

private struct TeamTasksEmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.secondary)
            Text(title).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding(20)
    }
}

struct TeamIntegrationsSettings: View {
    @ObservedObject private var integrations = TeamIntegrationService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var slackURL = ""
    @State private var teamsURL = ""
    @State private var setupIntegration: TeamIntegration?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Team collaboration").font(.system(size: 17, weight: .semibold))
                    Text("Use Team tasks locally first. Notifications are optional.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("1. Work together in MicroCode", systemImage: "person.2")
                    .font(.system(size: 13, weight: .semibold))
                Toggle("Use Team tasks in this app", isOn: Binding(
                    get: { integrations.teamTasksEnabled },
                    set: { integrations.setTeamTasksEnabled($0) }
                ))
                .toggleStyle(.switch)
                Text("Creates a small shared task board inside the project. It contains tasks, owners, and decisions — never chat transcripts.")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Divider()
                Toggle("Let the Agent use the selected task", isOn: Binding(
                    get: { integrations.agentContextEnabled },
                    set: { integrations.setAgentContextEnabled($0) }
                ))
                .toggleStyle(.switch)
                .disabled(!integrations.teamTasksEnabled)
                Text("Turn this off if you want the Agent to work only from the current chat. No Team task data will be included in its request.")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.primary.opacity(0.035))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.16)))
            .cornerRadius(6)

            VStack(alignment: .leading, spacing: 9) {
                Label("2. Send task updates somewhere else (optional)", systemImage: "bell")
                    .font(.system(size: 13, weight: .semibold))
                Text("MicroCode can post a concise update when a task is created, assigned, or changes status. It does not read or reply to channel messages.")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                integrationRow(.slack, detail: "Post updates to a Slack channel.")
                integrationRow(.teams, detail: "Post updates to a Microsoft Teams channel.")
            }
            .padding(12)
            .background(Color.primary.opacity(0.035))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.16)))
            .cornerRadius(6)

            if let setupIntegration {
                connectionSetup(setupIntegration)
            }

            if let result = integrations.lastResult {
                Text(result).font(.system(size: 10)).foregroundColor(.secondary)
            }

            HStack {
                Text("External notifications include only task title, owner, status, and objective. URLs are stored in macOS Keychain.")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 590)
    }

    private func integrationRow(
        _ integration: TeamIntegration,
        detail: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: integration == .slack ? "bubble.left.and.bubble.right" : "person.2")
                .frame(width: 18).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(integration.title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            if integrations.isConfigured(integration) {
                Toggle("", isOn: Binding(
                    get: { integrations.isEnabled(integration) },
                    set: { integrations.setEnabled($0, for: integration) }
                ))
                .labelsHidden()
                Button("Manage") { setupIntegration = integration }
                    .buttonStyle(.bordered)
            } else {
                Button("Connect") { setupIntegration = integration }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func connectionSetup(_ integration: TeamIntegration) -> some View {
        let isSlack = integration == .slack
        let url = isSlack ? $slackURL : $teamsURL
        let placeholder = isSlack
            ? "https://hooks.slack.com/services/..."
            : "Paste a Teams Workflow webhook URL"
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Connect \(integration.title)").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { setupIntegration = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            Text(isSlack
                 ? "Create an Incoming Webhook in Slack, choose its channel, then paste the URL here."
                 : "Create a Teams Workflow with “When a Teams webhook request is received”, then paste its URL here.")
                .font(.system(size: 10)).foregroundColor(.secondary)
            HStack(spacing: 7) {
                TextField(placeholder, text: url).textFieldStyle(.roundedBorder)
                Button("Save") {
                    _ = integrations.saveWebhook(url.wrappedValue, for: integration)
                    if integrations.isConfigured(integration) {
                        url.wrappedValue = ""
                        setupIntegration = nil
                    }
                }
                .buttonStyle(.bordered)
                .disabled(url.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if integrations.isConfigured(integration) {
                    Button("Send test") { Task { await integrations.test(integration) } }
                        .buttonStyle(.bordered)
                    Button(role: .destructive) { integrations.remove(integration) } label: { Image(systemName: "trash") }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.16)))
        .cornerRadius(6)
    }
}

private struct TeamTaskRow: View {
    let task: TeamTask
    let selected: Bool
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1)
                Text("\(task.status.label) · \(task.owner)").font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            if task.followers.count > 1 { Text("\(task.followers.count)").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary) }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(selected ? Color.accentColor.opacity(0.14) : Color.clear).cornerRadius(5)
    }
    private var statusColor: Color {
        switch task.status {
        case .planned: return .secondary
        case .active: return .accentColor
        case .blocked: return .orange
        case .review: return .purple
        case .done: return .green
        }
    }
}

private struct TeamTaskComposer: View {
    let workspacePath: String?
    let sourceChatID: String?
    @ObservedObject private var store = TeamTaskService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var objective = ""
    @State private var scope = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create shared task").font(.system(size: 17, weight: .semibold))
            Text("Write a concise contract. Your raw chat prompt is not copied or shared.")
                .font(.system(size: 11)).foregroundColor(.secondary)
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 5) {
                Text("Objective").font(.system(size: 11, weight: .medium))
                TextEditor(text: $objective).font(.system(size: 12)).frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2)))
            }
            TextField("Scope (files, components, or boundaries)", text: $scope).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                Button("Create task") {
                    store.load(workspacePath: workspacePath)
                    _ = store.createTask(title: title, objective: objective, scope: scope, sourceChatID: sourceChatID)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || workspacePath == nil)
            }
        }
        .padding(22).frame(width: 470)
    }
}
