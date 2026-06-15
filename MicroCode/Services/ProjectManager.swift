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
    
    private init() {}
    
    // MARK: - Project Detection
    
    func detectProjectType(at path: URL) -> ProjectType {
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(atPath: path.path)) ?? []
        
        // Check for specific project files
        for file in contents {
            let lowercased = file.lowercased()
            
            // Xcode
            if lowercased.hasSuffix(".xcodeproj") || lowercased.hasSuffix(".xcworkspace") {
                return .xcode
            }
            
            // Android
            if lowercased == "build.gradle" || lowercased == "build.gradle.kts" {
                if contents.contains("settings.gradle") || contents.contains("settings.gradle.kts") {
                    return .android
                }
            }
            
            // Flutter
            if lowercased == "pubspec.yaml" {
                if contents.contains("lib") || contents.contains("android") || contents.contains("ios") {
                    return .flutter
                }
            }
            
            // .NET
            if lowercased.hasSuffix(".csproj") || lowercased.hasSuffix(".fsproj") || lowercased.hasSuffix(".sln") {
                return .dotnet
            }
            
            // Java (Maven or standalone)
            if lowercased == "pom.xml" {
                return .java
            }
            
            // Kotlin
            if lowercased == "build.gradle.kts" && !contents.contains("android") {
                return .kotlin
            }
            
            // Ruby
            if lowercased == "gemfile" || lowercased == "rakefile" {
                return .ruby
            }
            
            // Python
            if lowercased == "requirements.txt" || lowercased == "setup.py" || lowercased == "pyproject.toml" {
                return .python
            }
            
            // Node.js
            if lowercased == "package.json" {
                return .nodejs
            }
            
            // Go
            if lowercased == "go.mod" {
                return .go
            }
            
            // Rust
            if lowercased == "cargo.toml" {
                return .rust
            }
            
            // Swift Package
            if lowercased == "package.swift" {
                return .swift
            }
            
            // CMake
            if lowercased == "cmakelists.txt" {
                return .cmake
            }
            
            // Makefile
            if lowercased == "makefile" {
                return .makefile
            }
            
            // PHP
            if lowercased == "composer.json" || lowercased == "index.php" {
                return .php
            }
            
            // WASM
            if lowercased.hasSuffix(".wasm") || lowercased == "wasm-pack.toml" {
                return .wasm
            }
            
            // Ardium
            if lowercased.hasSuffix(".ar") || lowercased == "ardium.json" {
                return .ardium
            }
        }
        
        return .unknown
    }
    
    // MARK: - Build Commands
    
    func getBuildCommand(for projectType: ProjectType, action: ProjectAction, config: BuildConfiguration, projectPath: String) -> (executable: String, arguments: [String])? {
        let isDebug = config.isDebug
        
        switch projectType {
        case .xcode:
            switch action {
            case .build:
                return ("xcodebuild", ["-configuration", isDebug ? "Debug" : "Release", "-project", projectPath])
            case .run:
                return ("xcodebuild", ["-configuration", isDebug ? "Debug" : "Release", "-project", projectPath, "build"])
            case .clean:
                return ("xcodebuild", ["clean", "-project", projectPath])
            case .test:
                return ("xcodebuild", ["test", "-project", projectPath])
            default:
                return nil
            }
            
        case .android:
            switch action {
            case .build:
                return ("./gradlew", [isDebug ? "assembleDebug" : "assembleRelease"])
            case .run:
                return ("./gradlew", ["installDebug"])
            case .clean:
                return ("./gradlew", ["clean"])
            case .test:
                return ("./gradlew", ["test"])
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
            switch action {
            case .build:
                return ("./gradlew", ["build"])
            case .run:
                return ("./gradlew", ["run"])
            case .clean:
                return ("./gradlew", ["clean"])
            case .test:
                return ("./gradlew", ["test"])
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
                return ("python3", ["main.py"])
            case .test:
                return ("python3", ["-m", "pytest"])
            case .install:
                return ("pip3", ["install", "-r", "requirements.txt"])
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
            switch action {
            case .build:
                // Use default main.ar if not specified, or just build the directory
                return ("/usr/local/bin/ar", ["build", "main.ar"])
            case .run:
                return ("/usr/local/bin/ar", ["run", "main.ar"])
            case .test:
                return ("/usr/local/bin/ar", ["test", "."])
            default:
                return nil
            }
            
        case .unknown:
            return nil
        }
    }
    
    // MARK: - Execute Action
    
    func execute(action: ProjectAction, projectPath: URL, completion: @escaping (Bool, String) -> Void) {
        guard !isRunning else {
            completion(false, "A process is already running")
            return
        }
        
        let projectType = detectProjectType(at: projectPath)
        guard let command = getBuildCommand(for: projectType, action: action, config: buildConfiguration, projectPath: projectPath.path) else {
            completion(false, "Action '\(action.rawValue)' not supported for \(projectType.rawValue) projects")
            return
        }
        
        if projectType == .xcode {
            buildParser.clear()
        }
        
        isRunning = true
        output = "[\(projectType.rawValue)] \(action.rawValue)...\n"
        output += "$ \(command.executable) \(command.arguments.joined(separator: " "))\n\n"
        
        let process = Process()
        process.currentDirectoryURL = projectPath
        process.executableURL = URL(fileURLWithPath: findExecutable(command.executable))
        process.arguments = command.arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        var lineBuffer = ""
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                DispatchQueue.main.async {
                    self?.output += text
                    
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
        }
        
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.currentProcess = nil
                
                if projectType == .xcode && !lineBuffer.isEmpty {
                    self?.buildParser.parseLine(lineBuffer)
                    lineBuffer = ""
                }
                
                let success = proc.terminationStatus == 0
                self?.output += "\n\(success ? "✅" : "❌") \(action.rawValue) \(success ? "succeeded" : "failed") (exit code: \(proc.terminationStatus))\n"
                completion(success, self?.output ?? "")
            }
        }
        
        do {
            try process.run()
            currentProcess = process
        } catch {
            isRunning = false
            output += "❌ Failed to start: \(error.localizedDescription)\n"
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
    
    private func findExecutable(_ name: String) -> String {
        // Common executable paths
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)",
            name
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return name
    }
}
