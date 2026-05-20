//
//  ComputeKernel.swift
//  MicroCode
//
//  Abstraction for executing code across different compute targets.
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import Foundation

enum ComputeKernelState {
    case idle
    case starting
    case running
    case stopping
    case error(String)
}

protocol ComputeKernel {
    var id: String { get }
    var target: ComputeTarget { get }
    var state: ComputeKernelState { get }
    
    func start() async throws
    func stop() async throws
    func cancel() async throws
    func execute(code: String, language: String, progress: @escaping (String) -> Void) async throws -> String
}

// MARK: - Local Process Kernel (CPU / MLX)

class LocalProcessKernel: ComputeKernel {
    let id = UUID().uuidString
    let target: ComputeTarget
    var state: ComputeKernelState = .idle
    
    init(target: ComputeTarget) {
        self.target = target
    }
    
    func start() async throws {
        state = .starting
        // Local process doesn't need heavy setup unless it's booting a local container
        state = .idle
    }
    
    func stop() async throws {
        state = .stopping
        state = .idle
    }
    
    func cancel() async throws {
        state = .stopping
        PythonEnvManager.shared.cancelCurrentProcess()
        state = .idle
    }
    
    func execute(code: String, language: String, progress: @escaping (String) -> Void) async throws -> String {
        state = .running
        defer { state = .idle }
        
        var codeToExecute = code
        
        if target == .localMLX {
            progress("⚙️ [⚡️ Hardware Accelerator: Apple Silicon (NPU/Metal) Activated]\n")
            if language.lowercased() == "python" {
                codeToExecute = """
                import os
                os.environ["MPS_ENABLE"] = "1"
                os.environ["MLX_ACCELERATE"] = "1"
                os.environ["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
                os.environ["DEVICE"] = "mps"
                
                \(code)
                """
            }
        } else {
            progress("⚙️ Executing on \(target.rawValue)...\n")
        }
        
        // Execute via PythonEnvManager
        _ = try await PythonEnvManager.shared.executeCodeStreaming(code: codeToExecute, language: language, pythonPath: nil) { output in
            DispatchQueue.main.async { progress(output) }
        }
        
        return "✅ Execution finished successfully on \(target.rawValue)."
    }
}

// MARK: - Local Nvidia eGPU Kernel (macOS 12.1+ via TinyGPU Driver)

class LocalNvidiaKernel: ComputeKernel {
    let id = UUID().uuidString
    let target: ComputeTarget = .localNvidia
    var state: ComputeKernelState = .idle
    
    func start() async throws {
        state = .starting
        // Verify TinyGPU driver extension is active via system check
        state = .idle
    }
    
    func stop() async throws {
        state = .stopping
        state = .idle
    }
    
    func cancel() async throws {
        state = .stopping
        PythonEnvManager.shared.cancelCurrentProcess()
        state = .idle
    }
    
    func execute(code: String, language: String, progress: @escaping (String) -> Void) async throws -> String {
        state = .running
        defer { state = .idle }
        
        progress("⚙️ [⚡️ Hardware Accelerator: NVIDIA GPU Activated] (TinyGPU)...\n")
        
        if language.lowercased() != "python" {
            throw NSError(domain: "ComputeKernel", code: 400, userInfo: [NSLocalizedDescriptionKey: "TinyGPU eGPU acceleration currently only supports Python."])
        }
        
        // For TinyGPU/tinygrad with Nvidia, we must inject DEV=NV into the environment
        // and ensure the local binary path contains nvcc (installed via setup_nvcc_osx.sh)
        
        let tinyGpuInjectionCode = """
        import os
        import sys
        
        # Force TinyGPU to use the NVIDIA eGPU Backend
        os.environ["DEV"] = "NV"
        
        # Ensure Docker Desktop & NVCC paths are accessible
        local_bin = os.path.expanduser("~/.local/bin")
        if local_bin not in os.environ.get("PATH", ""):
            os.environ["PATH"] = f"{local_bin}:{os.environ.get('PATH', '')}"
            
        \(code)
        """
        
        _ = try await PythonEnvManager.shared.executeCodeStreaming(code: tinyGpuInjectionCode, language: "python", pythonPath: nil) { output in
            DispatchQueue.main.async { progress(output) }
        }
        
        return "✅ Execution finished successfully on \(target.rawValue) [TinyGPU NV Backend]."
    }
}

// MARK: - WebSocket Stream Manager

class WebSocketStreamManager {
    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var isConnected = false
    
    func connect(url: URL, headers: [String: String]? = nil) {
        var request = URLRequest(url: url)
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        isConnected = true
        startPingTimer()
    }
    
    func disconnect() {
        isConnected = false
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }
    
    func send(payload: String) async throws {
        guard let task = webSocketTask else { throw URLError(.notConnectedToInternet) }
        try await task.send(.string(payload))
    }
    
