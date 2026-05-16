//
//  JupyterKernel.swift
//  MicroCode
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

        // (Re)connect when first used OR when the tunnel dropped the socket
        // (RunPod/Vast Cloudflare tunnels recycle connections). This makes
        // subsequent cells "just work" instead of erroring out.
        if !isKernelStarted || !client.isLive {
            if isKernelStarted && !client.isLive {
                progress("🔄 Remote tunnel dropped — reconnecting…\n")
            } else {
                progress("🚀 Connecting to remote Jupyter kernel (\(kernelName))…\n")
            }
            do {
                let kernelID = try await client.startKernel(name: kernelName)
                try client.connectWebSocket(kernelID: kernelID)
                try await client.waitUntilReady()   // don't lose the first cell
                isKernelStarted = true
                progress("✅ Connected — kernel [\(kernelID)] ready\n")
            } catch {
                isKernelStarted = false
                throw NSError(domain: "JupyterKernel", code: 500, userInfo: [NSLocalizedDescriptionKey: "Could not connect to the remote Jupyter server.\n\(error.localizedDescription)\n\nCheck: (1) the tunnel/URL is the Jupyter base URL, (2) the token is correct, (3) the '\(kernelName)' kernel is installed on the instance."])
            }
        }

        // Safety watchdog: a silently-dead tunnel must not hang the cell
        // forever. 45 min is generous enough for long training jobs while
        // still guaranteeing the UI is never stuck.
        return try await withCheckedThrowingContinuation { continuation in
            let settled = NSLock()
            var done = false
            func finish(_ block: () -> Void) {
                settled.lock(); defer { settled.unlock() }
                guard !done else { return }
                done = true
                block()
            }

            let watchdog = Task {
                try? await Task.sleep(nanoseconds: 45 * 60 * 1_000_000_000)
                finish { continuation.resume(throwing: NSError(domain: "JupyterKernel", code: 408, userInfo: [NSLocalizedDescriptionKey: "Remote execution timed out (no response for 45 min). The tunnel/instance may be down."])) }
            }

            Task {
                do {
                    try await client.executeCode(code: code, onOutput: { output in
                        DispatchQueue.main.async { progress(output) }
                    }, onComplete: { _ in
                        watchdog.cancel()
                        finish { continuation.resume(returning: "✅ Jupyter Execution complete.") }
                    }, onError: { error in
                        watchdog.cancel()
                        finish { continuation.resume(throwing: error) }
                    })
                } catch {
                    watchdog.cancel()
                    finish { continuation.resume(throwing: error) }
                }
            }
        }
    }
}
