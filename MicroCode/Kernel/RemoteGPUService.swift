//
//  RemoteGPUService.swift
//  MicroCode
//
//  One-paste Remote GPU connect for RunPod / Vast.ai.
//
//  The user pastes the provider's SSH command (the one line RunPod/Vast give
//  you). MicroCode then, with ZERO further input:
//    1. parses host / port / user / key,
//    2. SSHes in and launches a Jupyter server with a token IT generates
//       (the user never sees or types a token),
//    3. opens an SSH local port-forward to that server,
//    4. points the existing (hardened) Jupyter kernel at the local tunnel.
//
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import Foundation
import Combine

@MainActor
final class RemoteGPUService: ObservableObject {
    static let shared = RemoteGPUService()

    enum Status: Equatable {
        case disconnected, connecting, connected
        case failed(String)
    }

    @Published var status: Status = .disconnected
    @Published var log: String = ""
    @Published private(set) var localURL: String = ""

    private(set) var token: String = ""

    private var jupyterProc: Process?   // ssh exec that runs `jupyter server`
    private var tunnelProc: Process?    // ssh -N -L  (port forward)
    private let localPort = 8899
    private let remotePort = 8888
    private let sshPath = "/usr/bin/ssh"

    struct Target: Equatable {
        var host: String
        var port: Int
        var user: String
        var keyPath: String?
    }

    // MARK: - Parse the provider SSH command

    /// Accepts the line RunPod / Vast.ai hand you, e.g.
    ///   ssh -p 41122 root@213.1.2.3 -i ~/.ssh/id_ed25519
    ///   ssh root@ssh5.vast.ai -p 12345 -L 8080:localhost:8080
    static func parse(sshCommand raw: String, fallbackKey: String?) -> Target? {
        let toks = raw
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ").map(String.init)
            .filter { !$0.isEmpty }
        guard !toks.isEmpty else { return nil }

        var port = 22
        var key: String? = fallbackKey
        var hostUser: String?
        var pendingUser: String?
        var i = 0
        while i < toks.count {
            let t = toks[i]
            switch t {
            case "ssh": break
            case "-p":
                if i + 1 < toks.count { port = Int(toks[i + 1]) ?? port; i += 1 }
            case "-i":
                if i + 1 < toks.count { key = (toks[i + 1] as NSString).expandingTildeInPath; i += 1 }
            case "-l":
                if i + 1 < toks.count { pendingUser = toks[i + 1]; i += 1 }
            case "-L", "-R", "-o", "-D", "-J", "-w":
                if i + 1 < toks.count { i += 1 } // skip flag value
            default:
                if t.hasPrefix("-") { break }          // unknown flag, ignore
                if hostUser == nil { hostUser = t }     // first non-flag = [user@]host
            }
            i += 1
        }

        guard let hu = hostUser else { return nil }
        let user: String, host: String
        if hu.contains("@") {
            let parts = hu.split(separator: "@", maxSplits: 1).map(String.init)
            user = parts[0]; host = parts.count > 1 ? parts[1] : ""
        } else {
            user = pendingUser ?? "root"
            host = hu
        }
        guard !host.isEmpty else { return nil }
        return Target(host: host, port: port, user: user, keyPath: key)
    }

    private func append(_ s: String) {
        log += s
        if log.count > 12_000 { log = String(log.suffix(10_000)) }
    }

    // MARK: - MicroCode-managed SSH key (the good-UX path)

    /// MicroCode owns ONE ed25519 keypair. The user never picks a .pem — they
    /// just paste MicroCode's PUBLIC key into RunPod/Vast once (or it's
    /// auto-uploaded via the provider API key). Generated on first use.
    private var managedKeyPath: String {
        let dir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/MicroCode/ssh")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return (dir as NSString).appendingPathComponent("id_ed25519")
    }

