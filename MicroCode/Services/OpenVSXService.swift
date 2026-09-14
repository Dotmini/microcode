//
//  OpenVSXService.swift
//  MicroCode
//
//  Official Open VSX Registry Client & Package Downloader
//  https://open-vsx.org/api/
//
//  Tirawat Nantamas | Dotmini Company Limited
//

import SwiftUI
import Foundation
import Combine

// MARK: - Open VSX Data Models

public struct OpenVSXExtensionFiles: Codable, Equatable, Sendable {
    public let download: String?
    public let icon: String?
    public let readme: String?
    public let changelog: String?
    public let manifest: String?
    public let sha256: String?
}

public struct OpenVSXExtension: Identifiable, Codable, Equatable, Sendable {
    public let namespace: String
    public let name: String
    public let version: String
    public let displayName: String?
    public let description: String?
    public let downloadCount: Int?
    public let averageRating: Double?
    public let reviewCount: Int?
    public let timestamp: String?
    public let verified: Bool?
    public let files: OpenVSXExtensionFiles?
    public let categories: [String]?
    public let tags: [String]?
    
    public var id: String {
        "\(namespace).\(name)"
    }
    
    public var title: String {
        if let display = displayName, !display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return display
        }
        return name
    }
    
    public var author: String {
        namespace
    }
    
    public var iconURL: URL? {
        guard let iconStr = files?.icon, !iconStr.isEmpty else { return nil }
        return URL(string: iconStr)
    }
    
    public var downloadURL: URL? {
        guard let dlStr = files?.download, !dlStr.isEmpty else { return nil }
        return URL(string: dlStr)
    }
    
    public var readmeURL: URL? {
        guard let rmStr = files?.readme, !rmStr.isEmpty else { return nil }
        return URL(string: rmStr)
    }
    
    public var formattedDownloads: String {
        let count = downloadCount ?? 0
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }
    
    public var formattedRating: String {
        guard let rating = averageRating, rating > 0 else { return "" }
        if let reviews = reviewCount, reviews > 0 {
            return String(format: "★ %.1f (%d)", rating, reviews)
        }
        return String(format: "★ %.1f", rating)
    }
}

public struct OpenVSXSearchResult: Codable, Sendable {
    public let totalSize: Int?
    public let offset: Int?
    public let extensions: [OpenVSXExtension]
}

// MARK: - Open VSX Service

@MainActor
public final class OpenVSXService: ObservableObject {
    public static let shared = OpenVSXService()
    
    private let baseURL = "https://open-vsx.org/api"
    private let session: URLSession
    
    @Published public var searchResults: [OpenVSXExtension] = []
    @Published public var popularExtensions: [OpenVSXExtension] = []
    @Published public var isSearching: Bool = false
    @Published public var isLoadingPopular: Bool = false
    @Published public var errorMessage: String? = nil
    
    @Published public var downloadingIds: Set<String> = []
    @Published public var downloadProgress: [String: Double] = [:]
    
    private var readmeCache: [String: String] = [:]
    private var imageCache = NSCache<NSString, NSImage>()
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20.0
        config.timeoutIntervalForResource = 300.0
        config.httpAdditionalHeaders = [
            "User-Agent": "MicroCode-Editor/2.3.0 (Macintosh; Apple Silicon)"
        ]
        self.session = URLSession(configuration: config)
        
