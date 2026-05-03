//
//  LocalLLMService.swift
//  CodeTunner
//
//  Auto-detect and connect to Local LLM servers
//  Supports: LM Studio, Ollama, text-generation-webui, LocalAI
//
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import Foundation
import Combine

// MARK: - Local LLM Server Type

enum LocalLLMServerType: String, CaseIterable, Identifiable {
    case lmStudio = "LM Studio"
    case ollama = "Ollama"
    case textGenWebUI = "Text Gen WebUI"
    case localAI = "LocalAI"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var defaultPort: Int {
        switch self {
        case .lmStudio: return 1234
        case .ollama: return 11434
        case .textGenWebUI: return 5000
        case .localAI: return 8080
        case .custom: return 8080
        }
    }
    
    var defaultHost: String { "127.0.0.1" }
    
    var apiPath: String {
        switch self {
        case .lmStudio: return "/v1"
        case .ollama: return "/v1"  // Ollama supports OpenAI-compatible endpoint
        case .textGenWebUI: return "/v1"
        case .localAI: return "/v1"
        case .custom: return "/v1"
        }
    }
    
    var modelsPath: String {
        switch self {
        case .ollama: return "/api/tags"  // Ollama's native endpoint
        default: return "/v1/models"
        }
    }
    
    var icon: String {
        switch self {
        case .lmStudio: return "desktopcomputer"
        case .ollama: return "terminal"
        case .textGenWebUI: return "globe"
        case .localAI: return "cpu"
        case .custom: return "link"
        }
    }
    
    var color: String {
        switch self {
        case .lmStudio: return "blue"
        case .ollama: return "green"
        case .textGenWebUI: return "orange"
        case .localAI: return "purple"
        case .custom: return "gray"
        }
    }
}

// MARK: - Detected Server

struct DetectedLLMServer: Identifiable {
    let id = UUID()
    let type: LocalLLMServerType
    let host: String
    let port: Int
    var models: [LocalLLMModel] = []
    var isOnline: Bool = false
    var latency: TimeInterval = 0
    
    var endpoint: String {
        "http://\(host):\(port)\(type.apiPath)"
    }
    
    var displayName: String {
        "\(type.rawValue) (\(host):\(port))"
    }
}

struct LocalLLMModel: Identifiable, Hashable {
    let id: String
    let name: String
    let size: String?
    let quantization: String?
    
    var displayName: String {
        if let q = quantization {
            return "\(name) [\(q)]"
        }
        return name
    }
}

// MARK: - Local LLM Service

@MainActor
class LocalLLMService: ObservableObject {
    static let shared = LocalLLMService()
    
    @Published var detectedServers: [DetectedLLMServer] = []
    @Published var isScanning = false
    @Published var selectedServerIndex: Int = 0
    @Published var selectedModelId: String = ""
    @Published var customHost: String = "127.0.0.1"
    @Published var customPort: String = "1234"
    @Published var lastScanTime: Date?
    
    var activeServer: DetectedLLMServer? {
        guard !detectedServers.isEmpty, selectedServerIndex < detectedServers.count else { return nil }
        return detectedServers[selectedServerIndex]
    }
    
    var activeEndpoint: String {
        activeServer?.endpoint ?? "http://127.0.0.1:1234/v1"
    }
    
    var activeModel: String {
        if !selectedModelId.isEmpty { return selectedModelId }
        return activeServer?.models.first?.id ?? "local-model"
    }
    
    var availableModels: [LocalLLMModel] {
        activeServer?.models ?? []
    }
    
    // MARK: - Scan for Local Servers
    
    func scanForServers() async {
        isScanning = true
        detectedServers.removeAll()
        
        // Scan all known server types
        for serverType in LocalLLMServerType.allCases where serverType != .custom {
            let host = serverType.defaultHost
            let port = serverType.defaultPort
            
            if let server = await probeServer(type: serverType, host: host, port: port) {
                detectedServers.append(server)
            }
        }
        
        // Also try custom if configured
        if let port = Int(customPort), port > 0 {
            let customServer = await probeServer(
                type: .custom,
                host: customHost,
                port: port
            )
            if let server = customServer {
                detectedServers.append(server)
            }
        }
        
        // Auto-select first online server
        if let firstOnline = detectedServers.firstIndex(where: { $0.isOnline }) {
            selectedServerIndex = firstOnline
            if let firstModel = detectedServers[firstOnline].models.first {
                selectedModelId = firstModel.id
            }
        }
        
        lastScanTime = Date()
        isScanning = false
        
        print("🔍 Local LLM scan complete: \(detectedServers.filter { $0.isOnline }.count) server(s) found")
    }
    