    @discardableResult
    func ensureManagedKeypair() -> String {
        let priv = managedKeyPath
        if FileManager.default.fileExists(atPath: priv) { return priv }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        p.arguments = ["-t", "ed25519", "-N", "", "-q",
                       "-C", "microcode@\(Host.current().localizedName ?? "mac")",
                       "-f", priv]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: priv)
        CrashReporter.shared.breadcrumb("RemoteGPU.managedKey generated rc=\(p.terminationStatus)")
        return priv
    }

    /// The public key string to paste into the provider (one time).
    var managedPublicKey: String {
        ensureManagedKeypair()
        return (try? String(contentsOfFile: managedKeyPath + ".pub", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func sshBaseArgs(_ t: Target) -> [String] {
        var a = ["-o", "BatchMode=yes",
                 "-o", "StrictHostKeyChecking=accept-new",
                 "-o", "NumberOfPasswordPrompts=0",
                 "-o", "PreferredAuthentications=publickey",
                 "-o", "ServerAliveInterval=20",
                 "-o", "ServerAliveCountMax=3",
                 "-o", "ConnectTimeout=12",
                 "-p", String(t.port)]
        // User-chosen key wins; otherwise ALWAYS use MicroCode's own managed
        // key (deterministic — the user just pastes our public key once).
        let key = (t.keyPath?.isEmpty == false) ? t.keyPath! : ensureManagedKeypair()
        a += ["-i", key, "-o", "IdentitiesOnly=yes"]
        return a
    }

    /// Watch ssh stderr for the unmistakable key-auth failure and fail FAST
    /// with an actionable message instead of timing out 40 s later.
    private func checkAuthFailure(_ s: String) {
        guard status == .connecting else { return }
        if s.contains("Permission denied (publickey)")
            || s.contains("Too many authentication failures")
            || s.contains("No such identity")
            || s.contains("Host key verification failed")
            || s.contains("Connection closed by")           // Vast proxy rejects unknown key
            || s.contains("kex_exchange_identification") {
            CrashReporter.shared.breadcrumb("RemoteGPU.authFail: \(s.prefix(160))")
            append("\n❌ SSH key rejected.\n")
            status = .failed("SSH key not authorised yet. Click “Copy MicroCode SSH key”, paste it into your RunPod/Vast account (SSH Keys) once, then Connect again. (No need to manage your own .pem.)")
            disconnect(silent: true)
        }
    }

    // MARK: - Connect / Disconnect

    func connect(sshCommand: String, keyPath: String?) {
        guard status != .connecting else { return }
        disconnect(silent: true)
        guard let t = Self.parse(sshCommand: sshCommand, fallbackKey: keyPath) else {
            status = .failed("Couldn't read the SSH command. Paste the exact line your provider shows.")
            return
        }
        status = .connecting
        log = ""
        token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        CrashReporter.shared.breadcrumb("RemoteGPU.connect \(t.user)@\(t.host):\(t.port) key=\(t.keyPath ?? "none")")
        append("→ \(t.user)@\(t.host):\(t.port)\(t.keyPath.map { " (key: \(($0 as NSString).lastPathComponent))" } ?? "")\n")

        // 1) Launch Jupyter remotely (this ssh stays alive = the server).
        let remoteCmd = """
        (command -v jupyter >/dev/null 2>&1 || python3 -m pip install -q jupyter-server jupyterlab) ; \
        jupyter server --no-browser --ip=127.0.0.1 --port=\(remotePort) \
        --ServerApp.token='\(token)' --ServerApp.disable_check_xsrf=True --ServerApp.allow_origin='*'
        """
        let jp = Process()
        jp.executableURL = URL(fileURLWithPath: sshPath)
        jp.arguments = sshBaseArgs(t) + ["\(t.user)@\(t.host)", remoteCmd]
        let jpPipe = Pipe()
        jp.standardOutput = jpPipe
        jp.standardError = jpPipe
        jpPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            Task { @MainActor in self?.append(s); self?.checkAuthFailure(s) }
        }
        do { try jp.run(); jupyterProc = jp; append("• starting jupyter on the instance…\n") }
        catch { status = .failed("ssh failed: \(error.localizedDescription)"); return }

        // 2) After a moment, open the port-forward and poll readiness.
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            await self.openTunnelAndProbe(t)
        }
    }

    private func openTunnelAndProbe(_ t: Target) async {
        guard status == .connecting else { return }
        let tp = Process()
        tp.executableURL = URL(fileURLWithPath: sshPath)
        tp.arguments = sshBaseArgs(t) + ["-N", "-L",
            "\(localPort):127.0.0.1:\(remotePort)", "\(t.user)@\(t.host)"]
        let tpPipe = Pipe()
        tp.standardError = tpPipe
        tpPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            Task { @MainActor in self?.append("[tunnel] \(s)"); self?.checkAuthFailure(s) }
        }
        do { try tp.run(); tunnelProc = tp; append("• opening secure tunnel localhost:\(localPort) → remote:\(remotePort)…\n") }
        catch { status = .failed("Tunnel failed: \(error.localizedDescription)"); return }

        let base = "http://127.0.0.1:\(localPort)"
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard status == .connecting else { return }
            if let url = URL(string: "\(base)/api") {
                var r = URLRequest(url: url)
                r.timeoutInterval = 4
                r.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
                if let (_, resp) = try? await URLSession.shared.data(for: r),
                   let code = (resp as? HTTPURLResponse)?.statusCode,
                   code == 200 || code == 403 {
                    // Hand the tunneled server to the existing Jupyter kernel.
                    UserDefaults.standard.set(base, forKey: "hpcEndpoint")
                    UserDefaults.standard.set(token, forKey: "hpcToken")
                    localURL = base
                    status = .connected
                    CrashReporter.shared.breadcrumb("RemoteGPU.connected → \(base) (hpcEndpoint/hpcToken set)")
                    append("✅ Connected. Cells now run on the remote GPU.\n")
                    return
                }
            }
        }
        CrashReporter.shared.breadcrumb("RemoteGPU.timeout — jupyter never answered on \(base)")
        append("❌ Timed out waiting for the remote Jupyter server.\n")
        status = .failed("Timed out. Ensure Python/jupyter can run on the instance.")
        disconnect(silent: true)
    }

    func disconnect(silent: Bool = false) {
        tunnelProc?.terminate(); tunnelProc = nil
        jupyterProc?.terminate(); jupyterProc = nil
        localURL = ""
        if !silent {
            status = .disconnected
            append("• Disconnected.\n")
        }
    }
}
