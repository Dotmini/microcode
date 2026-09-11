//
//  NativeSimulatorBridgeService.swift
//  MicroCode
//
//  Native, low-latency iOS Simulator preview.  This is an independent Swift
//  implementation inspired by the framebuffer architecture in Evan Bacon's
//  serve-sim (Apache-2.0).  It deliberately has no Node, HTTP, WebSocket, or
//  WebKit dependency in the frame path:
//
//  SimulatorKit IOSurface -> CVPixelBuffer -> AVSampleBufferDisplayLayer
//
//  SimulatorKit is an Xcode-private framework.  It is loaded dynamically from
//  the selected Xcode, so this remains compatible with Xcode installed on an
//  external SSD.  When Apple changes that private surface, the caller falls
//  back to the supported Device Hub capture service.
//

import AppKit
import AVFoundation
import Combine
import CoreMedia
import CoreVideo
import Foundation
import IOSurface
import ObjectiveC

@MainActor
final class NativeSimulatorBridgeService: ObservableObject {
    static let shared = NativeSimulatorBridgeService()

    /// This is a ceiling, not synthetic interpolation.  The bridge renders
    /// every source frame up to 120 Hz and reports the measured source rate.
    static let maximumFrameRate = 120

    @Published private(set) var isActive = false
    @Published private(set) var statusMessage = "Native iOS Preview is idle."
    @Published private(set) var measuredFrameRate = 0
    @Published private(set) var pixelSize = CGSize.zero

    private let frameOutput = NativeSimulatorFrameOutput()
    private var capture: NativeSimulatorIOSurfaceCapture?
    private var activeSimulatorID: String?
    private var frameWindowStarted = Date()
    private var framesInWindow = 0

    private init() {}

    func attach(to layer: AVSampleBufferDisplayLayer) {
        frameOutput.attach(to: layer)
        layer.videoGravity = .resizeAspect
    }

    func detach(from layer: AVSampleBufferDisplayLayer) {
        guard frameOutput.displayLayer === layer else { return }
        frameOutput.displayLayer = nil
    }

    func start(simulatorID: String, simulatorName: String) async {
        stop()
        statusMessage = "Attaching native iOS preview to \(simulatorName)…"

        let capture = NativeSimulatorIOSurfaceCapture(maximumFrameRate: Self.maximumFrameRate)
        capture.onFrame = { [weak self] pixelBuffer, size in
            // AVSampleBufferDisplayLayer belongs to AppKit's main render
            // transaction. Enqueuing from SimulatorKit's private callback
            // queue can leave the layer permanently black even though a
            // framebuffer was found.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.frameOutput.enqueue(pixelBuffer)
                self.recordFrame(size: size)
            }
        }

        do {
            try await capture.start(deviceUDID: simulatorID)
            self.capture = capture
            activeSimulatorID = simulatorID
            isActive = true
            statusMessage = "Live · native IOSurface · up to 120 FPS"
        } catch {
            capture.stop()
            statusMessage = "Native iOS preview unavailable: \(error.localizedDescription)"
        }
    }

    func stop() {
        capture?.stop()
        capture = nil
        activeSimulatorID = nil
        isActive = false
        measuredFrameRate = 0
        pixelSize = .zero
        frameOutput.flush()
    }

    private func recordFrame(size: CGSize) {
        pixelSize = size
        framesInWindow += 1
        let elapsed = Date().timeIntervalSince(frameWindowStarted)
        guard elapsed >= 0.5 else { return }
        measuredFrameRate = min(Int((Double(framesInWindow) / elapsed).rounded()), Self.maximumFrameRate)
        framesInWindow = 0
        frameWindowStarted = Date()
    }
}

/// GPU-backed AppKit presentation.  Frames never make a round trip through an
/// image file, a local HTTP server, JavaScript, or a web view.
private final class NativeSimulatorFrameOutput {
    weak var displayLayer: AVSampleBufferDisplayLayer?
    private var formatDescription: CMVideoFormatDescription?
    private var renderedSize = CGSize.zero
    private var latestPixelBuffer: CVPixelBuffer?

