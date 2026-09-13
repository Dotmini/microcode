import Foundation
import Network
import CoreVideo
import QuartzCore

/// High-performance Android device screen streaming via scrcpy protocol.
/// Replaces the legacy `adb screencap -p` PNG polling with H.264 hardware
/// encoded video over an ADB-forwarded local socket.
@MainActor
final class AndroidStreamService: ObservableObject {
    static let shared = AndroidStreamService()
    
    @Published private(set) var isStreaming = false
    @Published private(set) var deviceName: String = ""
    @Published private(set) var deviceResolution: CGSize = .zero
    @Published private(set) var measuredFPS: Double = 0
    @Published private(set) var statusMessage = ""
    @Published private(set) var latencyMs: Double = 0
    @Published private(set) var availableDevices: [AndroidDeviceItem] = []
    @Published var activeSerial: String = ""

    struct AndroidDeviceItem: Identifiable, Equatable {
        let id: String
        let model: String
        let isEmulator: Bool
    }
    
    /// Frame callback — feeds CVPixelBuffer to DeviceMetalRenderer
    var onDecodedFrame: ((CVPixelBuffer) -> Void)?
    
    private var serverProcess: Process?
    private var connection: NWConnection?
    private var controlConnection: NWConnection?
    private var decoder: DeviceStreamDecoder?
    private var localPort: UInt16 = 27183
    private var controlPort: UInt16 = 27184
    
    // FPS tracking
    private var frameCount = 0
    private var lastFPSTime = CACurrentMediaTime()

