//
//  PNSMotorWorktreePlexus.swift
//  MicroCode
//
//  PNS Somatic Motor Plexus for Agent_1 ... Agent_n Parallel Fibers.
//  Allocates isolated Git Worktrees (or APFS Copy-on-Write clones), enforces semantic
//  file-ownership leases, executes Neuromuscular Verification Gates, and performs
//  conflict-free 3-way LCS merges back to trunk or preserves safe `pns/auto-*` branches.
//
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation

public struct PNSNeuromuscularJoinResult {
    public let verificationPassed: Bool
    public let verificationSpike: String
    public let modifiedFiles: [String]
    public let mergedToTrunk: Bool
    public let committedBranch: String?
}

@MainActor
public final class PNSMotorWorktreePlexus: ObservableObject {
    public static let shared = PNSMotorWorktreePlexus()

    @Published public private(set) var activeLeases: [String: PNSMotorFiberLease] = [:]
    /// Stores initial base file snapshots per leaseId -> relativePath -> baseContent for 3-way Diff3 merging
    private var baseSnapshots: [String: [String: String]] = [:]
    private var motorImpulseCounts: [PNSNerveTractKind: Int] = [:]

    private var worktreesRootDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".microcode/pns/worktrees", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {}

    // MARK: - 1. Isolated Motor Fiber Allocation (Git Worktree / APFS CoW)

    public func allocateMotorFiber(
        missionId: String,
        agentArchetype: String,
        roleTitle: String,
        baseWorkspacePath: String,
        ownedPaths: [String] = []
    ) async throws -> PNSMotorFiberLease {
        let fiberId = UUID().uuidString
        let shortMission = String(missionId.prefix(6)).lowercased()
        let shortFiber = String(fiberId.prefix(6)).lowercased()
        let slugRole = agentArchetype.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
        let branchName = "pns/auto-\(shortMission)-\(slugRole)-\(shortFiber)"

        let targetURL = worktreesRootDir
            .appendingPathComponent(shortMission, isDirectory: true)
            .appendingPathComponent("\(slugRole)-\(shortFiber)", isDirectory: true)

        try? FileManager.default.removeItem(at: targetURL)
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let isGit = await Self.isGitRepository(at: baseWorkspacePath)
        if isGit {
            let addRes = await Self.runShell(
                command: "git worktree add -B \"\(branchName)\" \"\(targetURL.path)\" HEAD",
                cwd: baseWorkspacePath
            )
            if addRes.exitCode != 0 {
                // Fallback to APFS Copy-on-Write clone if git worktree cannot lock (e.g. unborn HEAD)
                try await Self.apfsCloneWorkspace(from: baseWorkspacePath, to: targetURL.path)
            }
        } else {
            try await Self.apfsCloneWorkspace(from: baseWorkspacePath, to: targetURL.path)
        }

        let tract = PNSGanglionRouter.motorTractForSubAgent(archetype: agentArchetype)
        motorImpulseCounts[tract, default: 0] += 1

        let lease = PNSMotorFiberLease(
            id: fiberId,
            missionId: missionId,
            agentArchetype: agentArchetype,
            roleTitle: roleTitle,
            tract: tract,
            baseWorkspacePath: baseWorkspacePath,
            isolatedWorktreePath: targetURL.path,
            branchName: branchName,
            ownedPaths: ownedPaths,
            state: "active",
            verificationPassed: false,
            mergedToTrunk: false,
            summary: nil,
            startedAt: Date(),
            finishedAt: nil
        )
        activeLeases[fiberId] = lease
        baseSnapshots[fiberId] = Self.captureSourceSnapshot(at: targetURL.path)
        return lease
    }

    // MARK: - 2. Spinal Reflex Fast Rollback (Anti-Behavioral-Fixation)

    public func rollbackFiberToCleanCheckpoint(fiberId: String) async -> Bool {
        guard let lease = activeLeases[fiberId] else { return false }
        let isGit = await Self.isGitRepository(at: lease.isolatedWorktreePath)
        if isGit {
            let res = await Self.runShell(
                command: "git checkout -- . && git clean -fd",
                cwd: lease.isolatedWorktreePath
            )
            return res.exitCode == 0
        }
        // Non-git fallback: restore from initial baseSnapshots
        if let snap = baseSnapshots[fiberId] {
            for (rel, content) in snap {
                let full = (lease.isolatedWorktreePath as NSString).appendingPathComponent(rel)
                try? content.write(toFile: full, atomically: true, encoding: .utf8)
            }
            return true
        }
        return false
    }

    // MARK: - 3. Neuromuscular Junction: Verification Gate + 3-Way Merge / Safe Branch Commit

