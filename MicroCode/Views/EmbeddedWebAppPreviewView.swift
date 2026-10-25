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
    case iphone = "iPhone"
    case tablet = "iPad"
    case macbook = "MacBook"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .responsive: return "arrow.left.and.right"
        case .iphone: return "iphone"
        case .tablet: return "ipad"
        case .macbook: return "laptopcomputer"
        }
    }
    
    var defaultWidth: CGFloat? {
        switch self {
        case .responsive: return nil
        case .iphone: return 447.0
        case .tablet: return 646.0
        case .macbook: return 802.0
        }
    }
    
    var defaultHeight: CGFloat? {
        switch self {
        case .responsive: return nil
        case .iphone: return 972.0
        case .tablet: return 938.0
        case .macbook: return 503.0
        }
    }
    
    var subtitle: String {
        switch self {
        case .responsive: return "Fluid Responsive • Drag handles to resize freely"
        case .iphone: return "iPhone 16 Pro • Official Apple Bezel Frame"
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
    @State private var inspectInstructionText: String = ""
    @State private var showPortRadarPopover: Bool = false
    @State private var inspectPopupDragOffset: CGSize = .zero
    @State private var inspectPopupAccumulatedOffset: CGSize = .zero
    @FocusState private var isInspectInputFocused: Bool
    @State private var showPromotedCaptureCard: Bool = false
    @State private var captureCopiedFeedback: Bool = false
    @State private var captureSentFeedback: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. Viewport & Device Selection Bar (Clean & Professional)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Device Viewport Switcher: Responsive, iPhone, iPad, MacBook
                    HStack(spacing: 2) {
                        ForEach(WebAppViewport.allCases) { vp in
                            let isSelected = selectedViewport == vp
                            Button {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    selectedViewport = vp
                                    if vp == .responsive {
                                        // Keep responsive mode
                                    } else {
                                        showDeviceBezel = true
                                        customWidth = nil
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: vp.icon)
                                        .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                    Text(vp.rawValue)
                                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                                )
                                .foregroundColor(isSelected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .fixedSize(horizontal: true, vertical: false)
                            .help(vp.subtitle)
                        }
                    }
                    
                    // Mode-Specific Controls
                    if selectedViewport == .responsive {
                        // Quick Preset / Dimension Dropdown Pill
                        Menu {
                            Button("Fluid (100% Full Width)") {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    customWidth = nil
                                }
                            }
                            Divider()
                            Button("Mobile S (320 px)") { withAnimation { customWidth = 320 } }
                            Button("Mobile M (375 px)") { withAnimation { customWidth = 375 } }
                            Button("Mobile L (430 px)") { withAnimation { customWidth = 430 } }
                            Button("Tablet (768 px)") { withAnimation { customWidth = 768 } }
                            Button("Laptop (1024 px)") { withAnimation { customWidth = 1024 } }
                            Button("Desktop (1280 px)") { withAnimation { customWidth = 1280 } }
                            Button("Wide (1440 px)") { withAnimation { customWidth = 1440 } }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.left.and.right")
                                    .font(.system(size: 8))
                                if let w = customWidth {
                                    Text("\(Int(w)) px")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                } else {
                                    Text("Fluid 100%")
                                        .font(.system(size: 10, weight: .medium))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7))
                            }
                            .foregroundColor(customWidth != nil ? .accentColor : .secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(customWidth != nil ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                            .cornerRadius(5)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize(horizontal: true, vertical: false)
                        .help("Drag preview handles to resize freely, or click to pick standard breakpoint")
                        
                        if customWidth != nil {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    customWidth = nil
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reset to Fluid 100% Full Width")
                        }
                    } else {
                        // Official Hardware Frame Toggle Button
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showDeviceBezel.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showDeviceBezel ? "checkmark.shield.fill" : "rectangle")
                                    .font(.system(size: 9))
                                Text(showDeviceBezel ? "Official Frame" : "Frameless")
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(showDeviceBezel ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                            .foregroundColor(showDeviceBezel ? .accentColor : .secondary)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: false)
                        .help(showDeviceBezel ? "Showing authentic Apple hardware chassis frame. Click for frameless." : "Showing frameless viewport. Click for authentic Apple hardware chassis frame.")
                        
                        // Rotate Orientation (iPhone & iPad)
                        if selectedViewport != .macbook {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isLandscape.toggle()
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: isLandscape ? "iphone.landscape" : "iphone")
                                        .font(.system(size: 9))
                                    Text(isLandscape ? "Landscape" : "Portrait")
                                        .font(.system(size: 10, weight: .medium))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                            .fixedSize(horizontal: true, vertical: false)
                            .help("Rotate device orientation")
                        }
                        
                        // Zoom Mode (Fit Window / Fit Width / 100%)
                        Button {
                            switch zoomMode {
                            case .fit: zoomMode = .fitWidth
                            case .fitWidth: zoomMode = .actual
                            case .actual: zoomMode = .fit
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: zoomMode.icon)
                                    .font(.system(size: 9))
                                Text(zoomMode.rawValue)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.secondary)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: false)
                        .help("Zoom Mode: \(zoomMode.rawValue). Click to cycle.")
                    }
                    
                    // Live Reload Indicator
                    Button {
                        isLiveReloadEnabled.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(isLiveReloadEnabled ? Color.green : Color.secondary)
                                .frame(width: 6, height: 6)
                            Text("Live")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(isLiveReloadEnabled ? .primary : .secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
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

                // Feature #1: Pinned Click-to-Inspect DOM Element Toggle (Always Visible)
                Button {
                    browserAutomation.toggleInspectMode(target: "preview")
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(browserAutomation.isInspectMode ? "Inspecting" : "Inspect")
                            .font(.system(size: 9.5, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(browserAutomation.isInspectMode ? Color.cyan.opacity(0.22) : Color.cyan.opacity(0.10))
                    .foregroundColor(.cyan)
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.cyan.opacity(browserAutomation.isInspectMode ? 0.6 : 0.25), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help("Click-to-Inspect Element (or Right-Click / Drag-Select anywhere in Preview) → Direct Agent Edit")
                
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

                // Feature #6: Active Port & Zombie Process Radar Popover Button
                Button {
                    showPortRadarPopover.toggle()
                    if showPortRadarPopover {
                        browserAutomation.scanActivePorts()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 8.5, weight: .semibold))
                        Text(browserAutomation.activePortProcesses.isEmpty ? "Ports" : "Ports (\(browserAutomation.activePortProcesses.count))")
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(showPortRadarPopover ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                    .foregroundColor(showPortRadarPopover ? .accentColor : .secondary)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Active Port & Zombie Process Radar — Switch localhost ports or kill stuck dev servers")
                .popover(isPresented: $showPortRadarPopover, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.accentColor)
                            Text("Active Localhost Ports")
                                .font(.system(size: 11, weight: .bold))
                            Spacer()
                            Button {
                                browserAutomation.scanActivePorts()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .help("Rescan listening TCP ports")
                            if !browserAutomation.activePortProcesses.isEmpty {
                                Button("Kill All") {
                                    browserAutomation.killAllDevPortProcesses()
                                }
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(.red)
                                .buttonStyle(.plain)
                            }
                        }
                        Divider()
                        if browserAutomation.isScanningPorts {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.5)
                                Text("Scanning listening TCP ports...")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        } else if browserAutomation.activePortProcesses.isEmpty {
                            Text("No active user localhost servers detected.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(browserAutomation.activePortProcesses) { item in
                                        HStack(spacing: 8) {
                                            Text(":\(item.port)")
                                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                                .foregroundColor(.green)
                                                .frame(width: 48, alignment: .leading)
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
                                            .background(Color.accentColor.opacity(0.14))
                                            .foregroundColor(.accentColor)
                                            .cornerRadius(4)
                                            .buttonStyle(.plain)

                                            Button {
                                                browserAutomation.killPortProcess(item)
                                            } label: {
                                                Image(systemName: "xmark.octagon.fill")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.red.opacity(0.85))
                                            }
                                            .buttonStyle(.plain)
                                            .help("Kill process \(item.processName) (PID \(item.pid)) on port \(item.port)")
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(Color.primary.opacity(0.04))
                                        .cornerRadius(5)
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                        }
                    }
                    .padding(10)
                    .frame(width: 290)
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

            // Feature #2: Live DOM & Console Error Auto-Healer Banner
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
            
            Divider()
            
            // MARK: - 3. Interactive Web View Canvas
            GeometryReader { geo in
                ZStack {
                    canvasColor
                    
                    let availW = geo.size.width
                    let availH = geo.size.height
                    
                    if showDeviceBezel, let spec = selectedViewport.frameSpec(isLandscape: isLandscape) {
                        // MARK: Authentic Hardware Bezel Mode
                        let maxW = max(60, availW - 16)
                        let maxH = max(60, availH - 16)
                        let fitScale = min(maxW / spec.frameSize.width, maxH / spec.frameSize.height)
                        let fitWidthScale = maxW / spec.frameSize.width
                        let activeScale: CGFloat = {
                            switch zoomMode {
                            case .fit: return fitScale
                            case .fitWidth: return fitWidthScale
                            case .actual: return 1.0
                            }
                        }()
                        
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
                                if isLandscape && selectedViewport != .macbook {
                                    Image(nsImage: bezel)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: spec.frameSize.height, height: spec.frameSize.width)
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: spec.frameSize.width, height: spec.frameSize.height)
                                        .position(
                                            x: spec.frameSize.width / 2,
                                            y: spec.frameSize.height / 2
                                        )
                                        .allowsHitTesting(false)
                                } else {
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
                                }
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
                        
                        if zoomMode == .fitWidth || zoomMode == .actual {
                            ScrollView([.horizontal, .vertical]) {
                                deviceView
                                    .scaleEffect(activeScale)
                                    .frame(width: spec.frameSize.width * activeScale, height: spec.frameSize.height * activeScale)
                                    .padding(.vertical, 16)
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
                    
                    // MARK: - Floating Contextual Inspect Popover (Anchored Near Picked Element)
                    if let picked = browserAutomation.lastPickedElement {
                        let vpW = max(1, CGFloat(picked.viewportWidth))
                        let vpH = max(1, CGFloat(picked.viewportHeight))
                        let elCenterX = ((CGFloat(picked.boundsX) + CGFloat(picked.boundsWidth) * 0.5) / vpW) * availW
                        let elTopY = (CGFloat(picked.boundsY) / vpH) * availH
                        let elBottomY = ((CGFloat(picked.boundsY) + CGFloat(picked.boundsHeight)) / vpH) * availH
                        
                        let cardW = min(max(290, availW - 24), 390)
                        let cardH: CGFloat = 116
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
                        
                        VStack(alignment: .leading, spacing: 7) {
                            // Draggable Popover Header
                            HStack(spacing: 6) {
                                Image(systemName: "scope")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.cyan)
                                
                                Text(picked.selector)
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.cyan.opacity(0.16))
                                    .foregroundColor(.cyan)
                                    .cornerRadius(4)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                if !picked.text.isEmpty {
                                    Text(picked.text)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                
                                Spacer(minLength: 4)
                                
                                Button {
                                    browserAutomation.clearPickedElement(target: "preview")
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary.opacity(0.85))
                                }
                                .buttonStyle(.plain)
                                .help("Close inspect popup (Esc)")
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
                            
                            // Quick Action Preset Chips
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 5) {
                                    ForEach([
                                        ("🎨 เปลี่ยนสี/ดีไซน์", "ปรับดีไซน์และสีของส่วนนี้ให้สวยงามทันสมัยขึ้น"),
                                        ("✏️ แก้ข้อความ", "แก้ไขข้อความในส่วนนี้ให้เป็น: "),
                                        ("📐 ปรับขนาด/Layout", "จัด Layout และระยะห่าง (padding/alignment) ของส่วนนี้ให้สมดุล"),
                                        ("✨ เพิ่ม Animation", "เพิ่ม transition/hover animation ให้ส่วนนี้ดูลื่นไหล"),
                                        ("🐛 แก้บั๊กส่วนนี้", "ตรวจสอบและแก้ไขบั๊กการทำงานของปุ่ม/ส่วนนี้")
                                    ], id: \.0) { label, preset in
                                        Button {
                                            if label.contains("แก้ข้อความ") {
                                                inspectInstructionText = preset
                                                isInspectInputFocused = true
                                            } else {
                                                browserAutomation.sendPickedElementToAgent(
                                                    picked,
                                                    instruction: preset,
                                                    pageURL: urlString,
                                                    autoSend: true
                                                )
                                                inspectInstructionText = ""
                                            }
                                        } label: {
                                            Text(label)
                                                .font(.system(size: 9.5, weight: .medium))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(Color.primary.opacity(0.08))
                                                .foregroundColor(.primary.opacity(0.9))
                                                .cornerRadius(5)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            
                            // Inline Prompt Input & Actions
                            HStack(spacing: 6) {
                                TextField("สั่ง AI แก้ส่วนนี้... (กด Enter ส่งทันที)", text: $inspectInstructionText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11.5))
                                    .focused($isInspectInputFocused)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5.5)
                                    .background(Color.primary.opacity(0.08))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.cyan.opacity(isInspectInputFocused ? 0.55 : 0.2), lineWidth: 1)
                                    )
                                    .onSubmit {
                                        browserAutomation.sendPickedElementToAgent(
                                            picked,
                                            instruction: inspectInstructionText.isEmpty ? "ช่วยปรับปรุงและแก้ไขส่วนนี้" : inspectInstructionText,
                                            pageURL: urlString,
                                            autoSend: true
                                        )
                                        inspectInstructionText = ""
                                    }
                                
                                Button {
                                    browserAutomation.sendPickedElementToAgent(
                                        picked,
                                        instruction: inspectInstructionText,
                                        pageURL: urlString,
                                        autoSend: false
                                    )
                                    inspectInstructionText = ""
                                } label: {
                                    Image(systemName: "plus.bubble")
                                        .font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 6)
                                        .background(Color.primary.opacity(0.09))
                                        .foregroundColor(.secondary)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .help("Attach to Chat input without sending immediately")
                                
                                Button {
                                    browserAutomation.sendPickedElementToAgent(
                                        picked,
                                        instruction: inspectInstructionText.isEmpty ? "ช่วยปรับปรุงและแก้ไขส่วนนี้" : inspectInstructionText,
                                        pageURL: urlString,
                                        autoSend: true
                                    )
                                    inspectInstructionText = ""
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "paperplane.fill")
                                            .font(.system(size: 9.5))
                                        Text("Send")
                                            .font(.system(size: 10.5, weight: .semibold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.cyan)
                                    .foregroundColor(.black)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .help("Send directly to AI Agent and edit code immediately")
                            }
                        }
                        .padding(10)
                        .frame(width: cardW)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color.cyan.opacity(0.65), lineWidth: 1.2)
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 8)
                        .position(x: finalX, y: finalY)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                        .zIndex(999)
                    }
                }
            }
        }
        .background(canvasColor)
        .onChange(of: browserAutomation.lastPickedElement?.id) { newId in
            inspectPopupDragOffset = .zero
            inspectPopupAccumulatedOffset = .zero
            if newId != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isInspectInputFocused = true
                }
            }
        }
        .onAppear {
            detectLocalWorkspaceIndex()
            resolveInitialURL()
            browserAutomation.scanActivePorts()
        }
        .onChange(of: browserAutomation.activePortProcesses) { processes in
            guard !processes.isEmpty else { return }
            let preferredPorts = [5173, 5174, 3000, 8080, 4200, 4321, 8000]
            let activePorts = Set(processes.map(\.port))
            if urlString == "http://localhost:3000" && !activePorts.contains(3000) {
                if let match = preferredPorts.first(where: { activePorts.contains($0) }) ?? processes.first?.port {
                    sanitizeAndSetURL("http://localhost:\(match)")
                }
            }
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
        .onChange(of: runtime.lastDetectedDevServerPort) { newPort in
            if let port = newPort, runtime.targetWebURL == nil, currentURL?.isFileURL != true {
                sanitizeAndSetURL("http://localhost:\(port)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeFileSaved"))) { note in
            handleFileSavedNotification(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeEditorFolderOpened"))) { _ in
            detectLocalWorkspaceIndex()
        }
    }

    private func handleFileSavedNotification(_ note: Notification) {
        let savedPath = (note.userInfo?["path"] as? String) ?? ""
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
        } else if !browserAutomation.activePortProcesses.isEmpty {
            let preferredPorts = [5173, 5174, 3000, 8080, 4200, 4321, 8000]
            let activePorts = Set(browserAutomation.activePortProcesses.map(\.port))
            let chosen = preferredPorts.first(where: { activePorts.contains($0) }) ?? browserAutomation.activePortProcesses[0].port
            sanitizeAndSetURL("http://localhost:\(chosen)")
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