    var resolvedAdbPath: String? {
        let candidates = [
            "/Users/dotmini/Library/Android/sdk/platform-tools/adb",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    var hasControlSocket: Bool {
        controlConnection?.state == .ready
    }
    
    // MARK: - Start Streaming
    
    /// Start H.264 streaming from an Android device
    /// - Parameters:
    ///   - serial: ADB device serial number
    ///   - adbPath: Path to adb binary (optional, auto-detected)
    ///   - maxFPS: Maximum frame rate (default 60)
    ///   - maxSize: Max dimension in pixels (0 = device native)
    func startStreaming(serial: String, adbPath: String? = nil, maxFPS: Int = 60, maxSize: Int = 1280) async {
        stopStreaming()
        let resolvedAdb = adbPath ?? resolvedAdbPath ?? "adb"
        self.activeSerial = serial
        // Query model name via ADB
        if let model = try? await Self.runADB(resolvedAdb, args: ["-s", serial, "shell", "getprop", "ro.product.model"]) {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                self.deviceName = trimmed
            }
        }
        
        // Query resolution via ADB
        if let res = await Self.queryDeviceResolution(serial: serial, adbPath: resolvedAdb) {
            self.deviceResolution = res
        } else {
            self.deviceResolution = CGSize(width: 1080, height: 2400)
        }

        statusMessage = "Deploying scrcpy-server..."
        
        do {
            // Step 1: Push scrcpy-server to device
            try await pushServer(serial: serial, adbPath: resolvedAdb)
            
            // Step 2: Set up ADB port forwarding
            try await setupPortForwarding(serial: serial, adbPath: resolvedAdb)
            
            // Step 3: Launch scrcpy-server on device
            try launchServer(serial: serial, adbPath: resolvedAdb, maxFPS: maxFPS, maxSize: maxSize)
            
            // Step 4: Wait for server to start, then connect
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms for server startup
            
            // Step 5: Connect video socket
            try await connectVideoSocket()

            // Step 6: Connect control socket
            try? await connectControlSocket()
            
            statusMessage = "Live · \(deviceName.isEmpty ? "Android" : deviceName) · USB"
            isStreaming = true
            
        } catch {
            statusMessage = "Stream failed: \(error.localizedDescription)"
            print("[AndroidStream] Error: \(error)")
            stopStreaming()
        }
    }
    
    func stopStreaming() {
        connection?.cancel()
        connection = nil
        controlConnection?.cancel()
        controlConnection = nil
        serverProcess?.terminate()
        serverProcess = nil
        if !activeSerial.isEmpty, let adb = resolvedAdbPath {
            let serial = activeSerial
            let port = localPort
            Task {
                _ = try? await Self.runADB(adb, args: ["-s", serial, "forward", "--remove", "tcp:\(port)"])
            }
        }
        decoder = nil
        isStreaming = false
        frameCount = 0
        measuredFPS = 0
        latencyMs = 0
    }
    
    // MARK: - Server Deployment
    
    private func pushServer(serial: String, adbPath: String) async throws {
        // Look for scrcpy-server.jar in bundle resources first, then fallback paths
        var serverJarPath: String?
        if let bundled = Bundle.main.path(forResource: "scrcpy-server", ofType: "jar") {
            serverJarPath = bundled
        } else {
            let candidates = [
                "/opt/homebrew/share/scrcpy/scrcpy-server",
                "/usr/local/share/scrcpy/scrcpy-server",
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/share/scrcpy/scrcpy-server"
            ]
            serverJarPath = candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
        }
        guard let serverJarPath else {
            throw StreamError.serverNotFound
        }
        
        let result = try await Self.runADB(adbPath, args: ["-s", serial, "push", serverJarPath, "/data/local/tmp/scrcpy-server.jar"])
        print("[AndroidStream] Push result: \(result)")
    }
    
    private func setupPortForwarding(serial: String, adbPath: String) async throws {
        // Clear any previous forward on this port first
        _ = try? await Self.runADB(adbPath, args: ["-s", serial, "forward", "--remove", "tcp:\(localPort)"])
        
        // Forward TCP port to scrcpy abstract unix socket
        let result = try await Self.runADB(adbPath, args: [
            "-s", serial,
            "forward",
            "tcp:\(localPort)",
            "localabstract:scrcpy"
        ])
        print("[AndroidStream] Port forward result: \(result)")
    }
    
    private func launchServer(serial: String, adbPath: String, maxFPS: Int, maxSize: Int) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        let effectiveSize = maxSize > 0 ? maxSize : 1280
        process.arguments = [
            "-s", serial,
            "shell",
            "CLASSPATH=/data/local/tmp/scrcpy-server.jar",
            "app_process", "/",
            "com.genymobile.scrcpy.Server",
            "3.3.4",            // version matching scrcpy-server.jar
            "log_level=error",
            "max_size=\(effectiveSize)",
            "max_fps=\(maxFPS)",
            "video_codec=h264",
            "audio=false",
            "control=true",
            "tunnel_forward=true",
            "send_device_meta=false",
            "send_frame_meta=true",
            "show_touches=false",
            "stay_awake=true"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        serverProcess = process
        print("[AndroidStream] Server launched")
    }
    
    // MARK: - Socket Connection
    
    private func connectControlSocket() async throws {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: localPort)!
        )
        let params = NWParameters.tcp
        if let tcpOptions = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.noDelay = true
        }
        let conn = NWConnection(to: endpoint, using: params)
        self.controlConnection = conn
        
        return try await withCheckedThrowingContinuation { continuation in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[AndroidStream] Control socket connected")
                    continuation.resume()
                case .failed(let error):
                    print("[AndroidStream] Control socket failed: \(error)")
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            conn.start(queue: DispatchQueue(label: "net.dotmini.microcode.android-control", qos: .userInteractive))
        }
    }

    private func connectVideoSocket() async throws {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: localPort)!
        )
        
        let params = NWParameters.tcp
        if let tcpOptions = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.noDelay = true // Disable Nagle for lowest latency
        }
        
        let conn = NWConnection(to: endpoint, using: params)
        self.connection = conn
        
        return try await withCheckedThrowingContinuation { continuation in
            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("[AndroidStream] Video socket connected")
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.decoder = DeviceStreamDecoder()
                        self.decoder?.onDecodedFrame = { [weak self] pixelBuffer in
                            self?.handleDecodedFrame(pixelBuffer)
                        }
                        self.decoder?.onResolutionChanged = { [weak self] width, height in
                            DispatchQueue.main.async {
                                guard let self = self else { return }
                                if width > 0 && height > 0 {
                                    self.deviceResolution = CGSize(width: width, height: height)
                                    print("[AndroidStream] Resolution updated by decoder: \(width)x\(height)")
                                }
                            }
                        }
                        self.readVideoStream(conn)
                    }
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            conn.start(queue: DispatchQueue(label: "net.dotmini.microcode.android-stream", qos: .userInteractive))
        }
    }
    
    // MARK: - Video Stream Reading (H.264 NAL Units)
    
    private func readVideoStream(_ conn: NWConnection) {
        // scrcpy sends frame meta (12 bytes) + H.264 data for each frame:
        // - 8 bytes: PTS (big-endian int64, microseconds)
        // - 4 bytes: frame size (big-endian uint32)
        conn.receive(minimumIncompleteLength: 12, maximumLength: 12) { [weak self] metaData, _, _, error in
            guard let self, let metaData, metaData.count >= 12 else {
                if let error { print("[AndroidStream] Meta read error: \(error)") }
                return
            }
            
            // Parse PTS (8 bytes big-endian)
            var pts: UInt64 = 0
            for i in 0..<8 {
                pts = (pts << 8) | UInt64(metaData[i])
            }
            
            // Parse frame size (4 bytes big-endian)
            let frameSize = Int(metaData[8]) << 24 | Int(metaData[9]) << 16 | Int(metaData[10]) << 8 | Int(metaData[11])
            
            guard frameSize > 0, frameSize < 10_000_000 else {
                print("[AndroidStream] Invalid frame size: \(frameSize)")
                self.readVideoStream(conn)
                return
            }
            
            // Read the H.264 frame data
            conn.receive(minimumIncompleteLength: frameSize, maximumLength: frameSize) { [weak self] frameData, _, _, error in
                guard let self, let frameData else {
                    if let error { print("[AndroidStream] Frame read error: \(error)") }
                    return
                }
                
                // Feed to decoder
                DispatchQueue.main.async {
                    self.decoder?.decodeNALUnit(frameData)
                }
                
                // Continue reading
                self.readVideoStream(conn)
            }
        }
    }
    
    private func handleDecodedFrame(_ pixelBuffer: CVPixelBuffer) {
        frameCount += 1
        let now = CACurrentMediaTime()
        let elapsed = now - lastFPSTime
        if elapsed >= 1.0 {
            measuredFPS = Double(frameCount) / elapsed
            frameCount = 0
            lastFPSTime = now
            statusMessage = "Live · \(deviceName.isEmpty ? "Android" : deviceName) · USB"
        }
        
        onDecodedFrame?(pixelBuffer)
    }
    
    // MARK: - Touch & Input Control

    /// Send touch event to Android device
    func sendTouch(action: Int, x: Int, y: Int, width: Int, height: Int) {
        guard let conn = controlConnection else { return }
        
        // scrcpy control message type 2 = inject touch event
        var data = Data()
        data.append(2) // TYPE_INJECT_TOUCH_EVENT
        data.append(UInt8(action)) // ACTION_DOWN=0, ACTION_UP=1, ACTION_MOVE=2
        data.append(contentsOf: withUnsafeBytes(of: Int64(0).bigEndian) { Array($0) }) // pointer ID
        data.append(contentsOf: withUnsafeBytes(of: Int32(x).bigEndian) { Array($0) }) // x
        data.append(contentsOf: withUnsafeBytes(of: Int32(y).bigEndian) { Array($0) }) // y
        data.append(contentsOf: withUnsafeBytes(of: UInt16(width).bigEndian) { Array($0) }) // screen width
        data.append(contentsOf: withUnsafeBytes(of: UInt16(height).bigEndian) { Array($0) }) // screen height
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0xFFFF).bigEndian) { Array($0) }) // pressure
        data.append(contentsOf: withUnsafeBytes(of: Int32(1).bigEndian) { Array($0) }) // buttons
        
        conn.send(content: data, completion: .contentProcessed { _ in })
    }
    
    // MARK: - Input & Key Injection Controls

    /// Scan for connected physical Android devices via ADB
    func scanDevices() async {
        guard let adb = resolvedAdbPath else { return }
        guard let output = try? await Self.runADB(adb, args: ["devices", "-l"]) else { return }
        var list: [AndroidDeviceItem] = []
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("List of") else { continue }
            let parts = trimmed.split(separator: " ").map(String.init)
            guard parts.count >= 2, parts[1] == "device" else { continue }
            let serial = parts[0]
            let isEmu = serial.hasPrefix("emulator-")
            var model = serial
            if let modelPart = parts.first(where: { $0.hasPrefix("model:") }) {
                model = String(modelPart.dropFirst(6)).replacingOccurrences(of: "_", with: " ")
            } else if let prodPart = parts.first(where: { $0.hasPrefix("product:") }) {
                model = String(prodPart.dropFirst(8))
            }
            list.append(AndroidDeviceItem(id: serial, model: model, isEmulator: isEmu))
        }
        self.availableDevices = list
        let physical = list.filter { !$0.isEmulator }
        if let firstPhysical = physical.first, !isStreaming {
            self.activeSerial = firstPhysical.id
            self.deviceName = firstPhysical.model
        } else if let first = list.first, !isStreaming {
            self.activeSerial = first.id
            self.deviceName = first.model
        }
    }

    /// Inject Android hardware keycode (e.g. 4=Back, 3=Home, 187=App Switch, 26=Power, 24/25=Volume)
    func sendKey(_ keycode: Int) {
        let serial = activeSerial.isEmpty ? availableDevices.first?.id : activeSerial
        guard let adb = resolvedAdbPath else { return }
        Task.detached {
            var args = ["shell", "input", "keyevent", "\(keycode)"]
            if let serial, !serial.isEmpty {
                args = ["-s", serial] + args
            }
            _ = try? await Self.runADB(adb, args: args)
        }
    }

    /// Type text into focused Android input field
    func sendText(_ text: String) {
        let serial = activeSerial.isEmpty ? availableDevices.first?.id : activeSerial
        guard !text.isEmpty, let adb = resolvedAdbPath else { return }
        let escaped = text.replacingOccurrences(of: " ", with: "%s")
        Task.detached {
            var args = ["shell", "input", "text", escaped]
            if let serial, !serial.isEmpty {
                args = ["-s", serial] + args
            }
            _ = try? await Self.runADB(adb, args: args)
        }
    }

    /// Inject screen tap at pixel coordinates with both scrcpy and instant ADB execution
    func sendTap(x: Int, y: Int) {
        let serial = activeSerial.isEmpty ? availableDevices.first?.id : activeSerial
        guard let adb = resolvedAdbPath else { return }

        // Also send through control socket if ready
        let res = deviceResolution
        let w = Int(res.width > 0 ? res.width : 1080)
        let h = Int(res.height > 0 ? res.height : 2400)
        sendTouch(action: 0, x: x, y: y, width: w, height: h)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            self.sendTouch(action: 1, x: x, y: y, width: w, height: h)
        }

        // Fast ADB shell input tap
        Task.detached {
            var args = ["shell", "input", "tap", "\(x)", "\(y)"]
            if let serial, !serial.isEmpty {
                args = ["-s", serial] + args
            }
            _ = try? await Self.runADB(adb, args: args)
        }
    }

    /// Inject swipe gesture with both scrcpy and instant ADB execution
    func sendSwipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Int = 180) {
        let serial = activeSerial.isEmpty ? availableDevices.first?.id : activeSerial
        guard let adb = resolvedAdbPath else { return }

        let res = deviceResolution
        let w = Int(res.width > 0 ? res.width : 1080)
        let h = Int(res.height > 0 ? res.height : 2400)
        sendTouch(action: 0, x: x1, y: y1, width: w, height: h)
        sendTouch(action: 2, x: x2, y: y2, width: w, height: h)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(durationMs) / 1000.0) {
            self.sendTouch(action: 1, x: x2, y: y2, width: w, height: h)
        }

        Task.detached {
            var args = ["shell", "input", "swipe", "\(x1)", "\(y1)", "\(x2)", "\(y2)", "\(durationMs)"]
            if let serial, !serial.isEmpty {
                args = ["-s", serial] + args
            }
            _ = try? await Self.runADB(adb, args: args)
        }
    }

    /// Convert trackpad / mouse scroll wheel into smooth vertical or horizontal swipe
    func sendScroll(deltaX: CGFloat, deltaY: CGFloat) {
        let res = deviceResolution
        let w = Int(res.width > 0 ? res.width : 1080)
        let h = Int(res.height > 0 ? res.height : 2400)
        let midX = w / 2
        let midY = h / 2
        let scrollDist = Int(deltaY * 16)
        let targetY = max(80, min(h - 80, midY + scrollDist))
        sendSwipe(x1: midX, y1: midY, x2: midX, y2: targetY, durationMs: 120)
    }
    
    // MARK: - Utilities
    
    nonisolated private static func runADB(_ adbPath: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: adbPath)
            process.arguments = args
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: StreamError.adbFailed(output))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    /// Query the physical device screen resolution via ADB `wm size`
    nonisolated static func queryDeviceResolution(serial: String, adbPath: String) async -> CGSize? {
        guard let output = try? await runADB(adbPath, args: ["-s", serial, "shell", "wm", "size"]) else { return nil }
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("size:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    let dim = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    let wh = dim.components(separatedBy: "x")
                    if wh.count == 2, let w = Double(wh[0]), let h = Double(wh[1]), w > 0, h > 0 {
                        return CGSize(width: w, height: h)
                    }
                }
            }
        }
        return nil
    }
    
    enum StreamError: LocalizedError {
        case serverNotFound
        case adbFailed(String)
        case connectionFailed
        
        var errorDescription: String? {
            switch self {
            case .serverNotFound: return "scrcpy-server not found. Install via 'brew install scrcpy' or bundle in app."
            case .adbFailed(let msg): return "ADB command failed: \(msg)"
            case .connectionFailed: return "Could not connect to scrcpy server"
            }
        }
    }
}