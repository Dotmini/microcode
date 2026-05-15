//
//  RuntimeManager.swift
//  MicroCode
//
//  Manages runtime detection and on-demand downloads
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import SwiftUI
import Foundation

// MARK: - Runtime Definition

enum RuntimeType: String, CaseIterable, Identifiable {
    case python = "Python"
    case nodejs = "Node.js"
    case go = "Go"
    case rust = "Rust"
    case swift = "Swift"
    case dotnet = ".NET"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .python: return "🐍"
        case .nodejs: return "⬢"
        case .go: return "🐹"
        case .rust: return "🦀"
        case .swift: return "🐦"
        case .dotnet: return "🔷"
        }
    }
    
    var color: Color {
        switch self {
        case .python: return .yellow
        case .nodejs: return .green
        case .go: return .cyan
        case .rust: return .orange
        case .swift: return .orange
        case .dotnet: return .purple
        }
    }
    
    var binaryName: String {
        switch self {
        case .python: return "python3"
        case .nodejs: return "node"
        case .go: return "go"
        case .rust: return "rustc"
        case .swift: return "swift"
        case .dotnet: return "dotnet"
        }
    }
    
    // Download URLs (portable versions)
    func getDownloadInfo() -> (url: String, size: String, fileName: String)? {
        let arch = ProcessInfo.processInfo.machineArchitecture
        switch self {
        case .python:
            // Use standalone Python from python.org
            return ("https://www.python.org/ftp/python/3.12.0/python-3.12.0-macos11.pkg", "~45 MB", "python-3.12.0.pkg")
        case .nodejs:
            if arch == "arm64" {
                return ("https://nodejs.org/dist/v20.10.0/node-v20.10.0-darwin-arm64.tar.gz", "~25 MB", "node-v20.10.0-darwin-arm64.tar.gz")
            } else {
                return ("https://nodejs.org/dist/v20.10.0/node-v20.10.0-darwin-x64.tar.gz", "~28 MB", "node-v20.10.0-darwin-x64.tar.gz")
            }
        case .go:
            if arch == "arm64" {
                return ("https://go.dev/dl/go1.21.5.darwin-arm64.tar.gz", "~65 MB", "go1.21.5.darwin-arm64.tar.gz")
            } else {
                return ("https://go.dev/dl/go1.21.5.darwin-amd64.tar.gz", "~68 MB", "go1.21.5.darwin-amd64.tar.gz")
            }
        case .rust:
            return ("https://static.rust-lang.org/rustup/dist/aarch64-apple-darwin/rustup-init", "~8 MB", "rustup-init")
        case .swift:
            return nil // Built into macOS
        case .dotnet:
            return ("https://dot.net/v1/dotnet-install.sh", "~1 MB", "dotnet-install.sh")
        }
    }
}

// MARK: - Runtime Status

class RuntimeStatus: ObservableObject, Identifiable {
    let id = UUID()
    let type: RuntimeType
    @Published var isInstalled: Bool = false
    @Published var version: String?
    @Published var path: String?
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var statusMessage: String = ""
    
    init(type: RuntimeType) {
        self.type = type
    }
}

// MARK: - Runtime Manager

class RuntimeManager: ObservableObject {
    static let shared = RuntimeManager()
    
    @Published var runtimes: [RuntimeStatus] = []
    @Published var isDetecting: Bool = false
    @Published var lastDetectionDate: Date?
    @Published var errorMessage: String?
    
    let runtimesDir: URL
    
    init() {
        // Store runtimes in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        runtimesDir = appSupport.appendingPathComponent("MicroCode/Runtimes")
        
        try? FileManager.default.createDirectory(at: runtimesDir, withIntermediateDirectories: true)
        
        // Initialize with all runtime types
        runtimes = RuntimeType.allCases.map { RuntimeStatus(type: $0) }
        
        // Auto-detect on init
        detectAll()
    }
    
    // MARK: - Detection
    