    func attach(to layer: AVSampleBufferDisplayLayer) {
        displayLayer = layer
        if let latestPixelBuffer { enqueue(latestPixelBuffer) }
    }

    func enqueue(_ pixelBuffer: CVPixelBuffer) {
        latestPixelBuffer = pixelBuffer
        guard let layer = displayLayer else { return }
        if layer.status == .failed { layer.flushAndRemoveImage() }
        guard layer.isReadyForMoreMediaData else { return }

        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        if formatDescription == nil || renderedSize != size {
            var description: CMVideoFormatDescription?
            guard CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &description
            ) == noErr else { return }
            formatDescription = description
            renderedSize = size
        }
        guard let formatDescription else { return }

        let presentationTime = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else { return }
        layer.enqueue(sampleBuffer)
    }

    func flush() {
        formatDescription = nil
        renderedSize = .zero
        latestPixelBuffer = nil
        displayLayer?.flushAndRemoveImage()
    }
}

/// Owns the Xcode SimulatorKit callback registration on a serial interactive
/// queue.  The APIs are runtime-checked because SimulatorKit is private and
/// moves between Xcode releases; no private framework is linked at build time.
// All mutable state is confined to `queue`; the callback registration itself
// is also made on that queue.  This keeps the dynamically-loaded Objective-C
// bridge safe to hand into the Swift concurrency continuation below.
private final class NativeSimulatorIOSurfaceCapture: @unchecked Sendable {
    private let queue = DispatchQueue(label: "net.dotmini.microcode.native-simulator", qos: .userInteractive)
    private let maximumFrameRate: Int
    private var descriptors: [NSObject] = []
    private var callbackIDs: [ObjectIdentifier: UUID] = [:]
    private var lastSeeds: [ObjectIdentifier: UInt32] = [:]
    private var lastFrameTime = Date()
    private var expectedScreenSize: CGSize?
    private var framePollTimer: DispatchSourceTimer?

    var onFrame: ((CVPixelBuffer, CGSize) -> Void)?

    init(maximumFrameRate: Int) {
        self.maximumFrameRate = max(1, maximumFrameRate)
    }

