// Copyright © 2025 Dotmini Software. All rights reserved.

import Foundation
import Combine
import SwiftUI

enum LoopPhase: String, Codable {
    case idle
    case building
    case testing
    case analyzing
    case fixing
    case paused
    case completed
}

enum IterationStatus: String, Codable {
    case building
    case testing
    case analyzing
    case fixing
    case passed
    case failed
    case skipped
}

struct LoopConfig {
    var maxIterations: Int = 5
    var maxDurationSeconds: TimeInterval = 600  // 10 minutes
    var autoApply: Bool = false  // require approval for each fix
    var buildCommand: String = ""  // e.g. "cargo build", "npm run build"
    var testCommand: String = ""  // e.g. "pytest", "cargo test"
    var workingDirectory: String = ""
    var maxDiffLines: Int = 50  // pause if fix exceeds this
}

struct CommandResult {
    let command: String
    let exitCode: Int
    let stdout: String
    let stderr: String
    let duration: TimeInterval
    var passed: Bool { exitCode == 0 }
}

struct LoopIteration: Identifiable {
    let id: UUID = UUID()
    let number: Int
    let startedAt: Date
    var completedAt: Date?
    var buildResult: CommandResult?
    var testResult: CommandResult?
    var analysisResult: String?
    var fixApplied: String?  // diff description
    var status: IterationStatus
}

struct LoopSummary {
    let totalIterations: Int
    let testsPassedFinal: Bool
    let totalDuration: TimeInterval
    let fixesApplied: Int
    let filesModified: [String]
}

@MainActor
class AutonomousLoopService: ObservableObject {
    static let shared = AutonomousLoopService()
    
    @Published var config: LoopConfig = LoopConfig()
    @Published var iterations: [LoopIteration] = []
    @Published var isRunning: Bool = false
    @Published var currentPhase: LoopPhase = .idle
    @Published var summary: LoopSummary?
    
    private var cancelRequested = false
    private var pauseRequested = false
    
    private init() {}
    
    func startLoop(config: LoopConfig) async {
        self.config = config
        self.iterations = []
        self.isRunning = true
        self.cancelRequested = false
        self.pauseRequested = false
        self.currentPhase = .idle
        self.summary = nil
        
        let loopStartTime = Date()
        var fixesApplied = 0
        var testsPassedFinal = false
        var filesModified = Set<String>()
        
        for i in 1...config.maxIterations {
            guard !cancelRequested else { break }
            
            if pauseRequested {
                self.currentPhase = .paused
                // In a real implementation we would wait here
                // For now we will just break if paused
                break
            }
            
            var iteration = LoopIteration(number: i, startedAt: Date(), status: .building)
            self.iterations.append(iteration)
            
            // Phase: Build
            if !config.buildCommand.isEmpty {
                self.currentPhase = .building
                iteration.status = .building
                updateIteration(iteration)
                
                do {
                    let buildResult = try await runCommand(config.buildCommand, in: config.workingDirectory)
                    iteration.buildResult = buildResult
                    if !buildResult.passed {
                        iteration.status = .failed
                    }
                } catch {
                    iteration.status = .failed
                    updateIteration(iteration)
                    break
                }
            }
            
            // Check if build failed
            if iteration.status == .failed {
                self.currentPhase = .analyzing
                iteration.status = .analyzing
                updateIteration(iteration)
                
                // Analyze and Fix logic would go here
                let analysis = await analyzeFailure(iteration.buildResult ?? CommandResult(command: "", exitCode: -1, stdout: "", stderr: "", duration: 0))
                iteration.analysisResult = analysis
                
                if let fix = await generateFix(analysis: analysis, buildResult: iteration.buildResult, testResult: nil) {
                    self.currentPhase = .fixing
                    iteration.status = .fixing
                    updateIteration(iteration)
                    
                    do {
                        try await applyFix(fix)
                        fixesApplied += 1
                        iteration.fixApplied = "Applied fix based on build failure"
                    } catch {
                        print("Failed to apply fix: \(error)")
                    }
                }
                
                iteration.completedAt = Date()
                updateIteration(iteration)
                continue
            }
            
            // Phase: Test
            if !config.testCommand.isEmpty {
                self.currentPhase = .testing
                iteration.status = .testing
                updateIteration(iteration)
                
                do {
                    let testResult = try await runCommand(config.testCommand, in: config.workingDirectory)
                    iteration.testResult = testResult
                    if testResult.passed {
                        iteration.status = .passed
                        testsPassedFinal = true
                        iteration.completedAt = Date()
                        updateIteration(iteration)
                        break // Tests passed, we can exit the loop!
                    } else {
                        iteration.status = .failed
                    }
                } catch {
                    iteration.status = .failed
                    updateIteration(iteration)
                    break
                }
            }
            
            // Phase: Analyze and Fix for Tests
            if iteration.status == .failed {
                self.currentPhase = .analyzing
                iteration.status = .analyzing
                updateIteration(iteration)
                
                let analysis = await analyzeFailure(iteration.testResult ?? CommandResult(command: "", exitCode: -1, stdout: "", stderr: "", duration: 0))
                iteration.analysisResult = analysis
                
                if let fix = await generateFix(analysis: analysis, buildResult: nil, testResult: iteration.testResult) {
                    self.currentPhase = .fixing
                    iteration.status = .fixing
                    updateIteration(iteration)
                    
                    do {
                        try await applyFix(fix)
                        fixesApplied += 1
                        iteration.fixApplied = "Applied fix based on test failure"
                    } catch {
                        print("Failed to apply fix: \(error)")
                    }
                }
                
                iteration.completedAt = Date()
                updateIteration(iteration)
            }
            
            // Check time limits
            if Date().timeIntervalSince(loopStartTime) > config.maxDurationSeconds {
                break
            }
        }
        
        self.isRunning = false
        self.currentPhase = .completed
        self.summary = LoopSummary(
            totalIterations: self.iterations.count,
            testsPassedFinal: testsPassedFinal,
            totalDuration: Date().timeIntervalSince(loopStartTime),
            fixesApplied: fixesApplied,
            filesModified: Array(filesModified)
        )
    }
    
