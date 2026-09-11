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
    case responsive = "Responsive"
    case desktop = "MacBook Pro (PC)"
    case tablet = "iPad Pro"
    case mobile = "iPhone 16 Pro"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .responsive: return "arrow.up.left.and.arrow.down.right"
        case .desktop: return "laptopcomputer"
        case .tablet: return "ipad"
        case .mobile: return "iphone"
        }
    }
    
    var subtitle: String {
        switch self {
        case .responsive: return "Fluid Full Width"
        case .desktop: return "1280 × 830 • Liquid Retina"
        case .tablet: return "820 × 1189 • Liquid Retina"
        case .mobile: return "393 × 855 • Dynamic Island"
        }
    }
    
    var frameSpec: DeviceFrameSpec? {
        switch self {
        case .responsive:
            return nil
            
        case .desktop:
            // Native image: 1024x673, inner screen: x=111..912 (w=802), y=77..596 (h=520)
            let scale: CGFloat = 1280.0 / 802.0
            return DeviceFrameSpec(
                name: "MacBook Pro",
                frameSize: CGSize(width: 1024.0 * scale, height: 673.0 * scale),
                screenSize: CGSize(width: 1280.0, height: 520.0 * scale),
                screenOffset: CGPoint(x: 111.0 * scale, y: 77.0 * scale),
                cornerRadius: 10.0,
                isMacBook: true
            )
            
        case .tablet:
            // Native image: 729x1024, inner screen: x=41..687 (w=647), y=43..980 (h=938)
            let scale: CGFloat = 820.0 / 647.0
            return DeviceFrameSpec(
                name: "iPad Pro",
                frameSize: CGSize(width: 729.0 * scale, height: 1024.0 * scale),
                screenSize: CGSize(width: 820.0, height: 938.0 * scale),
                screenOffset: CGPoint(x: 41.0 * scale, y: 43.0 * scale),
                cornerRadius: 18.0,
                isMacBook: false
            )
            
        case .mobile:
            // Native image: 490x1024, inner screen: x=22..468 (w=447), y=26..997 (h=972)
            let scale: CGFloat = 393.0 / 447.0
            return DeviceFrameSpec(
                name: "iPhone 16 Pro",
                frameSize: CGSize(width: 490.0 * scale, height: 1024.0 * scale),
                screenSize: CGSize(width: 393.0, height: 972.0 * scale),
                screenOffset: CGPoint(x: 22.0 * scale, y: 26.0 * scale),
                cornerRadius: 46.0,
                isMacBook: false
            )
        }
    }
    
    var bezelImage: NSImage? {
        switch self {
        case .responsive:
            return nil
        case .desktop:
            return DeviceFrameAssets.loadMacBookProBezel()
        case .tablet:
            return DeviceFrameAssets.loadIPadProBezel()
        case .mobile:
            return DeviceFrameAssets.loadIPhoneProBezel()
        }
    }
    
    var dimensions: CGSize? {
        frameSpec?.screenSize
    }
}

enum DeviceZoomMode: String, CaseIterable, Identifiable {
    case fit = "Fit to Window"
    case actual = "100% (Actual Size)"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .fit: return "arrow.down.right.and.arrow.up.left"
        case .actual: return "viewfinder"
        }
    }
}

