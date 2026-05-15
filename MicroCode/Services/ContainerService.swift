//
//  ContainerService.swift
//  MicroCode
//
//  Apple Container Integration
//  Run, Build, Manage containers seamlessly
//
//  SPU AI CLUB - Dotmini Software
//

import Foundation
import Combine

// MARK: - Container Models

struct Container: Identifiable, Codable {
    let id: String
    var name: String
    var image: String
    var status: ContainerStatus
    var createdAt: Date?
    var ports: [PortMapping]
    var volumes: [VolumeMount]
    
    enum ContainerStatus: String, Codable {
        case running
        case stopped
        case created
        case exited
        case unknown
    }
    
    struct PortMapping: Codable {
        var hostPort: Int
        var containerPort: Int
        var protocol_: String
    }
    
    struct VolumeMount: Codable {
        var hostPath: String
        var containerPath: String
        var readOnly: Bool
    }
}

struct ContainerImage: Identifiable, Codable {
    var id: String { name }
    var name: String
    var tag: String
    var size: String?
    var createdAt: Date?
}

// MARK: - Container Service

@MainActor
class ContainerService: ObservableObject {
    static let shared = ContainerService()
    
    @Published var containers: [Container] = []
    @Published var images: [ContainerImage] = []
    @Published var isLoading = false
    @Published var terminalOutput: String = ""
    @Published var isContainerRunning = false
    @Published var activeContainer: Container?
    
    // System Status
    @Published var systemStatus: ContainerSystemStatus = .unknown
    @Published var systemStatusMessage: String = ""
    @Published var isSystemReady = false
    
    enum ContainerSystemStatus {
        case unknown
        case checking
        case notInstalled
        case pluginsUnavailable
        case needsStart
        case ready
        case error(String)
        
        var displayMessage: String {
            switch self {
            case .unknown: return "Checking container system..."
            case .checking: return "Verifying container runtime..."
            case .notInstalled: return "Apple Container CLI not installed"
            case .pluginsUnavailable: return "Container plugins unavailable"
            case .needsStart: return "Container system needs to be started"
            case .ready: return "Container system ready"
            case .error(let msg): return "Error: \(msg)"
            }
        }
        
        var isOperational: Bool {
            if case .ready = self { return true }
            return false
        }
    }
    
    // Production Deployment Profiles
    struct DeploymentProfile: Identifiable, Codable {
        var id = UUID()
        var name: String
        var baseImage: String
        var ports: [Container.PortMapping]
        var volumes: [Container.VolumeMount]
        var environment: [String: String]
        var command: String?
        var healthCheck: HealthCheck?
        var resources: ResourceLimits?
        
        struct HealthCheck: Codable {
            var test: String
            var interval: Int // seconds
            var timeout: Int
            var retries: Int
        }
        
        struct ResourceLimits: Codable {
            var cpuLimit: Double? // CPUs (e.g., 2.0)
            var memoryLimit: String? // e.g., "2g", "512m"
        }
        
        static let webApp = DeploymentProfile(
            name: "Web Application",
            baseImage: "node:20-slim",
            ports: [Container.PortMapping(hostPort: 3000, containerPort: 3000, protocol_: "tcp")],
            volumes: [],
            environment: ["NODE_ENV": "production"],
            command: "npm start"
        )
        
        static let api = DeploymentProfile(
            name: "REST API",
            baseImage: "python:3.12-slim",
            ports: [Container.PortMapping(hostPort: 8000, containerPort: 8000, protocol_: "tcp")],
            volumes: [],
            environment: ["PYTHONUNBUFFERED": "1"],
            command: "uvicorn main:app --host 0.0.0.0 --port 8000"
        )
        
        static let database = DeploymentProfile(
            name: "Database",
            baseImage: "postgres:16-alpine",
            ports: [Container.PortMapping(hostPort: 5432, containerPort: 5432, protocol_: "tcp")],
            volumes: [Container.VolumeMount(hostPath: "./data", containerPath: "/var/lib/postgresql/data", readOnly: false)],
            environment: ["POSTGRES_PASSWORD": "dev_password"],
            healthCheck: HealthCheck(test: "pg_isready", interval: 10, timeout: 5, retries: 3)
        )
    }
    
    @Published var deploymentProfiles: [DeploymentProfile] = [.webApp, .api, .database]
    
