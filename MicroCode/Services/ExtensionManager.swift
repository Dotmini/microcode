//
//  ExtensionManager.swift
//  MicroCode
//
//  Extension system - supports Rust/Swift/JS extensions
//

import Foundation
import SwiftUI

// MARK: - Extension Types
enum ExtensionType: String, Codable, CaseIterable {
    case theme = "theme"
    case iconTheme = "icon-theme"
    case language = "language"
    case aiProvider = "ai-provider"
    case fileFormat = "file-format"
    case command = "command"
    case tool = "tool"
    
    var icon: String {
        switch self {
        case .theme: return "paintpalette.fill"
        case .iconTheme: return "app.dashed"
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
        case .iconTheme: return "Icon Theme"
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
        case wasm = "wasm"
        case process = "process"
    }
}

// MARK: - Installed Extension
struct InstalledExtension: Identifiable {
    let id: String
    let manifest: ExtensionManifest
    let path: URL
    var isEnabled: Bool
    var isOfficial: Bool
    
    var iconURL: URL? {
        if let pkg = packageJSON, let iconPath = pkg.icon {
            let u = path.appendingPathComponent(iconPath)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        let rootIcon = path.appendingPathComponent("icon.png")
        if FileManager.default.fileExists(atPath: rootIcon.path) { return rootIcon }
        let rootLogo = path.appendingPathComponent("logo.png")
        if FileManager.default.fileExists(atPath: rootLogo.path) { return rootLogo }
        return nil
    }
    
    var displayIcon: String {
        manifest.icon ?? effectiveType.icon
    }

    var effectiveType: ExtensionType {
        if manifest.id.contains("material-icon-theme") || packageJSON?.contributes?.iconThemes != nil {
            return .iconTheme
        }
        if manifest.id.contains("night-owl") || manifest.id.contains("material-theme") || packageJSON?.contributes?.themes != nil {
            return .theme
        }
        return manifest.type
    }

    var packageJSON: VSCodePackageJSON? {
        let p = path.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: p) else { return nil }
        return try? JSONDecoder().decode(VSCodePackageJSON.self, from: data)
    }

    var readmeContent: String? {
        let candidates = ["README.md", "readme.md", "Readme.md"]
        for c in candidates {
            let u = path.appendingPathComponent(c)
            if let str = try? String(contentsOf: u, encoding: .utf8) { return str }
        }
        return nil
    }

    var commands: [VSCodeCommandContribution] {
        guard let contributes = packageJSON?.contributes, let cmds = contributes.commands else { return [] }
        return cmds.map { cmd in
            VSCodeCommandContribution(
                command: cmd.command,
                title: cmd.title,
                category: cmd.category,
                icon: cmd.icon
            )
        }
    }

    var configProperties: [VSCodeConfigProperty] {
        let p = path.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: p),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contrib = json["contributes"] as? [String: Any] else { return [] }
        
        var props: [VSCodeConfigProperty] = []
        func extractProps(from dict: [String: Any]) {
            guard let properties = dict["properties"] as? [String: [String: Any]] else { return }
            for (key, val) in properties {
                let typeStr = val["type"] as? String ?? "string"
                let desc = val["description"] as? String ?? val["markdownDescription"] as? String ?? ""
                var defStr = ""
                if let d = val["default"] {
                    if let str = d as? String { defStr = str }
                    else if let b = d as? Bool { defStr = b ? "true" : "false" }
                    else if let n = d as? NSNumber { defStr = "\(n)" }
                    else if let arr = d as? [Any] { defStr = "\(arr.count) items" }
                    else if let obj = d as? [String: Any] { defStr = "\(obj.count) keys" }
                }
                let enumVals = val["enum"] as? [String]
                props.append(VSCodeConfigProperty(key: key, type: typeStr, description: desc, defaultValue: defStr, enumValues: enumVals))
            }
        }
        
        if let config = contrib["configuration"] as? [String: Any] {
            extractProps(from: config)
        } else if let configList = contrib["configuration"] as? [[String: Any]] {
            for c in configList { extractProps(from: c) }
        }
        return props
    }
}

