//
//  ExtensionSettingsView.swift
//  MicroCode
//
//  Extension management settings view
//  Copyright © 2025 Dotmini Company Limited. All rights reserved.
//
//  Tirawat Nantamas | Dotmini Company Limited
//

import SwiftUI
import UniformTypeIdentifiers

struct ExtensionSettingsView: View {
    @StateObject private var extensionManager = ExtensionManager.shared
    @StateObject private var extensionHost = ExtensionHostService.shared
    @StateObject private var openVSX = OpenVSXService.shared
    @EnvironmentObject var appState: AppState
    
    @State private var selectedTab: Int = 0 // 0: Installed, 1: Open VSX Marketplace
    @State private var selectedType: ExtensionType? = nil
    @State private var searchText: String = ""
    @State private var showInstallSheet: Bool = false
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""
    @State private var isDropTargeted: Bool = false
    @State private var installingId: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 36, height: 36)
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Extension Hub")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text(extensionHost.statusMessage)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Text("Install, manage, and mount community and official extensions.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 8) {
                    Button(action: { showInstallSheet = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.circle")
                            Text("Install File")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Install .vsix, .zip, or extension folder")

                    Button(action: { createStarterExtension() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                            Text("New Starter")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Create a community extension scaffold")

                    Button(action: { NSWorkspace.shared.open(extensionManager.userExtensionsDirectory) }) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Open Extensions Folder in Finder")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.02))
            
            Divider().opacity(0.5)
            
            // Sub-nav & Search Bar
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    // Segmented tabs: Installed vs Open VSX Marketplace
                    HStack(spacing: 2) {
                        tabButton(title: "Installed", count: extensionManager.installedExtensions.count, tag: 0)
                        tabButton(title: "Open VSX Marketplace", count: openVSX.popularExtensions.count, tag: 1)
                    }
                    .padding(3)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    
                    Spacer()
                    
                    // Type Filter
                    Picker("Type", selection: $selectedType) {
                        Text("All Types").tag(nil as ExtensionType?)
                        ForEach(ExtensionType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type as ExtensionType?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
                
                // Search Field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    TextField("Search 50,000+ extensions from Open VSX or installed...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onChange(of: searchText) { newText in
                            if selectedTab == 1 {
                                searchTask?.cancel()
                                searchTask = Task {
                                    try? await Task.sleep(nanoseconds: 350_000_000)
                                    if !Task.isCancelled {
                                        _ = await openVSX.search(query: newText)
                                    }
                                }
                            }
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            if selectedTab == 1 {
                                Task { _ = await openVSX.search(query: "") }
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            Divider().opacity(0.5)
            
            // Success / Error Banner
            if !successMessage.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.primary)
                    Text(successMessage)
                        .font(.system(size: 11))
                    Spacer()
                    Button("Dismiss") { successMessage = "" }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
            }
            
            if !errorMessage.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.secondary)
                    Text(errorMessage)
                        .font(.system(size: 11))
                    Spacer()
                    Button("Dismiss") { errorMessage = "" }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
            }
            
            // Main List Area
            ScrollView {
                VStack(spacing: 10) {
                    if selectedTab == 0 {
                        installedListContent
                    } else {
                        catalogListContent
                    }
                }
                .padding(16)
            }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
                handleDroppedFiles(providers: providers)
            }
            .overlay(
                Group {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                            .background(Color.primary.opacity(0.05))
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "arrow.down.doc.fill")
                                        .font(.system(size: 32))
                                    Text("Drop .vsix, .zip, or Extension folder to install")
                                        .font(.system(size: 13, weight: .bold))
                                }
                            )
                            .padding(16)
                    }
                }
            )
        }
        .frame(minWidth: 560, minHeight: 450)
        .fileImporter(isPresented: $showInstallSheet, allowedContentTypes: [.folder, .zip, UTType(filenameExtension: "vsix") ?? .data]) { result in
            switch result {
            case .success(let url):
                Task {
                    do {
                        try await extensionManager.installExtension(from: url)
                        successMessage = "Extension successfully installed from \(url.lastPathComponent)"
                    } catch {
                        errorMessage = "Failed to install: \(error.localizedDescription)"
                    }
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Tab Button Helper
    private func tabButton(title: String, count: Int, tag: Int) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tag } }) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11.5, weight: selectedTab == tag ? .bold : .medium))
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(selectedTab == tag ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selectedTab == tag ? Color.primary.opacity(0.08) : Color.clear)
            .foregroundColor(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Installed List
    @ViewBuilder
    private var installedListContent: some View {
        let items = filteredInstalledExtensions
        if extensionManager.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading installed extensions...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else if items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No Installed Extensions Found")
                    .font(.system(size: 14, weight: .semibold))
                Text("Drag and drop .vsix or .zip files here, or install from the Available Catalog.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 8) {
                    Button("Browse Catalog") { selectedTab = 1 }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Install Local File") { showInstallSheet = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Create Starter") { createStarterExtension() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(Color.primary.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        } else {
            VStack(spacing: 10) {
                ForEach(items) { ext in
                    RoundedExtensionCard(
                        extension: ext,
                        onDelete: {
                            try? extensionManager.uninstallExtension(ext.id)
                            successMessage = "Uninstalled \(ext.manifest.name)"
                        },
                        onMountCanvas: {
                            appState.openExtensionStudio()
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Catalog / Open VSX List
    @ViewBuilder
    private var catalogListContent: some View {
        VStack(spacing: 12) {
            // Header Action Banner
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open VSX Registry")
                        .font(.system(size: 13, weight: .bold))
                    Text("Tens of thousands of community & official VS Code extensions (.vsix)")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    appState.openExtensionStudio()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.app")
                        Text("Open Full Studio")
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary)
                    .foregroundColor(Color.compat(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            
            // Open VSX results
            let openVSXItems = !openVSX.searchResults.isEmpty ? openVSX.searchResults : openVSX.popularExtensions
            if openVSXItems.isEmpty && openVSX.isSearching {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Searching Open VSX...")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else if !openVSXItems.isEmpty {
                ForEach(openVSXItems) { ext in
                    let isInstalled = extensionManager.isExtensionInstalled(ext.id)
                    let isInstalling = installingId == ext.id || openVSX.downloadingIds.contains(ext.id)
                    
                    OpenVSXSettingsCard(
                        ext: ext,
                        isInstalled: isInstalled,
                        isInstalling: isInstalling,
                        onInstall: {
                            installOpenVSXExtension(ext)
                        }
                    )
                }
            } else {
                let items = filteredCatalogExtensions
                ForEach(items) { manifest in
                    let isInstalled = extensionManager.installedExtensions.contains(where: { $0.id == manifest.id })
                    let isInstalling = installingId == manifest.id
                    
                    CatalogExtensionCard(
                        manifest: manifest,
                        isInstalled: isInstalled,
                        isInstalling: isInstalling,
                        onInstall: {
                            installCatalogExtension(manifest)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Helpers & Data
    private var catalogExtensions: [ExtensionManifest] {
        ExtensionManager.defaultOfficialExtensions
    }
    
    private var filteredInstalledExtensions: [InstalledExtension] {
        extensionManager.installedExtensions.filter { ext in
            let matchesType = selectedType == nil || ext.manifest.type == selectedType
            let matchesSearch = searchText.isEmpty ||
                ext.manifest.name.localizedCaseInsensitiveContains(searchText) ||
                ext.manifest.description.localizedCaseInsensitiveContains(searchText)
            return matchesType && matchesSearch
        }
    }
    
    private var filteredCatalogExtensions: [ExtensionManifest] {
        catalogExtensions.filter { manifest in
            let matchesType = selectedType == nil || manifest.type == selectedType
            let matchesSearch = searchText.isEmpty ||
                manifest.name.localizedCaseInsensitiveContains(searchText) ||
                manifest.description.localizedCaseInsensitiveContains(searchText)
            return matchesType && matchesSearch
        }
    }
    
    private func installOpenVSXExtension(_ ext: OpenVSXExtension) {
        installingId = ext.id
        Task {
            do {
                _ = try await openVSX.downloadAndInstall(extension: ext)
                await MainActor.run {
                    installingId = nil
                    successMessage = "Installed '\(ext.title)' from Open VSX!"
                }
            } catch {
                await MainActor.run {
                    installingId = nil
                    errorMessage = "Installation failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func installCatalogExtension(_ manifest: ExtensionManifest) {
        installingId = manifest.id
        Task {
            do {
                try await extensionManager.installFromCatalog(manifest)
                await MainActor.run {
                    installingId = nil
                    successMessage = "Installed and activated '\(manifest.name)'!"
                }
            } catch {
                await MainActor.run {
                    installingId = nil
                    errorMessage = "Installation failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func createStarterExtension() {
        Task {
            do {
                let folder = try await extensionManager.createJavaScriptStarterExtension()
                NSWorkspace.shared.open(folder)
                successMessage = "Created starter extension at \(folder.lastPathComponent)"
            } catch {
                errorMessage = "Could not create starter extension: \(error.localizedDescription)"
            }
        }
    }
    
    private func handleDroppedFiles(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    do {
                        try await extensionManager.installExtension(from: url)
                        successMessage = "Installed extension from dropped file: \(url.lastPathComponent)"
                    } catch {
                        errorMessage = "Drop install failed: \(error.localizedDescription)"
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Rounded Extension Card (Installed)
struct RoundedExtensionCard: View {
    let `extension`: InstalledExtension
    let onDelete: () -> Void
    let onMountCanvas: () -> Void
    
    @StateObject private var manager = ExtensionManager.shared
    @State private var showDeleteConfirm: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Rounded Icon Box
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 44, height: 44)
                Image(systemName: `extension`.displayIcon)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(`extension`.manifest.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if `extension`.isOfficial {
                        Text("OFFICIAL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    
                    Text("v\(`extension`.manifest.version)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                Text(`extension`.manifest.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: `extension`.manifest.type.icon)
                            .font(.system(size: 9))
                        Text(`extension`.manifest.type.displayName)
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.4))
                        .font(.system(size: 8))
                    
                    Text("by \(`extension`.manifest.author)")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary.opacity(0.8))
                    
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.4))
                        .font(.system(size: 8))
                    
                    Text("runtime: \(`extension`.manifest.runtime.rawValue)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                // Mount to Studio Canvas button
                Button(action: onMountCanvas) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                        Text("Open Canvas")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Mount and test this extension UI on the Extension Studio Canvas")

                if !`extension`.isOfficial {
                    Button(action: { showDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Uninstall Extension")
                }
                
                Toggle("", isOn: Binding(
                    get: { `extension`.isEnabled },
                    set: { manager.setEnabled(`extension`.id, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .scaleEffect(0.8)
                .labelsHidden()
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .alert("Uninstall Extension", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to uninstall '\(`extension`.manifest.name)'?")
        }
    }
}

// MARK: - Catalog Extension Card (Installable)
struct CatalogExtensionCard: View {
    let manifest: ExtensionManifest
    let isInstalled: Bool
    let isInstalling: Bool
    let onInstall: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Rounded Icon Box
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 44, height: 44)
                Image(systemName: manifest.icon ?? manifest.type.icon)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(manifest.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("v\(manifest.version)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                Text(manifest.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: manifest.type.icon)
                            .font(.system(size: 9))
                        Text(manifest.type.displayName)
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.4))
                        .font(.system(size: 8))
                    
                    Text("by \(manifest.author)")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary.opacity(0.8))
                    
                    if let keywords = manifest.keywords, !keywords.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.4))
                            .font(.system(size: 8))
                        Text(keywords.prefix(3).joined(separator: ", "))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
            }
            
            Spacer()
            
            // Install Button
            if isInstalled {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                    Text("Installed")
                        .font(.system(size: 10.5, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.08))
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if isInstalling {
                HStack(spacing: 5) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                    Text("Installing...")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06))
                .foregroundColor(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Button(action: onInstall) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11))
                        Text("Install")
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary)
                    .foregroundColor(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Open VSX Extension Card (Settings)
struct OpenVSXSettingsCard: View {
    let ext: OpenVSXExtension
    let isInstalled: Bool
    let isInstalling: Bool
    let onInstall: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 44, height: 44)
                if let iconURL = ext.iconURL {
                    AsyncImage(url: iconURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                               .aspectRatio(contentMode: .fit)
                               .frame(width: 36, height: 36)
                               .clipShape(RoundedRectangle(cornerRadius: 6))
                        default:
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                }
            }
            .frame(width: 44, height: 44)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(ext.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("v\(ext.version)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                    
                    if ext.verified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                
                if let desc = ext.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8))
                        Text(ext.formattedDownloads)
                            .font(.system(size: 9.5, design: .monospaced))
                    }
                    .foregroundColor(.secondary)
                    
                    if !ext.formattedRating.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.4))
                            .font(.system(size: 8))
                        Text(ext.formattedRating)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.4))
                        .font(.system(size: 8))
                    
                    Text("by \(ext.author)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            
            Spacer()
            
            // Install Button
            if isInstalled {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                    Text("Installed")
                        .font(.system(size: 10.5, weight: .bold))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else if isInstalling {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("Installing...")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Button(action: onInstall) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 10))
                        Text("Install")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.primary)
                    .foregroundColor(Color.compat(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

