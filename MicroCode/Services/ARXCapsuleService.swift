//
//  ARXCapsuleService.swift
//  MicroCode
//
//  Portable Sovereign Agent Capsule (.arx v2) Engine.
//  Packages Chat Transcripts + Implementation Plans + task.md + Workspace Rules + Git Diff Patch
//  into a single compressed, SHA-256-verified `.arx` file that can be exported, shared, dragged,
//  or double-clicked in macOS Finder to resume work seamlessly across machines.
//

import Foundation
import AppKit
import CryptoKit

// MARK: - .ARX v2 Portable Agent Capsule Schema

struct ARXCapsule: Codable {
    static let currentSchemaVersion = 2
    static let magicHeader = Data("MCARX2\n".utf8)

    var schemaVersion: Int
    var capsuleId: String
    var createdAt: Date
    var appVersion: String
    var title: String
    var workspace: WorkspaceSnapshot
    var modelState: ModelSnapshot
    var messages: [AgentMessageData]
    var activePlan: ImplementationPlan?
    var taskMarkdown: String?
    var walkthroughMarkdown: String?
    var learnedRulesMarkdown: String?
    var agentInstructionsMarkdown: String?
    var gitDiffPatch: String?
    var contentSHA256: String

    struct WorkspaceSnapshot: Codable {
        var projectName: String
        var gitBranch: String?
        var gitHeadCommit: String?
        var gitStatusSummary: String?
        var modifiedFiles: [String]
    }

    struct ModelSnapshot: Codable {
        var provider: String
        var model: String
        var activeSkillIds: [String]
    }
}

enum ARXCapsuleError: LocalizedError {
    case unreadableFile(String)
    case invalidFormat(String)
    case checksumMismatch
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let path):
            return "Cannot read .arx capsule at \(path)"
        case .invalidFormat(let detail):
            return "Invalid .arx capsule format: \(detail)"
        case .checksumMismatch:
            return ".arx capsule integrity check failed (SHA-256 mismatch)"
        case .decompressionFailed:
            return "Failed to decompress MCARX2 capsule payload"
        }
    }
}

// MARK: - ARXCapsuleService

final class ARXCapsuleService: Sendable {
    static let shared = ARXCapsuleService()

    private static let maxGitDiffBytes = 512 * 1024

    private init() {}

    // MARK: - Fast File Identification

    nonisolated static func isARXCapsuleFile(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "arx" {
            // Exclude internal auto-checkpoint AI.arx only when someone browses folders,
            // unless explicitly opened directly by URL.
            return true
        }
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        guard let prefix = try? fh.read(upToCount: ARXCapsule.magicHeader.count) else { return false }
        return prefix == ARXCapsule.magicHeader
    }

    nonisolated static func hasBinaryMagic(_ data: Data) -> Bool {
        data.count >= ARXCapsule.magicHeader.count &&
        data.prefix(ARXCapsule.magicHeader.count) == ARXCapsule.magicHeader
    }

    // MARK: - Encoding & Decoding (MCARX2 Zlib Envelope + Legacy v1 JSON Compatibility)

