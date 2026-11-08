//
//  DevPortTunnelService.swift
//  MicroCode
//
//  Zero-Setup Public HTTPS Tunneling for Arbitrary Local TCP Dev Ports
//  Primary Engine: Cloudflare Quick Tunnel (cloudflared)
//  Fallback Engine: macOS Native SSH Reverse Tunnel (localhost.run with pinned host keys)
//

import Foundation
import AppKit
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins

enum DevPortTunnelState: Equatable {
    case stopped
    case starting(String)
    case connected(url: String, provider: String)
    case failed(String)
}

@MainActor
final class DevPortTunnelService: ObservableObject {
    static let shared = DevPortTunnelService()

    @Published private(set) var tunnels: [Int: DevPortTunnelState] = [:]

    var activeTunnelCount: Int {
        tunnels.values.reduce(0) { count, state in
            switch state {
            case .starting, .connected:
                return count + 1
            case .stopped, .failed:
                return count
            }
        }
    }

    private var processes: [Int: Process] = [:]
    private var outputPipes: [Int: Pipe] = [:]
    private var outputBuffers: [Int: String] = [:]
    private var pendingTunnelURLs: [Int: String] = [:]
    private var qrImageCache: [String: NSImage] = [:]

    private init() {}

    // MARK: - Public Tunnel Lifecycle

    func startTunnel(for port: Int) {
        guard (1...65535).contains(port) else {
            tunnels[port] = .failed("Invalid TCP port \(port). Enter a port between 1 and 65535.")
            return
        }

        terminateTrackedProcess(for: port)
        tunnels[port] = .starting("Initializing HTTPS tunnel for :\(port)…")

        if let cfBinary = Self.findCloudflaredBinary() {
            launchCloudflaredTunnel(binaryPath: cfBinary, port: port)
        } else {
            launchSSHReverseTunnel(port: port)
        }
    }

    func stopTunnel(for port: Int) {
        terminateTrackedProcess(for: port)
        tunnels.removeValue(forKey: port)
    }

    func stopAllTunnels() {
        let allPorts = Array(Set(processes.keys).union(tunnels.keys))
        for port in allPorts {
            terminateTrackedProcess(for: port)
        }
        tunnels.removeAll()
    }

    func publicURL(for port: Int) -> String? {
        if case .connected(let url, _) = tunnels[port] {
            return url
        }
        return nil
    }