// MARK: - Extension Manager
@MainActor
class ExtensionManager: ObservableObject {
    static let shared = ExtensionManager()
    
    @Published var installedExtensions: [InstalledExtension] = []
    @Published var enabledExtensions: Set<String> = []
    @Published var isLoading: Bool = false
    
    // MARK: - Icon Theme Engine
    @Published var isIconThemeActive: Bool = UserDefaults.standard.object(forKey: "isIconThemeActive") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isIconThemeActive, forKey: "isIconThemeActive")
            NotificationCenter.default.post(name: NSNotification.Name("MicroCodeIconThemeChanged"), object: nil)
        }
    }
    
    private var materialIconsData: MaterialIconsManifest? = nil
    private var materialIconsDirectory: URL? = nil
    private var iconImageCache: [String: NSImage] = [:]
    private var hasAttemptedLoadingIcons = false
    
    public func setIconThemeActive(_ active: Bool) {
        isIconThemeActive = active
    }
    
    public func loadMaterialIconsIfNeeded() {
        guard !hasAttemptedLoadingIcons else { return }
        hasAttemptedLoadingIcons = true
        
        let candidateDirs = [
            extensionsDirectory.appendingPathComponent("PKief.material-icon-theme"),
            officialExtensionsDirectory.appendingPathComponent("PKief.material-icon-theme")
        ]
        
        guard let iconDir = candidateDirs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return
        }
        
        let jsonPath = iconDir.appendingPathComponent("dist/material-icons.json")
        guard let data = try? Data(contentsOf: jsonPath),
              let manifest = try? JSONDecoder().decode(MaterialIconsManifest.self, from: data) else {
            return
        }
        
        self.materialIconsData = manifest
        self.materialIconsDirectory = iconDir
    }
    
    public func iconImage(for filename: String, isDirectory: Bool = false, isExpanded: Bool = false) -> NSImage? {
        guard isIconThemeActive else { return nil }
        loadMaterialIconsIfNeeded()
        guard let manifest = materialIconsData, let iconDir = materialIconsDirectory else { return nil }
        
        let lowerName = filename.lowercased()
        var iconKey: String? = nil
        
        if isDirectory {
            if isExpanded, let expandedMap = manifest.folderNamesExpanded, let match = expandedMap[lowerName] {
                iconKey = match
            } else if let folderMap = manifest.folderNames, let match = folderMap[lowerName] {
                iconKey = match
            } else {
                iconKey = isExpanded ? (manifest.folderExpanded ?? "folder-open") : (manifest.folder ?? "folder")
            }
        } else {
            if let fileNamesMap = manifest.fileNames, let match = fileNamesMap[lowerName] {
                iconKey = match
            } else {
                let ext = (filename as NSString).pathExtension.lowercased()
                if !ext.isEmpty, let extMap = manifest.fileExtensions, let match = extMap[ext] {
                    iconKey = match
                } else if let defaultFile = manifest.file {
                    iconKey = defaultFile
                }
            }
        }
        
        guard let resolvedKey = iconKey else { return nil }
        let cacheKey = "\(resolvedKey)_\(isDirectory ? (isExpanded ? "open" : "closed") : "file")"
        if let cached = iconImageCache[cacheKey] {
            return cached
        }
        
        var relPath = manifest.iconDefinitions?[resolvedKey]?.iconPath
        if relPath == nil {
            relPath = "./../icons/\(resolvedKey).svg"
        }
        
        guard let pathString = relPath else { return nil }
        let cleanName: String
        if pathString.hasPrefix("./../icons/") {
            cleanName = String(pathString.dropFirst("./../icons/".count))
        } else if pathString.hasPrefix("./icons/") {
            cleanName = String(pathString.dropFirst("./icons/".count))
        } else {
            cleanName = (pathString as NSString).lastPathComponent
        }
        
        let svgURL = iconDir.appendingPathComponent("icons").appendingPathComponent(cleanName)
        guard FileManager.default.fileExists(atPath: svgURL.path),
              let img = NSImage(contentsOfFile: svgURL.path) else {
            return nil
        }
        
        img.size = NSSize(width: 16, height: 16)
        iconImageCache[cacheKey] = img
        return img
    }
    
    private let extensionsDirectory: URL
    private let officialExtensionsDirectory: URL

    var userExtensionsDirectory: URL { extensionsDirectory }
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        extensionsDirectory = appSupport.appendingPathComponent("MicroCode/Extensions", isDirectory: true)
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
    
    // MARK: - Default Official Catalog
    static let defaultOfficialExtensions: [ExtensionManifest] = [
        ExtensionManifest(
            id: "ms-python.python",
            name: "Python & Pyright LSP",
            version: "2025.1.0",
            author: "Microsoft",
            description: "Rich Python IntelliSense, Linting, Pyright type checking, and virtual environment auto-detection.",
            type: .language,
            runtime: .javascript,
            main: "extension.js",
            icon: "curlybraces",
            repository: "https://github.com/microsoft/vscode-python",
            license: "MIT",
            keywords: ["python", "pyright", "lsp"]
        ),
        ExtensionManifest(
            id: "rust-lang.rust-analyzer",
            name: "Rust Analyzer",
            version: "0.4.2",
            author: "Rust Community",
            description: "Modular compiler frontend for the Rust language, high-speed completion, and macro expansion.",
            type: .language,
            runtime: .rust,
            main: "rust-analyzer",
            icon: "gearshape.2.fill",
            repository: "https://github.com/rust-lang/rust-analyzer",
            license: "Apache-2.0",
            keywords: ["rust", "cargo", "lsp"]
        ),
        ExtensionManifest(
            id: "swiftlang.swift-vscode",
            name: "Swift & SourceKit-LSP",
            version: "1.11.0",
            author: "Swift Server Workgroup",
            description: "First-class Swift support for macOS and Linux, SwiftPM build tasks, and SourceKit-LSP integration.",
            type: .language,
            runtime: .swift,
            main: "extension.js",
            icon: "swift",
            repository: "https://github.com/swiftlang/vscode-swift",
            license: "Apache-2.0",
            keywords: ["swift", "apple", "swiftpm"]
        ),
        ExtensionManifest(
            id: "golang.go",
            name: "Go Language Tools",
            version: "0.41.0",
            author: "Go Team at Google",
            description: "Rich language support for Go, gopls language server, test runner, and delve debugger integration.",
            type: .language,
            runtime: .javascript,
            main: "extension.js",
            icon: "arrow.triangle.2.circlepath",
            repository: "https://github.com/golang/vscode-go",
            license: "MIT",
            keywords: ["go", "golang", "gopls"]
        ),
        ExtensionManifest(
            id: "bradlc.vscode-tailwindcss",
            name: "Tailwind CSS IntelliSense",
            version: "0.14.0",
            author: "Tailwind Labs",
            description: "Intelligent Tailwind CSS autocomplete, class sorting, syntax highlighting, and linting.",
            type: .tool,
            runtime: .javascript,
            main: "extension.js",
            icon: "paintbrush.fill",
            repository: "https://github.com/tailwindlabs/tailwindcss-intellisense",
            license: "MIT",
            keywords: ["tailwind", "css", "web"]
        ),
        ExtensionManifest(
            id: "esbenp.prettier-vscode",
            name: "Prettier Code Formatter",
            version: "10.4.0",
            author: "Prettier",
            description: "Opinionated code formatter supporting JavaScript, TypeScript, CSS, JSON, Markdown, and YAML.",
            type: .tool,
            runtime: .javascript,
            main: "extension.js",
            icon: "wand.and.stars",
            repository: "https://github.com/prettier/prettier-vscode",
            license: "MIT",
            keywords: ["formatter", "prettier", "js"]
        ),
        ExtensionManifest(
            id: "eamodio.gitlens",
            name: "GitLens Pro",
            version: "15.0.0",
            author: "GitKraken",
            description: "Supercharge Git within MicroCode. Line blame annotations, commit history graph, and interactive rebase.",
            type: .tool,
            runtime: .javascript,
            main: "extension.js",
            icon: "arrow.triangle.branch",
            repository: "https://github.com/gitkraken/vscode-gitlens",
            license: "MIT",
            keywords: ["git", "gitlens", "blame"]
        ),
        ExtensionManifest(
            id: "ms-toolsai.jupyter",
            name: "Jupyter Notebook Interactive",
            version: "2025.2.0",
            author: "Microsoft",
            description: "Interactive Python notebooks, execution cells, Matplotlib graphics, and remote kernel connections.",
            type: .fileFormat,
            runtime: .javascript,
            main: "extension.js",
            icon: "book.pages.fill",
            repository: "https://github.com/microsoft/vscode-jupyter",
            license: "MIT",
            keywords: ["jupyter", "ipynb", "python"]
        ),
        ExtensionManifest(
            id: "ms-azuretools.vscode-docker",
            name: "Docker & Containers",
            version: "1.29.0",
            author: "Microsoft",
            description: "Build, manage, and debug containerized applications with Docker CLI and compose file linting.",
            type: .tool,
            runtime: .javascript,
            main: "extension.js",
            icon: "shippingbox.fill",
            repository: "https://github.com/microsoft/vscode-docker",
            license: "MIT",
            keywords: ["docker", "containers", "devops"]
        ),
        ExtensionManifest(
            id: "dotmini.cloud-gpu",
            name: "Dotmini Cloud GPU Pod",
            version: "2.0.0",
            author: "Dotmini Software",
            description: "Direct zero-config compute bridge to RTX 4090, A100, H100, and B200 cloud clusters with 10Gbps dataset sync.",
            type: .aiProvider,
            runtime: .rust,
            main: "cloud_gpu",
            icon: "cpu.fill",
            repository: "https://github.com/Dotmini/microcode",
            license: "Proprietary",
            keywords: ["cloud", "gpu", "hpc", "runpod"]
        ),
        ExtensionManifest(
            id: "dotmini.cyber-dark",
            name: "Cyber Dark Pro Theme",
            version: "1.5.0",
            author: "Dotmini Software",
            description: "Sleek, near-black high contrast developer theme with neon syntax highlights and metal backgrounds.",
            type: .theme,
            runtime: .javascript,
            main: "theme.json",
            icon: "moon.stars.fill",
            repository: "https://github.com/Dotmini/microcode",
            license: "MIT",
            keywords: ["theme", "dark", "cyber"]
        ),
        ExtensionManifest(
            id: "google.colab-theme",
            name: "Google Colab Dark Theme",
            version: "1.0.0",
            author: "Project IDX Team",
            description: "Dark theme inspired by Google Colab & Project IDX editor palettes.",
            type: .theme,
            runtime: .javascript,
            main: "colab.json",
            icon: "paintpalette.fill",
            repository: "https://github.com/Dotmini/microcode",
            license: "MIT",
            keywords: ["theme", "colab", "google"]
        )
    ]

    // MARK: - Load Extensions
    func loadExtensions() async {
        isLoading = true
        var extensions: [InstalledExtension] = []
        
        // 1. Load official extensions from directory
        let dirOfficial = await loadExtensionsFromDirectory(officialExtensionsDirectory, isOfficial: true)
        extensions.append(contentsOf: dirOfficial)
        
        // 2. Load user extensions. Do not populate the page with a fake
        // catalog: only extensions that exist on disk are shown as installed.
        // A marketplace/catalog is a separate network-backed product surface.
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
            setEnabled(id, enabled: false)
        } else {
            // Check permissions before enabling
            if checkPermissions(for: id) {
                setEnabled(id, enabled: true)
            } else {
                requestPermissions(for: id)
            }
        }
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
        if enabled, let installedExtension = installedExtensions.first(where: { $0.id == id }) {
            Task {
                do {
                    try await ExtensionHostService.shared.activate(installedExtension)
                } catch {
                    ExtensionHostService.shared.reportFailure(error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Install Extension (Universal)
    public func isExtensionInstalled(_ id: String) -> Bool {
        let normalized = id.lowercased()
        return installedExtensions.contains {
            $0.id.lowercased() == normalized ||
            $0.manifest.id.lowercased() == normalized ||
            $0.manifest.name.lowercased() == normalized ||
            $0.path.lastPathComponent.lowercased() == normalized
        }
    }
    
    @discardableResult
    func installExtension(from url: URL) async throws -> String {
        if url.pathExtension.lowercased() == "vsix" {
            return try await installVSIX(from: url)
        } else {
            return try await installStandardExtension(from: url)
        }
    }

    /// Creates a minimal, runnable Node extension outside the application
    /// bundle. Community authors own this folder and can open it in any editor.
    func createJavaScriptStarterExtension() async throws -> URL {
        let slug = "community-extension-\(UUID().uuidString.prefix(8).lowercased())"
        let destination = extensionsDirectory.appendingPathComponent(slug, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)

        let manifest = ExtensionManifest(
            id: "community.\(slug)",
            name: "My MicroCode Extension",
            version: "0.1.0",
            author: NSFullUserName(),
            description: "A community extension for MicroCode.",
            type: .command,
            runtime: .javascript,
            main: "extension.js",
            icon: "puzzlepiece.extension",
            repository: nil,
            license: "MIT",
            keywords: ["community"]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: destination.appendingPathComponent("manifest.json"))
        let source = """
        // MicroCode extension host exposes a scoped VS Code-compatible API.
        const vscode = require('vscode');

        function activate(context) {
          const command = vscode.commands.registerCommand('community.hello', () => {
            vscode.window.showInformationMessage('Hello from your MicroCode extension.');
          });
          context.subscriptions.push(command);
        }

        module.exports = { activate };
        """
        try source.data(using: .utf8)?.write(to: destination.appendingPathComponent("extension.js"))
        
        // Provide initial UI feature canvas view
        let sampleHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
                    background-color: transparent;
                    color: currentColor;
                    margin: 0;
                    padding: 24px;
                }
                .card {
                    border: 1px solid rgba(128, 128, 128, 0.25);
                    border-radius: 12px;
                    padding: 20px;
                    background: rgba(128, 128, 128, 0.04);
                }
                .title { font-size: 16px; font-weight: 600; margin-bottom: 6px; }
                .btn {
                    padding: 7px 14px;
                    border-radius: 6px;
                    border: 1px solid rgba(128, 128, 128, 0.35);
                    background: rgba(128, 128, 128, 0.1);
                    color: inherit;
                    cursor: pointer;
                    font-size: 12px;
                }
            </style>
        </head>
        <body>
            <div class="card">
                <div class="title">My MicroCode Extension Canvas</div>
                <p style="font-size: 12px; opacity: 0.7;">This custom extension UI is running inside the MicroCode Extension Host Canvas.</p>
                <button class="btn" onclick="alert('Hello from Extension Canvas!')">Interact with Extension</button>
            </div>
        </body>
        </html>
        """
        try? sampleHTML.data(using: .utf8)?.write(to: destination.appendingPathComponent("ui.html"))
        
        await loadExtensions()
        setEnabled("community.\(slug)", enabled: true)
        return destination
    }

    /// Installs a catalog extension directly into user extensions directory
    func installFromCatalog(_ manifest: ExtensionManifest) async throws {
        let slug = manifest.id.replacingOccurrences(of: "/", with: "-")
        let destination = extensionsDirectory.appendingPathComponent(slug, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: destination.appendingPathComponent("manifest.json"))

        let entryFile = destination.appendingPathComponent(manifest.main)
        if !FileManager.default.fileExists(atPath: entryFile.path) {
            let defaultCode = """
            // MicroCode Extension: \(manifest.name)
            const vscode = require('vscode');

            function activate(context) {
                console.log('Extension \(manifest.id) activated');
            }

            module.exports = { activate };
            """
            try defaultCode.data(using: .utf8)?.write(to: entryFile)
        }

        let uiFile = destination.appendingPathComponent("ui.html")
        if !FileManager.default.fileExists(atPath: uiFile.path) {
            let sampleHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <style>
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
                        background-color: transparent;
                        color: currentColor;
                        margin: 0;
                        padding: 24px;
                        display: flex;
                        flex-direction: column;
                        gap: 16px;
                    }
                    .card {
                        border: 1px solid rgba(128, 128, 128, 0.25);
                        border-radius: 12px;
                        padding: 20px;
                        background: rgba(128, 128, 128, 0.05);
                    }
                    .title { font-size: 16px; font-weight: 600; margin-bottom: 6px; }
                    .subtitle { font-size: 12px; opacity: 0.7; margin-bottom: 14px; }
                    .btn {
                        padding: 6px 14px;
                        border-radius: 6px;
                        border: 1px solid rgba(128, 128, 128, 0.35);
                        background: rgba(128, 128, 128, 0.1);
                        color: inherit;
                        cursor: pointer;
                        font-size: 12px;
                        font-weight: 500;
                    }
                    .btn:hover { background: rgba(128, 128, 128, 0.2); }
                    .badge {
                        display: inline-block;
                        padding: 2px 8px;
                        border-radius: 20px;
                        font-size: 10px;
                        font-weight: 600;
                        background: rgba(128, 128, 128, 0.15);
                    }
                </style>
            </head>
            <body>
                <div class="card">
                    <div class="badge">\(manifest.type.displayName.uppercased())</div>
                    <div class="title" style="margin-top: 8px;">\(manifest.name)</div>
                    <div class="subtitle">\(manifest.description)</div>
                    <div style="display: flex; gap: 8px; margin-top: 12px;">
                        <button class="btn" onclick="alert('Feature Action executed for \(manifest.name)')">Execute Action</button>
                        <button class="btn" onclick="document.getElementById('status').innerText = 'Synced at ' + new Date().toLocaleTimeString()">Sync Status</button>
                    </div>
                    <div id="status" style="font-size: 11px; margin-top: 12px; opacity: 0.6; font-family: monospace;">Live UI Feature mounted in MicroCode Extension Canvas</div>
                </div>
            </body>
            </html>
            """
            try? sampleHTML.data(using: .utf8)?.write(to: uiFile)
        }

        await loadExtensions()
        setEnabled(manifest.id, enabled: true)
    }

    /// Retrieves the custom UI HTML content for a given extension
    func getUIContent(for extensionId: String) -> String? {
        guard let ext = installedExtensions.first(where: { $0.id == extensionId }) else { return nil }
        let uiCandidates = ["ui.html", "index.html", "webview.html"]
        for candidate in uiCandidates {
            let url = ext.path.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        return nil
    }

    /// Saves or updates the custom UI HTML for an extension
    func saveUIContent(for extensionId: String, html: String) throws {
        guard let ext = installedExtensions.first(where: { $0.id == extensionId }) else { return }
        let url = ext.path.appendingPathComponent("ui.html")
        try html.data(using: .utf8)?.write(to: url)
    }

    // MARK: - Standard Install
    private func installStandardExtension(from url: URL) async throws -> String {
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
        return destName
    }
    
    // MARK: - VSIX Install Logic
    private func installVSIX(from url: URL) async throws -> String {
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
        let pub = (vscodePkg.publisher ?? "").isEmpty ? "community" : (vscodePkg.publisher ?? "community")
        
        // 6. Install to Destination
        // VSIX contents are typically in 'extension/' folder inside the archive
        let sourceContent = tempDir.appendingPathComponent("extension")
        let destReqName = "\(pub).\(vscodePkg.name)"
        let destPath = extensionsDirectory.appendingPathComponent(destReqName)
        
        if FileManager.default.fileExists(atPath: destPath.path) {
            try FileManager.default.removeItem(at: destPath)
        }
        
        try FileManager.default.moveItem(at: sourceContent, to: destPath)
        
        // 7. Write new manifest.json
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: destPath.appendingPathComponent("manifest.json"))
        
        // 8. Ensure main entry file exists (or stub it for themes/languages)
        let mainPath = destPath.appendingPathComponent(manifest.main)
        if !FileManager.default.fileExists(atPath: mainPath.path) {
            let stubCode = """
            // MicroCode Extension: \(manifest.name)
            const vscode = require('vscode');
            function activate(context) {
                console.log('Extension \(manifest.id) activated');
            }
            module.exports = { activate };
            """
            try? stubCode.data(using: .utf8)?.write(to: mainPath)
        }
        
        await loadExtensions()
        setEnabled(manifest.id, enabled: true)
        return manifest.id
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
        if pkg.contributes?.iconThemes != nil && !(pkg.contributes?.iconThemes?.isEmpty ?? true) {
            type = .iconTheme
        } else if pkg.contributes?.themes != nil && !(pkg.contributes?.themes?.isEmpty ?? true) {
            type = .theme
        } else if pkg.contributes?.languages != nil && !(pkg.contributes?.languages?.isEmpty ?? true) {
            type = .language
        }
        
        let pub = pkg.publisher ?? "community"
        let entry = pkg.main ?? (type == .theme ? (pkg.contributes?.themes?.first?.path ?? "extension.js") : "extension.js")
        
        return ExtensionManifest(
            id: "\(pub).\(pkg.name)",
            name: pkg.displayName ?? pkg.name,
            version: pkg.version ?? "1.0.0",
            author: pub,
            description: pkg.description ?? "VS Code Extension for MicroCode",
            type: type,
            runtime: .javascript, // VSIX implies JS/TS runtime
            main: entry,
            icon: nil,
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
        for ext in installedExtensions where ext.isEnabled && (ext.effectiveType == .theme || ext.manifest.type == .theme) {
            applyThemeExtension(ext)
        }
    }
    
    public func applyThemeExtension(_ ext: InstalledExtension, in appState: AppState? = nil) {
        let id = ext.id.lowercased()
        let targetTheme: AppTheme?
        if id.contains("night-owl") {
            targetTheme = .nightOwl
        } else if id.contains("material-theme") || id.contains("one-dark") {
            targetTheme = .oneDarkPro
        } else if id.contains("dracula") {
            targetTheme = .dracula
        } else if id.contains("nord") {
            targetTheme = .nord
        } else if id.contains("tokyo") {
            targetTheme = .tokyoNight
        } else if id.contains("catppuccin") {
            targetTheme = .catppuccin
        } else if id.contains("github") {
            targetTheme = .githubDark
        } else if id.contains("solarized") {
            targetTheme = .solarizedDark
        } else if id.contains("monokai") {
            targetTheme = .monokaiPro
        } else {
            targetTheme = nil
        }
        
        if let target = targetTheme {
            if let state = appState ?? AppState.shared {
                state.appTheme = target
            }
            UserDefaults.standard.set(target.rawValue, forKey: "appTheme")
            NotificationCenter.default.post(name: NSNotification.Name("MicroCodeThemeChanged"), object: target)
            print("Successfully activated theme extension: \(target.displayName)")
        }
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
        setEnabled(id, enabled: true)
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
    let publisher: String?
    let version: String?
    let description: String?
    let main: String?
    let icon: String?
    let contributes: VSCodeContributions?
}

struct VSCodeCommandItem: Codable {
    let command: String
    let title: String
    let category: String?
    let icon: String?
}

struct VSCodeContributions: Codable {
    let themes: [VSCodeTheme]?
    let iconThemes: [VSCodeIconTheme]?
    let languages: [VSCodeLanguage]?
    let commands: [VSCodeCommandItem]?
}

struct VSCodeTheme: Codable {
    let label: String?
    let uiTheme: String?
    let path: String?
}

struct VSCodeIconTheme: Codable {
    let id: String?
    let label: String?
    let path: String?
}

// MARK: - Material Icons Decodable Model
struct MaterialIconsManifest: Decodable {
    let iconDefinitions: [String: IconDef]?
    let fileExtensions: [String: String]?
    let fileNames: [String: String]?
    let folderNames: [String: String]?
    let folderNamesExpanded: [String: String]?
    let file: String?
    let folder: String?
    let folderExpanded: String?
    
    struct IconDef: Decodable {
        let iconPath: String?
    }
}

struct VSCodeLanguage: Codable {
    let id: String
    let extensions: [String]?
}

struct VSCodeCommandContribution: Identifiable, Hashable {
    var id: String { command }
    let command: String
    let title: String
    let category: String?
    let icon: String?
}

struct VSCodeConfigProperty: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let type: String
    let description: String
    let defaultValue: String
    let enumValues: [String]?
}