        // Load initial popular extensions in background
        Task {
            await loadInitialPopular()
        }
    }
    
    // MARK: - Initial Popular Loader
    private func loadInitialPopular() async {
        isLoadingPopular = true
        defer { isLoadingPopular = false }
        
        let popular = await fetchPopular(size: 30)
        self.popularExtensions = popular
    }
    
    // MARK: - Search Extensions
    public func search(
        query: String,
        category: String? = nil,
        sortBy: String = "downloadCount",
        sortOrder: String = "desc",
        size: Int = 30,
        offset: Int = 0
    ) async -> [OpenVSXExtension] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "size", value: "\(size)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "sortBy", value: sortBy),
            URLQueryItem(name: "sortOrder", value: sortOrder)
        ]
        
        if !trimmed.isEmpty {
            queryItems.append(URLQueryItem(name: "query", value: trimmed))
        }
        
        if let cat = category, !cat.isEmpty, cat != "All" {
            queryItems.append(URLQueryItem(name: "category", value: cat))
        }
        
        var components = URLComponents(string: "\(baseURL)/-/search")
        components?.queryItems = queryItems
        
        guard let url = components?.url else { return [] }
        
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
                errorMessage = "Open VSX server returned unexpected response"
                return []
            }
            
            let result = try JSONDecoder().decode(OpenVSXSearchResult.self, from: data)
            self.searchResults = result.extensions
            return result.extensions
        } catch {
            if !Task.isCancelled {
                errorMessage = "Search failed: \(error.localizedDescription)"
            }
            return []
        }
    }
    
    // MARK: - Fetch Popular
    public func fetchPopular(category: String? = nil, size: Int = 30) async -> [OpenVSXExtension] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "size", value: "\(size)"),
            URLQueryItem(name: "sortBy", value: "downloadCount"),
            URLQueryItem(name: "sortOrder", value: "desc")
        ]
        
        if let cat = category, !cat.isEmpty, cat != "All" {
            queryItems.append(URLQueryItem(name: "category", value: cat))
        }
        
        var components = URLComponents(string: "\(baseURL)/-/search")
        components?.queryItems = queryItems
        
        guard let url = components?.url else { return [] }
        
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
                return []
            }
            let result = try JSONDecoder().decode(OpenVSXSearchResult.self, from: data)
            return result.extensions
        } catch {
            return []
        }
    }
    
    // MARK: - Fetch Extension README
    public func fetchReadme(for ext: OpenVSXExtension) async -> String? {
        if let cached = readmeCache[ext.id] {
            return cached
        }
        
        guard let readmeUrl = ext.readmeURL else { return nil }
        
        do {
            let (data, response) = try await session.data(from: readmeUrl)
            guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode),
                  let markdown = String(data: data, encoding: .utf8) else {
                return nil
            }
            readmeCache[ext.id] = markdown
            return markdown
        } catch {
            return nil
        }
    }
    
    // MARK: - Download Remote Icon
    public func loadIcon(for ext: OpenVSXExtension) async -> NSImage? {
        let key = ext.id as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        
        guard let iconURL = ext.iconURL else { return nil }
        
        do {
            let (data, response) = try await session.data(from: iconURL)
            guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode),
                  let img = NSImage(data: data) else {
                return nil
            }
            imageCache.setObject(img, forKey: key)
            return img
        } catch {
            return nil
        }
    }
    
    // MARK: - Download & Install VSIX Package
    @discardableResult
    public func downloadAndInstall(extension ext: OpenVSXExtension) async throws -> String {
        guard let downloadURL = ext.downloadURL else {
            throw NSError(
                domain: "OpenVSXService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No download URL provided by Open VSX for \(ext.id)"]
            )
        }
        
        downloadingIds.insert(ext.id)
        downloadProgress[ext.id] = 0.05
        
        defer {
            downloadingIds.remove(ext.id)
            downloadProgress.removeValue(forKey: ext.id)
        }
        
        // 1. Download file to temporary location
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let destinationVSIX = tempDir.appendingPathComponent("\(ext.id)-\(ext.version).vsix")
        
        downloadProgress[ext.id] = 0.20
        
        let (localTempURL, response) = try await session.download(from: downloadURL)
        guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
            throw NSError(
                domain: "OpenVSXService",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to download VSIX from Open VSX (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))"]
            )
        }
        
        downloadProgress[ext.id] = 0.65
        
        // Move downloaded file to designated vsix location
        if FileManager.default.fileExists(atPath: destinationVSIX.path) {
            try? FileManager.default.removeItem(at: destinationVSIX)
        }
        try FileManager.default.moveItem(at: localTempURL, to: destinationVSIX)
        
        downloadProgress[ext.id] = 0.85
        
        // 2. Install through ExtensionManager
        let installedId = try await ExtensionManager.shared.installExtension(from: destinationVSIX)
        
        downloadProgress[ext.id] = 1.0
        
        // 3. Post System Notifications
        NotificationCenter.default.post(name: NSNotification.Name("MicroCodeExtensionInstalled"), object: installedId)
        NotificationCenter.default.post(name: NSNotification.Name("MicroCodeThemeChanged"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("MicroCodeIconThemeChanged"), object: nil)
        
        return installedId
    }
}
