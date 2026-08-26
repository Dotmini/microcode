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

@MainActor
public final class AppleVisionEngine {
    public static let shared = AppleVisionEngine()
    
    private init() {}
    
    /// Analyzes an image data payload using Apple Neural Engine Vision & OCR
    public func analyzeImage(data: Data, filename: String = "image.png") async -> VisionAnalysisResult {
        guard let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return VisionAnalysisResult(
                filename: filename,
                dimensions: .zero,
                extractedText: "",
                recognizedLines: [],
                detectedElements: [],
                isCodeOrTerminal: false,
                formattedSummary: "[Image: \(filename)] (Unable to decode image bitmap)"
            )
        }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let dimensions = CGSize(width: width, height: height)
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var recognizedLines: [String] = []
                var detectedElements: [String] = []
                
                // 1. Text & Code OCR Recognition Request
                let textRequest = VNRecognizeTextRequest { request, error in
                    guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                        return
                    }
                    
                    for observation in observations {
                        if let topCandidate = observation.topCandidates(1).first {
                            let text = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !text.isEmpty {
                                recognizedLines.append(text)
                            }
                        }
                    }
                }
                
                textRequest.recognitionLevel = .accurate
                textRequest.usesCPUOnly = false // Use Apple Silicon Neural Engine (ANE)
                textRequest.recognitionLanguages = ["en-US", "th-TH", "zh-Hans", "ja-JP"]
                
                // 2. Rectangle / UI Box Detection Request
                let rectRequest = VNDetectRectanglesRequest { request, error in
                    guard let observations = request.results as? [VNRectangleObservation], error == nil else {
                        return
                    }
                    if observations.count > 0 {
                        detectedElements.append("\(observations.count) UI containers/panels detected")
                    }
                }
                rectRequest.minimumConfidence = 0.6
                
                // 3. Image Classification / Scene Understanding Request
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
                
                // Execute Vision Pipeline
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([textRequest, rectRequest, classifyRequest])
                
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
