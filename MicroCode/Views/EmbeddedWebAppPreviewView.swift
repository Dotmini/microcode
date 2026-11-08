//
//  EmbeddedWebAppPreviewView.swift
//  MicroCode
//
//  In-app WebApp Preview supporting Desktop, Tablet, and Mobile viewports
//  with live reload, URL bar, and WebEngine kernel.
//

import SwiftUI
import WebKit

// MARK: - Device Frame Specification

struct ScreenCornerRadii: Equatable {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomRight: CGFloat
    let bottomLeft: CGFloat
}

struct DeviceFrameSpec {
    let name: String
    let frameSize: CGSize       // Outer bezel size
    let screenSize: CGSize      // Inner viewport size
    let screenOffset: CGPoint   // Top-left origin of inner screen relative to top-left of outer frame
    let cornerRadius: CGFloat   // Inner screen corner radius
    let isMacBook: Bool         // If true, use top rounded corners & bottom flat
    var cornerRadii: ScreenCornerRadii? = nil
}

// MARK: - Screen Shape Definitions (macOS 13+ compatible)

struct UnevenScreenShape: Shape {
    let radii: ScreenCornerRadii

    func path(in rect: CGRect) -> Path {
        let maxR = min(rect.width, rect.height) * 0.5
        let tl = min(max(0, radii.topLeft), maxR)
        let tr = min(max(0, radii.topRight), maxR)
        let br = min(max(0, radii.bottomRight), maxR)
        let bl = min(max(0, radii.bottomLeft), maxR)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                radius: tr,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                radius: br,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                radius: bl,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                radius: tl,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }
        path.closeSubpath()
        return path
    }
}

struct MacBookScreenShape: Shape {
    var topRadius: CGFloat = 10
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(topRadius, min(rect.width / 2, rect.height / 2))
        
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct ScreenClipShape: Shape {
    let cornerRadius: CGFloat
    let isMacBook: Bool
    var cornerRadii: ScreenCornerRadii? = nil
    
    func path(in rect: CGRect) -> Path {
        if isMacBook {
            return MacBookScreenShape(topRadius: cornerRadius).path(in: rect)
        } else if let cornerRadii {
            return UnevenScreenShape(radii: cornerRadii).path(in: rect)
        } else {
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        }
    }
}

// MARK: - Viewports & Device Options

enum WebAppViewport: String, CaseIterable, Identifiable {
    case responsive = "Responsive"
    case iphone = "iPhone"
    case iphoneDuoOuter = "iPhone Duo (Outer)"
    case iphoneDuoInner = "iPhone Duo (Inner)"
    case tablet = "iPad"
    case macbook = "MacBook"
    
    var id: String { rawValue }

    var isIPhoneDuo: Bool {
        self == .iphoneDuoOuter || self == .iphoneDuoInner
    }

    var providesOrientationSpecificBezel: Bool {
        isIPhoneDuo
    }
    
    var icon: String {
        switch self {
        case .responsive: return "arrow.left.and.right"
        case .iphone: return "iphone"
        case .iphoneDuoOuter: return "iphone"
        case .iphoneDuoInner: return "book.pages"
        case .tablet: return "ipad"
        case .macbook: return "laptopcomputer"
        }
    }
    
    var defaultWidth: CGFloat? {
        switch self {
        case .responsive: return nil
        case .iphone: return 447.0
        case .iphoneDuoOuter: return 466.0
        case .iphoneDuoInner: return 951.0
        case .tablet: return 646.0
        case .macbook: return 802.0
        }
    }
    
    var defaultHeight: CGFloat? {
        switch self {
        case .responsive: return nil
        case .iphone: return 972.0
        case .iphoneDuoOuter: return 678.0
        case .iphoneDuoInner: return 669.0
        case .tablet: return 938.0
        case .macbook: return 503.0
        }
    }
    
    var subtitle: String {
        switch self {
        case .responsive: return "Fluid Responsive • Drag handles to resize freely"
        case .iphone: return "iPhone 16 Pro • Official Apple Bezel Frame"
        case .iphoneDuoOuter: return "iPhone Duo (จอนอก · Cover 466×678 pt @3x) • Apple Book-Fold Frame"
        case .iphoneDuoInner: return "iPhone Duo (จอใน · Unfolded 951×669 pt @3x) • Apple Foldable Frame"
        case .tablet: return "iPad Pro • Official Apple Bezel Frame"
        case .macbook: return "MacBook Pro • Official Apple Bezel Frame"
        }
    }
    
    func frameSpec(isLandscape: Bool = false) -> DeviceFrameSpec? {
        switch self {
        case .responsive:
            return nil
            
        case .iphone:
            if isLandscape {
                return DeviceFrameSpec(
                    name: "iPhone 16 Pro (Landscape)",
                    frameSize: CGSize(width: 1024.0, height: 490.0),
                    screenSize: CGSize(width: 972.0, height: 447.0),
                    screenOffset: CGPoint(x: 26.0, y: 22.0),
                    cornerRadius: 46.0,
                    isMacBook: false
                )
            }
            return DeviceFrameSpec(
                name: "iPhone 16 Pro",
                frameSize: CGSize(width: 490.0, height: 1024.0),
                screenSize: CGSize(width: 447.0, height: 972.0),
                screenOffset: CGPoint(x: 22.0, y: 26.0),
                cornerRadius: 46.0,
                isMacBook: false
            )

        case .iphoneDuoOuter:
            if isLandscape {
                return DeviceFrameSpec(
                    name: "iPhone Duo — จอนอก (Landscape)",
                    frameSize: CGSize(width: 706.0, height: 514.0),
                    screenSize: CGSize(width: 678.0, height: 466.0),
                    screenOffset: CGPoint(x: 14.0, y: 26.0),
                    cornerRadius: 59.0,
                    isMacBook: false,
                    cornerRadii: ScreenCornerRadii(topLeft: 8.0, topRight: 8.0, bottomRight: 59.0, bottomLeft: 59.0)
                )
            }
            return DeviceFrameSpec(
                name: "iPhone Duo — จอนอก (Outer Cover)",
                frameSize: CGSize(width: 514.0, height: 706.0),
                screenSize: CGSize(width: 466.0, height: 678.0),
                screenOffset: CGPoint(x: 26.0, y: 14.0),
                cornerRadius: 59.0,
                isMacBook: false,
                cornerRadii: ScreenCornerRadii(topLeft: 8.0, topRight: 59.0, bottomRight: 59.0, bottomLeft: 8.0)
            )

        case .iphoneDuoInner:
            // Default unfolded book-open posture is 951×669 pt (nativeOrientation: 270°);
            // toggling orientation rotates the unfolded display 90° to 669×951 pt portrait.
            if isLandscape {
                return DeviceFrameSpec(
                    name: "iPhone Duo — จอใน (Portrait 669×951)",
                    frameSize: CGSize(width: 703.0, height: 985.0),
                    screenSize: CGSize(width: 669.0, height: 951.0),
                    screenOffset: CGPoint(x: 17.0, y: 17.0),
                    cornerRadius: 55.0,
                    isMacBook: false
                )
            }
            return DeviceFrameSpec(
                name: "iPhone Duo — จอใน (Unfolded 951×669)",
                frameSize: CGSize(width: 985.0, height: 703.0),
                screenSize: CGSize(width: 951.0, height: 669.0),
                screenOffset: CGPoint(x: 17.0, y: 17.0),
                cornerRadius: 55.0,
                isMacBook: false
            )
            
        case .tablet:
            if isLandscape {
                return DeviceFrameSpec(
                    name: "iPad Pro (Landscape)",
                    frameSize: CGSize(width: 1024.0, height: 729.0),
                    screenSize: CGSize(width: 938.0, height: 646.0),
                    screenOffset: CGPoint(x: 43.0, y: 42.0),
                    cornerRadius: 18.0,
                    isMacBook: false
                )
            }
            return DeviceFrameSpec(
                name: "iPad Pro",
                frameSize: CGSize(width: 729.0, height: 1024.0),
                screenSize: CGSize(width: 646.0, height: 938.0),
                screenOffset: CGPoint(x: 42.0, y: 43.0),
                cornerRadius: 18.0,
                isMacBook: false
            )
            
        case .macbook:
            return DeviceFrameSpec(
                name: "MacBook Pro",
                frameSize: CGSize(width: 1024.0, height: 673.0),
                screenSize: CGSize(width: 802.0, height: 503.0),
                screenOffset: CGPoint(x: 111.0, y: 94.0),
                cornerRadius: 10.0,
                isMacBook: true
            )
        }
    }
    
