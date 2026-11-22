//
//  AIStreamingThreeDotsView.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2024 Dotmini Company Limited. All rights reserved.
//

import SwiftUI
import AppKit
import QuartzCore

// MARK: - 3-Dot Wave Indicator (Core Animation driven)

/// Three-dot wave shown in the chat transcript while the agent is streaming or running tools.
///
/// Performance contract: the wave runs entirely in Core Animation (the render server), so it never
/// asks SwiftUI for per-frame updates. It used to be a `TimelineView(.animation)`; because it sits
/// inside the transcript `ScrollView`/`LazyVStack`, every display frame (~120 Hz on ProMotion) ran a full
/// `NSHostingView.layout()` that re-measured the whole transcript and redrew its text. During long agent
/// runs that saturated the main thread, and it kept going after the window was ordered out
/// (2026-11-18). Being layer-driven also keeps it animating inside `.equatable()` rows, which never
/// re-render while the agent works.
/// Regression: Scripts/tests/run-streaming-indicator-idle.sh
struct AIStreamingThreeDotsView: View {
    var dotSize: CGFloat = 6
    var spacing: CGFloat = 5

    var body: some View {
        AIStreamingThreeDotsLayerView(dotSize: dotSize, spacing: spacing)
            .frame(
                width: AIStreamingThreeDotsWave.contentWidth(dotSize: dotSize, spacing: spacing),
                height: AIStreamingThreeDotsWave.contentHeight(dotSize: dotSize)
            )
    }
}

/// The wave the indicator has always drawn: dot `i` follows phase `t * 4.6 - i * 0.72`.
enum AIStreamingThreeDotsWave {
    static let angularSpeed: Double = 4.6
    static let phaseStepBetweenDots: Double = 0.72
    static let keyframesPerPeriod = 48

    static var period: CFTimeInterval { 2.0 * Double.pi / angularSpeed }

    struct Sample: Equatable {
        let scale: Double
        let opacity: Double
        /// Upward displacement in points (0 ... 2.2).
        let lift: Double
    }

    static func sample(phase: Double) -> Sample {
        let s = sin(phase)
        let wave = (s + 1.0) * 0.5 // 0.0 ... 1.0
        return Sample(scale: 0.72 + (0.36 * wave), opacity: 0.25 + (0.75 * wave), lift: 2.2 * max(0.0, s))
    }

    /// Animation-local time offset that delays dot `index` by its phase step, kept in `[0, period)`.
    static func timeOffset(forDot index: Int) -> CFTimeInterval {
        let delay = (phaseStepBetweenDots * Double(index)) / angularSpeed
        let wrapped = (period - delay).truncatingRemainder(dividingBy: period)
        return wrapped < 0 ? wrapped + period : wrapped
    }

    /// One period of samples starting at phase 0; the last keyframe repeats the first for a seamless loop.
    static func keyframes() -> [Sample] {
        (0...keyframesPerPeriod).map { k in
            sample(phase: 2.0 * Double.pi * Double(k) / Double(keyframesPerPeriod))
        }
    }

    static func contentWidth(dotSize: CGFloat, spacing: CGFloat) -> CGFloat {
        dotSize * 3 + spacing * 2
    }

    static func contentHeight(dotSize: CGFloat) -> CGFloat {
        dotSize + 6
    }
}

struct AIStreamingThreeDotsLayerView: NSViewRepresentable {
    var dotSize: CGFloat
    var spacing: CGFloat

    func makeNSView(context: Context) -> AIStreamingThreeDotsNSView {
        AIStreamingThreeDotsNSView(dotSize: dotSize, spacing: spacing)
    }