    nonisolated static func computeContentChecksum(_ capsule: ARXCapsule) -> String {
        var copy = capsule
        copy.contentSHA256 = ""
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(copy) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated func encodeCapsule(_ capsule: ARXCapsule, compressed: Bool = true) throws -> Data {
        var finalized = capsule
        finalized.contentSHA256 = Self.computeContentChecksum(finalized)

        let encoder = JSONEncoder()
        encoder.outputFormatting = compressed ? [.sortedKeys] : [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(finalized)

        guard compressed else { return jsonData }
        let compressedPayload = try (jsonData as NSData).compressed(using: .zlib) as Data
        var envelope = Data()
        envelope.reserveCapacity(ARXCapsule.magicHeader.count + compressedPayload.count)
        envelope.append(ARXCapsule.magicHeader)
        envelope.append(compressedPayload)
        return envelope
    }

    nonisolated func decodeCapsule(from rawData: Data) throws -> ARXCapsule {
        let jsonData: Data
        if Self.hasBinaryMagic(rawData) {
            let payload = rawData.dropFirst(ARXCapsule.magicHeader.count)
            guard let decompressed = try? (Data(payload) as NSData).decompressed(using: .zlib) as Data else {
                throw ARXCapsuleError.decompressionFailed
            }
            jsonData = decompressed
        } else {
            jsonData = rawData
        }

        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        if let v2 = try? isoDecoder.decode(ARXCapsule.self, from: jsonData) {
            if !v2.contentSHA256.isEmpty {
                let expected = Self.computeContentChecksum(v2)
                if !expected.isEmpty && expected != v2.contentSHA256 {
                    throw ARXCapsuleError.checksumMismatch
                }
            }
            return v2
        }

        let defaultDecoder = JSONDecoder()
        if let v2Default = try? defaultDecoder.decode(ARXCapsule.self, from: jsonData) {
            return v2Default
        }

        // Backward-compatible upgrade from legacy v1 `AIArxData` JSON
        if let legacy = try? defaultDecoder.decode(AIArxData.self, from: jsonData) {
            let lastModel = legacy.models.last
            let convertedMessages: [AgentMessageData] = legacy.memory.enumerated().map { idx, mem in
                AgentMessageData(
                    id: "legacy-\(idx)",
                    role: mem.role == "user" ? "user" : "assistant",
                    content: mem.content,
                    timestamp: mem.timestamp,
                    toolResults: nil,
                    attachmentHistoryContext: nil
                )
            }
            return ARXCapsule(
                schemaVersion: 1,
                capsuleId: UUID().uuidString,
                createdAt: legacy.lastUpdated,
                appVersion: "legacy-v1",
                title: "Recovered ARX Checkpoint",
                workspace: ARXCapsule.WorkspaceSnapshot(
                    projectName: "Workspace",
                    gitBranch: nil,
                    gitHeadCommit: nil,
                    gitStatusSummary: nil,
                    modifiedFiles: legacy.artifacts.map(\.path)
                ),
                modelState: ARXCapsule.ModelSnapshot(
                    provider: lastModel?.provider ?? "",
                    model: lastModel?.model ?? "",
                    activeSkillIds: []
                ),
                messages: convertedMessages,
                activePlan: nil,
                taskMarkdown: nil,
                walkthroughMarkdown: nil,
                learnedRulesMarkdown: nil,
                agentInstructionsMarkdown: nil,
                gitDiffPatch: nil,
                contentSHA256: ""
            )
        }

        throw ARXCapsuleError.invalidFormat("Unrecognized .arx payload")
    }

    nonisolated func readCapsule(from url: URL) throws -> ARXCapsule {
        guard let data = try? Data(contentsOf: url) else {
            throw ARXCapsuleError.unreadableFile(url.path)
        }
        return try decodeCapsule(from: data)
    }

    nonisolated func writeCapsule(_ capsule: ARXCapsule, to url: URL, compressed: Bool = true, ownerOnlyPermissions: Bool = false) throws {
        let encoded = try encodeCapsule(capsule, compressed: compressed)
        if ownerOnlyPermissions {
            try WorkspaceStoragePaths.writeSecureData(encoded, to: url)
        } else {
            let fm = FileManager.default
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: url, options: .atomic)
        }
    }

    private static let backgroundArxQueue = DispatchQueue(label: "com.dotmini.microcode.arx-writer", qos: .utility)

    /// Captures lightweight @MainActor pointers in <0.1ms and performs all disk transcript merges,
    /// regex privacy redaction, SHA-256 hashing, and compressed `.arx` I/O off the main thread.
    @MainActor
    func saveCapsuleInBackground(
        to arxURL: URL,
        chatId: String?,
        workspacePath: String,
        includeGitDiff: Bool = false
    ) {
        let agent = AgentService.shared
        let targetChatId = chatId ?? agent.activeChatId
        let activeScope = agent.activeScope
        let isTargetActive = (targetChatId == agent.activeChatId)
        let liveMessages: [AgentMessageData] = isTargetActive
            ? agent.messages.map { AgentMessageData.from($0) }
            : []
        let chatSession = targetChatId.flatMap { id in agent.chatSessions.first(where: { $0.id == id }) }

        let projectName: String = {
            if let name = chatSession?.projectName, !name.isEmpty { return name }
            if !workspacePath.isEmpty {
                return URL(fileURLWithPath: workspacePath).lastPathComponent
            }
            return "MicroCode"
        }()

        let plan = chatSession?.activePlan ?? ImplementationPlanManager.shared.currentPlan
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "2.5"
        let capsuleTitle = chatSession?.name ?? "Agent Session"
        let activeSkills = chatSession?.activeSkillIds ?? AgentSkillsStore.shared.enabledSkillIds()
        let modifiedFiles = Array(agent.filesModified).sorted()
        let provider = AppState.shared?.aiProvider ?? agent.lastProvider
        let model = AppState.shared?.aiModel ?? agent.lastModel

        Self.backgroundArxQueue.async {
            let rawMessages: [AgentMessageData]
            if let cid = targetChatId {
                let diskAll = AgentTranscriptStore.shared.loadRecent(chatID: cid, scope: activeScope, limit: 2000)
                if isTargetActive, !liveMessages.isEmpty {
                    if diskAll.count > liveMessages.count {
                        let liveIds = Set(liveMessages.map(\.id))
                        rawMessages = diskAll.filter { !liveIds.contains($0.id) } + liveMessages
                    } else {
                        rawMessages = liveMessages
                    }
                } else {
                    rawMessages = diskAll
                }
            } else {
                rawMessages = liveMessages
            }

            let sanitizedMessages: [AgentMessageData] = rawMessages.map { msg in
                let sanitizedTools: [PersistedToolResult]? = msg.toolResults?.map { tr in
                    PersistedToolResult(
                        toolCallId: tr.toolCallId,
                        toolName: tr.toolName,
                        stringParams: tr.stringParams,
                        success: tr.success,
                        output: AgentPrivacyGuard.sanitize(tr.output),
                        error: tr.error.map { AgentPrivacyGuard.sanitize($0) }
                    )
                }
                return AgentMessageData(
                    id: msg.id,
                    role: msg.role,
                    content: AgentPrivacyGuard.sanitize(msg.content),
                    timestamp: msg.timestamp,
                    toolResults: sanitizedTools,
                    attachmentHistoryContext: msg.attachmentHistoryContext.map { AgentPrivacyGuard.sanitize($0) },
                    attachments: msg.attachments
                )
            }

            let taskMd = Self.readRedactedFileIfPresent(
                WorkspaceStoragePaths.readableWorkspaceOrStateFile(named: "task.md", workspacePath: workspacePath)
            )
            let walkthroughMd = Self.readRedactedFileIfPresent(
                WorkspaceStoragePaths.readableWorkspaceOrStateFile(named: "walkthrough.md", workspacePath: workspacePath)
            )
            let rulesMd = Self.readRedactedFileIfPresent(
                WorkspaceStoragePaths.readableWorkspaceOrStateFile(named: "rules.md", workspacePath: workspacePath)
            )
            let agentMd = Self.readRedactedFileIfPresent(
                WorkspaceStoragePaths.readableWorkspaceOrStateFile(named: "agent.md", workspacePath: workspacePath)
            )

            let gitMeta = includeGitDiff && !workspacePath.isEmpty
                ? Self.captureGitSnapshot(workspacePath: workspacePath)
                : (branch: nil, commit: nil, status: nil, diff: nil)

            var capsule = ARXCapsule(
                schemaVersion: ARXCapsule.currentSchemaVersion,
                capsuleId: UUID().uuidString,
                createdAt: Date(),
                appVersion: appVersion,
                title: capsuleTitle,
                workspace: ARXCapsule.WorkspaceSnapshot(
                    projectName: projectName,
                    gitBranch: gitMeta.branch,
                    gitHeadCommit: gitMeta.commit,
                    gitStatusSummary: gitMeta.status,
                    modifiedFiles: modifiedFiles
                ),
                modelState: ARXCapsule.ModelSnapshot(
                    provider: provider,
                    model: model,
                    activeSkillIds: activeSkills
                ),
                messages: sanitizedMessages,
                activePlan: plan,
                taskMarkdown: taskMd,
                walkthroughMarkdown: walkthroughMd,
                learnedRulesMarkdown: rulesMd,
                agentInstructionsMarkdown: agentMd,
                gitDiffPatch: gitMeta.diff,
                contentSHA256: ""
            )
            capsule.contentSHA256 = Self.computeContentChecksum(capsule)
            try? ARXCapsuleService.shared.writeCapsule(capsule, to: arxURL, compressed: true, ownerOnlyPermissions: true)
        }
    }

    // MARK: - Build Capsule Snapshot from Live Agent & Workspace State

    @MainActor
    func buildCapsule(
        chatId: String? = nil,
        workspacePath: String? = nil,
        includeGitDiff: Bool = true
    ) -> ARXCapsule {
        let agent = AgentService.shared
        let targetChatId = chatId ?? agent.activeChatId
        let chatSession = targetChatId.flatMap { id in agent.chatSessions.first(where: { $0.id == id }) }

        let resolvedWorkspace = workspacePath
            ?? chatSession?.projectPath
            ?? agent.currentWorkspace
            ?? AppState.shared?.workspaceFolder?.path
            ?? ""

        let projectName: String = {
            if let name = chatSession?.projectName, !name.isEmpty { return name }
            if !resolvedWorkspace.isEmpty {
                return URL(fileURLWithPath: resolvedWorkspace).lastPathComponent
            }
            return "MicroCode"
        }()

        let rawMessages = agent.exportableMessages(for: targetChatId)
        let sanitizedMessages: [AgentMessageData] = rawMessages.map { msg in
            let sanitizedTools: [PersistedToolResult]? = msg.toolResults?.map { tr in
                PersistedToolResult(
                    toolCallId: tr.toolCallId,
                    toolName: tr.toolName,
                    stringParams: tr.stringParams,
                    success: tr.success,
                    output: AgentPrivacyGuard.sanitize(tr.output),
                    error: tr.error.map { AgentPrivacyGuard.sanitize($0) }
                )
            }
            return AgentMessageData(
                id: msg.id,
                role: msg.role,
                content: AgentPrivacyGuard.sanitize(msg.content),
                timestamp: msg.timestamp,
                toolResults: sanitizedTools,
                attachmentHistoryContext: msg.attachmentHistoryContext.map { AgentPrivacyGuard.sanitize($0) },
                attachments: msg.attachments
            )
        }

        let plan = chatSession?.activePlan ?? ImplementationPlanManager.shared.currentPlan
        let taskMd = Self.readRedactedFileIfPresent(
            WorkspaceStoragePaths.readableWorkspaceOrStateFile(named: "task.md", workspacePath: resolvedWorkspace)
        )
        let walkthroughMd = Self.readRedactedFileIfPresent(
            WorkspaceStoragePaths.readableWorkspaceOrStateFile(named: "walkthrough.md", workspacePath: resolvedWorkspace)
        )
        let rulesMd = Self.readRedactedFileIfPresent(
            WorkspaceStoragePaths.readableWorkspaceOrStateFile(named: "rules.md", workspacePath: resolvedWorkspace)
        )
        let agentMd = Self.readRedactedFileIfPresent(
            WorkspaceStoragePaths.readableWorkspaceOrStateFile(named: "agent.md", workspacePath: resolvedWorkspace)
        )

        let gitMeta = includeGitDiff && !resolvedWorkspace.isEmpty
            ? Self.captureGitSnapshot(workspacePath: resolvedWorkspace)
            : (branch: nil, commit: nil, status: nil, diff: nil)

        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "2.5"
        let capsuleTitle = chatSession?.name ?? "Agent Session"
        let activeSkills = chatSession?.activeSkillIds ?? AgentSkillsStore.shared.enabledSkillIds()

        var capsule = ARXCapsule(
            schemaVersion: ARXCapsule.currentSchemaVersion,
            capsuleId: UUID().uuidString,
            createdAt: Date(),
            appVersion: appVersion,
            title: capsuleTitle,
            workspace: ARXCapsule.WorkspaceSnapshot(
                projectName: projectName,
                gitBranch: gitMeta.branch,
                gitHeadCommit: gitMeta.commit,
                gitStatusSummary: gitMeta.status,
                modifiedFiles: Array(agent.filesModified).sorted()
            ),
            modelState: ARXCapsule.ModelSnapshot(
                provider: AppState.shared?.aiProvider ?? agent.lastProvider,
                model: AppState.shared?.aiModel ?? agent.lastModel,
                activeSkillIds: activeSkills
            ),
            messages: sanitizedMessages,
            activePlan: plan,
            taskMarkdown: taskMd,
            walkthroughMarkdown: walkthroughMd,
            learnedRulesMarkdown: rulesMd,
            agentInstructionsMarkdown: agentMd,
            gitDiffPatch: gitMeta.diff,
            contentSHA256: ""
        )
        capsule.contentSHA256 = Self.computeContentChecksum(capsule)
        return capsule
    }

    // MARK: - Import & Resume Capsule Session

    @MainActor
    @discardableResult
    func importAndResumeCapsule(from url: URL, appState: AppState?) throws -> ChatSession {
        let isSecured = url.startAccessingSecurityScopedResource()
        defer {
            if isSecured { url.stopAccessingSecurityScopedResource() }
        }

        let capsule = try readCapsule(from: url)
        let agent = AgentService.shared
        let targetWorkspace = appState?.workspaceFolder?.path ?? agent.currentWorkspace

        // Persist optional artifacts (task.md, walkthrough.md, git patch) into isolated workspace state
        var savedPatchPath: String? = nil
        if let diff = capsule.gitDiffPatch, !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let patchFileName = "capsule_\(capsule.capsuleId.prefix(8)).patch"
            let patchURL = WorkspaceStoragePaths.managedStateFile(named: "capsules/\(patchFileName)", workspacePath: targetWorkspace)
            try? WorkspaceStoragePaths.writeSecureData(Data(diff.utf8), to: patchURL)
            savedPatchPath = patchURL.path
        }

        if let taskMd = capsule.taskMarkdown, !taskMd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let taskURL = WorkspaceStoragePaths.managedStateFile(named: "task.md", workspacePath: targetWorkspace)
            try? WorkspaceStoragePaths.writeSecureData(Data(taskMd.utf8), to: taskURL)
        }

