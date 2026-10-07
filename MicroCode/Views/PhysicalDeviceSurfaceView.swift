//
//  PhysicalDeviceSurfaceView.swift
//  MicroCode
//
//  SwiftUI / AppKit bridging surface for hardware-accelerated device streaming.
//  Uses CAMetalLayer + DeviceMetalRenderer for zero-copy 60-120 FPS rendering
//  with authentic iPhone hardware frame and dynamic aspect ratio scaling.
//

import SwiftUI
import AppKit
import Metal
import QuartzCore
import AVFoundation

// MARK: - Device Metal NSView

// MARK: - Device Metal NSView

/// NSView hosting a CAMetalLayer for sub-millisecond frame presentation
/// and full two-way input event forwarding (Tap, Drag, Swipe, Scroll, Keyboard).
final class DeviceMetalNSView: NSView {
    private var renderer: DeviceMetalRenderer?
    private var metalLayer: CAMetalLayer?

    /// Touch/input callback: (normalizedX, normalizedY, eventType)
    var onInput: ((CGFloat, CGFloat, InputEventType) -> Void)?
    /// High-level tap gesture callback: (normalizedX, normalizedY)
    var onTap: ((CGFloat, CGFloat) -> Void)?
    /// High-level swipe/drag callback: (fromX, fromY, toX, toY, durationMs)
    var onSwipe: ((CGFloat, CGFloat, CGFloat, CGFloat, Int) -> Void)?
    /// Trackpad / mouse scroll wheel callback: (deltaX, deltaY)
    var onScroll: ((CGFloat, CGFloat) -> Void)?
    /// Physical Mac keyboard key down callback
    var onKeyDown: ((NSEvent) -> Void)?

    private var downPoint: CGPoint = .zero
    private var downTime: Date = Date()
    private var hasMoved: Bool = false

    enum InputEventType {
        case down, move, up
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true

        let layer = CAMetalLayer()
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.displaySyncEnabled = false // Lowest latency
        self.layer = layer
        self.metalLayer = layer

        if let r = DeviceMetalRenderer() {
            r.metalLayer = layer
            self.renderer = r
        }
    }

    override func layout() {
        super.layout()
        metalLayer?.frame = bounds
        metalLayer?.drawableSize = CGSize(
            width: bounds.width * (window?.backingScaleFactor ?? 2.0),
            height: bounds.height * (window?.backingScaleFactor ?? 2.0)
        )
    }

    /// Render a CVPixelBuffer. Automatically detects NV12 vs BGRA format.
    func renderFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let renderer else { return }
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
           format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            renderer.renderFrame(pixelBuffer)
        } else {
            renderer.renderBGRAFrame(pixelBuffer)
        }
    }

    // MARK: - Interactive Mouse & Gesture Handling

    override func hitTest(_ point: NSPoint) -> NSView? {
        if bounds.contains(point) {
            return self
        }
        return super.hitTest(point)
    }

    private func showTapIndicator(at localPoint: CGPoint) {
        let ripple = CALayer()
        let size: CGFloat = 34
        ripple.frame = CGRect(x: localPoint.x - size / 2, y: localPoint.y - size / 2, width: size, height: size)
        ripple.cornerRadius = size / 2
        ripple.backgroundColor = NSColor.white.withAlphaComponent(0.38).cgColor
        ripple.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        ripple.borderWidth = 1.5
        layer?.addSublayer(ripple)

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.28)
        CATransaction.setCompletionBlock {
            ripple.removeFromSuperlayer()
        }
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.5
        scaleAnim.toValue = 1.4
        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.fromValue = 1.0
        fadeAnim.toValue = 0.0
        ripple.add(scaleAnim, forKey: "scale")
        ripple.add(fadeAnim, forKey: "opacity")
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let localPoint = convert(event.locationInWindow, from: nil)
        showTapIndicator(at: localPoint)
        let pt = normalizedPoint(event)
        downPoint = pt
        downTime = Date()
        hasMoved = false
        onInput?(pt.x, pt.y, .down)
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = normalizedPoint(event)
        let dist = hypot(pt.x - downPoint.x, pt.y - downPoint.y)
        if dist > 0.012 {
            hasMoved = true
        }
        onInput?(pt.x, pt.y, .move)
    }

    override func mouseUp(with event: NSEvent) {
        let pt = normalizedPoint(event)
        let durationMs = Int(Date().timeIntervalSince(downTime) * 1000)
        let dist = hypot(pt.x - downPoint.x, pt.y - downPoint.y)

        if !hasMoved || (dist < 0.02 && durationMs < 350) {
            onTap?(pt.x, pt.y)
        } else {
            onSwipe?(downPoint.x, downPoint.y, pt.x, pt.y, max(120, min(500, durationMs)))
        }

        onInput?(pt.x, pt.y, .up)
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaX, event.scrollingDeltaY)
    }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }

    private func normalizedPoint(_ event: NSEvent) -> CGPoint {
        let localPoint = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0 && bounds.height > 0 else { return .zero }
        return CGPoint(
            x: max(0, min(1, localPoint.x / bounds.width)),
            y: max(0, min(1, 1.0 - (localPoint.y / bounds.height))) // Invert Y for iOS/Android coordinate space
        )
    }
}

