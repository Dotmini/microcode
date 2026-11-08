//
//  UniversalAttachmentEngine.swift
//  MicroCode
//
//  Universal Multi-Format Attachment & Grounded Perception Engine.
//  Stages attached files into ~/.microcode/attachments/<sessionBucket>/,
//  extracts 100% native macOS grounded text/OCR across PDF, OOXML (DOCX/XLSX/PPTX),
//  Rich Docs (RTF/DOC/ODT/HTML/EPUB), Multi-Encoding CSV/TSV (incl. Thai Windows-874/TIS-620),
//  JSON/YAML/XML/SQL, Jupyter (.ipynb), SQLite (.sqlite/.db), Parquet, Images (HEIC/TIFF/BMP/SVG),
//  Audio/Video (AVFoundation + keyframe ANE OCR), Archives (.zip/.tar/.gz), Folders, and Binaries,
//  and serves paged O(1) slices via `attachment_read`.
//  Tirawat Nantamas Founder and CEO of Dotmini Software.
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation
import AppKit
import PDFKit
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SQLite3

// MARK: - Vault Sidecar Metadata

struct VaultAttachmentSidecar: Codable, Sendable {
    let attachmentId: String
    let originalName: String
    let authorizedSourcePath: String?
    let stagedPath: String
    let extractedTextCachePath: String?
    let fileSizeBytes: Int64
    let semanticCategory: String
    let subtitleBadge: String
    let metricsSummary: String
    let extractionStatus: String
    let extractionWarning: String?
    let isPasswordProtected: Bool
    let createdAt: Date
}

// MARK: - Internal Extraction Result

struct AttachmentExtractionPayload: Sendable {
    var attachmentType: AIAttachment.AttachmentType
    var semanticCategory: AIAttachment.SemanticCategory
    var extractedText: String
    var subtitleBadge: String
    var metricsSummary: String
    var extractionStatus: String
    var extractionWarning: String?
    var normalizedVisionData: Data?
    var normalizedVisionMimeType: String?
    var nativeMediaMimeType: String?
    var isPasswordProtected: Bool = false
}

// MARK: - Universal Attachment Engine

final class UniversalAttachmentEngine: @unchecked Sendable {
    static let shared = UniversalAttachmentEngine()

    /// Root attachment vault directory (`~/.microcode/attachments/`)
    static var vaultRootDirectory: URL {
        let dir = WorkspaceStoragePaths.microcodeHomeDirectory.appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let maxDirectCopyBytes: Int64 = 128 * 1024 * 1024 // 128 MB
    private static let maxInMemoryAttachmentDataBytes: Int64 = 15 * 1024 * 1024 // 15 MB for inline PDF/media providers
    private static let maxUnpackedArchiveBytes: Int = 40 * 1024 * 1024 // 40 MB zip-bomb cap
    private static let maxSingleZipEntryBytes: Int = 14 * 1024 * 1024 // 14 MB XML entry cap
    private static let staleBucketMaxAgeSeconds: TimeInterval = 7 * 24 * 3600 // 7 days

    private let stateLock = NSLock()
    private var didScheduleStartupPrune = false
    private var inFlightTasks: [UUID: Task<AIAttachment, Never>] = [:]

    private init() {
        scheduleStaleVaultPruningOnce()
    }

    // MARK: - Instant Stage-1 Optimistic Preview (< 2 ms, Zero Blocking)

    private static func classifyExtension(_ name: String, isDirectory: Bool) -> (AIAttachment.AttachmentType, AIAttachment.SemanticCategory, String) {
        if isDirectory {
            return (.text, .folder, "Folder")
        }
        let lower = name.lowercased()
        let ext = (name as NSString).pathExtension.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") || lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tar.xz") || ext == "tar" || ext == "zip" || ext == "gz" || ext == "bz2" || ext == "xz" {
            return (.text, .archive, ext.isEmpty ? "Archive" : ext.uppercased())
        }
        switch ext {
        case "png", "jpg", "jpeg", "webp", "heic", "heif", "gif", "bmp", "tiff", "tif", "svg", "icns":
            let fmt = (ext == "jpg" || ext == "jpeg") ? "jpeg" : ((ext == "webp" || ext == "gif") ? ext : "png")
            return (.image(format: fmt), .image, ext.uppercased())
        case "pdf":
            return (.pdf, .pdf, "PDF")
        case "docx", "doc":
            return (.text, .wordDoc, ext.uppercased())
        case "xlsx", "xls":
            return (.text, .spreadsheet, ext.uppercased())
        case "pptx", "ppt":
            return (.text, .presentation, ext.uppercased())
        case "rtf", "rtfd", "odt", "epub":
            return (.text, .richDocument, ext.uppercased())
        case "ipynb":
            return (.text, .notebook, "Notebook")
        case "sqlite", "sqlite3", "db":
            return (.text, .database, "SQLite")
        case "csv", "tsv", "parquet":
            return (.text, .dataFile, ext.uppercased())
        case "mp3", "wav", "m4a", "aac", "flac", "ogg":
            return (.text, .audio, ext.uppercased())
        case "mp4", "mov", "m4v", "webm", "avi", "mkv":
            return (.text, .video, ext.uppercased())
        default:
            let label = ext.isEmpty ? "File" : ext.uppercased()
            return (.text, .codeOrText, label)
        }
    }

