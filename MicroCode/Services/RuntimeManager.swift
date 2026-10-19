//
//  RuntimeManager.swift
//  MicroCode
//
//  Manages runtime detection and on-demand downloads
//  Copyright © 2025 Dotmini Company Limited. All rights reserved.
//

import SwiftUI
import Foundation

// MARK: - Runtime Definition

enum RuntimeType: String, CaseIterable, Identifiable {
    case python = "Python"
    case nodejs = "Node.js"
    case bun = "Bun"
    case deno = "Deno"
    case r = "R"
    case julia = "Julia"
    case java = "Java"
    case kotlin = "Kotlin"
    case c = "C"
    case cpp = "C++"
    case go = "Go"
    case rust = "Rust"
    case swift = "Swift"
    case dotnet = ".NET"
    case ruby = "Ruby"
    case php = "PHP"
    case lua = "Lua"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .python: return "🐍"
        case .nodejs: return "⬢"
        case .bun: return "🥟"
        case .deno: return "🦕"
        case .r: return "Ⓡ"
        case .julia: return "●"
        case .java: return "☕️"
        case .kotlin: return "◆"
        case .c: return "C"
        case .cpp: return "C++"
        case .go: return "🐹"
        case .rust: return "🦀"
        case .swift: return "🐦"
        case .dotnet: return "🔷"
        case .ruby: return "💎"
        case .php: return "🐘"
        case .lua: return "🌙"
        }
    }
    
    var color: Color {
        switch self {
        case .python, .r, .julia: return .yellow
        case .nodejs, .bun, .deno: return .green
        case .java, .kotlin: return .red
        case .c, .cpp: return .blue
        case .go: return .cyan
        case .rust: return .orange
        case .swift: return .orange
        case .dotnet, .ruby, .php, .lua: return .purple
        }
    }
    
    var binaryName: String {
        switch self {
        case .python: return "python3"
        case .nodejs: return "node"
        case .bun: return "bun"
        case .deno: return "deno"
        case .r: return "R"
        case .julia: return "julia"
        case .java: return "java"
        case .kotlin: return "kotlinc"
        case .c: return "clang"
        case .cpp: return "clang++"
        case .go: return "go"
        case .rust: return "rustc"
        case .swift: return "swift"
        case .dotnet: return "dotnet"
        case .ruby: return "ruby"
        case .php: return "php"
        case .lua: return "lua"
        }
    }

    /// Subdirectory inside a Full-Bundle app:
    /// App.app/Contents/Resources/RuntimeLib/<bundleDirName>/bin/<binaryName>
    /// (matches bundle_runtimes.sh RUNTIMES_ROOT layout).
    var bundleDirName: String {
        switch self {
        case .nodejs: return "nodejs"
        case .dotnet: return "dotnet"
        default: return rawValue.lowercased().replacingOccurrences(of: "+", with: "p")
        }
    }
    
    // Download URLs (portable zero-dependency versions for macOS)
    func getDownloadInfo() -> (url: String, size: String, fileName: String, localCacheName: String?)? {
        let arch = ProcessInfo.processInfo.machineArchitecture
        let isArm = (arch == "arm64")
        switch self {
        case .python:
            let tag = "20241016"
            let ver = "3.12.7"
            let target = isArm ? "aarch64-apple-darwin" : "x86_64-apple-darwin"
            let cache = isArm ? "python-arm64.tar.gz" : "python-x86_64.tar.gz"
            return (
                "https://github.com/indygreg/python-build-standalone/releases/download/\(tag)/cpython-\(ver)+\(tag)-\(target)-install_only.tar.gz",
                "~32 MB",
                "cpython-\(ver)-\(target).tar.gz",
                cache
            )
        case .nodejs:
            let ver = "22.14.0"
            let target = isArm ? "darwin-arm64" : "darwin-x64"
            let cache = isArm ? "nodejs-arm64.tar.gz" : "nodejs-x86_64.tar.gz"
            return (
                "https://nodejs.org/dist/v\(ver)/node-v\(ver)-\(target).tar.gz",
                "~28 MB",
                "node-v\(ver)-\(target).tar.gz",
                cache
            )
        case .bun:
            let target = isArm ? "bun-darwin-aarch64.zip" : "bun-darwin-x64.zip"
            let cache = isArm ? "bun-arm64.zip" : "bun-x86_64.zip"
            return (
                "https://github.com/oven-sh/bun/releases/latest/download/\(target)",
                "~22 MB",
                target,
                cache
            )
        case .deno:
            let target = isArm ? "deno-aarch64-apple-darwin.zip" : "deno-x86_64-apple-darwin.zip"
            let cache = isArm ? "deno-arm64.zip" : "deno-x86_64.zip"
            return (
                "https://github.com/denoland/deno/releases/latest/download/\(target)",
                "~38 MB",
                target,
                cache
            )
        case .go:
            let ver = "1.23.4"
            let target = isArm ? "darwin-arm64" : "darwin-amd64"
            let cache = isArm ? "go-arm64.tar.gz" : "go-x86_64.tar.gz"
            return (
                "https://go.dev/dl/go\(ver).\(target).tar.gz",
                "~68 MB",
                "go\(ver).\(target).tar.gz",
                cache
            )
        case .rust:
            let target = isArm ? "aarch64-apple-darwin" : "x86_64-apple-darwin"
            let cache = isArm ? "rustup-init-arm64" : "rustup-init-x86_64"
            return (
                "https://static.rust-lang.org/rustup/dist/\(target)/rustup-init",
                "~8 MB",
                "rustup-init",
                cache
            )
        case .java:
            let target = isArm ? "aarch64" : "x64"
            return (
                "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jdk_\(target)_mac_hotspot_21.0.5_11.tar.gz",
                "~195 MB",
                "OpenJDK21U-jdk_\(target).tar.gz",
                nil
            )
        case .kotlin:
            return (
                "https://github.com/JetBrains/kotlin/releases/download/v2.1.0/kotlin-compiler-2.1.0.zip",
                "~75 MB",
                "kotlin-compiler-2.1.0.zip",
                nil
            )
        case .c, .cpp:
            let target = isArm ? "aarch64" : "x86_64"
            return (
                "https://ziglang.org/download/0.13.0/zig-macos-\(target)-0.13.0.tar.xz",
                "~45 MB",
                "zig-macos-\(target)-0.13.0.tar.xz",
                nil
            )
        case .dotnet:
            return (
                "https://dot.net/v1/dotnet-install.sh",
                "~1 MB",
                "dotnet-install.sh",
                nil
            )
        case .swift, .r, .julia, .ruby, .php, .lua:
            return nil
        }
    }
}

