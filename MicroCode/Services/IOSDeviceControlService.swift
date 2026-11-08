//
//  IOSDeviceControlService.swift
//  MicroCode
//
//  Native USB Direct Touch & Control Engine for physical iPhones and iPads inside MicroCode Preview.
//  Architecture (Zero iPhone Mirroring.app dependency):
//    1. CoreDevice USB Tunnel + WDA/XCTest HID Engine (Port 8100 over USB tunnel IP or localhost iproxy)
//       — System-wide multi-touch, tap, drag/swipe, trackpad scroll, hardware buttons & keyboard for iPhone & iPad.
//    2. MicroCode In-App Live Touch Bridge (Port 8101 over CoreDevice USB tunnel IP or localhost)
//       — Zero-configuration direct UIWindow touch/gesture/keyboard injection inside the developer's app.
//    3. Direct Apple CoreDevice (`xcrun devicectl`) USB Control
//       — Process launch, deep links, URL opening, pasteboard sync, and Darwin notifications.
//    4. Optional Continuity CGEvent Forwarding (strictly opt-in; never auto-opens iPhone Mirroring.app).
//

import Foundation
import AppKit
import Quartz

@MainActor
final class IOSDeviceControlService: ObservableObject {
    static let shared = IOSDeviceControlService()

    enum ControlTransportMode: String {
        case usbHID = "USB Direct HID"
        case inAppBridge = "USB App Bridge"
        case coreDevice = "USB CoreDevice"
        case continuityOptIn = "Continuity (Opt-in)"
    }

    @Published var isControlActive = false
    @Published var lastActionStatus = "USB Direct Ready"
    @Published var deviceUDID: String? = nil
    @Published var deviceModelName: String = "iPhone / iPad"
    @Published var isIPadDevice: Bool = false
    @Published var coreDeviceTunnelIP: String? = nil
    @Published var activeTransport: ControlTransportMode = .coreDevice
    @Published var isUSBHIDConnected: Bool = false
    @Published var isInAppBridgeConnected: Bool = false
    @Published var isMirroringRunning = false
    /// Strictly false by default so MicroCode NEVER pops open iPhone Mirroring.app
    @Published var allowMirroringFallback: Bool = false

    /// Logical screen size in iOS/iPadOS points (auto-detected from WDA or device resolution)
    @Published var logicalScreenSize: CGSize = CGSize(width: 393, height: 852)
    /// Last normalized cursor position on the Preview canvas (used for localized trackpad scrolling)
    var lastCursorNormalizedPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    private var wdaSessionID: String? = nil
    private var resolvedWDAEndpoint: String? = nil
    private var resolvedAppBridgeEndpoint: String? = nil
    private var iproxyProcess: Process? = nil
    private var isProbingTransport = false

    private nonisolated static let controlSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8.0
        cfg.timeoutIntervalForResource = 12.0
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    struct MirrorWindowInfo {
        let pid: pid_t
        let bounds: CGRect
    }

    private init() {
        discoverPhysicalUDID()
    }

    // MARK: - Coordinate Mapping (Normalized 0..1 -> iOS/iPadOS Logical Points)

    /// Real logical size reported by WDA / in-app bridge (portrait-native); never overwritten by guesses.
    private var reportedNativeSize: CGSize? = nil
    private var lastCaptureLandscape: Bool? = nil

    private func applyReportedSize(_ size: CGSize) {
        reportedNativeSize = size
        alignReportedSizeToCapture()
    }

    private func alignReportedSizeToCapture() {
        guard let native = reportedNativeSize else { return }
        var w = native.width, h = native.height
        if let land = lastCaptureLandscape, (w > h) != land { swap(&w, &h) }
        logicalScreenSize = CGSize(width: w, height: h)
    }

    func updateLogicalScreenSizeIfNeeded(capturePixelSize: CGSize) {
        guard capturePixelSize.width > 0, capturePixelSize.height > 0 else { return }
        let landscape = capturePixelSize.width > capturePixelSize.height
        if lastCaptureLandscape != landscape {
            lastCaptureLandscape = landscape
            alignReportedSizeToCapture()
        }
        if reportedNativeSize != nil { return }
        let aspect = capturePixelSize.width / capturePixelSize.height
        if aspect > 0.65 {
            // iPad Portrait or Landscape
            if capturePixelSize.width > capturePixelSize.height {
                logicalScreenSize = CGSize(width: 1180, height: 820)
            } else {
                logicalScreenSize = CGSize(width: 820, height: 1180)
            }
            isIPadDevice = true
        } else {
            // iPhone Portrait / Landscape
            let scale: CGFloat = 3.0
            let ptW = max(320, min(1366, (capturePixelSize.width / scale).rounded()))
            let ptH = max(568, min(1366, (capturePixelSize.height / scale).rounded()))
            logicalScreenSize = CGSize(width: ptW, height: ptH)
        }
    }

