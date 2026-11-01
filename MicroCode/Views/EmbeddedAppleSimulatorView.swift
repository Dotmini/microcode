//
//  EmbeddedAppleSimulatorView.swift
//  MicroCode
//

import SwiftUI
import WebKit

/// Interactive iOS Simulator preview. serve-sim supplies a real device frame
/// and forwards mouse, trackpad, and keyboard events to the simulator.
struct EmbeddedAppleSimulatorView: View {
    @ObservedObject var serveSim = ServeSimService.shared
    @ObservedObject private var runtime = DeviceRuntimeService.shared
    var canvasColor: Color = Color(nsColor: .windowBackgroundColor)
    var onConfigure: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil

    private var previewUnavailable: Bool {
        serveSim.connectionState == .failed
    }

    private var previewTitle: String { runtime.selectedApplePreviewTitle }

    private var previewIconName: String {
        if runtime.isSelectedDeviceIPhoneDuo {
            return runtime.iPhoneDuoDisplayMode == .inner ? "book.pages" : "iphone"
        }
        return runtime.selectedApplePreviewSymbolName == "ipad" ? "ipad" : "iphone"
    }

    private func openMatchingWebPreview(stoppingSim: Bool) {
        if stoppingSim {
            runtime.stopEmbeddedAppleSimulator(shutdownSimulator: true)
        }
        if runtime.isSelectedDeviceIPhoneDuo {
            runtime.targetViewport = runtime.iPhoneDuoDisplayMode == .inner ? "iphone duo inner" : "iphone duo outer"
        }
        PreviewDockService.shared.selectTab(id: "web")
    }

