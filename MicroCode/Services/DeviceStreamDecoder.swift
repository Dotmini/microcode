//
//  DeviceStreamDecoder.swift
//  MicroCode
//
//  Hardware-accelerated H.264/HEVC decoder using VideoToolbox.
//  Receives raw NAL units (Annex B format) from scrcpy or other sources,
//  converts to AVCC format, and outputs CVPixelBuffer backed by IOSurface
//  for zero-copy Metal rendering.
//

import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox

final class DeviceStreamDecoder {

    // MARK: - Public Interface

    /// Called on a background queue when a frame is decoded.
    /// The CVPixelBuffer is IOSurface-backed and Metal-compatible.
    var onDecodedFrame: ((CVPixelBuffer) -> Void)?

    /// Called when the stream resolution changes (e.g. device rotation).
    var onResolutionChanged: ((Int, Int) -> Void)?

    // MARK: - Private State

    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?

    // Cached SPS/PPS for session creation
    private var currentSPS: Data?
    private var currentPPS: Data?
    private var currentWidth: Int = 0
    private var currentHeight: Int = 0

    // NAL unit accumulation buffer for Annex B parsing
    private var nalBuffer = Data()

    // MARK: - Annex B → AVCC Parsing

    /// Feed raw H.264 Annex B data (may contain multiple NAL units).
    /// This handles start code detection, NAL unit extraction, and
    /// SPS/PPS tracking automatically.
    func decodeNALUnit(_ data: Data) {
        nalBuffer.append(data)
        extractAndProcessNALUnits()
    }

    /// Feed a complete Annex B access unit (frame).
    func decodeAccessUnit(_ data: Data) {
        let nalUnits = splitAnnexBNALUnits(data)
        for nal in nalUnits {
            processNALUnit(nal)
        }
    }

