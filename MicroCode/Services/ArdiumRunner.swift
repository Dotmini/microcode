import Foundation

/// Engine to execute Ardium code using the native 'arc' CLI.
class ArdiumRunner {
    
    enum RunnerError: Error {
        case arcNotFound
        case executionFailed(String)
        case fileWriteFailed
    }
    
    /// Checks if the Ardium Compiler (arc) is installed.
    static var isArcInstalled: Bool {
        return FileManager.default.fileExists(atPath: "/usr/local/bin/arc")
    }
    
    /// Executes the provided Ardium code and streams the output.
    /// - Parameter code: The source code string to execute.
    /// - Returns: An AsyncStream yielding lines of output (stdout/stderr).
    func run(code: String) -> AsyncStream<String> {
        return AsyncStream { continuation in
            let task = Task {
                // 1. Validate Environment
                guard Self.isArcInstalled else {
                    continuation.yield("❌ Error: 'arc' compiler not found at /usr/local/bin/arc")
                    continuation.yield("Please install Ardium Toolchain.")
                    continuation.finish()
                    return
                }
                
                // 2. Prepare Temporary File
                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent("StartUp.ar")
                
                do {
                    try code.write(to: fileURL, atomically: true, encoding: .utf8)
                } catch {
                    continuation.yield("❌ Error: Failed to write output file: \(error.localizedDescription)")
                    continuation.finish()
                    return
                }
                
                // 3. Configure Process
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/local/bin/arc")
                process.arguments = ["run", fileURL.path]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                // 4. Stream Output
                let fileHandle = pipe.fileHandleForReading
                
                process.terminationHandler = { _ in
                    // Ensure we catch any remaining data after termination
                    // (Handled by the async bytes iterator usually, but good for cleanup)
                }
                
                do {
                    try process.run()
                    
                    // Iterate over lines asynchronously
                    for try await line in fileHandle.bytes.lines {
                        continuation.yield(line)
                    }
                    
                    process.waitUntilExit()
                    
                    if process.terminationStatus != 0 {
                        continuation.yield("\n[Process exited with code \(process.terminationStatus)]")
                    } else {
                        continuation.yield("\n✅ Execution Finished.")
                    }
                    
                    continuation.finish()
                    
                } catch {
                    continuation.yield("❌ Error: Failed to launch 'arc': \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }
}
