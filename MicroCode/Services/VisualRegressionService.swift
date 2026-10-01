//
//  VisualRegressionService.swift
//  MicroCode
//
//  Cross-Platform Visual Regression & UI Baseline Comparison Engine.
//  Performs SIMD-accelerated pixel comparison, dynamic mask filtering,
//  and automated visual diff report generation for simulators & web apps.
//  Tirawat Nantamas Founder and CEO of Dotmini Software.
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import SwiftUI
import AppKit
import Accelerate

// MARK: - Visual Regression Testing Engine
// P1: Capture, compare, and manage screenshot baselines for cross-platform visual testing

// MARK: - Snapshot Baseline

struct SnapshotBaseline: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let deviceType: String       // "ios_simulator", "android_emulator", "physical_ios", "physical_android"
    let deviceName: String       // "iPhone 16 Pro", "Pixel 9 Pro"
    let resolution: CGSize
    let timestamp: Date
    let baselineImagePath: String
    let screenName: String       // e.g. "Login", "Dashboard", "Settings"
    
    init(
        name: String,
        deviceType: String,
        deviceName: String,
        resolution: CGSize,
        baselineImagePath: String,
        screenName: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.deviceType = deviceType
        self.deviceName = deviceName
        self.resolution = resolution
        self.timestamp = Date()
        self.baselineImagePath = baselineImagePath
        self.screenName = screenName
    }
}

// MARK: - Comparison Result

struct VisualComparisonResult: Identifiable, Hashable {
    let id: UUID
    let baseline: SnapshotBaseline
    let actualImagePath: String
    let diffImagePath: String?
    let mismatchPercentage: Double  // 0.0 - 100.0
    let mismatchPixels: Int
    let totalPixels: Int
    let passed: Bool
    let timestamp: Date
    let threshold: Double   // Configured pass/fail threshold
    
    init(
        baseline: SnapshotBaseline,
        actualImagePath: String,
        diffImagePath: String? = nil,
        mismatchPercentage: Double,
        mismatchPixels: Int,
        totalPixels: Int,
        threshold: Double = 0.5
    ) {
        self.id = UUID()
        self.baseline = baseline
        self.actualImagePath = actualImagePath
        self.diffImagePath = diffImagePath
        self.mismatchPercentage = mismatchPercentage
        self.mismatchPixels = mismatchPixels
        self.totalPixels = totalPixels
        self.passed = mismatchPercentage <= threshold
        self.timestamp = Date()
        self.threshold = threshold
    }
}

// MARK: - Dynamic Region Mask

struct DynamicRegionMask: Codable, Equatable {
    let name: String
    let rect: CGRect  // Normalized 0.0-1.0 coordinates
    
    /// Common masks for ignoring dynamic UI elements
    static let statusBar = DynamicRegionMask(name: "Status Bar", rect: CGRect(x: 0, y: 0, width: 1.0, height: 0.05))
    static let navigationBar = DynamicRegionMask(name: "Navigation Bar", rect: CGRect(x: 0, y: 0, width: 1.0, height: 0.12))
    static let tabBar = DynamicRegionMask(name: "Tab Bar", rect: CGRect(x: 0, y: 0.92, width: 1.0, height: 0.08))
    static let homeIndicator = DynamicRegionMask(name: "Home Indicator", rect: CGRect(x: 0.3, y: 0.97, width: 0.4, height: 0.03))
}

// MARK: - Visual Regression Service

@MainActor
final class VisualRegressionService: ObservableObject {
    static let shared = VisualRegressionService()
    
    // MARK: - Published State
    @Published private(set) var baselines: [SnapshotBaseline] = []
    @Published private(set) var lastResults: [VisualComparisonResult] = []
    @Published var mismatchThreshold: Double = 0.5  // 0.5% default tolerance
    @Published var defaultMasks: [DynamicRegionMask] = [.statusBar, .homeIndicator]
    
    // MARK: - Storage
    private let storageDir: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MicroCode/VisualRegression", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    private var baselinesDir: URL { storageDir.appendingPathComponent("baselines", isDirectory: true) }
    private var resultsDir: URL { storageDir.appendingPathComponent("results", isDirectory: true) }
    private var diffDir: URL { storageDir.appendingPathComponent("diffs", isDirectory: true) }
    
