//
//  RemoteProviderService.swift
//  MicroCode
//
//  Provider API-key shortcut: paste a RunPod / Vast.ai API key, list your
//  running instances, pick one — MicroCode derives the SSH target and hands
//  it to RemoteGPUService (the SSH auto-bootstrap path). One click, no SSH
//  command, no token typing.
//
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import Foundation
import Combine

@MainActor
final class RemoteProviderService: ObservableObject {
    static let shared = RemoteProviderService()

    enum Provider: String, CaseIterable, Identifiable {
        case runpod = "RunPod"
        case vast = "Vast.ai"
        case lambda = "Lambda Cloud"
        var id: String { rawValue }

        var keychainAccount: String {
            switch self {
            case .runpod: return "cloud_gpu_runpod_api_key"
            case .vast:   return "cloud_gpu_vast_api_key"
            case .lambda: return "cloud_gpu_lambda_api_key"
            }
        }

        var legacyDefaultsKey: String {
            switch self {
            case .runpod: return "runpodApiKey"
            case .vast:   return "vastApiKey"
            case .lambda: return "lambdaApiKey"
            }
        }
    }

    struct Instance: Identifiable, Equatable {
        let id: String
        let label: String      // shown in the picker (gpu + name + status)
        let sshHost: String
        let sshPort: Int
        let user: String
        let running: Bool
        var statusText: String = "RUNNING"
        var costPerHourUSD: Double? = nil
    }

    @Published var instances: [Instance] = []
    @Published var isLoading = false
    @Published var actionBusyId: String? = nil
    @Published var error: String = ""
    @Published var statusMessage: String = ""

    func apiKey(for provider: Provider) -> String {
        if let saved = KeychainManager.shared.readIntegrationSecret(account: provider.keychainAccount), !saved.isEmpty {
            return saved
        }
        if let legacy = UserDefaults.standard.string(forKey: provider.legacyDefaultsKey), !legacy.isEmpty {
            KeychainManager.shared.saveIntegrationSecret(legacy, account: provider.keychainAccount)
            UserDefaults.standard.removeObject(forKey: provider.legacyDefaultsKey)
            return legacy
        }
        return ""
    }

