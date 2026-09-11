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

    private static func loadResourceImage(named name: String) -> NSImage? {
        // 1. Try App Bundle Resources
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        
        // 2. Try App Bundle resourceURL
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("\(name).png"),
           FileManager.default.fileExists(atPath: resourceURL.path),
           let img = NSImage(contentsOf: resourceURL) {
            return img
        }
        
        // 3. Try App Bundle Contents/Resources direct path
        let bundleResourcePath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name).png").path
        if FileManager.default.fileExists(atPath: bundleResourcePath),
           let img = NSImage(contentsOfFile: bundleResourcePath) {
            return img
        }

        // 4. Try executable bundle directory
        if let exeURL = Bundle.main.executableURL {
            let resPath = exeURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/\(name).png").path
            if FileManager.default.fileExists(atPath: resPath),
               let img = NSImage(contentsOfFile: resPath) {
                return img
            }
        }

        // 5. Try Project Resources Directory
        let projectPath = "/Users/dotmini/Documents/SX/codetunner-native/MicroCode/Resources/\(name).png"
        if FileManager.default.fileExists(atPath: projectPath),
           let img = NSImage(contentsOfFile: projectPath) {
            return img
        }

        // 6. Try current working directory
        let cwdPath = FileManager.default.currentDirectoryPath + "/MicroCode/Resources/\(name).png"
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
}
