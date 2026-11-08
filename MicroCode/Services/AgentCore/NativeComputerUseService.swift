//
//  NativeComputerUseService.swift
//  MicroCode
//
//  Pragmatic Native macOS Computer Use Engine (Zero PyObjC Dependency)
//  - Multi-app window discovery (`CGWindowListCopyWindowInfo` + `NSWorkspace`)
//  - Hard-blocked security denylist (SecurityAgent, Keychain, Password Managers, System Settings)
//  - Hybrid Set-of-Mark (`[1]..[N]`) combining `AXUIElement`, in-process `NSView` fallback, and Apple Vision ANE OCR
//  - 1x Logical Coordinate Normalization (`.nominalResolution`) eliminating Retina 2x click drift
//  - Background-first `AXPress` / `AXValue` execution with cursor-restoring `CGEvent` fallback
//  - Clipboard-preserving fast paste typing, smooth drag, scroll, zoom-crop, batch macros, and pixel-diff QA verification
//

import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import Vision
import CoreImage

@MainActor
public final class NativeComputerUseService {
    public static let shared = NativeComputerUseService()

    public struct ComputerUseMark {
        public let id: Int
        public let role: String
        public let label: String
        public let value: String
        public let enabled: Bool
        /// Logical 1x screen frame (Quartz top-left origin)
        public let screenFrame: CGRect
        /// Logical 1x window-relative frame (top-left origin relative to captured window)
        public let windowFrame: CGRect
        public var screenCenter: CGPoint {
            CGPoint(x: screenFrame.midX.rounded(), y: screenFrame.midY.rounded())
        }
        public var windowCenter: CGPoint {
            CGPoint(x: windowFrame.midX.rounded(), y: windowFrame.midY.rounded())
        }
        fileprivate let axElement: AXUIElement?
        fileprivate weak var inProcessView: NSView?
    }

    public struct TargetWindowInfo {
        public let pid: pid_t
        public let windowId: CGWindowID
        public let appName: String
        public let bundleId: String
        public let windowTitle: String
        /// Logical 1x screen bounds (Quartz top-left origin)
        public let bounds: CGRect
        public let isMicroCodeProcess: Bool
    }

    /// Hard-blocked bundle IDs & process names that Computer Use must NEVER inspect, click, or type into.
    private static let blockedBundlePrefixes: [String] = [
        "com.apple.SecurityAgent",
        "com.apple.keychainaccess",
        "com.apple.systempreferences",
        "com.apple.Settings",
        "com.apple.Passwords",
        "com.apple.UserNotificationCenter",
        "com.1password",
        "com.agilebits",
        "com.bitwarden",
        "com.lastpass",
        "com.dashlane",
        "org.keepassxc"
    ]

    private static let blockedAppNames: Set<String> = [
        "securityagent",
        "keychain access",
        "system settings",
        "system preferences",
        "passwords",
        "1password",
        "bitwarden",
        "lastpass",
        "dashlane",
        "keepassxc"
    ]

