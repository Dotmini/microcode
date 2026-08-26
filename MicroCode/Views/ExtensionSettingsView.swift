//
//  ExtensionSettingsView.swift
//  MicroCode
//
//  Extension management settings view
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//
//  Tirawat Nantamas | Dotmini Software | SPU AI CLUB
//

import SwiftUI
import UniformTypeIdentifiers

struct ExtensionSettingsView: View {
    @StateObject private var extensionManager = ExtensionManager.shared
    @State private var selectedType: ExtensionType? = nil
    @State private var searchText: String = ""
    @State private var showInstallSheet: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "puzzlepiece.extension")
                    .foregroundColor(.secondary)
                Text("Extensions")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showInstallSheet = true }) {
                    Label("Install", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            
            Divider()
            
            // Filter Bar
            HStack(spacing: 12) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search extensions...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.compat(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                
                // Type Filter
                Picker("Type", selection: $selectedType) {
                    Text("All").tag(nil as ExtensionType?)
                    ForEach(ExtensionType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon)
                            .tag(type as ExtensionType?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Extension List
            if extensionManager.isLoading {
                VStack {
                    ProgressView()
                    Text("Loading extensions...")
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else if filteredExtensions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "puzzlepiece")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No extensions found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Install extensions to add new features")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    // Official Extensions
                    let official = filteredExtensions.filter { $0.isOfficial }
                    if !official.isEmpty {
                        Section.compat("Official") {
                            ForEach(official) { ext in
                                ExtensionRow(extension: ext)
                            }
                        }
                    }
                    
                    // User Extensions
                    let user = filteredExtensions.filter { !$0.isOfficial }
                    if !user.isEmpty {
                        Section.compat("Installed") {
                            ForEach(user) { ext in
                                ExtensionRow(extension: ext)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            
            // Error
            if !errorMessage.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") { errorMessage = "" }
                        .buttonStyle(.borderless)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .fileImporter(isPresented: $showInstallSheet, allowedContentTypes: [.folder, .zip, UTType(filenameExtension: "vsix") ?? .data]) { result in
            switch result {
            case .success(let url):
                Task {
                    do {
                        try await extensionManager.installExtension(from: url)
                    } catch {
                        errorMessage = "Failed to install: \(error.localizedDescription)"
                    }
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private var filteredExtensions: [InstalledExtension] {
        extensionManager.installedExtensions.filter { ext in
            let matchesType = selectedType == nil || ext.manifest.type == selectedType
            let matchesSearch = searchText.isEmpty || 
                ext.manifest.name.localizedCaseInsensitiveContains(searchText) ||
                ext.manifest.description.localizedCaseInsensitiveContains(searchText)
            return matchesType && matchesSearch
        }
    }
}

// MARK: - Extension Row
struct ExtensionRow: View {
    let `extension`: InstalledExtension
    @StateObject private var manager = ExtensionManager.shared
    @State private var showDeleteConfirm: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 38, height: 38)
                Image(systemName: `extension`.displayIcon)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(`extension`.manifest.name)
                        .font(.system(size: 13, weight: .semibold))
                    
                    if `extension`.isOfficial {
                        Text("OFFICIAL")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    
                    Text("v\(`extension`.manifest.version)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                
                Text(`extension`.manifest.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Label(`extension`.manifest.type.displayName, systemImage: `extension`.manifest.type.icon)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text("by \(`extension`.manifest.author)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                if !`extension`.isOfficial {
                    Button(action: { showDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
                
                Toggle("", isOn: Binding(
                    get: { `extension`.isEnabled },
                    set: { manager.setEnabled(`extension`.id, enabled: $0) }
                ))
                .toggleStyle(.switch)
            }
        }
        .padding(.vertical, 4)
        .background {
            if #available(macOS 12.0, *) {
                Color.clear.alert("Delete Extension", isPresented: $showDeleteConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        try? manager.uninstallExtension(`extension`.id)
                    }
                } message: {
                    Text("Are you sure you want to delete '\(`extension`.manifest.name)'?")
                }
            } else {
                Color.clear.alert(isPresented: $showDeleteConfirm) {
                    Alert(
                        title: Text("Delete Extension"),
                        message: Text("Are you sure you want to delete '\(`extension`.manifest.name)'?"),
                        primaryButton: .destructive(Text("Delete")) {
                           try? manager.uninstallExtension(`extension`.id)
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
        }
    }
}
