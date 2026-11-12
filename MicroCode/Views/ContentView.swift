//
//  ContentView.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2024 Dotmini Company Limited. All rights reserved.
//

import SwiftUI
import AppKit
import Combine
import QuartzCore

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var isWorkspaceMounted: Bool = true
    @State private var windowAuxiliaryReady: Bool = false
    @State private var deferredOverlaysReady: Bool = false
    // File-based flag survives app re-signing / dev rebuilds (unlike @AppStorage)
    @State private var welcomeCompleted: Bool = {
        let flag = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MicroCode/.welcome_done")
        return FileManager.default.fileExists(atPath: flag.path)
    }()

    var body: some View {
        ZStack {
            if isWorkspaceMounted {
                AgenticEditorWorkspace()
                    .environmentObject(appState)
                    .ignoresSafeArea(.all, edges: .top)
                    .overlay(autoHealerOverlay)
                    .overlay(welcomeOverlay)
                    .background {
                        if windowAuxiliaryReady {
                            Color.clear
                                .modifier(PrimarySheetsModifier(appState: appState))
                                .modifier(SecondarySheetsModifier(appState: appState))
                                .modifier(StudioSheetsModifier(appState: appState))
                                .modifier(GlobalKeyboardShortcutsModifier(appState: appState))
                        }
                    }
            } else {
                Color(nsColor: appState.appTheme.workspaceBackground)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            if !isWorkspaceMounted {
                DispatchQueue.main.async {
                    isWorkspaceMounted = true
                }
            }
            if !windowAuxiliaryReady {
                DispatchQueue.main.async {
                    windowAuxiliaryReady = true
                }
            }
            if !deferredOverlaysReady {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    deferredOverlaysReady = true
                }
            }
        }
        .sheet(isPresented: $appState.showingSettingsDialog) {
            SettingsView()
                .environmentObject(appState)
        }
        .alert(
            "MicroCode",
            isPresented: Binding(
                get: { appState.alertMessage != nil },
                set: { if !$0 { appState.alertMessage = nil } }
            )
        ) {
            Button("OK") { appState.alertMessage = nil }
        } message: {
            Text(appState.alertMessage ?? "")
        }
        // Keyboard shortcuts
        .onCommand(#selector(NSResponder.selectAll(_:))) { }
        .background(
            ZStack {
                if appState.appTheme.isGlass || appState.appTheme.usesDarkGlassSidebar {
                    Color.clear
                } else {
                    Color(nsColor: appState.appTheme.workspaceBackground)
                }
            }
        )
        .background(
            Button("") { appState.saveCurrentFile() }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
        )
        .background(
            Button("") {
                if appState.editorMode == .aiAgent {
                    ImplementationPlanManager.shared.clearPlan()
                    let ws = appState.workspaceFolder?.path ?? AgentService.shared.currentWorkspace
                    _ = AgentService.shared.createNewChat(projectPath: ws)
                } else {
                    appState.createNewFile()
                }
            }
                .keyboardShortcut("n", modifiers: .command)
                .hidden()
        )
        .background(
            Button("") {
                appState.aiChatVisible.toggle()
            }
                .keyboardShortcut("l", modifiers: .command)
                .hidden()
        )
        .background(
            Button("") {
                appState.toggleSidebar()
            }
                .keyboardShortcut("b", modifiers: .command)
                .hidden()
        )
    }

    @ViewBuilder
    private var welcomeOverlay: some View {
        if !welcomeCompleted || appState.showingFirstLaunchWelcome {
            FirstLaunchWelcomeView {
                // Write file-based flag so it survives app re-signing
                let dir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/MicroCode")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                FileManager.default.createFile(
                    atPath: dir.appendingPathComponent(".welcome_done").path,
                    contents: Data(), attributes: nil
                )
                withAnimation(.easeOut(duration: 0.2)) {
                    welcomeCompleted = true
                    appState.showingFirstLaunchWelcome = false
                }
            }
            .environmentObject(appState)
            .transition(.opacity)
            .zIndex(200)
        }
    }

    private var legacyWorkspace: some View {
        CompatHSplitView {
            if appState.sidebarVisible {
                NavigatorView()
                    .frame(minWidth: 200, idealWidth: 260, maxWidth: 400)
            }
            EditorArea()
            if appState.gitPanelVisible {
                InspectorView()
                    .frame(minWidth: 260, maxWidth: 350)
            }
            if appState.aiChatVisible {
                LegacyInlineAgentPanel()
                    .frame(minWidth: 340, idealWidth: 400, maxWidth: 520)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    // MARK: - Auto-Healer View

    @ViewBuilder
    private var autoHealerOverlay: some View {
        if deferredOverlaysReady, let suggestion = AutoHealerService.shared.currentSuggestion {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        AutoHealerService.shared.dismissSuggestion()
                    }

                HealerSuggestionView(
                    suggestion: suggestion,
                    onApply: {
                        AutoHealerService.shared.applyFix(suggestion)
                    },
                    onDismiss: {
                        AutoHealerService.shared.dismissSuggestion()
                    }
                )
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(100)
        }
    }
}

// MARK: - Agentic-first Code Workspace

enum AgenticWorkspaceSurface: String {
    case agent
    case editor
}

struct SidebarResizeSplitter: View {
    @EnvironmentObject var appState: AppState
    @Binding var width: Double
    var onCollapse: (() -> Void)? = nil

    var body: some View {
        NativePaneResizeSplitter(
            edge: .leadingPane,
            width: $width,
            minWidth: 160,
            maxWidth: 600,
            visualWidth: 4,
            showsGripPill: true,
            collapseThreshold: 95,
            onCollapse: onCollapse,
            onDoubleClick: {
                withAnimation(.easeInOut(duration: 0.16)) {
                    width = 270
                }
            }
        )
        .frame(width: 4)
        .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.workspaceBackground))
        .zIndex(30)
    }
}

struct WorkspaceSidebarToggleButton: View {
    @ObservedObject private var sidebarState = SidebarStateController.shared
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: {
            sidebarState.toggle()
        }) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovered ? .primary : (sidebarState.isVisible ? .primary.opacity(0.8) : .secondary))
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.primary.opacity(0.1) : (sidebarState.isVisible ? Color.clear : Color.primary.opacity(0.08)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHovered ? Color.primary.opacity(0.18) : (sidebarState.isVisible ? Color.clear : Color.primary.opacity(0.12)), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering in
            isHovered = hovering
        }
        .help(sidebarState.isVisible ? "Hide Sidebar (⌘B)" : "Show Sidebar (⌘B)")
    }
}

// MARK: - Zero-Overhead AppKit 120Hz Sidebar Split Container & Animation Bus

@MainActor
private final class SidebarAnimationBus {
    static let shared = SidebarAnimationBus()

    private(set) var revealedWidth: CGFloat = SidebarStateController.shared.isVisible
        ? CGFloat(max(160, min(600, SidebarStateController.shared.width)))
        : 0
    private(set) var isAnimating: Bool = false

    private var listeners: [UUID: (CGFloat, Bool) -> Void] = [:]

    func subscribe(_ handler: @escaping (CGFloat, Bool) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = handler
        handler(revealedWidth, isAnimating)
        return id
    }

    func unsubscribe(_ id: UUID) {
        listeners.removeValue(forKey: id)
    }

    func publish(revealedWidth: CGFloat, isAnimating: Bool) {
        guard abs(self.revealedWidth - revealedWidth) >= 0.1 || self.isAnimating != isAnimating else { return }
        self.revealedWidth = revealedWidth
        self.isAnimating = isAnimating
        for listener in listeners.values {
            listener(revealedWidth, isAnimating)
        }
    }
}

private final class ZeroSafeAreaHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
    override var safeAreaRect: NSRect { bounds }
}

private final class FlippedLayerClipView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return super.hitTest(point)
    }
}

private final class WeakSidebarDisplayLinkProxy: NSObject {
    weak var targetView: NativeSidebarSplitContainerView?

    init(targetView: NativeSidebarSplitContainerView) {
        self.targetView = targetView
    }

    @objc func handleTick() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                targetView?.stepAnimationFrame()
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.targetView?.stepAnimationFrame()
            }
        }
    }
}

@MainActor
private final class NativeSidebarSplitContainerView: NSView {
    override var isFlipped: Bool { true }

    private let mainBackdropView = NSView()
    private let sidebarClipView = FlippedLayerClipView()
    private let dividerView = PaneResizeSplitterNSView()
    private var sidebarHostAny: NSView?
    private var mainHostAny: NSView?

    private var showsGlobalSidebar: Bool = true
    private var isFullGlass: Bool = false
    private var usesDarkGlassSidebar: Bool = true
    private var workspaceBgColor: NSColor = .black

    private var targetWidth: CGFloat
    private var currentRevealedWidth: CGFloat

    private var animStartWidth: CGFloat = 0
    private var animEndWidth: CGFloat = 0
    private var animStartTime: CFTimeInterval = 0
    private var animDuration: CFTimeInterval = 0.12
    private var animatingTargetWidth: Bool = false
    private var isAnimatingSlide: Bool = false

