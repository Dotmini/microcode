//
//  TeamTasksView.swift
//  MicroCode
//

import SwiftUI

struct TeamTasksView: View {
    let workspacePath: String?
    let activeChatID: String?
    var onOpenInAgent: (() -> Void)? = nil
    var isEmbedded: Bool = false

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
                    taskList.frame(width: isEmbedded ? 225 : 270)
                    Divider().opacity(0.4)
                    taskDetail
                }
            } else {
                teamTasksDisabledState
            }
        }
        .frame(
            minWidth: isEmbedded ? nil : 760,
            maxWidth: .infinity,
            minHeight: isEmbedded ? 420 : 510
        )
        .background(Color(nsColor: isEmbedded ? .controlBackgroundColor : .windowBackgroundColor))
        .cornerRadius(isEmbedded ? 10 : 0)
        .overlay(
            RoundedRectangle(cornerRadius: isEmbedded ? 10 : 0)
                .stroke(Color.primary.opacity(isEmbedded ? 0.08 : 0), lineWidth: 1)
        )
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
                .font(.system(size: 26, weight: .light))
                .foregroundColor(.secondary)
            Text("Team tasks are turned off").font(.system(size: 14, weight: .semibold))
            Text("Existing local task contracts are preserved. Enable the feature when this workspace needs collaboration.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 410)
            Button {
                showingIntegrations = true
            } label: {
                Text("Configure Team Collaboration")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.09))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.18), lineWidth: 1))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Team Tasks").font(.system(size: 13.5, weight: .semibold))
                    Text("Shared contracts").font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer()
                Button { store.reload() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundColor(.secondary).help("Reload shared task board")
                Button { showingIntegrations = true } label: { Image(systemName: "bell").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundColor(.secondary).help("Slack and Microsoft Teams notifications")
                Button { isCreatingTask = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Create shared task")
            }
            .padding(12)
            Divider().opacity(0.4)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if store.tasks.isEmpty {
                        TeamTasksEmptyState(
                            icon: "checklist",
                            title: "No shared tasks",
                            detail: "Create a task contract for the team or an agent."
                        )
                            .padding(.top, 60)
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title).font(.system(size: 16, weight: .semibold))
                        Text("Updated \(task.updatedAt.formatted(date: .abbreviated, time: .shortened)) by \(task.updatedBy)")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(TeamTaskStatus.allCases, id: \.self) { status in
                            Button(status.label) { store.updateStatus(status, taskID: task.id) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(task.status.label)
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.07))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                Divider().opacity(0.4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        contractSection(title: "Objective", value: task.objective, empty: "No objective recorded")
                        contractSection(title: "Scope", value: task.scope, empty: "No scope recorded")
                        ownership(task)
                        decisionLog(task)
                    }
                    .padding(14)
                }
                Divider().opacity(0.4)
                HStack {
                    Text("The agent receives this contract only; chat transcripts remain private.")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        onOpenInAgent?()
                        if !isEmbedded { dismiss() }
                    } label: {
                        Text("Use in Agent")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.09))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.18), lineWidth: 1))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    Button {
                        store.delete(taskID: task.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
            }
        } else {
            TeamTasksEmptyState(
                icon: "person.2",
                title: "Select a team task",
                detail: "Task contracts make handoff, review, and agent context explicit."
            )
                .frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
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
                Button {
                    store.claim(taskID: task.id)
                } label: {
                    Text("Claim me")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                Button {
                    store.toggleFollowing(taskID: task.id)
                } label: {
                    Text(task.followers.contains(store.currentActorName) ? "Watching" : "Watch")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                TextField("Handoff to teammate", text: $handoffOwner)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.09), lineWidth: 1))
                    .cornerRadius(5)
                Button {
                    store.handoff(taskID: task.id, to: handoffOwner)
                    handoffOwner = ""
                } label: {
                    Text("Handoff")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.07))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
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
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.09), lineWidth: 1))
                    .cornerRadius(5)
                    .onSubmit { saveDecision(task) }
                Button {
                    saveDecision(task)
                } label: {
                    Text("Add")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.07))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
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
                    Text("Team Collaboration").font(.system(size: 16, weight: .semibold))
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
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.09)))
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
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.09)))
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
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.09))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.18), lineWidth: 1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
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
                Button {
                    setupIntegration = integration
                } label: {
                    Text("Manage")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.07))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    setupIntegration = integration
                } label: {
                    Text("Connect")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.07))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
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
                TextField(placeholder, text: url)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.09), lineWidth: 1))
                    .cornerRadius(5)
                Button {
                    _ = integrations.saveWebhook(url.wrappedValue, for: integration)
                    if integrations.isConfigured(integration) {
                        url.wrappedValue = ""
                        setupIntegration = nil
                    }
                } label: {
                    Text("Save")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(url.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if integrations.isConfigured(integration) {
                    Button {
                        Task { await integrations.test(integration) }
                    } label: {
                        Text("Send test")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    Button {
                        integrations.remove(integration)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.09)))
        .cornerRadius(6)
    }
}

private struct TeamTaskRow: View {
    let task: TeamTask
    let selected: Bool
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1)
                Text("\(task.status.label) · \(task.owner)").font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            if task.followers.count > 1 { Text("\(task.followers.count)").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary) }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(selected ? Color.primary.opacity(0.09) : Color.clear).cornerRadius(5)
    }
    private var statusColor: Color {
        switch task.status {
        case .planned: return Color.secondary.opacity(0.45)
        case .active: return Color.primary.opacity(0.85)
        case .blocked: return Color.primary.opacity(0.55)
        case .review: return Color.primary.opacity(0.70)
        case .done: return Color.secondary.opacity(0.65)
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
            Text("Create Shared Task").font(.system(size: 16, weight: .semibold))
            Text("Write a concise contract. Your raw chat prompt is not copied or shared.")
                .font(.system(size: 11)).foregroundColor(.secondary)
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.09), lineWidth: 1))
                .cornerRadius(6)
            VStack(alignment: .leading, spacing: 5) {
                Text("Objective").font(.system(size: 11, weight: .medium))
                TextEditor(text: $objective).font(.system(size: 12)).frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.1)))
            }
            TextField("Scope (files, components, or boundaries)", text: $scope)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.09), lineWidth: 1))
                .cornerRadius(6)
            HStack(spacing: 8) {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                Button {
                    store.load(workspacePath: workspacePath)
                    _ = store.createTask(title: title, objective: objective, scope: scope, sourceChatID: sourceChatID)
                    dismiss()
                } label: {
                    Text("Create Task")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.09))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.18), lineWidth: 1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || workspacePath == nil)
            }
        }
        .padding(22).frame(width: 470)
    }
}
