//
//  ProjectManager.swift
//  MicroCode
//
//  Universal Project Build/Run/Debug System
//  Supports: Xcode, Android/Kotlin, Flutter, Java, Ruby, .NET, Go, Rust, Python, Node.js
//

import Foundation
import AppKit

// MARK: - Project Type Detection

enum ProjectType: String, CaseIterable {
    case xcode = "Xcode"
    case android = "Android"
    case flutter = "Flutter"
    case java = "Java"
    case kotlin = "Kotlin"
    case dotnet = ".NET"
    case ruby = "Ruby"
    case python = "Python"
    case nodejs = "Node.js"
    case go = "Go"
    case rust = "Rust"
    case swift = "Swift Package"
    case cmake = "CMake"
    case makefile = "Makefile"
    case php = "PHP WebApp"
    case wasm = "WebAssembly"
    case ardium = "Ardium"
    case unknown = "Unknown"
    
    var icon: String {
        switch self {
        case .xcode: return "hammer.fill"
        case .android: return "cpu"
        case .flutter: return "bird.fill"
        case .java: return "cup.and.saucer.fill"
        case .kotlin: return "k.square.fill"
        case .dotnet: return "cube.box.fill"
        case .ruby: return "diamond.fill"
        case .python: return "brain"
        case .nodejs: return "network"
        case .go: return "g.square.fill"
        case .rust: return "gearshape.fill"
        case .swift: return "swift"
        case .cmake: return "wrench.fill"
        case .makefile: return "doc.text.fill"
        case .php: return "elephant.fill"
        case .wasm: return "square.fill"
        case .ardium: return "a.circle.fill"
        case .unknown: return "questionmark.folder"
        }
    }
    
    var color: NSColor {
        switch self {
        case .xcode: return .systemBlue
        case .android: return .systemGreen
        case .flutter: return .systemCyan
        case .java: return .systemOrange
        case .kotlin: return .systemPurple
        case .dotnet: return .systemIndigo
        case .ruby: return .systemRed
        case .python: return .systemYellow
        case .nodejs: return .systemGreen
        case .go: return .systemTeal
        case .rust: return .systemOrange
        case .swift: return .systemOrange
        case .cmake: return .systemGray
        case .makefile: return .systemGray
        case .php: return .systemIndigo
        case .wasm: return .systemPurple
        case .ardium: return .systemTeal
        case .unknown: return .secondaryLabelColor
        }
    }
    
    var displayName: String {
        return rawValue
    }
}

// MARK: - Build Configuration

struct BuildConfiguration: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let isDebug: Bool
    
    static let debug = BuildConfiguration(name: "Debug", isDebug: true)
    static let release = BuildConfiguration(name: "Release", isDebug: false)
}

// MARK: - Project Actions

enum ProjectAction: String, CaseIterable {
    case build = "Build"
    case run = "Run"
    case debug = "Debug"
    case test = "Test"
    case clean = "Clean"
    case install = "Install Dependencies"
    
    var icon: String {
        switch self {
        case .build: return "hammer.fill"
        case .run: return "play.fill"
        case .debug: return "ant.fill"
        case .test: return "checkmark.circle.fill"
        case .clean: return "trash.fill"
        case .install: return "arrow.down.circle.fill"
        }
    }
}

// MARK: - Project Manager

class ProjectManager: ObservableObject {
    static let shared = ProjectManager()
    
    @Published var detectedProjectType: ProjectType = .unknown
    @Published var isRunning: Bool = false
    @Published var currentProcess: Process?
    @Published var output: String = ""
    @Published var buildConfiguration: BuildConfiguration = .debug
    @Published var buildParser = XcodeBuildParser()
    
    private let schemeCacheLock = NSLock()
    private var xcodeSchemeCache: [String: String] = [:]
    private static let gradleMemorySafeFlags = [
        "--no-daemon",
        "-Dorg.gradle.jvmargs=-Xmx1536m -XX:MaxMetaspaceSize=512m"
    ]
    
    private init() {}
    
    // MARK: - Project Detection
    
    func detectProjectType(at path: URL) -> ProjectType {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: path.path, isDirectory: &isDir), !isDir.boolValue {
            let ext = path.pathExtension.lowercased()
            if ext == "xcodeproj" || ext == "xcworkspace" { return .xcode }
        }
        if path.pathExtension.lowercased() == "xcodeproj" || path.pathExtension.lowercased() == "xcworkspace" {
            return .xcode
        }

        let contents = (try? fileManager.contentsOfDirectory(atPath: path.path)) ?? []
        let lowerSet = Set(contents.map { $0.lowercased() })

