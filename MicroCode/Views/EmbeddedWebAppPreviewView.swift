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

struct DeviceFrameSpec {
    let name: String
    let frameSize: CGSize       // Outer bezel size
    let screenSize: CGSize      // Inner viewport size
    let screenOffset: CGPoint   // Top-left origin of inner screen relative to top-left of outer frame
    let cornerRadius: CGFloat   // Inner screen corner radius
    let isMacBook: Bool         // If true, use top rounded corners & bottom flat
}

// MARK: - Screen Shape Definitions (macOS 13+ compatible)

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
    
    func path(in rect: CGRect) -> Path {
        if isMacBook {
            return MacBookScreenShape(topRadius: cornerRadius).path(in: rect)
        } else {
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        }
    }
}

// MARK: - Viewports & Device Options

enum WebAppViewport: String, CaseIterable, Identifiable {
    case responsive = "Fluid Responsive"
    case mobileS = "Mobile S (320)"
    case mobile = "Mobile (375)"
    case iphone = "iPhone 16 (393)"
    case mobileMax = "Max (430)"
    case tablet = "iPad (768)"
    case laptop = "Laptop (1024)"
    case desktop = "MacBook (1280)"
    case desktopWide = "Desktop (1440)"
    
    var id: String { rawValue }
    
    var shortLabel: String {
        switch self {
        case .responsive: return "Fluid"
        case .mobileS: return "320"
        case .mobile: return "375"
        case .iphone: return "393"
        case .mobileMax: return "430"
        case .tablet: return "768"
        case .laptop: return "1024"
        case .desktop: return "1280"
        case .desktopWide: return "1440"
        }
    }
    
    var defaultWidth: CGFloat? {
        switch self {
        case .responsive: return nil
        case .mobileS: return 320.0
        case .mobile: return 375.0
        case .iphone: return 393.0
        case .mobileMax: return 430.0
        case .tablet: return 768.0
        case .laptop: return 1024.0
        case .desktop: return 1280.0
        case .desktopWide: return 1440.0
        }
    }
    
    var defaultHeight: CGFloat? {
        switch self {
        case .responsive: return nil
        case .mobileS: return 568.0
        case .mobile: return 667.0
        case .iphone: return 852.0
        case .mobileMax: return 932.0
        case .tablet: return 1024.0
        case .laptop: return 768.0
        case .desktop: return 800.0
        case .desktopWide: return 900.0
        }
    }
    
    var icon: String {
        switch self {
        case .responsive: return "arrow.up.left.and.arrow.down.right"
        case .mobileS: return "iphone"
        case .mobile: return "iphone"
        case .iphone: return "iphone.gen3"
        case .mobileMax: return "iphone"
        case .tablet: return "ipad"
        case .laptop: return "laptopcomputer"
        case .desktop: return "display"
        case .desktopWide: return "display.2"
        }
    }
    
    var subtitle: String {
        switch self {
        case .responsive: return "Fluid Full Width • Reflows with dock"
        case .mobileS: return "320 × 568 • Compact Mobile"
        case .mobile: return "375 × 667 • Standard Mobile"
        case .iphone: return "393 × 852 • iPhone 16 Pro"
        case .mobileMax: return "430 × 932 • iPhone 16 Pro Max"
        case .tablet: return "768 × 1024 • iPad / Tablet"
        case .laptop: return "1024 × 768 • Laptop Display"
        case .desktop: return "1280 × 800 • MacBook Retina"
        case .desktopWide: return "1440 × 900 • 2K Desktop Canvas"
        }
    }
    
    var hasBezel: Bool {
        switch self {
        case .iphone, .tablet, .desktop: return true
        default: return false
        }
    }
    
