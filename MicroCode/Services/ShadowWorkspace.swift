// Copyright © 2025 Dotmini Software. All rights reserved.
//
//  ShadowWorkspace.swift
//  MicroCode
//
//  Feature 5: Shadow Workspace — validates AI-generated code changes in an
//  isolated copy before applying to the real workspace. Catches build errors,
//  type mismatches, and regressions BEFORE they hit the user's code.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Shadow Error

public enum ShadowError: LocalizedError, Equatable {
    case creationFailed(String)
    case buildFailed(String)
    case validationTimeout
    case promotionFailed(String)

    public static let creationFailed = ShadowError.creationFailed("Shadow workspace creation failed")
    public static let buildFailed = ShadowError.buildFailed("Build validation failed")
    public static let promotionFailed = ShadowError.promotionFailed("Failed to promote changes to real workspace")

    public var errorDescription: String? {
        switch self {
        case .creationFailed(let reason):
            return "Shadow Workspace Creation Failed: \(reason)"
        case .buildFailed(let reason):
            return "Shadow Workspace Build Failed: \(reason)"
        case .validationTimeout:
            return "Shadow Workspace Validation Timed Out: Build process exceeded 60-second limit."
        case .promotionFailed(let reason):
            return "Shadow Workspace Promotion Failed: \(reason)"
        }
    }
}

// MARK: - Validation Result

public struct ValidationResult: Identifiable, Codable, Equatable {
    public var id: String
    public let isValid: Bool
    public let errors: [String]
    public let warnings: [String]
    public let buildOutput: String
    public let duration: TimeInterval

    public init(
        id: String = UUID().uuidString,
        isValid: Bool,
        errors: [String] = [],
        warnings: [String] = [],
        buildOutput: String = "",
        duration: TimeInterval = 0.0
    ) {
        self.id = id
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
        self.buildOutput = buildOutput
        self.duration = duration
    }

    public var errorCount: Int {
        errors.count
    }

    public var warningCount: Int {
        warnings.count
    }

    public var summary: String {
        if isValid {
            let warnText = warningCount > 0 ? " (\(warningCount) warning\(warningCount == 1 ? "" : "s"))" : ""
            return "Validation passed in \(String(format: "%.2f", duration))s\(warnText)"
        } else {
            return "Validation failed with \(errorCount) error\(errorCount == 1 ? "" : "s") and \(warningCount) warning\(warningCount == 1 ? "" : "s") (\(String(format: "%.2f", duration))s)"
        }
    }
}

// MARK: - Build System Detection

public enum BuildSystem: String, CaseIterable, Identifiable {
    case cargo = "Cargo"
    case swift = "SwiftPM"
    case npm = "npm"
    case make = "Make"

    public var id: String { rawValue }

    public var defaultCommand: String {
        switch self {
        case .cargo: return "cargo build"
        case .swift: return "swift build"
        case .npm: return "npm run build"
        case .make: return "make"
        }
    }
}

// MARK: - Shadow Workspace Service

@MainActor
public class ShadowWorkspace: ObservableObject {
    public static let shared = ShadowWorkspace()

    // Published State
    @Published public var isValidating: Bool = false
    @Published public var lastValidation: ValidationResult? = nil
    @Published public var shadowPath: String? = nil

    // Internal State
    private var activeProjectPath: String? = nil
    private var modifiedRelativePaths: Set<String> = []
    private var currentProcess: Process? = nil

    private init() {}

    // MARK: - Public API

    /// Creates an isolated shadow workspace by copying the project directory structure
    /// and symlinking unchanged files, allowing only modified files to be isolated.
    public func createShadow(projectPath: String) async throws {
        // Clean up any existing shadow session first
        cleanup()

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: projectPath, isDirectory: &isDir), isDir.boolValue else {
            throw ShadowError.creationFailed("Project directory does not exist: \(projectPath)")
        }

        let originalURL = URL(fileURLWithPath: (projectPath as NSString).standardizingPath).resolvingSymlinksInPath()
        let tempURL = fm.temporaryDirectory.appendingPathComponent("microcode-shadow-\(UUID().uuidString)")

        do {
            try fm.createDirectory(at: tempURL, withIntermediateDirectories: true)
        } catch {
            throw ShadowError.creationFailed("Failed to create temporary shadow directory: \(error.localizedDescription)")
        }

        // Perform shallow mirror in background to avoid blocking MainActor
        do {
            try await Task.detached(priority: .userInitiated) {
                try ShadowWorkspace.mirrorDirectoryTree(from: originalURL, to: tempURL)
            }.value
        } catch {
            try? fm.removeItem(at: tempURL)
            throw ShadowError.creationFailed("Failed to shallow copy project tree: \(error.localizedDescription)")
        }

