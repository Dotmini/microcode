//
//  AppleVisionEngine.swift
//  MicroCode
//
//  Production Universal Vision & OCR Adapter for AI Agent Harness
//  Enables 100% of LLMs (Text-Only, Local, DeepSeek, Qwen, Llama, etc.)
//  to see, read, and understand images via Apple Neural Engine Vision.
//

import Foundation
import AppKit
import ImageIO
import Vision
import CoreImage

// MARK: - Vision Analysis Result

public struct VisionAnalysisResult {
    public let filename: String
    public let dimensions: CGSize
    public let extractedText: String
    public let recognizedLines: [String]
    public let detectedElements: [String]
    public let isCodeOrTerminal: Bool
    public let formattedSummary: String
}

// MARK: - Apple Vision Engine

public final class AppleVisionEngine: @unchecked Sendable {
    public static let shared = AppleVisionEngine()
    
    private init() {}
    
    /// Thread-safe CGImage decoder that avoids @MainActor NSImage contention.
    private static func decodeCGImage(from data: Data) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        if let src = CGImageSourceCreateWithData(data as CFData, options as CFDictionary),
           let cg = CGImageSourceCreateImageAtIndex(src, 0, options as CFDictionary) {
            return cg
        }
        if let rep = NSBitmapImageRep(data: data), let cg = rep.cgImage {
            return cg
        }
        return nil
    }

    /// Analyzes an image data payload using Apple Neural Engine Vision & OCR off the MainActor.
    public func analyzeImage(
        data: Data,
        filename: String = "image.png",
        fastPreview: Bool = false,
        includeSceneClassification: Bool = false
    ) async -> VisionAnalysisResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = Self.decodeCGImage(from: data) else {
                    continuation.resume(returning: VisionAnalysisResult(
                        filename: filename,
                        dimensions: .zero,
                        extractedText: "",
                        recognizedLines: [],
                        detectedElements: [],
                        isCodeOrTerminal: false,
                        formattedSummary: "[Image: \(filename)] (Unable to decode image bitmap)"
                    ))
                    return
                }
                
                let width = CGFloat(cgImage.width)
                let height = CGFloat(cgImage.height)
                let dimensions = CGSize(width: width, height: height)
                var recognizedLines: [String] = []
                var detectedElements: [String] = []
                
                // 1. Text & Code OCR Recognition Request
                func extractLines(from request: VNRecognizeTextRequest) -> [String] {
                    guard let observations = request.results else { return [] }
                    var lines: [String] = []
                    lines.reserveCapacity(observations.count)
                    for observation in observations {
                        if let topCandidate = observation.topCandidates(1).first {
                            let text = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !text.isEmpty {
                                lines.append(text)
                            }
                        }
                    }
                    return lines
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                let primaryTextReq = VNRecognizeTextRequest()
                primaryTextReq.recognitionLevel = fastPreview ? .fast : .accurate
                if !fastPreview {
                    if #available(macOS 13.0, *) {
                        primaryTextReq.automaticallyDetectsLanguage = true
                    }
                    primaryTextReq.recognitionLanguages = ["th-TH", "en-US", "zh-Hans", "ja-JP"]
                } else {
                    primaryTextReq.recognitionLanguages = ["en-US"]
                }
                do {
                    try handler.perform([primaryTextReq])
                    recognizedLines = extractLines(from: primaryTextReq)
                } catch {
                    // Fallback when Apple Neural Engine e5rt is restricted (e.g. headless CI, VM, or sandboxed process)
                    let fallbackFastReq = VNRecognizeTextRequest()
                    fallbackFastReq.recognitionLevel = .fast
                    fallbackFastReq.recognitionLanguages = ["en-US"]
                    if (try? handler.perform([fallbackFastReq])) != nil {
                        recognizedLines = extractLines(from: fallbackFastReq)
                    }
                    if recognizedLines.isEmpty && !fastPreview {
                        let legacyReq = VNRecognizeTextRequest()
                        legacyReq.revision = 2
                        legacyReq.recognitionLevel = .accurate
                        if (try? handler.perform([legacyReq])) != nil {
                            recognizedLines = extractLines(from: legacyReq)
                        }
                    }
                }

                if includeSceneClassification {
                    // 2. Optional Rectangle / UI Box Detection Request
                    let rectRequest = VNDetectRectanglesRequest { request, error in
                        guard let observations = request.results as? [VNRectangleObservation], error == nil else {
                            return
                        }
                        if observations.count > 0 {
                            detectedElements.append("\(observations.count) UI containers/panels detected")
                        }
                    }
                    rectRequest.minimumConfidence = 0.6
                    try? handler.perform([rectRequest])

                    // 3. Optional Image Classification / Scene Understanding Request
                    let classifyRequest = VNClassifyImageRequest { request, error in
                        guard let observations = request.results as? [VNClassificationObservation], error == nil else {
                            return
                        }
                        let topClasses = observations.prefix(3)
                            .filter { $0.confidence > 0.4 }
                            .map { "\($0.identifier) (\(Int($0.confidence * 100))%)" }
                        if !topClasses.isEmpty {
                            detectedElements.append("Scene context: " + topClasses.joined(separator: ", "))
                        }
                    }
                    try? handler.perform([classifyRequest])
                }
                
                let extractedText = recognizedLines.joined(separator: "\n")
                
                // Heuristic detection for Code/Terminal/UI screenshot
                let lowerText = extractedText.lowercased()
                let isCodeOrTerminal = lowerText.contains("error") || lowerText.contains("func ") ||
                    lowerText.contains("import ") || lowerText.contains("class ") ||
                    lowerText.contains("const ") || lowerText.contains("let ") ||
                    lowerText.contains("var ") || lowerText.contains("def ") ||
                    lowerText.contains("return") || lowerText.contains("line ") ||
                    lowerText.contains("warning") || lowerText.contains("{") ||
                    lowerText.contains("}") || lowerText.contains("console.")
                
                // Format rich prompt descriptor
                var summary = """
                [Visual Description & OCR for Image: '\(filename)']
                Dimensions: \(Int(width)) × \(Int(height)) px
                """
                
                if !detectedElements.isEmpty {
                    summary += "\nLayout & Scene: " + detectedElements.joined(separator: " | ")
                }
                
                if isCodeOrTerminal {
                    summary += "\nContent Type: Code / Terminal Output / UI Error Dialog"
                }
                
                if !extractedText.isEmpty {
                    summary += "\n\n--- OCR Extracted Text & Code ---\n"
                    summary += extractedText
                    summary += "\n--- End of Visual Content ---"
                } else {
                    summary += "\n\n(No readable text found in image - purely graphical content)"
                }
                
                let result = VisionAnalysisResult(
                    filename: filename,
                    dimensions: dimensions,
                    extractedText: extractedText,
                    recognizedLines: recognizedLines,
                    detectedElements: detectedElements,
                    isCodeOrTerminal: isCodeOrTerminal,
                    formattedSummary: summary
                )
                
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Synchronous / Quick descriptor generator for offline pipelines
    public func quickDescribe(data: Data, filename: String = "image.png") -> String {
        guard let nsImage = NSImage(data: data) else {
            return "[Image: \(filename)] (Unable to decode image)"
        }
        let size = nsImage.size
        return "[Image: \(filename) (\(Int(size.width))×\(Int(size.height)) px, \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))]"
    }
}