    func setApiKey(_ key: String, for provider: Provider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainManager.shared.deleteIntegrationSecret(account: provider.keychainAccount)
        } else {
            KeychainManager.shared.saveIntegrationSecret(trimmed, account: provider.keychainAccount)
        }
        UserDefaults.standard.removeObject(forKey: provider.legacyDefaultsKey)
    }

    func listInstances(provider: Provider, apiKey: String) async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { error = "Enter your \(provider.rawValue) API key."; return }
        setApiKey(key, for: provider)
        isLoading = true; error = ""; statusMessage = ""; instances = []
        defer { isLoading = false }
        do {
            switch provider {
            case .runpod: instances = try await fetchRunPod(key)
            case .vast:   instances = try await fetchVast(key)
            case .lambda: instances = try await fetchLambda(key)
            }
            if instances.isEmpty { error = "No instances found for this \(provider.rawValue) account." }
        } catch {
            self.error = "Failed: \(error.localizedDescription)"
        }
    }

    /// Build the SSH command RemoteGPUService expects.
    func sshCommand(for i: Instance) -> String {
        guard !i.sshHost.isEmpty else { return "" }
        return "ssh -p \(i.sshPort) \(i.user)@\(i.sshHost)"
    }

    // MARK: - Pod / Instance Lifecycle Controls (Start / Stop / Terminate)

    func startInstance(provider: Provider, apiKey: String, instanceId: String) async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { error = "Missing API key."; return }
        actionBusyId = instanceId; error = ""; statusMessage = ""
        defer { actionBusyId = nil }
        do {
            switch provider {
            case .runpod:
                let query = #"{"query":"mutation($id:String!){podResume(input:{podId:$id,gpuCount:1}){id desiredStatus}}","variables":{"id":"\#(instanceId)"}}"#
                try await runpodGraphQL(key: key, body: query)
            case .vast:
                try await vastStateChange(key: key, instanceId: instanceId, method: "PUT", body: ["state": "running"])
            case .lambda:
                throw NSError(domain: "Lambda", code: 400, userInfo: [NSLocalizedDescriptionKey: "Lambda Cloud instances do not support stop/resume; launch a new instance instead."])
            }
            statusMessage = "Started instance \(instanceId)."
            await listInstances(provider: provider, apiKey: key)
        } catch {
            self.error = "Start failed: \(error.localizedDescription)"
        }
    }

    func stopInstance(provider: Provider, apiKey: String, instanceId: String) async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { error = "Missing API key."; return }
        actionBusyId = instanceId; error = ""; statusMessage = ""
        defer { actionBusyId = nil }
        do {
            switch provider {
            case .runpod:
                let query = #"{"query":"mutation($id:String!){podStop(input:{podId:$id}){id desiredStatus}}","variables":{"id":"\#(instanceId)"}}"#
                try await runpodGraphQL(key: key, body: query)
            case .vast:
                try await vastStateChange(key: key, instanceId: instanceId, method: "PUT", body: ["state": "stopped"])
            case .lambda:
                try await lambdaTerminate(key: key, instanceId: instanceId)
            }
            statusMessage = "Stopped instance \(instanceId)."
            await listInstances(provider: provider, apiKey: key)
        } catch {
            self.error = "Stop failed: \(error.localizedDescription)"
        }
    }

    func terminateInstance(provider: Provider, apiKey: String, instanceId: String) async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { error = "Missing API key."; return }
        actionBusyId = instanceId; error = ""; statusMessage = ""
        defer { actionBusyId = nil }
        do {
            switch provider {
            case .runpod:
                let query = #"{"query":"mutation($id:String!){podTerminate(input:{podId:$id})}","variables":{"id":"\#(instanceId)"}}"#
                try await runpodGraphQL(key: key, body: query)
            case .vast:
                try await vastStateChange(key: key, instanceId: instanceId, method: "DELETE", body: nil)
            case .lambda:
                try await lambdaTerminate(key: key, instanceId: instanceId)
            }
            statusMessage = "Terminated instance \(instanceId)."
            await listInstances(provider: provider, apiKey: key)
        } catch {
            self.error = "Terminate failed: \(error.localizedDescription)"
        }
    }

    /// Auto-register MicroCode's managed PUBLIC key on the provider account so
    /// the SSH connect just works — true zero-setup (no copy/paste). Best
    /// effort: if it fails the user can still paste the key manually.
    @discardableResult
    func uploadKey(provider: Provider, apiKey: String, publicKey: String) async -> Bool {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let pub = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !pub.isEmpty else { return false }
        switch provider {
        case .vast:
            guard let url = URL(string: "https://console.vast.ai/api/v0/ssh/") else { return false }
            var r = URLRequest(url: url)
            r.httpMethod = "POST"; r.timeoutInterval = 15
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            r.httpBody = try? JSONSerialization.data(withJSONObject: ["ssh_key": pub])
            if let (data, resp) = try? await URLSession.shared.data(for: r) {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: data, encoding: .utf8) ?? ""
                let ok = (200...299).contains(code) || body.lowercased().contains("already")
                CrashReporter.shared.breadcrumb("Vast.uploadKey HTTP \(code) ok=\(ok)")
                return ok
            }
            return false
        case .runpod:
            guard let url = URL(string: "https://api.runpod.io/graphql") else { return false }
            var r = URLRequest(url: url)
            r.httpMethod = "POST"; r.timeoutInterval = 15
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let esc = pub.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
                         .replacingOccurrences(of: "\n", with: "\\n")
            let q = "{\"query\":\"mutation{updateUserSettings(input:{pubKey:\\\"\(esc)\\\"}){id}}\"}"
            r.httpBody = q.data(using: .utf8)
            if let (data, resp) = try? await URLSession.shared.data(for: r) {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: data, encoding: .utf8) ?? ""
                let ok = (200...299).contains(code) && !body.contains("\"errors\"")
                CrashReporter.shared.breadcrumb("RunPod.uploadKey HTTP \(code) ok=\(ok)")
                return ok
            }
            return false
        case .lambda:
            guard let url = URL(string: "https://cloud.lambdalabs.com/api/v1/ssh-keys") else { return false }
            var r = URLRequest(url: url)
            r.httpMethod = "POST"; r.timeoutInterval = 15
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            r.httpBody = try? JSONSerialization.data(withJSONObject: [
                "name": "microcode-\(Host.current().localizedName ?? "mac")",
                "public_key": pub
            ])
            if let (_, resp) = try? await URLSession.shared.data(for: r) {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                return (200...299).contains(code) || code == 400 // 400 if key already exists
            }
            return false
        }
    }

    // MARK: - RunPod (GraphQL)

    private func runpodGraphQL(key: String, body: String) async throws {
        guard let url = URL(string: "https://api.runpod.io/graphql") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = body.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let code = (resp as? HTTPURLResponse)?.statusCode, !(200...299).contains(code) {
            throw NSError(domain: "RunPod", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errors = json["errors"] as? [[String: Any]],
           let firstMsg = errors.first?["message"] as? String {
            throw NSError(domain: "RunPod", code: 400, userInfo: [NSLocalizedDescriptionKey: firstMsg])
        }
    }

    private func fetchRunPod(_ key: String) async throws -> [Instance] {
        guard let url = URL(string: "https://api.runpod.io/graphql") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let query = """
        {"query":"query{myself{pods{id name desiredStatus costPerHr machine{gpuDisplayName} runtime{ports{ip isIpPublic privatePort publicPort type}}}}}"}
        """
        req.httpBody = query.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let code = (resp as? HTTPURLResponse)?.statusCode, !(200...299).contains(code) {
            throw NSError(domain: "RunPod", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code) — check the API key."])
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = json["data"] as? [String: Any],
              let me = d["myself"] as? [String: Any],
              let pods = me["pods"] as? [[String: Any]] else {
            throw NSError(domain: "RunPod", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unexpected API response."])
        }
        return pods.map { pod in
            let id = pod["id"] as? String ?? UUID().uuidString
            let name = pod["name"] as? String ?? "pod"
            let status = (pod["desiredStatus"] as? String ?? "UNKNOWN").uppercased()
            let gpu = (pod["machine"] as? [String: Any])?["gpuDisplayName"] as? String ?? "GPU"
            let cost = pod["costPerHr"] as? Double
            let ports = (pod["runtime"] as? [String: Any])?["ports"] as? [[String: Any]] ?? []
            let ssh = ports.first(where: {
                ($0["privatePort"] as? Int) == 22 &&
                (($0["isIpPublic"] as? Bool) == true) &&
                (($0["type"] as? String)?.lowercased() == "tcp")
            })
            let host = ssh?["ip"] as? String ?? ""
            let port = ssh?["publicPort"] as? Int ?? 22
            let costTag = cost.map { String(format: " · $%.2f/hr", $0) } ?? ""
            return Instance(id: id,
                            label: "\(gpu) · \(name) · \(status)\(costTag)",
                            sshHost: host, sshPort: port, user: "root",
                            running: status == "RUNNING" && !host.isEmpty,
                            statusText: status,
                            costPerHourUSD: cost)
        }
    }

    // MARK: - Vast.ai (REST)

    private func vastStateChange(key: String, instanceId: String, method: String, body: [String: Any]?) async throws {
        guard let url = URL(string: "https://console.vast.ai/api/v0/instances/\(instanceId)/") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        let (_, resp) = try await URLSession.shared.data(for: req)
        if let code = (resp as? HTTPURLResponse)?.statusCode, !(200...299).contains(code) {
            throw NSError(domain: "Vast", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
        }
    }

    private func fetchVast(_ key: String) async throws -> [Instance] {
        guard let url = URL(string: "https://console.vast.ai/api/v0/instances/?owner=me") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let code = (resp as? HTTPURLResponse)?.statusCode, !(200...299).contains(code) {
            throw NSError(domain: "Vast", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code) — check the API key."])
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["instances"] as? [[String: Any]] else {
            throw NSError(domain: "Vast", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unexpected API response."])
        }
        return arr.map { inst in
            let id = String(describing: inst["id"] ?? UUID().uuidString)
            let gpu = inst["gpu_name"] as? String ?? "GPU"
            let status = (inst["actual_status"] as? String ?? inst["cur_state"] as? String ?? "unknown").lowercased()
            let dph = inst["dph_total"] as? Double
            let host = (inst["ssh_host"] as? String) ?? (inst["public_ipaddr"] as? String) ?? ""
            let port = (inst["ssh_port"] as? Int) ?? Int(String(describing: inst["ssh_port"] ?? "")) ?? 22
            let costTag = dph.map { String(format: " · $%.2f/hr", $0) } ?? ""
            return Instance(id: id,
                            label: "\(gpu) · #\(id) · \(status.uppercased())\(costTag)",
                            sshHost: host, sshPort: port, user: "root",
                            running: status == "running" && !host.isEmpty,
                            statusText: status.uppercased(),
                            costPerHourUSD: dph)
        }
    }

    // MARK: - Lambda Cloud (REST)

    private func fetchLambda(_ key: String) async throws -> [Instance] {
        guard let url = URL(string: "https://cloud.lambdalabs.com/api/v1/instances") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let code = (resp as? HTTPURLResponse)?.statusCode, !(200...299).contains(code) {
            throw NSError(domain: "Lambda", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code) — check the API key."])
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            throw NSError(domain: "Lambda", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unexpected API response."])
        }
        return arr.map { inst in
            let id = inst["id"] as? String ?? UUID().uuidString
            let name = inst["name"] as? String ?? String(id.prefix(8))
            let status = (inst["status"] as? String ?? "unknown").uppercased()
            let ip = inst["ip"] as? String ?? ""
            let typeObj = inst["instance_type"] as? [String: Any]
            let gpuDesc = typeObj?["description"] as? String ?? (typeObj?["name"] as? String ?? "Lambda GPU")
            let centsPerHr = typeObj?["price_cents_per_hour"] as? Int
            let cost = centsPerHr.map { Double($0) / 100.0 }
            let costTag = cost.map { String(format: " · $%.2f/hr", $0) } ?? ""
            return Instance(id: id,
                            label: "\(gpuDesc) · \(name) · \(status)\(costTag)",
                            sshHost: ip, sshPort: 22, user: "ubuntu",
                            running: status == "ACTIVE" && !ip.isEmpty,
                            statusText: status,
                            costPerHourUSD: cost)
        }
    }

    private func lambdaTerminate(key: String, instanceId: String) async throws {
        guard let url = URL(string: "https://cloud.lambdalabs.com/api/v1/instance-operations/terminate") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["instance_ids": [instanceId]])
        let (_, resp) = try await URLSession.shared.data(for: req)
        if let code = (resp as? HTTPURLResponse)?.statusCode, !(200...299).contains(code) {
            throw NSError(domain: "Lambda", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
        }
    }
}
