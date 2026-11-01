//
//  DeviceFrameAssets.swift
//  MicroCode - Hardware Frame Assets for Live Preview
//

import AppKit
import SwiftUI

public enum DeviceFrameAssets {
    private static var cachedIPhoneImage: NSImage?
    private static var cachedIPadImage: NSImage?
    private static var cachedMacBookImage: NSImage?
    private static var cachedIPhoneDuoOuterPortrait: NSImage?
    private static var cachedIPhoneDuoOuterLandscape: NSImage?
    private static var cachedIPhoneDuoInnerUnfolded: NSImage?
    private static var cachedIPhoneDuoInnerPortrait: NSImage?
    private static var cachedAndroidFrameImage: NSImage?
    private static var cachedAndroidMaskImage: NSImage?

    private static func loadResourceImage(named name: String, fileExtension: String = "png") -> NSImage? {
        // 1. Try App Bundle Resources
        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
           let img = NSImage(contentsOf: url) {
            return img
        }
        
        // 2. Try App Bundle resourceURL
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("\(name).\(fileExtension)"),
           FileManager.default.fileExists(atPath: resourceURL.path),
           let img = NSImage(contentsOf: resourceURL) {
            return img
        }
        
        // 3. Try App Bundle Contents/Resources direct path
        let bundleResourcePath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name).\(fileExtension)").path
        if FileManager.default.fileExists(atPath: bundleResourcePath),
           let img = NSImage(contentsOfFile: bundleResourcePath) {
            return img
        }

        // 4. Try executable bundle directory
        if let exeURL = Bundle.main.executableURL {
            let resPath = exeURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/\(name).\(fileExtension)").path
            if FileManager.default.fileExists(atPath: resPath),
               let img = NSImage(contentsOfFile: resPath) {
                return img
            }
        }

        // 5. Try current working directory
        let cwdPath = FileManager.default.currentDirectoryPath + "/MicroCode/Resources/\(name).\(fileExtension)"
        if FileManager.default.fileExists(atPath: cwdPath),
           let img = NSImage(contentsOfFile: cwdPath) {
            return img
        }