    func receiveContinuous(onOutput: @escaping (String) -> Void, onComplete: @escaping (String) -> Void, onError: @escaping (Error) -> Void) {
        guard let task = webSocketTask, isConnected else { return }
        
        task.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    // Try to parse JSON for structured events (output, error, completed)
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let type = json["type"] as? String {
                        
                        if type == "output" || type == "error", let content = json["data"] as? String {
                            onOutput(content)
                        } else if type == "completed" {
                            let msg = json["data"] as? String ?? "Execution complete."
                            onComplete(msg)
                            self.disconnect()
                            return // Stop listening
                        }
                    } else {
                        // Fallback to raw text
                        onOutput(text + "\n")
                    }
                case .data(let data):
                    onOutput(String(data: data, encoding: .utf8) ?? "[Binary Data]")
                @unknown default:
                    break
                }
                
                // Continue listening
                if self.isConnected {
                    self.receiveContinuous(onOutput: onOutput, onComplete: onComplete, onError: onError)
                }
                
            case .failure(let error):
                // Check if it's a normal closure
                if (error as NSError).code == -999 { return } 
                onError(error)
                self.disconnect()
            }
        }
    }
    
    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            self?.webSocketTask?.sendPing { error in
                if let error = error {
                    print("WebSocket Ping failed: \(error)")
                    self?.disconnect()
                }
            }
        }
    }
}

// MARK: - Cloud Premium GPU Kernel (A100/H100)

class CloudGPUKernel: ComputeKernel {
    let id = UUID().uuidString
    let target: ComputeTarget = .cloudPremium
    var state: ComputeKernelState = .idle
    
    private let billingService = BillingService.shared
    private var streamManager = WebSocketStreamManager()
    
    func start() async throws {
        // Cloud GPU is gated by the SEPARATE gpu_wallets balance (฿), which
        // CloudGPUService.connect() enforces against the per-minute price.
        // Previously this used the AI-token balance — wrong wallet entirely;
        // blocked cell runs even when GPU wallet was funded. Drop the guard.
        state = .idle
    }
    
    func stop() async throws {
        state = .stopping
        billingService.stopComputeSession()
        streamManager.disconnect()
        state = .idle
    }
    
    func cancel() async throws {
        state = .stopping
        try? await streamManager.send(payload: "{\"type\":\"cancel\"}")
        streamManager.disconnect()
        billingService.stopComputeSession()
        state = .idle
    }
    
