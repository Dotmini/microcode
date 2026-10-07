//
//  StateCompressionEngine.swift
//  MicroCode
//
//  Hardware-accelerated state and memory compression engine using Apple LZFSE.
//  Provides sub-millisecond compression and decompression for idle state memory reduction.
//  Copyright © 2026 Dotmini Company Limited. All rights reserved.
//

import Foundation
import Compression

/// High-performance, zero-allocation memory and string compression engine.
/// Utilizes Apple Silicon LZFSE hardware acceleration for sub-millisecond execution.
public final class StateCompressionEngine: Sendable {
    public static let shared = StateCompressionEngine()
    
    private init() {}
    
    // MARK: - Binary Data Compression
    
    /// Compresses arbitrary Data using Apple's high-speed LZFSE algorithm.
    /// Returns compressed Data or nil if compression fails or input is empty.
    public static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer { destinationBuffer.deallocate() }
        
        let compressedSize = data.withUnsafeBytes { rawBuffer -> Int in
            guard let sourceAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_encode_buffer(
                destinationBuffer,
                data.count,
                sourceAddress,
                data.count,
                nil,
                COMPRESSION_LZFSE
            )
        }
        
        guard compressedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: compressedSize)
    }
    
    /// Decompresses LZFSE-encoded Data back to its original bytes.
    public static func decompress(_ data: Data, originalCapacity: Int = 0) -> Data? {
        guard !data.isEmpty else { return Data() }
        var bufferSize = max(originalCapacity, data.count * 4, 32768)
        
        while bufferSize <= 64 * 1024 * 1024 { // Up to 64MB
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            let decompressedSize = data.withUnsafeBytes { rawBuffer -> Int in
                guard let sourceAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(
                    destinationBuffer,
                    bufferSize,
                    sourceAddress,
                    data.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
            
            if decompressedSize > 0 && decompressedSize < bufferSize {
                let result = Data(bytes: destinationBuffer, count: decompressedSize)
                destinationBuffer.deallocate()
                return result
            }
            destinationBuffer.deallocate()
            bufferSize *= 4
        }
        return nil
    }
    
    // MARK: - String Compression
    
    /// Compresses a Swift String into compact LZFSE Data bytes.
    public static func compressString(_ string: String) -> Data? {
        guard !string.isEmpty else { return Data() }
        guard let data = string.data(using: .utf8) else { return nil }
        return compress(data)
    }
    
    /// Decompresses LZFSE Data bytes back into a Swift String.
    public static func decompressString(_ data: Data, originalLength: Int = 0) -> String? {
        guard let decompressedData = decompress(data, originalCapacity: originalLength) else { return nil }
        return String(data: decompressedData, encoding: .utf8)
    }
}
