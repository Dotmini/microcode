//
//  PNSModels.swift
//  MicroCode
//
//  PNS — Pseudo Neural System (Biomimetic 24/7 Autonomous Multi-Agent & MCP Nerve Architecture)
//  Core anatomical models, Hebbian synaptic plasticity (Myelination), 3-tier memory schemas,
//  and homeostatic metabolic pacing structures.
//
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation
import CryptoKit

// MARK: - 1. Autonomic Nervous System Modes (24/7 Homeostasis)

public enum PNSAutonomicMode: String, Codable, CaseIterable, Identifiable {
    /// Automatically modulates between Sympathetic burst and Parasympathetic maintenance
    /// based on Metabolic Budget Index M_t (thermal state, quota pressure, user foreground activity).
    case autoHomeostasis = "auto_homeostasis"
    /// High-priority parallel motor burst: max concurrent worktree fibers & frontier reasoning cortex.
    case sympathetic = "sympathetic"
    /// 24/7 low-cost resting homeostasis: local SLM / Flash routing, REM consolidation,
    /// idle MCP hibernation, and non-destructive background maintenance on isolated branches.
    case parasympathetic = "parasympathetic"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .autoHomeostasis: return "Auto Homeostasis (24/7 Adaptive)"
        case .sympathetic: return "Sympathetic (Parallel Burst)"
        case .parasympathetic: return "Parasympathetic (Nightly / Low-Burn)"
        }
    }

    public var iconName: String {
        switch self {
        case .autoHomeostasis: return "waveform.path.ecg"
        case .sympathetic: return "bolt.heart.fill"
        case .parasympathetic: return "moon.stars.fill"
        }
    }
}

// MARK: - 2. Specialized Neural Tracts (โครงข่ายเส้นประสาทเฉพาะทาง)

public enum PNSNerveTractKind: String, Codable, CaseIterable, Identifiable {
    // Efferent MCP Tracts (คุม MCP_1 ... MCP_xx)
    case mcpCodeAST = "mcp_code_ast"
    case mcpDataCloud = "mcp_data_cloud"
    case mcpBrowserVisual = "mcp_browser_visual"
    case mcpDeviceHardware = "mcp_device_hardware"
    case mcpKnowledgeScience = "mcp_knowledge_science"

    // Somatic Motor Agent Tracts (คุม Agent_1 ... Agent_n)
    case motorArchitecture = "motor_architecture"
    case motorImplementation = "motor_implementation"
    case motorVerification = "motor_verification"

    // CNS & Reflex Tracts
    case spinalReflex = "spinal_reflex"
    case thalamicSensory = "thalamic_sensory"
    case hippocampalREM = "hippocampal_rem"

    public var id: String { rawValue }

    public var isMCPTract: Bool {
        switch self {
        case .mcpCodeAST, .mcpDataCloud, .mcpBrowserVisual, .mcpDeviceHardware, .mcpKnowledgeScience:
            return true
        default:
            return false
        }
    }

    public var isMotorAgentTract: Bool {
        switch self {
        case .motorArchitecture, .motorImplementation, .motorVerification:
            return true
        default:
            return false
        }
    }

    public var title: String {
        switch self {
        case .mcpCodeAST: return "Tract A: Code, AST & Git MCP Plexus"
        case .mcpDataCloud: return "Tract B: Data, SQL & Cloud MCP Plexus"
        case .mcpBrowserVisual: return "Tract C: Browser, UI & Design MCP Plexus"
        case .mcpDeviceHardware: return "Tract D: Mobile, Device & Compute MCP Plexus"
        case .mcpKnowledgeScience: return "Tract E: Research, Docs & Science MCP Plexus"
        case .motorArchitecture: return "Motor Tract 1: Architecture & Contract Fibers"
        case .motorImplementation: return "Motor Tract 2: Parallel Worktree Builders"
        case .motorVerification: return "Motor Tract 3: Adversarial QA & Healer Fibers"
        case .spinalReflex: return "Spinal Cord Reflex Arc (<50ms)"
        case .thalamicSensory: return "Thalamic Sensory Attention Gate"
        case .hippocampalREM: return "Hippocampal REM Memory Consolidator"
        }
    }