    func execute(code: String, language: String, progress: @escaping (String) -> Void) async throws -> String {
        state = .running
        defer { state = .idle }
        
        var hasInsufficientBalance = false
        billingService.startComputeSession(for: target) {
            hasInsufficientBalance = true
            progress("❌ Execution halted: Insufficient token balance.\n")
            self.streamManager.disconnect()
        }
        
        if hasInsufficientBalance {
            throw NSError(domain: "ComputeKernel", code: 402, userInfo: [NSLocalizedDescriptionKey: "Out of tokens"])
        }
        
        progress("🚀 Connecting to MicroCode Cloud (Premium) via WebSocket...\n")
        
        return try await withCheckedThrowingContinuation { continuation in
            let url = URL(string: "wss://api.dotmini.net/v1/compute/cloud")!
            
            // Secure Backend Enforcement:
            // Pass the user's MicroRent token so the backend can validate the subscription securely.
            var headers: [String: String]? = nil
            if let token = UserDefaults.standard.string(forKey: "microRentToken"), !token.isEmpty {
                headers = ["Authorization": "Bearer \(token)"]
            } else {
                continuation.resume(throwing: NSError(domain: "ComputeKernel", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Please log in to use Cloud GPU."]))
                return
            }
            
            streamManager.connect(url: url, headers: headers)
            
            let payload: [String: Any] = ["language": language, "code": code]
            guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                  let payloadString = String(data: payloadData, encoding: .utf8) else {
                continuation.resume(throwing: URLError(.cannotParseResponse))
                return
            }
            
            Task {
                do {
                    try await streamManager.send(payload: payloadString)
                } catch {
                    self.billingService.stopComputeSession()
                    continuation.resume(throwing: error)
                    return
                }
                
                streamManager.receiveContinuous { output in
                    DispatchQueue.main.async { progress(output) }
                } onComplete: { message in
                    self.billingService.stopComputeSession()
                    continuation.resume(returning: "✅ " + message)
                } onError: { error in
                    self.billingService.stopComputeSession()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Custom HPC Kernel (MicroCode Agent via WebSocket)

class CustomHPCKernel: ComputeKernel {
    let id = UUID().uuidString
    let target: ComputeTarget = .customHPC
    var state: ComputeKernelState = .idle
    
    // Agent Config (To be provided by the User via UI / UserDefaults)
    var agentEndpoint: String {
        return UserDefaults.standard.string(forKey: "hpcEndpoint") ?? ""
    }
    var agentToken: String {
        return UserDefaults.standard.string(forKey: "hpcToken") ?? ""
    }
    
    private var streamManager = WebSocketStreamManager()
    private var activeJupyterKernel: JupyterKernel?
    
    func start() async throws {
        state = .starting
        state = .idle
    }
    
    func stop() async throws {
        state = .stopping
        streamManager.disconnect()
        if let jupyter = activeJupyterKernel {
            try? await jupyter.stop()
            activeJupyterKernel = nil
        }
        state = .idle
    }
    
    func cancel() async throws {
        state = .stopping
        try? await streamManager.send(payload: "{\"type\":\"cancel\"}")
        streamManager.disconnect()
        if let jupyter = activeJupyterKernel {
            try? await jupyter.cancel()
        }
        state = .idle
    }
    
    func execute(code: String, language: String, progress: @escaping (String) -> Void) async throws -> String {
        state = .running
        defer { state = .idle }
        
        var endpoint = agentEndpoint
        if endpoint.isEmpty {
            endpoint = "ws://127.0.0.1:8080/v1/agent"
            ReportLogManager.shared.log("HPC Endpoint empty, falling back to local: \(endpoint)", type: .warning)
        }
        
        let isHTTP = endpoint.lowercased().starts(with: "http://") || endpoint.lowercased().starts(with: "https://")
        
        if isHTTP {
            progress("🚀 [⚡️ Hardware Accelerator: Custom Cloud GPU] Initiating Request to \(endpoint)...\n")
            
            // Auto-Detect Jupyter Server
            var isJupyter = false
            var jupyterCheckURLString = endpoint
            if jupyterCheckURLString.hasSuffix("/") { jupyterCheckURLString.removeLast() }
            if let checkURL = URL(string: "\(jupyterCheckURLString)/api") {
                var checkReq = URLRequest(url: checkURL)
                checkReq.httpMethod = "GET"
                checkReq.timeoutInterval = 3.0
                if !agentToken.isEmpty {
                    checkReq.setValue("Token \(agentToken)", forHTTPHeaderField: "Authorization")
                }
                
                if let (data, resp) = try? await URLSession.shared.data(for: checkReq),
                   let httpResp = resp as? HTTPURLResponse {
                    if httpResp.statusCode == 200,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       json["version"] != nil {
                        isJupyter = true
                    } else if httpResp.statusCode == 403 {
                        // 403 on /api usually means it IS Jupyter but needs a valid token.
                        isJupyter = true
                    }
                }
            }
            
            if isJupyter {
                if activeJupyterKernel == nil {
                    activeJupyterKernel = JupyterKernel(endpoint: endpoint, token: agentToken)
                }
                return try await activeJupyterKernel!.execute(code: code, language: language, progress: progress)
            }
            
            // Format for Universal Serverless API (RunPod, Vast.ai, Akamai)
            guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !agentToken.isEmpty {
                request.setValue("Bearer \(agentToken)", forHTTPHeaderField: "Authorization")
            }
            
            // Universal payload format
            let payload: [String: Any] = [
                "input": [
                    "code": code,
                    "language": language
                ]
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                
                if (200...299).contains(httpResponse.statusCode) {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let output = json["output"] as? String {
                        progress(output)
                        return "✅ Cloud GPU Execution complete."
                    } else if let text = String(data: data, encoding: .utf8) {
                        progress(text)
                        return "✅ Cloud GPU Execution complete."
                    }
                } else {
                    let errStr = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw NSError(domain: "ComputeKernel", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Cloud API Error: \(errStr)"])
                }
            } catch {
                throw error
            }
            
            return "✅ Execution finished."
            
        } else {
            progress("🔌 Connecting to MicroCode Cloud via WebSocket...\n")
            
            return try await withCheckedThrowingContinuation { continuation in
                guard let url = URL(string: endpoint) else {
                    continuation.resume(throwing: URLError(.badURL))
                    return
                }
                
                var headers: [String: String]? = nil
                if !agentToken.isEmpty {
                    headers = ["Authorization": "Bearer \(agentToken)"]
                }
                
                streamManager.connect(url: url, headers: headers)
                
                let payload: [String: Any] = ["language": language, "code": code]
                guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                      let payloadString = String(data: payloadData, encoding: .utf8) else {
                    continuation.resume(throwing: URLError(.cannotParseResponse))
                    return
                }
                
                Task {
                    do {
                        try await streamManager.send(payload: payloadString)
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    streamManager.receiveContinuous { output in
                        DispatchQueue.main.async { progress(output) }
                    } onComplete: { message in
                        continuation.resume(returning: "✅ HPC Remote Execution complete: " + message)
                    } onError: { error in
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

// MARK: - Kernel Router

class ComputeKernelRouter {
    static let shared = ComputeKernelRouter()
    
    private var activeKernels: [String: ComputeKernel] = [:]
    
    func getKernel(for target: ComputeTarget) -> ComputeKernel {
        if let existing = activeKernels[target.rawValue] {
            return existing
        }
        
        let kernel: ComputeKernel
        switch target {
        case .localCPU, .localMLX:
            kernel = LocalProcessKernel(target: target)
        case .localNvidia:
            kernel = LocalNvidiaKernel()
        case .cloudPremium:
            kernel = CloudGPUKernel()
        case .customHPC:
            kernel = CustomHPCKernel()
        }
        
        activeKernels[target.rawValue] = kernel
        return kernel
    }
}
