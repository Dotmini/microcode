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
    
    var defaultPorts: [Int] {
        switch self {
        case .lmStudio: return [1234, 8080, 1235]
        case .ollama: return [11434, 11435]
        case .textGenWebUI: return [5000, 5001, 7860]
        case .localAI: return [8080, 8081]
        case .custom: return [8080]
        }
    }
    
    var defaultPort: Int { defaultPorts.first ?? 8080 }
    var defaultHost: String { "127.0.0.1" }
    var apiPath: String { "/v1" }
    
    var modelsPath: String {
        switch self {
        case .ollama: return "/api/tags"
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
    
    var endpoint: String { "http://\(host):\(port)\(type.apiPath)" }
    var displayName: String { "\(type.rawValue) (\(host):\(port))" }
}

struct LocalLLMModel: Identifiable, Hashable {
    let id: String
    let name: String
    let size: String?
    let quantization: String?
    var parameterSize: String?
    var family: String?
    var isDownloading: Bool = false
    var downloadProgress: Double = 0
    
    var displayName: String {
        if let q = quantization { return "\(name) [\(q)]" }
        return name
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: LocalLLMModel, rhs: LocalLLMModel) -> Bool { lhs.id == rhs.id }
}

// MARK: - Downloadable Model Catalog

struct DownloadableModel: Identifiable {
    let id: String
    let name: String
    let provider: String
    let description: String
    let params: String
    let sizeGB: Double
    let capabilities: [String]
    let ollamaTag: String
    
    var sizeLabel: String {
        sizeGB >= 1 ? String(format: "%.1f GB", sizeGB) : String(format: "%.0f MB", sizeGB * 1024)
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
    @Published var downloadingModels: [String: Double] = [:]
    @Published var scanLog: [String] = []
    
    nonisolated(unsafe) static var cachedEndpoint: String = "http://127.0.0.1:1234/v1"
    nonisolated(unsafe) static var cachedModel: String = "local-model"
    
    let modelCatalog: [DownloadableModel] = [
        DownloadableModel(id: "gemma3", name: "Gemma 3", provider: "Google", description: "Google's efficient open model. Great for coding and reasoning.", params: "4B", sizeGB: 3.3, capabilities: ["Code", "Reasoning"], ollamaTag: "gemma3"),
        DownloadableModel(id: "gemma3-12b", name: "Gemma 3 12B", provider: "Google", description: "Larger Gemma with stronger performance.", params: "12B", sizeGB: 8.1, capabilities: ["Code", "Reasoning", "Vision"], ollamaTag: "gemma3:12b"),
        DownloadableModel(id: "qwen3", name: "Qwen 3", provider: "Alibaba", description: "Hybrid thinking. Strong multilingual and code.", params: "8B", sizeGB: 5.2, capabilities: ["Code", "Reasoning", "Tool Use"], ollamaTag: "qwen3"),
        DownloadableModel(id: "llama3.3", name: "Llama 3.3", provider: "Meta", description: "Meta's latest. Excellent for general and code tasks.", params: "70B", sizeGB: 43.0, capabilities: ["Code", "Reasoning"], ollamaTag: "llama3.3"),
        DownloadableModel(id: "llama3.2", name: "Llama 3.2", provider: "Meta", description: "Efficient small model. Fast local inference.", params: "3B", sizeGB: 2.0, capabilities: ["Code", "Chat"], ollamaTag: "llama3.2"),
        DownloadableModel(id: "deepseek-r1", name: "DeepSeek R1", provider: "DeepSeek", description: "Reasoning-focused. Great for complex problem solving.", params: "8B", sizeGB: 5.0, capabilities: ["Reasoning", "Code"], ollamaTag: "deepseek-r1:8b"),
        DownloadableModel(id: "codellama", name: "Code Llama", provider: "Meta", description: "Specialized for code generation and debugging.", params: "7B", sizeGB: 3.8, capabilities: ["Code"], ollamaTag: "codellama"),
        DownloadableModel(id: "mistral", name: "Mistral", provider: "Mistral AI", description: "Fast, efficient model with strong reasoning.", params: "7B", sizeGB: 4.1, capabilities: ["Code", "Chat"], ollamaTag: "mistral"),
        DownloadableModel(id: "phi4", name: "Phi-4", provider: "Microsoft", description: "Compact but powerful reasoning model.", params: "14B", sizeGB: 9.1, capabilities: ["Code", "Reasoning"], ollamaTag: "phi4"),
        DownloadableModel(id: "nemotron", name: "Nemotron Mini", provider: "NVIDIA", description: "Compact model optimized for reasoning.", params: "4B", sizeGB: 2.7, capabilities: ["Reasoning", "Chat"], ollamaTag: "nemotron-mini"),
    ]
    
    var activeServer: DetectedLLMServer? {
        guard !detectedServers.isEmpty, selectedServerIndex < detectedServers.count else { return nil }
        return detectedServers[selectedServerIndex]
    }
    
    var activeEndpoint: String {
        let value = activeServer?.endpoint ?? "http://127.0.0.1:1234/v1"
        LocalLLMService.cachedEndpoint = value
        return value
    }
    
    var activeModel: String {
        let value = !selectedModelId.isEmpty ? selectedModelId : (activeServer?.models.first?.id ?? "local-model")
        LocalLLMService.cachedModel = value
        return value
    }
    
    var availableModels: [LocalLLMModel] { activeServer?.models ?? [] }
    
    // MARK: - Scan for Local Servers
    
    func scanForServers() async {
        isScanning = true
        detectedServers.removeAll()
        scanLog = ["🔍 Starting scan..."]
        
        for serverType in LocalLLMServerType.allCases where serverType != .custom {
            for port in serverType.defaultPorts {
                scanLog.append("  Probing \(serverType.rawValue) on :\(port)...")
                if let server = await probeServer(type: serverType, host: serverType.defaultHost, port: port) {
                    detectedServers.append(server)
                    scanLog.append("  ✓ Found \(serverType.rawValue) — \(server.models.count) model(s)")
                    break
                }
            }
        }
        
        if let port = Int(customPort), port > 0 {
            scanLog.append("  Probing Custom on \(customHost):\(port)...")
            if let server = await probeServer(type: .custom, host: customHost, port: port) {
                detectedServers.append(server)
                scanLog.append("  ✓ Found custom server — \(server.models.count) model(s)")
            }
        }
        
        // Try localhost aliases if nothing found
        if detectedServers.isEmpty {
            scanLog.append("  Trying localhost aliases...")
            for serverType in [LocalLLMServerType.lmStudio, .ollama] {
                for port in serverType.defaultPorts {
                    if let server = await probeServer(type: serverType, host: "localhost", port: port) {
                        detectedServers.append(server)
                        scanLog.append("  ✓ Found \(serverType.rawValue) on localhost:\(port)")
                        break
                    }
                }
            }
        }
        
        if let firstOnline = detectedServers.firstIndex(where: { $0.isOnline }) {
            selectedServerIndex = firstOnline
            if let firstModel = detectedServers[firstOnline].models.first {
                selectedModelId = firstModel.id
            }
        }
        
        lastScanTime = Date()
        isScanning = false
        let count = detectedServers.filter { $0.isOnline }.count
        scanLog.append("✅ Scan complete: \(count) server(s) found")
        print("🔍 Local LLM scan complete: \(count) server(s) found")
    }
    
    // MARK: - Probe Single Server
    
    private func probeServer(type: LocalLLMServerType, host: String, port: Int) async -> DetectedLLMServer? {
        let startTime = Date()
        var server = DetectedLLMServer(type: type, host: host, port: port)
        
        let modelsURL: URL
        if type == .ollama {
            guard let url = URL(string: "http://\(host):\(port)\(type.modelsPath)") else { return nil }
            modelsURL = url
        } else {
            guard let url = URL(string: "http://\(host):\(port)/v1/models") else { return nil }
            modelsURL = url
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        let session = URLSession(configuration: config)
        
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return nil }
            
            server.isOnline = true
            server.latency = Date().timeIntervalSince(startTime)
            
            if type == .ollama {
                server.models = parseOllamaModels(data)
            } else {
                server.models = parseOpenAIModels(data)
            }
            
            if server.models.isEmpty && type == .ollama {
                if let openaiURL = URL(string: "http://\(host):\(port)/v1/models") {
                    var req2 = URLRequest(url: openaiURL)
                    req2.timeoutInterval = 5
                    if let (data2, _) = try? await session.data(for: req2) {
                        server.models = parseOpenAIModels(data2)
                    }
                }
            }
            
            if server.models.isEmpty && type == .lmStudio {
                server.models = [LocalLLMModel(id: "lmstudio-default", name: "Default Model", size: nil, quantization: nil)]
            }
            
            return server
        } catch {
            return nil
        }
    }
    
    // MARK: - Download Model via Ollama
    
    func downloadModel(_ model: DownloadableModel) async {
        guard detectedServers.contains(where: { $0.type == .ollama && $0.isOnline }) else {
            scanLog.append("❌ Ollama not running. Start Ollama first.")
            return
        }
        
        let ollamaServer = detectedServers.first(where: { $0.type == .ollama })!
        guard let url = URL(string: "http://\(ollamaServer.host):\(ollamaServer.port)/api/pull") else { return }
        
        downloadingModels[model.id] = 0
        scanLog.append("⬇ Downloading \(model.name)...")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": model.ollamaTag])
        
        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            for try await line in bytes.lines {
                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let total = json["total"] as? Double, let completed = json["completed"] as? Double, total > 0 {
                        downloadingModels[model.id] = completed / total
                    }
                    if let status = json["status"] as? String, status == "success" {
                        downloadingModels.removeValue(forKey: model.id)
                        scanLog.append("✅ Downloaded \(model.name)")
                        await scanForServers()
                        return
                    }
                }
            }
        } catch {
            downloadingModels.removeValue(forKey: model.id)
            scanLog.append("❌ Download failed: \(error.localizedDescription)")
        }
    }
    
    func deleteModel(_ modelName: String) async {
        guard let ollamaServer = detectedServers.first(where: { $0.type == .ollama && $0.isOnline }) else { return }
        guard let url = URL(string: "http://\(ollamaServer.host):\(ollamaServer.port)/api/delete") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": modelName])
        
        _ = try? await URLSession.shared.data(for: request)
        scanLog.append("🗑 Deleted \(modelName)")
        await scanForServers()
    }
    
    // MARK: - Parse Models
    
    private func parseOpenAIModels(_ data: Data) -> [LocalLLMModel] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsArray = json["data"] as? [[String: Any]] else { return [] }
        
        return modelsArray.compactMap { modelDict -> LocalLLMModel? in
            guard let id = modelDict["id"] as? String else { return nil }
            let name = id.components(separatedBy: "/").last ?? id
            return LocalLLMModel(id: id, name: name, size: extractSize(from: name), quantization: extractQuantization(from: name))
        }
    }
    
    private func parseOllamaModels(_ data: Data) -> [LocalLLMModel] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsArray = json["models"] as? [[String: Any]] else { return [] }
        
        return modelsArray.compactMap { modelDict -> LocalLLMModel? in
            guard let name = modelDict["name"] as? String else { return nil }
            
            let size: String?
            if let sizeBytes = modelDict["size"] as? Int64 { size = formatBytes(sizeBytes) }
            else if let sizeBytes = modelDict["size"] as? Int { size = formatBytes(Int64(sizeBytes)) }
            else { size = extractSize(from: name) }
            
            var model = LocalLLMModel(id: name, name: name, size: size, quantization: extractQuantization(from: name))
            if let details = modelDict["details"] as? [String: Any] {
                model.parameterSize = details["parameter_size"] as? String
                model.family = details["family"] as? String
            }
            return model
        }
    }
    
    // MARK: - Helpers
    
    private func extractQuantization(from name: String) -> String? {
        let patterns = ["Q2_K", "Q3_K", "Q4_K_M", "Q4_K_S", "Q4_0", "Q4_1",
                       "Q5_K_M", "Q5_K_S", "Q5_0", "Q5_1",
                       "Q6_K", "Q8_0", "F16", "F32", "IQ2_M", "IQ3_M", "IQ4_NL"]
        let upper = name.uppercased()
        return patterns.first { upper.contains($0) }
    }
    
    private func extractSize(from name: String) -> String? {
        if let range = name.range(of: "\\d+x?\\d*[bB]", options: .regularExpression) {
            return String(name[range]).uppercased()
        }
        return nil
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        return gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", Double(bytes) / (1024 * 1024))
    }
    
    func quickCheck() async -> Bool {
        guard let server = activeServer,
              let url = URL(string: "http://\(server.host):\(server.port)/v1/models") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }
}
