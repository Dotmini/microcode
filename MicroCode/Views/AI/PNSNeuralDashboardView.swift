//
//  PNSNeuralDashboardView.swift
//  MicroCode
//
//  Interactive macOS Command & Topology Console for PNS (Pseudo Neural System 24/7).
//  Visualizes Efferent MCP Nerve Tracts (MCP_1..xx), Somatic Motor Worktree Fibers (Agent_1..n),
//  Out-of-Process `pnsd` 24/7 Daemon Status, Hebbian Synaptic Myelination, and REM Consolidation.
//
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import SwiftUI
import AppKit

struct PNSNeuralDashboardView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var pns = PNSOrchestrator.shared
    @ObservedObject private var ganglion = PNSGanglionRouter.shared
    @ObservedObject private var motorPlexus = PNSMotorWorktreePlexus.shared

    @State private var missionObjective: String = ""
    @State private var verificationCommand: String = ""
    @State private var branchPolicy: PNSBranchSafetyPolicy = .isolatedWorktreeBranch
    @State private var isDispatching: Bool = false
    @State private var statusBanner: String? = nil

    private var activeWorkspacePath: String {
        appState.workspaceFolder?.path
            ?? AgentService.shared.currentWorkspace
            ?? FileManager.default.currentDirectoryPath
    }

    var body: some View {
        let snapshot = pns.buildStatusSnapshot()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerBar(snapshot: snapshot)

                if let banner = statusBanner {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .foregroundColor(.accentColor)
                        Text(banner)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Button("Dismiss") { statusBanner = nil }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.10))
                    .cornerRadius(7)
                }

                vitalMetricsGrid(snapshot: snapshot)

                marathonLauncherCard

                if !pns.missions.isEmpty {
                    activeMissionsSection
                }

                neuralPlexusSection(snapshot: snapshot)

                synapticPlasticityAndSpikesSection(snapshot: snapshot)
            }
            .padding(18)
        }
        .onAppear {
            PNSGanglionRouter.shared.syncManifestsFromExternalMCP()
            pns.refreshLaunchAgentStatus()
            Task { _ = await pns.pollRemoteDaemonOnce() }
        }
    }

    // MARK: - 1. Header & Daemon Controls

    private func headerBar(snapshot: PNSDaemonStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("PNS — Pseudo Neural System")
                            .font(.system(size: 15, weight: .bold))

                        HStack(spacing: 5) {
                            Circle()
                                .fill(snapshot.isOutOfProcessDaemon ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(snapshot.isOutOfProcessDaemon
                                 ? "pnsd 24/7 ONLINE (PID \(snapshot.daemonPID) • Survives App Quit)"
                                 : "In-Process Standby")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((snapshot.isOutOfProcessDaemon ? Color.green : Color.orange).opacity(0.14))
                        .cornerRadius(99)
                    }

                    Text("Biomimetic 24/7 Nerve-Tract Orchestrator for Massive MCP_1..xx & Isolated Git-Worktree Agent_1..n Swarms")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if snapshot.isOutOfProcessDaemon {
                    Button {
                        Task {
                            await pns.stopOutOfProcessDaemon()
                            statusBanner = "Stopped out-of-process microcode-pnsd daemon."
                        }
                    } label: {
                        Label("Stop pnsd", systemImage: "stop.circle")
                            .font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.12))
                            .foregroundColor(.red)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        Task {
                            let ok = await pns.ensureOutOfProcessDaemonRunning()
                            statusBanner = ok
                                ? "Booted detached 24/7 microcode-pnsd daemon (PID \(pns.remoteDaemonPID)). Safe to close MicroCode.app."
                                : "Could not bind localhost:18890 for out-of-process daemon."
                        }
                    } label: {
                        Label("Boot 24/7 pnsd", systemImage: "power.circle.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.18))
                            .foregroundColor(.accentColor)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Picker("Autonomic Mode", selection: $pns.autonomicMode) {
                    ForEach(PNSAutonomicMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 260)

                Toggle(isOn: Binding(
                    get: { pns.isLaunchAgentInstalled },
                    set: { enabled in
                        Task {
                            _ = await pns.setLaunchAgentEnabled(enabled)
                            statusBanner = enabled
                                ? "Installed macOS launchd KeepAlive agent (~/Library/LaunchAgents/com.dotmini.microcode.pnsd.plist)."
                                : "Removed macOS launchd KeepAlive agent."
                        }
                    }
                )) {
                    Text("launchd 24/7 Keep-Alive")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Spacer()

                Button {
                    Task {
                        let report = await pns.runREMConsolidationCycle(projectPath: activeWorkspacePath, missionId: nil)
                        statusBanner = report
                    }
                } label: {
                    Label("REM Consolidate", systemImage: "brain.head.profile")
                        .font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Distill episodic logs into Procedural Playbooks & prune Context Rot")

                Button {
                    let hib = ganglion.hibernateIdleMCPServers(idleThresholdSeconds: 0)
                    statusBanner = hib.isEmpty
                        ? "All stdio MCP servers are already hibernated or remote."
                        : "Hibernated \(hib.count) MCP server(s) to 0 MB RAM (manifests cached): \(hib.joined(separator: ", "))"
                } label: {
                    Label("Hibernate Idle MCPs", systemImage: "leaf.fill")
                        .font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.035))
        .cornerRadius(10)
    }

    // MARK: - 2. Vital Homeostasis Metrics

    private func vitalMetricsGrid(snapshot: PNSDaemonStatusSnapshot) -> some View {
        HStack(spacing: 10) {
            metricTile(
                title: "Metabolic Index (M_t)",
                value: String(format: "%.0f%%", snapshot.metabolicBudgetIndex * 100),
                subtitle: "\(snapshot.effectiveMode.rawValue) • Thermal: \(snapshot.thermalStateLabel)",
                icon: snapshot.effectiveMode.iconName,
                tint: snapshot.metabolicBudgetIndex > 0.6 ? .green : .orange
            )
            metricTile(
                title: "MCP Ganglion Filter",
                value: "\(snapshot.totalExternalMCPTools) → \(snapshot.activeMountedSynapticTools)",
                subtitle: "\(snapshot.totalExternalMCPServers) MCPs (\(snapshot.hibernatedMCPServers) hibernated 0MB)",
                icon: "network",
                tint: .blue
            )
            metricTile(
                title: "Synaptic Plasticity",
                value: "\(snapshot.myelinatedSynapsesCount) Myelinated",
                subtitle: "\(snapshot.proceduralPlaybooksCount) Playbooks • \(snapshot.inhibitedSynapsesCount) Inhibited",
                icon: "bolt.shield.fill",
                tint: .purple
            )
            metricTile(
                title: "Spinal Reflex & REM",
                value: "\(snapshot.spinalReflexSavesCount) Saves",
                subtitle: "<50ms 0-LLM • \(snapshot.remConsolidationCycles) REM Cycles",
                icon: "waveform.path.ecg",
                tint: .teal
            )
        }
    }

    private func metricTile(title: String, value: String, subtitle: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    // MARK: - 3. 24/7 Marathon Mission Dispatcher

    private var marathonLauncherCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Dispatch 24/7 Autonomous Marathon Mission", systemImage: "flag.checkered.2.crossed")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text("Workspace: \(URL(fileURLWithPath: activeWorkspacePath).lastPathComponent)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            TextField("Describe long-horizon 24/7 engineering mission (e.g. Audit modules, fix failing tests, add unit coverage across isolated worktrees)...", text: $missionObjective)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))

            HStack(spacing: 10) {
                Picker("Branch Policy", selection: $branchPolicy) {
                    ForEach(PNSBranchSafetyPolicy.allCases) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280)

                TextField("Optional Verify Cmd (e.g. swift test / cargo check)", text: $verificationCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))

                Button {
                    let trimmed = missionObjective.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !isDispatching else { return }
                    isDispatching = true
                    Task {
                        let verify = verificationCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                        let mission = await pns.dispatchMarathonMission(
                            objective: trimmed,
                            workspacePath: activeWorkspacePath,
                            branchPolicy: branchPolicy,
                            verificationCommand: verify.isEmpty ? nil : verify,
                            preferOutOfProcessDaemon: true
                        )
                        missionObjective = ""
                        isDispatching = false
                        statusBanner = "Dispatched 24/7 mission '\(mission.title)' (\(mission.id.prefix(8))) to PNS."
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isDispatching ? "hourglass" : "paperplane.fill")
                        Text(isDispatching ? "Dispatching..." : "Launch 24/7")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(missionObjective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.15) : Color.accentColor)
                    .foregroundColor(missionObjective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(missionObjective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDispatching)
            }
        }
        .padding(13)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(9)
    }

    // MARK: - 4. Active Marathon Missions

    private var activeMissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("24/7 Marathon Missions Ledger")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            ForEach(pns.missions.prefix(6)) { mission in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(mission.status.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(missionStatusColor(mission.status).opacity(0.16))
                            .foregroundColor(missionStatusColor(mission.status))
                            .cornerRadius(4)

                        Text(mission.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)

                        Spacer()

                        Text("\(Int(mission.progressFraction * 100))% • REM:\(mission.remConsolidationsCount) • Reflex:\(mission.spinalReflexSavesCount)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)

                        if mission.status == .running || mission.status == .consolidatingREM {
                            Button("Pause") {
                                Task { await pns.controlMission(missionId: mission.id, action: "pause") }
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.orange)
                        } else if mission.status == .paused {
                            Button("Resume") {
                                Task { await pns.controlMission(missionId: mission.id, action: "resume") }
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.green)
                        }

                        if mission.status == .running || mission.status == .paused || mission.status == .queued {
                            Button("Cancel") {
                                Task { await pns.controlMission(missionId: mission.id, action: "cancel") }
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.red)
                        }
                    }

                    ProgressView(value: mission.progressFraction)
                        .progressViewStyle(.linear)

                    if !mission.subtasks.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(mission.subtasks) { st in
                                HStack(spacing: 6) {
                                    Image(systemName: st.status == .completed ? "checkmark.circle.fill" : (st.status == .running ? "bolt.circle.fill" : (st.status == .failed ? "xmark.circle.fill" : "circle")))
                                        .font(.system(size: 10.5))
                                        .foregroundColor(missionStatusColor(st.status))
                                    Text("[\(st.assignedArchetype)] \(st.title)")
                                        .font(.system(size: 10.5, weight: .medium))
                                        .lineLimit(1)
                                    Spacer()
                                    if let branch = st.worktreeBranch {
                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(branch, forType: .string)
                                            statusBanner = "Copied verified worktree branch '\(branch)' to clipboard."
                                        } label: {
                                            Text(branch)
                                                .font(.system(size: 9.5, design: .monospaced))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.accentColor.opacity(0.12))
                                                .cornerRadius(4)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(11)
                .background(Color.primary.opacity(0.025))
                .cornerRadius(8)
            }
        }
    }

    private func missionStatusColor(_ status: PNSMissionStatus) -> Color {
        switch status {
        case .completed: return .green
        case .running, .consolidatingREM: return .accentColor
        case .paused, .pacingHomeostasis, .queued: return .orange
        case .failed, .cancelled: return .red
        }
    }

    // MARK: - 5. Specialized Nerve Tracts Topology (MCP_1..xx & Agent_1..n)

    private func neuralPlexusSection(snapshot: PNSDaemonStatusSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Left: Efferent MCP Nerve Tracts
            VStack(alignment: .leading, spacing: 8) {
                Label("Efferent MCP Nerve Tracts (MCP_1 ... MCP_xx)", systemImage: "cable.connector.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                ForEach(snapshot.tracts.filter { $0.tract.isMCPTract }) { t in
                    tractCard(t)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right: Somatic Motor Agent Tracts
            VStack(alignment: .leading, spacing: 8) {
                Label("Somatic Motor Agent Tracts (Agent_1 ... Agent_n)", systemImage: "person.3.sequence.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                ForEach(snapshot.tracts.filter { $0.tract.isMotorAgentTract }) { t in
                    tractCard(t)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tractCard(_ t: PNSTractTelemetry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: t.tract.iconName)
                    .font(.system(size: 11.5))
                    .foregroundColor(.accentColor)
                Text(t.tract.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text("Active:\(t.activeCount) • Idle:\(t.hibernatedCount) • Myelin:\(t.myelinatedEdgesCount)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            if t.attachedNodes.isEmpty {
                Text("No fibers attached yet — auto-mounts discovered MCPs on impulse")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.75))
            } else {
                Text(t.attachedNodes.joined(separator: "  •  "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(7)
    }

    // MARK: - 6. Synaptic Plasticity Table & Episodic Action-Potential Stream

    private func synapticPlasticityAndSpikesSection(snapshot: PNSDaemonStatusSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Top Hebbian Synapses
            VStack(alignment: .leading, spacing: 8) {
                Label("Hebbian Synaptic Weights & Myelination (W_e)", systemImage: "bolt.horizontal.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                let sortedEdges = pns.synapses.values.sorted { $0.weight > $1.weight }.prefix(8)
                if sortedEdges.isEmpty {
                    Text("Synaptic weights populate automatically as MCP tools and SubAgent fibers execute tasks.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .padding(10)
                } else {
                    ForEach(Array(sortedEdges)) { edge in
                        HStack(spacing: 8) {
                            Text(edge.isMyelinated ? "MYELIN" : (edge.isInhibited ? "INHIB" : "PLASTIC"))
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background((edge.isMyelinated ? Color.purple : (edge.isInhibited ? Color.red : Color.blue)).opacity(0.15))
                                .foregroundColor(edge.isMyelinated ? .purple : (edge.isInhibited ? .red : .blue))
                                .cornerRadius(4)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(edge.targetNodeId)
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .lineLimit(1)
                                Text("\(edge.taskCategory) • +\(edge.successCount)/-\(edge.failureCount) • \(edge.avgLatencyMs)ms")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.2f", edge.weight))
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.025))
                        .cornerRadius(6)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Recent Action Potential Spikes
            VStack(alignment: .leading, spacing: 8) {
                Label("Thalamic & Autonomic Spike Feed (WAL)", systemImage: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                if snapshot.recentSpikes.isEmpty {
                    Text("Waiting for sensory or motor action-potential spikes...")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .padding(10)
                } else {
                    ForEach(snapshot.recentSpikes.reversed().prefix(8)) { spike in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(spike.tract.shortBadge)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.accentColor)
                                Text(spike.kind.rawValue)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("S:\(String(format: "%.2f", spike.salience))")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Text(spike.summary)
                                .font(.system(size: 10.5))
                                .foregroundColor(spike.succeeded ? .primary : .red)
                                .lineLimit(2)
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.025))
                        .cornerRadius(6)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