    private var displayLinkObj: AnyObject?
    private var fallbackTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    override init(frame frameRect: NSRect) {
        let controller = SidebarStateController.shared
        let clampedW = CGFloat(max(160, min(600, controller.width)))
        self.targetWidth = clampedW
        self.currentRevealedWidth = controller.isVisible ? clampedW : 0
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.masksToBounds = true

        mainBackdropView.wantsLayer = true
        addSubview(mainBackdropView)

        addSubview(sidebarClipView)

        dividerView.edge = .leadingPane
        dividerView.minWidth = 160
        dividerView.maxWidth = 600
        dividerView.currentWidth = Double(clampedW)
        dividerView.showsGripPill = true
        dividerView.collapseThreshold = 95
        dividerView.onWidthChange = { [weak self] newWidth in
            Task { @MainActor [weak self] in
                self?.handleLiveDragWidth(newWidth)
            }
        }
        dividerView.onCollapse = {
            Task { @MainActor in
                SidebarStateController.shared.setVisible(false)
            }
        }
        dividerView.onDoubleClick = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleDoubleClickReset()
            }
        }
        addSubview(dividerView)

        controller.$isVisible
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] visible in
                self?.animateVisibility(to: visible)
            }
            .store(in: &cancellables)

        controller.$width
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newW in
                guard let self, !self.dividerView.isDragging, !self.animatingTargetWidth else { return }
                let clamped = CGFloat(max(160, min(600, newW)))
                guard abs(self.targetWidth - clamped) >= 0.5 else { return }
                self.targetWidth = clamped
                self.dividerView.currentWidth = Double(clamped)
                if self.showsGlobalSidebar && SidebarStateController.shared.isVisible && !self.isAnimatingSlide {
                    self.currentRevealedWidth = clamped
                    SidebarAnimationBus.shared.publish(revealedWidth: clamped, isAnimating: false)
                    self.applyFrames()
                }
            }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func installHosts(sidebarHost: NSView, mainHost: NSView) {
        sidebarHost.translatesAutoresizingMaskIntoConstraints = true
        mainHost.translatesAutoresizingMaskIntoConstraints = true
        mainHost.wantsLayer = true
        mainHost.layer?.masksToBounds = true
        self.sidebarHostAny = sidebarHost
        self.mainHostAny = mainHost

        // Exact z-order: mainBackdropView -> mainHost -> sidebarClipView -> dividerView
        addSubview(mainHost, positioned: .above, relativeTo: mainBackdropView)
        sidebarClipView.addSubview(sidebarHost)
    }

    func applyConfiguration(
        showsGlobalSidebar: Bool,
        isFullGlass: Bool,
        usesDarkGlassSidebar: Bool,
        workspaceBgColor: NSColor,
        colorScheme: ColorScheme?
    ) {
        if let cs = colorScheme {
            let desiredName: NSAppearance.Name = (cs == .light) ? .aqua : .darkAqua
            if appearance?.name != desiredName {
                appearance = NSAppearance(named: desiredName)
            }
        } else if appearance != nil {
            appearance = nil
        }

        let modeChanged = (self.showsGlobalSidebar != showsGlobalSidebar)
        self.showsGlobalSidebar = showsGlobalSidebar
        self.isFullGlass = isFullGlass
        self.usesDarkGlassSidebar = usesDarkGlassSidebar
        self.workspaceBgColor = workspaceBgColor

        layer?.backgroundColor = (isFullGlass || usesDarkGlassSidebar) ? nil : workspaceBgColor.cgColor
        mainBackdropView.layer?.backgroundColor = isFullGlass ? nil : workspaceBgColor.cgColor

        if modeChanged {
            stopAnimationLink()
            currentRevealedWidth = (showsGlobalSidebar && SidebarStateController.shared.isVisible) ? targetWidth : 0
            SidebarAnimationBus.shared.publish(revealedWidth: currentRevealedWidth, isAnimating: false)
            applyFrames()
        }
    }

    private func handleLiveDragWidth(_ rawWidth: Double) {
        stopAnimationLink()
        let clamped = CGFloat(max(160, min(600, rawWidth)))
        targetWidth = clamped
        currentRevealedWidth = clamped
        SidebarStateController.shared.setWidth(Double(clamped))
        SidebarAnimationBus.shared.publish(revealedWidth: clamped, isAnimating: false)
        applyFrames()
    }

    private func handleDoubleClickReset() {
        SidebarStateController.shared.setWidth(270)
        dividerView.currentWidth = 270
        guard showsGlobalSidebar, SidebarStateController.shared.isVisible else {
            targetWidth = 270
            return
        }
        startSmoothSlide(from: currentRevealedWidth, to: 270, duration: 0.12, updatesTargetWidth: true)
    }

    private func animateVisibility(to visible: Bool) {
        guard showsGlobalSidebar else {
            stopAnimationLink()
            currentRevealedWidth = 0
            SidebarAnimationBus.shared.publish(revealedWidth: 0, isAnimating: false)
            applyFrames()
            return
        }
        let destination: CGFloat = visible ? targetWidth : 0
        let distance = abs(destination - currentRevealedWidth)
        if distance < 0.5 || window == nil {
            stopAnimationLink()
            currentRevealedWidth = destination
            SidebarAnimationBus.shared.publish(revealedWidth: destination, isAnimating: false)
            applyFrames()
            return
        }
        let fraction = min(1.0, max(0.35, distance / max(targetWidth, 1)))
        startSmoothSlide(from: currentRevealedWidth, to: destination, duration: 0.12 * Double(fraction), updatesTargetWidth: false)
    }

    private func startSmoothSlide(from startW: CGFloat, to endW: CGFloat, duration: CFTimeInterval, updatesTargetWidth: Bool) {
        animStartWidth = startW
        animEndWidth = endW
        animStartTime = CACurrentMediaTime()
        animDuration = max(0.05, duration)
        animatingTargetWidth = updatesTargetWidth
        isAnimatingSlide = true

        if endW > 0.01 && sidebarClipView.isHidden {
            sidebarClipView.isHidden = false
        }
        dividerView.isHidden = true
        SidebarAnimationBus.shared.publish(revealedWidth: currentRevealedWidth, isAnimating: true)

        guard displayLinkObj == nil && fallbackTimer == nil else { return }
        let proxy = WeakSidebarDisplayLinkProxy(targetView: self)
        if #available(macOS 14.0, *) {
            let link = self.displayLink(target: proxy, selector: #selector(WeakSidebarDisplayLinkProxy.handleTick))
            link.add(to: .main, forMode: .common)
            displayLinkObj = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 120.0, target: proxy, selector: #selector(WeakSidebarDisplayLinkProxy.handleTick), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            fallbackTimer = timer
        }
    }

    fileprivate func stepAnimationFrame() {
        let elapsed = CACurrentMediaTime() - animStartTime
        let rawT = min(1.0, max(0.0, elapsed / animDuration))
        // Snappy quartic ease-out: instant initial velocity on click, zero overshoot
        let inv = 1.0 - rawT
        let eased = CGFloat(1.0 - (inv * inv * inv * inv))
        let nextW = animStartWidth + (animEndWidth - animStartWidth) * eased

        if rawT >= 1.0 {
            let finalW = animEndWidth
            let updatedTarget = animatingTargetWidth
            stopAnimationLink()
            if updatedTarget {
                targetWidth = finalW
            }
            currentRevealedWidth = finalW
            SidebarAnimationBus.shared.publish(revealedWidth: finalW, isAnimating: false)
            applyFrames()
        } else {
            if animatingTargetWidth {
                targetWidth = nextW
            }
            currentRevealedWidth = nextW
            SidebarAnimationBus.shared.publish(revealedWidth: nextW, isAnimating: true)
            applyFrames()
        }
    }

    private func stopAnimationLink() {
        if #available(macOS 14.0, *), let link = displayLinkObj as? CADisplayLink {
            link.invalidate()
        }
        displayLinkObj = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        isAnimatingSlide = false
        animatingTargetWidth = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopAnimationLink()
        } else {
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        applyFrames()
    }

    private func applyFrames() {
        let totalW = bounds.width
        let totalH = bounds.height
        guard totalW > 0, totalH > 0 else { return }

        let scale = window?.backingScaleFactor ?? 2.0
        let effectiveRevealed = showsGlobalSidebar ? min(targetWidth, max(0, currentRevealedWidth)) : 0
        let snappedW: CGFloat
        if effectiveRevealed <= 0.25 {
            snappedW = 0
        } else if abs(effectiveRevealed - targetWidth) <= 0.25 {
            snappedW = (targetWidth * scale).rounded() / scale
        } else {
            snappedW = (effectiveRevealed * scale).rounded() / scale
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // 1. Solid backing behind main area overlapping 2pt under sidebar seam -> zero white flash ever
        let backdropX = max(0, snappedW - 2)
        let backdropFrame = NSRect(x: backdropX, y: 0, width: max(0, totalW - backdropX), height: totalH)
        if mainBackdropView.frame != backdropFrame {
            mainBackdropView.frame = backdropFrame
        }

        // 2. Main workspace content
        if let mainHost = mainHostAny {
            let mainW = max(320, totalW - snappedW)
            let mainFrame = NSRect(x: snappedW, y: 0, width: mainW, height: totalH)
            if mainHost.frame != mainFrame {
                mainHost.frame = mainFrame
            }
        }

        // 3. Sliding sidebar clip + constant-width inner sidebar host (zero inner column reflow!)
        if snappedW <= 0.01 {
            if !sidebarClipView.isHidden {
                sidebarClipView.isHidden = true
            }
            let zeroClip = NSRect(x: 0, y: 0, width: 0, height: totalH)
            if sidebarClipView.frame != zeroClip {
                sidebarClipView.frame = zeroClip
            }
        } else {
            if sidebarClipView.isHidden {
                sidebarClipView.isHidden = false
            }
            let clipFrame = NSRect(x: 0, y: 0, width: snappedW, height: totalH)
            if sidebarClipView.frame != clipFrame {
                sidebarClipView.frame = clipFrame
            }
            if let sidebarHost = sidebarHostAny {
                let snappedTarget = (targetWidth * scale).rounded() / scale
                let hostFrame = NSRect(x: snappedW - snappedTarget, y: 0, width: snappedTarget, height: totalH)
                if sidebarHost.frame != hostFrame {
                    sidebarHost.frame = hostFrame
                }
            }
        }

        // 4. Permanent AppKit resize splitter (never recreated in SwiftUI)
        let shouldShowDivider = showsGlobalSidebar && !isAnimatingSlide && snappedW > 1.0
        if dividerView.isHidden == shouldShowDivider {
            dividerView.isHidden = !shouldShowDivider
        }
        if shouldShowDivider {
            let divFrame = NSRect(x: max(0, snappedW - 3), y: 0, width: 6, height: totalH)
            if dividerView.frame != divFrame {
                dividerView.frame = divFrame
            }
        }

        CATransaction.commit()
    }
}

private struct NativeSidebarSplitContainer<SidebarContent: View, MainContent: View>: NSViewRepresentable {
    let appState: AppState
    let showsGlobalSidebar: Bool
    @ViewBuilder let sidebarContent: () -> SidebarContent
    @ViewBuilder let mainContent: () -> MainContent

    struct HostedPaneRoot<Pane: View>: View {
        let appState: AppState
        let content: Pane

        var body: some View {
            content
                .environmentObject(appState)
                .preferredColorScheme(appState.appTheme.colorScheme)
                .ignoresSafeArea(.all, edges: .top)
        }
    }

    final class Coordinator {
        var sidebarHost: ZeroSafeAreaHostingView<HostedPaneRoot<SidebarContent>>?
        var mainHost: ZeroSafeAreaHostingView<HostedPaneRoot<MainContent>>?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NativeSidebarSplitContainerView {
        let container = NativeSidebarSplitContainerView()

        let sbHost = ZeroSafeAreaHostingView(rootView: HostedPaneRoot(appState: appState, content: sidebarContent()))
        sbHost.sizingOptions = []

        let mnHost = ZeroSafeAreaHostingView(rootView: HostedPaneRoot(appState: appState, content: mainContent()))
        mnHost.sizingOptions = []

        context.coordinator.sidebarHost = sbHost
        context.coordinator.mainHost = mnHost

        container.installHosts(sidebarHost: sbHost, mainHost: mnHost)
        container.applyConfiguration(
            showsGlobalSidebar: showsGlobalSidebar,
            isFullGlass: appState.appTheme.isGlass,
            usesDarkGlassSidebar: appState.appTheme.usesDarkGlassSidebar,
            workspaceBgColor: appState.appTheme.workspaceBackground,
            colorScheme: appState.appTheme.colorScheme
        )
        return container
    }

