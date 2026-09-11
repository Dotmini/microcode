//
//  StoreLifecycleModalView.swift
//  MicroCode
//
//  One-Click Store Distribution, Keystore & Pre-Flight Inspector.
//  Zero-Xcode Organizer & Zero-Google Play Console Manual Overhead.
//
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import SwiftUI

struct StoreLifecycleModalView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var storeService = StoreLifecycleService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    @State private var keystoreAlias = "release_key"
    @State private var keystorePassword = "Password1234!"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("Store Distribution & Signing Engine")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(.regularMaterial)
            
            // Mode Tabs
            Picker("", selection: $selectedTab) {
                Text("1. Pre-Flight Inspector").tag(0)
                Text("2. Android Keystore").tag(1)
                Text("3. TestFlight & Play Upload").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            
            Divider()
            
            // Content
            if selectedTab == 0 {
                preFlightTab
            } else if selectedTab == 1 {
                androidKeystoreTab
            } else {
                storeUploadTab
            }
            
            Divider()
            
            // Bottom Action Footer
            HStack {
                if !storeService.deploymentStatus.isEmpty {
                    Text(storeService.deploymentStatus)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if selectedTab == 0 {
                    Button("Run Pre-Flight Audit") {
                        guard let root = appState.workspaceFolder else { return }
                        Task {
                            await storeService.runPreFlightInspection(projectRootURL: root)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else if selectedTab == 1 {
                    Button("Generate Keystore (.jks)") {
                        guard let root = appState.workspaceFolder else { return }
                        Task {
                            try? await storeService.createReleaseKeystore(
                                alias: keystoreAlias,
                                password: keystorePassword,
                                projectRootURL: root
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(storeService.isGeneratingKeystore)
                } else {
                    Button("Upload to TestFlight") {
                        Task {
                            await storeService.uploadIOSTestFlight(ipaPath: "")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!storeService.isAllPreFlightPassed)
                }
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 600, height: 480)
    }
    
    // MARK: - Tab 1: Pre-Flight Inspector
    
    private var preFlightTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Verify all App Store & Google Play compliance requirements before building production binaries.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            if storeService.preFlightResults.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checklist")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Click 'Run Pre-Flight Audit' below to inspect the project.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(storeService.preFlightResults) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: item.isPassed ? "checkmark.circle.fill" : (item.isWarning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill"))
                                    .font(.system(size: 14))
                                    .foregroundColor(item.isPassed ? .green : (item.isWarning ? .orange : .red))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(item.detail)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding(14)
    }
    
    // MARK: - Tab 2: Android Keystore Manager
    
    private var androidKeystoreTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create a production Java Keystore (.jks) for Google Play release signing. Fingerprints are automatically computed for Firebase & Google Sign-In.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Key Alias").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                    TextField("Alias", text: $keystoreAlias)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Password").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                    SecureField("Password", text: $keystorePassword)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
            }
            
            if let ks = storeService.generatedKeystore {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Generated Release Fingerprints:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SHA-1 (Firebase / Google OAuth):")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        HStack {
                            Text(ks.sha1)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(ks.sha1, forType: .string)
                            }
                            .controlSize(.mini)
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SHA-256:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        HStack {
                            Text(ks.sha256)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(ks.sha256, forType: .string)
                            }
                            .controlSize(.mini)
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                }
            }
            
            Spacer()
        }
        .padding(14)
    }
    
    // MARK: - Tab 3: Store Upload
    
    private var storeUploadTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Direct Store Submission Pipeline. Uploads .ipa directly to TestFlight and .aab to Google Play Internal Testing.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("App Store Connect API Key").font(.system(size: 11, weight: .semibold))
                HStack(spacing: 8) {
                    TextField("Issuer ID (UUID)", text: $storeService.appleIssuerID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    TextField("Key ID (10 chars)", text: $storeService.appleKeyID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(8)
            
            if !storeService.deploymentLog.isEmpty {
                Text("Deployment Log:")
                    .font(.system(size: 10, weight: .bold))
                ScrollView {
                    Text(storeService.deploymentLog)
                        .font(.system(size: 9, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(height: 120)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
            }
            
            Spacer()
        }
        .padding(14)
    }
}