    func bezelImage(isLandscape: Bool = false) -> NSImage? {
        switch self {
        case .iphone:
            return DeviceFrameAssets.loadIPhoneProBezel()
        case .iphoneDuoOuter:
            return DeviceFrameAssets.loadIPhoneDuoOuterBezel(isLandscape: isLandscape)
        case .iphoneDuoInner:
            return DeviceFrameAssets.loadIPhoneDuoInnerBezel(isRotatedPortrait: isLandscape)
        case .tablet:
            return DeviceFrameAssets.loadIPadProBezel()
        case .macbook:
            return DeviceFrameAssets.loadMacBookProBezel()
        default:
            return nil
        }
    }
}

enum DeviceZoomMode: String, CaseIterable, Identifiable {
    case fit = "Fit Window"
    case fitWidth = "Fit Width"
    case actual = "100%"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .fit: return "arrow.down.right.and.arrow.up.left"
        case .fitWidth: return "arrow.left.and.right"
        case .actual: return "viewfinder"
        }
    }
}

struct EmbeddedWebAppPreviewView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var runtime: DeviceRuntimeService
    var canvasColor: Color = Color(nsColor: .windowBackgroundColor)
    var onHide: (() -> Void)? = nil
    
    @State private var urlString: String = "http://localhost:3000"
    @State private var currentURL: URL? = URL(string: "http://localhost:3000")
    @State private var pageTitle: String = "WebApp Preview"
    @State private var isLoading: Bool = false
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var refreshTrigger: Bool = false
    @State private var goBackTrigger: Bool = false
    @State private var goForwardTrigger: Bool = false
    
    // Viewport & Device States
    @State private var selectedViewport: WebAppViewport = .responsive
    @State private var customWidth: CGFloat? = nil
    @State private var isDraggingHandle: Bool = false
    @State private var dragInitialWidth: CGFloat = 0
    @State private var showDeviceBezel: Bool = true
    @State private var isLandscape: Bool = false
    @State private var zoomMode: DeviceZoomMode = .fit
    @State private var isLiveReloadEnabled: Bool = true
    @State private var localWorkspaceIndexURL: URL? = nil
    @State private var isHoveringHandle: Bool = false
    @ObservedObject private var browserAutomation = IDEBrowserAutomationService.shared
    @ObservedObject private var universalBridge = UniversalAppPreviewBridge.shared
    @ObservedObject private var portTunnels = DevPortTunnelService.shared
    @State private var inspectInstructionText: String = ""
    @State private var showPortRadarPopover: Bool = false
    @State private var customTunnelPortText: String = "3000"
    @State private var qrPreviewPort: Int? = nil
    @State private var copiedTunnelPort: Int? = nil
    @State private var inspectPopupDragOffset: CGSize = .zero
    @State private var inspectPopupAccumulatedOffset: CGSize = .zero
    @FocusState private var isInspectInputFocused: Bool
    @State private var showPromotedCaptureCard: Bool = false
    @State private var captureCopiedFeedback: Bool = false
    @State private var captureSentFeedback: Bool = false
    
    var body: some View {
        previewRootContent
            .background(canvasColor)
            .onChange(of: browserAutomation.pickedElements.count) { newCount in
                if newCount == 0 {
                    inspectPopupDragOffset = .zero
                    inspectPopupAccumulatedOffset = .zero
                } else if newCount == 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isInspectInputFocused = true
                    }
                }
            }
            .onAppear {
                if runtime.targetViewport.lowercased() != "responsive" {
                    handleTargetViewportChange(runtime.targetViewport)
                }
                detectLocalWorkspaceIndex()
                resolveInitialURL()
                browserAutomation.scanActivePorts()
                universalBridge.refreshDetectedFramework()
            }
            .onChange(of: appState.currentFile?.path) { newPath in
                universalBridge.refreshDetectedFramework(activeFilePath: newPath, activeCode: appState.currentFile?.content)
            }
            .onChange(of: browserAutomation.activePortProcesses) { processes in
                handleActivePortProcessesChange(processes)
            }
            .onChange(of: runtime.targetWebURL) { newURL in
                if let newURL = newURL {
                    sanitizeAndSetURL(newURL.absoluteString)
                }
            }
            .onChange(of: runtime.webRefreshTrigger) { _ in
                refreshTrigger = true
            }
            .onChange(of: runtime.targetViewport) { newVP in
                handleTargetViewportChange(newVP)
            }
            .onChange(of: runtime.lastDetectedDevServerPort) { newPort in
                if let port = newPort, runtime.targetWebURL == nil, currentURL?.isFileURL != true {
                    sanitizeAndSetURL("http://localhost:\(port)")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeFileSaved"))) { note in
                handleFileSavedNotification(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeEditorFolderOpened"))) { _ in
                runtime.targetWebURL = nil
                detectLocalWorkspaceIndex()
                resolveInitialURL()
                browserAutomation.scanActivePorts()
                universalBridge.refreshDetectedFramework()
            }
    }

    private func handleActivePortProcessesChange(_ processes: [ActiveLocalPortProcess]) {
        guard !processes.isEmpty else { return }
        let preferredPorts = [5173, 5174, 4173, 3000, 8080, 4200, 4321, 8000]
        let activePorts = Set(processes.map(\.port))
        let currentPort = currentURL?.port
        let isDeadLocalhostPort = (currentPort != nil && !activePorts.contains(currentPort!))
        let isBundlerFileURL = (currentURL?.isFileURL == true && workspaceRequiresDevServer())
        if isDeadLocalhostPort || isBundlerFileURL || urlString.isEmpty {
            let wsPort = detectPreferredWorkspacePort()
            if activePorts.contains(wsPort) {
                sanitizeAndSetURL("http://localhost:\(wsPort)")
            } else if let match = preferredPorts.first(where: { activePorts.contains($0) }) ?? processes.first?.port {
                sanitizeAndSetURL("http://localhost:\(match)")
            }
        }
    }

    private func handleTargetViewportChange(_ newVP: String) {
        let key = newVP.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.contains("responsive") || key.contains("fluid") {
            selectedViewport = .responsive
            customWidth = nil
        } else if key.contains("duo") || key.contains("fold") || key.contains("จอนอก") || key.contains("จอใน") {
            let wantsInner = key.contains("inner") || key.contains("unfold") || key.contains("จอใน") || key.contains("main")
            selectedViewport = wantsInner ? .iphoneDuoInner : .iphoneDuoOuter
            isLandscape = false
            showDeviceBezel = true
        } else if key.contains("macbook") || key.contains("desktop") || key.contains("pc") || key.contains("laptop") {
            selectedViewport = .macbook
            showDeviceBezel = true
        } else if key.contains("ipad") || key.contains("tablet") {
            selectedViewport = .tablet
            showDeviceBezel = true
        } else if key.contains("iphone") || key.contains("mobile") || key.contains("phone") {
            selectedViewport = .iphone
            showDeviceBezel = true
        } else if let match = WebAppViewport.allCases.first(where: { $0.rawValue.lowercased() == key }) {
            selectedViewport = match
            if match != .responsive { showDeviceBezel = true }
        }
    }

    @ViewBuilder
    private var previewRootContent: some View {
        VStack(spacing: 0) {
            previewTopControlBar
            buildLogsDrawerSection
            runtimeIssueBannerSection
            Divider()
            previewInteractiveCanvasSection
        }
    }

    @ViewBuilder
    private var previewTopControlBar: some View {
        // MARK: - Unified Slim Preview Control Bar (Single 30px Row)
        HStack(spacing: 5) {
                // 1. Navigation Controls (< > ↻)
                HStack(spacing: 2) {
                    Button {
                        goBackTrigger = true
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 18, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canGoBack)
                    .help("Back")

                    Button {
                        goForwardTrigger = true
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 18, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canGoForward)
                    .help("Forward")

                    Button {
                        refreshTrigger = true
                    } label: {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.45)
                                .frame(width: 18, height: 20)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .medium))
                                .frame(width: 18, height: 20)
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Reload Page (⌘R)")
                }

                // 2. Compact Viewport & Frame Menu
                Menu {
                    Section("Device Viewport") {
                        ForEach(WebAppViewport.allCases) { vp in
                            Button {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    if vp.isIPhoneDuo && selectedViewport != vp {
                                        isLandscape = false
                                    }
                                    selectedViewport = vp
                                    if vp != .responsive {
                                        showDeviceBezel = true
                                        customWidth = nil
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: vp.icon)
                                    Text(vp.rawValue)
                                    if selectedViewport == vp {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    if selectedViewport == .responsive {
                        Divider()
                        Section("Responsive Breakpoints") {
                            Button("Fluid (100% Full Width)") { withAnimation { customWidth = nil } }
                            Button("Mobile S (320 px)") { withAnimation { customWidth = 320 } }
                            Button("Mobile M (375 px)") { withAnimation { customWidth = 375 } }
                            Button("Mobile L (430 px)") { withAnimation { customWidth = 430 } }
                            Button("Tablet (768 px)") { withAnimation { customWidth = 768 } }
                            Button("Laptop (1024 px)") { withAnimation { customWidth = 1024 } }
                            Button("Desktop (1280 px)") { withAnimation { customWidth = 1280 } }
                            Button("Wide (1440 px)") { withAnimation { customWidth = 1440 } }
                        }
                    } else {
                        Divider()
                        Button(showDeviceBezel ? "Hide Hardware Frame" : "Show Hardware Frame") {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showDeviceBezel.toggle()
                            }
                        }
                        if selectedViewport.isIPhoneDuo {
                            Button(selectedViewport == .iphoneDuoOuter ? "Unfold to Inner Screen (จอใน · 951×669)" : "Fold to Outer Screen (จอนอก · 466×678)") {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                    isLandscape = false
                                    selectedViewport = (selectedViewport == .iphoneDuoOuter) ? .iphoneDuoInner : .iphoneDuoOuter
                                    showDeviceBezel = true
                                }
                            }
                        }
                        if selectedViewport != .macbook {
                            let rotateLabel: String = {
                                if selectedViewport == .iphoneDuoInner {
                                    return isLandscape ? "Rotate to Unfolded Landscape (951×669)" : "Rotate to Unfolded Portrait (669×951)"
                                }
                                return isLandscape ? "Switch to Portrait" : "Switch to Landscape"
                            }()
                            Button(rotateLabel) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isLandscape.toggle()
                                }
                            }
                        }
                        Menu("Zoom (\(zoomMode.rawValue))") {
                            Button("Fit Window") { zoomMode = .fit }
                            Button("Fit Width") { zoomMode = .fitWidth }
                            Button("Actual Size (100%)") { zoomMode = .actual }
                        }
                    }

                    Divider()
                    Button(isLiveReloadEnabled ? "Pause Live Reload on Save" : "Enable Live Reload on Save") {
                        isLiveReloadEnabled.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: selectedViewport.icon)
                            .font(.system(size: 9.5, weight: .medium))
                        Text(selectedViewport == .responsive ? (customWidth != nil ? "\(Int(customWidth!))px" : "Responsive") : selectedViewport.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(Color.primary.opacity(0.06))
                    .foregroundColor(.primary)
                    .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Viewport Preset, Breakpoints & Device Frame")

                // 2b. Quick Fold / Unfold Switcher for iPhone Duo (จอนอก ↔ จอใน)
                if selectedViewport.isIPhoneDuo {
                    HStack(spacing: 2) {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                if selectedViewport != .iphoneDuoOuter {
                                    isLandscape = false
                                    selectedViewport = .iphoneDuoOuter
                                    showDeviceBezel = true
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "iphone")
                                    .font(.system(size: 8.5, weight: .semibold))
                                Text("จอนอก")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(selectedViewport == .iphoneDuoOuter ? Color.accentColor : Color.clear)
                            .foregroundColor(selectedViewport == .iphoneDuoOuter ? .white : .secondary)
                            .cornerRadius(3.5)
                        }
                        .buttonStyle(.plain)
                        .help("iPhone Duo — จอนอก (Outer Cover Display · 466×678 pt)")

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                if selectedViewport != .iphoneDuoInner {
                                    isLandscape = false
                                    selectedViewport = .iphoneDuoInner
                                    showDeviceBezel = true
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "book.pages")
                                    .font(.system(size: 8.5, weight: .semibold))
                                Text("จอใน")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(selectedViewport == .iphoneDuoInner ? Color.accentColor : Color.clear)
                            .foregroundColor(selectedViewport == .iphoneDuoInner ? .white : .secondary)
                            .cornerRadius(3.5)
                        }
                        .buttonStyle(.plain)
                        .help("iPhone Duo — จอใน (Unfolded Inner Main Display · 951×669 pt)")
                    }
                    .padding(2)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(5)
                    .fixedSize()
                }

                // 3. URL Input Bar
                HStack(spacing: 4) {
                    Image(systemName: currentURL?.isFileURL == true ? "doc.fill" : (urlString.hasPrefix("https") ? "lock.fill" : "globe"))
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)

                    TextField("http://localhost:3000", text: $urlString)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5, design: .monospaced))
                        .onSubmit {
                            loadNavigatedURL()
                        }

                    if let devPort = runtime.lastDetectedDevServerPort,
                       !urlString.contains(":\(devPort)"),
                       (currentURL?.port == nil || !browserAutomation.activePortProcesses.contains(where: { $0.port == currentURL?.port })) {
                        Button {
                            sanitizeAndSetURL("http://localhost:\(devPort)")
                        } label: {
                            Text(verbatim: ":\(devPort)")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.08))
                                .foregroundColor(.primary)
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help("Switch to detected local dev server on port \(devPort)")
                    }

                    if !urlString.isEmpty {
                        Button {
                            urlString = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)

                // 4. Multi-Point Click-to-Inspect DOM Element Toggle (Formal Monochrome)
                Button {
                    browserAutomation.toggleInspectMode(target: "preview")
                } label: {
                    HStack(spacing: 3.5) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 10, weight: browserAutomation.isInspectMode ? .bold : .medium))
                        if !browserAutomation.pickedElements.isEmpty {
                            Text("\(browserAutomation.pickedElements.count)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 0.5)
                                .background(Color.primary.opacity(0.14))
                                .cornerRadius(3)
                        }
                    }
                    .padding(.horizontal, browserAutomation.pickedElements.isEmpty ? 0 : 6)
                    .frame(minWidth: 22, minHeight: 22, maxHeight: 22)
                    .background((browserAutomation.isInspectMode || !browserAutomation.pickedElements.isEmpty) ? Color.primary.opacity(0.18) : Color.primary.opacity(0.06))
                    .foregroundColor((browserAutomation.isInspectMode || !browserAutomation.pickedElements.isEmpty) ? .primary : .secondary)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Multi-Point Inspect in Preview — Click multiple elements, Right-Click, or Drag to select")

                // 5. Active Port Radar Popover Button
                Button {
                    showPortRadarPopover.toggle()
                    if showPortRadarPopover {
                        if let activePort = currentURL?.port, (1...65535).contains(activePort),
                           (customTunnelPortText.isEmpty || customTunnelPortText == "3000") {
                            customTunnelPortText = "\(activePort)"
                        }
                        browserAutomation.scanActivePorts()
                    }
                } label: {
                    let hasActiveTunnels = portTunnels.activeTunnelCount > 0
                    HStack(spacing: 3) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 9, weight: hasActiveTunnels ? .semibold : .medium))
                        if !browserAutomation.activePortProcesses.isEmpty {
                            Text("\(browserAutomation.activePortProcesses.count)")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        }
                        if hasActiveTunnels {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5.5, height: 5.5)
                        }
                    }
                    .padding(.horizontal, 5)
                    .frame(height: 22)
                    .background(
                        hasActiveTunnels
                            ? Color.green.opacity(showPortRadarPopover ? 0.22 : 0.14)
                            : (showPortRadarPopover ? Color.primary.opacity(0.16) : Color.primary.opacity(0.06))
                    )
                    .foregroundColor(
                        hasActiveTunnels
                            ? Color.green
                            : (showPortRadarPopover ? .primary : .secondary)
                    )
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(portTunnels.activeTunnelCount > 0 ? "Active Localhost Ports (\(portTunnels.activeTunnelCount) HTTPS tunnel\(portTunnels.activeTunnelCount == 1 ? "" : "s") active)" : "Active Localhost Ports & HTTPS Tunnel")
                .popover(isPresented: $showPortRadarPopover, arrowEdge: .bottom) {
                    portRadarPopoverContent
                }

                // 6. Universal Build & Hot-Reload Compact Controls
                Button {
                    let targetSize = selectedViewport.frameSpec(isLandscape: isLandscape)?.screenSize
                        ?? CGSize(width: effectiveActiveWidth() ?? 960, height: 640)
                    Task {
                        await universalBridge.buildAndPreview(viewportSize: targetSize)
                    }
                } label: {
                    HStack(spacing: 3) {
                        if universalBridge.isBuilding {
                            ProgressView()
                                .scaleEffect(0.45)
                                .frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8.5, weight: .semibold))
                        }
                        Text(universalBridge.isBuilding ? "Build…" : "Build")
                            .font(.system(size: 9.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(Color.primary.opacity(0.10))
                    .foregroundColor(.primary)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Build & Preview (\(universalBridge.effectiveFramework.rawValue))")

                Button {
                    universalBridge.triggerHotReload(
                        savedFilePath: appState.currentFile?.path,
                        liveCode: appState.currentFile?.content,
                        reason: "Manual"
                    )
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.06))
                        .foregroundColor(.primary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Instant Hot Reload (\(universalBridge.effectiveFramework.rawValue))")

                if universalBridge.isRunning {
                    Button {
                        universalBridge.stopRunningPreview()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8.5, weight: .bold))
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.secondary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Stop running app preview process")
                }

                // 7. Consolidated More / Framework / Logs Menu
                Menu {
                    Section("Target Runtime (\(universalBridge.effectiveFramework.shortBadge))") {
                        ForEach(UniversalPreviewFramework.allCases) { fw in
                            Button {
                                universalBridge.selectedFramework = fw
                                universalBridge.refreshDetectedFramework()
                            } label: {
                                HStack {
                                    Image(systemName: fw.icon)
                                    Text(fw == .auto ? "Auto-Detect (\(universalBridge.detectedFramework.rawValue))" : fw.rawValue)
                                    if universalBridge.selectedFramework == fw {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    if universalBridge.renderedNativeImage != nil {
                        Button(universalBridge.isUsingNativeCanvas ? "Switch to Web Surface" : "Switch to Native GUI Surface") {
                            universalBridge.isUsingNativeCanvas.toggle()
                        }
                    }

                    Button(universalBridge.showBuildLogsDrawer ? "Hide Build & Hot-Reload Logs" : "Show Build & Hot-Reload Logs") {
                        universalBridge.toggleLogsDrawer()
                    }

                    if let localURL = localWorkspaceIndexURL {
                        Divider()
                        Button("Preview Workspace index.html") {
                            sanitizeAndSetURL(localURL.absoluteString)
                        }
                    }

                    Divider()

                    Button("Copy Preview URL") {
                        if let url = currentURL {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        }
                    }

                    Button("Open in External Browser") {
                        if let url = currentURL {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    Button("Hard Reload & Clear Cache") {
                        WebEngine.shared.clearCache()
                        refreshTrigger = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10.5, weight: .medium))
                        .frame(width: 22, height: 22)
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Preview Options, Framework Target & Logs")
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(canvasColor)
    }

    @ViewBuilder
    private var portRadarPopoverContent: some View {
        let detectedPortSet = Set(browserAutomation.activePortProcesses.map(\.port))
        let standaloneTunnelPorts = portTunnels.tunnels.keys
            .filter { !detectedPortSet.contains($0) && portTunnels.tunnels[$0] != .stopped }
            .sorted()
        let parsedCustomPort: Int? = {
            let trimmed = customTunnelPortText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let val = Int(trimmed), (1...65535).contains(val) else { return nil }
            return val
        }()

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(portTunnels.activeTunnelCount > 0 ? .green : .primary)
                Text("Active Localhost Ports")
                    .font(.system(size: 11, weight: .bold))
                if portTunnels.activeTunnelCount > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text("\(portTunnels.activeTunnelCount) live")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(4)
                }
                Spacer()
                Button {
                    browserAutomation.scanActivePorts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Rescan listening TCP ports")

                if portTunnels.activeTunnelCount > 0 {
                    Button("Stop Tunnels") {
                        portTunnels.stopAllTunnels()
                        qrPreviewPort = nil
                    }
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.orange)
                    .buttonStyle(.plain)
                }

                if !browserAutomation.activePortProcesses.isEmpty {
                    Button("Kill All") {
                        browserAutomation.killAllDevPortProcesses()
                    }
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.red)
                    .buttonStyle(.plain)
                }
            }

            // Quick Expose Port bar — expose any TCP port via public HTTPS immediately
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Quick Expose Port")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("Port", text: $customTunnelPortText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(width: 58)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                    .onSubmit {
                        if let port = parsedCustomPort {
                            portTunnels.startTunnel(for: port)
                        }
                    }
                Spacer(minLength: 2)
                Button {
                    if let port = parsedCustomPort {
                        portTunnels.startTunnel(for: port)
                    }
                } label: {
                    HStack(spacing: 3.5) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Start HTTPS Tunnel")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(parsedCustomPort != nil ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                    .foregroundColor(parsedCustomPort != nil ? .accentColor : .secondary)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(parsedCustomPort == nil)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.035))
            .cornerRadius(5)

            Divider()

            if browserAutomation.isScanningPorts && browserAutomation.activePortProcesses.isEmpty && standaloneTunnelPorts.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.5)
                    Text("Scanning listening TCP ports...")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else if browserAutomation.activePortProcesses.isEmpty && standaloneTunnelPorts.isEmpty {
                Text("No active user localhost servers detected.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        if browserAutomation.isScanningPorts {
                            HStack(spacing: 5) {
                                ProgressView().scaleEffect(0.45)
                                Text("Refreshing active ports…")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.bottom, 2)
                        }

                        ForEach(standaloneTunnelPorts, id: \.self) { port in
                            let tunnelState = portTunnels.tunnels[port] ?? .stopped
                            let isTunnelActive = isPortTunnelActive(tunnelState)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(":\(port)")
                                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .frame(width: 50, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Custom Port Tunnel")
                                            .font(.system(size: 10, weight: .medium))
                                            .lineLimit(1)
                                        Text("127.0.0.1:\(port)")
                                            .font(.system(size: 8.5, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button("Preview") {
                                        sanitizeAndSetURL("http://localhost:\(port)")
                                        showPortRadarPopover = false
                                    }
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.12))
                                    .foregroundColor(.primary)
                                    .cornerRadius(4)
                                    .buttonStyle(.plain)

                                    Button {
                                        if isTunnelActive {
                                            portTunnels.stopTunnel(for: port)
                                            if qrPreviewPort == port { qrPreviewPort = nil }
                                        } else {
                                            portTunnels.startTunnel(for: port)
                                        }
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "globe")
                                                .font(.system(size: 9, weight: .semibold))
                                            Text(isTunnelActive ? "Stop" : "Tunnel")
                                                .font(.system(size: 9.5, weight: .semibold))
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(isTunnelActive ? Color.green.opacity(0.18) : Color.primary.opacity(0.10))
                                        .foregroundColor(isTunnelActive ? .green : .primary)
                                        .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                }

                                if tunnelState != .stopped {
                                    portTunnelStatusStrip(for: port, state: tunnelState)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(5)
                        }

                        ForEach(browserAutomation.activePortProcesses) { item in
                            let tunnelState = portTunnels.tunnels[item.port] ?? .stopped
                            let isTunnelActive = isPortTunnelActive(tunnelState)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(":\(item.port)")
                                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .frame(width: 50, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.processName)
                                            .font(.system(size: 10, weight: .medium))
                                            .lineLimit(1)
                                        Text("PID \(item.pid)")
                                            .font(.system(size: 8.5, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button("Preview") {
                                        sanitizeAndSetURL("http://localhost:\(item.port)")
                                        showPortRadarPopover = false
                                    }
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.12))
                                    .foregroundColor(.primary)
                                    .cornerRadius(4)
                                    .buttonStyle(.plain)

                                    Button {
                                        if isTunnelActive {
                                            portTunnels.stopTunnel(for: item.port)
                                            if qrPreviewPort == item.port { qrPreviewPort = nil }
                                        } else {
                                            portTunnels.startTunnel(for: item.port)
                                        }
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "globe")
                                                .font(.system(size: 9, weight: .semibold))
                                            Text(isTunnelActive ? "Stop" : "Tunnel")
                                                .font(.system(size: 9.5, weight: .semibold))
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(isTunnelActive ? Color.green.opacity(0.18) : Color.primary.opacity(0.10))
                                        .foregroundColor(isTunnelActive ? .green : .primary)
                                        .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                    .help(isTunnelActive ? "Stop public HTTPS tunnel on port \(item.port)" : "Expose port \(item.port) via zero-setup public HTTPS tunnel")

                                    Button {
                                        browserAutomation.killPortProcess(item)
                                    } label: {
                                        Image(systemName: "xmark.octagon.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Kill process \(item.processName) (PID \(item.pid)) on port \(item.port)")
                                }

                                if tunnelState != .stopped {
                                    portTunnelStatusStrip(for: item.port, state: tunnelState)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(5)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(10)
        .frame(width: 360)
    }

    private func isPortTunnelActive(_ state: DevPortTunnelState) -> Bool {
        switch state {
        case .starting, .connected:
            return true
        case .stopped, .failed:
            return false
        }
    }

    @ViewBuilder
    private func portTunnelStatusStrip(for port: Int, state: DevPortTunnelState) -> some View {
        switch state {
        case .stopped:
            EmptyView()

        case .starting(let message):
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.45)
                    .frame(width: 11, height: 11)
                Text(message)
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.035))
            .cornerRadius(4)

        case .connected(let url, let provider):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5.5, height: 5.5)
                    Text(url)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.green)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help("\(provider) — \(url)")
                    Spacer(minLength: 4)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                        copiedTunnelPort = port
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedTunnelPort == port {
                                copiedTunnelPort = nil
                            }
                        }
                    } label: {
                        HStack(spacing: 2.5) {
                            Image(systemName: copiedTunnelPort == port ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text(copiedTunnelPort == port ? "Copied" : "Copy")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(copiedTunnelPort == port ? Color.green.opacity(0.18) : Color.primary.opacity(0.10))
                        .foregroundColor(copiedTunnelPort == port ? .green : .primary)
                        .cornerRadius(3.5)
                    }
                    .buttonStyle(.plain)

                    Button("Open") {
                        if let parsed = URL(string: url) {
                            NSWorkspace.shared.open(parsed)
                        }
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.10))
                    .foregroundColor(.primary)
                    .cornerRadius(3.5)
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            qrPreviewPort = (qrPreviewPort == port) ? nil : port
                        }
                    } label: {
                        HStack(spacing: 2.5) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text("QR")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(qrPreviewPort == port ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.10))
                        .foregroundColor(qrPreviewPort == port ? .accentColor : .primary)
                        .cornerRadius(3.5)
                    }
                    .buttonStyle(.plain)
                }

                if qrPreviewPort == port, let qrImage = portTunnels.qrCodeImage(for: url) {
                    HStack(spacing: 10) {
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 120, height: 120)
                            .cornerRadius(6)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("Scan with iPhone or Android camera to open this HTTPS preview on any network.")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(5)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.06))
            .cornerRadius(4)

        case .failed(let errorMessage):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9.5))
                    .foregroundColor(.orange)
                Text(errorMessage)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button("Retry") {
                    portTunnels.startTunnel(for: port)
                }
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.10))
                .cornerRadius(3.5)
                .buttonStyle(.plain)

                Button {
                    portTunnels.stopTunnel(for: port)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(4)
        }
    }

    @ViewBuilder
    private var buildLogsDrawerSection: some View {
        if universalBridge.showBuildLogsDrawer {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("UNIVERSAL BUILD & HOT-RELOAD OUTPUT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        universalBridge.toggleLogsDrawer()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                ScrollView {
                    Text(universalBridge.buildLogs.isEmpty ? "No build logs yet. Click 'Build & Preview' to compile and run." : universalBridge.buildLogs)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 92)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.18))
        }
    }

    @ViewBuilder
    private var runtimeIssueBannerSection: some View {
        if browserAutomation.totalRuntimeIssueCount > 0 {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                Text("\(browserAutomation.totalRuntimeIssueCount) Error(s)")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: true, vertical: false)
                Text(browserAutomation.runtimeErrorEntries.last?.message ?? "Failed network/asset request")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Button {
                    browserAutomation.dispatchAutoHealToAgent(pageURL: urlString)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 8.5))
                        Text("Fix in Agent")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.orange.opacity(0.18))
                    .foregroundColor(.orange)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help("Send all console errors, stack traces, and broken asset URLs to AI Agent to fix")

                Button {
                    browserAutomation.clearRuntimeIssues()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear error badge")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.06))
        }
    }

    @ViewBuilder
    private var previewInteractiveCanvasSection: some View {
        GeometryReader { geo in
            ZStack {
                canvasColor
                let availW = geo.size.width
                let availH = geo.size.height
                previewViewportLayer(availW: availW, availH: availH)
                activeInspectModeBannerLayer(availW: availW)
                floatingInspectPopoverLayer(availW: availW, availH: availH)
            }
        }
    }

    @ViewBuilder
    private func previewViewportLayer(availW: CGFloat, availH: CGFloat) -> some View {
        if showDeviceBezel, let spec = selectedViewport.frameSpec(isLandscape: isLandscape) {
                        // MARK: Authentic Hardware Bezel Mode (Direct Scaled Geometry — 100% AppKit WKWebView Frame Alignment)
                        let maxW = max(60, availW - 6)
                        let maxH = max(60, availH - 6)
                        let fitScale = min(maxW / spec.frameSize.width, maxH / spec.frameSize.height)
                        let fitWidthScale = maxW / spec.frameSize.width
                        let activeScale: CGFloat = {
                            switch zoomMode {
                            case .fit: return fitScale
                            case .fitWidth: return fitWidthScale
                            case .actual: return 1.0
                            }
                        }()
                        let scaledFrameW = spec.frameSize.width * activeScale
                        let scaledFrameH = spec.frameSize.height * activeScale
                        let scaledScreenW = spec.screenSize.width * activeScale
                        let scaledScreenH = spec.screenSize.height * activeScale
                        let scaledOffsetX = spec.screenOffset.x * activeScale
                        let scaledOffsetY = spec.screenOffset.y * activeScale
                        let scaledCornerRadius = spec.cornerRadius * activeScale
                        let scaledCornerRadii = spec.cornerRadii.map {
                            ScreenCornerRadii(
                                topLeft: $0.topLeft * activeScale,
                                topRight: $0.topRight * activeScale,
                                bottomRight: $0.bottomRight * activeScale,
                                bottomLeft: $0.bottomLeft * activeScale
                            )
                        }
                        
                        let topSafeAreaUnscaled: CGFloat = {
                            if spec.isMacBook { return 0 }
                            switch selectedViewport {
                            case .iphone:
                                return isLandscape ? 0 : 48
                            case .iphoneDuoOuter:
                                return isLandscape ? 0 : 30
                            case .iphoneDuoInner:
                                return 26
                            case .tablet:
                                return 22
                            default:
                                return 0
                            }
                        }()
                        let scaledTopSafe = topSafeAreaUnscaled * activeScale
                        let webSurfaceH = max(40, scaledScreenH - scaledTopSafe)
                        let webCornerRadii: ScreenCornerRadii = {
                            if scaledTopSafe > 0 {
                                if let cr = scaledCornerRadii {
                                    return ScreenCornerRadii(topLeft: 0, topRight: 0, bottomRight: cr.bottomRight, bottomLeft: cr.bottomLeft)
                                }
                                return ScreenCornerRadii(topLeft: 0, topRight: 0, bottomRight: scaledCornerRadius, bottomLeft: scaledCornerRadius)
                            }
                            if let cr = scaledCornerRadii { return cr }
                            return ScreenCornerRadii(topLeft: scaledCornerRadius, topRight: scaledCornerRadius, bottomRight: scaledCornerRadius, bottomLeft: scaledCornerRadius)
                        }()

                        let deviceView = ZStack {
                            // 1. Screen backdrop + Native Device Status Bar Safe Area (prevents Dynamic Island & 55pt/59pt top corners from overlapping web app header)
                            ZStack(alignment: .top) {
                                Color.white
                                if scaledTopSafe > 0 {
                                    HStack(spacing: 0) {
                                        Text(verbatim: "9:41")
                                            .font(.system(size: max(8, 13 * activeScale), weight: .semibold))
                                            .foregroundColor(.black.opacity(0.86))
                                        Spacer(minLength: 4)
                                        HStack(spacing: max(2, 4.5 * activeScale)) {
                                            Image(systemName: "cellularbars")
                                            Image(systemName: "wifi")
                                            Image(systemName: "battery.100")
                                        }
                                        .font(.system(size: max(7, 11.5 * activeScale), weight: .semibold))
                                        .foregroundColor(.black.opacity(0.86))
                                    }
                                    .padding(.leading, (selectedViewport == .iphoneDuoOuter ? 18 : 28) * activeScale)
                                    .padding(.trailing, (selectedViewport == .iphoneDuoOuter ? 32 : 28) * activeScale)
                                    .padding(.top, (selectedViewport == .iphone ? 14 : 6) * activeScale)
                                    .frame(width: scaledScreenW, height: scaledTopSafe, alignment: .top)
                                    .background(Color.white)
                                }
                            }
                            .frame(width: scaledScreenW, height: scaledScreenH)
                            .clipShape(ScreenClipShape(cornerRadius: scaledCornerRadius, isMacBook: spec.isMacBook, cornerRadii: scaledCornerRadii))
                            .position(
                                x: scaledOffsetX + scaledScreenW / 2,
                                y: scaledOffsetY + scaledScreenH / 2
                            )
                            
                            // 2. Interactive WebBrowserView or Universal Native GUI Surface (positioned below Status Bar / Dynamic Island so web content never overlaps)
                            previewSurfaceContent(
                                width: scaledScreenW,
                                height: webSurfaceH,
                                pageZoom: activeScale,
                                cornerRadius: scaledCornerRadius,
                                isMacBook: spec.isMacBook,
                                cornerRadii: webCornerRadii
                            )
                            .frame(width: scaledScreenW, height: webSurfaceH)
                            .clipShape(ScreenClipShape(cornerRadius: scaledCornerRadius, isMacBook: spec.isMacBook, cornerRadii: webCornerRadii))
                            .position(
                                x: scaledOffsetX + scaledScreenW / 2,
                                y: scaledOffsetY + scaledTopSafe + webSurfaceH / 2
                            )
                            
                            // 3. Authentic Hardware Bezel Overlay
                            if let bezel = selectedViewport.bezelImage(isLandscape: isLandscape) {
                                if isLandscape && selectedViewport != .macbook && !selectedViewport.providesOrientationSpecificBezel {
                                    Image(nsImage: bezel)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: scaledFrameH, height: scaledFrameW)
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: scaledFrameW, height: scaledFrameH)
                                        .position(
                                            x: scaledFrameW / 2,
                                            y: scaledFrameH / 2
                                        )
                                        .allowsHitTesting(false)
                                } else {
                                    Image(nsImage: bezel)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: scaledFrameW, height: scaledFrameH)
                                        .position(
                                            x: scaledFrameW / 2,
                                            y: scaledFrameH / 2
                                        )
                                        .allowsHitTesting(false)
                                }
                            } else {
                                ScreenClipShape(cornerRadius: scaledCornerRadius, isMacBook: spec.isMacBook, cornerRadii: scaledCornerRadii)
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 4 * activeScale)
                                    .frame(width: scaledScreenW, height: scaledScreenH)
                                    .position(
                                        x: scaledOffsetX + scaledScreenW / 2,
                                        y: scaledOffsetY + scaledScreenH / 2
                                    )
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(width: scaledFrameW, height: scaledFrameH)
                        .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 6)
                        
                        if zoomMode == .fitWidth || zoomMode == .actual {
                            ScrollView([.horizontal, .vertical]) {
                                deviceView
                                    .padding(.vertical, 6)
                            }
                            .frame(width: availW, height: availH)
                        } else {
                            deviceView
                                .frame(width: availW, height: availH)
                        }
                    } else if let activeW = effectiveActiveWidth() {
                        // MARK: Clean Responsive Screen Mode with Bilateral Drag Handles
                        let targetW = activeW
                        let isWiderThanDock = targetW > (availW - 36)
                        let fitScale = isWiderThanDock ? min(1.0, (availW - 36) / targetW) : 1.0
                        let activeScale = (zoomMode == .fit) ? fitScale : 1.0
                        
                        let cleanView = ZStack {
                            // The Web Content Viewport Card
                            VStack(spacing: 0) {
                                // Subtle top status header with live dimension readout
                                HStack {
                                    Circle().fill(Color.red.opacity(0.6)).frame(width: 7, height: 7)
                                    Circle().fill(Color.yellow.opacity(0.6)).frame(width: 7, height: 7)
                                    Circle().fill(Color.green.opacity(0.6)).frame(width: 7, height: 7)
                                    Spacer()
                                    Text("↔ \(Int(targetW)) px • \(selectedViewport.rawValue)")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button {
                                        withAnimation {
                                            selectedViewport = .responsive
                                            customWidth = nil
                                        }
                                    } label: {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.system(size: 8))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Reset to Fluid Full Width")
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.04))
                                
                                Divider()
                                
                                previewSurfaceContent(width: targetW, height: max(200, availH - 44))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.white)
                            }
                            .frame(width: targetW)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
                            
                            // Left & Right Interactive Drag Handles
                            HStack {
                                // Left Drag Handle
                                ZStack {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(width: 20)
                                        .contentShape(Rectangle())
                                    
                                    Capsule()
                                        .fill(isDraggingHandle || isHoveringHandle ? Color.accentColor : Color.secondary.opacity(0.4))
                                        .frame(width: 4, height: 44)
                                }
                                .offset(x: -10)
                                .onHover { inside in
                                    isHoveringHandle = inside
                                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                                }
                                .gesture(
                                    DragGesture(minimumDistance: 1)
                                        .onChanged { val in
                                            if !isDraggingHandle {
                                                isDraggingHandle = true
                                                dragInitialWidth = targetW
                                            }
                                            let newWidth = max(280, dragInitialWidth - val.translation.width * 2)
                                            customWidth = newWidth
                                        }
                                        .onEnded { _ in
                                            isDraggingHandle = false
                                            dragInitialWidth = 0
                                        }
                                )
                                
                                Spacer()
                                
                                // Right Drag Handle
                                ZStack {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(width: 20)
                                        .contentShape(Rectangle())
                                    
                                    Capsule()
                                        .fill(isDraggingHandle || isHoveringHandle ? Color.accentColor : Color.secondary.opacity(0.4))
                                        .frame(width: 4, height: 44)
                                }
                                .offset(x: 10)
                                .onHover { inside in
                                    isHoveringHandle = inside
                                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                                }
                                .gesture(
                                    DragGesture(minimumDistance: 1)
                                        .onChanged { val in
                                            if !isDraggingHandle {
                                                isDraggingHandle = true
                                                dragInitialWidth = targetW
                                            }
                                            let newWidth = max(280, dragInitialWidth + val.translation.width * 2)
                                            customWidth = newWidth
                                        }
                                        .onEnded { _ in
                                            isDraggingHandle = false
                                            dragInitialWidth = 0
                                        }
                                )
                            }
                            .frame(width: targetW)
                        }
                        
                        if zoomMode == .actual && isWiderThanDock {
                            ScrollView([.horizontal, .vertical]) {
                                cleanView.padding(20)
                            }
                            .frame(width: availW, height: availH)
                        } else {
                            cleanView
                                .scaleEffect(activeScale)
                                .padding(.vertical, 12)
                                .frame(width: availW, height: availH)
                        }
                    } else {
                        // MARK: Fluid Full Width Responsive Mode (Reflows with Dock)
                        ZStack(alignment: .trailing) {
                            previewSurfaceContent(width: availW, height: availH)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.white)
                            
                            // Right Drag Inward Handle (Seamlessly drag into custom responsive width)
                            ZStack {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 16)
                                    .contentShape(Rectangle())
                                
                                Capsule()
                                    .fill(isDraggingHandle || isHoveringHandle ? Color.accentColor : Color.secondary.opacity(0.35))
                                    .frame(width: 4, height: 40)
                            }
                            .onHover { inside in
                                isHoveringHandle = inside
                                if inside {
                                    NSCursor.resizeLeftRight.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { val in
                                        if !isDraggingHandle {
                                            isDraggingHandle = true
                                            dragInitialWidth = availW
                                        }
                                        let newWidth = max(280, dragInitialWidth + val.translation.width)
                                        customWidth = newWidth
                                    }
                                    .onEnded { _ in
                                        isDraggingHandle = false
                                        dragInitialWidth = 0
                                    }
                            )
                        }
                    }
    }

    @ViewBuilder
    private func activeInspectModeBannerLayer(availW: CGFloat) -> some View {
        // MARK: - Active Inspect Mode Hint Pill (When No Elements Picked Yet)
        if browserAutomation.isInspectMode && browserAutomation.pickedElements.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                Text("MULTI-POINT INSPECT ACTIVE — คลิกเลือกหลายจุดบนหน้าเว็บ, คลิกขวา หรือลากคลุมเพื่อเลือกหลายองค์ประกอบพร้อมกัน")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Button {
                    browserAutomation.toggleInspectMode(false, target: "preview")
                } label: {
                    Text("Exit")
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.12))
                        .foregroundColor(.primary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primary.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 10, x: 0, y: 4)
            .position(x: availW / 2, y: 26)
            .zIndex(998)
        }
    }

    @ViewBuilder
    private func floatingInspectPopoverLayer(availW: CGFloat, availH: CGFloat) -> some View {
        // MARK: - Floating Contextual Multi-Point Inspect Popover
        if let anchor = browserAutomation.pickedElements.first ?? browserAutomation.lastPickedElement,
           !browserAutomation.pickedElements.isEmpty {
            let selectedCount = browserAutomation.pickedElements.count
            let vpW = max(1, CGFloat(anchor.viewportWidth))
            let vpH = max(1, CGFloat(anchor.viewportHeight))
            let elCenterX = ((CGFloat(anchor.boundsX) + CGFloat(anchor.boundsWidth) * 0.5) / vpW) * availW
            let elTopY = (CGFloat(anchor.boundsY) / vpH) * availH
            let elBottomY = ((CGFloat(anchor.boundsY) + CGFloat(anchor.boundsHeight)) / vpH) * availH
            
            let cardW = min(max(320, availW - 24), 440)
            let estimatedRowsH = CGFloat(min(selectedCount, 3)) * 54.0
            let cardH: CGFloat = 128 + estimatedRowsH
            let minX = cardW / 2 + 12
            let maxX = max(minX, availW - cardW / 2 - 12)
            let baseX = min(max(minX, elCenterX), maxX)
            
            let prefersBelow = (elBottomY + cardH + 18) <= availH
            let rawY = prefersBelow ? (elBottomY + cardH / 2 + 10) : (elTopY - cardH / 2 - 10)
            let minY = cardH / 2 + 12
            let maxY = max(minY, availH - cardH / 2 - 12)
            let baseY = min(max(minY, rawY), maxY)
            
            let finalX = min(max(minX, baseX + inspectPopupAccumulatedOffset.width + inspectPopupDragOffset.width), maxX)
            let finalY = min(max(minY, baseY + inspectPopupAccumulatedOffset.height + inspectPopupDragOffset.height), maxY)
            
            VStack(alignment: .leading, spacing: 8) {
                inspectPopoverHeaderView(selectedCount: selectedCount)
                Divider().opacity(0.5)
                inspectSelectedElementsListView(selectedCount: selectedCount)
                inspectPresetChipsScrollView
                inspectBatchPromptInputRow(selectedCount: selectedCount)
            }
            .padding(10)
            .frame(width: cardW)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.primary.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 6)
            .position(x: finalX, y: finalY)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
            .zIndex(999)
        }
    }

    @ViewBuilder
    private func inspectPopoverHeaderView(selectedCount: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "viewfinder")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("INSPECT SELECTION")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
            
            Text("\(selectedCount) POINT\(selectedCount == 1 ? "" : "S")")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.1))
                .foregroundColor(.secondary)
                .cornerRadius(4)
            
            Spacer(minLength: 4)
            
            Button {
                browserAutomation.toggleInspectMode(target: "preview")
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: browserAutomation.isInspectMode ? "checkmark.circle.fill" : "plus.viewfinder")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(browserAutomation.isInspectMode ? "Picking Active" : "Add Spot")
                        .font(.system(size: 9.5, weight: .medium))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(browserAutomation.isInspectMode ? Color.primary.opacity(0.18) : Color.primary.opacity(0.07))
                .foregroundColor(.primary)
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Toggle continuous multi-point picking on the preview page")
            
            if selectedCount > 1 {
                Button {
                    browserAutomation.clearPickedElement(target: "preview")
                } label: {
                    Text("Clear All")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Clear all selected points")
            }
            
            Button {
                browserAutomation.clearPickedElement(target: "preview")
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Close inspect panel")
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { val in
                    inspectPopupDragOffset = val.translation
                }
                .onEnded { val in
                    inspectPopupAccumulatedOffset.width += val.translation.width
                    inspectPopupAccumulatedOffset.height += val.translation.height
                    inspectPopupDragOffset = .zero
                }
        )
    }

    @ViewBuilder
    private func inspectSelectedElementsListView(selectedCount: Int) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(browserAutomation.pickedElements.enumerated()), id: \.element.id) { idx, item in
                    inspectSelectedElementRow(idx: idx, item: item, selectedCount: selectedCount)
                }
            }
        }
        .frame(maxHeight: selectedCount == 1 ? 64 : min(CGFloat(selectedCount) * 62, 184))
    }

    @ViewBuilder
    private func inspectSelectedElementRow(idx: Int, item: BrowserPickedElement, selectedCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text("#\(idx + 1)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.14))
                    .foregroundColor(.primary)
                    .cornerRadius(3)
                
                Button {
                    browserAutomation.focusPickedElementOnPage(item, target: "preview")
                } label: {
                    Text(item.selector)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("Click to scroll to #\(idx + 1) in preview")
                
                Text(item.rect)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if !item.text.isEmpty {
                    Text("· \(item.text)")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                Spacer(minLength: 4)
                
                Button {
                    browserAutomation.removePickedElement(id: item.id, target: "preview")
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .help("Remove target #\(idx + 1)")
            }
            
            TextField(
                selectedCount > 1
                    ? "คำสั่งเฉพาะจุดที่ #\(idx + 1) (เว้นว่างได้หากใช้คำสั่งรวมด้านล่าง)..."
                    : "รายละเอียดเพิ่มเติมสำหรับจุดนี้ (ไม่บังคับ)...",
                text: Binding(
                    get: {
                        guard idx < browserAutomation.pickedElements.count else { return "" }
                        return browserAutomation.pickedElements[idx].note
                    },
                    set: { newValue in
                        guard idx < browserAutomation.pickedElements.count else { return }
                        browserAutomation.pickedElements[idx].note = newValue
                    }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 10.5))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .padding(6)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(5)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private struct InspectPresetItem: Identifiable {
        var id: String { label }
        let iconName: String
        let label: String
        let preset: String
    }

    private var inspectPresetItems: [InspectPresetItem] {
        [
            InspectPresetItem(iconName: "paintbrush", label: "ปรับสีและสไตล์", preset: "ปรับโทนสี พื้นหลัง และสไตล์ของจุดที่เลือกให้เข้ากับธีมและดูเป็นทางการ"),
            InspectPresetItem(iconName: "textformat", label: "แก้ไขข้อความ", preset: "แก้ไขข้อความในจุดที่เลือก: "),
            InspectPresetItem(iconName: "rectangle.3.group", label: "จัด Layout / ระยะห่าง", preset: "จัดระเบียบ Layout, ขนาด และระยะห่าง (padding/margin/alignment) ของจุดที่เลือกทั้งหมดให้สมดุลเท่ากัน"),
            InspectPresetItem(iconName: "square.resize", label: "ปรับขนาดให้เท่ากัน", preset: "ปรับขนาดความกว้าง/ความสูงและสัดส่วนของจุดที่เลือกทั้งหมดให้เท่ากันอย่างเป็นระเบียบ"),
            InspectPresetItem(iconName: "wrench.and.screwdriver", label: "แก้บั๊ก / การทำงาน", preset: "ตรวจสอบและแก้ไขบั๊กการแสดงผลหรือ Event/State ของจุดที่เลือกทั้งหมด")
        ]
    }

    @ViewBuilder
    private var inspectPresetChipsScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(inspectPresetItems) { item in
                    Button {
                        if item.label.contains("แก้ไขข้อความ") {
                            inspectInstructionText = item.preset
                            isInspectInputFocused = true
                        } else {
                            browserAutomation.sendPickedElementsToAgent(
                                browserAutomation.pickedElements,
                                instruction: item.preset,
                                pageURL: urlString,
                                autoSend: true
                            )
                            inspectInstructionText = ""
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: item.iconName)
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(item.label)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.primary.opacity(0.9))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func inspectBatchPromptInputRow(selectedCount: Int) -> some View {
        HStack(spacing: 6) {
            TextField(
                selectedCount > 1
                    ? "คำสั่งรวมสำหรับทั้ง \(selectedCount) จุด... (กด Enter ส่งทันที)"
                    : "สั่ง AI แก้ไขจุดนี้... (กด Enter ส่งทันที)",
                text: $inspectInstructionText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .focused($isInspectInputFocused)
            .padding(.horizontal, 8)
            .padding(.vertical, 5.5)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(isInspectInputFocused ? 0.35 : 0.14), lineWidth: 1)
            )
            .onSubmit {
                browserAutomation.sendPickedElementsToAgent(
                    browserAutomation.pickedElements,
                    instruction: inspectInstructionText,
                    pageURL: urlString,
                    autoSend: true
                )
                inspectInstructionText = ""
            }
            
            Button {
                browserAutomation.sendPickedElementsToAgent(
                    browserAutomation.pickedElements,
                    instruction: inspectInstructionText,
                    pageURL: urlString,
                    autoSend: false
                )
                inspectInstructionText = ""
            } label: {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.08))
                    .foregroundColor(.primary)
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Attach all selected points to Chat input without sending immediately")
            
            Button {
                browserAutomation.sendPickedElementsToAgent(
                    browserAutomation.pickedElements,
                    instruction: inspectInstructionText,
                    pageURL: urlString,
                    autoSend: true
                )
                inspectInstructionText = ""
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 10))
                    Text(selectedCount > 1 ? "Send (\(selectedCount))" : "Send")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary)
                .foregroundColor(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Send all selected points to AI Agent and edit code immediately")
        }
    }

    @ViewBuilder
    private func previewSurfaceContent(
        width: CGFloat,
        height: CGFloat,
        pageZoom: CGFloat = 1.0,
        cornerRadius: CGFloat = 0,
        isMacBook: Bool = false,
        cornerRadii: ScreenCornerRadii? = nil
    ) -> some View {
        if universalBridge.isUsingNativeCanvas, let nativeImg = universalBridge.renderedNativeImage {
            GeometryReader { canvasGeo in
                let w = max(1, canvasGeo.size.width)
                let h = max(1, canvasGeo.size.height)
                ZStack(alignment: .topLeading) {
                    Color(nsColor: .windowBackgroundColor)
                    Image(nsImage: nativeImg)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Render pinned multi-point inspect badges over Native Canvas
                    ForEach(Array(browserAutomation.pickedElements.enumerated()), id: \.element.id) { idx, item in
                        let vpW = max(1, CGFloat(item.viewportWidth))
                        let vpH = max(1, CGFloat(item.viewportHeight))
                        let rx = (CGFloat(item.boundsX) / vpW) * w
                        let ry = (CGFloat(item.boundsY) / vpH) * h
                        let rw = max(24, (CGFloat(item.boundsWidth) / vpW) * w)
                        let rh = max(24, (CGFloat(item.boundsHeight) / vpH) * h)
                        
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary, lineWidth: 1.5)
                                .background(Color.primary.opacity(0.08))
                                .frame(width: rw, height: rh)
                            
                            Text("#\(idx + 1)")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color(nsColor: .windowBackgroundColor))
                                .foregroundColor(.primary)
                                .cornerRadius(3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.primary.opacity(0.35), lineWidth: 1)
                                )
                                .offset(x: 0, y: -18)
                        }
                        .position(x: rx + rw / 2, y: ry + rh / 2)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            let nx = min(max(0, value.location.x / w), 1)
                            let ny = min(max(0, value.location.y / h), 1)
                            if browserAutomation.isInspectMode || NSEvent.modifierFlags.contains(.option) {
                                let startX = min(value.startLocation.x, value.location.x)
                                let startY = min(value.startLocation.y, value.location.y)
                                let dragW = abs(value.location.x - value.startLocation.x)
                                let dragH = abs(value.location.y - value.startLocation.y)
                                let finalX = dragW > 12 ? startX : max(0, value.location.x - 36)
                                let finalY = dragH > 12 ? startY : max(0, value.location.y - 20)
                                let finalW = dragW > 12 ? dragW : 72
                                let finalH = dragH > 12 ? dragH : 40
                                let pctX = Int(round((finalX / w) * 100))
                                let pctY = Int(round((finalY / h) * 100))
                                let fwName = universalBridge.detectedFramework.rawValue
                                let sel = "\(fwName)@(\(pctX)%,\(pctY)%)"
                                let newEl = BrowserPickedElement(
                                    selector: sel,
                                    tag: fwName.lowercased(),
                                    text: "Native UI Region (\(Int(finalW))×\(Int(finalH))pt at \(pctX)%, \(pctY)%)",
                                    outerHTML: "<!-- Native \(fwName) Canvas Region at (\(Int(finalX)), \(Int(finalY))) size \(Int(finalW))x\(Int(finalH)) -->",
                                    styles: "framework:\(fwName); x:\(pctX)%; y:\(pctY)%; width:\(Int(finalW))pt; height:\(Int(finalH))pt",
                                    rect: "\(Int(finalX)),\(Int(finalY)) (\(Int(finalW))x\(Int(finalH)))",
                                    boundsX: Double(finalX),
                                    boundsY: Double(finalY),
                                    boundsWidth: Double(finalW),
                                    boundsHeight: Double(finalH),
                                    viewportWidth: Double(w),
                                    viewportHeight: Double(h),
                                    timestamp: Date()
                                )
                                browserAutomation.pickedElements.append(newEl)
                                browserAutomation.lastPickedElement = newEl
                            } else {
                                universalBridge.sendCanvasClick(normalizedX: nx, normalizedY: ny)
                            }
                        }
                )
            }
        } else {
            WebBrowserView(
                url: currentURL,
                title: $pageTitle,
                isLoading: $isLoading,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                refreshTrigger: $refreshTrigger,
                goBackTrigger: $goBackTrigger,
                goForwardTrigger: $goForwardTrigger,
                pageZoom: pageZoom,
                cornerRadius: cornerRadius,
                isMacBook: isMacBook,
                cornerRadii: cornerRadii
            )
        }
    }

    private func handleFileSavedNotification(_ note: Notification) {
        let savedPath = (note.userInfo?["path"] as? String) ?? ""
        let savedContent = note.userInfo?["content"] as? String
        let ext = (savedPath as NSString).pathExtension.lowercased()
        if currentURL == nil && (ext == "html" || ext == "htm") {
            detectLocalWorkspaceIndex()
            if currentURL == nil && !savedPath.isEmpty {
                sanitizeAndSetURL(savedPath)
            }
            return
        }
        if ext == "css" || ext == "scss" || ext == "less" {
            return
        }
        let guiExts: Set<String> = ["swift", "py", "dart", "kt", "kts", "java", "cs", "razor", "xaml", "axaml", "ar"]
        if isLiveReloadEnabled && guiExts.contains(ext) {
            universalBridge.triggerHotReload(savedFilePath: savedPath, liveCode: savedContent, reason: "Save")
            return
        }
        if isLiveReloadEnabled && PreviewHotReloadEngine.shared.isAutoHotReloadEnabled {
            refreshTrigger = true
        }
    }
    
    // MARK: - Dimension Calculation
    
    private func effectiveActiveWidth() -> CGFloat? {
        if let custom = customWidth {
            if isLandscape, let h = selectedViewport.defaultHeight, selectedViewport != .responsive {
                return h
            }
            return custom
        }
        if let def = selectedViewport.defaultWidth {
            if isLandscape, let h = selectedViewport.defaultHeight {
                return h
            }
            return def
        }
        return nil
    }
    
    // MARK: - Workspace & URL Helpers
    
    private func workspaceRequiresDevServer() -> Bool {
        guard let folder = appState.workspaceFolder else { return false }
        let fm = FileManager.default
        let pkgPath = folder.appendingPathComponent("package.json").path
        if fm.fileExists(atPath: pkgPath) {
            return true
        }
        let bundlerConfigs = ["vite.config.ts", "vite.config.js", "next.config.js", "next.config.mjs", "svelte.config.js", "nuxt.config.ts", "angular.json", "astro.config.mjs"]
        for cfg in bundlerConfigs {
            if fm.fileExists(atPath: folder.appendingPathComponent(cfg).path) {
                return true
            }
        }
        return false
    }

    private func detectPreferredWorkspacePort() -> Int {
        guard let folder = appState.workspaceFolder else { return 3000 }
        let fm = FileManager.default
        for viteCfg in ["vite.config.ts", "vite.config.js", "vite.config.mjs", "svelte.config.js"] {
            if fm.fileExists(atPath: folder.appendingPathComponent(viteCfg).path) {
                return 5173
            }
        }
        if fm.fileExists(atPath: folder.appendingPathComponent("angular.json").path) {
            return 4200
        }
        if fm.fileExists(atPath: folder.appendingPathComponent("astro.config.mjs").path) {
            return 4321
        }
        let pkgURL = folder.appendingPathComponent("package.json")
        if let content = try? String(contentsOf: pkgURL, encoding: .utf8).lowercased() {
            if content.contains("\"vite\"") || content.contains("vite ") {
                return 5173
            }
            if content.contains("\"astro\"") {
                return 4321
            }
            if content.contains("\"@angular/core\"") {
                return 4200
            }
        }
        return 3000
    }

    private func detectLocalWorkspaceIndex() {
        localWorkspaceIndexURL = nil
        guard let folder = appState.workspaceFolder else { return }
        if workspaceRequiresDevServer() {
            return
        }
        let fm = FileManager.default
        let candidates = [
            folder.appendingPathComponent("index.html"),
            folder.appendingPathComponent("cmw/index.html"),
            folder.appendingPathComponent("public/index.html"),
            folder.appendingPathComponent("dist/index.html"),
            folder.appendingPathComponent("build/index.html"),
            folder.appendingPathComponent("src/index.html")
        ]
        for url in candidates {
            if fm.fileExists(atPath: url.path) {
                if let html = try? String(contentsOf: url, encoding: .utf8),
                   (html.contains("/src/main.") || html.contains("%PUBLIC_URL%") || html.contains("/@vite/")) {
                    continue
                }
                localWorkspaceIndexURL = url
                return
            }
        }
    }
    
    private func resolveInitialURL() {
        if let target = runtime.targetWebURL {
            if target.isFileURL && workspaceRequiresDevServer() {
                runtime.targetWebURL = nil
            } else {
                sanitizeAndSetURL(target.absoluteString)
                return
            }
        }
        if let detectedPort = runtime.lastDetectedDevServerPort {
            sanitizeAndSetURL("http://localhost:\(detectedPort)")
        } else if !browserAutomation.activePortProcesses.isEmpty {
            let preferredPorts = [5173, 5174, 4173, 3000, 8080, 4200, 4321, 8000]
            let activePorts = Set(browserAutomation.activePortProcesses.map(\.port))
            let wsPort = detectPreferredWorkspacePort()
            let chosen = activePorts.contains(wsPort)
                ? wsPort
                : (preferredPorts.first(where: { activePorts.contains($0) }) ?? browserAutomation.activePortProcesses[0].port)
            sanitizeAndSetURL("http://localhost:\(chosen)")
        } else if let localIndex = localWorkspaceIndexURL {
            sanitizeAndSetURL(localIndex.absoluteString)
        } else {
            let defaultPort = detectPreferredWorkspacePort()
            sanitizeAndSetURL("http://localhost:\(defaultPort)")
        }
    }
    
    private func loadNavigatedURL() {
        sanitizeAndSetURL(urlString)
    }
    
    private func sanitizeAndSetURL(_ raw: String) {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while str.hasPrefix("http://file://") {
            str = String(str.dropFirst(7))
        }
        while str.hasPrefix("https://file://") {
            str = String(str.dropFirst(8))
        }
        if str.hasPrefix("file://") {
            urlString = str
            currentURL = URL(string: str)
            if runtime.targetWebURL != currentURL {
                runtime.targetWebURL = currentURL
            }
            return
        }
        if str.hasPrefix("/") {
            let fileURL = URL(fileURLWithPath: str)
            urlString = fileURL.absoluteString
            currentURL = fileURL
            if runtime.targetWebURL != currentURL {
                runtime.targetWebURL = currentURL
            }
            return
        }
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "http://" + str
        }
        urlString = str
        currentURL = URL(string: str)
        if runtime.targetWebURL != currentURL {
            runtime.targetWebURL = currentURL
        }
    }
}