    func updateNSView(_ nsView: NativeSidebarSplitContainerView, context: Context) {
        context.coordinator.sidebarHost?.rootView = HostedPaneRoot(appState: appState, content: sidebarContent())
        context.coordinator.mainHost?.rootView = HostedPaneRoot(appState: appState, content: mainContent())
        nsView.applyConfiguration(
            showsGlobalSidebar: showsGlobalSidebar,
            isFullGlass: appState.appTheme.isGlass,
            usesDarkGlassSidebar: appState.appTheme.usesDarkGlassSidebar,
            workspaceBgColor: appState.appTheme.workspaceBackground,
            colorScheme: appState.appTheme.colorScheme
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NativeSidebarSplitContainerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 1200, height: proposal.height ?? 800)
    }
}

struct AgenticEditorWorkspace: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var deviceRuntime = DeviceRuntimeService.shared
    @State private var surface: AgenticWorkspaceSurface = AppEdition.isStandaloneAI ? .agent : .editor
    @State private var shortcutMonitor: Any? = nil

    /// Modes that manage their own left sidebar and don't need the global file browser.
    /// These modes (Embedded Studio, Browser, API Client, Remote Explorer) have
    /// specialized sidebars with mode-specific navigation.
    private var modeHasOwnSidebar: Bool {
        if AppEdition.isStandaloneAI { return false }
        return [.embedded, .browser, .apiClient, .remoteX, .notebook, .playground].contains(appState.editorMode)
    }

    private var shouldShowWelcome: Bool {
        if AppEdition.isStandaloneAI { return false }
        return (appState.workspaceFolder == nil && appState.openFiles.isEmpty && appState.editorMode == .code) || appState.showingWelcomeHome
    }