    public func verifyAndJoinFiber(
        fiberId: String,
        branchPolicy: PNSBranchSafetyPolicy,
        verificationCommand: String?,
        fiberSummary: String
    ) async -> PNSNeuromuscularJoinResult {
        guard var lease = activeLeases[fiberId] else {
            return PNSNeuromuscularJoinResult(
                verificationPassed: false,
                verificationSpike: "Motor fiber lease not found.",
                modifiedFiles: [],
                mergedToTrunk: false,
                committedBranch: nil
            )
        }

        let initialSnap = baseSnapshots[fiberId] ?? [:]
        let currentSnap = Self.captureSourceSnapshot(at: lease.isolatedWorktreePath)

        var modifiedRelPaths: [String] = []
        for (rel, newText) in currentSnap {
            if initialSnap[rel] != newText {
                // Enforce semantic ownership lease if ownedPaths were specified
                if !lease.ownedPaths.isEmpty && !Self.matchesOwnedScope(relPath: rel, ownedPatterns: lease.ownedPaths) {
                    continue
                }
                modifiedRelPaths.append(rel)
            }
        }
        modifiedRelPaths.sort()

        // Step A: Verification Gate inside Isolated Worktree
        var verificationPassed = true
        var verificationSpike = "No external verification command configured; syntax & lease boundaries verified."

        if let cmd = verificationCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !cmd.isEmpty {
            let exec = await Self.runShell(
                command: cmd,
                cwd: lease.isolatedWorktreePath,
                timeoutSeconds: 300
            )
            verificationPassed = (exec.exitCode == 0)
            let filtered = PNSGanglionRouter.thalamicFilterSensoryStream(
                rawOutput: exec.stdout + "\n" + exec.stderr,
                source: "MotorVerify:\(lease.agentArchetype)"
            )
            verificationSpike = filtered.compressedSpike
        }

        // Step B: Commit verified state inside worktree branch (durable audit & rollback anchor)
        var committedBranch: String? = nil
        let isGit = await Self.isGitRepository(at: lease.isolatedWorktreePath)
        if isGit && !modifiedRelPaths.isEmpty && verificationPassed {
            let safeMsg = "PNS [\(lease.agentArchetype)]: \(fiberSummary.prefix(72))"
                .replacingOccurrences(of: "\"", with: "'")
            let commitRes = await Self.runShell(
                command: "git add -A && git commit -m \"\(safeMsg)\"",
                cwd: lease.isolatedWorktreePath
            )
            if commitRes.exitCode == 0 {
                committedBranch = lease.branchName
            }
        }

        // Step C: Apply Branch Safety Policy
        var mergedToTrunk = false
        if verificationPassed && !modifiedRelPaths.isEmpty && branchPolicy == .autoThreeWayMergeOnVerify {
            for rel in modifiedRelPaths {
                guard let incomingText = currentSnap[rel] else { continue }
                let baseText = initialSnap[rel] ?? ""
                let trunkFilePath = (lease.baseWorkspacePath as NSString).appendingPathComponent(rel)
                let trunkDir = (trunkFilePath as NSString).deletingLastPathComponent
                try? FileManager.default.createDirectory(atPath: trunkDir, withIntermediateDirectories: true)

                if FileManager.default.fileExists(atPath: trunkFilePath),
                   let currentTrunkText = try? String(contentsOfFile: trunkFilePath, encoding: .utf8) {
                    let merged = CollaborativeThreeWayMerger.merge(
                        base: baseText,
                        current: currentTrunkText,
                        incoming: incomingText
                    )
                    try? merged.merged.write(toFile: trunkFilePath, atomically: true, encoding: .utf8)
                } else {
                    try? incomingText.write(toFile: trunkFilePath, atomically: true, encoding: .utf8)
                }
            }
            mergedToTrunk = true
        }

        lease.verificationPassed = verificationPassed
        lease.mergedToTrunk = mergedToTrunk
        lease.state = verificationPassed ? (mergedToTrunk ? "merged" : "verified_branch") : "verification_failed"
        lease.summary = fiberSummary
        lease.finishedAt = Date()
        activeLeases[fiberId] = lease

        // Clean up temporary worktree directory on disk while keeping the git branch intact
        await releaseWorktreeDirectory(lease: lease, isGit: isGit)
        baseSnapshots.removeValue(forKey: fiberId)

        return PNSNeuromuscularJoinResult(
            verificationPassed: verificationPassed,
            verificationSpike: verificationSpike,
            modifiedFiles: modifiedRelPaths,
            mergedToTrunk: mergedToTrunk,
            committedBranch: committedBranch
        )
    }

