//
//  PhoneCompanionService+NextGen.swift
//  MicroCode
//
//  Mobile Connect 2.0 Subsystem:
//  1. Smart Mac Keep-Awake (IOPMAssertion) while Mobile Companion / Agent is active
//  2. Tailscale / WireGuard Mesh VPN & MagicDNS Auto-Discovery
//  3. Lock-Screen Push Notification Bridge (ntfy.sh, Telegram, Discord/Slack/Custom Webhook)
//  4. Non-Blocking Mac Notifications & 6-Digit Numeric Pairing PIN Rate-Limited Verifier
//  5. Authenticated Live Preview Reverse Proxy (/preview/<port>/*) + 1-Tap Public Port Tunnel
//  6. Camera / Screenshot / File Upload Staging -> AIAttachment + Workspace @file Search/Reader
//  7. Mobile Git Review, Colored Unified Diff, Stage/Revert & AI Commit/Push
//  8. Mobile Quick Terminal & Auto-Detected Project Scripts Runner
//  9. Installable Fullscreen PWA Manifest, Service Worker & Touch Icon
//
//  Created by Dotmini Software
//

import Foundation
import AppKit
import Network
import IOKit.pwr_mgt
@preconcurrency import UserNotifications

// MARK: - 1. Tailscale & Push Models

struct TailscaleNodeInfo: Equatable {
    var isAvailable: Bool = false
    var ipv4: String = ""
    var magicDNSHostname: String = ""
    var tailnetName: String = ""

    var bestHost: String {
        if !magicDNSHostname.isEmpty { return magicDNSHostname }
        return ipv4
    }
}

enum MobilePushChannelType: String, CaseIterable, Codable, Identifiable {
    case disabled = "disabled"
    case ntfy = "ntfy"
    case telegram = "telegram"
    case webhook = "webhook"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled: return "Browser Only (In-App)"
        case .ntfy: return "ntfy.sh (1-Click Lock Screen)"
        case .telegram: return "Telegram Bot"
        case .webhook: return "Discord / Slack / Webhook"
        }
    }
}

struct MobilePushSettings: Codable, Equatable {
    var channel: MobilePushChannelType = .disabled
    var ntfyServerURL: String = "https://ntfy.sh"
    var ntfyTopic: String = ""
    var telegramBotToken: String = ""
    var telegramChatId: String = ""
    var webhookURL: String = ""
    var notifyOnApprovalNeeded: Bool = true
    var notifyOnTaskCompleted: Bool = true
    var notifyOnErrors: Bool = true

    static let defaultsKey = "microcode.phoneCompanion.pushSettings.v2"

    static func load() -> MobilePushSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(MobilePushSettings.self, from: data) else {
            var initial = MobilePushSettings()
            initial.ntfyTopic = generateRandomNtfyTopic()
            return initial
        }
        var copy = decoded
        if copy.ntfyTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.ntfyTopic = generateRandomNtfyTopic()
        }
        return copy
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    static func generateRandomNtfyTopic() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return "microcode-\(hex)"
    }
}

// MARK: - 2. Smart Mac Keep-Awake Manager (IOPMAssertion)

@MainActor
final class MobileSleepGuard {
    static let shared = MobileSleepGuard()
    private var assertionID: IOPMAssertionID = 0
    private(set) var isHoldingAssertion: Bool = false

    private init() {}

    func update(shouldHold: Bool, reason: String = "MicroCode Mobile Companion Active Session") -> Bool {
        if shouldHold && !isHoldingAssertion {
            var newID: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &newID
            )
            if result == kIOReturnSuccess {
                assertionID = newID
                isHoldingAssertion = true
            }
        } else if !shouldHold && isHoldingAssertion {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isHoldingAssertion = false
        }
        return isHoldingAssertion
    }
}

// MARK: - 3. PhoneCompanionService Next-Gen Extension

extension PhoneCompanionService {

    // MARK: - Keep-Awake Sync & Push Event Watcher

    func syncSleepAssertionAndPushEvents() {
        let agent = AgentService.shared
        let hasMobileClients = !sseConnections.isEmpty || connectedDevices.contains(where: {
            $0.approvalState == .approved && Date().timeIntervalSince($0.lastSeenAt) < 180
        })
        let shouldHoldSleep = isEnabled && preventMacSleepWhileActive && (hasMobileClients || agent.isLoading)
        let holding = MobileSleepGuard.shared.update(shouldHold: shouldHoldSleep)
        if isHoldingSleepAssertion != holding {
            isHoldingSleepAssertion = holding
        }

        evaluateAndDispatchPushEventsIfNeeded()
    }