    // MARK: - Probe Single Server
    
    private func probeServer(type: LocalLLMServerType, host: String, port: Int) async -> DetectedLLMServer? {
        let startTime = Date()
        var server = DetectedLLMServer(type: type, host: host, port: port)
        
        // Try to reach the models endpoint
        let modelsURL: URL
        if type == .ollama {
            // Ollama has its own models endpoint
            guard let url = URL(string: "http://\(host):\(port)\(type.modelsPath)") else { return nil }
            modelsURL = url
        } else {
            guard let url = URL(string: "http://\(host):\(port)/v1/models") else { return nil }
            modelsURL = url
        }
        
        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = 3 // Quick timeout for local scan
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            
            server.isOnline = true
            server.latency = Date().timeIntervalSince(startTime)
            
            // Parse models
            if type == .ollama {
                server.models = parseOllamaModels(data)
            } else {
                server.models = parseOpenAIModels(data)
            }
            
            // If no models from endpoint, try v1/models for Ollama too
            if server.models.isEmpty && type == .ollama {
                if let openaiURL = URL(string: "http://\(host):\(port)/v1/models") {
                    var req2 = URLRequest(url: openaiURL)
                    req2.timeoutInterval = 3
                    if let (data2, _) = try? await URLSession.shared.data(for: req2) {
                        server.models = parseOpenAIModels(data2)
                    }
                }
            }
            
            return server
            
        } catch {
            // Server not reachable
            return nil
        }
    }
    
    // MARK: - Parse Models
    
    private func parseOpenAIModels(_ data: Data) -> [LocalLLMModel] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsArray = json["data"] as? [[String: Any]] else { return [] }
        
        return modelsArray.compactMap { modelDict -> LocalLLMModel? in
            guard let id = modelDict["id"] as? String else { return nil }
            
            // Extract name and quantization from model ID
            let name = id.components(separatedBy: "/").last ?? id
            let quantization = extractQuantization(from: name)
            let size = extractSize(from: name)
            
            return LocalLLMModel(id: id, name: name, size: size, quantization: quantization)
        }
    }
    
    private func parseOllamaModels(_ data: Data) -> [LocalLLMModel] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsArray = json["models"] as? [[String: Any]] else { return [] }
        
        return modelsArray.compactMap { modelDict -> LocalLLMModel? in
            guard let name = modelDict["name"] as? String else { return nil }
            
            let size: String?
            if let sizeBytes = modelDict["size"] as? Int64 {
                size = formatBytes(sizeBytes)
            } else {
                size = extractSize(from: name)
            }
            
            let quantization = extractQuantization(from: name)
            
            return LocalLLMModel(id: name, name: name, size: size, quantization: quantization)
        }
    }
    
    // MARK: - Helpers
    
    private func extractQuantization(from name: String) -> String? {
        let patterns = ["Q2_K", "Q3_K", "Q4_K_M", "Q4_K_S", "Q4_0", "Q4_1",
                       "Q5_K_M", "Q5_K_S", "Q5_0", "Q5_1",
                       "Q6_K", "Q8_0", "F16", "F32",
                       "IQ2_M", "IQ3_M", "IQ4_NL"]
        
        let upper = name.uppercased()
        return patterns.first { upper.contains($0) }
    }
    
    private func extractSize(from name: String) -> String? {
        // Match patterns like "7b", "13b", "70b", "8x7b"
        let pattern = "\\d+x?\\d*[bB]"
        if let range = name.range(of: pattern, options: .regularExpression) {
            return String(name[range]).uppercased()
        }
        return nil
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }
    
    // MARK: - Quick Check (for UI status indicators)
    
    func quickCheck() async -> Bool {
        guard let server = activeServer else { return false }
        
        guard let url = URL(string: "http://\(server.host):\(server.port)/v1/models") else { return false }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
