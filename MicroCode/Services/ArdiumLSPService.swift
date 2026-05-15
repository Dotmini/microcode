import Foundation

/// Manages the Ardium Language Server Protocol (LSP) process.
class ArdiumLSPService {
    static let shared = ArdiumLSPService()
    
    private var lspProcess: Process?
    private var isRunning = false
    
    private init() {}
    
    /// Starts the `arc lsp` process if not already running.
    func start() {
        guard !isRunning else { return }
        
        // Locate 'arc' binary
        let searchPaths = ["/usr/local/bin/arc", "/opt/homebrew/bin/arc", "/usr/bin/arc"]
        guard let arcPath = searchPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            print("❌ Ardium LSP: 'arc' binary not found.")
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arcPath)
        process.arguments = ["lsp"]
        
        // Environment setup if needed
        var env = ProcessInfo.processInfo.environment
        env["RUST_LOG"] = "info"
        process.environment = env
        
        // Pipe configuration (Standard LSP communication via Stdio)
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        
        process.terminationHandler = { [weak self] _ in
            print("⚠️ Ardium LSP Terminated.")
            self?.isRunning = false
            self?.lspProcess = nil
        }
        
        do {
            print("🚀 Starting Ardium LSP: \(arcPath) lsp")
            try process.run()
            self.lspProcess = process
            self.isRunning = true
            
            // Monitor stderr for logs
            Task.detached {
                for try await line in stderr.fileHandleForReading.bytes.lines {
                    print("[LSP Log] \(line)")
                }
            }
            
            // Note: In a full implementation, we would attach a JSON-RPC handler to stdout/stdin here.
            // For now, we just ensure the process is running as requested.
            
        } catch {
            print("❌ Failed to start Ardium LSP: \(error.localizedDescription)")
        }
    }
    
    /// Stops the LSP process.
    func stop() {
        guard isRunning else { return }
        lspProcess?.terminate()
        lspProcess = nil
        isRunning = false
    }
}
