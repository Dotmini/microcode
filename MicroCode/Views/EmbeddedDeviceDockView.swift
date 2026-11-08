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
    @ObservedObject private var serveSim = ServeSimService.shared
    @ObservedObject private var dockService = PreviewDockService.shared
    @ObservedObject private var hotReloadEngine = PreviewHotReloadEngine.shared
    var showsCloseButton: Bool = true
    @State private var textToSend = ""
    @State private var showingTextInput = false
    @State private var isDropTargeted = false
    @State private var isHoveringCloseDock = false

    private var shouldShowHotReloadControls: Bool {
        guard let kind = dockService.activeTab?.kind else { return false }
        switch kind {
        case .web, .diff:
            return false
        case .ios, .android, .iOSPhysical, .androidPhysical:
            return true
        case .file(let url):
            let ext = url.pathExtension.lowercased()
            return ["swift", "html", "htm", "svg", "md", "markdown", "mdx"].contains(ext)
        }
    }

    var body: some View {
        let canvas = appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.editorBackground)
        let panelBg = appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground)
        VStack(spacing: 0) {
            // MARK: - Multi-Purpose Tab Strip
            HStack(spacing: 4) {
                // Scrollable Tabs with Auto-Scroll to Active Tab
                ScrollViewReader { tabScrollProxy in
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
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(isActive ? .primary.opacity(0.8) : .secondary)
                                                .frame(width: 16, height: 16)
                                                .background(Color.primary.opacity(isActive ? 0.08 : 0.0))
                                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .help("Close tab")
                                    }
                                }
                                .padding(.leading, 8)
                                .padding(.trailing, 5)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isActive ? Color(nsColor: appState.appTheme.elevatedBackground) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(isActive ? Color.primary.opacity(0.16) : Color.clear, lineWidth: 0.8)
                                )
                                .foregroundColor(isActive ? .primary : .secondary)
                                .id(tab.id)
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
                    .onAppear {
                        DispatchQueue.main.async {
                            tabScrollProxy.scrollTo(dockService.activeTabId, anchor: .center)
                        }
                    }
                    .onChange(of: dockService.activeTabId) { newId in
                        withAnimation(.easeInOut(duration: 0.16)) {
                            tabScrollProxy.scrollTo(newId, anchor: .center)
                        }
                    }
                    .onChange(of: dockService.openTabs.count) { _ in
                        DispatchQueue.main.async {
                            tabScrollProxy.scrollTo(dockService.activeTabId, anchor: .center)
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .clipped()
                }
                .layoutPriority(-1)
                
                Spacer(minLength: 4)

                // Universal Playground-style Hot Reload Control Group (shown only on runtime & live-renderable tabs)
                if shouldShowHotReloadControls {
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

                    if dockService.activeTab?.kind == .ios && (serveSim.isActive || serveSim.connectionState == .connecting || deviceRuntime.isWorking) {
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

                    if dockService.activeTab?.kind == .ios {
                        // iOS Simulator Target Picker (supports unified iPhone Duo Outer/Inner, all ready iPhone/iPad models, plus full detected Mac catalog)
                        Menu {
                            AppleSimulatorSelectorMenuContent(
                                autoStartIfActive: true,
                                workspaceURL: appState.workspaceFolder
                            )
                        } label: {
                            HStack(spacing: 3) {
                                let toolbarIcon: String = {
                                    if deviceRuntime.isSelectedDeviceIPhoneDuo && deviceRuntime.iPhoneDuoDisplayMode == .inner {
                                        return "book.pages"
                                    }
                                    if deviceRuntime.selectedDevice?.appleSimulatorFamily == .iPad {
                                        return "ipad"
                                    }
                                    return "iphone"
                                }()
                                Image(systemName: toolbarIcon)
                                    .font(.system(size: 10))
                                Text(deviceRuntime.selectedAppleToolbarTitle)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
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
                        .fixedSize()
                        .help("เลือกรุ่น iOS / iPadOS Simulator (iPhone Duo / iPhone / iPad ที่ตรวจพบในเครื่อง)")

                        // 1-Click Outer / Inner Screen Switcher for iPhone Duo (จอนอก ↔ จอใน)
                        if deviceRuntime.isSelectedDeviceIPhoneDuo {
                            HStack(spacing: 2) {
                                ForEach(IPhoneDuoDisplayMode.allCases) { mode in
                                    Button {
                                        Task { await deviceRuntime.setIPhoneDuoDisplayMode(mode) }
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: mode.icon)
                                                .font(.system(size: 8.5, weight: .semibold))
                                            Text(mode.compactBadge)
                                                .font(.system(size: 9.5, weight: .semibold))
                                        }
                                        .padding(.horizontal, 6)
                                        .frame(height: 18)
                                        .background(deviceRuntime.iPhoneDuoDisplayMode == mode ? Color.accentColor : Color.clear)
                                        .foregroundColor(deviceRuntime.iPhoneDuoDisplayMode == mode ? .white : .secondary)
                                        .cornerRadius(3.5)
                                    }
                                    .buttonStyle(.plain)
                                    .help("iPhone Duo — \(mode.shortLabel) (\(mode.resolutionLabel))")
                                }
                            }
                            .padding(2)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(5)
                            .fixedSize()
                        }
                    }

                    if deviceRuntime.embeddedDockMode == .android || dockService.activeTab?.kind == .android {
                        // Detected Android Device & AVD Picker (dynamically lists user's real AVDs & connected ADB phones)
                        Menu {
                            AndroidDeviceSelectorMenuContent(autoStartIfActive: true)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "candybarphone")
                                    .font(.system(size: 10))
                                Text(deviceRuntime.selectedAndroidToolbarTitle)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
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
                        .fixedSize()
                        .help("เลือกรุ่น Android Emulator / อุปกรณ์ Android ที่ตรวจพบในเครื่อง")

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
                    HStack(spacing: 5) {
                        Divider()
                            .frame(height: 14)
                            .padding(.trailing, 1)

                        // Expand / Restore Split Pane Width Button (matching Antigravity top-right controls)
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                dockService.isExpandedWidth.toggle()
                            }
                        } label: {
                            Image(systemName: dockService.isExpandedWidth ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(dockService.isExpandedWidth ? .accentColor : .primary.opacity(0.8))
                                .frame(width: 24, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(dockService.isExpandedWidth ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(dockService.isExpandedWidth ? Color.accentColor.opacity(0.32) : Color.primary.opacity(0.12), lineWidth: 0.8)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help(dockService.isExpandedWidth ? "Restore Split Width" : "Expand Preview Split Width")

                        // Unmistakable Close Button [✕] at top-right of Preview Split Pane
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                appState.hidePreviewInspector()
                                dockService.hideDock()
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundColor(isHoveringCloseDock ? .white : .primary.opacity(0.85))
                                .frame(width: 24, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(isHoveringCloseDock ? Color.red.opacity(0.85) : Color.primary.opacity(0.10))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(isHoveringCloseDock ? Color.red.opacity(0.95) : Color.primary.opacity(0.14), lineWidth: 0.8)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .onHover { hovering in
                            isHoveringCloseDock = hovering
                        }
                        .help("Close Preview Pane (⌘I)")
                    }
                    .padding(.leading, 4)
                    .fixedSize()
                    .layoutPriority(10)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(panelBg)
            
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
                        .onAppear {
                            deviceRuntime.selectDefaultAppleSimulatorIfNeeded()
                        }
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
                            .id(active.id)
                    case .diff(let id, let title, let oldContent, let newContent):
                        InteractiveDiffPreviewView(title: title, oldContent: oldContent, newContent: newContent)
                            .id("\(id):\(oldContent.hashValue):\(newContent.hashValue)")
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
    @ObservedObject private var serveSim = ServeSimService.shared
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
                
                let appleSimulators = deviceRuntime.pickerAppleSimulators
                let physicalAppleDevices = deviceRuntime.devices.filter(\.isPhysicalAppleDevice)
                let androidDevices = deviceRuntime.devices.filter { $0.platform == .android }
                
                if !appleSimulators.isEmpty {
                    ForEach(AppleSimulatorFamily.previewOrder) { family in
                        let devices = appleSimulators.filter { $0.appleSimulatorFamily == family }
                        if !devices.isEmpty {
                            Section(family.menuTitle) {
                                ForEach(devices) { device in
                                    let labelName = device.isIPhoneDuoFamily ? "iPhone Duo (\(deviceRuntime.iPhoneDuoDisplayMode.compactBadge))" : device.name
                                    Button("\(labelName) — \(device.state)") {
                                        Task { await openRuntimeDestination(device) }
                                    }
                                    .disabled(deviceRuntime.isWorking || !device.isReadyForLaunch)
                                }
                            }
                        }
                    }
                }

                if !deviceRuntime.detectedIPhoneModels.isEmpty || !deviceRuntime.detectedIPadModels.isEmpty {
                    Menu("เพิ่ม/รันรุ่นอื่นที่ตรวจพบในเครื่อง…") {
                        if !deviceRuntime.detectedIPhoneModels.isEmpty {
                            Menu("iPhone (\(deviceRuntime.detectedIPhoneModels.count) รุ่น)") {
                                ForEach(deviceRuntime.detectedIPhoneModels) { model in
                                    Button("\(model.name) (\(model.runtimeName))") {
                                        Task {
                                            withAnimation(.easeInOut(duration: 0.16)) {
                                                appState.showPreviewInspector()
                                                PreviewDockService.shared.selectTab(id: "ios")
                                            }
                                            await deviceRuntime.selectOrProvisionDetectedModel(model, autoStartIfActive: true)
                                            if !ServeSimService.shared.isActive {
                                                await deviceRuntime.startEmbeddedAppleSimulator()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if !deviceRuntime.detectedIPadModels.isEmpty {
                            Menu("iPad (\(deviceRuntime.detectedIPadModels.count) รุ่น)") {
                                ForEach(deviceRuntime.detectedIPadModels) { model in
                                    Button("\(model.name) (\(model.runtimeName))") {
                                        Task {
                                            withAnimation(.easeInOut(duration: 0.16)) {
                                                appState.showPreviewInspector()
                                                PreviewDockService.shared.selectTab(id: "ios")
                                            }
                                            await deviceRuntime.selectOrProvisionDetectedModel(model, autoStartIfActive: true)
                                            if !ServeSimService.shared.isActive {
                                                await deviceRuntime.startEmbeddedAppleSimulator()
                                            }
                                        }
                                    }
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
