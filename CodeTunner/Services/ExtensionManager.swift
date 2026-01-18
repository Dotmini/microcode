//
//  ExtensionManager.swift
//  CodeTunner
//
//  Extension system - supports Rust/Swift/JS extensions
//

import Foundation
import SwiftUI

// MARK: - Extension Types
enum ExtensionType: String, Codable, CaseIterable {
    case theme = "theme"
    case language = "language"
    case aiProvider = "ai-provider"
    case fileFormat = "file-format"
    case command = "command"
    case tool = "tool"
    
    var icon: String {
        switch self {
        case .theme: return "paintpalette.fill"
        case .language: return "chevron.left.forwardslash.chevron.right"
        case .aiProvider: return "brain"
        case .fileFormat: return "doc.badge.gearshape"
        case .command: return "terminal.fill"
        case .tool: return "hammer.fill"
        }
    }
    
    var displayName: String {
        switch self {
        case .theme: return "Theme"
        case .language: return "Language"
        case .aiProvider: return "AI Provider"
        case .fileFormat: return "File Format"
        case .command: return "Command"
        case .tool: return "Tool"
        }
    }
}

// MARK: - Extension Manifest
struct ExtensionManifest: Codable, Identifiable {
    let id: String
    let name: String
    let version: String
    let author: String
    let description: String
    let type: ExtensionType
    let runtime: ExtensionRuntime
    let main: String  // Entry file
    let icon: String?
    let repository: String?
    let license: String?
    let keywords: [String]?
    
    enum ExtensionRuntime: String, Codable {
        case rust = "rust"
        case swift = "swift"
        case javascript = "javascript"
    }
}

// MARK: - Installed Extension
struct InstalledExtension: Identifiable {
    let id: String
    let manifest: ExtensionManifest
    let path: URL
    var isEnabled: Bool
    var isOfficial: Bool
    
    var displayIcon: String {
        manifest.icon ?? manifest.type.icon
    }
}

// MARK: - Extension Manager
@MainActor
class ExtensionManager: ObservableObject {
    static let shared = ExtensionManager()
    
    @Published var installedExtensions: [InstalledExtension] = []
    @Published var enabledExtensions: Set<String> = []
    @Published var isLoading: Bool = false
    
    private let extensionsDirectory: URL
    private let officialExtensionsDirectory: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        extensionsDirectory = appSupport.appendingPathComponent("Project IDX/Extensions", isDirectory: true)
        officialExtensionsDirectory = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Extensions", isDirectory: true)
        
        // Create extensions directory if needed
        try? FileManager.default.createDirectory(at: extensionsDirectory, withIntermediateDirectories: true)
        
        // Load enabled extensions from UserDefaults
        if let enabled = UserDefaults.standard.array(forKey: "enabledExtensions") as? [String] {
            enabledExtensions = Set(enabled)
        }
        
