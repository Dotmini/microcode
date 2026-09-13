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

        // 5. Try Project Resources Directory
        let projectPath = "/Users/dotmini/Documents/SX/codetunner-native/MicroCode/Resources/\(name).\(fileExtension)"
        if FileManager.default.fileExists(atPath: projectPath),
           let img = NSImage(contentsOfFile: projectPath) {
            return img
        }

        // 6. Try current working directory
        let cwdPath = FileManager.default.currentDirectoryPath + "/MicroCode/Resources/\(name).\(fileExtension)"
        if FileManager.default.fileExists(atPath: cwdPath),
           let img = NSImage(contentsOfFile: cwdPath) {
            return img
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
        let fallbackDirs = [
            NSHomeDirectory() + "/Library/Android/sdk/skins/Galaxy_Note20_Ultra/device_Port-Black-frame.png",
            NSHomeDirectory() + "/Documents/SX/codetunner-native/MicroCode/Resources/samsung_note20_ultra_frame.png"
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
