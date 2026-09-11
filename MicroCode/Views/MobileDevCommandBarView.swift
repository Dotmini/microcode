//
//  MobileDevCommandBarView.swift
//  MicroCode
//
//  Mobile Dev Command Bar & Noise-Canceling Log Console.
//  Integrated directly into the Embedded Device Canvas.
//  Features:
//  - One-Click Push Notification Mocker
//  - Deep Link & Universal Link Launcher
//  - GPS Location Simulator with Global Presets
//  - Shake Gesture & Dark/Light Mode Switcher
//  - Integrated Noise-Canceling Log Console & One-Click Crash Healer
//
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import SwiftUI

struct MobileDevCommandBarView: View {
    @ObservedObject var commandService = DeviceCommandBarService.shared
    @ObservedObject var logService = NoiseCancelingLogService.shared
    @ObservedObject var deviceRuntime = DeviceRuntimeService.shared
    
    @State private var showingPushSheet = false
    @State private var showingLocationPopover = false
    @State private var showingDeepLinkPopover = false
    @State private var showingLogDrawer = false
    @State private var showingAssetMatrixSheet = false
    @State private var showingStoreLifecycleSheet = false
    
    var isAndroid: Bool {
        !deviceRuntime.showingEmbeddedAppleDock
    }
    
    var activeDeviceUDID: String? {
        deviceRuntime.selectedDeviceID
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Command Bar Strip (Dark Theme, Sleek Horizontal Scrolling Pills)
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // 1. Push Notification Mocker
                        Button {
                            showingPushSheet.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bell.badge")
                                Text("Push")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color(white: 0.15))
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingPushSheet) {
                            PushNotificationMockSheet(
                                isAndroid: isAndroid,
                                targetUDID: activeDeviceUDID,
                                bundleId: deviceRuntime.project?.displayName ?? "com.example.app"
                            )
                        }
                        
