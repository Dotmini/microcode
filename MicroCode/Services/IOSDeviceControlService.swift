//
//  IOSDeviceControlService.swift
//  MicroCode
//
//  Provides physical iOS device control and automation from inside MicroCode IDE.
//  Supports real-time mouse/touch forwarding to native iPhone Mirroring,
//  fast AppleScript shortcuts (Home, App Switcher, Spotlight), clipboard sync,
//  window docking, and background devicectl automation.
//

import Foundation
import AppKit
import Quartz

@MainActor
final class IOSDeviceControlService: ObservableObject {
    static let shared = IOSDeviceControlService()

    @Published var isControlActive = false
    @Published var lastActionStatus = ""
    @Published var deviceUDID: String? = nil
    @Published var deviceModelName: String = "iPhone"
    @Published var isMirroringRunning = false

    struct MirrorWindowInfo {
        let pid: pid_t
        let bounds: CGRect
    }

    private init() {
        discoverPhysicalUDID()
        checkMirroringStatus()
    }

    // MARK: - Mirroring Window & PID Detection

    /// Find iPhone Mirroring application PID and active screen window bounds
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
                // Main phone screen window in iPhone Mirroring is roughly 300-500 pt wide and 650-950 pt high
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

    // MARK: - Direct Touch / Mouse Forwarding into iPhone Mirroring

