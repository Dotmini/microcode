//
//  SimulatorManager.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import Foundation

// Using existing SimulatorDevice from ContentView.swift
// Note: ContentView's SimulatorDevice has: name, udid, state, runtime

class SimulatorManager {
    static let shared = SimulatorManager()
    
    private init() {}
    
    // MARK: - iOS Simulators
    
    func listIOSSimulators() async throws -> [SimulatorDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "-j"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let devices = json["devices"] as! [String: [[String: Any]]]
        
        var simulators: [SimulatorDevice] = []
        
        for (runtime, deviceList) in devices {
            for device in deviceList {
                let name = device["name"] as? String ?? ""
                let udid = device["udid"] as? String ?? ""
                let state = device["state"] as? String ?? ""
                let isAvailable = device["isAvailable"] as? Bool ?? false
                
                if isAvailable {
                    let sim = SimulatorDevice(
                        name: name,
                        udid: udid,
                        state: state,
                        runtime: runtime
                    )
                    simulators.append(sim)
                }
            }
        }
        
        return simulators
    }
    
    func bootSimulator(udid: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "boot", udid]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw SimulatorError.bootFailed
        }
    }
    
    func installApp(appPath: String, udid: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "install", udid, appPath]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw SimulatorError.installFailed
        }
    }
    
    func launchApp(bundleId: String, udid: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "launch", udid, bundleId]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw SimulatorError.launchFailed
        }
    }
    
    // MARK: - Android Emulators
    
    /// Find the Android SDK emulator path
    private func findEmulatorPath() -> String? {
        let fm = FileManager.default
        
        // 1. Check ANDROID_HOME environment variable
        if let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"] {
            let path = "\(androidHome)/emulator/emulator"
            if fm.fileExists(atPath: path) {
                return path
            }
        }
        
        // 2. Check ANDROID_SDK_ROOT
        if let sdkRoot = ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"] {
            let path = "\(sdkRoot)/emulator/emulator"
            if fm.fileExists(atPath: path) {
                return path
            }
        }
        
        // 3. Common macOS paths
        let commonPaths = [
            "\(NSHomeDirectory())/Library/Android/sdk/emulator/emulator",
            "/usr/local/share/android-sdk/emulator/emulator",
            "/opt/android-sdk/emulator/emulator",
            "/opt/homebrew/share/android-sdk/emulator/emulator",
            "\(NSHomeDirectory())/Android/Sdk/emulator/emulator",
            "/Applications/Android Studio.app/Contents/sdk/emulator/emulator"
        ]
        
        for path in commonPaths {
            if fm.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    /// Find ADB path for running devices
    private func findADBPath() -> String? {
        let fm = FileManager.default
        
        if let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"] {
            let path = "\(androidHome)/platform-tools/adb"
            if fm.fileExists(atPath: path) {
                return path
            }
        }
        
        let commonPaths = [
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "/usr/local/share/android-sdk/platform-tools/adb",
            "/opt/android-sdk/platform-tools/adb",
            "/opt/homebrew/share/android-sdk/platform-tools/adb"
        ]
        
        for path in commonPaths {
            if fm.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    func listAndroidEmulators() async throws -> [(name: String, id: String)] {
        guard let emulatorPath = findEmulatorPath() else {
            print("⚠️ Android emulator not found")
            return []
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: emulatorPath)
        process.arguments = ["-list-avds"]
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            let emulatorNames = output.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("INFO") && !$0.hasPrefix("WARNING") }
            
            print("📱 Found Android emulators: \(emulatorNames)")
            
            return emulatorNames.map { name in
                (name: name, id: name)
            }
        } catch {
            print("❌ Error listing Android emulators: \(error)")
            return []
        }
    }
    
    /// List running Android devices (real + emulator)
    func listRunningAndroidDevices() async throws -> [(name: String, id: String)] {
        guard let adbPath = findADBPath() else {
            return []
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["devices", "-l"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        var devices: [(name: String, id: String)] = []
        
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("device") && !trimmed.hasPrefix("List") {
                let parts = trimmed.components(separatedBy: .whitespaces)
                if let deviceId = parts.first {
                    // Try to get device model
                    var name = deviceId
                    if let modelRange = trimmed.range(of: "model:") {
                        let modelStart = trimmed.index(modelRange.upperBound, offsetBy: 0)
                        let remainder = String(trimmed[modelStart...])
                        name = remainder.components(separatedBy: .whitespaces).first ?? deviceId
                    }
                    devices.append((name: name, id: deviceId))
                }
            }
        }
        
        return devices
    }
    
    func launchAndroidEmulator(avdName: String) async throws {
        guard let emulatorPath = findEmulatorPath() else {
            throw SimulatorError.emulatorNotFound
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: emulatorPath)
        process.arguments = ["-avd", avdName, "-gpu", "auto"]
        
        try process.run()
        // Don't wait - emulator runs in background
        print("🚀 Launched Android emulator: \(avdName)")
    }
    
    // MARK: - Flutter Emulators
    
    func listFlutterEmulators() async throws -> [(name: String, id: String)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/flutter") // Common path, should ideally be dynamic
        process.arguments = ["emulators"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Example output:
            // apple_ios_simulator • iOS Simulator • apple • ios
            // pixel_5             • Pixel 5             • google • android
            
            var emulators: [(name: String, id: String)] = []
            let lines = output.components(separatedBy: "\n")
            
            for line in lines {
                let parts = line.components(separatedBy: "•")
                if parts.count >= 2 {
                    let id = parts[0].trimmingCharacters(in: .whitespaces)
                    let name = parts[1].trimmingCharacters(in: .whitespaces)
                    if !id.isEmpty && !id.hasPrefix("-") {
                        emulators.append((name: name, id: id))
                    }
                }
            }
            
            return emulators
        } catch {
            print("❌ Error listing Flutter emulators: \(error)")
            return []
        }
    }
    
    // MARK: - Device Creation
    
    func createIOSSimulator(name: String, deviceTypeId: String, runtimeId: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "create", name, deviceTypeId, runtimeId]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw SimulatorError.creationFailed("Failed to create iOS Simulator")
        }
    }
    
    func createAndroidEmulator(name: String, package: String) async throws {
        // Need to find avdmanager
        guard let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"] ?? 
                ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"] ??
                "\(NSHomeDirectory())/Library/Android/sdk" as String? else {
            throw SimulatorError.emulatorNotFound
        }
        
        let avdManagerPath = "\(androidHome)/tools/bin/avdmanager"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: avdManagerPath)
        // echo "no" | avdmanager create avd -n name -k package
        process.arguments = ["create", "avd", "-n", name, "-k", package, "-f"]
        
        // Provide "no" to the prompt about custom hardware profile
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        
        try process.run()
        inputPipe.fileHandleForWriting.write("no\n".data(using: .utf8)!)
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw SimulatorError.creationFailed("Failed to create Android Emulator. Ensure the system image '\(package)' is installed.")
        }
    }
    
    func listAvailableRuntimes() async throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "runtimes", "-j"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let runtimes = json["runtimes"] as! [[String: Any]]
        
        return runtimes.compactMap { $0["identifier"] as? String }
    }
    
    func listAvailableDeviceTypes() async throws -> [(name: String, id: String)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devicetypes", "-j"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let deviceTypes = json["devicetypes"] as! [[String: Any]]
        
        return deviceTypes.compactMap { 
            guard let name = $0["name"] as? String, let id = $0["identifier"] as? String else { return nil }
            return (name: name, id: id)
        }
    }
    
    // MARK: - Build Operations
    
    func buildXcodeProject(projectPath: String, scheme: String, configuration: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = [
            "-project", projectPath,
            "-scheme", scheme,
            "-configuration", configuration,
            "-sdk", "iphonesimulator"
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        var output = ""
        
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if let text = String(data: data, encoding: .utf8) {
                output += text
            }
        }
        
        try process.run()
        process.waitUntilExit()
        
        handle.readabilityHandler = nil
        
        if process.terminationStatus != 0 {
            throw SimulatorError.buildFailed(output)
        }
        
        return output
    }
}

enum SimulatorError: LocalizedError {
    case bootFailed
    case installFailed
    case launchFailed
    case buildFailed(String)
    case emulatorNotFound
    case creationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .bootFailed:
            return "Failed to boot simulator"
        case .installFailed:
            return "Failed to install app"
        case .launchFailed:
            return "Failed to launch app"
        case .buildFailed(let output):
            return "Build failed:\n\(output)"
        case .emulatorNotFound:
            return "Android emulator not found. Please install Android Studio or set ANDROID_HOME."
        case .creationFailed(let message):
            return message
        }
    }
}
