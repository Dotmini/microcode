//
//  RuntimeManagerView.swift
//  MicroCode
//
//  UI for managing runtime downloads
//  Copyright © 2025 Dotmini Company Limited. All rights reserved.
//

import SwiftUI

struct RuntimeManagerView: View {
    @StateObject private var manager = RuntimeManager.shared
    @State private var showingError = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Runtime List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ArcToolchainCard(updater: ArcToolchainUpdater.shared)
                    ForEach(manager.runtimes) { runtime in
                        RuntimeCard(runtime: runtime, onInstall: {
                            manager.install(runtime.type)
                        })
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 550, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Installation Note", isPresented: $showingError) {
            Button("OK") { manager.errorMessage = nil }
        } message: {
            Text(manager.errorMessage ?? "")
        }
        .onChange(of: manager.errorMessage) { newValue in
            showingError = newValue != nil
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Runtime Manager")
                    .font(.title2.bold())
                Text("Install language runtimes for code execution")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                for type in [RuntimeType.python, .nodejs, .bun, .go, .java, .c, .cpp] {
                    if let status = manager.runtimes.first(where: { $0.type == type }), !status.isInstalled, !status.isDownloading {
                        manager.install(type)
                    }
                }
            } label: {
                Label("Install Core Pack", systemImage: "shippingbox.and.arrow.backward.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(manager.isDetecting)
            
            Button {
                manager.detectAll(force: true)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(manager.isDetecting)
        }
        .padding()
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Architecture: \(ProcessInfo.processInfo.machineArchitecture)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let lastDetection = manager.lastDetectionDate {
                    Text("Last scan: \(lastDetection.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Text("Install dir: ~/Library/Application Support/MicroCode/Runtimes")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            Spacer()
            
            Button {
                NSWorkspace.shared.open(manager.runtimesDir)
            } label: {
                Label("Open Folder", systemImage: "folder")
                    .font(.caption)
            }
        }
        .padding()
    }
}

// MARK: - Runtime Card

struct RuntimeCard: View {
    @ObservedObject var runtime: RuntimeStatus
    let onInstall: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Text(runtime.type.icon)
                .font(.system(size: 32))
                .frame(width: 50, height: 50)
                .background(runtime.type.color.opacity(0.2))
                .cornerRadius(12)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(runtime.type.rawValue)
                        .font(.headline)
                    
                    if runtime.isInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                
                if runtime.isInstalled {
                    if let version = runtime.version {
                        Text("v\(version)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let path = runtime.path {
                        Text(path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else if runtime.isDownloading {
                    Text(runtime.statusMessage)
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    if let info = runtime.type.getDownloadInfo() {
                        Text("Not installed • \(info.size)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text("Built into macOS")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Action
            if runtime.isDownloading {
                VStack(spacing: 4) {
                    ProgressView(value: runtime.downloadProgress)
                        .frame(width: 80)
                    Text("\(Int(runtime.downloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if runtime.isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            } else if runtime.type.getDownloadInfo() != nil {
                Button(action: onInstall) {
                    Label("Install", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("✓")
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Arc Toolchain Card

/// Arc (formerly Ardium) toolchain: what is installed, where updates come from, and the update state.
struct ArcToolchainCard: View {
    @ObservedObject var updater: ArcToolchainUpdater
    @State private var toolchain = ArcToolchain.shared.statusDescription

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 50, height: 50)
                .background(Color.accentColor.opacity(0.15))
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text("Arc")
                    .font(.headline)
                Text(toolchain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(updater.sourcePath.map { "Source: \($0)" } ?? "Source: Arc repo not found")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(updater.statusText)
                    .font(.caption)
                    .foregroundColor(statusColor)
                    .lineLimit(2)
                if let last = updater.lastChecked {
                    Text("Last checked: \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    if updater.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Check Now") {
                        Task { await updater.check(manual: true) }
                    }
                    .disabled(updater.isBusy)
                }
                Button("Choose Source…", action: chooseSource)
                    .disabled(updater.isBusy)
                Toggle("Auto-update", isOn: $updater.autoUpdate)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .font(.caption)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .onReceive(updater.$status) { _ in
            toolchain = ArcToolchain.shared.statusDescription
        }
    }

    private var statusColor: Color {
        switch updater.status {
        case .failed, .noSource: return .orange
        case .installed: return .green
        default: return .secondary
        }
    }

    private func chooseSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the Arc source repository (the folder with VERSION, Makefile and src/compiler)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        updater.setSourceRepo(url.path)
        Task { await updater.check(manual: true) }
    }
}
