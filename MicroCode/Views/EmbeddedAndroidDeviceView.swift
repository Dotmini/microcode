//
//  EmbeddedAndroidDeviceView.swift
//  MicroCode
//
//  A native in-app surface for a real Android Emulator/ADB device.
//

import SwiftUI
import AppKit

struct EmbeddedAndroidDeviceView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var runtime: DeviceRuntimeService
    @ObservedObject private var streamService = AndroidStreamService.shared
    var canvasColor: Color? = nil
    var onConfigure: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil
    @State private var textToSend = ""
    @State private var showingTextInput = false

    private var effectiveCanvasColor: Color {
        if let canvasColor {
            return canvasColor
        }
        return appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.editorBackground)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Background follows our theme perfectly (black/dark/light)
                effectiveCanvasColor

                AndroidDeviceSurface(
                    image: runtime.embeddedAndroidImage,
                    officialFrame: runtime.embeddedAndroidFrame ?? DeviceFrameAssets.loadAndroidDeviceBezel(for: runtime.selectedAndroidSkin),
                    officialMask: runtime.embeddedAndroidMask ?? DeviceFrameAssets.loadAndroidDeviceMask(for: runtime.selectedAndroidSkin),
                    availableSize: proxy.size,
                    runtime: runtime,
                    streamService: streamService
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(effectiveCanvasColor)
        .onAppear {
            if (!streamService.isStreaming && runtime.embeddedAndroidImage == nil) ||
               (streamService.isStreaming && !streamService.hasReceivedFirstFrame && streamService.latestPixelBuffer == nil) {
                Task {
                    await runtime.startPreferredEmbeddedAndroid()
                }
            }
        }
    }
}

/// A native device host for the real Android display with 60 FPS Metal GPU acceleration.
/// Measurements are dynamically adapted to the selected hardware skin (Samsung Galaxy Note 20 Ultra or Pixel 9 Pro),
/// keeping the display flush and authentic with chassis, camera punch hole, and buttons.
private struct AndroidDeviceSurface: View {
    let image: NSImage?
    let officialFrame: NSImage?
    let officialMask: NSImage?
    let availableSize: CGSize
    @ObservedObject var runtime: DeviceRuntimeService
    @ObservedObject var streamService: AndroidStreamService

    private var skin: AndroidDeviceSkin {
        runtime.selectedAndroidSkin
    }

    private var bodyWidth: CGFloat { skin.outerSize.width }
    private var bodyHeight: CGFloat { skin.outerSize.height }
    private var screenWidth: CGFloat { skin.displayRect.width }
    private var screenHeight: CGFloat { skin.displayRect.height }
    private var screenX: CGFloat { skin.displayRect.origin.x }
    private var screenY: CGFloat { skin.displayRect.origin.y }
    private var cornerRadius: CGFloat { skin.cornerRadius }

    var body: some View {
        let frameAspect = bodyWidth / bodyHeight
        let usableWidth = max(availableSize.width - 32, 120)
        let usableHeight = max(availableSize.height - 24, 160)
        let frameHeight = min(usableHeight, usableWidth / frameAspect)
        let frameWidth = frameHeight * frameAspect
        let displayWidth = frameWidth * screenWidth / bodyWidth
        let displayHeight = frameHeight * screenHeight / bodyHeight
        let screenOffset = CGSize(
            width: frameWidth * ((screenX + screenWidth / 2) / bodyWidth - 0.5),
            height: frameHeight * ((screenY + screenHeight / 2) / bodyHeight - 0.5)
        )
        let screenCorner = max(displayWidth * cornerRadius / screenWidth, 4)

        ZStack {
            // 1. Screen Viewport (Display) - 60 FPS Metal GPU or fallback screencap
            ZStack {
                Color.black
                if streamService.isStreaming && (streamService.hasReceivedFirstFrame || streamService.latestPixelBuffer != nil) {
                    AndroidDeviceMetalSurface(androidStream: streamService)
                        .frame(width: displayWidth, height: displayHeight)
                } else if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: displayWidth, height: displayHeight)
                } else if streamService.isStreaming {
                    AndroidDeviceMetalSurface(androidStream: streamService)
                        .frame(width: displayWidth, height: displayHeight)
                } else {
                    VStack(spacing: 12) {
                        let status = runtime.embeddedAndroidStatus
                        let isError = status.contains("stopped") ||
                                      status.contains("offline") ||
                                      status.contains("failed") ||
                                      status.contains("No Android") ||
                                      status.contains("unresponsive") ||
                                      status.contains("unavailable")
                        if isError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.orange)
                        } else {
                            ProgressView()
                                .controlSize(.regular)
                        }
                        
                        Text(status.isEmpty ? "Connecting to Android Emulator…" : status)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)

                        Button {
                            Task {
                                await runtime.startPreferredEmbeddedAndroid()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise")
                                Text("Attach / Retry")
                            }
                            .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 4)
                    }
                    .padding(16)
                }
            }
            .frame(width: displayWidth, height: displayHeight)
            .clipShape(RoundedRectangle(cornerRadius: screenCorner, style: .continuous))
            .offset(screenOffset)

            // 2. Official Punch-Hole Camera Cutout (Mask)
            if let officialMask {
                Image(nsImage: officialMask)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: displayWidth, height: displayHeight)
                    .clipShape(RoundedRectangle(cornerRadius: screenCorner, style: .continuous))
                    .offset(screenOffset)
                    .allowsHitTesting(false)
            } else {
                // Centered punch-hole camera hardware cutout fallback
                Circle()
                    .fill(Color.black)
                    .frame(width: max(8, displayWidth * 0.038), height: max(8, displayWidth * 0.038))
                    .overlay(
                        Circle()
                            .stroke(Color(white: 0.18), lineWidth: 0.8)
                    )
                    .offset(x: screenOffset.width, y: screenOffset.height - displayHeight / 2 + displayHeight * 0.024)
                    .allowsHitTesting(false)
            }

            // 3. AppKit Input Interaction Overlay (active for fallback screencap)
            if !streamService.isStreaming && image != nil {
                AndroidDeviceInputOverlay(runtime: runtime)
                    .frame(width: displayWidth, height: displayHeight)
                    .offset(screenOffset)
                    .clipShape(RoundedRectangle(cornerRadius: screenCorner, style: .continuous))
            }

            // 4. Genuine Hardware Chassis & Bezel Frame (Always Real, Never Missing)
            if let frame = officialFrame ?? DeviceFrameAssets.loadAndroidDeviceBezel(for: runtime.selectedAndroidSkin) {
                Image(nsImage: frame)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: frameWidth, height: frameHeight)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: frameWidth, height: frameHeight)
        .shadow(color: .black.opacity(0.40), radius: 18, x: 0, y: 8)
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