// MARK: - Runtime Status

class RuntimeStatus: ObservableObject, Identifiable {
    let id = UUID()
    let type: RuntimeType
    @Published var isInstalled: Bool = false
    @Published var version: String?
    @Published var path: String?
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var statusMessage: String = ""
    
    init(type: RuntimeType) {
        self.type = type
    }
}

// MARK: - Runtime Manager

class RuntimeManager: ObservableObject {
    static let shared = RuntimeManager()
    
    @Published var runtimes: [RuntimeStatus] = []
    @Published var isDetecting: Bool = false
    @Published var lastDetectionDate: Date?
    @Published var errorMessage: String?
    
    let runtimesDir: URL
    private let detectionQueue = DispatchQueue(label: "com.dotmini.microcode.runtimeDetection", qos: .utility)
    private var versionCache: [String: String] = [:]
    private let cacheLock = NSLock()
    
    init() {
        // Store runtimes in Application Support: ~/Library/Application Support/MicroCode/Runtimes
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        runtimesDir = appSupport.appendingPathComponent("MicroCode/Runtimes")
        
        try? FileManager.default.createDirectory(at: runtimesDir, withIntermediateDirectories: true)
        
        // Initialize with all runtime types
        runtimes = RuntimeType.allCases.map { RuntimeStatus(type: $0) }
        
        // Auto-detect on init
        detectAll(force: true)
    }
    
    // MARK: - Language Mapping & Environment Helpers
    