    func qrCodeImage(for urlString: String) -> NSImage? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let cached = qrImageCache[trimmed] {
            return cached
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(trimmed.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }

        let ciContext = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false
        ])
        guard let rawCGImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        let pixelDimension = 240
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let cgContext = CGContext(
            data: nil,
            width: pixelDimension,
            height: pixelDimension,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        cgContext.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        cgContext.fill(CGRect(x: 0, y: 0, width: pixelDimension, height: pixelDimension))
        cgContext.interpolationQuality = .none
        cgContext.draw(rawCGImage, in: CGRect(x: 0, y: 0, width: pixelDimension, height: pixelDimension))

        guard let crispCGImage = cgContext.makeImage() else { return nil }
        let image = NSImage(cgImage: crispCGImage, size: NSSize(width: 120, height: 120))
        if qrImageCache.count >= 32 {
            qrImageCache.removeAll()
        }
        qrImageCache[trimmed] = image
        return image
    }

    // MARK: - Primary Engine: Cloudflare Quick Tunnel

    private nonisolated static func findCloudflaredBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/cloudflared",
            "/usr/local/bin/cloudflared",
            "\(home)/Library/Application Support/MicroCode/bin/cloudflared"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private nonisolated static func reapStaleCloudflared(for port: Int) {
        let reap = Process()
        reap.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        reap.arguments = ["-f", "cloudflared tunnel --url http://127\\.0\\.0\\.1:\(port)($| )"]
        reap.standardOutput = FileHandle.nullDevice
        reap.standardError = FileHandle.nullDevice
        try? reap.run()
        reap.waitUntilExit()
    }

    private func launchCloudflaredTunnel(binaryPath: String, port: Int) {
        tunnels[port] = .starting("Starting Cloudflare Quick Tunnel…")
        Self.reapStaleCloudflared(for: port)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = ["tunnel", "--url", "http://127.0.0.1:\(port)", "--no-autoupdate"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        outputBuffers[port] = ""

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let chunk = String(decoding: data, as: UTF8.self)
            guard !chunk.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self, self.processes[port] === proc else { return }
                self.consumeTunnelOutput(
                    chunk: chunk,
                    port: port,
                    pattern: #"https://[a-zA-Z0-9-]+\.trycloudflare\.com"#,
                    provider: "Cloudflare Quick Tunnel"
                )
            }
        }

        proc.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                guard let self, self.processes[port] === proc else { return }
                self.processes.removeValue(forKey: port)
                self.outputPipes.removeValue(forKey: port)
                self.outputBuffers.removeValue(forKey: port)

                if case .starting = self.tunnels[port] {
                    // Auto-fallback to macOS SSH tunnel if cloudflared exited before connecting
                    self.launchSSHReverseTunnel(port: port)
                } else if case .connected = self.tunnels[port] {
                    self.tunnels[port] = .failed("Cloudflare tunnel for :\(port) disconnected.")
                }
            }
        }

        do {
            try proc.run()
            processes[port] = proc
            outputPipes[port] = pipe
        } catch {
            launchSSHReverseTunnel(port: port)
        }
    }

    // MARK: - Fallback Engine: macOS Native SSH Reverse Tunnel (localhost.run)

    private func launchSSHReverseTunnel(port: Int) {
        tunnels[port] = .starting("Starting SSH HTTPS Tunnel…")

        let knownHostsURL = PhoneCompanionService.ensurePinnedKnownHostsFile()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        proc.arguments = [
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UserKnownHostsFile=\(knownHostsURL.path)",
            "-o", "ServerAliveInterval=30",
            "-o", "ExitOnForwardFailure=yes",
            "-R", "80:127.0.0.1:\(port)",
            "nokey@localhost.run"
        ]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.standardInput = Pipe()
        outputBuffers[port] = ""

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let chunk = String(decoding: data, as: UTF8.self)
            guard !chunk.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self, self.processes[port] === proc else { return }
                self.consumeTunnelOutput(
                    chunk: chunk,
                    port: port,
                    pattern: #"https://[a-zA-Z0-9-]+\.lhr\.life"#,
                    provider: "SSH Quick Tunnel"
                )
            }
        }

        proc.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                guard let self, self.processes[port] === proc else { return }
                self.processes.removeValue(forKey: port)
                self.outputPipes.removeValue(forKey: port)
                self.outputBuffers.removeValue(forKey: port)

                if case .starting = self.tunnels[port] {
                    self.tunnels[port] = .failed("Could not establish HTTPS tunnel for :\(port). Check your internet connection.")
                } else if case .connected = self.tunnels[port] {
                    self.tunnels[port] = .failed("SSH tunnel for :\(port) disconnected.")
                }
            }
        }

        do {
            try proc.run()
            processes[port] = proc
            outputPipes[port] = pipe
        } catch {
            tunnels[port] = .failed("Failed to launch tunnel: \(error.localizedDescription)")
        }
    }

    // MARK: - Internal Helpers

    private func consumeTunnelOutput(chunk: String, port: Int, pattern: String, provider: String) {
        if case .connected = tunnels[port] { return }
        let combined = String(((outputBuffers[port] ?? "") + chunk).suffix(12_288))
        outputBuffers[port] = combined

        if pendingTunnelURLs[port] == nil,
           let range = combined.range(of: pattern, options: .regularExpression) {
            let publicURL = String(combined[range])
            if provider.contains("Cloudflare") {
                pendingTunnelURLs[port] = publicURL
                tunnels[port] = .starting("Activating Cloudflare edge route…")
                // Fallback activation after 3.5s in case cloudflared log verbosity suppresses connection confirmation
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    guard let self, let pending = self.pendingTunnelURLs[port], self.processes[port]?.isRunning == true else { return }
                    if case .connected = self.tunnels[port] { return }
                    self.pendingTunnelURLs.removeValue(forKey: port)
                    self.outputBuffers.removeValue(forKey: port)
                    self.tunnels[port] = .connected(url: pending, provider: provider)
                }
            } else {
                outputBuffers.removeValue(forKey: port)
                tunnels[port] = .connected(url: publicURL, provider: provider)
            }
        }

        if let pending = pendingTunnelURLs[port],
           combined.contains("Registered tunnel connection") {
            pendingTunnelURLs.removeValue(forKey: port)
            outputBuffers.removeValue(forKey: port)
            tunnels[port] = .connected(url: pending, provider: provider)
        }
    }

    private func terminateTrackedProcess(for port: Int) {
        if let pipe = outputPipes.removeValue(forKey: port) {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        outputBuffers.removeValue(forKey: port)
        pendingTunnelURLs.removeValue(forKey: port)
        if let proc = processes.removeValue(forKey: port), proc.isRunning {
            proc.terminate()
        }
    }
}
