//
//  CacheSettingsView.swift
//  MicroCode
//
//  Created by Antigravity on 2026-06-15.
//

import SwiftUI

struct CacheSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var isCleaning = false
    @State private var customPattern = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.title2)
                    .foregroundStyle(LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build Cache & DerivedData")
                        .font(.system(size: 15, weight: .bold))
                    Text("Manage Xcode build artifacts and free up hard disk space.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 8)
            
            // Statistics Card (Glassmorphic look)
            VStack(spacing: 16) {
                HStack(spacing: 24) {
                    // Size Stat
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TOTAL SIZE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        if appState.isCheckingCache {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(height: 32)
                        } else {
                            Text(formatBytes(appState.derivedDataInfo?.size_bytes ?? 0))
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundStyle(LinearGradient(colors: [.primary, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                    
                    Divider()
                        .frame(height: 40)
                    
                    // Folder Count Stat
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PROJECT CACHES")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Text("\(appState.derivedDataInfo?.folder_count ?? 0)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    }
                    
                    Spacer()
                    
                    // Refresh Button
                    Button(action: {
                        appState.checkDerivedDataSize()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Recalculate DerivedData size")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                )
                
                // Path display
                HStack {
                    Image(systemName: "folder")
                        .foregroundColor(.secondary)
                    Text(appState.derivedDataInfo?.path ?? "~/Library/Developer/Xcode/DerivedData")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    Button(action: {
                        let path = appState.derivedDataInfo?.path ?? ""
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(path, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy Path")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.04))
                .cornerRadius(8)
            }
            
            Divider()
            
            // Quota Limits Card
            VStack(alignment: .leading, spacing: 14) {
                Text("Smart Quota Controls")
                    .font(.system(size: 13, weight: .bold))
                
                HStack {
                    Text("DerivedData Quota Limit")
                    Spacer()
                    Picker("", selection: $appState.derivedDataQuotaLimitGB) {
                        Text("5 GB").tag(5.0)
                        Text("10 GB").tag(10.0)
                        Text("20 GB").tag(20.0)
                        Text("50 GB").tag(50.0)
                        Text("Unlimited").tag(0.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .onChange(of: appState.derivedDataQuotaLimitGB) { _ in
                        appState.saveSettings()
                    }
                }
                
                // Toggle options
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show alert notification when quota exceeded", isOn: $appState.enableDerivedDataAlert)
                        .onChange(of: appState.enableDerivedDataAlert) { _ in
                            appState.saveSettings()
                        }
                    
                    Toggle("Automatically purge DerivedData when quota exceeded", isOn: $appState.enableDerivedDataAutoPurge)
                        .onChange(of: appState.enableDerivedDataAutoPurge) { _ in
                            appState.saveSettings()
                        }
                        .foregroundColor(appState.enableDerivedDataAutoPurge ? .orange : .primary)
                }
                .padding(.leading, 4)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                    )
            )
            
            Divider()
            
            // Clean Operations Panel
            VStack(alignment: .leading, spacing: 12) {
                Text("Clean Operations")
                    .font(.system(size: 13, weight: .bold))
                
                HStack(spacing: 12) {
                    // Global Clean Button
                    Button(action: {
                        cleanCaches(pattern: nil)
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Clean All DerivedData")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isCleaning)
                    
                    // Project Specific clean if active workspace exists
                    if let workspace = appState.workspaceFolder {
                        let projName = workspace.lastPathComponent
                        Button(action: {
                            cleanCaches(pattern: projName)
                        }) {
                            HStack {
                                Image(systemName: "folder.badge.minus")
                                Text("Clean '\(projName)' Caches")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCleaning)
                    }
                }
                
                // Custom Pattern Clean option
                HStack {
                    TextField("Enter custom project prefix pattern to clean...", text: $customPattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    
                    Button("Clean Matching") {
                        cleanCaches(pattern: customPattern)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCleaning || customPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            appState.checkDerivedDataSize()
        }
    }
    
    private func cleanCaches(pattern: String?) {
        isCleaning = true
        appState.clearDerivedData(projectPattern: pattern)
        
        // Wait a short time to simulate cleaning animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isCleaning = false
            self.customPattern = ""
        }
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0.00 GB" }
        let gigabytes = Double(bytes) / 1_000_000_000.0
        return String(format: "%.2f GB", gigabytes)
    }
}
