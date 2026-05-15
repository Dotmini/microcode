//
//  HotReloadClient.swift
//  MicroCode
//
//  Complete Hot Reload Client for Xcode-like Live Preview
//  Communicates with the Rust backend hot_reload engine
//
//  SPU AI CLUB - Dotmini Software
//

import SwiftUI
import Combine

// MARK: - API Response Models

struct HotReloadVersionInfo: Codable {
    let engine: String
    let version: String
    let features: [String]
    let architecture: String
}

struct ThunkListResponse: Codable {
    let thunks: [String]
    let count: Int
}

struct StateSnapshotResponse: Codable {
    let snapshot: [String: String]
    let count: Int
}

struct PreviewStatusResponse: Codable {
    let serverRunning: Bool
    let socketPath: String
    
    enum CodingKeys: String, CodingKey {
        case serverRunning = "server_running"
        case socketPath = "socket_path"
    }
}

struct AgentStartResponse: Codable {
    let success: Bool
    let pid: Int?
    let socketPath: String?
    let message: String?
    let error: String?
    
    enum CodingKeys: String, CodingKey {
        case success, pid, message, error
        case socketPath = "socket_path"
    }
}

// MARK: - Hot Reload Client

/// Complete Hot Reload Client for IDE integration
@MainActor
class HotReloadClient: ObservableObject {
    static let shared = HotReloadClient()
    
    // MARK: - Published State
    
    @Published var isAgentRunning: Bool = false
    @Published var isReloading: Bool = false
    @Published var currentVersion: Int = 0
    @Published var lastCompileTimeMs: Int = 0
    @Published var lastRenderTimeMs: Int = 0
    @Published var lastError: String?
    @Published var registeredThunks: [String] = []
    @Published var stateSnapshot: [String: String] = [:]
    @Published var engineInfo: HotReloadVersionInfo?
    
    // MARK: - Configuration
    
    private let baseURL = "http://127.0.0.1:3000"
    private var statusCheckTimer: Timer?
    
    private init() {
        startStatusPolling()
    }
    
    deinit {
        statusCheckTimer?.invalidate()
    }
    
    // MARK: - Agent Control
    
    /// Start the preview agent process
    func startAgent() async throws {
        let url = URL(string: "\(baseURL)/api/preview/agent/start")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(AgentStartResponse.self, from: data)
        
        if response.success {
            isAgentRunning = true
            lastError = nil
        } else {
            lastError = response.error ?? "Failed to start agent"
            throw HotReloadError.agentStartFailed(lastError!)
        }
    }
    
    /// Stop the preview agent process
    func stopAgent() async throws {
        let url = URL(string: "\(baseURL)/api/preview/agent/stop")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (_, _) = try await URLSession.shared.data(for: request)
        isAgentRunning = false
    }
    