        // 1. Xcode (.xcworkspace / .xcodeproj) — validate container so broken stubs gracefully fall back to Package.swift
        if resolveXcodeContainerPath(in: path.path, contents: contents) != nil {
            return .xcode
        }

        // 2. Flutter
        if lowerSet.contains("pubspec.yaml") && (lowerSet.contains("lib") || lowerSet.contains("android") || lowerSet.contains("ios")) {
            return .flutter
        }

        // 3. Android vs Kotlin Gradle
        if lowerSet.contains("build.gradle") || lowerSet.contains("build.gradle.kts") {
            let hasSettings = lowerSet.contains("settings.gradle") || lowerSet.contains("settings.gradle.kts")
            let hasAndroidAppManifest = fileManager.fileExists(atPath: path.appendingPathComponent("app/src/main/AndroidManifest.xml").path)
                || fileManager.fileExists(atPath: path.appendingPathComponent("src/main/AndroidManifest.xml").path)
            let hasAndroidDirOrMarker: Bool = {
                if hasAndroidAppManifest || lowerSet.contains("local.properties") { return true }
                for gradleFile in ["build.gradle", "build.gradle.kts", "app/build.gradle", "app/build.gradle.kts"] {
                    if let text = try? String(contentsOf: path.appendingPathComponent(gradleFile), encoding: .utf8),
                       text.contains("com.android") || text.contains("android {") || text.contains("libs.plugins.android") {
                        return true
                    }
                }
                return false
            }()
            if hasAndroidDirOrMarker || (hasSettings && lowerSet.contains("app")) {
                return .android
            }
            if lowerSet.contains("build.gradle.kts") && !lowerSet.contains("android") {
                return .kotlin
            }
            if hasSettings {
                return .android
            }
        }

        // 4. Swift Package (coexists gracefully behind valid .xcodeproj/.xcworkspace)
        if lowerSet.contains("package.swift") {
            return .swift
        }

        // 5. .NET
        if contents.contains(where: {
            let l = $0.lowercased()
            return l.hasSuffix(".sln") || l.hasSuffix(".csproj") || l.hasSuffix(".fsproj")
        }) {
            return .dotnet
        }

        // 6. Rust / Go / Java
        if lowerSet.contains("cargo.toml") { return .rust }
        if lowerSet.contains("go.mod") { return .go }
        if lowerSet.contains("pom.xml") { return .java }

        // 7. Node.js / Python / Ruby / PHP
        if lowerSet.contains("package.json") { return .nodejs }
        if lowerSet.contains("pyproject.toml") || lowerSet.contains("requirements.txt") || lowerSet.contains("setup.py") {
            return .python
        }
        if lowerSet.contains("gemfile") || lowerSet.contains("rakefile") { return .ruby }
        if lowerSet.contains("composer.json") || lowerSet.contains("index.php") { return .php }

        // 8. WASM / Ardium / CMake / Makefile
        if lowerSet.contains("wasm-pack.toml") || contents.contains(where: { $0.lowercased().hasSuffix(".wasm") }) {
            return .wasm
        }
        if lowerSet.contains("ardium.json") || contents.contains(where: { $0.lowercased().hasSuffix(".ar") }) {
            return .ardium
        }
        if lowerSet.contains("cmakelists.txt") { return .cmake }
        if lowerSet.contains("makefile") { return .makefile }

        // Fallback single-script Python root detection
        if lowerSet.contains("main.py") || lowerSet.contains("app.py") || lowerSet.contains("run.py") || lowerSet.contains("manage.py") {
            return .python
        }

