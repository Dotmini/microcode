import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import CoreMediaIO

@MainActor
final class IOSDeviceCaptureService: NSObject, ObservableObject {
    static let shared = IOSDeviceCaptureService()
    
    @Published private(set) var isCapturing = false
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var deviceResolution: CGSize = .zero
    @Published private(set) var measuredFPS: Double = 0
    @Published private(set) var statusMessage = "Connect an iPhone or iPad via USB"
    @Published private(set) var state: IOSDeviceCaptureState = .searching
    @Published private(set) var availableDevices: [AVCaptureDevice] = []
    
    enum IOSDeviceCaptureState: Equatable {
        case searching, connected, streaming, disconnected, error(String)
    }
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let captureQueue = DispatchQueue(label: "net.dotmini.microcode.ios-capture", qos: .userInteractive)
    
    // Frame callback - DeviceMetalRenderer will set this
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    
    // FPS measurement
    private var frameCount = 0
    private var lastFPSTime = CACurrentMediaTime()
    
    // MARK: - CoreMediaIO Screen Capture Activation
    
    /// Tells CoreMediaIO DAL system to expose iOS USB screen capture devices (same as QuickTime)
    private func enableScreenCaptureDevices() {
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let size = UInt32(MemoryLayout<UInt32>.size)
        CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &prop,
            0,
            nil,
            size,
            &allow
        )
    }
    
    // MARK: - Device Discovery
    
    /// Scan for connected iOS devices that expose screen capture over USB
    func discoverDevices() -> [AVCaptureDevice] {
        guard #available(macOS 14.0, *) else { return [] }
        enableScreenCaptureDevices()
        
        // 1. Primary: Muxed device (This is the official iOS USB screen recording device)
        let muxedSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified
        )
        let screenDevices = muxedSession.devices.filter { device in
            let name = device.localizedName.lowercased()
            return name.contains("iphone") || name.contains("ipad") || name.contains("ipod")
        }
        
        if !screenDevices.isEmpty {
            return screenDevices
        }
        
        // 2. Secondary fallback: External video devices
        let videoSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        return videoSession.devices.filter { device in
            let name = device.localizedName.lowercased()
            let model = (device.modelID ?? "").lowercased()
            return name.contains("iphone") || name.contains("ipad") || name.contains("ipod") ||
                   model.contains("iphone") || model.contains("ipad")
        }
    }
    
    /// Manual scan triggered by user
    func scanForDevices() {
        let found = discoverDevices()
        self.availableDevices = found
        if let first = found.first {
            self.state = .connected
            self.connectedDeviceName = first.localizedName
            self.statusMessage = "\(first.localizedName) ready via USB"
            // Auto-start capture immediately!
            startCapture(device: first)
        } else {
            self.state = .searching
            self.statusMessage = "No iPhone or iPad detected. Connect via USB and tap 'Trust This Computer'."
        }
    }
    
    // MARK: - Capture Lifecycle
    
    /// Start capturing from the first available iOS device
    func startCapture() {
        startCapture(device: nil)
    }
    
    /// Start capturing from a specific device
    func startCapture(device: AVCaptureDevice? = nil) {
        Task { @MainActor in
            await startCaptureAsync(device: device)
        }
    }
    
    private func startCaptureAsync(device: AVCaptureDevice? = nil) async {
        stopCapture()
        
        // Step 1: Ensure CoreMediaIO allows USB screen capture devices
        enableScreenCaptureDevices()
        
        // Step 2: Check & request video / camera permission safely without crashing TCC
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus == .notDetermined {
            statusMessage = "Requesting Video permission…"
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                state = .error("Camera permission denied. Please allow MicroCode in System Settings -> Privacy & Security -> Camera.")
                statusMessage = "Permission denied in Settings"
                return
            }
        } else if authStatus == .denied || authStatus == .restricted {
            state = .error("Camera permission denied. Please allow MicroCode in System Settings -> Privacy & Security -> Camera.")
            statusMessage = "Camera permission denied"
            return
        }
        
        // Step 3: Locate target device
        let targetDevice: AVCaptureDevice
        if let device = device {
            targetDevice = device
        } else {
            let available = discoverDevices()
            guard let first = available.first else {
                state = .searching
                statusMessage = "No iPhone or iPad detected. Connect via USB and tap 'Trust This Computer'."
                return
            }
            targetDevice = first
        }
        
        // Step 4: Configure AVCaptureSession
        do {
            let session = AVCaptureSession()
            session.sessionPreset = .high
            
            let input = try AVCaptureDeviceInput(device: targetDevice)
            guard session.canAddInput(input) else {
                state = .error("Cannot add device input: \(targetDevice.localizedName)")
                statusMessage = "Failed to bind device input"
                return
            }
            session.addInput(input)
            
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: captureQueue)
            
            guard session.canAddOutput(output) else {
                state = .error("Cannot add video output")
                statusMessage = "Failed to bind video output"
                return
            }
            session.addOutput(output)
            
            self.captureSession = session
            self.videoOutput = output
            self.connectedDeviceName = targetDevice.localizedName
            self.frameCount = 0
            self.lastFPSTime = CACurrentMediaTime()
            
            // Start running asynchronously off the main actor (prevents UI hitch & Apple warning)
            let queue = self.captureQueue
            queue.async {
                session.startRunning()
            }
            
            state = .streaming
            isCapturing = true
            statusMessage = "Live · \(targetDevice.localizedName) · USB"
            print("[IOSCapture] Started capturing from \(targetDevice.localizedName)")
            
        } catch {
            state = .error(error.localizedDescription)
            statusMessage = "Capture failed: \(error.localizedDescription)"
            print("[IOSCapture] Error: \(error)")
        }
    }
    
    func stopCapture() {
        if let session = captureSession {
            captureQueue.async {
                session.stopRunning()
            }
        }
        captureSession = nil
        videoOutput = nil
        isCapturing = false
        connectedDeviceName = nil
        deviceResolution = .zero
        measuredFPS = 0
        state = .disconnected
    }
    
    /// Monitor for device connect/disconnect
    func startMonitoring() {
        enableScreenCaptureDevices()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceConnected(_:)),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceDisconnected(_:)),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }
    
    func stopMonitoring() {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func deviceConnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice else { return }
        let name = device.localizedName.lowercased()
        guard name.contains("iphone") || name.contains("ipad") || name.contains("ipod") else { return }
        
        DispatchQueue.main.async {
            self.availableDevices = self.discoverDevices()
            self.state = .connected
            self.connectedDeviceName = device.localizedName
            self.statusMessage = "\(device.localizedName) connected via USB"
            print("[IOSCapture] Device connected: \(device.localizedName)")
            // Auto start capture
            self.startCapture(device: device)
        }
    }
    
    @objc private func deviceDisconnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice,
              device.localizedName == connectedDeviceName else { return }
        DispatchQueue.main.async {
            self.stopCapture()
            self.availableDevices = self.discoverDevices()
            self.state = .searching
            self.statusMessage = "Device disconnected"
            print("[IOSCapture] Device disconnected")
        }
    }
}

extension IOSDeviceCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        // Update resolution on first frame
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let size = CGSize(width: width, height: height)
        let now = CACurrentMediaTime()
        
        // All MainActor property access happens on main queue
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Deliver frame to metal renderer
            self.onFrame?(pixelBuffer, presentationTime)
            
            if self.deviceResolution != size {
                self.deviceResolution = size
            }
            self.frameCount += 1
            let elapsed = now - self.lastFPSTime
            if elapsed >= 1.0 {
                self.measuredFPS = Double(self.frameCount) / elapsed
                self.frameCount = 0
                self.lastFPSTime = now
                self.statusMessage = "Live · \(self.connectedDeviceName ?? "iOS") · USB"
            }
        }
    }
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Frame dropped — this is expected under alwaysDiscardsLateVideoFrames
    }
}