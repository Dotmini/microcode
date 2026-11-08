//
//  DeviceFrameAssets.swift
//  MicroCode - Hardware Frame Assets for Live Preview
//

import AppKit
import ImageIO
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

    /// Releases cached Android bezel/mask bitmaps when the embedded Android dock is closed.
    public static func purgeCachedAndroidSkinImages() {
        cachedAndroidFrameImage = nil
        cachedAndroidMaskImage = nil
    }

    /// Loads and downsamples an image via ImageIO so large 1408x2965 SDK WebP skins consume ~3-4 MB instead of 16 MB each.
    public static func loadDownsampledImage(at url: URL, maxPixelSize: Int = 1080) -> NSImage? {
        let sourceOpts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOpts as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        return NSImage(contentsOf: url)
    }

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
    /// 514×706 pt outer, 466×678 pt screen @ (26, 14), asymmetric 8pt spine / 59pt right corners).
    public static func loadIPhoneDuoOuterBezel(isLandscape: Bool = false) -> NSImage {
        if !isLandscape, let cached = cachedIPhoneDuoOuterPortrait { return cached }
        if isLandscape, let cached = cachedIPhoneDuoOuterLandscape { return cached }

        let portraitSize = NSSize(width: 514, height: 706)
        let portrait = NSImage(size: portraitSize, flipped: false) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let chromeDir = "/Library/Developer/DeviceKit/Chrome/phone15.devicechrome/Contents/Resources"
            let chromeCompositePath = "\(chromeDir)/PhoneComposite.pdf"
            if let deviceKitComposite = NSImage(contentsOfFile: chromeCompositePath) {
                // Draw official Apple hardware buttons behind the chassis composite per phone15/chrome.json
                if let volBtn = NSImage(contentsOfFile: "\(chromeDir)/Vol BTN.pdf") {
                    volBtn.draw(in: CGRect(x: 236, y: bounds.maxY - 16, width: 66, height: 16))
                    volBtn.draw(in: CGRect(x: 316, y: bounds.maxY - 16, width: 66, height: 16))
                }
                if let pwrBtn = NSImage(contentsOfFile: "\(chromeDir)/X_Power BTN.pdf") {
                    pwrBtn.draw(in: CGRect(x: bounds.maxX - 15, y: bounds.maxY - 202 - 113, width: 16, height: 113))
                }
                deviceKitComposite.draw(in: bounds)
            } else {
                // Procedural fallback matching exact phone15 geometry (80pt right outer, 8pt left spine)
                let outerPath = unevenRoundedCGPath(
                    in: bounds.insetBy(dx: 1.5, dy: 1.5),
                    topLeft: 14,
                    topRight: 76,
                    bottomRight: 76,
                    bottomLeft: 14
                )
                ctx.saveGState()
                ctx.addPath(outerPath)
                ctx.setFillColor(NSColor(calibratedWhite: 0.11, alpha: 1.0).cgColor)
                ctx.fillPath()
                ctx.restoreGState()

                let spineRect = CGRect(x: 1.5, y: 8, width: 16, height: bounds.height - 16)
                let spinePath = CGPath(roundedRect: spineRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
                ctx.saveGState()
                ctx.addPath(spinePath)
                ctx.setFillColor(NSColor(calibratedWhite: 0.22, alpha: 0.95).cgColor)
                ctx.fillPath()
                ctx.restoreGState()

                ctx.saveGState()
                ctx.addPath(outerPath)
                ctx.setStrokeColor(NSColor(calibratedWhite: 0.42, alpha: 0.85).cgColor)
                ctx.setLineWidth(2.0)
                ctx.strokePath()
                ctx.restoreGState()
            }

            // Screen aperture cutout (x: 26, y: 14, width: 466, height: 678)
            // Uses official Apple framebufferMask PDF (1C896A2B-F0D7-405C-8D0F-66E4B80AD044.pdf: UL=8, LL=8, UR=59, LR=59)
            let screenRect = CGRect(x: 26, y: 14, width: 466, height: 678)
            let maskPaths = [
                "/Library/Developer/CoreSimulator/Profiles/DeviceTypes/iPhone Duo.simdevicetype/Contents/Resources/1C896A2B-F0D7-405C-8D0F-66E4B80AD044.pdf",
                "/Library/Developer/DeviceKit/FramebufferMasks/1C896A2B-F0D7-405C-8D0F-66E4B80AD044.pdf"
            ]
            var punchedWithOfficialMask = false
            for maskPath in maskPaths {
                if let maskImg = NSImage(contentsOfFile: maskPath) {
                    maskImg.draw(in: screenRect, from: .zero, operation: .destinationOut, fraction: 1.0)
                    punchedWithOfficialMask = true
                    break
                }
            }
            if !punchedWithOfficialMask {
                let screenPath = unevenRoundedCGPath(
                    in: screenRect,
                    topLeft: 8.0,
                    topRight: 59.0,
                    bottomRight: 59.0,
                    bottomLeft: 8.0
                )
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                ctx.addPath(screenPath)
                ctx.fillPath()
                ctx.restoreGState()
            }
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
    /// 985×703 pt unfolded book-open default [951×669 pt screen + 17pt symmetric bezel, 55pt corners],
    /// or 703×985 pt when rotated to tall portrait).
    public static func loadIPhoneDuoInnerBezel(isRotatedPortrait: Bool = false) -> NSImage {
        if !isRotatedPortrait, let cached = cachedIPhoneDuoInnerUnfolded { return cached }
        if isRotatedPortrait, let cached = cachedIPhoneDuoInnerPortrait { return cached }

        let portraitSize = NSSize(width: 703, height: 985)
        let bezelInset: CGFloat = 17
        let screenCornerRadius: CGFloat = 55.0
        let outerCornerRadius: CGFloat = 72.0

        let portrait = NSImage(size: portraitSize, flipped: false) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let chromeDir = "/Library/Developer/DeviceKit/Chrome/phone14.devicechrome/Contents/Resources"
            let chromeCompositePath = "\(chromeDir)/PhoneComposite.pdf"
            if let deviceKitComposite = NSImage(contentsOfFile: chromeCompositePath) {
                if let volBtn = NSImage(contentsOfFile: "\(chromeDir)/Vol BTN.pdf") {
                    volBtn.draw(in: CGRect(x: 0, y: bounds.maxY - 114 - 63, width: 16, height: 63))
                    volBtn.draw(in: CGRect(x: 0, y: bounds.maxY - 188 - 63, width: 16, height: 63))
                }
                if let pwrBtn = NSImage(contentsOfFile: "\(chromeDir)/X Power BTN.pdf") {
                    pwrBtn.draw(in: CGRect(x: bounds.maxX - 196 - 107, y: bounds.maxY - 16, width: 107, height: 16))
                }
                deviceKitComposite.draw(in: bounds)
            } else {
                let outerRect = bounds.insetBy(dx: 1.5, dy: 1.5)
                let outerPath = CGPath(roundedRect: outerRect, cornerWidth: outerCornerRadius, cornerHeight: outerCornerRadius, transform: nil)
                ctx.saveGState()
                ctx.addPath(outerPath)
                ctx.setFillColor(NSColor(calibratedWhite: 0.09, alpha: 1.0).cgColor)
                ctx.fillPath()
                ctx.setStrokeColor(NSColor(calibratedWhite: 0.38, alpha: 0.85).cgColor)
                ctx.setLineWidth(2.0)
                ctx.addPath(outerPath)
                ctx.strokePath()
                ctx.restoreGState()
            }

            // Screen aperture cutout (x: 17, y: 17, width: 669, height: 951)
            // Uses official Apple framebufferMask PDF (BF0DC480-5EE2-4EC1-B02B-C75E94759832.pdf: 55pt symmetric corners)
            let screenRect = bounds.insetBy(dx: bezelInset, dy: bezelInset)
            let maskPath = "/Library/Developer/CoreSimulator/Profiles/DeviceTypes/iPhone Duo.simdevicetype/Contents/Resources/BF0DC480-5EE2-4EC1-B02B-C75E94759832.pdf"
            if let maskImg = NSImage(contentsOfFile: maskPath) {
                maskImg.draw(in: screenRect, from: .zero, operation: .destinationOut, fraction: 1.0)
            } else {
                let screenPath = CGPath(roundedRect: screenRect, cornerWidth: screenCornerRadius, cornerHeight: screenCornerRadius, transform: nil)
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                ctx.addPath(screenPath)
                ctx.fillPath()
                ctx.restoreGState()
            }
            return true
        }

        cachedIPhoneDuoInnerPortrait = portrait
        if isRotatedPortrait { return portrait }

        // Default unfolded posture is 985×703 (rotated -90° from 703×985 portrait)
        let unfoldedSize = NSSize(width: 985, height: 703)
        let unfolded = NSImage(size: unfoldedSize, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.translateBy(x: 0, y: unfoldedSize.height)
            ctx.rotate(by: -.pi / 2)
            portrait.draw(in: CGRect(origin: .zero, size: portraitSize))
            ctx.restoreGState()
            return true
        }
        cachedIPhoneDuoInnerUnfolded = unfolded
        return unfolded
    }

    /// Loads the authentic Google Pixel hardware chassis frame.
    /// Always guaranteed to return a real device frame, never leaving the emulator naked.
    public static func loadAndroidPixelProBezel() -> NSImage? {
        if let cached = cachedAndroidFrameImage { return cached }
        // Prioritize user's installed Android SDK Pixel 10 Pro / Pixel Pro skins
        let sdkSkins = [
            NSHomeDirectory() + "/Library/Android/sdk/skins/pixel_10_pro/back.webp",
            NSHomeDirectory() + "/Library/Android/sdk/skins/pixel_9_pro/back.webp",
            NSHomeDirectory() + "/Library/Android/sdk/skins/pixel_8_pro/back.webp",
            NSHomeDirectory() + "/Library/Android/sdk/skins/pixel_7_pro/back.webp"
        ]
        for path in sdkSkins {
            if FileManager.default.fileExists(atPath: path),
               let img = loadDownsampledImage(at: URL(fileURLWithPath: path)) {
                cachedAndroidFrameImage = img
                return img
            }
        }
        if let img = loadResourceImage(named: "android_pixel_frame", fileExtension: "png") {
            cachedAndroidFrameImage = img
            return img
        }
        if let img = loadResourceImage(named: "android_pixel_frame", fileExtension: "webp") {
            cachedAndroidFrameImage = img
            return img
        }
        return nil
    }

    /// Loads the authentic Google Pixel front camera punch-hole cutout mask.
    public static func loadAndroidPixelProMask() -> NSImage? {
        if let cached = cachedAndroidMaskImage { return cached }
        let sdkMasks = [
            NSHomeDirectory() + "/Library/Android/sdk/skins/pixel_10_pro/mask.webp",
            NSHomeDirectory() + "/Library/Android/sdk/skins/pixel_9_pro/mask.webp",
            NSHomeDirectory() + "/Library/Android/sdk/skins/pixel_8_pro/mask.webp",
            NSHomeDirectory() + "/Library/Android/sdk/skins/pixel_7_pro/mask.webp"
        ]
        for path in sdkMasks {
            if FileManager.default.fileExists(atPath: path),
               let img = loadDownsampledImage(at: URL(fileURLWithPath: path)) {
                cachedAndroidMaskImage = img
                return img
            }
        }
        if let img = loadResourceImage(named: "android_pixel_mask", fileExtension: "png") {
            cachedAndroidMaskImage = img
            return img
        }
        if let img = loadResourceImage(named: "android_pixel_mask", fileExtension: "webp") {
            cachedAndroidMaskImage = img
            return img
        }
        return nil
    }

    /// Parses an Android SDK skin `layout` file (`parts.device.display` + `layouts.portrait`) into exact geometry.
    public static func parseAndroidSkinLayout(at layoutURL: URL) -> AndroidSkinGeometry? {
        guard let text = try? String(contentsOf: layoutURL, encoding: .utf8) else { return nil }

        var dispWidth: CGFloat?
        var dispHeight: CGFloat?
        var cornerRadius: CGFloat?
        var outerWidth: CGFloat?
        var outerHeight: CGFloat?
        var dispX: CGFloat?
        var dispY: CGFloat?

        if let dispRange = text.range(of: "display\\s*\\{[^\\}]*\\}", options: .regularExpression) {
            let block = String(text[dispRange])
            dispWidth = Self.firstCGFloat(matching: "\\bwidth\\s+([0-9]+)", in: block)
            dispHeight = Self.firstCGFloat(matching: "\\bheight\\s+([0-9]+)", in: block)
            cornerRadius = Self.firstCGFloat(matching: "\\bcorner_radius\\s+([0-9]+)", in: block)
        }

        if let layoutsIdx = text.range(of: "layouts\\s*\\{", options: .regularExpression)?.lowerBound {
            let tail = String(text[layoutsIdx...])
            if let portIdx = tail.range(of: "portrait\\s*\\{", options: .regularExpression)?.upperBound {
                let portBody = String(tail[portIdx...])
                outerWidth = Self.firstCGFloat(matching: "\\bwidth\\s+([0-9]+)", in: portBody)
                outerHeight = Self.firstCGFloat(matching: "\\bheight\\s+([0-9]+)", in: portBody)

                let partPattern = "part[0-9]+\\s*\\{[^\\}]*name\\s+device[^\\}]*\\}"
                if let devPartRange = portBody.range(of: partPattern, options: .regularExpression) {
                    let devBlock = String(portBody[devPartRange])
                    dispX = Self.firstCGFloat(matching: "\\bx\\s+([0-9]+)", in: devBlock)
                    dispY = Self.firstCGFloat(matching: "\\by\\s+([0-9]+)", in: devBlock)
                }
            }
        }

        guard let w = dispWidth, let h = dispHeight, w > 0, h > 0 else { return nil }
        let ow = outerWidth ?? (w + 128)
        let oh = outerHeight ?? (h + 109)
        let dx = dispX ?? ((ow - w) / 2.0)
        let dy = dispY ?? ((oh - h) / 2.0)
        let cr = cornerRadius ?? round(w * 0.077)
        return AndroidSkinGeometry(
            outerSize: CGSize(width: ow, height: oh),
            displayRect: CGRect(x: dx, y: dy, width: w, height: h),
            cornerRadius: cr
        )
    }

    private static func firstCGFloat(matching pattern: String, in text: String) -> CGFloat? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let val = Double(text[range]) else { return nil }
        return CGFloat(val)
    }

    public static func loadAndroidDeviceBezel(for skin: AndroidDeviceSkin = .pixelPro) -> NSImage? {
        loadAndroidPixelProBezel()
    }

    public static func loadAndroidDeviceMask(for skin: AndroidDeviceSkin = .pixelPro) -> NSImage? {
        loadAndroidPixelProMask()
    }
}

