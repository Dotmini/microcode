//
//  CloudGPUView.swift
//  MicroCode
//
//  Unified Dotmini Cloud GPU Hub: GPU Cluster, GPU Wallet, Git Ingest, & SSH/Custom.
//  Zero-config managed Cloud GPU with Pay-as-you-go Beam Payment / PromptPay.
//
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import SwiftUI
import AppKit

struct CloudGPUView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var svc = CloudGPUService.shared
    @ObservedObject private var gpu = RemoteGPUService.shared
    @ObservedObject private var prov = RemoteProviderService.shared

    @AppStorage("remoteSSHCommand") private var sshCmd = ""
    @AppStorage("remoteSSHKey") private var sshKey = ""
    @AppStorage("runpodApiKey") private var runpodKey = ""
    @AppStorage("vastApiKey") private var vastKey = ""

    @State private var selectedTab = 0 // 0=Cluster, 1=Wallet, 2=Git Ingest, 3=SSH
    @State private var providerSel: RemoteProviderService.Provider = .runpod
    @State private var customAmount: String = "300"
    @State private var topUpMsg = ""
    @State private var topUpBusy = false
    @State private var dataMsg = ""
    @State private var dataBusy = false

    // Git Ingestion State
    @State private var gitRepoURL: String = ""
    @State private var gitBranch: String = "main"
    @State private var gitToken: String = ""
    @State private var gitDestination: String = "data"
    @State private var isIngesting: Bool = false
    @State private var ingestLogs: String = ""
    @State private var cloudFileList: [String] = []
    @State private var isRefreshingFiles: Bool = false

    @State private var testing = false
    @State private var testOK: Bool? = nil
    @State private var testMsg = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Hub Header ──
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                        .frame(width: 42, height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                        )
                    Image(systemName: "cpu")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Dotmini Cloud GPU Hub")
                        .font(.system(size: 16, weight: .bold))
                    Text("High-performance compute clusters, persistent storage, and dataset ingestion.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Balance Badge
                Button {
                    selectedTab = 1
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 11))
                        Text(svc.balanceText)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.045))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // ── Segmented Control ──
            Picker("", selection: $selectedTab) {
                Text("GPU Cluster").tag(0)
                Text("GPU Wallet (Pay As You Go)").tag(1)
                Text("Git Ingest (10Gbps)").tag(2)
                Text("SSH / Custom").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider().opacity(0.5)

            // ── Tab Content ──
            Group {
                switch selectedTab {
                case 0:
                    gpuClusterView
                case 1:
                    gpuWalletView
                case 2:
                    gitIngestView
                case 3:
                    sshCustomView
                default:
                    gpuClusterView
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await svc.refresh() }
    }

    // MARK: - Tab 0: GPU Cluster
    private var gpuClusterView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Active Session Banner
            if svc.status == .running, let s = svc.activeSession {
                HStack(spacing: 12) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Instance: \(s.gpuLabel)")
                            .font(.system(size: 13, weight: .semibold))
                        Text(sessionDetail(s))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        Task { await svc.stop() }
                    } label: {
                        Text("Disconnect")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor).opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }

            if svc.status == .connecting {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.7)
                    Text("Provisioning GPU cluster — booting pod & kernel (2–3 mins)...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
            }

            if !svc.gatewayMessage.isEmpty {
                let gatewayFailed: Bool = {
                    if case .failed = svc.status { return true }
                    return false
                }()
                Label(svc.gatewayMessage, systemImage: gatewayFailed ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundColor(gatewayFailed ? .red : .secondary)
            }

            Text("Select a GPU instance. Rates are billed per minute from your GPU Wallet.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            // GPU Grid
            VStack(spacing: 8) {
                ForEach(svc.catalog) { gpuItem in
                    HStack(spacing: 14) {
                        gpuVendorMark(for: gpuItem.label)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(gpuItem.label)
                                    .font(.system(size: 13, weight: .semibold))
                                Text("\(gpuItem.vramGB)GB VRAM")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.05))
                                    .foregroundColor(.secondary)
                                    .clipShape(Capsule())
                            }
                            Text(gpuItem.pricePerHourText + " (\(svc.priceText(gpuItem.pricePerMinute)))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button {
                            Task {
                                await svc.connect(gpu: gpuItem) {
                                    selectedTab = 1 // Switch to wallet on insufficient balance
                                }
                            }
                        } label: {
                            Text(svc.activeSession?.gpuLabel == gpuItem.label ? "Connected" : "Launch")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(svc.activeSession != nil || svc.status == .connecting)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                    )
                }
            }

            if !svc.lastError.isEmpty {
                Text(svc.lastError)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
        }
    }

    private func elapsedText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func sessionDetail(_ session: CloudGPUService.Session) -> String {
        let used = svc.priceText(svc.activeSessionCostSatang)
            .replacingOccurrences(of: "/min", with: "")
        return "Notebook cells & jobs run on this instance. \(svc.priceText(session.pricePerMinute)) · \(elapsedText(svc.activeSessionElapsedSeconds)) · \(used) used"
    }

    /// A neutral wordmark until an approved vendor brand asset is supplied.
    /// GPU vendor names are derived from the live catalog so AMD and Intel are
    /// shown automatically when their instances are made available.
    private func gpuVendorMark(for gpuLabel: String) -> some View {
        let label = gpuLabel.lowercased()
        let vendor: String
        if label.contains("nvidia") { vendor = "NVIDIA" }
        else if label.contains("amd") || label.contains("radeon") || label.contains("instinct") { vendor = "AMD" }
        else if label.contains("intel") || label.contains("arc") || label.contains("gaudi") { vendor = "INTEL" }
        else { vendor = "GPU" }

        return Text(vendor)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(.secondary)
            .frame(width: 52, height: 28)
            .background(Color.primary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Tab 1: GPU Wallet
    private var gpuWalletView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Balance Card
            VStack(alignment: .leading, spacing: 6) {
                Text("GPU WALLET BALANCE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline) {
                    Text(svc.balanceText)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                    Button {
                        Task { await svc.loadWallet() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Balance")
                }

                Text("Pay-as-you-go computing. Balance is deducted only while your GPU cluster is actively running.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
            )

            // Packages
            Text("Top-up Packages")
                .font(.system(size: 12, weight: .semibold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(CloudGPUService.defaultTopupPackages) { pkg in
                    Button {
                        executeTopUp(amountTHB: pkg.amountTHB, packageId: pkg.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(pkg.name)
                                    .font(.system(size: 12, weight: .bold))
                                Spacer()
                                if let b = pkg.badge {
                                    Text(b)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.primary.opacity(0.05))
                                        .foregroundColor(.secondary)
                                        .clipShape(Capsule())
                                }
                            }
                            Text("฿\(pkg.amountTHB)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                            if pkg.bonusTHB > 0 {
                                Text("+฿\(pkg.bonusTHB) Bonus Credit")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(topUpBusy)
                }
            }

            // Custom Top-Up
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Top-up (minimum ฿100)")
                    .font(.system(size: 12, weight: .semibold))

                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Text("฿")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        TextField("Amount (e.g. 500)", text: $customAmount)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(width: 140)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    )

                    Button("Top Up ฿\(customAmount)") {
                        let amt = Int(customAmount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 300
                        executeTopUp(amountTHB: amt, packageId: "custom_\(amt)")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(topUpBusy || (Int(customAmount) ?? 0) < 100)

                    if topUpBusy {
                        ProgressView().scaleEffect(0.7)
                    }
                }
            }

            if !topUpMsg.isEmpty {
                Text(topUpMsg)
                    .font(.system(size: 11))
                    .foregroundColor(topUpMsg.hasPrefix("Opened") ? .green : .red)
            }

            Text("Opens the payment provider's secure checkout. Balance updates after payment is confirmed.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Tab 2: Git Ingest
    private var gitIngestView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ingest large datasets or repositories from GitHub / GitLab / HuggingFace directly to the Cloud Pod's 10Gbps storage without using your local bandwidth.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("REPOSITORY URL").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                TextField("https://github.com/username/large-dataset", text: $gitRepoURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    )
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BRANCH").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                    TextField("main", text: $gitBranch)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("DESTINATION PATH").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                    TextField("data/my-dataset", text: $gitDestination)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                        )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ACCESS TOKEN (OPTIONAL FOR PRIVATE REPOS)").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                SecureField("ghp_... or glpat_...", text: $gitToken)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    )
            }

            Button {
                triggerGitClone()
            } label: {
                HStack(spacing: 6) {
                    if isIngesting {
                        ProgressView().scaleEffect(0.6)
                        Text("Cloning dataset at 10Gbps...")
                    } else {
                        Image(systemName: "arrow.down.circle")
                        Text("Start Cloud Git Ingestion")
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(gitRepoURL.isEmpty || isIngesting || svc.activeSession == nil)

            if svc.activeSession == nil {
                Label("Connect to a GPU instance first in the GPU Cluster tab.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if !ingestLogs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("INGEST LOGS").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                    ScrollView {
                        Text(ingestLogs)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 80)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(6)
                }
            }
        }
    }

    // MARK: - Tab 3: SSH / Custom
    private var sshCustomView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect directly to any custom remote GPU or cluster via SSH command.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("SSH COMMAND").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                TextField("ssh -p 41122 root@1.2.3.4 -i ~/.ssh/key", text: $sshCmd)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("SSH PRIVATE KEY (OPTIONAL)").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                TextEditor(text: $sshKey)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 70)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    )
            }

            HStack(spacing: 10) {
                Button {
                    gpu.connect(sshCommand: sshCmd, keyPath: sshKey.isEmpty ? nil : sshKey)
                } label: {
                    Text(gpu.status == .connected ? "Connected" : "Connect via SSH")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(gpu.status == .connecting || sshCmd.trimmingCharacters(in: .whitespaces).isEmpty)

                if gpu.status == .connected {
                    Button(role: .destructive) {
                        gpu.disconnect()
                    } label: {
                        Text("Disconnect")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            DisclosureGroup("Advanced: Cloudflare / Custom Jupyter URL") {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("https://xxxx.trycloudflare.com", text: $appState.hpcEndpoint)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                        )
                    SecureField("Jupyter Token", text: $appState.hpcToken)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                        )
                    Button("Test Connection") {
                        Task { await testJupyterConnection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if !testMsg.isEmpty {
                        Text(testMsg)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(testOK == true ? .green : .red)
                    }
                }
                .padding(.top, 4)
            }
            .font(.system(size: 11))
        }
    }

    // MARK: - Actions
    private func executeTopUp(amountTHB: Int, packageId: String) {
        topUpMsg = ""
        topUpBusy = true
        Task {
            let r: (url: URL?, error: String?)
            if packageId.hasPrefix("custom_") {
                r = await svc.topUpCustom(amountTHB: amountTHB)
            } else {
                r = await svc.topUp(packageId: packageId)
            }
            await MainActor.run {
                topUpBusy = false
                if let url = r.url {
                    NSWorkspace.shared.open(url)
                    topUpMsg = "Opened secure checkout in your browser…"
                } else {
                    topUpMsg = r.error ?? "Top-up failed."
                }
            }
        }
    }

    private func triggerGitClone() {
        guard !gitRepoURL.isEmpty else { return }
        isIngesting = true
        ingestLogs = "🚀 Starting 10Gbps direct clone from \(gitRepoURL)...\n"
        Task {
            do {
                let res = try await svc.cloneGitRepository(
                    repoURL: gitRepoURL,
                    branch: gitBranch.isEmpty ? "main" : gitBranch,
                    token: gitToken.isEmpty ? nil : gitToken,
                    destination: gitDestination.isEmpty ? "data" : gitDestination
                ) { line in
                    DispatchQueue.main.async { ingestLogs += line + "\n" }
                }
                await MainActor.run {
                    isIngesting = false
                    ingestLogs += "\n✅ " + res
                }
            } catch {
                await MainActor.run {
                    isIngesting = false
                    ingestLogs += "\n❌ Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func testJupyterConnection() async {
        testing = true; testOK = nil; testMsg = ""
        defer { testing = false }
        var base = appState.hpcEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base.removeLast() }
        var probe = base
        if probe.hasPrefix("ws://") { probe = "http://" + probe.dropFirst(5) }
        if probe.hasPrefix("wss://") { probe = "https://" + probe.dropFirst(6) }
        guard let url = URL(string: "\(probe)/api/kernelspecs") else {
            testOK = false; testMsg = "Invalid URL"; return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        let tok = appState.hpcToken.trimmingCharacters(in: .whitespaces)
        if !tok.isEmpty { req.setValue("Token \(tok)", forHTTPHeaderField: "Authorization") }
        let t0 = Date()
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            guard let http = resp as? HTTPURLResponse else {
                testOK = false; testMsg = "No HTTP response"; return
            }
            if http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let specs = json["kernelspecs"] as? [String: Any] {
                testOK = true
                testMsg = "✅ Jupyter reachable (\(ms) ms)\nKernels: \(specs.keys.sorted().joined(separator: ", "))"
            } else {
                testOK = false; testMsg = "HTTP \(http.statusCode)"
            }
        } catch {
            testOK = false; testMsg = "Failed: \(error.localizedDescription)"
        }
    }
}
