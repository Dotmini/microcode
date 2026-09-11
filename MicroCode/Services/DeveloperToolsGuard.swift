//
//  DeveloperToolsGuard.swift
//  MicroCode
//
//  Created to prevent intrusive macOS "The python3 command requires the command line developer tools" dialogs.
//

import Foundation

enum DeveloperToolsGuard {
    /// Cached check of whether Apple's Command Line Tools (or Xcode) are actually installed.
    /// If false, calling `/usr/bin/python3`, `/usr/bin/git`, `/usr/bin/clang`, etc.
    /// will trigger an intrusive system prompt dialog on macOS.
    static let hasCommandLineTools: Bool = {
        let fm = FileManager.default
        // 1. Direct receipt or standard CLT tool binary check
        if fm.fileExists(atPath: "/Library/Developer/CommandLineTools/usr/bin/git") ||
           fm.fileExists(atPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/git") {
            return true
        }
        
        // 2. Query xcode-select -p quietly
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        proc.arguments = ["-p"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }()
    
    /// Verify if an executable path can be run without triggering Apple's xcode-select prompt.
    static func isSafeToExecute(_ path: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        
        // Check for Apple developer stub tools in /usr/bin
        if path.hasPrefix("/usr/bin/") {
            let toolName = (path as NSString).lastPathComponent
            let appleDevShims: Set<String> = [
                "python3", "python", "clang", "clang++", "gcc", "g++",
                "swift", "swiftc", "git", "make", "ld", "svn", "lldb"
            ]
            if appleDevShims.contains(toolName) && !hasCommandLineTools {
                return false
            }
        }
        return true
    }
}
