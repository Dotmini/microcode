//
//  SSHConfigParser.swift
//  MicroCode
//
//  Created by SPU AI CLUB.
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import Foundation

struct SSHConfigEntry {
    var host: String
    var hostName: String
    var user: String?
    var identityFile: String?
    var port: UInt16?
}

class SSHConfigParser {
    static let shared = SSHConfigParser()
    
    func parseDefaultConfig() -> [SSHConfigEntry] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configPath = home.appendingPathComponent(".ssh/config")
        return parse(fileURL: configPath)
    }
    
    func parse(fileURL: URL) -> [SSHConfigEntry] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }
        
        var entries: [SSHConfigEntry] = []
        var currentEntry: SSHConfigEntry?
        
        // Simple line-by-line parser
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard components.count >= 2 else { continue }
            
            let keyword = components[0].lowercased()
            let value = components[1...].joined(separator: " ")
            
            if keyword == "host" {
                // Save previous entry
                if let entry = currentEntry {
                    // Only add if it has a HostName (real connection)
                    if !entry.hostName.isEmpty {
                        entries.append(entry)
                    }
                }
                
                // Start new entry
                // Handle multiple aliases "Host foo bar" -> just take first for now or simplify
                let hostAlias = components[1] 
                currentEntry = SSHConfigEntry(host: hostAlias, hostName: "", user: nil, identityFile: nil, port: 22)
            } else if let _ = currentEntry {
                switch keyword {
                case "hostname":
                    currentEntry?.hostName = value
                case "user":
                    currentEntry?.user = value
                case "identityfile":
                    // Handle ~ expansion
                    let expanded = (value as NSString).expandingTildeInPath
                    currentEntry?.identityFile = expanded
                case "port":
                    if let p = UInt16(value) {
                        currentEntry?.port = p
                    }
                default:
                    break
                }
            }
        }
        
        // Add last entry
        if let entry = currentEntry, !entry.hostName.isEmpty {
            entries.append(entry)
        }
        
        return entries
    }
}
