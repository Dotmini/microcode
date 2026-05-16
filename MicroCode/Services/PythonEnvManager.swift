//
//  PythonEnvManager.swift
//  MicroCode
//
//  Python Virtual Environment and Package Management
//  - Create/manage virtual environments
//  - Detect imports from code
//  - Auto-install missing packages
//

import Foundation
import AppKit

// MARK: - Python Environment

struct PythonEnvironment: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: URL
    let pythonVersion: String
    var packages: [PythonPackage]
    
    var pythonPath: String {
        path.appendingPathComponent("bin/python3").path
    }
    
    var pipPath: String {
        path.appendingPathComponent("bin/pip3").path
    }
    
    var isActive: Bool = false
}

struct PythonPackage: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let version: String
    var isInstalled: Bool
}

// MARK: - Python Environment Manager

class PythonEnvManager: ObservableObject {
    static let shared = PythonEnvManager()
    
    @Published var environments: [PythonEnvironment] = []
    @Published var activeEnvironment: PythonEnvironment?
    @Published var isWorking: Bool = false
    @Published var output: String = ""
    @Published var detectedPackages: [String] = []
    
    private let envsDirectory: URL
    private let systemPython: String
    
    private init() {
        // Store environments in ~/Library/Application Support/MicroCode/envs
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        envsDirectory = appSupport.appendingPathComponent("MicroCode/envs")
        
        // Resolve Python:
        // 1. Full-Bundle embedded Python (App.app/Contents/Resources/RuntimeLib/python/bin/python3)
        // 2. Common system / Homebrew locations
        // 3. The user's login shell (covers pyenv / asdf / custom installs;
        //    a GUI app has a stripped PATH so bare "python3" fails at runtime)
        let fm = FileManager.default
        var resolved: String?
        if let res = Bundle.main.resourceURL {
            let embedded = res.appendingPathComponent("RuntimeLib/python/bin/python3").path
            if fm.isExecutableFile(atPath: embedded) { resolved = embedded }
        }
        if resolved == nil {
            let candidates = [
                "/opt/homebrew/bin/python3",
                "/usr/local/bin/python3",
                "/usr/bin/python3",
                "\(NSHomeDirectory())/.pyenv/shims/python3"
            ]
            resolved = candidates.first { fm.isExecutableFile(atPath: $0) }
        }
        if resolved == nil {
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            if fm.isExecutableFile(atPath: shell) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: shell)
                p.arguments = ["-l", "-c", "command -v python3 2>/dev/null"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                if (try? p.run()) != nil {
                    p.waitUntilExit()
                    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .split(separator: "\n").first.map(String.init)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !out.isEmpty, fm.isExecutableFile(atPath: out) { resolved = out }
                }
            }
        }
        systemPython = resolved ?? "python3"
        
        // Ensure envs directory exists
        try? FileManager.default.createDirectory(at: envsDirectory, withIntermediateDirectories: true)
        