    func start(deviceUDID: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else { return }
                // `simctl bootstatus -b` guarantees SpringBoard, but the
                // SimulatorKit framebuffer port can arrive a few turns later.
                // Wait for the native surface instead of invoking the
                // ScreenCaptureKit fallback and its TCC permission prompt.
                let deadline = Date().addingTimeInterval(12)
                var lastError: Error?
                while Date() < deadline {
                    do {
                        try self.startSynchronously(deviceUDID: deviceUDID)
                        continuation.resume()
                        return
                    } catch {
                        lastError = error
                        self.clearAttachment(preserveOutput: true)
                        Thread.sleep(forTimeInterval: 0.15)
                    }
                }
                continuation.resume(throwing: lastError ?? NativeSimulatorError.unavailable("The iOS framebuffer did not become ready."))
            }
        }
    }

    func stop() {
        queue.async { [weak self] in self?.stopSynchronously() }
    }

    private func startSynchronously(deviceUDID: String) throws {
        NativeSimulatorPrivateFrameworks.load()
        guard let device = findDevice(udid: deviceUDID) else {
            throw NativeSimulatorError.unavailable("The selected simulator is not available through the active Xcode.")
        }
        let state = device.value(forKey: "stateString") as? String ?? "unknown"
        guard state.caseInsensitiveCompare("booted") == .orderedSame else {
            throw NativeSimulatorError.unavailable("The selected simulator has not finished booting (state: \(state)).")
        }
        expectedScreenSize = nativeScreenSize(for: device)
        guard let io = device.perform(NSSelectorFromString("io"))?.takeUnretainedValue() as? NSObject else {
            throw NativeSimulatorError.unavailable("Simulator framebuffer IO is unavailable in this Xcode runtime.")
        }
        io.perform(NSSelectorFromString("updateIOPorts"))
        guard let ports = io.value(forKey: "deviceIOPorts") as? [NSObject] else {
            throw NativeSimulatorError.unavailable("Simulator framebuffer ports were not exposed.")
        }
        // Apple has changed this identifier between Xcode releases. The
        // stable capability is `framebufferSurface`, so prefer the capability
        // rather than rejecting valid ports with a newer identifier.
        descriptors = ports.compactMap { port in
            guard let descriptor = port.perform(NSSelectorFromString("descriptor"))?.takeUnretainedValue() as? NSObject,
                  descriptor.responds(to: NSSelectorFromString("framebufferSurface")) else { return nil }
            return descriptor
        }
        guard !descriptors.isEmpty else {
            throw NativeSimulatorError.unavailable("No live iOS framebuffer is available yet.")
        }
        for descriptor in descriptors {
            _ = try registerCallbacks(on: descriptor)
        }
        guard captureFrame(force: true) else {
            throw NativeSimulatorError.unavailable("The iOS framebuffer surface is still initializing.")
        }
        // Callback registration can succeed but never fire on some Xcode
        // builds. Polling IOSurface's seed is cheap and guarantees a live
        // frame path in both cases; callbacks merely reduce latency.
        startFramePolling()
    }

    @discardableResult
    private func registerCallbacks(on descriptor: NSObject) throws -> Bool {
        let selector = #selector(NativeSimulatorFramebufferDescriptor.registerScreenCallbacks)
        guard descriptor.responds(to: selector) else {
            // Some releases expose the IOSurface but omit callbacks. Poll its
            // seed on the native interactive queue, up to the 120 Hz ceiling.
            return false
        }
        let callbackID = UUID()
        callbackIDs[ObjectIdentifier(descriptor)] = callbackID
        // The selector is verified above. `unsafeBitCast` sends that Objective-C
        // message without requiring the private descriptor class at compile time.
        let typedDescriptor = unsafeBitCast(descriptor, to: NativeSimulatorFramebufferDescriptor.self)
        typedDescriptor.registerScreenCallbacks(
            uuid: callbackID,
            callbackQueue: queue,
            frameCallback: { [weak self] in self?.captureFrame() },
            surfacesChangedCallback: { [weak self] in self?.captureFrame(force: true) },
            propertiesChangedCallback: {}
        )
        return true
    }

    private func startFramePolling() {
        framePollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(8_333_333), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.captureFrame() }
        framePollTimer = timer
        timer.resume()
    }

    @discardableResult
    private func captureFrame(force: Bool = false) -> Bool {
        guard let descriptor = preferredDescriptor(),
              let value = descriptor.perform(NSSelectorFromString("framebufferSurface"))?.takeUnretainedValue()
        else { return false }
        let surface = unsafeBitCast(value, to: IOSurface.self)
        let seed = IOSurfaceGetSeed(surface)
        let identifier = ObjectIdentifier(descriptor)
        guard force || lastSeeds[identifier] != seed else { return true }
        lastSeeds[identifier] = seed

        // Do not manufacture intermediate frames. Throttle only if a runtime
        // genuinely exceeds the selected 120 Hz ceiling.
        let now = Date()
        let minimumSeconds = 1.0 / Double(maximumFrameRate)
        if !force, now.timeIntervalSince(lastFrameTime) < minimumSeconds { return true }
        lastFrameTime = now

        let width = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        guard width > 0, height > 0 else { return false }
        var output: Unmanaged<CVPixelBuffer>?
        guard CVPixelBufferCreateWithIOSurface(
            kCFAllocatorDefault,
            surface,
            [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA] as CFDictionary,
            &output
        ) == kCVReturnSuccess, let pixelBuffer = output?.takeRetainedValue() else { return false }
        onFrame?(pixelBuffer, CGSize(width: width, height: height))
        return true
    }

    private func preferredDescriptor() -> NSObject? {
        let candidates: [(NSObject, CGSize)] = descriptors.compactMap { descriptor in
            guard let value = descriptor.perform(NSSelectorFromString("framebufferSurface"))?.takeUnretainedValue() else { return nil }
            let surface = unsafeBitCast(value, to: IOSurface.self)
            let size = CGSize(width: IOSurfaceGetWidth(surface), height: IOSurfaceGetHeight(surface))
            return size.width > 0 && size.height > 0 ? (descriptor, size) : nil
        }
        guard !candidates.isEmpty else { return nil }
        if let expectedScreenSize,
           let exact = candidates.first(where: { $0.1 == expectedScreenSize || $0.1 == CGSize(width: expectedScreenSize.height, height: expectedScreenSize.width) }) {
            return exact.0
        }
        return candidates.max { ($0.1.width * $0.1.height) < ($1.1.width * $1.1.height) }?.0
    }

    private func nativeScreenSize(for device: NSObject) -> CGSize? {
        let deviceTypeSelector = NSSelectorFromString("deviceType")
        guard let type = device.perform(deviceTypeSelector)?.takeUnretainedValue() as? NSObject else { return nil }
        let sizeSelector = NSSelectorFromString("mainScreenSize")
        guard type.responds(to: sizeSelector) else { return nil }
        typealias GetSize = @convention(c) (AnyObject, Selector) -> CGSize
        let function = unsafeBitCast(type.method(for: sizeSelector), to: GetSize.self)
        let result = function(type, sizeSelector)
        return result.width > 0 && result.height > 0 ? result : nil
    }

    private func findDevice(udid: String) -> NSObject? {
        guard let serviceContext = NSClassFromString("SimServiceContext") as? NSObject.Type else { return nil }
        let developerDirectory = NativeSimulatorPrivateFrameworks.developerDirectory()
        let shared = NSSelectorFromString("sharedServiceContextForDeveloperDir:error:")
        guard let context = serviceContext.perform(shared, with: developerDirectory, with: nil)?.takeUnretainedValue() as? NSObject,
              let set = context.perform(NSSelectorFromString("defaultDeviceSetWithError:"), with: nil)?.takeUnretainedValue() as? NSObject,
              let devices = set.value(forKey: "devices") as? [NSObject] else { return nil }
        return devices.first { ($0.value(forKey: "UDID") as? NSUUID)?.uuidString.caseInsensitiveCompare(udid) == .orderedSame }
    }

    private func stopSynchronously() {
        // Drop the output closure before unregistering. A callback already on
        // the serial queue can otherwise enqueue one stale frame after Preview
        // has been closed or a different device was selected.
        clearAttachment(preserveOutput: false)
    }

    private func clearAttachment(preserveOutput: Bool) {
        framePollTimer?.setEventHandler {}
        framePollTimer?.cancel()
        framePollTimer = nil
        let unregister = NSSelectorFromString("unregisterScreenCallbacksWithUUID:")
        for descriptor in descriptors {
            if let callbackID = callbackIDs[ObjectIdentifier(descriptor)], descriptor.responds(to: unregister) {
                descriptor.perform(unregister, with: callbackID)
            }
        }
        callbackIDs.removeAll()
        lastSeeds.removeAll()
        descriptors.removeAll()
        expectedScreenSize = nil
        if !preserveOutput { onFrame = nil }
    }
}