        return .unknown
    }
    
    // MARK: - Build Commands
    
    func getBuildCommand(for projectType: ProjectType, action: ProjectAction, config: BuildConfiguration, projectPath: String) -> (executable: String, arguments: [String])? {
        let isDebug = config.isDebug
        
        switch projectType {
        case .xcode:
            let workspaceRootPath: String
            let resolvedContainer: String?
            if projectPath.hasSuffix(".xcodeproj") || projectPath.hasSuffix(".xcworkspace") {
                workspaceRootPath = (projectPath as NSString).deletingLastPathComponent
                resolvedContainer = projectPath
            } else {
                workspaceRootPath = projectPath
                let sub = (try? FileManager.default.contentsOfDirectory(atPath: projectPath)) ?? []
                resolvedContainer = resolveXcodeContainerPath(in: projectPath, contents: sub)
            }

            guard let actualProjectPath = resolvedContainer else {
                // Graceful Package.swift coexistence fallback if no Xcode container is present
                let pkgSwift = (workspaceRootPath as NSString).appendingPathComponent("Package.swift")
                if FileManager.default.fileExists(atPath: pkgSwift) {
                    return getBuildCommand(for: .swift, action: action, config: config, projectPath: workspaceRootPath)
                }
                return nil
            }

            let schemeName = resolveXcodeScheme(containerPath: actualProjectPath, workspaceRootPath: workspaceRootPath)
            let isWorkspace = actualProjectPath.hasSuffix(".xcworkspace")
            let projFlag = isWorkspace ? "-workspace" : "-project"
            
            switch action {
            case .build:
                return ("xcodebuild", ["-configuration", isDebug ? "Debug" : "Release", projFlag, actualProjectPath, "-scheme", schemeName])
            case .run:
                return ("xcodebuild", ["-configuration", isDebug ? "Debug" : "Release", projFlag, actualProjectPath, "-scheme", schemeName, "build"])
            case .clean:
                return ("xcodebuild", ["clean", projFlag, actualProjectPath, "-scheme", schemeName])
            case .test:
                return ("xcodebuild", ["test", projFlag, actualProjectPath, "-scheme", schemeName])
            default:
                return nil
            }
            
        case .android:
            let gradleExec = resolveGradleExecutable(at: projectPath)
            switch action {
            case .build:
                return (gradleExec, [isDebug ? "assembleDebug" : "assembleRelease"] + Self.gradleMemorySafeFlags)
            case .run:
                return (gradleExec, ["installDebug"] + Self.gradleMemorySafeFlags)
            case .clean:
                return (gradleExec, ["clean"] + Self.gradleMemorySafeFlags)
            case .test:
                return (gradleExec, ["test"] + Self.gradleMemorySafeFlags)
            default:
                return nil
            }
            
        case .flutter:
            switch action {
            case .build:
                return ("flutter", ["build", "apk", isDebug ? "--debug" : "--release"])
            case .run:
                return ("flutter", ["run", isDebug ? "--debug" : "--release"])
            case .clean:
                return ("flutter", ["clean"])
            case .test:
                return ("flutter", ["test"])
            case .install:
                return ("flutter", ["pub", "get"])
            default:
                return nil
            }
            
        case .java:
            switch action {
            case .build:
                return ("mvn", ["compile"])
            case .run:
                return ("mvn", ["exec:java"])
            case .clean:
                return ("mvn", ["clean"])
            case .test:
                return ("mvn", ["test"])
            case .install:
                return ("mvn", ["install"])
            default:
                return nil
            }
            
        case .kotlin:
            let gradleExec = resolveGradleExecutable(at: projectPath)
            switch action {
            case .build:
                return (gradleExec, ["build"] + Self.gradleMemorySafeFlags)
            case .run:
                return (gradleExec, ["run"] + Self.gradleMemorySafeFlags)
            case .clean:
                return (gradleExec, ["clean"] + Self.gradleMemorySafeFlags)
            case .test:
                return (gradleExec, ["test"] + Self.gradleMemorySafeFlags)
            default:
                return nil
            }
            
        case .dotnet:
            switch action {
            case .build:
                return ("dotnet", ["build", "-c", isDebug ? "Debug" : "Release"])
            case .run:
                return ("dotnet", ["run", "-c", isDebug ? "Debug" : "Release"])
            case .debug:
                return ("dotnet", ["run", "-c", "Debug", "--", "--debug"])
            case .clean:
                return ("dotnet", ["clean"])
            case .test:
                return ("dotnet", ["test"])
            case .install:
                return ("dotnet", ["restore"])
            }
            
        case .ruby:
            switch action {
            case .run:
                return ("ruby", ["main.rb"])
            case .test:
                return ("rake", ["test"])
            case .install:
                return ("bundle", ["install"])
            default:
                return nil
            }
            
        case .python:
            switch action {
            case .run:
                return ("python3", [resolvePythonEntryScript(at: projectPath)])
            case .test:
                return ("python3", ["-m", "pytest"])
            case .install:
                let reqPath = (projectPath as NSString).appendingPathComponent("requirements.txt")
                if FileManager.default.fileExists(atPath: reqPath) {
                    return ("pip3", ["install", "-r", "requirements.txt"])
                }
                return ("pip3", ["install", "-e", "."])
            default:
                return nil
            }
            
        case .nodejs:
            switch action {
            case .build:
                return ("npm", ["run", "build"])
            case .run:
                // Check for dev script first for web frameworks
                let fm = FileManager.default
                let pkgPath = (projectPath as NSString).appendingPathComponent("package.json")
                if let data = fm.contents(atPath: pkgPath),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let scripts = json["scripts"] as? [String: String] {
                    if scripts["dev"] != nil {
                        return ("npm", ["run", "dev"])
                    }
                }
                return ("npm", ["start"])
            case .test:
                return ("npm", ["test"])
            case .install:
                return ("npm", ["install"])
            default:
                return nil
            }
            
        case .php:
            switch action {
            case .run:
                return ("php", ["-S", "localhost:8000"])
            case .install:
                return ("composer", ["install"])
            case .test:
                return ("./vendor/bin/phpunit", [])
            default:
                return nil
            }
            
        case .wasm:
            switch action {
            case .build:
                return ("wasm-pack", ["build"])
            case .run:
                return ("wasm-pack", ["serve"])
            case .test:
                return ("wasm-pack", ["test"])
            default:
                return nil
            }
            
        case .go:
            switch action {
            case .build:
                return ("go", ["build", "./..."])
            case .run:
                return ("go", ["run", "."])
            case .test:
                return ("go", ["test", "./..."])
            case .clean:
                return ("go", ["clean"])
            default:
                return nil
            }
            
        case .rust:
            switch action {
            case .build:
                return ("cargo", ["build", isDebug ? "" : "--release"].filter { !$0.isEmpty })
            case .run:
                return ("cargo", ["run", isDebug ? "" : "--release"].filter { !$0.isEmpty })
            case .test:
                return ("cargo", ["test"])
            case .clean:
                return ("cargo", ["clean"])
            default:
                return nil
            }
            
        case .swift:
            switch action {
            case .build:
                return ("swift", ["build", "-c", isDebug ? "debug" : "release"])
            case .run:
                return ("swift", ["run"])
            case .test:
                return ("swift", ["test"])
            case .clean:
                return ("swift", ["package", "clean"])
            default:
                return nil
            }
            
        case .cmake:
            switch action {
            case .build:
                return ("cmake", ["--build", "build", "--config", isDebug ? "Debug" : "Release"])
            case .clean:
                return ("cmake", ["--build", "build", "--target", "clean"])
            default:
                return nil
            }
            
        case .makefile:
            switch action {
            case .build:
                return ("make", [])
            case .clean:
                return ("make", ["clean"])
            case .run:
                return ("make", ["run"])
            default:
                return nil
            }
            
        case .ardium:
            let arCompiler = resolveArdiumExecutable()
            let arEntry = resolveArdiumEntryFile(at: projectPath)
            switch action {
            case .build:
                // Use default main.ar if present, or fallback to first .ar file in root
                return (arCompiler, ["build", arEntry])
            case .run:
                return (arCompiler, ["run", arEntry])
            case .test:
                return (arCompiler, ["test", "."])
            default:
                return nil
            }
            
        case .unknown:
            return nil
        }
    }
    
    // MARK: - Execute Action

    /// Build products and package caches are stored on the external SSD when
    /// it is mounted. CODETUNER_BUILD_ROOT can override the default location.
    private func externalBuildRoot(for projectPath: URL) -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let defaultRoot = "/Volumes/MAC/CodeTunerBuild"
        let rootPath: String

        if let configuredRoot = environment["CODETUNER_BUILD_ROOT"], !configuredRoot.isEmpty {
            rootPath = configuredRoot
        } else if FileManager.default.fileExists(atPath: "/Volumes/MAC") {
            rootPath = defaultRoot
        } else {
            return nil
        }

        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let projectName = projectPath.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "-")

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("cargo-home"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("cargo-target"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("rustup-home"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("swiftpm"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("derived-data"), withIntermediateDirectories: true)
            return root.appendingPathComponent(projectName, isDirectory: true)
        } catch {
            return nil
        }
    }
    
    func execute(
        action: ProjectAction,
        projectPath: URL,
        onOutput: ((String) -> Void)? = nil,
        completion: @escaping (Bool, String) -> Void
    ) {
        guard !isRunning else {
            completion(false, "A process is already running")
            return
        }
        
        let projectType = detectProjectType(at: projectPath)
        guard let baseCommand = getBuildCommand(for: projectType, action: action, config: buildConfiguration, projectPath: projectPath.path) else {
            completion(false, "Action '\(action.rawValue)' not supported for \(projectType.rawValue) projects")
            return
        }

        var command = baseCommand
        let buildRoot = externalBuildRoot(for: projectPath)
        if let buildRoot {
            if command.executable == "xcodebuild" {
                command.arguments += ["-derivedDataPath", buildRoot.appendingPathComponent("derived-data").path]
            } else if command.executable == "swift" {
                command.arguments += ["--scratch-path", buildRoot.appendingPathComponent("swiftpm").path]
            }
        }
        
        if projectType == .xcode {
            buildParser.clear()
        }
        
        let developerPath = buildDeveloperPath()
        let resolvedExecutable = findExecutable(command.executable, projectPath: projectPath, developerPath: developerPath)

        isRunning = true
        let initialBanner = "[\(projectType.rawValue)] \(action.rawValue)...\n$ \(command.executable) \(command.arguments.joined(separator: " "))\n\n"
        output = initialBanner
        onOutput?(initialBanner)
        
        let process = Process()
        process.currentDirectoryURL = projectPath
        process.executableURL = URL(fileURLWithPath: resolvedExecutable)
        process.arguments = command.arguments

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = developerPath
        if let buildRoot {
            environment["CARGO_HOME"] = buildRoot.deletingLastPathComponent().appendingPathComponent("cargo-home").path
            environment["CARGO_TARGET_DIR"] = buildRoot.deletingLastPathComponent().appendingPathComponent("cargo-target").path
            environment["RUSTUP_HOME"] = buildRoot.deletingLastPathComponent().appendingPathComponent("rustup-home").path
        }
        process.environment = environment
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        let readHandle = pipe.fileHandleForReading
        var lineBuffer = ""
        readHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            guard !text.isEmpty else { return }
            DispatchQueue.main.async {
                self?.output += text
                onOutput?(text)
                
                if projectType == .xcode {
                    lineBuffer += text
                    var lines = lineBuffer.components(separatedBy: "\n")
                    if let last = lines.popLast() {
                        lineBuffer = last
                    } else {
                        lineBuffer = ""
                    }
                    for line in lines {
                        self?.buildParser.parseLine(line)
                    }
                }
            }
        }
        
        process.terminationHandler = { [weak self] proc in
            readHandle.readabilityHandler = nil
            let trailingData = readHandle.readDataToEndOfFile()
            let trailingText = trailingData.isEmpty ? "" : String(decoding: trailingData, as: UTF8.self)
            DispatchQueue.main.async {
                if !trailingText.isEmpty {
                    self?.output += trailingText
                    onOutput?(trailingText)
                    if projectType == .xcode {
                        lineBuffer += trailingText
                        var lines = lineBuffer.components(separatedBy: "\n")
                        if let last = lines.popLast() {
                            lineBuffer = last
                        } else {
                            lineBuffer = ""
                        }
                        for line in lines {
                            self?.buildParser.parseLine(line)
                        }
                    }
                }

                self?.isRunning = false
                self?.currentProcess = nil
                
                if projectType == .xcode && !lineBuffer.isEmpty {
                    self?.buildParser.parseLine(lineBuffer)
                    lineBuffer = ""
                }
                
                let success = proc.terminationStatus == 0
                let summaryLine = "\n\(success ? "✅" : "❌") \(action.rawValue) \(success ? "succeeded" : "failed") (exit code: \(proc.terminationStatus))\n"
                self?.output += summaryLine
                onOutput?(summaryLine)
                completion(success, self?.output ?? "")
            }
        }
        
        do {
            try process.run()
            currentProcess = process
        } catch {
            readHandle.readabilityHandler = nil
            isRunning = false
            let failLine = "❌ Failed to start '\(command.executable)': \(error.localizedDescription)\n"
            output += failLine
            onOutput?(failLine)
            completion(false, output)
        }
    }
    
    func stopCurrentProcess() {
        currentProcess?.terminate()
        currentProcess = nil
        isRunning = false
        output += "\n⚠️ Process terminated by user\n"
    }
    
    // MARK: - Helpers

    private func buildDeveloperPath() -> String {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        var candidateDirs: [String] = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "\(home)/.cargo/bin",
            "\(home)/go/bin",
            "\(home)/.bun/bin",
            "\(home)/.dotnet",
            "\(home)/.local/bin",
            "\(home)/Library/Android/sdk/platform-tools",
            "\(home)/Library/Android/sdk/cmdline-tools/latest/bin",
            "\(home)/development/flutter/bin",
            "\(home)/flutter/bin",
            "\(home)/.pub-cache/bin",
            "\(home)/.ardium/bin"
        ]

        // Include newest ~/.nvm/versions/node/*/bin directory if present
        let nvmVersionsDir = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmVersionsDir) {
            let sortedNewestFirst = versions.sorted {
                $0.localizedStandardCompare($1) == .orderedDescending
            }
            if let newest = sortedNewestFirst.first(where: {
                fm.fileExists(atPath: "\(nvmVersionsDir)/\($0)/bin")
            }) {
                candidateDirs.insert("\(nvmVersionsDir)/\(newest)/bin", at: 3)
            }
        }

        candidateDirs.append(contentsOf: ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])

        if let existingPath = ProcessInfo.processInfo.environment["PATH"], !existingPath.isEmpty {
            for entry in existingPath.split(separator: ":").map(String.init) where !entry.isEmpty {
                candidateDirs.append(entry)
            }
        }

        var seen = Set<String>()
        var ordered: [String] = []
        for dir in candidateDirs where !dir.isEmpty {
            if seen.insert(dir).inserted {
                ordered.append(dir)
            }
        }
        return ordered.joined(separator: ":")
    }
    
    private func findExecutable(_ name: String, projectPath: URL? = nil, developerPath: String? = nil) -> String {
        let fm = FileManager.default

        // 1. Project-relative paths such as ./gradlew or ./vendor/bin/phpunit
        if name.hasPrefix("./") || (!name.hasPrefix("/") && name.contains("/")) {
            if let projectPath {
                let relative = name.hasPrefix("./") ? String(name.dropFirst(2)) : name
                let resolved = projectPath.appendingPathComponent(relative).standardizedFileURL.path
                if fm.fileExists(atPath: resolved) {
                    if !fm.isExecutableFile(atPath: resolved) && relative == "gradlew" {
                        ensureExecutablePermission(at: resolved)
                    }
                    return resolved
                }
            }
            return name
        }

        // 2. Explicit absolute path
        if name.hasPrefix("/") {
            if fm.fileExists(atPath: name) {
                return name
            }
            // Do not fall back from Ardium compiler to /usr/bin/ar static archiver
            if name.hasSuffix("/ar") {
                return resolveArdiumExecutable()
            }
        }

        // 3. Search across enriched developer PATH
        let pathString = developerPath ?? buildDeveloperPath()
        for dir in pathString.split(separator: ":").map(String.init) where !dir.isEmpty {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        for dir in pathString.split(separator: ":").map(String.init) where !dir.isEmpty {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return name
    }

    private func ensureExecutablePermission(at path: String) {
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let perms = attrs[.posixPermissions] as? NSNumber {
            let updated = perms.uint16Value | 0o755
            try? fm.setAttributes([.posixPermissions: NSNumber(value: updated)], ofItemAtPath: path)
        } else {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
    }

    private func resolveGradleExecutable(at projectPath: String) -> String {
        let fm = FileManager.default
        let gradlewPath = (projectPath as NSString).appendingPathComponent("gradlew")
        if fm.fileExists(atPath: gradlewPath) {
            if !fm.isExecutableFile(atPath: gradlewPath) {
                ensureExecutablePermission(at: gradlewPath)
            }
            return "./gradlew"
        }
        return "gradle"
    }

    private func resolvePythonEntryScript(at projectPath: String) -> String {
        let fm = FileManager.default
        for preferred in ["main.py", "app.py", "run.py", "manage.py"] {
            let candidate = (projectPath as NSString).appendingPathComponent(preferred)
            if fm.fileExists(atPath: candidate) {
                return preferred
            }
        }
        let contents = (try? fm.contentsOfDirectory(atPath: projectPath)) ?? []
        let pyFiles = contents.filter { $0.lowercased().hasSuffix(".py") }.sorted()
        let ignored = Set(["setup.py", "conftest.py", "__init__.py"])
        if let firstAppPy = pyFiles.first(where: { !ignored.contains($0.lowercased()) }) {
            return firstAppPy
        }
        return pyFiles.first ?? "main.py"
    }

    private func resolveArdiumExecutable() -> String {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/ar",
            "/usr/local/bin/ar",
            "\(home)/.ardium/bin/ar"
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return "/opt/homebrew/bin/ar"
    }

    private func resolveArdiumEntryFile(at projectPath: String) -> String {
        let fm = FileManager.default
        let mainPath = (projectPath as NSString).appendingPathComponent("main.ar")
        if fm.fileExists(atPath: mainPath) {
            return "main.ar"
        }
        let contents = (try? fm.contentsOfDirectory(atPath: projectPath)) ?? []
        if let firstAr = contents.filter({ $0.lowercased().hasSuffix(".ar") }).sorted().first {
            return firstAr
        }
        return "main.ar"
    }

    private func resolveXcodeContainerPath(in directoryPath: String, contents: [String]) -> String? {
        let fm = FileManager.default
        let folderName = URL(fileURLWithPath: directoryPath).lastPathComponent.lowercased()

        let workspaces = contents
            .filter { $0.lowercased().hasSuffix(".xcworkspace") && $0.lowercased() != "project.xcworkspace" }
            .filter {
                let full = (directoryPath as NSString).appendingPathComponent($0)
                return fm.fileExists(atPath: (full as NSString).appendingPathComponent("contents.xcworkspacedata"))
                    || fm.fileExists(atPath: full)
            }
            .sorted { lhs, rhs in
                let lMatch = URL(fileURLWithPath: lhs).deletingPathExtension().lastPathComponent.lowercased() == folderName
                let rMatch = URL(fileURLWithPath: rhs).deletingPathExtension().lastPathComponent.lowercased() == folderName
                if lMatch != rMatch { return lMatch }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }

        if let ws = workspaces.first {
            return (directoryPath as NSString).appendingPathComponent(ws)
        }

        let projects = contents
            .filter { $0.lowercased().hasSuffix(".xcodeproj") }
            .filter {
                let full = (directoryPath as NSString).appendingPathComponent($0)
                return fm.fileExists(atPath: (full as NSString).appendingPathComponent("project.pbxproj"))
            }
            .sorted { lhs, rhs in
                let lMatch = URL(fileURLWithPath: lhs).deletingPathExtension().lastPathComponent.lowercased() == folderName
                let rMatch = URL(fileURLWithPath: rhs).deletingPathExtension().lastPathComponent.lowercased() == folderName
                if lMatch != rMatch { return lMatch }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }

        if let proj = projects.first {
            return (directoryPath as NSString).appendingPathComponent(proj)
        }

        return nil
    }

    private func resolveXcodeScheme(containerPath: String, workspaceRootPath: String) -> String {
        schemeCacheLock.lock()
        if let cached = xcodeSchemeCache[containerPath] {
            schemeCacheLock.unlock()
            return cached
        }
        schemeCacheLock.unlock()

        let containerName = URL(fileURLWithPath: containerPath).deletingPathExtension().lastPathComponent
        let folderName = URL(fileURLWithPath: workspaceRootPath).lastPathComponent

        // 1. Fast disk scan of shared & user .xcscheme files inside the container
        var diskSchemes = collectSchemeFiles(inContainer: containerPath)

        // If container is an .xcworkspace without schemes directly inside it, scan sibling .xcodeproj containers
        if diskSchemes.isEmpty && containerPath.lowercased().hasSuffix(".xcworkspace") {
            let siblings = (try? FileManager.default.contentsOfDirectory(atPath: workspaceRootPath)) ?? []
            for item in siblings.sorted() where item.lowercased().hasSuffix(".xcodeproj") {
                let projPath = (workspaceRootPath as NSString).appendingPathComponent(item)
                diskSchemes.append(contentsOf: collectSchemeFiles(inContainer: projPath))
            }
        }

        if let chosen = selectPreferredScheme(from: diskSchemes, containerName: containerName, folderName: folderName) {
            cacheXcodeScheme(chosen, for: containerPath)
            return chosen
        }

        // 2. Query `xcodebuild -list -json` with a short timeout for Xcode auto-generated schemes
        if let listed = queryXcodebuildSchemes(containerPath: containerPath, workspaceRootPath: workspaceRootPath),
           let chosen = selectPreferredScheme(from: listed, containerName: containerName, folderName: folderName) {
            cacheXcodeScheme(chosen, for: containerPath)
            return chosen
        }

        // 3. Parse PBXNativeTarget names from project.pbxproj if available
        let pbxprojCandidates: [String] = {
            if containerPath.lowercased().hasSuffix(".xcodeproj") {
                return [(containerPath as NSString).appendingPathComponent("project.pbxproj")]
            }
            let siblings = (try? FileManager.default.contentsOfDirectory(atPath: workspaceRootPath)) ?? []
            return siblings
                .filter { $0.lowercased().hasSuffix(".xcodeproj") }
                .map { ((workspaceRootPath as NSString).appendingPathComponent($0) as NSString).appendingPathComponent("project.pbxproj") }
        }()

        for pbxPath in pbxprojCandidates {
            if let text = try? String(contentsOfFile: pbxPath, encoding: .utf8) {
                let targets = parsePBXNativeTargets(from: text)
                if let chosen = selectPreferredScheme(from: targets, containerName: containerName, folderName: folderName) {
                    cacheXcodeScheme(chosen, for: containerPath)
                    return chosen
                }
            }
        }

        return containerName
    }

    private func cacheXcodeScheme(_ scheme: String, for containerPath: String) {
        schemeCacheLock.lock()
        xcodeSchemeCache[containerPath] = scheme
        schemeCacheLock.unlock()
    }

    private func collectSchemeFiles(inContainer containerPath: String) -> [String] {
        let fm = FileManager.default
        var found: [String] = []

        // Shared schemes
        let sharedDir = (containerPath as NSString).appendingPathComponent("xcshareddata/xcschemes")
        if let items = try? fm.contentsOfDirectory(atPath: sharedDir) {
            for item in items.sorted() where item.hasSuffix(".xcscheme") {
                found.append(URL(fileURLWithPath: item).deletingPathExtension().lastPathComponent)
            }
        }

        // User-specific schemes
        let userDataDir = (containerPath as NSString).appendingPathComponent("xcuserdata")
        if let userDirs = try? fm.contentsOfDirectory(atPath: userDataDir) {
            for userDir in userDirs.sorted() where userDir.hasSuffix(".xcuserdatad") {
                let schemesDir = ((userDataDir as NSString).appendingPathComponent(userDir) as NSString)
                    .appendingPathComponent("xcschemes")
                if let items = try? fm.contentsOfDirectory(atPath: schemesDir) {
                    for item in items.sorted() where item.hasSuffix(".xcscheme") {
                        let name = URL(fileURLWithPath: item).deletingPathExtension().lastPathComponent
                        if !found.contains(name) {
                            found.append(name)
                        }
                    }
                }
            }
        }

        return found
    }

    private func selectPreferredScheme(from candidates: [String], containerName: String, folderName: String) -> String? {
        let cleaned = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }

        let nonPods = cleaned.filter { !$0.hasPrefix("Pods-") && $0 != "Pods" }
        let pool = nonPods.isEmpty ? cleaned : nonPods
        let nonTests = pool.filter {
            let lower = $0.lowercased()
            return !lower.hasSuffix("tests") && !lower.hasSuffix("uitests")
        }
        let primaryPool = nonTests.isEmpty ? pool : nonTests

        if let exactContainer = primaryPool.first(where: { $0.caseInsensitiveCompare(containerName) == .orderedSame }) {
            return exactContainer
        }
        if let exactFolder = primaryPool.first(where: { $0.caseInsensitiveCompare(folderName) == .orderedSame }) {
            return exactFolder
        }
        return primaryPool.first
    }

    private func queryXcodebuildSchemes(containerPath: String, workspaceRootPath: String) -> [String]? {
        let xcodebuildPath = "/usr/bin/xcodebuild"
        guard FileManager.default.isExecutableFile(atPath: xcodebuildPath) else { return nil }

        let isWorkspace = containerPath.lowercased().hasSuffix(".xcworkspace")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: xcodebuildPath)
        proc.arguments = [isWorkspace ? "-workspace" : "-project", containerPath, "-list", "-json"]
        proc.currentDirectoryURL = URL(fileURLWithPath: workspaceRootPath)

        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        let done = DispatchSemaphore(value: 0)
        var collectedData = Data()

        DispatchQueue.global(qos: .userInitiated).async {
            collectedData = outPipe.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }

        do {
            try proc.run()
        } catch {
            return nil
        }

        let waitResult = done.wait(timeout: .now() + 3.5)
        if waitResult == .timedOut {
            if proc.isRunning { proc.terminate() }
            return nil
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: collectedData) as? [String: Any] else {
            return nil
        }

        if let ws = json["workspace"] as? [String: Any],
           let schemes = ws["schemes"] as? [String], !schemes.isEmpty {
            return schemes
        }
        if let proj = json["project"] as? [String: Any] {
            if let schemes = proj["schemes"] as? [String], !schemes.isEmpty {
                return schemes
            }
            if let targets = proj["targets"] as? [String], !targets.isEmpty {
                return targets
            }
        }
        return nil
    }

    private func parsePBXNativeTargets(from pbxprojText: String) -> [String] {
        let pattern = #"isa\s*=\s*PBXNativeTarget;[^}]*?\bname\s*=\s*"?([^";\r\n]+)"?\s*;"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsRange = NSRange(pbxprojText.startIndex..<pbxprojText.endIndex, in: pbxprojText)
        var results: [String] = []
        for match in regex.matches(in: pbxprojText, options: [], range: nsRange) {
            if let range = Range(match.range(at: 1), in: pbxprojText) {
                let targetName = String(pbxprojText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !targetName.isEmpty && !results.contains(targetName) {
                    results.append(targetName)
                }
            }
        }
        return results
    }
}