    func frameSpec(isLandscape: Bool = false) -> DeviceFrameSpec? {
        switch self {
        case .responsive:
            return nil
            
        case .mobileS:
            let w: CGFloat = isLandscape ? 568.0 : 320.0
            let h: CGFloat = isLandscape ? 320.0 : 568.0
            return DeviceFrameSpec(
                name: "Mobile Small",
                frameSize: CGSize(width: w, height: h),
                screenSize: CGSize(width: w, height: h),
                screenOffset: .zero,
                cornerRadius: 14.0,
                isMacBook: false
            )
            
        case .mobile:
            let w: CGFloat = isLandscape ? 667.0 : 375.0
            let h: CGFloat = isLandscape ? 375.0 : 667.0
            return DeviceFrameSpec(
                name: "Mobile Standard",
                frameSize: CGSize(width: w, height: h),
                screenSize: CGSize(width: w, height: h),
                screenOffset: .zero,
                cornerRadius: 16.0,
                isMacBook: false
            )
            
        case .iphone:
            if isLandscape {
                return DeviceFrameSpec(
                    name: "iPhone 16 Pro (Landscape)",
                    frameSize: CGSize(width: 852.0, height: 393.0),
                    screenSize: CGSize(width: 852.0, height: 393.0),
                    screenOffset: .zero,
                    cornerRadius: 36.0,
                    isMacBook: false
                )
            }
            let scale: CGFloat = 393.0 / 447.0
            return DeviceFrameSpec(
                name: "iPhone 16 Pro",
                frameSize: CGSize(width: 490.0 * scale, height: 1024.0 * scale),
                screenSize: CGSize(width: 393.0, height: 972.0 * scale),
                screenOffset: CGPoint(x: 22.0 * scale, y: 26.0 * scale),
                cornerRadius: 46.0,
                isMacBook: false
            )
            
        case .mobileMax:
            let w: CGFloat = isLandscape ? 932.0 : 430.0
            let h: CGFloat = isLandscape ? 430.0 : 932.0
            return DeviceFrameSpec(
                name: "Mobile Max",
                frameSize: CGSize(width: w, height: h),
                screenSize: CGSize(width: w, height: h),
                screenOffset: .zero,
                cornerRadius: 38.0,
                isMacBook: false
            )
            
        case .tablet:
            if isLandscape {
                return DeviceFrameSpec(
                    name: "iPad Pro (Landscape)",
                    frameSize: CGSize(width: 1024.0, height: 768.0),
                    screenSize: CGSize(width: 1024.0, height: 768.0),
                    screenOffset: .zero,
                    cornerRadius: 18.0,
                    isMacBook: false
                )
            }
            let scale: CGFloat = 768.0 / 647.0
            return DeviceFrameSpec(
                name: "iPad",
                frameSize: CGSize(width: 729.0 * scale, height: 1024.0 * scale),
                screenSize: CGSize(width: 768.0, height: 938.0 * scale),
                screenOffset: CGPoint(x: 41.0 * scale, y: 43.0 * scale),
                cornerRadius: 18.0,
                isMacBook: false
            )
            
        case .laptop:
            return DeviceFrameSpec(
                name: "Laptop",
                frameSize: CGSize(width: 1024.0, height: 768.0),
                screenSize: CGSize(width: 1024.0, height: 768.0),
                screenOffset: .zero,
                cornerRadius: 10.0,
                isMacBook: true
            )
            
        case .desktop:
            let scale: CGFloat = 1280.0 / 802.0
            return DeviceFrameSpec(
                name: "MacBook Pro",
                frameSize: CGSize(width: 1024.0 * scale, height: 673.0 * scale),
                screenSize: CGSize(width: 1280.0, height: 520.0 * scale),
                screenOffset: CGPoint(x: 111.0 * scale, y: 77.0 * scale),
                cornerRadius: 10.0,
                isMacBook: true
            )
            
        case .desktopWide:
            return DeviceFrameSpec(
                name: "Desktop Wide",
                frameSize: CGSize(width: 1440.0, height: 900.0),
                screenSize: CGSize(width: 1440.0, height: 900.0),
                screenOffset: .zero,
                cornerRadius: 8.0,
                isMacBook: false
            )
        }
    }
    
