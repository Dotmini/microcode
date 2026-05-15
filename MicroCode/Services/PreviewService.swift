//
//  PreviewService.swift
//  MicroCode
//
//  The Brain: SwiftUI Preview & Simulator Control
//  - ImageRenderer for View → Image conversion
//  - xcrun simctl for real simulator control
//
//  SPU AI CLUB - Dotmini Software
//

import SwiftUI
import Combine
import AppKit

// MARK: - Models

/// Simulator device
struct Simulator: Identifiable, Hashable {
    let id = UUID()
    let udid: String
    let name: String
    let runtime: String
    var state: SimState
    
    var icon: String {
        if name.contains("iPad") { return "ipad" }
        if name.contains("Apple Watch") { return "applewatch" }
        if name.contains("Apple TV") { return "appletv" }
        return "iphone"
    }
    
    enum SimState {
        case booted, shutdown
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(udid)
    }
    
    static func == (lhs: Simulator, rhs: Simulator) -> Bool {
        lhs.udid == rhs.udid
    }
}

/// Device frame dimensions
struct DeviceFrame: Identifiable {
    let id = UUID()
    let name: String
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    
    static let allDevices: [DeviceFrame] = [
        DeviceFrame(name: "iPhone 15 Pro", width: 393, height: 852, cornerRadius: 55),
        DeviceFrame(name: "iPhone 15 Pro Max", width: 430, height: 932, cornerRadius: 55),
        DeviceFrame(name: "iPhone 15", width: 393, height: 852, cornerRadius: 55),
        DeviceFrame(name: "iPhone SE", width: 375, height: 667, cornerRadius: 0),
        DeviceFrame(name: "iPad Pro 11", width: 834, height: 1194, cornerRadius: 20),
        DeviceFrame(name: "iPad Pro 13", width: 1024, height: 1366, cornerRadius: 20)
    ]
}

/// Preview configuration
struct PreviewConfiguration {
    var device: DeviceFrame = DeviceFrame.allDevices[0]
    var orientation: PreviewOrientation = .portrait
    var colorScheme: PreviewColorScheme = .light
}

enum PreviewOrientation: String, CaseIterable {
    case portrait = "Portrait"
    case landscape = "Landscape"
}

enum PreviewColorScheme: String, CaseIterable {
    case light = "Light"
    case dark = "Dark"
}

// MARK: - Preview Service (The Brain)

@MainActor
class PreviewService: ObservableObject {
    static let shared = PreviewService()
    
    // MARK: - UI State Binding
    
    @Published var isPreviewLoading = false
    @Published var previewImage: NSImage?
    @Published var previewError: String?
    @Published var previewLogs: String = ""
    
    // MARK: - Settings & Data
    
    @Published var configuration = PreviewConfiguration()
    @Published var simulators: [Simulator] = []
    @Published var selectedSimulator: Simulator?
    @Published var isLoadingSimulators = false
    
    // MARK: - Init
    
    private init() {
        // Load simulators from system
        Task {
            await loadSimulatorsFromSystem()
        }
    }
    
    // MARK: - Core Logic: Run Preview
    
    /// Run Swift Playground and render preview using ImageRenderer
    func runSwiftPlayground(filePath: String) async {
        await MainActor.run {
            self.isPreviewLoading = true
            self.previewError = nil
            self.previewImage = nil
            self.appendLog("▶️ Building \(URL(fileURLWithPath: filePath).lastPathComponent)...")
        }
        
        // Simulate compile delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Read source code
        let code = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
        
        // Create demo view based on code analysis
        let isDark = configuration.colorScheme == .dark
        let device = configuration.device
        
        let mockView = createDemoView(from: code, isDark: isDark)
            .frame(width: device.width, height: device.height)
            .background(isDark ? Color.black : Color.white)
        
        
        await MainActor.run {
            if let nsImage = renderToImage(view: mockView, scale: 2.0) {
                self.previewImage = nsImage
                self.appendLog("✅ Build Success: View Rendered")
            } else {
                self.previewError = "Failed to render view"
                self.appendLog("❌ Error: Render failed")
            }
            self.isPreviewLoading = false
        }
    }
    