    var body: some View {
        Group {
            if shouldShowWelcome {
                WelcomeScreen(surface: $surface)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        appState.appTheme.isGlass
                            ? AnyView(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
                            : AnyView(Color(nsColor: appState.appTheme.workspaceBackground))
                    )
            } else {
                NativeSidebarSplitContainer(
                    appState: appState,
                    showsGlobalSidebar: !modeHasOwnSidebar
                ) {
                    Group {
                        if surface == .editor && !AppEdition.isStandaloneAI {
                            XcodeEditorSidebar(surface: $surface)
                        } else {
                            AgenticWorkspaceSidebar(surface: $surface)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SidebarAdaptiveBackground())
                } mainContent: {
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            WorkspaceUnifiedHeaderBar(
                                surface: surface,
                                modeHasOwnSidebar: modeHasOwnSidebar
                            )

                            if surface == .agent || AppEdition.isStandaloneAI {
                                AIAgentView(allowsChatSidebar: false, usesUnifiedWindowToolbar: true)
                                    .environmentObject(appState)
                            } else {
                                activeEditorSurface
                            }
                        }
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(0)

                        if appState.agenticContextVisible {
                            AgenticContextInspector(surface: $surface)
                                .layoutPriority(1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    CollaborationWorkspaceMouseOverlay(
                        surface: surface == .agent ? "agent" : "editor"
                    )
                )
            }
        }
        .sheet(isPresented: $deviceRuntime.showingDeviceRuntimeSheet) {
            DeviceRuntimeView(onEmbeddedAndroidOpened: {
                deviceRuntime.showingEmbeddedDeviceDock = true
                deviceRuntime.showingEmbeddedAppleDock = false
            }, onEmbeddedAppleSimulatorOpened: {
                deviceRuntime.showingEmbeddedDeviceDock = true
                deviceRuntime.showingEmbeddedAppleDock = true
            })
            .environmentObject(appState)
        }
        .onAppear {
            surface = (appState.editorMode == .aiAgent) ? .agent : .editor
            installFastShortcutMonitorIfNeeded()
            if surface == .agent, let workspace = appState.workspaceFolder {
                AgentService.shared.setWorkspace(workspace.path)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak appState] in
                guard let appState else { return }
                PhoneCompanionService.shared.appState = appState
                if PhoneCompanionService.shared.isEnabled {
                    PhoneCompanionService.shared.startServerIfNeeded()
                }
                if LocalLLMGatewayService.shared.isEnabled {
                    LocalLLMGatewayService.shared.startServerIfNeeded()
                }
            }
        }
        .onDisappear {
            if let monitor = shortcutMonitor {
                NSEvent.removeMonitor(monitor)
                shortcutMonitor = nil
            }
        }
        .onChange(of: appState.editorMode) { newMode in
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                let targetSurface: AgenticWorkspaceSurface = (newMode == .aiAgent) ? .agent : .editor
                if surface != targetSurface {
                    surface = targetSurface
                }
            }
            if newMode == .aiAgent, let ws = appState.workspaceFolder {
                AgentService.shared.setWorkspace(ws.path)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeWorkspaceChanged"))) { notif in
            if let path = notif.object as? String, !path.isEmpty {
                let normalizedNew = URL(fileURLWithPath: path).standardizedFileURL.path
                let normalizedCurrent = appState.workspaceFolder?.standardizedFileURL.path
                if normalizedCurrent != normalizedNew {
                    Task { @MainActor in
                        await appState.openWorkspace(url: URL(fileURLWithPath: normalizedNew))
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeOpenFileURL"))) { notif in
            if let url = notif.object as? URL {
                Task { @MainActor in
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                        if isDir.boolValue {
                            await appState.openWorkspace(url: url)
                            AgentService.shared.setWorkspace(url.path)
                        } else if url.pathExtension.lowercased() == "arx" {
                            if let _ = try? ARXCapsuleService.shared.importAndResumeCapsule(from: url, appState: appState) {
                                surface = .agent
                            }
                        } else if surface == .agent || appState.editorMode == .aiAgent {
                            PreviewDockService.shared.openFile(url: url, makeActive: true)
                        } else {
                            await appState.loadFile(url: url)
                            surface = .editor
                        }
                    } else if surface == .agent || appState.editorMode == .aiAgent {
                        PreviewDockService.shared.openFileFromReference(url.absoluteString, workspacePath: appState.workspaceFolder?.path)
                    }
                }
            }
        }
    }

    private func installFastShortcutMonitorIfNeeded() {
        guard shortcutMonitor == nil else { return }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
                return event
            }
            if flags == [.command], chars == "b" {
                if let win = NSApp.keyWindow, !win.isSheet, win.attachedSheet == nil, win.sheetParent == nil {
                    SidebarStateController.shared.toggle()
                    return nil
                }
            }
            if !AppEdition.isStandaloneAI && (flags == [.control] || flags == [.command, .option]) {
                switch chars {
                case "0" where flags == [.control]:
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    withTransaction(tx) {
                        appState.showingWelcomeHome.toggle()
                    }
                    return nil
                case "1":
                    appState.switchToMode(.code)
                    return nil
                case "2":
                    appState.switchToMode(.aiAgent)
                    return nil
                case "3":
                    appState.switchToMode(.notebook)
                    return nil
                case "4":
                    appState.switchToMode(.playground)
                    return nil
                case "5":
                    appState.switchToMode(.science)
                    return nil
                case "6":
                    appState.switchToMode(.browser)
                    return nil
                case "7":
                    appState.switchToMode(.remoteX)
                    return nil
                case "8":
                    appState.switchToMode(.embedded)
                    return nil
                case "9":
                    appState.openAPIStudio()
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }

    @ViewBuilder
    private var activeEditorSurface: some View {
        switch appState.editorMode {
        case .aiAgent:
            AIAgentView(allowsChatSidebar: false, usesUnifiedWindowToolbar: true)
                .environmentObject(appState)
        case .notebook:
            NotebookView()
                .environmentObject(appState)
        case .science:
            ScienceModeView()
                .environmentObject(appState)
        case .playground:
            PlaygroundView()
                .environmentObject(appState)
        case .browser:
            IDEBrowserView()
                .environmentObject(appState)
        case .remoteX:
            RemoteXView()
                .environmentObject(appState)
        case .embedded:
            EmbeddedStudioView()
                .environmentObject(appState)
        case .apiClient:
            APIClientView()
                .environmentObject(appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .extensions:
            ExtensionStudioView()
                .environmentObject(appState)
        default:
            EditorArea()
                .environmentObject(appState)
        }
    }
}

// MARK: - Zero-GeometryReader Unified 36pt Workspace Header Bar

private enum HeaderWidthBucket: Int, Equatable {
    case regular = 0     // >= 1120pt
    case compact = 1     // 760..<1120pt
    case tight = 2       // 540..<760pt
    case ultraTight = 3  // < 540pt

    static func from(width: CGFloat) -> HeaderWidthBucket {
        if width >= 1120 { return .regular }
        if width >= 760 { return .compact }
        if width >= 540 { return .tight }
        return .ultraTight
    }
}

private struct HeaderWidthBucketObserver: NSViewRepresentable {
    @Binding var bucket: HeaderWidthBucket

    final class ObserverNSView: NSView {
        var onBucketChange: ((HeaderWidthBucket) -> Void)?
        private var lastBucket: HeaderWidthBucket?
        private var busToken: UUID?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil && busToken == nil {
                busToken = SidebarAnimationBus.shared.subscribe { [weak self] _, isAnimating in
                    if !isAnimating {
                        self?.evaluateWidth()
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    self?.evaluateWidth()
                }
            } else if window == nil, let token = busToken {
                SidebarAnimationBus.shared.unsubscribe(token)
                busToken = nil
            }
        }

        deinit {
            if let token = busToken {
                Task { @MainActor in
                    SidebarAnimationBus.shared.unsubscribe(token)
                }
            }
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            guard !SidebarAnimationBus.shared.isAnimating || lastBucket == nil else { return }
            evaluateWidth()
        }

        override func layout() {
            super.layout()
            // Defer threshold transitions until 120ms slide settles -> zero mid-animation NSMenu rebuilds!
            guard !SidebarAnimationBus.shared.isAnimating || lastBucket == nil else { return }
            evaluateWidth()
        }

        private func evaluateWidth() {
            let w = bounds.width
            guard w > 80 else { return }
            let next = HeaderWidthBucket.from(width: w)
            guard next != lastBucket else { return }
            lastBucket = next
            DispatchQueue.main.async { [weak self] in
                self?.onBucketChange?(next)
            }
        }
    }

    func makeNSView(context: Context) -> ObserverNSView {
        let view = ObserverNSView()
        view.onBucketChange = { next in
            if bucket != next {
                bucket = next
            }
        }
        return view
    }

    func updateNSView(_ nsView: ObserverNSView, context: Context) {
        nsView.onBucketChange = { next in
            if bucket != next {
                bucket = next
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ObserverNSView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

/// Pure AppKit leading inset spacer that keeps `[◧]` parked safely at `x >= 78` (never touching macOS traffic lights)
/// when the sidebar collapses below `68pt`, and stays constant at `10pt` for `w >= 68pt` — zero SwiftUI `.body` runs!
private struct HeaderLeadingSpacer: NSViewRepresentable {
    let modeHasOwnSidebar: Bool

    final class SpacerNSView: NSView {
        var modeHasOwnSidebar: Bool = false {
            didSet {
                if oldValue != modeHasOwnSidebar {
                    recomputeWidth()
                }
            }
        }
        private var revealedSidebarWidth: CGFloat = SidebarAnimationBus.shared.revealedWidth
        private var isWindowFullScreen: Bool = WindowTrafficLightsController.shared.isFullScreen
        private var currentSpacerWidth: CGFloat = 10
        private var busToken: UUID?
        private var enterFSToken: NSObjectProtocol?
        private var exitFSToken: NSObjectProtocol?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setContentHuggingPriority(.required, for: .horizontal)
            setContentCompressionResistancePriority(.required, for: .horizontal)
            recomputeWidth()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: currentSpacerWidth, height: 1)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let win = window {
                isWindowFullScreen = win.styleMask.contains(.fullScreen)
                if busToken == nil {
                    busToken = SidebarAnimationBus.shared.subscribe { [weak self] revealedW, _ in
                        guard let self else { return }
                        self.revealedSidebarWidth = revealedW
                        self.recomputeWidth()
                    }
                }
                if enterFSToken == nil {
                    enterFSToken = NotificationCenter.default.addObserver(
                        forName: NSWindow.didEnterFullScreenNotification,
                        object: win,
                        queue: .main
                    ) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            self?.isWindowFullScreen = true
                            self?.recomputeWidth()
                        }
                    }
                }
                if exitFSToken == nil {
                    exitFSToken = NotificationCenter.default.addObserver(
                        forName: NSWindow.didExitFullScreenNotification,
                        object: win,
                        queue: .main
                    ) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            self?.isWindowFullScreen = false
                            self?.recomputeWidth()
                        }
                    }
                }
                recomputeWidth()
            } else {
                tearDownSubscriptions()
            }
        }

        deinit {
            if let e1 = enterFSToken { NotificationCenter.default.removeObserver(e1) }
            if let e2 = exitFSToken { NotificationCenter.default.removeObserver(e2) }
            if let token = busToken {
                Task { @MainActor in
                    SidebarAnimationBus.shared.unsubscribe(token)
                }
            }
        }

        private func tearDownSubscriptions() {
            if let token = busToken {
                SidebarAnimationBus.shared.unsubscribe(token)
                busToken = nil
            }
            if let e1 = enterFSToken {
                NotificationCenter.default.removeObserver(e1)
                enterFSToken = nil
            }
            if let e2 = exitFSToken {
                NotificationCenter.default.removeObserver(e2)
                exitFSToken = nil
            }
        }

        private func recomputeWidth() {
            let collapsedLeading: CGFloat = isWindowFullScreen ? 12 : 78
            let desired: CGFloat
            if modeHasOwnSidebar {
                desired = collapsedLeading
            } else {
                desired = max(10, collapsedLeading - revealedSidebarWidth)
            }
            let snapped = (desired * 2.0).rounded() / 2.0
            guard abs(snapped - currentSpacerWidth) >= 0.5 else { return }
            currentSpacerWidth = snapped
            invalidateIntrinsicContentSize()
        }
    }

    func makeNSView(context: Context) -> SpacerNSView {
        let v = SpacerNSView()
        v.modeHasOwnSidebar = modeHasOwnSidebar
        return v
    }

    func updateNSView(_ nsView: SpacerNSView, context: Context) {
        nsView.modeHasOwnSidebar = modeHasOwnSidebar
    }
}

private struct HeaderCollapsedNewChatButton: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var sidebarState = SidebarStateController.shared

    var body: some View {
        if !sidebarState.isVisible {
            Button(action: {
                AgentWorkspaceBarState.shared.isPlanMode = false
                ImplementationPlanManager.shared.clearPlan()
                _ = AgentService.shared.createNewChat(
                    projectPath: AgentService.shared.currentWorkspace ?? appState.workspaceFolder?.path
                )
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("New Conversation (⌘N)")
        }
    }
}

private struct HeaderBreadcrumbSlot: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var sidebarState = SidebarStateController.shared
    let surface: AgenticWorkspaceSurface
    let isCompactHeader: Bool
    let isTightHeader: Bool

    var body: some View {
        if !(isTightHeader && sidebarState.isVisible) {
            UnifiedHeaderBreadcrumbView(
                surface: surface,
                showDetailSegment: !isTightHeader,
                maxBreadcrumbWidth: isCompactHeader ? 180 : 240
            )
            .environmentObject(appState)
            .frame(minWidth: 0)
        }
    }
}

private struct HeaderCollapsedSettingsButton: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var sidebarState = SidebarStateController.shared
    let modeHasOwnSidebar: Bool

    var body: some View {
        if !sidebarState.isVisible || modeHasOwnSidebar {
            Button(action: { appState.showingSettingsDialog = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Settings (⌘,)")
        }
    }
}

private struct WorkspaceUnifiedHeaderBar: View {
    @EnvironmentObject var appState: AppState
    let surface: AgenticWorkspaceSurface
    let modeHasOwnSidebar: Bool

    @State private var widthBucket: HeaderWidthBucket = .regular

    var body: some View {
        let isCompactHeader = widthBucket != .regular
        let isTightHeader = (widthBucket == .tight || widthBucket == .ultraTight)
        let isUltraTightHeader = (widthBucket == .ultraTight)
        let isAgentSurface = (surface == .agent || appState.editorMode == .aiAgent)

        HStack(spacing: 0) {
            HeaderLeadingSpacer(modeHasOwnSidebar: modeHasOwnSidebar)
                .frame(height: 1)

            HStack(spacing: isTightHeader ? 4 : (isCompactHeader ? 5 : 8)) {
                // Sidebar Toggle + New Chat (when sidebar is hidden in Agent Mode) — pinned at top priority so [◧] never clips
                if !modeHasOwnSidebar {
                    HStack(spacing: isCompactHeader ? 4 : 6) {
                        WorkspaceSidebarToggleButton()

                        if isAgentSurface {
                            HeaderCollapsedNewChatButton()
                                .environmentObject(appState)
                        }
                    }
                    .fixedSize()
                    .layoutPriority(10)
                }

                // Breadcrumb (project / active task or file) — yields horizontally before any button can overflow
                if !modeHasOwnSidebar {
                    HeaderBreadcrumbSlot(
                        surface: surface,
                        isCompactHeader: isCompactHeader,
                        isTightHeader: isTightHeader
                    )
                    .environmentObject(appState)
                    .layoutPriority(-0.5)
                }

                WindowDragSpacerView()
                    .frame(minWidth: 4, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(-1)

                if isAgentSurface {
                    HStack(spacing: isCompactHeader ? 4 : 6) {
                        UnifiedAgentModePillsView(veryCompact: isTightHeader)
                            .environmentObject(appState)

                        UnifiedWorkspacePreviewMenu(isIconOnly: isTightHeader)
                            .environmentObject(appState)

                        UnifiedAgentActionsMenu(isCompact: isCompactHeader)
                            .environmentObject(appState)
                    }
                    .fixedSize()
                    .layoutPriority(2)
                } else if surface == .editor && appState.editorMode == .code {
                    // In Code Editor mode, provide Run, Build, Unified Preview, Console quick action pills
                    HStack(spacing: isTightHeader ? 4 : 5) {
                        Button(action: { appState.runCode() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9, weight: .bold))
                                if !isUltraTightHeader {
                                    Text("Run")
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                }
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal, isUltraTightHeader ? 7 : 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help("Run Code (⌘R)")

                        Button(action: { appState.buildProject() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "hammer.fill")
                                    .font(.system(size: 9, weight: .medium))
                                if !isTightHeader {
                                    Text("Build")
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                }
                            }
                            .foregroundColor(.primary.opacity(0.85))
                            .padding(.horizontal, isTightHeader ? 7 : 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help("Build Project (⌘⇧B)")

                        UnifiedWorkspacePreviewMenu(isIconOnly: isTightHeader)
                            .environmentObject(appState)

                        Button(action: { appState.toggleConsole() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 9))
                                if !isTightHeader {
                                    Text("Console")
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                }
                            }
                            .foregroundColor(appState.consoleVisible ? .accentColor : .secondary)
                            .padding(.horizontal, isTightHeader ? 7 : 8)
                            .padding(.vertical, 4)
                            .background(appState.consoleVisible ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help("Toggle Terminal / Console (⌘J)")
                    }
                    .fixedSize()
                    .layoutPriority(2)
                }

                if !isUltraTightHeader {
                    HeaderCollaborationPresenceBar()
                        .environmentObject(appState)
                        .fixedSize()
                        .layoutPriority(1)
                }

                // Surface Toggle (Agent vs Code Editor vs More Mode) — hidden in Standalone MicroCode AI
                if !AppEdition.isStandaloneAI {
                    let isMoreSurfaceActive = surface == .editor && appState.editorMode != .code && appState.editorMode != .aiAgent
                    HStack(spacing: 2) {
                        Button {
                            appState.switchToMode(.aiAgent)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "brain")
                                    .font(.system(size: 10))
                                if !isUltraTightHeader {
                                    Text("Agent")
                                        .font(.system(size: 11, weight: isAgentSurface ? .semibold : .medium))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .agenticTabStyle(active: isAgentSurface, compact: isCompactHeader)
                        .help("Agent Mode")

                        Button {
                            appState.switchToMode(.code)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "curlybraces")
                                    .font(.system(size: 10))
                                if !isUltraTightHeader {
                                    Text(isCompactHeader ? "Editor" : "Code Editor")
                                        .font(.system(size: 11, weight: (surface == .editor && appState.editorMode == .code) ? .semibold : .medium))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .agenticTabStyle(active: surface == .editor && appState.editorMode == .code, compact: isCompactHeader)
                        .help("Code Editor Mode")

                        Menu {
                            Button("Playground Mode") {
                                appState.switchToMode(.playground)
                            }
                            Button("Cell Mode (Notebook)") {
                                appState.switchToMode(.notebook)
                            }
                            Button("SSH Remote Browser") {
                                appState.switchToMode(.remoteX)
                            }
                            Button("Science Mode") {
                                appState.switchToMode(.science)
                            }
                            Button("IDE Web Browser") {
                                appState.switchToMode(.browser)
                            }
                            Button("Embed & IoT Studio") {
                                appState.switchToMode(.embedded)
                            }
                            Button("API Studio") {
                                appState.openAPIStudio()
                            }
                            Button("Extension Studio") {
                                appState.openExtensionStudio()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 10))
                                if !isUltraTightHeader && (isMoreSurfaceActive || !isCompactHeader) {
                                    Text(isMoreSurfaceActive ? appState.editorMode.displayName : "More Mode")
                                        .font(.system(size: 11, weight: isMoreSurfaceActive ? .semibold : .medium))
                                        .lineLimit(1)
                                }
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7, weight: .bold))
                            }
                        }
                        .agenticTabStyle(active: isMoreSurfaceActive, compact: isCompactHeader)
                        .help("More Modes (Playground, Notebook, Science, SSH, Browser, IoT, API)")
                    }
                    .padding(2)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                    .fixedSize()
                    .layoutPriority(3)
                }

                // Trailing window/panel controls — pinned at top priority so [...] and [◨] are never pushed off-screen
                HStack(spacing: isCompactHeader ? 4 : 6) {
                    if !AppEdition.isStandaloneAI {
                        // Overflow Layout Menu [...]
                        AgenticLayoutMenu()
                            .environmentObject(appState)
                            .fixedSize()
                    }

                    // Context & Preview Inspector [sidebar.right]
                    UnifiedRightInspectorToggleButton()
                        .environmentObject(appState)

                    // Settings [⚙] — always accessible in Standalone AI or when left sidebar is hidden
                    if AppEdition.isStandaloneAI {
                        Button(action: { appState.showingSettingsDialog = true }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(width: 28, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help("Settings (⌘,)")
                    } else {
                        HeaderCollapsedSettingsButton(modeHasOwnSidebar: modeHasOwnSidebar)
                            .environmentObject(appState)
                    }
                }
                .fixedSize()
                .layoutPriority(10)
            }
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
        .clipped()
        .background(HeaderWidthBucketObserver(bucket: $widthBucket))
        .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.workspaceBackground))
    }
}

// MARK: - Unified 36pt Bar Subcomponents

private struct UnifiedHeaderBreadcrumbView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var sessionSummary = AgentSessionSummaryStore.shared
    private var agent: AgentService { AgentService.shared }
    let surface: AgenticWorkspaceSurface
    let showDetailSegment: Bool
    let maxBreadcrumbWidth: CGFloat

    private var activeTaskTitle: String {
        if let currentChat = agent.chatSessions.first(where: { $0.id == agent.activeChatId }) {
            return currentChat.name
        }
        return "New Task"
    }

    private var activeProjectName: String {
        if surface == .agent || appState.editorMode == .aiAgent {
            if let currentChat = agent.chatSessions.first(where: { $0.id == agent.activeChatId }),
               let pName = currentChat.projectName, !pName.isEmpty {
                return pName
            }
        }
        return appState.workspaceFolder?.lastPathComponent ?? "MicroCode"
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize()
            Text(activeProjectName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if showDetailSegment {
                Text("/")
                    .foregroundColor(.secondary.opacity(0.6))
                    .font(.system(size: 11))
                    .fixedSize()
                Text((surface == .agent || appState.editorMode == .aiAgent)
                     ? activeTaskTitle
                     : (appState.currentFile?.name ?? (appState.editorMode == .code ? "Editor" : appState.editorMode.displayName)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)
            }
        }
        .frame(minWidth: 0, maxWidth: maxBreadcrumbWidth, alignment: .leading)
    }
}

private struct UnifiedRightInspectorToggleButton: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var previewDock = PreviewDockService.shared
    @ObservedObject private var deviceRuntime = DeviceRuntimeService.shared

    var body: some View {
        let isRightPaneOpen = appState.agenticContextVisible || appState.showingPreviewView || previewDock.isDockVisible || deviceRuntime.showingEmbeddedDeviceDock
        Button(action: {
            withAnimation(.easeInOut(duration: 0.16)) {
                appState.toggleAgenticContext()
            }
        }) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 12))
                .foregroundColor(isRightPaneOpen ? .accentColor : .secondary)
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isRightPaneOpen ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("i", modifiers: [.command])
        .fixedSize()
        .help("Toggle Preview & Context Inspector (⌘I)")
    }
}

private struct UnifiedAgentModePillsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var barState = AgentWorkspaceBarState.shared
    @ObservedObject private var planManager = ImplementationPlanManager.shared
    let veryCompact: Bool

    private var isPlanActive: Bool {
        barState.isPlanMode || planManager.isPlanVisible
    }

    private var isChatActive: Bool {
        !isPlanActive && !barState.isPaperMode && !barState.isCellMode && !barState.isTaskMode && !barState.isWalkthroughMode
    }

    private var isSecondaryActive: Bool {
        barState.isCellMode || barState.isWalkthroughMode || (barState.isTaskMode && barState.activeTaskTab > 0)
    }

    private var secondaryLabel: String {
        if barState.isWalkthroughMode { return "Walkthrough" }
        if barState.isCellMode { return "Cells" }
        if barState.isTaskMode {
            switch barState.activeTaskTab {
            case 1: return "Spec"
            case 2: return "Walkthrough"
            case 3: return "Logs"
            case 4: return "Cost"
            case 5: return "Audit"
            case 6: return "Verify"
            case 7: return "Background"
            default: break
            }
        }
        return "More"
    }

    var body: some View {
        HStack(spacing: 2) {
            pillButton("Chat", icon: "bubble.left.and.bubble.right", isActive: isChatActive) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    barState.selectChatMode()
                }
            }

            pillButton("Plan", icon: "list.bullet.clipboard", isActive: isPlanActive, badgeDot: planManager.currentPlan?.approvalState == .pending ? .orange : nil) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    barState.togglePlanMode(workspacePath: appState.workspaceFolder?.path)
                }
            }

            pillButton("Task", icon: "checklist", isActive: barState.isTaskMode && barState.activeTaskTab == 0) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    barState.selectTaskTab(0)
                }
            }

            Menu {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { barState.selectWalkthroughMode() }
                } label: {
                    Label("Walkthrough Summary", systemImage: "sparkles")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { barState.selectCellMode() }
                } label: {
                    Label("Interactive Notebook Cells", systemImage: "square.grid.2x2")
                }

                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { barState.selectTaskTab(7) }
                } label: {
                    Label("Background Worktree Agents", systemImage: "arrow.triangle.branch")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { barState.selectTaskTab(4) }
                } label: {
                    Label("Token & Cost Usage", systemImage: "chart.bar.xaxis")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { barState.selectTaskTab(3) }
                } label: {
                    Label("Diagnostic Logs", systemImage: "terminal")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { barState.selectTaskTab(5) }
                } label: {
                    Label("Audit Log (Flight Recorder)", systemImage: "shield.checkered")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { barState.selectTaskTab(6) }
                } label: {
                    Label("Consensus Engine", systemImage: "checkmark.shield")
                }
            } label: {
                HStack(spacing: 3) {
                    if veryCompact && !isSecondaryActive {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 9.5))
                    } else {
                        Text(secondaryLabel)
                            .font(.system(size: 11, weight: isSecondaryActive ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundColor(isSecondaryActive ? .primary : .secondary)
                .padding(.horizontal, veryCompact ? 6 : 7)
                .padding(.vertical, 4)
                .background(isSecondaryActive ? Color.primary.opacity(0.10) : Color.clear)
                .cornerRadius(5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Walkthrough, Cells, Background Agents, Logs, Cost, Audit & Consensus")
        }
        .padding(2)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
        .fixedSize()
    }

    private func pillButton(_ label: String, icon: String, isActive: Bool, badgeDot: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if veryCompact {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                } else {
                    Text(label)
                        .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
                if let dot = badgeDot {
                    Circle()
                        .fill(dot)
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundColor(isActive ? .primary : .secondary)
            .padding(.horizontal, veryCompact ? 6 : 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.primary.opacity(0.10) : Color.clear)
            .cornerRadius(5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(label)
    }
}

private struct UnifiedWorkspacePreviewMenu: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var deviceRuntime = DeviceRuntimeService.shared
    @ObservedObject private var previewDock = PreviewDockService.shared
    var isIconOnly: Bool = false
    @State private var isPopoverPresented = false

    private var isPreviewActive: Bool {
        previewDock.isDockVisible ||
        deviceRuntime.showingEmbeddedDeviceDock ||
        (appState.agenticContextVisible && appState.selectedInspectorTab == .preview)
    }

    var body: some View {
        Button(action: { isPopoverPresented.toggle() }) {
            HStack(spacing: 3) {
                Image(systemName: (isPreviewActive && deviceRuntime.showingEmbeddedAppleDock) ? "iphone" : "apps.iphone")
                    .font(.system(size: 9.5))
                if !isIconOnly {
                    Text("Preview")
                        .font(.system(size: 11, weight: isPreviewActive ? .semibold : .medium))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .foregroundColor(isPreviewActive ? .white : .primary.opacity(0.85))
            .padding(.horizontal, isIconOnly ? 6 : 7)
            .padding(.vertical, 4)
            .background(isPreviewActive ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isPreviewActive ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Live Multi-Platform Preview (Web, iOS Simulator, Android Emulator & USB Devices)")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            PreviewCategoryCardsPopover(isPresented: $isPopoverPresented)
                .environmentObject(appState)
        }
    }
}

private struct PreviewCategoryCardsPopover: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var deviceRuntime = DeviceRuntimeService.shared
    @ObservedObject private var previewDock = PreviewDockService.shared
    @Binding var isPresented: Bool

    @State private var expandedAppleFamily: AppleSimulatorFamily? = nil
    @State private var isAndroidListExpanded: Bool = false
    @State private var simulatorSearchText: String = ""

    private var isPreviewActive: Bool {
        previewDock.isDockVisible ||
        deviceRuntime.showingEmbeddedDeviceDock ||
        (appState.agenticContextVisible && appState.selectedInspectorTab == .preview)
    }

    private var appleSimulators: [RuntimeDevice] {
        deviceRuntime.devices.filter { $0.isAppleSimulator && $0.isReadyForLaunch }
    }

    private var physicalAppleDevices: [RuntimeDevice] {
        deviceRuntime.devices.filter(\.isPhysicalAppleDevice)
    }

    private var androidDevices: [RuntimeDevice] {
        deviceRuntime.devices.filter { $0.platform == .android }
    }

    private var activeOrPhysicalDevices: [RuntimeDevice] {
        let bootedSims = appleSimulators.filter { $0.state.localizedCaseInsensitiveContains("booted") }
        let bootedAndroid = androidDevices.filter {
            $0.state.localizedCaseInsensitiveContains("booted") ||
            $0.state.localizedCaseInsensitiveContains("online") ||
            $0.state.localizedCaseInsensitiveContains("device")
        }
        return physicalAppleDevices + bootedSims + bootedAndroid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top Header: Title + Dock Toggle + Refresh
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "apps.iphone")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text("Live Preview")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        if isPreviewActive {
                            appState.hidePreviewInspector()
                            previewDock.hideDock()
                        } else {
                            appState.showPreviewInspector()
                        }
                    }
                    isPresented = false
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isPreviewActive ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 5.5, height: 5.5)
                        Text(isPreviewActive ? "Hide Dock" : "Show Dock")
                            .font(.system(size: 10.5, weight: .medium))
                        Text("⌥⌘P")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isPreviewActive ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await deviceRuntime.refresh(workspace: appState.workspaceFolder) }
                } label: {
                    Group {
                        if deviceRuntime.isWorking {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                    }
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Refresh Connected Devices & Simulators")
            }

            // CARD 1 (Big Category): Web & Browser
            previewCardContainer {
                VStack(alignment: .leading, spacing: 7) {
                    categoryCardHeader(icon: "globe", iconColor: .blue, title: "Web & Localhost")

                    HStack(spacing: 6) {
                        subActionTile(
                            icon: "rectangle.righthalf.inset.filled",
                            title: "Localhost Dock",
                            subtitle: "Side-by-side web"
                        ) {
                            deviceRuntime.embeddedDockMode = .web
                            withAnimation(.easeInOut(duration: 0.16)) {
                                appState.showPreviewInspector(tab: "web")
                            }
                            isPresented = false
                        }

                        subActionTile(
                            icon: "safari",
                            title: "Full Browser",
                            subtitle: "IDE web workspace"
                        ) {
                            appState.switchToMode(.browser)
                            isPresented = false
                        }
                    }
                }
            }

            // CARD 2 (Big Category): Physical USB & Active Runtimes
            previewCardContainer {
                VStack(alignment: .leading, spacing: 7) {
                    categoryCardHeader(
                        icon: "cable.connector",
                        iconColor: .green,
                        title: "Connected & Active",
                        badgeCount: activeOrPhysicalDevices.isEmpty ? nil : activeOrPhysicalDevices.count
                    )

                    if !activeOrPhysicalDevices.isEmpty {
                        VStack(spacing: 3) {
                            ForEach(activeOrPhysicalDevices) { device in
                                deviceRowButton(device, highlightActive: true)
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        subActionTile(
                            icon: "iphone.gen3",
                            title: "iPhone USB",
                            subtitle: "Physical iOS/iPadOS"
                        ) {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                appState.showPreviewInspector(tab: "ios-physical")
                            }
                            isPresented = false
                        }

                        subActionTile(
                            icon: "flipphone",
                            title: "Android USB",
                            subtitle: "Physical ADB device"
                        ) {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                appState.showPreviewInspector(tab: "android-physical")
                            }
                            isPresented = false
                        }
                    }
                }
            }

            // CARD 3 (Big Category -> Subcategory Family Chips -> Individual Simulators): Apple Simulators
            previewCardContainer {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        categoryCardHeader(
                            icon: "apple.logo",
                            iconColor: .primary,
                            title: "Apple Simulators",
                            badgeCount: appleSimulators.isEmpty ? nil : appleSimulators.count
                        )
                        Spacer()
                        quickDockPill(title: "Open iOS Dock") {
                            deviceRuntime.embeddedDockMode = .ios
                            deviceRuntime.showingEmbeddedAppleDock = true
                            withAnimation(.easeInOut(duration: 0.16)) {
                                appState.showPreviewInspector(tab: "ios")
                            }
                            isPresented = false
                        }
                    }

                    let availableFamilies = AppleSimulatorFamily.previewOrder.filter { fam in
                        appleSimulators.contains(where: { $0.appleSimulatorFamily == fam })
                    }

                    if availableFamilies.isEmpty {
                        Text("No Xcode Simulators detected")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    } else {
                        // Medium Level: Subcategory Family Chips (iPhone, iPad, Watch, TV, Vision)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(availableFamilies) { family in
                                    let count = appleSimulators.filter { $0.appleSimulatorFamily == family }.count
                                    let isExpanded = (expandedAppleFamily == family)
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.16)) {
                                            if expandedAppleFamily == family {
                                                expandedAppleFamily = nil
                                                simulatorSearchText = ""
                                            } else {
                                                expandedAppleFamily = family
                                                simulatorSearchText = ""
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: family.symbolName)
                                                .font(.system(size: 9.5))
                                            Text(shortFamilyName(family))
                                                .font(.system(size: 10.5, weight: isExpanded ? .semibold : .medium))
                                            Text("\(count)")
                                                .font(.system(size: 9.5, design: .monospaced))
                                                .foregroundColor(isExpanded ? .accentColor : .secondary)
                                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                                .font(.system(size: 7, weight: .bold))
                                                .foregroundColor(.secondary)
                                        }
                                        .foregroundColor(isExpanded ? .accentColor : .primary.opacity(0.85))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4.5)
                                        .background(isExpanded ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(isExpanded ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
                                        )
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Small Level: Specific Simulator Models for the selected Subcategory
                        if let selectedFamily = expandedAppleFamily {
                            let familyDevices = sortedDevices(
                                appleSimulators.filter { $0.appleSimulatorFamily == selectedFamily }
                            )
                            let filteredDevices = simulatorSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? familyDevices
                                : familyDevices.filter { $0.name.localizedCaseInsensitiveContains(simulatorSearchText) }

                            VStack(alignment: .leading, spacing: 5) {
                                if familyDevices.count > 6 {
                                    HStack(spacing: 5) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.secondary)
                                        TextField("Filter \(shortFamilyName(selectedFamily)) models…", text: $simulatorSearchText)
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 10.5))
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.05))
                                    .cornerRadius(5)
                                }

                                ScrollView {
                                    VStack(spacing: 2) {
                                        ForEach(filteredDevices) { device in
                                            deviceRowButton(device, highlightActive: false)
                                        }
                                    }
                                }
                                .frame(maxHeight: 156)
                            }
                            .padding(.top, 2)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }

            // CARD 4 (Big Category -> Sub-list): Android Emulator
            previewCardContainer {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        categoryCardHeader(
                            icon: "cpu",
                            iconColor: .mint,
                            title: "Android Emulator",
                            badgeCount: androidDevices.isEmpty ? nil : androidDevices.count
                        )
                        Spacer()
                        quickDockPill(title: "Open Android Dock") {
                            deviceRuntime.embeddedDockMode = .android
                            deviceRuntime.showingEmbeddedAppleDock = false
                            withAnimation(.easeInOut(duration: 0.16)) {
                                appState.showPreviewInspector(tab: "android")
                            }
                            isPresented = false
                        }
                    }

                    if !androidDevices.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isAndroidListExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 9.5))
                                Text("AVD Runtimes (\(androidDevices.count))")
                                    .font(.system(size: 10.5, weight: .medium))
                                Spacer()
                                Image(systemName: isAndroidListExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 7.5, weight: .bold))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        if isAndroidListExpanded {
                            ScrollView {
                                VStack(spacing: 2) {
                                    ForEach(sortedDevices(androidDevices)) { device in
                                        deviceRowButton(device, highlightActive: false)
                                    }
                                }
                            }
                            .frame(maxHeight: 132)
                        }
                    }
                }
            }

            // Bottom Action: Full Device & Run Target Sheet
            Button {
                isPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    deviceRuntime.showingDeviceRuntimeSheet = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.2.square.on.square")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    Text("Choose Device & Run Target…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .cornerRadius(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 356)
    }

    private func shortFamilyName(_ family: AppleSimulatorFamily) -> String {
        switch family {
        case .iPhone: return "iPhone"
        case .iPad: return "iPad"
        case .watch: return "Watch"
        case .tv: return "Apple TV"
        case .vision: return "Vision"
        case .other: return "Other"
        }
    }

    private func sortedDevices(_ list: [RuntimeDevice]) -> [RuntimeDevice] {
        list.sorted { a, b in
            let aBooted = a.state.localizedCaseInsensitiveContains("booted") || a.state.localizedCaseInsensitiveContains("paired")
            let bBooted = b.state.localizedCaseInsensitiveContains("booted") || b.state.localizedCaseInsensitiveContains("paired")
            if aBooted != bBooted { return aBooted }
            return a.name.localizedStandardCompare(b.name) == .orderedDescending
        }
    }

    @ViewBuilder
    private func previewCardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .cornerRadius(9)
    }

    private func categoryCardHeader(icon: String, iconColor: Color, title: String, badgeCount: Int? = nil) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
            if let badgeCount {
                Text("\(badgeCount)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.07))
                    .cornerRadius(4)
            }
        }
    }

    private func quickDockPill(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12))
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    private func subActionTile(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
            .cornerRadius(7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func deviceRowButton(_ device: RuntimeDevice, highlightActive: Bool) -> some View {
        let isOnline = device.state.localizedCaseInsensitiveContains("booted") ||
                       device.state.localizedCaseInsensitiveContains("paired") ||
                       device.state.localizedCaseInsensitiveContains("available") ||
                       device.state.localizedCaseInsensitiveContains("online")
        return Button {
            isPresented = false
            Task { await AgentWorkspaceBarState.openRuntimeDestination(device, appState: appState) }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isOnline ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 5.5, height: 5.5)
                Text(device.name)
                    .font(.system(size: 10.5, weight: isOnline ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(isOnline ? (device.isPhysicalAppleDevice ? "Paired" : "Booted") : "Ready")
                    .font(.system(size: 9.5, weight: isOnline ? .medium : .regular))
                    .foregroundColor(isOnline ? .green : .secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(isOnline ? Color.green.opacity(0.12) : Color.clear)
                    .cornerRadius(4)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4.5)
            .background(highlightActive ? Color.green.opacity(0.06) : Color.primary.opacity(0.025))
            .cornerRadius(5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(deviceRuntime.isWorking || !device.isReadyForLaunch)
    }
}

private struct UnifiedAgentActionsMenu: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var barState = AgentWorkspaceBarState.shared
    @ObservedObject private var acpHost = ACPHostService.shared
    @ObservedObject private var teamIntegrations = TeamIntegrationService.shared
    @ObservedObject private var teamTasks = TeamTaskService.shared
    @ObservedObject private var sessionSummary = AgentSessionSummaryStore.shared
    private var agent: AgentService { AgentService.shared }
    let isCompact: Bool

    private var hasActiveTeamContext: Bool {
        teamIntegrations.teamTasksEnabled && (
            teamTasks.selectedTask != nil ||
            teamIntegrations.enabled.values.contains(true)
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            if hasActiveTeamContext {
                Menu {
                    Button { barState.showingTeamTasks = true } label: {
                        Label("Team Tasks", systemImage: "checklist")
                    }
                    Button { barState.showingTeamIntegrations = true } label: {
                        Label("Configure Team Collaboration", systemImage: "slider.horizontal.3")
                    }
                    if let task = teamTasks.selectedTask {
                        Divider()
                        Text("Active: \(task.title)")
                        Text("\(task.status.label) · \(task.owner)")
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "person.2")
                            .font(.system(size: 9.5, weight: .medium))
                        if !isCompact {
                            Text("Team")
                                .font(.system(size: 11, weight: teamTasks.selectedTask != nil ? .semibold : .medium))
                        }
                        if teamTasks.selectedTask != nil {
                            Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                        }
                    }
                    .foregroundColor(teamTasks.selectedTask != nil ? .primary : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Team Tasks & Collaboration")
            }

            Menu {
                Section("Agents, Rules & MCP") {
                    Button {
                        barState.showingAgentConnections = true
                    } label: {
                        Label("Connect External Agents (1-Click)…", systemImage: "link.badge.plus")
                    }
                    Button {
                        barState.agentEcosystemTab = .rules
                        barState.showingAgentEcosystem = true
                    } label: {
                        Label("Rules, MCP & Context Settings…", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        barState.showingTeamTasks = true
                    } label: {
                        Label("Team Tasks…", systemImage: "checklist")
                    }
                    Button {
                        barState.showingTeamIntegrations = true
                    } label: {
                        Label("Configure Team Collaboration…", systemImage: "person.2")
                    }
                }
                if !acpHost.registeredConfigs.isEmpty {
                    Divider()
                    Section("Switch Active Agent") {
                        ForEach(acpHost.registeredConfigs) { config in
                            Button {
                                AgentWorkspaceBarState.switchToACPConfig(config, appState: appState)
                            } label: {
                                HStack {
                                    Label(config.name, systemImage: config.type.iconName)
                                    if acpHost.activeAgentId == config.id {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        Button {
                            AgentWorkspaceBarState.switchToNativeAgent(appState: appState)
                        } label: {
                            HStack {
                                Label("Use Internal AI", systemImage: "brain")
                                if acpHost.activeAgentId == nil {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Divider()
                Button {
                    Task { await appState.microCodeService?.indexProject() }
                } label: {
                    Label("Index Project", systemImage: "database")
                }
                Divider()
                Button {
                    ARXCapsuleService.shared.exportCapsuleWithSavePanel(
                        chatId: agent.activeChatId,
                        workspacePath: agent.currentWorkspace ?? appState.workspaceFolder?.path
                    )
                } label: {
                    Label("Export .ARX Capsule…", systemImage: "shippingbox.and.arrow.backward")
                }
                Button {
                    ARXCapsuleService.shared.importCapsuleWithOpenPanel(appState: appState)
                } label: {
                    Label("Import .ARX Capsule…", systemImage: "shippingbox")
                }
                if let patchPath = agent.lastImportedArxPatchPath,
                   FileManager.default.fileExists(atPath: patchPath) {
                    Button {
                        let ws = agent.currentWorkspace ?? appState.workspaceFolder?.path ?? ""
                        let res = ARXCapsuleService.shared.applyPatchFile(patchPath, in: ws)
                        agent.messages.append(AgentMessageModel(
                            id: UUID().uuidString,
                            role: .assistant,
                            content: res.success ? "✅ \(res.message)" : "⚠️ \(res.message)",
                            toolResults: [],
                            pendingChanges: [],
                            timestamp: Date()
                        ))
                        agent.saveChats()
                    } label: {
                        Label("Apply Imported .ARX Git Patch", systemImage: "arrow.down.doc.fill")
                    }
                }
                Divider()
                Button {
                    if agent.messages.count >= 2 {
                        agent.messages.removeLast(2)
                        agent.saveChats()
                    }
                } label: {
                    Label("Undo Last", systemImage: "arrow.uturn.backward")
                }
                Button(role: .destructive) {
                    agent.clearCurrentChat()
                    barState.clearChatAttachmentsTrigger &+= 1
                    acpHost.resetAllSessions()
                } label: {
                    Label("Clear Chat", systemImage: "trash")
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                    if !isCompact {
                        Text("Actions")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                    }
                }
                .foregroundColor(.primary.opacity(0.85))
                .padding(.horizontal, isCompact ? 7 : 7)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Agent Actions (External Agents, Rules & MCP, Team, .ARX Capsule, Clear Chat)")
        }
    }
}

struct AgenticLayoutMenu: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var trafficLights = WindowTrafficLightsController.shared

    var body: some View {
        Menu {
            Section("Developer Tools") {
                Button { appState.runCode() } label: { Label("Run Code (⌘R)", systemImage: "play.fill") }
                Button { appState.buildProject() } label: { Label("Build Project (⌘B)", systemImage: "hammer.fill") }
                Button { appState.toggleConsole() } label: { Label(appState.consoleVisible ? "Hide Terminal / Console" : "Show Terminal / Console (⌘J)", systemImage: "terminal.fill") }
            }

            Section("Specialized Studios") {
                Button { appState.showingDatabaseStudio = true } label: { Label("Database Studio", systemImage: "server.rack") }
                Button { 
                    appState.openAPIStudio()
                } label: { Label("API Studio", systemImage: "network") }
                Button { appState.showingContainerView = true } label: { Label("Apple Container Studio", systemImage: "shippingbox.fill") }
                Button { appState.showingCICDView = true } label: { Label("CI/CD Pipelines", systemImage: "checklist") }
                Button { appState.showingCollaborationView = true } label: { Label("Realtime Collaboration", systemImage: "person.2.fill") }
            }

            Section("Window & Panels") {
                Toggle(isOn: $trafficLights.autoHideEnabled) {
                    Label("Auto-Hide Window Controls", systemImage: "macwindow")
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { appState.toggleAgenticContext() }
                } label: {
                    Label(appState.agenticContextVisible ? "Hide Context Inspector" : "Show Context Inspector (⌘I)", systemImage: "sidebar.right")
                }
                Button {
                    appState.settingsSelectedTab = 11
                    appState.showingSettingsDialog = true
                } label: {
                    Label("Connect with Phone (QR)…", systemImage: "qrcode")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Tools & Layout")
    }
}

extension View {
    func agenticTabStyle(active: Bool, compact: Bool = false) -> some View {
        self
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: active ? .semibold : .regular))
            .foregroundColor(active ? .primary : .secondary)
            .padding(.horizontal, compact ? 7 : 10)
            .padding(.vertical, 4)
            .background(active ? Color.primary.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

struct AgenticWorkspaceSidebar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var sessionSummary = AgentSessionSummaryStore.shared
    private var agent: AgentService { AgentService.shared }
    @ObservedObject private var trafficLights = WindowTrafficLightsController.shared
    @Binding var surface: AgenticWorkspaceSurface
    @State private var isProjectsExpanded = true
    @State private var isFilesExpanded = true
    @State private var collapsedProjectIds: Set<String> = []
    @State private var expandedHistoryProjectIds: Set<String> = []
    @State private var hoveredNewConvoButton: Bool = false
    @State private var hoveredProjectId: String? = nil
    @State private var hoveredPlusProjectId: String? = nil
    @State private var hoveredChatId: String? = nil
    @State private var searchText: String = ""
    @State private var isSearchVisible: Bool = false
    @State private var renamingChatId: String? = nil
    @State private var renameText: String = ""

    private let maxPreviewChatsPerWorkspace = 5

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            
            if isSearchVisible {
                sidebarSearchBar
            }
            
            sidebarNewConversationButton
                .padding(.top, 2)
            
            projectsSection
                .padding(.top, 8)
                .padding(.bottom, 8)
            
            if !AppEdition.isStandaloneAI {
                workspaceFilesSection
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, maxHeight: isFilesExpanded ? .infinity : nil, alignment: .top)
                
                if !isFilesExpanded {
                    Spacer(minLength: 0)
                }
            } else if !isProjectsExpanded {
                Spacer(minLength: 0)
            }
            
            sidebarFooter
        }
        .background(Color.clear)
    }

    private func activateAgentSurface() {
        if appState.editorMode != .aiAgent {
            appState.switchToMode(.aiAgent)
        }
        if surface != .agent {
            surface = .agent
        }
    }

    private func createNewConversation(in projectPath: String?, groupId: String? = nil) {
        ImplementationPlanManager.shared.clearPlan()
        let fallbackPath = appState.workspaceFolder?.path ?? agent.currentWorkspace
        let targetPath = (projectPath?.isEmpty == false) ? projectPath : fallbackPath

        isProjectsExpanded = true
        if let gid = groupId {
            collapsedProjectIds.remove(gid)
        }
        if let path = targetPath, !path.isEmpty {
            collapsedProjectIds.remove(path)
            if let canonical = AgentService.canonicalWorkspacePath(path) {
                collapsedProjectIds.remove(canonical)
            }
            agent.setWorkspace(path)
        }

        _ = agent.createNewChat(projectPath: targetPath)
        activateAgentSurface()

        if let path = targetPath, !path.isEmpty {
            let folderURL = URL(fileURLWithPath: path)
            if appState.workspaceFolder?.standardizedFileURL.path != folderURL.standardizedFileURL.path {
                Task { @MainActor in
                    await appState.openWorkspace(url: folderURL, autoOpenEntryFile: false)
                }
            }
        }
    }

    private func selectWorkspaceGroup(_ group: ProjectChatGroup) {
        // Selecting a workspace ALWAYS keeps its conversations visible (never collapses them)
        collapsedProjectIds.remove(group.id)
        if let path = group.projectPath, !path.isEmpty {
            collapsedProjectIds.remove(path)
            agent.setWorkspace(path)
            let folderURL = URL(fileURLWithPath: path)
            if appState.workspaceFolder?.standardizedFileURL.path != folderURL.standardizedFileURL.path {
                Task { @MainActor in
                    await appState.openWorkspace(url: folderURL, autoOpenEntryFile: false)
                }
            }
        }
        // Switch to the latest conversation in this workspace if current active chat belongs elsewhere
        if let activeId = agent.activeChatId,
           !group.chats.contains(where: { $0.id == activeId }),
           let latestChat = group.chats.first {
            agent.switchChat(to: latestChat.id)
        }
        activateAgentSurface()
    }
    
    // MARK: - Header
    @ViewBuilder
    private var sidebarHeader: some View {
        HStack(spacing: 6) {
            Text(AppEdition.displayName)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)

            WindowDragSpacerView()
                .frame(minWidth: 8, maxWidth: .infinity, maxHeight: .infinity)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isSearchVisible.toggle()
                    if !isSearchVisible { searchText = "" }
                }
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(isSearchVisible ? .primary : .secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Search Conversations")
        }
        .padding(.leading, trafficLights.leadingInset(whenVisible: 78, whenHidden: 14))
        .padding(.trailing, 10)
        .frame(height: 36)
        .animation(.easeOut(duration: 0.15), value: trafficLights.showsInlineTrafficLights)
    }

    @ViewBuilder
    private var sidebarSearchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            TextField("Search tasks & conversations...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
    
    @ViewBuilder
    private var sidebarNewConversationButton: some View {
        Button {
            createNewConversation(in: appState.workspaceFolder?.path ?? agent.currentWorkspace)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.primary.opacity(0.92))
                Text("New Conversation")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary.opacity(0.92))
                Spacer()
                Text("⌘N")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.75))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hoveredNewConvoButton ? 0.11 : 0.065))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(hoveredNewConvoButton ? 0.14 : 0.06), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredNewConvoButton = hovering }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .help("Start a New Conversation in Active Workspace (⌘N)")
    }
    
    
    // MARK: - Workspaces & Conversations Section (Distinct MicroCode Obsidian Glass Layout)
    private var estimatedProjectsListHeight: CGFloat {
        let groups = filteredProjectGroups
        if groups.isEmpty { return 36 }
        var total: CGFloat = 8
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        for group in groups {
            total += 30
            if isProjectGroupExpanded(group) {
                let showAll = isSearching || expandedHistoryProjectIds.contains(group.id)
                let visibleCount = showAll ? group.chats.count : min(group.chats.count, maxPreviewChatsPerWorkspace)
                total += CGFloat(visibleCount) * 30
                if !isSearching && group.chats.count > maxPreviewChatsPerWorkspace {
                    total += 24
                }
            }
        }
        return max(total, 64)
    }

    @ViewBuilder
    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("WORKSPACES")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { appState.openFolder() }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Another Workspace Folder…")

                Button(action: { withAnimation(.easeInOut(duration: 0.16)) { isProjectsExpanded.toggle() } }) {
                    Image(systemName: isProjectsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isProjectsExpanded ? "Fold Workspaces Section" : "Expand Workspaces Section")
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)

            if isProjectsExpanded {
                let groups = filteredProjectGroups
                if groups.isEmpty {
                    Text("No matching conversations")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                } else if isFilesExpanded && !AppEdition.isStandaloneAI {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(groups) { group in
                                projectGroupRow(group: group)
                            }
                        }
                    }
                    .frame(height: min(estimatedProjectsListHeight, 240))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(groups) { group in
                                projectGroupRow(group: group)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var filteredProjectGroups: [ProjectChatGroup] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return agent.projectGroups }
        return agent.projectGroups.compactMap { group in
            let matchingChats = group.chats.filter { $0.name.lowercased().contains(q) }
            if group.projectName.lowercased().contains(q) {
                return group
            } else if !matchingChats.isEmpty {
                return ProjectChatGroup(projectName: group.projectName, projectPath: group.projectPath, chats: matchingChats)
            }
            return nil
        }
    }
    
    @ViewBuilder
    private func projectGroupRow(group: ProjectChatGroup) -> some View {
        let isExpanded = isProjectGroupExpanded(group)
        let isActiveWorkspace = isActiveProjectGroup(group)
        let isRowHovered = (hoveredProjectId == group.id)
        let isPlusHovered = (hoveredPlusProjectId == group.id)
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let showAllChats = isSearching || expandedHistoryProjectIds.contains(group.id)
        let visibleChats = showAllChats ? group.chats : Array(group.chats.prefix(maxPreviewChatsPerWorkspace))
        let hiddenCount = max(0, group.chats.count - visibleChats.count)

        VStack(alignment: .leading, spacing: 1) {
            // Sibling button architecture — NEVER nest "+" inside the workspace row Button!
            HStack(spacing: 2) {
                // 1. Dedicated Fold/Unfold Chevron (ONLY control that collapses a workspace's chat list)
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        if isExpanded {
                            collapsedProjectIds.insert(group.id)
                        } else {
                            collapsedProjectIds.remove(group.id)
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.8))
                        .frame(width: 18, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Fold \(group.projectName) Conversations" : "Show \(group.projectName) Conversations")

                // 2. Workspace Selection Button (Switches workspace & guarantees conversations stay open)
                Button {
                    selectWorkspaceGroup(group)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isActiveWorkspace ? "folder.fill" : "folder")
                            .font(.system(size: 12))
                            .foregroundColor(isActiveWorkspace ? .accentColor : .secondary)

                        Text(group.projectName)
                            .font(.system(size: 12.5, weight: isActiveWorkspace ? .semibold : .medium))
                            .foregroundColor(isActiveWorkspace ? .primary : .primary.opacity(0.85))
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if !isExpanded && !group.chats.isEmpty {
                            Text("\(group.chats.count)")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.8))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(4)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Switch Active Workspace to \(group.projectName)")

                // 3. Independent Sibling "+" Button (100% isolated hit target — never collapses chats!)
                Button {
                    createNewConversation(in: group.projectPath, groupId: group.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(isPlusHovered ? .primary : .secondary.opacity(isRowHovered || isActiveWorkspace ? 0.9 : 0.65))
                        .frame(width: 24, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isPlusHovered ? Color.primary.opacity(0.14) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        guard !ChatScrollActivityGate.isScrolling else { return }
                        if hoveredPlusProjectId != group.id { hoveredPlusProjectId = group.id }
                    } else if hoveredPlusProjectId == group.id {
                        hoveredPlusProjectId = nil
                    }
                }
                .help("New Conversation in \(group.projectName)")

                if agent.isWorkspaceRunning(group.projectPath) && !isExpanded {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.65)
                        .frame(width: 12, height: 12)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isRowHovered ? Color.primary.opacity(0.045) : Color.clear)
            )
            .padding(.horizontal, 6)
            .onHover { hovering in
                if hovering {
                    guard !ChatScrollActivityGate.isScrolling else { return }
                    if hoveredProjectId != group.id { hoveredProjectId = group.id }
                } else if hoveredProjectId == group.id {
                    hoveredProjectId = nil
                }
            }
            .contextMenu {
                Button("New Conversation in \(group.projectName)") {
                    createNewConversation(in: group.projectPath, groupId: group.id)
                }
                if let path = group.projectPath, !path.isEmpty {
                    if !AppEdition.isStandaloneAI {
                        Button("Open in Code Editor") {
                            Task { @MainActor in
                                await appState.openWorkspace(url: URL(fileURLWithPath: path))
                                appState.switchToMode(.code)
                            }
                        }
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                    }
                }
                Divider()
                Button(isExpanded ? "Fold Conversations" : "Expand Conversations") {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        if isExpanded {
                            collapsedProjectIds.insert(group.id)
                        } else {
                            collapsedProjectIds.remove(group.id)
                        }
                    }
                }
            }

            if isExpanded {
                ForEach(visibleChats) { chat in
                    projectChatRow(chat: chat, group: group)
                }

                if !isSearching && group.chats.count > maxPreviewChatsPerWorkspace {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            if showAllChats {
                                expandedHistoryProjectIds.remove(group.id)
                            } else {
                                expandedHistoryProjectIds.insert(group.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: showAllChats ? "chevron.up" : "ellipsis")
                                .font(.system(size: 9, weight: .semibold))
                            Text(showAllChats ? "Show recent" : "\(hiddenCount) older conversation\(hiddenCount == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                        }
                        .foregroundColor(.secondary.opacity(0.75))
                        .padding(.leading, 30)
                        .padding(.trailing, 10)
                        .frame(height: 22)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                }
            }
        }
        .padding(.bottom, 3)
    }
    
    @ViewBuilder
    private func projectChatRow(chat: ChatSession, group: ProjectChatGroup) -> some View {
        let isActive = agent.activeChatId == chat.id && surface == .agent
        let isBusy = agent.isChatRunning(chat.id) || (isActive && agent.isLoading && agent.runningChatIds.isEmpty)
        let isHovered = (hoveredChatId == chat.id)
        
        Button {
            agent.switchChat(to: chat.id)
            collapsedProjectIds.remove(group.id)
            if let path = chat.projectPath ?? group.projectPath, !path.isEmpty {
                collapsedProjectIds.remove(path)
                agent.setWorkspace(path)
                let folderURL = URL(fileURLWithPath: path)
                if appState.workspaceFolder?.standardizedFileURL.path != folderURL.standardizedFileURL.path {
                    Task { @MainActor in
                        await appState.openWorkspace(url: folderURL, autoOpenEntryFile: false)
                    }
                }
            }
            activateAgentSurface()
        } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(width: 2.5, height: 14)

                if renamingChatId == chat.id {
                    TextField("Chat Name", text: $renameText, onCommit: {
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            agent.renameChat(chat.id, to: trimmed)
                        }
                        renamingChatId = nil
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 5)
                    .background(Color.primary.opacity(0.1))
                    .cornerRadius(4)
                } else {
                    Text(chat.name)
                        .font(.system(size: 12.5, weight: isActive ? .medium : .regular))
                        .foregroundColor(isActive ? .primary : (isHovered ? .primary.opacity(0.9) : .secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                Spacer(minLength: 4)
                
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 14, height: 14)
                } else {
                    Text(compactRelativeAge(from: chat.updatedAt))
                        .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary.opacity(isActive ? 0.8 : 0.55))
                }
            }
            .padding(.leading, 22)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.primary.opacity(0.09) : (isHovered ? Color.primary.opacity(0.045) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                guard !ChatScrollActivityGate.isScrolling else { return }
                if hoveredChatId != chat.id { hoveredChatId = chat.id }
            } else if hoveredChatId == chat.id {
                hoveredChatId = nil
            }
        }
        .padding(.horizontal, 6)
        .contextMenu {
            Button("Export as .ARX Capsule…") {
                ARXCapsuleService.shared.exportCapsuleWithSavePanel(
                    chatId: chat.id,
                    workspacePath: chat.projectPath ?? group.projectPath
                )
            }
            Divider()
            Button("Rename Conversation…") {
                renameText = chat.name
                renamingChatId = chat.id
            }
            Button("Copy Title") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(chat.name, forType: .string)
            }
            Divider()
            Button("Delete Conversation", role: .destructive) {
                agent.deleteChat(chat.id)
            }
        }
    }

    private func compactRelativeAge(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 30 { return "\(days)d" }
        let months = days / 30
        return "\(months)mo"
    }
    
    @ViewBuilder
    private var workspaceFilesSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("WORKSPACE FILES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { appState.openFolder() }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Folder")

                Button(action: { withAnimation(.easeInOut(duration: 0.16)) { isFilesExpanded.toggle() } }) {
                    Image(systemName: isFilesExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)

            if isFilesExpanded {
                NavigatorView(showsToolbar: false, onOpenFile: { surface = .editor })
                    .environmentObject(appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        if appState.fileTree.isEmpty && appState.workspaceFolder != nil {
                            Task { @MainActor in
                                await appState.refreshFileTree()
                            }
                        }
                    }
            }
        }
    }
    
    // MARK: - Footer
    @ViewBuilder
    private var sidebarFooter: some View {
        HStack(spacing: 10) {
            Button(action: { appState.showingSettingsDialog = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11.5))
                    Text("Settings")
                        .font(.system(size: 11.5, weight: .regular))
                }
                .foregroundColor(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("MicroCode Settings")

            Spacer()

            SidebarPhoneCompanionButton(appState: appState)

            Button(action: { appState.showingSettingsDialog = true }) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("MicroCode Help")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private static func normalizeProjectPath(_ raw: String) -> String {
        var trimmed = raw
        while trimmed.count > 1 && trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return (trimmed as NSString).standardizingPath
    }

    private func isActiveProjectGroup(_ group: ProjectChatGroup) -> Bool {
        if let ws = appState.workspaceFolder?.path ?? agent.currentWorkspace, !ws.isEmpty,
           let groupPath = group.projectPath, !groupPath.isEmpty {
            if ws == groupPath || Self.normalizeProjectPath(ws) == Self.normalizeProjectPath(groupPath) {
                return true
            }
        }
        if let activeId = agent.activeChatId, group.chats.contains(where: { $0.id == activeId }) {
            return true
        }
        return false
    }

    private func isProjectGroupExpanded(_ group: ProjectChatGroup) -> Bool {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        // Default every workspace to expanded; ONLY explicit chevron clicks fold a workspace.
        return !collapsedProjectIds.contains(group.id)
    }
}

private struct SidebarPhoneCompanionButton: View {
    let appState: AppState
    @ObservedObject private var companion = PhoneCompanionService.shared

    private var approvedCount: Int {
        companion.connectedDevices.filter { $0.approvalState == .approved }.count
    }

    var body: some View {
        let pending = companion.pendingApprovalCount
        Button(action: {
            appState.settingsSelectedTab = 11
            appState.showingSettingsDialog = true
        }) {
            HStack(spacing: 4.5) {
                Image(systemName: pending > 0 ? "iphone.radiowaves.left.and.right" : "qrcode")
                    .font(.system(size: 11))
                Text("Phone")
                    .font(.system(size: 11, weight: .medium))

                if pending > 0 {
                    Text("\(pending)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(Color.orange)
                        .clipShape(Capsule())
                } else if companion.isEnabled && approvedCount > 0 {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundColor(pending > 0 ? .primary : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(pending > 0 ? Color.orange.opacity(0.14) : Color.primary.opacity(0.055))
            .cornerRadius(5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pending > 0 ? "\(pending) mobile device(s) waiting for approval" : "Connect with Phone via QR Code or 6-Digit PIN")
    }
}


