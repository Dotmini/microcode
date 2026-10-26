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
    @ObservedObject private var hotReloadEngine = PreviewHotReloadEngine.shared
    var showsCloseButton: Bool = true
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
                            HStack(spacing: 5) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        dockService.selectTab(id: tab.id)
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        if case .file(let fileURL) = tab.kind {
                                            ProgrammingLanguageIconView(fileName: fileURL.lastPathComponent, size: 13)
                                        } else {
                                            Image(systemName: tab.icon)
                                                .font(.system(size: 10))
                                        }
                                        Text(tab.title)
                                            .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
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
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isActive ? Color.primary.opacity(0.11) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(isActive ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 0.8)
                            )
                            .foregroundColor(isActive ? .primary : .secondary)
                        }

                        // "+" Open Preview / File Tab menu
                        Menu {
                            Button {
                                dockService.selectTab(id: "web")
                            } label: {
                                Label("WebApp Preview (Localhost)", systemImage: "globe")
                            }
                            Button {
                                dockService.selectTab(id: "ios")
                            } label: {
                                Label("iOS Simulator", systemImage: "iphone")
                            }
                            Button {
                                dockService.selectTab(id: "android")
                            } label: {
                                Label("Android Emulator", systemImage: "candybarphone")
                            }
                            Divider()
                            Button {
                                dockService.pickAndOpenFile()
                            } label: {
                                Label("Open File to Preview…", systemImage: "doc.badge.plus")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Open WebApp Preview, Simulator, or File in Split Pane")
                        
                    }
                    .padding(.horizontal, 4)
                }
                
                Spacer()

                // Universal Playground-style Hot Reload Control Group (hidden on .web tab which has its own unified toolbar)
                if dockService.activeTab?.kind != .web {
                    hotReloadControlsBar
                }

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

                    if dockService.activeTab?.kind == .ios && (ServeSimService.shared.isActive || deviceRuntime.isWorking) {
                        Button {
                            deviceRuntime.stopEmbeddedAppleSimulator(shutdownSimulator: true)
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Stop iOS Simulator & free CPU")
                    }

                    if dockService.activeTab?.kind == .android && (deviceRuntime.isEmbeddedAndroidActive || deviceRuntime.isWorking) {
                        Button {
                            deviceRuntime.stopEmbeddedAndroid(shutdownEmulator: true)
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Stop Android Emulator & free CPU")
                    }

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

                if showsCloseButton {
                    Divider()
                        .frame(height: 14)
                        .padding(.horizontal, 2)

                    // Expand / Restore Split Pane Width Button (matching Antigravity top-right controls)
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            dockService.isExpandedWidth.toggle()
                        }
                    } label: {
                        Image(systemName: dockService.isExpandedWidth ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(dockService.isExpandedWidth ? .accentColor : .secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(dockService.isExpandedWidth ? "Restore Split Width" : "Expand Preview Split Width")

                    // Standard macOS Human Interface Close Button [✕] at top-right
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            appState.hidePreviewInspector()
                            dockService.hideDock()
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Close Preview Split Pane (⌘I)")
                    .layoutPriority(10)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
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
                                appState.hidePreviewInspector()
                                dockService.hideDock()
                            }
                        )
                    case .ios:
                        EmbeddedAppleSimulatorView(
                            canvasColor: canvas,
                            onConfigure: { deviceRuntime.showingDeviceRuntimeSheet = true },
                            onHide: {
                                appState.hidePreviewInspector()
                                dockService.hideDock()
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
                                appState.hidePreviewInspector()
                                dockService.hideDock()
                            }
                        )
                    case .file(let url):
                        filePreviewRouter(for: url, canvas: canvas)
                    case .diff(_, let title, let oldContent, let newContent):
                        InteractiveDiffPreviewView(title: title, oldContent: oldContent, newContent: newContent)
                    }
                } else {
                    // Quick Preview Hub (shown only if all tabs were cleared)
                    VStack(spacing: 14) {
                        Image(systemName: "sparkles.tv")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.accentColor.opacity(0.85))
                        Text("Live Preview & Device Hub")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Select a runtime surface or drop any file here to preview")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Button {
                                dockService.selectTab(id: "web")
                            } label: {
                                Label("WebApp Preview", systemImage: "globe")
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.16))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            Button {
                                dockService.selectTab(id: "ios")
                            } label: {
                                Label("iOS Sim", systemImage: "iphone")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.primary.opacity(0.08))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            Button {
                                dockService.pickAndOpenFile()
                            } label: {
                                Label("Open File…", systemImage: "doc")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.primary.opacity(0.08))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        dockService.ensureDefaultTabsIfEmpty()
                    }
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
        .onAppear {
            dockService.ensureDefaultTabsIfEmpty()
            hotReloadEngine.scanWorkspaceForRecentChanges(source: "Startup")
        }
        .onChange(of: appState.workspaceFolder) { _ in
            hotReloadEngine.scanWorkspaceForRecentChanges(source: "Workspace")
        }
    }

    @ViewBuilder
    private var hotReloadControlsBar: some View {
        HStack(spacing: 4) {
            Menu {
                Toggle("Auto Hot Reload on Save / Agent Edit", isOn: $hotReloadEngine.isAutoHotReloadEnabled)
                Toggle("Live Typing (Playground Mode)", isOn: $hotReloadEngine.isLiveTypingEnabled)
                Divider()
                Button {
                    triggerActiveTabHotReload()
                } label: {
                    Label("Hot Reload Now (⌘R)", systemImage: "bolt.clockwise")
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: hotReloadEngine.isAutoHotReloadEnabled ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(hotReloadEngine.isAutoHotReloadEnabled ? .green : .secondary)
                    if deviceRuntime.isHotReloading {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.65)
                    } else if hotReloadEngine.reloadCount > 0 {
                        Text("\(hotReloadEngine.lastReloadDurationMs)ms")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Hot")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(hotReloadEngine.isAutoHotReloadEnabled ? .primary : .secondary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(hotReloadEngine.isAutoHotReloadEnabled ? Color.green.opacity(0.12) : Color.primary.opacity(0.06))
                )
            }
            .menuStyle(.borderlessButton)
            .help("Hot Reload Settings (Auto Reload on Save, Agent Edit & Live Typing)")

            Button {
                triggerActiveTabHotReload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(deviceRuntime.isHotReloading ? .accentColor : .secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Instant Hot Reload Active Preview")
        }
    }

    private func triggerActiveTabHotReload() {
        let start = CFAbsoluteTimeGetCurrent()
        guard let active = dockService.activeTab else {
            dockService.reloadWeb()
            return
        }
        switch active.kind {
        case .web:
            dockService.reloadWeb()
            hotReloadEngine.reloadCount += 1
            hotReloadEngine.lastReloadDurationMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
            hotReloadEngine.lastReloadSource = "Manual Web"
        case .ios, .android, .iOSPhysical, .androidPhysical:
            deviceRuntime.performHotReload(reason: "Manual")
            hotReloadEngine.reloadCount += 1
        case .file(let url):
            NotificationCenter.default.post(
                name: NSNotification.Name("MicroCodeFileSaved"),
                object: nil,
                userInfo: ["path": url.path, "source": "Manual"]
            )
            hotReloadEngine.reloadCount += 1
            hotReloadEngine.lastReloadDurationMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
            hotReloadEngine.lastReloadSource = "Manual File"
        case .diff:
            break
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
            InteractiveCodePreviewView(url: url, highlightRange: dockService.activeTab?.highlightRange)
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
                        appState.showPreviewInspector()
                        PreviewDockService.shared.selectTab(id: "ios-physical")
                    }
                }

                Button("Android USB (Hardware)") {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        appState.showPreviewInspector()
                        PreviewDockService.shared.selectTab(id: "android-physical")
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