struct EmbeddedWebAppPreviewView: View {
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
    @State private var selectedViewport: WebAppViewport = .responsive
    @State private var zoomMode: DeviceZoomMode = .fit
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 12))
                
                Text(pageTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)
                
                // Navigation controls
                HStack(spacing: 4) {
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
                    .help("Reload Page")
                }
                
                // URL input bar
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundColor(urlString.hasPrefix("https") ? .green : .secondary)
                    
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
                
                // Viewport selector
                Menu {
                    Section("Hardware Device Frame") {
                        ForEach(WebAppViewport.allCases) { vp in
                            Button {
                                selectedViewport = vp
                            } label: {
                                HStack {
                                    Label(vp.rawValue, systemImage: vp.icon)
                                    if selectedViewport == vp {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    
                    if selectedViewport != .responsive {
                        Section("Display Zoom") {
                            ForEach(DeviceZoomMode.allCases) { mode in
                                Button {
                                    zoomMode = mode
                                } label: {
                                    HStack {
                                        Label(mode.rawValue, systemImage: mode.icon)
                                        if zoomMode == mode {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button("Copy Preview URL") {
                        if let url = currentURL {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        }
                    }
                    
                    Button("Open in Default Browser") {
                        if let url = currentURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedViewport.icon)
                            .font(.system(size: 10))
                        Text(selectedViewport.rawValue)
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.07))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Device Viewport: \(selectedViewport.rawValue)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(canvasColor)
            
            Divider()
            
            // Web View Canvas
            GeometryReader { geo in
                ZStack {
                    canvasColor
                    
                    if let spec = selectedViewport.frameSpec {
                        // Authentic Hardware Frame Container
                        let availW = max(60, geo.size.width - 40)
                        let availH = max(60, geo.size.height - 40)
                        let fitScale = min(1.0, min(availW / spec.frameSize.width, availH / spec.frameSize.height))
                        let activeScale = (zoomMode == .fit) ? fitScale : 1.0
                        
                        let deviceView = ZStack {
                            // 1. Screen white backdrop
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
                            
                            // 3. Authentic Hardware Bezel Overlay (allowsHitTesting: false passes clicks/scrolls to WebBrowserView)
                            if let bezel = selectedViewport.bezelImage {
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
                                // Graceful simulated border fallback
                                ScreenClipShape(cornerRadius: spec.cornerRadius, isMacBook: spec.isMacBook)
                                    .stroke(Color.primary.opacity(0.25), lineWidth: 8)
                                    .frame(width: spec.screenSize.width, height: spec.screenSize.height)
                                    .position(
                                        x: spec.screenOffset.x + spec.screenSize.width / 2,
                                        y: spec.screenOffset.y + spec.screenSize.height / 2
                                    )
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(width: spec.frameSize.width, height: spec.frameSize.height)
                        .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 12)
                        
                        if zoomMode == .actual {
                            ScrollView([.horizontal, .vertical]) {
                                deviceView
                                    .padding(32)
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                        } else {
                            deviceView
                                .scaleEffect(activeScale)
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    } else {
                        // Full responsive viewport
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
                    }
                }
            }
        }
        .background(canvasColor)
        .onAppear {
            if let target = runtime.targetWebURL {
                urlString = target.absoluteString
                currentURL = target
            } else if let detectedPort = runtime.lastDetectedDevServerPort {
                urlString = "http://localhost:\(detectedPort)"
                currentURL = URL(string: urlString)
            }
        }
        .onChange(of: runtime.targetWebURL) { newURL in
            if let newURL = newURL {
                urlString = newURL.absoluteString
                currentURL = newURL
            }
        }
        .onChange(of: runtime.webRefreshTrigger) { _ in
            refreshTrigger = true
        }
        .onChange(of: runtime.targetViewport) { newVP in
            let key = newVP.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key.contains("responsive") || key.contains("fluid") {
                selectedViewport = .responsive
            } else if key.contains("macbook") || key.contains("desktop") || key.contains("pc") || key.contains("laptop") {
                selectedViewport = .desktop
            } else if key.contains("ipad") || key.contains("tablet") {
                selectedViewport = .tablet
            } else if key.contains("iphone") || key.contains("mobile") || key.contains("phone") {
                selectedViewport = .mobile
            } else if let match = WebAppViewport.allCases.first(where: { $0.rawValue.lowercased() == key }) {
                selectedViewport = match
            }
        }
        .onChange(of: runtime.lastDetectedDevServerPort) { newPort in
            if let port = newPort, runtime.targetWebURL == nil {
                urlString = "http://localhost:\(port)"
                currentURL = URL(string: urlString)
            }
        }
    }
    
    private func loadNavigatedURL() {
        var str = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "http://" + str
            urlString = str
        }
        if let url = URL(string: str) {
            currentURL = url
        }
    }
}
