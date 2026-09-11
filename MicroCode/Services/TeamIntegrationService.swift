//
//  TeamIntegrationService.swift
//  MicroCode
//
//  Outbound notifications for shared team tasks. Secrets live in Keychain and
//  outgoing messages intentionally never contain chat transcripts.
//

import Foundation
import Combine

enum TeamIntegration: String, Codable, CaseIterable, Identifiable {
    case slack
    case teams

    var id: String { rawValue }
    var title: String { self == .slack ? "Slack" : "Microsoft Teams" }
    var keychainAccount: String { "TEAM_WEBHOOK_\(rawValue.uppercased())" }
}

enum TeamTaskEvent: String {
    case created = "created"
    case statusChanged = "changed status"
    case claimed = "claimed"
    case handedOff = "handed off"
    case updated = "updated"
}

private struct TeamIntegrationConfiguration: Codable {
    /// Collaboration data stays local until a user explicitly enables one of
    /// the outbound connectors below.  These switches let teams keep task
    /// contracts and agent context independently configurable.
    var teamTasksEnabled: Bool = true
    var agentContextEnabled: Bool = true
    var enabled: [String: Bool] = [:]

    private enum CodingKeys: String, CodingKey {
        case teamTasksEnabled, agentContextEnabled, enabled
    }

    init(teamTasksEnabled: Bool = true, agentContextEnabled: Bool = true, enabled: [String: Bool] = [:]) {
        self.teamTasksEnabled = teamTasksEnabled
        self.agentContextEnabled = agentContextEnabled
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teamTasksEnabled = try container.decodeIfPresent(Bool.self, forKey: .teamTasksEnabled) ?? true
        agentContextEnabled = try container.decodeIfPresent(Bool.self, forKey: .agentContextEnabled) ?? true
        enabled = try container.decodeIfPresent([String: Bool].self, forKey: .enabled) ?? [:]
    }
}

@MainActor
final class TeamIntegrationService: ObservableObject {
    static let shared = TeamIntegrationService()

    @Published private(set) var enabled: [String: Bool] = [:]
    @Published private(set) var teamTasksEnabled = true
    @Published private(set) var agentContextEnabled = true
    @Published private(set) var lastResult: String?

    private let defaultsKey = "microcode.team-integrations.v1"
    private let keychain = KeychainManager.shared

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let config = try? JSONDecoder().decode(TeamIntegrationConfiguration.self, from: data) {
            enabled = config.enabled
            teamTasksEnabled = config.teamTasksEnabled
            agentContextEnabled = config.agentContextEnabled
        }
    }

    func setTeamTasksEnabled(_ value: Bool) {
        teamTasksEnabled = value
        persistConfiguration()
    }

    func setAgentContextEnabled(_ value: Bool) {
        agentContextEnabled = value
        persistConfiguration()
    }

    func isConfigured(_ integration: TeamIntegration) -> Bool {
        keychain.readIntegrationSecret(account: integration.keychainAccount) != nil
    }

    func isEnabled(_ integration: TeamIntegration) -> Bool {
        enabled[integration.rawValue] == true && isConfigured(integration)
    }

    @discardableResult
    func saveWebhook(_ rawURL: String, for integration: TeamIntegration) -> Bool {
        let rawURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validate(rawURL, for: integration) else {
            lastResult = "Invalid \(integration.title) webhook URL."
            return false
        }
        guard keychain.saveIntegrationSecret(rawURL, account: integration.keychainAccount) else {
            lastResult = "Could not save \(integration.title) credential in Keychain."
            return false
        }
        enabled[integration.rawValue] = true
        persistConfiguration()
        lastResult = "\(integration.title) is connected."
        return true
    }

    func setEnabled(_ value: Bool, for integration: TeamIntegration) {
        guard !value || isConfigured(integration) else {
            lastResult = "Add a \(integration.title) webhook first."
            return
        }
        enabled[integration.rawValue] = value
        persistConfiguration()
    }

    func remove(_ integration: TeamIntegration) {
        _ = keychain.deleteIntegrationSecret(account: integration.keychainAccount)
        enabled[integration.rawValue] = false
        persistConfiguration()
        lastResult = "\(integration.title) disconnected."
    }

    func test(_ integration: TeamIntegration) async {
        guard let url = keychain.readIntegrationSecret(account: integration.keychainAccount) else {
            lastResult = "Add a \(integration.title) webhook first."
            return
        }
        do {
            try await send(text: "MicroCode connected. Team task notifications are ready.", to: integration, url: url)
            lastResult = "Test delivered to \(integration.title)."
        } catch {
            lastResult = "\(integration.title) test failed: \(error.localizedDescription)"
        }
    }

    func publish(event: TeamTaskEvent, task: TeamTask) async {
        let targets = TeamIntegration.allCases.filter(isEnabled)
        guard !targets.isEmpty else { return }
        let text = taskSummary(event: event, task: task)
        for target in targets {
            guard let url = keychain.readIntegrationSecret(account: target.keychainAccount) else { continue }
            do {
                try await send(text: text, to: target, url: url)
                lastResult = "Task update sent to \(target.title)."
            } catch {
                lastResult = "Could not notify \(target.title): \(error.localizedDescription)"
            }
        }
    }

    private func send(text: String, to integration: TeamIntegration, url rawURL: String) async throws {
        guard let url = URL(string: rawURL) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func validate(_ rawURL: String, for integration: TeamIntegration) -> Bool {
        guard let url = URL(string: rawURL), url.scheme == "https", url.host != nil else { return false }
        if integration == .slack { return url.host == "hooks.slack.com" }
        return true // Teams Workflow URLs use the tenant's Power Automate host.
    }

    private func taskSummary(event: TeamTaskEvent, task: TeamTask) -> String {
        let objective = task.objective.isEmpty ? "No objective recorded" : String(task.objective.prefix(1_200))
        return """
        MicroCode team task \(event.rawValue)
        • \(task.title)
        Status: \(task.status.label) · Owner: \(task.owner)
        Objective: \(objective)
        """
    }

    private func persistConfiguration() {
        UserDefaults.standard.set(
            try? JSONEncoder().encode(TeamIntegrationConfiguration(
                teamTasksEnabled: teamTasksEnabled,
                agentContextEnabled: agentContextEnabled,
                enabled: enabled
            )),
            forKey: defaultsKey
        )
    }
}
