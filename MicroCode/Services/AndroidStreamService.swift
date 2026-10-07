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
    
    @Published var hasReceivedFirstFrame: Bool = false
    @Published var latestPixelBuffer: CVPixelBuffer? = nil
    
    private var serverProcess: Process?
    private var connection: NWConnection?
    private var controlConnection: NWConnection?
    private var decoder: DeviceStreamDecoder?
    private var localPort: UInt16 = 27183
    private var controlPort: UInt16 = 27184
    private var scid: String = String(format: "%08x", UInt32.random(in: 0x10000000...0x7fffffff))
    
    // FPS tracking
    private var frameCount = 0
    private var lastFPSTime = CACurrentMediaTime()

    var resolvedAdbPath: String? {
        let candidates = [
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
    
    private var isConnecting = false

    /// Start H.264 streaming from an Android device
    /// - Parameters:
    ///   - serial: ADB device serial number
    ///   - adbPath: Path to adb binary (optional, auto-detected)
    ///   - maxFPS: Maximum frame rate (default 60)
    ///   - maxSize: Max dimension in pixels (0 = device native)
    func startStreaming(serial: String, adbPath: String? = nil, maxFPS: Int = 60, maxSize: Int = 1280) async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }

        stopStreaming()
        hasReceivedFirstFrame = false
        latestPixelBuffer = nil
        self.scid = String(format: "%08x", UInt32.random(in: 0x10000000...0x7fffffff))
        self.localPort = UInt16.random(in: 27180...27280)
        self.controlPort = self.localPort + 1
        let resolvedAdb = adbPath ?? resolvedAdbPath ?? "adb"
        self.activeSerial = serial

        // Fast check: ensure device is online before attempting scrcpy handshake
        if let state = try? await Self.runADB(resolvedAdb, args: ["-s", serial, "get-state"], timeoutSeconds: 2.0) {
            let trimmed = state.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "offline" {
                _ = try? await Self.runADB(resolvedAdb, args: ["-s", serial, "reconnect", "offline"], timeoutSeconds: 2.0)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            } else if trimmed != "device" {
                statusMessage = "Device not ready (\(trimmed))"
                return
            }
        }

        // Query model name via ADB
        if let model = try? await Self.runADB(resolvedAdb, args: ["-s", serial, "shell", "getprop", "ro.product.model"], timeoutSeconds: 2.0) {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                self.deviceName = trimmed
            }
        }
        
        // Query device resolution via wm size
        if let res = await Self.queryDeviceResolution(serial: serial, adbPath: resolvedAdb) {
            self.deviceResolution = res
        }

        statusMessage = "Deploying scrcpy-server..."
        
        do {
            // Step 1: Push scrcpy-server to device
            try await pushServer(serial: serial, adbPath: resolvedAdb)
            
            // Step 2: Set up ADB port forwarding to scrcpy abstract socket
            try await setupPortForwarding(serial: serial, adbPath: resolvedAdb)
            
            // Step 3: Launch scrcpy-server on device
            try launchServer(serial: serial, adbPath: resolvedAdb, maxFPS: maxFPS, maxSize: maxSize)
            
            // Step 4: Connect sockets with retry for server startup
            var connected = false
            for attempt in 1...6 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                do {
                    try await connectVideoSocket()
                    try? await connectControlSocket()
                    connected = true
                    break
                } catch {
                    print("[AndroidStream] Connection attempt \(attempt) failed: \(error). Retrying...")
                    connection?.cancel()
                    connection = nil
                    controlConnection?.cancel()
                    controlConnection = nil
                }
            }
            
            guard connected else {
                throw StreamError.connectionFailed
            }
            
            statusMessage = "Live · \(deviceName.isEmpty ? "Android" : deviceName) · 60 FPS Native GPU"
            isStreaming = true
            
        } catch {
            statusMessage = "Stream failed: \(error.localizedDescription)"
            print("[AndroidStream] Error: \(error)")
            stopStreaming()
        }
    }
    
    func stopStreaming() {
        isConnecting = false
        connection?.cancel()
        connection = nil
        controlConnection?.cancel()
        controlConnection = nil
        if let proc = serverProcess, proc.isRunning {
            proc.terminate()
            kill(proc.processIdentifier, SIGKILL)
        }
        serverProcess = nil
        if !activeSerial.isEmpty, let adb = resolvedAdbPath {
            let serial = activeSerial
            let port = localPort
            Task {
                _ = try? await Self.runADB(adb, args: ["-s", serial, "forward", "--remove", "tcp:\(port)"], timeoutSeconds: 1.5)
            }
        }
        decoder = nil
        latestPixelBuffer = nil
        isStreaming = false
        hasReceivedFirstFrame = false
        frameCount = 0
        measuredFPS = 0
        latencyMs = 0
    }
    
    // MARK: - Server Deployment
    
    private func pushServer(serial: String, adbPath: String) async throws {
        var serverJarPath: String?
        if let bundled = Bundle.main.path(forResource: "scrcpy-server", ofType: "jar") {
            serverJarPath = bundled
        } else if let resURL = Bundle.main.resourceURL?.appendingPathComponent("scrcpy-server.jar"),
                  FileManager.default.fileExists(atPath: resURL.path) {
            serverJarPath = resURL.path
        } else {
            let candidates = [
                "/opt/homebrew/share/scrcpy/scrcpy-server",
                "/opt/homebrew/Cellar/scrcpy/3.3.4/share/scrcpy/scrcpy-server",
                FileManager.default.currentDirectoryPath + "/MicroCode/Resources/scrcpy-server.jar",
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
            "localabstract:scrcpy_\(scid)"
        ])
        print("[AndroidStream] Port forward result: \(result)")
    }
    
    private func launchServer(serial: String, adbPath: String, maxFPS: Int, maxSize: Int) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        let effectiveSize = maxSize > 0 ? maxSize : 1280
        let cmd = "CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server 3.3.4 scid=\(scid) log_level=info audio=false max_size=\(effectiveSize) max_fps=\(maxFPS) tunnel_forward=true cleanup=false"
        process.arguments = [
            "-s", serial,
            "shell",
            "sh", "-c",
            cmd
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        serverProcess = process
        print("[AndroidStream] Server launched with scid=\(scid)")
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
            let lock = NSLock()
            var isResumed = false
            
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
            timer.schedule(deadline: .now() + 2.0)
            timer.setEventHandler { [weak conn] in
                lock.lock()
                defer { lock.unlock() }
                guard !isResumed else { return }
                isResumed = true
                conn?.cancel()
                continuation.resume(throwing: StreamError.connectionFailed)
            }
            timer.resume()

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timer.cancel()
                    lock.lock()
                    defer { lock.unlock() }
                    guard !isResumed else { return }
                    isResumed = true
                    print("[AndroidStream] Control socket connected")
                    continuation.resume()
                case .failed(let error):
                    timer.cancel()
                    lock.lock()
                    defer { lock.unlock() }
                    guard !isResumed else { return }
                    isResumed = true
                    print("[AndroidStream] Control socket failed: \(error)")
                    continuation.resume(throwing: error)
                case .cancelled:
                    timer.cancel()
                    lock.lock()
                    defer { lock.unlock() }
                    guard !isResumed else { return }
                    isResumed = true
                    continuation.resume(throwing: StreamError.connectionFailed)
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
            let lock = NSLock()
            var isResumed = false
            
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
            timer.schedule(deadline: .now() + 3.0)
            timer.setEventHandler { [weak conn] in
                lock.lock()
                defer { lock.unlock() }
                guard !isResumed else { return }
                isResumed = true
                conn?.cancel()
                continuation.resume(throwing: StreamError.connectionFailed)
            }
            timer.resume()

            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    timer.cancel()
                    lock.lock()
                    defer { lock.unlock() }
                    guard !isResumed else { return }
                    isResumed = true
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
                    timer.cancel()
                    lock.lock()
                    defer { lock.unlock() }
                    guard !isResumed else { return }
                    isResumed = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    timer.cancel()
                    lock.lock()
                    defer { lock.unlock() }
                    guard !isResumed else { return }
                    isResumed = true
                    continuation.resume(throwing: StreamError.connectionFailed)
                default:
                    break
                }
            }
            conn.start(queue: DispatchQueue(label: "net.dotmini.microcode.android-stream", qos: .userInteractive))
        }
    }
    
    // MARK: - Video Stream Reading (H.264 NAL Units)
    
    private func readVideoStream(_ conn: NWConnection) {
        // Step 1: Read dummy byte (1 byte)
        readExactBytes(conn, length: 1) { [weak self] dummyData in
            guard let self, let dummyData, !dummyData.isEmpty else {
                print("[AndroidStream] Stream dummy byte error or closed")
                return
            }
            
            // Step 2: Read device name (64 bytes null-padded)
            self.readExactBytes(conn, length: 64) { [weak self] nameData in
                guard let self, let nameData, nameData.count >= 64 else {
                    print("[AndroidStream] Stream device name error or closed")
                    return
                }
                let devName = String(decoding: nameData, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\n\r"))
                print("[AndroidStream] Scrcpy device name: \(devName)")
                if !devName.isEmpty && self.deviceName.isEmpty {
                    DispatchQueue.main.async {
                        self.deviceName = devName
                    }
                }
                
                // Step 3: Read codec header (12 bytes: 4B codec + 4B width + 4B height)
                self.readExactBytes(conn, length: 12) { [weak self] headerData in
                    guard let self, let headerData, headerData.count >= 12 else {
                        print("[AndroidStream] Stream codec header error or closed")
                        return
                    }
                    let w = Int(headerData[4]) << 24 | Int(headerData[5]) << 16 | Int(headerData[6]) << 8 | Int(headerData[7])
                    let h = Int(headerData[8]) << 24 | Int(headerData[9]) << 16 | Int(headerData[10]) << 8 | Int(headerData[11])
                    print("[AndroidStream] Scrcpy stream header received: \(w)x\(h)")
                    if w > 0 && h > 0 {
                        DispatchQueue.main.async {
                            self.deviceResolution = CGSize(width: w, height: h)
                        }
                    }
                    
                    // Step 4: Continuously read video frame packets
                    self.readNextVideoPacket(conn)
                }
            }
        }
    }
    
    private func readNextVideoPacket(_ conn: NWConnection) {
        // scrcpy sends frame meta (12 bytes) + H.264 data for each frame:
        // - 8 bytes: PTS (big-endian int64, microseconds)
        // - 4 bytes: frame size (big-endian uint32)
        readExactBytes(conn, length: 12) { [weak self] metaData in
            guard let self, let metaData, metaData.count >= 12 else {
                print("[AndroidStream] Meta read error or closed")
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
                self.readNextVideoPacket(conn)
                return
            }
            
            // Read the exact H.264 frame data
            self.readExactBytes(conn, length: frameSize) { [weak self] frameData in
                guard let self, let frameData else {
                    print("[AndroidStream] Frame read error or closed for size \(frameSize)")
                    return
                }
                
                // Feed to VideoToolbox decoder
                self.decoder?.decodeNALUnit(frameData)
                
                // Continue reading next packet
                self.readNextVideoPacket(conn)
            }
        }
    }

    private func readExactBytes(_ conn: NWConnection, length: Int, accumulated: Data = Data(), completion: @escaping (Data?) -> Void) {
        let needed = length - accumulated.count
        guard needed > 0 else {
            completion(accumulated)
            return
        }
        conn.receive(minimumIncompleteLength: 1, maximumLength: needed) { [weak self] chunk, _, _, error in
            guard let self else { return }
            if let error {
                print("[AndroidStream] Read exact bytes error: \(error)")
                completion(nil)
                return
            }
            guard let chunk, !chunk.isEmpty else {
                completion(nil)
                return
            }
            var newAcc = accumulated
            newAcc.append(chunk)
            if newAcc.count >= length {
                completion(newAcc)
            } else {
                self.readExactBytes(conn, length: length, accumulated: newAcc, completion: completion)
            }
        }
    }
    
    private func handleDecodedFrame(_ pixelBuffer: CVPixelBuffer) {
        frameCount += 1
        latestPixelBuffer = pixelBuffer
        if !hasReceivedFirstFrame {
            DispatchQueue.main.async {
                self.hasReceivedFirstFrame = true
            }
        }
        let now = CACurrentMediaTime()
        let elapsed = now - lastFPSTime
        if elapsed >= 1.0 {
            measuredFPS = Double(frameCount) / elapsed
            frameCount = 0
            lastFPSTime = now
            statusMessage = "Live · \(deviceName.isEmpty ? "Android" : deviceName) · 60 FPS Native GPU"
        }
        
        onDecodedFrame?(pixelBuffer)
    }
    
    // MARK: - Touch & Input Control

    /// Send touch event to Android device via ultra-low latency scrcpy control socket (32 bytes)
    func sendTouch(action: Int, x: Int, y: Int, width: Int, height: Int) {
        guard let conn = controlConnection else { return }
        
        // scrcpy 3.x control message type 2 = INJECT_TOUCH_EVENT (exact 32 bytes)
        // [1B type=2] [1B action] [8B pointerId] [4B x] [4B y] [2B width] [2B height] [2B pressure] [4B actionButton] [4B buttons]
        let isUp = (action == 1)
        var data = Data()
        data.append(2) // TYPE_INJECT_TOUCH_EVENT
        data.append(UInt8(action)) // 0=down, 1=up, 2=move
        data.append(contentsOf: withUnsafeBytes(of: Int64(0).bigEndian) { Array($0) }) // pointer ID
        data.append(contentsOf: withUnsafeBytes(of: Int32(x).bigEndian) { Array($0) }) // x
        data.append(contentsOf: withUnsafeBytes(of: Int32(y).bigEndian) { Array($0) }) // y
        data.append(contentsOf: withUnsafeBytes(of: UInt16(width).bigEndian) { Array($0) }) // screen width
        data.append(contentsOf: withUnsafeBytes(of: UInt16(height).bigEndian) { Array($0) }) // screen height
        data.append(contentsOf: withUnsafeBytes(of: UInt16(isUp ? 0 : 0xFFFF).bigEndian) { Array($0) }) // pressure
        data.append(contentsOf: withUnsafeBytes(of: Int32(isUp ? 0 : 1).bigEndian) { Array($0) }) // actionButton
        data.append(contentsOf: withUnsafeBytes(of: Int32(isUp ? 0 : 1).bigEndian) { Array($0) }) // buttons
        
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
    /// Uses 0ms scrcpy control socket when connected, falls back to ADB CLI if offline.
    func sendKey(_ keycode: Int) {
        if let conn = controlConnection {
            // scrcpy TYPE_INJECT_KEYCODE = 0 (14 bytes)
            // [1B type=0] [1B action=0(down)] [4B keycode] [4B repeat=0] [4B metaState=0]
            var down = Data([0, 0])
            down.append(contentsOf: withUnsafeBytes(of: Int32(keycode).bigEndian) { Array($0) })
            down.append(contentsOf: withUnsafeBytes(of: Int32(0).bigEndian) { Array($0) })
            down.append(contentsOf: withUnsafeBytes(of: Int32(0).bigEndian) { Array($0) })
            conn.send(content: down, completion: .contentProcessed { _ in })
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak conn] in
                guard let conn else { return }
                var up = Data([0, 1])
                up.append(contentsOf: withUnsafeBytes(of: Int32(keycode).bigEndian) { Array($0) })
                up.append(contentsOf: withUnsafeBytes(of: Int32(0).bigEndian) { Array($0) })
                up.append(contentsOf: withUnsafeBytes(of: Int32(0).bigEndian) { Array($0) })
                conn.send(content: up, completion: .contentProcessed { _ in })
            }
            return
        }

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

    /// Type text into focused Android input field (0ms socket injection)
    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        if let conn = controlConnection {
            // scrcpy TYPE_INJECT_TEXT = 1
            // [1B type=1] [4B length] [UTF-8 bytes]
            let textData = Data(text.utf8)
            var data = Data([1])
            data.append(contentsOf: withUnsafeBytes(of: UInt32(textData.count).bigEndian) { Array($0) })
            data.append(textData)
            conn.send(content: data, completion: .contentProcessed { _ in })
            return
        }

        let serial = activeSerial.isEmpty ? availableDevices.first?.id : activeSerial
        guard let adb = resolvedAdbPath else { return }
        let escaped = text.replacingOccurrences(of: " ", with: "%s")
        Task.detached {
            var args = ["shell", "input", "text", escaped]
            if let serial, !serial.isEmpty {
                args = ["-s", serial] + args
            }
            _ = try? await Self.runADB(adb, args: args)
        }
    }

    /// Inject screen tap at pixel coordinates with instant sub-millisecond execution
    func sendTap(x: Int, y: Int) {
        let res = deviceResolution
        let w = Int(res.width > 0 ? res.width : 1080)
        let h = Int(res.height > 0 ? res.height : 2400)

        if controlConnection != nil {
            sendTouch(action: 0, x: x, y: y, width: w, height: h)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in
                self?.sendTouch(action: 1, x: x, y: y, width: w, height: h)
            }
            return
        }

        // Fallback to ADB shell input tap only if control socket unavailable
        let serial = activeSerial.isEmpty ? availableDevices.first?.id : activeSerial
        guard let adb = resolvedAdbPath else { return }
        Task.detached {
            var args = ["shell", "input", "tap", "\(x)", "\(y)"]
            if let serial, !serial.isEmpty {
                args = ["-s", serial] + args
            }
            _ = try? await Self.runADB(adb, args: args)
        }
    }

    /// Inject swipe gesture with sub-millisecond socket execution
    func sendSwipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Int = 180) {
        let res = deviceResolution
        let w = Int(res.width > 0 ? res.width : 1080)
        let h = Int(res.height > 0 ? res.height : 2400)

        if controlConnection != nil {
            sendTouch(action: 0, x: x1, y: y1, width: w, height: h)
            let midX = (x1 + x2) / 2
            let midY = (y1 + y2) / 2
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.sendTouch(action: 2, x: midX, y: midY, width: w, height: h)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                self?.sendTouch(action: 2, x: x2, y: y2, width: w, height: h)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.10, Double(durationMs) / 1000.0)) { [weak self] in
                self?.sendTouch(action: 1, x: x2, y: y2, width: w, height: h)
            }
            return
        }

        let serial = activeSerial.isEmpty ? availableDevices.first?.id : activeSerial
        guard let adb = resolvedAdbPath else { return }
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
    
    nonisolated private static func runADB(_ adbPath: String, args: [String], timeoutSeconds: Double = 3.5) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: adbPath)
            process.arguments = args
            process.standardOutput = pipe
            process.standardError = pipe
            
            let lock = NSLock()
            var isResumed = false
            
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
            timer.schedule(deadline: .now() + timeoutSeconds)
            timer.setEventHandler {
                lock.lock()
                defer { lock.unlock() }
                guard !isResumed else { return }
                isResumed = true
                process.terminate()
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                try? pipe.fileHandleForReading.close()
                continuation.resume(throwing: StreamError.adbFailed("Timed out after \(timeoutSeconds)s: \(args.joined(separator: " "))"))
            }
            timer.resume()
            
            process.terminationHandler = { proc in
                timer.cancel()
                lock.lock()
                defer { lock.unlock() }
                guard !isResumed else { return }
                isResumed = true
                let data = (try? pipe.fileHandleForReading.readDataToEndOfFile()) ?? Data()
                try? pipe.fileHandleForReading.close()
                let output = String(decoding: data, as: UTF8.self)
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: StreamError.adbFailed(output))
                }
            }
            do {
                try process.run()
            } catch {
                timer.cancel()
                lock.lock()
                defer { lock.unlock() }
                guard !isResumed else { return }
                isResumed = true
                try? pipe.fileHandleForReading.close()
                continuation.resume(throwing: error)
            }
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