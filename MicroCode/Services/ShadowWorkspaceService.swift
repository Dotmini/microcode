//
//  ShadowWorkspaceService.swift
//  MicroCode
//
//  Shadow Git Worktree & Sandboxed Code Mutation Verification Pipeline.
//  Isolates agent code edits into ephemeral worktrees, runs compilations
//  and test suites in isolation, and guarantees zero-corrupt real workspaces.
//  Tirawat Nantamas Founder and CEO of Dotmini Software.
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation

/// Manages shadow workspaces for verified code mutations.
/// All agent file changes go through a shadow git worktree first.
/// Changes are only applied to the real workspace after:
/// 1. Compilation passes
/// 2. Tests pass (optional)
/// 3. User approves the diff
@MainActor
public class ShadowWorkspaceService: ObservableObject {
    public static let shared = ShadowWorkspaceService()
    
    @Published public var isActive: Bool = false
    @Published public var currentShadowPath: String?
    @Published public var verificationStatus: VerificationStatus = .idle
    @Published public var pendingChanges: [ShadowFileChange] = []
    
    private let backendURL = "http://localhost:3000"
    
    private init() {}
    
    // MARK: - Shadow Workspace Lifecycle
    
    /// Create a new shadow workspace (git worktree) for the current project
    public func createShadow(workspaceRoot: String, branchName: String? = nil) async throws -> String {
        isActive = true
        verificationStatus = .creating
        
        let url = URL(string: "\(backendURL)/api/shadow/create")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "workspace_root": workspaceRoot,
            "branch_name": branchName ?? "shadow-workspace"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            verificationStatus = .error("Failed to create shadow workspace")
            throw URLError(.badServerResponse)
        }
        
        struct CreateResponse: Decodable {
            let shadow_path: String
        }
        