    func runtimeType(forLanguage language: String) -> RuntimeType? {
        switch language.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "python", "py", "python3":
            return .python
        case "javascript", "js", "node", "nodejs":
            return .nodejs
        case "typescript", "ts":
            // Prefer Bun or Deno if installed, otherwise provision Bun (fastest zero-config TS runner)
            if isRuntimeAvailable(.bun) { return .bun }
            if isRuntimeAvailable(.deno) { return .deno }
            if isRuntimeAvailable(.nodejs) { return .nodejs }
            return .bun
        case "bun":
            return .bun
        case "deno":
            return .deno
        case "go", "golang":
            return .go
        case "rust", "rs":
            return .rust
        case "java":
            return .java
        case "kotlin", "kt":
            return .kotlin
        case "c":
            return .c
        case "cpp", "c++", "cc", "cxx":
            return .cpp
        case "swift":
            return .swift
        case "csharp", "cs", "dotnet", "fsharp", "fs":
            return .dotnet
        case "r", "rmarkdown", "rmd":
            return .r
        case "julia", "jl":
            return .julia
        case "ruby", "rb":
            return .ruby
        case "php":
            return .php
        case "lua":
            return .lua
        default:
            return nil
        }
    }
    
    func isRuntimeAvailable(_ type: RuntimeType) -> Bool {
        if let existing = runtimes.first(where: { $0.type == type }), existing.isInstalled, let path = existing.path,
           DeveloperToolsGuard.isSafeToExecute(path) {
            // Special check for Java: Playground/Cell mode needs `javac` as well as `java`
            if type == .java {
                let javacPath = (path as NSString).deletingLastPathComponent + "/javac"
                if !FileManager.default.isExecutableFile(atPath: javacPath) && searchCommonInstallPaths("javac") == nil {
                    return false
                }
            }
            return true
        }
        let detected = detectRuntimeQuick(type)
        if type == .java, detected.isInstalled, let path = detected.path {
            let javacPath = (path as NSString).deletingLastPathComponent + "/javac"
            if !FileManager.default.isExecutableFile(atPath: javacPath) && searchCommonInstallPaths("javac") == nil {
                return false
            }
        }
        return detected.isInstalled
    }
    
    /// Returns all portable/bundled runtime `bin` directories to prepend to PATH
    func allRuntimeBinDirectories() -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var bins: [String] = []
        
        var roots: [URL] = [
            runtimesDir,
            URL(fileURLWithPath: "\(home)/.microcode/runtimes")
        ]
        if let res = Bundle.main.resourceURL {
            roots.append(res.appendingPathComponent("RuntimeLib"))
        }
        
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                let binDir = item.appendingPathComponent("bin").path
                if fm.fileExists(atPath: binDir) {
                    bins.append(binDir)
                }
                let nestedGoBin = item.appendingPathComponent("go/bin").path
                if fm.fileExists(atPath: nestedGoBin) {
                    bins.append(nestedGoBin)
                }
                let nestedJavaBin = item.appendingPathComponent("Contents/Home/bin").path
                if fm.fileExists(atPath: nestedJavaBin) {
                    bins.append(nestedJavaBin)
                }
                let nestedCargoBin = item.appendingPathComponent("cargo/bin").path
                if fm.fileExists(atPath: nestedCargoBin) {
                    bins.append(nestedCargoBin)
                }
                // Direct executable directory (e.g. dotnet)
                if item.lastPathComponent == "dotnet" && fm.isExecutableFile(atPath: item.appendingPathComponent("dotnet").path) {
                    bins.append(item.path)
                }
            }
        }
        return bins
    }
    
    func portableJavaHome() -> String? {
        let fm = FileManager.default
        let rscPath = Bundle.main.resourceURL?.path
        var candidates: [String] = [
            runtimesDir.appendingPathComponent("java/Contents/Home").path,
            runtimesDir.appendingPathComponent("java").path
        ]
        if let rscPath = rscPath {
            candidates.append((rscPath as NSString).appendingPathComponent("RuntimeLib/java/Contents/Home"))
            candidates.append((rscPath as NSString).appendingPathComponent("RuntimeLib/java"))
        }
        candidates.append("/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home")
        candidates.append("/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home")
        return candidates.first { fm.isExecutableFile(atPath: ($0 as NSString).appendingPathComponent("bin/java")) }
    }
    
    func portableGoRoot() -> String? {
        let fm = FileManager.default
        let rscPath = Bundle.main.resourceURL?.path
        var candidates: [String] = [
            runtimesDir.appendingPathComponent("go/go").path,
            runtimesDir.appendingPathComponent("go").path
        ]
        if let rscPath = rscPath {
            candidates.append((rscPath as NSString).appendingPathComponent("RuntimeLib/go"))
        }
        return candidates.first {
            fm.isExecutableFile(atPath: ($0 as NSString).appendingPathComponent("bin/go")) &&
            fm.fileExists(atPath: ($0 as NSString).appendingPathComponent("pkg"))
        }
    }
    
    /// Ensures the runtime required for `language` is installed. If missing and a portable runtime
    /// package is available, automatically downloads and provisions it into Application Support.
    func ensureRuntime(forLanguage language: String, onStatus: ((String) -> Void)? = nil) async -> Bool {
        guard let type = runtimeType(forLanguage: language) else {
            return true
        }
        if isRuntimeAvailable(type) {
            return true
        }
        // For Kotlin, also ensure Java is available
        if type == .kotlin && !isRuntimeAvailable(.java) {
            onStatus?("📦 Installing portable Java JDK 21 for Kotlin...")
            _ = await downloadAndInstallAsync(.java, onStatus: onStatus)
        }
        guard type.getDownloadInfo() != nil else {
            return false
        }
        onStatus?("📦 Installing portable \(type.rawValue) runtime (first-run setup)...")
        let ok = await downloadAndInstallAsync(type, onStatus: onStatus)
        if ok {
            onStatus?("✅ \(type.rawValue) runtime ready!")
        }
        return ok
    }
    
    private func downloadAndInstallAsync(_ type: RuntimeType, onStatus: ((String) -> Void)? = nil) async -> Bool {
        guard let downloadInfo = type.getDownloadInfo() else { return false }
        guard let runtime = runtimes.first(where: { $0.type == type }) else { return false }
        
        await MainActor.run {
            runtime.isDownloading = true
            runtime.downloadProgress = 0.05
            runtime.statusMessage = "Downloading \(type.rawValue)..."
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let success = self.performInstallSync(type: type, runtime: runtime, downloadInfo: downloadInfo, onStatus: onStatus)
                continuation.resume(returning: success)
            }
        }
    }
    
    // MARK: - Detection (Zero-Storm Batched Scanner)
    
    func detectAll(force: Bool = false) {
        if !force, let last = lastDetectionDate, Date().timeIntervalSince(last) < 3.0 {
            return
        }
        
        detectionQueue.async { [weak self] in
            guard let self = self else { return }
            if !force, self.isDetecting { return }
            
            DispatchQueue.main.async {
                self.isDetecting = true
            }
            
            var results: [(RuntimeStatus, Bool, String?, String?)] = []
            var unresolved: [RuntimeStatus] = []
            
            // Pass 1: Fast filesystem-only check (no shell processes spawned!)
            for runtime in self.runtimes {
                let quick = self.detectRuntimeQuick(runtime.type)
                if quick.isInstalled {
                    results.append((runtime, true, quick.version, quick.path))
                } else {
                    unresolved.append(runtime)
                }
            }
            
            // Pass 2: Single batched login-shell query for any remaining unresolved binaries
            if !unresolved.isEmpty {
                let resolvedMap = self.resolveBatchViaLoginShell(unresolved.map { $0.type.binaryName })
                for runtime in unresolved {
                    if let path = resolvedMap[runtime.type.binaryName], DeveloperToolsGuard.isSafeToExecute(path) {
                        let ver = self.getVersionCached(for: runtime.type, at: path)
                        results.append((runtime, true, ver, path))
                    } else {
                        results.append((runtime, false, nil, nil))
                    }
                }
            }
            
            DispatchQueue.main.async {
                for (runtime, installed, version, path) in results {
                    runtime.isInstalled = installed
                    runtime.version = version
                    runtime.path = path
                }
                self.isDetecting = false
                self.lastDetectionDate = Date()
            }
        }
    }

    /// All discovered installs, including version managers.
    func availablePaths(for type: RuntimeType) -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var candidates = Set<String>()
        if let current = runtimes.first(where: { $0.type == type })?.path { candidates.insert(current) }
        if let saved = UserDefaults.standard.string(forKey: "runtimeOverride.\(type.rawValue)"),
           fm.isExecutableFile(atPath: saved) { candidates.insert(saved) }
        for portable in portableBinaryCandidates(for: type) where fm.isExecutableFile(atPath: portable) {
            candidates.insert(portable)
        }
        if type == .nodejs {
            for root in ["\(home)/.nvm/versions/node", "\(home)/.asdf/installs/nodejs"] {
                for version in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
                    let path = "\(root)/\(version)/bin/node"
                    if fm.isExecutableFile(atPath: path) { candidates.insert(path) }
                }
            }
        }
        if type == .dotnet {
            for root in [runtimesDir.appendingPathComponent("dotnet").path, "/usr/local/share/dotnet", "\(home)/.dotnet"] {
                let path = "\(root)/dotnet"
                if fm.isExecutableFile(atPath: path) { candidates.insert(path) }
            }
        }
        return candidates.sorted()
    }

    func activateRuntime(_ path: String, for type: RuntimeType) {
        UserDefaults.standard.set(path, forKey: "runtimeOverride.\(type.rawValue)")
        detectAll(force: true)
    }

    /// The executable chosen in Manage Environments.
    func selectedExecutable(for type: RuntimeType) -> String? {
        let fm = FileManager.default
        if let override = UserDefaults.standard.string(forKey: "runtimeOverride.\(type.rawValue)"),
           fm.isExecutableFile(atPath: override) {
            return override
        }
        if let installedPath = runtimes.first(where: { $0.type == type && $0.isInstalled })?.path,
           fm.isExecutableFile(atPath: installedPath) {
            return installedPath
        }
        return detectRuntimeQuick(type).path
    }
    
    private func portableBinaryCandidates(for type: RuntimeType) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = type.bundleDirName
        let rawDir = type.rawValue.lowercased()
        let bin = type.binaryName
        
        var paths: [String] = []
        if let res = Bundle.main.resourceURL {
            paths.append(res.appendingPathComponent("RuntimeLib/\(dir)/bin/\(bin)").path)
            paths.append(res.appendingPathComponent("RuntimeLib/\(dir)/Contents/Home/bin/\(bin)").path)
        }
        paths.append(runtimesDir.appendingPathComponent("\(dir)/bin/\(bin)").path)
        paths.append(runtimesDir.appendingPathComponent("\(rawDir)/bin/\(bin)").path)
        paths.append("\(home)/.microcode/runtimes/\(dir)/bin/\(bin)")
        
        if type == .go {
            paths.append(runtimesDir.appendingPathComponent("go/go/bin/go").path)
        }
        if type == .java {
            paths.append(runtimesDir.appendingPathComponent("java/Contents/Home/bin/java").path)
        }
        if type == .rust {
            paths.append(runtimesDir.appendingPathComponent("rust/cargo/bin/rustc").path)
        }
        if type == .dotnet {
            paths.append(runtimesDir.appendingPathComponent("dotnet/dotnet").path)
        }
        return paths
    }
    
    /// Fast filesystem check without spawning any login shell
    private func detectRuntimeQuick(_ type: RuntimeType) -> (isInstalled: Bool, version: String?, path: String?) {
        if let override = UserDefaults.standard.string(forKey: "runtimeOverride.\(type.rawValue)"),
           DeveloperToolsGuard.isSafeToExecute(override) {
            return (true, getVersionCached(for: type, at: override) ?? "selected", override)
        }

        // 1. Check embedded RuntimeLib and in-app Runtimes directory
        for candidate in portableBinaryCandidates(for: type) {
            if DeveloperToolsGuard.isSafeToExecute(candidate) {
                return (true, getVersionCached(for: type, at: candidate) ?? "portable", candidate)
            }
        }

        // 2. Scan well-known install locations (Homebrew, Cargo, pyenv, nvm, SDKs, system CLT)
        if let p = searchCommonInstallPaths(type.binaryName) {
            return (true, getVersionCached(for: type, at: p), p)
        }

        return (false, nil, nil)
    }

    /// Resolve multiple missing binary names in a SINGLE login shell invocation to prevent process storms.
    private func resolveBatchViaLoginShell(_ bins: [String]) -> [String: String] {
        let uniqueBins = Array(Set(bins)).filter { !$0.isEmpty }
        guard !uniqueBins.isEmpty else { return [:] }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return [:] }
        
        let script = uniqueBins.map { bin in
            "p=$(command -v '\(bin)' 2>/dev/null | head -n 1); if [ -n \"$p\" ]; then echo \"\(bin)=$p\"; fi"
        }.joined(separator: "; ")
        
        let r = runCommand(shell, arguments: ["-l", "-c", script])
        var map: [String: String] = [:]
        guard let output = r.output else { return map }
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let path = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if path.hasPrefix("/") && DeveloperToolsGuard.isSafeToExecute(path) {
                    map[name] = path
                }
            }
        }
        return map
    }

    /// Scan well-known install locations on macOS
    private func searchCommonInstallPaths(_ bin: String) -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var dirs = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
            "\(home)/.cargo/bin", "\(home)/.local/bin", "\(home)/.bun/bin", "\(home)/.deno/bin",
            "\(home)/go/bin", "/usr/local/go/bin", "\(home)/.pyenv/shims",
            "/opt/homebrew/opt/openjdk@21/bin", "/opt/homebrew/opt/openjdk@17/bin", "/opt/homebrew/opt/openjdk/bin",
            "/opt/homebrew/opt/python@3.12/bin", "/opt/homebrew/opt/python@3.11/bin",
            "/Library/Frameworks/Python.framework/Versions/Current/bin",
            "/usr/local/share/dotnet", "\(home)/.dotnet"
        ]
        if DeveloperToolsGuard.hasCommandLineTools {
            dirs.append("/usr/bin")
            dirs.append("/bin")
        } else if bin == "ruby" || bin == "php" {
            dirs.append("/usr/bin")
        }
        let nvmRoot = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmRoot) {
            for v in versions.sorted().reversed() { dirs.append("\(nvmRoot)/\(v)/bin") }
        }
        for d in dirs {
            let p = (d as NSString).appendingPathComponent(bin)
            if DeveloperToolsGuard.isSafeToExecute(p) { return p }
        }
        return nil
    }
    
    private func getVersionCached(for type: RuntimeType, at executablePath: String? = nil) -> String? {
        let exe = executablePath ?? runtimes.first(where: { $0.type == type })?.path
        guard let validExe = exe, DeveloperToolsGuard.isSafeToExecute(validExe) else { return nil }
        
        cacheLock.lock()
        if let cached = versionCache[validExe] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        
        let result: CommandResult
        switch type {
        case .go:
            result = runCommand(validExe, arguments: ["version"])
        case .java:
            result = runCommand(validExe, arguments: ["-version"])
        case .kotlin:
            result = runCommand(validExe, arguments: ["-version"])
        default:
            result = runCommand(validExe, arguments: ["--version"])
        }
        
        let combined = ((result.output ?? "") + "\n" + (result.error ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = combined.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let parts = firstLine.components(separatedBy: " ")
            let ver = parts.count >= 2 ? (parts.first(where: { $0.first?.isNumber == true || $0.hasPrefix("v") || $0.hasPrefix("go1") }) ?? parts.last ?? firstLine) : firstLine
            cacheLock.lock()
            versionCache[validExe] = ver
            cacheLock.unlock()
            return ver
        }
        return nil
    }
    
    // MARK: - Download & Install
    
    func install(_ type: RuntimeType) {
        guard let downloadInfo = type.getDownloadInfo() else {
            DispatchQueue.main.async {
                self.errorMessage = "\(type.rawValue) is managed by macOS or system packages."
            }
            return
        }
        
        guard let runtime = runtimes.first(where: { $0.type == type }) else { return }
        
        DispatchQueue.main.async {
            runtime.isDownloading = true
            runtime.downloadProgress = 0.0
            runtime.statusMessage = "Starting download..."
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.performInstallSync(type: type, runtime: runtime, downloadInfo: downloadInfo, onStatus: nil)
        }
    }
    
    @discardableResult
    private func performInstallSync(
        type: RuntimeType,
        runtime: RuntimeStatus,
        downloadInfo: (url: String, size: String, fileName: String, localCacheName: String?),
        onStatus: ((String) -> Void)?
    ) -> Bool {
        let fm = FileManager.default
        let downloadDir = runtimesDir.appendingPathComponent("downloads")
        try? fm.createDirectory(at: downloadDir, withIntermediateDirectories: true)
        
        let downloadPath = downloadDir.appendingPathComponent(downloadInfo.fileName)
        try? fm.removeItem(at: downloadPath)
        
        // Check local .runtime_cache first for instant offline install if available
        var usedLocalCache = false
        if let cacheName = downloadInfo.localCacheName {
            let candidateCaches = [
                URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".runtime_cache/\(cacheName)"),
                URL(fileURLWithPath: "/Users/dotmini/Documents/SX/codetunner-native/.runtime_cache/\(cacheName)")
            ]
            if let existingCache = candidateCaches.first(where: { fm.fileExists(atPath: $0.path) }) {
                try? fm.copyItem(at: existingCache, to: downloadPath)
                usedLocalCache = fm.fileExists(atPath: downloadPath.path)
            }
        }
        
        if !usedLocalCache {
            DispatchQueue.main.async {
                runtime.statusMessage = "Downloading \(type.rawValue) (\(downloadInfo.size))..."
                runtime.downloadProgress = 0.2
            }
            onStatus?("⬇️ Downloading portable \(type.rawValue) (\(downloadInfo.size))...")
            
            let curlArgs = ["-fSL", "--retry", "2", "-o", downloadPath.path, downloadInfo.url]
            let downloadResult = runCommand("/usr/bin/curl", arguments: curlArgs)
            
            if downloadResult.exitCode != 0 || !fm.fileExists(atPath: downloadPath.path) {
                DispatchQueue.main.async {
                    runtime.isDownloading = false
                    runtime.statusMessage = "Download failed"
                    self.errorMessage = "Download failed for \(type.rawValue): \(downloadResult.error ?? "Network error")"
                }
                onStatus?("❌ Failed to download \(type.rawValue): \(downloadResult.error ?? "Network error")")
                return false
            }
        }
        
        DispatchQueue.main.async {
            runtime.statusMessage = "Extracting & configuring \(type.rawValue)..."
            runtime.downloadProgress = 0.7
        }
        onStatus?("⚙️ Extracting portable \(type.rawValue) into Application Support...")
        
        let installResult: Bool
        let fileName = downloadInfo.fileName
        
        if type == .c || type == .cpp {
            installResult = installZigClangToolchain(archivePath: downloadPath)
        } else if fileName.hasSuffix(".tar.gz") || fileName.hasSuffix(".tar.xz") {
            installResult = installTarArchive(type: type, archivePath: downloadPath)
        } else if fileName.hasSuffix(".zip") {
            installResult = installZipArchive(type: type, archivePath: downloadPath)
        } else if fileName.hasSuffix(".pkg") {
            installResult = installPkg(type: type, pkgPath: downloadPath)
        } else if fileName.hasSuffix(".sh") {
            installResult = installScript(type: type, scriptPath: downloadPath)
        } else if fileName == "rustup-init" {
            installResult = installRustup(rustupPath: downloadPath)
        } else {
            installResult = false
        }
        
        try? fm.removeItem(at: downloadPath)
        
        // Strip quarantine attributes so macOS Gatekeeper never blocks execution
        let targetDir = runtimesDir.appendingPathComponent(type.bundleDirName)
        _ = runCommand("/usr/bin/xattr", arguments: ["-dr", "com.apple.quarantine", targetDir.path])
        
        // Refresh state immediately
        let detected = detectRuntimeQuick(type)
        DispatchQueue.main.async {
            runtime.isDownloading = false
            runtime.downloadProgress = 1.0
            runtime.isInstalled = installResult && detected.isInstalled
            runtime.version = detected.version
            runtime.path = detected.path
            runtime.statusMessage = installResult ? "Installed!" : "Installation failed"
            self.detectAll(force: true)
        }
        
        return installResult && detected.isInstalled
    }
    
    private func installTarArchive(type: RuntimeType, archivePath: URL) -> Bool {
        let fm = FileManager.default
        let installDir = runtimesDir.appendingPathComponent(type.bundleDirName)
        try? fm.removeItem(at: installDir)
        try? fm.createDirectory(at: installDir, withIntermediateDirectories: true)
        
        let tarFlag = archivePath.path.hasSuffix(".tar.xz") ? "-xJf" : "-xzf"
        
        if type == .java {
            let tempJava = runtimesDir.appendingPathComponent("java_tmp_\(UUID().uuidString.prefix(6))")
            try? fm.createDirectory(at: tempJava, withIntermediateDirectories: true)
            let res = runCommand("/usr/bin/tar", arguments: [tarFlag, archivePath.path, "-C", tempJava.path, "--strip-components=1"])
            guard res.exitCode == 0 else {
                try? fm.removeItem(at: tempJava)
                return false
            }
            let contentsHome = tempJava.appendingPathComponent("Contents/Home")
            let sourceRoot = fm.fileExists(atPath: contentsHome.path) ? contentsHome : tempJava
            try? fm.removeItem(at: installDir)
            try? fm.moveItem(at: sourceRoot, to: installDir)
            try? fm.removeItem(at: tempJava)
            return fm.isExecutableFile(atPath: installDir.appendingPathComponent("bin/java").path)
        }
        
        let result = runCommand("/usr/bin/tar", arguments: [
            tarFlag, archivePath.path,
            "-C", installDir.path,
            "--strip-components=1"
        ])
        
        if result.exitCode != 0 {
            let result2 = runCommand("/usr/bin/tar", arguments: [
                tarFlag, archivePath.path,
                "-C", installDir.path
            ])
            return result2.exitCode == 0
        }
        
        return true
    }
    
    private func installZipArchive(type: RuntimeType, archivePath: URL) -> Bool {
        let fm = FileManager.default
        let installDir = runtimesDir.appendingPathComponent(type.bundleDirName)
        let binDir = installDir.appendingPathComponent("bin")
        try? fm.removeItem(at: installDir)
        try? fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        
        let tempExtract = runtimesDir.appendingPathComponent("zip_tmp_\(UUID().uuidString.prefix(6))")
        try? fm.createDirectory(at: tempExtract, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempExtract) }
        
        let res = runCommand("/usr/bin/unzip", arguments: ["-qo", archivePath.path, "-d", tempExtract.path])
        guard res.exitCode == 0 else { return false }
        
        if type == .bun {
            // Bun extracts inside a subfolder like bun-darwin-aarch64/bun
            if let enumerator = fm.enumerator(at: tempExtract, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "bun" {
                    let dest = binDir.appendingPathComponent("bun")
                    try? fm.moveItem(at: fileURL, to: dest)
                    _ = runCommand("/bin/chmod", arguments: ["+x", dest.path])
                    try? fm.createSymbolicLink(at: binDir.appendingPathComponent("bunx"), withDestinationURL: dest)
                    return fm.isExecutableFile(atPath: dest.path)
                }
            }
            return false
        } else if type == .deno {
            let denoSrc = tempExtract.appendingPathComponent("deno")
            let dest = binDir.appendingPathComponent("deno")
            if fm.fileExists(atPath: denoSrc.path) {
                try? fm.moveItem(at: denoSrc, to: dest)
                _ = runCommand("/bin/chmod", arguments: ["+x", dest.path])
                return fm.isExecutableFile(atPath: dest.path)
            }
            return false
        } else if type == .kotlin {
            let kotlincDir = tempExtract.appendingPathComponent("kotlinc")
            if fm.fileExists(atPath: kotlincDir.path) {
                try? fm.removeItem(at: installDir)
                try? fm.moveItem(at: kotlincDir, to: installDir)
                _ = runCommand("/bin/chmod", arguments: ["-R", "+x", installDir.appendingPathComponent("bin").path])
                return fm.isExecutableFile(atPath: installDir.appendingPathComponent("bin/kotlinc").path)
            }
            return false
        }
        return false
    }
    
    /// Installs portable Zig toolchain and creates drop-in `clang` and `clang++` wrappers
    /// so C and C++ compile and execute out-of-the-box without Xcode Command Line Tools.
    private func installZigClangToolchain(archivePath: URL) -> Bool {
        let fm = FileManager.default
        let zigDir = runtimesDir.appendingPathComponent("zig")
        try? fm.removeItem(at: zigDir)
        try? fm.createDirectory(at: zigDir, withIntermediateDirectories: true)
        
        let res = runCommand("/usr/bin/tar", arguments: [
            "-xJf", archivePath.path,
            "-C", zigDir.path,
            "--strip-components=1"
        ])
        guard res.exitCode == 0 else { return false }
        let zigBin = zigDir.appendingPathComponent("zig").path
        guard fm.isExecutableFile(atPath: zigBin) else { return false }
        _ = runCommand("/usr/bin/xattr", arguments: ["-dr", "com.apple.quarantine", zigDir.path])
        
        let cBinDir = runtimesDir.appendingPathComponent("c/bin")
        let cppBinDir = runtimesDir.appendingPathComponent("cpp/bin")
        try? fm.createDirectory(at: cBinDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: cppBinDir, withIntermediateDirectories: true)
        
        let clangWrapper = cBinDir.appendingPathComponent("clang")
        let gccWrapper = cBinDir.appendingPathComponent("gcc")
        let clangppWrapper = cppBinDir.appendingPathComponent("clang++")
        let gppWrapper = cppBinDir.appendingPathComponent("g++")
        let zigSymlink = cBinDir.appendingPathComponent("zig")
        
        let cScript = """
        #!/bin/sh
        exec "\(zigBin)" cc "$@"
        """
        let cppScript = """
        #!/bin/sh
        exec "\(zigBin)" c++ "$@"
        """
        
        try? cScript.write(to: clangWrapper, atomically: true, encoding: .utf8)
        try? cScript.write(to: gccWrapper, atomically: true, encoding: .utf8)
        try? cppScript.write(to: clangppWrapper, atomically: true, encoding: .utf8)
        try? cppScript.write(to: gppWrapper, atomically: true, encoding: .utf8)
        try? fm.createSymbolicLink(at: zigSymlink, withDestinationURL: URL(fileURLWithPath: zigBin))
        
        _ = runCommand("/bin/chmod", arguments: ["+x", clangWrapper.path, gccWrapper.path, clangppWrapper.path, gppWrapper.path])
        return fm.isExecutableFile(atPath: clangWrapper.path) && fm.isExecutableFile(atPath: clangppWrapper.path)
    }
    
    private func installPkg(type: RuntimeType, pkgPath: URL) -> Bool {
        NSWorkspace.shared.activateFileViewerSelecting([pkgPath])
        DispatchQueue.main.async {
            self.errorMessage = "Please run the .pkg installer that opened. After installation, click Refresh to detect \(type.rawValue)."
        }
        return true
    }
    
    private func installScript(type: RuntimeType, scriptPath: URL) -> Bool {
        _ = runCommand("/bin/chmod", arguments: ["+x", scriptPath.path])
        if type == .dotnet {
            let installDir = runtimesDir.appendingPathComponent("dotnet")
            let binDir = installDir.appendingPathComponent("bin")
            try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
            
            let result = runCommand("/bin/bash", arguments: [
                scriptPath.path,
                "--install-dir", installDir.path
            ])
            if result.exitCode == 0 {
                let dotnetExe = installDir.appendingPathComponent("dotnet")
                let symlinkExe = binDir.appendingPathComponent("dotnet")
                try? FileManager.default.removeItem(at: symlinkExe)
                try? FileManager.default.createSymbolicLink(at: symlinkExe, withDestinationURL: dotnetExe)
                return true
            }
        }
        return false
    }
    
    private func installRustup(rustupPath: URL) -> Bool {
        let fm = FileManager.default
        _ = runCommand("/bin/chmod", arguments: ["+x", rustupPath.path])
        let target = runtimesDir.appendingPathComponent("rust")
        let binDir = target.appendingPathComponent("bin")
        try? fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        
        let process = Process()
        process.executableURL = rustupPath
        process.arguments = ["-y", "--no-modify-path", "--default-toolchain", "stable", "--profile", "minimal"]
        var env = ProcessInfo.processInfo.environment
        env["RUSTUP_HOME"] = target.appendingPathComponent("rustup").path
        env["CARGO_HOME"] = target.appendingPathComponent("cargo").path
        process.environment = env
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                for tool in ["rustc", "cargo", "rustup"] {
                    let src = target.appendingPathComponent("cargo/bin/\(tool)")
                    let dst = binDir.appendingPathComponent(tool)
                    if fm.fileExists(atPath: src.path) {
                        try? fm.removeItem(at: dst)
                        try? fm.createSymbolicLink(at: dst, withDestinationURL: src)
                    }
                }
                return fm.isExecutableFile(atPath: binDir.appendingPathComponent("rustc").path)
            }
        } catch {}
        return false
    }
    
    // MARK: - Helper
    
    struct CommandResult {
        var output: String?
        var error: String?
        var exitCode: Int32
    }
    
    private func runCommand(_ executable: String, arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            return CommandResult(
                output: String(data: outputData, encoding: .utf8),
                error: String(data: errorData, encoding: .utf8),
                exitCode: process.terminationStatus
            )
        } catch {
            return CommandResult(output: nil, error: error.localizedDescription, exitCode: -1)
        }
    }
}

// MARK: - ProcessInfo Extension

extension ProcessInfo {
    var machineArchitecture: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return machine ?? "unknown"
    }
}
