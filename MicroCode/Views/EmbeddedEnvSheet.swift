//
//  EmbeddedEnvSheet.swift
//  MicroCode
//
//  UI for Embedded Environment & Arduino Library Management
//  Modeled after Cell Mode's PythonEnvSheet for seamless embedded workflow.
//

import SwiftUI

public struct EmbeddedEnvSheet: View {
    @ObservedObject var envManager = EmbeddedEnvManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTab: Int = 0 // 0: Installed, 1: Search, 2: Popular, 3: Toolchains
    @State private var manualLibraryToInstall: String = ""
    @State private var searchQuery: String = ""
    @State private var customIdfInput: String = ""
    @State private var isConsoleExpanded: Bool = true
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            header
            
            Divider().opacity(0.4)
            
            HStack(spacing: 0) {
                // Left Navigator (Categorized like Cell Mode)
                leftNavigator
                    .frame(width: 230)
                    .background(Color(white: 0.05))
                
                Divider().opacity(0.4)
                
                // Right Content Panel
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            switch selectedTab {
                            case 0:
                                installedLibrariesView
                            case 1:
                                registrySearchView
                            case 2:
                                popularLibrariesView
                            case 3:
                                toolchainsView
                            default:
                                installedLibrariesView
                            }
                        }
                        .padding(22)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Expandable Live CLI Console Output
                    if !envManager.consoleOutput.isEmpty {
                        Divider().opacity(0.4)
                        consoleOutputDrawer
                    }
                }
            }
        }
        .frame(width: 860, height: 640)
        .background(Color(white: 0.07))
        .onAppear {
            envManager.refreshInstalledLibraries()
            envManager.detectEspIdf()
            envManager.detectAllToolchains()
            customIdfInput = envManager.idfPath
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 32, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25), lineWidth: 1))
                
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Embedded Environment & Libraries")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text("Manage Arduino libraries, hardware toolchains, and sketch dependencies.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.6))
            }
            
            Spacer(minLength: 12)
            
            if envManager.isWorking {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.65).frame(width: 14, height: 14)
                    Text(envManager.workingMessage)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Color(white: 0.7))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .cornerRadius(4)
            }
            
            Button(action: {
                envManager.refreshInstalledLibraries()
                envManager.detectAllToolchains()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("REFRESH")
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .foregroundColor(.white)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(envManager.isWorking)
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundColor(Color(white: 0.6))
            .background(Color.white.opacity(0.06), in: Circle())
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(white: 0.06))
    }
    
    // MARK: - Left Navigator
    
    private var leftNavigator: some View {
        VStack(alignment: .leading, spacing: 14) {
            // SECTION: LIBRARIES
            VStack(alignment: .leading, spacing: 4) {
                Text("LIBRARIES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.45))
                    .tracking(0.8)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                
                navButton(title: "Installed Libraries", icon: "folder.fill", badge: "\(envManager.installedLibraries.count)", tab: 0)
                navButton(title: "Popular Hardware Libs", icon: "sparkles", badge: "12", tab: 2)
                navButton(title: "Registry Search", icon: "magnifyingglass", badge: nil, tab: 1)
            }
            
            // SECTION: TOOLCHAINS
            VStack(alignment: .leading, spacing: 4) {
                Text("TOOLCHAINS & HARDWARE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.45))
                    .tracking(0.8)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                
                navButton(title: "Compilers & Tools", icon: "hammer.fill", badge: "\(envManager.toolchains.filter { $0.isInstalled }.count)/\(envManager.toolchains.count)", tab: 3)
            }
            
            Spacer()
            
            // Quick Status Footer
            VStack(alignment: .leading, spacing: 4) {
                Text("ARDUINO CLI PATH")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                Text(envManager.toolchains.first(where: { $0.binaryName == "arduino-cli" })?.path ?? "Not found")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundColor(Color(white: 0.6))
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.02))
        }
    }
    
    private func navButton(title: String, icon: String, badge: String?, tab: Int) -> some View {
        let isSelected = selectedTab == tab
        return Button(action: { selectedTab = tab }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 16)
                    .foregroundColor(isSelected ? .white : Color(white: 0.5))
                
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : Color(white: 0.7))
                
                Spacer()
                
                if let b = badge {
                    Text(b)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(isSelected ? .white : Color(white: 0.4))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                        .cornerRadius(3)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
            .cornerRadius(5)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(isSelected ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
    
    // MARK: - Tab 0: Installed Libraries
    
    private var installedLibrariesView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Card 1: Detected in Code (Just like Cell Mode's packageSuggestions!)
            detectedLibrariesCard
            
            // Card 2: Manual Install Bar
            manualInstallCard
            
            // Card 3: List of Installed Libraries
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("INSTALLED LIBRARIES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))
                        .tracking(0.8)
                    Spacer()
                    Text("\(envManager.installedLibraries.count) TOTAL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                }
                
                if envManager.installedLibraries.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 14))
                            .foregroundColor(Color(white: 0.3))
                        Text("No external Arduino libraries found. Use 'Install Detected' or pick from 'Popular Hardware Libs'.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(white: 0.4))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.05), lineWidth: 1))
                } else {
                    VStack(spacing: 6) {
                        ForEach(envManager.installedLibraries) { lib in
                            installedLibraryRow(lib)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Detected in Code Card
    
    private var detectedLibrariesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .foregroundColor(.white)
                Text("Detected in Current Sketch")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("FROM ACTIVE CODE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
            }
            
            if envManager.detectedLibraries.isEmpty {
                Text("No third-party headers detected in the current file. Add #include statements (e.g. <WiFi.h>, <ArduinoJson.h>, <Adafruit_NeoPixel.h>) to detect dependencies.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.5))
            } else {
                HStack(spacing: 6) {
                    ForEach(envManager.detectedLibraries, id: \.self) { item in
                        let isInst = envManager.installedLibraries.contains(where: { $0.name.lowercased() == item.lowercased() })
                        HStack(spacing: 4) {
                            Circle()
                                .fill(isInst ? Color.white : Color(white: 0.3))
                                .frame(width: 4, height: 4)
                            Text(item)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(isInst ? .white : Color(white: 0.7))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(isInst ? 0.12 : 0.04))
                        .cornerRadius(3)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(isInst ? 0.25 : 0.08), lineWidth: 1))
                    }
                }
                
                let missingCount = envManager.detectedLibraries.filter { item in
                    !envManager.installedLibraries.contains(where: { $0.name.lowercased() == item.lowercased() }) &&
                    !item.contains("(I2C)") && !item.contains("(Bus)") && !item.contains("(NVS)")
                }.count
                
                HStack(spacing: 8) {
                    Button(action: {
                        envManager.installMultipleLibraries(names: envManager.detectedLibraries)
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("INSTALL DETECTED LIBRARIES (\(envManager.detectedLibraries.count))")
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(envManager.isWorking)
                    
                    if missingCount == 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                            Text("All dependencies installed")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color(white: 0.7))
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
    
    // MARK: - Manual Install Card
    
    private var manualInstallCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUICK INSTALL ARDUINO LIBRARY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
            
            HStack(spacing: 8) {
                TextField("Type library name (e.g. ArduinoJson, FastLED, Adafruit NeoPixel)", text: $manualLibraryToInstall)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.black)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15), lineWidth: 1))
                
                Button(action: {
                    let name = manualLibraryToInstall.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    envManager.installLibrary(name: name) { success, _ in
                        if success {
                            manualLibraryToInstall = ""
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        Text("INSTALL")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(manualLibraryToInstall.trimmingCharacters(in: .whitespaces).isEmpty || envManager.isWorking)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.02))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
    
    private func installedLibraryRow(_ lib: EmbeddedLibrary) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 24, height: 24)
                Image(systemName: "cube.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(lib.name)
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    
                    Text("v\(lib.version)")
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(white: 0.6))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(2)
                    
                    Text(lib.category)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                }
                
                Text(lib.descriptionText)
                    .font(.system(size: 9.5))
                    .foregroundColor(Color(white: 0.5))
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: {
                envManager.uninstallLibrary(name: lib.name) { _, _ in }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                    Text("REMOVE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.04))
                .foregroundColor(Color(white: 0.6))
                .cornerRadius(3)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(envManager.isWorking)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(5)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
    
    // MARK: - Tab 1: Registry Search
    
    private var registrySearchView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SEARCH ARDUINO LIBRARY REGISTRY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
                .tracking(0.8)
            
            HStack(spacing: 8) {
                TextField("Search across 5,000+ libraries (e.g. WiFi, MQTT, LoRa, Modbus)...", text: $searchQuery)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.black)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15), lineWidth: 1))
                
                Button(action: {
                    envManager.searchLibraries(query: searchQuery)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                        Text("SEARCH")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || envManager.isWorking)
            }
            
            if envManager.searchResults.isEmpty {
                Text("Type a keyword above to query the online Arduino package repository via arduino-cli.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.4))
                    .padding(.top, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(envManager.searchResults) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                Text(item.descriptionText)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(Color(white: 0.5))
                            }
                            
                            Spacer()
                            
                            let isInst = envManager.installedLibraries.contains(where: { $0.name.lowercased() == item.name.lowercased() })
                            if isInst {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark")
                                    Text("INSTALLED")
                                }
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(white: 0.6))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                            } else {
                                Button(action: {
                                    envManager.installLibrary(name: item.name) { _, _ in }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.down.circle")
                                        Text("INSTALL")
                                    }
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.12))
                                    .foregroundColor(.white)
                                    .cornerRadius(3)
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.2), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .disabled(envManager.isWorking)
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.06), lineWidth: 1))
                    }
                }
            }
        }
    }
    
    // MARK: - Tab 2: Popular Hardware Libs (Instant 1-Click)
    
    private var popularLibrariesView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("POPULAR EMBEDDED LIBRARIES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.5))
                    .tracking(0.8)
                Spacer()
                Text("1-CLICK INSTALL")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
            }
            
            VStack(spacing: 8) {
                ForEach(envManager.popularCatalog) { lib in
                    let isInst = envManager.installedLibraries.contains(where: { $0.name.lowercased() == lib.name.lowercased() })
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(0.06))
                                .frame(width: 30, height: 30)
                            Image(systemName: "sparkle")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(lib.name)
                                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                
                                Text("#include <\(lib.headerInclude)>")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(Color(white: 0.5))
                                
                                Spacer()
                                
                                Text(lib.category.uppercased())
                                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(white: 0.4))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.04))
                                    .cornerRadius(2)
                            }
                            
                            Text(lib.summary)
                                .font(.system(size: 10))
                                .foregroundColor(Color(white: 0.6))
                        }
                        
                        if isInst {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                Text("INSTALLED")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(Color(white: 0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                        } else {
                            Button(action: {
                                envManager.installLibrary(name: lib.name) { _, _ in }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("INSTALL")
                                }
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white)
                                .foregroundColor(.black)
                                .cornerRadius(3)
                            }
                            .buttonStyle(.plain)
                            .disabled(envManager.isWorking)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.06), lineWidth: 1))
                }
            }
        }
    }
    
    // MARK: - Tab 3: Hardware Toolchains View
    
    private var toolchainsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ESP-IDF & FreeRTOS Dedicated Engine Card
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "cpu.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("ESP-IDF & FreeRTOS Engine")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text(envManager.isEspIdfConfigured ? "CONFIGURED" : "SYNTHETIC STUBS ACTIVE")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(envManager.isEspIdfConfigured ? 0.15 : 0.07))
                                .foregroundColor(envManager.isEspIdfConfigured ? .white : Color(white: 0.6))
                                .cornerRadius(3)
                        }
                        
                        Text("Manages CMake scaffolding, FreeRTOS kernel include paths, and export.sh sourcing for ESP32/ESP32-S3.")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.6))
                    }
                    
                    Spacer()
                }
                
                Divider().opacity(0.3)
                
                // Path Input Row
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("IDF_PATH:")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(white: 0.5))
                        
                        TextField("e.g. /Users/username/esp/esp-idf", text: $customIdfInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        
                        Button(action: {
                            envManager.saveCustomIdfPath(customIdfInput)
                        }) {
                            Text("APPLY")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white)
                                .foregroundColor(.black)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            envManager.detectEspIdf()
                            customIdfInput = envManager.idfPath
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("AUTO-DETECT")
                            }
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Status Details
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Text("VERSION:")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(white: 0.4))
                            Text(envManager.idfVersion)
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundColor(Color(white: 0.7))
                        }
                        
                        HStack(spacing: 4) {
                            Text("EXPORT SCRIPT:")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(white: 0.4))
                            Text(envManager.detectedExportScript.isEmpty ? "Not found" : (envManager.detectedExportScript as NSString).lastPathComponent)
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundColor(Color(white: 0.7))
                        }
                        
                        HStack(spacing: 4) {
                            Text("INCLUDES:")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(white: 0.4))
                            Text("\(envManager.espIdfIncludePaths.count) components linked")
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundColor(Color(white: 0.7))
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
            
            Text("HARDWARE COMPILERS & TOOLCHAINS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
                .tracking(0.8)
            
            VStack(spacing: 8) {
                ForEach(envManager.toolchains) { tool in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 32, height: 32)
                            Image(systemName: tool.isInstalled ? "terminal.fill" : "exclamationmark.triangle")
                                .font(.system(size: 12))
                                .foregroundColor(tool.isInstalled ? .white : Color(white: 0.4))
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(tool.name)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                
                                Text(tool.role)
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundColor(Color(white: 0.5))
                            }
                            
                            Text(tool.path)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(Color(white: 0.6))
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(tool.isInstalled ? Color.white : Color(white: 0.3))
                                .frame(width: 5, height: 5)
                            Text(tool.isInstalled ? "DETECTED" : "MISSING")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(tool.isInstalled ? .white : Color(white: 0.4))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(tool.isInstalled ? 0.1 : 0.03))
                        .cornerRadius(3)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(tool.isInstalled ? 0.2 : 0.05), lineWidth: 1))
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.06), lineWidth: 1))
                }
            }
        }
    }
    
    // MARK: - Expandable Live CLI Console Drawer
    
    private var consoleOutputDrawer: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "terminal")
                        .font(.system(size: 9))
                    Text("PACKAGE MANAGER CONSOLE")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                }
                .foregroundColor(Color(white: 0.6))
                
                Spacer()
                
                Button(action: { envManager.consoleOutput = "" }) {
                    Text("CLEAR")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))
                }
                .buttonStyle(.plain)
                
                Button(action: { isConsoleExpanded.toggle() }) {
                    Image(systemName: isConsoleExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9))
                        .foregroundColor(Color(white: 0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Color(white: 0.04))
            
            if isConsoleExpanded {
                ScrollView {
                    Text(envManager.consoleOutput)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(Color(white: 0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .textSelection(.enabled)
                }
                .frame(height: 120)
                .background(Color.black)
            }
        }
    }
}
