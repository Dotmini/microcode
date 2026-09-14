//
//  ArdiumRunner.swift
//  MicroCode
//
//  Engine to execute Ardium code using native arc / ardium CLI.
//  Copyright © 2025 Dotmini Software | Dotmini Company Limited. All rights reserved.
//

import Foundation

/// Engine to execute Ardium code using the native 'arc' / 'ardium' CLI.
class ArdiumRunner {
    
    enum RunnerError: Error {
        case arcNotFound
        case executionFailed(String)
        case fileWriteFailed
    }
    
    /// Finds the available Ardium compiler / runner binary on the system.
    static func findBinary() -> String? {
        if let envBin = ProcessInfo.processInfo.environment["ARDIUM_BIN"],
           FileManager.default.fileExists(atPath: envBin) {
            return envBin
        }
        
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidatePaths = [
            "\(home)/.cargo/bin/arc",
            "\(home)/.cargo/bin/TitanScript",
            "/opt/homebrew/bin/arc",
            "/usr/local/bin/arc",
            "/usr/local/ardium/bin/arc",
            "/usr/local/bin/ardium",
            "/usr/local/ardium/ardium",
            "/opt/homebrew/bin/ardium"
        ]
        
        for path in candidatePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Fallback: check PATH via 'which'
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["arc"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        if (try? whichProcess.run()) != nil {
            whichProcess.waitUntilExit()
            if whichProcess.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let found = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !found.isEmpty {
                    return found
                }
            }
        }
        
        return nil
    }
    
    /// Checks if the Ardium Compiler (arc / ardium) is installed.
    static var isArcInstalled: Bool {
        return findBinary() != nil
    }
    
    /// Direct async execution returning stdout, stderr, and exit code.
    static func execute(code: String, arguments: [String] = []) async -> (stdout: String, stderr: String, exitCode: Int32) {
        guard let binaryPath = findBinary() else {
            return ("", "❌ Error: Ardium compiler not found. Please install Ardium Toolchain at /usr/local/ardium.", 1)
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("ardium_\(UUID().uuidString).ar")
        
        do {
            try code.write(to: tempFile, atomically: true, encoding: .utf8)
        } catch {
            return ("", "❌ Error: Failed to write temp file: \(error.localizedDescription)", 1)
        }
        
        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }
        
        var execArgs = ["run", tempFile.path]
        execArgs.append(contentsOf: arguments)
        
        return await runProcess(executable: binaryPath, arguments: execArgs)
    }
    
    /// Compiles an Ardium source file to a standalone binary.
    static func compile(code: String, outputPath: String, flags: [String] = []) async -> (stdout: String, stderr: String, exitCode: Int32) {
        guard let binaryPath = findBinary() else {
            return ("", "❌ Error: Ardium compiler not found.", 1)
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("ardium_build_\(UUID().uuidString).ar")
        
        do {
            try code.write(to: tempFile, atomically: true, encoding: .utf8)
        } catch {
            return ("", "❌ Error: Failed to write temp file: \(error.localizedDescription)", 1)
        }
        
        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }
        
        var execArgs = ["build", tempFile.path, "-o", outputPath]
        execArgs.append(contentsOf: flags)
        
        return await runProcess(executable: binaryPath, arguments: execArgs)
    }
    
    /// Executes the provided Ardium code and streams the output line by line.
    func run(code: String) -> AsyncStream<String> {
        return AsyncStream { continuation in
            let _ = Task {
                // 1. Validate Environment
                guard let binaryPath = Self.findBinary() else {
                    continuation.yield("❌ Error: Ardium compiler not found at /usr/local/ardium/bin/arc or /usr/local/bin/ardium")
                    continuation.yield("Please install Ardium Toolchain.")
                    continuation.finish()
                    return
                }
                
                // 2. Prepare Temporary File
                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent("StartUp_\(UUID().uuidString.prefix(8)).ar")
                
                do {
                    try code.write(to: fileURL, atomically: true, encoding: .utf8)
                } catch {
                    continuation.yield("❌ Error: Failed to write output file: \(error.localizedDescription)")
                    continuation.finish()
                    return
                }
                
                defer {
                    try? FileManager.default.removeItem(at: fileURL)
                }
                
                // 3. Configure Process
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binaryPath)
                process.arguments = ["run", fileURL.path]
                
                // Ensure environment is properly passed
                var env = ProcessInfo.processInfo.environment
                env["DYLD_LIBRARY_PATH"] = "/usr/local/ardium/lib:" + (env["DYLD_LIBRARY_PATH"] ?? "")
                env["ARDIUM_LIB_PATH"] = "/usr/local/ardium/lib"
                env["ARDIUM_STDLIB"] = "/usr/local/ardium/stdlib"
                process.environment = env
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                // 4. Stream Output
                let fileHandle = pipe.fileHandleForReading
                
                do {
                    try process.run()
                    
                    for try await line in fileHandle.bytes.lines {
                        if line.contains("Target Triple") { continue }
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
                    continuation.yield("❌ Error: Failed to launch Ardium runner: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }
    
    private static func runProcess(executable: String, arguments: [String]) async -> (stdout: String, stderr: String, exitCode: Int32) {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            
            var env = ProcessInfo.processInfo.environment
            env["DYLD_LIBRARY_PATH"] = "/usr/local/ardium/lib:" + (env["DYLD_LIBRARY_PATH"] ?? "")
            env["ARDIUM_LIB_PATH"] = "/usr/local/ardium/lib"
            env["ARDIUM_STDLIB"] = "/usr/local/ardium/stdlib"
            process.environment = env
            
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                
                continuation.resume(returning: (stdout, stderr, process.terminationStatus))
            } catch {
                continuation.resume(returning: ("", "Execution error: \(error.localizedDescription)", 1))
            }
        }
    }
}

