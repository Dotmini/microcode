//
//  PreviewView.swift
//  CodeTunner
//
//  Swift Preview แบบ Xcode / Swift Playground
//  iPhone/iPad Frame สวยเหมือนของจริง
//  ไม่ต้องใช้ iOS Simulator
//
//  SPU AI CLUB - Dotmini Software
//

import SwiftUI

struct PreviewView: View {
    @StateObject private var previewService = PreviewService.shared
    @EnvironmentObject var appState: AppState
    
    @State private var zoomLevel: CGFloat = 0.5
    @State private var isRunning = false
    @State private var selectedDevice: DeviceModel = .iPhone15Pro
    @State private var isDarkMode = false
    @State private var isLandscape = false
    @State private var isUniversalMode = false
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            topBar
            
            Divider()
            
            // Preview Area
            HStack(spacing: 0) {
                // Device Preview (Single or Universal)
                if isUniversalMode {
                    UniversalPreviewView()
                } else {
                    devicePreviewArea
                }
                
                Divider()
                
                // Console
                consoleArea
                    .frame(width: 280)
            }
        }
        .frame(width: 950, height: 700)
        .background(Color(white: 0.12))
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack(spacing: 12) {
            // Run Button
            Button {
                runPreview()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    Text(isRunning ? "Stop" : "Run")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isRunning ? Color.red : Color.green)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            Divider().frame(height: 20)
            
            // Device Picker
            Menu {
                ForEach(DeviceModel.allCases, id: \.self) { device in
                    Button {
                        selectedDevice = device
                    } label: {
                        HStack {
                            Image(systemName: device.icon)
                            Text(device.name)
                            if selectedDevice == device {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: selectedDevice.icon)
                    Text(selectedDevice.name)
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(white: 0.2))
                .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)
            
            // Orientation
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isLandscape.toggle()
                }
            } label: {
                Image(systemName: isLandscape ? "rectangle" : "rectangle.portrait")
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .padding(6)
            .background(Color(white: 0.2))
            .cornerRadius(6)
            
            // Dark Mode
            Button {
                isDarkMode.toggle()
            } label: {
                Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                    .foregroundColor(isDarkMode ? .yellow : .orange)
            }
            .buttonStyle(.plain)
            .padding(6)
            .background(Color(white: 0.2))
            .cornerRadius(6)
            
            // Universal Mode
            Button {
                withAnimation { isUniversalMode.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.split.3x1.fill")
                    Text("Universal")
                        .font(.caption)
                }
                .foregroundColor(isUniversalMode ? .white : .secondary)
            }
            .buttonStyle(.plain)
            .padding(6)
            .background(isUniversalMode ? Color.accentColor : Color(white: 0.2))
            .cornerRadius(6)
            
            Spacer()
            
            // Zoom
            HStack(spacing: 8) {
                Button { zoomLevel = max(0.3, zoomLevel - 0.1) } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.plain)
                
                Text("\(Int(zoomLevel * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 35)
                
                Button { zoomLevel = min(1.0, zoomLevel + 0.1) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            
            // Close
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.15))
    }
    
    // MARK: - Device Preview Area
    
    private var devicePreviewArea: some View {
        ZStack {
            // Grid background
            GridBackground()
            
            // Device Frame
            VStack(spacing: 16) {
                realisticDeviceFrame
                    .scaleEffect(zoomLevel)
                
                // Device name
                Text(selectedDevice.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Realistic Device Frame
    
    private var realisticDeviceFrame: some View {
        let device = selectedDevice
        let width = isLandscape ? device.height : device.width
        let height = isLandscape ? device.width : device.height
        
        return ZStack {
            // Device Body (Titanium frame)
            RoundedRectangle(cornerRadius: device.cornerRadius + 8)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.25), Color(white: 0.15), Color(white: 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: width + 20, height: height + 20)
                .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
            
            // Inner bezel (black)
            RoundedRectangle(cornerRadius: device.cornerRadius + 4)
                .fill(Color.black)
                .frame(width: width + 10, height: height + 10)
            
            // Screen
            ZStack {
                // Screen background
                RoundedRectangle(cornerRadius: device.cornerRadius)
                    .fill(isDarkMode ? Color.black : Color.white)
                
                // Screen content
                screenContent
                
                // Dynamic Island / Notch
                if device.hasDynamicIsland {
                    dynamicIslandView
                }
                
                // Status Bar
                statusBarView
                
                // Home Indicator
                if device.hasHomeIndicator {
                    homeIndicatorView
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: device.cornerRadius))
            
            // Side Buttons
            sideButtons(width: width, height: height)
        }
    }
    
    // MARK: - Dynamic Island
    
    private var dynamicIslandView: some View {
        VStack {
            Capsule()
                .fill(Color.black)
                .frame(width: 126, height: 37)
                .padding(.top, isLandscape ? 8 : 12)
            Spacer()
        }
    }
    
    // MARK: - Status Bar
    
    private var statusBarView: some View {
        let textColor = isDarkMode ? Color.white : Color.black
        
        return VStack {
            HStack {
                // Time
                Text("9:41")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(textColor)
                
                Spacer()
                
                // Status icons
                HStack(spacing: 5) {
                    Image(systemName: "cellularbars")
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100")
                }
                .font(.system(size: 12))
                .foregroundColor(textColor)
            }
            .padding(.horizontal, selectedDevice.hasDynamicIsland ? 32 : 20)
            .padding(.top, selectedDevice.hasDynamicIsland ? 55 : 12)
            
            Spacer()
        }
    }
    
    // MARK: - Home Indicator
    
    private var homeIndicatorView: some View {
        VStack {
            Spacer()
            Capsule()
                .fill(isDarkMode ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                .frame(width: 134, height: 5)
                .padding(.bottom, 8)
        }
    }
    
    // MARK: - Side Buttons
    
    private func sideButtons(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Power button (right)
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.3))
                    .frame(width: 3, height: 45)
                    .offset(x: width / 2 + 12, y: -height * 0.15)
            }
            
            // Volume buttons (left)
            HStack {
                VStack(spacing: 15) {
                    // Silent switch
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(white: 0.3))
                        .frame(width: 3, height: 25)
                    
                    // Volume up
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(white: 0.3))
                        .frame(width: 3, height: 45)
                    
                    // Volume down
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(white: 0.3))
                        .frame(width: 3, height: 45)
                }
                .offset(x: -(width / 2 + 12), y: -height * 0.12)
                
                Spacer()
            }
        }
    }
    
    // MARK: - Screen Content
    
    private var screenContent: some View {
        Group {
            if previewService.isPreviewLoading || isRunning {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(isDarkMode ? .white : .black)
                    Text("Building...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let image = previewService.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let error = previewService.previewError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "swift")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    
                    Text("Swift Preview")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(isDarkMode ? .white : .black)
                    
                    Text("Click Run to preview")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Console Area
    
    private var consoleArea: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.green)
                Text("Console")
                    .font(.caption.bold())
                Spacer()
                Button {
                    previewService.clearLogs()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color(white: 0.15))
            
            Divider()
            
            // Logs
            ScrollView {
                Text(previewService.previewLogs.isEmpty ? "Ready" : previewService.previewLogs)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(previewService.previewLogs.isEmpty ? .secondary : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(white: 0.08))
        }
    }
    
    // MARK: - Actions
    
    private func runPreview() {
        guard let filePath = appState.currentFile?.path else { return }
        
        if isRunning {
            previewService.stopPreview()
            isRunning = false
            return
        }
        
        isRunning = true
        
        // Update config
        previewService.configuration.colorScheme = isDarkMode ? .dark : .light
        previewService.configuration.device = DeviceFrame.allDevices.first { $0.name == selectedDevice.name }
            ?? DeviceFrame.allDevices[0]
        
        Task {
            if isUniversalMode {
                // Universal Run
                // Hardcoded devices for V1 (matches UniversalPreviewView)
                let devices: [DeviceFrame] = [
                    DeviceFrame.allDevices.first { $0.name == "iPhone SE" },
                    DeviceFrame.allDevices.first { $0.name == "iPhone 15 Pro" },
                    DeviceFrame.allDevices.first { $0.name == "iPad Pro 11" }
                ].compactMap { $0 }
                guard !devices.isEmpty else { isRunning = false; return }
                await previewService.runUniversalPreview(filePath: filePath, devices: devices, isDark: isDarkMode)
            } else {
                // Standard Run
                await previewService.runSwiftPlayground(filePath: filePath)
            }
            isRunning = false
        }
    }
}

// MARK: - Device Model

enum DeviceModel: String, CaseIterable {
    case iPhone15Pro = "iPhone 15 Pro"
    case iPhone15ProMax = "iPhone 15 Pro Max"
    case iPhone15 = "iPhone 15"
    case iPhoneSE = "iPhone SE"
    case iPadPro11 = "iPad Pro 11"
    case iPadPro13 = "iPad Pro 13"
    
    var name: String { rawValue }
    
    var width: CGFloat {
        switch self {
        case .iPhone15Pro, .iPhone15: return 393
        case .iPhone15ProMax: return 430
        case .iPhoneSE: return 375
        case .iPadPro11: return 834
        case .iPadPro13: return 1024
        }
    }
    
    var height: CGFloat {
        switch self {
        case .iPhone15Pro, .iPhone15: return 852
        case .iPhone15ProMax: return 932
        case .iPhoneSE: return 667
        case .iPadPro11: return 1194
        case .iPadPro13: return 1366
        }
    }
    
    var cornerRadius: CGFloat {
        switch self {
        case .iPhone15Pro, .iPhone15ProMax, .iPhone15: return 55
        case .iPhoneSE: return 0
        case .iPadPro11, .iPadPro13: return 20
        }
    }
    
    var icon: String {
        switch self {
        case .iPhone15Pro, .iPhone15ProMax, .iPhone15, .iPhoneSE: return "iphone"
        case .iPadPro11, .iPadPro13: return "ipad"
        }
    }
    
    var hasDynamicIsland: Bool {
        switch self {
        case .iPhone15Pro, .iPhone15ProMax, .iPhone15: return true
        default: return false
        }
    }
    
    var hasHomeIndicator: Bool {
        self != .iPhoneSE
    }
}

// MARK: - Grid Background

struct GridBackground: View {
    var body: some View {
        Canvas { context, size in
            let gridSize: CGFloat = 20
            
            for x in stride(from: 0, to: size.width, by: gridSize) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
            }
            
            for y in stride(from: 0, to: size.height, by: gridSize) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
            }
        }
        .background(Color(white: 0.1))
    }
}

// MARK: - Preview