    /// Check agent status
    func checkStatus() async {
        guard let url = URL(string: "\(baseURL)/api/preview/status") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(PreviewStatusResponse.self, from: data)
            isAgentRunning = response.serverRunning
        } catch {
            isAgentRunning = false
        }
    }
    
    // MARK: - Hot Reload Operations
    
    /// Request hot reload with source code
    func reload(sourceCode: String, language: String, filePath: String? = nil) async throws -> HotReloadResult {
        isReloading = true
        defer { isReloading = false }
        
        let url = URL(string: "\(baseURL)/api/preview/reload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "source_code": sourceCode,
            "language": language
        ]
        if let path = filePath {
            body["file_path"] = path
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let result = try JSONDecoder().decode(HotReloadResult.self, from: data)
        
        lastCompileTimeMs = result.compileTimeMs
        lastRenderTimeMs = result.renderTimeMs
        
        if !result.success {
            lastError = result.error
        } else {
            lastError = nil
            currentVersion += 1
        }
        
        return result
    }
    
    /// Trigger rollback to previous version
    func rollback() async throws {
        let url = URL(string: "\(baseURL)/api/hotreload/rollback")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (_, _) = try await URLSession.shared.data(for: request)
        if currentVersion > 0 {
            currentVersion -= 1
        }
    }
    
    // MARK: - Thunk Table Operations
    
    /// List all registered thunks
    func listThunks() async throws {
        let url = URL(string: "\(baseURL)/api/hotreload/thunk/list")!
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ThunkListResponse.self, from: data)
        
        registeredThunks = response.thunks
    }
    
    /// Register a new thunk (for testing)
    func registerThunk(name: String, address: UInt64) async throws {
        let url = URL(string: "\(baseURL)/api/hotreload/thunk/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["name": name, "address": address]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, _) = try await URLSession.shared.data(for: request)
        
        // Refresh thunk list
        try await listThunks()
    }
    
    // MARK: - State Operations
    
    /// Get state snapshot
    func getStateSnapshot() async throws {
        let url = URL(string: "\(baseURL)/api/hotreload/state/snapshot")!
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(StateSnapshotResponse.self, from: data)
        
        stateSnapshot = response.snapshot
    }
    
    /// Clear all state
    func clearState() async throws {
        let url = URL(string: "\(baseURL)/api/hotreload/state/clear")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (_, _) = try await URLSession.shared.data(for: request)
        stateSnapshot = [:]
    }
    
    // MARK: - Engine Info
    
    /// Get hot reload engine version and capabilities
    func getEngineInfo() async throws {
        let url = URL(string: "\(baseURL)/api/hotreload/version")!
        
        let (data, _) = try await URLSession.shared.data(from: url)
        engineInfo = try JSONDecoder().decode(HotReloadVersionInfo.self, from: data)
    }
    
    // MARK: - Private Helpers
    
    private func startStatusPolling() {
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkStatus()
            }
        }
    }
}

// MARK: - Errors

enum HotReloadError: LocalizedError {
    case agentStartFailed(String)
    case reloadFailed(String)
    case connectionFailed
    
    var errorDescription: String? {
        switch self {
        case .agentStartFailed(let msg):
            return "Agent start failed: \(msg)"
        case .reloadFailed(let msg):
            return "Reload failed: \(msg)"
        case .connectionFailed:
            return "Connection to backend failed"
        }
    }
}

// MARK: - Hot Reload Status View

struct HotReloadStatusView: View {
    @ObservedObject var client = HotReloadClient.shared
    
    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(client.isAgentRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            Text(client.isAgentRunning ? "Live" : "Offline")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(client.isAgentRunning ? .green : .secondary)
            
            if client.isReloading {
                ProgressView()
                    .scaleEffect(0.6)
            }
            
            if client.lastCompileTimeMs > 0 {
                Text("\(client.lastCompileTimeMs)ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Text("v\(client.currentVersion)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
        .cornerRadius(4)
    }
}

// MARK: - Hot Reload Control Panel

struct HotReloadControlPanel: View {
    @ObservedObject var client = HotReloadClient.shared
    @State private var showingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.orange)
                Text("Hot Reload Engine")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { client.isAgentRunning },
                    set: { newValue in
                        Task {
                            if newValue {
                                try? await client.startAgent()
                            } else {
                                try? await client.stopAgent()
                            }
                        }
                    }
                ))
                .toggleStyle(.switch)
                .scaleEffect(0.8)
            }
            
            Divider()
            
            // Stats
            HStack(spacing: 20) {
                VStack {
                    Text("\(client.currentVersion)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Version")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\(client.lastCompileTimeMs)ms")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Compile")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\(client.registeredThunks.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Thunks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Error display
            if let error = client.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Actions
            HStack {
                Button("Rollback") {
                    Task { try? await client.rollback() }
                }
                .disabled(client.currentVersion == 0)
                
                Button("Clear State") {
                    Task { try? await client.clearState() }
                }
                
                Button("Refresh") {
                    Task {
                        try? await client.listThunks()
                        try? await client.getStateSnapshot()
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .onAppear {
            Task {
                await client.checkStatus()
                try? await client.getEngineInfo()
            }
        }
    }
}