    private func evaluateAndDispatchPushEventsIfNeeded() {
        guard isEnabled, pushSettings.channel != .disabled else {
            wasAgentLoadingLastTick = AgentService.shared.isLoading
            return
        }

        let agent = AgentService.shared
        let planMgr = ImplementationPlanManager.shared
        let toolMgr = ToolApprovalManager.shared
        let wsName: String = {
            let p = currentCompanionWorkspacePath()
            return p.isEmpty ? "MicroCode" : URL(fileURLWithPath: p).lastPathComponent
        }()

        // 1. Pending Tool Approval Alert
        if pushSettings.notifyOnApprovalNeeded, let req = toolMgr.pendingRequest {
            let key = "tool:\(req.id.uuidString)"
            if lastPushedEventKey != key {
                lastPushedEventKey = key
                Task {
                    await sendExternalPushNotification(
                        title: "⚠️ MicroCode Approval Needed (\(wsName))",
                        body: "Tool '\(req.toolName)' is waiting for your approval: \(req.description.prefix(120))",
                        priority: "high",
                        tags: "warning,wrench"
                    )
                }
            }
        }

        // 2. Pending Implementation Plan Alert
        if pushSettings.notifyOnApprovalNeeded,
           let plan = planMgr.currentPlan,
           plan.approvalState == .pending {
            let key = "plan:\(plan.title):\(plan.totalSteps)"
            if lastPushedEventKey != key {
                lastPushedEventKey = key
                Task {
                    await sendExternalPushNotification(
                        title: "📋 Plan Ready for Review (\(wsName))",
                        body: "\(plan.title) (\(plan.totalSteps) steps) — tap to review and proceed.",
                        priority: "high",
                        tags: "clipboard"
                    )
                }
            }
        }

        // 3. Agent Task Finished Transition
        if wasAgentLoadingLastTick && !agent.isLoading && pushSettings.notifyOnTaskCompleted {
            let lastAssistant = agent.messages.last(where: { $0.role == .assistant })?.content ?? ""
            let cleanSummary = AIStructuredTurnCodec.stripToolCallArtifacts(lastAssistant)
                .replacingOccurrences(of: #"<(?:thought|thinking|think)>[\s\S]*?</(?:thought|thinking|think)>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = cleanSummary.isEmpty ? "Agent finished executing steps in \(wsName)." : String(cleanSummary.prefix(160))
            let finishKey = "done:\(agent.activeChatId ?? ""):\(agent.messages.count)"
            if lastPushedEventKey != finishKey {
                lastPushedEventKey = finishKey
                Task {
                    await sendExternalPushNotification(
                        title: "✅ MicroCode Task Complete (\(wsName))",
                        body: snippet,
                        priority: "default",
                        tags: "white_check_mark"
                    )
                }
            }
        }

        wasAgentLoadingLastTick = agent.isLoading
    }

    // MARK: - External Push Sender (ntfy.sh / Telegram / Discord / Slack / Webhook)

    @discardableResult
    func sendExternalPushNotification(
        title: String,
        body: String,
        priority: String = "default",
        tags: String = "iphone"
    ) async -> (ok: Bool, message: String) {
        let cfg = pushSettings
        let clickURL = activeCompanionSessionURLForPush()

        switch cfg.channel {
        case .disabled:
            return (false, "Push channel is set to Browser Only.")

        case .ntfy:
            let base = cfg.ntfyServerURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let topic = cfg.ntfyTopic.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !base.isEmpty, !topic.isEmpty, let url = URL(string: "\(base)/\(topic)") else {
                return (false, "Invalid ntfy server URL or topic.")
            }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.httpMethod = "POST"
            req.setValue(title, forHTTPHeaderField: "Title")
            req.setValue(priority, forHTTPHeaderField: "Priority")
            req.setValue(tags, forHTTPHeaderField: "Tags")
            if !clickURL.isEmpty {
                req.setValue(clickURL, forHTTPHeaderField: "Click")
            }
            req.httpBody = Data(body.utf8)
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(code) {
                    return (true, "Sent push via ntfy (\(topic))")
                }
                return (false, "ntfy returned HTTP \(code)")
            } catch {
                return (false, "ntfy error: \(error.localizedDescription)")
            }

        case .telegram:
            let bot = cfg.telegramBotToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let chat = cfg.telegramChatId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bot.isEmpty, !chat.isEmpty,
                  let url = URL(string: "https://api.telegram.org/bot\(bot)/sendMessage") else {
                return (false, "Enter both Telegram Bot Token and Chat ID.")
            }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let textPayload = clickURL.isEmpty ? "\(title)\n\n\(body)" : "\(title)\n\n\(body)\n\n🔗 \(clickURL)"
            let payload: [String: Any] = [
                "chat_id": chat,
                "text": textPayload,
                "disable_web_page_preview": true
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                return (200..<300).contains(code)
                    ? (true, "Sent push to Telegram (\(chat))")
                    : (false, "Telegram returned HTTP \(code)")
            } catch {
                return (false, "Telegram error: \(error.localizedDescription)")
            }

        case .webhook:
            let raw = cfg.webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: raw), !raw.isEmpty else {
                return (false, "Enter a valid HTTPS Webhook URL.")
            }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let fullText = clickURL.isEmpty ? "**\(title)**\n\(body)" : "**\(title)**\n\(body)\n\(clickURL)"
            // Compatible simultaneously with Discord (`content`), Slack (`text`), and custom webhooks (`title`/`body`/`url`)
            let payload: [String: Any] = [
                "content": fullText,
                "text": fullText,
                "title": title,
                "body": body,
                "url": clickURL
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                return (200..<300).contains(code)
                    ? (true, "Webhook delivered (HTTP \(code))")
                    : (false, "Webhook returned HTTP \(code)")
            } catch {
                return (false, "Webhook error: \(error.localizedDescription)")
            }
        }
    }

    private func activeCompanionSessionURLForPush() -> String {
        switch connectionMode {
        case .online:
            if case .connected(let base, _) = tunnelState {
                return base
            }
        case .tailscale:
            if tailscaleInfo.isAvailable {
                return "http://\(tailscaleInfo.bestHost):\(listeningPort)"
            }
        case .lan:
            break
        }
        return "http://\(activeLANHost):\(listeningPort)"
    }

    // MARK: - Tailscale / WireGuard Auto-Detection

    func refreshTailscaleStatus() {
        let candidates = [
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            "/opt/homebrew/bin/tailscale",
            "/usr/local/bin/tailscale"
        ]
        let cgnatIP = allNetworkAddresses.first(where: { item in
            item.interface.hasPrefix("utun") && Self.isTailscaleCGNAT(item.ip)
        })?.ip ?? ""

        Task.detached(priority: .utility) {
            var detected = TailscaleNodeInfo()
            if !cgnatIP.isEmpty {
                detected.isAvailable = true
                detected.ipv4 = cgnatIP
            }

            if let bin = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: bin)
                proc.arguments = ["status", "--json"]
                let out = Pipe()
                proc.standardOutput = out
                proc.standardError = FileHandle.nullDevice
                if (try? proc.run()) != nil {
                    let deadline = Date().addingTimeInterval(2.5)
                    while proc.isRunning && Date() < deadline {
                        try? await Task.sleep(nanoseconds: 40_000_000)
                    }
                    if proc.isRunning { proc.terminate() }
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let backendState = (json["BackendState"] as? String) ?? ""
                        if backendState == "Running" {
                            if let selfNode = json["Self"] as? [String: Any] {
                                if let dns = selfNode["DNSName"] as? String {
                                    let cleanDNS = dns.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                                    if !cleanDNS.isEmpty {
                                        detected.magicDNSHostname = cleanDNS
                                        detected.isAvailable = true
                                    }
                                }
                                if let ips = selfNode["TailscaleIPs"] as? [String],
                                   let v4 = ips.first(where: { !$0.contains(":") }) {
                                    detected.ipv4 = v4
                                    detected.isAvailable = true
                                }
                            }
                            if let tailnet = (json["CurrentTailnet"] as? [String: Any])?["Name"] as? String {
                                detected.tailnetName = tailnet
                            }
                        }
                    }
                }
            }

            let finalInfo = detected
            await MainActor.run {
                if PhoneCompanionService.shared.tailscaleInfo != finalInfo {
                    PhoneCompanionService.shared.tailscaleInfo = finalInfo
                    PhoneCompanionService.shared.regenerateQRCode()
                }
            }
        }
    }

    nonisolated private static func isTailscaleCGNAT(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        // 100.64.0.0/10
        return parts[0] == 100 && parts[1] >= 64 && parts[1] <= 127
    }

    // MARK: - Non-Blocking Mac Notification & 6-Digit PIN Verification

    func notifyMacNewPendingDeviceNonBlocking(_ device: ConnectedPhoneDevice) {
        NSApp.requestUserAttention(.informationalRequest)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Mobile Companion Pairing Request"
            content.body = "\(device.name) (\(device.ipAddress) · \(device.connectionVia)) requested access. Open MicroCode → Phone to Approve, or enter PIN on phone."
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: "mc-phone-pair-\(device.id)",
                content: content,
                trigger: nil
            )
            center.add(req, withCompletionHandler: nil)
        }
    }

    func verifySixDigitPINAttempt(suppliedPIN: String, remoteIP: String, headers: [String: String]) -> (ok: Bool, error: String?) {
        let now = Date()
        // Prune expired lockouts
        pinFailedAttempts = pinFailedAttempts.filter { now.timeIntervalSince($0.value.lastAttempt) < 300 }
        if let record = pinFailedAttempts[remoteIP], record.count >= 6 {
            return (false, "Too many failed PIN attempts. Wait 5 minutes or scan the QR code on Mac.")
        }

        let normalizedSupplied = suppliedPIN.filter(\.isNumber)
        let normalizedActual = sixDigitPairingPIN.filter(\.isNumber)
        guard normalizedSupplied.count == 6,
              Self.constantTimeEquals(normalizedSupplied, normalizedActual) else {
            let prev = pinFailedAttempts[remoteIP]?.count ?? 0
            pinFailedAttempts[remoteIP] = (count: prev + 1, lastAttempt: now)
            return (false, "Incorrect 6-digit PIN.")
        }

        pinFailedAttempts.removeValue(forKey: remoteIP)
        let device = recordConnectedDevice(headers: headers, remoteIP: remoteIP, isLocalMac: false)
        approveDevice(id: device.id)
        // Rotate PIN after successful redemption so shoulder-surfed PINs cannot be reused
        regenerateSixDigitPIN()
        return (true, nil)
    }

    // MARK: - Authenticated Live Preview Reverse Proxy (/preview/<port>/*)

    func handlePreviewReverseProxy(
        method: String,
        rawTarget: String,
        headers: [String: String],
        bodyData: Data
    ) async -> Data {
        // Path format: /preview/<port> or /preview/<port>/subpath?query
        let stripped = rawTarget.dropFirst("/preview/".count)
        let slashIdx = stripped.firstIndex(of: "/")
        let qIdx = stripped.firstIndex(of: "?")
        let portEnd: Substring.Index = {
            switch (slashIdx, qIdx) {
            case let (s?, q?): return min(s, q)
            case let (s?, nil): return s
            case let (nil, q?): return q
            case (nil, nil): return stripped.endIndex
            }
        }()
        let portString = String(stripped[..<portEnd])
        guard let port = Int(portString), (1...65535).contains(port), port != Int(listeningPort) else {
            return makeHTTPResponse(
                status: "400 Bad Request",
                contentType: "text/plain; charset=utf-8",
                body: Data("Invalid preview port.".utf8)
            )
        }

        var remainder = String(stripped[portEnd...])
        if remainder.isEmpty {
            // Redirect `/preview/3000` -> `/preview/3000/` so relative assets resolve under `/preview/3000/`
            return makeHTTPResponse(
                status: "302 Found",
                contentType: "text/plain",
                extraHeaders: ["Location": "/preview/\(port)/"],
                body: Data()
            )
        }
        if remainder.hasPrefix("?") {
            remainder = "/" + remainder
        }

        guard let targetURL = URL(string: "http://127.0.0.1:\(port)\(remainder)") else {
            return makeHTTPResponse(
                status: "400 Bad Request",
                contentType: "text/plain; charset=utf-8",
                body: Data("Malformed preview URL.".utf8)
            )
        }

        var req = URLRequest(url: targetURL, timeoutInterval: 15)
        req.httpMethod = method
        let hopByHop: Set<String> = ["host", "connection", "accept-encoding", "content-length", "cookie", "x-companion-token"]
        for (k, v) in headers where !hopByHop.contains(k.lowercased()) {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.setValue("127.0.0.1:\(port)", forHTTPHeaderField: "Host")
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if !bodyData.isEmpty && method != "GET" && method != "HEAD" {
            req.httpBody = bodyData
        }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return makeHTTPResponse(status: "502 Bad Gateway", contentType: "text/plain", body: Data("Invalid upstream response".utf8))
            }
            let statusLine = "\(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode).capitalized)"
            let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream")
            var extra: [String: String] = [:]
            if let loc = http.value(forHTTPHeaderField: "Location"), loc.hasPrefix("/") {
                extra["Location"] = "/preview/\(port)\(loc)"
            }

            var outBody = data
            if contentType.lowercased().contains("text/html"), var html = String(data: data, encoding: .utf8) {
                let prefix = "/preview/\(port)"
                if !html.lowercased().contains("<base ") {
                    let baseTag = #"<base href="\#(prefix)/">"#
                    if let headRange = html.range(of: "<head>", options: .caseInsensitive) {
                        html.insert(contentsOf: baseTag, at: headRange.upperBound)
                    } else {
                        html = baseTag + html
                    }
                }
                // Rewrite root-anchored src="/..." and href="/..." (excluding // protocol-relative and already-prefixed /preview/)
                if let attrRegex = try? NSRegularExpression(pattern: #"(\b(?:src|href|action)\s*=\s*["'])/(?!/|preview/)"#, options: .caseInsensitive) {
                    let ns = html as NSString
                    html = attrRegex.stringByReplacingMatches(
                        in: html,
                        options: [],
                        range: NSRange(location: 0, length: ns.length),
                        withTemplate: "$1\(prefix)/"
                    )
                }
                outBody = Data(html.utf8)
            }

            return makeHTTPResponse(status: statusLine, contentType: contentType, extraHeaders: extra, body: outBody)
        } catch {
            let errHTML = """
            <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>body{background:#0d0d0f;color:#e4e4e7;font-family:-apple-system,sans-serif;padding:28px;text-align:center}
            .box{max-width:380px;margin:12vh auto;background:#16161a;border:1px solid rgba(255,255,255,0.1);border-radius:12px;padding:22px}
            code{background:rgba(255,255,255,0.08);padding:2px 6px;border-radius:4px}</style></head>
            <body><div class="box"><h3>Dev Server Offline on :\(port)</h3>
            <p style="color:#a1a1aa;font-size:13px">Nothing is currently listening on <code>127.0.0.1:\(port)</code> on your Mac. Start your dev server from the <b>Term</b> tab or ask the AI Agent to run it.</p></div></body></html>
            """
            return makeHTTPResponse(status: "502 Bad Gateway", contentType: "text/html; charset=utf-8", body: Data(errHTML.utf8))
        }
    }

    func buildPreviewPortsPayload() -> [String: Any] {
        var portsSet = Set<Int>()
        if let p = DeviceRuntimeService.shared.targetWebURL?.port { portsSet.insert(p) }
        if let p = DeviceRuntimeService.shared.lastDetectedDevServerPort { portsSet.insert(p) }
        for proc in IDEBrowserAutomationService.shared.activePortProcesses {
            portsSet.insert(proc.port)
        }
        for p in DevPortTunnelService.shared.tunnels.keys {
            portsSet.insert(p)
        }
        portsSet.remove(Int(listeningPort))
        portsSet.remove(8470)
        portsSet.remove(8471)

        let sortedPorts = portsSet.sorted()
        let items: [[String: Any]] = sortedPorts.map { p in
            var tunnelURL = ""
            var tunnelStatus = "stopped"
            if let st = DevPortTunnelService.shared.tunnels[p] {
                switch st {
                case .connected(let u, _):
                    tunnelURL = u
                    tunnelStatus = "connected"
                case .starting(let msg):
                    tunnelStatus = msg
                case .failed(let err):
                    tunnelStatus = "failed: \(err)"
                case .stopped:
                    tunnelStatus = "stopped"
                }
            }
            return [
                "port": p,
                "proxyPath": "/preview/\(p)/",
                "lanURL": activeLANHost != "127.0.0.1" ? "http://\(activeLANHost):\(p)/" : "",
                "publicTunnelURL": tunnelURL,
                "tunnelStatus": tunnelStatus
            ]
        }
        return ["ok": true, "ports": items]
    }

    // MARK: - Camera, Screenshot & File Attachments Builder

    func buildMobileAttachments(from rawItems: [[String: Any]]) -> [AIAttachment] {
        guard !rawItems.isEmpty else { return [] }
        let stagingDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("MicroCodeMobileUploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        var built: [AIAttachment] = []
        for item in rawItems.prefix(8) {
            let rawName = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "upload.bin"
            let safeName = URL(fileURLWithPath: rawName).lastPathComponent
            let mime = (item["mimeType"] as? String)?.lowercased() ?? "application/octet-stream"
            guard var b64 = item["dataBase64"] as? String, !b64.isEmpty else { continue }
            if let comma = b64.firstIndex(of: ","), b64[..<comma].contains("base64") {
                b64 = String(b64[b64.index(after: comma)...])
            }
            guard let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters), !data.isEmpty else { continue }

            let ext = (safeName as NSString).pathExtension.lowercased()
            let uniqueFile = stagingDir.appendingPathComponent("\(UUID().uuidString.prefix(8))-\(safeName)")
            try? data.write(to: uniqueFile, options: .atomic)

            if mime.hasPrefix("image/") || ["png", "jpg", "jpeg", "webp", "gif", "heic"].contains(ext) {
                let fmt = ext.isEmpty ? "jpeg" : ext
                let thumb = AIAttachment.makeFastThumbnail(from: data)
                built.append(AIAttachment(
                    name: safeName,
                    data: data,
                    type: .image(format: fmt),
                    sourceURL: uniqueFile,
                    stagedPath: uniqueFile.path,
                    subtitleBadge: fmt.uppercased(),
                    normalizedVisionData: data,
                    normalizedVisionMimeType: mime.hasPrefix("image/") ? mime : "image/jpeg",
                    nativeMediaMimeType: mime.hasPrefix("image/") ? mime : "image/jpeg",
                    fileSizeBytes: Int64(data.count),
                    semanticCategory: .image,
                    previewThumbnail: thumb
                ))
            } else if mime == "application/pdf" || ext == "pdf" {
                built.append(AIAttachment(
                    name: safeName,
                    data: data,
                    type: .pdf,
                    sourceURL: uniqueFile,
                    stagedPath: uniqueFile.path,
                    subtitleBadge: "PDF",
                    nativeMediaMimeType: "application/pdf",
                    fileSizeBytes: Int64(data.count),
                    semanticCategory: .pdf
                ))
            } else {
                let textPreview = String(data: data.prefix(120_000), encoding: .utf8)
                built.append(AIAttachment(
                    name: safeName,
                    data: data,
                    type: .text,
                    sourceURL: uniqueFile,
                    stagedPath: uniqueFile.path,
                    extractedFullText: textPreview,
                    subtitleBadge: ext.isEmpty ? "FILE" : ext.uppercased(),
                    fileSizeBytes: Int64(data.count),
                    semanticCategory: .codeOrText
                ))
            }
        }
        return built
    }

    // MARK: - Workspace File Search (@mention) & File Viewer

    func searchWorkspaceFiles(query: String, limit: Int = 40) -> [[String: Any]] {
        let wsPath = currentCompanionWorkspacePath()
        guard !wsPath.isEmpty, wsPath != "__general__" else { return [] }
        let rootURL = URL(fileURLWithPath: wsPath).standardizedFileURL
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let ignoredDirs: Set<String> = [
            ".git", "node_modules", ".build", ".codetuner-build", "target",
            "DerivedData", "Pods", ".next", "dist", "build", "__pycache__", ".venv", "venv"
        ]

        var matches: [[String: Any]] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var scanned = 0
        while let fileURL = enumerator.nextObject() as? URL {
            scanned += 1
            if scanned > 6000 || matches.count >= limit { break }
            let name = fileURL.lastPathComponent
            if ignoredDirs.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            let vals = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if vals?.isDirectory == true { continue }

            let fullPath = fileURL.standardizedFileURL.path
            guard fullPath.hasPrefix(rootURL.path + "/") else { continue }
            let relPath = String(fullPath.dropFirst(rootURL.path.count + 1))

            if q.isEmpty || relPath.lowercased().contains(q) || name.lowercased().contains(q) {
                matches.append([
                    "name": name,
                    "path": relPath,
                    "ext": fileURL.pathExtension.lowercased(),
                    "size": vals?.fileSize ?? 0
                ])
            }
        }
        return matches
    }

    func readWorkspaceFileSafe(relativePath: String) -> [String: Any] {
        let wsPath = currentCompanionWorkspacePath()
        guard !wsPath.isEmpty, wsPath != "__general__" else {
            return ["ok": false, "error": "No active workspace selected."]
        }
        let rootURL = URL(fileURLWithPath: wsPath).standardizedFileURL
        let cleanRel = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let targetURL = rootURL.appendingPathComponent(cleanRel).standardizedFileURL
        guard targetURL.path.hasPrefix(rootURL.path + "/") else {
            return ["ok": false, "error": "Access outside workspace is denied."]
        }
        guard let data = try? Data(contentsOf: targetURL) else {
            return ["ok": false, "error": "Could not read file."]
        }
        let truncated = data.count > 120_000
        let slice = truncated ? data.prefix(120_000) : data[...]
        guard let content = String(data: slice, encoding: .utf8) else {
            return ["ok": false, "error": "Binary file (\(data.count) bytes) — cannot render as text."]
        }
        return [
            "ok": true,
            "path": cleanRel,
            "name": targetURL.lastPathComponent,
            "content": content,
            "truncated": truncated,
            "size": data.count
        ]
    }

    // MARK: - Mobile Git Suite (Status, Diff, Stage, Revert, AI Commit, Push/Pull)

    private nonisolated static func runCommandAsync(
        executable: String,
        arguments: [String],
        cwd: String,
        timeout: TimeInterval = 20
    ) async -> (exitCode: Int32, stdout: String, stderr: String, durationMs: Int) {
        await Task.detached(priority: .userInitiated) {
            let start = DispatchTime.now()
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: executable)
            proc.arguments = arguments
            proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
            var env = ProcessInfo.processInfo.environment
            env["GIT_TERMINAL_PROMPT"] = "0"
            env["TERM"] = "dumb"
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
            proc.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            proc.standardInput = FileHandle.nullDevice

            do {
                try proc.run()
            } catch {
                return (-1, "", error.localizedDescription, 0)
            }

            async let outRead: Data = Task.detached(priority: .userInitiated) {
                outPipe.fileHandleForReading.readDataToEndOfFile()
            }.value
            async let errRead: Data = Task.detached(priority: .userInitiated) {
                errPipe.fileHandleForReading.readDataToEndOfFile()
            }.value

            let deadline = Date().addingTimeInterval(timeout)
            while proc.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            var timedOut = false
            if proc.isRunning {
                timedOut = true
                proc.terminate()
            }
            let outData = await outRead
            let errData = await errRead
            let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
            let outStr = String(decoding: outData.prefix(200_000), as: UTF8.self)
            var errStr = String(decoding: errData.prefix(80_000), as: UTF8.self)
            if timedOut {
                errStr += "\n[Timed out after \(Int(timeout))s]"
            }
            return (timedOut ? 124 : proc.terminationStatus, outStr, errStr, elapsedMs)
        }.value
    }

    func handleGitStatus() async -> [String: Any] {
        let wsPath = currentCompanionWorkspacePath()
        guard !wsPath.isEmpty, wsPath != "__general__" else {
            return ["ok": false, "error": "No active workspace folder."]
        }
        let res = await Self.runCommandAsync(
            executable: "/usr/bin/git",
            arguments: ["status", "--porcelain=v1", "-b"],
            cwd: wsPath,
            timeout: 8
        )
        guard res.exitCode == 0 else {
            return ["ok": false, "error": res.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not a git repository." : res.stderr]
        }

        var branch = "HEAD"
        var ahead = 0
        var behind = 0
        var files: [[String: Any]] = []

        for line in res.stdout.components(separatedBy: "\n") where !line.isEmpty {
            if line.hasPrefix("## ") {
                let header = String(line.dropFirst(3))
                branch = header.components(separatedBy: "...").first?.components(separatedBy: " ").first ?? header
                if let m = header.range(of: #"ahead (\d+)"#, options: .regularExpression) {
                    ahead = Int(header[m].dropFirst(6)) ?? 0
                }
                if let m = header.range(of: #"behind (\d+)"#, options: .regularExpression) {
                    behind = Int(header[m].dropFirst(7)) ?? 0
                }
                continue
            }
            guard line.count >= 3 else { continue }
            let idxChar = String(line.prefix(1))
            let wtChar = String(line.dropFirst(1).prefix(1))
            var rawPath = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if let arrow = rawPath.range(of: " -> ") {
                rawPath = String(rawPath[arrow.upperBound...])
            }
            rawPath = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let staged = (idxChar != " " && idxChar != "?")
            let statusBadge: String = {
                if idxChar == "?" { return "U" }
                if idxChar == "A" || wtChar == "A" { return "A" }
                if idxChar == "D" || wtChar == "D" { return "D" }
                if idxChar == "R" { return "R" }
                return "M"
            }()
            files.append([
                "path": rawPath,
                "status": statusBadge,
                "staged": staged,
                "untracked": idxChar == "?"
            ])
        }

        return [
            "ok": true,
            "branch": branch,
            "ahead": ahead,
            "behind": behind,
            "files": files
        ]
    }

    func handleGitDiff(filePath: String, staged: Bool) async -> [String: Any] {
        let wsPath = currentCompanionWorkspacePath()
        guard !wsPath.isEmpty, wsPath != "__general__" else {
            return ["ok": false, "error": "No active workspace."]
        }
        let clean = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        var args = ["diff"]
        if staged { args.append("--cached") }
        if !clean.isEmpty {
            args.append("--")
            args.append(clean)
        }
        let res = await Self.runCommandAsync(executable: "/usr/bin/git", arguments: args, cwd: wsPath, timeout: 10)
        var diffText = res.stdout
        if diffText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !clean.isEmpty && !staged {
            // Check if untracked file -> render synthetic + diff preview
            let fileRes = readWorkspaceFileSafe(relativePath: clean)
            if let content = fileRes["content"] as? String {
                let plusLines = content.components(separatedBy: "\n").prefix(200).map { "+\($0)" }.joined(separator: "\n")
                diffText = "--- /dev/null\n+++ b/\(clean)\n@@ -0,0 +1 @@\n\(plusLines)"
            }
        }
        return [
            "ok": res.exitCode == 0,
            "path": clean,
            "diff": String(diffText.prefix(100_000))
        ]
    }

    func handleGitAction(action: String, body: [String: Any]) async -> [String: Any] {
        let wsPath = currentCompanionWorkspacePath()
        guard !wsPath.isEmpty, wsPath != "__general__" else {
            return ["ok": false, "error": "No active workspace."]
        }
        let targetFile = (body["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch action {
        case "stage":
            let args = targetFile.isEmpty ? ["add", "-A"] : ["add", "--", targetFile]
            let r = await Self.runCommandAsync(executable: "/usr/bin/git", arguments: args, cwd: wsPath)
            return ["ok": r.exitCode == 0, "message": r.exitCode == 0 ? "Staged" : r.stderr]

        case "unstage":
            let args = targetFile.isEmpty ? ["reset", "HEAD"] : ["reset", "HEAD", "--", targetFile]
            let r = await Self.runCommandAsync(executable: "/usr/bin/git", arguments: args, cwd: wsPath)
            return ["ok": r.exitCode == 0, "message": r.exitCode == 0 ? "Unstaged" : r.stderr]

        case "revert":
            guard !targetFile.isEmpty else {
                return ["ok": false, "error": "Specify a file path to revert."]
            }
            // Check if untracked first
            let st = await Self.runCommandAsync(executable: "/usr/bin/git", arguments: ["ls-files", "--error-unmatch", "--", targetFile], cwd: wsPath)
            if st.exitCode != 0 {
                let rootURL = URL(fileURLWithPath: wsPath).standardizedFileURL
                let fileURL = rootURL.appendingPathComponent(targetFile).standardizedFileURL
                if fileURL.path.hasPrefix(rootURL.path + "/") {
                    try? FileManager.default.removeItem(at: fileURL)
                    return ["ok": true, "message": "Removed untracked file \(targetFile)"]
                }
                return ["ok": false, "error": "Invalid path."]
            }
            let r = await Self.runCommandAsync(executable: "/usr/bin/git", arguments: ["checkout", "--", targetFile], cwd: wsPath)
            return ["ok": r.exitCode == 0, "message": r.exitCode == 0 ? "Reverted \(targetFile)" : r.stderr]

        case "commit":
            let msg = (body["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !msg.isEmpty else {
                return ["ok": false, "error": "Commit message cannot be empty."]
            }
            _ = await Self.runCommandAsync(executable: "/usr/bin/git", arguments: ["add", "-A"], cwd: wsPath)
            let r = await Self.runCommandAsync(executable: "/usr/bin/git", arguments: ["commit", "-m", msg], cwd: wsPath, timeout: 20)
            return ["ok": r.exitCode == 0, "message": r.exitCode == 0 ? r.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : r.stderr]

        case "ai-message":
            let diffStat = await Self.runCommandAsync(executable: "/usr/bin/git", arguments: ["status", "-s"], cwd: wsPath)
            let diffBody = await Self.runCommandAsync(executable: "/usr/bin/git", arguments: ["diff", "HEAD"], cwd: wsPath)
            let sample = String((diffStat.stdout + "\n" + diffBody.stdout).prefix(6000))
            guard !sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ["ok": false, "error": "No working tree changes to summarize."]
            }
            let state = appState ?? AppState.shared
            let provStr = state?.aiProvider ?? "gemini"
            let modelStr = state?.aiModel ?? "gemini-2.5-flash"
            let apiKey = state?.resolveApiKey(for: provStr) ?? ""
            let streamProv = StreamableAIProvider(rawValue: provStr) ?? StreamableAIProvider.detect(from: modelStr)
            do {
                let generated = try await AIClient.shared.sendSync(
                    messages: [[("role", "user"), ("content", "Write a concise single-line Conventional Commit message (e.g. feat: ..., fix: ...) for these git changes. Output ONLY the commit message line without quotes or markdown:\n\n\(sample)")]],
                    systemPrompt: "You generate crisp, accurate single-line git commit messages.",
                    provider: streamProv,
                    model: modelStr,
                    apiKey: apiKey
                )
                let cleanLine = generated.text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "`\"'"))
                    .components(separatedBy: .newlines).first ?? ""
                return ["ok": !cleanLine.isEmpty, "message": cleanLine]
            } catch {
                return ["ok": false, "error": error.localizedDescription]
            }

        case "push":
            let r = await Self.runCommandAsync(executable: "/usr/bin/git", arguments: ["push"], cwd: wsPath, timeout: 30)
            return ["ok": r.exitCode == 0, "message": (r.stdout + "\n" + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)]

        case "pull":
            let r = await Self.runCommandAsync(executable: "/usr/bin/git", arguments: ["pull", "--ff-only"], cwd: wsPath, timeout: 30)
            return ["ok": r.exitCode == 0, "message": (r.stdout + "\n" + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)]

        default:
            return ["ok": false, "error": "Unknown git action."]
        }
    }

    // MARK: - Mobile Quick Terminal & Project Scripts Discovery

    func discoverWorkspaceQuickScripts() -> [[String: String]] {
        let wsPath = currentCompanionWorkspacePath()
        guard !wsPath.isEmpty, wsPath != "__general__" else {
            return [
                ["label": "uname -a", "cmd": "uname -a"],
                ["label": "top processes", "cmd": "ps aux | head -n 15"]
            ]
        }
        let fm = FileManager.default
        let root = URL(fileURLWithPath: wsPath)
        var scripts: [[String: String]] = []

        if fm.fileExists(atPath: root.appendingPathComponent("build_dev.sh").path) {
            scripts.append(["label": "./build_dev.sh", "cmd": "./build_dev.sh"])
        }
        if fm.fileExists(atPath: root.appendingPathComponent("package.json").path),
           let data = try? Data(contentsOf: root.appendingPathComponent("package.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let pkgScripts = json["scripts"] as? [String: String] {
            let runner = fm.fileExists(atPath: root.appendingPathComponent("pnpm-lock.yaml").path) ? "pnpm"
                : (fm.fileExists(atPath: root.appendingPathComponent("bun.lockb").path) ? "bun run" : "npm run")
            for key in ["dev", "build", "test", "lint", "start"] where pkgScripts[key] != nil {
                scripts.append(["label": "\(runner) \(key)", "cmd": "\(runner) \(key)"])
            }
        }
        if fm.fileExists(atPath: root.appendingPathComponent("Package.swift").path) {
            scripts.append(["label": "swift build", "cmd": "swift build"])
            scripts.append(["label": "swift test", "cmd": "swift test"])
        }
        if fm.fileExists(atPath: root.appendingPathComponent("Cargo.toml").path) {
            scripts.append(["label": "cargo check", "cmd": "cargo check"])
            scripts.append(["label": "cargo test", "cmd": "cargo test"])
        }
        if fm.fileExists(atPath: root.appendingPathComponent("pyproject.toml").path) || fm.fileExists(atPath: root.appendingPathComponent("pytest.ini").path) {
            scripts.append(["label": "pytest", "cmd": "pytest"])
        }
        scripts.append(["label": "git status", "cmd": "git status -sb"])
        scripts.append(["label": "git log -5", "cmd": "git log --oneline -n 5"])
        return Array(scripts.prefix(10))
    }

    func executeMobileTerminalCommand(_ rawCommand: String) async -> [String: Any] {
        let cmd = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else {
            return ["ok": false, "error": "Empty command."]
        }
        let wsPath = currentCompanionWorkspacePath()
        let cwd = (!wsPath.isEmpty && wsPath != "__general__")
            ? wsPath
            : FileManager.default.homeDirectoryForCurrentUser.path

        let res = await Self.runCommandAsync(
            executable: "/bin/zsh",
            arguments: ["-c", cmd],
            cwd: cwd,
            timeout: 35
        )
        let combined = [res.stdout, res.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: res.stdout.isEmpty ? "" : "\n")
        // Strip ANSI escape sequences so mobile output renders cleanly
        let cleanOutput: String = {
            if let ansi = try? NSRegularExpression(pattern: #"\x1B\[[0-9;]*[A-Za-z]"#, options: []) {
                let ns = combined as NSString
                return ansi.stringByReplacingMatches(in: combined, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
            }
            return combined
        }()
        return [
            "ok": res.exitCode == 0,
            "exitCode": res.exitCode,
            "durationMs": res.durationMs,
            "cwd": cwd,
            "output": cleanOutput.isEmpty ? "(Command exited with code \(res.exitCode), no output)" : cleanOutput
        ]
    }

    // MARK: - Fullscreen Installable PWA Assets (/manifest.json, /sw.js, /apple-touch-icon.png)

    func buildPWAManifestJSON() -> Data {
        let manifest: [String: Any] = [
            "name": "MicroCode AI Companion",
            "short_name": "MicroCode",
            "description": "Remote AI Agent Workstation, Diff Reviewer, Live Preview & Terminal for MicroCode",
            "start_url": "/",
            "display": "standalone",
            "orientation": "portrait",
            "background_color": "#0d0d0f",
            "theme_color": "#141417",
            "icons": [
                [
                    "src": "/apple-touch-icon.png",
                    "sizes": "180x180",
                    "type": "image/png",
                    "purpose": "any maskable"
                ]
            ]
        ]
        return (try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted])) ?? Data("{}".utf8)
    }

    func buildPWAServiceWorkerJS() -> Data {
        let js = """
        self.addEventListener('install', (e) => { self.skipWaiting(); });
        self.addEventListener('activate', (e) => { e.waitUntil(self.clients.claim()); });
        self.addEventListener('notificationclick', (event) => {
          event.notification.close();
          event.waitUntil(
            self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
              for (const client of clientList) {
                if ('focus' in client) return client.focus();
              }
              if (self.clients.openWindow) return self.clients.openWindow('/');
            })
          );
        });
        """
        return Data(js.utf8)
    }

    func buildTouchIconPNGData() -> Data {
        let size = NSSize(width: 180, height: 180)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.09, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        if let appIcon = NSApp.applicationIconImage {
            appIcon.draw(in: NSRect(x: 14, y: 14, width: 152, height: 152))
        }
        img.unlockFocus()
        if let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        return Data()
    }
}