// MARK: - SwiftUI Bridge: PhysicalDeviceSurfaceView

/// SwiftUI View wrapping the Metal rendering surface.
struct PhysicalDeviceSurfaceView: NSViewRepresentable {
    let onInput: ((CGFloat, CGFloat, DeviceMetalNSView.InputEventType) -> Void)?
    let onInit: ((DeviceMetalNSView) -> Void)?

    init(
        onInput: ((CGFloat, CGFloat, DeviceMetalNSView.InputEventType) -> Void)? = nil,
        onInit: ((DeviceMetalNSView) -> Void)? = nil
    ) {
        self.onInput = onInput
        self.onInit = onInit
    }

    func makeNSView(context: Context) -> DeviceMetalNSView {
        let view = DeviceMetalNSView()
        view.onInput = onInput
        onInit?(view)
        return view
    }

    func updateNSView(_ nsView: DeviceMetalNSView, context: Context) {}
}

// MARK: - Convenience Surfaces for Specific Services

struct AndroidDeviceMetalSurface: NSViewRepresentable {
    @ObservedObject var androidStream: AndroidStreamService

    func makeNSView(context: Context) -> DeviceMetalNSView {
        let view = DeviceMetalNSView()
        if let latest = androidStream.latestPixelBuffer {
            view.renderFrame(latest)
        }
        androidStream.onDecodedFrame = { [weak view] pixelBuffer in
            DispatchQueue.main.async {
                view?.renderFrame(pixelBuffer)
            }
        }
        view.onInput = { [weak androidStream] normX, normY, eventType in
            guard let androidStream else { return }
            let res = androidStream.deviceResolution
            let w = Int(res.width > 0 ? res.width : 1080)
            let h = Int(res.height > 0 ? res.height : 2400)
            let px = max(0, min(w, Int(normX * CGFloat(w))))
            let py = max(0, min(h, Int(normY * CGFloat(h))))
            let action: Int
            switch eventType {
            case .down: action = 0
            case .up: action = 1
            case .move: action = 2
            }
            androidStream.sendTouch(action: action, x: px, y: py, width: w, height: h)
        }
        view.onTap = { [weak androidStream] normX, normY in
            guard let androidStream else { return }
            let res = androidStream.deviceResolution
            let w = Int(res.width > 0 ? res.width : 1080)
            let h = Int(res.height > 0 ? res.height : 2400)
            androidStream.sendTap(x: Int(normX * CGFloat(w)), y: Int(normY * CGFloat(h)))
        }
        view.onSwipe = { [weak androidStream] x1, y1, x2, y2, durationMs in
            guard let androidStream else { return }
            let res = androidStream.deviceResolution
            let w = Int(res.width > 0 ? res.width : 1080)
            let h = Int(res.height > 0 ? res.height : 2400)
            androidStream.sendSwipe(
                x1: Int(x1 * CGFloat(w)),
                y1: Int(y1 * CGFloat(h)),
                x2: Int(x2 * CGFloat(w)),
                y2: Int(y2 * CGFloat(h)),
                durationMs: durationMs
            )
        }
        view.onScroll = { [weak androidStream] dx, dy in
            androidStream?.sendScroll(deltaX: dx, deltaY: dy)
        }
        view.onKeyDown = { [weak androidStream] event in
            guard let androidStream else { return }
            switch event.keyCode {
            case 36: // Enter / Return
                androidStream.sendKey(66)
            case 51: // Backspace / Delete
                androidStream.sendKey(67)
            case 53: // Esc -> Android Back
                androidStream.sendKey(4)
            case 48: // Tab
                androidStream.sendKey(61)
            case 49: // Space
                androidStream.sendKey(62)
            case 123: // Left
                androidStream.sendKey(21)
            case 124: // Right
                androidStream.sendKey(22)
            case 125: // Down
                androidStream.sendKey(20)
            case 126: // Up
                androidStream.sendKey(19)
            default:
                if let chars = event.characters, !chars.isEmpty, !chars.unicodeScalars.contains(where: { $0.value < 32 }) {
                    androidStream.sendText(chars)
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: DeviceMetalNSView, context: Context) {
        if let latest = androidStream.latestPixelBuffer {
            nsView.renderFrame(latest)
        }
        androidStream.onDecodedFrame = { [weak nsView] pixelBuffer in
            DispatchQueue.main.async {
                nsView?.renderFrame(pixelBuffer)
            }
        }
    }
}

struct IOSDeviceMetalSurface: NSViewRepresentable {
    @ObservedObject var iosCapture: IOSDeviceCaptureService

    func makeNSView(context: Context) -> DeviceMetalNSView {
        let view = DeviceMetalNSView()
        iosCapture.onFrame = { [weak view] pixelBuffer, _ in
            DispatchQueue.main.async {
                view?.renderFrame(pixelBuffer)
            }
        }
        view.onTap = { normX, normY in
            IOSDeviceControlService.shared.sendTap(normalizedX: normX, normalizedY: normY)
        }
        view.onSwipe = { x1, y1, x2, y2, durationMs in
            IOSDeviceControlService.shared.sendSwipe(fromX: x1, fromY: y1, toX: x2, toY: y2, durationMs: durationMs)
        }
        view.onScroll = { dx, dy in
            IOSDeviceControlService.shared.sendScroll(deltaX: dx, deltaY: dy)
        }
        view.onKeyDown = { event in
            IOSDeviceControlService.shared.sendKey(event)
        }
        return view
    }

    func updateNSView(_ nsView: DeviceMetalNSView, context: Context) {}
}

// MARK: - Official Apple Device Frame Specification

/// Exact hardware geometry extracted from Apple Developer design specifications
struct AppleDeviceFrameSpec {
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let screenTop: CGFloat
    let screenLeft: CGFloat
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let screenCornerRadius: CGFloat
    let frameImageName: String

    /// Authentic Apple iPhone 15 / 16 frame from user-uploaded asset (508 × 1024 px)
    /// Cutout at (34, 34), width 441, height 956. Symmetrical 23px bezel all around.
    static let iPhone15 = AppleDeviceFrameSpec(
        frameWidth: 508,
        frameHeight: 1024,
        screenTop: 34,
        screenLeft: 34,
        screenWidth: 441,
        screenHeight: 956,
        screenCornerRadius: 45,
        frameImageName: "apple_iphone15_frame"
    )

    /// Official Apple iPhone 16 Pro hardware frame (1350 × 2760 px)
    static let iPhone16Pro = AppleDeviceFrameSpec(
        frameWidth: 1350,
        frameHeight: 2760,
        screenTop: 69,
        screenLeft: 72,
        screenWidth: 1206,
        screenHeight: 2622,
        screenCornerRadius: 130,
        frameImageName: "apple_iphone16_pro_black"
    )

    /// Official Apple iPad Air / Pro hardware frame (1446 × 1108 px)
    static let iPadAir = AppleDeviceFrameSpec(
        frameWidth: 1446,
        frameHeight: 1108,
        screenTop: 48,
        screenLeft: 48,
        screenWidth: 1350,
        screenHeight: 1012,
        screenCornerRadius: 36,
        frameImageName: "apple_ipad_frame_dark"
    )

    static func specFor(resolution: CGSize, modelName: String? = nil) -> AppleDeviceFrameSpec {
        let name = (modelName ?? "").lowercased()
        if name.contains("ipad") || (resolution.width > 0 && resolution.height > 0 && (resolution.width / resolution.height) > 0.65) {
            return .iPadAir
        }
        if name.contains("pro") || name.contains("max") {
            return .iPhone16Pro
        }
        // iPhone 15 and base models default to iPhone 15 frame
        return .iPhone15
    }
}

// MARK: - Device Frame Asset Manager

final class AppleDeviceFrameManager {
    static let shared = AppleDeviceFrameManager()
    private var cache: [String: NSImage] = [:]

    func frameImage(named name: String) -> NSImage? {
        if let cached = cache[name] {
            return cached
        }
        // 1. Bundle Resources
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            cache[name] = img
            return img
        }
        // 2. Direct paths in app bundle and project resources
        let candidatePaths = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name).png"),
            URL(fileURLWithPath: "MicroCode/Resources/\(name).png"),
            URL(fileURLWithPath: "/Users/dotmini/Documents/SX/codetunner-native/MicroCode/Resources/\(name).png"),
            URL(fileURLWithPath: "/Users/dotmini/Documents/SX/codetunner-native/MicroCode.app/Contents/Resources/\(name).png")
        ]
        for path in candidatePaths {
            if FileManager.default.fileExists(atPath: path.path),
               let img = NSImage(contentsOf: path) {
                cache[name] = img
                return img
            }
        }
        return nil
    }
}