        Task {
            await loadExtensions()
        }
    }
    
    // MARK: - Load Extensions
    func loadExtensions() async {
        isLoading = true
        var extensions: [InstalledExtension] = []
        
        // Load official extensions first
        extensions.append(contentsOf: await loadExtensionsFromDirectory(officialExtensionsDirectory, isOfficial: true))
        
        // Load user extensions
        extensions.append(contentsOf: await loadExtensionsFromDirectory(extensionsDirectory, isOfficial: false))
        
        await MainActor.run {
            installedExtensions = extensions
            isLoading = false
        }
    }
    
    private func loadExtensionsFromDirectory(_ directory: URL, isOfficial: Bool) async -> [InstalledExtension] {
        var extensions: [InstalledExtension] = []
        
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return extensions
        }
        
        for item in contents {
            let manifestPath = item.appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: manifestPath.path) else { continue }
            
            do {
                let data = try Data(contentsOf: manifestPath)
                let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: data)
                
                let ext = InstalledExtension(
                    id: manifest.id,
                    manifest: manifest,
                    path: item,
                    isEnabled: enabledExtensions.contains(manifest.id),
                    isOfficial: isOfficial
                )
                extensions.append(ext)
            } catch {
                print("Failed to load extension at \(item): \(error)")
            }
        }
        
        return extensions
    }
    
    // MARK: - Enable/Disable
    func toggleExtension(_ id: String) {
        if enabledExtensions.contains(id) {
            enabledExtensions.remove(id)
        } else {
            // Check permissions before enabling
            if checkPermissions(for: id) {
                enabledExtensions.insert(id)
            } else {
                requestPermissions(for: id)
            }
        }
        
        // Update installed extensions
        for i in installedExtensions.indices {
            if installedExtensions[i].id == id {
                installedExtensions[i].isEnabled = enabledExtensions.contains(id)
            }
        }
        
        // Save to UserDefaults
        UserDefaults.standard.set(Array(enabledExtensions), forKey: "enabledExtensions")
        
        // Apply changes
        applyExtensionChanges()
    }
    
    func setEnabled(_ id: String, enabled: Bool) {
        if enabled {
            enabledExtensions.insert(id)
        } else {
            enabledExtensions.remove(id)
        }
        
        for i in installedExtensions.indices {
            if installedExtensions[i].id == id {
                installedExtensions[i].isEnabled = enabled
            }
        }
        
        UserDefaults.standard.set(Array(enabledExtensions), forKey: "enabledExtensions")
        applyExtensionChanges()
    }
    
    // MARK: - Install Extension (Universal)
    func installExtension(from url: URL) async throws {
        if url.pathExtension.lowercased() == "vsix" {
            try await installVSIX(from: url)
        } else {
            try await installStandardExtension(from: url)
        }
    }

    // MARK: - Standard Install
    private func installStandardExtension(from url: URL) async throws {
        let destName = url.deletingPathExtension().lastPathComponent
        let destPath = extensionsDirectory.appendingPathComponent(destName)
        
        // If it's a zip, extract it
        if url.pathExtension.lowercased() == "zip" {
            try unzip(url, to: destPath)
        } else {
            // Copy directory
            try FileManager.default.copyItem(at: url, to: destPath)
        }
        
        await loadExtensions()
    }
    
    // MARK: - VSIX Install Logic
    private func installVSIX(from url: URL) async throws {
        // 1. Create Temp Directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // 2. Unzip VSIX (it's a zip)
        try unzip(url, to: tempDir)
        
        // 3. Find package.json (usually in 'extension' subdir)
        let packageJsonPath = tempDir.appendingPathComponent("extension/package.json")
        guard FileManager.default.fileExists(atPath: packageJsonPath.path) else {
            throw NSError(domain: "ExtensionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid VSIX: package.json not found"])
        }
        
        // 4. Parse package.json
        let data = try Data(contentsOf: packageJsonPath)
        let vscodePkg = try JSONDecoder().decode(VSCodePackageJSON.self, from: data)
        
        // 5. Convert to ExtensionManifest
        let manifest = convertToManifest(vscodePkg)
        
        // 6. Install to Destination
        // VSIX contents are typically in 'extension/' folder inside the archive
        let sourceContent = tempDir.appendingPathComponent("extension")
        let destReqName = "\(vscodePkg.publisher).\(vscodePkg.name)"
        let destPath = extensionsDirectory.appendingPathComponent(destReqName)
        
        if FileManager.default.fileExists(atPath: destPath.path) {
            try FileManager.default.removeItem(at: destPath)
        }
        
        try FileManager.default.moveItem(at: sourceContent, to: destPath)
        
        // 7. Write new manifest.json
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: destPath.appendingPathComponent("manifest.json"))
        
        await loadExtensions()
    }
    
    private func unzip(_ url: URL, to dest: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", url.path, "-d", dest.path]
        try process.run()
        process.waitUntilExit()
    }
    
    private func convertToManifest(_ pkg: VSCodePackageJSON) -> ExtensionManifest {
        // Determine type based on contributions
        var type: ExtensionType = .tool
        if pkg.contributes?.themes != nil {
            type = .theme
        } else if pkg.contributes?.languages != nil {
            type = .language
        }
        
        return ExtensionManifest(
            id: "\(pkg.publisher).\(pkg.name)",
            name: pkg.displayName ?? pkg.name,
            version: pkg.version,
            author: pkg.publisher,
            description: pkg.description ?? "No description",
            type: type,
            runtime: .javascript, // VSIX implies JS/TS runtime
            main: pkg.main ?? "index.js",
            icon: nil, // TODO: Extract icon if exists
            repository: nil,
            license: nil,
            keywords: nil
        )
    }
    
    // MARK: - Uninstall Extension
    func uninstallExtension(_ id: String) throws {
        guard let ext = installedExtensions.first(where: { $0.id == id }) else { return }
        guard !ext.isOfficial else {
            throw NSError(domain: "ExtensionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot uninstall official extensions"])
        }
        
        try FileManager.default.removeItem(at: ext.path)
        enabledExtensions.remove(id)
        installedExtensions.removeAll { $0.id == id }
        UserDefaults.standard.set(Array(enabledExtensions), forKey: "enabledExtensions")
    }
    
    // MARK: - Apply Changes
    private func applyExtensionChanges() {
        // Apply theme extensions
        for ext in installedExtensions where ext.isEnabled && ext.manifest.type == .theme {
            applyThemeExtension(ext)
        }
    }
    
    private func applyThemeExtension(_ ext: InstalledExtension) {
        let themePath = ext.path.appendingPathComponent(ext.manifest.main)
        guard let data = try? Data(contentsOf: themePath),
              let theme = try? JSONDecoder().decode(ThemeColors.self, from: data) else { return }
        
        // Apply colors (would integrate with app's theme system)
        print("Applied theme: \(ext.manifest.name)")
    }
    
    // MARK: - Permissions Helper
    private func checkPermissions(for id: String) -> Bool {
        // Mock permission check
        return UserDefaults.standard.bool(forKey: "ext_perm_\(id)")
    }
    
    private func requestPermissions(for id: String) {
        guard let ext = installedExtensions.first(where: { $0.id == id }) else { return }
        
        // In a real app, this would show a dialog. For now, we auto-grant but log.
        print("🔐 Requesting permissions for extension: \(ext.manifest.name)")
        print("Permissions required: fileSystem, network")
        
        // Auto-grant for demo purposes
        UserDefaults.standard.set(true, forKey: "ext_perm_\(id)")
        enabledExtensions.insert(id)
        
        // Update UI
        for i in installedExtensions.indices {
            if installedExtensions[i].id == id {
                installedExtensions[i].isEnabled = true
            }
        }
    }
    
    // MARK: - Get Extensions by Type
    func extensions(ofType type: ExtensionType) -> [InstalledExtension] {
        installedExtensions.filter { $0.manifest.type == type && $0.isEnabled }
    }
}

// MARK: - Theme Colors Model
struct ThemeColors: Codable {
    let name: String
    let isDark: Bool
    let colors: [String: String]
    let syntaxColors: [String: String]?
}

// MARK: - VS Code Compatibility Models
struct VSCodePackageJSON: Codable {
    let name: String
    let displayName: String?
    let publisher: String
    let version: String
    let description: String?
    let main: String?
    let engines: [String: String]?
    let contributes: VSCodeContributions?
}

struct VSCodeContributions: Codable {
    let themes: [VSCodeTheme]?
    let languages: [VSCodeLanguage]?
}

struct VSCodeTheme: Codable {
    let label: String?
    let uiTheme: String?
    let path: String?
}

struct VSCodeLanguage: Codable {
    let id: String
    let extensions: [String]?
}