    /// Forward a tap/click from MicroCode's iPhone preview screen directly to the device
    func sendTap(normalizedX: CGFloat, normalizedY: CGFloat) {
        guard let info = getMirroringWindowInfo() else {
            // Auto-launch iPhone Mirroring if not yet active
            launchNativeInteractiveControl()
            lastActionStatus = "Launching iPhone Mirroring..."
            return
        }

        // Account for standard window chrome / dynamic island top inset (~34 pt)
        let insetTop: CGFloat = 34
        let usableHeight = max(100, info.bounds.height - insetTop - 16)
        let targetX = info.bounds.origin.x + (normalizedX * info.bounds.width)
        let targetY = info.bounds.origin.y + insetTop + (normalizedY * usableHeight)
        let targetPoint = CGPoint(x: targetX, y: targetY)

        let src = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: targetPoint, mouseButton: .left),
           let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: targetPoint, mouseButton: .left) {
            down.postToPid(info.pid)
            down.post(tap: .cghidEventTap)
            usleep(35000)
            up.postToPid(info.pid)
            up.post(tap: .cghidEventTap)
            lastActionStatus = "Tap (\(Int(targetX)), \(Int(targetY)))"
        }
    }

    /// Forward a drag/swipe gesture from MicroCode's iPhone preview screen directly to the device
    func sendSwipe(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat, durationMs: Int = 180) {
        guard let info = getMirroringWindowInfo() else { return }

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

        let src = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: startPt, mouseButton: .left) {
            down.postToPid(info.pid)
            down.post(tap: .cghidEventTap)
        }

        let steps = max(4, durationMs / 20)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let curr = CGPoint(x: startPt.x + (endPt.x - startPt.x) * t, y: startPt.y + (endPt.y - startPt.y) * t)
            if let drag = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged, mouseCursorPosition: curr, mouseButton: .left) {
                drag.postToPid(info.pid)
                drag.post(tap: .cghidEventTap)
            }
            usleep(UInt32((durationMs * 1000) / steps))
        }

        if let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: endPt, mouseButton: .left) {
            up.postToPid(info.pid)
            up.post(tap: .cghidEventTap)
            lastActionStatus = "Swipe sent"
        }
    }

    /// Forward trackpad / mouse scroll wheel events
    func sendScroll(deltaX: CGFloat, deltaY: CGFloat) {
        guard let info = getMirroringWindowInfo() else { return }
        let center = CGPoint(x: info.bounds.midX, y: info.bounds.midY)
        if let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(deltaY * 5), wheel2: Int32(deltaX * 5), wheel3: 0) {
            scroll.location = center
            scroll.postToPid(info.pid)
            scroll.post(tap: .cghidEventTap)
        }
    }

    /// Forward physical Mac keyboard events directly to iPhone Mirroring
    func sendKey(_ event: NSEvent) {
        guard let info = getMirroringWindowInfo() else { return }
        if let cgEvent = event.cgEvent {
            cgEvent.postToPid(info.pid)
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Fast Hardware Navigation Actions

    /// Trigger Home Action on physical device (Instant Cmd+1 to iPhone Mirroring)
    func goHome() {
        lastActionStatus = "Home Screen"
        let script = """
        tell application "System Events"
            if exists (process "iPhone Mirroring") then
                tell process "iPhone Mirroring"
                    key code 18 using {command down}
                end tell
            end if
        end tell
        """
        runAppleScript(script)
        // Background devicectl fallback
        runDevicectl(args: ["device", "process", "launch", "--device", targetUDID, "com.apple.springboard"])
    }

    /// Open App Switcher / Multitasking (Instant Cmd+2 to iPhone Mirroring)
    func openAppSwitcher() {
        lastActionStatus = "App Switcher"
        let script = """
        tell application "System Events"
            if exists (process "iPhone Mirroring") then
                tell process "iPhone Mirroring"
                    key code 19 using {command down}
                end tell
            end if
        end tell
        """
        runAppleScript(script)
    }

    /// Open Spotlight Search on iPhone (Instant Cmd+3 to iPhone Mirroring)
    func openSpotlight() {
        lastActionStatus = "Spotlight"
        let script = """
        tell application "System Events"
            if exists (process "iPhone Mirroring") then
                tell process "iPhone Mirroring"
                    key code 20 using {command down}
                end tell
            end if
        end tell
        """
        runAppleScript(script)
    }

    /// Lock / Wake screen toggle
    func lockOrWake() {
        lastActionStatus = "Lock / Wake"
        let script = """
        tell application "System Events"
            if exists (process "iPhone Mirroring") then
                tell process "iPhone Mirroring"
                    key code 49
                end tell
            end if
        end tell
        """
        runAppleScript(script)
        runDevicectl(args: ["device", "notification", "post", "--device", targetUDID, "com.apple.springboard.lockcomplete"])
    }

    /// Open URL on physical device in Mobile Safari
    func openURL(_ urlString: String) {
        guard !urlString.isEmpty else { return }
        lastActionStatus = "Opening \(urlString)"
        runDevicectl(args: ["device", "process", "launch", "--device", targetUDID, "com.apple.mobilesafari", "--url", urlString])
    }

    /// Launch app by bundle identifier
    func launchApp(bundleID: String) {
        guard !bundleID.isEmpty else { return }
        lastActionStatus = "Launching \(bundleID)"
        runDevicectl(args: ["device", "process", "launch", "--device", targetUDID, bundleID])
    }

    /// Push Mac clipboard text directly to iPhone pasteboard
    func pushClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        lastActionStatus = "Pushed to iPhone clipboard"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // Universal Clipboard / AirDrop push + devicectl copy
        let tempFile = NSTemporaryDirectory() + "microcode_clip.txt"
        try? text.write(toFile: tempFile, atomically: true, encoding: .utf8)
        runDevicectl(args: ["device", "pasteboard", "copy", "--device", targetUDID, "--file", tempFile])
    }

    /// Inject typed text directly into focused iOS field
    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        lastActionStatus = "Typing text..."
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "System Events"
            if exists (process "iPhone Mirroring") then
                tell process "iPhone Mirroring"
                    keystroke "\(escaped)"
                end tell
            end if
        end tell
        """
        runAppleScript(script)
    }

    /// Snap & dock the official iPhone Mirroring window right next to MicroCode IDE window
    func dockMirroringWindow(nextTo window: NSWindow? = nil) {
        guard let win = window ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }
        let screenFrame = win.frame
        let targetX = Int(screenFrame.maxX + 8)
        let mainScreenH = Int(NSScreen.main?.frame.height ?? 1080)
        let targetY = max(32, mainScreenH - Int(screenFrame.maxY))

        let script = """
        tell application "System Events"
            if exists (process "iPhone Mirroring") then
                tell process "iPhone Mirroring"
                    set frontmost to true
                    try
                        set position of window 1 to {\(targetX), \(targetY)}
                    end try
                end tell
            end if
        end tell
        """
        runAppleScript(script)
        lastActionStatus = "Docked alongside IDE"
    }

    /// Open Apple Native iPhone Mirroring for full direct mouse/keyboard control
    func launchNativeInteractiveControl(dockBeside window: NSWindow? = nil) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ScreenContinuity") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                if let error {
                    print("[IOSControl] Error launching ScreenContinuity: \(error)")
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        self?.checkMirroringStatus()
                        self?.dockMirroringWindow(nextTo: window)
                    }
                }
            }
        }
    }

    // MARK: - Device Discovery & Utilities

    func discoverPhysicalUDID() {
        Task {
            let proc = Process()
            let pipe = Pipe()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            proc.arguments = ["devicectl", "list", "devices", "--json-output", "-"]
            proc.standardOutput = pipe
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let result = json["result"] as? [String: Any],
                   let devices = result["devices"] as? [[String: Any]] {
                    for d in devices {
                        let reality = (d["hardwareProperties"] as? [String: Any])?["reality"] as? String ?? ""
                        let model = (d["hardwareProperties"] as? [String: Any])?["marketingName"] as? String ?? ""
                        if reality == "physical" {
                            if let id = d["identifier"] as? String {
                                self.deviceUDID = id
                                if !model.isEmpty {
                                    self.deviceModelName = model
                                }
                                break
                            }
                        }
                    }
                }
            } catch {
                print("[IOSControl] Failed to list devices: \(error)")
            }
        }
    }

    private var targetUDID: String {
        deviceUDID ?? "D92572EC-11A1-5B5C-9147-4AB0353A9C7E"
    }

    private func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInteractive).async {
            var error: NSDictionary?
            if let script = NSAppleScript(source: source) {
                script.executeAndReturnError(&error)
                if let error {
                    print("[IOSControl] AppleScript notice: \(error)")
                }
            }
        }
    }

    private func runDevicectl(args: [String]) {
        Task.detached(priority: .utility) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            proc.arguments = ["devicectl"] + args
            do {
                try proc.run()
            } catch {
                print("[IOSControl] devicectl error: \(error)")
            }
        }
    }
}
