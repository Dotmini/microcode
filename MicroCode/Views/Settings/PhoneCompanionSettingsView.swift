//
//  PhoneCompanionSettingsView.swift
//  MicroCode
//
//  Native macOS HIG Settings Panel for Mobile Connect 2.0 — Responsive Layout,
//  Zero-Setup QR Code & 6-Digit PIN Pairing, LAN / Tailscale / Cloud HTTPS (cloudai.dotmini.net),
//  Smart Mac Keep-Awake, and Lock-Screen Push Notifications.
//

import SwiftUI
import AppKit

struct PhoneCompanionSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var companion = PhoneCompanionService.shared
    @State private var copiedURL = false
    @State private var copiedEndpoint = false
    @State private var copiedPIN = false
    @State private var copiedNtfyTopic = false
    @State private var isSendingTestPush = false
    @State private var gridWidth: CGFloat = 0

    private let gridSpacing: CGFloat = 14

    private var useTwoColumns: Bool {
        gridWidth == 0 || gridWidth >= 560
    }

    private var useHorizontalTransportBar: Bool {
        gridWidth == 0 || gridWidth >= 460
    }

    private var equalColumnWidth: CGFloat? {
        guard useTwoColumns, gridWidth > 60 else { return nil }
        return floor((gridWidth - gridSpacing) / 2.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            serviceHeaderSection

            if companion.isEnabled {
                if companion.pendingApprovalCount > 0 {
                    pendingApprovalsBanner
                }

                // Full-width responsive transport selector so all 3 mode cards breathe cleanly
                transportModeSection

                // Responsive 50/50 Grid (2-column when >= 560pt, 1-column stack when narrow)
                if useTwoColumns {
                    HStack(alignment: .top, spacing: gridSpacing) {
                        qrPairingPanel
                            .frame(width: equalColumnWidth)
                            .frame(maxWidth: equalColumnWidth == nil ? .infinity : nil, maxHeight: .infinity, alignment: .top)

                        endpointAndSecuritySection
                            .frame(width: equalColumnWidth)
                            .frame(maxWidth: equalColumnWidth == nil ? .infinity : nil, maxHeight: .infinity, alignment: .top)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .top, spacing: gridSpacing) {
                        pushNotificationsSection
                            .frame(width: equalColumnWidth)
                            .frame(maxWidth: equalColumnWidth == nil ? .infinity : nil, maxHeight: .infinity, alignment: .topLeading)

                        activeSessionsSection
                            .frame(width: equalColumnWidth)
                            .frame(maxWidth: equalColumnWidth == nil ? .infinity : nil, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        qrPairingPanel
                        endpointAndSecuritySection
                        pushNotificationsSection
                        activeSessionsSection
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { gridWidth = geo.size.width }
                    .onChange(of: geo.size.width) { newWidth in
                        if abs(gridWidth - newWidth) > 0.5 {
                            gridWidth = newWidth
                        }
                    }
            }
        )
        .onAppear {
            companion.appState = appState
            companion.refreshNetworkAddresses()
            companion.refreshTailscaleStatus()
            companion.startServerIfNeeded()
            companion.ensureBackgroundMonitorRunning()
            if companion.isEnabled && companion.connectionMode == .online {
                if case .connected = companion.tunnelState {
                    // Already active
                } else if case .starting = companion.tunnelState {
                    // Connecting
                } else {
                    companion.startOnlineTunnel()
                }
            }
            companion.regenerateQRCode()
        }
    }

    // MARK: - 1. Service Header

    private var serviceHeaderSection: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 36, height: 36)
                Image(systemName: "qrcode")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
            }
            .fixedSize()

            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 8) {
                    Text("Mobile Connect 2.0")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(companion.isServerRunning ? Color.green.opacity(0.85) : Color.secondary.opacity(0.4))
                            .frame(width: 5.5, height: 5.5)
                        Text(companion.isServerRunning ? ":\(String(companion.listeningPort))" : "Starting")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
                    .fixedSize()
                }

                Text("Remote Chat, File/Camera uploads, Live Preview, Git controls, Terminal, Voice Dictation, and Push.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $companion.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .fixedSize()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - 1b. Non-Blocking Pending Approval Banner

    private var pendingApprovalsBanner: some View {
        let pendingDevices = companion.connectedDevices.filter { $0.approvalState == .pending }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 12.5))
                Text("Device Requesting Access (\(pendingDevices.count))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer(minLength: 6)
                Text("Or enter 6-digit PIN on phone")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            ForEach(pendingDevices) { device in
                HStack(spacing: 10) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("\(device.name) · \(device.ipAddress) (\(device.connectionVia))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        Button("Approve") {
                            companion.approveDevice(id: device.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Deny") {
                            companion.rejectDevice(id: device.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .fixedSize()
                }
            }
        }
        .padding(11)
        .background(Color.orange.opacity(0.09))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.32), lineWidth: 1)
        )
    }

    // MARK: - 2. Full-Width Responsive Transport Mode Bar

    private var transportModeSection: some View {
        Group {
            if useHorizontalTransportBar {
                HStack(spacing: 10) {
                    ForEach(PhoneConnectionMode.allCases) { mode in
                        transportModeCard(mode)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ForEach(PhoneConnectionMode.allCases) { mode in
                        transportModeCard(mode)
                    }
                }
            }
        }
    }

    private func transportModeCard(_ mode: PhoneConnectionMode) -> some View {
        let isSelected = companion.connectionMode == mode
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.12)) {
                companion.connectionMode = mode
            }
        }) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.primary.opacity(0.1) : Color.primary.opacity(0.04))
                        .frame(width: 30, height: 30)
                    Image(systemName: mode.icon)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(isSelected ? .primary : .secondary)
                }
                .fixedSize()

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(mode.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(mode.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .primary : .secondary.opacity(0.45))
                    .font(.system(size: 12))
                    .fixedSize()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(isSelected ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .controlBackgroundColor).opacity(0.65))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? Color.primary.opacity(0.26) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.2 : 1)
            )
            .cornerRadius(9)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. QR Code & 6-Digit PIN Pairing Panel

    private var transportBadgeText: String {
        switch companion.connectionMode {
        case .lan: return "WI-FI / LAN"
        case .tailscale: return "TAILSCALE"
        case .online: return "CELLULAR · HTTPS"
        }
    }

    private var formattedSixDigitPIN: String {
        let raw = companion.sixDigitPairingPIN
        guard raw.count == 6 else { return raw }
        return "\(raw.prefix(3)) \(raw.suffix(3))"
    }

    private var qrPairingPanel: some View {
        VStack(alignment: .center, spacing: 10) {
            HStack {
                Text("QR PAIRING")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(transportBadgeText)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                    .fixedSize()
            }

            Spacer(minLength: 0)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 168, height: 168)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )

                if companion.connectionMode == .online, case .starting = companion.tunnelState {
                    VStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Connecting…")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.black.opacity(0.68))
                    }
                    .frame(width: 150, height: 150)
                } else if let qrImage = companion.qrCodeImage {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 148, height: 148)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 0)

            pinDisplayBox

            Text("Scan QR with phone camera, or open URL and enter PIN.")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            qrActionButtons
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var pinDisplayBox: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("6-DIGIT PAIRING PIN")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(formattedSixDigitPIN)
                    .font(.system(size: 14.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }

            Spacer(minLength: 6)

            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(companion.sixDigitPairingPIN, forType: .string)
                copiedPIN = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copiedPIN = false
                }
            }) {
                Image(systemName: copiedPIN ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Copy 6-Digit PIN")

            Button(action: {
                companion.regenerateSixDigitPIN()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Generate New 6-Digit PIN")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.035))
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var qrActionButtons: some View {
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
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5.5)
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
                    Text("Open Preview")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5.5)
                .background(Color.primary.opacity(0.04))
                .foregroundColor(.secondary)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 4. Endpoint, Security & Smart Keep-Awake Section

    private var endpointSectionTitle: String {
        switch companion.connectionMode {
        case .lan: return "LOCAL ENDPOINT"
        case .tailscale: return "TAILSCALE ENDPOINT"
        case .online: return "CLOUD ENDPOINT"
        }
    }

    private var endpointAndSecuritySection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(endpointSectionTitle)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: {
                    companion.refreshNetworkAddresses()
                    companion.refreshTailscaleStatus()
                    if companion.connectionMode == .online {
                        companion.startOnlineTunnel()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                        Text(companion.connectionMode == .online ? "Reconnect" : "Refresh")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .fixedSize()
            }

            switch companion.connectionMode {
            case .lan:
                lanEndpointContent
            case .tailscale:
                tailscaleEndpointContent
            case .online:
                onlineEndpointContent
            }

            Spacer(minLength: 0)

            Divider().opacity(0.4)

            tokenRotationRow

            Divider().opacity(0.4)

            macApprovalToggleRow

            Divider().opacity(0.4)

            keepAwakeToggleRow
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var lanEndpointContent: some View {
        if companion.allNetworkAddresses.count > 1 {
            HStack(spacing: 8) {
                Text("Interface")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize()
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
        endpointURLRow(url: companion.lanPairingURL)
        Text("Host: \(companion.activeLANHost):\(String(companion.listeningPort)) · Direct local socket")
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private var tailscaleEndpointContent: some View {
        if companion.tailscaleInfo.isAvailable, let tsURL = companion.tailscalePairingURL {
            endpointURLRow(url: tsURL)
            let hostLabel = companion.tailscaleInfo.magicDNSHostname.isEmpty
                ? companion.tailscaleInfo.ipv4
                : companion.tailscaleInfo.magicDNSHostname
            Text("WireGuard Mesh · \(hostLabel)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tailscale is not connected on this Mac.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                Text("Sign in to Tailscale on both Mac and Phone for a private WireGuard address, then click Refresh.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(6)
        }
    }

    @ViewBuilder
    private var onlineEndpointContent: some View {
        switch companion.tunnelState {
        case .connected(let publicURL, let provider):
            endpointURLRow(url: companion.onlinePairingURL ?? "\(publicURL)/?pair=\(companion.oneTimePairingCode)")
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green.opacity(0.85))
                    .frame(width: 5.5, height: 5.5)
                if let shapeID = companion.activeRelayShapeID {
                    Text("\(provider) · Unique route #\(shapeID + 1)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("\(provider) · End-to-end TLS")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        case .starting(let msg):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
        case .failed(let err):
            VStack(alignment: .leading, spacing: 3) {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("LAN still active on \(companion.lanIPAddress):\(String(companion.listeningPort))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.8))
                    .lineLimit(1)
            }
        case .stopped:
            Button("Connect") {
                companion.startOnlineTunnel()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func endpointURLRow(url: String) -> some View {
        HStack(spacing: 8) {
            Text(url)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
                copiedEndpoint = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copiedEndpoint = false
                }
            }) {
                Image(systemName: copiedEndpoint ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Copy Endpoint URL")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(6)
    }

    private var tokenRotationRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "key.horizontal")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
                .frame(width: 16)
                .fixedSize()

            VStack(alignment: .leading, spacing: 1.5) {
                Text("URL Route & Session Token")
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Text("Generates a new unique URL route, PIN, and revokes old links.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Rotate") {
                companion.rotatePairingToken()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
        }
    }

    private var macApprovalToggleRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "checkmark.shield")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
                .frame(width: 16)
                .fixedSize()

            VStack(alignment: .leading, spacing: 1.5) {
                Text("Require Mac Approval")
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Text("New QR scans wait for Mac approval (PIN approves immediately).")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $companion.requireMacApprovalForNewDevices)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .fixedSize()
        }
    }

    private var keepAwakeToggleRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: companion.isHoldingSleepAssertion ? "bolt.fill" : "bolt")
                .foregroundColor(companion.isHoldingSleepAssertion ? .green : .secondary)
                .font(.system(size: 12))
                .frame(width: 16)
                .fixedSize()

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 6) {
                    Text("Smart Mac Keep-Awake")
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    if companion.isHoldingSleepAssertion {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(4)
                            .fixedSize()
                    }
                }
                Text("Prevents idle sleep during AI tasks or active phone sessions.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $companion.preventMacSleepWhileActive)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .fixedSize()
        }
    }

    // MARK: - 5. Lock-Screen Push Notifications Section

    private var pushNotificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                    Text("LOCK-SCREEN PUSH")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Picker("", selection: $companion.pushSettings.channel) {
                    ForEach(MobilePushChannelType.allCases) { ch in
                        Text(ch.title).tag(ch)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 165)
            }

            switch companion.pushSettings.channel {
            case .disabled:
                Text("Browser alerts and chime stay active while open. Choose ntfy.sh, Telegram, or Webhook for instant lock-screen alerts.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .ntfy:
                ntfyPushConfigView
            case .telegram:
                telegramPushConfigView
            case .webhook:
                webhookPushConfigView
            }

            if companion.pushSettings.channel != .disabled {
                Divider().opacity(0.4)
                pushEventTogglesAndTestRow
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var ntfyPushConfigView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Install the free ntfy app on iOS/Android and subscribe to this private topic:")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                TextField("https://ntfy.sh", text: $companion.pushSettings.ntfyServerURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 100, maxWidth: 130)

                TextField("microcode-topic", text: $companion.pushSettings.ntfyTopic)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 6) {
                Button(copiedNtfyTopic ? "Copied" : "Copy Topic") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(companion.pushSettings.ntfyTopic, forType: .string)
                    copiedNtfyTopic = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedNtfyTopic = false
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("New Topic") {
                    companion.pushSettings.ntfyTopic = MobilePushSettings.generateRandomNtfyTopic()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Open Web") {
                    let base = companion.pushSettings.ntfyServerURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    if let u = URL(string: "\(base)/\(companion.pushSettings.ntfyTopic)") {
                        NSWorkspace.shared.open(u)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)
            }
        }
    }

    private var telegramPushConfigView: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Bot Token (@BotFather)")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                SecureField("123456789:ABCdefGHI...", text: $companion.pushSettings.telegramBotToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Chat ID")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                TextField("e.g. 987654321", text: $companion.pushSettings.telegramChatId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }
        }
    }

    private var webhookPushConfigView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Discord, Slack, or Custom JSON Webhook URL:")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
            TextField("https://discord.com/api/webhooks/...", text: $companion.pushSettings.webhookURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
        }
    }

    private var pushEventTogglesAndTestRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle("Approvals", isOn: $companion.pushSettings.notifyOnApprovalNeeded)
                    .controlSize(.small)
                    .font(.system(size: 11))
                    .fixedSize()
                Toggle("Task Done", isOn: $companion.pushSettings.notifyOnTaskCompleted)
                    .controlSize(.small)
                    .font(.system(size: 11))
                    .fixedSize()
                Spacer(minLength: 4)
                Button(action: {
                    isSendingTestPush = true
                    Task {
                        let res = await companion.sendExternalPushNotification(
                            title: "MicroCode Push Connected",
                            body: "Lock-screen notifications are active for tool approvals and completed AI tasks."
                        )
                        companion.lastPushStatusMessage = res.message
                        isSendingTestPush = false
                    }
                }) {
                    HStack(spacing: 5) {
                        if isSendingTestPush {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 10))
                        }
                        Text("Test Push")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSendingTestPush)
                .fixedSize()
            }

            if !companion.lastPushStatusMessage.isEmpty {
                Text(companion.lastPushStatusMessage)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - 6. Active Sessions Section

    private var activeSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                    Text("ACTIVE CLIENTS (\(companion.connectedDevices.count))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if !companion.connectedDevices.isEmpty {
                    Button("Revoke All") {
                        companion.rotatePairingToken()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .fixedSize()
                }
            }

            if companion.connectedDevices.isEmpty {
                Spacer(minLength: 2)
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.75))
                    Text("No mobile clients connected yet. Scan the QR code or enter the 6-digit PIN on your phone.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 2)
            } else {
                ForEach(companion.connectedDevices) { device in
                    connectedDeviceRow(device)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func connectedDeviceRow(_ device: ConnectedPhoneDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
                .fixedSize()

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Text("\(device.ipAddress) · \(device.connectionVia)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if device.approvalState == .pending {
                HStack(spacing: 6) {
                    Button("Approve") {
                        companion.approveDevice(id: device.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Deny") {
                        companion.rejectDevice(id: device.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .fixedSize()
            } else if device.approvalState == .rejected {
                HStack(spacing: 6) {
                    Text("Denied")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Button("Approve") {
                        companion.approveDevice(id: device.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .fixedSize()
            } else {
                HStack(spacing: 8) {
                    Text("Approved")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)

                    Button("Revoke") {
                        companion.revokeDevice(id: device.id)
                    }
                    .font(.system(size: 10.5))
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                .fixedSize()
            }
        }
        .padding(.vertical, 3)
    }
}
