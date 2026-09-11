//
//  DeviceRuntimeView.swift
//  MicroCode
//

import SwiftUI

/// Controls real local simulators/emulators. Android is rendered from a real
/// ADB device inside MicroCode; Apple simulators use a native IOSurface path.
struct DeviceRuntimeView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var runtime = DeviceRuntimeService.shared
    @Environment(\.dismiss) private var dismiss
    /// The host puts the real device surface beside Chat after selection.
    var onEmbeddedAndroidOpened: (() -> Void)? = nil
    /// Apple Simulator is presented in the same dock; physical Apple devices
    /// remain physical-only.
    var onEmbeddedAppleSimulatorOpened: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    projectCard
                    deviceCard
                    // The Agent host owns the dock.  This fallback only keeps
                    // the device reachable when Device & Run is opened from
                    // the code-editor toolbar, where no Chat dock exists.
                    if onEmbeddedAndroidOpened == nil && runtime.isEmbeddedAndroidActive {
                        embeddedAndroidCard
                    }
                    agentPermissionCard
                    if !runtime.output.isEmpty { outputCard }
                }
                .padding(20)
            }
        }
        .frame(
            width: onEmbeddedAndroidOpened == nil && runtime.isEmbeddedAndroidActive ? 1_050 : 720,
            height: onEmbeddedAndroidOpened == nil && runtime.isEmbeddedAndroidActive ? 720 : 620
        )
        .task(id: appState.workspaceFolder?.path) {
            await runtime.refresh(workspace: appState.workspaceFolder)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Device & Run").font(.system(size: 18, weight: .semibold))
                Text("Choose an iPhone, iPad, Apple Watch, Apple TV, Android runtime, or paired Apple device. Interactive previews open beside Chat.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button { Task { await runtime.refresh(workspace: appState.workspaceFolder) } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.bordered).disabled(runtime.isWorking)
            Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(18)
    }

    private var projectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Run configuration", systemImage: "hammer")
                .font(.system(size: 13, weight: .semibold))
            if let project = runtime.project {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.runtime.rawValue).font(.system(size: 14, weight: .medium))
                        Text(project.root.path).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(project.runtime == .unknown ? "Not supported" : "Ready")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(project.runtime == .unknown ? .orange : .green)
                }
                if project.runtime == .xcode, !runtime.buildSchemes.isEmpty {
                    HStack(spacing: 8) {
                        Label("Scheme", systemImage: "shippingbox")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        Picker("Scheme", selection: $runtime.selectedScheme) {
                            ForEach(runtime.buildSchemes, id: \.self) { scheme in
                                Text(scheme).tag(Optional(scheme))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .padding(.top, 2)
                } else if project.runtime == .xcode {
                    Text("No shared Xcode scheme found. In Xcode, enable Product → Scheme → Manage Schemes → Shared.")
                        .font(.system(size: 10)).foregroundColor(.orange)
                }
            } else {
                Text("Open a project first.").font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
        .panelCard()
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Destination", systemImage: "iphone.gen3")
                .font(.system(size: 13, weight: .semibold))
            Text(runtime.statusMessage).font(.system(size: 11)).foregroundColor(.secondary)
            if runtime.devices.isEmpty {
                Text("Install the required Xcode Simulator runtime (iPhone, iPad, Watch, or TV), pair physical devices in Xcode Device Hub, or install Android Studio with an AVD. Then refresh.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                Picker("Run destination", selection: $runtime.selectedDeviceID) {
                    ForEach(runtime.devices) { device in
                        Label("\(device.name) — \(device.detail)", systemImage: device.displaySymbolName)
                            .tag(Optional(device.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                if let selected = runtime.devices.first(where: { $0.id == runtime.selectedDeviceID }),
                   let preflight = selected.preflightMessage {
                    Label(preflight, systemImage: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    let selectedIsReady = runtime.devices.first(where: { $0.id == runtime.selectedDeviceID })?.isReadyForLaunch ?? false
                    let selectedPlatform = runtime.devices.first(where: { $0.id == runtime.selectedDeviceID })?.platform
                    Button(deviceActionTitle(for: selectedPlatform)) {
                        Task {
                            if selectedPlatform == .android {
                                await runtime.startEmbeddedAndroid()
                                guard runtime.isEmbeddedAndroidActive else { return }
                                onEmbeddedAndroidOpened?()
                                if onEmbeddedAndroidOpened != nil { dismiss() }
                            } else if let selected = runtime.devices.first(where: { $0.id == runtime.selectedDeviceID }), selected.isAppleSimulator {
                                await runtime.startEmbeddedAppleSimulator()
                                guard runtime.isEmbeddedApplePreviewActive else { return }
                                onEmbeddedAppleSimulatorOpened?()
                                if onEmbeddedAppleSimulatorOpened != nil { dismiss() }
                            } else {
                                await runtime.startSelectedDevice()
                            }
                        }
                    }
                        .buttonStyle(.bordered)
                        .disabled(runtime.selectedDeviceID == nil || runtime.isWorking || !selectedIsReady)
                    Button("Build & Run") {
                        Task {
                            await runtime.runSelectedProject()
                            if selectedPlatform == .android, runtime.isEmbeddedAndroidActive {
                                onEmbeddedAndroidOpened?()
                                if onEmbeddedAndroidOpened != nil { dismiss() }
                            } else if let selected = runtime.devices.first(where: { $0.id == runtime.selectedDeviceID }),
                                      selected.isAppleSimulator,
                                      runtime.isEmbeddedApplePreviewActive {
                                onEmbeddedAppleSimulatorOpened?()
                                if onEmbeddedAppleSimulatorOpened != nil { dismiss() }
                            }
                        }
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(runtime.project?.runtime == .unknown || runtime.selectedDeviceID == nil || runtime.isWorking || !selectedIsReady || (runtime.project?.runtime == .xcode && runtime.buildSchemes.isEmpty))
                    if runtime.isWorking { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Stop") { runtime.stopActiveRuntime() }
                        .buttonStyle(.bordered)
                }
                Text("Preview supports iPhone, iPad, Apple Watch, and Apple TV simulators beside Chat. Build & Run uses the selected real destination; Flutter/React Native are limited to iPhone and iPad.")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
        .panelCard()
    }

    private func deviceActionTitle(for platform: DeviceRuntimePlatform?) -> String {
        guard let selected = runtime.devices.first(where: { $0.id == runtime.selectedDeviceID }) else { return "Start" }
        if platform == .android { return "Preview" }
        if selected.isPhysicalAppleDevice { return "Use Device" }
        if selected.isAppleSimulator { return "Start \(selected.previewTitle)" }
        return "Start"
    }

    private var agentPermissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Allow Agent to launch and deploy", isOn: $runtime.allowAgentDeviceControl)
                .font(.system(size: 12, weight: .medium))
            Text("Off by default. When on, the Agent may use the selected structured device tool to start a runtime or run the current project. It cannot create, wipe, or delete simulators/AVDs.")
                .font(.system(size: 10)).foregroundColor(.secondary)
        }
        .panelCard()
    }

    private var embeddedAndroidCard: some View {
        EmbeddedAndroidDeviceView(runtime: runtime)
            .frame(minHeight: 520)
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Build output", systemImage: "terminal")
                .font(.system(size: 12, weight: .semibold))
            ScrollView {
                Text(runtime.output).font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .frame(maxHeight: 150)
            .background(Color.primary.opacity(0.035)).cornerRadius(5)
        }
        .panelCard()
    }
}

private extension View {
    func panelCard() -> some View {
        padding(14)
            .background(Color.primary.opacity(0.035))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.16)))
            .cornerRadius(7)
    }
}