/// Exact hardware chassis & viewport geometry resolved from the user's Android AVD / SDK skin
public struct AndroidSkinGeometry: Equatable {
    public var outerSize: CGSize
    public var displayRect: CGRect
    public var cornerRadius: CGFloat

    public init(outerSize: CGSize, displayRect: CGRect, cornerRadius: CGFloat) {
        self.outerSize = outerSize
        self.displayRect = displayRect
        self.cornerRadius = cornerRadius
    }

    public static let pixelProDefault = AndroidSkinGeometry(
        outerSize: CGSize(width: 1408, height: 2965),
        displayRect: CGRect(x: 59, y: 60, width: 1280, height: 2856),
        cornerRadius: 99
    )
}

/// Default Android hardware skin fallback when no custom AVD skin layout is specified
public enum AndroidDeviceSkin: String, CaseIterable, Identifiable {
    case pixelPro = "Google Pixel Pro"

    public var id: String { rawValue }

    public var shortName: String { "Pixel Pro" }

    public var outerSize: CGSize { AndroidSkinGeometry.pixelProDefault.outerSize }

    public var displayRect: CGRect { AndroidSkinGeometry.pixelProDefault.displayRect }

    public var cornerRadius: CGFloat { AndroidSkinGeometry.pixelProDefault.cornerRadius }
}