    private static let keycodes: [String: CGKeyCode] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49,
        "delete": 51, "backspace": 51, "forwarddelete": 117, "escape": 53, "esc": 53,
        "command": 55, "cmd": 55, "shift": 56, "capslock": 57,
        "option": 58, "opt": 58, "alt": 58, "control": 59, "ctrl": 59,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
        "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50
    ]

    private var cachedMarks: [Int: ComputerUseMark] = [:]
    private var lastTargetWindow: TargetWindowInfo?

    private init() {}

    // MARK: - 1. Permission & Security Checks

    public func permissionStatus(promptIfNeeded: Bool = false) -> [String: Any] {
        let axTrusted: Bool
        if promptIfNeeded {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            axTrusted = AXIsProcessTrustedWithOptions(opts)
        } else {
            axTrusted = AXIsProcessTrusted()
        }
        let screenGranted = CGPreflightScreenCaptureAccess()
        if promptIfNeeded && !screenGranted {
            _ = CGRequestScreenCaptureAccess()
        }
        return [
            "accessibility_granted": axTrusted,
            "screen_recording_granted": screenGranted,
            "in_process_microcode_ready": true,
            "note": (!axTrusted || !screenGranted)
                ? "MicroCode own-window capture & in-process UI inspection work immediately. Controlling external apps or posting global CGEvents requires Accessibility & Screen Recording in System Settings → Privacy & Security."
                : "Full macOS Accessibility & Screen Recording active."
        ]
    }

    public static func isBlockedApplication(bundleId: String, appName: String) -> Bool {
        let lowerBundle = bundleId.lowercased()
        let lowerName = appName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if blockedAppNames.contains(lowerName) { return true }
        for prefix in blockedBundlePrefixes {
            if lowerBundle.hasPrefix(prefix.lowercased()) {
                return true
            }
        }
        return false
    }

    // MARK: - 2. Window Discovery (Any Safe macOS App or MicroCode)

    public func listWindows(appFilter: String? = nil, includeOffscreen: Bool = false) -> [[String: Any]] {
        let infos = discoverWindows(appFilter: appFilter, titleFilter: nil, includeOffscreen: includeOffscreen)
        return infos.map { w in
            [
                "window_id": Int(w.windowId),
                "pid": Int(w.pid),
                "app_name": w.appName,
                "bundle_id": w.bundleId,
                "title": w.windowTitle,
                "is_microcode": w.isMicroCodeProcess,
                "bounds": [
                    "x": Double(w.bounds.origin.x.rounded()),
                    "y": Double(w.bounds.origin.y.rounded()),
                    "width": Double(w.bounds.width.rounded()),
                    "height": Double(w.bounds.height.rounded())
                ]
            ]
        }
    }

    public func resolveTargetWindow(
        appName: String? = nil,
        windowId: Int? = nil,
        windowTitle: String? = nil
    ) throws -> TargetWindowInfo {
        if let appName, Self.isBlockedApplication(bundleId: appName, appName: appName) {
            throw NSError(
                domain: "NativeComputerUse",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Security Shield: Computer Use is blocked from interacting with sensitive application '\(appName)'."]
            )
        }
        let all = discoverWindows(appFilter: appName, titleFilter: windowTitle, includeOffscreen: false)
        if let wid = windowId, let exact = all.first(where: { Int($0.windowId) == wid }) {
            try enforceNotBlocked(exact)
            lastTargetWindow = exact
            return exact
        }
        if let first = all.first {
            try enforceNotBlocked(first)
            lastTargetWindow = first
            return first
        }
        // Fallback: if MicroCode itself has an NSWindow even if minimized/unlisted
        let selfPid = ProcessInfo.processInfo.processIdentifier
        if appName == nil || appName?.lowercased().contains("microcode") == true,
           let nsWin = NSApp.windows.first(where: { $0.isVisible && $0.frame.width >= 200 }) ?? NSApp.mainWindow ?? NSApp.windows.first {
            let screenH = NSScreen.main?.frame.height ?? 1080
            let f = nsWin.frame
            // Convert AppKit bottom-left origin to Quartz top-left origin
            let qRect = CGRect(x: f.origin.x, y: screenH - (f.origin.y + f.height), width: f.width, height: f.height)
            let info = TargetWindowInfo(
                pid: selfPid,
                windowId: CGWindowID(max(1, nsWin.windowNumber)),
                appName: "MicroCode",
                bundleId: Bundle.main.bundleIdentifier ?? "com.dotmini.microcode",
                windowTitle: nsWin.title,
                bounds: qRect,
                isMicroCodeProcess: true
            )
            lastTargetWindow = info
            return info
        }
        throw NSError(
            domain: "NativeComputerUse",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "No visible window found matching app='\(appName ?? "MicroCode")' title='\(windowTitle ?? "*")'."]
        )
    }

    private func enforceNotBlocked(_ info: TargetWindowInfo) throws {
        if Self.isBlockedApplication(bundleId: info.bundleId, appName: info.appName) {
            throw NSError(
                domain: "NativeComputerUse",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Security Shield: Computer Use is blocked from interacting with sensitive application '\(info.appName)' (\(info.bundleId))."]
            )
        }
    }

    private func discoverWindows(
        appFilter: String?,
        titleFilter: String?,
        includeOffscreen: Bool
    ) -> [TargetWindowInfo] {
        let selfPid = ProcessInfo.processInfo.processIdentifier
        let runningByPid: [pid_t: NSRunningApplication] = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }
        )

        let opts: CGWindowListOption = includeOffscreen
            ? [.excludeDesktopElements]
            : [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawList = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let cleanApp = appFilter?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanTitle = titleFilter?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var candidates: [(priority: Int, area: Double, zOrder: Int, info: TargetWindowInfo)] = []
        for (idx, entry) in rawList.enumerated() {
            let layer = (entry[kCGWindowLayer as String] as? Int) ?? 0
            guard layer == 0 else { continue }
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let wid = entry[kCGWindowNumber as String] as? CGWindowID,
                  let bDict = entry[kCGWindowBounds as String] as? [String: Any] else { continue }

            let x = (bDict["X"] as? Double) ?? 0
            let y = (bDict["Y"] as? Double) ?? 0
            let w = (bDict["Width"] as? Double) ?? 0
            let h = (bDict["Height"] as? Double) ?? 0
            guard w >= 160 && h >= 120 else { continue }

            let ownerName = (entry[kCGWindowOwnerName as String] as? String) ?? runningByPid[pid]?.localizedName ?? "App"
            let bundleId = runningByPid[pid]?.bundleIdentifier ?? ""
            let winTitle = (entry[kCGWindowName as String] as? String) ?? ""

            if Self.isBlockedApplication(bundleId: bundleId, appName: ownerName) {
                continue
            }

            if let cleanApp, !cleanApp.isEmpty {
                let matchesOwner = ownerName.lowercased().contains(cleanApp)
                let matchesBundle = bundleId.lowercased().contains(cleanApp)
                if !matchesOwner && !matchesBundle { continue }
            } else {
                // Default to MicroCode when no app filter is specified, unless MicroCode has no window
                if pid != selfPid && !ownerName.lowercased().contains("microcode") {
                    continue
                }
            }

            if let cleanTitle, !cleanTitle.isEmpty, !winTitle.lowercased().contains(cleanTitle) {
                continue
            }

            let isSelf = (pid == selfPid) || ownerName.lowercased().contains("microcode")
            let isLargeMain = (w >= 420 && h >= 300) ? 10 : 1
            let info = TargetWindowInfo(
                pid: pid,
                windowId: wid,
                appName: ownerName,
                bundleId: bundleId,
                windowTitle: winTitle,
                bounds: CGRect(x: x, y: y, width: w, height: h),
                isMicroCodeProcess: isSelf
            )
            candidates.append((isLargeMain, w * h, -idx, info))
        }

        // If default (nil appFilter) found nothing for MicroCode, retry across all safe visible apps
        if candidates.isEmpty && appFilter == nil {
            for (idx, entry) in rawList.enumerated() {
                let layer = (entry[kCGWindowLayer as String] as? Int) ?? 0
                guard layer == 0,
                      let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                      let wid = entry[kCGWindowNumber as String] as? CGWindowID,
                      let bDict = entry[kCGWindowBounds as String] as? [String: Any] else { continue }
                let w = (bDict["Width"] as? Double) ?? 0
                let h = (bDict["Height"] as? Double) ?? 0
                guard w >= 300 && h >= 200 else { continue }
                let ownerName = (entry[kCGWindowOwnerName as String] as? String) ?? "App"
                let bundleId = runningByPid[pid]?.bundleIdentifier ?? ""
                if Self.isBlockedApplication(bundleId: bundleId, appName: ownerName) { continue }
                let info = TargetWindowInfo(
                    pid: pid,
                    windowId: wid,
                    appName: ownerName,
                    bundleId: bundleId,
                    windowTitle: (entry[kCGWindowName as String] as? String) ?? "",
                    bounds: CGRect(
                        x: (bDict["X"] as? Double) ?? 0,
                        y: (bDict["Y"] as? Double) ?? 0,
                        width: w,
                        height: h
                    ),
                    isMicroCodeProcess: pid == selfPid
                )
                candidates.append((1, w * h, -idx, info))
            }
        }

        candidates.sort { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            if a.zOrder != b.zOrder { return a.zOrder > b.zOrder }
            return a.area > b.area
        }
        return candidates.map(\.info)
    }

    // MARK: - 3. Hybrid Set-of-Mark Inspection (AXUIElement + In-Process NSView + ANE Vision OCR)

    public func inspectElements(
        target: TargetWindowInfo,
        query: String? = nil,
        roleFilter: String? = nil,
        maxDepth: Int = 14,
        cgImageForOCR: CGImage? = nil
    ) async -> [ComputerUseMark] {
        var rawMarks: [ComputerUseMark] = []
        var seenCenters: [CGPoint] = []

        func isDuplicateCenter(_ pt: CGPoint, label: String) -> Bool {
            for existing in seenCenters {
                if hypot(existing.x - pt.x, existing.y - pt.y) < 10 {
                    return true
                }
            }
            seenCenters.append(pt)
            return false
        }

        // Layer A: macOS Accessibility (`AXUIElement`) when process is trusted
        if AXIsProcessTrusted() {
            let appAX = AXUIElementCreateApplication(target.pid)
            var winVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(appAX, kAXWindowsAttribute as CFString, &winVal) == .success,
               let axWindows = winVal as? [AXUIElement] {
                var collected: [(role: String, label: String, value: String, enabled: Bool, frame: CGRect, elem: AXUIElement)] = []

                func walkAX(_ elem: AXUIElement, depth: Int) {
                    guard depth <= maxDepth, collected.count < 160 else { return }
                    let role = Self.axString(elem, kAXRoleAttribute) ?? ""
                    let title = Self.axString(elem, kAXTitleAttribute) ?? ""
                    let desc = Self.axString(elem, kAXDescriptionAttribute) ?? ""
                    let help = Self.axString(elem, kAXHelpAttribute) ?? ""
                    let valStr = Self.axString(elem, kAXValueAttribute) ?? ""
                    let enabled = Self.axBool(elem, kAXEnabledAttribute) ?? true

                    if let pos = Self.axPoint(elem, kAXPositionAttribute),
                       let size = Self.axSize(elem, kAXSizeAttribute),
                       size.width >= 10, size.height >= 10,
                       size.width <= target.bounds.width * 1.05,
                       size.height <= target.bounds.height * 1.05 {
                        let frame = CGRect(origin: pos, size: size)
                        let label = [title, desc, help, valStr]
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .first(where: { !$0.isEmpty }) ?? ""
                        let isInteractiveRole = [
                            "AXButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton",
                            "AXPopUpButton", "AXMenuButton", "AXMenuItem", "AXTab", "AXTabGroup",
                            "AXLink", "AXComboBox", "AXSearchField", "AXSegmentedControl", "AXDisclosureTriangle"
                        ].contains(role)

                        if isInteractiveRole || (!label.isEmpty && label.count <= 90 && (role.contains("Button") || role.contains("Text") || role.contains("Cell"))) {
                            let center = CGPoint(x: frame.midX, y: frame.midY)
                            if target.bounds.insetBy(dx: -20, dy: -20).contains(center),
                               !isDuplicateCenter(center, label: label) {
                                collected.append((role, label.isEmpty ? role.replacingOccurrences(of: "AX", with: "") : label, String(valStr.prefix(80)), enabled, frame, elem))
                            }
                        }
                    }

                    var childrenRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                       let children = childrenRef as? [AXUIElement] {
                        for child in children.prefix(60) {
                            walkAX(child, depth: depth + 1)
                        }
                    }
                }

                for w in axWindows {
                    walkAX(w, depth: 0)
                }

                for item in collected {
                    let winFrame = CGRect(
                        x: item.frame.origin.x - target.bounds.origin.x,
                        y: item.frame.origin.y - target.bounds.origin.y,
                        width: item.frame.width,
                        height: item.frame.height
                    )
                    let nextId = rawMarks.count + 1
                    rawMarks.append(ComputerUseMark(
                        id: nextId,
                        role: item.role,
                        label: item.label,
                        value: item.value,
                        enabled: item.enabled,
                        screenFrame: item.frame,
                        windowFrame: winFrame,
                        axElement: item.elem,
                        inProcessView: nil
                    ))
                }
            }
        }

        // Layer B: In-Process AppKit `NSView` Hierarchy Fallback (works 100% WITHOUT macOS Accessibility TCC for MicroCode's own windows!)
        if rawMarks.isEmpty && target.isMicroCodeProcess {
            let nsWin = NSApp.windows.first(where: { $0.windowNumber == Int(target.windowId) })
                ?? NSApp.mainWindow
                ?? NSApp.windows.first(where: { $0.isVisible })
            if let nsWin, let rootView = nsWin.contentView {
                let screenH = NSScreen.main?.frame.height ?? 1080
                var viewItems: [(role: String, label: String, frame: CGRect, view: NSView)] = []

                func walkNSView(_ v: NSView, depth: Int) {
                    guard depth <= 22, !v.isHidden, v.alphaValue > 0.05, viewItems.count < 140 else { return }
                    let winRect = v.convert(v.bounds, to: nil)
                    let screenRectAppKit = nsWin.convertToScreen(winRect)
                    let qFrame = CGRect(
                        x: screenRectAppKit.origin.x,
                        y: screenH - (screenRectAppKit.origin.y + screenRectAppKit.height),
                        width: screenRectAppKit.width,
                        height: screenRectAppKit.height
                    )

                    if qFrame.width >= 14 && qFrame.height >= 12 && qFrame.width < target.bounds.width * 0.95 {
                        var label = v.accessibilityLabel() ?? v.accessibilityTitle() ?? v.toolTip ?? ""
                        var role = ""
                        if let btn = v as? NSButton {
                            role = "AXButton"
                            if label.isEmpty { label = btn.title }
                        } else if let tf = v as? NSTextField {
                            role = tf.isEditable ? "AXTextField" : "AXStaticText"
                            if label.isEmpty { label = tf.placeholderString ?? tf.stringValue }
                        } else if let seg = v as? NSSegmentedControl {
                            role = "AXSegmentedControl"
                            var segLabels: [String] = []
                            for i in 0..<seg.segmentCount {
                                if let l = seg.label(forSegment: i), !l.isEmpty { segLabels.append(l) }
                            }
                            if label.isEmpty { label = segLabels.joined(separator: " | ") }
                        } else if let pop = v as? NSPopUpButton {
                            role = "AXPopUpButton"
                            if label.isEmpty { label = pop.titleOfSelectedItem ?? pop.title }
                        } else if !label.isEmpty {
                            role = v.accessibilityRole()?.rawValue ?? "AXControl"
                        }

                        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !role.isEmpty && (!cleanLabel.isEmpty || role == "AXTextField") {
                            let center = CGPoint(x: qFrame.midX, y: qFrame.midY)
                            if !isDuplicateCenter(center, label: cleanLabel) {
                                viewItems.append((role, cleanLabel.isEmpty ? role : String(cleanLabel.prefix(80)), qFrame, v))
                            }
                        }
                    }

                    for sub in v.subviews {
                        walkNSView(sub, depth: depth + 1)
                    }
                }

                walkNSView(rootView, depth: 0)
                for item in viewItems {
                    let winFrame = CGRect(
                        x: item.frame.origin.x - target.bounds.origin.x,
                        y: item.frame.origin.y - target.bounds.origin.y,
                        width: item.frame.width,
                        height: item.frame.height
                    )
                    let nextId = rawMarks.count + 1
                    rawMarks.append(ComputerUseMark(
                        id: nextId,
                        role: item.role,
                        label: item.label,
                        value: "",
                        enabled: true,
                        screenFrame: item.frame,
                        windowFrame: winFrame,
                        axElement: nil,
                        inProcessView: item.view
                    ))
                }
            }
        }

        // Layer C: Apple Neural Engine Vision OCR Augmentation (fills in SwiftUI/Metal/Web labels not exposed via AX)
        if let cgImage = cgImageForOCR, rawMarks.count < 85 {
            let ocrBoxes = await Self.recognizeOCRTextBoxes(in: cgImage)
            for box in ocrBoxes {
                guard rawMarks.count < 110 else { break }
                // Convert normalized Vision rect (bottom-left 0..1) to top-left logical window coordinates
                let winX = box.normalizedRect.origin.x * target.bounds.width
                let winY = (1.0 - box.normalizedRect.origin.y - box.normalizedRect.height) * target.bounds.height
                let winW = box.normalizedRect.width * target.bounds.width
                let winH = box.normalizedRect.height * target.bounds.height
                let winFrame = CGRect(x: winX, y: winY, width: winW, height: winH)
                let screenFrame = CGRect(
                    x: target.bounds.origin.x + winX,
                    y: target.bounds.origin.y + winY,
                    width: winW,
                    height: winH
                )
                let center = CGPoint(x: screenFrame.midX, y: screenFrame.midY)
                if !isDuplicateCenter(center, label: box.text) {
                    let nextId = rawMarks.count + 1
                    rawMarks.append(ComputerUseMark(
                        id: nextId,
                        role: "OCRText",
                        label: box.text,
                        value: "",
                        enabled: true,
                        screenFrame: screenFrame,
                        windowFrame: winFrame,
                        axElement: nil,
                        inProcessView: nil
                    ))
                }
            }
        }

        // Cache all marks by ID for instant `click(mark_id:)` lookup
        self.cachedMarks.removeAll()
        for m in rawMarks {
            self.cachedMarks[m.id] = m
        }

        // Apply optional query / role filter for return list while keeping cachedMarks intact
        var filtered = rawMarks
        if let q = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !q.isEmpty {
            filtered = filtered.filter {
                $0.label.lowercased().contains(q) || $0.role.lowercased().contains(q) || $0.value.lowercased().contains(q)
            }
        }
        if let r = roleFilter?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !r.isEmpty {
            filtered = filtered.filter { $0.role.lowercased().contains(r) }
        }
        return filtered
    }

    // MARK: - 4. Window Capture + Set-of-Mark Visual Overlay (1x Logical Coordinates)

    public func captureAndAnnotate(
        target: TargetWindowInfo,
        drawSetOfMark: Bool = true,
        outputPath: String? = nil,
        cropRect: CGRect? = nil,
        highResolutionCrop: Bool = false
    ) async throws -> (path: String, base64JPEG: String, imageSize: CGSize, marks: [ComputerUseMark], captureMethod: String) {
        let (rawCGImage, captureMethod) = try captureWindowCGImage(target: target, nominalResolution: !highResolutionCrop)

        var workingCGImage = rawCGImage
        if let crop = cropRect {
            let scaleX = CGFloat(rawCGImage.width) / max(1.0, target.bounds.width)
            let scaleY = CGFloat(rawCGImage.height) / max(1.0, target.bounds.height)
            let scaledCrop = CGRect(
                x: max(0, crop.origin.x * scaleX),
                y: max(0, crop.origin.y * scaleY),
                width: min(CGFloat(rawCGImage.width), crop.width * scaleX),
                height: min(CGFloat(rawCGImage.height), crop.height * scaleY)
            ).integral
            if let cropped = rawCGImage.cropping(to: scaledCrop) {
                workingCGImage = cropped
            }
        }

        let marks = await inspectElements(
            target: target,
            cgImageForOCR: workingCGImage
        )

        let logicalSize = cropRect?.size ?? target.bounds.size
        let finalImage: NSImage
        if drawSetOfMark && cropRect == nil {
            finalImage = Self.renderSetOfMarkOverlay(baseCGImage: workingCGImage, logicalSize: logicalSize, marks: marks)
        } else {
            finalImage = NSImage(cgImage: workingCGImage, size: logicalSize)
        }

        let destPath = outputPath ?? "/tmp/microcode_computer_use_som.png"
        let absURL = URL(fileURLWithPath: (destPath as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: absURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var jpegBase64 = ""
        if let tiff = finalImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            if destPath.lowercased().hasSuffix(".jpg") || destPath.lowercased().hasSuffix(".jpeg") {
                if let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.80]) {
                    try? jpg.write(to: absURL)
                    jpegBase64 = jpg.base64EncodedString()
                }
            } else {
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: absURL)
                }
                if let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.78]) {
                    jpegBase64 = jpg.base64EncodedString()
                }
            }
        }

        return (absURL.path, jpegBase64, logicalSize, marks, captureMethod)
    }

    private func captureWindowCGImage(
        target: TargetWindowInfo,
        nominalResolution: Bool
    ) throws -> (CGImage, String) {
        // Method 1: For MicroCode's own windows, try in-process AppKit view caching if Screen Recording TCC isn't granted
        if target.isMicroCodeProcess && !CGPreflightScreenCaptureAccess() {
            if let cg = captureInProcessMicroCodeWindow(windowId: Int(target.windowId)) {
                return (cg, "in_process_appkit_no_tcc")
            }
        }

        // Method 2: CoreGraphics Window Capture (`.nominalResolution` guarantees 1:1 match with logical 1x CGEvent points)
        let imgOpts: CGWindowImageOption = nominalResolution
            ? [.boundsIgnoreFraming, .nominalResolution]
            : [.boundsIgnoreFraming, .bestResolution]
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, target.windowId, imgOpts),
           cg.width > 10 && cg.height > 10 {
            return (cg, nominalResolution ? "cgwindow_1x_nominal" : "cgwindow_2x_retina")
        }

        // Method 3: In-process AppKit fallback for MicroCode window even when CGWindowListCreateImage returns nil
        if target.isMicroCodeProcess, let cg = captureInProcessMicroCodeWindow(windowId: Int(target.windowId)) {
            return (cg, "in_process_appkit_fallback")
        }

        throw NSError(
            domain: "NativeComputerUse",
            code: 403,
            userInfo: [NSLocalizedDescriptionKey: "Unable to capture window #\(target.windowId) (\(target.appName)). Grant Screen Recording permission in System Settings → Privacy & Security → Screen Recording."]
        )
    }

    private func captureInProcessMicroCodeWindow(windowId: Int) -> CGImage? {
        let nsWin = NSApp.windows.first(where: { $0.windowNumber == windowId })
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.isVisible && $0.frame.width >= 200 })
        guard let nsWin, let contentView = nsWin.contentView else { return nil }
        let bounds = contentView.bounds
        guard bounds.width > 10 && bounds.height > 10,
              let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        contentView.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    private static func renderSetOfMarkOverlay(
        baseCGImage: CGImage,
        logicalSize: CGSize,
        marks: [ComputerUseMark]
    ) -> NSImage {
        let size = NSSize(width: max(1, logicalSize.width), height: max(1, logicalSize.height))
        let img = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            return NSImage(cgImage: baseCGImage, size: size)
        }

        ctx.draw(baseCGImage, in: CGRect(origin: .zero, size: size))

        // Draw Set-of-Mark badges in top-left logical coordinates (flip Y for AppKit drawing context)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white
        ]

        for mark in marks.prefix(75) {
            let wf = mark.windowFrame
            let appKitY = size.height - wf.origin.y - wf.height
            let rect = CGRect(x: wf.origin.x, y: appKitY, width: wf.width, height: wf.height)

            let color: NSColor = mark.role == "OCRText"
                ? NSColor(calibratedRed: 0.12, green: 0.55, blue: 0.95, alpha: 0.88)
                : NSColor(calibratedRed: 0.92, green: 0.18, blue: 0.28, alpha: 0.92)

            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(1.25)
            ctx.stroke(rect)

            let tagStr = "\(mark.id)" as NSString
            let textSize = tagStr.size(withAttributes: attrs)
            let badgeW = max(16, textSize.width + 6)
            let badgeH: CGFloat = 14
            let badgeX = max(0, min(size.width - badgeW, rect.minX))
            let badgeY = max(0, min(size.height - badgeH, rect.maxY - badgeH))
            let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)

            let path = NSBezierPath(roundedRect: badgeRect, xRadius: 3, yRadius: 3)
            color.setFill()
            path.fill()
            tagStr.draw(
                at: NSPoint(x: badgeX + (badgeW - textSize.width) / 2.0, y: badgeY + 1),
                withAttributes: attrs
            )
        }

        return img
    }

    // MARK: - 5. Pragmatic Action Execution (Background-First AX + Cursor-Restoring CGEvent)

    public func performClick(
        targetWindow: TargetWindowInfo,
        markId: Int? = nil,
        query: String? = nil,
        roleFilter: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        windowRelative: Bool = false,
        button: String = "left",
        clickCount: Int = 1,
        deliveryMode: String = "auto",
        restoreCursor: Bool = true
    ) async throws -> [String: Any] {
        try enforceNotBlocked(targetWindow)

        var resolvedMark: ComputerUseMark? = nil
        if let mid = markId {
            if cachedMarks[mid] == nil {
                _ = await inspectElements(target: targetWindow)
            }
            resolvedMark = cachedMarks[mid]
            if resolvedMark == nil {
                throw NSError(domain: "NativeComputerUse", code: 404, userInfo: [NSLocalizedDescriptionKey: "Mark [\(mid)] not found. Call computer_use_observe first to refresh Set-of-Mark IDs."])
            }
        } else if let q = query, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let matches = await inspectElements(target: targetWindow, query: q, roleFilter: roleFilter)
            resolvedMark = matches.first
            if resolvedMark == nil {
                throw NSError(domain: "NativeComputerUse", code: 404, userInfo: [NSLocalizedDescriptionKey: "No UI element or OCR text matching '\(q)' found in \(targetWindow.appName)."])
            }
        }

        // 1. Background / Cursorless Attempt (`deliveryMode == "auto"` or `"ax"`)
        let mode = deliveryMode.lowercased()
        if mode != "cgevent" && mode != "physical",
           button.lowercased() == "left",
           clickCount == 1,
           let mark = resolvedMark {
            // 1A: Native AXUIElement `kAXPressAction` (does NOT move mouse or steal focus)
            if let axElem = mark.axElement {
                let err = AXUIElementPerformAction(axElem, kAXPressAction as CFString)
                if err == .success {
                    return [
                        "success": true,
                        "action": "click",
                        "delivery_used": "ax_press_background",
                        "cursor_moved": false,
                        "focus_stolen": false,
                        "mark_id": mark.id,
                        "element": mark.label,
                        "role": mark.role,
                        "coordinates": ["x": mark.screenCenter.x, "y": mark.screenCenter.y]
                    ]
                }
            }
            // 1B: In-Process AppKit `NSControl.performClick` for MicroCode's own controls (works without TCC!)
            if targetWindow.isMicroCodeProcess, let view = mark.inProcessView {
                if let btn = view as? NSButton {
                    btn.performClick(nil)
                    return [
                        "success": true,
                        "action": "click",
                        "delivery_used": "in_process_nsbutton_background",
                        "cursor_moved": false,
                        "focus_stolen": false,
                        "mark_id": mark.id,
                        "element": mark.label,
                        "role": mark.role,
                        "coordinates": ["x": mark.screenCenter.x, "y": mark.screenCenter.y]
                    ]
                } else if let tf = view as? NSTextField, tf.isEditable {
                    tf.window?.makeFirstResponder(tf)
                    return [
                        "success": true,
                        "action": "focus_textfield",
                        "delivery_used": "in_process_first_responder",
                        "cursor_moved": false,
                        "focus_stolen": false,
                        "mark_id": mark.id,
                        "element": mark.label,
                        "role": mark.role,
                        "coordinates": ["x": mark.screenCenter.x, "y": mark.screenCenter.y]
                    ]
                }
            }
        }

        // 2. Physical / Quartz `CGEvent` Fallback (activates target window for hit-testing, optionally restores cursor)
        let targetPoint: CGPoint
        if let mark = resolvedMark {
            targetPoint = mark.screenCenter
        } else if let x, let y {
            if windowRelative {
                targetPoint = CGPoint(x: targetWindow.bounds.origin.x + x, y: targetWindow.bounds.origin.y + y)
            } else {
                targetPoint = CGPoint(x: x, y: y)
            }
        } else {
            throw NSError(domain: "NativeComputerUse", code: 400, userInfo: [NSLocalizedDescriptionKey: "Provide 'mark_id', 'target' label, or ('x', 'y') coordinates."])
        }

        let savedCursor = CGEvent(source: nil)?.location
        activateApplication(pid: targetWindow.pid)
        try? await Task.sleep(nanoseconds: 45_000_000)

        postMouseClick(at: targetPoint, button: button, clickCount: max(1, clickCount))

        if restoreCursor, let savedCursor {
            try? await Task.sleep(nanoseconds: 35_000_000)
            if let moveBack = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: savedCursor, mouseButton: .left) {
                moveBack.post(tap: .cghidEventTap)
            }
        }

        return [
            "success": true,
            "action": button == "right" ? "right_click" : (clickCount > 1 ? "double_click" : "click"),
            "delivery_used": "cgevent_hid",
            "cursor_restored": restoreCursor,
            "mark_id": resolvedMark?.id as Any,
            "element": resolvedMark?.label ?? "(coordinates)",
            "role": resolvedMark?.role ?? "Coordinate",
            "clicked_at": ["x": Double(targetPoint.x.rounded()), "y": Double(targetPoint.y.rounded())]
        ]
    }

    public func performHover(
        targetWindow: TargetWindowInfo,
        markId: Int? = nil,
        x: Double? = nil,
        y: Double? = nil,
        windowRelative: Bool = false
    ) async throws -> [String: Any] {
        try enforceNotBlocked(targetWindow)
        let pt: CGPoint
        if let mid = markId, let m = cachedMarks[mid] {
            pt = m.screenCenter
        } else if let x, let y {
            pt = windowRelative
                ? CGPoint(x: targetWindow.bounds.origin.x + x, y: targetWindow.bounds.origin.y + y)
                : CGPoint(x: x, y: y)
        } else {
            throw NSError(domain: "NativeComputerUse", code: 400, userInfo: [NSLocalizedDescriptionKey: "Hover requires mark_id or (x, y)."])
        }
        if let ev = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left) {
            ev.post(tap: .cghidEventTap)
        }
        return ["success": true, "action": "hover", "at": ["x": pt.x, "y": pt.y]]
    }

    public func performDrag(
        targetWindow: TargetWindowInfo,
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double,
        windowRelative: Bool = false,
        steps: Int = 14
    ) async throws -> [String: Any] {
        try enforceNotBlocked(targetWindow)
        let start = windowRelative
            ? CGPoint(x: targetWindow.bounds.origin.x + fromX, y: targetWindow.bounds.origin.y + fromY)
            : CGPoint(x: fromX, y: fromY)
        let end = windowRelative
            ? CGPoint(x: targetWindow.bounds.origin.x + toX, y: targetWindow.bounds.origin.y + toY)
            : CGPoint(x: toX, y: toY)

        activateApplication(pid: targetWindow.pid)
        try? await Task.sleep(nanoseconds: 40_000_000)

        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 20_000_000)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)

        let totalSteps = max(4, min(40, steps))
        for i in 1...totalSteps {
            let t = CGFloat(i) / CGFloat(totalSteps)
            let cur = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged, mouseCursorPosition: cur, mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)?.post(tap: .cghidEventTap)

        return [
            "success": true,
            "action": "drag",
            "from": ["x": start.x, "y": start.y],
            "to": ["x": end.x, "y": end.y]
        ]
    }

    public func performScroll(
        targetWindow: TargetWindowInfo,
        deltaY: Int32,
        deltaX: Int32 = 0,
        x: Double? = nil,
        y: Double? = nil
    ) async throws -> [String: Any] {
        try enforceNotBlocked(targetWindow)
        let pt = (x != nil && y != nil)
            ? CGPoint(x: x!, y: y!)
            : CGPoint(x: targetWindow.bounds.midX, y: targetWindow.bounds.midY)

        let savedCursor = CGEvent(source: nil)?.location
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 15_000_000)

        if let scrollEv = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) {
            scrollEv.post(tap: .cghidEventTap)
        }

        if let savedCursor {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: savedCursor, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        return [
            "success": true,
            "action": "scroll",
            "delta_y": Int(deltaY),
            "delta_x": Int(deltaX),
            "at": ["x": pt.x, "y": pt.y]
        ]
    }

    public func performType(
        targetWindow: TargetWindowInfo,
        text: String,
        markId: Int? = nil,
        mode: String = "auto",
        pressEnter: Bool = false
    ) async throws -> [String: Any] {
        try enforceNotBlocked(targetWindow)

        var deliveryUsed = "keystroke"
        let lowerMode = mode.lowercased()

        // 1. If a specific markId was given, try background AXValue / in-process NSTextField first
        if let mid = markId, let mark = cachedMarks[mid] {
            if lowerMode != "keystroke", let axElem = mark.axElement {
                let setErr = AXUIElementSetAttributeValue(axElem, kAXValueAttribute as CFString, text as CFTypeRef)
                if setErr == .success {
                    if pressEnter {
                        _ = try? sendShortcut(targetWindow: targetWindow, modifiers: [], key: "return")
                    }
                    return [
                        "success": true,
                        "action": "type",
                        "delivery_used": "ax_set_value_background",
                        "typed_length": text.count,
                        "mark_id": mid
                    ]
                }
            }
            if targetWindow.isMicroCodeProcess, let tf = mark.inProcessView as? NSTextField, tf.isEditable {
                tf.stringValue = text
                if pressEnter {
                    tf.sendAction(tf.action, to: tf.target)
                }
                return [
                    "success": true,
                    "action": "type",
                    "delivery_used": "in_process_nstextfield",
                    "typed_length": text.count,
                    "mark_id": mid
                ]
            }
            // Otherwise focus the target element first
            _ = try? await performClick(targetWindow: targetWindow, markId: mid, restoreCursor: true)
            try? await Task.sleep(nanoseconds: 40_000_000)
        }

        // 2. Clipboard-Preserving Instant Paste (fast & 100% accurate for Thai/CJK/multiline/long strings)
        if lowerMode == "paste" || (lowerMode == "auto" && (text.count > 24 || !text.allSatisfy(\.isASCII))) {
            activateApplication(pid: targetWindow.pid)
            let pb = NSPasteboard.general
            let previousString = pb.string(forType: .string)
            pb.clearContents()
            pb.setString(text, forType: .string)
            try? await Task.sleep(nanoseconds: 25_000_000)
            try sendShortcut(targetWindow: targetWindow, modifiers: ["cmd"], key: "v", activateFirst: false)
            try? await Task.sleep(nanoseconds: 65_000_000)
            // Restore previous clipboard
            pb.clearContents()
            if let previousString {
                pb.setString(previousString, forType: .string)
            }
            deliveryUsed = "clipboard_paste_restored"
        } else {
            // 3. Hardware UTF-16 CGEvent Keystroke Injection
            activateApplication(pid: targetWindow.pid)
            let utf16Units = Array(text.utf16)
            let src = CGEventSource(stateID: .hidSystemState)
            for unit in utf16Units {
                var ch = unit
                if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                   let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                    down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
                    up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
                    down.post(tap: .cghidEventTap)
                    up.post(tap: .cghidEventTap)
                }
                try? await Task.sleep(nanoseconds: 6_000_000)
            }
            deliveryUsed = "cgevent_keystroke"
        }

        if pressEnter {
            try? await Task.sleep(nanoseconds: 30_000_000)
            try sendShortcut(targetWindow: targetWindow, modifiers: [], key: "return", activateFirst: false)
        }

        return [
            "success": true,
            "action": "type",
            "delivery_used": deliveryUsed,
            "typed_length": text.count,
            "pressed_enter": pressEnter
        ]
    }

    @discardableResult
    public func sendShortcut(
        targetWindow: TargetWindowInfo,
        modifiers: [String],
        key: String,
        activateFirst: Bool = true
    ) throws -> [String: Any] {
        try enforceNotBlocked(targetWindow)
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let keycode = Self.keycodes[cleanKey] else {
            throw NSError(domain: "NativeComputerUse", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unknown key name '\(key)'."])
        }

        if activateFirst {
            activateApplication(pid: targetWindow.pid)
        }

        var flags: CGEventFlags = []
        for mod in modifiers {
            switch mod.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "cmd", "command", "meta", "super":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "opt", "option", "alt":
                flags.insert(.maskAlternate)
            case "ctrl", "control":
                flags.insert(.maskControl)
            default:
                break
            }
        }

        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keycode, keyDown: true),
           let up = CGEvent(keyboardEventSource: src, virtualKey: keycode, keyDown: false) {
            if !flags.isEmpty {
                down.flags = flags
                up.flags = flags
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        return [
            "success": true,
            "action": "shortcut",
            "shortcut": modifiers.isEmpty ? cleanKey : "\(modifiers.joined(separator: "+"))+\(cleanKey)"
        ]
    }

    public func waitForCondition(
        targetWindow: TargetWindowInfo,
        text: String,
        timeoutMs: Int = 5000
    ) async -> [String: Any] {
        let deadline = Date().addingTimeInterval(Double(max(200, min(15_000, timeoutMs))) / 1000.0)
        let needle = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while Date() < deadline {
            if let (cg, _) = try? captureWindowCGImage(target: targetWindow, nominalResolution: true) {
                let marks = await inspectElements(target: targetWindow, query: needle, cgImageForOCR: cg)
                if let match = marks.first {
                    return [
                        "success": true,
                        "matched": match.label,
                        "mark_id": match.id,
                        "role": match.role
                    ]
                }
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return [
            "success": false,
            "matched": NSNull(),
            "error": "Timed out waiting \(timeoutMs)ms for '\(text)' in \(targetWindow.appName)."
        ]
    }

    // MARK: - 6. Unified JSON Router (for HTTP :18888, MCP Server, and In-Process AgentToolBox)

    public func handleRequest(_ payload: [String: Any]) async -> [String: Any] {
        let action = ((payload["action"] as? String) ?? "observe").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let appName = payload["app"] as? String
        let windowId = (payload["window_id"] as? Int) ?? (payload["window_id"] as? NSNumber)?.intValue
        let windowTitle = payload["window_title"] as? String

        if action == "permissions" || action == "status" {
            let prompt = (payload["prompt"] as? Bool) ?? false
            return [
                "success": true,
                "permissions": permissionStatus(promptIfNeeded: prompt),
                "windows": listWindows(appFilter: appName)
            ]
        }

        if action == "windows" || action == "list_windows" {
            return [
                "success": true,
                "permissions": permissionStatus(promptIfNeeded: false),
                "windows": listWindows(appFilter: appName)
            ]
        }

        do {
            let target = try resolveTargetWindow(appName: appName, windowId: windowId, windowTitle: windowTitle)

            switch action {
            case "inspect":
                let cg = (try? captureWindowCGImage(target: target, nominalResolution: true))?.0
                let marks = await inspectElements(
                    target: target,
                    query: payload["query"] as? String,
                    roleFilter: payload["role"] as? String,
                    cgImageForOCR: cg
                )
                return [
                    "success": true,
                    "window": Self.encodeWindow(target),
                    "permissions": permissionStatus(promptIfNeeded: false),
                    "element_count": marks.count,
                    "elements": marks.map(Self.encodeMark)
                ]

            case "observe", "capture":
                let drawSoM = (payload["set_of_mark"] as? Bool) ?? (action == "observe")
                let outPath = payload["output_path"] as? String
                let includeImage = (payload["include_image"] as? Bool) ?? true
                let obs = try await captureAndAnnotate(
                    target: target,
                    drawSetOfMark: drawSoM,
                    outputPath: outPath
                )
                var resp: [String: Any] = [
                    "success": true,
                    "path": obs.path,
                    "capture_method": obs.captureMethod,
                    "window": Self.encodeWindow(target),
                    "logical_size": ["width": obs.imageSize.width, "height": obs.imageSize.height],
                    "permissions": permissionStatus(promptIfNeeded: false),
                    "mark_count": obs.marks.count,
                    "marks": obs.marks.prefix(80).map(Self.encodeMark)
                ]
                if includeImage && !obs.base64JPEG.isEmpty {
                    resp["image_base64"] = obs.base64JPEG
                    resp["image_mime_type"] = "image/jpeg"
                }
                return resp

            case "zoom":
                let x = (payload["x"] as? Double) ?? (payload["x"] as? NSNumber)?.doubleValue ?? 0
                let y = (payload["y"] as? Double) ?? (payload["y"] as? NSNumber)?.doubleValue ?? 0
                let w = (payload["width"] as? Double) ?? (payload["width"] as? NSNumber)?.doubleValue ?? 320
                let h = (payload["height"] as? Double) ?? (payload["height"] as? NSNumber)?.doubleValue ?? 240
                let crop = CGRect(x: x, y: y, width: max(40, w), height: max(40, h))
                let obs = try await captureAndAnnotate(
                    target: target,
                    drawSetOfMark: false,
                    outputPath: (payload["output_path"] as? String) ?? "/tmp/microcode_zoom.png",
                    cropRect: crop,
                    highResolutionCrop: true
                )
                return [
                    "success": true,
                    "action": "zoom",
                    "path": obs.path,
                    "crop_rect": ["x": x, "y": y, "width": w, "height": h],
                    "image_base64": obs.base64JPEG,
                    "image_mime_type": "image/jpeg"
                ]

            case "click", "double_click", "right_click":
                let markId = (payload["mark_id"] as? Int) ?? (payload["mark_id"] as? NSNumber)?.intValue
                let query = (payload["target"] as? String) ?? (payload["query"] as? String)
                let x = (payload["x"] as? Double) ?? (payload["x"] as? NSNumber)?.doubleValue
                let y = (payload["y"] as? Double) ?? (payload["y"] as? NSNumber)?.doubleValue
                let clicks = action == "double_click" ? 2 : ((payload["click_count"] as? Int) ?? 1)
                let btn = action == "right_click" ? "right" : ((payload["button"] as? String) ?? "left")
                let delivery = (payload["delivery"] as? String) ?? "auto"
                let restore = (payload["restore_cursor"] as? Bool) ?? true
                let winRel = (payload["window_relative"] as? Bool) ?? false
                return try await performClick(
                    targetWindow: target,
                    markId: markId,
                    query: query,
                    roleFilter: payload["role"] as? String,
                    x: x,
                    y: y,
                    windowRelative: winRel,
                    button: btn,
                    clickCount: clicks,
                    deliveryMode: delivery,
                    restoreCursor: restore
                )

            case "hover":
                return try await performHover(
                    targetWindow: target,
                    markId: (payload["mark_id"] as? Int) ?? (payload["mark_id"] as? NSNumber)?.intValue,
                    x: (payload["x"] as? Double) ?? (payload["x"] as? NSNumber)?.doubleValue,
                    y: (payload["y"] as? Double) ?? (payload["y"] as? NSNumber)?.doubleValue,
                    windowRelative: (payload["window_relative"] as? Bool) ?? false
                )

            case "drag":
                return try await performDrag(
                    targetWindow: target,
                    fromX: (payload["x"] as? Double) ?? (payload["from_x"] as? Double) ?? 0,
                    fromY: (payload["y"] as? Double) ?? (payload["from_y"] as? Double) ?? 0,
                    toX: (payload["to_x"] as? Double) ?? (payload["x2"] as? Double) ?? 0,
                    toY: (payload["to_y"] as? Double) ?? (payload["y2"] as? Double) ?? 0,
                    windowRelative: (payload["window_relative"] as? Bool) ?? false
                )

            case "scroll":
                let dy = Int32((payload["delta_y"] as? Int) ?? (payload["delta_y"] as? NSNumber)?.intValue ?? -240)
                let dx = Int32((payload["delta_x"] as? Int) ?? (payload["delta_x"] as? NSNumber)?.intValue ?? 0)
                return try await performScroll(
                    targetWindow: target,
                    deltaY: dy,
                    deltaX: dx,
                    x: (payload["x"] as? Double) ?? (payload["x"] as? NSNumber)?.doubleValue,
                    y: (payload["y"] as? Double) ?? (payload["y"] as? NSNumber)?.doubleValue
                )

            case "type":
                let text = (payload["text"] as? String) ?? ""
                let markId = (payload["mark_id"] as? Int) ?? (payload["mark_id"] as? NSNumber)?.intValue
                let mode = (payload["mode"] as? String) ?? "auto"
                let enter = (payload["press_enter"] as? Bool) ?? false
                return try await performType(
                    targetWindow: target,
                    text: text,
                    markId: markId,
                    mode: mode,
                    pressEnter: enter
                )

            case "shortcut", "key":
                let mods = (payload["modifiers"] as? [String]) ?? []
                let key = (payload["key"] as? String) ?? "return"
                return try sendShortcut(targetWindow: target, modifiers: mods, key: key)

            case "wait_for":
                let text = (payload["text"] as? String) ?? (payload["target"] as? String) ?? ""
                let timeout = (payload["timeout_ms"] as? Int) ?? 5000
                return await waitForCondition(targetWindow: target, text: text, timeoutMs: timeout)

            case "batch":
                let steps = (payload["steps"] as? [[String: Any]]) ?? []
                var stepResults: [[String: Any]] = []
                for step in steps.prefix(25) {
                    if let sleepMs = (step["sleep_ms"] as? Int) ?? (step["sleep_ms"] as? NSNumber)?.intValue {
                        try? await Task.sleep(nanoseconds: UInt64(max(10, min(5000, sleepMs))) * 1_000_000)
                        stepResults.append(["action": "sleep_ms", "ms": sleepMs, "success": true])
                        continue
                    }
                    var merged = step
                    if merged["app"] == nil, let appName { merged["app"] = appName }
                    if merged["window_id"] == nil, let windowId { merged["window_id"] = windowId }
                    let res = await handleRequest(merged)
                    stepResults.append(res)
                    if (res["success"] as? Bool) == false && ((step["stop_on_error"] as? Bool) ?? true) {
                        break
                    }
                }
                let finalObs = try? await captureAndAnnotate(target: target, drawSetOfMark: true)
                return [
                    "success": true,
                    "action": "batch",
                    "executed_steps": stepResults.count,
                    "step_results": stepResults,
                    "after_screenshot": finalObs?.path as Any,
                    "after_mark_count": finalObs?.marks.count ?? 0,
                    "image_base64": (finalObs?.base64JPEG ?? ""),
                    "image_mime_type": "image/jpeg"
                ]

            case "qa_verify", "live_test":
                let beforePath = "/tmp/microcode_qa_before.png"
                let afterPath = "/tmp/microcode_qa_after.png"
                let beforeImg = try captureWindowCGImage(target: target, nominalResolution: true).0
                _ = try? await captureAndAnnotate(target: target, drawSetOfMark: false, outputPath: beforePath)

                var stepResults: [[String: Any]] = []
                if let steps = payload["steps"] as? [[String: Any]], !steps.isEmpty {
                    for step in steps.prefix(20) {
                        var merged = step
                        if merged["app"] == nil, let appName { merged["app"] = appName }
                        stepResults.append(await handleRequest(merged))
                    }
                } else if let clickTarget = payload["target"] as? String {
                    stepResults.append(try await performClick(targetWindow: target, query: clickTarget))
                }

                try? await Task.sleep(nanoseconds: 350_000_000)
                let afterImg = try captureWindowCGImage(target: target, nominalResolution: true).0
                let afterObs = try await captureAndAnnotate(target: target, drawSetOfMark: true, outputPath: afterPath)
                let diffRatio = Self.computePixelDiffRatio(beforeImg, afterImg)

                var expectationMet = true
                if let expectedText = payload["expect_text"] as? String, !expectedText.isEmpty {
                    let needle = expectedText.lowercased()
                    expectationMet = afterObs.marks.contains { $0.label.lowercased().contains(needle) }
                }

                return [
                    "status": expectationMet ? "success" : "expectation_failed",
                    "success": expectationMet,
                    "before_screenshot": beforePath,
                    "after_screenshot": afterObs.path,
                    "pixel_diff_ratio": Double((diffRatio * 10000).rounded() / 10000),
                    "visual_changed": diffRatio > 0.001,
                    "mark_count": afterObs.marks.count,
                    "marks": afterObs.marks.prefix(50).map(Self.encodeMark),
                    "step_results": stepResults,
                    "image_base64": afterObs.base64JPEG,
                    "image_mime_type": "image/jpeg"
                ]

            default:
                return ["success": false, "error": "Unknown Computer Use action '\(action)'."]
            }
        } catch {
            return [
                "success": false,
                "error": error.localizedDescription,
                "permissions": permissionStatus(promptIfNeeded: false)
            ]
        }
    }

    // MARK: - Helpers (AX Attributes, Mouse Post, OCR, Pixel Diff)

    private func activateApplication(pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func postMouseClick(at pt: CGPoint, button: String, clickCount: Int) {
        let src = CGEventSource(stateID: .hidSystemState)
        let isRight = button.lowercased() == "right"
        let downType: CGEventType = isRight ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = isRight ? .rightMouseUp : .leftMouseUp
        let mouseBtn: CGMouseButton = isRight ? .right : .left

        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(18_000)

        for i in 1...max(1, clickCount) {
            if let down = CGEvent(mouseEventSource: src, mouseType: downType, mouseCursorPosition: pt, mouseButton: mouseBtn),
               let up = CGEvent(mouseEventSource: src, mouseType: upType, mouseCursorPosition: pt, mouseButton: mouseBtn) {
                down.setIntegerValueField(.mouseEventClickState, value: Int64(i))
                up.setIntegerValueField(.mouseEventClickState, value: Int64(i))
                down.post(tap: .cghidEventTap)
                usleep(25_000)
                up.post(tap: .cghidEventTap)
                if i < clickCount { usleep(40_000) }
            }
        }
    }

    private nonisolated static func recognizeOCRTextBoxes(
        in cgImage: CGImage
    ) async -> [(text: String, normalizedRect: CGRect)] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .fast
                req.recognitionLanguages = ["en-US", "th-TH"]
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([req])
                var out: [(String, CGRect)] = []
                for obs in (req.results ?? []).prefix(70) {
                    if let top = obs.topCandidates(1).first {
                        let str = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        if str.count >= 2 && str.count <= 60 {
                            out.append((str, obs.boundingBox))
                        }
                    }
                }
                continuation.resume(returning: out)
            }
        }
    }

    private nonisolated static func computePixelDiffRatio(_ a: CGImage, _ b: CGImage) -> Double {
        let sampleW = 64
        let sampleH = 64
        let bytesPerRow = sampleW * 4
        var bufA = [UInt8](repeating: 0, count: sampleH * bytesPerRow)
        var bufB = [UInt8](repeating: 0, count: sampleH * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctxA = CGContext(data: &bufA, width: sampleW, height: sampleH, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo),
              let ctxB = CGContext(data: &bufB, width: sampleW, height: sampleH, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return 0
        }
        ctxA.draw(a, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))
        ctxB.draw(b, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))

        var changed = 0
        let totalPixels = sampleW * sampleH
        for i in stride(from: 0, to: bufA.count, by: 4) {
            let dr = abs(Int(bufA[i]) - Int(bufB[i]))
            let dg = abs(Int(bufA[i + 1]) - Int(bufB[i + 1]))
            let db = abs(Int(bufA[i + 2]) - Int(bufB[i + 2]))
            if dr + dg + db > 28 {
                changed += 1
            }
        }
        return Double(changed) / Double(max(1, totalPixels))
    }

    private static func axString(_ elem: AXUIElement, _ attr: String) -> String? {
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, attr as CFString, &val) == .success, let val else { return nil }
        if let s = val as? String { return s }
        if let n = val as? NSNumber { return n.stringValue }
        return nil
    }

    private static func axBool(_ elem: AXUIElement, _ attr: String) -> Bool? {
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, attr as CFString, &val) == .success,
              let b = val as? Bool else { return nil }
        return b
    }

    private static func axPoint(_ elem: AXUIElement, _ attr: String) -> CGPoint? {
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, attr as CFString, &val) == .success,
              let val, CFGetTypeID(val) == AXValueGetTypeID() else { return nil }
        var pt = CGPoint.zero
        return AXValueGetValue(val as! AXValue, .cgPoint, &pt) ? pt : nil
    }

    private static func axSize(_ elem: AXUIElement, _ attr: String) -> CGSize? {
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, attr as CFString, &val) == .success,
              let val, CFGetTypeID(val) == AXValueGetTypeID() else { return nil }
        var sz = CGSize.zero
        return AXValueGetValue(val as! AXValue, .cgSize, &sz) ? sz : nil
    }

    private static func encodeWindow(_ w: TargetWindowInfo) -> [String: Any] {
        [
            "window_id": Int(w.windowId),
            "pid": Int(w.pid),
            "app_name": w.appName,
            "bundle_id": w.bundleId,
            "title": w.windowTitle,
            "bounds": [
                "x": Double(w.bounds.origin.x.rounded()),
                "y": Double(w.bounds.origin.y.rounded()),
                "width": Double(w.bounds.width.rounded()),
                "height": Double(w.bounds.height.rounded())
            ]
        ]
    }

    private static func encodeMark(_ m: ComputerUseMark) -> [String: Any] {
        [
            "mark_id": m.id,
            "role": m.role,
            "label": m.label,
            "value": m.value,
            "enabled": m.enabled,
            "center": ["x": Double(m.screenCenter.x), "y": Double(m.screenCenter.y)],
            "window_center": ["x": Double(m.windowCenter.x), "y": Double(m.windowCenter.y)],
            "bounds": [
                "x": Double(m.screenFrame.origin.x.rounded()),
                "y": Double(m.screenFrame.origin.y.rounded()),
                "width": Double(m.screenFrame.width.rounded()),
                "height": Double(m.screenFrame.height.rounded())
            ]
        ]
    }
}