    private func logicalPoint(normalizedX: CGFloat, normalizedY: CGFloat) -> CGPoint {
        let clampedX = max(0.0, min(1.0, normalizedX))
        let clampedY = max(0.0, min(1.0, normalizedY))
        return CGPoint(
            x: (clampedX * logicalScreenSize.width).rounded(),
            y: (clampedY * logicalScreenSize.height).rounded()
        )
    }

    // MARK: - 1. Native USB Direct Touch, Swipe, Scroll & Keyboard (No iPhone Mirroring.app)

    /// Handle real-time mouse/touch down/move/up from `DeviceMetalNSView`
    func sendTouchEvent(normalizedX: CGFloat, normalizedY: CGFloat, phase: String) {
        lastCursorNormalizedPoint = CGPoint(x: normalizedX, y: normalizedY)
        if let appBridge = resolvedAppBridgeEndpoint {
            let pt = logicalPoint(normalizedX: normalizedX, normalizedY: normalizedY)
            postJSONFireAndForget(
                urlString: "\(appBridge)/microcode/touch",
                payload: [
                    "phase": phase,
                    "x": pt.x,
                    "y": pt.y,
                    "normX": normalizedX,
                    "normY": normalizedY
                ]
            )
        }
    }

    /// Direct tap inside MicroCode's iPhone/iPad Preview screen over USB (NEVER opens iPhone Mirroring.app)
    func sendTap(normalizedX: CGFloat, normalizedY: CGFloat) {
        lastCursorNormalizedPoint = CGPoint(x: normalizedX, y: normalizedY)
        let pt = logicalPoint(normalizedX: normalizedX, normalizedY: normalizedY)
        lastActionStatus = "USB Tap (\(Int(pt.x)), \(Int(pt.y)))"

        enqueueGesture { [self] in
            // Engine 1: USB WDA / XCTest HID Runner (System-wide iPhone & iPad touch)
            if await dispatchWDATap(point: pt) {
                activeTransport = .usbHID
                isControlActive = true
                return
            }

            // Engine 2: MicroCode In-App Live Touch Bridge (Port 8101 over CoreDevice USB tunnel / localhost)
            if await dispatchInAppBridgeTap(point: pt, normX: normalizedX, normY: normalizedY) {
                activeTransport = .inAppBridge
                isControlActive = true
                return
            }

            // Engine 3: Optional Continuity Window Forwarding ONLY if user explicitly opted in and window exists
            if allowMirroringFallback, let info = getMirroringWindowInfo() {
                activeTransport = .continuityOptIn
                forwardCGEventTap(to: info, normalizedX: normalizedX, normalizedY: normalizedY)
                return
            }

            // Probe USB transports in background and inform user in toolbar status
            await probeUSBControlTransports()
            if isUSBHIDConnected {
                _ = await dispatchWDATap(point: pt)
            } else if isInAppBridgeConnected {
                _ = await dispatchInAppBridgeTap(point: pt, normX: normalizedX, normY: normalizedY)
            } else {
                lastActionStatus = "Tap (\(Int(pt.x)), \(Int(pt.y))) · Click 'USB Touch' in toolbar to activate HID"
            }
        }
    }

    /// Direct drag/swipe gesture inside MicroCode's iPhone/iPad Preview screen over USB
    func sendSwipe(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat, durationMs: Int = 180, fromScroll: Bool = false) {
        if !fromScroll { lastCursorNormalizedPoint = CGPoint(x: toX, y: toY) }
        let startPt = logicalPoint(normalizedX: fromX, normalizedY: fromY)
        let endPt = logicalPoint(normalizedX: toX, normalizedY: toY)
        lastActionStatus = "USB Swipe (\(Int(startPt.x)),\(Int(startPt.y)) → \(Int(endPt.x)),\(Int(endPt.y)))"

        enqueueGesture { [self] in
            // Detect bottom-edge Home / App Switcher swipe gesture natively!
            if fromY > 0.93 && toY < 0.78 && abs(toX - fromX) < 0.25 {
                if durationMs > 320 && toY < 0.68 {
                    openAppSwitcher()
                    return
                } else {
                    goHome()
                    return
                }
            }

            // Engine 1: USB WDA / XCTest HID Runner
            if await dispatchWDASwipe(from: startPt, to: endPt, durationMs: durationMs) {
                activeTransport = .usbHID
                isControlActive = true
                return
            }

            // Engine 2: MicroCode In-App Live Touch Bridge
            if await dispatchInAppBridgeSwipe(from: startPt, to: endPt, durationMs: durationMs) {
                activeTransport = .inAppBridge
                isControlActive = true
                return
            }

            // Engine 3: Optional Continuity Window Forwarding (opt-in only)
            if allowMirroringFallback, let info = getMirroringWindowInfo() {
                forwardCGEventSwipe(to: info, fromX: fromX, fromY: fromY, toX: toX, toY: toY, durationMs: durationMs)
                return
            }

            await probeUSBControlTransports()
        }
    }

    private var gestureTail: Task<Void, Never>? = nil

    /// Run gestures strictly one after another so touches never overlap or reorder.
    private func enqueueGesture(_ op: @escaping @MainActor () async -> Void) {
        let prev = gestureTail
        gestureTail = Task { @MainActor in
            await prev?.value
            await op()
        }
    }