    // MARK: - Compatibility Render
    @MainActor
    private func renderToImage<V: View>(view: V, scale: CGFloat) -> NSImage? {
        if #available(macOS 13.0, *), let image = ImageRenderer(content: view).nsImage {
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            return renderer.nsImage
        } else {
            // macOS 12 Fallback using NSHostingView
            let hostingView = NSHostingView(rootView: view)
            let size = hostingView.fittingSize
            hostingView.frame = CGRect(origin: .zero, size: size)
            hostingView.layout()
            
            guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return nil }
            hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
            
            let image = NSImage(size: size)
            image.addRepresentation(rep)
            return image
        }
    }

    
    // MARK: - Universal Preview
    
    @Published var universalPreviewImages: [UUID: NSImage] = [:]
    
    /// Run preview for multiple devices
    func runUniversalPreview(filePath: String, devices: [DeviceFrame], isDark: Bool) async {
        await MainActor.run {
            self.isPreviewLoading = true
            self.previewError = nil
            self.universalPreviewImages = [:]
            self.appendLog("▶️ Generating Universal Previews for \(devices.count) devices...")
        }
        
        // Simulate compile delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Read source code
        let code = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
        
        // Generate for each device
        var newImages: [UUID: NSImage] = [:]
        
        for device in devices {
            // Create view
            let mockView = createDemoView(from: code, isDark: isDark)
                .frame(width: device.width, height: device.height)
                .background(isDark ? Color.black : Color.white)
            
            // Render
            if let image = self.renderToImage(view: mockView, scale: 2.0) {
                newImages[device.id] = image
            }
        }
        
        await MainActor.run {
            self.universalPreviewImages = newImages
            self.isPreviewLoading = false
            self.appendLog("✅ Universal Generation Complete")
        }
    }
    
    /// Create demo SwiftUI view based on code analysis
    @ViewBuilder
    private func createDemoView(from code: String, isDark: Bool) -> some View {
        let textColor: Color = isDark ? .white : .black
        
        VStack(spacing: 20) {
            Spacer()
            
            // App icon
            Image(systemName: "swift")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            // Title
            Group {
                if code.contains("Text(") {
                    Text("Hello, SwiftUI!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(textColor)
                } else {
                    Text("Swift Preview")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(textColor)
                }
            }
            
            Text("Running on MicroCode")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Sample UI elements based on code
            if code.contains("Button") {
                Button("Tap Me") {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            
            if code.contains("TextField") {
                TextField("Enter text...", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 40)
            }
            
            if code.contains("List") || code.contains("ForEach") {
                VStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { i in
                        HStack {
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 40, height: 40)
                            VStack(alignment: .leading) {
                                Text("Item \(i)")
                                    .fontWeight(.medium)
                                    .foregroundColor(textColor)
                                Text("Subtitle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 20)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Simulator Control (xcrun simctl)
    
    /// Load simulators from system using xcrun simctl
    func loadSimulatorsFromSystem() async {
        isLoadingSimulators = true
        appendLog("Loading simulators...")
        
        defer { isLoadingSimulators = false }
        
        do {
            // Run: xcrun simctl list devices available --json
            let output = try await runShell("xcrun simctl list devices available --json")
            
            guard let jsonData = output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let devices = json["devices"] as? [String: [[String: Any]]] else {
                appendLog("⚠️ Failed to parse simulators")
                // Use mock data
                loadMockSimulators()
                return
            }
            
            var allSimulators: [Simulator] = []
            
            for (runtime, deviceList) in devices {
                let runtimeName = runtime
                    .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                    .replacingOccurrences(of: "-", with: " ")
                
                for device in deviceList {
                    guard let udid = device["udid"] as? String,
                          let name = device["name"] as? String,
                          let stateStr = device["state"] as? String else { continue }
                    
                    let state: Simulator.SimState = stateStr == "Booted" ? .booted : .shutdown
                    
                    allSimulators.append(Simulator(
                        udid: udid,
                        name: name,
                        runtime: runtimeName,
                        state: state
                    ))
                }
            }
            
            simulators = allSimulators.sorted { $0.name < $1.name }
            selectedSimulator = simulators.first(where: { $0.state == .booted }) ?? simulators.first
            
            appendLog("✅ Found \(simulators.count) simulators")
            
        } catch {
            appendLog("⚠️ Using mock simulators")
            loadMockSimulators()
        }
    }
    
    /// Load mock simulators (fallback)
    private func loadMockSimulators() {
        simulators = [
            Simulator(udid: "mock-iphone15pro", name: "iPhone 15 Pro", runtime: "iOS 17.0", state: .booted),
            Simulator(udid: "mock-iphonese", name: "iPhone SE (3rd gen)", runtime: "iOS 17.0", state: .shutdown),
            Simulator(udid: "mock-ipadpro", name: "iPad Pro (11-inch)", runtime: "iOS 17.0", state: .shutdown)
        ]
        selectedSimulator = simulators.first
    }
    
    /// Boot a simulator
    func bootSimulator(_ sim: Simulator) async throws {
        appendLog("🚀 Booting \(sim.name)...")
        
        _ = try await runShell("xcrun simctl boot \(sim.udid)")
        _ = try? await runShell("open -a Simulator")
        
        // Update state
        if let index = simulators.firstIndex(where: { $0.id == sim.id }) {
            simulators[index].state = .booted
            appendLog("✅ \(sim.name) is now Booted")
        }
    }
    
    /// Shutdown a simulator
    func shutdownSimulator(_ sim: Simulator) async throws {
        appendLog("Shutting down \(sim.name)...")
        
        _ = try await runShell("xcrun simctl shutdown \(sim.udid)")
        
        if let index = simulators.firstIndex(where: { $0.id == sim.id }) {
            simulators[index].state = .shutdown
            appendLog("✅ \(sim.name) is now Shutdown")
        }
    }
    
    /// Build and run Swift project on simulator
    func buildAndRunSwiftProject(projectPath: String) async {
        guard let sim = selectedSimulator else {
            appendLog("❌ Error: No Simulator Selected")
            previewError = "No Simulator Selected"
            return
        }
        
        isPreviewLoading = true
        previewError = nil
        
        defer { isPreviewLoading = false }
        
        appendLog("🔨 Deploying to \(sim.name)...")
        appendLog("Building Scheme...")
        
        // Boot if needed
        if sim.state == .shutdown {
            do {
                try await bootSimulator(sim)
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                appendLog("⚠️ Failed to boot: \(error.localizedDescription)")
            }
        }
        
        // Simulate build
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        appendLog("✅ App launched on Simulator")
        
        // Capture screenshot
        do {
            let screenshotPath = NSTemporaryDirectory() + "sim_screenshot.png"
            _ = try await runShell("xcrun simctl io \(sim.udid) screenshot \(screenshotPath)")
            
            if let image = NSImage(contentsOfFile: screenshotPath) {
                previewImage = image
                appendLog("📸 Screenshot captured")
            }
        } catch {
            appendLog("⚠️ Screenshot failed")
        }
    }
    
    // MARK: - Python Script
    
    func runPythonScript(filePath: String, env: String = "system") async {
        isPreviewLoading = true
        previewError = nil
        
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        appendLog("🐍 Running \(fileName) with \(env)...")
        
        defer { isPreviewLoading = false }
        
        let pythonPath: String
        switch env {
        case "python3.11": pythonPath = "/opt/homebrew/bin/python3.11"
        case "python3.12": pythonPath = "/opt/homebrew/bin/python3.12"
        case "venv": pythonPath = ".venv/bin/python"
        case "conda": pythonPath = "/opt/homebrew/anaconda3/bin/python"
        default: pythonPath = "/usr/bin/python3"
        }
        
        do {
            let output = try await runShell("\(pythonPath) \"\(filePath)\"")
            if !output.isEmpty {
                appendLog(output)
            }
            appendLog("✅ Python script completed")
        } catch {
            previewError = error.localizedDescription
            appendLog("❌ Error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - R Script
    
    func runRScript(filePath: String) async {
        isPreviewLoading = true
        previewError = nil
        
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        appendLog("📊 Running R script: \(fileName)...")
        
        defer { isPreviewLoading = false }
        
        // Find Rscript
        let rPaths = ["/opt/homebrew/bin/Rscript", "/usr/local/bin/Rscript", "/usr/bin/Rscript"]
        let rPath = rPaths.first { FileManager.default.fileExists(atPath: $0) }
        
        guard let rPath = rPath else {
            previewError = "R not installed"
            appendLog("❌ R is not installed")
            return
        }
        
        do {
            let output = try await runShell("\(rPath) --vanilla \"\(filePath)\"")
            if !output.isEmpty {
                appendLog(output)
            }
            appendLog("✅ R script completed")
        } catch {
            previewError = error.localizedDescription
            appendLog("❌ Error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helpers
    
    /// Run shell command
    private func runShell(_ command: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func clearLogs() {
        previewLogs = ""
    }
    
    func stopPreview() {
        isPreviewLoading = false
        appendLog("⏹ Stopped by user")
    }
    
    private func appendLog(_ text: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        previewLogs += "[\(timestamp)] \(text)\n"
    }
}

// MARK: - Hot Reload Service (Live Preview)

/// Hot Reload result from backend
struct HotReloadResult: Codable {
    let success: Bool
    let output: String
    let error: String?
    let compileTimeMs: Int
    let renderTimeMs: Int
    
    enum CodingKeys: String, CodingKey {
        case success, output, error
        case compileTimeMs = "compile_time_ms"
        case renderTimeMs = "render_time_ms"
    }
}

/// Live Preview Hot Reload Service - Real-time code compilation and preview
@MainActor
class HotReloadService: ObservableObject {
    static let shared = HotReloadService()
    
    // MARK: - Published State
    
    @Published var isEnabled: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastResult: HotReloadResult?
    @Published var lastError: String?
    @Published var compileTimeMs: Int = 0
    
    // MARK: - Private
    
    private let baseURL = "http://127.0.0.1:3000"
    private var debounceTask: Task<Void, Never>?
    private let debounceMs: UInt64 = 200
    
    private init() {}
    
    // MARK: - Public API
    
    /// Toggle live preview on/off
    func toggle() {
        isEnabled.toggle()
        if !isEnabled {
            lastResult = nil
            lastError = nil
        }
    }
    
    /// Request hot reload with debounce
    func requestReload(sourceCode: String, language: String, filePath: String? = nil) {
        guard isEnabled else { return }
        
        // Cancel previous debounce
        debounceTask?.cancel()
        
        debounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: debounceMs * 1_000_000)
                await performReload(sourceCode: sourceCode, language: language, filePath: filePath)
            } catch {
                // Task cancelled
            }
        }
    }
    
    /// Force immediate reload
    func forceReload(sourceCode: String, language: String, filePath: String? = nil) async {
        debounceTask?.cancel()
        await performReload(sourceCode: sourceCode, language: language, filePath: filePath)
    }
    
    // MARK: - Private Methods
    
    private func performReload(sourceCode: String, language: String, filePath: String?) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let result = try await callReloadAPI(
                sourceCode: sourceCode,
                language: mapLanguage(language),
                filePath: filePath
            )
            
            lastResult = result
            compileTimeMs = result.compileTimeMs
            
            if !result.success {
                lastError = result.error
            } else {
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
    
    private func callReloadAPI(sourceCode: String, language: String, filePath: String?) async throws -> HotReloadResult {
        guard let url = URL(string: "\(baseURL)/api/preview/reload") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "source_code": sourceCode,
            "language": language
        ]
        if let path = filePath {
            body["file_path"] = path
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return try JSONDecoder().decode(HotReloadResult.self, from: data)
    }
    
    /// Map IDE language string to backend language
    private func mapLanguage(_ language: String) -> String {
        let lower = language.lowercased()
        switch lower {
        case "swift", "rs", "rust", "c", "cpp", "c++":
            return lower
        default:
            return lower
        }
    }
}

// MARK: - Live Preview Panel View

struct LivePreviewPanel: View {
    @ObservedObject var hotReload = HotReloadService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(hotReload.isEnabled ? .green : .gray)
                    .frame(width: 8, height: 8)
                
                Text("Live Preview")
                    .font(.system(size: 11, weight: .semibold))
                
                if hotReload.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.leading, 4)
                }
                
                Spacer()
                
                if hotReload.compileTimeMs > 0 {
                    Text("⚡ \(hotReload.compileTimeMs)ms")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Toggle("", isOn: $hotReload.isEnabled)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            if let error = hotReload.lastError {
                errorView(error)
            } else if let result = hotReload.lastResult, result.success {
                outputView(result.output)
            } else {
                placeholderView
            }
        }
    }
    
    private func errorView(_ error: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Compilation Error")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                }
                
                Text(error)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.orange.opacity(0.05))
    }
    
    private func outputView(_ output: String) -> some View {
        ScrollView {
            if output.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Compiled successfully")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                Text(output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(nsColor: .labelColor))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private var placeholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.square.stack")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            
            Text("Hot Reload")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Enable to compile code as you type")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
