//
//  SSHConfigParser.swift
//  MicroCode
//
//  Created by Tirawat Nantamas.
//  Copyright © 2025 Dotmini Company Limited. All rights reserved.
//

import Foundation

struct SSHConfigEntry {
    var host: String
    var hostName: String
    var user: String?
    var identityFile: String?
    var port: UInt16?
    var proxyJump: String?
    var forwardAgent: Bool = false
}

class SSHConfigParser {
    static let shared = SSHConfigParser()
    
    private let cacheLock = NSLock()
    private var cachedEntries: [SSHConfigEntry]?
    private var cachedModificationDate: Date?
    
    func parseDefaultConfig(forceRefresh: Bool = false) -> [SSHConfigEntry] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configPath = home.appendingPathComponent(".ssh/config")
        let mtime = (try? FileManager.default.attributesOfItem(atPath: configPath.path)[.modificationDate]) as? Date
        
        cacheLock.lock()
        if !forceRefresh, let cached = cachedEntries, cachedModificationDate == mtime {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        
        let parsed = parse(fileURL: configPath)
        cacheLock.lock()
        cachedEntries = parsed
        cachedModificationDate = mtime
        cacheLock.unlock()
        return parsed
    }
    
    func parse(fileURL: URL, visited: Set<URL> = []) -> [SSHConfigEntry] {
        let resolvedURL = fileURL.standardizedFileURL
        guard !visited.contains(resolvedURL),
              let content = try? String(contentsOf: resolvedURL, encoding: .utf8) else {
            return []
        }
        var nextVisited = visited
        nextVisited.insert(resolvedURL)
        
        var entries: [SSHConfigEntry] = []
        var activeAliases: [String] = []
        var currentBlock: (
            hostName: String?,
            user: String?,
            identityFile: String?,
            port: UInt16?,
            proxyJump: String?,
            forwardAgent: Bool?
        ) = (nil, nil, nil, nil, nil, nil)
        
        var globalDefaults: (
            user: String?,
            identityFile: String?,
            port: UInt16?,
            proxyJump: String?,
            forwardAgent: Bool?
        ) = (nil, nil, nil, nil, nil)
        
        func flushCurrentBlock() {
            guard !activeAliases.isEmpty else { return }
            if activeAliases == ["*"] {
                if let u = currentBlock.user { globalDefaults.user = u }
                if let id = currentBlock.identityFile { globalDefaults.identityFile = id }
                if let p = currentBlock.port { globalDefaults.port = p }
                if let pj = currentBlock.proxyJump { globalDefaults.proxyJump = pj }
                if let fa = currentBlock.forwardAgent { globalDefaults.forwardAgent = fa }
            } else {
                for alias in activeAliases where !alias.contains("*") && !alias.contains("?") {
                    let resolvedHostName = (currentBlock.hostName?.isEmpty == false) ? currentBlock.hostName! : alias
                    let entry = SSHConfigEntry(
                        host: alias,
                        hostName: resolvedHostName,
                        user: currentBlock.user ?? globalDefaults.user,
                        identityFile: currentBlock.identityFile ?? globalDefaults.identityFile,
                        port: currentBlock.port ?? globalDefaults.port ?? 22,
                        proxyJump: currentBlock.proxyJump ?? globalDefaults.proxyJump,
                        forwardAgent: currentBlock.forwardAgent ?? globalDefaults.forwardAgent ?? false
                    )
                    entries.append(entry)
                }
            }
            activeAliases = []
            currentBlock = (nil, nil, nil, nil, nil, nil)
        }
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            // Support both "Key Value" and "Key=Value" syntax
            let normalized = trimmed.replacingOccurrences(
                of: "^([A-Za-z0-9]+)\\s*=\\s*",
                with: "$1 ",
                options: .regularExpression
            )
            let components = normalized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard components.count >= 2 else { continue }
            
            let keyword = components[0].lowercased()
            let value = components[1...].joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            
            if keyword == "include" {
                let sshDir = resolvedURL.deletingLastPathComponent()
                let rawPattern = (value as NSString).expandingTildeInPath
                let fullPattern = rawPattern.hasPrefix("/") ? rawPattern : sshDir.appendingPathComponent(rawPattern).path
                for matchedURL in Self.expandGlob(pattern: fullPattern) {
                    entries.append(contentsOf: parse(fileURL: matchedURL, visited: nextVisited))
                }
            } else if keyword == "host" {
                flushCurrentBlock()
                activeAliases = Array(components[1...])
            } else if !activeAliases.isEmpty {
                switch keyword {
                case "hostname":
                    currentBlock.hostName = value
                case "user":
                    currentBlock.user = value
                case "identityfile":
                    currentBlock.identityFile = (value as NSString).expandingTildeInPath
                case "port":
                    if let p = UInt16(value) {
                        currentBlock.port = p
                    }
                case "proxyjump":
                    currentBlock.proxyJump = value
                case "forwardagent":
                    currentBlock.forwardAgent = (value.lowercased() == "yes" || value.lowercased() == "true")
                default:
                    break
                }
            }
        }
        
        flushCurrentBlock()
        return entries
    }
    
    private static func expandGlob(pattern: String) -> [URL] {
        var gt = glob_t()
        defer { globfree(&gt) }
        guard glob(pattern, GLOB_TILDE | GLOB_BRACE, nil, &gt) == 0 else { return [] }
        var urls: [URL] = []
        for i in 0..<Int(gt.gl_matchc) {
            if let cStr = gt.gl_pathv[i] {
                let path = String(cString: cStr)
                urls.append(URL(fileURLWithPath: path))
            }
        }
        return urls
    }
}