                        // 2. Deep Link Launcher
                        Button {
                            showingDeepLinkPopover.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                Text("Link")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color(white: 0.15))
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingDeepLinkPopover) {
                            DeepLinkLauncherPopover(
                                isAndroid: isAndroid,
                                targetUDID: activeDeviceUDID
                            )
                        }
                        
                        // 3. Asset Matrix & Manifest Sync
                        Button {
                            showingAssetMatrixSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.grid.3x3.square")
                                Text("Assets")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color(white: 0.15))
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showingAssetMatrixSheet) {
                            AssetMatrixModalView()
                        }
                        
                        // 4. Store & Signing Engine
                        Button {
                            showingStoreLifecycleSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "shippingbox")
                                Text("Store")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color(white: 0.15))
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showingStoreLifecycleSheet) {
                            StoreLifecycleModalView()
                        }
                        
                        // 5. Location / GPS Presets
                        Button {
                            showingLocationPopover.toggle()
                        } label: {
                            HStack(spacing: 3) {
                                Text(commandService.currentLocationPreset.flag)
                                Text(commandService.currentLocationPreset.name)
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color(white: 0.15))
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingLocationPopover) {
                            LocationPresetsPopover(
                                isAndroid: isAndroid,
                                targetUDID: activeDeviceUDID
                            )
                        }
                        
                        // 6. Shake Gesture
                        Button {
                            Task {
                                await commandService.triggerShake(targetUDID: activeDeviceUDID, isAndroid: isAndroid)
                            }
                        } label: {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color(white: 0.15))
                                .cornerRadius(5)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("Simulate Shake Gesture")
                        
                        // 7. Dark / Light Mode Switcher
                        Button {
                            Task {
                                await commandService.toggleAppearance(targetUDID: activeDeviceUDID, isAndroid: isAndroid)
                            }
                        } label: {
                            Image(systemName: commandService.isDarkMode ? "moon.fill" : "sun.max.fill")
                                .font(.system(size: 10))
                                .foregroundColor(commandService.isDarkMode ? .indigo : .orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color(white: 0.15))
                                .cornerRadius(5)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("Toggle Dark / Light Appearance")
                        
                        // 8. Noise-Canceling Log Toggle
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingLogDrawer.toggle()
                                if showingLogDrawer && !logService.isStreaming {
                                    logService.startStreaming(
                                        targetUDID: activeDeviceUDID,
                                        bundleId: deviceRuntime.project?.displayName ?? "com.example.app",
                                        isAndroid: isAndroid
                                    )
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "waveform.badge.magnifyingglass")
                                Text(showingLogDrawer ? "Hide Logs" : "Logs")
                                if logService.latestCrash != nil {
                                    Circle().fill(Color.red).frame(width: 5, height: 5)
                                }
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(showingLogDrawer ? .accentColor : .white.opacity(0.9))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(showingLogDrawer ? Color.accentColor.opacity(0.25) : Color(white: 0.15))
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 2)
                }
                
                // Status Feedback Toast
                if let result = commandService.lastActionResult {
                    Text(result)
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .transition(.opacity)
                }
                
                // Close / Dismiss Drawer Button
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        deviceRuntime.showingMobileDevTools = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close Dev Tools Strip")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(white: 0.08))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.08)), alignment: .bottom)
            
            // Noise-Canceling Log Drawer (Expandable)
            if showingLogDrawer {
                Divider()
                NoiseCancelingLogDrawer(isAndroid: isAndroid, targetUDID: activeDeviceUDID)
                    .frame(height: 180)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Subviews & Popovers

private struct PushNotificationMockSheet: View {
    @ObservedObject var service = DeviceCommandBarService.shared
    let isAndroid: Bool
    let targetUDID: String?
    let bundleId: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(.accentColor)
                Text("Mock Push Notification (\(isAndroid ? "Android" : "iOS"))")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Title").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                TextField("Push Title", text: $service.pushTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Body").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                TextField("Push Body Message", text: $service.pushBody)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }
            
            HStack {
                Text("Badge Count").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                Stepper("\(service.pushBadge)", value: $service.pushBadge, in: 0...99)
                    .controlSize(.small)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom JSON Payload").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                TextEditor(text: $service.pushCustomPayload)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
            }
            
            HStack {
                Spacer()
                Button("Send Mock Push") {
                    Task {
                        await service.sendMockPush(
                            targetUDID: targetUDID,
                            bundleId: bundleId,
                            isAndroid: isAndroid
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

private struct DeepLinkLauncherPopover: View {
    @ObservedObject var service = DeviceCommandBarService.shared
    let isAndroid: Bool
    let targetUDID: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.accentColor)
                Text("Deep Link & Universal Link")
                    .font(.system(size: 12, weight: .semibold))
            }
            
            TextField("e.g. myapp://settings/profile?id=42", text: $service.deepLinkURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            
            HStack {
                Button("myapp://home") {
                    service.deepLinkURL = "myapp://home"
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                
                Button("myapp://profile") {
                    service.deepLinkURL = "myapp://profile"
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                
                Spacer()
                
                Button("Launch") {
                    Task {
                        await service.launchDeepLink(targetUDID: targetUDID, isAndroid: isAndroid)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}

private struct LocationPresetsPopover: View {
    @ObservedObject var service = DeviceCommandBarService.shared
    let isAndroid: Bool
    let targetUDID: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GPS Location Presets")
                .font(.system(size: 12, weight: .semibold))
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(LocationPreset.presets) { preset in
                    Button {
                        Task {
                            await service.selectLocationPreset(preset, targetUDID: targetUDID, isAndroid: isAndroid)
                        }
                    } label: {
                        HStack {
                            Text(preset.flag)
                            Text(preset.name).font(.system(size: 11))
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(service.currentLocationPreset.name == preset.name ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lat: \(String(format: "%.4f", service.customLatitude))")
                    Text("Lng: \(String(format: "%.4f", service.customLongitude))")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Apply GPS") {
                    Task {
                        await service.applyLocation(targetUDID: targetUDID, isAndroid: isAndroid)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}

private struct NoiseCancelingLogDrawer: View {
    @ObservedObject var logService = NoiseCancelingLogService.shared
    let isAndroid: Bool
    let targetUDID: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Channel Header Bar
            HStack(spacing: 6) {
                ForEach(LogChannel.allCases) { channel in
                    Button {
                        logService.selectedChannel = channel
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: channel.icon)
                            Text(channel.rawValue)
                        }
                        .font(.system(size: 10, weight: logService.selectedChannel == channel ? .semibold : .regular))
                        .foregroundColor(logService.selectedChannel == channel ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(logService.selectedChannel == channel ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                TextField("Filter logs…", text: $logService.searchFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .controlSize(.mini)
                
                Button {
                    logService.clearLogs()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("Clear logs")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Crash Alert Banner if detected
            if let crash = logService.latestCrash {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(crash.reason)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                        Text("Suggested Fix: \(crash.suggestedFix)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Apply Agent Fix") {
                        // In future phase, sends patch to AppState / file editor
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                .padding(6)
                .background(Color.red.opacity(0.1))
            }
            
            Divider()
            
            // Log Stream Table
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if logService.displayedLogs.isEmpty {
                        Text("No logs captured. Run the app on the simulator to inspect output.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(12)
                    } else {
                        ForEach(logService.displayedLogs) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Text(item.formattedTime)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 65, alignment: .leading)
                                
                                if let file = item.sourceFile, let line = item.lineNumber {
                                    Text("\(file):\(line)")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                }
                                
                                Text(item.message)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(item.isCrash ? .red : (item.channel == .errors ? .orange : .primary))
                                    .textSelection(.enabled)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        }
    }
}
