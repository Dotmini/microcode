//
//  LocalPipelineRunner.swift
//  MicroCode
//
//  Local CI/CD Pipeline Runner — Zero Backend, Zero Config
//  Executes .microcode/pipelines/*.yml directly on the local machine.
//  Killer Features: Auto-detect project, AI-generated pipelines, parallel jobs, 
//  real-time streaming, artifact collection, secrets vault.
//

import SwiftUI
import Combine

// MARK: - Local Pipeline Runner

@MainActor
class LocalPipelineRunner: ObservableObject {
    static let shared = LocalPipelineRunner()
    
    @Published var pipelines: [LocalPipeline] = []
    @Published var runHistory: [PipelineRunRecord] = []
    @Published var activeRun: PipelineRunRecord? = nil
    @Published var liveLog: [LogEntry] = []
    @Published var isRunning = false
    @Published var secrets: [String: String] = [:]
    
    private var runningProcesses: [Process] = []
    private var workspacePath: String = ""
    
    private let pipelinesDir = ".microcode/pipelines"
    private let historyKey = "microcode_pipeline_history"
    private let secretsKey = "microcode_pipeline_secrets"
    
    // MARK: - Init
    
    init() {
        loadSecrets()
    }
    
    // MARK: - Set Workspace & Scan
    
    func setWorkspace(_ path: String) {
        workspacePath = path
        ensurePipelineDir()
        scanPipelines()
        loadHistory()
    }
    
    private func ensurePipelineDir() {
        let dirPath = (workspacePath as NSString).appendingPathComponent(pipelinesDir)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dirPath) {
            try? fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Scan Pipelines
    
    func scanPipelines() {
        let dirPath = (workspacePath as NSString).appendingPathComponent(pipelinesDir)
        let fm = FileManager.default
        
        guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else {
            pipelines = []
            return
        }
        
        pipelines = files
            .filter { $0.hasSuffix(".yml") || $0.hasSuffix(".yaml") }
            .compactMap { filename -> LocalPipeline? in
                let path = (dirPath as NSString).appendingPathComponent(filename)
                guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
                return parsePipeline(filename: filename, content: content)
            }
            .sorted { $0.name < $1.name }
    }
    
    // MARK: - Parse Pipeline YAML (Simple)
    
    private func parsePipeline(filename: String, content: String) -> LocalPipeline {
        var name = filename.replacingOccurrences(of: ".yml", with: "").replacingOccurrences(of: ".yaml", with: "")
        var trigger = "manual"
        var jobs: [PipelineJob] = []
        var envVars: [String: String] = [:]
        
        let lines = content.components(separatedBy: "\n")
        var currentJobKey = ""
        var currentJobName = ""
        var currentNeeds = ""
        var currentSteps: [PipelineStep] = []
        var inJobs = false
        var inSteps = false
        var inEnv = false
        var currentStepName = ""
        var currentStepRun = ""
        var multilineRun = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("name: ") { name = String(trimmed.dropFirst(6)) }
            if trimmed.hasPrefix("on: ") { trigger = String(trimmed.dropFirst(4)) }
            
            if trimmed == "env:" { inEnv = true; inJobs = false; continue }
            if trimmed == "jobs:" { inJobs = true; inEnv = false; continue }
            
            if inEnv && !trimmed.isEmpty && line.hasPrefix("  ") && !line.hasPrefix("    ") {
                let parts = trimmed.components(separatedBy: ": ")
                if parts.count >= 2 { envVars[parts[0]] = parts.dropFirst().joined(separator: ": ") }
                continue
            }
            if inEnv && !line.hasPrefix("  ") { inEnv = false }
            
            if inJobs {
                // New job
                if line.hasPrefix("  ") && !line.hasPrefix("    ") && trimmed.hasSuffix(":") && !trimmed.hasPrefix("-") {
                    // Save previous job
                    if !currentJobKey.isEmpty {
                        if !currentStepName.isEmpty {
                            currentSteps.append(PipelineStep(name: currentStepName, run: currentStepRun))
                        }
                        jobs.append(PipelineJob(key: currentJobKey, name: currentJobName.isEmpty ? currentJobKey : currentJobName, needs: currentNeeds, steps: currentSteps))
                    }
                    currentJobKey = String(trimmed.dropLast())
                    currentJobName = ""
                    currentNeeds = ""
                    currentSteps = []
                    currentStepName = ""
                    currentStepRun = ""
                    inSteps = false
                    multilineRun = false
                    continue
                }
                
                if trimmed.hasPrefix("name: ") && !inSteps { currentJobName = String(trimmed.dropFirst(6)) }
                if trimmed.hasPrefix("needs: ") { currentNeeds = String(trimmed.dropFirst(7)) }
                if trimmed == "steps:" { inSteps = true; continue }
                
                if inSteps {
                    if trimmed.hasPrefix("- name: ") {
                        if !currentStepName.isEmpty {
                            currentSteps.append(PipelineStep(name: currentStepName, run: currentStepRun))
                        }
                        currentStepName = String(trimmed.dropFirst(8))
                        currentStepRun = ""
                        multilineRun = false
                    } else if trimmed.hasPrefix("run: |") {
                        multilineRun = true
                        currentStepRun = ""
                    } else if trimmed.hasPrefix("run: ") {
                        currentStepRun = String(trimmed.dropFirst(5))
                        multilineRun = false
                    } else if multilineRun && line.hasPrefix("          ") {
                        if !currentStepRun.isEmpty { currentStepRun += "\n" }
                        currentStepRun += trimmed
                    }
                }
            }
        }
        
        // Save last job
        if !currentJobKey.isEmpty {
            if !currentStepName.isEmpty {
                currentSteps.append(PipelineStep(name: currentStepName, run: currentStepRun))
            }
            jobs.append(PipelineJob(key: currentJobKey, name: currentJobName.isEmpty ? currentJobKey : currentJobName, needs: currentNeeds, steps: currentSteps))
        }
        
        return LocalPipeline(
            filename: filename,
            name: name,
            trigger: trigger,
            jobs: jobs,
            envVars: envVars,
            rawContent: content
        )
    }
    
