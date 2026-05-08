//
//  RuntimeManagerView.swift
//  CodeTunner
//
//  UI for managing runtime downloads
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
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
                manager.detectAll()
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
                
                Text("Install dir: ~/Library/Application Support/CodeTunner/Runtimes")
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