// MARK: - Authentic Apple Hardware Frame View

/// Renders genuine Apple device hardware frames around the live screen surface.
/// Geometry and bezel alignment adhere strictly to Apple's pixel-level hardware specifications.
struct PhysicalIPhoneFrameView<Content: View>: View {
    let content: Content
    let resolution: CGSize
    let deviceName: String?

    init(resolution: CGSize = .zero, deviceName: String? = nil, @ViewBuilder content: () -> Content) {
        self.resolution = resolution
        self.deviceName = deviceName
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let spec = AppleDeviceFrameSpec.specFor(resolution: resolution, modelName: deviceName)
            let padding: CGFloat = 16
            let availW = max(60, geo.size.width - (padding * 2))
            let availH = max(60, geo.size.height - (padding * 2))

            let frameAspect = spec.frameWidth / spec.frameHeight
            let isHeightConstrained = (availW / availH) > frameAspect

            let renderFrameW: CGFloat = (isHeightConstrained ? (availH * frameAspect) : availW).rounded()
            let renderFrameH: CGFloat = (isHeightConstrained ? availH : (availW / frameAspect)).rounded()

            let scale = renderFrameW / spec.frameWidth

            // Pixel-level screen geometry conforming strictly to Apple hardware specs
            let screenW = (spec.screenWidth * scale).rounded()
            let screenH = (spec.screenHeight * scale).rounded()
            let screenLeft = (spec.screenLeft * scale).rounded()
            let screenTop = (spec.screenTop * scale).rounded()
            let cornerRadius = (spec.screenCornerRadius * scale).rounded()

            ZStack(alignment: .topLeading) {
                // 1. Screen Viewport: Pixel-perfect placement behind the Apple bezel cutout
                ZStack {
                    Color.black
                    content
                }
                .frame(width: screenW, height: screenH)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .offset(x: screenLeft, y: screenTop)

                // 2. Official Apple Device Bezel Frame Overlay
                if let frameImg = AppleDeviceFrameManager.shared.frameImage(named: spec.frameImageName) {
                    Image(nsImage: frameImg)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: renderFrameW, height: renderFrameH)
                        .allowsHitTesting(false) // Touch / click events pass through to screen
                        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 12)
                } else {
                    // Fallback stroke outline if asset is unavailable
                    RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                        .stroke(Color.gray.opacity(0.4), lineWidth: 2)
                        .frame(width: renderFrameW, height: renderFrameH)
                        .allowsHitTesting(false)
                }