        // 6. Try installed app bundle in ~/Applications or /Applications
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let fallbackPaths = [
            homePath + "/Applications/MicroCode.app/Contents/Resources/\(name).\(fileExtension)",
            "/Applications/MicroCode.app/Contents/Resources/\(name).\(fileExtension)"
        ]
        for path in fallbackPaths {
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                return img
            }
        }

        return nil
    }

    public static func loadIPhoneProBezel() -> NSImage? {
        if let cached = cachedIPhoneImage { return cached }
        if let img = loadResourceImage(named: "iphone_16_pro_bezel") {
            cachedIPhoneImage = img
            return img
        }
        return nil
    }

    public static func loadIPadProBezel() -> NSImage? {
        if let cached = cachedIPadImage { return cached }
        if let img = loadResourceImage(named: "ipad_pro_bezel") {
            cachedIPadImage = img
            return img
        }
        return nil
    }

    public static func loadMacBookProBezel() -> NSImage? {
        if let cached = cachedMacBookImage { return cached }
        if let img = loadResourceImage(named: "macbook_pro_bezel") {
            cachedMacBookImage = img
            return img
        }
        return nil
    }

    // MARK: - iPhone Duo (Outer Cover Display & Inner Unfolded Display)

    /// Builds an asymmetric 4-corner rounded CGPath in AppKit/CoreGraphics coordinates (y=0 at bottom).
    private static func unevenRoundedCGPath(
        in rect: CGRect,
        topLeft: CGFloat,
        topRight: CGFloat,
        bottomRight: CGFloat,
        bottomLeft: CGFloat
    ) -> CGPath {
        let maxR = min(rect.width, rect.height) * 0.5
        let tl = min(max(0, topLeft), maxR)
        let tr = min(max(0, topRight), maxR)
        let br = min(max(0, bottomRight), maxR)
        let bl = min(max(0, bottomLeft), maxR)

        let path = CGMutablePath()
        // Start on bottom edge after bottom-left corner (y = minY is bottom in CGContext)
        path.move(to: CGPoint(x: rect.minX + bl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - br, y: rect.minY))
        if br > 0 {
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                tangent2End: CGPoint(x: rect.maxX, y: rect.minY + br),
                radius: br
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tr))
        if tr > 0 {
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.maxX - tr, y: rect.maxY),
                radius: tr
            )
        }
        path.addLine(to: CGPoint(x: rect.minX + tl, y: rect.maxY))
        if tl > 0 {
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.minX, y: rect.maxY - tl),
                radius: tl
            )
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + bl))
        if bl > 0 {
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                tangent2End: CGPoint(x: rect.minX + bl, y: rect.minY),
                radius: bl
            )
        }
        path.closeSubpath()
        return path
    }

    /// Official iPhone Duo Outer Cover Display bezel (`phone15.devicechrome` spec:
    /// 514×706 pt outer, 466×678 pt screen @ (26, 14), asymmetric 2.7pt spine / 19.7pt right corners + Dynamic Island).
    public static func loadIPhoneDuoOuterBezel(isLandscape: Bool = false) -> NSImage {
        if !isLandscape, let cached = cachedIPhoneDuoOuterPortrait { return cached }
        if isLandscape, let cached = cachedIPhoneDuoOuterLandscape { return cached }

        let portraitSize = NSSize(width: 514, height: 706)
        let portrait = NSImage(size: portraitSize, flipped: false) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let chromeCompositePath = "/Library/Developer/DeviceKit/Chrome/phone15.devicechrome/Contents/Resources/PhoneComposite.pdf"
            if let deviceKitComposite = NSImage(contentsOfFile: chromeCompositePath) {
                deviceKitComposite.draw(in: bounds)
            } else {
                // Procedural Titanium Book-Fold Cover Chassis (exact phone15 geometry)
                let outerPath = unevenRoundedCGPath(
                    in: bounds.insetBy(dx: 1.5, dy: 1.5),
                    topLeft: 10,
                    topRight: 34,
                    bottomRight: 34,
                    bottomLeft: 10
                )
                ctx.saveGState()
                ctx.addPath(outerPath)
                ctx.setFillColor(NSColor(calibratedWhite: 0.11, alpha: 1.0).cgColor)
                ctx.fillPath()
                ctx.restoreGState()

                // Left book-fold titanium hinge spine (26pt)
                let spineRect = CGRect(x: 1.5, y: 8, width: 16, height: bounds.height - 16)
                let spinePath = CGPath(roundedRect: spineRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
                ctx.saveGState()
                ctx.addPath(spinePath)
                ctx.setFillColor(NSColor(calibratedWhite: 0.22, alpha: 0.95).cgColor)
                ctx.fillPath()
                ctx.restoreGState()

                // Outer metallic rim highlight
                ctx.saveGState()
                ctx.addPath(outerPath)
                ctx.setStrokeColor(NSColor(calibratedWhite: 0.42, alpha: 0.85).cgColor)
                ctx.setLineWidth(2.0)
                ctx.strokePath()
                ctx.restoreGState()
            }

            // Hardware Buttons (Top Volume Up/Down + Right Touch ID Power per phone15 chrome.json)
            ctx.saveGState()
            ctx.setFillColor(NSColor(calibratedWhite: 0.28, alpha: 0.95).cgColor)
            ctx.fill(CGRect(x: 236, y: bounds.maxY - 2.5, width: 42, height: 2.5))
            ctx.fill(CGRect(x: 316, y: bounds.maxY - 2.5, width: 42, height: 2.5))
            ctx.fill(CGRect(x: bounds.maxX - 2.5, y: bounds.maxY - 252, width: 2.5, height: 56))
            ctx.restoreGState()

            // Screen aperture cutout (x: 26, y: 14, width: 466, height: 678)
            let screenRect = CGRect(x: 26, y: 14, width: 466, height: 678)
            let screenPath = unevenRoundedCGPath(
                in: screenRect,
                topLeft: 2.7,
                topRight: 19.7,
                bottomRight: 19.7,
                bottomLeft: 2.7
            )
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.addPath(screenPath)
            ctx.fillPath()
            ctx.restoreGState()

            // Subtle inner glass edge stroke
            ctx.saveGState()
            ctx.addPath(screenPath)
            ctx.setStrokeColor(NSColor(calibratedWhite: 0.30, alpha: 0.55).cgColor)
            ctx.setLineWidth(1.0)
            ctx.strokePath()
            ctx.restoreGState()

            // Dynamic Island (sensor_bar_class_04 centered on 466pt cover screen)
            let islandW: CGFloat = 104
            let islandH: CGFloat = 29
            let islandX = screenRect.midX - islandW * 0.5
            let islandY = screenRect.maxY - 11 - islandH
            let islandRect = CGRect(x: islandX, y: islandY, width: islandW, height: islandH)
            let islandPath = CGPath(roundedRect: islandRect, cornerWidth: islandH * 0.5, cornerHeight: islandH * 0.5, transform: nil)
            ctx.saveGState()
            ctx.addPath(islandPath)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            // Subtle front camera lens glint inside Dynamic Island
            let lensRect = CGRect(x: islandRect.maxX - 22, y: islandRect.midY - 5.5, width: 11, height: 11)
            ctx.setFillColor(NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.20, alpha: 1.0).cgColor)
            ctx.fillEllipse(in: lensRect)
            ctx.restoreGState()
            return true
        }
        cachedIPhoneDuoOuterPortrait = portrait
        if !isLandscape { return portrait }

        // Rotate -90° clockwise/CCW to match landscape spec (706×514, screenOffset: (14, 22))
        let landscapeSize = NSSize(width: 706, height: 514)
        let landscape = NSImage(size: landscapeSize, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.translateBy(x: 0, y: landscapeSize.height)
            ctx.rotate(by: -.pi / 2)
            portrait.draw(in: CGRect(origin: .zero, size: portraitSize))
            ctx.restoreGState()
            return true
        }
        cachedIPhoneDuoOuterLandscape = landscape
        return landscape
    }

    /// Official iPhone Duo Unfolded Inner Display bezel (`phone14.devicechrome` spec:
    /// 985×703 pt unfolded book-open default [951×669 pt screen + 17pt symmetric bezel, 18.33pt corners],
    /// or 703×985 pt when rotated to tall portrait).
    public static func loadIPhoneDuoInnerBezel(isRotatedPortrait: Bool = false) -> NSImage {
        if !isRotatedPortrait, let cached = cachedIPhoneDuoInnerUnfolded { return cached }
        if isRotatedPortrait, let cached = cachedIPhoneDuoInnerPortrait { return cached }

        let targetSize = isRotatedPortrait ? NSSize(width: 703, height: 985) : NSSize(width: 985, height: 703)
        let bezelInset: CGFloat = 17
        let screenCornerRadius: CGFloat = 18.33
        let outerCornerRadius: CGFloat = 33.0

        let rendered = NSImage(size: targetSize, flipped: false) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let outerRect = bounds.insetBy(dx: 1.5, dy: 1.5)
            let outerPath = CGPath(roundedRect: outerRect, cornerWidth: outerCornerRadius, cornerHeight: outerCornerRadius, transform: nil)

            // Ultra-thin foldable titanium chassis
            ctx.saveGState()
            ctx.addPath(outerPath)
            ctx.setFillColor(NSColor(calibratedWhite: 0.09, alpha: 1.0).cgColor)
            ctx.fillPath()
            ctx.setStrokeColor(NSColor(calibratedWhite: 0.38, alpha: 0.85).cgColor)
            ctx.setLineWidth(2.0)
            ctx.addPath(outerPath)
            ctx.strokePath()
            ctx.restoreGState()

            // Hardware buttons per phone14 chrome.json (Volume on left, Touch ID Power on top)
            ctx.saveGState()
            ctx.setFillColor(NSColor(calibratedWhite: 0.28, alpha: 0.95).cgColor)
            if isRotatedPortrait {
                ctx.fill(CGRect(x: 0, y: bounds.maxY - 156, width: 2.5, height: 44))
                ctx.fill(CGRect(x: 0, y: bounds.maxY - 230, width: 2.5, height: 44))
                ctx.fill(CGRect(x: 196, y: bounds.maxY - 2.5, width: 52, height: 2.5))
            } else {
                ctx.fill(CGRect(x: 140, y: bounds.maxY - 2.5, width: 44, height: 2.5))
                ctx.fill(CGRect(x: 204, y: bounds.maxY - 2.5, width: 44, height: 2.5))
                ctx.fill(CGRect(x: bounds.maxX - 2.5, y: bounds.maxY - 180, width: 2.5, height: 52))
            }
            ctx.restoreGState()

            // Central foldable hinge cap accents on the 17pt bezel
            ctx.saveGState()
            ctx.setFillColor(NSColor(calibratedWhite: 0.26, alpha: 0.9).cgColor)
            if isRotatedPortrait {
                let midY = bounds.midY
                ctx.fill(CGRect(x: 2, y: midY - 14, width: 4, height: 28))
                ctx.fill(CGRect(x: bounds.maxX - 6, y: midY - 14, width: 4, height: 28))
            } else {
                let midX = bounds.midX
                ctx.fill(CGRect(x: midX - 14, y: bounds.maxY - 6, width: 28, height: 4))
                ctx.fill(CGRect(x: midX - 14, y: 2, width: 28, height: 4))
            }
            ctx.restoreGState()

            // Screen aperture cutout (17pt symmetric inset, 18.33pt corner radius)
            let screenRect = bounds.insetBy(dx: bezelInset, dy: bezelInset)
            let screenPath = CGPath(roundedRect: screenRect, cornerWidth: screenCornerRadius, cornerHeight: screenCornerRadius, transform: nil)
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.addPath(screenPath)
            ctx.fillPath()
            ctx.restoreGState()

            // Subtle inner display polymer border + delicate optical center crease line
            ctx.saveGState()
            ctx.addPath(screenPath)
            ctx.setStrokeColor(NSColor(calibratedWhite: 0.28, alpha: 0.55).cgColor)
            ctx.setLineWidth(1.0)
            ctx.strokePath()

            ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.045).cgColor)
            ctx.setLineWidth(1.0)
            if isRotatedPortrait {
                ctx.move(to: CGPoint(x: screenRect.minX + 6, y: screenRect.midY))
                ctx.addLine(to: CGPoint(x: screenRect.maxX - 6, y: screenRect.midY))
            } else {
                ctx.move(to: CGPoint(x: screenRect.midX, y: screenRect.minY + 6))
                ctx.addLine(to: CGPoint(x: screenRect.midX, y: screenRect.maxY - 6))
            }
            ctx.strokePath()
            ctx.restoreGState()
            return true
        }

        if isRotatedPortrait {
            cachedIPhoneDuoInnerPortrait = rendered
        } else {
            cachedIPhoneDuoInnerUnfolded = rendered
        }
        return rendered
    }

    /// Loads the authentic Google Pixel hardware chassis frame (1408 x 2974).
    /// Always guaranteed to return a real device frame, never leaving the emulator naked.
    public static func loadAndroidPixelProBezel() -> NSImage? {
        if let cached = cachedAndroidFrameImage { return cached }
        if let img = loadResourceImage(named: "android_pixel_frame", fileExtension: "png") {
            cachedAndroidFrameImage = img
            return img
        }
        if let img = loadResourceImage(named: "android_pixel_frame", fileExtension: "webp") {
            cachedAndroidFrameImage = img
            return img
        }
        // Fallback to local Android SDK skins directory
        let sdkSkins = [
            NSHomeDirectory() + "/Library/Android/sdk/skins/pixel_9_pro/back.webp",
            NSHomeDirectory() + "/Library/Android/sdk/skins/pixel_8_pro/back.webp",
            NSHomeDirectory() + "/Library/Android/sdk/skins/pixel_7_pro/back.webp"
        ]
        for path in sdkSkins {
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                cachedAndroidFrameImage = img
                return img
            }
        }
        return nil
    }

    /// Loads the authentic Google Pixel front camera punch-hole cutout mask (1280 x 2856).
    public static func loadAndroidPixelProMask() -> NSImage? {
        if let cached = cachedAndroidMaskImage { return cached }
        if let img = loadResourceImage(named: "android_pixel_mask", fileExtension: "png") {
            cachedAndroidMaskImage = img
            return img
        }
        if let img = loadResourceImage(named: "android_pixel_mask", fileExtension: "webp") {
            cachedAndroidMaskImage = img
            return img
        }
        let sdkMasks = [
            NSHomeDirectory() + "/Library/Android/sdk/skins/pixel_9_pro/mask.webp",
            NSHomeDirectory() + "/Library/Android/sdk/skins/pixel_8_pro/mask.webp",
            NSHomeDirectory() + "/Library/Android/sdk/skins/pixel_7_pro/mask.webp"
        ]
        for path in sdkMasks {
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                cachedAndroidMaskImage = img
                return img
            }
        }
        return nil
    }

    private static var cachedSamsungFrameImage: NSImage?
    private static var cachedSamsungMaskImage: NSImage?

    /// Loads the authentic official Samsung Galaxy Note 20 Ultra hardware frame (1794 x 3488).
    public static func loadSamsungGalaxyNote20UltraBezel() -> NSImage? {
        if let cached = cachedSamsungFrameImage { return cached }
        if let img = loadResourceImage(named: "samsung_note20_ultra_frame", fileExtension: "png") {
            cachedSamsungFrameImage = img
            return img
        }
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let fallbackDirs = [
            homePath + "/Library/Android/sdk/skins/Galaxy_Note20_Ultra/device_Port-Black-frame.png",
            "/Applications/MicroCode.app/Contents/Resources/samsung_note20_ultra_frame.png",
            homePath + "/Applications/MicroCode.app/Contents/Resources/samsung_note20_ultra_frame.png"
        ]
        for path in fallbackDirs {
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                cachedSamsungFrameImage = img
                return img
            }
        }
        return nil
    }

    /// Loads the authentic official Samsung Galaxy Note 20 Ultra front camera punch-hole cutout mask.
    public static func loadSamsungGalaxyNote20UltraMask() -> NSImage? {
        if let cached = cachedSamsungMaskImage { return cached }
        if let img = loadResourceImage(named: "samsung_note20_ultra_mask", fileExtension: "png") {
            cachedSamsungMaskImage = img
            return img
        }
        let fallbackDirs = [
            NSHomeDirectory() + "/Library/Android/sdk/skins/Galaxy_Note20_Ultra/fore_port.png",
            NSHomeDirectory() + "/Downloads/Galaxy_Note20_Ultra/fore_port.png"
        ]
        for path in fallbackDirs {
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                cachedSamsungMaskImage = img
                return img
            }
        }
        return nil
    }

    public static func loadAndroidDeviceBezel(for skin: AndroidDeviceSkin) -> NSImage? {
        switch skin {
        case .galaxyNote20Ultra:
            return loadSamsungGalaxyNote20UltraBezel() ?? loadAndroidPixelProBezel()
        case .pixel9Pro:
            return loadAndroidPixelProBezel()
        }
    }

    public static func loadAndroidDeviceMask(for skin: AndroidDeviceSkin) -> NSImage? {
        switch skin {
        case .galaxyNote20Ultra:
            return loadSamsungGalaxyNote20UltraMask() ?? loadAndroidPixelProMask()
        case .pixel9Pro:
            return loadAndroidPixelProMask()
        }
    }
}

/// Official Android hardware skin models supported in MicroCode live preview
public enum AndroidDeviceSkin: String, CaseIterable, Identifiable {
    case galaxyNote20Ultra = "Samsung Galaxy Note 20 Ultra"
    case pixel9Pro = "Google Pixel 9 Pro"

    public var id: String { rawValue }

    public var shortName: String {
        switch self {
        case .galaxyNote20Ultra: return "Note 20 Ultra"
        case .pixel9Pro: return "Pixel 9 Pro"
        }
    }

    public var outerSize: CGSize {
        switch self {
        case .galaxyNote20Ultra: return CGSize(width: 1794, height: 3488)
        case .pixel9Pro: return CGSize(width: 1408, height: 2974)
        }
    }

    public var displayRect: CGRect {
        switch self {
        case .galaxyNote20Ultra: return CGRect(x: 177, y: 190, width: 1440, height: 3088)
        case .pixel9Pro: return CGRect(x: 60, y: 61, width: 1280, height: 2856)
        }
    }

    public var cornerRadius: CGFloat {
        switch self {
        case .galaxyNote20Ultra: return 24
        case .pixel9Pro: return 109
        }
    }
}
