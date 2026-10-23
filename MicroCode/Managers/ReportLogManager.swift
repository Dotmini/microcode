//
//  ReportLogManager.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2026 Dotmini Company Limited. All rights reserved.
//

import Foundation
import AppKit

public enum LogType: String {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case debug = "DEBUG"
}

public class ReportLogManager {
    public static let shared = ReportLogManager()
    
    private let fileManager = FileManager.default
    private let logQueue = DispatchQueue(label: "com.microcode.reportlog", qos: .utility)
    
    private var logsDirectory: URL?
    
    private init() {
        setupLogsDirectory()
    }
    
    /// Auto-locate and create the Logs folder in Documents
    private func setupLogsDirectory() {
        // Try to locate ~/Documents/MicroCode/Logs
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let appFolder = documentsURL.appendingPathComponent("MicroCode")
            let logsFolder = appFolder.appendingPathComponent("Logs")
            
            self.logsDirectory = logsFolder
            
            // Create directory if it doesn't exist
            if !fileManager.fileExists(atPath: logsFolder.path) {
                do {
                    try fileManager.createDirectory(at: logsFolder, withIntermediateDirectories: true, attributes: nil)
                    print("[ReportLog] Created logs directory at: \(logsFolder.path)")
                } catch {
                    print("[ReportLog] Failed to create logs directory: \(error)")
                }
            } else {
                 print("[ReportLog] Logs directory found at: \(logsFolder.path)")
            }
        }
    }
    
    /// Log a message to the daily log file
    public func log(_ message: String, type: LogType = .info, file: String = #file, function: String = #function, line: Int = #line) {
        logQueue.async { [weak self] in
            guard let self = self, let logsDir = self.logsDirectory else { return }
            
            let timestamp = Date()
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            let timeString = dateFormatter.string(from: timestamp)
            
            let fileName = (file as NSString).lastPathComponent
            let logMessage = "[\(timeString)] [\(type.rawValue)] [\(fileName):\(line)] \(function) - \(message)\n"
            
            // Console output for debug
            #if DEBUG
            print(logMessage, terminator: "")
            #endif
            
            // Get today's file path
            let fileDateFormatter = DateFormatter()
            fileDateFormatter.locale = Locale(identifier: "en_US_POSIX")
            fileDateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = fileDateFormatter.string(from: timestamp)
            let logFileURL = logsDir.appendingPathComponent("Log_\(dateString).txt")
            
            self.appendToFile(url: logFileURL, content: logMessage)
        }
    }
    
    private func appendToFile(url: URL, content: String) {
        if !fileManager.fileExists(atPath: url.path) {
            // Create new file
            try? content.write(to: url, atomically: true, encoding: .utf8)
        } else {
            // Append to existing using Swift's throwing FileHandle APIs so disk-full
            // (ENOSPC / errno 28) or I/O errors never raise an uncaught ObjC
            // NSFileHandleOperationException and crash the app.
            do {
                let fileHandle = try FileHandle(forWritingTo: url)
                defer { try? fileHandle.close() }
                let size = try fileHandle.seekToEnd()
                if size > 2_000_000 {
                    try? fileHandle.truncate(atOffset: 0)
                    _ = try? fileHandle.seekToEnd()
                }
                if let data = content.data(using: .utf8) {
                    try fileHandle.write(contentsOf: data)
                }
            } catch {
                // Silently ignore logging write failures (e.g., No space left on device)
            }
        }
    }
    
    /// Open the logs folder in Finder
    public func openLogsFolder() {
        guard let url = logsDirectory else { return }
        NSWorkspace.shared.open(url)
    }
}