    func updateNSView(_ nsView: AIStreamingThreeDotsNSView, context: Context) {
        nsView.configure(dotSize: dotSize, spacing: spacing)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AIStreamingThreeDotsNSView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

final class AIStreamingThreeDotsNSView: NSView {
    static let animationKeys = ["microcode.wave.transform", "microcode.wave.opacity"]

    private(set) var dotSize: CGFloat
    private(set) var spacing: CGFloat
    private(set) var dotLayers: [CALayer] = []
    private var installedLiftSign: CGFloat?
    private var colorObserver: NSObjectProtocol?

    init(dotSize: CGFloat, spacing: CGFloat) {
        self.dotSize = dotSize
        self.spacing = spacing
        super.init(frame: NSRect(
            x: 0, y: 0,
            width: AIStreamingThreeDotsWave.contentWidth(dotSize: dotSize, spacing: spacing),
            height: AIStreamingThreeDotsWave.contentHeight(dotSize: dotSize)
        ))
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        if #available(macOS 14.0, *) {
            clipsToBounds = false
        }
        layer?.masksToBounds = false
        for _ in 0..<3 {
            let dot = CALayer()
            dot.actions = ["position": NSNull(), "bounds": NSNull(), "cornerRadius": NSNull(), "backgroundColor": NSNull()]
            layer?.addSublayer(dot)
            dotLayers.append(dot)
        }
        updateDotColors()
        colorObserver = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDotColors() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let colorObserver {
            NotificationCenter.default.removeObserver(colorObserver)
        }
    }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: AIStreamingThreeDotsWave.contentWidth(dotSize: dotSize, spacing: spacing),
            height: AIStreamingThreeDotsWave.contentHeight(dotSize: dotSize)
        )
    }

    func configure(dotSize: CGFloat, spacing: CGFloat) {
        guard dotSize != self.dotSize || spacing != self.spacing else { return }
        self.dotSize = dotSize
        self.spacing = spacing
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let midY = bounds.midY
        for (index, dot) in dotLayers.enumerated() {
            dot.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
            dot.cornerRadius = dotSize / 2
            dot.position = CGPoint(x: CGFloat(index) * (dotSize + spacing) + dotSize / 2, y: midY)
        }
        installAnimationsIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // AppKit can drop layer animations while a view is out of a window (e.g. LazyVStack reuse).
        installedLiftSign = nil
        installAnimationsIfNeeded()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDotColors()
    }

    private func updateDotColors() {
        var accent: CGColor = NSColor.controlAccentColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            accent = NSColor.controlAccentColor.cgColor
        }
        for dot in dotLayers {
            dot.backgroundColor = accent
        }
    }

    private func installAnimationsIfNeeded() {
        guard let hostLayer = layer else { return }
        // Lift is "up" on screen: negative y when this layer's sublayer space is flipped (y-down).
        let liftSign: CGFloat = hostLayer.contentsAreFlipped() ? -1 : 1
        let allPresent = dotLayers.allSatisfy { dot in
            Self.animationKeys.allSatisfy { dot.animation(forKey: $0) != nil }
        }
        if installedLiftSign == liftSign && allPresent { return }
        installedLiftSign = liftSign

        let samples = AIStreamingThreeDotsWave.keyframes()
        let transforms = samples.map { sample -> NSValue in
            let scaled = CATransform3DMakeScale(CGFloat(sample.scale), CGFloat(sample.scale), 1)
            let lifted = CATransform3DConcat(scaled, CATransform3DMakeTranslation(0, liftSign * CGFloat(sample.lift), 0))
            return NSValue(caTransform3D: lifted)
        }
        let opacities = samples.map { NSNumber(value: $0.opacity) }

        for (index, dot) in dotLayers.enumerated() {
            let offset = AIStreamingThreeDotsWave.timeOffset(forDot: index)
            let resting = AIStreamingThreeDotsWave.sample(phase: -AIStreamingThreeDotsWave.phaseStepBetweenDots * Double(index))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dot.opacity = Float(resting.opacity)
            dot.add(Self.loop(keyPath: "transform", values: transforms, timeOffset: offset), forKey: Self.animationKeys[0])
            dot.add(Self.loop(keyPath: "opacity", values: opacities, timeOffset: offset), forKey: Self.animationKeys[1])
            CATransaction.commit()
        }
    }

    private static func loop(keyPath: String, values: [Any], timeOffset: CFTimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.calculationMode = .linear
        animation.duration = AIStreamingThreeDotsWave.period
        animation.repeatCount = .infinity
        animation.timeOffset = timeOffset
        animation.isRemovedOnCompletion = false
        return animation
    }
}
