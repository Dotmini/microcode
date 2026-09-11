//
//  AssetMatrixModalView.swift
//  MicroCode
//
//  Autonomous Asset, Icon & Manifest Matrix Control Panel.
//  Zero-Xcode & Zero-Android Studio Asset and Permission Management.
//
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import SwiftUI

struct AssetMatrixModalView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var assetService = AssetMatrixService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    @State private var droppedImage: NSImage?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "square.grid.3x3.square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("Autonomous Asset & Permission Matrix")
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
                Text("App Icons (Single-Asset)").tag(0)
                Text("Permissions & Manifest Sync").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            
            Divider()
            
            // Content
            if selectedTab == 0 {
                singleAssetIconTab
            } else {
                permissionsMatrixTab
            }
            
            Divider()
            
            // Bottom Action Footer
            HStack {
                if !assetService.statusMessage.isEmpty {
                    Text(assetService.statusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if selectedTab == 0 {
                    Button("Generate All Icons") {
                        guard let img = droppedImage, let root = appState.workspaceFolder else { return }
                        Task {
                            try? await assetService.generateAppIcons(from: img, projectRootURL: root)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(droppedImage == nil || assetService.isGenerating)
                } else {
                    Button("Sync Info.plist & Manifest") {
                        guard let root = appState.workspaceFolder else { return }
                        Task {
                            try? await assetService.syncPermissionsToProject(projectRootURL: root)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 580, height: 460)
    }
    
    // MARK: - Tab 1: Single-Asset Icon
    
    private var singleAssetIconTab: some View {
        VStack(spacing: 16) {
            Text("Drop a single 1024x1024 SVG or PNG image. MicroCode will automatically generate all iOS (1x, 2x, 3x) and Android (Adaptive Mipmap) icon files.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundColor(droppedImage != nil ? Color.accentColor : Color.secondary.opacity(0.4))
                    .background(Color.primary.opacity(0.02))
                
                if let image = droppedImage {
                    VStack(spacing: 8) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .cornerRadius(18)
                            .shadow(radius: 4)
                        Text("Ready to Generate")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("Drag and Drop Master Icon (1024x1024)")
                            .font(.system(size: 12, weight: .medium))
                        Button("Choose Image File…") {
                            chooseImageFile()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .frame(height: 190)
            
            // Output Breakdown Pills
            HStack(spacing: 12) {
                Label("iOS: Assets.xcassets (12 sizes)", systemImage: "applelogo")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Label("Android: mipmap mdpi-xxxhdpi + XML", systemImage: "apps.iphone")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            if assetService.isGenerating {
                ProgressView(value: assetService.generationProgress)
                    .progressViewStyle(.linear)
            }
            
            Spacer()
        }
        .padding(16)
    }
    
    // MARK: - Tab 2: Permissions Matrix
    
    private var permissionsMatrixTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Select the capabilities your app requires. MicroCode syncs Info.plist, AndroidManifest.xml, and PrivacyInfo.xcprivacy with human interface compliant rationales.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                ForEach(AppPermissionItem.standardPermissions) { item in
                    let isEnabled = assetService.enabledPermissionIDs.contains(item.id)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Toggle(isOn: Binding(
                                get: { isEnabled },
                                set: { val in
                                    if val {
                                        assetService.enabledPermissionIDs.insert(item.id)
                                    } else {
                                        assetService.enabledPermissionIDs.remove(item.id)
                                    }
                                }
                            )) {
                                HStack(spacing: 6) {
                                    Image(systemName: item.icon)
                                        .foregroundColor(.accentColor)
                                        .frame(width: 16)
                                    Text(item.name)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("(\(item.category))")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            
                            Spacer()
                            
                            Text(item.iosKey)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        if isEnabled {
                            TextField("AI App Store Review Rationale (Thai/English)", text: Binding(
                                get: { assetService.permissionRationales[item.id] ?? item.defaultRationaleTh },
                                set: { assetService.permissionRationales[item.id] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 10))
                            .padding(.leading, 24)
                        }
                    }
                    .padding(8)
                    .background(isEnabled ? Color.accentColor.opacity(0.06) : Color.clear)
                    .cornerRadius(6)
                }
            }
            .padding(14)
        }
    }
    
    private func chooseImageFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .svg]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            droppedImage = image
        }
    }
}