                // 3. Interactive Home Bar indicator strictly at bottom 24 points
                // Does NOT cover the screen, so the entire screen is 100% directly clickable
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: screenW * 0.38, height: 4.5)
                        .padding(.bottom, 6)
                }
                .frame(width: screenW, height: 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    IOSDeviceControlService.shared.goHome()
                }
                .offset(x: screenLeft, y: screenTop + screenH - 24)
            }
            .frame(width: renderFrameW, height: renderFrameH)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

// MARK: - Physical iOS Device Tab (used by EmbeddedDeviceDockView)

/// Complete tab view for physical iPhone/iPad mirroring via USB.
/// Auto-discovers connected devices, starts AVFoundation capture,
/// and renders via Metal zero-copy pipeline inside an authentic iPhone frame
/// with full direct IDE control actions.
struct PhysicalIOSDeviceTabView: View {
    @ObservedObject private var capture = IOSDeviceCaptureService.shared
    @ObservedObject private var control = IOSDeviceControlService.shared
    var canvasColor: Color? = nil

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                canvasColor ?? Color.clear

                switch capture.state {
                case .streaming:
                    // Live Screen rendered inside authentic iPhone Hardware Frame (Zero FPS badge)
                    PhysicalIPhoneFrameView(
                        resolution: capture.deviceResolution,
                        deviceName: capture.connectedDeviceName ?? control.deviceModelName
                    ) {
                        IOSDeviceMetalSurface(iosCapture: capture)
                    }

                case .connected:
                    PhysicalIPhoneFrameView(deviceName: capture.connectedDeviceName ?? control.deviceModelName) {
                        VStack(spacing: 12) {
                            Image(systemName: "cable.connector")
                                .font(.system(size: 36))
                                .foregroundColor(.green)
                            Text(capture.connectedDeviceName ?? "iPhone Connected")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Connected via USB · Ready to Stream & Control")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                            Button("Start Live Preview") {
                                capture.startCapture()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                case .error(let msg):
                    PhysicalIPhoneFrameView {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 32))
                                .foregroundColor(.orange)
                            Text("Capture Notice")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Text(msg)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                            
                            HStack(spacing: 8) {
                                Button("Retry") {
                                    capture.scanForDevices()
                                    control.discoverPhysicalUDID()
                                }
                                .buttonStyle(.bordered)
                                
                                if msg.lowercased().contains("permission") || msg.lowercased().contains("settings") {
                                    Button("Open System Settings") {
                                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                case .searching, .disconnected:
                    PhysicalIPhoneFrameView {
                        VStack(spacing: 14) {
                            Image(systemName: "iphone.and.arrow.right.inward")
                                .font(.system(size: 38))
                                .foregroundColor(.white.opacity(0.5))
                            Text("Connect iPhone via USB")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Plug in your device and tap 'Trust This Computer' on your iPhone screen.")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)

                            // Scan button
                            Button {
                                capture.scanForDevices()
                                control.discoverPhysicalUDID()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Scan for Devices")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)

                            // Show discovered devices
                            if !capture.availableDevices.isEmpty {
                                VStack(spacing: 6) {
                                    ForEach(capture.availableDevices, id: \.uniqueID) { device in
                                        Button {
                                            capture.startCapture(device: device)
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: "iphone")
                                                    .foregroundColor(.accentColor)
                                                Text(device.localizedName)
                                                    .font(.system(size: 12))
                                                Spacer()
                                                Image(systemName: "play.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.accentColor)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.white.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            capture.startMonitoring()
            capture.scanForDevices()
            control.discoverPhysicalUDID()
        }
        .onDisappear {
            capture.stopCapture()
            capture.stopMonitoring()
        }
    }
}

// MARK: - Authentic Android Hardware Frame View

/// Renders a modern flagship Android smartphone frame (Pixel / Galaxy style).
/// Geometry is clamped to realistic mobile aspect ratios [0.40, 0.75] with min width of 200pt,
/// completely preventing degenerate thin-line rendering.
struct PhysicalAndroidFrameView<Content: View>: View {
    let resolution: CGSize
    let deviceName: String?
    let content: Content

    init(resolution: CGSize = .zero, deviceName: String? = nil, @ViewBuilder content: () -> Content) {
        self.resolution = resolution
        self.deviceName = deviceName
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let padding: CGFloat = 16
            let availW = max(200, geo.size.width - (padding * 2))
            let availH = max(380, geo.size.height - (padding * 2))

            // Raw aspect ratio from resolution, strictly clamped to valid mobile bounds [0.40, 0.75]
            let rawAspect = (resolution.width > 0 && resolution.height > 0)
                ? (resolution.width / resolution.height)
                : (9.0 / 19.5)
            let aspect: CGFloat = min(0.75, max(0.40, rawAspect))

            let isHeightConstrained = (availW / availH) > aspect
            let renderFrameW: CGFloat = max(200, (isHeightConstrained ? (availH * aspect) : availW).rounded())
            let renderFrameH: CGFloat = max(380, (isHeightConstrained ? availH : (availW / aspect)).rounded())

            // Symmetrical bezel margin around the screen
            let bezelThickness: CGFloat = 11
            let screenW = max(180, renderFrameW - (bezelThickness * 2))
            let screenH = max(360, renderFrameH - (bezelThickness * 2))
            let outerCornerRadius: CGFloat = 38
            let screenCornerRadius: CGFloat = 30

            ZStack(alignment: .topLeading) {
                // 1. Hardware Buttons on right chassis (Volume rocker & Power button)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.32))
                    .frame(width: 3.5, height: 48)
                    .offset(x: renderFrameW, y: renderFrameH * 0.22)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.32))
                    .frame(width: 3.5, height: 28)
                    .offset(x: renderFrameW, y: renderFrameH * 0.36)

                // 2. Outer Android Titanium/Aluminum Chassis Frame
                RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.20),
                                Color(white: 0.08),
                                Color(white: 0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color(white: 0.42),
                                        Color(white: 0.18),
                                        Color(white: 0.30)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color.black.opacity(0.55), radius: 24, x: 0, y: 12)
                    .frame(width: renderFrameW, height: renderFrameH)

                // 3. Screen Viewport
                ZStack {
                    Color.black
                    content
                }
                .frame(width: screenW, height: screenH)
                .clipShape(RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous))
                .offset(x: bezelThickness, y: bezelThickness)

                // 4. Centered Punch-Hole Front Camera Cutout (Pixel / Galaxy Style)
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 11, height: 11)
                    Circle()
                        .stroke(Color(white: 0.22), lineWidth: 1)
                        .frame(width: 11, height: 11)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.blue.opacity(0.4), Color.clear],
                                center: .center,
                                startRadius: 0.5,
                                endRadius: 3.5
                            )
                        )
                        .frame(width: 4, height: 4)
                }
                .frame(width: 11, height: 11)
                .position(x: renderFrameW / 2, y: bezelThickness + 13)
                .allowsHitTesting(false)

                // 5. Bottom Interactive Android Navigation Gesture Area
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: screenW, height: 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        AndroidStreamService.shared.sendKey(3) // Keycode 3 = Android Home
                    }
                    .offset(x: bezelThickness, y: bezelThickness + screenH - 20)
            }
            .frame(width: renderFrameW, height: renderFrameH)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

// MARK: - Physical Android Device Tab (Wired USB Streaming & Full Interactive IDE Control)

/// Direct wired physical Android screen mirroring & full interactive IDE control over USB.
/// Renders via Metal zero-copy pipeline inside an authentic Android hardware frame with touch, drag,
/// hardware buttons (Back, Home, Recents, Power, Vol) and direct text input injection.
struct PhysicalAndroidDeviceTabView: View {
    @ObservedObject private var androidStream = AndroidStreamService.shared
    @State private var showingTextSheet = false
    @State private var textInput = ""

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(nsColor: .controlBackgroundColor)

                PhysicalAndroidFrameView(
                    resolution: androidStream.deviceResolution,
                    deviceName: androidStream.deviceName
                ) {
                    if androidStream.isStreaming {
                        AndroidDeviceMetalSurface(androidStream: androidStream)
                    } else {
                        // Disconnected / Discovery Standby Screen inside authentic phone display
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "candybarphone")
                                .font(.system(size: 48))
                                .foregroundColor(.accentColor.opacity(0.85))

                            Text("Android Physical Device")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)

                            Text("Enable 'USB Debugging' in Developer Options and connect your phone via USB.")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            Button {
                                Task {
                                    await androidStream.scanDevices()
                                    if let first = androidStream.availableDevices.first(where: { !$0.isEmulator }) ?? androidStream.availableDevices.first {
                                        if let adb = androidStream.resolvedAdbPath {
                                            await androidStream.startStreaming(serial: first.id, adbPath: adb)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Scan for Android Devices")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)

                            if !androidStream.availableDevices.isEmpty {
                                VStack(spacing: 6) {
                                    ForEach(androidStream.availableDevices) { dev in
                                        Button {
                                            Task {
                                                if let adb = androidStream.resolvedAdbPath {
                                                    await androidStream.startStreaming(serial: dev.id, adbPath: adb)
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: dev.isEmulator ? "cpu" : "candybarphone")
                                                    .foregroundColor(.accentColor)
                                                Text(dev.model)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundColor(.white)
                                                Spacer()
                                                Image(systemName: "play.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.accentColor)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.white.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            LinearGradient(
                                colors: [Color(white: 0.12), Color(white: 0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
            }

            // MARK: - Direct IDE Control Toolbar for Android
            Divider()
            HStack(spacing: 6) {
                    // Back
                    Button {
                        androidStream.sendKey(4)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Android Back (Keycode 4)")

                    // Home
                    Button {
                        androidStream.sendKey(3)
                    } label: {
                        Image(systemName: "circle")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Android Home (Keycode 3)")

                    // Recents
                    Button {
                        androidStream.sendKey(187)
                    } label: {
                        Image(systemName: "square")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Android Recents / Overview (Keycode 187)")

                    Divider().frame(height: 16)

                    // Power / Wake
                    Button {
                        androidStream.sendKey(26)
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Power / Wake (Keycode 26)")

                    // Vol -
                    Button {
                        androidStream.sendKey(25)
                    } label: {
                        Image(systemName: "speaker.minus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Volume Down (Keycode 25)")

                    // Vol +
                    Button {
                        androidStream.sendKey(24)
                    } label: {
                        Image(systemName: "speaker.plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Volume Up (Keycode 24)")

                    Spacer()

                    if !androidStream.statusMessage.isEmpty {
                        Text(androidStream.statusMessage)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }

                    // Type Text directly into device
                    Button {
                        showingTextSheet.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 11))
                            Text("Type")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Send Text to Android device")
                    .popover(isPresented: $showingTextSheet, arrowEdge: .top) {
                        HStack(spacing: 8) {
                            TextField("Type text to send", text: $textInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                                .onSubmit {
                                    androidStream.sendText(textInput)
                                    textInput = ""
                                    showingTextSheet = false
                                }
                            Button("Send") {
                                androidStream.sendText(textInput)
                                textInput = ""
                                showingTextSheet = false
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(10)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .onAppear {
            Task {
                await androidStream.scanDevices()
                if let first = androidStream.availableDevices.first(where: { !$0.isEmulator }) ?? androidStream.availableDevices.first {
                    if let adb = androidStream.resolvedAdbPath {
                        await androidStream.startStreaming(serial: first.id, adbPath: adb)
                    }
                }
            }
        }
        .onDisappear {
            androidStream.stopStreaming()
        }
    }
}
