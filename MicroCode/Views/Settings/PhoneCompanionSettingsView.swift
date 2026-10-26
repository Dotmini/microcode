//
//  PhoneCompanionSettingsView.swift
//  MicroCode
//
//  Formal IDE Settings Panel for "Connect with Phone" — Zero-Setup QR Code Pairing.
//  Matches MicroCode's native monochrome Settings theme.
//

import SwiftUI
import AppKit

struct PhoneCompanionSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var companion = PhoneCompanionService.shared
    @State private var copiedURL = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 1. Service Status & Master Toggle
            serviceHeaderSection
            
            if companion.isEnabled {
                // 2. Main Two-Column Pairing & Configuration Layout
                HStack(alignment: .top, spacing: 18) {
                    qrPairingPanel
                        .frame(width: 280)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        transportModeSection
                        endpointAndSecuritySection
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // 3. Active Mobile Sessions
                activeSessionsSection
            }
        }
        .onAppear {
            companion.appState = appState
            companion.refreshNetworkAddresses()
            companion.startServerIfNeeded()
        }
    }
    
    // MARK: - 1. Service Header
    
    private var serviceHeaderSection: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 38, height: 38)
                Image(systemName: "qrcode")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Mobile Companion Service")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 5) {
                        Circle()
                            .fill(companion.isServerRunning ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.4))
                            .frame(width: 5.5, height: 5.5)
                        Text(companion.isServerRunning ? "Listening on port \(companion.listeningPort)" : "Starting")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
                }
                
                Text("Synchronize active AI Agent conversations, live tool executions, code diffs, and model selection with iOS Safari or Android Chrome.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Toggle("", isOn: $companion.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - 2. QR Code Pairing Panel
    
    private var qrPairingPanel: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack {
                Text("QR PAIRING CODE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(companion.connectionMode == .lan ? "LAN" : "HTTPS")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 216, height: 216)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                
                if companion.connectionMode == .online, case .starting(let statusMsg) = companion.tunnelState {
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(statusMsg)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.black.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                    }
                    .frame(width: 196, height: 196)
                } else if let qrImage = companion.qrCodeImage {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 192, height: 192)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 2)
            
            Text("Scan with system Camera app to open the synchronized MicroCode AI workspace.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 8) {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(companion.activePairingURL, forType: .string)
                    copiedURL = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        copiedURL = false
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: copiedURL ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .medium))
                        Text(copiedURL ? "Copied" : "Copy URL")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.07))
                    .foregroundColor(.primary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    if let url = URL(string: companion.activePairingURL) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10.5, weight: .medium))
                        Text("Open Local")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.04))
                    .foregroundColor(.secondary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - 3. Transport Mode Section
    
    private var transportModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRANSPORT MODE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
            
            HStack(spacing: 10) {
                ForEach(PhoneConnectionMode.allCases) { mode in
                    let isSelected = companion.connectionMode == mode
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            companion.connectionMode = mode
                        }
                    }) {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(isSelected ? .primary : .secondary)
                                .frame(width: 18, height: 18)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text(mode.subtitle)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(isSelected ? .primary : .secondary.opacity(0.5))
                                .font(.system(size: 12))
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(isSelected ? Color.primary.opacity(0.07) : Color.primary.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.primary.opacity(0.24) : Color.primary.opacity(0.07), lineWidth: 1)
                        )
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - 4. Endpoint & Token Security Section
    
    private var endpointAndSecuritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(companion.connectionMode == .lan ? "NETWORK ENDPOINT" : "TUNNEL ENDPOINT")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    companion.refreshNetworkAddresses()
                    if companion.connectionMode == .online {
                        companion.startOnlineTunnel()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                        Text(companion.connectionMode == .online ? "Reconnect" : "Refresh Interface")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if companion.connectionMode == .lan {
                if companion.allNetworkAddresses.count > 1 {
                    HStack(spacing: 8) {
                        Text("Interface:")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                        Picker("", selection: $companion.selectedLANIP) {
                            ForEach(companion.allNetworkAddresses, id: \.ip) { item in
                                Text("\(item.ip) (\(item.interface))").tag(item.ip)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(maxWidth: 220)
                    }
                }
                
                endpointURLRow(url: companion.lanPairingURL, label: companion.activeLANHost)
            } else {
                switch companion.tunnelState {
                case .connected(let publicURL, let provider):
                    endpointURLRow(url: "\(publicURL)/?token=\(companion.pairingToken)", label: provider)
                case .starting(let msg):
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(msg)
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                case .failed(let err):
                    VStack(alignment: .leading, spacing: 4) {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("Active fallback: \(companion.lanIPAddress)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                case .stopped:
                    Button("Start HTTPS Tunnel") {
                        companion.startOnlineTunnel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            Divider().opacity(0.4)
            
            HStack(spacing: 10) {
                Image(systemName: "key.horizontal")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session Access Token")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("192-bit token embedded in pairing URL. Rotating invalidates existing mobile sessions.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Rotate Token") {
                    companion.rotatePairingToken()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func endpointURLRow(url: String, label: String) -> some View {
        HStack(spacing: 8) {
            Text(url)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(label)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .cornerRadius(6)
    }
    
    // MARK: - 5. Active Sessions Section
    
    private var activeSessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ACTIVE MOBILE CLIENTS (\(companion.connectedDevices.count))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                if !companion.connectedDevices.isEmpty {
                    Button("Revoke All") {
                        companion.rotatePairingToken()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            
            if companion.connectedDevices.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("No mobile clients connected.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(companion.connectedDevices) { device in
                    HStack(spacing: 10) {
                        Image(systemName: "iphone")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name)
                                .font(.system(size: 11.5, weight: .medium))
                            Text("\(device.ipAddress) · \(device.connectionVia)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("Connected")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(4)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