    /// Track the pointer so scroll gestures start under the cursor.
    func updateCursor(normalizedX: CGFloat, normalizedY: CGFloat) {
        lastCursorNormalizedPoint = CGPoint(x: normalizedX, y: normalizedY)
    }

    private var pendingScrollDX: CGFloat = 0
    private var pendingScrollDY: CGFloat = 0
    private var scrollFlushScheduled = false

    /// Convert Mac trackpad / mouse scroll wheel into ONE smooth touch scroll per ~120 ms (coalesced).
    func sendScroll(deltaX: CGFloat, deltaY: CGFloat) {
        pendingScrollDX += deltaX
        pendingScrollDY += deltaY
        guard !scrollFlushScheduled else { return }
        scrollFlushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self else { return }
            let dx = self.pendingScrollDX, dy = self.pendingScrollDY
            self.pendingScrollDX = 0; self.pendingScrollDY = 0
            self.scrollFlushScheduled = false
            guard abs(dx) > 1 || abs(dy) > 1 else { return }
            let startX = self.lastCursorNormalizedPoint.x
            let startY = self.lastCursorNormalizedPoint.y
            let endX = max(0.04, min(0.96, startX + max(-0.5, min(0.5, dx / 500.0))))
            let endY = max(0.06, min(0.94, startY + max(-0.6, min(0.6, dy / 500.0))))
            self.sendSwipe(fromX: startX, fromY: startY, toX: endX, toY: endY, durationMs: 90, fromScroll: true)
        }
    }

    /// Direct physical Mac keyboard forwarding over USB to iPhone / iPad
    func sendKey(_ event: NSEvent) {
        switch event.keyCode {
        case 36: // Return / Enter
            sendText("\n")
        case 51: // Delete / Backspace
            sendText("\u{0008}")
        case 53: // Escape -> Home screen
            goHome()
        default:
            if event.modifierFlags.contains(.command) {
                if event.charactersIgnoringModifiers == "1" {
                    goHome()
                    return
                } else if event.charactersIgnoringModifiers == "2" {
                    openAppSwitcher()
                    return
                } else if event.charactersIgnoringModifiers == "3" {
                    openSpotlight()
                    return
                }
            }
            if let chars = event.characters, !chars.isEmpty,
               !chars.unicodeScalars.contains(where: { $0.value < 32 }) {
                sendText(chars)
            }
        }
    }

    // MARK: - 2. Hardware Navigation & System Actions over USB

    /// Trigger Home Action on physical iPhone / iPad over USB
    func goHome() {
        lastActionStatus = "Home Screen (USB)"
        Task {
            if await dispatchWDAButton("home") {
                return
            }
            // Direct USB CoreDevice SpringBoard activation (works on every paired iPhone & iPad without WDA!)
            runDevicectl(args: ["device", "process", "launch", "--device", targetUDID, "com.apple.springboard"])
        }
    }

    /// Open App Switcher / Multitasking on iPhone / iPad over USB
    func openAppSwitcher() {
        lastActionStatus = "App Switcher (USB)"
        let midX = (logicalScreenSize.width * 0.5).rounded()
        let bottomY = (logicalScreenSize.height * 0.985).rounded()
        let centerY = (logicalScreenSize.height * 0.52).rounded()
        Task {
            if await dispatchWDASwipe(from: CGPoint(x: midX, y: bottomY), to: CGPoint(x: midX, y: centerY), durationMs: 460) {
                return
            }
            runDevicectl(args: ["device", "process", "launch", "--device", targetUDID, "com.apple.springboard"])
        }
    }

    /// Open Spotlight Search on iPhone / iPad over USB
    func openSpotlight() {
        lastActionStatus = "Spotlight Search (USB)"
        let midX = (logicalScreenSize.width * 0.5).rounded()
        let startY = (logicalScreenSize.height * 0.25).rounded()
        let endY = (logicalScreenSize.height * 0.68).rounded()
        Task {
            _ = await dispatchWDASwipe(from: CGPoint(x: midX, y: startY), to: CGPoint(x: midX, y: endY), durationMs: 220)
        }
    }

    /// Volume Up over USB HID
    func volumeUp() {
        lastActionStatus = "Volume Up (USB)"
        Task {
            _ = await dispatchWDAButton("volumeUp")
        }
    }

    /// Volume Down over USB HID
    func volumeDown() {
        lastActionStatus = "Volume Down (USB)"
        Task {
            _ = await dispatchWDAButton("volumeDown")
        }
    }

    /// Lock / Wake screen toggle over USB
    func lockOrWake() {
        lastActionStatus = "Lock / Wake (USB)"
        Task {
            if let base = await ensureWDAEndpoint() {
                let isLocked = ( await requestJSON(method: "GET", urlString: "\(base)/wda/locked")?["value"] as? Bool ) ?? false
                let endpoint = isLocked ? "\(base)/wda/unlock" : "\(base)/wda/lock"
                if await requestJSON(method: "POST", urlString: endpoint, body: [:]) != nil {
                    return
                }
            }
            runDevicectl(args: ["device", "notification", "post", "--device", targetUDID, "com.apple.springboard.lockcomplete"])
        }
    }

    /// Open URL on physical iPhone / iPad in Mobile Safari over USB
    func openURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        lastActionStatus = "Opening \(normalized)"
        Task {
            if let base = await ensureWDAEndpoint() {
                let sessionPath = wdaSessionID.map { "/session/\($0)" } ?? ""
                if await requestJSON(method: "POST", urlString: "\(base)\(sessionPath)/url", body: ["url": normalized]) != nil {
                    return
                }
            }
            runDevicectl(args: ["device", "process", "launch", "--device", targetUDID, "com.apple.mobilesafari", "--payload-url", normalized])
        }
    }

    /// Launch app by bundle identifier over USB
    func launchApp(bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastActionStatus = "Launching \(trimmed)"
        runDevicectl(args: ["device", "process", "launch", "--device", targetUDID, trimmed])
    }

    /// Push Mac clipboard text directly to iPhone / iPad pasteboard over USB
    func pushClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        lastActionStatus = "Synced to \(deviceModelName) clipboard"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        Task {
            if let base = await ensureWDAEndpoint() {
                let b64 = Data(text.utf8).base64EncodedString()
                _ = await requestJSON(
                    method: "POST",
                    urlString: "\(base)/wda/setPasteboard",
                    body: ["content": b64, "contentType": "plaintext"]
                )
            }
        }
    }

    /// Inject typed text directly into focused iOS / iPadOS field over USB
    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        lastActionStatus = "USB Type: \(text.prefix(18))"
        Task {
            // 1. Direct USB WDA keyboard injection
            if let base = await ensureWDAEndpoint() {
                let chars = text.map { String($0) }
                let sessionPath = wdaSessionID.map { "/session/\($0)" } ?? ""
                if await requestJSON(method: "POST", urlString: "\(base)\(sessionPath)/wda/keys", body: ["value": chars]) != nil {
                    activeTransport = .usbHID
                    return
                }
                if await requestJSON(method: "POST", urlString: "\(base)/wda/keys", body: ["value": chars]) != nil {
                    activeTransport = .usbHID
                    return
                }
            }
            // 2. Direct In-App USB Touch Bridge keyboard injection
            if let appBridge = resolvedAppBridgeEndpoint {
                if await requestJSON(method: "POST", urlString: "\(appBridge)/microcode/keys", body: ["text": text]) != nil {
                    activeTransport = .inAppBridge
                    return
                }
            }
            // 3. Fallback: push to clipboard so user can paste
            pushClipboard(text)
        }
    }

    // MARK: - 3. USB HID (WDA / XCTest) & In-App Bridge Transport Layer

    /// Probe and activate USB port forwarding (`iproxy`) + CoreDevice tunnel endpoints for ports 8100 (WDA) & 8101 (In-App Bridge)
    func startUSBTouchBridge() {
        lastActionStatus = "Starting USB Direct Touch Bridge…"
        discoverPhysicalUDID()
        startIproxyIfAvailable()
        Task {
            await probeUSBControlTransports()
            if isUSBHIDConnected {
                lastActionStatus = "USB Direct HID Active (\(deviceModelName))"
            } else if isInAppBridgeConnected {
                lastActionStatus = "USB App Bridge Active (\(deviceModelName))"
            } else if deviceUDID != nil {
                startWDARunner()
            } else {
                lastActionStatus = "USB CoreDevice Connected · Start WDA or Embed Touch Bridge for Touch"
            }
        }
    }

    private var wdaRunnerProcess: Process? = nil

    /// Builds (if needed) and launches the WebDriverAgent XCTest runner on the connected iPhone/iPad over USB.
    /// Project path and signing team can be overridden with UserDefaults keys
    /// `microcode.wda.path` and `microcode.wda.team`.
    func startWDARunner() {
        if let p = wdaRunnerProcess, p.isRunning { return }
        guard let udid = deviceUDID, !udid.isEmpty else { return }
        let defaults = UserDefaults.standard
        let path = defaults.string(forKey: "microcode.wda.path") ?? "/Volumes/MAC/CodeTunerBuild/wda"
        let team = defaults.string(forKey: "microcode.wda.team") ?? "YH4U3ZNHBB"
        guard FileManager.default.fileExists(atPath: path + "/WebDriverAgent.xcodeproj") else {
            lastActionStatus = "WebDriverAgent project not found at \(path)"
            return
        }
        lastActionStatus = "Starting WebDriverAgent on \(deviceModelName)…"
        let dd = path + "-dd"
        let cmd = """
        cd '\(path)' && xcodebuild build-for-testing -project WebDriverAgent.xcodeproj -scheme WebDriverAgentRunner -destination 'id=\(udid)' -derivedDataPath '\(dd)' -allowProvisioningUpdates DEVELOPMENT_TEAM=\(team) CODE_SIGN_STYLE=Automatic PRODUCT_BUNDLE_IDENTIFIER=com.microcode.wda.runner && xcodebuild test-without-building -project WebDriverAgent.xcodeproj -scheme WebDriverAgentRunner -destination 'id=\(udid)' -derivedDataPath '\(dd)' DEVELOPMENT_TEAM=\(team)
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", cmd]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        wdaRunnerProcess = proc
        Task {
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await probeUSBControlTransports()
                if isUSBHIDConnected {
                    lastActionStatus = "USB Direct HID Active (\(deviceModelName))"
                    return
                }
            }
        }
    }

    private func startIproxyIfAvailable() {
        if let proc = iproxyProcess, proc.isRunning { return }
        let candidatePaths = [
            "/opt/homebrew/bin/iproxy",
            "/usr/local/bin/iproxy"
        ]
        guard let iproxyPath = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return
        }
        let udid = deviceUDID
        Task.detached(priority: .utility) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: iproxyPath)
            if let udid, !udid.isEmpty {
                proc.arguments = ["8100:8100", "8101:8101", "-u", udid]
            } else {
                proc.arguments = ["8100:8100", "8101:8101"]
            }
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            await MainActor.run {
                IOSDeviceControlService.shared.iproxyProcess = proc
            }
        }
    }

    func probeUSBControlTransports() async {
        guard !isProbingTransport else { return }
        isProbingTransport = true
        defer { isProbingTransport = false }

        var wdaCandidates: [String] = ["http://127.0.0.1:8100"]
        var appBridgeCandidates: [String] = ["http://127.0.0.1:8101"]

        if let tunnelIP = coreDeviceTunnelIP, !tunnelIP.isEmpty {
            let formattedHost = tunnelIP.contains(":") && !tunnelIP.hasPrefix("[") ? "[\(tunnelIP)]" : tunnelIP
            wdaCandidates.insert("http://\(formattedHost):8100", at: 0)
            appBridgeCandidates.insert("http://\(formattedHost):8101", at: 0)
        }

        // 1. Check WDA / XCTest USB HID Runner (port 8100)
        var foundWDA: String? = nil
        for candidate in wdaCandidates {
            if let statusJSON = await requestJSON(method: "GET", urlString: "\(candidate)/status") {
                foundWDA = candidate
                if let sid = statusJSON["sessionId"] as? String, !sid.isEmpty {
                    wdaSessionID = sid
                } else if let sessionResp = await requestJSON(method: "POST", urlString: "\(candidate)/session", body: ["capabilities": [:] as [String: Any]]),
                          let sid = (sessionResp["sessionId"] as? String) ?? ((sessionResp["value"] as? [String: Any])?["sessionId"] as? String) {
                    wdaSessionID = sid
                }
                // Query logical window size if available
                let sidPath = wdaSessionID.map { "/session/\($0)" } ?? ""
                if let sizeResp = await requestJSON(method: "GET", urlString: "\(candidate)\(sidPath)/window/size"),
                   let val = sizeResp["value"] as? [String: Any],
                   let w = val["width"] as? CGFloat,
                   let h = val["height"] as? CGFloat,
                   w > 100, h > 100 {
                    applyReportedSize(CGSize(width: w, height: h))
                }
                // Speed: no idle/animation waits, no accessibility snapshots on gestures.
                if let sid = wdaSessionID {
                    _ = await requestJSON(method: "POST", urlString: "\(candidate)/session/\(sid)/appium/settings", body: [
                        "settings": [
                            "waitForIdleTimeout": 0,
                            "animationCoolOffTimeout": 0,
                            "shouldWaitForQuiescence": false,
                            "snapshotMaxDepth": 1,
                            "mjpegServerFramerate": 30,
                            "mjpegScalingFactor": 60,
                            "mjpegServerScreenshotQuality": 35,
                            "screenshotQuality": 2
                        ] as [String: Any]
                    ])
                }
                break
            }
        }
        resolvedWDAEndpoint = foundWDA
        isUSBHIDConnected = (foundWDA != nil)
        if isUSBHIDConnected {
            activeTransport = .usbHID
            isControlActive = true
            // Wireless: if no USB video is streaming, use WDA's MJPEG stream over the tunnel / Wi-Fi.
            if let host = foundWDA.flatMap({ URL(string: $0)?.host }),
               IOSDeviceCaptureService.shared.state != .streaming || IOSWirelessStreamService.shared.isRunning {
                IOSWirelessStreamService.shared.start(host: host)
            }
        }

        // 2. Check MicroCode In-App USB Touch Bridge (port 8101)
        var foundBridge: String? = nil
        for candidate in appBridgeCandidates {
            if let bridgeStatus = await requestJSON(method: "GET", urlString: "\(candidate)/microcode/ping") {
                foundBridge = candidate
                if let w = bridgeStatus["width"] as? CGFloat,
                   let h = bridgeStatus["height"] as? CGFloat,
                   w > 100, h > 100 {
                    applyReportedSize(CGSize(width: w, height: h))
                }
                break
            }
        }
        resolvedAppBridgeEndpoint = foundBridge
        isInAppBridgeConnected = (foundBridge != nil)
        if !isUSBHIDConnected && isInAppBridgeConnected {
            activeTransport = .inAppBridge
            isControlActive = true
        }
    }

    private func ensureWDAEndpoint() async -> String? {
        if let existing = resolvedWDAEndpoint {
            return existing
        }
        await probeUSBControlTransports()
        return resolvedWDAEndpoint
    }

    private func dispatchWDATap(point: CGPoint) async -> Bool {
        guard let base = resolvedWDAEndpoint else { return false }
        let sidPath = wdaSessionID.map { "/session/\($0)" } ?? ""

        // W3C Pointer Actions (works across iOS 15–18 & iPadOS 15–18)
        let actionsPayload: [String: Any] = [
            "actions": [
                [
                    "type": "pointer",
                    "id": "finger1",
                    "parameters": ["pointerType": "touch"],
                    "actions": [
                        ["type": "pointerMove", "duration": 0, "x": Int(point.x), "y": Int(point.y)],
                        ["type": "pointerDown", "button": 0],
                        ["type": "pause", "duration": 35],
                        ["type": "pointerUp", "button": 0]
                    ]
                ]
            ]
        ]
        if !sidPath.isEmpty,
           await requestJSON(method: "POST", urlString: "\(base)\(sidPath)/actions", body: actionsPayload) != nil {
            return true
        }
        // Fallback WDA tap endpoint
        if await requestJSON(method: "POST", urlString: "\(base)\(sidPath)/wda/tap/0", body: ["x": point.x, "y": point.y]) != nil {
            return true
        }
        if await requestJSON(method: "POST", urlString: "\(base)/wda/tap/0", body: ["x": point.x, "y": point.y]) != nil {
            return true
        }
        resolvedWDAEndpoint = nil
        isUSBHIDConnected = false
        return false
    }

    private func dispatchWDASwipe(from startPt: CGPoint, to endPt: CGPoint, durationMs: Int) async -> Bool {
        guard let base = resolvedWDAEndpoint else { return false }
        let sidPath = wdaSessionID.map { "/session/\($0)" } ?? ""

        let actionsPayload: [String: Any] = [
            "actions": [
                [
                    "type": "pointer",
                    "id": "finger1",
                    "parameters": ["pointerType": "touch"],
                    "actions": [
                        ["type": "pointerMove", "duration": 0, "x": Int(startPt.x), "y": Int(startPt.y)],
                        ["type": "pointerDown", "button": 0],
                        ["type": "pointerMove", "duration": max(80, durationMs), "x": Int(endPt.x), "y": Int(endPt.y)],
                        ["type": "pointerUp", "button": 0]
                    ]
                ]
            ]
        ]
        if !sidPath.isEmpty,
           await requestJSON(method: "POST", urlString: "\(base)\(sidPath)/actions", body: actionsPayload) != nil {
            return true
        }
        let durationSec = max(0.08, Double(durationMs) / 1000.0)
        let dragBody: [String: Any] = [
            "fromX": startPt.x,
            "fromY": startPt.y,
            "toX": endPt.x,
            "toY": endPt.y,
            "duration": durationSec
        ]
        if await requestJSON(method: "POST", urlString: "\(base)\(sidPath)/wda/dragfromtoforduration", body: dragBody) != nil {
            return true
        }
        if await requestJSON(method: "POST", urlString: "\(base)/wda/dragfromtoforduration", body: dragBody) != nil {
            return true
        }
        return false
    }

    private func dispatchWDAButton(_ buttonName: String) async -> Bool {
        guard let base = await ensureWDAEndpoint() else { return false }
        let sidPath = wdaSessionID.map { "/session/\($0)" } ?? ""
        if await requestJSON(method: "POST", urlString: "\(base)\(sidPath)/wda/pressButton", body: ["name": buttonName]) != nil {
            return true
        }
        if await requestJSON(method: "POST", urlString: "\(base)/wda/pressButton", body: ["name": buttonName]) != nil {
            return true
        }
        return false
    }

    private func dispatchInAppBridgeTap(point: CGPoint, normX: CGFloat, normY: CGFloat) async -> Bool {
        guard let base = resolvedAppBridgeEndpoint else { return false }
        let body: [String: Any] = [
            "action": "tap",
            "x": point.x,
            "y": point.y,
            "normX": normX,
            "normY": normY
        ]
        if await requestJSON(method: "POST", urlString: "\(base)/microcode/gesture", body: body) != nil {
            return true
        }
        resolvedAppBridgeEndpoint = nil
        isInAppBridgeConnected = false
        return false
    }

    private func dispatchInAppBridgeSwipe(from startPt: CGPoint, to endPt: CGPoint, durationMs: Int) async -> Bool {
        guard let base = resolvedAppBridgeEndpoint else { return false }
        let body: [String: Any] = [
            "action": "swipe",
            "fromX": startPt.x,
            "fromY": startPt.y,
            "toX": endPt.x,
            "toY": endPt.y,
            "durationMs": durationMs
        ]
        return await requestJSON(method: "POST", urlString: "\(base)/microcode/gesture", body: body) != nil
    }

    private func requestJSON(method: String, urlString: String, body: [String: Any]? = nil) async -> [String: Any]? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, resp) = try await Self.controlSession.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
            return ["ok": true]
        } catch {
            return nil
        }
    }

    private func postJSONFireAndForget(urlString: String, payload: [String: Any]) {
        guard let url = URL(string: urlString),
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        Self.controlSession.dataTask(with: req).resume()
    }

    // MARK: - Zero-Config In-App Touch Bridge Snippet Generator

    /// Copies a ready-to-drop Swift snippet that enables 0-latency USB touch, swipe, and keyboard control
    /// inside any iOS / iPadOS app over the CoreDevice USB tunnel without needing WebDriverAgent.
    func copyInAppTouchBridgeSnippetToClipboard() {
        let snippet = """
        // MicroCodeUSBPreviewBridge.swift
        // Drop into your iOS/iPadOS target (Debug) for zero-setup USB touch & keyboard control inside MicroCode Preview.
        #if canImport(UIKit) && DEBUG
        import UIKit
        import Network

        public final class MicroCodeUSBPreviewBridge {
            public static let shared = MicroCodeUSBPreviewBridge()
            private var listener: NWListener?

            public func start(port: UInt16 = 8101) {
                guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
                listener = try? NWListener(using: .tcp, on: nwPort)
                listener?.newConnectionHandler = { [weak self] conn in
                    conn.start(queue: .main)
                    self?.receive(on: conn)
                }
                listener?.start(queue: .main)
            }

            private func receive(on conn: NWConnection) {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
                    if let data, let raw = String(data: data, encoding: .utf8) {
                        self?.handleHTTP(raw: raw, conn: conn)
                    }
                }
            }

            private func handleHTTP(raw: String, conn: NWConnection) {
                let win = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first { $0.isKeyWindow }
                let size = win?.bounds.size ?? UIScreen.main.bounds.size
                if let bodyRange = raw.range(of: "\\r\\n\\r\\n"),
                   let json = try? JSONSerialization.jsonObject(with: Data(raw[bodyRange.upperBound...].utf8)) as? [String: Any] {
                    if let x = json["x"] as? CGFloat, let y = json["y"] as? CGFloat, let win {
                        let pt = CGPoint(x: x, y: y)
                        if let target = win.hitTest(pt, with: nil) {
                            if let ctrl = target as? UIControl {
                                ctrl.sendActions(for: .touchUpInside)
                            } else if target.canBecomeFirstResponder {
                                target.becomeFirstResponder()
                            }
                        }
                    } else if let text = json["text"] as? String {
                        UIApplication.shared.sendAction(#selector(UIKeyInput.insertText(_:)), to: nil, from: text, for: nil)
                    }
                }
                let resp = "{\\"ok\\":true,\\"width\\":\\(Int(size.width)),\\"height\\":\\(Int(size.height))}"
                let http = "HTTP/1.1 200 OK\\r\\nContent-Type: application/json\\r\\nContent-Length: \\(resp.utf8.count)\\r\\n\\r\\n\\(resp)"
                conn.send(content: Data(http.utf8), completion: .contentProcessed { _ in conn.cancel() })
            }
        }
        #endif
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet, forType: .string)
        lastActionStatus = "Copied MicroCodeUSBPreviewBridge.swift to clipboard!"
    }

    // MARK: - 4. Optional Continuity Window Forwarding (Strictly Opt-In, Never Auto-Launched)

    func getMirroringWindowInfo() -> MirrorWindowInfo? {
        guard let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for w in windowList {
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            if owner == "iPhone Mirroring" || owner.contains("ScreenContinuity") {
                let boundsDict = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
                let width = boundsDict["Width"] as? CGFloat ?? 0
                let height = boundsDict["Height"] as? CGFloat ?? 0
                let x = boundsDict["X"] as? CGFloat ?? 0
                let y = boundsDict["Y"] as? CGFloat ?? 0
                if height > 400 && width > 200 && width < 900 {
                    let pid = w[kCGWindowOwnerPID as String] as? pid_t ?? 0
                    return MirrorWindowInfo(pid: pid, bounds: CGRect(x: x, y: y, width: width, height: height))
                }
            }
        }
        return nil
    }

    func checkMirroringStatus() {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ScreenContinuity").isEmpty
        self.isMirroringRunning = running
    }

    private func forwardCGEventTap(to info: MirrorWindowInfo, normalizedX: CGFloat, normalizedY: CGFloat) {
        let insetTop: CGFloat = 34
        let usableHeight = max(100, info.bounds.height - insetTop - 16)
        let targetX = info.bounds.origin.x + (normalizedX * info.bounds.width)
        let targetY = info.bounds.origin.y + insetTop + (normalizedY * usableHeight)
        let targetPoint = CGPoint(x: targetX, y: targetY)
        let pid = info.pid
        Task.detached(priority: .userInteractive) {
            let src = CGEventSource(stateID: .combinedSessionState)
            if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: targetPoint, mouseButton: .left),
               let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: targetPoint, mouseButton: .left) {
                down.postToPid(pid)
                try? await Task.sleep(nanoseconds: 35_000_000)
                up.postToPid(pid)
            }
        }
    }

    private func forwardCGEventSwipe(to info: MirrorWindowInfo, fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat, durationMs: Int) {
        let insetTop: CGFloat = 34
        let usableHeight = max(100, info.bounds.height - insetTop - 16)
        let startPt = CGPoint(
            x: info.bounds.origin.x + (fromX * info.bounds.width),
            y: info.bounds.origin.y + insetTop + (fromY * usableHeight)
        )
        let endPt = CGPoint(
            x: info.bounds.origin.x + (toX * info.bounds.width),
            y: info.bounds.origin.y + insetTop + (toY * usableHeight)
        )
        let pid = info.pid
        Task.detached(priority: .userInteractive) {
            let src = CGEventSource(stateID: .combinedSessionState)
            if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: startPt, mouseButton: .left) {
                down.postToPid(pid)
            }
            let steps = max(4, durationMs / 20)
            let stepNs = UInt64(max(1, (durationMs * 1_000_000) / steps))
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let curr = CGPoint(x: startPt.x + (endPt.x - startPt.x) * t, y: startPt.y + (endPt.y - startPt.y) * t)
                if let drag = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged, mouseCursorPosition: curr, mouseButton: .left) {
                    drag.postToPid(pid)
                }
                try? await Task.sleep(nanoseconds: stepNs)
            }
            if let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: endPt, mouseButton: .left) {
                up.postToPid(pid)
            }
        }
    }

    // MARK: - 5. Device Discovery & CoreDevice USB Tunnel Extraction

    private var isDiscoveringUDID = false

    func discoverPhysicalUDID() {
        guard !isDiscoveringUDID else { return }
        isDiscoveringUDID = true
        Task.detached(priority: .utility) {
            var foundID: String? = nil
            var foundModel: String? = nil
            var foundTunnelIP: String? = nil
            let proc = Process()
            let pipe = Pipe()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            proc.arguments = ["devicectl", "list", "devices", "--json-output", "-", "--omit-deprecated-fields-in-json", "--timeout", "3"]
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let result = json["result"] as? [String: Any],
                   let devices = result["devices"] as? [[String: Any]] {
                    // Prefer the device that is actually connected right now (wired USB tunnel first),
                    // instead of the first "physical" entry which may be an offline paired device.
                    func rank(_ d: [String: Any]) -> Int {
                        let conn = d["connectionProperties"] as? [String: Any]
                        let state = conn?["tunnelState"] as? String ?? ""
                        let transport = conn?["transportType"] as? String ?? ""
                        if state == "connected" && transport == "wired" { return 0 }
                        if state == "connected" { return 1 }
                        return 2
                    }
                    let ordered = devices.sorted { rank($0) < rank($1) }
                    for d in ordered {
                        let hw = (d["hardwareProperties"] as? [String: Any])
                            ?? ((d["properties"] as? [String: Any])?["hardware"] as? [String: Any])
                        let conn = d["connectionProperties"] as? [String: Any]
                        let reality = hw?["reality"] as? String ?? ""
                        let model = hw?["marketingName"] as? String ?? (hw?["deviceType"] as? String ?? "")
                        if reality.caseInsensitiveCompare("physical") == .orderedSame {
                            if let id = (hw?["udid"] as? String) ?? (d["identifier"] as? String) {
                                foundID = id
                                if !model.isEmpty {
                                    foundModel = model
                                }
                                if let tip = conn?["tunnelIPAddress"] as? String, !tip.isEmpty {
                                    foundTunnelIP = tip
                                }
                                break
                            }
                        }
                    }
                }
            } catch {
                print("[IOSControl] Failed to list devices: \(error)")
            }
            let finalID = foundID
            let finalModel = foundModel
            let finalTunnelIP = foundTunnelIP
            await MainActor.run {
                let service = IOSDeviceControlService.shared
                service.isDiscoveringUDID = false
                if let finalID {
                    service.deviceUDID = finalID
                }
                if let finalModel, !finalModel.isEmpty {
                    service.deviceModelName = finalModel
                    service.isIPadDevice = finalModel.lowercased().contains("ipad")
                }
                if let finalTunnelIP {
                    service.coreDeviceTunnelIP = finalTunnelIP
                }
                Task {
                    await service.probeUSBControlTransports()
                }
            }
        }
    }

    private var targetUDID: String {
        deviceUDID ?? "D92572EC-11A1-5B5C-9147-4AB0353A9C7E"
    }

    private func runDevicectl(args: [String]) {
        Task.detached(priority: .utility) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            proc.arguments = ["devicectl"] + args
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
            } catch {
                print("[IOSControl] devicectl error: \(error)")
            }
        }
    }
}