        let result = try JSONDecoder().decode(CreateResponse.self, from: data)
        currentShadowPath = result.shadow_path
        verificationStatus = .idle
        return result.shadow_path
    }
    
    /// Apply a file change to the shadow workspace (not the real workspace)
    public func applyToShadow(shadowPath: String, filePath: String, content: String) async throws {
        let url = URL(string: "\(backendURL)/api/shadow/apply")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "shadow_path": shadowPath,
            "file_path": filePath,
            "content": content
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    /// Run verification in the shadow workspace
    public func verify(shadowPath: String, buildCommand: String?, testCommand: String?) async throws -> VerificationResult {
        verificationStatus = .building
        let start = Date()
        
        // 1. Run build command in shadow workspace
        let buildPassed = try await runCommand(shadowPath: shadowPath, command: buildCommand ?? "cargo check")
        
        var testsPassed = true
        var testOutput = ""
        
        if buildPassed.passed, let testCommand = testCommand {
            verificationStatus = .testing
            let testResult = try await runCommand(shadowPath: shadowPath, command: testCommand)
            testsPassed = testResult.passed
            testOutput = testResult.stdout + "\n" + testResult.stderr
        }
        
        let duration = Date().timeIntervalSince(start)
        
        let result = VerificationResult(
            buildPassed: buildPassed.passed,
            testsPassed: testsPassed,
            buildOutput: buildPassed.stdout + "\n" + buildPassed.stderr,
            testOutput: testOutput,
            diagnostics: buildPassed.diagnostics.map { "\($0.severity): \($0.message) at \($0.file):\($0.line ?? 0)" },
            duration: duration
        )
        
        verificationStatus = .verified(passed: result.allPassed)
        return result
    }
    
    private func runCommand(shadowPath: String, command: String) async throws -> BackendVerificationResult {
        let url = URL(string: "\(backendURL)/api/shadow/verify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "shadow_path": shadowPath,
            "command": command
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return try JSONDecoder().decode(BackendVerificationResult.self, from: data)
    }
    
    /// Collect all changes made in the shadow workspace as diffs
    public func collectChanges(shadowPath: String, workspaceRoot: String) async throws -> [ShadowFileChange] {
        verificationStatus = .collecting
        let url = URL(string: "\(backendURL)/api/shadow/diff")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "shadow_path": shadowPath,
            "workspace_root": workspaceRoot
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let changes = try JSONDecoder().decode([ShadowFileChange].self, from: data)
        self.pendingChanges = changes
        verificationStatus = .idle
        return changes
    }
    
    /// Apply verified changes from shadow to real workspace
    public func applyToWorkspace(shadowPath: String, workspaceRoot: String, changes: [ShadowFileChange]) async throws {
        let url = URL(string: "\(backendURL)/api/shadow/apply_to_workspace")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "shadow_path": shadowPath,
            "workspace_root": workspaceRoot,
            "changes": changes.map { $0.id }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    /// Clean up shadow workspace
    public func destroyShadow(shadowPath: String) async throws {
        let url = URL(string: "\(backendURL)/api/shadow/destroy")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "shadow_path": shadowPath
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        isActive = false
        currentShadowPath = nil
        pendingChanges = []
        verificationStatus = .idle
    }

    // MARK: - Lightweight Per-Turn Git Tree Checkpoints (Zero Side Effects on .git/index or HEAD)

    /// Captures a fast, non-destructive Git tree SHA of the current workspace tracked files using an isolated
    /// temporary `GIT_INDEX_FILE`. Never modifies the user's real `.git/index`, `HEAD`, branches, or reflog.
    nonisolated public func captureTurnTreeSnapshot(workspaceRoot: String) async -> String? {
        let trimmedRoot = workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRoot.isEmpty else { return nil }
        return await Task.detached(priority: .utility) {
            let rootURL = URL(fileURLWithPath: trimmedRoot, isDirectory: true)
            guard let gitDirRaw = Self.runGitSync(["rev-parse", "--git-dir"], cwd: rootURL) else {
                return nil
            }
            let gitDirPath = gitDirRaw.hasPrefix("/")
                ? gitDirRaw
                : rootURL.appendingPathComponent(gitDirRaw).standardizedFileURL.path
            let realIndexURL = URL(fileURLWithPath: gitDirPath).appendingPathComponent("index")
            let tempIndexURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("mc-turn-idx-\(UUID().uuidString)")
            defer {
                try? FileManager.default.removeItem(at: tempIndexURL)
            }
            if FileManager.default.fileExists(atPath: realIndexURL.path) {
                try? FileManager.default.copyItem(at: realIndexURL, to: tempIndexURL)
            }
            let env = ["GIT_INDEX_FILE": tempIndexURL.path]
            _ = Self.runGitSync(["add", "-u"], cwd: rootURL, extraEnv: env)
            guard let treeSHA = Self.runGitSync(["write-tree"], cwd: rootURL, extraEnv: env),
                  treeSHA.count == 40,
                  treeSHA.allSatisfy({ $0.isHexDigit }) else {
                return nil
            }
            return treeSHA
        }.value
    }

    /// Restores tracked working-tree files from a previously captured `captureTurnTreeSnapshot` tree SHA
    /// using an isolated temporary `GIT_INDEX_FILE`, leaving the user's real `.git/index` and `HEAD` untouched.
    nonisolated public func restoreTurnTreeSnapshot(workspaceRoot: String, treeSHA: String) async -> Bool {
        let trimmedRoot = workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSHA = treeSHA.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedRoot.isEmpty,
              cleanSHA.count == 40,
              cleanSHA.allSatisfy({ $0.isHexDigit }) else {
            return false
        }
        return await Task.detached(priority: .userInitiated) {
            let rootURL = URL(fileURLWithPath: trimmedRoot, isDirectory: true)
            guard let gitDirRaw = Self.runGitSync(["rev-parse", "--git-dir"], cwd: rootURL) else {
                return false
            }
            let gitDirPath = gitDirRaw.hasPrefix("/")
                ? gitDirRaw
                : rootURL.appendingPathComponent(gitDirRaw).standardizedFileURL.path
            let realIndexURL = URL(fileURLWithPath: gitDirPath).appendingPathComponent("index")
            let tempIndexURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("mc-restore-idx-\(UUID().uuidString)")
            defer {
                try? FileManager.default.removeItem(at: tempIndexURL)
            }
            if FileManager.default.fileExists(atPath: realIndexURL.path) {
                try? FileManager.default.copyItem(at: realIndexURL, to: tempIndexURL)
            }
            let env = ["GIT_INDEX_FILE": tempIndexURL.path]
            return Self.runGitSync(["checkout", cleanSHA, "--", "."], cwd: rootURL, extraEnv: env) != nil
        }.value
    }

    nonisolated private static func runGitSync(
        _ args: [String],
        cwd: URL,
        extraEnv: [String: String] = [:]
    ) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = args
        proc.currentDirectoryURL = cwd
        if !extraEnv.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (k, v) in extraEnv {
                env[k] = v
            }
            proc.environment = env
        }
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

// MARK: - Models

public enum VerificationStatus: Equatable {
    case idle
    case creating
    case building
    case testing
    case collecting
    case verified(passed: Bool)
    case error(String)
}

public struct VerificationResult {
    public let buildPassed: Bool
    public let testsPassed: Bool
    public let buildOutput: String
    public let testOutput: String
    public let diagnostics: [String]
    public let duration: TimeInterval
    
    public var allPassed: Bool { buildPassed && testsPassed }
}

public struct ShadowFileChange: Identifiable, Decodable {
    public let id: String
    public let filePath: String
    public let changeType: ChangeType // .added, .modified, .deleted
    public let unifiedDiff: String
    public let oldContent: String?
    public let newContent: String
    
    public enum ChangeType: String, Decodable {
        case added, modified, deleted
    }
}

// Backend models
struct BackendDiagnostic: Decodable {
    let file: String
    let line: Int?
    let severity: String
    let message: String
}

struct BackendVerificationResult: Decodable {
    let passed: Bool
    let diagnostics: [BackendDiagnostic]
    let stdout: String
    let stderr: String
    let exit_code: Int
}
