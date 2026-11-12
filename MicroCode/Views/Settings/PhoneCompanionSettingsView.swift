//
//  PhoneCompanionSettingsView.swift
//  MicroCode
//
//  Formal IDE Settings Panel for "Mobile Connect 2.0" — Zero-Setup QR Code & 6-Digit PIN Pairing,
//  LAN / Tailscale Mesh VPN / Cloudflare Named & Quick Tunnels, Smart Mac Keep-Awake,
//  and Lock-Screen Push Notifications (ntfy.sh, Telegram, Discord/Slack/Webhook).
//

import SwiftUI
import AppKit

struct PhoneCompanionSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var companion = PhoneCompanionService.shared
    @State private var copiedURL = false
    @State private var copiedPIN = false
    @State private var copiedNtfyTopic = false
    @State private var showNamedTunnelConfig = false
    @State private var isSendingTestPush = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            serviceHeaderSection

            if companion.isEnabled {
                if companion.pendingApprovalCount > 0 {
                    pendingApprovalsBanner
                }

                HStack(alignment: .top, spacing: 18) {
                    qrPairingPanel
                        .frame(width: 280)

                    VStack(alignment: .leading, spacing: 16) {
                        transportModeSection
                        endpointAndSecuritySection
                    }
                    .frame(maxWidth: .infinity)
                }

                pushNotificationsSection
                activeSessionsSection
            }
        }
        .onAppear {
            companion.appState = appState
            companion.refreshNetworkAddresses()
            companion.refreshTailscaleStatus()
            companion.startServerIfNeeded()
            companion.ensureBackgroundMonitorRunning()
            companion.regenerateQRCode()
            if !companion.cloudflareNamedPublicHostname.isEmpty || !companion.cloudflareNamedTunnelToken.isEmpty {
                showNamedTunnelConfig = true
            }
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
                    Text("Mobile Connect 2.0")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(companion.isServerRunning ? Color.green.opacity(0.85) : Color.secondary.opacity(0.4))
                            .frame(width: 5.5, height: 5.5)
                        Text(companion.isServerRunning ? "Listening on :\(companion.listeningPort)" : "Starting")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
                }

                Text("Full mobile AI workstation: Chat + Camera/File uploads, Live Preview proxy, Git diff/commit/push, Quick Terminal, Voice Dictation, and Lock-Screen Push.")
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

    // MARK: - 1b. Non-Blocking Pending Approval Banner

    private var pendingApprovalsBanner: some View {
        let pendingDevices = companion.connectedDevices.filter { $0.approvalState == .pending }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 13))
                Text("New Mobile Device Requesting Access (\(pendingDevices.count))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("Or enter the 6-digit PIN on phone")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }

            ForEach(pendingDevices) { device in
                HStack(spacing: 10) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("\(device.name) · \(device.ipAddress) (\(device.connectionVia))")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.primary)
                    Spacer()
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
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.09))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.32), lineWidth: 1)
        )
    }

    // MARK: - 2. QR Code & 6-Digit PIN Pairing Panel

    private var transportBadgeText: String {
        switch companion.connectionMode {
        case .lan: return "LAN"
        case .tailscale: return "TAILSCALE"
        case .online: return "HTTPS"
        }
    }

    private var formattedSixDigitPIN: String {
        let raw = companion.sixDigitPairingPIN
        guard raw.count == 6 else { return raw }
        let prefix = raw.prefix(3)
        let suffix = raw.suffix(3)
        return "\(prefix) \(suffix)"
    }

    private var qrPairingPanel: some View {
        VStack(alignment: .center, spacing: 11) {
            HStack {
                Text("QR PAIRING CODE")
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
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 212, height: 212)
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
                    .frame(width: 192, height: 192)
                } else if let qrImage = companion.qrCodeImage {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 188, height: 188)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            pinDisplayBox

            Text("Scan QR with phone camera, or open the host URL and enter the 6-digit PIN.")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            qrActionButtons
        }
        .padding(14)
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
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }

            Spacer()

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
        .padding(.vertical, 7)
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

    // MARK: - 3. Transport Mode Section

    private var transportModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRANSPORT MODE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(PhoneConnectionMode.allCases) { mode in
                    transportModeCard(mode)
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

    private func transportModeCard(_ mode: PhoneConnectionMode) -> some View {
        let isSelected = companion.connectionMode == mode
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.12)) {
                companion.connectionMode = mode
            }
        }) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: mode.icon)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(isSelected ? .primary : .secondary)
                    Spacer()
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(isSelected ? .primary : .secondary.opacity(0.5))
                        .font(.system(size: 11.5))
                }

                Text(mode.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(mode.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
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

    // MARK: - 4. Endpoint, Security & Smart Keep-Awake Section

    private var endpointSectionTitle: String {
        switch companion.connectionMode {
        case .lan: return "NETWORK ENDPOINT"
        case .tailscale: return "TAILSCALE MESH ENDPOINT"
        case .online: return "HTTPS TUNNEL ENDPOINT"
        }
    }

    private var endpointAndSecuritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(endpointSectionTitle)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
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
            }

            switch companion.connectionMode {
            case .lan:
                lanEndpointContent
            case .tailscale:
                tailscaleEndpointContent
            case .online:
                onlineEndpointContent
            }

            Divider().opacity(0.4)

            tokenRotationRow

            Divider().opacity(0.4)

            macApprovalToggleRow

            Divider().opacity(0.4)

            keepAwakeToggleRow
        }
        .padding(14)
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
    }

    @ViewBuilder
    private var tailscaleEndpointContent: some View {
        if companion.tailscaleInfo.isAvailable, let tsURL = companion.tailscalePairingURL {
            endpointURLRow(
                url: tsURL,
                label: companion.tailscaleInfo.tailnetName.isEmpty ? companion.tailscaleInfo.bestHost : companion.tailscaleInfo.tailnetName
            )
            if !companion.tailscaleInfo.ipv4.isEmpty && !companion.tailscaleInfo.magicDNSHostname.isEmpty {
                Text("Tailscale IPv4: \(companion.tailscaleInfo.ipv4) · MagicDNS: \(companion.tailscaleInfo.magicDNSHostname)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("Tailscale not detected or disconnected on this Mac.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                Text("Open Tailscale.app and sign in on both Mac and Phone for a permanent, zero-config WireGuard URL across any network, then click Refresh.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(6)
        }
    }

    @ViewBuilder
    private var onlineEndpointContent: some View {
        switch companion.tunnelState {
        case .connected(let publicURL, let provider):
            endpointURLRow(url: companion.onlinePairingURL ?? "\(publicURL)/?pair=\(companion.oneTimePairingCode)", label: provider)
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
                Text("Active LAN fallback: \(companion.lanIPAddress):\(companion.listeningPort)")
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

        DisclosureGroup("Permanent Cloudflare Named Tunnel (Optional)", isExpanded: $showNamedTunnelConfig) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bind a fixed custom domain so your PWA home-screen icon never changes URL across Mac restarts.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

                HStack(spacing: 8) {
                    Text("Public Hostname:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 105, alignment: .leading)
                    TextField("https://code.yourdomain.com", text: $companion.cloudflareNamedPublicHostname)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }

                HStack(spacing: 8) {
                    Text("Tunnel Token:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 105, alignment: .leading)
                    SecureField("eyJhIjoi... (from Cloudflare Zero Trust)", text: $companion.cloudflareNamedTunnelToken)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }

                HStack {
                    Spacer()
                    if !companion.cloudflareNamedPublicHostname.isEmpty || !companion.cloudflareNamedTunnelToken.isEmpty {
                        Button("Clear Named Tunnel") {
                            companion.cloudflareNamedPublicHostname = ""
                            companion.cloudflareNamedTunnelToken = ""
                            companion.startOnlineTunnel()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                    }
                    Button("Apply & Reconnect") {
                        companion.startOnlineTunnel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.top, 4)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)
    }

    private var tokenRotationRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.horizontal")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("One-Time QR Pairing & Session Token")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("QR code and 6-digit PIN issue an HttpOnly session token. Rotating revokes all connected phones.")
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

    private var macApprovalToggleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("Require Mac Approval for QR Scans")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("New phones scanning the QR code wait for non-blocking approval (entering the 6-digit PIN approves immediately).")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $companion.requireMacApprovalForNewDevices)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    private var keepAwakeToggleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: companion.isHoldingSleepAssertion ? "bolt.fill" : "bolt")
                .foregroundColor(companion.isHoldingSleepAssertion ? .green : .secondary)
                .font(.system(size: 12))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Smart Mac Keep-Awake")
                        .font(.system(size: 11.5, weight: .semibold))
                    if companion.isHoldingSleepAssertion {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
                Text("Prevents macOS idle sleep via IOKit while an AI Agent task is running or a phone session was active in the last 30 min.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $companion.preventMacSleepWhileActive)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
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

    // MARK: - 5. Lock-Screen Push Notifications Section

    private var pushNotificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                    Text("LOCK-SCREEN PUSH NOTIFICATIONS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: $companion.pushSettings.channel) {
                    ForEach(MobilePushChannelType.allCases) { ch in
                        Text(ch.title).tag(ch)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 220)
            }

            switch companion.pushSettings.channel {
            case .disabled:
                Text("In-app browser notifications, chime, and vibration remain active while Safari/PWA is open. Select ntfy.sh, Telegram, or Webhook to receive instant lock-screen alerts when away from your phone.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
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
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var ntfyPushConfigView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Install the free ntfy app on iOS/Android and subscribe to this private random topic:")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                TextField("https://ntfy.sh", text: $companion.pushSettings.ntfyServerURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 155)

                TextField("microcode-topic", text: $companion.pushSettings.ntfyTopic)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))

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
            }
        }
    }

    private var telegramPushConfigView: some View {
        HStack(spacing: 10) {
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
                    .frame(width: 170)
            }
        }
    }

    private var webhookPushConfigView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Discord Webhook, Slack Incoming Webhook, or Custom JSON Endpoint:")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
            TextField("https://discord.com/api/webhooks/...", text: $companion.pushSettings.webhookURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
        }
    }

    private var pushEventTogglesAndTestRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Toggle("Tool & Plan Approvals", isOn: $companion.pushSettings.notifyOnApprovalNeeded)
                    .controlSize(.small)
                    .font(.system(size: 11))
                Toggle("Agent Task Completed", isOn: $companion.pushSettings.notifyOnTaskCompleted)
                    .controlSize(.small)
                    .font(.system(size: 11))
                Spacer()
                Button(action: {
                    isSendingTestPush = true
                    Task {
                        let res = await companion.sendExternalPushNotification(
                            title: "🚀 MicroCode Push Connected",
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
                        Text("Send Test Push")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSendingTestPush)
            }

            if !companion.lastPushStatusMessage.isEmpty {
                Text(companion.lastPushStatusMessage)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 6. Active Sessions Section

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
                    connectedDeviceRow(device)
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

    private func connectedDeviceRow(_ device: ConnectedPhoneDevice) -> some View {
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
            }
        }
        .padding(.vertical, 4)
    }
}