    func invalidate() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
        }
        decompressionSession = nil
        formatDescription = nil
        currentSPS = nil
        currentPPS = nil
        nalBuffer.removeAll()
    }

    deinit {
        invalidate()
    }

    // MARK: - Annex B Parsing

    private static let startCode3: [UInt8] = [0x00, 0x00, 0x01]
    private static let startCode4: [UInt8] = [0x00, 0x00, 0x00, 0x01]

    private func extractAndProcessNALUnits() {
        let nalUnits = splitAnnexBNALUnits(nalBuffer)
        guard !nalUnits.isEmpty else { return }

        // Keep any trailing incomplete NAL data
        if let lastStartCode = findLastStartCode(in: nalBuffer) {
            // Check if the last NAL is complete (has end marker or next start code)
            let remaining = nalBuffer.suffix(from: lastStartCode)
            let innerUnits = splitAnnexBNALUnits(remaining)
            if innerUnits.count <= 1 {
                // Last NAL might be incomplete — keep it
                nalBuffer = Data(remaining)
            } else {
                nalBuffer.removeAll(keepingCapacity: true)
            }
        } else {
            nalBuffer.removeAll(keepingCapacity: true)
        }

        for nal in nalUnits {
            processNALUnit(nal)
        }
    }

    private func splitAnnexBNALUnits(_ data: Data) -> [Data] {
        var units: [Data] = []
        var i = 0
        let bytes = [UInt8](data)
        let count = bytes.count

        var nalStart = -1

        while i < count {
            // Look for start code (00 00 01 or 00 00 00 01)
            if i + 2 < count && bytes[i] == 0x00 && bytes[i + 1] == 0x00 {
                var startCodeLen = 0
                if bytes[i + 2] == 0x01 {
                    startCodeLen = 3
                } else if i + 3 < count && bytes[i + 2] == 0x00 && bytes[i + 3] == 0x01 {
                    startCodeLen = 4
                }

                if startCodeLen > 0 {
                    if nalStart >= 0 {
                        // Save previous NAL unit
                        let nalData = Data(bytes[nalStart..<i])
                        if !nalData.isEmpty { units.append(nalData) }
                    }
                    nalStart = i + startCodeLen
                    i += startCodeLen
                    continue
                }
            }
            i += 1
        }

        // Last NAL unit
        if nalStart >= 0 && nalStart < count {
            let nalData = Data(bytes[nalStart..<count])
            if !nalData.isEmpty { units.append(nalData) }
        }

        return units
    }

    private func findLastStartCode(in data: Data) -> Data.Index? {
        let bytes = [UInt8](data)
        let count = bytes.count
        var lastIndex: Int? = nil

        var i = 0
        while i < count - 2 {
            if bytes[i] == 0x00 && bytes[i + 1] == 0x00 {
                if bytes[i + 2] == 0x01 {
                    lastIndex = i
                    i += 3
                } else if i + 3 < count && bytes[i + 2] == 0x00 && bytes[i + 3] == 0x01 {
                    lastIndex = i
                    i += 4
                } else {
                    i += 1
                }
            } else {
                i += 1
            }
        }

        return lastIndex.map { data.startIndex.advanced(by: $0) }
    }

    // MARK: - NAL Unit Processing

    private func processNALUnit(_ nalData: Data) {
        guard !nalData.isEmpty else { return }

        let nalType = nalData[nalData.startIndex] & 0x1F

        switch nalType {
        case 7: // SPS
            if currentSPS != nalData {
                currentSPS = nalData
                parseSPSResolution(nalData)
                recreateDecompressionSession()
            }
        case 8: // PPS
            if currentPPS != nalData {
                currentPPS = nalData
                recreateDecompressionSession()
            }
        case 5: // IDR (keyframe)
            decodeVideoNAL(nalData, isKeyFrame: true)
        case 1: // Non-IDR (P/B frame)
            decodeVideoNAL(nalData, isKeyFrame: false)
        default:
            break // SEI, AUD, etc — skip
        }
    }

    // MARK: - SPS Resolution Parsing (simplified)

    private func parseSPSResolution(_ sps: Data) {
        // Basic SPS parsing for width/height
        // Full parsing requires exp-golomb decoding; for now we rely on
        // CMVideoFormatDescription to report the correct dimensions.
    }

    // MARK: - Decompression Session

    private func recreateDecompressionSession() {
        guard let sps = currentSPS, let pps = currentPPS else { return }

        // Invalidate old session
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }

        // Create format description from SPS/PPS
        let spsPointer = [UInt8](sps)
        let ppsPointer = [UInt8](pps)

        var newFormat: CMVideoFormatDescription?
        let parameterSetPointers: [UnsafePointer<UInt8>] = spsPointer.withUnsafeBufferPointer { spsBuf in
            ppsPointer.withUnsafeBufferPointer { ppsBuf in
                [spsBuf.baseAddress!, ppsBuf.baseAddress!]
            }
        }

        // We need stable pointers for the C API
        let spsArray = [UInt8](sps)
        let ppsArray = [UInt8](pps)
        let parameterSetSizes = [spsArray.count, ppsArray.count]

        spsArray.withUnsafeBufferPointer { spsPtr in
            ppsArray.withUnsafeBufferPointer { ppsPtr in
                let pointers = [spsPtr.baseAddress!, ppsPtr.baseAddress!]
                pointers.withUnsafeBufferPointer { pointersPtr in
                    parameterSetSizes.withUnsafeBufferPointer { sizesPtr in
                        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: pointersPtr.baseAddress!,
                            parameterSetSizes: sizesPtr.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &newFormat
                        )
                        if status != noErr {
                            print("[Decoder] Failed to create format description: \(status)")
                        }
                    }
                }
            }
        }

        guard let format = newFormat else { return }
        formatDescription = format

        // Extract dimensions
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)
        if width != currentWidth || height != currentHeight {
            currentWidth = width
            currentHeight = height
            onResolutionChanged?(width, height)
        }

        // Configure output pixel buffer attributes for zero-copy Metal
        let outputAttributes: [NSString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
        ]

        // Create decompression session
        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: format,
            decoderSpecification: nil,
            imageBufferAttributes: outputAttributes as CFDictionary,
            outputCallback: &callbackRecord,
            decompressionSessionOut: &decompressionSession
        )

        if status == noErr {
            // Enable real-time decoding for lowest latency
            VTSessionSetProperty(decompressionSession!, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
            print("[Decoder] Session created: \(width)×\(height)")
        } else {
            print("[Decoder] Failed to create decompression session: \(status)")
        }
    }

    // MARK: - Decode Video Frame

    private func decodeVideoNAL(_ nalData: Data, isKeyFrame: Bool) {
        guard let session = decompressionSession,
              let format = formatDescription else {
            // If we get video data without a session, request keyframe
            return
        }

        // Convert NAL unit to AVCC format (4-byte length prefix)
        var avccData = Data(count: 4 + nalData.count)
        let length = UInt32(nalData.count).bigEndian
        avccData.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: length, as: UInt32.self)
        }
        avccData.replaceSubrange(4..<4 + nalData.count, with: nalData)

        // Create CMBlockBuffer
        var blockBuffer: CMBlockBuffer?
        let avccCount = avccData.count
        avccData.withUnsafeMutableBytes { rawPtr in
            guard let baseAddress = rawPtr.baseAddress else { return }
            let memoryBlock = UnsafeMutableRawPointer.allocate(
                byteCount: avccCount,
                alignment: MemoryLayout<UInt8>.alignment
            )
            memoryBlock.copyMemory(from: baseAddress, byteCount: avccCount)

            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: memoryBlock,
                blockLength: avccCount,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: avccCount,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }

        guard let buffer = blockBuffer else { return }

        // Create CMSampleBuffer
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: CMTime(value: 0, timescale: 1000),
            decodeTimeStamp: CMTime.invalid
        )

        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: buffer,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard let sample = sampleBuffer else { return }

        // Decode
        var flags: VTDecodeInfoFlags = []
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: [._EnableAsynchronousDecompression, ._EnableTemporalProcessing],
            frameRefcon: nil,
            infoFlagsOut: &flags
        )

        if decodeStatus != noErr {
            print("[Decoder] Decode error: \(decodeStatus)")
        }
    }
}

// MARK: - Decompression Callback (C function)

private func decompressionCallback(
    decompressionOutputRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTDecodeInfoFlags,
    imageBuffer: CVImageBuffer?,
    presentationTimeStamp: CMTime,
    presentationDuration: CMTime
) {
    guard status == noErr,
          let refCon = decompressionOutputRefCon,
          let pixelBuffer = imageBuffer else { return }

    let decoder = Unmanaged<DeviceStreamDecoder>.fromOpaque(refCon).takeUnretainedValue()
    decoder.onDecodedFrame?(pixelBuffer)
}