    static func readImageHeaderDimensions(from url: URL) -> (width: Int, height: Int)? {
        let opts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, opts as CFDictionary) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else {
            return nil
        }
        return (w, h)
    }

    static func readImageHeaderDimensions(from data: Data) -> (width: Int, height: Int)? {
        guard !data.isEmpty else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithData(data as CFData, opts as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, opts as CFDictionary) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else {
            return nil
        }
        return (w, h)
    }

    /// Creates instant (< 1 ms) preview `AIAttachment` chips from disk URLs without blocking `@MainActor`
    /// on file copies, subprocesses, PDF rasterization, or CoreML Vision passes.
    func makeInstantPreviewAttachments(urls: [URL]) -> [AIAttachment] {
        let fm = FileManager.default
        return urls.map { rawURL in
            let canonicalPath = WorkspacePathPolicy.canonicalPath(rawURL.path)
            let sourceURL = URL(fileURLWithPath: canonicalPath)
            let displayName = rawURL.lastPathComponent.isEmpty ? sourceURL.lastPathComponent : rawURL.lastPathComponent
            var isDirObj: ObjCBool = false
            let exists = fm.fileExists(atPath: sourceURL.path, isDirectory: &isDirObj)
            let isDirectory = exists && isDirObj.boolValue
            let fileSize: Int64 = (!exists || isDirectory)
                ? 0
                : (((try? fm.attributesOfItem(atPath: sourceURL.path)[.size]) as? NSNumber)?.int64Value ?? 0)
            let sizeStr = isDirectory ? "Folder" : ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            let (attType, category, label) = Self.classifyExtension(displayName, isDirectory: isDirectory)

            var thumb: NSImage? = nil
            var badge = isDirectory ? "Folder" : "\(label) • \(sizeStr)"
            if category == .image && exists {
                if let dims = Self.readImageHeaderDimensions(from: sourceURL) {
                    badge = "\(label) • \(dims.width)×\(dims.height) • \(sizeStr)"
                }
                if fileSize <= 32 * 1024 * 1024 {
                    thumb = AIAttachment.makeFastThumbnail(from: sourceURL)
                }
            }

            return AIAttachment(
                id: UUID(),
                name: displayName,
                data: Data(),
                type: attType,
                sourceURL: sourceURL,
                stagedPath: nil,
                subtitleBadge: badge,
                extractionStatus: "STAGING",
                fileSizeBytes: fileSize,
                semanticCategory: category,
                previewThumbnail: thumb
            )
        }
    }

    /// Creates an instant (< 0.5 ms) preview chip for raw dropped bytes.
    func makeInstantDataPreview(
        data: Data,
        fileName: String,
        explicitType: AIAttachment.AttachmentType? = nil
    ) -> AIAttachment {
        let (detectedType, detectedCat, label) = Self.classifyExtension(fileName, isDirectory: false)
        let resolvedType = explicitType ?? detectedType
        let resolvedCat: AIAttachment.SemanticCategory = {
            if case .image = resolvedType { return .image }
            if case .pdf = resolvedType { return .pdf }
            return detectedCat
        }()
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        var badge = "\(label) • \(sizeStr)"
        var thumb: NSImage? = nil
        if resolvedCat == .image {
            if let dims = Self.readImageHeaderDimensions(from: data) {
                badge = "\(label) • \(dims.width)×\(dims.height) • \(sizeStr)"
            }
            thumb = AIAttachment.makeFastThumbnail(from: data)
        }
        return AIAttachment(
            id: UUID(),
            name: fileName,
            data: Data(),
            type: resolvedType,
            subtitleBadge: badge,
            extractionStatus: "STAGING",
            fileSizeBytes: Int64(data.count),
            semanticCategory: resolvedCat,
            previewThumbnail: thumb
        )
    }

    /// Creates an instant (< 0.5 ms) preview chip for a pasted clipboard `NSImage` without running
    /// expensive `tiffRepresentation` or PNG compression on `@MainActor`.
    func makeInstantClipboardImagePreview(nsImage: NSImage, fileName: String) -> (preview: AIAttachment, cgImage: CGImage?) {
        let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let w = cg?.width ?? Int(nsImage.size.width)
        let h = cg?.height ?? Int(nsImage.size.height)
        let thumb: NSImage? = {
            guard let cg else { return nsImage }
            let maxEdge = max(cg.width, cg.height)
            guard maxEdge > 72 else {
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            let scale = 72.0 / Double(maxEdge)
            let tw = max(1, Int(Double(cg.width) * scale))
            let th = max(1, Int(Double(cg.height) * scale))
            if let ctx = CGContext(
                data: nil,
                width: tw,
                height: th,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                ctx.interpolationQuality = .medium
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
                if let smallCG = ctx.makeImage() {
                    return NSImage(cgImage: smallCG, size: NSSize(width: tw, height: th))
                }
            }
            return nsImage
        }()
        let dimStr = (w > 0 && h > 0) ? "\(w)×\(h)" : "Image"
        let preview = AIAttachment(
            id: UUID(),
            name: fileName,
            data: Data(),
            type: .image(format: "png"),
            subtitleBadge: "PNG • \(dimStr)",
            extractionStatus: "STAGING",
            semanticCategory: .image,
            previewThumbnail: thumb
        )
        return (preview, cg)
    }

    private static func encodeCGImageFast(_ cgImage: CGImage, maxPixelEdge: Int = 2048) -> (data: Data, mimeType: String) {
        let w = cgImage.width
        let h = cgImage.height
        let maxEdge = max(w, h)
        let targetCG: CGImage
        if maxEdge > maxPixelEdge {
            let scale = Double(maxPixelEdge) / Double(maxEdge)
            let tw = max(1, Int(round(Double(w) * scale)))
            let th = max(1, Int(round(Double(h) * scale)))
            if let ctx = CGContext(
                data: nil,
                width: tw,
                height: th,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                ctx.interpolationQuality = .high
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: tw, height: th))
                targetCG = ctx.makeImage() ?? cgImage
            } else {
                targetCG = cgImage
            }
        } else {
            targetCG = cgImage
        }

        // Encode via hardware-accelerated ImageIO CGImageDestination
        let pngBuf = NSMutableData()
        if let dest = CGImageDestinationCreateWithData(pngBuf as CFMutableData, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, targetCG, nil)
            if CGImageDestinationFinalize(dest), pngBuf.length <= 3_800_000 {
                return (pngBuf as Data, "image/png")
            }
        }
        let jpgBuf = NSMutableData()
        if let dest = CGImageDestinationCreateWithData(jpgBuf as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) {
            let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.86]
            CGImageDestinationAddImage(dest, targetCG, opts as CFDictionary)
            if CGImageDestinationFinalize(dest) {
                return (jpgBuf as Data, "image/jpeg")
            }
        }
        return (pngBuf as Data, "image/png")
    }

    private func lookupInFlightTask(_ id: UUID) -> Task<AIAttachment, Never>? {
        stateLock.withLock { inFlightTasks[id] }
    }

    private func removeInFlightTask(_ id: UUID) {
        _ = stateLock.withLock { inFlightTasks.removeValue(forKey: id) }
    }

    /// Launches Stage-2 vault staging & content indexing on a detached background executor.
    /// Tracked by `preview.id` so if the user hits Send immediately, `ensureIngested` awaits the exact same task with zero duplicate work.
    @discardableResult
    func stageInBackground(
        preview: AIAttachment,
        clipboardCGImage: CGImage? = nil,
        rawData: Data? = nil,
        chatId: String?,
        totalBatchCount: Int = 1,
        eagerImageOCR: Bool = false
    ) -> Task<AIAttachment, Never> {
        let task = Task.detached(priority: .userInitiated) { [self] () -> AIAttachment in
            defer {
                self.removeInFlightTask(preview.id)
            }
            var result: AIAttachment
            if let cg = clipboardCGImage {
                let encoded = Self.encodeCGImageFast(cg)
                result = await self.ingestDataInternal(
                    id: preview.id,
                    data: encoded.data,
                    fileName: preview.name,
                    explicitType: encoded.mimeType == "image/jpeg" ? .image(format: "jpeg") : .image(format: "png"),
                    chatId: chatId,
                    eagerImageOCR: eagerImageOCR,
                    preNormalizedVision: encoded
                )
            } else if let rawData {
                result = await self.ingestDataInternal(
                    id: preview.id,
                    data: rawData,
                    fileName: preview.name,
                    explicitType: preview.type,
                    chatId: chatId,
                    eagerImageOCR: eagerImageOCR
                )
            } else if let src = preview.sourceURL {
                result = await self.ingestSingleURL(
                    src,
                    existingID: preview.id,
                    chatId: chatId,
                    totalBatchCount: totalBatchCount,
                    eagerImageOCR: eagerImageOCR
                )
            } else {
                result = preview
            }
            if result.previewThumbnail == nil, let thumb = preview.previewThumbnail {
                result.previewThumbnail = thumb
            }
            return result
        }
        stateLock.lock()
        inFlightTasks[preview.id] = task
        stateLock.unlock()
        return task
    }

    func cancelBackgroundStage(id: UUID) {
        stateLock.lock()
        let task = inFlightTasks.removeValue(forKey: id)
        stateLock.unlock()
        task?.cancel()
    }

    // MARK: - Vault Pruning (7-Day Retention)

    private func scheduleStaleVaultPruningOnce() {
        stateLock.lock()
        let shouldRun = !didScheduleStartupPrune
        didScheduleStartupPrune = true
        stateLock.unlock()
        guard shouldRun else { return }

        Task.detached(priority: .background) {
            let fm = FileManager.default
            let root = Self.vaultRootDirectory
            guard let items = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            let cutoff = Date().addingTimeInterval(-Self.staleBucketMaxAgeSeconds)
            for item in items {
                guard let vals = try? item.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey]),
                      vals.isDirectory == true else { continue }
                let lastTouched = vals.contentModificationDate ?? vals.creationDate ?? .distantPast
                if lastTouched < cutoff {
                    try? fm.removeItem(at: item)
                }
            }
        }
    }

    // MARK: - Session Bucket & Staging Helpers

    static func sessionBucketDirectory(for chatId: String?) -> URL {
        let raw = (chatId?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? defaultDateBucketName()
        let clean = raw.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let bucketName = clean.isEmpty ? defaultDateBucketName() : String(clean.prefix(64))
        let dir = vaultRootDirectory.appendingPathComponent(bucketName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func defaultDateBucketName() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd"
        return "session_\(fmt.string(from: Date()))"
    }

    static func sanitizeFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "attachment.bin" }
        let cleaned = trimmed.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        return cleaned.isEmpty ? "attachment.bin" : String(cleaned.prefix(96))
    }

    private static func makeShortHexID(_ uuid: UUID = UUID()) -> String {
        String(uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8))
    }

    // MARK: - Public Ingestion Entry Points

    /// Concurrently ingests an array of file/folder URLs off the MainActor with bounded parallelism,
    /// safely handling 50–100+ simultaneous attachments without blocking UI or exhausting RAM.
    func ingest(urls: [URL], chatId: String?, eagerImageOCR: Bool = false) async -> [AIAttachment] {
        guard !urls.isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) { [self] in
            let maxConcurrency = 6
            var indexedResults: [(Int, AIAttachment)] = []
            indexedResults.reserveCapacity(urls.count)

            await withTaskGroup(of: (Int, AIAttachment)?.self) { group in
                var nextIndex = 0
                let initialCount = min(maxConcurrency, urls.count)
                for _ in 0..<initialCount {
                    let idx = nextIndex
                    let url = urls[idx]
                    nextIndex += 1
                    group.addTask(priority: .userInitiated) {
                        let item = await self.ingestSingleURL(
                            url,
                            chatId: chatId,
                            totalBatchCount: urls.count,
                            eagerImageOCR: eagerImageOCR
                        )
                        return (idx, item)
                    }
                }
                while let completed = await group.next() {
                    if let pair = completed {
                        indexedResults.append(pair)
                    }
                    if nextIndex < urls.count {
                        let idx = nextIndex
                        let url = urls[idx]
                        nextIndex += 1
                        group.addTask(priority: .userInitiated) {
                            let item = await self.ingestSingleURL(
                                url,
                                chatId: chatId,
                                totalBatchCount: urls.count,
                                eagerImageOCR: eagerImageOCR
                            )
                            return (idx, item)
                        }
                    }
                }
            }

            return indexedResults.sorted { $0.0 < $1.0 }.map { $0.1 }
        }.value
    }

    /// Stages and analyzes raw in-memory bytes (e.g., pasted clipboard image or drag-dropped data) off `@MainActor`.
    func ingestData(
        data: Data,
        fileName: String,
        explicitType: AIAttachment.AttachmentType? = nil,
        chatId: String?,
        eagerImageOCR: Bool = false
    ) async -> AIAttachment {
        await Task.detached(priority: .userInitiated) { [self] in
            await self.ingestDataInternal(
                id: UUID(),
                data: data,
                fileName: fileName,
                explicitType: explicitType,
                chatId: chatId,
                eagerImageOCR: eagerImageOCR
            )
        }.value
    }

    private func ingestDataInternal(
        id attachmentUUID: UUID,
        data: Data,
        fileName: String,
        explicitType: AIAttachment.AttachmentType? = nil,
        chatId: String?,
        eagerImageOCR: Bool = false,
        preNormalizedVision: (data: Data, mimeType: String)? = nil
    ) async -> AIAttachment {
        let shortHex = Self.makeShortHexID(attachmentUUID)
        let bucketDir = Self.sessionBucketDirectory(for: chatId)
        let safeName = Self.sanitizeFileName(fileName)
        let stagedURL = bucketDir.appendingPathComponent("\(shortHex)_\(safeName)")

        try? data.write(to: stagedURL, options: .atomic)
        let extracted = await extractFromFileOrDirectory(
            targetURL: stagedURL,
            originalName: fileName,
            stagedVaultURL: stagedURL,
            fileSize: Int64(data.count),
            isDirectory: false,
            eagerImageOCR: eagerImageOCR,
            preNormalizedVision: preNormalizedVision
        )

        let extractedCacheURL = stagedURL.appendingPathExtension("extracted.txt")
        if !extracted.extractedText.isEmpty {
            try? extracted.extractedText.write(to: extractedCacheURL, atomically: true, encoding: .utf8)
        }
        let sidecar = VaultAttachmentSidecar(
            attachmentId: attachmentUUID.uuidString,
            originalName: fileName,
            authorizedSourcePath: stagedURL.path,
            stagedPath: stagedURL.path,
            extractedTextCachePath: FileManager.default.fileExists(atPath: extractedCacheURL.path) ? extractedCacheURL.path : nil,
            fileSizeBytes: Int64(data.count),
            semanticCategory: extracted.semanticCategory.rawValue,
            subtitleBadge: extracted.subtitleBadge,
            metricsSummary: extracted.metricsSummary,
            extractionStatus: extracted.extractionStatus,
            extractionWarning: extracted.extractionWarning,
            isPasswordProtected: extracted.isPasswordProtected,
            createdAt: Date()
        )
        writeSidecar(sidecar, alongside: stagedURL)

        let resolvedType = explicitType ?? extracted.attachmentType
        let keepInlineData: Data = {
            if case .image = resolvedType {
                return extracted.normalizedVisionData ?? (data.count <= Int(Self.maxInMemoryAttachmentDataBytes) ? data : Data())
            }
            if data.count <= 2 * 1024 * 1024 {
                return data
            }
            return Data()
        }()

        return AIAttachment(
            id: attachmentUUID,
            name: fileName,
            data: keepInlineData,
            type: resolvedType,
            sourceURL: stagedURL,
            stagedPath: stagedURL.path,
            extractedTextCachePath: FileManager.default.fileExists(atPath: extractedCacheURL.path) ? extractedCacheURL.path : nil,
            extractedFullText: extracted.extractedText,
            subtitleBadge: extracted.subtitleBadge,
            metricsSummary: extracted.metricsSummary,
            extractionStatus: extracted.extractionStatus,
            extractionWarning: extracted.extractionWarning,
            normalizedVisionData: extracted.normalizedVisionData,
            normalizedVisionMimeType: extracted.normalizedVisionMimeType,
            nativeMediaMimeType: extracted.nativeMediaMimeType,
            fileSizeBytes: Int64(data.count),
            semanticCategory: extracted.semanticCategory,
            isPasswordProtected: extracted.isPasswordProtected,
            includeInlineTextInProviderPayload: true
        )
    }

    /// Ensures any optimistic Stage-1 or legacy `AIAttachment` instances finish background staging
    /// (reusing `inFlightTasks` with zero duplicate work) and enriches images with Apple Vision OCR
    /// automatically if the selected model is text-only (`requireImageOCR == true`).
    func ensureIngested(
        _ attachments: [AIAttachment],
        chatId: String?,
        requireImageOCR: Bool = false
    ) async -> [AIAttachment] {
        guard !attachments.isEmpty else { return [] }
        var output: [AIAttachment] = []
        output.reserveCapacity(attachments.count)
        for item in attachments {
            let inFlight = lookupInFlightTask(item.id)

            var resolved: AIAttachment
            if let inFlight {
                resolved = await inFlight.value
                resolved.includeInlineTextInProviderPayload = item.includeInlineTextInProviderPayload
            } else if let staged = item.stagedPath, !staged.isEmpty,
                      (item.extractedFullText != nil || item.extractedTextCachePath != nil) {
                resolved = item
            } else if let src = item.sourceURL, FileManager.default.fileExists(atPath: src.path) {
                let captured = item
                resolved = await Task.detached(priority: .userInitiated) { [self] in
                    await self.ingestSingleURL(
                        src,
                        existingID: captured.id,
                        chatId: chatId,
                        totalBatchCount: attachments.count,
                        eagerImageOCR: requireImageOCR
                    )
                }.value
                resolved.includeInlineTextInProviderPayload = item.includeInlineTextInProviderPayload
            } else {
                let captured = item
                resolved = await Task.detached(priority: .userInitiated) { [self] in
                    await self.ingestDataInternal(
                        id: captured.id,
                        data: captured.data,
                        fileName: captured.name,
                        explicitType: captured.type,
                        chatId: chatId,
                        eagerImageOCR: requireImageOCR
                    )
                }.value
                resolved.includeInlineTextInProviderPayload = item.includeInlineTextInProviderPayload
            }

            if resolved.previewThumbnail == nil, let thumb = item.previewThumbnail {
                resolved.previewThumbnail = thumb
            }

            // Text-only LLM fallback: if image skipped Vision OCR during fast staging, run accurate ANE OCR now
            if requireImageOCR && resolved.semanticCategory == .image && resolved.extractionStatus == "FAST_IMAGE_READY" {
                let visionBytes = resolved.effectiveVisionData.isEmpty
                    ? (resolved.loadRawBinaryData(maxBytes: 15 * 1024 * 1024) ?? Data())
                    : resolved.effectiveVisionData
                if !visionBytes.isEmpty {
                    let vision = await AppleVisionEngine.shared.analyzeImage(data: visionBytes, filename: resolved.name)
                    resolved.extractedFullText = vision.formattedSummary
                    resolved.extractionStatus = vision.extractedText.isEmpty ? "READ_OK" : "OCR_EXTRACTED"
                    if let staged = resolved.stagedPath {
                        let cachePath = staged + ".extracted.txt"
                        try? vision.formattedSummary.write(toFile: cachePath, atomically: true, encoding: .utf8)
                        resolved.extractedTextCachePath = cachePath
                    }
                }
            }

            output.append(resolved)
        }
        return output
    }

    // MARK: - Single URL Staging & Extraction

    private func ingestSingleURL(
        _ rawURL: URL,
        existingID: UUID? = nil,
        chatId: String?,
        totalBatchCount: Int,
        eagerImageOCR: Bool = false
    ) async -> AIAttachment {
        let fm = FileManager.default
        let attachmentUUID = existingID ?? UUID()
        let shortHex = Self.makeShortHexID(attachmentUUID)
        let bucketDir = Self.sessionBucketDirectory(for: chatId)
        let canonicalSourcePath = WorkspacePathPolicy.canonicalPath(rawURL.path)
        let sourceURL = URL(fileURLWithPath: canonicalSourcePath)
        let displayName = rawURL.lastPathComponent.isEmpty ? sourceURL.lastPathComponent : rawURL.lastPathComponent
        let safeName = Self.sanitizeFileName(displayName)

        var isDirObj: ObjCBool = false
        let exists = fm.fileExists(atPath: sourceURL.path, isDirectory: &isDirObj)
        let isDirectory = exists && isDirObj.boolValue

        if !exists {
            let warn = "File does not exist or is unreadable at '\(rawURL.path)'"
            let stagedFallback = bucketDir.appendingPathComponent("\(shortHex)_\(safeName).missing.txt")
            let msg = "[ATTACHMENT ERROR: '\(displayName)' could not be read from disk (\(warn)).]"
            try? msg.write(to: stagedFallback, atomically: true, encoding: .utf8)
            return AIAttachment(
                id: attachmentUUID,
                name: displayName,
                data: Data(),
                type: .text,
                sourceURL: rawURL,
                stagedPath: stagedFallback.path,
                extractedTextCachePath: stagedFallback.path,
                extractedFullText: msg,
                subtitleBadge: "Unreadable",
                metricsSummary: "missing",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: warn,
                fileSizeBytes: 0,
                semanticCategory: .binary
            )
        }

        let stagedURL = bucketDir.appendingPathComponent("\(shortHex)_\(safeName)", isDirectory: isDirectory)
        let fileSize: Int64
        if isDirectory {
            fileSize = computeDirectoryTotalBytes(at: sourceURL, maxEntries: 2_000)
            try? fm.createDirectory(at: stagedURL, withIntermediateDirectories: true)
        } else {
            let attr = try? fm.attributesOfItem(atPath: sourceURL.path)
            fileSize = (attr?[.size] as? NSNumber)?.int64Value ?? 0
            if fileSize <= Self.maxDirectCopyBytes {
                try? fm.removeItem(at: stagedURL)
                do {
                    try fm.copyItem(at: sourceURL, to: stagedURL)
                } catch {
                    // Fallback: read-only manifest stub if APFS copy fails (e.g. special FIFO/permission)
                    let manifestStub = "Manifest for \(displayName)\nCanonical Source: \(sourceURL.path)\nSize: \(fileSize) bytes\n"
                    try? manifestStub.write(to: stagedURL, atomically: true, encoding: .utf8)
                }
            } else {
                let manifestText = """
                [LARGE ATTACHMENT VAULT MANIFEST]
                Original Filename: \(displayName)
                Size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)) (\(fileSize) bytes)
                Note: File exceeds 128 MB direct vault clone threshold; indexed text is cached in .extracted.txt and paged on-demand via attachment_read.
                """
                try? manifestText.write(to: stagedURL, atomically: true, encoding: .utf8)
            }
        }

        let readTargetURL = (!isDirectory && fileSize <= Self.maxDirectCopyBytes && fm.fileExists(atPath: stagedURL.path))
            ? stagedURL
            : sourceURL

        let extracted = await extractFromFileOrDirectory(
            targetURL: readTargetURL,
            originalName: displayName,
            stagedVaultURL: stagedURL,
            fileSize: fileSize,
            isDirectory: isDirectory,
            eagerImageOCR: eagerImageOCR
        )

        let extractedCacheURL = URL(fileURLWithPath: stagedURL.path + ".extracted.txt")
        if !extracted.extractedText.isEmpty {
            try? extracted.extractedText.write(to: extractedCacheURL, atomically: true, encoding: .utf8)
        }

        let sidecar = VaultAttachmentSidecar(
            attachmentId: attachmentUUID.uuidString,
            originalName: displayName,
            authorizedSourcePath: sourceURL.path,
            stagedPath: stagedURL.path,
            extractedTextCachePath: fm.fileExists(atPath: extractedCacheURL.path) ? extractedCacheURL.path : nil,
            fileSizeBytes: fileSize,
            semanticCategory: extracted.semanticCategory.rawValue,
            subtitleBadge: extracted.subtitleBadge,
            metricsSummary: extracted.metricsSummary,
            extractionStatus: extracted.extractionStatus,
            extractionWarning: extracted.extractionWarning,
            isPasswordProtected: extracted.isPasswordProtected,
            createdAt: Date()
        )
        writeSidecar(sidecar, alongside: stagedURL)

        // RAM budget discipline: when attaching many files or large containers, keep resident Data minimal
        // because AIClient.loadRawBinaryData(maxBytes:) memory-maps from stagedPath on demand!
        let residentData: Data = {
            if case .image = extracted.attachmentType {
                if let norm = extracted.normalizedVisionData { return norm }
                if fileSize <= 4 * 1024 * 1024, let raw = try? Data(contentsOf: readTargetURL) { return raw }
                return Data()
            }
            if totalBatchCount <= 8 && !isDirectory && fileSize > 0 && fileSize <= 2 * 1024 * 1024,
               case .pdf = extracted.attachmentType,
               let raw = try? Data(contentsOf: readTargetURL) {
                return raw
            }
            return Data()
        }()

        let hasExtractedCache = fm.fileExists(atPath: extractedCacheURL.path)
        let residentTextLimit = totalBatchCount > 20 ? 32_000 : 256_000
        let residentExtractedText: String? = (hasExtractedCache && extracted.extractedText.utf8.count > residentTextLimit)
            ? nil
            : extracted.extractedText

        return AIAttachment(
            id: attachmentUUID,
            name: displayName,
            data: residentData,
            type: extracted.attachmentType,
            sourceURL: sourceURL,
            stagedPath: stagedURL.path,
            extractedTextCachePath: hasExtractedCache ? extractedCacheURL.path : nil,
            extractedFullText: residentExtractedText,
            subtitleBadge: extracted.subtitleBadge,
            metricsSummary: extracted.metricsSummary,
            extractionStatus: extracted.extractionStatus,
            extractionWarning: extracted.extractionWarning,
            normalizedVisionData: extracted.normalizedVisionData,
            normalizedVisionMimeType: extracted.normalizedVisionMimeType,
            nativeMediaMimeType: extracted.nativeMediaMimeType,
            fileSizeBytes: fileSize,
            semanticCategory: extracted.semanticCategory,
            isPasswordProtected: extracted.isPasswordProtected,
            includeInlineTextInProviderPayload: true
        )
    }

    private func writeSidecar(_ sidecar: VaultAttachmentSidecar, alongside stagedURL: URL) {
        let metaURL = URL(fileURLWithPath: stagedURL.path + ".meta.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let json = try? encoder.encode(sidecar) {
            try? json.write(to: metaURL, options: .atomic)
        }
    }

    private func readSidecar(for path: String) -> VaultAttachmentSidecar? {
        let candidates = [
            path + ".meta.json",
            path.hasSuffix(".extracted.txt") ? String(path.dropLast(".extracted.txt".count)) + ".meta.json" : nil
        ].compactMap { $0 }
        for metaPath in candidates {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
               let decoded = try? JSONDecoder().decode(VaultAttachmentSidecar.self, from: data) {
                return decoded
            }
        }
        return nil
    }

    // MARK: - Master Format Router

    private func extractFromFileOrDirectory(
        targetURL: URL,
        originalName: String,
        stagedVaultURL: URL,
        fileSize: Int64,
        isDirectory: Bool,
        eagerImageOCR: Bool = false,
        preNormalizedVision: (data: Data, mimeType: String)? = nil
    ) async -> AttachmentExtractionPayload {
        let sizeStr = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        if isDirectory {
            return extractDirectory(sourceDir: targetURL, stagedDir: stagedVaultURL, folderName: originalName, totalSize: fileSize)
        }

        let lowerName = originalName.lowercased()
        let ext = (originalName as NSString).pathExtension.lowercased()

        // Compound archive extensions (.tar.gz, .tar.bz2, .tar.xz)
        if lowerName.hasSuffix(".tar.gz") || lowerName.hasSuffix(".tgz") ||
           lowerName.hasSuffix(".tar.bz2") || lowerName.hasSuffix(".tbz2") ||
           lowerName.hasSuffix(".tar.xz") || lowerName.hasSuffix(".txz") ||
           ext == "tar" {
            return extractTarArchive(url: targetURL, name: originalName, stagedVaultURL: stagedVaultURL, sizeStr: sizeStr)
        }

        switch ext {
        case "pdf":
            return await extractPDF(url: targetURL, name: originalName, stagedPath: stagedVaultURL.path, sizeStr: sizeStr)
        case "docx":
            return extractDOCX(url: targetURL, name: originalName, sizeStr: sizeStr)
        case "xlsx":
            return extractXLSX(url: targetURL, name: originalName, sizeStr: sizeStr)
        case "pptx":
            return extractPPTX(url: targetURL, name: originalName, sizeStr: sizeStr)
        case "rtf", "rtfd", "doc", "odt":
            return extractRichDocument(url: targetURL, ext: ext, name: originalName, sizeStr: sizeStr)
        case "html", "htm", "xhtml":
            return extractHTMLDocument(url: targetURL, name: originalName, sizeStr: sizeStr)
        case "epub":
            return extractEPUB(url: targetURL, name: originalName, sizeStr: sizeStr)
        case "csv", "tsv":
            return extractDelimitedTable(url: targetURL, ext: ext, name: originalName, fileSize: fileSize, sizeStr: sizeStr)
        case "ipynb":
            return extractJupyterNotebook(url: targetURL, name: originalName, sizeStr: sizeStr)
        case "sqlite", "sqlite3", "db":
            return extractSQLiteDatabase(url: targetURL, name: originalName, sizeStr: sizeStr)
        case "parquet":
            return extractParquet(url: targetURL, name: originalName, stagedPath: stagedVaultURL.path, fileSize: fileSize, sizeStr: sizeStr)
        case "png", "jpg", "jpeg", "webp", "heic", "heif", "gif", "bmp", "tiff", "tif", "svg", "icns":
            return await extractImage(
                url: targetURL,
                ext: ext,
                name: originalName,
                stagedPath: stagedVaultURL.path,
                sizeStr: sizeStr,
                eagerOCR: eagerImageOCR,
                preNormalizedVision: preNormalizedVision
            )
        case "mp3", "wav", "m4a", "aac", "flac", "ogg":
            return await extractAudioOrVideo(url: targetURL, ext: ext, isVideo: false, name: originalName, sizeStr: sizeStr)
        case "mp4", "mov", "m4v", "webm", "avi", "mkv":
            return await extractAudioOrVideo(url: targetURL, ext: ext, isVideo: true, name: originalName, sizeStr: sizeStr)
        case "zip":
            return extractZipArchive(url: targetURL, name: originalName, stagedVaultURL: stagedVaultURL, sizeStr: sizeStr)
        case "gz", "bz2", "xz":
            return extractCompressedSingleFile(url: targetURL, ext: ext, name: originalName, stagedVaultURL: stagedVaultURL, sizeStr: sizeStr)
        default:
            return extractGenericTextOrBinary(url: targetURL, ext: ext, name: originalName, fileSize: fileSize, sizeStr: sizeStr)
        }
    }

    // MARK: - Bounded Process Execution (Deadlock-Free & Zip-Bomb Safe)

    struct ProcessOutput {
        let exitCode: Int32
        let stdout: Data
        let stderr: Data
        let truncated: Bool
        let timedOut: Bool
    }

    static func runBoundedCommand(
        executable: String,
        arguments: [String],
        maxOutputBytes: Int = 12 * 1024 * 1024,
        timeoutSeconds: TimeInterval = 10.0
    ) -> ProcessOutput {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return ProcessOutput(exitCode: -1, stdout: Data(), stderr: Data("Executable not found".utf8), truncated: false, timedOut: false)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return ProcessOutput(exitCode: -1, stdout: Data(), stderr: Data(error.localizedDescription.utf8), truncated: false, timedOut: false)
        }

        final class CollectorState: @unchecked Sendable {
            var stdout = Data()
            var stderr = Data()
            var truncated = false
            var timedOut = false
        }
        let state = CollectorState()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let handle = outPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                let remaining = maxOutputBytes - state.stdout.count
                if remaining > 0 {
                    state.stdout.append(chunk.prefix(remaining))
                }
                if state.stdout.count >= maxOutputBytes {
                    state.truncated = true
                    if proc.isRunning { proc.terminate() }
                    break
                }
            }
            try? handle.close()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let handle = errPipe.fileHandleForReading
            let errCap = 64 * 1024
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                if state.stderr.count < errCap {
                    state.stderr.append(chunk.prefix(errCap - state.stderr.count))
                } else {
                    break
                }
            }
            try? handle.close()
            group.leave()
        }

        let timeoutWork = DispatchWorkItem {
            if proc.isRunning {
                state.timedOut = true
                proc.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWork)

        proc.waitUntilExit()
        timeoutWork.cancel()
        _ = group.wait(timeout: .now() + 2.0)

        return ProcessOutput(
            exitCode: proc.terminationStatus,
            stdout: state.stdout,
            stderr: state.stderr,
            truncated: state.truncated,
            timedOut: state.timedOut
        )
    }

    static func escapeUnzipEntryGlob(_ entry: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(entry.count + 4)
        for ch in entry {
            if ch == "[" || ch == "]" || ch == "*" || ch == "?" {
                escaped.append("\\")
            }
            escaped.append(ch)
        }
        return escaped
    }

    // MARK: - Smart Multi-Encoding Text Decoder (UTF-8 / UTF-16 / Thai Windows-874 & TIS-620 / CP1252)

    static func decodeTextSmart(_ data: Data) -> (text: String, encodingName: String)? {
        if data.isEmpty {
            return ("", "UTF-8")
        }

        // 1. Explicit BOM checks
        if data.count >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
            if let s = String(data: data.dropFirst(3), encoding: .utf8) {
                return (s, "UTF-8 (BOM)")
            }
        }
        if data.count >= 4 && data[0] == 0xFF && data[1] == 0xFE && data[2] == 0x00 && data[3] == 0x00 {
            if let s = String(data: data.dropFirst(4), encoding: .utf32LittleEndian) {
                return (s, "UTF-32LE")
            }
        }
        if data.count >= 4 && data[0] == 0x00 && data[1] == 0x00 && data[2] == 0xFE && data[3] == 0xFF {
            if let s = String(data: data.dropFirst(4), encoding: .utf32BigEndian) {
                return (s, "UTF-32BE")
            }
        }
        if data.count >= 2 && data[0] == 0xFF && data[1] == 0xFE {
            if let s = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
                return (s, "UTF-16LE")
            }
        }
        if data.count >= 2 && data[0] == 0xFE && data[1] == 0xFF {
            if let s = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
                return (s, "UTF-16BE")
            }
        }

        // Inspect byte statistics on up to 64 KB sample
        let sampleLen = min(data.count, 65_536)
        var nullCount = 0
        var evenNulls = 0
        var oddNulls = 0
        var thaiHighBytes = 0
        for i in 0..<sampleLen {
            let b = data[i]
            if b == 0 {
                nullCount += 1
                if i % 2 == 0 { evenNulls += 1 } else { oddNulls += 1 }
            } else if (b >= 0xA1 && b <= 0xFB) || b == 0x80 || b == 0x85 || (b >= 0x91 && b <= 0x97) {
                thaiHighBytes += 1
            }
        }

        // 2. Strict UTF-8 (when no binary null-byte contamination)
        if nullCount == 0, let utf8 = String(data: data, encoding: .utf8) {
            if printableScalarRatio(utf8) >= 0.85 {
                return (utf8, "UTF-8")
            }
        }

        // 3. BOM-less UTF-16LE / UTF-16BE (common in Excel "Unicode Text" TSV exports)
        if data.count >= 4 && data.count % 2 == 0 && nullCount > sampleLen / 5 {
            if oddNulls > evenNulls * 3, let s = String(data: data, encoding: .utf16LittleEndian), printableScalarRatio(s) >= 0.86 {
                return (s, "UTF-16LE")
            }
            if evenNulls > oddNulls * 3, let s = String(data: data, encoding: .utf16BigEndian), printableScalarRatio(s) >= 0.86 {
                return (s, "UTF-16BE")
            }
        }

        // Reject binary payloads containing NUL bytes before single-byte codepage fallbacks
        guard nullCount == 0 else { return nil }

        // 4. Thai Windows-874 (CP874) & TIS-620 (ISO-8859-11)
        if thaiHighBytes > 0 {
            let thaiEncodings: [(CFStringEncodings, String)] = [
                (.dosThai, "Thai Windows-874"),
                (.isoLatinThai, "Thai TIS-620")
            ]
            for (cfEnc, label) in thaiEncodings {
                let nsEnc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEnc.rawValue))
                let encoding = String.Encoding(rawValue: nsEnc)
                if let decoded = String(data: data, encoding: encoding) {
                    let stats = analyzeThaiAndPrintableScalars(decoded)
                    if stats.validThaiCount >= 1 && stats.invalidThaiUnassignedCount == 0 && stats.printableRatio >= 0.88 {
                        return (decoded, label)
                    }
                }
            }
        }

        // 5. Strict Windows-1252 / ISO-8859-1 ONLY if printable ratio >= 0.88 and 0 null bytes
        if let cp1252 = String(data: data, encoding: .windowsCP1252), printableScalarRatio(cp1252) >= 0.88 {
            return (cp1252, "Windows-1252")
        }
        if let latin1 = String(data: data, encoding: .isoLatin1), printableScalarRatio(latin1) >= 0.88 {
            return (latin1, "ISO-8859-1")
        }

        return nil
    }

    private static func printableScalarRatio(_ text: String) -> Double {
        var total = 0
        var printable = 0
        for scalar in text.unicodeScalars {
            total += 1
            if total > 32_768 { break }
            let v = scalar.value
            if v == 0x09 || v == 0x0A || v == 0x0D {
                printable += 1
            } else if v < 0x20 || (v >= 0x7F && v <= 0x9F) || v == 0xFFFD {
                continue
            } else {
                printable += 1
            }
        }
        guard total > 0 else { return 1.0 }
        return Double(printable) / Double(total)
    }

    private static func analyzeThaiAndPrintableScalars(_ text: String) -> (validThaiCount: Int, invalidThaiUnassignedCount: Int, printableRatio: Double) {
        var total = 0
        var printable = 0
        var validThai = 0
        var invalidThai = 0
        for scalar in text.unicodeScalars {
            total += 1
            if total > 32_768 { break }
            let v = scalar.value
            if v >= 0x0E01 && v <= 0x0E5B {
                if v >= 0x0E3B && v <= 0x0E3E {
                    invalidThai += 1
                } else {
                    validThai += 1
                    printable += 1
                }
            } else if v >= 0x0E5C && v <= 0x0E7F {
                invalidThai += 1
            } else if v == 0x09 || v == 0x0A || v == 0x0D {
                printable += 1
            } else if v < 0x20 || (v >= 0x7F && v <= 0x9F) || v == 0xFFFD {
                continue
            } else {
                printable += 1
            }
        }
        let ratio = total > 0 ? Double(printable) / Double(total) : 1.0
        return (validThai, invalidThai, ratio)
    }

    // MARK: - 1. PDF Extractor (Digital Layer + Scanned/Chart ANE Vision OCR)

    private func extractPDF(url: URL, name: String, stagedPath: String, sizeStr: String) async -> AttachmentExtractionPayload {
        guard let doc = PDFDocument(url: url) else {
            let warn = "Corrupted or unreadable PDF header"
            return AttachmentExtractionPayload(
                attachmentType: .pdf,
                semanticCategory: .pdf,
                extractedText: "[PDF EXTRACTION WARNING: '\(name)' could not be parsed by PDFKit (\(warn)). Do NOT guess internal contents.]",
                subtitleBadge: "PDF • Error • \(sizeStr)",
                metricsSummary: "unreadable PDF",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: warn,
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: "application/pdf"
            )
        }

        if doc.isLocked && !doc.unlock(withPassword: "") {
            let warn = "Encrypted / password-protected PDF — cannot read pages without password"
            return AttachmentExtractionPayload(
                attachmentType: .pdf,
                semanticCategory: .pdf,
                extractedText: "[LOCKED PDF WARNING: '\(name)' (\(sizeStr)) is encrypted / password-protected. Pages cannot be read without a password. Inform the user clearly and do NOT guess its contents.]",
                subtitleBadge: "PDF • Locked • \(sizeStr)",
                metricsSummary: "password-locked",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: warn,
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: "application/pdf",
                isPasswordProtected: true
            )
        }

        let totalPages = doc.pageCount
        if totalPages == 0 {
            let warn = "PDF has 0 pages"
            return AttachmentExtractionPayload(
                attachmentType: .pdf,
                semanticCategory: .pdf,
                extractedText: "[PDF WARNING: '\(name)' contains 0 pages.]",
                subtitleBadge: "PDF • 0p • \(sizeStr)",
                metricsSummary: "0 pages",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: warn,
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: "application/pdf"
            )
        }

        var sections: [String] = []
        sections.reserveCapacity(totalPages + 1)
        sections.append("[PDF Document: \(name) | Total Pages: \(totalPages) | Size: \(sizeStr)]")

        var ocrCount = 0
        var unocredLowTextPages: [Int] = []
        var firstRasterizedPagePNG: Data? = nil
        // Fast background PDF ingestion: only run quick preview OCR on Page 1 of scanned PDFs during staging
        // so 50-page scanned PDFs stage in <60ms instead of 15s; `attachment_read(..., ocr: true)` performs full `.accurate` OCR on demand.
        let maxAutoOCRPages = 1

        for idx in 0..<totalPages {
            let pageNum = idx + 1
            guard let page = doc.page(at: idx) else { continue }
            let rawText = page.string ?? ""
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

            var pageBody = trimmed
            if trimmed.count < 48 {
                if ocrCount < maxAutoOCRPages,
                   let pngData = Self.rasterizePDFPageToPNG(page: page, dpi: 135.0) {
                    if firstRasterizedPagePNG == nil && pngData.count <= 4_500_000 {
                        firstRasterizedPagePNG = pngData
                    }
                    ocrCount += 1
                    let vision = await AppleVisionEngine.shared.analyzeImage(
                        data: pngData,
                        filename: "\(name)#page-\(pageNum).png",
                        fastPreview: true
                    )
                    let ocrText = vision.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let ocrNote = ocrText.isEmpty
                        ? "[Page \(pageNum) Fast Preview OCR]: (Graphical/scanned page — call `attachment_read(path: \"\(stagedPath)\", page_start: \(pageNum), page_end: \(min(totalPages, pageNum + 9)), ocr: true)` for high-precision multi-language OCR)"
                        : "[Page \(pageNum) Fast Preview OCR]:\n\(ocrText)"
                    pageBody = pageBody.isEmpty ? ocrNote : (pageBody + "\n\n" + ocrNote)
                } else {
                    unocredLowTextPages.append(pageNum)
                    let deferredNote = "[Page \(pageNum): Scanned/low-text page (\(trimmed.count) digital chars) — call `attachment_read(path: \"\(stagedPath)\", page_start: \(pageNum), page_end: \(min(totalPages, pageNum + 9)), ocr: true)` to run ANE Vision OCR on demand]"
                    pageBody = pageBody.isEmpty ? deferredNote : (pageBody + "\n" + deferredNote)
                }
            }

            sections.append("=== Page \(pageNum) of \(totalPages) ===\n\(pageBody)")
        }

        let status = ocrCount > 0 ? "OCR_EXTRACTED" : "READ_OK"
        let metrics = ocrCount > 0
            ? "\(totalPages) pages (\(ocrCount) ANE OCR)"
            : "\(totalPages) pages"
        let badge = ocrCount > 0
            ? "PDF • \(totalPages)p (OCR) • \(sizeStr)"
            : "PDF • \(totalPages)p • \(sizeStr)"
        let warning: String? = unocredLowTextPages.isEmpty
            ? nil
            : "\(unocredLowTextPages.count) additional scanned page(s) available via attachment_read(ocr: true)"

        return AttachmentExtractionPayload(
            attachmentType: .pdf,
            semanticCategory: .pdf,
            extractedText: sections.joined(separator: "\n\n"),
            subtitleBadge: badge,
            metricsSummary: metrics,
            extractionStatus: status,
            extractionWarning: warning,
            normalizedVisionData: firstRasterizedPagePNG,
            normalizedVisionMimeType: firstRasterizedPagePNG != nil ? "image/png" : nil,
            nativeMediaMimeType: "application/pdf"
        )
    }

    static func rasterizePDFPageToPNG(page: PDFPage, dpi: CGFloat = 150.0) -> Data? {
        let mediaBounds = page.bounds(for: .mediaBox)
        guard mediaBounds.width > 1, mediaBounds.height > 1 else { return nil }
        let rawScale = dpi / 72.0
        let maxEdge = max(mediaBounds.width * rawScale, mediaBounds.height * rawScale)
        let clampedScale = maxEdge > 2200.0 ? (2200.0 / max(mediaBounds.width, mediaBounds.height)) : rawScale

        let pixelWidth = max(1, Int(ceil(mediaBounds.width * clampedScale)))
        let pixelHeight = max(1, Int(ceil(mediaBounds.height * clampedScale)))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.saveGState()
        ctx.scaleBy(x: clampedScale, y: clampedScale)
        ctx.translateBy(x: -mediaBounds.origin.x, y: -mediaBounds.origin.y)
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()

        guard let cgImg = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImg)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - 2. OOXML Office Extractors (.docx, .xlsx, .pptx)

    static func listZipEntries(at path: String) -> [String] {
        let out = runBoundedCommand(
            executable: "/usr/bin/unzip",
            arguments: ["-Z1", path],
            maxOutputBytes: 2 * 1024 * 1024,
            timeoutSeconds: 8.0
        )
        guard let text = String(data: out.stdout, encoding: .utf8) ?? String(data: out.stdout, encoding: .isoLatin1) else {
            return []
        }
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func readZipEntry(at zipPath: String, entry: String, maxBytes: Int = maxSingleZipEntryBytes) -> Data? {
        let escaped = escapeUnzipEntryGlob(entry)
        let out = runBoundedCommand(
            executable: "/usr/bin/unzip",
            arguments: ["-p", zipPath, escaped],
            maxOutputBytes: maxBytes,
            timeoutSeconds: 8.0
        )
        guard !out.stdout.isEmpty else { return nil }
        return out.stdout
    }

    private func extractDOCX(url: URL, name: String, sizeStr: String) -> AttachmentExtractionPayload {
        let entries = Self.listZipEntries(at: url.path)
        guard !entries.isEmpty else {
            let warn = "Invalid or encrypted DOCX container"
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: .wordDoc,
                extractedText: "[DOCX WARNING: '\(name)' could not be opened as an OOXML zip container (it may be password-encrypted or corrupted).]",
                subtitleBadge: "DOCX • Locked/Err • \(sizeStr)",
                metricsSummary: "unreadable DOCX",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: warn,
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil,
                isPasswordProtected: true
            )
        }

        let headers = entries.filter { $0.hasPrefix("word/header") && $0.hasSuffix(".xml") }.sorted()
        let footers = entries.filter { $0.hasPrefix("word/footer") && $0.hasSuffix(".xml") }.sorted()
        var targetXMLPaths: [String] = []
        targetXMLPaths.append(contentsOf: headers)
        if entries.contains("word/document.xml") {
            targetXMLPaths.append("word/document.xml")
        }
        targetXMLPaths.append(contentsOf: footers)

        var blocks: [String] = []
        var totalTables = 0
        var totalParagraphs = 0

        for entry in targetXMLPaths {
            guard let xmlData = Self.readZipEntry(at: url.path, entry: entry) else { continue }
            let parser = DocxXMLParser()
            let parsed = parser.parse(data: xmlData)
            totalTables += parsed.tableCount
            totalParagraphs += parsed.paragraphCount
            let trimmed = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if entry.hasPrefix("word/header") {
                    blocks.append("[Header]\n\(trimmed)")
                } else if entry.hasPrefix("word/footer") {
                    blocks.append("[Footer]\n\(trimmed)")
                } else {
                    blocks.append(trimmed)
                }
            }
        }

        let joined = blocks.joined(separator: "\n\n")
        let headerBanner = "[Word Document: \(name) | Paragraphs: \(totalParagraphs) | Tables: \(totalTables) | Size: \(sizeStr)]"
        let fullText = joined.isEmpty ? "\(headerBanner)\n(Empty Word document)" : "\(headerBanner)\n\n\(joined)"
        return AttachmentExtractionPayload(
            attachmentType: .text,
            semanticCategory: .wordDoc,
            extractedText: fullText,
            subtitleBadge: "DOCX • \(totalParagraphs) para • \(sizeStr)",
            metricsSummary: "\(totalParagraphs) paragraphs, \(totalTables) tables",
            extractionStatus: "READ_OK",
            extractionWarning: nil,
            normalizedVisionData: nil,
            normalizedVisionMimeType: nil,
            nativeMediaMimeType: nil
        )
    }

    private func extractXLSX(url: URL, name: String, sizeStr: String) -> AttachmentExtractionPayload {
        let workbook = Self.parseXLSXWorkbook(at: url.path, maxRowsPerSheet: 5_000)
        guard !workbook.sheets.isEmpty else {
            let warn = workbook.warning ?? "Invalid or encrypted XLSX workbook"
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: .spreadsheet,
                extractedText: "[XLSX WARNING: '\(name)' could not be parsed (\(warn)).]",
                subtitleBadge: "XLSX • Error • \(sizeStr)",
                metricsSummary: "unreadable XLSX",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: warn,
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }

        var sections: [String] = []
        let sheetSummary = workbook.sheets.map { "\($0.name) (\($0.totalRows)r×\($0.maxCols)c)" }.joined(separator: ", ")
        sections.append("[Excel Workbook: \(name) | Sheets (\(workbook.sheets.count)): \(sheetSummary) | Size: \(sizeStr)]")

        var grandTotalRows = 0
        for sheet in workbook.sheets {
            grandTotalRows += sheet.totalRows
            sections.append(Self.renderSheetMarkdownSection(sheet: sheet))
        }

        return AttachmentExtractionPayload(
            attachmentType: .text,
            semanticCategory: .spreadsheet,
            extractedText: sections.joined(separator: "\n\n"),
            subtitleBadge: "XLSX • \(workbook.sheets.count) sh / \(grandTotalRows)r • \(sizeStr)",
            metricsSummary: "\(workbook.sheets.count) sheets, \(grandTotalRows) rows",
            extractionStatus: "READ_OK",
            extractionWarning: workbook.warning,
            normalizedVisionData: nil,
            normalizedVisionMimeType: nil,
            nativeMediaMimeType: nil
        )
    }

    private func extractPPTX(url: URL, name: String, sizeStr: String) -> AttachmentExtractionPayload {
        let slides = Self.parsePPTXSlides(at: url.path)
        guard !slides.isEmpty else {
            let warn = "Invalid, empty, or password-protected PPTX presentation"
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: .presentation,
                extractedText: "[PPTX WARNING: '\(name)' could not be parsed as an OOXML slide deck (\(warn)).]",
                subtitleBadge: "PPTX • Error • \(sizeStr)",
                metricsSummary: "unreadable PPTX",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: warn,
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }

        var sections: [String] = ["[PowerPoint Presentation: \(name) | Slides: \(slides.count) | Size: \(sizeStr)]"]
        for (idx, slide) in slides.enumerated() {
            var block = "=== Slide \(idx + 1) of \(slides.count) ===\n\(slide.body.isEmpty ? "(Visual-only slide / no text shapes)" : slide.body)"
            if !slide.notes.isEmpty {
                block += "\n[Speaker Notes]:\n\(slide.notes)"
            }
            sections.append(block)
        }

        return AttachmentExtractionPayload(
            attachmentType: .text,
            semanticCategory: .presentation,
            extractedText: sections.joined(separator: "\n\n"),
            subtitleBadge: "PPTX • \(slides.count) slides • \(sizeStr)",
            metricsSummary: "\(slides.count) slides",
            extractionStatus: "READ_OK",
            extractionWarning: nil,
            normalizedVisionData: nil,
            normalizedVisionMimeType: nil,
            nativeMediaMimeType: nil
        )
    }

    // MARK: - 3. Rich Text, HTML & EPUB Extractors

    private func extractRichDocument(url: URL, ext: String, name: String, sizeStr: String) -> AttachmentExtractionPayload {
        var extracted = ""

        // Primary out-of-process macOS native `/usr/bin/textutil` (supports .rtf, .rtfd, .doc, .odt cleanly without WebKit MainThread lockups)
        let textutilOut = Self.runBoundedCommand(
            executable: "/usr/bin/textutil",
            arguments: ["-convert", "txt", "-stdout", url.path],
            maxOutputBytes: 12 * 1024 * 1024,
            timeoutSeconds: 8.0
        )
        if textutilOut.exitCode == 0, let decoded = Self.decodeTextSmart(textutilOut.stdout)?.text, !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            extracted = decoded
        }

        // ODT XML fallback (`content.xml`)
        if extracted.isEmpty && ext == "odt", let contentXML = Self.readZipEntry(at: url.path, entry: "content.xml") {
            let parser = DocxXMLParser()
            extracted = parser.parse(data: contentXML).text
        }

        // NSAttributedString fallback for RTF
        if extracted.isEmpty && ext == "rtf", let data = try? Data(contentsOf: url, options: .mappedIfSafe),
           let attr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            extracted = attr.string
        }

        let trimmed = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let warn = "Unable to extract readable text from .\(ext) document"
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: .richDocument,
                extractedText: "[DOCUMENT WARNING: '\(name)' (.\(ext), \(sizeStr)) produced no readable text.]",
                subtitleBadge: "\(ext.uppercased()) • Empty • \(sizeStr)",
                metricsSummary: "0 chars",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: warn,
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }

        let lineCount = trimmed.components(separatedBy: "\n").count
        return AttachmentExtractionPayload(
            attachmentType: .text,
            semanticCategory: .richDocument,
            extractedText: "[Rich Document: \(name) | Format: \(ext.uppercased()) | Lines: \(lineCount) | Size: \(sizeStr)]\n\n\(trimmed)",
            subtitleBadge: "\(ext.uppercased()) • \(lineCount)L • \(sizeStr)",
            metricsSummary: "\(lineCount) lines",
            extractionStatus: "READ_OK",
            extractionWarning: nil,
            normalizedVisionData: nil,
            normalizedVisionMimeType: nil,
            nativeMediaMimeType: nil
        )
    }

    private func extractHTMLDocument(url: URL, name: String, sizeStr: String) -> AttachmentExtractionPayload {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let decoded = Self.decodeTextSmart(data) else {
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: .richDocument,
                extractedText: "[HTML WARNING: Unable to decode '\(name)'.]",
                subtitleBadge: "HTML • Error • \(sizeStr)",
                metricsSummary: "unreadable",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: "Unreadable HTML encoding",
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }

        let readable = Self.stripHTMLToStructuredText(decoded.text)
        let combined: String
        if decoded.text.count <= 24_000 {
            combined = "[HTML Document: \(name) | Encoding: \(decoded.encodingName) | Size: \(sizeStr)]\n\n--- Rendered Text View ---\n\(readable)\n\n--- Raw HTML Markup ---\n\(decoded.text)"
        } else {
            combined = "[HTML Document: \(name) | Encoding: \(decoded.encodingName) | Size: \(sizeStr)]\n\n\(readable)"
        }

        return AttachmentExtractionPayload(
            attachmentType: .text,
            semanticCategory: .richDocument,
            extractedText: combined,
            subtitleBadge: "HTML • \(sizeStr)",
            metricsSummary: "\(decoded.text.count) chars",
            extractionStatus: "READ_OK",
            extractionWarning: nil,
            normalizedVisionData: nil,
            normalizedVisionMimeType: nil,
            nativeMediaMimeType: nil
        )
    }

    private func extractEPUB(url: URL, name: String, sizeStr: String) -> AttachmentExtractionPayload {
        let entries = Self.listZipEntries(at: url.path)
        let chapterEntries = entries.filter {
            let lower = $0.lowercased()
            return (lower.hasSuffix(".xhtml") || lower.hasSuffix(".html") || lower.hasSuffix(".htm")) && !lower.contains("toc.") && !lower.contains("nav.")
        }.sorted()

        let targets = chapterEntries.isEmpty
            ? entries.filter { $0.lowercased().hasSuffix(".xhtml") || $0.lowercased().hasSuffix(".html") }.sorted()
            : chapterEntries

        guard !targets.isEmpty else {
            let warn = "DRM-protected or invalid EPUB archive"
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: .richDocument,
                extractedText: "[EPUB WARNING: '\(name)' contains no readable XHTML chapters (possibly DRM-protected).]",
                subtitleBadge: "EPUB • Locked • \(sizeStr)",
                metricsSummary: "unreadable EPUB",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: warn,
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }

        var chapters: [String] = ["[EPUB eBook: \(name) | Chapters: \(targets.count) | Size: \(sizeStr)]"]
        var totalChars = 0
        for (idx, entry) in targets.prefix(120).enumerated() {
            guard let data = Self.readZipEntry(at: url.path, entry: entry, maxBytes: 4 * 1024 * 1024),
                  let rawHTML = Self.decodeTextSmart(data)?.text else { continue }
            let clean = Self.stripHTMLToStructuredText(rawHTML)
            if !clean.isEmpty {
                chapters.append("=== Chapter \(idx + 1): \((entry as NSString).lastPathComponent) ===\n\(clean)")
                totalChars += clean.count
                if totalChars > 1_500_000 { break }
            }
        }

        return AttachmentExtractionPayload(
            attachmentType: .text,
            semanticCategory: .richDocument,
            extractedText: chapters.joined(separator: "\n\n"),
            subtitleBadge: "EPUB • \(targets.count) ch • \(sizeStr)",
            metricsSummary: "\(targets.count) chapters",
            extractionStatus: "READ_OK",
            extractionWarning: nil,
            normalizedVisionData: nil,
            normalizedVisionMimeType: nil,
            nativeMediaMimeType: nil
        )
    }

    // MARK: - 4. Data, Spreadsheets (CSV/TSV), Notebooks (.ipynb), SQLite & Parquet

    private func extractDelimitedTable(url: URL, ext: String, name: String, fileSize: Int64, sizeStr: String) -> AttachmentExtractionPayload {
        let maxReadBytes = 24 * 1024 * 1024
        let rawData: Data? = {
            if fileSize <= Int64(maxReadBytes) {
                return try? Data(contentsOf: url, options: .mappedIfSafe)
            }
            guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? fh.close() }
            return try? fh.read(upToCount: maxReadBytes)
        }()

        guard let data = rawData, let decoded = Self.decodeTextSmart(data) else {
            let warn = "Binary or unsupported character encoding in .\(ext)"
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: .spreadsheet,
                extractedText: "[CSV/TSV WARNING: '\(name)' could not be decoded as text (\(warn)).]",
                subtitleBadge: "\(ext.uppercased()) • Error • \(sizeStr)",
                metricsSummary: "unreadable",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: warn,
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }

        let normalizedNewlines = decoded.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let nonEmptyLines = normalizedNewlines.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let delimiter: Character = ext == "tsv" ? "\t" : Self.detectCSVDelimiter(sampleLine: nonEmptyLines.first ?? "")
        let parsedPreviewRows = nonEmptyLines.prefix(61).map { Self.parseDelimitedLine($0, delimiter: delimiter) }
        let headerCols = parsedPreviewRows.first ?? []
        let dataRowCount = max(0, nonEmptyLines.count - (headerCols.isEmpty ? 0 : 1))

        var mdPreview = ""
        if !parsedPreviewRows.isEmpty {
            mdPreview = Self.renderMarkdownTable(rows: parsedPreviewRows)
        }

        let truncatedDiskNotice = fileSize > Int64(maxReadBytes)
            ? "\n[Note: File is \(sizeStr); indexed first 24 MB (\(nonEmptyLines.count) rows).]"
            : ""

        let summaryHeader = """
        [\(ext.uppercased()) Dataset: \(name) | Encoding: \(decoded.encodingName) | Rows: \(dataRowCount) | Columns (\(headerCols.count)): \(headerCols.joined(separator: ", ")) | Size: \(sizeStr)]\(truncatedDiskNotice)

        --- Structured Table Preview (First \(min(60, dataRowCount)) Data Rows) ---
        \(mdPreview)

        --- Full Raw \(ext.uppercased()) Rows ---
        \(normalizedNewlines)
        """

        return AttachmentExtractionPayload(
            attachmentType: .text,
            semanticCategory: .spreadsheet,
            extractedText: summaryHeader,
            subtitleBadge: "\(ext.uppercased()) • \(dataRowCount)r×\(headerCols.count)c • \(sizeStr)",
            metricsSummary: "\(dataRowCount) rows, \(headerCols.count) cols (\(decoded.encodingName))",
            extractionStatus: "READ_OK",
            extractionWarning: fileSize > Int64(maxReadBytes) ? "Indexed first 24 MB of \(sizeStr)" : nil,
            normalizedVisionData: nil,
            normalizedVisionMimeType: nil,
            nativeMediaMimeType: nil
        )
    }

    private func extractJupyterNotebook(url: URL, name: String, sizeStr: String) -> AttachmentExtractionPayload {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cells = root["cells"] as? [[String: Any]] else {
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: .notebook,
                extractedText: "[IPYNB WARNING: '\(name)' is not a valid JSON Jupyter Notebook.]",
                subtitleBadge: "Notebook • Error • \(sizeStr)",
                metricsSummary: "invalid JSON",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: "Invalid .ipynb JSON",
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }

        func joinNotebookLines(_ val: Any?) -> String {
            if let str = val as? String { return str }
            if let arr = val as? [String] { return arr.joined() }
            return ""
        }

        var sections: [String] = ["[Jupyter Notebook: \(name) | Cells: \(cells.count) | Size: \(sizeStr)]"]
        for (idx, cell) in cells.enumerated() {
            let cellType = (cell["cell_type"] as? String) ?? "code"
            let execCount = cell["execution_count"].flatMap { "\($0)" }.flatMap { $0 == "<null>" ? nil : $0 }
            let execLabel = execCount != nil ? " (In[\(execCount!)])" : ""
            let source = joinNotebookLines(cell["source"]).trimmingCharacters(in: .newlines)

            var block = "### Cell \(idx + 1) [\(cellType)]\(execLabel)\n\(source)"
            if let outputs = cell["outputs"] as? [[String: Any]], !outputs.isEmpty {
                var outParts: [String] = []
                for out in outputs {
                    let outType = (out["output_type"] as? String) ?? ""
                    if outType == "stream" {
                        let txt = joinNotebookLines(out["text"]).trimmingCharacters(in: .newlines)
                        if !txt.isEmpty { outParts.append(txt) }
                    } else if outType == "execute_result" || outType == "display_data" {
                        if let dataDict = out["data"] as? [String: Any] {
                            let plain = joinNotebookLines(dataDict["text/plain"]).trimmingCharacters(in: .newlines)
                            if !plain.isEmpty { outParts.append(plain) }
                            for mime in ["image/png", "image/jpeg", "image/svg+xml"] where dataDict[mime] != nil {
                                outParts.append("[Image output: \(mime)]")
                            }
                        }
                    } else if outType == "error" {
                        let ename = (out["ename"] as? String) ?? "Error"
                        let evalue = (out["evalue"] as? String) ?? ""
                        outParts.append("[Exception \(ename): \(evalue)]")
                    }
                }
                if !outParts.isEmpty {
                    let renderedOut = outParts.joined(separator: "\n")
                    let cappedOut = renderedOut.count > 4_000 ? String(renderedOut.prefix(4_000)) + "\n...(cell output truncated)" : renderedOut
                    block += "\n--- Output ---\n\(cappedOut)"
                }
            }
            sections.append(block)
        }

        return AttachmentExtractionPayload(
            attachmentType: .text,
            semanticCategory: .notebook,
            extractedText: sections.joined(separator: "\n\n"),
            subtitleBadge: "IPYNB • \(cells.count) cells • \(sizeStr)",
            metricsSummary: "\(cells.count) cells",
            extractionStatus: "READ_OK",
            extractionWarning: nil,
            normalizedVisionData: nil,
            normalizedVisionMimeType: nil,
            nativeMediaMimeType: nil
        )
    }

    private func extractSQLiteDatabase(url: URL, name: String, sizeStr: String) -> AttachmentExtractionPayload {
        let result = Self.inspectSQLite(at: url.path, targetTable: nil, rowOffset: 0, rowLimit: 25)
        guard result.success else {
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: .database,
                extractedText: "[SQLITE WARNING: '\(name)' could not be opened as SQLite3 (\(result.warning ?? "unreadable")).]",
                subtitleBadge: "SQLite • Error • \(sizeStr)",
                metricsSummary: "unreadable SQLite",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: result.warning,
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }

        let banner = "[SQLite Database: \(name) | Tables/Views: \(result.tableCount) | Size: \(sizeStr)]"
        return AttachmentExtractionPayload(
            attachmentType: .text,
            semanticCategory: .database,
            extractedText: "\(banner)\n\n\(result.formattedText)",
            subtitleBadge: "SQLite • \(result.tableCount) tbl • \(sizeStr)",
            metricsSummary: "\(result.tableCount) tables",
            extractionStatus: "READ_OK",
            extractionWarning: nil,
            normalizedVisionData: nil,
            normalizedVisionMimeType: nil,
            nativeMediaMimeType: nil
        )
    }

    private func extractParquet(url: URL, name: String, stagedPath: String, fileSize: Int64, sizeStr: String) -> AttachmentExtractionPayload {
        guard let fh = try? FileHandle(forReadingFrom: url) else {
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: .dataFile,
                extractedText: "[PARQUET WARNING: Cannot open '\(name)'.]",
                subtitleBadge: "Parquet • Error",
                metricsSummary: "unreadable",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: "Cannot open file",
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }
        defer { try? fh.close() }

        let head = (try? fh.read(upToCount: 4)) ?? Data()
        let isParquetMagic = head == Data("PAR1".utf8)
        if !isParquetMagic {
            let warn = "Missing PAR1 magic header — file is not valid Apache Parquet"
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: .dataFile,
                extractedText: "[PARQUET WARNING: '\(name)' (\(sizeStr)) does not start with 'PAR1' magic bytes.]",
                subtitleBadge: "Parquet • Invalid • \(sizeStr)",
                metricsSummary: "invalid magic",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: warn,
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }

        // Attempt fast 3s Python duckdb / pyarrow / pandas schema + sample inspection if installed locally
        let pyScript = """
        import sys
        p = sys.argv[1]
        tried = False
        try:
            import duckdb
            con = duckdb.connect()
            cnt = con.execute("SELECT COUNT(*) FROM read_parquet(?)", [p]).fetchone()[0]
            desc = con.execute("DESCRIBE SELECT * FROM read_parquet(?)", [p]).fetchall()
            print(f"Engine: DuckDB | Total Rows: {cnt}")
            print("Schema:", ", ".join(f"{r[0]}:{r[1]}" for r in desc))
            rows = con.execute("SELECT * FROM read_parquet(?) LIMIT 25", [p]).fetchall()
            cols = [r[0] for r in desc]
            print("| " + " | ".join(cols) + " |")
            print("| " + " | ".join("---" for _ in cols) + " |")
            for row in rows:
                print("| " + " | ".join(str(v).replace("|", "\\\\|")[:120] for v in row) + " |")
            sys.exit(0)
        except Exception:
            pass
        try:
            import pyarrow.parquet as pq
            pf = pq.ParquetFile(p)
            print(f"Engine: PyArrow | Total Rows: {pf.metadata.num_rows} | RowGroups: {pf.num_row_groups}")
            print(pf.schema)
            tbl = pf.read_row_group(0).slice(0, 25).to_pydict()
            cols = list(tbl.keys())
            if cols:
                print("| " + " | ".join(cols) + " |")
                print("| " + " | ".join("---" for _ in cols) + " |")
                n = len(tbl[cols[0]])
                for i in range(n):
                    print("| " + " | ".join(str(tbl[c][i]).replace("|", "\\\\|")[:120] for c in cols) + " |")
            sys.exit(0)
        except Exception:
            sys.exit(2)
        """

        for pyBin in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"] where FileManager.default.isExecutableFile(atPath: pyBin) {
            let out = Self.runBoundedCommand(
                executable: pyBin,
                arguments: ["-c", pyScript, url.path],
                maxOutputBytes: 2 * 1024 * 1024,
                timeoutSeconds: 3.0
            )
            if out.exitCode == 0, let txt = String(data: out.stdout, encoding: .utf8), !txt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return AttachmentExtractionPayload(
                    attachmentType: .text,
                    semanticCategory: .dataFile,
                    extractedText: "[Apache Parquet Dataset: \(name) | Size: \(sizeStr) | Staged: \(stagedPath)]\n\n\(txt)",
                    subtitleBadge: "Parquet • \(sizeStr)",
                    metricsSummary: "Parquet table decoded",
                    extractionStatus: "READ_OK",
                    extractionWarning: nil,
                    normalizedVisionData: nil,
                    normalizedVisionMimeType: nil,
                    nativeMediaMimeType: nil
                )
            }
        }

        // Native Thrift footer ASCII schema identifier extraction when Python pyarrow/duckdb is absent
        var footerTokens: [String] = []
        if fileSize >= 12 {
            try? fh.seek(toOffset: UInt64(fileSize - 8))
            if let tail8 = try? fh.read(upToCount: 8), tail8.count == 8, Data(tail8[4..<8]) == Data("PAR1".utf8) {
                let footerLen = UInt32(tail8[0]) | (UInt32(tail8[1]) << 8) | (UInt32(tail8[2]) << 16) | (UInt32(tail8[3]) << 24)
                let boundedLen = min(Int64(footerLen), min(fileSize - 8, 262_144))
                if boundedLen > 0 {
                    try? fh.seek(toOffset: UInt64(fileSize - 8 - boundedLen))
                    if let footerData = try? fh.read(upToCount: Int(boundedLen)) {
                        footerTokens = Self.extractPrintableIdentifiers(from: footerData, minLen: 3, maxCount: 60)
                    }
                }
            }
        }

        let tokenList = footerTokens.isEmpty ? "(No ASCII column identifiers found in footer)" : footerTokens.joined(separator: ", ")
        let report = """
        [Apache Parquet Dataset: \(name) | Verified PAR1 Magic | Size: \(sizeStr) | Staged Path: \(stagedPath)]
        Footer Schema / Column Identifiers: \(tokenList)
        [Note: Local Python duckdb/pyarrow was not available for inline row decoding. Only Parquet footer metadata is shown above — do NOT guess row values without querying '\(stagedPath)'.]
        """

        return AttachmentExtractionPayload(
            attachmentType: .text,
            semanticCategory: .dataFile,
            extractedText: report,
            subtitleBadge: "Parquet • Meta • \(sizeStr)",
            metricsSummary: "PAR1 footer (\(footerTokens.count) schema tokens)",
            extractionStatus: "PARTIAL_PAGED",
            extractionWarning: "Parquet footer metadata extracted (install duckdb/pyarrow for full row table)",
            normalizedVisionData: nil,
            normalizedVisionMimeType: nil,
            nativeMediaMimeType: nil
        )
    }

    // MARK: - 5. Image Transcoder + Lazy / On-Demand Apple Vision ANE OCR

    private func extractImage(
        url: URL,
        ext: String,
        name: String,
        stagedPath: String,
        sizeStr: String,
        eagerOCR: Bool = false,
        preNormalizedVision: (data: Data, mimeType: String)? = nil
    ) async -> AttachmentExtractionPayload {
        guard let rawData = try? Data(contentsOf: url, options: .mappedIfSafe), !rawData.isEmpty else {
            return AttachmentExtractionPayload(
                attachmentType: .image(format: "png"),
                semanticCategory: .image,
                extractedText: "[IMAGE WARNING: Unable to read image bytes for '\(name)'.]",
                subtitleBadge: "Image • Error",
                metricsSummary: "unreadable",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: "Cannot read image bytes",
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }

        var svgSourceSnippet = ""
        if ext == "svg", let svgText = Self.decodeTextSmart(rawData)?.text {
            let capped = svgText.count > 16_000 ? String(svgText.prefix(16_000)) + "\n...(SVG XML truncated)" : svgText
            svgSourceSnippet = "\n\n--- SVG Vector XML Source ---\n\(capped)"
        }

        let normalized = preNormalizedVision ?? Self.normalizeImageForUniversalVision(data: rawData, ext: ext)
        let resolvedFormat = (normalized?.mimeType == "image/jpeg") ? "jpeg" : ((normalized?.mimeType == "image/webp") ? "webp" : ((normalized?.mimeType == "image/gif") ? "gif" : "png"))

        if !eagerOCR {
            let dims = Self.readImageHeaderDimensions(from: rawData)
                ?? (normalized.flatMap { Self.readImageHeaderDimensions(from: $0.data) })
            let w = dims?.width ?? 0
            let h = dims?.height ?? 0
            let dimBadge = (w > 0 && h > 0) ? "\(w)×\(h)" : ext.uppercased()
            let fastSummary = """
            [Visual Image Attached: '\(name)' | Dimensions: \(dimBadge) px | Size: \(sizeStr)]
            Delivered directly as native multimodal image input. If exact character-by-character OCR text extraction is needed, call `attachment_read(path: "\(stagedPath)", ocr: true)`.
            """ + svgSourceSnippet

            return AttachmentExtractionPayload(
                attachmentType: .image(format: resolvedFormat),
                semanticCategory: .image,
                extractedText: fastSummary,
                subtitleBadge: "\(ext.uppercased()) • \(dimBadge) • \(sizeStr)",
                metricsSummary: "\(dimBadge) px",
                extractionStatus: "FAST_IMAGE_READY",
                extractionWarning: normalized == nil && w == 0 ? "Image bitmap could not be decoded" : nil,
                normalizedVisionData: normalized?.data,
                normalizedVisionMimeType: normalized?.mimeType,
                nativeMediaMimeType: normalized?.mimeType
            )
        }

        let visionInput = normalized?.data ?? rawData
        let vision = await AppleVisionEngine.shared.analyzeImage(data: visionInput, filename: name)

        let w = Int(vision.dimensions.width)
        let h = Int(vision.dimensions.height)
        let dimBadge = (w > 0 && h > 0) ? "\(w)×\(h)" : ext.uppercased()
        let fullText = vision.formattedSummary + svgSourceSnippet

        return AttachmentExtractionPayload(
            attachmentType: .image(format: resolvedFormat),
            semanticCategory: .image,
            extractedText: fullText,
            subtitleBadge: "\(ext.uppercased()) • \(dimBadge) • \(sizeStr)",
            metricsSummary: "\(dimBadge) px\(vision.extractedText.isEmpty ? "" : ", ANE OCR")",
            extractionStatus: vision.extractedText.isEmpty ? "READ_OK" : "OCR_EXTRACTED",
            extractionWarning: normalized == nil && w == 0 ? "Image bitmap could not be decoded" : nil,
            normalizedVisionData: normalized?.data,
            normalizedVisionMimeType: normalized?.mimeType,
            nativeMediaMimeType: normalized?.mimeType
        )
    }

    static func normalizeImageForUniversalVision(data: Data, ext: String) -> (data: Data, mimeType: String)? {
        let lowerExt = ext.lowercased()
        let passthroughExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]

        // Zero-decode fast path: inspect 24-byte ImageIO header first without decoding pixels!
        let srcOpts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        let imageSource = CGImageSourceCreateWithData(data as CFData, srcOpts as CFDictionary)
        if let src = imageSource,
           passthroughExts.contains(lowerExt),
           data.count <= 4_500_000,
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, srcOpts as CFDictionary) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int,
           let h = props[kCGImagePropertyPixelHeight] as? Int,
           w > 0, h > 0, max(w, h) <= 2048 {
            let mime: String
            switch lowerExt {
            case "jpg", "jpeg": mime = "image/jpeg"
            case "gif": mime = "image/gif"
            case "webp": mime = "image/webp"
            default: mime = "image/png"
            }
            return (data, mime)
        }

        // Hardware-accelerated SIMD ImageIO thumbnail/transcode path (~6ms on Retina screenshots)
        if let src = imageSource, lowerExt != "svg" && lowerExt != "icns" {
            let thumbOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: false
            ]
            if let scaledCG = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) {
                return encodeCGImageFast(scaledCG, maxPixelEdge: 2048)
            }
        }

        // Fallback for SVG / ICNS / non-ImageIO vector formats
        var cgImage: CGImage?
        if let src = imageSource,
           let img = CGImageSourceCreateImageAtIndex(src, 0, srcOpts as CFDictionary) {
            cgImage = img
        } else if let nsImg = NSImage(data: data) {
            var rect = CGRect(origin: .zero, size: nsImg.size)
            if rect.width <= 0 || rect.height <= 0 {
                rect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
            }
            cgImage = nsImg.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }

        guard let sourceCG = cgImage else { return nil }
        let width = sourceCG.width
        let height = sourceCG.height
        let maxEdge = max(width, height)
        let scale: CGFloat = maxEdge > 2048 ? (2048.0 / CGFloat(maxEdge)) : 1.0
        let targetW = max(1, Int(round(CGFloat(width) * scale)))
        let targetH = max(1, Int(round(CGFloat(height) * scale)))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: targetW, height: targetH))
        ctx.interpolationQuality = .high
        ctx.draw(sourceCG, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))

        guard let outCG = ctx.makeImage() else { return nil }
        return encodeCGImageFast(outCG, maxPixelEdge: 2048)
    }

    // MARK: - 6. Audio & Video Inspector (+ Video Keyframe ANE Vision OCR)

    private func extractAudioOrVideo(url: URL, ext: String, isVideo: Bool, name: String, sizeStr: String) async -> AttachmentExtractionPayload {
        let asset = AVURLAsset(url: url)
        let durationTime = (try? await asset.load(.duration)) ?? .zero
        let seconds = CMTimeGetSeconds(durationTime)
        let validDuration = seconds.isFinite && seconds > 0 ? seconds : 0
        let durationStr = Self.formatMediaDuration(validDuration)

        var trackDescriptions: [String] = []
        var videoDimensionsStr = ""
        if let tracks = try? await asset.load(.tracks) {
            for track in tracks {
                let mediaType = track.mediaType.rawValue
                if track.mediaType == .video {
                    let natSize = (try? await track.load(.naturalSize)) ?? .zero
                    let fps = (try? await track.load(.nominalFrameRate)) ?? 0
                    videoDimensionsStr = "\(Int(abs(natSize.width)))×\(Int(abs(natSize.height)))"
                    trackDescriptions.append("Video Track (\(videoDimensionsStr) @ \(String(format: "%.1f", fps)) fps)")
                } else if track.mediaType == .audio {
                    trackDescriptions.append("Audio Track (\(mediaType))")
                } else {
                    trackDescriptions.append("Track (\(mediaType))")
                }
            }
        }

        var metaLines: [String] = []
        if let commonMeta = try? await asset.load(.commonMetadata) {
            for item in commonMeta.prefix(12) {
                let key = item.commonKey?.rawValue ?? "meta"
                if let strVal = try? await item.load(.stringValue), !strVal.isEmpty {
                    metaLines.append("\(key): \(strVal)")
                }
            }
        }

        var middleKeyframeData: Data?
        var keyframeTranscripts: [String] = []

        if isVideo && validDuration > 0.05 {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280, height: 1280)
            let fractions: [Double] = validDuration < 1.5 ? [0.5] : [0.10, 0.50, 0.85]

            for (idx, frac) in fractions.enumerated() {
                let t = CMTime(seconds: validDuration * frac, preferredTimescale: 600)
                if let cgImg = try? generator.copyCGImage(at: t, actualTime: nil) {
                    let rep = NSBitmapImageRep(cgImage: cgImg)
                    if let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.84]) {
                        if idx == fractions.count / 2 {
                            middleKeyframeData = jpg
                        }
                        let tsLabel = Self.formatMediaDuration(validDuration * frac)
                        let vision = await AppleVisionEngine.shared.analyzeImage(data: jpg, filename: "\(name)@\(tsLabel)")
                        let ocr = vision.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let scene = vision.detectedElements.joined(separator: " | ")
                        keyframeTranscripts.append("""
                        [Video Keyframe @ \(Int(frac * 100))% (\(tsLabel))]:
                        Scene: \(scene.isEmpty ? "Video frame \(cgImg.width)×\(cgImg.height)" : scene)
                        OCR Text: \(ocr.isEmpty ? "(No on-screen text detected)" : ocr)
                        """)
                    }
                }
            }
        }

        let nativeMime: String? = {
            switch ext {
            case "mp3": return "audio/mp3"
            case "wav": return "audio/wav"
            case "m4a": return "audio/mp4"
            case "aac": return "audio/aac"
            case "flac": return "audio/flac"
            case "ogg": return "audio/ogg"
            case "mp4", "m4v": return "video/mp4"
            case "mov": return "video/quicktime"
            case "webm": return "video/webm"
            default: return nil
            }
        }()

        var report = """
        [\(isVideo ? "Video" : "Audio") Media File: \(name) | Format: \(ext.uppercased()) | Duration: \(durationStr) | Size: \(sizeStr)]
        Tracks: \(trackDescriptions.isEmpty ? "Standard \(ext.uppercased()) stream" : trackDescriptions.joined(separator: ", "))
        """
        if !metaLines.isEmpty {
            report += "\nMetadata: " + metaLines.joined(separator: " | ")
        }
        if !keyframeTranscripts.isEmpty {
            report += "\n\n--- Sampled Video Keyframes (Apple Vision ANE OCR) ---\n" + keyframeTranscripts.joined(separator: "\n\n")
        } else if !isVideo {
            report += "\n[Note: Audio stream metadata extracted natively. On Gemini multimodal models, audio inlineData is also attached when <= 14 MB.]"
        }

        let badge = isVideo
            ? "\(ext.uppercased()) • \(durationStr)\(videoDimensionsStr.isEmpty ? "" : " • \(videoDimensionsStr)") • \(sizeStr)"
            : "\(ext.uppercased()) • \(durationStr) • \(sizeStr)"

        return AttachmentExtractionPayload(
            attachmentType: .text,
            semanticCategory: isVideo ? .video : .audio,
            extractedText: report,
            subtitleBadge: badge,
            metricsSummary: "duration \(durationStr)",
            extractionStatus: keyframeTranscripts.isEmpty ? "READ_OK" : "OCR_EXTRACTED",
            extractionWarning: nil,
            normalizedVisionData: middleKeyframeData,
            normalizedVisionMimeType: middleKeyframeData != nil ? "image/jpeg" : nil,
            nativeMediaMimeType: nativeMime
        )
    }

    private static func formatMediaDuration(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds > 0 else { return "0:00" }
        let total = Int(round(seconds))
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        return hrs > 0 ? String(format: "%d:%02d:%02d", hrs, mins, secs) : String(format: "%d:%02d", mins, secs)
    }

    // MARK: - 7. Directories, Archives (.zip / .tar / .gz) & Generic Text/Binary

    private static let ignoredDirectoryNames: Set<String> = [
        ".git", "node_modules", ".build", "DerivedData", "target", "__pycache__", ".venv", "venv", ".DS_Store", ".idea", "Pods"
    ]

    private func computeDirectoryTotalBytes(at dirURL: URL, maxEntries: Int) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else { return 0 }

        var count = 0
        var total: Int64 = 0
        while let item = enumerator.nextObject() as? URL {
            let name = item.lastPathComponent
            if Self.ignoredDirectoryNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            if let vals = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]) {
                if vals.isSymbolicLink == true { continue }
                if vals.isDirectory != true {
                    total += Int64(vals.fileSize ?? 0)
                }
            }
            count += 1
            if count >= maxEntries { break }
        }
        return total
    }

    private func extractDirectory(sourceDir: URL, stagedDir: URL, folderName: String, totalSize: Int64) -> AttachmentExtractionPayload {
        let fm = FileManager.default
        let sizeStr = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        try? fm.createDirectory(at: stagedDir, withIntermediateDirectories: true)

        var treeLines: [String] = []
        var sampleSnippets: [String] = []
        var copiedBytes = 0
        var sampleTextChars = 0
        var fileCount = 0
        let maxEntries = 2_000
        let maxStagedFolderCopyBytes = 96 * 1024 * 1024
        let maxInlineSampleChars = 60_000

        if let enumerator = fm.enumerator(
            at: sourceDir,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey],
            options: []
        ) {
            while let item = enumerator.nextObject() as? URL {
                let name = item.lastPathComponent
                if Self.ignoredDirectoryNames.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }
                guard let vals = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]),
                      vals.isSymbolicLink != true else { continue }

                let relPath = item.path.replacingOccurrences(of: sourceDir.path + "/", with: "")
                if vals.isDirectory == true {
                    treeLines.append("[DIR]  \(relPath)/")
                } else {
                    fileCount += 1
                    let fSize = Int64(vals.fileSize ?? 0)
                    let fSizeStr = ByteCountFormatter.string(fromByteCount: fSize, countStyle: .file)
                    let destFile = stagedDir.appendingPathComponent(relPath)

                    var stagedChildPath = item.path
                    if fSize <= 8 * 1024 * 1024 && (copiedBytes + Int(fSize)) <= maxStagedFolderCopyBytes &&
                       WorkspacePathPolicy.contains(destFile.path, in: stagedDir.path) {
                        try? fm.createDirectory(at: destFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                        if (try? fm.copyItem(at: item, to: destFile)) != nil {
                            copiedBytes += Int(fSize)
                            stagedChildPath = destFile.path
                        }
                    }

                    treeLines.append("[FILE] \(relPath) (\(fSizeStr)) -> staged: \(stagedChildPath)")

                    if fSize > 0 && fSize <= 256_000 && sampleTextChars < maxInlineSampleChars,
                       let raw = try? Data(contentsOf: item, options: .mappedIfSafe),
                       let decoded = Self.decodeTextSmart(raw) {
                        let snippet = decoded.text.count > 4_000 ? String(decoded.text.prefix(4_000)) + "\n...(truncated — read full file via attachment_read path=\"\(stagedChildPath)\")" : decoded.text
                        sampleSnippets.append("=== Folder File: \(relPath) (path: \(stagedChildPath)) ===\n\(snippet)")
                        sampleTextChars += snippet.count
                    }
                }
                if treeLines.count >= maxEntries {
                    treeLines.append("... (Folder listing capped at \(maxEntries) entries)")
                    break
                }
            }
        }

        var fullReport = """
        [Attached Folder: \(folderName) | Files: \(fileCount) | Total Size: \(sizeStr) | Vault Dir: \(stagedDir.path)]
        --- Directory Tree & Staged File Paths ---
        \(treeLines.joined(separator: "\n"))
        """
        if !sampleSnippets.isEmpty {
            fullReport += "\n\n--- Extracted Folder File Contents ---\n" + sampleSnippets.joined(separator: "\n\n")
        }

        return AttachmentExtractionPayload(
            attachmentType: .text,
            semanticCategory: .folder,
            extractedText: fullReport,
            subtitleBadge: "Folder • \(fileCount) files • \(sizeStr)",
            metricsSummary: "\(fileCount) files",
            extractionStatus: "READ_OK",
            extractionWarning: nil,
            normalizedVisionData: nil,
            normalizedVisionMimeType: nil,
            nativeMediaMimeType: nil
        )
    }

    private func extractZipArchive(url: URL, name: String, stagedVaultURL: URL, sizeStr: String) -> AttachmentExtractionPayload {
        let allEntries = Self.listZipEntries(at: url.path)
        guard !allEntries.isEmpty else {
            let warn = "Encrypted or corrupted ZIP archive"
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: .archive,
                extractedText: "[ZIP WARNING: '\(name)' could not be listed via unzip (\(warn)).]",
                subtitleBadge: "ZIP • Error • \(sizeStr)",
                metricsSummary: "unreadable ZIP",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: warn,
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }

        let unpackedRoot = URL(fileURLWithPath: stagedVaultURL.path + "_unpacked", isDirectory: true)
        try? FileManager.default.createDirectory(at: unpackedRoot, withIntermediateDirectories: true)

        let cappedEntries = Array(allEntries.prefix(2_000))
        var manifestLines: [String] = []
        var sampleBlocks: [String] = []
        var totalUnpackedBytes = 0
        var unpackedFilesCount = 0

        for entry in cappedEntries {
            if entry.hasSuffix("/") {
                manifestLines.append("[DIR]  \(entry)")
                continue
            }
            if entry.contains("..") || entry.hasPrefix("/") || entry.contains("__MACOSX/") || entry.hasSuffix(".DS_Store") {
                continue
            }
            if unpackedFilesCount < 80 && totalUnpackedBytes < Self.maxUnpackedArchiveBytes {
                let destURL = unpackedRoot.appendingPathComponent(entry)
                if WorkspacePathPolicy.contains(destURL.path, in: unpackedRoot.path),
                   let data = Self.readZipEntry(at: url.path, entry: entry, maxBytes: 2 * 1024 * 1024) {
                    try? FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: destURL, options: .atomic)
                    totalUnpackedBytes += data.count
                    unpackedFilesCount += 1
                    manifestLines.append("[FILE] \(entry) (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))) -> unpacked: \(destURL.path)")

                    if sampleBlocks.count < 25, let decoded = Self.decodeTextSmart(data) {
                        let preview = decoded.text.count > 3_000 ? String(decoded.text.prefix(3_000)) + "\n...(truncated — use attachment_read on \(destURL.path))" : decoded.text
                        sampleBlocks.append("=== Archive Entry: \(entry) (path: \(destURL.path)) ===\n\(preview)")
                    }
                    continue
                }
            }
            manifestLines.append("[FILE] \(entry)")
        }

        var report = """
        [ZIP Archive: \(name) | Entries: \(allEntries.count) | Unpacked to Vault: \(unpackedRoot.path) | Size: \(sizeStr)]
        --- Archive Manifest ---
        \(manifestLines.joined(separator: "\n"))
        """
        if !sampleBlocks.isEmpty {
            report += "\n\n--- Sample Unpacked Text Entries ---\n" + sampleBlocks.joined(separator: "\n\n")
        }

        return AttachmentExtractionPayload(
            attachmentType: .text,
            semanticCategory: .archive,
            extractedText: report,
            subtitleBadge: "ZIP • \(allEntries.count) items • \(sizeStr)",
            metricsSummary: "\(allEntries.count) entries",
            extractionStatus: "READ_OK",
            extractionWarning: allEntries.count > 2_000 ? "Manifest capped at first 2,000 entries" : nil,
            normalizedVisionData: nil,
            normalizedVisionMimeType: nil,
            nativeMediaMimeType: nil
        )
    }

    private func extractTarArchive(url: URL, name: String, stagedVaultURL: URL, sizeStr: String) -> AttachmentExtractionPayload {
        let listOut = Self.runBoundedCommand(
            executable: "/usr/bin/tar",
            arguments: ["-tf", url.path],
            maxOutputBytes: 2 * 1024 * 1024,
            timeoutSeconds: 8.0
        )
        let entries = (String(data: listOut.stdout, encoding: .utf8) ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !entries.isEmpty else {
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: .archive,
                extractedText: "[TAR WARNING: '\(name)' could not be listed via /usr/bin/tar.]",
                subtitleBadge: "TAR • Error • \(sizeStr)",
                metricsSummary: "unreadable TAR",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: "Corrupted or unsupported tar archive",
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }

        let unpackedRoot = URL(fileURLWithPath: stagedVaultURL.path + "_unpacked", isDirectory: true)
        try? FileManager.default.createDirectory(at: unpackedRoot, withIntermediateDirectories: true)

        var manifestLines: [String] = []
        var sampleBlocks: [String] = []
        var totalUnpacked = 0
        var extractedFiles = 0

        for entry in entries.prefix(2_000) {
            if entry.hasSuffix("/") {
                manifestLines.append("[DIR]  \(entry)")
                continue
            }
            let cleanRel = entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
            if cleanRel.contains("..") || cleanRel.hasPrefix("/") || cleanRel.contains("node_modules/") || cleanRel.hasSuffix(".DS_Store") {
                continue
            }
            if extractedFiles < 50 && totalUnpacked < Self.maxUnpackedArchiveBytes {
                let destURL = unpackedRoot.appendingPathComponent(cleanRel)
                if WorkspacePathPolicy.contains(destURL.path, in: unpackedRoot.path) {
                    let extOut = Self.runBoundedCommand(
                        executable: "/usr/bin/tar",
                        arguments: ["-xOf", url.path, entry],
                        maxOutputBytes: 2 * 1024 * 1024,
                        timeoutSeconds: 5.0
                    )
                    if extOut.exitCode == 0 && !extOut.stdout.isEmpty {
                        try? FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? extOut.stdout.write(to: destURL, options: .atomic)
                        totalUnpacked += extOut.stdout.count
                        extractedFiles += 1
                        manifestLines.append("[FILE] \(cleanRel) -> unpacked: \(destURL.path)")
                        if sampleBlocks.count < 20, let decoded = Self.decodeTextSmart(extOut.stdout) {
                            let preview = decoded.text.count > 3_000 ? String(decoded.text.prefix(3_000)) + "\n...(truncated)" : decoded.text
                            sampleBlocks.append("=== Tar Entry: \(cleanRel) (path: \(destURL.path)) ===\n\(preview)")
                        }
                        continue
                    }
                }
            }
            manifestLines.append("[FILE] \(cleanRel)")
        }

        var report = """
        [TAR Archive: \(name) | Entries: \(entries.count) | Unpacked Vault: \(unpackedRoot.path) | Size: \(sizeStr)]
        --- Archive Manifest ---
        \(manifestLines.joined(separator: "\n"))
        """
        if !sampleBlocks.isEmpty {
            report += "\n\n--- Sample Unpacked Entries ---\n" + sampleBlocks.joined(separator: "\n\n")
        }

        return AttachmentExtractionPayload(
            attachmentType: .text,
            semanticCategory: .archive,
            extractedText: report,
            subtitleBadge: "TAR • \(entries.count) items • \(sizeStr)",
            metricsSummary: "\(entries.count) entries",
            extractionStatus: "READ_OK",
            extractionWarning: nil,
            normalizedVisionData: nil,
            normalizedVisionMimeType: nil,
            nativeMediaMimeType: nil
        )
    }

    private func extractCompressedSingleFile(url: URL, ext: String, name: String, stagedVaultURL: URL, sizeStr: String) -> AttachmentExtractionPayload {
        let tool: String = ext == "bz2" ? "/usr/bin/bzip2" : (ext == "xz" ? "/usr/bin/xz" : "/usr/bin/gzip")
        let out = Self.runBoundedCommand(
            executable: tool,
            arguments: ["-dc", url.path],
            maxOutputBytes: 16 * 1024 * 1024,
            timeoutSeconds: 8.0
        )
        if !out.stdout.isEmpty, let decoded = Self.decodeTextSmart(out.stdout) {
            let unpackedURL = URL(fileURLWithPath: stagedVaultURL.path + ".decompressed.txt")
            try? decoded.text.write(to: unpackedURL, atomically: true, encoding: .utf8)
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: .archive,
                extractedText: "[Compressed File: \(name) | Encoding: \(decoded.encodingName) | Decompressed: \(unpackedURL.path)]\n\n\(decoded.text)",
                subtitleBadge: "\(ext.uppercased()) • Text • \(sizeStr)",
                metricsSummary: "decompressed \(decoded.text.count) chars",
                extractionStatus: "READ_OK",
                extractionWarning: out.truncated ? "Decompressed stream capped at 16 MB" : nil,
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }
        return extractGenericTextOrBinary(url: url, ext: ext, name: name, fileSize: Int64(out.stdout.count), sizeStr: sizeStr)
    }

    private func extractGenericTextOrBinary(url: URL, ext: String, name: String, fileSize: Int64, sizeStr: String) -> AttachmentExtractionPayload {
        let maxTextBytes = 20 * 1024 * 1024
        let dataSample: Data? = {
            if fileSize <= Int64(maxTextBytes) {
                return try? Data(contentsOf: url, options: .mappedIfSafe)
            }
            guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? fh.close() }
            return try? fh.read(upToCount: maxTextBytes)
        }()

        guard let data = dataSample else {
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: .binary,
                extractedText: "[BINARY / UNREADABLE CONTENT NOTICE: Unable to read bytes from '\(name)'. Do NOT guess internal contents.]",
                subtitleBadge: "Binary • \(sizeStr)",
                metricsSummary: "unreadable",
                extractionStatus: "LOCKED_OR_BINARY",
                extractionWarning: "Unreadable file",
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }

        // Native MicroCode Portable Agent Capsule (.arx v2 MCARX2 envelope or JSON capsule)
        if ext == "arx" || ARXCapsuleService.hasBinaryMagic(data) {
            if let capsuleText = ARXCapsuleService.formatGroundedAttachmentSummary(for: url) {
                return AttachmentExtractionPayload(
                    attachmentType: .text,
                    semanticCategory: .dataFile,
                    extractedText: capsuleText,
                    subtitleBadge: "ARX Capsule • \(sizeStr)",
                    metricsSummary: "portable capsule",
                    extractionStatus: "OK",
                    extractionWarning: nil,
                    normalizedVisionData: nil,
                    normalizedVisionMimeType: nil,
                    nativeMediaMimeType: nil
                )
            }
        }

        // Check SQLite magic header even on custom extension (e.g., .arx, .store, .dat)
        if data.count >= 16 && Data(data.prefix(15)) == Data("SQLite format 3".utf8) {
            return extractSQLiteDatabase(url: url, name: name, sizeStr: sizeStr)
        }

        if let decoded = Self.decodeTextSmart(data) {
            let lineCount = decoded.text.components(separatedBy: "\n").count
            let isDataExt = ["json", "jsonl", "ndjson", "yaml", "yml", "xml", "toml", "ini", "env", "sql"].contains(ext)
            var structuralPrefix = "[File: \(name) | Encoding: \(decoded.encodingName) | Lines: \(lineCount) | Size: \(sizeStr)]"

            if ext == "json", let jsonObj = try? JSONSerialization.jsonObject(with: data) {
                if let dict = jsonObj as? [String: Any] {
                    structuralPrefix += "\nJSON Structure: Object with \(dict.count) top-level keys (\(dict.keys.sorted().prefix(20).joined(separator: ", ")))"
                } else if let arr = jsonObj as? [Any] {
                    structuralPrefix += "\nJSON Structure: Array with \(arr.count) items"
                }
            } else if ext == "jsonl" || ext == "ndjson" {
                let nonEmpty = decoded.text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
                structuralPrefix += "\nJSONL Records: \(nonEmpty)"
            }

            let truncWarning = fileSize > Int64(maxTextBytes) ? "Indexed first 20 MB of \(sizeStr)" : nil
            let label = ext.isEmpty ? "TXT" : ext.uppercased()
            return AttachmentExtractionPayload(
                attachmentType: .text,
                semanticCategory: isDataExt ? .dataFile : .codeOrText,
                extractedText: "\(structuralPrefix)\n\n\(decoded.text)",
                subtitleBadge: "\(label) • \(lineCount)L • \(sizeStr)",
                metricsSummary: "\(lineCount) lines (\(decoded.encodingName))",
                extractionStatus: truncWarning == nil ? "READ_OK" : "PARTIAL_PAGED",
                extractionWarning: truncWarning,
                normalizedVisionData: nil,
                normalizedVisionMimeType: nil,
                nativeMediaMimeType: nil
            )
        }

        // Unknown / Compiled Binary: Magic-Byte Detection + Honest Notice
        let magicDesc = Self.detectBinaryMagicSignature(data)
        let hexPreview = data.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ")
        let binaryNotice = """
        [Binary File Metadata: \(name)]
        Detected Signature: \(magicDesc)
        File Size: \(sizeStr) (\(fileSize) bytes)
        Header Bytes (Hex): \(hexPreview)
        [BINARY / UNREADABLE CONTENT NOTICE: Only file header metadata is available. Do NOT guess or fabricate internal contents.]
        """

        return AttachmentExtractionPayload(
            attachmentType: .text,
            semanticCategory: .binary,
            extractedText: binaryNotice,
            subtitleBadge: "BIN (\(magicDesc)) • \(sizeStr)",
            metricsSummary: magicDesc,
            extractionStatus: "LOCKED_OR_BINARY",
            extractionWarning: "Binary format (\(magicDesc)) — header metadata only",
            normalizedVisionData: nil,
            normalizedVisionMimeType: nil,
            nativeMediaMimeType: nil
        )
    }

    static func detectBinaryMagicSignature(_ data: Data) -> String {
        guard data.count >= 4 else { return "Raw Binary" }
        let b0 = data[0], b1 = data[1], b2 = data[2], b3 = data[3]
        if (b0 == 0xCF && b1 == 0xFA && b2 == 0xED && b3 == 0xFE) ||
           (b0 == 0xCE && b1 == 0xFA && b2 == 0xED && b3 == 0xFE) {
            return "Mach-O Executable/Library"
        }
        if b0 == 0xCA && b1 == 0xFE && b2 == 0xBA && b3 == 0xBE {
            return "Universal Mach-O / Java Class"
        }
        if b0 == 0x7F && b1 == 0x45 && b2 == 0x4C && b3 == 0x46 {
            return "ELF Binary"
        }
        if b0 == 0x4D && b1 == 0x5A {
            return "Windows PE/COFF Executable"
        }
        if b0 == 0x00 && b1 == 0x61 && b2 == 0x73 && b3 == 0x6D {
            return "WebAssembly (WASM)"
        }
        if b0 == 0x50 && b1 == 0x4B && (b2 == 0x03 || b2 == 0x05 || b2 == 0x07) {
            return "ZIP / Container"
        }
        if b0 == 0x1F && b1 == 0x8B {
            return "GZIP Stream"
        }
        if b0 == 0x25 && b1 == 0x50 && b2 == 0x44 && b3 == 0x46 {
            return "PDF Header"
        }
        if b0 == 0x89 && b1 == 0x50 && b2 == 0x4E && b3 == 0x47 {
            return "PNG Image"
        }
        if b0 == 0xFF && b1 == 0xD8 && b2 == 0xFF {
            return "JPEG Image"
        }
        if b0 == 0x37 && b1 == 0x7A && b2 == 0xBC && b3 == 0xAF {
            return "7-Zip Archive"
        }
        if b0 == 0x52 && b1 == 0x61 && b2 == 0x72 && b3 == 0x21 {
            return "RAR Archive"
        }
        return "Binary Data"
    }

    // MARK: - Adaptive Multi-File Grounded Turn Package Builder

    /// Builds a bounded, 100% grounded turn context package that scales smoothly from 1 to 100+ simultaneous attachments.
    /// Includes an explicit manifest of every attached file + water-filling fair-share inline content + exact `attachment_read` paging instructions.
    func buildGroundedTurnPackage(attachments: [AIAttachment], maxInlineChars: Int = 90_000) -> String {
        guard !attachments.isEmpty else { return "" }

        var manifestLines: [String] = []
        manifestLines.reserveCapacity(attachments.count + 3)
        manifestLines.append("[ATTACHED FILES MANIFEST — \(attachments.count) file(s)]")
        manifestLines.append("Ground-Truth Vault Active: Every attached file is staged locally below. NEVER guess, extrapolate, or fabricate unseen pages, sheets, or rows. If any file is marked PARTIAL_PAGED, call tool `attachment_read` with `path=\"<staged_path>\"` (supports `page_start`/`page_end`, `sheet`, `start_line`/`end_line`, `query`, `ocr: true`) to read the exact unseen section.")

        let fullTexts: [String] = attachments.map { $0.groundedExtractedText }

        // Compute water-filling fair-share character budgets across all N attachments
        let estimatedManifestOverhead = min(maxInlineChars / 2, attachments.count * 210 + 450)
        let totalContentPool = max(2_400, maxInlineChars - estimatedManifestOverhead)
        let allocatedBudgets = Self.computeWaterFillingBudgets(
            lengths: fullTexts.map(\.count),
            totalPool: totalContentPool,
            minFloorPerFile: attachments.count > 40 ? 600 : 1_200
        )

        var contentBlocks: [String] = []
        contentBlocks.reserveCapacity(attachments.count)

        for (idx, att) in attachments.enumerated() {
            let fullText = fullTexts[idx]
            let alloc = allocatedBudgets[idx]
            let staged = att.stagedPath ?? att.sourceURL?.path ?? att.name
            let cacheInfo = att.extractedTextCachePath.map { " | extracted_cache=\"\($0)\"" } ?? ""
            let badge = att.subtitleBadge ?? att.formattedSize
            let metrics = att.metricsSummary ?? att.formattedSize
            let fitsCompletely = fullText.count <= alloc

            let status: String = {
                if att.isPasswordProtected || att.extractionStatus == "LOCKED_OR_BINARY" {
                    return "LOCKED_OR_BINARY"
                }
                if !fitsCompletely || att.extractionStatus == "PARTIAL_PAGED" {
                    return "PARTIAL_PAGED"
                }
                if att.extractionStatus == "OCR_EXTRACTED" {
                    return "OCR_EXTRACTED"
                }
                return "READ_OK"
            }()

            let warnSuffix = att.extractionWarning.map { " | warning=\"\($0)\"" } ?? ""
            manifestLines.append("- #\(idx + 1) | name=\"\(att.name)\" | badge=\"\(badge)\" | metrics=\"\(metrics)\" | status=\(status) | staged_path=\"\(staged)\"\(cacheInfo)\(warnSuffix)")

            if fitsCompletely {
                contentBlocks.append("""
                <attached_file index="\(idx + 1)" name="\(att.name)" status="\(status)" staged_path="\(staged)">
                [FULL CONTENT INCLUDED (\(fullText.count) chars)]
                \(fullText)
                </attached_file>
                """)
            } else {
                let pagedPreview = Self.buildPagedPreviewWithOutline(
                    fullText: fullText,
                    budgetChars: alloc,
                    stagedPath: staged
                )
                contentBlocks.append("""
                <attached_file index="\(idx + 1)" name="\(att.name)" status="PARTIAL_PAGED" staged_path="\(staged)">
                \(pagedPreview)
                </attached_file>
                """)
            }
        }

        return manifestLines.joined(separator: "\n") + "\n\n" + contentBlocks.joined(separator: "\n\n")
    }

    /// Compact follow-up reference persisted in chat transcript history so Turn 2+ ("What about page 5?")
    /// retains exact `staged_path`s, badges, warnings, and synopses without re-bloating multi-turn history.
    func buildFollowUpHistoryDigest(attachments: [AIAttachment], maxTotalChars: Int = 4_200) -> String {
        guard !attachments.isEmpty else { return "" }
        let perItemSynopsis = max(80, min(320, (maxTotalChars - 400) / max(1, attachments.count)))
        var lines: [String] = [
            "[Attached in this turn (\(attachments.count) file(s)) — Staged in ~/.microcode/attachments for follow-up `attachment_read` queries:]"
        ]
        for (idx, att) in attachments.prefix(80).enumerated() {
            let staged = att.stagedPath ?? att.sourceURL?.path ?? att.name
            let badge = att.subtitleBadge ?? att.formattedSize
            let warn = att.extractionWarning.map { " [Warning: \($0)]" } ?? ""
            let cleanPreview = att.groundedExtractedText
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let synopsis = cleanPreview.count > perItemSynopsis
                ? String(cleanPreview.prefix(perItemSynopsis)) + "..."
                : cleanPreview
            lines.append("- #\(idx + 1) `\(att.name)` (\(badge)) | staged_path=\"\(staged)\"\(warn) | excerpt: \(synopsis)")
        }
        if attachments.count > 80 {
            lines.append("- ... and \(attachments.count - 80) additional staged file(s).")
        }
        return lines.joined(separator: "\n")
    }

    /// Clean, human-readable 1-line badge summary displayed inside user chat bubbles.
    func buildUserBubbleAttachmentSummary(attachments: [AIAttachment]) -> String {
        guard !attachments.isEmpty else { return "" }
        let chips = attachments.prefix(8).map { att -> String in
            let badge = att.subtitleBadge ?? att.formattedSize
            let warnIcon = att.extractionWarning != nil ? " ⚠️" : ""
            return "📎 \(att.name) (\(badge))\(warnIcon)"
        }
        let extra = attachments.count > 8 ? " +\(attachments.count - 8) more" : ""
        return chips.joined(separator: "  ") + extra
    }

    private static func computeWaterFillingBudgets(lengths: [Int], totalPool: Int, minFloorPerFile: Int) -> [Int] {
        guard !lengths.isEmpty else { return [] }
        let count = lengths.count
        var budgets = Array(repeating: 0, count: count)
        let sortedIndices = lengths.indices.sorted { lengths[$0] < lengths[$1] }

        var remainingPool = totalPool
        var remainingFiles = count

        for idx in sortedIndices {
            let fairShare = max(minFloorPerFile, remainingPool / max(1, remainingFiles))
            let needed = lengths[idx]
            if needed <= fairShare {
                budgets[idx] = needed
                remainingPool = max(0, remainingPool - needed)
            } else {
                budgets[idx] = fairShare
                remainingPool = max(0, remainingPool - fairShare)
            }
            remainingFiles -= 1
        }
        return budgets
    }

    private static func buildPagedPreviewWithOutline(fullText: String, budgetChars: Int, stagedPath: String) -> String {
        let safeBudget = max(450, budgetChars)
        let lines = fullText.components(separatedBy: "\n")

        // Collect structural markers (Pages, Sheets, Slides, Tables, Notebook Cells, Chapters)
        let structuralHeadings = lines.enumerated().compactMap { (idx, line) -> String? in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("=== ") || t.hasPrefix("### Cell ") || t.hasPrefix("[FILE] ") {
                return "L\(idx + 1): \(t)"
            }
            return nil
        }

        let outlineQuota = structuralHeadings.isEmpty ? 0 : min(safeBudget / 4, 1_800)
        var outlineBlock = ""
        if outlineQuota > 120 {
            var acc = "[Document Structural Index]:\n"
            for heading in structuralHeadings.prefix(60) {
                if acc.count + heading.count + 2 > outlineQuota {
                    acc += "... (\(structuralHeadings.count) total sections)\n"
                    break
                }
                acc += heading + "\n"
            }
            outlineBlock = acc + "\n"
        }

        let bodyQuota = max(300, safeBudget - outlineBlock.count)
        let headChars = (bodyQuota * 3) / 4
        let tailChars = max(100, bodyQuota - headChars)

        let headText = String(fullText.prefix(headChars))
        let tailText = String(fullText.suffix(tailChars))
        let includedCount = min(fullText.count, headText.count + tailText.count)

        return """
        \(outlineBlock)\(headText)

        [TRUNCATED INLINE AT \(includedCount) / \(fullText.count) CHARS (Total Lines: \(lines.count)) — Use tool 'attachment_read' with path="\(stagedPath)" (supports page_start/page_end, sheet, start_line/end_line, query, or ocr: true) to read any remaining section verbatim. NEVER guess unseen pages/rows!]

        --- Tail Preview ---
        \(tailText)
        """
    }

    // MARK: - On-Demand Paged Reader & Search (`readAttachmentSlice`)

    func readAttachmentSlice(
        path: String,
        pageStart: Int? = nil,
        pageEnd: Int? = nil,
        sheet: String? = nil,
        rowStart: Int? = nil,
        rowEnd: Int? = nil,
        startLine: Int? = nil,
        endLine: Int? = nil,
        query: String? = nil,
        forceOCR: Bool = false
    ) async -> String {
        let fm = FileManager.default
        let resolvedInputPath = WorkspacePathPolicy.canonicalPath(path)
        let sidecar = readSidecar(for: resolvedInputPath)

        // Resolve underlying binary file URL (honoring sidecar's authorizedSourcePath for >128MB files staged as manifests inside vault)
        let binaryPath: String = {
            if let sidecar,
               let authSrc = sidecar.authorizedSourcePath,
               sidecar.fileSizeBytes > Self.maxDirectCopyBytes,
               fm.fileExists(atPath: authSrc) {
                return authSrc
            }
            if resolvedInputPath.hasSuffix(".extracted.txt") {
                let base = String(resolvedInputPath.dropLast(".extracted.txt".count))
                if fm.fileExists(atPath: base) { return base }
            }
            return resolvedInputPath
        }()

        let binaryURL = URL(fileURLWithPath: binaryPath)
        let displayName = sidecar?.originalName ?? binaryURL.lastPathComponent
        let ext = (displayName as NSString).pathExtension.lowercased()

        var isDirObj: ObjCBool = false
        guard fm.fileExists(atPath: resolvedInputPath, isDirectory: &isDirObj) || fm.fileExists(atPath: binaryPath, isDirectory: &isDirObj) else {
            return "Error: Attachment or file not found at '\(path)'"
        }

        // 1. PDF targeted page range / on-demand ANE Vision OCR
        if ext == "pdf" && (pageStart != nil || pageEnd != nil || forceOCR) && query == nil {
            guard let doc = PDFDocument(url: binaryURL) else {
                return "Error: Unable to open PDF document '\(displayName)'."
            }
            if doc.isLocked && !doc.unlock(withPassword: "") {
                return "[LOCKED PDF WARNING: '\(displayName)' is password-protected and cannot be read without a password.]"
            }
            let totalPages = doc.pageCount
            guard totalPages > 0 else { return "[PDF '\(displayName)' has 0 pages.]" }
            let pStart = max(1, min(totalPages, pageStart ?? 1))
            let defaultEnd = min(totalPages, pStart + 14)
            let pEnd = max(pStart, min(totalPages, pageEnd ?? defaultEnd))

            var pageOutputs: [String] = ["[PDF Slice: \(displayName) | Pages \(pStart)-\(pEnd) of \(totalPages)]"]
            for p in pStart...pEnd {
                guard let page = doc.page(at: p - 1) else { continue }
                let digital = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                var body = digital
                if forceOCR || digital.count < 48 {
                    if let png = Self.rasterizePDFPageToPNG(page: page, dpi: 165.0) {
                        let vision = await AppleVisionEngine.shared.analyzeImage(data: png, filename: "\(displayName)#page-\(p).png")
                        let ocrText = vision.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let ocrBlock = ocrText.isEmpty
                            ? "[Page \(p) ANE Vision OCR]: (No recognizable text characters on page)"
                            : "[Page \(p) ANE Vision OCR]:\n\(ocrText)"
                        body = body.isEmpty ? ocrBlock : (body + "\n\n" + ocrBlock)
                    }
                }
                pageOutputs.append("=== Page \(p) of \(totalPages) ===\n\(body)")
            }
            if pEnd < totalPages {
                pageOutputs.append("[More pages available: pass page_start=\(pEnd + 1), page_end=\(min(totalPages, pEnd + 15)) to continue reading.]")
            }
            return pageOutputs.joined(separator: "\n\n")
        }

        // 1b. Image on-demand ANE Vision OCR (`ocr: true`)
        if ["png", "jpg", "jpeg", "webp", "heic", "heif", "gif", "bmp", "tiff", "tif", "svg", "icns"].contains(ext) && forceOCR {
            guard let imgData = try? Data(contentsOf: binaryURL, options: .mappedIfSafe), !imgData.isEmpty else {
                return "Error: Unable to read image bytes from '\(displayName)'."
            }
            let normalized = Self.normalizeImageForUniversalVision(data: imgData, ext: ext)
            let vision = await AppleVisionEngine.shared.analyzeImage(data: normalized?.data ?? imgData, filename: displayName)
            let cacheURL = URL(fileURLWithPath: binaryURL.path + ".extracted.txt")
            try? vision.formattedSummary.write(to: cacheURL, atomically: true, encoding: .utf8)
            return vision.formattedSummary
        }

        // 2. PPTX targeted slide range (`page_start` / `page_end` map to slides!)
        if ext == "pptx" && (pageStart != nil || pageEnd != nil) && query == nil {
            let slides = Self.parsePPTXSlides(at: binaryURL.path)
            guard !slides.isEmpty else { return "Error: Unable to read slides from '\(displayName)'." }
            let sStart = max(1, min(slides.count, pageStart ?? 1))
            let sEnd = max(sStart, min(slides.count, pageEnd ?? min(slides.count, sStart + 19)))
            var blocks: [String] = ["[PPTX Slice: \(displayName) | Slides \(sStart)-\(sEnd) of \(slides.count)]"]
            for s in sStart...sEnd {
                let slide = slides[s - 1]
                var b = "=== Slide \(s) of \(slides.count) ===\n\(slide.body)"
                if !slide.notes.isEmpty {
                    b += "\n[Speaker Notes]:\n\(slide.notes)"
                }
                blocks.append(b)
            }
            return blocks.joined(separator: "\n\n")
        }

        // 3. XLSX targeted sheet & row slice
        if ext == "xlsx" && (sheet != nil || rowStart != nil || rowEnd != nil) && query == nil {
            let workbook = Self.parseXLSXWorkbook(at: binaryURL.path, maxRowsPerSheet: 50_000)
            guard !workbook.sheets.isEmpty else {
                return "Error: Unable to parse XLSX workbook '\(displayName)'."
            }
            let targetSheet: ParsedXLSXSheet? = {
                guard let req = sheet?.trimmingCharacters(in: .whitespacesAndNewlines), !req.isEmpty else {
                    return workbook.sheets.first
                }
                if let exact = workbook.sheets.first(where: { $0.name.caseInsensitiveCompare(req) == .orderedSame }) {
                    return exact
                }
                return workbook.sheets.first(where: { $0.name.localizedCaseInsensitiveContains(req) })
            }()
            guard let chosen = targetSheet else {
                let available = workbook.sheets.map(\.name).joined(separator: ", ")
                return "Sheet '\(sheet ?? "")' not found in '\(displayName)'. Available sheets: \(available)"
            }
            let rStart = max(1, rowStart ?? startLine ?? 1)
            let rEnd = max(rStart, min(chosen.rows.count, rowEnd ?? endLine ?? min(chosen.rows.count, rStart + 149)))
            guard !chosen.rows.isEmpty, rStart <= chosen.rows.count else {
                return "[Excel Sheet '\(chosen.name)' has \(chosen.rows.count) non-empty rows.]"
            }
            var sliceRows: [[String]] = []
            if rStart > 1, let header = chosen.rows.first {
                sliceRows.append(header)
            }
            sliceRows.append(contentsOf: chosen.rows[(rStart - 1)..<rEnd])
            let tableMD = Self.renderMarkdownTable(rows: sliceRows)
            let moreNote = rEnd < chosen.rows.count
                ? "\n\n[Showing rows \(rStart)-\(rEnd) of \(chosen.rows.count) in sheet '\(chosen.name)'. Pass sheet=\"\(chosen.name)\", start_line=\(rEnd + 1), end_line=\(min(chosen.rows.count, rEnd + 150)) for next rows.]"
                : ""
            return "[XLSX Sheet: \(chosen.name) | Rows \(rStart)-\(rEnd) of \(chosen.rows.count) | Cols: \(chosen.maxCols)]\n\n\(tableMD)\(moreNote)"
        }

        // 4. SQLite targeted table pagination (`sheet` = table name)
        if (["sqlite", "sqlite3", "db"].contains(ext)) && sheet != nil && query == nil {
            let rStart = max(1, rowStart ?? startLine ?? 1)
            let limit = max(1, min(500, (rowEnd ?? endLine).map { max(1, $0 - rStart + 1) } ?? 100))
            let sqlRes = Self.inspectSQLite(at: binaryURL.path, targetTable: sheet, rowOffset: rStart - 1, rowLimit: limit)
            return sqlRes.formattedText
        }

        // 5. Image forced OCR re-analysis
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "webp", "heic", "heif", "gif", "bmp", "tiff", "tif", "svg", "icns"]
        if imageExts.contains(ext) && forceOCR && query == nil {
            if let raw = try? Data(contentsOf: binaryURL, options: .mappedIfSafe) {
                let norm = Self.normalizeImageForUniversalVision(data: raw, ext: ext)?.data ?? raw
                let vision = await AppleVisionEngine.shared.analyzeImage(data: norm, filename: displayName)
                return vision.formattedSummary
            }
        }

        // 6. Load cached `.extracted.txt` in O(1) or extract on-the-fly if reading a workspace file directly
        let fullExtractedText = await loadOrExtractCachedText(
            inputPath: resolvedInputPath,
            binaryURL: binaryURL,
            displayName: displayName,
            sidecar: sidecar,
            isDirectory: isDirObj.boolValue
        )

        // 7. Universal Keyword / Substring Search (`query`) across all pages, sheets, cells, or lines
        if let rawQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines), !rawQuery.isEmpty {
            return Self.searchExtractedText(fullExtractedText, fileName: displayName, query: rawQuery)
        }

        // 8. Universal 1-based Line Slicing (`start_line` / `end_line` / `row_start` / `row_end`)
        let lines = fullExtractedText.components(separatedBy: "\n")
        let totalLines = lines.count
        let reqStart = startLine ?? rowStart ?? pageStart.map { ($0 - 1) * 60 + 1 }
        let reqEnd = endLine ?? rowEnd

        let sIdx = max(0, (reqStart ?? 1) - 1)
        let defaultWindow = reqStart != nil ? 400 : 450
        let eIdx = min(totalLines, max(sIdx, reqEnd ?? (sIdx + defaultWindow)))

        guard sIdx < totalLines else {
            return "[Attachment: \(displayName) | Total Lines: \(totalLines)] Requested start_line \(sIdx + 1) exceeds total line count (\(totalLines))."
        }

        let numberedSlice = lines[sIdx..<eIdx].enumerated()
            .map { "\(sIdx + $0.offset + 1): \($0.element)" }
            .joined(separator: "\n")

        let footer = eIdx < totalLines
            ? "\n\n[Showing lines \(sIdx + 1)-\(eIdx) of \(totalLines). Call `attachment_read` with path=\"\(path)\", start_line=\(eIdx + 1), end_line=\(min(totalLines, eIdx + 400)) to read the next section.]"
            : ""

        return "[Attachment Slice: \(displayName) | Lines \(sIdx + 1)-\(eIdx) of \(totalLines)]\n\n\(numberedSlice)\(footer)"
    }

    private func loadOrExtractCachedText(
        inputPath: String,
        binaryURL: URL,
        displayName: String,
        sidecar: VaultAttachmentSidecar?,
        isDirectory: Bool
    ) async -> String {
        let fm = FileManager.default
        let cacheCandidates = [
            sidecar?.extractedTextCachePath,
            inputPath.hasSuffix(".extracted.txt") ? inputPath : (inputPath + ".extracted.txt"),
            binaryURL.path + ".extracted.txt"
        ].compactMap { $0 }

        for candidate in cacheCandidates where fm.fileExists(atPath: candidate) {
            if let cached = try? String(contentsOfFile: candidate, encoding: .utf8), !cached.isEmpty {
                return cached
            }
        }

        let size = ((try? fm.attributesOfItem(atPath: binaryURL.path)[.size]) as? NSNumber)?.int64Value ?? 0
        let payload = await extractFromFileOrDirectory(
            targetURL: binaryURL,
            originalName: displayName,
            stagedVaultURL: binaryURL,
            fileSize: size,
            isDirectory: isDirectory
        )

        // Cache inside vault if path already resides inside vaultRootDirectory
        if WorkspacePathPolicy.contains(inputPath, in: Self.vaultRootDirectory.path), !payload.extractedText.isEmpty {
            let cacheURL = URL(fileURLWithPath: inputPath + ".extracted.txt")
            try? payload.extractedText.write(to: cacheURL, atomically: true, encoding: .utf8)
        }
        return payload.extractedText
    }

    private static func searchExtractedText(_ fullText: String, fileName: String, query: String) -> String {
        let lines = fullText.components(separatedBy: "\n")
        var currentSection = "Header"
        var matches: [String] = []
        let maxMatches = 40

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("=== ") || trimmed.hasPrefix("### Cell ") {
                currentSection = trimmed.replacingOccurrences(of: "===", with: "").trimmingCharacters(in: .whitespaces)
            }
            if line.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                let prev = idx > 0 ? "  \(idx): \(lines[idx - 1])\n" : ""
                let curr = "> \(idx + 1): \(line)"
                let next = (idx + 1 < lines.count) ? "\n  \(idx + 2): \(lines[idx + 1])" : ""
                matches.append("[Line \(idx + 1) | \(currentSection)]\n\(prev)\(curr)\(next)")
                if matches.count >= maxMatches { break }
            }
        }

        if matches.isEmpty {
            return "[Search in '\(fileName)' for \"\(query)\"]: 0 matches across \(lines.count) extracted lines."
        }
        return "[Search in '\(fileName)' for \"\(query)\" — \(matches.count)\(matches.count >= maxMatches ? "+" : "") match(es) across \(lines.count) lines]:\n\n" + matches.joined(separator: "\n\n")
    }

    // MARK: - Native SQLite3 Read-Only Inspector

    static func inspectSQLite(at path: String, targetTable: String?, rowOffset: Int, rowLimit: Int) -> (success: Bool, tableCount: Int, formattedText: String, warning: String?) {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 failed (\(rc))"
            if let db { sqlite3_close(db) }
            return (false, 0, "", msg)
        }
        defer { sqlite3_close(db) }

        var masterStmt: OpaquePointer?
        let masterSQL = "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' AND type IN ('table', 'view') ORDER BY type, name;"
        guard sqlite3_prepare_v2(db, masterSQL, -1, &masterStmt, nil) == SQLITE_OK, let masterStmt else {
            let err = String(cString: sqlite3_errmsg(db))
            return (false, 0, "", err)
        }
        defer { sqlite3_finalize(masterStmt) }

        struct TableMeta {
            let kind: String
            let name: String
            let ddl: String
        }
        var tables: [TableMeta] = []
        while sqlite3_step(masterStmt) == SQLITE_ROW {
            let kind = sqlite3_column_text(masterStmt, 0).map { String(cString: $0) } ?? "table"
            let name = sqlite3_column_text(masterStmt, 1).map { String(cString: $0) } ?? ""
            let ddl = sqlite3_column_text(masterStmt, 2).map { String(cString: $0) } ?? ""
            if !name.isEmpty {
                tables.append(TableMeta(kind: kind, name: name, ddl: ddl))
            }
        }

        if let requested = targetTable?.trimmingCharacters(in: .whitespacesAndNewlines), !requested.isEmpty {
            guard let matched = tables.first(where: { $0.name.caseInsensitiveCompare(requested) == .orderedSame })
                ?? tables.first(where: { $0.name.localizedCaseInsensitiveContains(requested) }) else {
                let names = tables.map(\.name).joined(separator: ", ")
                return (true, tables.count, "Table '\(requested)' not found. Available tables/views: \(names)", nil)
            }
            let section = renderSQLiteTableSection(db: db, kind: matched.kind, name: matched.name, ddl: matched.ddl, offset: rowOffset, limit: rowLimit)
            return (true, tables.count, section, nil)
        }

        if tables.isEmpty {
            return (true, 0, "(SQLite database contains 0 user tables or views.)", nil)
        }

        var sections: [String] = []
        for tbl in tables.prefix(35) {
            sections.append(renderSQLiteTableSection(db: db, kind: tbl.kind, name: tbl.name, ddl: tbl.ddl, offset: 0, limit: rowLimit))
        }
        if tables.count > 35 {
            let remaining = tables.dropFirst(35).map(\.name).joined(separator: ", ")
            sections.append("[+\(tables.count - 35) additional tables: \(remaining) — pass sheet=\"<table_name>\" to attachment_read to inspect.]")
        }
        return (true, tables.count, sections.joined(separator: "\n\n"), nil)
    }

    private static func renderSQLiteTableSection(db: OpaquePointer, kind: String, name: String, ddl: String, offset: Int, limit: Int) -> String {
        let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
        var totalRows: Int64 = 0
        var countStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \"\(escaped)\";", -1, &countStmt, nil) == SQLITE_OK, let countStmt {
            if sqlite3_step(countStmt) == SQLITE_ROW {
                totalRows = sqlite3_column_int64(countStmt, 0)
            }
            sqlite3_finalize(countStmt)
        }

        var rows: [[String]] = []
        var selectStmt: OpaquePointer?
        let querySQL = "SELECT * FROM \"\(escaped)\" LIMIT \(max(1, limit)) OFFSET \(max(0, offset));"
        if sqlite3_prepare_v2(db, querySQL, -1, &selectStmt, nil) == SQLITE_OK, let selectStmt {
            let colCount = Int(sqlite3_column_count(selectStmt))
            if colCount > 0 {
                let colHeaders = (0..<colCount).map { idx -> String in
                    sqlite3_column_name(selectStmt, Int32(idx)).map { String(cString: $0) } ?? "col_\(idx)"
                }
                rows.append(colHeaders)

                while sqlite3_step(selectStmt) == SQLITE_ROW {
                    let rowVals = (0..<colCount).map { idx -> String in
                        let colIdx = Int32(idx)
                        switch sqlite3_column_type(selectStmt, colIdx) {
                        case SQLITE_NULL:
                            return "NULL"
                        case SQLITE_INTEGER:
                            return "\(sqlite3_column_int64(selectStmt, colIdx))"
                        case SQLITE_FLOAT:
                            return String(sqlite3_column_double(selectStmt, colIdx))
                        case SQLITE_BLOB:
                            let bytes = sqlite3_column_bytes(selectStmt, colIdx)
                            return "<BLOB \(bytes)B>"
                        default:
                            if let cStr = sqlite3_column_text(selectStmt, colIdx) {
                                let s = String(cString: cStr)
                                return s.count > 240 ? String(s.prefix(240)) + "..." : s
                            }
                            return ""
                        }
                    }
                    rows.append(rowVals)
                }
            }
            sqlite3_finalize(selectStmt)
        }

        var out = "=== \(kind.capitalized): \(name) (Total Rows: \(totalRows)) ==="
        if !ddl.isEmpty {
            out += "\nSchema: \(ddl)"
        }
        if rows.count > 1 {
            out += "\n\n" + renderMarkdownTable(rows: rows)
            if Int64(offset + rows.count - 1) < totalRows {
                out += "\n[Showing rows \(offset + 1)-\(offset + rows.count - 1) of \(totalRows) — pass sheet=\"\(name)\", start_line=\(offset + rows.count) to read more rows.]"
            }
        } else if let headerOnly = rows.first {
            out += "\nColumns: " + headerOnly.joined(separator: ", ") + "\n(0 rows)"
        }
        return out
    }

    // MARK: - OOXML Excel (.xlsx) & PowerPoint (.pptx) Parsers

    struct ParsedXLSXSheet {
        let name: String
        let rows: [[String]]
        let totalRows: Int
        let maxCols: Int
    }

    static func parseXLSXWorkbook(at zipPath: String, maxRowsPerSheet: Int) -> (sheets: [ParsedXLSXSheet], warning: String?) {
        let entries = listZipEntries(at: zipPath)
        guard !entries.isEmpty else {
            return ([], "Cannot read XLSX zip entries (encrypted or corrupted)")
        }

        var sharedStrings: [String] = []
        if entries.contains("xl/sharedStrings.xml"),
           let ssData = readZipEntry(at: zipPath, entry: "xl/sharedStrings.xml", maxBytes: 16 * 1024 * 1024) {
            sharedStrings = XlsxSharedStringsParser().parse(data: ssData)
        }

        var relsMap: [String: String] = [:]
        if entries.contains("xl/_rels/workbook.xml.rels"),
           let relsData = readZipEntry(at: zipPath, entry: "xl/_rels/workbook.xml.rels") {
            relsMap = XlsxRelsParser().parse(data: relsData)
        }

        var orderedSheetTargets: [(name: String, entry: String)] = []
        if entries.contains("xl/workbook.xml"),
           let wbData = readZipEntry(at: zipPath, entry: "xl/workbook.xml") {
            let wbSheets = XlsxWorkbookMetaParser().parse(data: wbData)
            for (idx, item) in wbSheets.enumerated() {
                if let target = relsMap[item.relId] {
                    let cleanTarget = target.hasPrefix("/")
                        ? String(target.dropFirst())
                        : (target.hasPrefix("xl/") ? target : "xl/\(target)")
                    if entries.contains(cleanTarget) {
                        orderedSheetTargets.append((item.name, cleanTarget))
                        continue
                    }
                }
                let fallbackEntry = "xl/worksheets/sheet\(idx + 1).xml"
                if entries.contains(fallbackEntry) {
                    orderedSheetTargets.append((item.name, fallbackEntry))
                }
            }
        }

        if orderedSheetTargets.isEmpty {
            let rawWorksheets = entries.filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
                .sorted { extractTrailingNumber($0) < extractTrailingNumber($1) }
            orderedSheetTargets = rawWorksheets.enumerated().map { ("Sheet\($0.offset + 1)", $0.element) }
        }

        var parsedSheets: [ParsedXLSXSheet] = []
        for target in orderedSheetTargets {
            guard let wsData = readZipEntry(at: zipPath, entry: target.entry, maxBytes: 16 * 1024 * 1024) else { continue }
            let ws = XlsxWorksheetParser(sharedStrings: sharedStrings, maxRows: maxRowsPerSheet).parse(data: wsData)
            parsedSheets.append(ParsedXLSXSheet(name: target.name, rows: ws.rows, totalRows: ws.totalRows, maxCols: ws.maxCols))
        }
        return (parsedSheets, nil)
    }

    static func renderSheetMarkdownSection(sheet: ParsedXLSXSheet) -> String {
        var header = "=== Sheet: \(sheet.name) (Rows: \(sheet.totalRows), Cols: \(sheet.maxCols)) ==="
        guard !sheet.rows.isEmpty else {
            return header + "\n(Empty worksheet)"
        }
        let previewRows = Array(sheet.rows.prefix(500))
        header += "\n" + renderMarkdownTable(rows: previewRows)
        if sheet.totalRows > previewRows.count {
            header += "\n[Sheet '\(sheet.name)' continues for \(sheet.totalRows - previewRows.count) more rows — use `attachment_read(sheet: \"\(sheet.name)\", start_line: \(previewRows.count + 1), end_line: \(min(sheet.totalRows, previewRows.count + 200)))`]"
        }
        return header
    }

    static func parsePPTXSlides(at zipPath: String) -> [(body: String, notes: String)] {
        let entries = listZipEntries(at: zipPath)
        let slideEntries = entries.filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            .sorted { extractTrailingNumber($0) < extractTrailingNumber($1) }
        guard !slideEntries.isEmpty else { return [] }

        var results: [(body: String, notes: String)] = []
        for slideEntry in slideEntries {
            let slideNum = extractTrailingNumber(slideEntry)
            let body: String
            if let data = readZipEntry(at: zipPath, entry: slideEntry) {
                body = PptxSlideXMLParser().parse(data: data)
            } else {
                body = ""
            }
            var notes = ""
            let notesEntry = "ppt/notesSlides/notesSlide\(slideNum).xml"
            if entries.contains(notesEntry), let nData = readZipEntry(at: zipPath, entry: notesEntry) {
                notes = PptxSlideXMLParser().parse(data: nData)
            }
            results.append((body: body, notes: notes))
        }
        return results
    }

    private static func extractTrailingNumber(_ path: String) -> Int {
        let base = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let digits = base.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        return Int(String(String.UnicodeScalarView(digits))) ?? 0
    }

    static func excelColumnIndex(from cellRef: String) -> Int {
        var col = 0
        for scalar in cellRef.uppercased().unicodeScalars {
            if scalar.value >= 65 && scalar.value <= 90 {
                col = col * 26 + Int(scalar.value - 64)
            } else {
                break
            }
        }
        return max(0, col - 1)
    }

    // MARK: - Formatting & Delimiter Helpers

    static func detectCSVDelimiter(sampleLine: String) -> Character {
        let candidates: [Character] = [",", "\t", ";", "|"]
        var best: Character = ","
        var bestCount = 0
        for cand in candidates {
            let cnt = sampleLine.filter { $0 == cand }.count
            if cnt > bestCount {
                bestCount = cnt
                best = cand
            }
        }
        return best
    }

    static func parseDelimitedLine(_ line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if inQuotes && i + 1 < chars.count && chars[i + 1] == "\"" {
                    current.append("\"")
                    i += 2
                    continue
                }
                inQuotes.toggle()
            } else if c == delimiter && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(c)
            }
            i += 1
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    static func renderMarkdownTable(rows: [[String]]) -> String {
        guard !rows.isEmpty else { return "" }
        let colCount = max(1, rows.map(\.count).max() ?? 1)
        let cappedColCount = min(colCount, 40)

        func formatRow(_ row: [String]) -> String {
            var cells: [String] = []
            cells.reserveCapacity(cappedColCount)
            for c in 0..<cappedColCount {
                let raw = c < row.count ? row[c] : ""
                let clean = raw
                    .replacingOccurrences(of: "\r\n", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "|", with: "\\|")
                cells.append(clean)
            }
            if colCount > cappedColCount {
                cells.append("...(+\(colCount - cappedColCount) cols)")
            }
            return "| " + cells.joined(separator: " | ") + " |"
        }

        var lines: [String] = []
        lines.reserveCapacity(rows.count + 1)
        lines.append(formatRow(rows[0]))
        let dividerCols = colCount > cappedColCount ? cappedColCount + 1 : cappedColCount
        lines.append("| " + Array(repeating: "---", count: dividerCols).joined(separator: " | ") + " |")
        for row in rows.dropFirst() {
            lines.append(formatRow(row))
        }
        return lines.joined(separator: "\n")
    }

    static func stripHTMLToStructuredText(_ html: String) -> String {
        var s = html
        // Remove <script> and <style> blocks
        s = s.replacingOccurrences(of: #"(?is)<(script|style)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)</(p|div|section|article|tr|li|h[1-6])>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<li\b[^>]*>"#, with: "- ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)</t[dh]>"#, with: " | ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&mdash;", "—"), ("&ndash;", "–")
        ]
        for (k, v) in entities {
            s = s.replacingOccurrences(of: k, with: v)
        }
        return s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func extractPrintableIdentifiers(from data: Data, minLen: Int, maxCount: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        var current: [UInt8] = []

        func flush() {
            guard current.count >= minLen && current.count <= 64 else {
                current.removeAll(keepingCapacity: true)
                return
            }
            if let str = String(bytes: current, encoding: .ascii),
               str.range(of: #"^[A-Za-z_][A-Za-z0-9_.:-]*$"#, options: .regularExpression) != nil,
               !seen.contains(str) {
                seen.insert(str)
                result.append(str)
            }
            current.removeAll(keepingCapacity: true)
        }

        for b in data {
            if (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x5F || b == 0x2D || b == 0x2E {
                current.append(b)
            } else {
                flush()
                if result.count >= maxCount { break }
            }
        }
        flush()
        return result
    }
}

// MARK: - XML Delegate Parsers for DOCX / ODT / XLSX / PPTX

private final class DocxXMLParser: NSObject, XMLParserDelegate {
    private var blocks: [String] = []
    private var currentParagraph = ""
    private var inTextRun = false
    private var tableDepth = 0
    private var currentTableRows: [[String]] = []
    private var currentRowCells: [String] = []
    private var currentCellParagraphs: [String] = []
    private(set) var paragraphCount = 0
    private(set) var tableCount = 0

    func parse(data: Data) -> (text: String, paragraphCount: Int, tableCount: Int) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        return (blocks.joined(separator: "\n"), paragraphCount, tableCount)
    }

    private func localTag(_ raw: String) -> String {
        if let idx = raw.lastIndex(of: ":") {
            return String(raw[raw.index(after: idx)...])
        }
        return raw
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let tag = localTag(elementName)
        switch tag {
        case "tbl", "table":
            tableDepth += 1
            if tableDepth == 1 {
                currentTableRows = []
            }
        case "tr", "table-row":
            if tableDepth == 1 {
                currentRowCells = []
            }
        case "tc", "table-cell":
            if tableDepth == 1 {
                currentCellParagraphs = []
            }
        case "p", "h":
            currentParagraph = ""
        case "t", "span":
            if elementName.hasPrefix("w:") || tag == "t" {
                inTextRun = true
            }
        case "tab", "s":
            currentParagraph += (tableDepth > 0 ? " " : "\t")
        case "br", "cr", "line-break":
            currentParagraph += (tableDepth > 0 ? " / " : "\n")
        default:
            if elementName.hasPrefix("text:") {
                inTextRun = true
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTextRun {
            currentParagraph += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let tag = localTag(elementName)
        switch tag {
        case "t":
            inTextRun = false
        case "p", "h":
            inTextRun = false
            let trimmed = currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if tableDepth == 1 {
                if !trimmed.isEmpty {
                    currentCellParagraphs.append(trimmed)
                }
            } else if !trimmed.isEmpty {
                paragraphCount += 1
                blocks.append(trimmed)
            }
            currentParagraph = ""
        case "tc", "table-cell":
            if tableDepth == 1 {
                currentRowCells.append(currentCellParagraphs.joined(separator: " "))
                currentCellParagraphs = []
            }
        case "tr", "table-row":
            if tableDepth == 1 && !currentRowCells.isEmpty {
                currentTableRows.append(currentRowCells)
                currentRowCells = []
            }
        case "tbl", "table":
            if tableDepth == 1 {
                if !currentTableRows.isEmpty {
                    tableCount += 1
                    blocks.append(UniversalAttachmentEngine.renderMarkdownTable(rows: currentTableRows))
                }
                currentTableRows = []
            }
            tableDepth = max(0, tableDepth - 1)
        default:
            break
        }
    }
}

private final class XlsxSharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var currentItem = ""
    private var inSI = false
    private var inT = false
    private var inPhoneticRun = false

    func parse(data: Data) -> [String] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        _ = parser.parse()
        return strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let tag = elementName.components(separatedBy: ":").last ?? elementName
        if tag == "si" {
            inSI = true
            currentItem = ""
        } else if tag == "rPh" {
            inPhoneticRun = true
        } else if tag == "t" && inSI && !inPhoneticRun {
            inT = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inT && !inPhoneticRun {
            currentItem += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let tag = elementName.components(separatedBy: ":").last ?? elementName
        if tag == "t" {
            inT = false
        } else if tag == "rPh" {
            inPhoneticRun = false
        } else if tag == "si" {
            strings.append(currentItem)
            inSI = false
        }
    }
}

private final class XlsxRelsParser: NSObject, XMLParserDelegate {
    private var map: [String: String] = [:]

    func parse(data: Data) -> [String: String] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        _ = parser.parse()
        return map
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let tag = elementName.components(separatedBy: ":").last ?? elementName
        if tag == "Relationship", let id = attributeDict["Id"], let target = attributeDict["Target"] {
            map[id] = target
        }
    }
}

private final class XlsxWorkbookMetaParser: NSObject, XMLParserDelegate {
    private var sheets: [(name: String, relId: String)] = []

    func parse(data: Data) -> [(name: String, relId: String)] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        _ = parser.parse()
        return sheets
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let tag = elementName.components(separatedBy: ":").last ?? elementName
        if tag == "sheet" {
            let name = attributeDict["name"] ?? "Sheet\(sheets.count + 1)"
            let rId = attributeDict["r:id"] ?? attributeDict["id"] ?? ""
            sheets.append((name, rId))
        }
    }
}

private final class XlsxWorksheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private let maxRows: Int
    private var rows: [[String]] = []
    private var totalRows = 0
    private var maxCols = 0

    private var currentRowCells: [Int: String] = [:]
    private var currentColIndex = 0
    private var currentCellType = ""
    private var currentValue = ""
    private var currentFormula = ""
    private var inV = false
    private var inInlineT = false
    private var inFormula = false

    init(sharedStrings: [String], maxRows: Int) {
        self.sharedStrings = sharedStrings
        self.maxRows = maxRows
    }

    func parse(data: Data) -> (rows: [[String]], totalRows: Int, maxCols: Int) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        _ = parser.parse()
        return (rows, totalRows, maxCols)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let tag = elementName.components(separatedBy: ":").last ?? elementName
        switch tag {
        case "row":
            currentRowCells.removeAll(keepingCapacity: true)
            currentColIndex = 0
        case "c":
            if let ref = attributeDict["r"] {
                currentColIndex = UniversalAttachmentEngine.excelColumnIndex(from: ref)
            }
            currentCellType = attributeDict["t"] ?? ""
            currentValue = ""
            currentFormula = ""
        case "v":
            inV = true
        case "t":
            if currentCellType == "inlineStr" {
                inInlineT = true
            }
        case "f":
            inFormula = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inV || inInlineT {
            currentValue += string
        } else if inFormula {
            currentFormula += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let tag = elementName.components(separatedBy: ":").last ?? elementName
        switch tag {
        case "v":
            inV = false
        case "t":
            inInlineT = false
        case "f":
            inFormula = false
        case "c":
            let resolved: String
            switch currentCellType {
            case "s":
                if let idx = Int(currentValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                   idx >= 0 && idx < sharedStrings.count {
                    resolved = sharedStrings[idx]
                } else {
                    resolved = currentValue
                }
            case "b":
                resolved = currentValue.trimmingCharacters(in: .whitespacesAndNewlines) == "1" ? "TRUE" : "FALSE"
            default:
                if !currentValue.isEmpty {
                    resolved = currentValue
                } else if !currentFormula.isEmpty {
                    resolved = "=\(currentFormula)"
                } else {
                    resolved = ""
                }
            }
            if !resolved.isEmpty {
                currentRowCells[currentColIndex] = resolved
            }
            currentColIndex += 1
        case "row":
            guard !currentRowCells.isEmpty else { return }
            totalRows += 1
            let highestCol = (currentRowCells.keys.max() ?? 0) + 1
            maxCols = max(maxCols, highestCol)
            if rows.count < maxRows {
                let boundedCols = min(highestCol, 60)
                var rowArr = Array(repeating: "", count: boundedCols)
                for (colIdx, val) in currentRowCells where colIdx >= 0 && colIdx < boundedCols {
                    rowArr[colIdx] = val
                }
                rows.append(rowArr)
            }
        default:
            break
        }
    }
}

private final class PptxSlideXMLParser: NSObject, XMLParserDelegate {
    private var lines: [String] = []
    private var currentPara = ""
    private var inAText = false

    func parse(data: Data) -> String {
        let parser = XMLParser(data: data)
        parser.delegate = self
        _ = parser.parse()
        return lines.joined(separator: "\n")
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let tag = elementName.components(separatedBy: ":").last ?? elementName
        if tag == "p" {
            currentPara = ""
        } else if tag == "t" {
            inAText = true
        } else if tag == "br" {
            currentPara += "\n"
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inAText {
            currentPara += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let tag = elementName.components(separatedBy: ":").last ?? elementName
        if tag == "t" {
            inAText = false
        } else if tag == "p" {
            let trimmed = currentPara.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lines.append(trimmed)
            }
            currentPara = ""
        }
    }
}