    @ViewBuilder
    private func simulatorModelSelectorPill(autoStart: Bool, isFloatingOverlay: Bool = false) -> some View {
        Menu {
            AppleSimulatorSelectorMenuContent(autoStartIfActive: autoStart)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: previewIconName)
                    .font(.system(size: isFloatingOverlay ? 9.5 : 10.5, weight: .semibold))
                Text(runtime.selectedAppleToolbarTitle)
                    .font(.system(size: isFloatingOverlay ? 10 : 11, weight: .semibold))
                    .lineLimit(1)
                if !isFloatingOverlay, let rt = runtime.selectedDevice?.runtime, !rt.isEmpty {
                    Text("· \(rt)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, isFloatingOverlay ? 9 : 11)
            .padding(.vertical, isFloatingOverlay ? 4 : 5)
            .background(
                isFloatingOverlay
                    ? AnyShapeStyle(.regularMaterial)
                    : AnyShapeStyle(Color.primary.opacity(0.08))
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(isFloatingOverlay ? 0.14 : 0.10), lineWidth: 0.8)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("เลือกโมเดล iOS / iPadOS Simulator ที่ตรวจพบในเครื่องนี้")
    }

    @ViewBuilder
    private var duoDisplayModeControls: some View {
        if runtime.isSelectedDeviceIPhoneDuo {
            HStack(spacing: 4) {
                ForEach(IPhoneDuoDisplayMode.allCases) { mode in
                    let isSelected = runtime.iPhoneDuoDisplayMode == mode
                    Button {
                        Task { await runtime.setIPhoneDuoDisplayMode(mode) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 9.5, weight: .semibold))
                            Text(mode.shortLabel)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isSelected ? Color.accentColor : Color.primary.opacity(0.07))
                        .foregroundColor(isSelected ? .white : .primary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(mode.resolutionLabel)
                }
            }
        }
    }

    private func closePreview() {
        runtime.stopEmbeddedAppleSimulator(shutdownSimulator: true)
        if let onHide {
            onHide()
        } else {
            PreviewDockService.shared.hideDock()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                canvasColor
                // Do not remove the WebView during a reconnect. Removing it
                // destroys serve-sim's genuine Apple device frame and is the
                // visible flash/jank users were seeing whenever the stream
                // briefly changed state.
                if let url = serveSim.previewURL {
                    ServeSimPreviewView(url: url)
                } else {
                    AppleDeviceFramePlaceholder(family: runtime.selectedApplePreviewSymbolName)
                }

                if serveSim.previewURL == nil || serveSim.connectionState != .ready {
                    VStack(spacing: 10) {
                        switch serveSim.connectionState {
                        case .idle:
                            Image(systemName: previewIconName)
                                .font(.system(size: 26, weight: .light))
                                .foregroundColor(.secondary)
                            Text("\(previewTitle) Preview")
                                .font(.system(size: 13, weight: .semibold))

                            simulatorModelSelectorPill(autoStart: false)
                            duoDisplayModeControls

                            Text(runtime.isWorking
                                 ? "Booting \(previewTitle)…"
                                 : "เลือกรุ่น iPhone / iPad / iPhone Duo จากเครื่องของคุณ แล้วกด Start Simulator (Idle 0% CPU)")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 290)

                            if runtime.isWorking {
                                ProgressView()
                                    .controlSize(.small)
                                HStack(spacing: 8) {
                                    Button("Stop & Cancel") {
                                        runtime.stopEmbeddedAppleSimulator(shutdownSimulator: true)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                    .controlSize(.small)

                                    Button("Close Preview") {
                                        closePreview()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(.top, 4)
                            } else {
                                HStack(spacing: 8) {
                                    Button("Start Simulator") {
                                        Task { await runtime.startEmbeddedAppleSimulator() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)

                                    Button(runtime.isSelectedDeviceIPhoneDuo ? "Web Preview (Duo)" : "Web Preview") {
                                        openMatchingWebPreview(stoppingSim: false)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Close") {
                                        closePreview()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(.top, 4)
                            }

                        case .connecting:
                            ProgressView()
                                .controlSize(.small)
                            Text("Connecting to \(previewTitle)…")
                                .font(.system(size: 12, weight: .medium))

                            simulatorModelSelectorPill(autoStart: true)
                            duoDisplayModeControls

                            Text(serveSim.statusMessage)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 290)

                            HStack(spacing: 8) {
                                Button("Stop & Cancel") {
                                    runtime.stopEmbeddedAppleSimulator(shutdownSimulator: true)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.small)

                                Button(runtime.isSelectedDeviceIPhoneDuo ? "Web Preview (Duo)" : "Web Preview") {
                                    openMatchingWebPreview(stoppingSim: true)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("Close") {
                                    closePreview()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.top, 4)

                        case .failed:
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.orange)
                            Text("\(previewTitle) Unavailable")
                                .font(.system(size: 12, weight: .semibold))

                            simulatorModelSelectorPill(autoStart: true)
                            duoDisplayModeControls

                            Text(serveSim.statusMessage)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 290)

                            HStack(spacing: 8) {
                                Button("Retry") {
                                    Task { await runtime.startEmbeddedAppleSimulator() }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Button(runtime.isSelectedDeviceIPhoneDuo ? "Web Preview (Duo)" : "Web Preview") {
                                    openMatchingWebPreview(stoppingSim: true)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("Close") {
                                    closePreview()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.top, 4)

                        case .ready:
                            EmptyView()
                        }
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
                }
            }
        }
        .background(canvasColor)
        .onAppear {
            runtime.selectDefaultAppleSimulatorIfNeeded()
        }
    }
}

/// Shared menu listing ready iPhone/iPad/Foldable simulators plus the full dynamic catalog
/// of hardware `SimDeviceType` profiles detected on the user's Mac.
struct AppleSimulatorSelectorMenuContent: View {
    @ObservedObject var runtime = DeviceRuntimeService.shared
    var autoStartIfActive: Bool = true
    var workspaceURL: URL? = nil

    private var hasIPhoneDuoAvailable: Bool {
        runtime.representativeIPhoneDuoSimulator != nil || runtime.detectedAppleModels.contains(where: \.isIPhoneDuo)
    }

    var body: some View {
        if hasIPhoneDuoAvailable {
            Section("Foldable · iPhone Duo") {
                ForEach(IPhoneDuoDisplayMode.allCases) { mode in
                    Button {
                        Task {
                            runtime.iPhoneDuoDisplayMode = mode
                            if runtime.representativeIPhoneDuoSimulator != nil {
                                await runtime.setIPhoneDuoDisplayMode(mode)
                                if autoStartIfActive && !ServeSimService.shared.isActive && runtime.showingEmbeddedAppleDock {
                                    // setIPhoneDuoDisplayMode already starts when dock is active
                                }
                            } else {
                                await runtime.createIPhoneDuoSimulator()
                                if autoStartIfActive && ServeSimService.shared.isActive {
                                    await runtime.startEmbeddedAppleSimulator()
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Label("iPhone Duo — \(mode.shortLabel) (\(mode.resolutionLabel))", systemImage: mode.icon)
                            if runtime.isSelectedDeviceIPhoneDuo && runtime.iPhoneDuoDisplayMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }

        let iPhones = runtime.pickerIPhoneSimulators
        if !iPhones.isEmpty {
            Section("iPhone Simulators") {
                ForEach(iPhones) { sim in
                    Button {
                        Task { await runtime.selectAppleSimulator(sim, autoStartIfActive: autoStartIfActive) }
                    } label: {
                        HStack {
                            let stateSuffix = sim.isBooted ? " · Booted" : ""
                            Label("\(sim.name) (\(sim.runtime)\(stateSuffix))", systemImage: "iphone")
                            if runtime.selectedDeviceID == sim.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }

        let iPads = runtime.pickerIPadSimulators
        if !iPads.isEmpty {
            Section("iPad Simulators") {
                ForEach(iPads) { sim in
                    Button {
                        Task { await runtime.selectAppleSimulator(sim, autoStartIfActive: autoStartIfActive) }
                    } label: {
                        HStack {
                            let stateSuffix = sim.isBooted ? " · Booted" : ""
                            Label("\(sim.name) (\(sim.runtime)\(stateSuffix))", systemImage: "ipad")
                            if runtime.selectedDeviceID == sim.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }

        let others = runtime.pickerOtherAppleSimulators
        if !others.isEmpty {
            Section("Watch / TV / Vision") {
                ForEach(others) { sim in
                    Button {
                        Task { await runtime.selectAppleSimulator(sim, autoStartIfActive: autoStartIfActive) }
                    } label: {
                        HStack {
                            let stateSuffix = sim.isBooted ? " · Booted" : ""
                            Label("\(sim.name) (\(sim.runtime)\(stateSuffix))", systemImage: sim.displaySymbolName)
                            if runtime.selectedDeviceID == sim.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }

        let allIPhones = runtime.detectedIPhoneModels
        let allIPads = runtime.detectedIPadModels
        let allOthers = runtime.detectedOtherAppleModels
        if !allIPhones.isEmpty || !allIPads.isEmpty || !allOthers.isEmpty {
            Divider()
            let existingNames = Set(runtime.appleSimulators.map { $0.name.lowercased() })

            if !allIPhones.isEmpty {
                Menu {
                    ForEach(allIPhones) { model in
                        Button {
                            Task { await runtime.selectOrProvisionDetectedModel(model, autoStartIfActive: autoStartIfActive) }
                        } label: {
                            HStack {
                                let isCreated = existingNames.contains(model.name.lowercased())
                                Text(isCreated ? "\(model.name) · พร้อมใช้" : "+ \(model.name) (\(model.runtimeName))")
                                if runtime.selectedDevice?.name.caseInsensitiveCompare(model.name) == .orderedSame {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("รุ่น iPhone ทั้งหมดในเครื่อง (\(allIPhones.count) รุ่น)…", systemImage: "iphone.badge.plus")
                }
            }

            if !allIPads.isEmpty {
                Menu {
                    ForEach(allIPads) { model in
                        Button {
                            Task { await runtime.selectOrProvisionDetectedModel(model, autoStartIfActive: autoStartIfActive) }
                        } label: {
                            HStack {
                                let isCreated = existingNames.contains(model.name.lowercased())
                                Text(isCreated ? "\(model.name) · พร้อมใช้" : "+ \(model.name) (\(model.runtimeName))")
                                if runtime.selectedDevice?.name.caseInsensitiveCompare(model.name) == .orderedSame {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("รุ่น iPad ทั้งหมดในเครื่อง (\(allIPads.count) รุ่น)…", systemImage: "ipad.badge.play")
                }
            }

            if !allOthers.isEmpty {
                Menu {
                    ForEach(allOthers) { model in
                        Button {
                            Task { await runtime.selectOrProvisionDetectedModel(model, autoStartIfActive: autoStartIfActive) }
                        } label: {
                            HStack {
                                let isCreated = existingNames.contains(model.name.lowercased())
                                Text(isCreated ? "\(model.name) · พร้อมใช้" : "+ \(model.name) (\(model.runtimeName))")
                                if runtime.selectedDevice?.name.caseInsensitiveCompare(model.name) == .orderedSame {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Watch / TV / Vision ในเครื่อง (\(allOthers.count) รุ่น)…", systemImage: "applewatch")
                }
            }
        }

        Divider()
        Button {
            runtime.showingDeviceRuntimeSheet = true
        } label: {
            Label("Choose Device & Run…", systemImage: "slider.horizontal.3")
        }
        Button {
            Task { await runtime.refresh(workspace: workspaceURL, force: true) }
        } label: {
            Label("Refresh Simulators", systemImage: "arrow.clockwise")
        }
    }
}

private struct ServeSimPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(
            source: previewBrandingCleanupScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.load(url, in: view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.load(url, in: view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var loadedURL: String?

        func load(_ url: URL, in webView: WKWebView) {
            // The session query changes only after a helper restart. Normal
            // status/fps updates therefore do not reload WebKit or interrupt
            // touches, while a new helper on the same localhost port always
            // gets a fresh page instead of a permanently black old one.
            guard loadedURL != url.absoluteString else { return }
            loadedURL = url.absoluteString
            webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy))
        }
    }
}

/// Keep a stable portrait device silhouette while a cold simulator is booting
/// or a stream is reconnecting. The actual Apple DeviceKit frame returns as
/// soon as serve-sim is ready; this avoids a distracting empty black panel.
private struct AppleDeviceFramePlaceholder: View {
    let family: String

    var body: some View {
        GeometryReader { proxy in
            if family == "iphone-duo-inner" {
                // iPhone Duo Unfolded Inner Main Display (951:669 book-open ratio)
                let aspect: CGFloat = 951.0 / 669.0
                let width = min(proxy.size.width * 0.88, proxy.size.height * 0.78 * aspect)
                let height = width / aspect
                let outerR = height * 0.056
                let innerR = height * 0.044
                ZStack {
                    RoundedRectangle(cornerRadius: outerR, style: .continuous)
                        .fill(Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: outerR, style: .continuous)
                                .stroke(Color.white.opacity(0.24), lineWidth: 3)
                        )
                    RoundedRectangle(cornerRadius: innerR, style: .continuous)
                        .fill(Color.black.opacity(0.84))
                        .padding(height * 0.025)

                    // Subtle book-fold center crease & hinge caps
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color.white.opacity(0.10), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 1.5, height: height * 0.94)
                }
                .frame(width: width, height: height)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            } else if family == "iphone-duo-outer" {
                // iPhone Duo Folded Cover Display (466:678 ratio, sharp left spine, rounded right)
                let aspect: CGFloat = 466.0 / 678.0
                let height = min(proxy.size.height * 0.80, (proxy.size.width * 0.82) / aspect)
                let width = height * aspect
                let outerShape = UnevenScreenShape(
                    radii: ScreenCornerRadii(
                        topLeft: width * 0.022,
                        topRight: width * 0.11,
                        bottomRight: width * 0.11,
                        bottomLeft: width * 0.022
                    )
                )
                let innerShape = UnevenScreenShape(
                    radii: ScreenCornerRadii(
                        topLeft: width * 0.010,
                        topRight: width * 0.088,
                        bottomRight: width * 0.088,
                        bottomLeft: width * 0.010
                    )
                )
                ZStack {
                    outerShape
                        .fill(Color.black)
                        .overlay(outerShape.stroke(Color.white.opacity(0.24), lineWidth: 3))
                    innerShape
                        .fill(Color.black.opacity(0.84))
                        .padding(.leading, width * 0.052)
                        .padding(.trailing, width * 0.032)
                        .padding(.vertical, width * 0.032)
                    // Left titanium book-fold hinge spine accent
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: max(2, width * 0.014), height: height * 0.94)
                        .offset(x: -width * 0.482)
                    // Dynamic Island
                    Capsule()
                        .fill(Color.black)
                        .frame(width: width * 0.27, height: height * 0.028)
                        .offset(x: width * 0.01, y: -height * 0.43)
                }
                .frame(width: width, height: height)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            } else {
                let height = min(proxy.size.height * 0.82, proxy.size.width * 2.05)
                let width = family == "ipad" ? min(proxy.size.width * 0.78, height * 0.74) : height * 0.49
                ZStack {
                    RoundedRectangle(cornerRadius: width * 0.15, style: .continuous)
                        .fill(Color.black)
                        .overlay(RoundedRectangle(cornerRadius: width * 0.15, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 3))
                    RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
                        .fill(Color.black.opacity(0.82))
                        .padding(width * 0.028)
                    if family == "iphone" {
                        Capsule().fill(Color.black).frame(width: width * 0.31, height: height * 0.026).offset(y: -height * 0.43)
                    }
                }
                .frame(width: width, height: height)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The bundled simulator page is an implementation detail. Keep its device
/// frame and controls, but remove implementation-branding and the large blue
/// DeviceKit placeholder artwork. The native toolbar already uses Apple's SF
/// Symbol, which is sharper and visually consistent with the rest of MicroCode.
private let previewBrandingCleanupScript = """
(() => {
  const injectThemeStyles = () => {
    let style = document.getElementById('microcode-theme-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'microcode-theme-style';
      document.head.appendChild(style);
    }
    style.textContent = `
      html, body, #root, .container, main, [data-serve-sim-root] {
        background: transparent !important;
        background-color: transparent !important;
      }
      :not(html):not(body)[style*="nwse-resize"],
      [role="slider"][style*="nwse-resize"] {
        display: none !important;
        pointer-events: none !important;
      }
    `;
    if (document.documentElement) {
      document.documentElement.style.setProperty('background', 'transparent', 'important');
      document.documentElement.style.setProperty('background-color', 'transparent', 'important');
    }
    if (document.body) {
      document.body.style.setProperty('background', 'transparent', 'important');
      document.body.style.setProperty('background-color', 'transparent', 'important');
    }
  };

  const cleanElement = (element) => {
    if (!(element instanceof Element) || element.children.length !== 0) return;
    const label = (element.textContent || '').trim().toLowerCase();
    if (label === 'serve-sim') {
      element.style.setProperty('display', 'none', 'important');
      return;
    }
    if (label === 'live') {
      element.style.setProperty('display', 'none', 'important');
      const parent = element.parentElement;
      if (parent) {
        parent.querySelectorAll('*').forEach((sibling) => {
          if ((sibling.textContent || '').trim() === '•') {
            sibling.style.setProperty('display', 'none', 'important');
          }
        });
      }
    }
  };
  const cleanTree = (root) => {
    injectThemeStyles();
    cleanElement(root);
    if (root instanceof Element) {
      root.querySelectorAll('*').forEach(cleanElement);
      root.querySelectorAll('[data-microcode-device-art]').forEach((image) => image.remove());
    }
  };
  cleanTree(document.documentElement);
  new MutationObserver((records) => {
    injectThemeStyles();
    for (const record of records) {
      if (record.type === 'characterData') cleanElement(record.target.parentElement);
      record.addedNodes.forEach((node) => {
        if (node instanceof Element) {
          cleanTree(node);
        }
      });
    }
  }).observe(document.documentElement, { childList: true, characterData: true, subtree: true });
})();
"""