    private let containerPath = "/usr/local/bin/container"
    private var runningProcess: Process?
    
    init() {
        Task {
            await checkSystemStatus()
        }
    }
    
    // MARK: - System Status & Initialization
    
    /// Check if container system is operational
    func checkSystemStatus() async {
        systemStatus = .checking
        
        // Check if container CLI exists
        guard FileManager.default.fileExists(atPath: containerPath) else {
            systemStatus = .notInstalled
            systemStatusMessage = "Install Apple Container CLI: brew install container"
            isSystemReady = false
            return
        }
        
        do {
            // Try a simple command to check system status
            let output = try await runContainerCommand(["system", "status"])
            
            if output.lowercased().contains("running") || output.lowercased().contains("ready") {
                systemStatus = .ready
                systemStatusMessage = "Container system operational"
                isSystemReady = true
                terminalOutput += "✅ Container system ready\n"
            } else if output.lowercased().contains("not running") || output.lowercased().contains("stopped") {
                systemStatus = .needsStart
                systemStatusMessage = "Run: container system start"
                isSystemReady = false
            } else {
                systemStatus = .ready
                isSystemReady = true
            }
        } catch {
            let errorMsg = error.localizedDescription
            
            if errorMsg.contains("Plugins are unavailable") || errorMsg.contains("plugins") {
                systemStatus = .pluginsUnavailable
                systemStatusMessage = "Start container system: container system start"
                isSystemReady = false
                terminalOutput += "⚠️ Container plugins unavailable. Run: container system start\n"
            } else if errorMsg.contains("not found") || errorMsg.contains("No such file") {
                systemStatus = .notInstalled
                systemStatusMessage = "Container CLI not found at \(containerPath)"
                isSystemReady = false
            } else {
                // Might still be operational despite error
                systemStatus = .ready
                isSystemReady = true
            }
        }
    }
    
    /// Initialize container system (start services)
    func initializeSystem() async throws {
        terminalOutput += "$ container system start\n"
        systemStatus = .checking
        
        do {
            let output = try await runContainerCommand(["system", "start"])
            terminalOutput += output + "\n"
            
            // Wait a moment for services to initialize
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            await checkSystemStatus()
            
            if isSystemReady {
                terminalOutput += "✅ Container system started successfully\n"
            }
        } catch {
            terminalOutput += "❌ Failed to start: \(error.localizedDescription)\n"
            throw error
        }
    }
    
    /// Stop container system
    func stopSystem() async throws {
        terminalOutput += "$ container system stop\n"
        let output = try await runContainerCommand(["system", "stop"])
        terminalOutput += output + "\n"
        isSystemReady = false
        systemStatus = .needsStart
    }
    
    // MARK: - Production Deployment
    
    /// Deploy a container using a production profile
    func deployWithProfile(_ profile: DeploymentProfile, projectPath: String, containerName: String? = nil) async throws -> Container {
        if !isSystemReady {
            try await initializeSystem()
        }
        
        let name = containerName ?? "deploy-\(profile.name.lowercased().replacingOccurrences(of: " ", with: "-"))-\(UUID().uuidString.prefix(6))"
        
        var args = ["run", "-d", "--name", name]
        
        // Add ports
        for port in profile.ports {
            args.append("-p")
            args.append("\(port.hostPort):\(port.containerPort)")
        }
        
        // Add volumes
        let projectVolume = Container.VolumeMount(hostPath: projectPath, containerPath: "/app", readOnly: false)
        let allVolumes = [projectVolume] + profile.volumes
        
        for vol in allVolumes {
            args.append("-v")
            let hostPath = vol.hostPath.hasPrefix("/") ? vol.hostPath : "\(projectPath)/\(vol.hostPath)"
            args.append("\(hostPath):\(vol.containerPath)\(vol.readOnly ? ":ro" : "")")
        }
        
        // Add environment variables
        for (key, value) in profile.environment {
            args.append("-e")
            args.append("\(key)=\(value)")
        }
        
        // Set working directory
        args.append("-w")
        args.append("/app")
        
        // Add resource limits if specified
        if let resources = profile.resources {
            if let cpu = resources.cpuLimit {
                args.append("--cpus")
                args.append(String(cpu))
            }
            if let mem = resources.memoryLimit {
                args.append("-m")
                args.append(mem)
            }
        }
        
        // Add image
        args.append(profile.baseImage)
        
        // Add command
        if let cmd = profile.command {
            args.append("sh")
            args.append("-c")
            args.append(cmd)
        }
        
        terminalOutput += "🚀 Deploying with profile: \(profile.name)\n"
        terminalOutput += "$ container \(args.joined(separator: " "))\n"
        
        let output = try await runContainerCommand(args)
        terminalOutput += output + "\n"
        
        try await listContainers()
        
        if let container = containers.first(where: { $0.name == name }) {
            terminalOutput += "✅ Container deployed: \(name)\n"
            return container
        }
        
        return Container(
            id: output.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name,
            image: profile.baseImage,
            status: .running,
            createdAt: Date(),
            ports: profile.ports,
            volumes: allVolumes
        )
    }
    