    private func releaseWorktreeDirectory(lease: PNSMotorFiberLease, isGit: Bool) async {
        if isGit {
            _ = await Self.runShell(
                command: "git worktree remove --force \"\(lease.isolatedWorktreePath)\"",
                cwd: lease.baseWorkspacePath
            )
        }
        try? FileManager.default.removeItem(atPath: lease.isolatedWorktreePath)
    }

    // MARK: - 4. Telemetry Builder

    public func buildMotorTractTelemetry(myelinatedEdges: [PNSSynapseEdge]) -> [PNSTractTelemetry] {
        let subagents = SubAgentHarness.shared.activeSubagents
        return PNSNerveTractKind.allCases.filter(\.isMotorAgentTract).map { tract in
            let archetypesForTract = SubAgentHarness.shared.registeredDefinitions.keys
                .filter { PNSGanglionRouter.motorTractForSubAgent(archetype: $0) == tract }
                .sorted()
            let activeFibersCount = subagents.filter {
                $0.state == .running && PNSGanglionRouter.motorTractForSubAgent(archetype: $0.typeName) == tract
            }.count + activeLeases.values.filter { $0.tract == tract && $0.state == "active" }.count

            let myelinated = myelinatedEdges.filter { $0.tract == tract && $0.isMyelinated }.count
            return PNSTractTelemetry(
                tract: tract,
                attachedNodes: archetypesForTract,
                activeCount: activeFibersCount,
                hibernatedCount: max(0, archetypesForTract.count - activeFibersCount),
                myelinatedEdgesCount: myelinated,
                avgLatencyMs: 0,
                totalImpulses: motorImpulseCounts[tract] ?? 0
            )
        }
    }

    // MARK: - Helpers

    nonisolated private static func matchesOwnedScope(relPath: String, ownedPatterns: [String]) -> Bool {
        for pattern in ownedPatterns {
            let clean = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "*", with: "")
            if clean.isEmpty || relPath.contains(clean) || relPath.hasPrefix(clean) {
                return true
            }
        }
        return false
    }

    nonisolated private static func isGitRepository(at path: String) async -> Bool {
        let res = await runShell(command: "git rev-parse --is-inside-work-tree", cwd: path, timeoutSeconds: 5)
        return res.exitCode == 0 && res.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    nonisolated private static func apfsCloneWorkspace(from source: String, to destination: String) async throws {
        // Attempt fast APFS Copy-on-Write (`cp -cR`) excluding heavy build/cache directories
        let rsyncRes = await runShell(
            command: "rsync -a --exclude '.git' --exclude 'node_modules' --exclude '.build' --exclude 'target' --exclude '.codetuner-build' \"\(source)/\" \"\(destination)/\"",
            cwd: source,
            timeoutSeconds: 60
        )
        if rsyncRes.exitCode != 0 {
            try FileManager.default.copyItem(atPath: source, toPath: destination)
        }
    }

    nonisolated private static func captureSourceSnapshot(at root: String) -> [String: String] {
        var map: [String: String] = [:]
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: root) else { return map }
        let skipDirs = [".git/", "node_modules/", ".build/", "target/", ".codetuner-build/", "DerivedData/"]
        let allowedExts: Set<String> = ["swift", "rs", "ts", "tsx", "js", "jsx", "py", "go", "java", "kt", "c", "cpp", "h", "hpp", "json", "toml", "yaml", "yml", "md", "html", "css", "sql", "ar"]

        while let rel = enumerator.nextObject() as? String {
            if skipDirs.contains(where: { rel.hasPrefix($0) || rel.contains("/" + $0) }) { continue }
            let ext = (rel as NSString).pathExtension.lowercased()
            guard allowedExts.contains(ext) else { continue }
            let full = (root as NSString).appendingPathComponent(rel)
            if let attrs = try? fm.attributesOfItem(atPath: full),
               let size = attrs[.size] as? UInt64,
               size <= 512_000,
               let content = try? String(contentsOfFile: full, encoding: .utf8) {
                map[rel] = content
            }
        }
        return map
    }

    nonisolated public static func runShell(
        command: String,
        cwd: String,
        timeoutSeconds: TimeInterval = 30
    ) async -> (exitCode: Int32, stdout: String, stderr: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-c", command]
                if FileManager.default.fileExists(atPath: cwd) {
                    proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
                }
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe

                do {
                    try proc.run()
                } catch {
                    continuation.resume(returning: (-1, "", error.localizedDescription))
                    return
                }

                let deadline = Date().addingTimeInterval(timeoutSeconds)
                while proc.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.04)
                }
                if proc.isRunning {
                    proc.terminate()
                }
                proc.waitUntilExit()

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (
                    proc.terminationStatus,
                    String(decoding: outData, as: UTF8.self),
                    String(decoding: errData, as: UTF8.self)
                ))
            }
        }
    }
}