    func pauseLoop() {
        self.pauseRequested = true
    }
    
    func resumeLoop() async {
        self.pauseRequested = false
        // Real implementation would resume where it left off
        if self.currentPhase == .paused {
            self.currentPhase = .idle
            // Need complex state restoration for real resume
        }
    }
    
    func cancelLoop() {
        self.cancelRequested = true
        self.isRunning = false
    }
    
    func detectTestCommand(in directory: String) -> String? {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: directory)
        
        if fm.fileExists(atPath: url.appendingPathComponent("Cargo.toml").path) {
            return "cargo test"
        } else if fm.fileExists(atPath: url.appendingPathComponent("package.json").path) {
            return "npm test"
        } else if fm.fileExists(atPath: url.appendingPathComponent("pytest.ini").path) ||
                  fm.fileExists(atPath: url.appendingPathComponent("setup.py").path) ||
                  fm.fileExists(atPath: url.appendingPathComponent("pyproject.toml").path) {
            return "pytest"
        } else if fm.fileExists(atPath: url.appendingPathComponent("go.mod").path) {
            return "go test ./..."
        } else if fm.fileExists(atPath: url.appendingPathComponent("Makefile").path) {
            return "make test"
        } else if (try? fm.contentsOfDirectory(atPath: directory))?.contains(where: { $0.hasSuffix(".xcodeproj") }) == true {
            return "xcodebuild test"
        }
        return nil
    }
    
    func detectBuildCommand(in directory: String) -> String? {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: directory)
        
        if fm.fileExists(atPath: url.appendingPathComponent("Cargo.toml").path) {
            return "cargo build"
        } else if fm.fileExists(atPath: url.appendingPathComponent("package.json").path) {
            return "npm run build"
        } else if fm.fileExists(atPath: url.appendingPathComponent("go.mod").path) {
            return "go build ./..."
        } else if fm.fileExists(atPath: url.appendingPathComponent("Makefile").path) {
            return "make"
        } else if (try? fm.contentsOfDirectory(atPath: directory))?.contains(where: { $0.hasSuffix(".xcodeproj") }) == true {
            return "xcodebuild build"
        }
        return nil
    }
    
    private func updateIteration(_ iteration: LoopIteration) {
        if let index = iterations.firstIndex(where: { $0.id == iteration.id }) {
            iterations[index] = iteration
        }
    }
    
    private func runCommand(_ cmd: String, in directory: String) async throws -> CommandResult {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", cmd]
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            let startTime = Date()
            
            do {
                try process.run()
                
                DispatchQueue.global().async {
                    process.waitUntilExit()
                    
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                    let duration = Date().timeIntervalSince(startTime)
                    
                    let result = CommandResult(
                        command: cmd,
                        exitCode: Int(process.terminationStatus),
                        stdout: stdout,
                        stderr: stderr,
                        duration: duration
                    )
                    
                    continuation.resume(returning: result)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func analyzeFailure(_ result: CommandResult) async -> String {
        // Mocking AI analysis
        return "Analyzed failure: \(result.stderr.prefix(100))"
    }
    
    private func generateFix(analysis: String, buildResult: CommandResult?, testResult: CommandResult?) async -> String? {
        // Mocking fix generation
        return "Generated fix based on analysis"
    }
    
    private func applyFix(_ fixContent: String) async throws {
        // Mocking fix application
        print("Applying fix: \(fixContent)")
    }
}
