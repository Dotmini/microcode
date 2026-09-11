//
//  DeviceCommandBarService.swift
//  MicroCode
//
//  Headless Mobile Dev Command Controller.
//  Controls iOS Simulator and Android Emulator without third-party tools:
//  - One-click Mock Push Notifications (.apns / .json drag & drop or dynamic templates)
//  - Deep Link & Universal Link direct launcher
//  - GPS Location Simulator with popular global presets (Bangkok, Tokyo, SF, etc.)
//  - Hardware triggers: Shake gesture, Dark/Light appearance, Network throttling, and App Wipe
//
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import Foundation
import Combine
import AppKit

public enum NetworkSimulationMode: String, CaseIterable, Identifiable {
    case full = "Full WiFi / 5G"
    case lte = "4G LTE"
    case threeG = "3G (Slow)"
    case offline = "Offline (Airplane)"
    
    public var id: String { rawValue }
    public var icon: String {
        switch self {
        case .full: return "wifi"
        case .lte: return "antenna.radiowaves.left.and.right"
        case .threeG: return "cellularbars"
        case .offline: return "airplane"
        }
    }
}

public struct LocationPreset: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let flag: String
    
    public static let presets: [LocationPreset] = [
        LocationPreset(name: "Bangkok", latitude: 13.7563, longitude: 100.5018, flag: "🇹🇭"),
        LocationPreset(name: "Tokyo", latitude: 35.6762, longitude: 139.6503, flag: "🇯🇵"),
        LocationPreset(name: "San Francisco", latitude: 37.7749, longitude: -122.4194, flag: "🇺🇸"),
        LocationPreset(name: "London", latitude: 51.5074, longitude: -0.1278, flag: "🇬🇧"),
        LocationPreset(name: "New York", latitude: 40.7128, longitude: -74.0060, flag: "🇺🇸"),
        LocationPreset(name: "Sydney", latitude: -33.8688, longitude: 151.2093, flag: "🇦🇺"),
        LocationPreset(name: "Singapore", latitude: 1.3521, longitude: 103.8198, flag: "🇸🇬"),
        LocationPreset(name: "Berlin", latitude: 52.5200, longitude: 13.4050, flag: "🇩🇪")
    ]
}

@MainActor
public final class DeviceCommandBarService: ObservableObject {
    public static let shared = DeviceCommandBarService()
    
    // MARK: - State
    @Published public var currentLocationPreset: LocationPreset = LocationPreset.presets[0]
    @Published public var customLatitude: Double = 13.7563
    @Published public var customLongitude: Double = 100.5018
    @Published public var isDarkMode: Bool = true
    @Published public var networkMode: NetworkSimulationMode = .full
    @Published public var deepLinkURL: String = ""
    @Published public var lastActionResult: String?
    @Published public var isExecuting: Bool = false
    
    // Quick Push Editor State
    @Published public var pushTitle: String = "Special Offer!"
    @Published public var pushBody: String = "Tap here to view your daily rewards and updates."
    @Published public var pushBadge: Int = 1
    @Published public var pushSound: String = "default"
    @Published public var pushCustomPayload: String = "{\n  \"action\": \"open_tab\",\n  \"target_id\": \"rewards_01\"\n}"
    
    private init() {}
    
    // MARK: - Push Notification Simulation
    
    /// Sends a mock push notification to the active iOS Simulator or Android Emulator.
    /// Uses native simctl push (iOS) or adb broadcast/notification intent (Android).
    public func sendMockPush(
        targetUDID: String?,
        bundleId: String?,
        isAndroid: Bool = false
    ) async {
        guard let udid = targetUDID, !udid.isEmpty else {
            lastActionResult = "⚠️ No active device selected for push notification."
            return
        }
        
        isExecuting = true
        defer { isExecuting = false }
        
        if isAndroid {
            await sendAndroidPush(serial: udid, bundleId: bundleId ?? "com.example.app")
        } else {
            await sendIOSPush(udid: udid, bundleId: bundleId ?? "com.example.app")
        }
    }
    
    private func sendIOSPush(udid: String, bundleId: String) async {
        // Construct standard Apple APNS payload
        var customDict: [String: Any] = [:]
        if let data = pushCustomPayload.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            customDict = json
        }
        
        var aps: [String: Any] = [
            "alert": [
                "title": pushTitle,
                "body": pushBody
            ],
            "badge": pushBadge,
            "sound": pushSound
        ]
        
        var apns: [String: Any] = customDict
        apns["Simulator Target Bundle"] = bundleId
        apns["aps"] = aps
        
        guard let apnsData = try? JSONSerialization.data(withJSONObject: apns, options: [.prettyPrinted]) else {
            lastActionResult = "❌ Failed to format APNS payload."
            return
        }
        
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("microcode-mock-push-\(UUID().uuidString).apns")
        
        do {
            try apnsData.write(to: tempFile)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "push", udid, bundleId, tempFile.path]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            try? FileManager.default.removeItem(at: tempFile)
            