        // Load existing environments asynchronously
        Task {
            await loadEnvironments()
        }
    }
    
    // MARK: - Environment Management
    
    func loadEnvironments() async {
        let envs: [PythonEnvironment] = await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return [] }
            var envs: [PythonEnvironment] = []
            
            guard let contents = try? FileManager.default.contentsOfDirectory(at: self.envsDirectory, includingPropertiesForKeys: nil) else {
                return []
            }
            
            for url in contents {
                if FileManager.default.fileExists(atPath: url.appendingPathComponent("bin/python3").path) {
                    let version = self.getPythonVersion(at: url)
                    let env = PythonEnvironment(
                        name: url.lastPathComponent,
                        path: url,
                        pythonVersion: version,
                        packages: []
                    )
                    envs.append(env)
                }
            }
            return envs
        }.value
        
        await MainActor.run {
            self.environments = envs
        }
    }
    
    func createEnvironment(name: String, pythonPath: String? = nil, completion: @escaping (Bool, String) -> Void) {
        let envPath = envsDirectory.appendingPathComponent(name)
        
        guard !FileManager.default.fileExists(atPath: envPath.path) else {
            completion(false, "Environment '\(name)' already exists")
            return
        }
        
        // Use provided pythonPath or fall back to systemPython
        let pythonExecutable = pythonPath ?? systemPython
        
        isWorking = true
        output = "🐍 Creating virtual environment '\(name)'...\n"
        output += "📌 Using Python: \(pythonExecutable)\n"
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonExecutable)
            process.arguments = ["-m", "venv", envPath.path]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let processOutput = String(data: data, encoding: .utf8) ?? ""
                
                DispatchQueue.main.async {
                    self.isWorking = false
                    
                    if process.terminationStatus == 0 {
                        self.output += "✅ Environment created successfully!\n"
                        self.output += "📍 Location: \(envPath.path)\n"
                        Task { await self.loadEnvironments() }
                        completion(true, "Environment created")
                    } else {
                        self.output += "❌ Failed to create environment\n"
                        self.output += processOutput
                        completion(false, processOutput)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.output += "❌ Error: \(error.localizedDescription)\n"
                    completion(false, error.localizedDescription)
                }
            }
        }
    }
    
    func deleteEnvironment(_ env: PythonEnvironment, completion: @escaping (Bool) -> Void) {
        do {
            try FileManager.default.removeItem(at: env.path)
            Task { await loadEnvironments() }
            if activeEnvironment?.id == env.id {
                activeEnvironment = nil
            }
            completion(true)
        } catch {
            output += "❌ Failed to delete environment: \(error.localizedDescription)\n"
            completion(false)
        }
    }
    
    func activateEnvironment(_ env: PythonEnvironment) {
        activeEnvironment = env
        output += "✅ Activated environment: \(env.name)\n"
    }
    
    // MARK: - Package Detection
    
    func detectImportsFromCode(_ code: String) -> [String] {
        let packages = PythonEnvManager.analyzeImports(code)
        self.detectedPackages = packages
        return packages
    }
    
    /// Pure function for background analysis
    static func analyzeImports(_ code: String) -> [String] {
        var imports: Set<String> = []
        
        // Regex patterns for Python imports
        let patterns = [
            "^import\\s+([\\w.]+)",                    // import module
            "^from\\s+([\\w.]+)\\s+import",            // from module import
            "^import\\s+([\\w.]+)\\s+as\\s+\\w+",     // import module as alias
        ]
        
        let lines = code.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Optimization: Skip lines that definitely aren't imports
            if !trimmed.starts(with: "import") && !trimmed.starts(with: "from") {
                continue
            }
            
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                    let range = NSRange(trimmed.startIndex..., in: trimmed)
                    if let match = regex.firstMatch(in: trimmed, options: [], range: range) {
                        if let moduleRange = Range(match.range(at: 1), in: trimmed) {
                            let module = String(trimmed[moduleRange])
                            // Get top-level module name
                            let topModule = module.components(separatedBy: ".").first ?? module
                            imports.insert(topModule)
                        }
                    }
                }
            }
        }
        
        // Filter out standard library modules
        let standardLibrary: Set<String> = [
            "os", "sys", "re", "json", "math", "random", "datetime", "time",
            "collections", "itertools", "functools", "operator", "string",
            "io", "pathlib", "glob", "shutil", "tempfile", "pickle",
            "logging", "warnings", "traceback", "typing", "abc", "copy",
            "threading", "multiprocessing", "subprocess", "socket", "http",
            "urllib", "email", "html", "xml", "csv", "sqlite3", "hashlib",
            "base64", "struct", "codecs", "unicodedata", "locale", "gettext",
            "argparse", "configparser", "unittest", "pdb", "profile", "gc",
            "inspect", "dis", "ast", "types", "weakref", "contextlib",
            "asyncio", "concurrent", "queue", "sched", "heapq", "bisect",
            "array", "enum", "graphlib", "pprint", "reprlib", "textwrap"
        ]
        
        return imports.filter { !standardLibrary.contains($0) }.sorted()
    }
    
    // MARK: - Package Installation
    
    func installPackages(_ packages: [String], in env: PythonEnvironment, completion: @escaping (Bool, String) -> Void) {
        guard !packages.isEmpty else {
            completion(true, "No packages to install")
            return
        }
        
        isWorking = true
        output += "\n📦 Installing packages: \(packages.joined(separator: ", "))...\n"
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: env.pipPath)
            process.arguments = ["install"] + packages
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            // Read output in real-time
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    DispatchQueue.main.async {
                        self.output += text
                    }
                }
            }
            
            do {
                try process.run()
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    self.isWorking = false
                    pipe.fileHandleForReading.readabilityHandler = nil
                    
                    if process.terminationStatus == 0 {
                        self.output += "\n✅ Packages installed successfully!\n"
                        completion(true, "Installed")
                    } else {
                        self.output += "\n❌ Some packages failed to install\n"
                        completion(false, "Failed")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.output += "❌ Error: \(error.localizedDescription)\n"
                    completion(false, error.localizedDescription)
                }
            }
        }
    }
    
    func installPackage(_ package: String, version: String? = nil, in env: PythonEnvironment, completion: @escaping (Bool) -> Void) {
        let packageSpec = version != nil ? "\(package)==\(version!)" : package
        installPackages([packageSpec], in: env) { success, _ in
            completion(success)
        }
    }
    
    func getInstalledPackages(in env: PythonEnvironment, completion: @escaping ([PythonPackage]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: env.pipPath)
            process.arguments = ["list", "--format=json"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    let packages = json.compactMap { item -> PythonPackage? in
                        guard let name = item["name"] as? String,
                              let version = item["version"] as? String else { return nil }
                        return PythonPackage(name: name, version: version, isInstalled: true)
                    }
                    DispatchQueue.main.async {
                        completion(packages)
                    }
                } else {
                    DispatchQueue.main.async {
                        completion([])
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }
    
    private var currentProcess: Process?
    private let processLock = NSLock()
    
    // MARK: - Code Execution
    
    func executeCode(_ code: String, in env: PythonEnvironment?, completion: @escaping (String, Bool) -> Void) {
        let pythonPath = env?.pythonPath ?? systemPython
        executeCode(code, pythonPath: pythonPath, completion: completion)
    }
    
    func executeCode(_ code: String, pythonPath: String, completion: @escaping (String, Bool) -> Void) {
        // Sanitize code: replace curly quotes with straight quotes
        // macOS TextEditor can auto-substitute quotes which breaks Python syntax
        let sanitizedCode = code
            .replacingOccurrences(of: "\u{2018}", with: "'")  // Left single quote
            .replacingOccurrences(of: "\u{2019}", with: "'")  // Right single quote
            .replacingOccurrences(of: "\u{201C}", with: "\"") // Left double quote
            .replacingOccurrences(of: "\u{201D}", with: "\"") // Right double quote
        
        // Cancel any existing process
        processLock.lock()
        if let existing = currentProcess, existing.isRunning {
            existing.terminate()
        }
        processLock.unlock()
        
        isWorking = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = ["-c", sanitizedCode]
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            // Store current process
            self.processLock.lock()
            self.currentProcess = process
            self.processLock.unlock()
            
            do {
                try process.run()
                process.waitUntilExit()
                
                // Clear current process ref
                self.processLock.lock()
                if self.currentProcess === process {
                    self.currentProcess = nil
                }
                self.processLock.unlock()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                let success = process.terminationStatus == 0
                let result = success ? output : (output + "\n" + error)
                
                DispatchQueue.main.async {
                    self.isWorking = false
                    completion(result, success)
                }
            } catch {
                self.processLock.lock()
                if self.currentProcess === process {
                    self.currentProcess = nil
                }
                self.processLock.unlock()
                
                DispatchQueue.main.async {
                    self.isWorking = false
                    // If terminated manually (e.g. new keystroke), don't show error?
                    // But here we can't easily distinguish. We'll show logic error if any.
                    completion("Error: \(error.localizedDescription)", false)
                }
            }
        }
    }
    
    // MARK: - Streaming & Async Execution
    
    func cancelCurrentProcess() {
        processLock.lock()
        if let existing = currentProcess, existing.isRunning {
            existing.terminate()
        }
        processLock.unlock()
    }
    
    func executeCodeStreaming(code: String, language: String, pythonPath: String? = nil, progress: @escaping (String) -> Void) async throws -> String {
        let lang = language.lowercased()
        
        let executablePath: String
        var arguments: [String] = []
        var forceUnbuffered = false
        
        // Sanitize code
        let sanitizedCode = code
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            
        switch lang {
        case "python":
            executablePath = pythonPath ?? systemPython
            arguments = ["-c", sanitizedCode]
            forceUnbuffered = true
        case "r":
            // Attempt to find Rscript in standard locations
            executablePath = ["/opt/homebrew/bin/Rscript", "/usr/local/bin/Rscript", "/usr/bin/Rscript"].first { FileManager.default.fileExists(atPath: $0) } ?? "Rscript"
            arguments = ["-e", sanitizedCode]
        case "julia":
            executablePath = ["/opt/homebrew/bin/julia", "/usr/local/bin/julia", "/usr/bin/julia"].first { FileManager.default.fileExists(atPath: $0) } ?? "julia"
            arguments = ["-e", sanitizedCode]
        default:
            throw NSError(domain: "EnvManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unsupported language: \(language)"])
        }
            
        cancelCurrentProcess()
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: URLError(.cancelled))
                    return
                }
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                
                // Inherit environment and patch if needed
                var env = ProcessInfo.processInfo.environment
                if forceUnbuffered {
                    env["PYTHONUNBUFFERED"] = "1" // Force unbuffered stdout to stream immediately
                }
                process.environment = env
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                self.processLock.lock()
                self.currentProcess = process
                self.processLock.unlock()
                
                // Set up streaming
                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                        progress(text)
                    }
                }
                
                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                        progress(text)
                    }
                }
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    
                    self.processLock.lock()
                    if self.currentProcess === process {
                        self.currentProcess = nil
                    }
                    self.processLock.unlock()
                    
                    if process.terminationStatus == 0 || process.terminationStatus == 15 {
                        continuation.resume(returning: "")
                    } else {
                        continuation.resume(throwing: NSError(domain: "PythonEnv", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Process exited with status \(process.terminationStatus)"]))
                    }
                } catch {
                    self.processLock.lock()
                    if self.currentProcess === process {
                        self.currentProcess = nil
                    }
                    self.processLock.unlock()
                    
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func getPythonVersion(at envPath: URL) -> String {
        let pythonPath = envPath.appendingPathComponent("bin/python3").path
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["--version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
        } catch {
            return "Unknown"
        }
    }
}