    public var shortBadge: String {
        switch self {
        case .mcpCodeAST: return "MCP:Code/AST"
        case .mcpDataCloud: return "MCP:Data/Cloud"
        case .mcpBrowserVisual: return "MCP:UI/Browser"
        case .mcpDeviceHardware: return "MCP:Device/SSH"
        case .mcpKnowledgeScience: return "MCP:Docs/Sci"
        case .motorArchitecture: return "Agent:Arch"
        case .motorImplementation: return "Agent:Build"
        case .motorVerification: return "Agent:Verify"
        case .spinalReflex: return "Reflex:<50ms"
        case .thalamicSensory: return "Thalamus"
        case .hippocampalREM: return "REM:Memory"
        }
    }

    public var iconName: String {
        switch self {
        case .mcpCodeAST: return "curlybraces.square.fill"
        case .mcpDataCloud: return "externaldrive.connected.to.line.below.fill"
        case .mcpBrowserVisual: return "macwindow.on.rectangle"
        case .mcpDeviceHardware: return "iphone.gen3.radiowaves.left.and.right"
        case .mcpKnowledgeScience: return "atom"
        case .motorArchitecture: return "compass.drawing"
        case .motorImplementation: return "hammer.circle.fill"
        case .motorVerification: return "checkmark.shield.fill"
        case .spinalReflex: return "bolt.horizontal.circle.fill"
        case .thalamicSensory: return "dot.radiowaves.left.and.right"
        case .hippocampalREM: return "brain.head.profile"
        }
    }
}

// MARK: - 3. Synaptic Plasticity & Myelination (Reward-Modulated Hebbian Routing)

public struct PNSSynapseEdge: Codable, Identifiable, Equatable {
    /// Deterministic key: `<taskCategory>::<tractKind>::<targetNodeId>`
    public let id: String
    public let taskCategory: String
    public let tract: PNSNerveTractKind
    /// Target identifier e.g. `mcp__postgres__execute_sql`, `agent:bug_hunter`, or `model:gemini-2.5-flash`
    public let targetNodeId: String
    public var projectPath: String?
    /// Synaptic conductance weight W_e in [0.01, 1.00]
    public var weight: Double
    public var successCount: Int
    public var failureCount: Int
    public var avgLatencyMs: Int
    public var avgTokensUsed: Int
    public var lastFiredAt: Date

    public init(
        taskCategory: String,
        tract: PNSNerveTractKind,
        targetNodeId: String,
        projectPath: String? = nil,
        weight: Double = 0.50,
        successCount: Int = 0,
        failureCount: Int = 0,
        avgLatencyMs: Int = 0,
        avgTokensUsed: Int = 0,
        lastFiredAt: Date = Date()
    ) {
        self.id = Self.makeID(taskCategory: taskCategory, tract: tract, targetNodeId: targetNodeId, projectPath: projectPath)
        self.taskCategory = taskCategory
        self.tract = tract
        self.targetNodeId = targetNodeId
        self.projectPath = projectPath
        self.weight = min(1.0, max(0.01, weight))
        self.successCount = successCount
        self.failureCount = failureCount
        self.avgLatencyMs = avgLatencyMs
        self.avgTokensUsed = avgTokensUsed
        self.lastFiredAt = lastFiredAt
    }