    func detectAll() {
        isDetecting = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            for runtime in self.runtimes {
                let (installed, version, path) = self.detectRuntime(runtime.type)
                
                DispatchQueue.main.async {
                    runtime.isInstalled = installed
                    runtime.version = version
                    runtime.path = path
                }
            }
            
            DispatchQueue.main.async {
                self.isDetecting = false
                self.lastDetectionDate = Date()
            }
        }
    }
    
    private func detectRuntime(_ type: RuntimeType) -> (isInstalled: Bool, version: String?, path: String?) {
        // First check system PATH
        let whichResult = runCommand("/usr/bin/which", arguments: [type.binaryName])
        if let path = whichResult.output?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            let version = getVersion(for: type)
            return (true, version, path)
        }
        
        // Check our bundled runtime
        let bundledBin = runtimesDir.appendingPathComponent(type.rawValue.lowercased())
            .appendingPathComponent("bin")
            .appendingPathComponent(type.binaryName)
        
        if FileManager.default.fileExists(atPath: bundledBin.path) {
            return (true, "bundled", bundledBin.path)
        }
        
        // For Go, check GOROOT
        let goBin = runtimesDir.appendingPathComponent("go/go/bin/go")
        if type == .go && FileManager.default.fileExists(atPath: goBin.path) {
            return (true, "bundled", goBin.path)
        }
        
        return (false, nil, nil)
    }
    
    private func getVersion(for type: RuntimeType) -> String? {
        let result: CommandResult
        switch type {
        case .python:
            result = runCommand("/usr/bin/env", arguments: ["python3", "--version"])
        case .nodejs:
            result = runCommand("/usr/bin/env", arguments: ["node", "--version"])
        case .go:
            result = runCommand("/usr/bin/env", arguments: ["go", "version"])
        case .rust:
            result = runCommand("/usr/bin/env", arguments: ["rustc", "--version"])
        case .swift:
            result = runCommand("/usr/bin/env", arguments: ["swift", "--version"])
        case .dotnet:
            result = runCommand("/usr/bin/env", arguments: ["dotnet", "--version"])
        }
        
        if let output = result.output?.trimmingCharacters(in: .whitespacesAndNewlines) {
            // Extract version number
            let parts = output.components(separatedBy: " ")
            if parts.count >= 2 {
                return parts.last
            }
            return output
        }
        return nil
    }
    
    // MARK: - Download & Install
    
    func install(_ type: RuntimeType) {
        guard let downloadInfo = type.getDownloadInfo() else {
            DispatchQueue.main.async {
                self.errorMessage = "\(type.rawValue) is built into macOS"
            }
            return
        }
        
        guard let runtime = runtimes.first(where: { $0.type == type }) else { return }
        
        DispatchQueue.main.async {
            runtime.isDownloading = true
            runtime.downloadProgress = 0.0
            runtime.statusMessage = "Starting download..."
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.performInstall(type: type, runtime: runtime, downloadInfo: downloadInfo)
        }
    }
    
    private func performInstall(type: RuntimeType, runtime: RuntimeStatus, downloadInfo: (url: String, size: String, fileName: String)) {
        let downloadDir = runtimesDir.appendingPathComponent("downloads")
        try? FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)
        
        let downloadPath = downloadDir.appendingPathComponent(downloadInfo.fileName)
        
        // Remove existing download
        try? FileManager.default.removeItem(at: downloadPath)
        
        DispatchQueue.main.async {
            runtime.statusMessage = "Downloading..."
        }
        
        // Use curl for reliable download with progress
        let curlArgs = ["-L", "-o", downloadPath.path, "--progress-bar", downloadInfo.url]
        let downloadResult = runCommand("/usr/bin/curl", arguments: curlArgs)
        
        DispatchQueue.main.async {
            runtime.downloadProgress = 0.5
        }
        
        if downloadResult.exitCode != 0 {
            DispatchQueue.main.async {
                runtime.isDownloading = false
                runtime.statusMessage = "Download failed"
                self.errorMessage = "Download failed: \(downloadResult.error ?? "Unknown error")"
            }
            return
        }
        
        // Check file exists
        guard FileManager.default.fileExists(atPath: downloadPath.path) else {
            DispatchQueue.main.async {
                runtime.isDownloading = false
                runtime.statusMessage = "Download failed"
                self.errorMessage = "Downloaded file not found"
            }
            return
        }
        
        DispatchQueue.main.async {
            runtime.statusMessage = "Installing..."
            runtime.downloadProgress = 0.7
        }
        
        // Install based on file type
        let installResult: Bool
        let fileName = downloadInfo.fileName
        
        if fileName.hasSuffix(".tar.gz") {
            installResult = installTarGz(type: type, archivePath: downloadPath)
        } else if fileName.hasSuffix(".pkg") {
            installResult = installPkg(type: type, pkgPath: downloadPath)
        } else if fileName.hasSuffix(".sh") {
            installResult = installScript(type: type, scriptPath: downloadPath)
        } else if fileName == "rustup-init" {
            installResult = installRustup(rustupPath: downloadPath)
        } else {
            installResult = false
        }
        
        DispatchQueue.main.async {
            runtime.isDownloading = false
            runtime.downloadProgress = 1.0
            
            if installResult {
                runtime.statusMessage = "Installed!"
                self.detectAll()
            } else {
                runtime.statusMessage = "Installation failed"
            }
        }
        
        // Cleanup download
        try? FileManager.default.removeItem(at: downloadPath)
    }
    
    private func installTarGz(type: RuntimeType, archivePath: URL) -> Bool {
        let installDir = runtimesDir.appendingPathComponent(type.rawValue.lowercased())
        try? FileManager.default.removeItem(at: installDir)
        try? FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        
        // Extract
        let result = runCommand("/usr/bin/tar", arguments: [
            "-xzf", archivePath.path,
            "-C", installDir.path,
            "--strip-components=1"
        ])
        
        if result.exitCode != 0 {
            // Try without strip-components (for Go)
            let result2 = runCommand("/usr/bin/tar", arguments: [
                "-xzf", archivePath.path,
                "-C", installDir.path
            ])
            return result2.exitCode == 0
        }
        
        return true
    }
    
    private func installPkg(type: RuntimeType, pkgPath: URL) -> Bool {
        // For PKG, open in Finder for user to install manually
        NSWorkspace.shared.activateFileViewerSelecting([pkgPath])
        
        // Show dialog
        DispatchQueue.main.async {
            self.errorMessage = "Please run the .pkg installer that opened. After installation, click Refresh to detect \(type.rawValue)."
        }
        
        return true
    }
    
    private func installScript(type: RuntimeType, scriptPath: URL) -> Bool {
        // Make executable
        _ = runCommand("/bin/chmod", arguments: ["+x", scriptPath.path])
        
        // For .NET, run the install script
        if type == .dotnet {
            let installDir = runtimesDir.appendingPathComponent("dotnet")
            try? FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
            
            let result = runCommand("/bin/bash", arguments: [
                scriptPath.path,
                "--install-dir", installDir.path
            ])
            
            return result.exitCode == 0
        }
        
        return false
    }
    
    private func installRustup(rustupPath: URL) -> Bool {
        // Make executable
        _ = runCommand("/bin/chmod", arguments: ["+x", rustupPath.path])
        
        // Run rustup-init with defaults
        let result = runCommand(rustupPath.path, arguments: ["-y", "--no-modify-path"])
        
        return result.exitCode == 0
    }
    
    // MARK: - Helper
    
    struct CommandResult {
        var output: String?
        var error: String?
        var exitCode: Int32
    }
    
    private func runCommand(_ executable: String, arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            return CommandResult(
                output: String(data: outputData, encoding: .utf8),
                error: String(data: errorData, encoding: .utf8),
                exitCode: process.terminationStatus
            )
        } catch {
            return CommandResult(output: nil, error: error.localizedDescription, exitCode: -1)
        }
    }
}

// MARK: - ProcessInfo Extension

extension ProcessInfo {
    var machineArchitecture: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return machine ?? "unknown"
    }
}