    /// Quick deploy common configurations
    func quickDeploy(type: QuickDeployType, projectPath: String) async throws -> Container {
        let profile: DeploymentProfile
        
        switch type {
        case .webApp(let port):
            profile = DeploymentProfile(
                name: "Quick Web",
                baseImage: "node:20-slim",
                ports: [Container.PortMapping(hostPort: port, containerPort: port, protocol_: "tcp")],
                volumes: [],
                environment: ["PORT": String(port)],
                command: "npm install && npm start"
            )
        case .pythonAPI(let port):
            profile = DeploymentProfile(
                name: "Python API",
                baseImage: "python:3.12-slim",
                ports: [Container.PortMapping(hostPort: port, containerPort: port, protocol_: "tcp")],
                volumes: [],
                environment: ["PYTHONUNBUFFERED": "1"],
                command: "pip install -r requirements.txt && python main.py"
            )
        case .staticSite(let port):
            profile = DeploymentProfile(
                name: "Static Site",
                baseImage: "nginx:alpine",
                ports: [Container.PortMapping(hostPort: port, containerPort: 80, protocol_: "tcp")],
                volumes: [Container.VolumeMount(hostPath: projectPath, containerPath: "/usr/share/nginx/html", readOnly: true)],
                environment: [:]
            )
        case .devEnvironment(let language):
            profile = DeploymentProfile(
                name: "Dev Env",
                baseImage: getImageForLanguage(language),
                ports: [],
                volumes: [],
                environment: ["DEV": "true"],
                command: "tail -f /dev/null" // Keep alive for exec
            )
        }
        
        return try await deployWithProfile(profile, projectPath: projectPath)
    }
    
    enum QuickDeployType {
        case webApp(port: Int)
        case pythonAPI(port: Int)
        case staticSite(port: Int)
        case devEnvironment(language: String)
    }
    
    // MARK: - Container Management
    