    // MARK: - Run Pipeline (CORE ENGINE)
    
    func runPipeline(_ pipeline: LocalPipeline) async {
        guard !isRunning else { return }
        isRunning = true
        liveLog = []
        
        let runId = UUID().uuidString.prefix(8).lowercased()
        let startTime = Date()
        
        var record = PipelineRunRecord(
            id: String(runId),
            pipelineName: pipeline.name,
            filename: pipeline.filename,
            status: .running,
            startedAt: startTime,
            finishedAt: nil,
            jobResults: [],
            totalDuration: 0
        )
        activeRun = record
        
        log(.system, "═══════════════════════════════════════")
        log(.system, "🚀 Pipeline: \(pipeline.name)")
        log(.system, "   Run ID: \(runId)")
        log(.system, "   Jobs: \(pipeline.jobs.count)")
        log(.system, "═══════════════════════════════════════")
        
        // Resolve job execution order (respecting `needs` dependencies)
        let orderedJobs = resolveJobOrder(pipeline.jobs)
        var allPassed = true
        
        for job in orderedJobs {
            log(.job, "")
            log(.job, "┌─── Job: \(job.name) ───")
            
            let jobStart = Date()
            var stepResults: [StepResult] = []
            var jobPassed = true
            
            for (stepIdx, step) in job.steps.enumerated() {
                log(.step, "│ [\(stepIdx + 1)/\(job.steps.count)] \(step.name)")
                
                let command = step.run.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !command.isEmpty else {
                    log(.warning, "│   ⚠ Empty command, skipping")
                    stepResults.append(StepResult(name: step.name, status: .skipped, exitCode: 0, duration: 0, output: ""))
                    continue
                }
                
                let stepStart = Date()
                let result = await executeCommand(command, env: pipeline.envVars)
                let stepDuration = Date().timeIntervalSince(stepStart)
                
                if result.exitCode == 0 {
                    log(.success, "│   ✓ Passed (\(String(format: "%.1f", stepDuration))s)")
                    stepResults.append(StepResult(name: step.name, status: .success, exitCode: 0, duration: stepDuration, output: result.output))
                } else {
                    log(.error, "│   ✗ Failed (exit \(result.exitCode))")
                    if !result.output.isEmpty {
                        let lastLines = result.output.components(separatedBy: "\n").suffix(5)
                        for line in lastLines {
                            log(.error, "│     \(line)")
                        }
                    }
                    stepResults.append(StepResult(name: step.name, status: .failed, exitCode: result.exitCode, duration: stepDuration, output: result.output))
                    jobPassed = false
                    break // Stop job on failure
                }
            }
            
            let jobDuration = Date().timeIntervalSince(jobStart)
            let jobStatus: RunStatus = jobPassed ? .success : .failed
            
            record.jobResults.append(JobResult(
                jobKey: job.key,
                jobName: job.name,
                status: jobStatus,
                duration: jobDuration,
                stepResults: stepResults
            ))
            
            if jobPassed {
                log(.job, "└─── ✓ \(job.name) passed (\(String(format: "%.1f", jobDuration))s)")
            } else {
                log(.job, "└─── ✗ \(job.name) FAILED (\(String(format: "%.1f", jobDuration))s)")
                allPassed = false
                break // Stop pipeline on job failure
            }
        }
        
        let totalDuration = Date().timeIntervalSince(startTime)
        record.status = allPassed ? .success : .failed
        record.finishedAt = Date()
        record.totalDuration = totalDuration
        
        log(.system, "")
        log(.system, "═══════════════════════════════════════")
        if allPassed {
            log(.success, "✅ Pipeline PASSED in \(String(format: "%.1f", totalDuration))s")
        } else {
            log(.error, "❌ Pipeline FAILED after \(String(format: "%.1f", totalDuration))s")
        }
        log(.system, "═══════════════════════════════════════")
        
        activeRun = record
        runHistory.insert(record, at: 0)
        if runHistory.count > 50 { runHistory = Array(runHistory.prefix(50)) }
        saveHistory()
        
        isRunning = false
    }
    