    public static func makeID(
        taskCategory: String,
        tract: PNSNerveTractKind,
        targetNodeId: String,
        projectPath: String?
    ) -> String {
        let scope = (projectPath ?? "global").trimmingCharacters(in: .whitespacesAndNewlines)
        let scopeDigest = SHA256.hash(data: Data(scope.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return "\(scopeDigest)::\(taskCategory)::\(tract.rawValue)::\(targetNodeId)"
    }

    /// Myelinated Fast-Path: high synaptic weight earned through repeated verified successes.
    public var isMyelinated: Bool {
        weight >= 0.75 && successCount >= 3
    }

    /// Long-Term Depression (LTD) Inhibition: pathway repeatedly failed; suppress repeating broken strategy.
    public var isInhibited: Bool {
        weight <= 0.22 && failureCount >= 2
    }

    /// Reward-Modulated Hebbian Update:
    /// W(t+1) = clip((1 - lambda) * W(t) + eta_pos * R_t * I_ok - eta_neg * C_t * I_fail, 0.01, 1.0)
    public mutating func applyHebbianImpulse(
        succeeded: Bool,
        verifiedProgress: Double = 1.0,
        tokensUsed: Int,
        latencyMs: Int,
        regressionPenalty: Double = 1.0
    ) {
        let lambda = 0.015
        let etaPlus = 0.14
        let etaMinus = 0.20

        let tokenFactor = log(1.0 + Double(max(1, tokensUsed)) / 250.0)
        let latencyFactor = log(1.0 + Double(max(1, latencyMs)) / 500.0)
        let denom = max(0.65, sqrt(max(1.0, tokenFactor * latencyFactor)))
        let reward = min(1.6, max(0.35, verifiedProgress / denom))

        var updated = (1.0 - lambda) * weight
        if succeeded {
            updated += etaPlus * reward
            successCount += 1
        } else {
            updated -= etaMinus * max(0.5, regressionPenalty)
            failureCount += 1
        }
        weight = min(1.0, max(0.01, updated))
        avgLatencyMs = avgLatencyMs == 0 ? latencyMs : ((avgLatencyMs * 3 + latencyMs) / 4)
        avgTokensUsed = avgTokensUsed == 0 ? tokensUsed : ((avgTokensUsed * 3 + tokensUsed) / 4)
        lastFiredAt = Date()
    }
}

// MARK: - 4. Three-Tier Biomimetic Memory (Episodic WAL -> Procedural Playbooks -> Semantic Invariants)

public enum PNSSpikeKind: String, Codable {
    case sensoryStimulus = "sensory_stimulus"
    case ganglionRoute = "ganglion_route"
    case spinalReflex = "spinal_reflex"
    case motorFiberSpawn = "motor_fiber_spawn"
    case motorFiberMerge = "motor_fiber_merge"
    case remConsolidation = "rem_consolidation"
    case homeostasisShift = "homeostasis_shift"
    case nociceptivePain = "nociceptive_pain"
}

/// Tier 1: Episodic Action-Potential Spike persisted to append-only JSONL WAL
public struct PNSEpisodicSpike: Codable, Identifiable, Equatable {
    public let id: String
    public let timestamp: Date
    public let kind: PNSSpikeKind
    public let tract: PNSNerveTractKind
    public let missionId: String?
    public let projectPath: String?
    public let summary: String
    public let salience: Double
    public let latencyMs: Int
    public let succeeded: Bool

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        kind: PNSSpikeKind,
        tract: PNSNerveTractKind,
        missionId: String? = nil,
        projectPath: String? = nil,
        summary: String,
        salience: Double = 0.7,
        latencyMs: Int = 0,
        succeeded: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.tract = tract
        self.missionId = missionId
        self.projectPath = projectPath
        self.summary = summary
        self.salience = min(1.0, max(0.0, salience))
        self.latencyMs = latencyMs
        self.succeeded = succeeded
    }
}

/// Tier 2: Procedural Skill Playbook distilled during Hippocampal REM Consolidation
public struct PNSProceduralPlaybook: Codable, Identifiable, Equatable {
    public let id: String
    public let triggerSignature: String
    public let projectPath: String?
    public let tract: PNSNerveTractKind
    public var toolSequence: [String]
    public var distilledStrategy: String
    public var verificationCheck: String
    public var confidenceWeight: Double
    public var executionWins: Int
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        triggerSignature: String,
        projectPath: String?,
        tract: PNSNerveTractKind,
        toolSequence: [String],
        distilledStrategy: String,
        verificationCheck: String,
        confidenceWeight: Double = 0.78,
        executionWins: Int = 1,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.triggerSignature = triggerSignature
        self.projectPath = projectPath
        self.tract = tract
        self.toolSequence = toolSequence
        self.distilledStrategy = distilledStrategy
        self.verificationCheck = verificationCheck
        self.confidenceWeight = confidenceWeight
        self.executionWins = executionWins
        self.updatedAt = updatedAt
    }
}

/// Tier 3: Project-Scoped Semantic Invariant & Broken-Assumption Guard
public struct PNSSemanticInvariant: Codable, Identifiable, Equatable {
    public let id: String
    public let projectPath: String
    public let moduleScope: String
    public let ruleStatement: String
    /// True if extracted from a failed dead-end / behavioral fixation circuit break
    public let isInhibitionWarning: Bool
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        projectPath: String,
        moduleScope: String,
        ruleStatement: String,
        isInhibitionWarning: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectPath = projectPath
        self.moduleScope = moduleScope
        self.ruleStatement = ruleStatement
        self.isInhibitionWarning = isInhibitionWarning
        self.createdAt = createdAt
    }
}

