import AppKit
import SwiftUI
import QuartzCore

// Regression: the agent "working" 3-dot indicator must not drive per-frame SwiftUI updates.
//
// 2026-11-18: AIStreamingThreeDotsView was a TimelineView(.animation). Inside the chat transcript
// ScrollView it made NSHostingView.layout() run every display frame (~120/s), re-measuring the whole
// transcript LazyVStack and redrawing its text; the main thread saturated during long agent runs and
// kept spinning after the window was ordered out.
//
// Compiled with the real MicroCode/Views/AI/AIStreamingThreeDotsView.swift by run-streaming-indicator-idle.sh.
// Needs a logged-in GUI session (it opens a small window for a few seconds).

final class CountingHostingView<Content: View>: NSHostingView<Content> {
    static var layouts: Int { get { layoutCounter } set { layoutCounter = newValue } }
    override func layout() {
        layoutCounter += 1
        super.layout()
    }
}
nonisolated(unsafe) private var layoutCounter = 0

private struct Transcript: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                ForEach(0..<10, id: \.self) { index in
                    Text("Ran tool step \(index): read_file Sources/App/Feature\(index).swift (exit 0, 1.2s)")
                        .font(.system(size: 12.5))
                }
                HStack(spacing: 7) {
                    AIStreamingThreeDotsView(dotSize: 5, spacing: 4)
                    Text("Working…")
                }
                AIStreamingThreeDotsView()
            }
            .padding(12)
        }
    }
}

private func check(_ condition: Bool, _ message: String) {
    if !condition {
        print("STREAMING INDICATOR IDLE REGRESSION: FAIL — \(message)")
        exit(1)
    }
}

private func findDotViews(in view: NSView) -> [AIStreamingThreeDotsNSView] {
    var found: [AIStreamingThreeDotsNSView] = []
    if let dots = view as? AIStreamingThreeDotsNSView { found.append(dots) }
    for subview in view.subviews { found += findDotViews(in: subview) }
    return found
}

private func checkWaveMatchesOriginalFormula() {
    // The original TimelineView body, for dot `i` at time `t`.
    func original(_ t: Double, _ i: Int) -> (scale: Double, opacity: Double, lift: Double) {
        let phase = t * 4.6 - Double(i) * 0.72
        let wave = (sin(phase) + 1.0) * 0.5
        return (0.72 + 0.36 * wave, 0.25 + 0.75 * wave, 2.2 * max(0.0, sin(phase)))
    }
    let period = AIStreamingThreeDotsWave.period
    for i in 0..<3 {
        for step in 0..<40 {
            let t = Double(step) * 0.037
            // Core Animation evaluates the loop at local time `t + timeOffset`.
            let local = (t + AIStreamingThreeDotsWave.timeOffset(forDot: i)).truncatingRemainder(dividingBy: period)
            let sample = AIStreamingThreeDotsWave.sample(phase: 2.0 * Double.pi * local / period)
            let expected = original(t, i)
            check(abs(sample.scale - expected.scale) < 1e-9 && abs(sample.opacity - expected.opacity) < 1e-9
                  && abs(sample.lift - expected.lift) < 1e-9, "wave for dot \(i) at t=\(t) diverges from the original formula")
        }
    }
    let frames = AIStreamingThreeDotsWave.keyframes()
    check(frames.count == AIStreamingThreeDotsWave.keyframesPerPeriod + 1, "keyframe count")
    check(abs(frames.first!.opacity - frames.last!.opacity) < 1e-9 && abs(frames.first!.scale - frames.last!.scale) < 1e-9,
          "keyframe loop is not seamless")
}

@MainActor private final class Runner: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var host: CountingHostingView<Transcript>!

    func applicationDidFinishLaunching(_ notification: Notification) {
        checkWaveMatchesOriginalFormula()

        host = CountingHostingView(rootView: Transcript())
        window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 640, height: 420),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "streaming-indicator-idle-regression"
        window.contentView = host
        window.orderFrontRegardless()

        after(1.0) { self.checkAnimationIsLive() }
    }

    func checkAnimationIsLive() {
        let dotViews = findDotViews(in: host)
        check(dotViews.count == 2, "expected 2 indicator views in the transcript, found \(dotViews.count)")
        for view in dotViews {
            for dot in view.dotLayers {
                for key in AIStreamingThreeDotsNSView.animationKeys {
                    check(dot.animation(forKey: key) != nil, "dot is missing Core Animation loop '\(key)'")
                }
            }
        }
        let probe = dotViews[0].dotLayers[0]
        let first = probe.presentation()?.opacity ?? -1
        after(0.31) {
            let second = probe.presentation()?.opacity ?? -1
            check(first >= 0 && second >= 0 && abs(first - second) > 0.01,
                  "indicator is frozen (presentation opacity \(first) -> \(second))")
            self.measure(label: "visible") {
                self.window.orderOut(nil)
                self.measure(label: "hidden") {
                    print("STREAMING INDICATOR IDLE REGRESSION: PASS")
                    exit(0)
                }
            }
        }
    }

    /// Before the fix this was ~120 layouts/s in both states; idle SwiftUI does none.
    func measure(label: String, then next: @escaping () -> Void) {
        after(0.5) {
            let start = CountingHostingView<Transcript>.layouts
            let began = Date()
            self.after(2.0) {
                let perSecond = Double(CountingHostingView<Transcript>.layouts - start) / Date().timeIntervalSince(began)
                print(String(format: "  %@: %.1f NSHostingView layouts/s", label, perSecond))
                check(perSecond < 5, "indicator drives per-frame SwiftUI layout while \(label) (\(perSecond)/s)")
                next()
            }
        }
    }

    func after(_ seconds: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { body() } }
    }
}

@main struct StreamingIndicatorIdleRegression {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let runner = Runner()
        app.delegate = runner
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            print("STREAMING INDICATOR IDLE REGRESSION: FAIL — timed out")
            exit(1)
        }
        withExtendedLifetime(runner) { app.run() }
    }
}
