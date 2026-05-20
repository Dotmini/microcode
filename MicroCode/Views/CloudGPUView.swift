//
//  CloudGPUView.swift
//  MicroCode
//
//  Zero-config managed Cloud GPU: pick a GPU, it just runs. Pay-as-you-go
//  from a Wallet that is separate from the Pro subscription.
//
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import SwiftUI
import AppKit

struct CloudGPUView: View {
    @ObservedObject private var svc = CloudGPUService.shared
    @State private var showTopUp = false
    @State private var topUpMsg = ""
    @State private var topUpBusy = false
    @State private var dataMsg = ""
    @State private var dataBusy = false

    private let topUpPackages: [(id: String, label: String)] = [
        ("credit_200", "฿200"), ("credit_500", "฿500"),
        ("credit_1000", "฿1,000"), ("credit_2000", "฿2,000")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "cpu.fill").font(.title2).foregroundColor(.blue)
                Text("Cloud GPU").font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "creditcard").foregroundColor(.secondary)
                    Text(svc.balanceText).font(.system(size: 13, weight: .semibold))
                    Button("Add credit") { showTopUp.toggle() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }

            Text("Pick a GPU and run — no SSH, no tokens, no setup. Billed per minute from your Wallet (separate from your subscription).")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showTopUp {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ADD CREDIT").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        ForEach(topUpPackages, id: \.id) { p in
                            Button(p.label) {
                                topUpMsg = ""; topUpBusy = true
                                Task {
                                    let r = await svc.topUp(packageId: p.id)
                                    topUpBusy = false
                                    if let url = r.url {
                                        NSWorkspace.shared.open(url)
                                        topUpMsg = "Opened secure checkout in your browser…"
                                    } else {
                                        topUpMsg = r.error ?? "Top-up failed."
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(topUpBusy)
                        }
                        if topUpBusy { ProgressView().scaleEffect(0.6) }
                    }
                    if !topUpMsg.isEmpty {
                        Text(topUpMsg)
                            .font(.system(size: 10))
                            .foregroundColor(topUpMsg.hasPrefix("Opened") ? .green : .red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Opens a secure Stripe checkout. Balance updates after payment.")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }

            Divider()

            // Active session
            if svc.status == .running, let s = svc.activeSession {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("Connected — \(s.gpuLabel)").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(svc.priceText(s.pricePerMinute)).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Text("Notebook cells now run on this GPU. Python + Bash kernels are ready. Billing stops when you disconnect.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    // Data transfer (Jupyter Contents API via secure proxy)
                    HStack(spacing: 8) {
                        Button {
                            let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = false; p.allowsMultipleSelection = false
                            if p.runModal() == .OK, let local = p.url {
                                dataBusy = true; dataMsg = "Uploading \(local.lastPathComponent)…"
                                Task {
                                    let err = await svc.uploadFile(local, to: local.lastPathComponent)
                                    dataBusy = false
                                    dataMsg = err ?? "✓ Uploaded \(local.lastPathComponent) to /\(local.lastPathComponent)"
                                }
                            }
                        } label: { Label("Upload file", systemImage: "arrow.up.doc") }
                            .disabled(dataBusy)
                        Button {
                            let alert = NSAlert(); alert.messageText = "Download file from GPU"
                            alert.informativeText = "Remote path (relative to home), e.g. outputs/result.csv"
                            let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24)); tf.placeholderString = "outputs/result.csv"
                            alert.accessoryView = tf; alert.addButton(withTitle: "Download"); alert.addButton(withTitle: "Cancel")
                            if alert.runModal() == .alertFirstButtonReturn {
                                let remote = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !remote.isEmpty else { return }
                                let save = NSSavePanel(); save.nameFieldStringValue = (remote as NSString).lastPathComponent
                                if save.runModal() == .OK, let dest = save.url {
                                    dataBusy = true; dataMsg = "Downloading \(remote)…"
                                    Task {
                                        let err = await svc.downloadFile(remote, to: dest)
                                        dataBusy = false
                                        dataMsg = err ?? "✓ Downloaded to \(dest.lastPathComponent)"
                                    }
                                }
                            }
                        } label: { Label("Download", systemImage: "arrow.down.doc") }
                            .disabled(dataBusy)
                        if dataBusy { ProgressView().scaleEffect(0.6) }
                    }
                    if !dataMsg.isEmpty {
                        Text(dataMsg)
                            .font(.system(size: 10))
                            .foregroundColor(dataMsg.hasPrefix("✓") ? .green : (dataMsg.hasPrefix("Uploading") || dataMsg.hasPrefix("Downloading") ? .secondary : .red))
                    }
                    Button(role: .destructive) {
                        Task { await svc.stop() }
                    } label: { Label("Disconnect", systemImage: "stop.circle") }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.08)))
            } else {
                // Catalog
                if svc.status == .connecting {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Provisioning GPU — this can take 2–4 minutes (booting pod & Jupyter)…")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if case .failed(let m) = svc.status {
                    Text(m).font(.system(size: 11)).foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if svc.catalog.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "cpu").font(.system(size: 30)).foregroundColor(.secondary.opacity(0.4))
                        Text(svc.lastError.isEmpty ? "Loading available GPUs…" : svc.lastError)
                            .font(.system(size: 12)).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    VStack(spacing: 8) {
                        ForEach(svc.catalog) { gpu in
                            HStack(spacing: 12) {
                                Image(systemName: "cpu").foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(gpu.label).font(.system(size: 13, weight: .medium))
                                    Text("\(gpu.vramGB) GB VRAM · \(svc.priceText(gpu.pricePerMinute))")
                                        .font(.system(size: 11)).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Connect") {
                                    Task { await svc.connect(gpu: gpu) { showTopUp = true } }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!gpu.available || svc.status == .connecting)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
                            .opacity(gpu.available ? 1 : 0.5)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: 520, alignment: .leading)
        .task { await svc.refresh() }
    }
}
