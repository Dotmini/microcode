//
//  AppleSimulatorCaptureService.swift
//  MicroCode
//
//  A low-latency capture bridge for Apple's real simulator surface. Xcode 27
//  exposes it through Device Hub; older Xcode releases use Simulator.app.
//  The runtime remains Apple-owned. MicroCode only displays its genuine window
//  beside Chat using ScreenCaptureKit, so no fake phone frame or canvas
//  renderer is involved.
//

import AppKit
import AVFoundation
import CoreMedia
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class AppleSimulatorCaptureService: NSObject, ObservableObject {
    static let shared = AppleSimulatorCaptureService()

    @Published private(set) var isActive = false
    @Published private(set) var statusMessage = "Select an iOS Simulator to open its live preview."
    /// ScreenCaptureKit is protected by macOS TCC.  We preflight before
    /// launching Device Hub so a Preview click never unexpectedly opens an
    /// external window and immediately throws a system permission sheet.
    @Published private(set) var needsScreenRecordingPermission = false

    private var stream: SCStream?
    private var streamOutput: SimulatorWindowStreamOutput?
    private weak var displayLayer: AVSampleBufferDisplayLayer?

    func attach(to layer: AVSampleBufferDisplayLayer) {
        displayLayer = layer
        streamOutput?.displayLayer = layer
        layer.videoGravity = .resizeAspect
    }

    func detach(from layer: AVSampleBufferDisplayLayer) {
        guard displayLayer === layer else { return }
        displayLayer = nil
        streamOutput?.displayLayer = nil
    }

    /// Captures the actual Device Hub (Xcode 27+) or Simulator.app window.
    /// Permission is explicitly requested by the user from the dock instead
    /// of being triggered as a side effect of starting a simulator.
    func start(simulatorName: String) async {
        stop()
        guard CGPreflightScreenCaptureAccess() else {
            needsScreenRecordingPermission = true
            statusMessage = "Screen Recording permission is required to show the real Apple Device Hub beside Chat. Allow it in Privacy & Security, then retry Preview."
            return
        }
        needsScreenRecordingPermission = false
        statusMessage = "Opening Apple Device Hub…"
        do {
            try await openAppleDeviceApplication()
            let window = try await waitForSimulatorWindow(preferredName: simulatorName)
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            // Device Hub is a complete Apple application window: navigator,
            // toolbar and the selected device.  The preview must show only
            // Apple's genuine device bezel, not a tiny screenshot of that
            // whole application.  `sourceRect` crops the native stream before
            // it reaches SwiftUI, so no synthetic iPhone frame is drawn.
            // `SCStreamConfiguration.sourceRect` is in the captured window's
            // own coordinate space — it is *not* in the desktop coordinate
            // space reported by SCWindow.frame.  Using `window.frame` here
            // offsets the crop by the position of Device Hub on the desktop,
            // which is why the previous preview showed half a phone next to a
            // large white rectangle.
            let sourceRect = deviceFrameSourceRect(for: window) ?? CGRect(origin: .zero, size: window.frame.size)
            configuration.sourceRect = sourceRect
            configuration.width = max(Int(sourceRect.width) * 2, 1)
            configuration.height = max(Int(sourceRect.height) * 2, 1)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            configuration.queueDepth = 5
            configuration.capturesAudio = false
            configuration.showsCursor = false

            let output = SimulatorWindowStreamOutput()
            output.displayLayer = displayLayer
            let newStream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try newStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
            try await newStream.startCapture()
            stream = newStream
            streamOutput = output
            isActive = true
            statusMessage = "Live · Apple iPhone frame · 60 FPS target"
            bringMicroCodeToFront()
        } catch {
            isActive = false
            statusMessage = "iOS preview unavailable: \(error.localizedDescription)"
        }
    }

    func stop() {
        let activeStream = stream
        stream = nil
        streamOutput?.displayLayer = nil
        streamOutput = nil
        isActive = false
        displayLayer?.flushAndRemoveImage()
        if let activeStream {
            Task { try? await activeStream.stopCapture() }
        }
    }

    /// This is the only method that may show the macOS privacy prompt.  It is
    /// invoked from an explicit "Allow" button, never from an automatic run.
    func requestScreenRecordingPermission() {
        guard !CGPreflightScreenCaptureAccess() else {
            needsScreenRecordingPermission = false
            statusMessage = "Screen Recording permission is already enabled. Start Preview again."
            return
        }
        _ = CGRequestScreenCaptureAccess()
        needsScreenRecordingPermission = !CGPreflightScreenCaptureAccess()
        statusMessage = needsScreenRecordingPermission
            ? "Enable MicroCode in System Settings → Privacy & Security → Screen Recording, then return and retry Preview."
            : "Screen Recording permission granted. Start Preview again."
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openAppleDeviceApplication() async throws {
        let developer = try await activeDeveloperDirectory()
        // `xcrun --find simctl` returns
        // .../Contents/Developer/usr/bin/simctl.  Its third parent is
        // Developer (not the second, which is .../Developer/usr).  Resolving
        // it from the active xcode-select toolchain makes an Xcode copy on an
        // external SSD work exactly like an internal installation.
        let configuredPath = UserDefaults.standard.string(forKey: "MicroCode.simulatorApplicationPath")
        let environmentPath = ProcessInfo.processInfo.environment["MICROCODE_SIMULATOR_APP_PATH"]
        let configuredCandidates = [environmentPath, configuredPath]
            .compactMap { $0 }
            .map(URL.init(fileURLWithPath:))
        // Device Hub replaced the separately launched Simulator.app in Xcode
        // 27. Keep Simulator.app as a compatibility fallback for older Xcode.
        let fallbackCandidates = configuredCandidates + [
            developer.appendingPathComponent("Applications/DeviceHub.app"),
            developer.appendingPathComponent("Applications/Simulator.app"),
            developer.appendingPathComponent("Platforms/iPhoneSimulator.platform/Developer/Applications/Simulator.app")
        ]
        let simulator = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Devices")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iphonesimulator")
            ?? fallbackCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
        guard let simulator else {
            throw NSError(
                domain: "MicroCode.iOSPreview",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No Apple Device Hub or Simulator app was found in the active Xcode installation. Select a complete Xcode installation, then refresh Preview."]
            )
        }
        // Keep Device Hub in the background.  The capture is desktop-
        // independent and MicroCode is reactivated after the stream starts,
        // so users do not get thrown out of their editor just to see Preview.
        _ = try await run("/usr/bin/open", ["-g", simulator.path])
    }

    private func activeDeveloperDirectory() async throws -> URL {
        let configured = try await run("/usr/bin/xcode-select", ["-p"])
        let selected = URL(fileURLWithPath: configured.trimmingCharacters(in: .whitespacesAndNewlines), isDirectory: true)
        if FileManager.default.fileExists(atPath: selected.path) {
            return selected
        }

        // Fallback for a per-process DEVELOPER_DIR or an externally mounted
        // Xcode selected by xcrun.  This preserves compatibility when the
        // global selection changes while MicroCode is already running.
        let simctl = try await run("/usr/bin/xcrun", ["--find", "simctl"])
        let executable = URL(fileURLWithPath: simctl.trimmingCharacters(in: .whitespacesAndNewlines))
        return executable
            .deletingLastPathComponent() // bin
            .deletingLastPathComponent() // usr
            .deletingLastPathComponent() // Developer
    }

    private func waitForSimulatorWindow(preferredName: String) async throws -> SCWindow {
        // Device Hub can take a few seconds on its first launch. Keep this
        // bounded so an unavailable app or missing permission never turns the
        // preview into an unbounded spinner.
        for _ in 0..<30 {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let candidates = content.windows.filter { window in
                let bundleID = window.owningApplication?.bundleIdentifier.lowercased() ?? ""
                let appName = window.owningApplication?.applicationName.lowercased() ?? ""
                return bundleID == "com.apple.dt.devices"
                    || bundleID.contains("iphonesimulator")
                    || appName == "devicehub"
                    || appName == "device hub"
                    || appName == "simulator"
            }
        if let exact = candidates.first(where: { ($0.title ?? "").localizedCaseInsensitiveContains(preferredName) }) {
                return exact
            }
            if let first = candidates.first { return first }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        throw NSError(domain: "MicroCode.iOSPreview", code: 2, userInfo: [NSLocalizedDescriptionKey: "Apple Device Hub did not expose a capture window. Allow Screen Recording for MicroCode in System Settings, then reopen Preview."])
    }

    /// Returns the portrait-device region inside the real Xcode Device Hub
    /// window.  Device Hub keeps its selected device in a stable centre-right
    /// canvas; cropping in ScreenCaptureKit (instead of cropping in SwiftUI)
    /// preserves the native Apple bezel at full resolution and drops all
    /// Device Hub chrome.  Simulator.app windows already contain only a
    /// device, so they are deliberately left untouched.
    private func deviceFrameSourceRect(for window: SCWindow) -> CGRect? {
        guard window.owningApplication?.bundleIdentifier == "com.apple.dt.Devices" else {
            return nil
        }

        // `window.frame` is expressed in desktop coordinates.  Use only its
        // dimensions for the layout calculation, then return a zero-based
        // rectangle for ScreenCaptureKit.
        let size = window.frame.size
        let bounds = CGRect(origin: .zero, size: size)
        // This is a portrait iPhone layout.  A landscape Device Hub window is
        // the normal configuration; if the window is itself portrait, there is
        // no navigator chrome to remove and capturing it whole is safer.
        guard size.width > size.height * 1.2 else { return nil }

        // In Device Hub's standard wide layout, the selected device lives in
        // the canvas just right of the navigator.  This crop deliberately
        // keeps only a narrow margin around Apple's genuine bezel/shadow and
        // drops Device Hub's navigator, toolbar, and white canvas.
        let deviceHeight = size.height * 0.86
        let deviceWidth = deviceHeight * 0.50
        let centre = CGPoint(
            x: size.width * 0.61,
            y: size.height * 0.54
        )
        let crop = CGRect(
            x: centre.x - deviceWidth * 0.62,
            y: centre.y - deviceHeight * 0.52,
            width: deviceWidth * 1.24,
            height: deviceHeight * 1.04
        )
        let clipped = crop.intersection(bounds)
        return clipped.isNull || clipped.isEmpty ? nil : clipped
    }

    private func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self)
                process.terminationStatus == 0
                    ? continuation.resume(returning: text)
                    : continuation.resume(throwing: NSError(domain: "MicroCode.iOSPreview", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "Command failed: \(executable)" : text]))
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    private func bringMicroCodeToFront() {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
    }
}

private final class SimulatorWindowStreamOutput: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "net.dotmini.microcode.simulator-preview", qos: .userInteractive)
    weak var displayLayer: AVSampleBufferDisplayLayer?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen,
              CMSampleBufferDataIsReady(sampleBuffer),
              let layer = displayLayer else { return }
        if layer.status == .failed { layer.flushAndRemoveImage() }
        if layer.isReadyForMoreMediaData { layer.enqueue(sampleBuffer) }
    }
}
