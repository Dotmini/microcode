//
//  JupyterKernel.swift
//  CodeTunner
//
//  Wraps JupyterClient into the ComputeKernel protocol for seamless integration.
//

import Foundation

class JupyterKernel: ComputeKernel {
    let id = UUID().uuidString
    let target: ComputeTarget = .customHPC // Technically Jupyter falls under CustomHPC in UI
    var state: ComputeKernelState = .idle
    
    private let client: JupyterClient
    private var isKernelStarted = false
    
    init(endpoint: String, token: String) {
        self.client = JupyterClient(endpoint: endpoint, token: token)
    }
    
    // Map MicroCode CellLanguage to standard Jupyter kernel names
    private func getJupyterKernelName(for language: String) -> String {
        let lang = language.lowercased()
        switch lang {
        case "python": return "python3"
        case "r": return "ir"
        case "julia": return "julia-1.9" // Often ijulia is registered as julia-1.x
        case "c++": return "xeus-cling" // or xcpp
        case "rust": return "evcxr"
        case "go": return "gophernotes"
        case "java": return "ijava"
        case "c#": return "icsharp"
        default: return "python3" // Fallback to python3 if unknown
        }
    }
    
    func start() async throws {
        // We defer starting the specific kernel to the execute method since we need the language
        // Or we can just initialize connection state here
        state = .idle
    }
    
    func stop() async throws {
        state = .stopping
        await client.stopKernel()
        isKernelStarted = false
        state = .idle
    }
    
    func cancel() async throws {
        state = .stopping
        // Jupyter API allows interrupt, but for simplicity we stop it or let it run
        // Real implementation would hit /api/kernels/<id>/interrupt
        state = .idle
    }
    
    func execute(code: String, language: String, progress: @escaping (String) -> Void) async throws -> String {
        state = .running
        defer { state = .idle }
        
        let kernelName = getJupyterKernelName(for: language)
        
        if !isKernelStarted {
            progress("🚀 Connecting to Jupyter Notebook Server (Kernel: \(kernelName))...\n")
            do {
                let kernelID = try await client.startKernel(name: kernelName)
                try client.connectWebSocket(kernelID: kernelID)
                isKernelStarted = true
                progress("✅ Connected to Jupyter Kernel [\(kernelID)]\n")
            } catch {
                throw NSError(domain: "JupyterKernel", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to Jupyter Server: \(error.localizedDescription). Please verify your URL, Token, and ensure the requested kernel (\(kernelName)) is installed."])
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    try await client.executeCode(code: code, onOutput: { output in
                        DispatchQueue.main.async { progress(output) }
                    }, onComplete: { message in
                        continuation.resume(returning: "✅ Jupyter Execution complete.")
                    }, onError: { error in
                        continuation.resume(throwing: error)
                    })
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
