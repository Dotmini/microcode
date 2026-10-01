//
//  GoogleColabSheetView.swift
//  MicroCode
//
//  Google Colab Cloud Compute Management Sheet for Cell Mode.
//  Workstation-grade Apple HIG interface for Colab GPU allocation and kernel telemetry.
//  Strictly monochrome (Black & White) matching MicroCode's native theme engine.
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import SwiftUI
import AppKit
import Combine

struct GoogleColabSheetView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var colab = GoogleColabService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var sessionLinkInput: String = ""
    @State private var isConnecting: Bool = false
    @State private var hasCopiedCode: Bool = false
    @State private var showDiagnostics: Bool = false
    @State private var autoDetectedBanner: String? = nil
    @State private var lastProcessedClipboard: String = ""
    
    // Continuous clipboard listener while sheet is open (0.6s interval in .common RunLoop mode)
    private let clipboardCheckTimer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()
    
    // Theme-Aware Dynamic Colors (Apple HIG Monochrome)
    private var windowBackground: Color {
        appState.appTheme.isGlass ? Color.clear : Color(nsColor: .windowBackgroundColor)
    }
    
    private var cardBackground: Color {
        if appState.appTheme.isGlass {
            return Color.white.opacity(appState.appTheme.isDark ? 0.08 : 0.4)
        }
        return Color(nsColor: .controlBackgroundColor)
    }
    
    private var subtleBorderColor: Color {
        Color.primary.opacity(appState.appTheme.isDark ? 0.12 : 0.08)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerView
            
            Divider()
                .opacity(0.4)
            
            // MARK: - Content
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if colab.status.isConnected {
                        connectedStateView
                    } else {
                        oneClickSetupView
                    }
                    
                    // Telemetry Tiles
                    hardwareTelemetryView
                    
                    // Anti-Idle & Options
                    keepAliveSection
                    
                    // Diagnostics Console (Collapsible)
                    diagnosticsSection
                }
                .padding(14)
            }
        }
        .frame(width: 440)
        .background(windowBackground)
        .onAppear {
            self.sessionLinkInput = colab.jupyterEndpoint
            if !colab.status.isConnected {
                colab.checkAndConnectFromClipboardIfValid()
            }
        }
        .onReceive(clipboardCheckTimer) { _ in
            guard !colab.status.isConnected && !colab.status.isConnecting else { return }
            guard let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !clip.isEmpty, clip != lastProcessedClipboard else { return }
            
            if let parsed = GoogleColabService.parseColabEndpointAndToken(from: clip) {
                lastProcessedClipboard = clip
                sessionLinkInput = parsed.token.isEmpty ? parsed.endpoint : "\(parsed.endpoint)/?token=\(parsed.token)"
                autoDetectedBanner = "⚡ Detected Colab session on clipboard! Connecting…"
                colab.appendLog("[AUTO] Sheet detected Colab link on clipboard: \(parsed.endpoint)")
                Task {
                    isConnecting = true
                    await colab.connectToColab(endpoint: parsed.endpoint, token: parsed.token)
                    isConnecting = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        autoDetectedBanner = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(cardBackground)
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(subtleBorderColor, lineWidth: 0.5)
                    )
                Image(systemName: "cpu.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 6) {
                    Text("Google Colab Cloud GPU")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Cell Mode")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(cardBackground)
                        .foregroundColor(.secondary)
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(subtleBorderColor, lineWidth: 0.5))
                }
                
                Text("Free Remote NVIDIA GPU / TPU Accelerator")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status Indicator Pill
            HStack(spacing: 5) {
                if colab.status.isConnecting {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Connecting…")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.primary)
                } else if colab.status.isConnected {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Online")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                } else if colab.isListeningForSession {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Waiting…")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.primary)
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text("Ready")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(cardBackground)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(subtleBorderColor, lineWidth: 0.5))
            
            // Close Button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(5)
                    .background(cardBackground)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(subtleBorderColor, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    // MARK: - 1-Click Zero-Friction Setup Card
    private var oneClickSetupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Hero 1-Click Action
            Button {
                colab.launchAndAutoConnect()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("1-Click Launch & Connect Colab")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            
            // Listening Pulse Banner
            if colab.isListeningForSession {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Listening for Colab Session…")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Click Run in Google Colab — MicroCode will connect automatically.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Cancel") {
                        colab.stopListeningForClipboardSession()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(cardBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15), lineWidth: 0.8))
            }
            
            // Auto-Detected Clipboard Banner
            if let banner = autoDetectedBanner {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(banner)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(9)
                .background(cardBackground)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.18), lineWidth: 0.8))
            }
            
            Divider()
                .opacity(0.3)
            
            // Direct Link or Clipboard Auto-Detect
            VStack(alignment: .leading, spacing: 6) {
                Text("Manual Link / Clipboard Sync")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    TextField("Colab session link or leave empty to auto-detect", text: $sessionLinkInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    
                    Button {
                        Task {
                            isConnecting = true
                            let trimmed = sessionLinkInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty {
                                await colab.connectFromClipboard()
                            } else {
                                await colab.connectWithSingleLink(trimmed)
                            }
                            isConnecting = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isConnecting {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: sessionLinkInput.isEmpty ? "doc.on.clipboard" : "link")
                                    .font(.system(size: 10))
                            }
                            Text(sessionLinkInput.isEmpty ? "Paste & Connect" : "Connect")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            // 1-Click Code Copy Fallback
            HStack {
                Text("Need the starter snippet manually?")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    colab.copyBridgeCodeToClipboard()
                    hasCopiedCode = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        hasCopiedCode = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: hasCopiedCode ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5))
                        Text(hasCopiedCode ? "Copied to Clipboard!" : "Copy Starter Code")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(hasCopiedCode ? .green : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(cardBackground)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(subtleBorderColor, lineWidth: 0.5))
    }
    
    // MARK: - Connected State View
    private var connectedStateView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connected to Google Colab GPU")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    Text(colab.detectedGPU)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    colab.openColabInBrowser()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open Colab Tab in Browser")
                
                Button("Disconnect") {
                    colab.disconnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundColor(.red)
            }
            
            if !colab.jupyterEndpoint.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                    Text(colab.jupyterEndpoint)
                        .font(.system(size: 9.5, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    if let ping = colab.lastKeepAliveTime {
                        Text("Active • \(ping.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(cardBackground)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.35), lineWidth: 0.8))
    }
    
    // MARK: - Hardware Telemetry
    private var hardwareTelemetryView: some View {
        HStack(spacing: 10) {
            // Accelerator Card
            VStack(alignment: .leading, spacing: 3) {
                Text("ACCELERATOR")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.4)
                
                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    Text(colab.status.isConnected ? colab.detectedGPU : "Standby (Colab)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(cardBackground)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(subtleBorderColor, lineWidth: 0.5))
            
            // VRAM Card
            VStack(alignment: .leading, spacing: 3) {
                Text("ALLOCATED VRAM")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.4)
                
                HStack(spacing: 5) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    Text(colab.status.isConnected ? colab.gpuMemory : "15.0 GB GDDR6")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(cardBackground)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(subtleBorderColor, lineWidth: 0.5))
        }
    }
    
    // MARK: - Keep Alive Toggle
    private var keepAliveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $colab.antiIdleKeepAlive) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anti-Idle Persistent Heartbeat")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Transmits periodic pings to keep the Colab cloud session active without timing out.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(10)
        .background(cardBackground)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(subtleBorderColor, lineWidth: 0.5))
    }
    
    // MARK: - Diagnostics Console (Collapsible)
    private var diagnosticsSection: some View {
        DisclosureGroup(isExpanded: $showDiagnostics) {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if colab.connectionLogs.isEmpty {
                            Text("Ready. Launch or paste a Colab session link to begin.")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(colab.connectionLogs.suffix(20).enumerated()), id: \.offset) { _, log in
                                Text(log)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundColor(log.contains("[ERR]") ? .red : .primary.opacity(0.85))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: 90)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                Text("Diagnostics & Session Logs")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundColor(.secondary)
        }
    }
}
