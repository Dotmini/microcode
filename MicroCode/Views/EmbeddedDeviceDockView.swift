//
//  EmbeddedDeviceDockView.swift
//  MicroCode
//
//  Shared interactive simulator / emulator dock for iOS & Android
//  Usable across both Code Editor and Agent modes.
//

import SwiftUI

struct EmbeddedDeviceDockView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var deviceRuntime = DeviceRuntimeService.shared
    @ObservedObject private var dockService = PreviewDockService.shared
    @State private var textToSend = ""
    @State private var showingTextInput = false
    @State private var isDropTargeted = false

    var body: some View {
        let canvas = appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.editorBackground)
        VStack(spacing: 0) {
            // MARK: - Multi-Purpose Tab Strip
            HStack(spacing: 4) {
                // Scrollable Tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(dockService.openTabs) { tab in
                            let isActive = (dockService.activeTabId == tab.id)
                            HStack(spacing: 4) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        dockService.selectTab(id: tab.id)
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: tab.icon)
                                            .font(.system(size: 10))
                                        Text(tab.title)
                                            .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                                            .lineLimit(1)
                                            .fixedSize()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if tab.isClosable {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            dockService.closeTab(id: tab.id)
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.secondary)
                                            .padding(3)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Close tab")
                                }
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isActive ? Color.primary.opacity(0.12) : Color.clear)
                            )
                            .foregroundColor(isActive ? .primary : .secondary)
                        }
                        
                    }
                    .padding(.horizontal, 4)
                }
                
                Spacer()

                // Quick action tools (clean, non-overlapping)
                if dockService.activeTab?.kind == .iOSPhysical {
                    // Physical iPhone Quick Refresh / Rescan
                    Button {
                        IOSDeviceCaptureService.shared.scanForDevices()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Rescan for connected iPhone/iPad")
                }

                if dockService.activeTab?.kind == .androidPhysical {
                    // Physical Android Quick Refresh / Rescan
                    Button {
                        Task { await AndroidStreamService.shared.scanDevices() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Rescan for connected Android USB devices")
                }

                if deviceRuntime.embeddedDockMode != .web && (dockService.activeTab?.kind == .ios || dockService.activeTab?.kind == .android) {
                    // Mobile Dev Tools Toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            deviceRuntime.showingMobileDevTools.toggle()
                        }
                    } label: {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 11))
                            .foregroundColor(deviceRuntime.showingMobileDevTools ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(deviceRuntime.showingMobileDevTools ? "Hide Dev Tools" : "Show Dev Tools (Push, GPS, Link, Logs)")

                    // Device Settings
                    Button {
                        deviceRuntime.showingDeviceRuntimeSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Device & Run settings")

                    if DeviceRuntimeService.shared.project?.runtime == .flutter {
                        Button {
                            DeviceRuntimeService.shared.hotReloadCurrentProject()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Flutter Hot Reload")
                    }

                    if deviceRuntime.embeddedDockMode == .android || dockService.activeTab?.kind == .android {
                        // Hardware Skin Switcher (Samsung Note 20 Ultra / Google Pixel 9 Pro)
                        Menu {
                            ForEach(AndroidDeviceSkin.allCases) { skin in
                                Button {
                                    deviceRuntime.selectedAndroidSkin = skin
                                } label: {
                                    HStack {
                                        Text(skin.rawValue)
                                        if deviceRuntime.selectedAndroidSkin == skin {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "candybarphone")
                                    .font(.system(size: 10))
                                Text(deviceRuntime.selectedAndroidSkin.shortName)
                                    .font(.system(size: 10, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(5)
                        }
                        .menuStyle(.borderlessButton)
                        .help("Select Android Hardware Frame & Skin")

                        Button { deviceRuntime.sendEmbeddedAndroidKey("4") } label: { Image(systemName: "chevron.left").font(.system(size: 11)) }
                            .buttonStyle(.plain).help("Android Back")
                        Button { deviceRuntime.sendEmbeddedAndroidKey("3") } label: { Image(systemName: "circle").font(.system(size: 11)) }
                            .buttonStyle(.plain).help("Android Home")
                        Button { deviceRuntime.sendEmbeddedAndroidKey("187") } label: { Image(systemName: "square.on.square").font(.system(size: 11)) }
                            .buttonStyle(.plain).help("Recent apps")
                        Button { showingTextInput.toggle() } label: { Image(systemName: "keyboard").font(.system(size: 11)) }
                            .buttonStyle(.plain).help("Send text to Android")
                            .popover(isPresented: $showingTextInput, arrowEdge: .top) {
                                HStack(spacing: 8) {
                                    TextField("Send text to device", text: $textToSend)
                                        .frame(width: 200)
                                        .onSubmit {
                                            deviceRuntime.sendEmbeddedAndroidText(textToSend)
                                            textToSend = ""
                                            showingTextInput = false
                                        }
                                    Button("Send") {
                                        deviceRuntime.sendEmbeddedAndroidText(textToSend)
                                        textToSend = ""
                                        showingTextInput = false
                                    }
                                }
                                .padding(10)
                            }
                    }
                }

                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 2)

                // Standard macOS Human Interface Close Button [✕] at top-right
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        appState.hidePreviewInspector()
                        dockService.hideDock()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close Preview Dock (⌘I)")
                .layoutPriority(10)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(canvas)
            
            Divider()

            if deviceRuntime.showingMobileDevTools && (dockService.activeTab?.kind == .ios || dockService.activeTab?.kind == .iOSPhysical || dockService.activeTab?.kind == .android) {
                MobileDevCommandBarView()
                Divider()
            }

            // MARK: - Dynamic Tab Content Router
            Group {
                if let active = dockService.activeTab {
                    switch active.kind {
                    case .web:
                        EmbeddedWebAppPreviewView(
                            runtime: deviceRuntime,
                            canvasColor: canvas,
                            onHide: {
                                deviceRuntime.showingEmbeddedDeviceDock = false
                                dockService.isDockVisible = false
                            }
                        )
                    case .ios:
                        EmbeddedAppleSimulatorView(
                            canvasColor: canvas,
                            onConfigure: { deviceRuntime.showingDeviceRuntimeSheet = true },
                            onHide: {
                                Task { await ServeSimService.shared.stop() }
                                deviceRuntime.showingEmbeddedDeviceDock = false
                                dockService.isDockVisible = false
                                deviceRuntime.showingEmbeddedAppleDock = false
                            }
                        )
                    case .iOSPhysical:
                        PhysicalIOSDeviceTabView(canvasColor: canvas)
                    case .androidPhysical:
                        PhysicalAndroidDeviceTabView()
                    case .android:
                        EmbeddedAndroidDeviceView(
                            runtime: deviceRuntime,
                            canvasColor: canvas,
                            onConfigure: { deviceRuntime.showingDeviceRuntimeSheet = true },
                            onHide: {
                                deviceRuntime.showingEmbeddedDeviceDock = false
                                dockService.isDockVisible = false
                            }
                        )
                    case .file(let url):
                        filePreviewRouter(for: url, canvas: canvas)
                    case .diff(_, let title, let oldContent, let newContent):
                        InteractiveDiffPreviewView(title: title, oldContent: oldContent, newContent: newContent)
                    }
                } else {
                    // Empty Drop Zone State
                    VStack(spacing: 10) {
                        Image(systemName: "square.dashed")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.35))
                        Text("Drop a file here to preview")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(canvas)
        .overlay(
            Group {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .background(Color.accentColor.opacity(0.08))
                }
            }
        )
        .onDrop(of: ["public.file-url"], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let fileURL = url {
                    DispatchQueue.main.async {
                        dockService.openFile(url: fileURL, makeActive: true)
                    }
                }
            }
            return true
        }
    }

    @ViewBuilder
    private func filePreviewRouter(for url: URL, canvas: Color) -> some View {
        let fileType = PreviewFileType.detect(url: url)
        switch fileType {
        case .image:
            InteractiveImagePreviewView(url: url)
        case .pdf:
            InteractivePDFPreviewView(url: url)
        case .spreadsheet:
            UniversalSpreadsheetView(url: url)
        case .diff:
            InteractiveDiffFilePreviewView(url: url)
        case .codeOrText:
            InteractiveCodePreviewView(url: url)
        case .quickLook:
            QuickLookDocumentHost(url: url)
        }
    }
}

struct DevicePreviewHeaderMenu: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var deviceRuntime = DeviceRuntimeService.shared
    @ObservedObject private var dockService = PreviewDockService.shared

    private var isPreviewShowing: Bool {
        deviceRuntime.showingEmbeddedDeviceDock || dockService.isDockVisible || (appState.agenticContextVisible && appState.selectedInspectorTab == .preview)
    }

    var body: some View {
        HStack(spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isPreviewShowing {
                        appState.hidePreviewInspector()
                        dockService.hideDock()
                    } else {
                        appState.showPreviewInspector()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: deviceRuntime.showingEmbeddedAppleDock ? "iphone" : "candybarphone")
                        .font(.system(size: 10))
                        .foregroundColor(isPreviewShowing ? .accentColor : .secondary)
                    
                    Text("Preview")
                        .font(.system(size: 11, weight: isPreviewShowing ? .semibold : .medium))
                        .foregroundColor(isPreviewShowing ? .primary : .secondary)
                }
                .padding(.leading, 8)
                .padding(.trailing, 2)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .help(isPreviewShowing ? "Hide Simulator / Preview" : "Show Simulator / Preview")
            
            Menu {
                Button("Choose Device & Run…") {
                    deviceRuntime.showingDeviceRuntimeSheet = true
                }
                
                Button("iPhone USB (Hardware)") {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        PreviewDockService.shared.selectTab(id: "ios-physical")
                    }
                }
                
                Divider()
                
                let appleSimulators = deviceRuntime.devices.filter(\.isAppleSimulator)
                let physicalAppleDevices = deviceRuntime.devices.filter(\.isPhysicalAppleDevice)
                let androidDevices = deviceRuntime.devices.filter { $0.platform == .android }
                
                if !appleSimulators.isEmpty {
                    ForEach(AppleSimulatorFamily.previewOrder) { family in
                        let devices = appleSimulators.filter { $0.appleSimulatorFamily == family }
                        if !devices.isEmpty {
                            Section(family.menuTitle) {
                                ForEach(devices) { device in
                                    Button("\(device.name) — \(device.state)") {
                                        Task { await openRuntimeDestination(device) }
                                    }
                                    .disabled(deviceRuntime.isWorking || !device.isReadyForLaunch)
                                }
                            }
                        }
                    }
                }
                
                if !physicalAppleDevices.isEmpty {
                    Section("iPhone & iPad") {
                        ForEach(physicalAppleDevices) { device in
                            Button("\(device.name) — \(device.state)") {
                                Task { await openRuntimeDestination(device) }
                            }
                            .disabled(deviceRuntime.isWorking || !device.isReadyForLaunch)
                        }
                    }
                }
                
                if !androidDevices.isEmpty {
                    Section("Android Preview") {
                        ForEach(androidDevices) { device in
                            Button("\(device.name) — \(device.state)") {
                                Task { await openRuntimeDestination(device) }
                            }
                            .disabled(deviceRuntime.isWorking || !device.isReadyForLaunch)
                        }
                    }
                }
                
                if appleSimulators.isEmpty && physicalAppleDevices.isEmpty && androidDevices.isEmpty {
                    Text("No runtimes detected")
                }
                
                Divider()
                Button("Refresh Devices") {
                    Task { await deviceRuntime.refresh(workspace: appState.workspaceFolder) }
                }
                
                if isPreviewShowing {
                    Divider()
                    Button("Close Preview") {
                        withAnimation {
                            appState.hidePreviewInspector()
                            dockService.hideDock()
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 2)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 14)
            .padding(.trailing, 4)
        }
        .background(deviceRuntime.showingEmbeddedDeviceDock ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
        .cornerRadius(5)
    }
    
    private func openRuntimeDestination(_ device: RuntimeDevice) async {
        await deviceRuntime.openRuntimeDestination(device)
    }
}
