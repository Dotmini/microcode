import SwiftUI
import AppKit

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var appearanceName: NSAppearance.Name? = nil

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        if let appearanceName {
            visualEffectView.appearance = NSAppearance(named: appearanceName)
        }
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        if let appearanceName {
            visualEffectView.appearance = NSAppearance(named: appearanceName)
        } else {
            visualEffectView.appearance = nil
        }
    }
}

/// Single-NSView Obsidian Glass surface for the left workspace sidebar.
/// Keeps the behind-window `NSVisualEffectView` and its jet-black obsidian veil inside the exact
/// same layer-backed AppKit `NSView` (`masksToBounds = true`), making white backdrop flashes
/// during sidebar open/close animations physically impossible.
private struct ObsidianSidebarGlassRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> ObsidianSidebarGlassNSView {
        ObsidianSidebarGlassNSView()
    }

    func updateNSView(_ nsView: ObsidianSidebarGlassNSView, context: Context) {}

    final class ObsidianSidebarGlassNSView: NSView {
        private let effectView = NSVisualEffectView()
        private let veilView = NSView()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = true
            layer?.backgroundColor = NSColor(calibratedRed: 0.005, green: 0.006, blue: 0.010, alpha: 1.0).cgColor

            effectView.material = .underWindowBackground
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.appearance = NSAppearance(named: .darkAqua)
            effectView.autoresizingMask = [.width, .height]
            effectView.frame = bounds
            addSubview(effectView)

            veilView.wantsLayer = true
            veilView.layer?.backgroundColor = NSColor(calibratedRed: 0.006, green: 0.007, blue: 0.012, alpha: 0.94).cgColor
            veilView.autoresizingMask = [.width, .height]
            veilView.frame = bounds
            addSubview(veilView)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

struct SidebarDarkGlassBackground: View {
    var body: some View {
        ObsidianSidebarGlassRepresentable()
            .ignoresSafeArea(.container, edges: .vertical)
    }
}

struct SidebarAdaptiveBackground: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.appTheme.usesDarkGlassSidebar {
            SidebarDarkGlassBackground()
        } else if appState.appTheme.isGlass {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea(.container, edges: .vertical)
        } else {
            Color(nsColor: appState.appTheme.panelBackground)
                .ignoresSafeArea(.container, edges: .vertical)
        }
    }
}
