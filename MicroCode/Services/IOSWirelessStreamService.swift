//
//  IOSWirelessStreamService.swift
//  MicroCode
//
//  Wireless (Wi-Fi / CoreDevice network tunnel) live screen for iPhone & iPad.
//  Reads the MJPEG stream served by the on-device WebDriverAgent (port 9100)
//  and feeds decoded frames to the same Metal surface used by the USB capture path.
//

import Foundation
import CoreVideo
import CoreGraphics
import ImageIO
import CoreMedia

final class MJPEGStreamClient: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private let decodeQueue = DispatchQueue(label: "net.dotmini.microcode.mjpeg", qos: .userInteractive)
    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onDisconnect: (() -> Void)?

    func start(url: URL) {
        stop()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 24 * 3600
        let q = OperationQueue()
        q.underlyingQueue = decodeQueue
        q.maxConcurrentOperationCount = 1
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: q)
        task = session?.dataTask(with: url)
        task?.resume()
    }

    func stop() {
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
        buffer.removeAll(keepingCapacity: false)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onDisconnect?()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        // Extract the newest complete JPEG (SOI FFD8 ... EOI FFD9); skip stale ones to stay real-time.
        var latest: Data?
        while let soi = buffer.range(of: Data([0xFF, 0xD8])),
              let eoi = buffer.range(of: Data([0xFF, 0xD9]), in: soi.upperBound..<buffer.endIndex) {
            latest = buffer.subdata(in: soi.lowerBound..<eoi.upperBound)
            buffer.removeSubrange(buffer.startIndex..<eoi.upperBound)
        }
        if buffer.count > 8_000_000 { buffer.removeAll() }
        if let jpeg = latest, let pb = decode(jpeg) {
            onFrame?(pb)
        }
    }

    private func decode(_ jpeg: Data) -> CVPixelBuffer? {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = img.width, h = img.height
        if pool == nil || poolSize != CGSize(width: w, height: h) {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            var newPool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &newPool)
            pool = newPool
            poolSize = CGSize(width: w, height: h)
        }
        guard let pool else { return nil }
        var pbOut: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pbOut)
        guard let pb = pbOut else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pb),
            width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pb
    }
}

@MainActor
final class IOSWirelessStreamService {
    static let shared = IOSWirelessStreamService()
    private let client = MJPEGStreamClient()
    private(set) var isRunning = false
    private var currentHost: String?

    /// Start the wireless MJPEG screen from `host` (IPv4 or IPv6 tunnel address).
    func start(host: String) {
        guard !(isRunning && currentHost == host) else { return }
        let formatted = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        guard let url = URL(string: "http://\(formatted):9100") else { return }
        currentHost = host
        isRunning = true
        client.onFrame = { pb in
            let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
            DispatchQueue.main.async {
                IOSDeviceCaptureService.shared.deliverWirelessFrame(pb, size: CGSize(width: w, height: h))
            }
        }
        client.onDisconnect = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRunning = false
                self.currentHost = nil
                IOSDeviceCaptureService.shared.wirelessStreamEnded()
            }
        }
        client.start(url: url)
    }

    func stop() {
        client.stop()
        isRunning = false
        currentHost = nil
    }
}