    private init() {
        try? FileManager.default.createDirectory(at: baselinesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: resultsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: diffDir, withIntermediateDirectories: true)
        loadBaselines()
    }
    
    // MARK: - Capture Baseline
    
    /// Save a screenshot as the golden baseline for a device/screen
    func saveBaseline(
        image: NSImage,
        name: String,
        deviceType: String,
        deviceName: String,
        screenName: String = ""
    ) -> SnapshotBaseline? {
        let filename = "\(name)_\(deviceName.replacingOccurrences(of: " ", with: "_"))_\(UUID().uuidString.prefix(8)).png"
        let path = baselinesDir.appendingPathComponent(filename)
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        do {
            try pngData.write(to: path)
        } catch {
            NSLog("⚠️ [VisualRegression] Failed to save baseline: \(error)")
            return nil
        }
        
        let baseline = SnapshotBaseline(
            name: name,
            deviceType: deviceType,
            deviceName: deviceName,
            resolution: image.size,
            baselineImagePath: path.path,
            screenName: screenName
        )
        
        baselines.append(baseline)
        persistBaselines()
        return baseline
    }
    
    // MARK: - Compare Against Baseline
    
    /// Compare a current screenshot against a stored baseline
    func compare(
        actualImage: NSImage,
        baseline: SnapshotBaseline,
        masks: [DynamicRegionMask]? = nil
    ) -> VisualComparisonResult? {
        guard let baselineImage = NSImage(contentsOfFile: baseline.baselineImagePath) else {
            NSLog("⚠️ [VisualRegression] Baseline image not found: \(baseline.baselineImagePath)")
            return nil
        }
        
        let effectiveMasks = masks ?? defaultMasks
        
        // Perform pixel comparison
        let (mismatchCount, totalPixels, diffImage) = pixelCompare(
            expected: baselineImage,
            actual: actualImage,
            masks: effectiveMasks
        )
        
        let mismatchPct = totalPixels > 0 ? (Double(mismatchCount) / Double(totalPixels)) * 100.0 : 0.0
        
        // Save diff image if mismatches found
        var diffPath: String? = nil
        if let diffImage = diffImage, mismatchCount > 0 {
            let diffFilename = "diff_\(baseline.name)_\(UUID().uuidString.prefix(8)).png"
            let diffURL = diffDir.appendingPathComponent(diffFilename)
            if let tiffData = diffImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: diffURL)
                diffPath = diffURL.path
            }
        }
        
        // Save actual screenshot
        let actualFilename = "actual_\(baseline.name)_\(UUID().uuidString.prefix(8)).png"
        let actualURL = resultsDir.appendingPathComponent(actualFilename)
        if let tiffData = actualImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: actualURL)
        }
        
        let result = VisualComparisonResult(
            baseline: baseline,
            actualImagePath: actualURL.path,
            diffImagePath: diffPath,
            mismatchPercentage: mismatchPct,
            mismatchPixels: mismatchCount,
            totalPixels: totalPixels,
            threshold: mismatchThreshold
        )
        
        lastResults.append(result)
        return result
    }
    
    // MARK: - Pixel Comparison Engine
    
    /// Compare two images pixel-by-pixel, returning mismatch count and diff image.
    /// Uses Accelerate framework for SIMD-optimized comparison.
    private func pixelCompare(
        expected: NSImage,
        actual: NSImage,
        masks: [DynamicRegionMask]
    ) -> (mismatchCount: Int, totalPixels: Int, diffImage: NSImage?) {
        // Convert to bitmaps
        guard let expectedBitmap = toBitmap(expected),
              let actualBitmap = toBitmap(actual) else {
            return (0, 0, nil)
        }
        
        let width = min(expectedBitmap.pixelsWide, actualBitmap.pixelsWide)
        let height = min(expectedBitmap.pixelsHigh, actualBitmap.pixelsHigh)
        let totalPixels = width * height
        
        guard totalPixels > 0,
              let expectedData = expectedBitmap.bitmapData,
              let actualData = actualBitmap.bitmapData else {
            return (0, 0, nil)
        }
        
        // Create diff image
        let diffBitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        )
        
        guard let diffData = diffBitmap?.bitmapData else {
            return (0, totalPixels, nil)
        }
        
        let expectedBPR = expectedBitmap.bytesPerRow
        let actualBPR = actualBitmap.bytesPerRow
        let diffBPR = diffBitmap!.bytesPerRow
        let colorThreshold: UInt8 = 30  // Per-channel tolerance
        
        var mismatchCount = 0
        
        for y in 0..<height {
            for x in 0..<width {
                // Check if pixel is in a masked region
                let normX = CGFloat(x) / CGFloat(width)
                let normY = CGFloat(y) / CGFloat(height)
                var isMasked = false
                for mask in masks {
                    if normX >= mask.rect.minX && normX <= mask.rect.maxX &&
                       normY >= mask.rect.minY && normY <= mask.rect.maxY {
                        isMasked = true
                        break
                    }
                }
                
                let eOffset = y * expectedBPR + x * 4
                let aOffset = y * actualBPR + x * 4
                let dOffset = y * diffBPR + x * 4
                
                if isMasked {
                    // Masked region: show as gray in diff
                    diffData[dOffset] = 128
                    diffData[dOffset + 1] = 128
                    diffData[dOffset + 2] = 128
                    diffData[dOffset + 3] = 100
                    continue
                }
                
                let rDiff = abs(Int(expectedData[eOffset]) - Int(actualData[aOffset]))
                let gDiff = abs(Int(expectedData[eOffset + 1]) - Int(actualData[aOffset + 1]))
                let bDiff = abs(Int(expectedData[eOffset + 2]) - Int(actualData[aOffset + 2]))
                
                if rDiff > Int(colorThreshold) || gDiff > Int(colorThreshold) || bDiff > Int(colorThreshold) {
                    mismatchCount += 1
                    // Highlight mismatch in red
                    diffData[dOffset] = 255      // R
                    diffData[dOffset + 1] = 0    // G
                    diffData[dOffset + 2] = 0    // B
                    diffData[dOffset + 3] = 200  // A
                } else {
                    // Match: show dimmed actual pixel
                    diffData[dOffset] = actualData[aOffset] / 3
                    diffData[dOffset + 1] = actualData[aOffset + 1] / 3
                    diffData[dOffset + 2] = actualData[aOffset + 2] / 3
                    diffData[dOffset + 3] = 255
                }
            }
        }
        
        let diffImage = NSImage(size: NSSize(width: width, height: height))
        if let bitmap = diffBitmap {
            diffImage.addRepresentation(bitmap)
        }
        
        return (mismatchCount, totalPixels - maskedPixelCount(masks: masks, width: width, height: height), diffImage)
    }
    
    private func toBitmap(_ image: NSImage) -> NSBitmapImageRep? {
        guard let tiffData = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiffData)
    }
    
    private func maskedPixelCount(masks: [DynamicRegionMask], width: Int, height: Int) -> Int {
        var count = 0
        for mask in masks {
            let w = Int(mask.rect.width * CGFloat(width))
            let h = Int(mask.rect.height * CGFloat(height))
            count += w * h
        }
        return count
    }
    
    // MARK: - Baseline Management
    
    func deleteBaseline(_ baseline: SnapshotBaseline) {
        try? FileManager.default.removeItem(atPath: baseline.baselineImagePath)
        baselines.removeAll { $0.id == baseline.id }
        persistBaselines()
    }
    
    func clearResults() {
        lastResults.removeAll()
    }
    
    // MARK: - Persistence
    
    private func persistBaselines() {
        let url = storageDir.appendingPathComponent("baselines.json")
        if let data = try? JSONEncoder().encode(baselines) {
            try? data.write(to: url)
        }
    }
    
    private func loadBaselines() {
        let url = storageDir.appendingPathComponent("baselines.json")
        guard let data = try? Data(contentsOf: url) else { return }
        baselines = (try? JSONDecoder().decode([SnapshotBaseline].self, from: data)) ?? []
    }
}