// MARK: - 5. 24/7 Marathon Mission & Isolated Worktree Motor Fiber Contracts

public enum PNSBranchSafetyPolicy: String, Codable, CaseIterable, Identifiable {
    /// Safe 24/7 default: commits verified work inside isolated `pns/auto-*` git worktree branch without mutating open editor files.
    case isolatedWorktreeBranch = "isolated_worktree_branch"
    /// Automatically merges verified fiber changes into workspace via 3-way LCS Diff3 merger when build/tests pass 100%.
    case autoThreeWayMergeOnVerify = "auto_three_way_merge_on_verify"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .isolatedWorktreeBranch:
            return "Safe Worktree Branch (pns/auto-*)"
        case .autoThreeWayMergeOnVerify:
            return "Auto 3-Way Merge After Verification"
        }
    }
}

public enum PNSMissionStatus: String, Codable {
    case queued
    case running
    case consolidatingREM
    case pacingHomeostasis
    case paused
    case completed
    case failed
    case cancelled
}

public struct PNSMotorFiberLease: Codable, Identifiable, Equatable {
    public let id: String
    public let missionId: String
    public let agentArchetype: String
    public let roleTitle: String
    public let tract: PNSNerveTractKind
    public let baseWorkspacePath: String
    public let isolatedWorktreePath: String
    public let branchName: String
    public let ownedPaths: [String]
    public var state: String
    public var verificationPassed: Bool
    public var mergedToTrunk: Bool
    public var summary: String?
    public let startedAt: Date
    public var finishedAt: Date?
}

public struct PNSMissionSubtask: Codable, Identifiable, Equatable {
    public let id: String
    public var title: String
    public var description: String
    public var assignedArchetype: String
    public var tract: PNSNerveTractKind
    public var ownedPaths: [String]
    public var dependencies: [String]
    public var status: PNSMissionStatus
    public var attempts: Int
    public var resultSummary: String?
    public var worktreeBranch: String?
}

public struct PNSMarathonMission: Codable, Identifiable, Equatable {
    public let id: String
    public var title: String
    public var objective: String
    public var workspacePath: String
    public var branchPolicy: PNSBranchSafetyPolicy
    public var verificationCommand: String?
    public var status: PNSMissionStatus
    public var subtasks: [PNSMissionSubtask]
    public var activeFibers: [PNSMotorFiberLease]
    public var completedEpisodes: Int
    public var remConsolidationsCount: Int
    public var spinalReflexSavesCount: Int
    public var distilledWorkingMemory: String
    public let createdAt: Date
    public var updatedAt: Date
    public var lastError: String?

    public var progressFraction: Double {
        guard !subtasks.isEmpty else { return status == .completed ? 1.0 : 0.0 }
        let done = subtasks.filter { $0.status == .completed }.count
        return Double(done) / Double(subtasks.count)
    }
}

// MARK: - 6. Daemon Live Telemetry Snapshot (Shared over Localhost IPC & Disk WAL)

public struct PNSTractTelemetry: Codable, Identifiable, Equatable {
    public var id: String { tract.rawValue }
    public let tract: PNSNerveTractKind
    public var attachedNodes: [String]
    public var activeCount: Int
    public var hibernatedCount: Int
    public var myelinatedEdgesCount: Int
    public var avgLatencyMs: Int
    public var totalImpulses: Int
}

public struct PNSDaemonStatusSnapshot: Codable, Equatable {
    public let daemonPID: Int32
    public let isOutOfProcessDaemon: Bool
    public let startedAt: Date
    public let autonomicMode: PNSAutonomicMode
    public let effectiveMode: PNSAutonomicMode
    public let metabolicBudgetIndex: Double
    public let thermalStateLabel: String
    public let totalExternalMCPServers: Int
    public let totalExternalMCPTools: Int
    public let activeMountedSynapticTools: Int
    public let hibernatedMCPServers: Int
    public let myelinatedSynapsesCount: Int
    public let inhibitedSynapsesCount: Int
    public let proceduralPlaybooksCount: Int
    public let semanticInvariantsCount: Int
    public let spinalReflexSavesCount: Int
    public let remConsolidationCycles: Int
    public let tracts: [PNSTractTelemetry]
    public let missions: [PNSMarathonMission]
    public let recentSpikes: [PNSEpisodicSpike]
}
