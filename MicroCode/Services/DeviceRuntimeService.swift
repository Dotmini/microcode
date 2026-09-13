//
//  DeviceRuntimeService.swift
//  MicroCode
//
//  Real local device runtimes. This service launches Apple's Simulator and
//  Google's Android Emulator as their own native windows; it intentionally
//  does not draw a fake device canvas inside the IDE.
//

import Foundation
import Combine
import AppKit
import ImageIO

enum DeviceRuntimePlatform: String, CaseIterable, Identifiable {
    case ios = "iOS / iPadOS"
    case android = "Android"
    case macOS = "macOS"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .ios: return "iphone"
        case .android: return "apps.iphone"
        case .macOS: return "desktopcomputer"
        }
    }
}

/// Keeps the deployment transport explicit. iOS simulators use `simctl`, while
/// paired phones and iPads use Xcode's CoreDevice (`devicectl`) APIs.
enum RuntimeDeviceKind: String, Hashable {
    case simulator
    case physical
    case generic
}

/// `simctl` reports every Apple simulator through the same inventory.  Keep
/// the family explicit so the UI does not present an Apple Watch or Apple TV
/// as an iPhone, and so run compatibility can be explained before a command
/// is launched.
enum AppleSimulatorFamily: String, CaseIterable, Hashable, Identifiable {
    case iPhone
    case iPad
    case watch
    case tv
    case vision
    case other

    var id: String { rawValue }

    init(name: String, runtime: String) {
        let value = "\(name) \(runtime)".lowercased()
        if value.contains("watch") || value.contains("watchos") { self = .watch }
        else if value.contains("apple tv") || value.contains("tvos") { self = .tv }
        else if value.contains("ipad") || value.contains("ipados") { self = .iPad }
        else if value.contains("vision") || value.contains("xros") { self = .vision }
        else if value.contains("iphone") || value.contains("ios") { self = .iPhone }
        else { self = .other }
    }

    var previewTitle: String {
        switch self {
        case .iPhone: return "iPhone Simulator"
        case .iPad: return "iPad Simulator"
        case .watch: return "Apple Watch Simulator"
        case .tv: return "Apple TV Simulator"
        case .vision: return "Apple Vision Simulator"
        case .other: return "Apple Simulator"
        }
    }

    var menuTitle: String {
        switch self {
        case .iPhone: return "iPhone Simulator"
        case .iPad: return "iPad Simulator"
        case .watch: return "Apple Watch Simulator"
        case .tv: return "Apple TV Simulator"
        case .vision: return "Apple Vision Simulator"
        case .other: return "Other Apple Simulator"
        }
    }

    var symbolName: String {
        switch self {
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .watch: return "applewatch"
        case .tv: return "appletv"
        case .vision: return "visionpro"
        case .other: return "rectangle.on.rectangle"
        }
    }

    var isMobile: Bool { self == .iPhone || self == .iPad }
    static let previewOrder: [AppleSimulatorFamily] = [.iPhone, .iPad, .watch, .tv, .vision, .other]
}

enum GUIProjectRuntime: String, Equatable {
    case xcode = "Apple app"
    case android = "Android app"
    case flutter = "Flutter"
    case reactNative = "React Native"
    case expo = "Expo"
    case unknown = "Unsupported"

    var supportedPlatforms: [DeviceRuntimePlatform] {
        switch self {
        case .xcode: return [.ios, .macOS]
        case .android: return [.android]
        case .flutter, .reactNative, .expo: return [.ios, .android]
        case .unknown: return []
        }
    }
}

struct RuntimeDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let platform: DeviceRuntimePlatform
    let state: String
    let runtime: String
    let isReadyForLaunch: Bool
    let preflightMessage: String?
    let kind: RuntimeDeviceKind

    init(
        id: String,
        name: String,
        platform: DeviceRuntimePlatform,
        state: String,
        runtime: String,
        isReadyForLaunch: Bool = true,
        preflightMessage: String? = nil,
        kind: RuntimeDeviceKind = .generic
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.state = state
        self.runtime = runtime
        self.isReadyForLaunch = isReadyForLaunch
        self.preflightMessage = preflightMessage
        self.kind = kind
    }

    var isAppleSimulator: Bool { platform == .ios && kind == .simulator }
    var isPhysicalAppleDevice: Bool { platform == .ios && kind == .physical }
    var appleSimulatorFamily: AppleSimulatorFamily? {
        guard isAppleSimulator else { return nil }
        return AppleSimulatorFamily(name: name, runtime: runtime)
    }
    var previewTitle: String { appleSimulatorFamily?.previewTitle ?? "Apple Simulator" }
    var displaySymbolName: String { appleSimulatorFamily?.symbolName ?? platform.icon }
    var isBooted: Bool {
        isPhysicalAppleDevice || state.caseInsensitiveCompare("booted") == .orderedSame || state.caseInsensitiveCompare("device") == .orderedSame
    }
    var detail: String { runtime.isEmpty ? state : "\(state) · \(runtime)" }
}

struct GUIProjectDescriptor: Equatable {
    let runtime: GUIProjectRuntime
    let root: URL
    let displayName: String
    let xcodeContainer: URL?
    let preferredScheme: String?

    static func detect(at root: URL) -> GUIProjectDescriptor {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        let lowerNames = Set(names.map { $0.lowercased() })
        let packageURL = root.appendingPathComponent("package.json")
        let package = (try? Data(contentsOf: packageURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let dependencies = (package?["dependencies"] as? [String: Any] ?? [:])
            .merging(package?["devDependencies"] as? [String: Any] ?? [:]) { current, _ in current }

        if let xcodeName = names.first(where: { $0.hasSuffix(".xcworkspace") || $0.hasSuffix(".xcodeproj") }) {
            return GUIProjectDescriptor(runtime: .xcode, root: root, displayName: xcodeName, xcodeContainer: root.appendingPathComponent(xcodeName), preferredScheme: nil)
        }
        if lowerNames.contains("pubspec.yaml") && (lowerNames.contains("ios") || lowerNames.contains("android")) {
            return GUIProjectDescriptor(runtime: .flutter, root: root, displayName: "Flutter", xcodeContainer: nil, preferredScheme: nil)
        }
        if dependencies["expo"] != nil {
            return GUIProjectDescriptor(runtime: .expo, root: root, displayName: "Expo", xcodeContainer: nil, preferredScheme: nil)
        }
        if dependencies["react-native"] != nil {
            return GUIProjectDescriptor(runtime: .reactNative, root: root, displayName: "React Native", xcodeContainer: nil, preferredScheme: nil)
        }
        if lowerNames.contains("settings.gradle") || lowerNames.contains("settings.gradle.kts") || lowerNames.contains("build.gradle") || lowerNames.contains("build.gradle.kts") {
            return GUIProjectDescriptor(runtime: .android, root: root, displayName: "Android", xcodeContainer: nil, preferredScheme: nil)
        }
        return GUIProjectDescriptor(runtime: .unknown, root: root, displayName: "No GUI runtime detected", xcodeContainer: nil, preferredScheme: nil)
    }
}

@MainActor
final class DeviceRuntimeService: ObservableObject {
    static let shared = DeviceRuntimeService()

    @Published private(set) var project: GUIProjectDescriptor?
    @Published private(set) var devices: [RuntimeDevice] = []
    @Published private(set) var statusMessage = "Open a GUI app project to use real devices."
    @Published private(set) var output = ""
    @Published private(set) var isWorking = false
    @Published var selectedDeviceID: String?
    @Published private(set) var buildSchemes: [String] = []
    @Published var selectedScheme: String?
    /// A downsampled real screen capture from an Android device/AVD. The
    /// source pixel size remains separate so display scaling never alters ADB
    /// pointer coordinates.
    @Published private(set) var embeddedAndroidImage: NSImage?
    /// The official Android SDK skin asset for the currently attached AVD.
    /// This is deliberately loaded from the AVD's configured skin rather than
    /// approximated with a SwiftUI bezel.
    @Published private(set) var embeddedAndroidFrame: NSImage?
    /// The official front camera punch-hole cutout mask for the attached AVD.
    @Published private(set) var embeddedAndroidMask: NSImage?
    @Published private(set) var embeddedAndroidPixelSize: CGSize = .zero
    @Published private(set) var embeddedAndroidSerial: String?
    @Published private(set) var isEmbeddedAndroidActive = false
    @Published private(set) var embeddedAndroidStatus = ""
    enum EmbeddedDockMode: String, CaseIterable, Identifiable {
        case web = "Web"
        case ios = "iOS"
        case android = "Android"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .web: return "globe"
            case .ios: return "iphone"
            case .android: return "candybarphone"
            }
        }
    }

    @Published var embeddedDockMode: EmbeddedDockMode = .ios
    @Published var lastDetectedDevServerPort: Int? = 3000
    @Published var targetWebURL: URL? = URL(string: "http://localhost:3000")
    @Published var webRefreshTrigger: Bool = false
    @Published var targetViewport: String = "responsive"
    @Published var showingEmbeddedDeviceDock = false
    @Published var showingEmbeddedAppleDock = false
    @Published var showingDeviceRuntimeSheet = false
    @Published var showingMobileDevTools = false

    /// Agent launch/deploy remains off until the owner enables it in Device & Run.
    @Published var allowAgentDeviceControl: Bool {
        didSet { UserDefaults.standard.set(allowAgentDeviceControl, forKey: Self.agentControlDefaultsKey) }
    }