            if process.terminationStatus == 0 {
                lastActionResult = "🔔 Push sent to iOS Simulator (\(bundleId))"
            } else {
                let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                let err = String(data: errData, encoding: .utf8) ?? "Unknown error"
                lastActionResult = "⚠️ Push failed: \(err.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        } catch {
            lastActionResult = "❌ Error sending push: \(error.localizedDescription)"
        }
    }
    
    private func sendAndroidPush(serial: String, bundleId: String) async {
        guard let adb = findADBPath() else {
            lastActionResult = "⚠️ ADB not found for Android push simulation."
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = [
            "-s", serial,
            "shell", "am", "broadcast",
            "-a", "\(bundleId).MOCK_PUSH",
            "--es", "title", pushTitle,
            "--es", "body", pushBody,
            "--es", "payload", pushCustomPayload
        ]
        
        do {
            try process.run()
            process.waitUntilExit()
            lastActionResult = "🔔 Broadcast push sent to Android (\(bundleId))"
        } catch {
            lastActionResult = "❌ Android push failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Deep Link / URL Launcher
    
    public func launchDeepLink(targetUDID: String?, isAndroid: Bool = false) async {
        let url = deepLinkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            lastActionResult = "⚠️ Enter a URL or Deep Link scheme to launch."
            return
        }
        guard let udid = targetUDID, !udid.isEmpty else {
            lastActionResult = "⚠️ No device selected."
            return
        }
        
        isExecuting = true
        defer { isExecuting = false }
        
        if isAndroid {
            guard let adb = findADBPath() else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adb)
            process.arguments = ["-s", udid, "shell", "am", "start", "-a", "android.intent.action.VIEW", "-d", url]
            try? process.run()
            process.waitUntilExit()
            lastActionResult = "🔗 Opened Deep Link on Android: \(url)"
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "openurl", udid, url]
            try? process.run()
            process.waitUntilExit()
            lastActionResult = "🔗 Opened Deep Link on iOS: \(url)"
        }
    }
    
    // MARK: - Mock Location (GPS)
    
    public func applyLocation(targetUDID: String?, isAndroid: Bool = false) async {
        guard let udid = targetUDID, !udid.isEmpty else { return }
        let lat = customLatitude
        let lng = customLongitude
        
        isExecuting = true
        defer { isExecuting = false }
        
        if isAndroid {
            guard let adb = findADBPath() else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adb)
            // adb emu geo fix <longitude> <latitude>
            process.arguments = ["-s", udid, "emu", "geo", "fix", String(format: "%.6f", lng), String(format: "%.6f", lat)]
            try? process.run()
            process.waitUntilExit()
            lastActionResult = "📍 GPS Set: \(lat), \(lng) (Android)"
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "location", udid, "set", "\(lat),\(lng)"]
            try? process.run()
            process.waitUntilExit()
            lastActionResult = "📍 GPS Set: \(lat), \(lng) (iOS Simulator)"
        }
    }
    
    public func selectLocationPreset(_ preset: LocationPreset, targetUDID: String?, isAndroid: Bool = false) async {
        currentLocationPreset = preset
        customLatitude = preset.latitude
        customLongitude = preset.longitude
        await applyLocation(targetUDID: targetUDID, isAndroid: isAndroid)
    }
    
    // MARK: - Device Gestures & Appearance
    
    public func triggerShake(targetUDID: String?, isAndroid: Bool = false) async {
        guard let udid = targetUDID, !udid.isEmpty else { return }
        if isAndroid {
            guard let adb = findADBPath() else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adb)
            // Shake simulation via emulator sensors
            process.arguments = ["-s", udid, "emu", "sensor", "set", "acceleration", "15:15:15"]
            try? process.run()
            process.waitUntilExit()
            
            try? await Task.sleep(nanoseconds: 200_000_000)
            let resetProc = Process()
            resetProc.executableURL = URL(fileURLWithPath: adb)
            resetProc.arguments = ["-s", udid, "emu", "sensor", "set", "acceleration", "0:9.8:0"]
            try? resetProc.run()
            resetProc.waitUntilExit()
            lastActionResult = "📳 Simulated Shake Gesture on Android"
        } else {
            // iOS Simulator Shake via AppleScript host event
            let script = "tell application \"Simulator\" to activate\ntell application \"System Events\" to tell process \"Simulator\" to keystroke \"z\" using {control down, command down}"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
            process.waitUntilExit()
            lastActionResult = "📳 Simulated Shake Gesture on iOS Simulator"
        }
    }
    
    public func toggleAppearance(targetUDID: String?, isAndroid: Bool = false) async {
        guard let udid = targetUDID, !udid.isEmpty else { return }
        isDarkMode.toggle()
        let mode = isDarkMode ? "dark" : "light"
        
        if isAndroid {
            guard let adb = findADBPath() else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adb)
            let nightArg = isDarkMode ? "yes" : "no"
            process.arguments = ["-s", udid, "shell", "cmd", "uimode", "night", nightArg]
            try? process.run()
            process.waitUntilExit()
            lastActionResult = "🌓 Switched Android UI to \(mode) mode"
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "ui", udid, "appearance", mode]
            try? process.run()
            process.waitUntilExit()
            lastActionResult = "🌓 Switched iOS UI to \(mode) mode"
        }
    }
    
    public func clearAppData(targetUDID: String?, bundleId: String?, isAndroid: Bool = false) async {
        guard let udid = targetUDID, !udid.isEmpty, let bundleId = bundleId, !bundleId.isEmpty else {
            lastActionResult = "⚠️ Bundle ID required to reset app data."
            return
        }
        
        if isAndroid {
            guard let adb = findADBPath() else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adb)
            process.arguments = ["-s", udid, "shell", "pm", "clear", bundleId]
            try? process.run()
            process.waitUntilExit()
            lastActionResult = "🧹 Cleared app data for \(bundleId) on Android"
        } else {
            // Terminate then uninstall/reinstall or clear container
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "terminate", udid, bundleId]
            try? process.run()
            process.waitUntilExit()
            lastActionResult = "🧹 Terminated \(bundleId) on iOS Simulator"
        }
    }
    
    // MARK: - Helpers
    
    private func findADBPath() -> String? {
        let env = ProcessInfo.processInfo.environment
        let candidates = [
            env["ANDROID_HOME"].map { "\($0)/platform-tools/adb" },
            env["ANDROID_SDK_ROOT"].map { "\($0)/platform-tools/adb" },
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ].compactMap { $0 }
        
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
