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
        var id: String { rawValue }
    }

    struct Instance: Identifiable, Equatable {
        let id: String
        let label: String      // shown in the picker (gpu + name + status)
        let sshHost: String
        let sshPort: Int
        let user: String
        let running: Bool
    }

    @Published var instances: [Instance] = []
    @Published var isLoading = false
    @Published var error: String = ""

    func listInstances(provider: Provider, apiKey: String) async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { error = "Enter your API key."; return }
        isLoading = true; error = ""; instances = []
        defer { isLoading = false }
        do {
            switch provider {
            case .runpod: instances = try await fetchRunPod(key)
            case .vast:   instances = try await fetchVast(key)
            }
            if instances.isEmpty { error = "No instances found for this API key." }
        } catch {
            self.error = "Failed: \(error.localizedDescription)"
        }
    }

    /// Build the SSH command RemoteGPUService expects.
    func sshCommand(for i: Instance) -> String {
        "ssh -p \(i.sshPort) \(i.user)@\(i.sshHost)"
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
            // RunPod stores SSH keys in account settings; append ours.
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
        }
    }

    // MARK: - RunPod (GraphQL)

    private func fetchRunPod(_ key: String) async throws -> [Instance] {
        guard let url = URL(string: "https://api.runpod.io/graphql") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let query = """
        {"query":"query{myself{pods{id name desiredStatus machine{gpuDisplayName} runtime{ports{ip isIpPublic privatePort publicPort type}}}}}"}
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
        return pods.compactMap { pod in
            let id = pod["id"] as? String ?? UUID().uuidString
            let name = pod["name"] as? String ?? "pod"
            let status = (pod["desiredStatus"] as? String ?? "").uppercased()
            let gpu = (pod["machine"] as? [String: Any])?["gpuDisplayName"] as? String ?? "GPU"
            // Find the public TCP mapping of SSH (privatePort 22).
            let ports = (pod["runtime"] as? [String: Any])?["ports"] as? [[String: Any]] ?? []
            guard let ssh = ports.first(where: {
                ($0["privatePort"] as? Int) == 22 &&
                (($0["isIpPublic"] as? Bool) == true) &&
                (($0["type"] as? String)?.lowercased() == "tcp")
            }), let host = ssh["ip"] as? String, let port = ssh["publicPort"] as? Int else {
                return nil // no public SSH mapping → can't connect
            }
            return Instance(id: id,
                            label: "\(gpu) · \(name) · \(status)",
                            sshHost: host, sshPort: port, user: "root",
                            running: status == "RUNNING")
        }
    }

    // MARK: - Vast.ai (REST)

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
        return arr.compactMap { inst in
            let id = String(describing: inst["id"] ?? UUID().uuidString)
            let gpu = inst["gpu_name"] as? String ?? "GPU"
            let status = (inst["actual_status"] as? String ?? inst["cur_state"] as? String ?? "").lowercased()
            // Vast exposes ssh_host/ssh_port (jump host) or direct public IP.
            let host = (inst["ssh_host"] as? String)
                ?? (inst["public_ipaddr"] as? String)
            let port = (inst["ssh_port"] as? Int)
                ?? Int(String(describing: inst["ssh_port"] ?? "")) ?? 22
            guard let h = host, !h.isEmpty else { return nil }
            return Instance(id: id,
                            label: "\(gpu) · #\(id) · \(status)",
                            sshHost: h, sshPort: port, user: "root",
                            running: status == "running")
        }
    }
}