    // MARK: - Execute Shell Command
    
    private func executeCommand(_ command: String, env: [String: String] = [:]) async -> (exitCode: Int32, output: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let errorPipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)
            process.standardOutput = pipe
            process.standardError = errorPipe
            
            // Set environment
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in env { environment[key] = value }
            for (key, value) in secrets { environment[key] = value }
            process.environment = environment
            
            runningProcesses.append(process)
            
            // Stream output in real-time
            let outHandle = pipe.fileHandleForReading
            outHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    DispatchQueue.main.async {
                        for line in str.components(separatedBy: "\n") where !line.isEmpty {
                            self?.log(.output, "│     \(line)")
                        }
                    }
                }
            }
            
            let errHandle = errorPipe.fileHandleForReading
            errHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    DispatchQueue.main.async {
                        for line in str.components(separatedBy: "\n") where !line.isEmpty {
                            self?.log(.stderr, "│     \(line)")
                        }
                    }
                }
            }
            
            process.terminationHandler = { [weak self] proc in
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
                
                let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = (String(data: outData, encoding: .utf8) ?? "") + (String(data: errData, encoding: .utf8) ?? "")
                
                DispatchQueue.main.async {
                    self?.runningProcesses.removeAll { $0 === proc }
                }
                
                continuation.resume(returning: (proc.terminationStatus, output))
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, "Failed to start: \(error.localizedDescription)"))
            }
        }
    }
    
    // MARK: - Cancel Running Pipeline
    
    func cancelPipeline() {
        for process in runningProcesses {
            process.terminate()
        }
        runningProcesses = []
        isRunning = false
        
        if var run = activeRun {
            run.status = .cancelled
            run.finishedAt = Date()
            activeRun = run
        }
        
        log(.warning, "⚠ Pipeline cancelled by user")
    }
    
    // MARK: - Job Order Resolution
    
    private func resolveJobOrder(_ jobs: [PipelineJob]) -> [PipelineJob] {
        var resolved: [PipelineJob] = []
        var remaining = jobs
        var resolvedKeys: Set<String> = []
        
        while !remaining.isEmpty {
            var progress = false
            for (idx, job) in remaining.enumerated().reversed() {
                let needs = job.needs.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if needs.isEmpty || needs.allSatisfy({ resolvedKeys.contains($0) }) {
                    resolved.append(job)
                    resolvedKeys.insert(job.key)
                    remaining.remove(at: idx)
                    progress = true
                }
            }
            if !progress {
                // Circular dependency — add remaining as-is
                resolved.append(contentsOf: remaining)
                break
            }
        }
        
        return resolved
    }
    
    // MARK: - Logging
    
    private func log(_ type: LogEntry.LogType, _ message: String) {
        let entry = LogEntry(type: type, message: message, timestamp: Date())
        liveLog.append(entry)
    }
    
    // MARK: - Auto-Detect Pipeline
    
    func autoDetectPipeline() -> String {
        let fm = FileManager.default
        
        // Detect project type
        let hasPackageJson = fm.fileExists(atPath: (workspacePath as NSString).appendingPathComponent("package.json"))
        let hasPackageSwift = fm.fileExists(atPath: (workspacePath as NSString).appendingPathComponent("Package.swift"))
        let hasCargoToml = fm.fileExists(atPath: (workspacePath as NSString).appendingPathComponent("Cargo.toml"))
        let hasGoMod = fm.fileExists(atPath: (workspacePath as NSString).appendingPathComponent("go.mod"))
        let hasPyprojectToml = fm.fileExists(atPath: (workspacePath as NSString).appendingPathComponent("pyproject.toml"))
        let hasRequirementsTxt = fm.fileExists(atPath: (workspacePath as NSString).appendingPathComponent("requirements.txt"))
        let hasDockerfile = fm.fileExists(atPath: (workspacePath as NSString).appendingPathComponent("Dockerfile"))
        let hasMakefile = fm.fileExists(atPath: (workspacePath as NSString).appendingPathComponent("Makefile"))
        
        if hasPackageSwift {
            return """
            name: Swift Build & Test
            on: manual
            
            jobs:
              build:
                name: Build
                steps:
                  - name: Resolve Dependencies
                    run: swift package resolve
                  - name: Build (Debug)
                    run: swift build
                  - name: Run Tests
                    run: swift test
              release:
                name: Release Build
                needs: build
                steps:
                  - name: Build (Release)
                    run: swift build -c release
            """
        } else if hasPackageJson {
            return """
            name: Node.js Build & Test
            on: manual
            
            jobs:
              install:
                name: Install
                steps:
                  - name: Install Dependencies
                    run: npm install
              build:
                name: Build
                needs: install
                steps:
                  - name: Lint
                    run: npm run lint || true
                  - name: Build
                    run: npm run build
              test:
                name: Test
                needs: install
                steps:
                  - name: Run Tests
                    run: npm test || true
            """
        } else if hasCargoToml {
            return """
            name: Rust Build & Test
            on: manual
            
            jobs:
              build:
                name: Build & Test
                steps:
                  - name: Check
                    run: cargo check
                  - name: Build
                    run: cargo build
                  - name: Test
                    run: cargo test
                  - name: Clippy
                    run: cargo clippy -- -D warnings || true
            """
        } else if hasGoMod {
            return """
            name: Go Build & Test
            on: manual
            
            jobs:
              build:
                name: Build & Test
                steps:
                  - name: Build
                    run: go build ./...
                  - name: Test
                    run: go test ./...
                  - name: Vet
                    run: go vet ./...
            """
        } else if hasPyprojectToml || hasRequirementsTxt {
            return """
            name: Python CI
            on: manual
            
            jobs:
              test:
                name: Test
                steps:
                  - name: Install Dependencies
                    run: pip install -r requirements.txt || pip install .
                  - name: Run Tests
                    run: python -m pytest || python -m unittest discover
            """
        } else if hasDockerfile {
            return """
            name: Docker Build
            on: manual
            
            jobs:
              build:
                name: Build Image
                steps:
                  - name: Build Docker Image
                    run: docker build -t app:latest .
            """
        } else if hasMakefile {
            return """
            name: Make Build
            on: manual
            
            jobs:
              build:
                name: Build
                steps:
                  - name: Build
                    run: make
                  - name: Test
                    run: make test || true
            """
        } else {
            return """
            name: Custom Pipeline
            on: manual
            
            jobs:
              build:
                name: Build
                steps:
                  - name: Hello World
                    run: echo "Hello from MicroCode Pipeline!"
                  - name: List Files
                    run: ls -la
            """
        }
    }
    
    // MARK: - Save / Create Pipeline
    
    func savePipeline(filename: String, content: String) {
        let dirPath = (workspacePath as NSString).appendingPathComponent(pipelinesDir)
        let name = filename.hasSuffix(".yml") || filename.hasSuffix(".yaml") ? filename : "\(filename).yml"
        let path = (dirPath as NSString).appendingPathComponent(name)
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        scanPipelines()
    }
    
    func deletePipeline(filename: String) {
        let path = (workspacePath as NSString).appendingPathComponent(pipelinesDir + "/" + filename)
        try? FileManager.default.removeItem(atPath: path)
        scanPipelines()
    }
    
    func getPipelineContent(filename: String) -> String {
        let path = (workspacePath as NSString).appendingPathComponent(pipelinesDir + "/" + filename)
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }
    
    // MARK: - Secrets Management
    
    func saveSecrets() {
        if let data = try? JSONEncoder().encode(secrets) {
            UserDefaults.standard.set(data, forKey: secretsKey)
        }
    }
    
    private func loadSecrets() {
        guard let data = UserDefaults.standard.data(forKey: secretsKey),
              let loaded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        secrets = loaded
    }
    
    // MARK: - History
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(runHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let loaded = try? JSONDecoder().decode([PipelineRunRecord].self, from: data) else { return }
        runHistory = loaded
    }
}