    func listContainers() async throws {
        isLoading = true
        defer { isLoading = false }
        
        let output = try await runContainerCommand(["list", "--format", "json"])
        
        // Parse JSON output
        if let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            containers = json.compactMap { parseContainer($0) }
        } else {
            // Fallback: parse text output
            containers = parseTextContainerList(output)
        }
    }
    
    func createContainer(
        name: String,
        image: String,
        ports: [Container.PortMapping] = [],
        volumes: [Container.VolumeMount] = [],
        workDir: String? = nil
    ) async throws -> Container {
        isLoading = true
        defer { isLoading = false }
        
        var args = ["create", "--name", name]
        
        // Add ports
        for port in ports {
            args.append("-p")
            args.append("\(port.hostPort):\(port.containerPort)")
        }
        
        // Add volumes
        for vol in volumes {
            args.append("-v")
            args.append("\(vol.hostPath):\(vol.containerPath)\(vol.readOnly ? ":ro" : "")")
        }
        
        // Add working directory
        if let wd = workDir {
            args.append("-w")
            args.append(wd)
        }
        
        args.append(image)
        
        let output = try await runContainerCommand(args)
        terminalOutput += "$ container \(args.joined(separator: " "))\n\(output)\n"
        
        // Refresh list
        try await listContainers()
        
        return containers.first(where: { $0.name == name }) ?? Container(
            id: output.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name,
            image: image,
            status: .created,
            createdAt: Date(),
            ports: ports,
            volumes: volumes
        )
    }
    
    func runContainer(
        image: String,
        name: String? = nil,
        ports: [Container.PortMapping] = [],
        volumes: [Container.VolumeMount] = [],
        workDir: String? = nil,
        command: String? = nil,
        detached: Bool = true
    ) async throws {
        isLoading = true
        
        var args = ["run"]
        
        if detached {
            args.append("-d")
        }
        
        if let n = name {
            args.append("--name")
            args.append(n)
        }
        
        // Add ports
        for port in ports {
            args.append("-p")
            args.append("\(port.hostPort):\(port.containerPort)")
        }
        
        // Add volumes
        for vol in volumes {
            args.append("-v")
            args.append("\(vol.hostPath):\(vol.containerPath)\(vol.readOnly ? ":ro" : "")")
        }
        
        // Add working directory
        if let wd = workDir {
            args.append("-w")
            args.append(wd)
        }
        
        args.append(image)
        
        if let cmd = command {
            args.append(contentsOf: cmd.split(separator: " ").map(String.init))
        }
        
        terminalOutput += "$ container \(args.joined(separator: " "))\n"
        
        let output = try await runContainerCommand(args)
        terminalOutput += output + "\n"
        
        isLoading = false
        isContainerRunning = true
        
        try await listContainers()
    }
    
    func startContainer(_ containerId: String) async throws {
        let output = try await runContainerCommand(["start", containerId])
        terminalOutput += "$ container start \(containerId)\n\(output)\n"
        try await listContainers()
    }
    
    func stopContainer(_ containerId: String) async throws {
        let output = try await runContainerCommand(["stop", containerId])
        terminalOutput += "$ container stop \(containerId)\n\(output)\n"
        isContainerRunning = false
        try await listContainers()
    }
    
    func deleteContainer(_ containerId: String) async throws {
        let output = try await runContainerCommand(["delete", containerId])
        terminalOutput += "$ container delete \(containerId)\n\(output)\n"
        try await listContainers()
    }
    
    func execInContainer(_ containerId: String, command: String) async throws -> String {
        var args = ["exec", containerId]
        args.append(contentsOf: command.split(separator: " ").map(String.init))
        
        let output = try await runContainerCommand(args)
        terminalOutput += "$ container exec \(containerId) \(command)\n\(output)\n"
        return output
    }
    
    func getLogs(_ containerId: String, follow: Bool = false, tail: Int = 100) async throws -> String {
        var args = ["logs"]
        if follow {
            args.append("-f")
        }
        args.append("--tail")
        args.append("\(tail)")
        args.append(containerId)
        
        return try await runContainerCommand(args)
    }
    
    // MARK: - Image Management
    
    func listImages() async throws {
        let output = try await runContainerCommand(["image", "list"])
        images = parseImageList(output)
    }
    
    func buildImage(dockerfile: String, tag: String, context: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let args = ["build", "-f", dockerfile, "-t", tag, context]
        terminalOutput += "$ container \(args.joined(separator: " "))\n"
        
        let output = try await runContainerCommand(args)
        terminalOutput += output + "\n"
        
        try await listImages()
    }
    
    func pullImage(_ name: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        terminalOutput += "$ container image pull \(name)\n"
        let output = try await runContainerCommand(["image", "pull", name])
        terminalOutput += output + "\n"
        
        try await listImages()
    }
    
    // MARK: - Project Integration
    
    func runProjectInContainer(projectPath: String, language: String) async throws {
        let containerName = "microcode-dev-\(UUID().uuidString.prefix(8))"
        
        // Select appropriate image based on language
        let image = getImageForLanguage(language)
        
        // Mount project directory
        let volume = Container.VolumeMount(
            hostPath: projectPath,
            containerPath: "/app",
            readOnly: false
        )
        
        // Get run command for language
        let command = getRunCommandForLanguage(language)
        
        try await runContainer(
            image: image,
            name: containerName,
            volumes: [volume],
            workDir: "/app",
            command: command,
            detached: false
        )
    }
    
    func buildProjectInContainer(projectPath: String, language: String) async throws -> String {
        let containerName = "microcode-build-\(UUID().uuidString.prefix(8))"
        
        let image = getImageForLanguage(language)
        let buildCmd = getBuildCommandForLanguage(language)
        
        let volume = Container.VolumeMount(
            hostPath: projectPath,
            containerPath: "/app",
            readOnly: false
        )
        
        try await runContainer(
            image: image,
            name: containerName,
            volumes: [volume],
            workDir: "/app",
            command: buildCmd,
            detached: false
        )
        
        return terminalOutput
    }
    
    // MARK: - Helper Methods
    
    private func runContainerCommand(_ args: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: containerPath)
            process.arguments = args
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if process.terminationStatus != 0 {
                    continuation.resume(throwing: ContainerError.commandFailed(output))
                } else {
                    continuation.resume(returning: output)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func parseContainer(_ json: [String: Any]) -> Container? {
        guard let id = json["Id"] as? String ?? json["id"] as? String,
              let name = json["Name"] as? String ?? json["name"] as? String,
              let image = json["Image"] as? String ?? json["image"] as? String else {
            return nil
        }
        
        let statusStr = json["Status"] as? String ?? json["status"] as? String ?? "unknown"
        let status: Container.ContainerStatus = {
            if statusStr.lowercased().contains("running") { return .running }
            if statusStr.lowercased().contains("exited") { return .exited }
            if statusStr.lowercased().contains("stopped") { return .stopped }
            return .unknown
        }()
        
        return Container(
            id: id,
            name: name,
            image: image,
            status: status,
            createdAt: nil,
            ports: [],
            volumes: []
        )
    }
    
    private func parseTextContainerList(_ output: String) -> [Container] {
        let lines = output.split(separator: "\n").map(String.init)
        guard lines.count > 1 else { return [] }
        
        return lines.dropFirst().compactMap { line -> Container? in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 3 else { return nil }
            
            let status: Container.ContainerStatus = parts.contains("running") ? .running : .stopped
            
            return Container(
                id: parts[0],
                name: parts.count > 1 ? parts[1] : parts[0],
                image: parts.count > 2 ? parts[2] : "",
                status: status,
                createdAt: nil,
                ports: [],
                volumes: []
            )
        }
    }
    
    private func parseImageList(_ output: String) -> [ContainerImage] {
        let lines = output.split(separator: "\n").map(String.init)
        guard lines.count > 1 else { return [] }
        
        return lines.dropFirst().compactMap { line -> ContainerImage? in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { return nil }
            
            return ContainerImage(
                name: parts[0],
                tag: parts.count > 1 ? parts[1] : "latest",
                size: parts.count > 2 ? parts[2] : nil,
                createdAt: nil
            )
        }
    }
    
    private func getImageForLanguage(_ language: String) -> String {
        switch language.lowercased() {
        case "python", "py": return "python:3.12-slim"
        case "node", "javascript", "js", "typescript", "ts": return "node:20-slim"
        case "go", "golang": return "golang:1.22-alpine"
        case "rust", "rs": return "rust:1.75-slim"
        case "ruby", "rb": return "ruby:3.3-slim"
        case "java": return "openjdk:21-slim"
        case "swift": return "swift:5.9-slim"
        case "c", "cpp", "c++": return "gcc:13"
        default: return "ubuntu:22.04"
        }
    }
    
    private func getRunCommandForLanguage(_ language: String) -> String {
        switch language.lowercased() {
        case "python", "py": return "python main.py"
        case "node", "javascript", "js": return "node index.js"
        case "typescript", "ts": return "npx ts-node index.ts"
        case "go", "golang": return "go run ."
        case "rust", "rs": return "cargo run"
        case "ruby", "rb": return "ruby main.rb"
        case "java": return "java Main.java"
        case "swift": return "swift run"
        default: return "bash"
        }
    }
    
    private func getBuildCommandForLanguage(_ language: String) -> String {
        switch language.lowercased() {
        case "go", "golang": return "go build -o app ."
        case "rust", "rs": return "cargo build --release"
        case "typescript", "ts": return "npm run build"
        case "java": return "javac *.java"
        case "swift": return "swift build"
        case "c", "cpp", "c++": return "make"
        default: return "echo 'No build step needed'"
        }
    }
    
    func clearTerminal() {
        terminalOutput = ""
    }
}

// MARK: - Errors

enum ContainerError: LocalizedError {
    case commandFailed(String)
    case containerNotFound
    case imageNotFound
    
    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return "Container command failed: \(msg)"
        case .containerNotFound: return "Container not found"
        case .imageNotFound: return "Image not found"
        }
    }
}