        if let walkthroughMd = capsule.walkthroughMarkdown, !walkthroughMd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let wtURL = WorkspaceStoragePaths.managedStateFile(named: "walkthrough.md", workspacePath: targetWorkspace)
            try? WorkspaceStoragePaths.writeSecureData(Data(walkthroughMd.utf8), to: wtURL)
        }

        // Build summary banner appended at the bottom of the restored conversation so the user knows exact capsule context
        var summaryLines: [String] = [
            "📦 **Restored `.ARX` Portable Agent Capsule** — *\(capsule.title)*",
            "- **Origin Project:** `\(capsule.workspace.projectName)`" +
                (capsule.workspace.gitBranch.map { " · branch `\($0)`" } ?? "") +
                (capsule.workspace.gitHeadCommit.map { " (`\($0.prefix(7))`)" } ?? ""),
            "- **Messages Restored:** \(capsule.messages.count) turns"
        ]
        if let plan = capsule.activePlan {
            summaryLines.append("- **Implementation Plan:** *\(plan.title)* (\(plan.totalSteps) steps)")
        }
        if let patchPath = savedPatchPath, let diff = capsule.gitDiffPatch {
            let diffLines = diff.components(separatedBy: .newlines).count
            summaryLines.append("- **Uncommitted Git Diff Included:** \(diffLines) lines saved at `\(patchPath)` — type `/arx apply` to apply this patch to your current workspace.")
        }

        var restoredMessages = capsule.messages
        restoredMessages.append(
            AgentMessageData(
                id: UUID().uuidString,
                role: "assistant",
                content: summaryLines.joined(separator: "\n"),
                timestamp: Date(),
                toolResults: nil,
                attachmentHistoryContext: nil
            )
        )

        let sessionProjectName: String? = {
            if let ws = targetWorkspace, !ws.isEmpty {
                return URL(fileURLWithPath: ws).lastPathComponent
            }
            return capsule.workspace.projectName
        }()

        let newSession = ChatSession(
            id: UUID().uuidString,
            name: capsule.title.hasSuffix(" (ARX)") ? capsule.title : "\(capsule.title) (ARX)",
            projectPath: targetWorkspace,
            projectName: sessionProjectName,
            activeSkillIds: capsule.modelState.activeSkillIds.isEmpty ? nil : capsule.modelState.activeSkillIds,
            messages: [],
            messageCount: restoredMessages.count,
            summaryThroughMessageID: nil,
            activePlan: capsule.activePlan,
            createdAt: capsule.createdAt,
            updatedAt: Date()
        )

        agent.restoreImportedCapsuleSession(newSession, messages: restoredMessages, latestPatchPath: savedPatchPath)
        appState?.switchToMode(.aiAgent)
        return newSession
    }

    // MARK: - Interactive Save / Open Panels

    @MainActor
    func exportCapsuleWithSavePanel(chatId: String? = nil, workspacePath: String? = nil) {
        let capsule = buildCapsule(chatId: chatId, workspacePath: workspacePath, includeGitDiff: true)
        let safeName = capsule.title
            .replacingOccurrences(of: "[^A-Za-z0-9._ -]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
        let defaultFilename = (safeName.isEmpty ? "MicroCode-Session" : String(safeName.prefix(48))) + ".arx"

        let panel = NSSavePanel()
        panel.title = "Export .ARX Portable Agent Capsule"
        panel.message = "Bundles conversation history, implementation plan, task.md, rules, and uncommitted git diff into a single portable .arx capsule."
        panel.nameFieldStringValue = defaultFilename
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        if panel.runModal() == .OK, let destURL = panel.url {
            let finalURL = destURL.pathExtension.lowercased() == "arx"
                ? destURL
                : destURL.appendingPathExtension("arx")
            do {
                try writeCapsule(capsule, to: finalURL, compressed: true, ownerOnlyPermissions: false)
                let confirmMsg = AgentMessageModel(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: "✅ **Exported `.ARX` Capsule:** `\(finalURL.path)`\n\nIncludes **\(capsule.messages.count)** messages" +
                        (capsule.activePlan != nil ? ", active **Implementation Plan**" : "") +
                        (capsule.gitDiffPatch != nil ? ", and **Git Diff Snapshot**" : "") +
                        ". Double-click this file on any Mac with MicroCode to resume immediately.",
                    toolResults: [],
                    pendingChanges: [],
                    timestamp: Date()
                )
                AgentService.shared.messages.append(confirmMsg)
                AgentService.shared.saveChats()
            } catch {
                AppState.shared?.alertMessage = "Failed to export .ARX capsule: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    func importCapsuleWithOpenPanel(appState: AppState?) {
        let panel = NSOpenPanel()
        panel.title = "Import .ARX Portable Agent Capsule"
        panel.message = "Select a MicroCode .arx capsule file to restore its conversation, plan, and git patch."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                _ = try importAndResumeCapsule(from: url, appState: appState)
            } catch {
                appState?.alertMessage = "Failed to import .ARX capsule: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Apply Git Patch from Imported Capsule

    nonisolated func applyPatchFile(_ patchPath: String, in workspacePath: String) -> (success: Bool, message: String) {
        guard FileManager.default.fileExists(atPath: patchPath) else {
            return (false, "Patch file not found at \(patchPath)")
        }
        guard !workspacePath.isEmpty, FileManager.default.fileExists(atPath: workspacePath) else {
            return (false, "Open a target workspace folder before applying the capsule's git patch.")
        }

        let check = Self.runGit(["apply", "--check", patchPath], cwd: workspacePath)
        if check.status != 0 {
            let check3Way = Self.runGit(["apply", "--check", "--3way", patchPath], cwd: workspacePath)
            if check3Way.status == 0 {
                let applied = Self.runGit(["apply", "--3way", patchPath], cwd: workspacePath)
                return applied.status == 0
                    ? (true, "Applied capsule git patch cleanly (3-way merge) in `\(workspacePath)`.")
                    : (false, "git apply --3way failed:\n\(applied.output)")
            }
            return (false, "Patch cannot be applied cleanly to current workspace:\n\(check.output)")
        }

        let applyRes = Self.runGit(["apply", patchPath], cwd: workspacePath)
        return applyRes.status == 0
            ? (true, "Applied capsule git patch cleanly to `\(workspacePath)`.")
            : (false, "git apply failed:\n\(applyRes.output)")
    }

    // MARK: - Grounded Summary for UniversalAttachmentEngine

    nonisolated static func formatGroundedAttachmentSummary(for url: URL) -> String? {
        guard let capsule = try? ARXCapsuleService.shared.readCapsule(from: url) else { return nil }
        var out: [String] = []
        out.append("[MicroCode Portable Agent Capsule (.arx v\(capsule.schemaVersion))]")
        out.append("Title: \(capsule.title)")
        out.append("Project: \(capsule.workspace.projectName)")
        if let branch = capsule.workspace.gitBranch {
            out.append("Git Branch: \(branch) (\(capsule.workspace.gitHeadCommit?.prefix(7) ?? "unknown"))")
        }
        out.append("Created: \(ISO8601DateFormatter().string(from: capsule.createdAt))")
        out.append("Model: \(capsule.modelState.provider) / \(capsule.modelState.model)")
        out.append("Messages: \(capsule.messages.count)")

        if let plan = capsule.activePlan {
            out.append("\n--- Implementation Plan: \(plan.title) ---")
            let allSteps = plan.sections.flatMap { $0.steps }
            for (idx, step) in allSteps.enumerated() {
                out.append("\(idx + 1). [\(step.status.rawValue)] \(step.description)")
            }
        }
        if let taskMd = capsule.taskMarkdown, !taskMd.isEmpty {
            out.append("\n--- task.md ---\n\(String(taskMd.prefix(8_000)))")
        }
        if !capsule.messages.isEmpty {
            out.append("\n--- Conversation Transcript (Recent Turns) ---")
            for msg in capsule.messages.suffix(20) {
                out.append("[\(msg.role.uppercased())] \(String(msg.content.prefix(2_000)))")
            }
        }
        if let diff = capsule.gitDiffPatch, !diff.isEmpty {
            out.append("\n--- Uncommitted Git Diff Snapshot ---\n\(String(diff.prefix(20_000)))")
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    nonisolated private static func readRedactedFileIfPresent(_ url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return AgentPrivacyGuard.sanitize(trimmed)
    }

    nonisolated private static func captureGitSnapshot(workspacePath: String) -> (branch: String?, commit: String?, status: String?, diff: String?) {
        let gitCheck = runGit(["rev-parse", "--is-inside-work-tree"], cwd: workspacePath)
        guard gitCheck.status == 0 else { return (nil, nil, nil, nil) }

        let branchRes = runGit(["rev-parse", "--abbrev-ref", "HEAD"], cwd: workspacePath)
        let commitRes = runGit(["rev-parse", "HEAD"], cwd: workspacePath)
        let statusRes = runGit(["status", "--short"], cwd: workspacePath)
        let diffRes = runGit(["diff", "HEAD"], cwd: workspacePath, maxBytes: maxGitDiffBytes)

        let branch = branchRes.status == 0 ? branchRes.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let commit = commitRes.status == 0 ? commitRes.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let status = statusRes.status == 0 && !statusRes.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AgentPrivacyGuard.sanitize(statusRes.output.trimmingCharacters(in: .whitespacesAndNewlines))
            : nil
        let diffRaw = diffRes.status == 0 ? diffRes.output : ""
        let diff = !diffRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AgentPrivacyGuard.sanitize(diffRaw)
            : nil

        return (branch, commit, status, diff)
    }

    nonisolated private static func runGit(_ args: [String], cwd: String, maxBytes: Int = 256 * 1024) -> (status: Int32, output: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return (-1, "")
        }
        let data = (try? pipe.fileHandleForReading.read(upToCount: maxBytes)) ?? Data()
        // Close read end BEFORE waitUntilExit so git never deadlocks on full kernel pipe when output > maxBytes
        try? pipe.fileHandleForReading.close()
        proc.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return (proc.terminationStatus, text)
    }
}