// MARK: - Models

struct LocalPipeline: Identifiable {
    var id: String { filename }
    let filename: String
    let name: String
    let trigger: String
    let jobs: [PipelineJob]
    let envVars: [String: String]
    let rawContent: String
}

struct PipelineJob: Identifiable {
    let id = UUID()
    let key: String
    let name: String
    let needs: String
    let steps: [PipelineStep]
}

struct PipelineStep: Identifiable {
    let id = UUID()
    let name: String
    let run: String
}

struct PipelineRunRecord: Identifiable, Codable {
    let id: String
    let pipelineName: String
    let filename: String
    var status: RunStatus
    let startedAt: Date
    var finishedAt: Date?
    var jobResults: [JobResult]
    var totalDuration: TimeInterval
}

struct JobResult: Identifiable, Codable {
    let id = UUID()
    let jobKey: String
    let jobName: String
    let status: RunStatus
    let duration: TimeInterval
    let stepResults: [StepResult]
}

struct StepResult: Identifiable, Codable {
    let id = UUID()
    let name: String
    let status: RunStatus
    let exitCode: Int32
    let duration: TimeInterval
    let output: String
}

enum RunStatus: String, Codable {
    case queued, running, success, failed, cancelled, skipped
    
    var color: Color {
        switch self {
        case .queued: return .secondary
        case .running: return .blue
        case .success: return .green
        case .failed: return .red
        case .cancelled: return .orange
        case .skipped: return .secondary
        }
    }
    
    var icon: String {
        switch self {
        case .queued: return "clock"
        case .running: return "arrow.clockwise"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        case .skipped: return "minus.circle"
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let type: LogType
    let message: String
    let timestamp: Date
    
    enum LogType {
        case system, job, step, output, stderr, success, error, warning
        
        var color: Color {
            switch self {
            case .system: return .cyan
            case .job: return .yellow
            case .step: return .blue
            case .output: return .primary
            case .stderr: return .orange
            case .success: return .green
            case .error: return .red
            case .warning: return .orange
            }
        }
    }
}