        self.shadowPath = tempURL.path
        self.activeProjectPath = originalURL.path
        self.modifiedRelativePaths.removeAll()
        self.lastValidation = nil
    }

    /// Writes an AI-generated code change into the shadow workspace, replacing any existing symlink with the real modified file.
    public func applyChange(filePath: String, content: String) async throws {
        guard let shadow = self.shadowPath else {
            throw ShadowError.creationFailed("No active shadow workspace. Call createShadow first.")
        }

        let relativePath = resolveRelativePath(filePath: filePath, shadowRoot: shadow)
        let shadowFileURL = URL(fileURLWithPath: shadow).appendingPathComponent(relativePath)
        let parentDir = shadowFileURL.deletingLastPathComponent()

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        } catch {
            throw ShadowError.creationFailed("Could not create parent directories for \(relativePath): \(error.localizedDescription)")
        }

        // If a symlink or file exists at destination, remove it first so we don't write through a symlink to the real workspace
        if fm.fileExists(atPath: shadowFileURL.path) || (try? shadowFileURL.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            try? fm.removeItem(at: shadowFileURL)
        }

        do {
            try content.write(to: shadowFileURL, atomically: true, encoding: .utf8)
            self.modifiedRelativePaths.insert(relativePath)
        } catch {
            throw ShadowError.creationFailed("Failed to write change to shadow file at \(relativePath): \(error.localizedDescription)")
        }
    }

    /// Validates the shadow workspace by running the detected build command within the isolated directory.
    public func validate() async throws -> ValidationResult {
        try await validate(customCommand: nil)
    }

    /// Validates with an optional custom build command, falling back to auto-detection.
    public func validate(customCommand: String?) async throws -> ValidationResult {
        guard let shadow = self.shadowPath else {
            throw ShadowError.creationFailed("No shadow workspace exists to validate. Call createShadow first.")
        }

        let commandToRun: String
        if let custom = customCommand, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commandToRun = custom
        } else if let detected = ShadowWorkspace.detectBuildSystem(at: shadow) {
            commandToRun = detected.command
        } else {
            throw ShadowError.buildFailed("No recognized build system (Cargo.toml, Package.swift, package.json, Makefile) found.")
        }

        self.isValidating = true
        defer { self.isValidating = false }

        let startTime = Date()
        let result = try await executeBuild(command: commandToRun, workingDirectory: shadow, timeoutSeconds: 60.0, startTime: startTime)
        self.lastValidation = result
        return result
    }

    /// Copies validated changes from the shadow workspace back to the real project directory.
    public func promoteToReal(projectPath: String) async throws {
        guard let shadow = self.shadowPath else {
            throw ShadowError.promotionFailed("No active shadow workspace to promote.")
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: projectPath, isDirectory: &isDir), isDir.boolValue else {
            throw ShadowError.promotionFailed("Destination project directory does not exist: \(projectPath)")
        }

        let targetURL = URL(fileURLWithPath: (projectPath as NSString).standardizingPath).resolvingSymlinksInPath()
        let shadowURL = URL(fileURLWithPath: shadow).resolvingSymlinksInPath()

        var filesToPromote = modifiedRelativePaths

        // Scan shadow directory for any non-symlink regular files (e.g. newly created files)
        if let enumerator = fm.enumerator(
            at: shadowURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                let path = fileURL.path
                let relative = String(path.dropFirst(shadowURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))

                // Skip build artifact directories
                if relative.hasPrefix(".build") ||
                   relative.hasPrefix("target") ||
                   relative.hasPrefix("node_modules") ||
                   relative.hasPrefix("DerivedData") ||
                   relative.hasPrefix("dist") ||
                   relative.hasPrefix(".git") {
                    continue
                }

                if let values = try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]),
                   values.isRegularFile == true, values.isSymbolicLink != true {
                    filesToPromote.insert(relative)
                }
            }
        }

        guard !filesToPromote.isEmpty else {
            return
        }

        for relativePath in filesToPromote {
            let shadowFile = shadowURL.appendingPathComponent(relativePath)
            let targetFile = targetURL.appendingPathComponent(relativePath)

            guard fm.fileExists(atPath: shadowFile.path) else { continue }

            do {
                let parentDir = targetFile.deletingLastPathComponent()
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

                let data = try Data(contentsOf: shadowFile)
                try data.write(to: targetFile, options: .atomic)
            } catch {
                throw ShadowError.promotionFailed("Failed to copy '\(relativePath)': \(error.localizedDescription)")
            }
        }
    }

    /// Convenience promotion using the recorded original project path.
    public func promoteToReal() async throws {
        guard let project = activeProjectPath else {
            throw ShadowError.promotionFailed("No active project path recorded for promotion.")
        }
        try await promoteToReal(projectPath: project)
    }

    /// Removes the temporary shadow workspace directory and resets state.
    public func cleanup() {
        if let proc = currentProcess, proc.isRunning {
            proc.terminate()
        }
        currentProcess = nil

        if let path = shadowPath {
            try? FileManager.default.removeItem(atPath: path)
        }

        shadowPath = nil
        activeProjectPath = nil
        modifiedRelativePaths.removeAll()
        isValidating = false
    }

    /// Validates an array of `PendingChangeModel`s in an isolated shadow workspace.
    func validatePendingChanges(projectPath: String, changes: [PendingChangeModel]) async throws -> ValidationResult {
        try await createShadow(projectPath: projectPath)
        for change in changes {
            try await applyChange(filePath: change.filePath, content: change.newContent)
        }
        return try await validate()
    }

    // MARK: - Build System Auto-Detection

    /// Auto-detects the build system and command for a workspace directory:
    /// - Cargo.toml → cargo build
    /// - Package.swift → swift build
    /// - package.json → npm run build
    /// - Makefile → make
    public static func detectBuildSystem(at path: String) -> (system: BuildSystem, command: String)? {
        let fm = FileManager.default
        let pathURL = URL(fileURLWithPath: path)

        if fm.fileExists(atPath: pathURL.appendingPathComponent("Cargo.toml").path) {
            return (.cargo, "cargo build")
        }
        if fm.fileExists(atPath: pathURL.appendingPathComponent("Package.swift").path) {
            return (.swift, "swift build")
        }
        if fm.fileExists(atPath: pathURL.appendingPathComponent("package.json").path) {
            return (.npm, "npm run build")
        }
        if fm.fileExists(atPath: pathURL.appendingPathComponent("Makefile").path) ||
           fm.fileExists(atPath: pathURL.appendingPathComponent("makefile").path) {
            return (.make, "make")
        }
        return nil
    }

    // MARK: - Output Parsing

    /// Parses compiler and toolchain output for errors and warnings.
    nonisolated public static func parseDiagnostics(from output: String) -> (errors: [String], warnings: [String]) {
        var errors: [String] = []
        var warnings: [String] = []

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let lower = trimmed.lowercased()

            let isError = (lower.contains("error:") ||
                           lower.contains("error[") ||
                           lower.contains(" - error") ||
                           lower.hasPrefix("error ") ||
                           lower.hasPrefix("npm err!") ||
                           lower.contains("fatal error:") ||
                           lower.contains("fatal: ") ||
                           lower.hasPrefix("make: ***")) &&
                          !lower.contains("0 errors") &&
                          !lower.contains("no errors")

            let isWarning = (lower.contains("warning:") ||
                             lower.contains("warning[") ||
                             lower.contains(" - warning") ||
                             lower.hasPrefix("warning ")) &&
                            !lower.contains("0 warnings") &&
                            !lower.contains("no warnings")

            if isError {
                errors.append(trimmed)
            } else if isWarning {
                warnings.append(trimmed)
            }
        }

        return (errors, warnings)
    }

    // MARK: - Private Helpers

    private func resolveRelativePath(filePath: String, shadowRoot: String) -> String {
        if let project = self.activeProjectPath, filePath.hasPrefix(project) {
            var rel = String(filePath.dropFirst(project.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            return rel
        } else if filePath.hasPrefix(shadowRoot) {
            var rel = String(filePath.dropFirst(shadowRoot.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            return rel
        } else if filePath.hasPrefix("/") {
            let standardized = (filePath as NSString).standardizingPath
            if let project = self.activeProjectPath, standardized.hasPrefix(project) {
                var rel = String(standardized.dropFirst(project.count))
                if rel.hasPrefix("/") { rel.removeFirst() }
                return rel
            }
            return (filePath as NSString).lastPathComponent
        } else {
            return filePath
        }
    }

    nonisolated private static func mirrorDirectoryTree(from sourceDir: URL, to destDir: URL) throws {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(
            at: sourceDir,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )

        for item in items {
            let name = item.lastPathComponent

            // Skip VCS metadata and OS files
            if name == ".git" || name == ".svn" || name == ".hg" || name == ".DS_Store" {
                continue
            }

            let destItem = destDir.appendingPathComponent(name)
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDirectory = values?.isDirectory ?? false

            if isDirectory {
                // Dependency directories: symlink directly to avoid deep recursive copies
                if name == "node_modules" || name == "Pods" || name == "vendor" {
                    try? fm.createSymbolicLink(atPath: destItem.path, withDestinationPath: item.path)
                    continue
                }

                // SwiftPM build cache: symlink checkouts and repositories so swift build reuses packages
                if name == ".build" {
                    try? fm.createDirectory(at: destItem, withIntermediateDirectories: true)
                    let checkouts = item.appendingPathComponent("checkouts")
                    if fm.fileExists(atPath: checkouts.path) {
                        try? fm.createSymbolicLink(atPath: destItem.appendingPathComponent("checkouts").path, withDestinationPath: checkouts.path)
                    }
                    let repositories = item.appendingPathComponent("repositories")
                    if fm.fileExists(atPath: repositories.path) {
                        try? fm.createSymbolicLink(atPath: destItem.appendingPathComponent("repositories").path, withDestinationPath: repositories.path)
                    }
                    let artifacts = item.appendingPathComponent("artifacts")
                    if fm.fileExists(atPath: artifacts.path) {
                        try? fm.createSymbolicLink(atPath: destItem.appendingPathComponent("artifacts").path, withDestinationPath: artifacts.path)
                    }
                    continue
                }

                // Skip build output directories to keep shadow builds fresh and isolated
                if name == "target" || name == "DerivedData" || name == "dist" || name == "out" {
                    continue
                }

                // Standard directory: create corresponding folder in shadow and recurse
                try fm.createDirectory(at: destItem, withIntermediateDirectories: true)
                try mirrorDirectoryTree(from: item, to: destItem)
            } else {
                // Regular file: create symbolic link pointing to the original file
                try? fm.createSymbolicLink(atPath: destItem.path, withDestinationPath: item.path)
            }
        }
    }

    private func executeBuild(
        command: String,
        workingDirectory: String,
        timeoutSeconds: TimeInterval,
        startTime: Date
    ) async throws -> ValidationResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            self.currentProcess = process

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

            // Setup development toolchain environment
            var env = ProcessInfo.processInfo.environment
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let extraPaths = [
                "/opt/homebrew/bin",
                "/opt/homebrew/sbin",
                "/usr/local/bin",
                "/usr/bin",
                "/bin",
                "/usr/sbin",
                "/sbin",
                "\(homeDir)/.cargo/bin",
                "\(homeDir)/.local/bin",
                "\(homeDir)/.nvm/current/bin"
            ].joined(separator: ":")
            let currentPath = env["PATH"] ?? ""
            env["PATH"] = "\(extraPaths):\(currentPath)"
            env["TERM"] = "dumb"
            env["CI"] = "true"
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            var outputData = Data()
            let dataLock = NSLock()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let available = handle.availableData
                if !available.isEmpty {
                    dataLock.lock()
                    outputData.append(available)
                    dataLock.unlock()
                }
            }

            var didTimeout = false
            var isCompleted = false
            let completionLock = NSLock()

            let timeoutItem = DispatchWorkItem { [weak process] in
                completionLock.lock()
                guard !isCompleted else {
                    completionLock.unlock()
                    return
                }
                didTimeout = true
                completionLock.unlock()

                process?.terminate()
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutItem)

            process.terminationHandler = { [weak self] proc in
                timeoutItem.cancel()

                pipe.fileHandleForReading.readabilityHandler = nil
                let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                dataLock.lock()
                outputData.append(remaining)
                let fullOutput = String(data: outputData, encoding: .utf8) ?? ""
                dataLock.unlock()

                completionLock.lock()
                let timedOut = didTimeout
                isCompleted = true
                completionLock.unlock()

                Task { @MainActor in
                    self?.currentProcess = nil
                }

                if timedOut {
                    continuation.resume(throwing: ShadowError.validationTimeout)
                    return
                }

                let exitCode = Int(proc.terminationStatus)
                let duration = Date().timeIntervalSince(startTime)

                let (parsedErrors, parsedWarnings) = ShadowWorkspace.parseDiagnostics(from: fullOutput)
                var finalErrors = parsedErrors

                if exitCode != 0 && finalErrors.isEmpty {
                    let trimmed = fullOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let lastLine = trimmed.components(separatedBy: .newlines).last, !lastLine.isEmpty {
                        finalErrors.append("Build exited with code \(exitCode): \(lastLine)")
                    } else {
                        finalErrors.append("Build exited with code \(exitCode)")
                    }
                }

                let isValid = (exitCode == 0 && finalErrors.isEmpty)

                let result = ValidationResult(
                    isValid: isValid,
                    errors: finalErrors,
                    warnings: parsedWarnings,
                    buildOutput: fullOutput,
                    duration: duration
                )
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                timeoutItem.cancel()
                pipe.fileHandleForReading.readabilityHandler = nil
                completionLock.lock()
                isCompleted = true
                completionLock.unlock()

                Task { @MainActor in
                    self.currentProcess = nil
                }
                continuation.resume(throwing: ShadowError.buildFailed("Failed to start build command: \(error.localizedDescription)"))
            }
        }
    }
}