private enum NativeSimulatorPrivateFrameworks {
    static func developerDirectory() -> String {
        if let explicit = ProcessInfo.processInfo.environment["DEVELOPER_DIR"], !explicit.isEmpty { return explicit }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "/Applications/Xcode.app/Contents/Developer" }
        process.waitUntilExit()
        let value = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "/Applications/Xcode.app/Contents/Developer" : value
    }

    static func load() {
        let developer = developerDirectory()
        let candidates = [
            "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator",
            "\(developer)/Library/PrivateFrameworks/CoreSimulator.framework/CoreSimulator",
            "\(developer)/../SharedFrameworks/SimulatorKit.framework/SimulatorKit",
            "\(developer)/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"
        ]
        for candidate in candidates { _ = dlopen(candidate, RTLD_NOW) }
    }
}

private enum NativeSimulatorError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): return message }
    }
}

@objc private protocol NativeSimulatorFramebufferDescriptor {
    @objc(registerScreenCallbacksWithUUID:callbackQueue:frameCallback:surfacesChangedCallback:propertiesChangedCallback:)
    func registerScreenCallbacks(
        uuid: UUID,
        callbackQueue: DispatchQueue,
        frameCallback: @convention(block) @escaping () -> Void,
        surfacesChangedCallback: @convention(block) @escaping () -> Void,
        propertiesChangedCallback: @convention(block) @escaping () -> Void
    )
}
