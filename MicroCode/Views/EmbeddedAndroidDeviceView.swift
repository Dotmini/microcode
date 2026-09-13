//
//  EmbeddedAndroidDeviceView.swift
//  MicroCode
//
//  A native in-app surface for a real Android Emulator/ADB device.
//

import SwiftUI
import AppKit

struct EmbeddedAndroidDeviceView: View {
    @ObservedObject var runtime: DeviceRuntimeService
    var canvasColor: Color = Color(nsColor: .windowBackgroundColor)
    var onConfigure: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil
    @State private var textToSend = ""
    @State private var showingTextInput = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // This is the same canvas that owns the rest of the dock.
                // The real AVD screen is only the screen; Android's desktop
                // window must not leak its black letterbox into MicroCode.
                canvasColor
                if let image = runtime.embeddedAndroidImage {
                    AndroidDeviceSurface(
                        image: image,
                        officialFrame: runtime.embeddedAndroidFrame,
                        availableSize: proxy.size,
                        runtime: runtime
                    )
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.regular)
                        Text(runtime.embeddedAndroidStatus.isEmpty ? "Connecting to Android Emulator…" : runtime.embeddedAndroidStatus)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        
                        Button {
                            Task {
                                await runtime.startPreferredEmbeddedAndroid()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("Attach / Retry Connection")
                            }
                            .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
        }
        .background(canvasColor)
        .onAppear {
            if runtime.embeddedAndroidImage == nil {
                Task {
                    await runtime.startPreferredEmbeddedAndroid()
                }
            }
        }
    }
}

/// A native device host for the *real* ADB screen capture.  Its measurements
/// match the installed Pixel 9 Pro Android skin: 1408 x 2974 outer frame with
/// the 1280 x 2856 display inset at x:60, y:61.  This keeps the result flush
/// and device-like instead of centering a naked screenshot in a black panel.
private struct AndroidDeviceSurface: View {
    let image: NSImage
    let officialFrame: NSImage?
    let availableSize: CGSize
    @ObservedObject var runtime: DeviceRuntimeService

    private let bodyWidth: CGFloat = 1408
    private let bodyHeight: CGFloat = 2974
    private let screenWidth: CGFloat = 1280
    private let screenHeight: CGFloat = 2856
    private let screenX: CGFloat = 60
    private let screenY: CGFloat = 61

    var body: some View {
        let frameAspect = officialFrame != nil ? (bodyWidth / bodyHeight) : (image.size.width / max(image.size.height, 1))
        let usableWidth = max(availableSize.width - 36, 120)
        let usableHeight = max(availableSize.height - 28, 160)
        let frameHeight = min(usableHeight, usableWidth / frameAspect)
        let frameWidth = frameHeight * frameAspect
        let displayWidth = officialFrame != nil ? (frameWidth * screenWidth / bodyWidth) : frameWidth
        let displayHeight = officialFrame != nil ? (frameHeight * screenHeight / bodyHeight) : frameHeight
        let screenOffset = officialFrame != nil ? CGSize(
            width: frameWidth * ((screenX + screenWidth / 2) / bodyWidth - 0.5),
            height: frameHeight * ((screenY + screenHeight / 2) / bodyHeight - 0.5)
        ) : .zero
        // The official Pixel 9 Pro skin declares a 109 px display radius in
        // a 1,280 px display. This clips only the live screen; the physical
        // chassis itself comes from Android SDK's official `back.webp` asset.
        let screenCorner = max(displayWidth * 109 / (officialFrame != nil ? screenWidth : displayWidth), 12)

        ZStack {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: displayWidth, height: displayHeight)
                .clipShape(RoundedRectangle(cornerRadius: screenCorner, style: .continuous))
                .offset(screenOffset)

            // AppKit receives the focused Mac keyboard plus continuous mouse
            // wheel/trackpad events. SwiftUI DragGesture only fires the old
            // implementation's swipe after the user has lifted their finger.
            AndroidDeviceInputOverlay(runtime: runtime)
                .frame(width: displayWidth, height: displayHeight)
                .offset(screenOffset)
                .clipShape(RoundedRectangle(cornerRadius: screenCorner, style: .continuous))

            if let officialFrame {
                Image(nsImage: officialFrame)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: frameWidth, height: frameHeight)
                    .allowsHitTesting(false)
            } else {
                // A physical device may not expose an SDK skin. Keep the
                // fallback neutral, but never use it for a configured AVD.
                RoundedRectangle(cornerRadius: screenCorner, style: .continuous)
                    .stroke(Color.primary.opacity(0.22), lineWidth: 1)
                    .allowsHitTesting(false)
            }

        }
        .frame(width: frameWidth, height: frameHeight)
        .shadow(color: .black.opacity(officialFrame == nil ? 0.16 : 0.10), radius: 8, y: 3)
    }

}

/// Focused, transparent AppKit input surface for the real Android display.
/// A click focuses it; all subsequent ordinary Mac keystrokes, arrows,
/// backspace, return, Escape and trackpad scroll are sent to that AVD only.
private struct AndroidDeviceInputOverlay: NSViewRepresentable {
    @ObservedObject var runtime: DeviceRuntimeService

    func makeNSView(context: Context) -> AndroidDeviceInputNSView {
        let view = AndroidDeviceInputNSView()
        view.runtime = runtime
        return view
    }

    func updateNSView(_ nsView: AndroidDeviceInputNSView, context: Context) {
        nsView.runtime = runtime
    }
}

private final class AndroidDeviceInputNSView: NSView {
    weak var runtime: DeviceRuntimeService?
    private var dragStart: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStart = normalized(event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        guard let runtime, let start = dragStart, let end = normalized(event) else { return }
        if hypot(end.x - start.x, end.y - start.y) < 0.012 {
            runtime.sendEmbeddedAndroidTap(normalizedX: end.x, normalizedY: end.y)
        } else {
            runtime.sendEmbeddedAndroidSwipe(from: start, to: end)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        window?.makeFirstResponder(self)
        runtime?.sendEmbeddedAndroidScroll(deltaY: event.scrollingDeltaY)
    }

    override func keyDown(with event: NSEvent) {
        // Preserve IDE command/control shortcuts; only ordinary typing is
        // redirected once the user has explicitly focused the device surface.
        if event.modifierFlags.intersection([.command, .control]).isEmpty {
            switch event.keyCode {
            case 36: runtime?.sendEmbeddedAndroidKey("66")   // Return
            case 48: runtime?.sendEmbeddedAndroidKey("61")   // Tab
            case 51: runtime?.sendEmbeddedAndroidKey("67")   // Delete
            case 53: runtime?.sendEmbeddedAndroidKey("4")    // Escape / Back
            case 123: runtime?.sendEmbeddedAndroidKey("21")  // Left
            case 124: runtime?.sendEmbeddedAndroidKey("22")  // Right
            case 125: runtime?.sendEmbeddedAndroidKey("20")  // Down
            case 126: runtime?.sendEmbeddedAndroidKey("19")  // Up
            default:
                if let characters = event.characters, !characters.isEmpty {
                    runtime?.sendEmbeddedAndroidText(characters)
                }
            }
            return
        }
        super.keyDown(with: event)
    }

    private func normalized(_ event: NSEvent) -> CGPoint? {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let x = point.x / bounds.width
        // AppKit's origin is bottom-left; Android's display is top-left.
        let y = 1 - point.y / bounds.height
        guard (0...1).contains(x), (0...1).contains(y) else { return nil }
        return CGPoint(x: x, y: y)
    }
}