// MARK: - In-Process AgentTool Wrapper (`computer_use`)

struct NativeComputerUseTool: AgentTool {
    let name = "computer_use"
    let description = """
    Native macOS Computer Use engine with Hybrid Set-of-Mark (`[1..N]` AX + Apple Vision OCR), 1x logical Retina-accurate coordinates, background-first AXPress/AXValue execution, cursor restoration, multi-app window targeting, and strict security denylist (SecurityAgent, Keychain, Password Managers, System Settings blocked).
    Actions: 'observe', 'inspect', 'windows', 'click', 'double_click', 'right_click', 'hover', 'drag', 'scroll', 'type', 'shortcut', 'zoom', 'wait_for', 'batch', 'qa_verify', 'permissions'.
    """

    let parameters: [ToolParameter] = [
        ToolParameter(name: "action", type: "string", description: "Action: 'observe' (Set-of-Mark screenshot + mark list), 'inspect', 'windows', 'click', 'double_click', 'right_click', 'hover', 'drag', 'scroll', 'type', 'shortcut', 'zoom', 'wait_for', 'batch', 'qa_verify', 'permissions'", required: true),
        ToolParameter(name: "app", type: "string", description: "Optional target application name (defaults to 'MicroCode')", required: false),
        ToolParameter(name: "window_id", type: "integer", description: "Optional specific CGWindowID", required: false),
        ToolParameter(name: "mark_id", type: "integer", description: "Set-of-Mark numeric badge ID `[1..N]` from 'observe' or 'inspect'", required: false),
        ToolParameter(name: "target", type: "string", description: "Element label/title or OCR text substring to click or wait_for", required: false),
        ToolParameter(name: "role", type: "string", description: "Optional AX role filter (e.g. AXButton, AXTextField)", required: false),
        ToolParameter(name: "x", type: "number", description: "Logical 1x X coordinate", required: false),
        ToolParameter(name: "y", type: "number", description: "Logical 1x Y coordinate", required: false),
        ToolParameter(name: "to_x", type: "number", description: "Destination X coordinate for 'drag'", required: false),
        ToolParameter(name: "to_y", type: "number", description: "Destination Y coordinate for 'drag'", required: false),
        ToolParameter(name: "delta_y", type: "integer", description: "Vertical scroll delta in pixels (negative scrolls down)", required: false),
        ToolParameter(name: "text", type: "string", description: "Text to type ('type') or text to wait for ('wait_for')", required: false),
        ToolParameter(name: "press_enter", type: "boolean", description: "Press Return after typing", required: false),
        ToolParameter(name: "key", type: "string", description: "Key name for 'shortcut' (e.g. 'return', 'k', 's', 'escape')", required: false),
        ToolParameter(name: "modifiers", type: "string", description: "Comma-separated or JSON array of modifiers: cmd, shift, opt, ctrl", required: false),
        ToolParameter(name: "delivery", type: "string", description: "'auto' (background AXPress first, then CGEvent), 'ax' (background only), or 'cgevent' (physical mouse)", required: false),
        ToolParameter(name: "output_path", type: "string", description: "Destination PNG path for 'observe', 'capture', or 'zoom'", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        var normalized = params
        if let modStr = params["modifiers"] as? String {
            let parts = modStr
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .replacingOccurrences(of: "\"", with: "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            normalized["modifiers"] = parts
        }
        // Strip inline base64 from text JSON returned to in-process text loop to save context tokens; path is preserved
        if normalized["include_image"] == nil {
            normalized["include_image"] = false
        }
        let result = await NativeComputerUseService.shared.handleRequest(normalized)
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