    private static let agentControlDefaultsKey = "microcode.device-runtime.agent-control"
    /// Device boot (Android Emulator) and the app/dev-server are independent
    /// processes. Keeping them separate is essential: launching Flutter must
    /// never terminate the AVD that is rendering beside Chat.
    private var deviceRuntimeProcess: Process?
    private var applicationProcess: Process?
    private var applicationInputHandle: FileHandle?
    private var androidMirrorProcess: Process?
    private var androidMirrorReadHandle: FileHandle?
    private var androidPNGBuffer = Data()
    private var pendingAndroidFrame: Data?
    private var isDecodingAndroidFrame = false
    private var androidInputProcess: Process?
    private var androidInputHandle: FileHandle?
    private var androidInputSerial: String?
    private var lastAndroidScrollEvent = Date.distantPast

    private init() {
        allowAgentDeviceControl = UserDefaults.standard.bool(forKey: Self.agentControlDefaultsKey)
    }

    func refresh(workspace: URL?) async {
        // Device Preview is a local capability, not a property of the opened
        // project.  A user must be able to open an already-installed iOS
        // Simulator or Android AVD beside Chat while working in a non-GUI
        // repository (or before opening any repository at all).  Project
        // detection remains important for Build & Run, but must never hide
        // real devices from the Preview menu.
        let descriptor = workspace.map(GUIProjectDescriptor.detect(at:))
        project = descriptor
        isWorking = true
        defer { isWorking = false }
        var found: [RuntimeDevice] = []
        found += await listAppleSimulators()
        found += await listApplePhysicalDevices()
        found += await listAndroidDevices()
        if descriptor?.runtime.supportedPlatforms.contains(.macOS) == true {
            found.append(RuntimeDevice(id: "macos-host", name: "My Mac", platform: .macOS, state: "Available", runtime: "Local"))
        }
        if descriptor?.runtime == .xcode, let descriptor {
            buildSchemes = (try? await xcodeSchemes(descriptor)) ?? []
            if selectedScheme == nil || !buildSchemes.contains(selectedScheme ?? "") {
                selectedScheme = buildSchemes.first
            }
        } else {
            buildSchemes = []
            selectedScheme = nil
        }
        devices = found.sorted {
            let priority: (RuntimeDevice) -> Int = { device in
                if device.isAppleSimulator && device.isReadyForLaunch { return 0 }
                if device.isPhysicalAppleDevice && device.isReadyForLaunch { return 1 }
                if device.platform == .android && device.isReadyForLaunch { return 2 }
                if device.platform == .macOS { return 3 }
                return 4
            }
            return priority($0) == priority($1)
                ? ($0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending)
                : priority($0) < priority($1)
        }
        // A cross-platform project must not silently default to Android just
        // because its label sorts first alphabetically. Prefer a ready Apple
        // Simulator when one is installed; the chosen destination is then
        // retained until it disappears.
        if selectedDeviceID == nil || !devices.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = devices.first?.id
        }
        let runnable = devices.filter(\.isReadyForLaunch)
        statusMessage = devices.isEmpty
            ? "Install the required Xcode Simulator runtime or Android SDK/AVD, then refresh."
            : runnable.isEmpty
                ? "Runtime targets were found, but none pass the local launch preflight."
                : descriptor?.runtime == .unknown || descriptor == nil
                    ? "\(runnable.count) real runtime target\(runnable.count == 1 ? "" : "s") ready for Preview. Open a GUI app project to use Build & Run."
                    : "\(runnable.count) real runtime target\(runnable.count == 1 ? "" : "s") ready."
    }

    func startSelectedDevice() async {
        guard let device = selectedDevice else { statusMessage = "Choose a device first."; return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await startDevice(device)
        } catch {
            statusMessage = error.localizedDescription
            appendOutput(error.localizedDescription)
        }
    }

    /// Header shortcut for the Agent workspace. It deliberately starts the
    /// Android runtime without changing the chat layout; the separate preview
    /// button decides whether the in-app surface is visible.
    func startPreferredEmbeddedAndroid() async {
        // A header Preview click can occur before the asynchronous workspace
        // device discovery has completed. Refresh Android destinations here
        // rather than making that harmless timing race look like a failed
        // Preview action.
        if !devices.contains(where: { $0.platform == .android }) {
            let androidDevices = await listAndroidDevices()
            devices.removeAll { $0.platform == .android }
            devices.append(contentsOf: androidDevices)
            devices.sort { $0.platform.rawValue < $1.platform.rawValue || ($0.platform == $1.platform && $0.name < $1.name) }
            if selectedDeviceID == nil || !devices.contains(where: { $0.id == selectedDeviceID }) {
                selectedDeviceID = devices.first(where: { $0.platform == .android })?.id
            }
        }
        let preferred = selectedDevice?.platform == .android
            ? selectedDevice
            : devices.first(where: { $0.platform == .android })
        guard let device = preferred else {
            statusMessage = "No Android AVD or device was detected. Open Device & Run to refresh targets."
            return
        }
        selectedDeviceID = device.id
        await startEmbeddedAndroid()
    }

    /// Header shortcut for starting or attaching the preferred Apple Simulator
    func startPreferredEmbeddedAppleSimulator() async {
        if !devices.contains(where: { $0.isAppleSimulator }) {
            let simDevices = await listAppleSimulators()
            devices.removeAll { $0.isAppleSimulator }
            devices.append(contentsOf: simDevices)
        }
        let preferred = (selectedDevice?.isAppleSimulator == true ? selectedDevice : nil)
            ?? devices.first(where: { $0.isAppleSimulator && $0.isBooted })
            ?? devices.first(where: { $0.isAppleSimulator && $0.appleSimulatorFamily == .iPhone })
            ?? devices.first(where: { $0.isAppleSimulator })
        guard let device = preferred else {
            statusMessage = "No Apple Simulator was detected. Open Device & Run to refresh targets."
            return
        }
        selectedDeviceID = device.id
        showingEmbeddedAppleDock = true
        showingEmbeddedDeviceDock = true
        await startEmbeddedAppleSimulator()
    }

    /// Unified destination opener for both iOS Simulator and Android Emulator
    func openRuntimeDestination(_ device: RuntimeDevice) async {
        selectedDeviceID = device.id
        if device.platform == .android {
            AppleSimulatorCaptureService.shared.stop()
            showingEmbeddedDeviceDock = true
            showingEmbeddedAppleDock = false
            await startEmbeddedAndroid()
            return
        }
        if device.isAppleSimulator {
            stopEmbeddedAndroid()
            showingEmbeddedDeviceDock = true
            showingEmbeddedAppleDock = true
            await startEmbeddedAppleSimulator()
            return
        }
        await startSelectedDevice()
    }

    func runSelectedProject() async {
        guard let project, let device = selectedDevice else { statusMessage = "Choose a project and device first."; return }
        do {
            // Android's destination is the live surface beside Chat. A Build & Run
            // must therefore attach/launch that surface first rather than making
            // the user perform a separate Preview action.
            if device.platform == .android {
                await startEmbeddedAndroid()
                guard isEmbeddedAndroidActive else { return }
            } else if device.isAppleSimulator {
                // Build & Run and Preview share one destination: the genuine
                // Simulator window in the dock beside Chat.  Starting capture
                // first avoids a separate, confusing Simulator workflow.
                await startEmbeddedAppleSimulator()
            }
            try await run(project: project, on: device)
        } catch {
            statusMessage = error.localizedDescription
            appendOutput(error.localizedDescription)
        }
    }

    func stopActiveRuntime() {
        stopEmbeddedAndroid()
        NativeSimulatorBridgeService.shared.stop()
        AppleSimulatorCaptureService.shared.stop()
        Task { await ServeSimService.shared.stop() }
        if deviceRuntimeProcess?.isRunning == true { deviceRuntimeProcess?.terminate() }
        deviceRuntimeProcess = nil
        try? applicationInputHandle?.close()
        applicationInputHandle = nil
        if applicationProcess?.isRunning == true { applicationProcess?.terminate() }
        applicationProcess = nil
        statusMessage = "Stopped the MicroCode-launched runtime process."
    }

    /// Called during normal Quit and SIGTERM/SIGINT handling. The screen
    /// capture, persistent ADB shell and child emulator/dev-server processes
    /// are all explicitly reaped so they can never keep MicroCode alive.
    func shutdownAllRuntimes() {
        stopEmbeddedAndroid()
        NativeSimulatorBridgeService.shared.stop()
        AppleSimulatorCaptureService.shared.stop()
        Task { await ServeSimService.shared.stop() }
        if deviceRuntimeProcess?.isRunning == true { deviceRuntimeProcess?.terminate() }
        deviceRuntimeProcess = nil
        try? applicationInputHandle?.close()
        applicationInputHandle = nil
        if applicationProcess?.isRunning == true { applicationProcess?.terminate() }
        applicationProcess = nil
    }

    func executeForAgent(
        operation: String,
        workspacePath: String?,
        deviceID: String?,
        x: Int? = nil,
        y: Int? = nil,
        x2: Int? = nil,
        y2: Int? = nil,
        duration: Int? = nil,
        text: String? = nil,
        key: String? = nil,
        packageName: String? = nil,
        filePath: String? = nil,
        command: String? = nil
    ) async throws -> String {
        let safeOperation = operation.lowercased()
        let allowedOps = [
            "status", "list_devices", "start", "run", "stop",
            "tap", "swipe", "type_text", "key_event", "screenshot",
            "launch_app", "install_app", "adb_shell"
        ]
        guard allowedOps.contains(safeOperation) else {
            throw ToolBoxError.invalidParams("operation must be one of: \(allowedOps.joined(separator: ", "))")
        }
        
        await refresh(workspace: workspacePath.map(URL.init(fileURLWithPath:)))
        if let deviceID, devices.contains(where: { $0.id == deviceID }) {
            selectedDeviceID = deviceID
        }
        
        guard let targetDevice = selectedDevice ?? (deviceID.flatMap { id in devices.first(where: { $0.id == id }) } ?? devices.first) else {
            if safeOperation == "status" || safeOperation == "list_devices" {
                return summary()
            }
            throw ToolBoxError.executionFailed("No Android device or Apple Simulator detected. Connect an Android phone via USB/WiFi, or launch a simulator.")
        }
        
        switch safeOperation {
        case "status", "list_devices":
            return summary()
            
        case "start":
            selectedDeviceID = targetDevice.id
            await startSelectedDevice()
            return "\(statusMessage)\n\n\(output.suffix(4_000))"
            
        case "run":
            selectedDeviceID = targetDevice.id
            await runSelectedProject()
            return "\(statusMessage)\n\n\(output.suffix(4_000))"
            
        case "stop":
            stopActiveRuntime()
            return "Active runtime stopped successfully."
            
        case "tap":
            guard let x, let y else { throw ToolBoxError.invalidParams("tap requires 'x' and 'y' pixel coordinates") }
            return try await executeDeviceTap(device: targetDevice, x: x, y: y)
            
        case "swipe":
            guard let x, let y, let x2, let y2 else {
                throw ToolBoxError.invalidParams("swipe requires 'x', 'y', 'x2', and 'y2' pixel coordinates")
            }
            let dur = duration ?? 200
            return try await executeDeviceSwipe(device: targetDevice, x1: x, y1: y, x2: x2, y2: y2, durationMs: dur)
            
        case "type_text":
            guard let text, !text.isEmpty else { throw ToolBoxError.invalidParams("type_text requires 'text'") }
            return try await executeDeviceTypeText(device: targetDevice, text: text)
            
        case "key_event":
            guard let key, !key.isEmpty else { throw ToolBoxError.invalidParams("key_event requires 'key' (e.g. 3, 4, KEYCODE_HOME)") }
            return try await executeDeviceKeyEvent(device: targetDevice, key: key)
            
        case "screenshot":
            let destPath = filePath ?? "\(NSTemporaryDirectory())microcode_capture_\(Int(Date().timeIntervalSince1970)).png"
            return try await executeDeviceScreenshot(device: targetDevice, destinationPath: destPath)
            
        case "launch_app":
            guard let pkg = packageName ?? text, !pkg.isEmpty else {
                throw ToolBoxError.invalidParams("launch_app requires 'package_name' or bundle identifier")
            }
            return try await executeDeviceLaunchApp(device: targetDevice, identifier: pkg)
            
        case "install_app":
            guard let path = filePath ?? text, !path.isEmpty else {
                throw ToolBoxError.invalidParams("install_app requires 'file_path' to .apk or .app")
            }
            return try await executeDeviceInstallApp(device: targetDevice, packagePath: path)
            
        case "adb_shell":
            guard let cmd = command ?? text, !cmd.isEmpty else {
                throw ToolBoxError.invalidParams("adb_shell requires 'command'")
            }
            return try await executeAdbCommand(device: targetDevice, commandString: cmd)
            
        default:
            return summary()
        }
    }

    // MARK: - Direct Device Action Executions
    
    private func executeDeviceTap(device: RuntimeDevice, x: Int, y: Int) async throws -> String {
        switch device.platform {
        case .android:
            let serial = try await readyAndroidSerial(for: device)
            let adb = try androidTool("adb")
            _ = try await command(adb, ["-s", serial, "shell", "input", "tap", "\(x)", "\(y)"], directory: nil)
            return "✅ [Android] Sent tap at (\(x), \(y)) on device \(serial)"
            
        case .ios:
            return "⚠️ Direct pixel tap on iOS Simulator requires accessibility automation. Use UI test runner or simctl openurl/launch."
            
        case .macOS:
            return "macOS does not require simulated touch events."
        }
    }
    
    private func executeDeviceSwipe(device: RuntimeDevice, x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Int) async throws -> String {
        switch device.platform {
        case .android:
            let serial = try await readyAndroidSerial(for: device)
            let adb = try androidTool("adb")
            _ = try await command(adb, ["-s", serial, "shell", "input", "swipe", "\(x1)", "\(y1)", "\(x2)", "\(y2)", "\(durationMs)"], directory: nil)
            return "✅ [Android] Sent swipe from (\(x1), \(y1)) to (\(x2), \(y2)) in \(durationMs)ms on device \(serial)"
            
        case .ios:
            return "⚠️ Direct swipe on iOS Simulator requires accessibility automation."
            
        case .macOS:
            return "macOS does not require simulated swipe events."
        }
    }
    
    private func executeDeviceTypeText(device: RuntimeDevice, text: String) async throws -> String {
        switch device.platform {
        case .android:
            let serial = try await readyAndroidSerial(for: device)
            let adb = try androidTool("adb")
            let encoded = text.replacingOccurrences(of: " ", with: "%s").replacingOccurrences(of: "\n", with: "%s")
            _ = try await command(adb, ["-s", serial, "shell", "input", "text", encoded], directory: nil)
            return "✅ [Android] Typed text: '\(text)' on device \(serial)"
            
        case .ios:
            return "⚠️ Text input on iOS Simulator can be entered via pasteboard or accessibility commands."
            
        case .macOS:
            return "macOS does not require remote text input."
        }
    }
    
    private func executeDeviceKeyEvent(device: RuntimeDevice, key: String) async throws -> String {
        switch device.platform {
        case .android:
            let serial = try await readyAndroidSerial(for: device)
            let adb = try androidTool("adb")
            let resolvedKey: String
            switch key.uppercased() {
            case "HOME", "KEYCODE_HOME": resolvedKey = "3"
            case "BACK", "KEYCODE_BACK": resolvedKey = "4"
            case "ENTER", "KEYCODE_ENTER": resolvedKey = "66"
            case "POWER", "KEYCODE_POWER": resolvedKey = "26"
            case "VOLUP", "VOLUME_UP": resolvedKey = "24"
            case "VOLDOWN", "VOLUME_DOWN": resolvedKey = "25"
            case "RECENT", "RECENTS", "APP_SWITCH": resolvedKey = "187"
            default: resolvedKey = key
            }
            _ = try await command(adb, ["-s", serial, "shell", "input", "keyevent", resolvedKey], directory: nil)
            return "✅ [Android] Sent key event \(resolvedKey) to device \(serial)"
            
        case .ios:
            return "⚠️ Hardware keyevent on iOS Simulator requires simctl host shortcut."
            
        case .macOS:
            return "macOS does not require simulated keyevent."
        }
    }
    
    private func executeDeviceScreenshot(device: RuntimeDevice, destinationPath: String) async throws -> String {
        let destURL = URL(fileURLWithPath: destinationPath)
        try? FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        switch device.platform {
        case .android:
            let serial = try await readyAndroidSerial(for: device)
            let adb = try androidTool("adb")
            let data = try await commandData(adb, ["-s", serial, "exec-out", "screencap", "-p"], directory: nil)
            try data.write(to: destURL)
            return "📸 [Android] Screenshot saved to \(destinationPath) (\(data.count) bytes)"
            
        case .ios:
            if !device.isBooted {
                _ = try await command("/usr/bin/xcrun", ["simctl", "boot", device.id], directory: nil)
            }
            _ = try await command("/usr/bin/xcrun", ["simctl", "io", device.id, "screenshot", destinationPath], directory: nil)
            return "📸 [iOS] Screenshot saved to \(destinationPath)"
            
        case .macOS:
            _ = try await command("/usr/sbin/screencapture", ["-x", destinationPath], directory: nil)
            return "📸 [macOS] Screen capture saved to \(destinationPath)"
        }
    }
    
    private func executeDeviceLaunchApp(device: RuntimeDevice, identifier: String) async throws -> String {
        switch device.platform {
        case .android:
            let serial = try await readyAndroidSerial(for: device)
            let adb = try androidTool("adb")
            let res = try await command(adb, ["-s", serial, "shell", "monkey", "-p", identifier, "-c", "android.intent.category.LAUNCHER", "1"], directory: nil)
            return "🚀 [Android] Launched package \(identifier) on \(serial):\n\(res.output)"
            
        case .ios:
            if !device.isBooted {
                _ = try await command("/usr/bin/xcrun", ["simctl", "boot", device.id], directory: nil)
                _ = try await command("/usr/bin/xcrun", ["simctl", "bootstatus", device.id, "-b"], directory: nil)
            }
            let res = try await command("/usr/bin/xcrun", ["simctl", "launch", device.id, identifier], directory: nil)
            return "🚀 [iOS] Launched bundle \(identifier) on \(device.name):\n\(res.output)"
            
        case .macOS:
            _ = try await command("/usr/bin/open", ["-a", identifier], directory: nil)
            return "🚀 [macOS] Opened \(identifier)"
        }
    }
    
    private func executeDeviceInstallApp(device: RuntimeDevice, packagePath: String) async throws -> String {
        guard FileManager.default.fileExists(atPath: packagePath) else {
            throw ToolBoxError.executionFailed("File not found at path: \(packagePath)")
        }
        switch device.platform {
        case .android:
            let serial = try await readyAndroidSerial(for: device)
            let adb = try androidTool("adb")
            let res = try await command(adb, ["-s", serial, "install", "-r", "-t", packagePath], directory: nil)
            return "📦 [Android] Installed APK \(packagePath) on \(serial):\n\(res.output)"
            
        case .ios:
            if !device.isBooted {
                _ = try await command("/usr/bin/xcrun", ["simctl", "boot", device.id], directory: nil)
            }
            let res = try await command("/usr/bin/xcrun", ["simctl", "install", device.id, packagePath], directory: nil)
            return "📦 [iOS] Installed app bundle \(packagePath) on \(device.name):\n\(res.output)"
            
        case .macOS:
            return "⚠️ Install app is supported for Android APKs and iOS Simulator bundles."
        }
    }
    
    private func executeAdbCommand(device: RuntimeDevice, commandString: String) async throws -> String {
        guard device.platform == .android else {
            throw ToolBoxError.executionFailed("adb_shell is only available for Android devices/emulators.")
        }
        let serial = try await readyAndroidSerial(for: device)
        let adb = try androidTool("adb")
        let res = try await command(adb, ["-s", serial, "shell", commandString], directory: nil)
        return "📟 [ADB Output - \(serial)]:\n\(res.output)"
    }

    var selectedDevice: RuntimeDevice? { devices.first(where: { $0.id == selectedDeviceID }) }
    var selectedApplePreviewTitle: String { selectedDevice?.previewTitle ?? "Apple Simulator" }
    var selectedApplePreviewSymbolName: String { selectedDevice?.displaySymbolName ?? "iphone" }

    /// Attaches MicroCode's native device surface to a genuine Android device.
    /// ADB is the documented, authenticated control channel; no process or RAM
    /// inspection is used.
    func startEmbeddedAndroid() async {
        await MainActor.run {
            self.embeddedDockMode = .android
            self.showingEmbeddedAppleDock = false
            self.showingEmbeddedDeviceDock = true
            PreviewDockService.shared.selectTab(id: "android")
            if self.embeddedAndroidFrame == nil {
                self.embeddedAndroidFrame = DeviceFrameAssets.loadAndroidPixelProBezel()
                self.embeddedAndroidMask = DeviceFrameAssets.loadAndroidPixelProMask()
            }
        }
        
        // Ensure an Android device is selected; auto-pick booted or available Android device
        var targetDevice = selectedDevice
        if targetDevice?.platform != .android {
            targetDevice = devices.first(where: { $0.platform == .android && $0.state == "Running" })
                ?? devices.first(where: { $0.platform == .android })
            if let targetDevice {
                selectedDeviceID = targetDevice.id
            }
        }
        
        guard let device = targetDevice, device.platform == .android else {
            let fresh = await listAndroidDevices()
            if let first = fresh.first {
                devices.removeAll { $0.platform == .android }
                devices.append(contentsOf: fresh)
                selectedDeviceID = first.id
                await startEmbeddedAndroid()
                return
            }
            statusMessage = "Choose an Android device or AVD first."
            embeddedAndroidStatus = "No Android device or emulator detected. Make sure the emulator is running."
            return
        }
        
        isWorking = true
        defer { isWorking = false }
        do {
            // 1. If device ID is an active serial (e.g. "emulator-5554" or USB physical device)
            if !device.id.hasPrefix("avd:") {
                startAndroidMirror(serial: device.id, deviceName: device.name)
                statusMessage = "Attached to Android device: \(device.name)."
                return
            }
            
            let avdName = String(device.id.dropFirst(4))
            
            // 2. Reattaching to an already booted AVD is immediate
            if let serial = await attachedAndroidSerial(named: avdName) {
                startAndroidMirror(serial: serial, deviceName: device.name)
                statusMessage = "Attached to running Android Emulator: \(device.name)."
                return
            }
            
            // 3. Fast fallback: if ANY emulator-* is currently active in ADB, attach to it immediately!
            if let firstRunning = await firstAttachedEmulatorSerial() {
                startAndroidMirror(serial: firstRunning, deviceName: device.name)
                statusMessage = "Attached to running Android Emulator (\(firstRunning)): \(device.name)."
                return
            }
            
            try await startDevice(device)
            let serial = try await readyAndroidSerial(for: device)
            startAndroidMirror(serial: serial, deviceName: device.name)
            statusMessage = "Android Emulator is running inside MicroCode: \(device.name)."
        } catch {
            statusMessage = error.localizedDescription
            embeddedAndroidStatus = "Could not start emulator: \(error.localizedDescription)"
            appendOutput(error.localizedDescription)
        }
    }

    var isEmbeddedApplePreviewActive: Bool { ServeSimService.shared.isActive }

    /// serve-sim is the interactive default: it supplies the device frame,
    /// keyboard, gestures, and hardware controls in one local WebView. The
    /// raw IOSurface transport remains available for diagnostics only.
    func startEmbeddedAppleSimulator() async {
        await MainActor.run {
            self.embeddedDockMode = .ios
            self.showingEmbeddedAppleDock = true
            self.showingEmbeddedDeviceDock = true
            PreviewDockService.shared.selectTab(id: "ios")
        }
        guard let device = selectedDevice, device.isAppleSimulator else {
            statusMessage = "Choose an Apple Simulator first."
            return
        }
        // A warm preview must be an attach, not another boot + stream spawn.
        // This is the normal path after the first click and is effectively
        // immediate while preserving the existing iPhone/iPad frame.
        if ServeSimService.shared.isShowing(simulatorID: device.id) {
            statusMessage = "Interactive \(device.previewTitle) is already ready beside Chat: \(device.name)."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await startDevice(device)
            NativeSimulatorBridgeService.shared.stop()
            AppleSimulatorCaptureService.shared.stop()
            await ServeSimService.shared.start(simulatorID: device.id, simulatorName: device.name)
            if ServeSimService.shared.isActive {
                statusMessage = "Interactive \(device.previewTitle) is ready beside Chat: \(device.name)."
            } else {
                statusMessage = ServeSimService.shared.statusMessage
                appendOutput(statusMessage)
            }
        } catch {
            statusMessage = error.localizedDescription
            appendOutput(error.localizedDescription)
        }
    }

    func hotReloadCurrentProject() {
        guard project?.runtime == .flutter else {
            statusMessage = "Hot Reload is available for the active Flutter run only."
            return
        }
        guard applicationProcess?.isRunning == true, let input = applicationInputHandle else {
            statusMessage = "Start Flutter with Build & Run first, then use Hot Reload."
            return
        }
        input.write(Data("r\n".utf8))
        statusMessage = "Sent Flutter Hot Reload to the active runtime."
    }

    func stopEmbeddedAndroid() {
        stopAndroidMirrorTransport()
        stopAndroidInputChannel()
        embeddedAndroidImage = nil
        embeddedAndroidFrame = nil
        embeddedAndroidMask = nil
        embeddedAndroidPixelSize = .zero
        embeddedAndroidSerial = nil
        isEmbeddedAndroidActive = false
        embeddedAndroidStatus = ""
    }

    func sendEmbeddedAndroidTap(normalizedX: CGFloat, normalizedY: CGFloat) {
        guard let serial = embeddedAndroidSerial, embeddedAndroidPixelSize.width > 0, embeddedAndroidPixelSize.height > 0 else { return }
        let x = max(0, min(Int(embeddedAndroidPixelSize.width * normalizedX), Int(embeddedAndroidPixelSize.width - 1)))
        let y = max(0, min(Int(embeddedAndroidPixelSize.height * normalizedY), Int(embeddedAndroidPixelSize.height - 1)))
        sendAndroidInput(serial: serial, arguments: ["shell", "input", "tap", "\(x)", "\(y)"])
    }

    /// Sends a genuine touch swipe to the attached AVD/device.  Keeping this
    /// in normalized screen coordinates lets the native preview resize freely
    /// while the ADB input still lands on the correct real-device pixels.
    func sendEmbeddedAndroidSwipe(
        from start: CGPoint,
        to end: CGPoint,
        durationMilliseconds: Int = 110
    ) {
        guard let serial = embeddedAndroidSerial, embeddedAndroidPixelSize.width > 0, embeddedAndroidPixelSize.height > 0 else { return }
        let width = max(Int(embeddedAndroidPixelSize.width - 1), 1)
        let height = max(Int(embeddedAndroidPixelSize.height - 1), 1)
        func pixelPoint(_ point: CGPoint) -> (Int, Int) {
            (
                max(0, min(Int(point.x * CGFloat(width)), width)),
                max(0, min(Int(point.y * CGFloat(height)), height))
            )
        }
        let (startX, startY) = pixelPoint(start)
        let (endX, endY) = pixelPoint(end)
        sendAndroidInput(
            serial: serial,
            arguments: ["shell", "input", "swipe", "\(startX)", "\(startY)", "\(endX)", "\(endY)", "\(max(durationMilliseconds, 80))"]
        )
    }

    func sendEmbeddedAndroidKey(_ key: String) {
        guard let serial = embeddedAndroidSerial else { return }
        sendAndroidInput(serial: serial, arguments: ["shell", "input", "keyevent", key])
    }

    func sendEmbeddedAndroidText(_ text: String) {
        guard let serial = embeddedAndroidSerial else { return }
        // `input text` accepts %s for a literal space. The persistent ADB
        // shell quotes every argument below, so this can safely accept real
        // Mac keyboard input instead of silently dropping punctuation.
        let encoded = text
            .replacingOccurrences(of: " ", with: "%s")
            .replacingOccurrences(of: "\n", with: "%s")
        guard !encoded.isEmpty else { return }
        sendAndroidInput(serial: serial, arguments: ["shell", "input", "text", encoded])
    }

    /// Wheel/trackpad events are coalesced before crossing ADB. The old
    /// gesture waited for a drag to end, which is why scrolling felt delayed.
    func sendEmbeddedAndroidScroll(deltaY: CGFloat) {
        guard let serial = embeddedAndroidSerial,
              embeddedAndroidPixelSize.width > 0,
              embeddedAndroidPixelSize.height > 0,
              abs(deltaY) > 0.1 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAndroidScrollEvent) >= 0.045 else { return }
        lastAndroidScrollEvent = now
        let x = Int(embeddedAndroidPixelSize.width / 2)
        let centerY = Int(embeddedAndroidPixelSize.height / 2)
        // Android scrolling is a finger swipe. A positive macOS delta means
        // moving content down, therefore the virtual finger travels down too.
        let distance = max(-560, min(560, Int(deltaY * 9)))
        guard abs(distance) > 3 else { return }
        let startY = max(40, min(centerY - distance / 2, Int(embeddedAndroidPixelSize.height) - 40))
        let endY = max(40, min(centerY + distance / 2, Int(embeddedAndroidPixelSize.height) - 40))
        sendAndroidInput(serial: serial, arguments: ["shell", "input", "swipe", "\(x)", "\(startY)", "\(x)", "\(endY)", "45"])
    }

    private func startAndroidMirror(serial: String, deviceName: String) {
        stopAndroidMirrorTransport()
        stopAndroidInputChannel()
        embeddedAndroidSerial = serial
        isEmbeddedAndroidActive = true
        embeddedAndroidStatus = "Connecting to \(deviceName)…"
        
        // Load authentic Android hardware frame & mask immediately so the device is NEVER frame-less
        let initialSkin = resolveOfficialAndroidSkin(forAVDNamed: deviceName)
        embeddedAndroidFrame = initialSkin.frame ?? DeviceFrameAssets.loadAndroidPixelProBezel()
        embeddedAndroidMask = initialSkin.mask ?? DeviceFrameAssets.loadAndroidPixelProMask()
        
        Task { [weak self] in
            guard let self, let avdName = await androidAVDName(serial: serial),
                  embeddedAndroidSerial == serial else { return }
            let resolvedSkin = resolveOfficialAndroidSkin(forAVDNamed: avdName)
            if let frame = resolvedSkin.frame {
                await MainActor.run {
                    self.embeddedAndroidFrame = frame
                    self.embeddedAndroidMask = resolvedSkin.mask ?? DeviceFrameAssets.loadAndroidPixelProMask()
                    self.embeddedAndroidStatus = "Live · official \(avdName) frame"
                }
            }
        }
        startAndroidInputChannel(serial: serial)
        do {
            let adb = try androidTool("adb")
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: adb)
            // ADB screencap is a CPU PNG path, not the emulator's GPU display
            // transport. Uncapped capture was starving the UI and making the
            // AVD appear slow. Keep only the latest frame at a responsive
            // preview cadence; the GPU/WebRTC transport can replace this
            // compatibility path without changing the view or input API.
            process.arguments = ["-s", serial, "exec-out", "sh", "-c", "while true; do screencap -p; sleep 0.08; done"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            androidMirrorProcess = process
            let readHandle = output.fileHandleForReading
            androidMirrorReadHandle = readHandle
            readHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                Task { @MainActor [weak self] in
                    self?.consumeAndroidMirrorBytes(data)
                }
            }
            process.terminationHandler = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.androidMirrorProcess === process else { return }
                    self.androidMirrorReadHandle?.readabilityHandler = nil
                    self.androidMirrorReadHandle = nil
                    self.androidMirrorProcess = nil
                    // Keep the dock open with a useful state. A temporary
                    // capture transport failure must never make Preview
                    // disappear after the user has clicked it.
                    self.embeddedAndroidStatus = "Display stream stopped — click Preview to retry."
                }
            }
        } catch {
            embeddedAndroidStatus = "Could not start the Android display stream: \(error.localizedDescription)"
        }
    }

    private func sendAndroidInput(serial: String, arguments: [String]) {
        if serial == androidInputSerial,
           androidInputProcess?.isRunning == true,
           let handle = androidInputHandle,
           arguments.first == "shell" {
            // Quote each value before it enters the persistent authenticated
            // ADB shell. This keeps keyboard text safe while preserving the
            // no-process-launch fast path for taps, keys and trackpad scroll.
            let command = arguments.dropFirst().map(Self.shellQuote).joined(separator: " ") + "\n"
            handle.write(Data(command.utf8))
            return
        }
        Task { [weak self] in
            guard let self, let adb = try? self.androidTool("adb") else { return }
            _ = try? await self.command(adb, ["-s", serial] + arguments, directory: nil)
        }
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static let pngEndMarker = Data([0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])

    private func consumeAndroidMirrorBytes(_ data: Data) {
        androidPNGBuffer.append(data)
        while let end = androidPNGBuffer.range(of: Self.pngEndMarker) {
            let endIndex = end.upperBound
            let rawFrame = androidPNGBuffer.prefix(upTo: endIndex)
            androidPNGBuffer.removeSubrange(..<endIndex)
            guard let start = rawFrame.range(of: Self.pngSignature) else { continue }
            enqueueAndroidFrame(Data(rawFrame[start.lowerBound..<rawFrame.endIndex]))
        }
        // A bad/incomplete stream must never grow the IDE's RAM indefinitely.
        if androidPNGBuffer.count > 16 * 1_024 * 1_024 {
            androidPNGBuffer.removeAll(keepingCapacity: true)
        }
    }

    private func enqueueAndroidFrame(_ data: Data) {
        pendingAndroidFrame = data
        decodeNextAndroidFrameIfNeeded()
    }

    private func decodeNextAndroidFrameIfNeeded() {
        guard !isDecodingAndroidFrame, let data = pendingAndroidFrame else { return }
        pendingAndroidFrame = nil
        isDecodingAndroidFrame = true
        Task { [weak self] in
            let capture = await Task.detached(priority: .userInitiated) {
                Self.makeAndroidPreview(from: data)
            }.value
            guard let self else { return }
            isDecodingAndroidFrame = false
            if let capture {
                embeddedAndroidImage = capture.image
                embeddedAndroidPixelSize = capture.sourceSize
                embeddedAndroidStatus = "Live · \(Int(capture.sourceSize.width)) × \(Int(capture.sourceSize.height))"
            }
            decodeNextAndroidFrameIfNeeded()
        }
    }

    private func stopAndroidMirrorTransport() {
        androidMirrorReadHandle?.readabilityHandler = nil
        androidMirrorReadHandle?.closeFile()
        androidMirrorReadHandle = nil
        if androidMirrorProcess?.isRunning == true { androidMirrorProcess?.terminate() }
        androidMirrorProcess = nil
        androidPNGBuffer.removeAll(keepingCapacity: false)
        pendingAndroidFrame = nil
        isDecodingAndroidFrame = false
    }

    private func startAndroidInputChannel(serial: String) {
        guard androidInputSerial != serial || androidInputProcess?.isRunning != true else { return }
        stopAndroidInputChannel()
        guard let adb = try? androidTool("adb") else { return }
        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = ["-s", serial, "shell"]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            androidInputProcess = process
            androidInputHandle = input.fileHandleForWriting
            androidInputSerial = serial
        } catch {
            appendOutput("Android input channel unavailable: \(error.localizedDescription)")
        }
    }

    private func stopAndroidInputChannel() {
        try? androidInputHandle?.close()
        androidInputHandle = nil
        if androidInputProcess?.isRunning == true { androidInputProcess?.terminate() }
        androidInputProcess = nil
        androidInputSerial = nil
    }

    private nonisolated static func makeAndroidPreview(from data: Data) -> (image: NSImage, sourceSize: CGSize)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0 else { return nil }

        // The dock is only a few hundred points wide. 960 px keeps text sharp
        // while materially reducing ImageIO decode work during a fast scroll.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 960,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return (NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)), CGSize(width: width, height: height))
    }

    /// Starts the real platform runtime. Errors propagate to Build & Run so a
    /// failed boot can never be mistaken for a successful deployment.
    private func startDevice(_ device: RuntimeDevice) async throws {
        guard device.isReadyForLaunch else {
            throw ToolBoxError.executionFailed(device.preflightMessage ?? "This device did not pass its launch preflight.")
        }
        switch device.platform {
        case .ios:
            if device.isPhysicalAppleDevice {
                statusMessage = "Physical Apple device is paired and ready: \(device.name)."
                return
            }
            if !device.isBooted {
                _ = try await command("/usr/bin/xcrun", ["simctl", "boot", device.id], directory: nil)
            }
            // `boot` only starts CoreSimulator.  Wait for SpringBoard before
            // handing the destination to xcodebuild/install/launch.
            _ = try await command("/usr/bin/xcrun", ["simctl", "bootstatus", device.id, "-b"], directory: nil)
            statusMessage = "\(device.previewTitle) is ready: \(device.name)."
        case .android:
            if device.id.hasPrefix("avd:") {
                let avdName = String(device.id.dropFirst(4))
                if let _ = await attachedAndroidSerial(named: avdName) {
                    statusMessage = "Android Emulator is already running: \(device.name)."
                    return
                }
                let emulator = try androidTool("emulator")
                if deviceRuntimeProcess?.isRunning != true {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: emulator)
                    // Keep the emulator's own Qt window hidden: MicroCode owns
                    // the visible device frame and talks to the real AVD over
                    // the supported ADB transport.
                    // Preserve Quick Boot snapshots and skip the boot animation.
                    // This makes a warm AVD attach immediately and keeps a cold
                    // start as short as the Android runtime permits.
                    // Use hardware GPU plus a real multi-core guest. Warm
                    // Quick Boot remains enabled; a stopped AVD still has an
                    // unavoidable cold-boot phase, but it no longer blocks
                    // opening the Preview dock.
                    process.arguments = ["-avd", avdName, "-no-window", "-no-audio", "-no-boot-anim", "-no-metrics", "-crash-report-mode", "disabled", "-gpu", "host", "-cores", "4", "-netdelay", "none", "-netspeed", "full"]
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    deviceRuntimeProcess = process
                    // The Emulator validates AVD disk allocation immediately.
                    // Detect an early exit here rather than making the user wait
                    // through the full ADB readiness timeout with no diagnosis.
                    try await Task.sleep(nanoseconds: 800_000_000)
                    guard process.isRunning else {
                        deviceRuntimeProcess = nil
                        throw ToolBoxError.executionFailed("Android Emulator stopped before startup. Check free disk space for this AVD, or create/move the AVD to your configured external SSD location.")
                    }
                }
                statusMessage = "Starting Android Emulator: \(device.name). Build & Run will wait until ADB reports it ready."
            } else {
                statusMessage = "\(device.name) is ready through ADB."
            }
        case .macOS:
            statusMessage = "My Mac is ready."
        }
    }

    private func run(project: GUIProjectDescriptor, on device: RuntimeDevice) async throws {
        isWorking = true; defer { isWorking = false }
        if !device.isBooted && device.platform != .macOS { try await startDevice(device) }
        var readyDevice = device
        if device.platform == .android {
            let serial = try await readyAndroidSerial(for: device)
            readyDevice = RuntimeDevice(id: serial, name: device.name, platform: .android, state: "Device", runtime: "ADB")
        }
        switch project.runtime {
        case .xcode: try await runXcode(project, device: readyDevice)
        case .android: try await runAndroid(project, device: readyDevice)
        case .flutter: try await runFlutter(project, device: readyDevice)
        case .reactNative, .expo: try await runReactNative(project, device: readyDevice)
        case .unknown: throw ToolBoxError.executionFailed("No supported GUI runtime detected.")
        }
    }

    private func runXcode(_ project: GUIProjectDescriptor, device: RuntimeDevice) async throws {
        guard let container = project.xcodeContainer else { throw ToolBoxError.executionFailed("No Xcode project or workspace found.") }
        let scheme = try await xcodeScheme(project)
        var base = container.pathExtension == "xcworkspace" ? ["-workspace", container.path] : ["-project", container.path]
        base += ["-scheme", scheme]
        if device.platform == .ios { base += ["-destination", "id=\(device.id)"] }
        if device.platform == .macOS { base += ["-destination", "platform=macOS"] }
        base += ["build"]
        let result = try await command("/usr/bin/xcodebuild", base, directory: project.root)
        appendOutput(result.output)
        let settings = try await xcodeBuildSettings(project, scheme: scheme, device: device)
        guard let targetDir = settings["TARGET_BUILD_DIR"], let wrapper = settings["WRAPPER_NAME"] else {
            throw ToolBoxError.executionFailed("Xcode built successfully but MicroCode could not determine the app bundle path.")
        }
        let appURL = URL(fileURLWithPath: targetDir).appendingPathComponent(wrapper)
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw ToolBoxError.executionFailed("Xcode built successfully but app bundle was not found at \(appURL.path).")
        }
        if device.platform == .ios {
            guard let bundleID = settings["PRODUCT_BUNDLE_IDENTIFIER"], !bundleID.isEmpty else {
                throw ToolBoxError.executionFailed("The Xcode target has no PRODUCT_BUNDLE_IDENTIFIER.")
            }
            let launched: CommandResult
            if device.isPhysicalAppleDevice {
                let installed = try await command("/usr/bin/xcrun", ["devicectl", "device", "install", "app", "--device", device.id, appURL.path], directory: project.root)
                appendOutput(installed.output)
                launched = try await command("/usr/bin/xcrun", ["devicectl", "device", "process", "launch", "--device", device.id, "--terminate-existing", bundleID], directory: project.root)
            } else {
                _ = try await command("/usr/bin/xcrun", ["simctl", "install", device.id, appURL.path], directory: project.root)
                launched = try await command("/usr/bin/xcrun", ["simctl", "launch", device.id, bundleID], directory: project.root)
            }
            appendOutput(launched.output)
            statusMessage = "Installed and launched \(scheme) on \(device.isPhysicalAppleDevice ? "physical device" : device.previewTitle): \(device.name)."
        } else {
            _ = try await command("/usr/bin/open", [appURL.path], directory: project.root)
            statusMessage = "Launched \(scheme) on My Mac."
        }
    }

    private func runAndroid(_ project: GUIProjectDescriptor, device: RuntimeDevice) async throws {
        guard device.platform == .android else { throw ToolBoxError.executionFailed("Choose an Android target for this project.") }
        let serial = try await readyAndroidSerial(for: device)
        let gradle = FileManager.default.fileExists(atPath: project.root.appendingPathComponent("gradlew").path) ? "./gradlew" : "gradle"
        let result = try await command(gradle, ["installDebug"], directory: project.root)
        appendOutput(result.output)
        guard let applicationID = androidApplicationID(project.root) else {
            statusMessage = "Installed debug build on \(device.name). Add an applicationId to launch it automatically."
            return
        }
        let adb = try androidTool("adb")
        let launched = try await command(adb, ["-s", serial, "shell", "monkey", "-p", applicationID, "1"], directory: project.root)
        appendOutput(launched.output)
        statusMessage = "Installed and launched \(applicationID) on \(device.name)."
    }

    private func runFlutter(_ project: GUIProjectDescriptor, device: RuntimeDevice) async throws {
        guard device.platform != .macOS else { throw ToolBoxError.executionFailed("Choose an iOS or Android target for Flutter.") }
        try requireMobileAppleSimulator(device, technology: "Flutter")
        try launchLongRunning("/usr/bin/env", ["flutter", "run", "-d", device.id], directory: project.root)
        statusMessage = "Flutter is running on \(device.name)."
    }

    private func runReactNative(_ project: GUIProjectDescriptor, device: RuntimeDevice) async throws {
        let isExpo = project.runtime == .expo
        try requireMobileAppleSimulator(device, technology: isExpo ? "Expo" : "React Native")
        let args: [String]
        switch device.platform {
        case .ios:
            args = isExpo ? ["npx", "expo", "run:ios", "--device", device.name] : ["npx", "react-native", "run-ios", "--udid", device.id]
        case .android:
            args = isExpo ? ["npx", "expo", "run:android", "--device", device.id] : ["npx", "react-native", "run-android", "--deviceId", device.id]
        case .macOS:
            throw ToolBoxError.executionFailed("React Native requires an iOS or Android target.")
        }
        try launchLongRunning("/usr/bin/env", args, directory: project.root)
        statusMessage = "\(isExpo ? "Expo" : "React Native") is running on \(device.name)."
    }

    private func requireMobileAppleSimulator(_ device: RuntimeDevice, technology: String) throws {
        guard let family = device.appleSimulatorFamily, !family.isMobile else { return }
        throw ToolBoxError.executionFailed("\(technology) can run on iPhone and iPad simulators. \(family.previewTitle) remains available for interactive Preview; build a native Xcode target to deploy to it.")
    }

    private func listAppleSimulators() async -> [RuntimeDevice] {
        struct Response: Decodable { let devices: [String: [Device]] }
        struct Device: Decodable { let name: String; let udid: String; let state: String; let isAvailable: Bool? }
        guard let result = try? await command("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "-j"], directory: nil),
              let response = try? JSONDecoder().decode(Response.self, from: Data(result.output.utf8)) else { return [] }
        return response.devices.flatMap { runtime, list in
            list.filter { $0.isAvailable ?? true }.map {
                RuntimeDevice(
                    id: $0.udid,
                    name: $0.name,
                    platform: .ios,
                    state: $0.state,
                    runtime: runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: ""),
                    kind: .simulator
                )
            }
        }
    }

    /// Uses the active Xcode's CoreDevice inventory rather than an old
    /// `instruments` parser. The JSON schema is versioned by Apple and lists
    /// both USB and paired wireless iPhone/iPad destinations.
    private func listApplePhysicalDevices() async -> [RuntimeDevice] {
        guard let result = try? await command(
            "/usr/bin/xcrun",
            ["devicectl", "list", "devices", "--json-output", "-", "--omit-deprecated-fields-in-json", "--timeout", "5"],
            directory: nil
        ), let root = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any],
           let payload = root["result"] as? [String: Any],
           let rawDevices = payload["devices"] as? [[String: Any]] else { return [] }

        return rawDevices.compactMap { raw in
            guard let properties = raw["properties"] as? [String: Any],
                  let hardware = properties["hardware"] as? [String: Any],
                  let reality = hardware["reality"] as? String,
                  reality.caseInsensitiveCompare("physical") == .orderedSame,
                  let platform = hardware["platform"] as? String,
                  platform.lowercased().contains("ios"),
                  let identifier = hardware["udid"] as? String ?? raw["identifier"] as? String else { return nil }

            let stateProperties = properties["state"] as? [String: Any]
            let connection = properties["connection"] as? [String: Any]
            let name = (stateProperties?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (hardware["marketingName"] as? String)
                ?? "Apple device"
            let connectionState = (connection?["state"] as? String) ?? "Unavailable"
            let connected = connectionState.caseInsensitiveCompare("connected") == .orderedSame
            let model = (hardware["marketingName"] as? String) ?? (hardware["productType"] as? String) ?? "iPhone/iPad"
            let preflight = connected ? nil : "Connect/unlock this device by USB or pair it in Xcode Device Hub; enable Developer Mode before Build & Run."
            return RuntimeDevice(
                id: identifier,
                name: name,
                platform: .ios,
                state: connected ? "Connected" : connectionState.capitalized,
                runtime: "Physical · \(model)",
                isReadyForLaunch: connected,
                preflightMessage: preflight,
                kind: .physical
            )
        }
    }

    private func listAndroidDevices() async -> [RuntimeDevice] {
        var result: [RuntimeDevice] = []
        if let emulator = try? androidTool("emulator"), let avds = try? await command(emulator, ["-list-avds"], directory: nil) {
            result += avds.output.split(whereSeparator: \.isNewline).map { rawName in
                let name = String(rawName)
                let preflight = androidAVDPreflight(named: name)
                return RuntimeDevice(
                    id: "avd:\(name)",
                    name: name,
                    platform: .android,
                    state: preflight.isReady ? "Stopped" : "Needs space",
                    runtime: preflight.runtimeDetail,
                    isReadyForLaunch: preflight.isReady,
                    preflightMessage: preflight.message
                )
            }
        }
        if let adb = try? androidTool("adb"), let attached = try? await command(adb, ["devices", "-l"], directory: nil) {
            for line in attached.output.split(whereSeparator: \.isNewline).dropFirst() {
                let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                guard let id = fields.first, fields.dropFirst().contains("device") else { continue }
                let serial = String(id)
                // An AVD is simultaneously listed by the emulator binary and
                // by ADB. Treat those as one destination, never as a generic
                // `emulator-5554` device plus a second stopped AVD. Besides
                // avoiding a confusing duplicate, this retains the AVD's
                // exact disk image, Quick Boot snapshot and official skin.
                if serial.hasPrefix("emulator-"),
                   let avdName = await androidAVDName(serial: serial),
                   let index = result.firstIndex(where: { $0.id == "avd:\(avdName)" }) {
                    let configured = result[index]
                    result[index] = RuntimeDevice(
                        id: configured.id,
                        name: configured.name,
                        platform: .android,
                        state: "Running",
                        runtime: configured.runtime,
                        isReadyForLaunch: true,
                        preflightMessage: nil
                    )
                } else {
                    result.removeAll { $0.id == serial }
                    result.append(RuntimeDevice(id: serial, name: serial, platform: .android, state: "Running", runtime: "ADB", isReadyForLaunch: true, preflightMessage: nil))
                }
            }
        }
        return result
    }

    /// Reads the AVD's own config before any emulator process is launched.
    /// This makes a low-space AVD visibly unavailable rather than presenting a
    /// Start button that is guaranteed to fail.
    private func androidAVDPreflight(named name: String) -> (isReady: Bool, runtimeDetail: String, message: String?) {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        let roots = [env["ANDROID_AVD_HOME"], NSHomeDirectory() + "/.android/avd"].compactMap { $0 }
        let avdPath: String? = roots.lazy.compactMap { root in
            let metadata = URL(fileURLWithPath: root).appendingPathComponent("\(name).ini")
            if let text = try? String(contentsOf: metadata, encoding: .utf8),
               let path = self.iniValue("path", in: text) {
                return path
            }
            let fallback = URL(fileURLWithPath: root).appendingPathComponent("\(name).avd").path
            return fm.fileExists(atPath: fallback) ? fallback : nil
        }.first

        guard let avdPath, fm.fileExists(atPath: avdPath) else {
            return (false, "AVD configuration unavailable", "MicroCode could not locate the storage directory for Android AVD ‘\(name)’. Refresh Android Studio Device Manager, then refresh MicroCode.")
        }
        let configURL = URL(fileURLWithPath: avdPath).appendingPathComponent("config.ini")
        let config = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let configuredBytes = storageSize(in: config, key: "disk.dataPartition.size") ?? 2 * 1_024 * 1_024 * 1_024
        let reserve: UInt64 = 512 * 1_024 * 1_024
        let required = configuredBytes + reserve
        let available = ((try? fm.attributesOfFileSystem(forPath: avdPath))?[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let freeText = formatter.string(fromByteCount: Int64(available))
        let dataText = formatter.string(fromByteCount: Int64(configuredBytes))
        let neededText = formatter.string(fromByteCount: Int64(required))
        let detail = "AVD · \(freeText) free"
        guard available >= required else {
            return (
                false,
                detail,
                "Android AVD ‘\(name)’ is stored at \(avdPath). Its data partition is \(dataText); MicroCode requires at least \(neededText) free on that volume, but only \(freeText) is available. Free space or move/create this AVD on a volume with sufficient capacity."
            )
        }
        return (true, detail, nil)
    }

    /// Resolves the exact skin selected in this AVD's `config.ini` or matches the AVD model to installed SDK skins.
    /// Android Studio ships `back.webp` as the official device chassis and `mask.webp` as the camera punch-hole cutout;
    /// using them preserves manufacturer proportions, camera treatment and buttons.
    /// If no custom skin is located, it ALWAYS falls back to the authentic Pixel 9 Pro hardware frame from DeviceFrameAssets.
    func resolveOfficialAndroidSkin(forAVDNamed name: String) -> (frame: NSImage?, mask: NSImage?) {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        let roots = [
            env["ANDROID_AVD_HOME"],
            NSHomeDirectory() + "/.android/avd",
            NSHomeDirectory() + "/Library/Android/sdk/avd"
        ].compactMap { $0 }

        let sdkSkinRoots = [
            NSHomeDirectory() + "/Library/Android/sdk/skins",
            env["ANDROID_HOME"].map { "\($0)/skins" },
            env["ANDROID_SDK_ROOT"].map { "\($0)/skins" }
        ].compactMap { $0 }

        // 1. Try resolving through AVD config.ini
        for root in roots {
            var candidateConfigURLs: [URL] = []
            let iniPath = URL(fileURLWithPath: root).appendingPathComponent("\(name).ini")
            if let iniText = try? String(contentsOf: iniPath, encoding: .utf8),
               let path = self.iniValue("path", in: iniText) {
                candidateConfigURLs.append(URL(fileURLWithPath: path).appendingPathComponent("config.ini"))
            }
            candidateConfigURLs.append(URL(fileURLWithPath: root).appendingPathComponent("\(name).avd/config.ini"))
            candidateConfigURLs.append(URL(fileURLWithPath: root).appendingPathComponent("\(name)/config.ini"))

            for configURL in candidateConfigURLs {
                guard let config = try? String(contentsOf: configURL, encoding: .utf8) else { continue }
                let skinName = iniValue("skin.name", in: config)
                let skinPath = iniValue("skin.path", in: config)

                // Try skin.path directly if absolute
                if let skinPath, skinPath.hasPrefix("/"), fm.fileExists(atPath: skinPath) {
                    let back = URL(fileURLWithPath: skinPath).appendingPathComponent("back.webp")
                    let mask = URL(fileURLWithPath: skinPath).appendingPathComponent("mask.webp")
                    if let frameImg = NSImage(contentsOf: back) {
                        return (frameImg, NSImage(contentsOf: mask))
                    }
                }

                // Try resolving skin.name or skin.path inside SDK skin roots
                let identifiers = [skinName, skinPath?.replacingOccurrences(of: "skins/", with: "")].compactMap { $0 }
                for id in identifiers {
                    for sdkRoot in sdkSkinRoots {
                        let candidateDir = URL(fileURLWithPath: sdkRoot).appendingPathComponent(id)
                        let back = candidateDir.appendingPathComponent("back.webp")
                        let mask = candidateDir.appendingPathComponent("mask.webp")
                        if let frameImg = NSImage(contentsOf: back) {
                            return (frameImg, NSImage(contentsOf: mask))
                        }
                    }
                }
            }
        }

        // 2. Try fuzzy matching AVD name to SDK skins (e.g. Pixel_9_Pro_ARM64 -> pixel_9_pro)
        let cleanName = name.lowercased()
            .replacingOccurrences(of: "_arm64", with: "")
            .replacingOccurrences(of: "-arm64", with: "")
            .replacingOccurrences(of: " ", with: "_")
        for sdkRoot in sdkSkinRoots {
            let candidateDir = URL(fileURLWithPath: sdkRoot).appendingPathComponent(cleanName)
            let back = candidateDir.appendingPathComponent("back.webp")
            let mask = candidateDir.appendingPathComponent("mask.webp")
            if let frameImg = NSImage(contentsOf: back) {
                return (frameImg, NSImage(contentsOf: mask))
            }
        }

        // 3. Fallback: Always return official bundled Pixel 9 Pro frame and mask
        let frameImg = DeviceFrameAssets.loadAndroidPixelProBezel()
        let maskImg = DeviceFrameAssets.loadAndroidPixelProMask()
        return (frameImg, maskImg)
    }

    func officialAndroidFrame(forAVDNamed name: String) -> NSImage? {
        return resolveOfficialAndroidSkin(forAVDNamed: name).frame ?? DeviceFrameAssets.loadAndroidPixelProBezel()
    }

    /// Android Studio writes some AVD config keys as `key=value` and others
    /// as `key = value`. Treat those as the same format; requiring an exact
    /// no-space prefix was why the official Pixel 9 Pro skin silently became
    /// the generic fallback frame.
    private func iniValue(_ key: String, in text: String) -> String? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let parts = rawLine.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespacesAndNewlines) == key else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private func storageSize(in config: String, key: String) -> UInt64? {
        guard let line = config.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("\(key)=") }) else { return nil }
        let raw = String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pattern = "^([0-9]+)\\s*([kmgt]?)(?:b)?$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let valueRange = Range(match.range(at: 1), in: raw),
              let value = UInt64(raw[valueRange]) else { return nil }
        let unit = match.range(at: 2).location == NSNotFound ? "" : String(raw[Range(match.range(at: 2), in: raw)!])
        let multiplier: UInt64
        switch unit {
        case "k": multiplier = 1_024
        case "m": multiplier = 1_024 * 1_024
        case "g": multiplier = 1_024 * 1_024 * 1_024
        case "t": multiplier = 1_024 * 1_024 * 1_024 * 1_024
        default: multiplier = 1
        }
        return value.multipliedReportingOverflow(by: multiplier).overflow ? nil : value * multiplier
    }

    private func xcodeScheme(_ project: GUIProjectDescriptor) async throws -> String {
        if let selectedScheme, buildSchemes.contains(selectedScheme) { return selectedScheme }
        let schemes = try await xcodeSchemes(project)
        guard let scheme = schemes.first else {
            throw ToolBoxError.executionFailed("No shared Xcode scheme found. Mark a scheme as Shared in Xcode first.")
        }
        return scheme
    }

    private func xcodeSchemes(_ project: GUIProjectDescriptor) async throws -> [String] {
        guard let container = project.xcodeContainer else { throw ToolBoxError.executionFailed("No Xcode container found.") }
        let args = container.pathExtension == "xcworkspace" ? ["-workspace", container.path, "-list", "-json"] : ["-project", container.path, "-list", "-json"]
        let result = try await command("/usr/bin/xcodebuild", args, directory: project.root)
        let json = try JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any]
        let root = container.pathExtension == "xcworkspace" ? json?["workspace"] as? [String: Any] : json?["project"] as? [String: Any]
        return (root?["schemes"] as? [String] ?? []).sorted()
    }

    private func xcodeBuildSettings(_ project: GUIProjectDescriptor, scheme: String, device: RuntimeDevice) async throws -> [String: String] {
        guard let container = project.xcodeContainer else { throw ToolBoxError.executionFailed("No Xcode container found.") }
        var args = container.pathExtension == "xcworkspace" ? ["-workspace", container.path] : ["-project", container.path]
        args += ["-scheme", scheme]
        args += device.platform == .ios ? ["-destination", "id=\(device.id)"] : ["-destination", "platform=macOS"]
        args += ["-showBuildSettings", "-json"]
        let result = try await command("/usr/bin/xcodebuild", args, directory: project.root)
        guard let list = try JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [[String: Any]],
              let first = list.first,
              let settings = first["buildSettings"] as? [String: String] else {
            throw ToolBoxError.executionFailed("Unable to read Xcode build settings.")
        }
        return settings
    }

    private func androidApplicationID(_ root: URL) -> String? {
        let candidates = [
            root.appendingPathComponent("app/build.gradle"),
            root.appendingPathComponent("app/build.gradle.kts"),
            root.appendingPathComponent("app/src/main/AndroidManifest.xml")
        ]
        let patterns = ["applicationId\\s*[=\\s]*[\\\"']([^\\\"']+)", "package=\\\"([^\\\"]+)\\\""]
        for url in candidates {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range(at: 1), in: text) else { continue }
                return String(text[range])
            }
        }
        return nil
    }

    /// A newly launched AVD is not immediately visible to Gradle/ADB.  Wait for
    /// the *actual* device connection rather than racing an install against boot.
    private func readyAndroidSerial(for device: RuntimeDevice) async throws -> String {
        if !device.id.hasPrefix("avd:") { return device.id }
        let avdName = String(device.id.dropFirst(4))
        for _ in 0..<90 {
            if let serial = await attachedAndroidSerial(named: avdName) { return serial }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw ToolBoxError.executionFailed("Android Emulator did not become ready within 90 seconds. Open it once from Android Studio, then try again.")
    }

    /// `adb devices` alone cannot tell which AVD owns an emulator serial. The
    /// emulator console can, and lets us attach to the requested AVD instead
    /// of racing whichever Android target happened to boot first.
    private func attachedAndroidSerial(named avdName: String) async -> String? {
        guard let adb = try? androidTool("adb"),
              let result = try? await command(adb, ["devices"], directory: nil) else { return nil }
        let serials = result.output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .map { $0.split(separator: "\t") }
            .compactMap { fields -> String? in
                guard fields.count >= 2, fields[1] == "device", fields[0].hasPrefix("emulator-") else { return nil }
                return String(fields[0])
            }
        for serial in serials {
            guard let name = try? await command(adb, ["-s", serial, "emu", "avd", "name"], directory: nil) else { continue }
            // The emulator console appends a protocol acknowledgement ("OK")
            // after the actual name. Compare only the first non-empty line.
            let reportedName = name.output
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty && $0 != "OK" })
            if reportedName == avdName { return serial }
        }
        return nil
    }

    private func androidAVDName(serial: String) async -> String? {
        guard let adb = try? androidTool("adb"),
              let name = try? await command(adb, ["-s", serial, "emu", "avd", "name"], directory: nil) else { return nil }
        return name.output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && $0 != "OK" })
    }

    private func firstAttachedEmulatorSerial() async -> String? {
        guard let adb = try? androidTool("adb"),
              let result = try? await command(adb, ["devices"], directory: nil) else { return nil }
        let serials = result.output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line -> String? in
                let parts = line.split(separator: "\t")
                guard parts.count >= 2, parts[1].trimmingCharacters(in: .whitespacesAndNewlines) == "device" else { return nil }
                let serial = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                return serial.hasPrefix("emulator-") ? serial : nil
            }
        return serials.first
    }

    private func androidTool(_ name: String) throws -> String {
        let env = ProcessInfo.processInfo.environment
        let homes = [env["ANDROID_SDK_ROOT"], env["ANDROID_HOME"], NSHomeDirectory() + "/Library/Android/sdk"].compactMap { $0 }
        for home in homes {
            let path = name == "adb" ? "\(home)/platform-tools/adb" : "\(home)/emulator/emulator"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        throw ToolBoxError.executionFailed("Android SDK \(name) is not installed. Install Android Studio with Emulator and Platform Tools, then refresh.")
    }

    private func launchLongRunning(_ executable: String, _ arguments: [String], directory: URL) throws {
        try? applicationInputHandle?.close()
        applicationInputHandle = nil
        applicationProcess?.terminate()
        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // React Native/Flutter keep writing while their dev server runs.  A
        // non-drained Pipe eventually fills and freezes the child process.
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard self?.applicationProcess === process else { return }
                self?.applicationInputHandle = nil
                self?.applicationProcess = nil
            }
        }
        try process.run()
        applicationInputHandle = input.fileHandleForWriting
        applicationProcess = process
    }

    private func appendOutput(_ text: String) {
        output = String((output + (output.isEmpty ? "" : "\n\n") + text).suffix(30_000))
    }

    private func summary() -> String {
        let projectText = project.map { "Project: \($0.runtime.rawValue)" } ?? "Project: not detected"
        let deviceText = devices.map { "- \($0.id): \($0.name) [\($0.platform.rawValue), \($0.detail)]" }.joined(separator: "\n")
        return "\(projectText)\n\(statusMessage)\n\nDevices:\n\(deviceText.isEmpty ? "None found" : deviceText)"
    }

    private struct CommandResult { let output: String; let status: Int32 }

    private nonisolated func command(_ executable: String, _ arguments: [String], directory: URL?) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = directory
            // xcodebuild can produce megabytes of logs.  Writing to an unread
            // Pipe can block the build indefinitely, so capture into a bounded-
            // lifetime file and read it once the process exits.
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("microcode-device-command-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            let outputHandle: FileHandle
            do {
                outputHandle = try FileHandle(forWritingTo: outputURL)
            } catch {
                continuation.resume(throwing: error)
                return
            }
            process.standardOutput = outputHandle
            process.standardError = outputHandle
            process.terminationHandler = { process in
                try? outputHandle.close()
                let data = (try? Data(contentsOf: outputURL)) ?? Data()
                let output = String(data: data, encoding: .utf8) ?? ""
                try? FileManager.default.removeItem(at: outputURL)
                if process.terminationStatus == 0 { continuation.resume(returning: CommandResult(output: output, status: process.terminationStatus)) }
                else { continuation.resume(throwing: ToolBoxError.executionFailed(output.isEmpty ? "\(executable) exited with status \(process.terminationStatus)." : output)) }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    /// Binary command variant for Android's PNG screen capture. The reader is
    /// started before the child can fill its pipe, eliminating per-frame
    /// temporary files and SSD I/O without risking a producer deadlock.
    private nonisolated func commandData(_ executable: String, _ arguments: [String], directory: URL?) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = directory
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }
            let readHandle = outputPipe.fileHandleForReading
            DispatchQueue.global(qos: .userInitiated).async {
                let data = readHandle.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ToolBoxError.executionFailed("Android screen capture failed (status \(process.terminationStatus))."))
                }
            }
        }
    }
}