    func bezelImage(isLandscape: Bool = false) -> NSImage? {
        if isLandscape { return nil }
        switch self {
        case .iphone:
            return DeviceFrameAssets.loadIPhoneProBezel()
        case .tablet:
            return DeviceFrameAssets.loadIPadProBezel()
        case .desktop:
            return DeviceFrameAssets.loadMacBookProBezel()
        default:
            return nil
        }
    }
}

enum DeviceZoomMode: String, CaseIterable, Identifiable {
    case fit = "Fit to Window"
    case actual = "100% (Actual)"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .fit: return "arrow.down.right.and.arrow.up.left"
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
    
    // FResponsive States
    @State private var selectedViewport: WebAppViewport = .responsive
    @State private var customWidth: CGFloat? = nil
    @State private var isDraggingHandle: Bool = false
    @State private var dragInitialWidth: CGFloat = 0
    @State private var showDeviceBezel: Bool = false
    @State private var isLandscape: Bool = false
    @State private var zoomMode: DeviceZoomMode = .fit
    @State private var isLiveReloadEnabled: Bool = true
    @State private var localWorkspaceIndexURL: URL? = nil
    @State private var isHoveringHandle: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. FResponsive Quick Switcher Bar (Fully Scrollable & Adaptive)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // FResponsive Brand Pill
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.accentColor)
                        Text("FResponsive")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(4)
                    
                    // Viewport Preset Switchers
                    HStack(spacing: 2) {
                        ForEach(WebAppViewport.allCases) { vp in
                            let isSelected = (selectedViewport == vp && customWidth == vp.defaultWidth) || (vp == .responsive && customWidth == nil)
                            Button {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    selectedViewport = vp
                                    customWidth = vp.defaultWidth
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: vp.icon)
                                        .font(.system(size: 9))
                                    Text(vp.shortLabel)
                                        .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                                )
                                .foregroundColor(isSelected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .help(vp.subtitle)
                        }
                    }
                    
                    // Orientation Switch (Portrait / Landscape)
                    if selectedViewport != .responsive || customWidth != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isLandscape.toggle()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: isLandscape ? "iphone.landscape" : "iphone")
                                    .font(.system(size: 9))
                                Text(isLandscape ? "Landscape" : "Portrait")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Toggle Portrait / Landscape Orientation")
                    }
                    
                    // Mode Toggle: Clean Screen vs Realistic Bezel
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showDeviceBezel.toggle()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: showDeviceBezel ? "iphone.badge.play" : "display")
                                .font(.system(size: 9))
                            Text(showDeviceBezel ? "Bezel" : "Clean")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(showDeviceBezel ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                        .foregroundColor(showDeviceBezel ? .accentColor : .secondary)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help(showDeviceBezel ? "Showing realistic device chassis. Click for Clean Screen." : "Clean frameless screen. Click for realistic device chassis.")
                    
                    // Live Dimension Badge
                    Menu {
                        Button("Fluid (100% Full Width)") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedViewport = .responsive
                                customWidth = nil
                            }
                        }
                        Divider()
                        Button("320 × 568 (Mobile S)") { customWidth = 320; selectedViewport = .mobileS }
                        Button("375 × 667 (Mobile M)") { customWidth = 375; selectedViewport = .mobile }
                        Button("393 × 852 (iPhone 16 Pro)") { customWidth = 393; selectedViewport = .iphone }
                        Button("430 × 932 (iPhone 16 Pro Max)") { customWidth = 430; selectedViewport = .mobileMax }
                        Button("768 × 1024 (iPad)") { customWidth = 768; selectedViewport = .tablet }
                        Button("1024 × 768 (Laptop)") { customWidth = 1024; selectedViewport = .laptop }
                        Button("1280 × 800 (Desktop)") { customWidth = 1280; selectedViewport = .desktop }
                        Button("1440 × 900 (Wide)") { customWidth = 1440; selectedViewport = .desktopWide }
                    } label: {
                        HStack(spacing: 3) {
                            if let w = effectiveActiveWidth() {
                                Text("\(Int(w)) px")
                                    .font(.system(size: 9, design: .monospaced))
                            } else {
                                Text("Fluid 100%")
                                    .font(.system(size: 9, design: .monospaced))
                            }
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Current Viewport Width. Click to jump to common breakpoints.")
                    
                    // Display Zoom Toggle (Fit / 100%)
                    if selectedViewport != .responsive || customWidth != nil {
                        Button {
                            zoomMode = (zoomMode == .fit) ? .actual : .fit
                        } label: {
                            Image(systemName: zoomMode.icon)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(3)
                        }
                        .buttonStyle(.plain)
                        .help(zoomMode.rawValue)
                    }
                    
                    // Live Reload Indicator
                    Button {
                        isLiveReloadEnabled.toggle()
                    } label: {
                        HStack(spacing: 2) {
                            Circle()
                                .fill(isLiveReloadEnabled ? Color.green : Color.secondary)
                                .frame(width: 6, height: 6)
                            Text("Live")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(isLiveReloadEnabled ? .primary : .secondary)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help(isLiveReloadEnabled ? "Live Reload Active (reloads on file save)" : "Live Reload Paused")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(Color.primary.opacity(0.03))
            
            Divider()
            
            // MARK: - 2. Navigation & Address Bar
            HStack(spacing: 6) {
                // Navigation controls
                HStack(spacing: 3) {
                    Button {
                        goBackTrigger = true
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canGoBack)
                    .help("Back")
                    
                    Button {
                        goForwardTrigger = true
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canGoForward)
                    .help("Forward")
                    
                    Button {
                        refreshTrigger = true
                    } label: {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Reload Page (⌘R)")
                }
                
                // Quick Source Switchers (Local index.html / DevServer)
                if let localURL = localWorkspaceIndexURL {
                    let isLocalSelected = (currentURL?.isFileURL == true)
                    Button {
                        sanitizeAndSetURL(localURL.absoluteString)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 9))
                            Text("index.html")
                                .font(.system(size: 9, weight: isLocalSelected ? .bold : .regular))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isLocalSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                        .foregroundColor(isLocalSelected ? .accentColor : .secondary)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Preview local workspace index.html directly")
                }
                
                if let devPort = runtime.lastDetectedDevServerPort {
                    let isPortSelected = (urlString.contains(":\(devPort)"))
                    Button {
                        sanitizeAndSetURL("http://localhost:\(devPort)")
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8))
                            Text(":\(devPort)")
                                .font(.system(size: 9, weight: isPortSelected ? .bold : .regular))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isPortSelected ? Color.green.opacity(0.18) : Color.primary.opacity(0.06))
                        .foregroundColor(isPortSelected ? .green : .secondary)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Switch to detected local dev server on port \(devPort)")
                }
                
                // URL input bar
                HStack(spacing: 4) {
                    Image(systemName: currentURL?.isFileURL == true ? "doc.fill" : (urlString.hasPrefix("https") ? "lock.fill" : "globe"))
                        .font(.system(size: 8))
                        .foregroundColor(currentURL?.isFileURL == true ? .accentColor : (urlString.hasPrefix("https") ? .green : .secondary))
                    
                    TextField("http://localhost:3000", text: $urlString)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .onSubmit {
                            loadNavigatedURL()
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(6)
                
                // Actions Menu
                Menu {
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
                    
                    Divider()
                    
                    Button("Reset to Fluid Viewport") {
                        withAnimation {
                            selectedViewport = .responsive
                            customWidth = nil
                        }
                    }
                    
                    Button("Hard Reload & Clear Cache") {
                        WebEngine.shared.clearCache()
                        refreshTrigger = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(canvasColor)
            
            Divider()
            
            // MARK: - 3. Interactive Web View Canvas
            GeometryReader { geo in
                ZStack {
                    canvasColor
                    
                    let availW = geo.size.width
                    let availH = geo.size.height
                    
                    if showDeviceBezel, let spec = selectedViewport.frameSpec(isLandscape: isLandscape) {
                        // MARK: Authentic Hardware Bezel Mode
                        let maxW = max(60, availW - 40)
                        let maxH = max(60, availH - 40)
                        let fitScale = min(1.0, min(maxW / spec.frameSize.width, maxH / spec.frameSize.height))
                        let activeScale = (zoomMode == .fit) ? fitScale : 1.0
                        
                        let deviceView = ZStack {
                            // 1. Screen backdrop
                            Color.white
                                .frame(width: spec.screenSize.width, height: spec.screenSize.height)
                                .clipShape(ScreenClipShape(cornerRadius: spec.cornerRadius, isMacBook: spec.isMacBook))
                                .position(
                                    x: spec.screenOffset.x + spec.screenSize.width / 2,
                                    y: spec.screenOffset.y + spec.screenSize.height / 2
                                )
                            
                            // 2. Interactive WebBrowserView
                            WebBrowserView(
                                url: currentURL,
                                title: $pageTitle,
                                isLoading: $isLoading,
                                canGoBack: $canGoBack,
                                canGoForward: $canGoForward,
                                refreshTrigger: $refreshTrigger,
                                goBackTrigger: $goBackTrigger,
                                goForwardTrigger: $goForwardTrigger
                            )
                            .frame(width: spec.screenSize.width, height: spec.screenSize.height)
                            .clipShape(ScreenClipShape(cornerRadius: spec.cornerRadius, isMacBook: spec.isMacBook))
                            .position(
                                x: spec.screenOffset.x + spec.screenSize.width / 2,
                                y: spec.screenOffset.y + spec.screenSize.height / 2
                            )
                            
                            // 3. Authentic Hardware Bezel Overlay
                            if let bezel = selectedViewport.bezelImage(isLandscape: isLandscape) {
                                Image(nsImage: bezel)
                                    .resizable()
                                    .interpolation(.high)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: spec.frameSize.width, height: spec.frameSize.height)
                                    .position(
                                        x: spec.frameSize.width / 2,
                                        y: spec.frameSize.height / 2
                                    )
                                    .allowsHitTesting(false)
                            } else {
                                ScreenClipShape(cornerRadius: spec.cornerRadius, isMacBook: spec.isMacBook)
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 4)
                                    .frame(width: spec.screenSize.width, height: spec.screenSize.height)
                                    .position(
                                        x: spec.screenOffset.x + spec.screenSize.width / 2,
                                        y: spec.screenOffset.y + spec.screenSize.height / 2
                                    )
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(width: spec.frameSize.width, height: spec.frameSize.height)
                        .shadow(color: Color.black.opacity(0.28), radius: 20, x: 0, y: 10)
                        
                        if zoomMode == .actual {
                            ScrollView([.horizontal, .vertical]) {
                                deviceView.padding(32)
                            }
                            .frame(width: availW, height: availH)
                        } else {
                            deviceView
                                .scaleEffect(activeScale)
                                .frame(width: availW, height: availH)
                        }
                    } else if let activeW = effectiveActiveWidth() {
                        // MARK: Clean Responsive Screen Mode with Bilateral Drag Handles
                        let targetW = activeW
                        let isWiderThanDock = targetW > (availW - 32)
                        let fitScale = isWiderThanDock ? min(1.0, (availW - 32) / targetW) : 1.0
                        let activeScale = (zoomMode == .fit) ? fitScale : 1.0
                        
                        let cleanView = ZStack(alignment: .trailing) {
                            // The Web Content Viewport Card
                            VStack(spacing: 0) {
                                // Subtle top status header with live dimension readout
                                HStack {
                                    Circle().fill(Color.red.opacity(0.6)).frame(width: 7, height: 7)
                                    Circle().fill(Color.yellow.opacity(0.6)).frame(width: 7, height: 7)
                                    Circle().fill(Color.green.opacity(0.6)).frame(width: 7, height: 7)
                                    Spacer()
                                    Text("\(Int(targetW)) px • \(selectedViewport.shortLabel)")
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
                                
                                WebBrowserView(
                                    url: currentURL,
                                    title: $pageTitle,
                                    isLoading: $isLoading,
                                    canGoBack: $canGoBack,
                                    canGoForward: $canGoForward,
                                    refreshTrigger: $refreshTrigger,
                                    goBackTrigger: $goBackTrigger,
                                    goForwardTrigger: $goForwardTrigger
                                )
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
                            
                            // Interactive Right Drag Handle (Resize Grip)
                            ZStack {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 16)
                                    .contentShape(Rectangle())
                                
                                Capsule()
                                    .fill(isDraggingHandle || isHoveringHandle ? Color.accentColor : Color.secondary.opacity(0.45))
                                    .frame(width: 4, height: 36)
                            }
                            .offset(x: 8)
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
                            WebBrowserView(
                                url: currentURL,
                                title: $pageTitle,
                                isLoading: $isLoading,
                                canGoBack: $canGoBack,
                                canGoForward: $canGoForward,
                                refreshTrigger: $refreshTrigger,
                                goBackTrigger: $goBackTrigger,
                                goForwardTrigger: $goForwardTrigger
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.white)
                            
                            // Right Drag Inward Handle (Seamlessly drag into custom breakpoint)
                            ZStack {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 14)
                                    .contentShape(Rectangle())
                                
                                Capsule()
                                    .fill(isDraggingHandle || isHoveringHandle ? Color.accentColor : Color.secondary.opacity(0.3))
                                    .frame(width: 3, height: 32)
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
            }
        }
        .background(canvasColor)
        .onAppear {
            detectLocalWorkspaceIndex()
            resolveInitialURL()
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
            let key = newVP.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key.contains("responsive") || key.contains("fluid") {
                selectedViewport = .responsive
                customWidth = nil
            } else if key.contains("macbook") || key.contains("desktop") || key.contains("pc") || key.contains("laptop") {
                selectedViewport = .desktop
                customWidth = selectedViewport.defaultWidth
            } else if key.contains("ipad") || key.contains("tablet") {
                selectedViewport = .tablet
                customWidth = selectedViewport.defaultWidth
            } else if key.contains("iphone") || key.contains("mobile") || key.contains("phone") {
                selectedViewport = .iphone
                customWidth = selectedViewport.defaultWidth
            } else if let match = WebAppViewport.allCases.first(where: { $0.rawValue.lowercased() == key || $0.shortLabel == key }) {
                selectedViewport = match
                customWidth = match.defaultWidth
            }
        }
        .onChange(of: runtime.lastDetectedDevServerPort) { newPort in
            if let port = newPort, runtime.targetWebURL == nil, currentURL?.isFileURL != true {
                sanitizeAndSetURL("http://localhost:\(port)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeFileSaved"))) { _ in
            if isLiveReloadEnabled {
                refreshTrigger = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeEditorFolderOpened"))) { _ in
            detectLocalWorkspaceIndex()
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
    
    private func detectLocalWorkspaceIndex() {
        guard let folder = appState.workspaceFolder else { return }
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
                localWorkspaceIndexURL = url
                return
            }
        }
    }
    
    private func resolveInitialURL() {
        if let target = runtime.targetWebURL {
            sanitizeAndSetURL(target.absoluteString)
        } else if let detectedPort = runtime.lastDetectedDevServerPort {
            sanitizeAndSetURL("http://localhost:\(detectedPort)")
        } else if let localIndex = localWorkspaceIndexURL {
            sanitizeAndSetURL(localIndex.absoluteString)
        } else {
            sanitizeAndSetURL("http://localhost:3000")
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
            return
        }
        if str.hasPrefix("/") {
            let fileURL = URL(fileURLWithPath: str)
            urlString = fileURL.absoluteString
            currentURL = fileURL
            return
        }
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "http://" + str
        }
        urlString = str
        currentURL = URL(string: str)
    }
}
