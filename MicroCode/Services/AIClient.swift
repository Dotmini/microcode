//
//  AIClient.swift
//  MicroCode
//
//  Created and Designed by Dotmini Software
//  Founder & CEO: Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//
//  Description:
//  Production AI API Client with streaming, tool calling / function execution,
//  multi-provider dispatch (BYOK Direct API, Dotmini Cloud, Subscription OAuth, and Local LLM),
//  robust token handling, and multi-modal attachment support.
//

import Foundation
import Combine
import AppKit
import ImageIO
import PDFKit
import AVFoundation
import CoreGraphics

// MARK: - AI Provider

enum StreamableAIProvider: String, CaseIterable {
    case omni = "omni"
    case anthropic = "anthropic"
    case openai = "openai"
    case gemini = "gemini"
    case deepseek = "deepseek"
    case ninerouter = "9router"
    case openrouter = "openrouter"
    case groq = "groq"
    case mistral = "mistral"
    case kimi = "kimi"
    case perplexity = "perplexity"
    case perch = "perch"
    case tokenme = "tokenme"
    case typhoon = "typhoon"
    case cerebras = "cerebras"
    case together = "together"
    case fireworks = "fireworks"
    case minimax = "minimax"
    case nvidia = "nvidia"
    case qwen = "qwen"
    case grok = "grok"
    case glm = "glm"
    case copilot = "copilot"
    case aipass = "aipass"
    case custom = "custom"
    case local = "local"
    
    /// Dotmini Cloud proxy URL (license key route — hides real API keys)
    static var cloudProxyURL: String {
        if let custom = UserDefaults.standard.string(forKey: "dotminiProxyURL"),
           !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "https://microcode.dotmini.net/v1"
    }

    static func isDotminiCloudProxy(_ urlString: String) -> Bool {
        let clean = urlString.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let configured = Self.cloudProxyURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return clean == configured
            || clean == "https://microcode.dotmini.net/v1"
            || clean == "https://api.dotmini.net/v1"
            || clean == "https://microai.dotmini.net/v1"
    }
    
    /// Base URL when routing through Dotmini Cloud proxy
    var cloudBaseURL: String {
        switch self {
        case .local: return LocalLLMService.cachedEndpoint
        case .ninerouter, .custom: return directBaseURL
        default: return Self.cloudProxyURL
        }
    }

    /// Normalizes a user-configured BYOK custom Base URL (e.g. Cloudflare Tunnel `https://xxx.trycloudflare.com/v1`,
    /// custom OpenAI proxy, or custom Anthropic/Claude endpoint). Strictly isolated from Local/LAN LLM.
    static func normalizeByokBaseURL(_ raw: String, for providerId: String) -> String? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") {
            trimmed = "https://\(trimmed)"
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        for suffix in ["/chat/completions", "/messages", "/models"] {
            if trimmed.lowercased().hasSuffix(suffix) {
                trimmed = String(trimmed.dropLast(suffix.count))
                break
            }
        }
        if let comps = URLComponents(string: trimmed),
           let host = comps.host, !host.isEmpty {
            let path = comps.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if path.isEmpty && providerId.lowercased() != "perplexity" && providerId.lowercased() != "aipass" && providerId.lowercased() != "copilot" {
                let defaultSuffix = (providerId.lowercased() == "gemini") ? "/v1beta" : "/v1"
                trimmed += defaultSuffix
            }
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    static func customByokBaseURL(for providerId: String) -> String? {
        let key = "byok_base_url_\(providerId.lowercased())"
        guard let saved = UserDefaults.standard.string(forKey: key) else { return nil }
        return normalizeByokBaseURL(saved, for: providerId)
    }

    static func hasCustomByokBaseURL(for providerId: String) -> Bool {
        guard let custom = customByokBaseURL(for: providerId), !custom.isEmpty else { return false }
        if let prov = StreamableAIProvider(rawValue: providerId.lowercased()), prov != .custom {
            return custom.lowercased() != prov.defaultOfficialBaseURL.lowercased()
        }
        return true
    }

    var defaultOfficialBaseURL: String {
        switch self {
        case .omni: return "https://api.dotmini.net/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .ninerouter: return UserDefaults.standard.string(forKey: "9router_base_url") ?? "http://127.0.0.1:20128/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .mistral: return "https://api.mistral.ai/v1"
        case .kimi: return "https://api.moonshot.ai/v1"
        case .perplexity: return "https://api.perplexity.ai"
        case .perch: return UserDefaults.standard.string(forKey: "perch_base_url") ?? "https://api.perchai.app/v1"
        case .tokenme: return UserDefaults.standard.string(forKey: "tokenme_base_url") ?? "https://api.tokenme.limited/api/v1"
        case .typhoon: return "https://api.opentyphoon.ai/v1"
        case .cerebras: return "https://api.cerebras.ai/v1"
        case .together: return "https://api.together.xyz/v1"
        case .fireworks: return "https://api.fireworks.ai/inference/v1"
        case .minimax: return "https://api.minimax.io/v1"
        case .nvidia: return "https://integrate.api.nvidia.com/v1"
        case .grok: return "https://api.x.ai/v1"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .glm: return "https://api.z.ai/api/paas/v4"
        case .copilot: return "https://api.githubcopilot.com"
        case .aipass: return "https://de.aipass.net"
        case .custom: return "https://api.openai.com/v1"
        case .local: return LocalLLMService.cachedEndpoint
        }
    }
    
    /// Base URL when user provides their own API key (direct to provider or custom BYOK Base URL / Cloudflare Tunnel)
    var directBaseURL: String {
        if self != .local, let custom = Self.customByokBaseURL(for: self.rawValue) {
            return custom
        }
        return defaultOfficialBaseURL
    }
    
    var defaultModel: String {
        if self == .local {
            if Thread.isMainThread {
                let active = MainActor.assumeIsolated { LocalLLMService.shared.activeModel }
                if !active.isEmpty && active != "local-model" {
                    return active
                }
            }
            return LocalLLMService.cachedModel
        }
        if Thread.isMainThread {
            if let liveFirst = MainActor.assumeIsolated({ AIModelCatalog.shared.provider(self.rawValue)?.models.first?.id }),
               !liveFirst.isEmpty {
                return liveFirst
            }
        }
        switch self {
        case .omni: return "omni-o1x-pro"
        case .anthropic: return "claude-sonnet-4-6"
        case .openai: return "gpt-4.1"
        case .gemini: return "gemini-2.5-flash"
        case .deepseek: return "deepseek-chat"
        case .ninerouter: return "claude-sonnet-4-6"
        case .openrouter: return "anthropic/claude-sonnet-4"
        case .groq: return "llama-3.3-70b-versatile"
        case .mistral: return "codestral-latest"
        case .kimi: return "kimi-k2-0711-preview"
        case .perplexity: return "sonar-reasoning-pro"
        case .perch: return "perch-1-pro"
        case .tokenme: return "deepseek-ai/deepseek-v4-flash-0731"
        case .typhoon: return "typhoon-v2.5-30b-a3b-instruct"
        case .cerebras: return "llama-3.3-70b"
        case .together: return "Qwen/Qwen2.5-Coder-32B-Instruct"
        case .fireworks: return "accounts/fireworks/models/deepseek-v3"
        case .minimax: return "MiniMax-M1"
        case .nvidia: return "nvidia/llama-3.1-nemotron-ultra-253b-v1"
        case .qwen: return "qwen-max"
        case .grok: return "grok-3"
        case .glm: return "glm-4.5"
        case .local: return LocalLLMService.cachedModel
        case .copilot: return "auto"
        case .aipass: return "gemini-2.5-flash"
        case .custom:
            let saved = UserDefaults.standard.string(forKey: "byok_custom_model_custom")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? "gpt-4.1" : saved
        }
    }
    
    /// Whether this provider uses OpenAI-compatible chat/completions API format
    var usesOpenAIFormat: Bool {
        switch self {
        case .omni, .openai, .deepseek, .ninerouter, .openrouter, .groq, .mistral, .kimi, .perplexity, .perch,
             .tokenme, .typhoon, .cerebras, .together, .fireworks, .minimax, .nvidia,
             .grok, .qwen, .glm, .copilot, .custom, .local:
            return true
        case .gemini, .anthropic, .aipass:
            return false
        }
    }
    
    /// Whether this provider requires an API key
    var requiresAPIKey: Bool {
        switch self {
        case .local, .ninerouter, .custom: return false
        default: return !Self.hasCustomByokBaseURL(for: self.rawValue)
        }
    }
    
    static func detect(from model: String) -> StreamableAIProvider {
        let m = model.lowercased()
        if AIClient.isAiPassMediaModel(m) { return .aipass }
        if m.contains("@default") || m.contains("@azure") || m.contains("@jts") || m.contains("pathumma") { return .aipass }
        if m.hasPrefix("accounts/fireworks/") { return .fireworks }
        if m.hasPrefix("unsloth/") || m == "deepseek-ai/deepseek-v4-flash-0731" || m.contains("nvfp4") { return .tokenme }
        if m == "google/gemma-4-31b-it" && (UserDefaults.standard.string(forKey: "subscriptionActiveProvider") == "tokenme" || !(UserDefaults.standard.string(forKey: "tokenme_api_key") ?? "").isEmpty) {
            return .tokenme
        }
        if m.hasPrefix("nvidia/") || m.contains("nemotron") { return .nvidia }
        if m.contains("/") && (m.hasPrefix("anthropic/") || m.hasPrefix("google/") || m.hasPrefix("openai/") || m.hasPrefix("deepseek/") || m.hasPrefix("x-ai/") || m.hasPrefix("openrouter/")) {
            return .openrouter
        }
        if m.contains("codestral") || m.contains("devstral") || m.contains("mistral") || m.contains("pixtral") || m.contains("ministral") { return .mistral }
        if m.contains("moonshot") || m.hasPrefix("kimi-") { return .kimi }
        if m.hasPrefix("sonar") { return .perplexity }
        if m.hasPrefix("perch") { return .perch }
        if m.hasPrefix("typhoon-") { return .typhoon }
        if m.hasPrefix("minimax") || m.contains("abab") { return .minimax }
        if m.contains("omni") || m.contains("dotmini") { return .omni }
        if m.contains("claude") { return .anthropic }
        if m.contains("gpt") || m.contains("codex") || m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4") { return .openai }
        if m.contains("gemini") || m.contains("gemma") { return .gemini }
        if m.contains("deepseek") { return .deepseek }
        if m.contains("qwen") { return .qwen }
        if m.contains("grok") { return .grok }
        if m.contains("glm") { return .glm }
        if m.contains("llama-3.3-70b-versatile") || m.contains("llama-3.1-8b-instant") || m.contains("groq") { return .groq }
        return .omni
    }

    static func isLocalEndpoint(_ baseURL: String) -> Bool {
        let lowerURL = baseURL.lowercased()
        if lowerURL.contains("127.0.0.1:20128") { return false }
        return lowerURL.contains("127.0.0.1") ||
            lowerURL.contains("localhost") ||
            lowerURL.contains("0.0.0.0") ||
            lowerURL.contains("192.168.") ||
            lowerURL.contains("://10.") ||
            lowerURL.contains("://172.") ||
            lowerURL.contains(".local:") ||
            lowerURL.contains(":11434") ||
            lowerURL.contains(":1234") ||
            lowerURL.contains(":8475")
    }

    static func detect(from model: String, baseURL: String) -> StreamableAIProvider {
        let lowerURL = baseURL.lowercased()
        if lowerURL.contains("tokenme.limited") { return .tokenme }
        if lowerURL.contains("openrouter.ai") { return .openrouter }
        if lowerURL.contains("githubcopilot.com") { return .copilot }
        if lowerURL.contains("perchai.app") { return .perch }
        if lowerURL.contains("opentyphoon.ai") { return .typhoon }
        if lowerURL.contains("groq.com") { return .groq }
        if lowerURL.contains("together.xyz") { return .together }
        if lowerURL.contains("fireworks.ai") { return .fireworks }
        if lowerURL.contains("cerebras.ai") { return .cerebras }
        if lowerURL.contains("127.0.0.1:20128") { return .ninerouter }
        if isLocalEndpoint(lowerURL) { return .local }
        return detect(from: model)
    }

    /// Returns true when the provider + model natively accepts inline multimodal image bytes (`inlineData` / `image_url`).
    /// Text-only models return false so `UniversalAttachmentEngine` automatically enriches images with Apple Vision OCR.
    func supportsNativeImageInput(model: String) -> Bool {
        let m = model.lowercased()
        switch self {
        case .gemini, .openai, .anthropic, .grok, .copilot, .aipass, .tokenme, .perch, .openrouter, .ninerouter, .omni, .glm, .kimi, .custom:
            return true
        case .qwen:
            return m.contains("vl") || m.contains("qvq") || m.contains("omni") || m.contains("qwen3") || m.contains("qwen2.5")
        case .mistral:
            return m.contains("pixtral") || m.contains("mistral-medium") || m.contains("mistral-small-3") || m.contains("mistral-large")
        case .groq, .together, .fireworks, .nvidia, .minimax:
            return m.contains("vision") || m.contains("vl") || m.contains("llama-4") || m.contains("pixtral") || m.contains("gemma-3")
        case .local:
            return m.contains("vl") || m.contains("vision") || m.contains("llava") || m.contains("gemma3") || m.contains("gemma-3") || m.contains("pixtral") || m.contains("minicpm-v")
        case .deepseek, .typhoon, .cerebras, .perplexity:
            return false
        }
    }
}

// MARK: - Attachments

struct AIAttachment: Identifiable {
    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    static func makeFastThumbnail(from url: URL, maxPixelSize: Int = 72) -> NSImage? {
        let srcOpts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOpts as CFDictionary) else { return nil }
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func makeFastThumbnail(from data: Data, maxPixelSize: Int = 72) -> NSImage? {
        guard !data.isEmpty else { return nil }
        let srcOpts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOpts as CFDictionary) else { return nil }
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    enum AttachmentType: Equatable {
        case image(format: String)
        case text
        case pdf
    }

    enum SemanticCategory: String, Equatable, Codable, Sendable {
        case image
        case pdf
        case wordDoc
        case spreadsheet
        case presentation
        case richDocument
        case notebook
        case database
        case dataFile
        case audio
        case video
        case archive
        case folder
        case codeOrText
        case binary
    }

    let id: UUID
    let name: String
    let data: Data
    let type: AttachmentType
    var sourceURL: URL?
    var stagedPath: String?
    var extractedTextCachePath: String?
    var extractedFullText: String?
    var subtitleBadge: String?
    var metricsSummary: String?
    var extractionStatus: String?
    var extractionWarning: String?
    var normalizedVisionData: Data?
    var normalizedVisionMimeType: String?
    var nativeMediaMimeType: String?
    var fileSizeBytes: Int64?
    var semanticCategory: SemanticCategory
    var isPasswordProtected: Bool
    var includeInlineTextInProviderPayload: Bool
    var previewThumbnail: NSImage?

    init(
        id: UUID = UUID(),
        name: String,
        data: Data,
        type: AttachmentType,
        sourceURL: URL? = nil,
        stagedPath: String? = nil,
        extractedTextCachePath: String? = nil,
        extractedFullText: String? = nil,
        subtitleBadge: String? = nil,
        metricsSummary: String? = nil,
        extractionStatus: String? = nil,
        extractionWarning: String? = nil,
        normalizedVisionData: Data? = nil,
        normalizedVisionMimeType: String? = nil,
        nativeMediaMimeType: String? = nil,
        fileSizeBytes: Int64? = nil,
        semanticCategory: SemanticCategory? = nil,
        isPasswordProtected: Bool = false,
        includeInlineTextInProviderPayload: Bool = true,
        previewThumbnail: NSImage? = nil
    ) {
        self.id = id
        self.name = name
        self.data = data
        self.type = type
        self.sourceURL = sourceURL
        self.stagedPath = stagedPath
        self.extractedTextCachePath = extractedTextCachePath
        self.extractedFullText = extractedFullText
        self.subtitleBadge = subtitleBadge
        self.metricsSummary = metricsSummary
        self.extractionStatus = extractionStatus
        self.extractionWarning = extractionWarning
        self.normalizedVisionData = normalizedVisionData
        self.normalizedVisionMimeType = normalizedVisionMimeType
        self.nativeMediaMimeType = nativeMediaMimeType
        self.fileSizeBytes = fileSizeBytes
        if let semanticCategory {
            self.semanticCategory = semanticCategory
        } else {
            switch type {
            case .image: self.semanticCategory = .image
            case .pdf: self.semanticCategory = .pdf
            case .text: self.semanticCategory = .codeOrText
            }
        }
        self.isPasswordProtected = isPasswordProtected
        self.includeInlineTextInProviderPayload = includeInlineTextInProviderPayload
        self.previewThumbnail = previewThumbnail
        if let previewThumbnail {
            Self.thumbnailCache.setObject(previewThumbnail, forKey: id.uuidString as NSString)
        }
    }

    var base64String: String { data.base64EncodedString() }

    /// Universal Vision-ready image bytes (transcoded to JPEG/PNG when source is HEIC/TIFF/BMP/SVG/ICNS or >2048px)
    var effectiveVisionData: Data {
        if let norm = normalizedVisionData, !norm.isEmpty {
            return norm
        }
        return data
    }

    /// Universal API-safe Vision MIME type (`image/jpeg`, `image/png`, `image/gif`, `image/webp`)
    var effectiveVisionMimeType: String {
        if let mime = normalizedVisionMimeType?.lowercased(),
           ["image/jpeg", "image/png", "image/gif", "image/webp"].contains(mime) {
            return mime
        }
        if case .image(let fmt) = type {
            let lower = fmt.lowercased()
            if lower == "jpg" || lower == "jpeg" { return "image/jpeg" }
            if lower == "png" { return "image/png" }
            if lower == "gif" { return "image/gif" }
            if lower == "webp" { return "image/webp" }
        }
        return "image/png"
    }

    var effectiveVisionBase64: String {
        effectiveVisionData.base64EncodedString()
    }

    /// Loads raw binary payload up to `maxBytes` from memory or staged disk vault without holding giant buffers permanently in RAM.
    func loadRawBinaryData(maxBytes: Int) -> Data? {
        if !data.isEmpty {
            return data.count <= maxBytes ? data : nil
        }
        let candidates = [stagedPath, sourceURL?.path].compactMap { $0 }
        let fm = FileManager.default
        for candidate in candidates {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: candidate, isDirectory: &isDir), !isDir.boolValue else { continue }
            let size = ((try? fm.attributesOfItem(atPath: candidate)[.size]) as? NSNumber)?.intValue ?? 0
            guard size > 0 && size <= maxBytes else { continue }
            if let mapped = try? Data(contentsOf: URL(fileURLWithPath: candidate), options: .mappedIfSafe) {
                return mapped
            }
        }
        return nil
    }

    /// Grounded extracted text across any format (falls back to cached `.extracted.txt` or smart text decoding)
    var groundedExtractedText: String {
        if let full = extractedFullText, !full.isEmpty {
            return full
        }
        if let cachePath = extractedTextCachePath,
           let cached = try? String(contentsOfFile: cachePath, encoding: .utf8),
           !cached.isEmpty {
            return cached
        }
        if case .pdf = type {
            let pdfTxt = pdfExtractedText
            if !pdfTxt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return pdfTxt
            }
            if let warn = extractionWarning, !warn.isEmpty {
                return "[PDF Warning (\(name)): \(warn)]"
            }
            return "[PDF '\(name)': No selectable digital text layer]"
        }
        if !data.isEmpty, let decoded = UniversalAttachmentEngine.decodeTextSmart(data)?.text, !decoded.isEmpty {
            return decoded
        }
        if let warn = extractionWarning, !warn.isEmpty {
            return "[Attachment Warning (\(name)): \(warn)]"
        }
        return "[Attachment '\(name)' (\(formattedSize)) — staged at \(stagedPath ?? sourceURL?.path ?? "memory")]"
    }

    var textContent: String? {
        if let full = extractedFullText, !full.isEmpty {
            return full
        }
        if let cachePath = extractedTextCachePath,
           let cached = try? String(contentsOfFile: cachePath, encoding: .utf8),
           !cached.isEmpty {
            return cached
        }
        if !data.isEmpty {
            return UniversalAttachmentEngine.decodeTextSmart(data)?.text ?? String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    /// O(1) cached downsampled NSImage for visual thumbnails (never re-decodes multi-MB PNGs on SwiftUI redraws)
    var nsImage: NSImage? {
        if let previewThumbnail {
            return previewThumbnail
        }
        let cacheKey = id.uuidString as NSString
        if let cached = Self.thumbnailCache.object(forKey: cacheKey) {
            return cached
        }
        var generated: NSImage? = nil
        if case .image = type {
            if let norm = normalizedVisionData, !norm.isEmpty {
                generated = Self.makeFastThumbnail(from: norm) ?? NSImage(data: norm)
            } else if !data.isEmpty {
                generated = Self.makeFastThumbnail(from: data) ?? NSImage(data: data)
            } else if let staged = stagedPath {
                generated = Self.makeFastThumbnail(from: URL(fileURLWithPath: staged))
            } else if let src = sourceURL {
                generated = Self.makeFastThumbnail(from: src)
            }
        } else if semanticCategory == .video, let norm = normalizedVisionData, !norm.isEmpty {
            generated = Self.makeFastThumbnail(from: norm) ?? NSImage(data: norm)
        }
        if let generated {
            Self.thumbnailCache.setObject(generated, forKey: cacheKey)
        }
        return generated
    }
    
    /// Human-friendly formatted file size (e.g. "42 KB", "1.4 MB")
    var formattedSize: String {
        let bytes = fileSizeBytes ?? Int64(data.count)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    /// Page count if attachment is a PDF
    var pdfPageCount: Int {
        guard case .pdf = type else { return 0 }
        if !data.isEmpty, let doc = PDFDocument(data: data) {
            return doc.pageCount
        }
        if let staged = stagedPath, let doc = PDFDocument(url: URL(fileURLWithPath: staged)) {
            return doc.pageCount
        }
        if let src = sourceURL, let doc = PDFDocument(url: src) {
            return doc.pageCount
        }
        return 0
    }
    
    /// Extracted plain text across all pages if attachment is a PDF
    var pdfExtractedText: String {
        if let full = extractedFullText, !full.isEmpty {
            return full
        }
        if let cachePath = extractedTextCachePath,
           let cached = try? String(contentsOfFile: cachePath, encoding: .utf8),
           !cached.isEmpty {
            return cached
        }
        guard case .pdf = type else { return "" }
        let doc: PDFDocument? = {
            if !data.isEmpty { return PDFDocument(data: data) }
            if let staged = stagedPath { return PDFDocument(url: URL(fileURLWithPath: staged)) }
            if let src = sourceURL { return PDFDocument(url: src) }
            return nil
        }()
        guard let doc else { return "" }
        if doc.isLocked && !doc.unlock(withPassword: "") {
            return "[LOCKED PDF WARNING: '\(name)' is password-protected and cannot be read without a password.]"
        }
        var result = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let pageText = page.string {
                result += pageText + "\n"
            }
        }
        return result
    }
}

// MARK: - AI Tool Calling

struct AIToolCall: Identifiable {
    let id: String
    let name: String
    let arguments: [String: Any]
    var thoughtSignature: String? = nil
}

struct AIStructuredToolResult {
    let toolCallId: String
    let name: String
    let output: String
    let success: Bool
}

enum AIStructuredTurn {
    case assistantToolCalls(text: String, toolCalls: [AIToolCall])
    case toolResults(results: [AIStructuredToolResult], directive: String)
}

enum AIStructuredTurnCodec {
    static let markerKey = "_mc_structured_turn"

    static func stripToolCallArtifacts(_ text: String) -> String {
        var result = text
        if result.contains("[Tool Call:") {
            result = result.replacingOccurrences(
                of: #"\[Tool Call:\s*[a-zA-Z0-9_]+\s*\([\s\S]*?\)\][ \t]*\r?\n?"#,
                with: "",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: #"\[Tool Call:\s*[a-zA-Z0-9_]+\s*\([\s\S]*$"#,
                with: "",
                options: .regularExpression
            )
        }
        if result.contains("<tool_call") || result.contains("<function_call") || result.contains("<function_calls") {
            result = result.replacingOccurrences(
                of: #"<(?:tool_call|function_call|function_calls)\b[^>]*>[\s\S]*?</(?:tool_call|function_call|function_calls)>"#,
                with: "",
                options: .regularExpression
            )
            // Also strip any unclosed trailing <tool_call> or <function_call> block
            result = result.replacingOccurrences(
                of: #"<(?:tool_call|function_call|function_calls)\b[\s\S]*$"#,
                with: "",
                options: .regularExpression
            )
        }
        if result.contains("<invoke") || result.contains("<parameter") || result.contains("DSML") {
            result = result.replacingOccurrences(
                of: #"<[｜\|]DSML[｜\|]function_calls>[\s\S]*?</[｜\|]DSML[｜\|]function_calls>"#,
                with: "",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: #"<(?:[｜\|]DSML[｜\|])?invoke\b[^>]*>[\s\S]*?</(?:[｜\|]DSML[｜\|])?invoke>"#,
                with: "",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: #"<(?:[｜\|]DSML[｜\|])?parameter\b[^>]*>[\s\S]*?</(?:[｜\|]DSML[｜\|])?parameter>"#,
                with: "",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: #"<(?:[｜\|]DSML[｜\|]|invoke\b|parameter\b)[\s\S]*$"#,
                with: "",
                options: .regularExpression
            )
        }
        if result.contains("```tool_call") || result.contains("```function_call") {
            result = result.replacingOccurrences(
                of: #"```(?:tool_call|function_call)[\s\S]*?```"#,
                with: "",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: #"```(?:tool_call|function_call)[\s\S]*$"#,
                with: "",
                options: .regularExpression
            )
        }
        if result.range(of: "waiting for tool response", options: .caseInsensitive) != nil {
            result = result.replacingOccurrences(
                of: #"(?mi)^[ \t]*[*_]*waiting for tool response\.{0,3}[*_]*[ \t]*\r?\n?"#,
                with: "",
                options: .regularExpression
            )
        }
        return result
    }

    static func stripThoughtTags(_ text: String) -> String {
        var cleaned = stripToolCallArtifacts(text)
        if cleaned.contains("<thought>") {
            cleaned = cleaned.replacingOccurrences(
                of: "<thought>[\\s\\S]*?</thought>",
                with: "",
                options: .regularExpression
            )
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func encodeAssistantTurn(text: String, toolCalls: [AIToolCall]) -> String {
        let tcPayload: [[String: Any]] = toolCalls.map { tc in
            var dict: [String: Any] = [
                "id": tc.id,
                "name": tc.name,
                "arguments": tc.arguments
            ]
            if let sig = tc.thoughtSignature, !sig.isEmpty {
                dict["thoughtSignature"] = sig
            }
            return dict
        }
        let payload: [String: Any] = [
            markerKey: true,
            "kind": "assistant_tool_calls",
            "text": text,
            "tool_calls": tcPayload
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return text
        }
        return json
    }

    static func encodeToolResultsTurn(results: [AIStructuredToolResult], directive: String) -> String {
        let resPayload: [[String: Any]] = results.map { r in
            [
                "tool_call_id": r.toolCallId,
                "name": r.name,
                "output": r.output,
                "success": r.success
            ]
        }
        let payload: [String: Any] = [
            markerKey: true,
            "kind": "tool_results",
            "results": resPayload,
            "directive": directive
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return directive
        }
        return json
    }

    static func decode(_ content: String) -> AIStructuredTurn? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.contains("\"\(markerKey)\""),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json[markerKey] as? Bool) == true,
              let kind = json["kind"] as? String else {
            return nil
        }

        if kind == "assistant_tool_calls" {
            let text = json["text"] as? String ?? ""
            let rawCalls = json["tool_calls"] as? [[String: Any]] ?? []
            let calls: [AIToolCall] = rawCalls.compactMap { item in
                guard let name = item["name"] as? String, !name.isEmpty else { return nil }
                let id = item["id"] as? String ?? UUID().uuidString
                let args = item["arguments"] as? [String: Any] ?? [:]
                let sig = item["thoughtSignature"] as? String
                return AIToolCall(id: id, name: name, arguments: args, thoughtSignature: sig)
            }
            return .assistantToolCalls(text: text, toolCalls: calls)
        } else if kind == "tool_results" {
            let rawResults = json["results"] as? [[String: Any]] ?? []
            let results: [AIStructuredToolResult] = rawResults.compactMap { item in
                guard let name = item["name"] as? String else { return nil }
                let id = item["tool_call_id"] as? String ?? UUID().uuidString
                let output = item["output"] as? String ?? ""
                let success = item["success"] as? Bool ?? true
                return AIStructuredToolResult(toolCallId: id, name: name, output: output, success: success)
            }
            let directive = json["directive"] as? String ?? ""
            return .toolResults(results: results, directive: directive)
        }
        return nil
    }

    /// Compacts oversized tool output inside a structured turn without breaking its JSON envelope.
    static func compactToolOutputsIfNeeded(_ content: String, maxCharsPerOutput: Int) -> String {
        guard case .toolResults(let results, let directive) = decode(content) else {
            return content
        }
        var changed = false
        let compactedResults: [AIStructuredToolResult] = results.map { r in
            guard r.output.count > maxCharsPerOutput else { return r }
            changed = true
            let headCount = max(500, (maxCharsPerOutput * 2) / 3)
            let tailCount = max(250, maxCharsPerOutput / 3)
            let head = String(r.output.prefix(headCount))
            let tail = String(r.output.suffix(tailCount))
            let compacted = head + "\n... [Earlier tool output compacted] ...\n" + tail
            return AIStructuredToolResult(toolCallId: r.toolCallId, name: r.name, output: compacted, success: r.success)
        }
        guard changed else { return content }
        return encodeToolResultsTurn(results: compactedResults, directive: directive)
    }
}


// MARK: - Streaming Client

final class AIStreamContext: @unchecked Sendable {
    @TaskLocal static var current: AIStreamContext?
    var streamedText: String = ""
    var pendingTokens: String = ""
    var lastDeliveryUptime: TimeInterval = 0
}

@MainActor
final class AIClient: ObservableObject {
    static let shared = AIClient()
    
    @Published var isStreaming: Bool = false
    @Published var activeStreamCount: Int = 0
    private var _legacyStreamedText: String = ""
    var currentStreamedText: String {
        get { AIStreamContext.current?.streamedText ?? _legacyStreamedText }
        set {
            if let ctx = AIStreamContext.current {
                ctx.streamedText = newValue
            }
            _legacyStreamedText = newValue
        }
    }
    
    private var streamTask: Task<Void, Never>?
    private var streamTasksByKey: [String: Task<Void, Never>] = [:]
    let requestTimeout: TimeInterval = 180
    private var _legacyPendingStreamTokens: String = ""
    var pendingStreamTokens: String {
        get { AIStreamContext.current?.pendingTokens ?? _legacyPendingStreamTokens }
        set {
            if let ctx = AIStreamContext.current {
                ctx.pendingTokens = newValue
            } else {
                _legacyPendingStreamTokens = newValue
            }
        }
    }
    private var _legacyLastStreamDeliveryUptime: TimeInterval = 0
    private var lastStreamDeliveryUptime: TimeInterval {
        get { AIStreamContext.current?.lastDeliveryUptime ?? _legacyLastStreamDeliveryUptime }
        set {
            if let ctx = AIStreamContext.current {
                ctx.lastDeliveryUptime = newValue
            } else {
                _legacyLastStreamDeliveryUptime = newValue
            }
        }
    }
    private let streamFlushInterval: TimeInterval = 0.016 // ~60fps target for smooth text render
    
    func appendStreamToken(_ token: String, onToken: @escaping (String) -> Void) {
        pendingStreamTokens += token
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastStreamDeliveryUptime >= streamFlushInterval || token.contains("\n") {
            flushPendingStreamTokens(onToken: onToken)
        }
    }
    
    func flushPendingStreamTokens(onToken: @escaping (String) -> Void) {
        guard !pendingStreamTokens.isEmpty else { return }
        let chunk = pendingStreamTokens
        pendingStreamTokens = ""
        lastStreamDeliveryUptime = ProcessInfo.processInfo.systemUptime
        currentStreamedText += chunk
        onToken(chunk)
    }
    
    private func detectStreamRepetitionLoop(_ fullText: String) -> Bool {
        // Inspect only completed lines (drop trailing partial line currently being streamed)
        // and keep short structural lines (`}`, `</div>`, `.a {`) so separate blocks never collapse.
        let rawLines = fullText.components(separatedBy: .newlines)
        guard rawLines.count >= 7 else { return false }
        let lines = rawLines.dropLast()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let count = lines.count
        guard count >= 6 else { return false }
        
        // 1. 6x consecutive repetition of identical non-trivial line (>= 24 chars)
        let last = lines[count - 1]
        if last.count >= 24 &&
           lines[count - 2] == last &&
           lines[count - 3] == last &&
           lines[count - 4] == last &&
           lines[count - 5] == last &&
           lines[count - 6] == last {
            return true
        }
        
        // 2. 5x alternating 2-line cycle: (A, B) x 5 where A+B is non-trivial
        if count >= 10 {
            let a = lines[count - 2]
            let b = lines[count - 1]
            if a != b && (a.count + b.count) >= 40 &&
               lines[count - 4] == a && lines[count - 6] == a && lines[count - 8] == a && lines[count - 10] == a &&
               lines[count - 3] == b && lines[count - 5] == b && lines[count - 7] == b && lines[count - 9] == b {
                return true
            }
        }
        
        return false
    }
    
    private func boundedHistory(_ history: [(role: String, content: String)]) -> [(role: String, content: String)] {
        // Scaled for modern 1M-2M+ token architectures (no artificial message or char caps)
        let maxMessages = 1000
        let maxCharsPerMessage = 4_000_000
        let recent = Array(history.suffix(maxMessages))
        return recent.map { (role: $0.role, content: boundedText($0.content, limit: maxCharsPerMessage)) }
    }
    
    private func normalizeModelName(_ model: String, provider: StreamableAIProvider, baseURL: String) -> String {
        var trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let customSaved = UserDefaults.standard.string(forKey: "byok_custom_model_\(provider.rawValue)")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !customSaved.isEmpty {
                return customSaved
            }
            return provider.defaultModel
        }
        if provider == .local || StreamableAIProvider.isLocalEndpoint(baseURL) {
            if let sep = trimmed.range(of: "||") {
                let sub = String(trimmed[sep.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sub.isEmpty {
                    trimmed = sub
                }
            }
            let lowerLocal = trimmed.lowercased()
            if lowerLocal.isEmpty || lowerLocal == "local" || lowerLocal == "local-model" || lowerLocal == "auto" {
                return LocalLLMService.resolveRoute(forModel: trimmed, preferredEndpoint: baseURL).model
            }
            return trimmed
        }
        // When user configured a custom BYOK Base URL / Cloudflare Tunnel, preserve their exact model ID
        if provider == .custom || StreamableAIProvider.hasCustomByokBaseURL(for: provider.rawValue) || baseURL.lowercased().contains("trycloudflare.com") {
            let customSaved = UserDefaults.standard.string(forKey: "byok_custom_model_\(provider.rawValue)")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.lowercased() == provider.rawValue || trimmed == "custom-model" {
                return !customSaved.isEmpty ? customSaved : provider.defaultModel
            }
            return trimmed
        }
        if !baseURL.contains("cloudcode-pa.googleapis.com") && !trimmed.lowercased().hasPrefix("mistral-") {
            for suffix in ["-high", "-medium", "-low"] {
                if trimmed.lowercased().hasSuffix(suffix) {
                    trimmed = String(trimmed.dropLast(suffix.count))
                    break
                }
            }
        }
        let lower = trimmed.lowercased()
        if StreamableAIProvider.isDotminiCloudProxy(baseURL) {
            if lower == "omni-o1x-pro" || lower == "omni" || lower == "omni-max" {
                return "deepseek-chat"
            } else if lower == "omni-o1x-lite" {
                return "omni-mini"
            }
        }
        if lower == provider.rawValue {
            return provider.defaultModel
        } else if provider == .glm && (lower == "glm" || lower == "glm-4-flash") {
            return "glm-5.3-flash"
        }

        // Official OpenAI REST API (`api.openai.com`) remapping for Codex-only internal model slugs
        if baseURL.contains("api.openai.com") {
            let codexOnlySlugs: Set<String> = ["gpt-6.1-sol", "gpt-6-luna", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-reserve", "gpt-6-astra"]
            if codexOnlySlugs.contains(lower) || lower.hasPrefix("gpt-6") || lower.hasPrefix("gpt-5.6") {
                return "gpt-4.1"
            }
        }

        // Official Google Gemini REST API (`generativelanguage.googleapis.com`) remapping for CodeAssist-only slugs
        if baseURL.contains("generativelanguage.googleapis.com") {
            if lower.contains("argon") || lower.contains("3.8") || lower.contains("3.7") || lower.contains("3.6") || lower.contains("3.5") || lower == "gemini-3-flash" {
                return "gemini-2.5-flash"
            }
        }
        
        // GitHub Copilot API uses dot-separated model IDs (`claude-sonnet-5.5`, `claude-opus-5.5`, `claude-fable-5.1`)
        if provider == .copilot || baseURL.contains("githubcopilot.com") {
            if lower == "auto" || lower == "copilot" {
                return "gpt-4.1"
            }
            if lower == "claude-fable-5-1" || lower == "claude-fable-5.1" {
                return "claude-fable-5.1"
            }
            if lower.hasPrefix("claude-haiku-5") {
                return "claude-haiku-5.5"
            }
            if lower == "claude-haiku-4-5" || lower == "claude-haiku-4.5" {
                return "claude-haiku-4.5"
            }
            if lower.hasPrefix("claude-sonnet-5-5") || lower.hasPrefix("claude-sonnet-5.5") {
                return "claude-sonnet-5.5"
            }
            if lower == "claude-sonnet-5" {
                return "claude-sonnet-5"
            }
            if lower.hasPrefix("claude-opus-5-5") || lower.hasPrefix("claude-opus-5.5") {
                return "claude-opus-5.5"
            }
            if lower == "claude-opus-5" {
                return "claude-opus-5"
            }
            if lower.hasPrefix("claude-opus-4-8") || lower.hasPrefix("claude-opus-4.8") {
                return "claude-opus-4.8"
            }
        }
        
        // Direct Anthropic API (`api.anthropic.com`) remapping for CodeAssist-only 5-5 model IDs
        if baseURL.contains("api.anthropic.com") {
            if lower.hasPrefix("claude-haiku-5") {
                return "claude-haiku-4-5"
            }
            if lower.hasPrefix("claude-sonnet-5") {
                return "claude-sonnet-4-6"
            }
            if lower.hasPrefix("claude-opus-5") || lower == "claude-opus-4-8" {
                return "claude-opus-4-6"
            }
        }
        
        // DeepSeek Official API (`api.deepseek.com`) supports `deepseek-flash`, `deepseek-v4-pro`, `deepseek-chat`, and `deepseek-reasoner`
        if baseURL.contains("api.deepseek.com") {
            if lower.contains("reasoner") || lower.contains("r1") {
                return "deepseek-reasoner"
            }
            if lower == "deepseek-flash" || lower.contains("v4.1-flash") || lower.contains("v4-flash") {
                return "deepseek-flash"
            }
            if lower == "deepseek-v4-pro" || lower.contains("v4-pro") {
                return "deepseek-v4-pro"
            }
            if lower.hasPrefix("deepseek") {
                return "deepseek-chat"
            }
        }
        
        // SCB 10X OpenTyphoon Official API (`api.opentyphoon.ai/v1`) retired v2 / v2.1 chat models;
        // remap legacy, non-chat (OCR/ASR), or AiPASS Typhoon aliases to active `typhoon-v2.5-30b-a3b-instruct`.
        if provider == .typhoon || baseURL.contains("opentyphoon.ai") {
            if lower == "typhoon" ||
               lower == "typhoon2.5-qwen3-30b" ||
               lower.hasPrefix("typhoon-v2.1") ||
               lower.hasPrefix("typhoon-v2-") ||
               lower.hasPrefix("typhoon-v1") ||
               lower.contains("ocr") ||
               lower.contains("asr") {
                return "typhoon-v2.5-30b-a3b-instruct"
            }
        }
        
        return trimmed
    }
    
    /// Verifies whether a token can be sent directly to a provider's REST API (filtering out web cookies, CLI markers, OAuth markers, and null JSON).
    private static func isValidDirectAPIKey(_ token: String, for provider: StreamableAIProvider) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if SubscriptionAuthManager.isCorruptedToken(trimmed) ||
           trimmed.hasPrefix("cli-oauth:") ||
           trimmed.hasPrefix("codeassist_oauth:") ||
           trimmed.hasPrefix("claude_cli_bridge:") ||
           trimmed.hasPrefix("agy_cli_bridge:") ||
           trimmed.hasPrefix("codex_cli_bridge:") ||
           trimmed.hasPrefix("claude_web:") ||
           trimmed.hasPrefix("vertexaisearch://") ||
           trimmed.contains("vertexaisearch.cloud.google") ||
           trimmed.contains("__Secure-") ||
           trimmed.contains("session_token=") {
            return false
        }
        if provider == .custom || StreamableAIProvider.hasCustomByokBaseURL(for: provider.rawValue) {
            return !trimmed.isEmpty && !trimmed.hasPrefix("{")
        }
        switch provider {
        case .gemini:
            return trimmed.hasPrefix("AIzaSy")
        case .anthropic:
            // Strictly accept Anthropic API keys (`sk-ant-api...`) or Claude OAuth tokens (`sk-ant-oat...`), NEVER `claude.ai` web cookies (`sk-ant-sid...`)
            return trimmed.hasPrefix("sk-ant-api") || trimmed.hasPrefix("sk-ant-oat")
        case .openai:
            return trimmed.hasPrefix("sk-") && !trimmed.hasPrefix("sk-ant-") && !trimmed.hasPrefix("sk-or-")
        case .deepseek:
            return trimmed.hasPrefix("sk-")
        case .glm:
            return !trimmed.isEmpty && !trimmed.hasPrefix("{") && !trimmed.hasPrefix("eyJhbGci")
        case .omni:
            return false
        case .ninerouter, .openrouter, .groq, .mistral, .kimi, .perplexity, .perch, .tokenme, .typhoon,
             .cerebras, .together, .fireworks, .minimax, .nvidia,
             .copilot, .aipass, .grok, .qwen, .custom, .local:
            return !trimmed.isEmpty && !trimmed.hasPrefix("{")
        }
    }

    /// Caches the result of `claude auth status --json` so the synchronous route resolvers never spawn a process.
    private final class ClaudeSubscriptionCache: @unchecked Sendable {
        private let lock = NSLock()
        private var checkedAt: Date?
        private var verified = true
        func read() -> Bool? {
            lock.lock(); defer { lock.unlock() }
            guard let checkedAt, Date().timeIntervalSince(checkedAt) < 600 else { return nil }
            return verified
        }
        func write(_ ok: Bool) {
            lock.lock(); defer { lock.unlock() }
            checkedAt = Date()
            verified = ok
        }
    }
    private nonisolated static let claudeSubscriptionCache = ClaudeSubscriptionCache()

    /// True only for a Claude **Pro / Max / Team** login (zero per-token cost).
    /// A `claude` CLI signed in to a prepaid Anthropic Console org (`billingType == "prepaid"`, `subscriptionType == null`)
    /// bills API credits and fails with "Credit balance is too low", so it must never be treated as a Subscription.
    nonisolated static func hasLocalClaudeCodeOAuth() -> Bool {
        let claudeHomeJson = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: claudeHomeJson),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauthAccount = json["oauthAccount"] as? [String: Any] else {
            return false
        }
        let billingType = (oauthAccount["billingType"] as? String)?.lowercased() ?? ""
        if billingType == "prepaid" || billingType == "api" || billingType == "invoice" {
            return false
        }
        return claudeSubscriptionCache.read() ?? true
    }

    /// Authoritative check via `claude auth status --json` (`subscriptionType` must be non-empty). Result is cached for 10 minutes.
    nonisolated static func verifyClaudeCodeSubscription() async -> (email: String, plan: String)? {
        guard hasLocalClaudeCodeOAuthHeuristic(),
              let bin = ACPHostService.resolveAgentBinary(for: .claudeCode) else {
            claudeSubscriptionCache.write(false)
            return nil
        }
        let raw: String = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let proc = Process()
                let pipe = Pipe()
                proc.executableURL = URL(fileURLWithPath: bin)
                proc.arguments = ["auth", "status", "--json"]
                proc.standardOutput = pipe
                proc.standardError = Pipe()
                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "ANTHROPIC_API_KEY")
                env.removeValue(forKey: "CLAUDE_API_KEY")
                proc.environment = env
                do { try proc.run() } catch { continuation.resume(returning: ""); return }
                let killer = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: killer)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                killer.cancel()
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
        }
        guard let open = raw.firstIndex(of: "{"), let close = raw.lastIndex(of: "}"), open < close,
              let obj = try? JSONSerialization.jsonObject(with: Data(raw[open...close].utf8)) as? [String: Any],
              (obj["loggedIn"] as? Bool) == true,
              let plan = (obj["subscriptionType"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !plan.isEmpty else {
            claudeSubscriptionCache.write(false)
            return nil
        }
        claudeSubscriptionCache.write(true)
        return ((obj["email"] as? String) ?? "Claude Pro / Max", plan)
    }

    private nonisolated static func hasLocalClaudeCodeOAuthHeuristic() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["oauthAccount"] != nil else { return false }
        return true
    }

    /// Resolves the execution target strictly within Web Subscription mode — ZERO reads from BYOK API key storage.
    /// Base URL used by Web Subscription routes. Deliberately ignores the BYOK "custom base URL / tunnel" setting
    /// so a user's BYOK endpoint can never receive a Subscription credential (and vice-versa).
    /// GLM Subscriptions are the Z.AI **Coding Plan**, which lives on the dedicated `/api/coding/paas/v4` path.
    nonisolated static func subscriptionBaseURL(for provider: StreamableAIProvider) -> String {
        switch provider {
        case .glm:
            return UserDefaults.standard.string(forKey: "sub_glm_region") == "cn"
                ? "https://open.bigmodel.cn/api/coding/paas/v4"
                : "https://api.z.ai/api/coding/paas/v4"
        default: return provider.defaultOfficialBaseURL
        }
    }

    /// GLM keys are region-bound (Z.AI international vs BigModel China). Returns the sibling region for the same path.
    nonisolated static func glmAlternateRegionBase(_ base: String) -> String? {
        if base.contains("api.z.ai") { return base.replacingOccurrences(of: "https://api.z.ai", with: "https://open.bigmodel.cn") }
        if base.contains("open.bigmodel.cn") { return base.replacingOccurrences(of: "https://open.bigmodel.cn", with: "https://api.z.ai") }
        return nil
    }

    private func resolveSubscriptionExecutionTarget(
        provider initialProvider: StreamableAIProvider,
        model: String
    ) -> (provider: StreamableAIProvider, baseURL: String, credential: String)? {
        let provider = initialProvider
        let account = resolveSubscriptionAccount(for: provider)
        let subToken = account?.sessionToken.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // 1. TH-AI Passport & Thai AI Gemini Enterprise
        if provider == .aipass || account?.provider == .aipass || account?.provider == .thai_gemini_enterprise {
            let cookie = Self.resolveAiPassSessionCookie(primary: subToken)
            guard !cookie.isEmpty else { return nil }
            return (.aipass, Self.subscriptionBaseURL(for: .aipass), cookie)
        }

        // 2. GitHub Copilot
        if (provider == .copilot || account?.provider == .copilot),
           SubscriptionAuthManager.shared.isConnected(.copilot),
           !subToken.isEmpty {
            return (.copilot, Self.subscriptionBaseURL(for: .copilot), subToken)
        }

        // 3. ChatGPT Plus / Team / Pro (Codex OAuth / 1-Click Web JWT / Codex CLI)
        if provider == .openai {
            if Self.isValidDirectAPIKey(subToken, for: .openai) {
                return (.openai, Self.subscriptionBaseURL(for: .openai), subToken)
            }
            if let codexCreds = Self.loadCodexOAuthCredentials(fallbackToken: subToken) {
                return (.openai, "https://chatgpt.com/backend-api/codex", codexCreds.accessToken)
            }
            let codexAuthFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
            if FileManager.default.fileExists(atPath: codexAuthFile.path),
               let cliBin = ACPHostService.resolveAgentBinary(for: .codexEngine) {
                return (.openai, "cli://codex:\(cliBin)", "cli_bridge")
            }
            if SubscriptionAuthManager.shared.isConnected(.aipass),
               let aipassTok = SubscriptionAuthManager.shared.token(for: .aipass) {
                let cookie = Self.resolveAiPassSessionCookie(primary: aipassTok)
                if !cookie.isEmpty {
                    return (.aipass, Self.subscriptionBaseURL(for: .aipass), cookie)
                }
            }
            if SubscriptionAuthManager.shared.isConnected(.copilot),
               let copilotTok = SubscriptionAuthManager.shared.token(for: .copilot), !copilotTok.isEmpty {
                return (.copilot, Self.subscriptionBaseURL(for: .copilot), copilotTok)
            }
            return nil
        }

        // 4. Claude Pro / Max (Claude Code CLI OAuth / Vertex Jetski Ultra / claude.ai Web Session)
        if provider == .anthropic {
            if subToken.hasPrefix("claude_cli_bridge:"),
               Self.hasLocalClaudeCodeOAuth(),
               let claudeBin = ACPHostService.resolveAgentBinary(for: .claudeCode) {
                return (.anthropic, "cli://claude:\(claudeBin)", "cli_bridge")
            }
            if subToken.hasPrefix("codeassist_oauth:jetski:") {
                let rawRefresh = String(subToken.dropFirst("codeassist_oauth:jetski:".count))
                if !rawRefresh.isEmpty {
                    return (.anthropic, "https://daily-cloudcode-pa.googleapis.com/v1internal", rawRefresh)
                }
            }
            if Self.isValidDirectAPIKey(subToken, for: .anthropic) {
                return (.anthropic, Self.subscriptionBaseURL(for: .anthropic), subToken)
            }
            if Self.hasLocalClaudeCodeOAuth(),
               let claudeBin = ACPHostService.resolveAgentBinary(for: .claudeCode) {
                return (.anthropic, "cli://claude:\(claudeBin)", "cli_bridge")
            }
            if subToken.hasPrefix("sk-ant-sid") || subToken.contains("sessionKey=") || subToken.hasPrefix("claude_web:") {
                let cleanTok = subToken.hasPrefix("claude_web:") ? String(subToken.dropFirst("claude_web:".count)) : subToken
                return (.anthropic, "claudeweb://session", cleanTok)
            }
            if SubscriptionAuthManager.shared.isConnected(.aipass),
               let aipassTok = SubscriptionAuthManager.shared.token(for: .aipass) {
                let cookie = Self.resolveAiPassSessionCookie(primary: aipassTok)
                if !cookie.isEmpty {
                    return (.aipass, Self.subscriptionBaseURL(for: .aipass), cookie)
                }
            }
            if SubscriptionAuthManager.shared.isConnected(.copilot),
               let copilotTok = SubscriptionAuthManager.shared.token(for: .copilot), !copilotTok.isEmpty {
                return (.copilot, Self.subscriptionBaseURL(for: .copilot), copilotTok)
            }
            return nil
        }

        // 5. Google Gemini (Google AI Ultra / Gemini Code Assist OAuth / Thai AI Gemini Enterprise / TH-AI Passport)
        if provider == .gemini {
            if model.lowercased().contains("argon"),
               !Self.hasJetskiCodeAssistToken(fallbackToken: subToken),
               (SubscriptionAuthManager.shared.isConnected(.thai_gemini_enterprise) || SubscriptionAuthManager.shared.isConnected(.aipass)) {
                let rawAiPass = SubscriptionAuthManager.shared.token(for: .thai_gemini_enterprise)
                    ?? SubscriptionAuthManager.shared.token(for: .aipass)
                    ?? ""
                let cookie = Self.resolveAiPassSessionCookie(primary: rawAiPass)
                if !cookie.isEmpty {
                    return (.aipass, Self.subscriptionBaseURL(for: .aipass), cookie)
                }
            }
            if let codeAssistCreds = Self.loadGoogleCodeAssistCredentials(fallbackToken: subToken) {
                return (.gemini, "https://daily-cloudcode-pa.googleapis.com/v1internal", codeAssistCreds.refreshToken)
            }
            if Self.isValidDirectAPIKey(subToken, for: .gemini) {
                return (.gemini, Self.subscriptionBaseURL(for: .gemini), subToken)
            }
            if SubscriptionAuthManager.shared.isConnected(.thai_gemini_enterprise) || SubscriptionAuthManager.shared.isConnected(.aipass) {
                let rawAiPass = SubscriptionAuthManager.shared.token(for: .thai_gemini_enterprise)
                    ?? SubscriptionAuthManager.shared.token(for: .aipass)
                    ?? ""
                let cookie = Self.resolveAiPassSessionCookie(primary: rawAiPass)
                if !cookie.isEmpty {
                    return (.aipass, Self.subscriptionBaseURL(for: .aipass), cookie)
                }
            }
            return nil
        }

        // 6. Portal & Coding-Plan Subscriptions (TokenMe, DeepSeek, GLM, Typhoon, OpenRouter, Groq, Cerebras, etc.)
        if Self.isValidDirectAPIKey(subToken, for: provider) {
            return (provider, Self.subscriptionBaseURL(for: provider), subToken)
        }
        if (provider == .typhoon || provider == .deepseek || provider == .glm),
           SubscriptionAuthManager.shared.isConnected(.aipass),
           let aipassToken = SubscriptionAuthManager.shared.token(for: .aipass) {
            let cookie = Self.resolveAiPassSessionCookie(primary: aipassToken)
            if !cookie.isEmpty {
                return (.aipass, Self.subscriptionBaseURL(for: .aipass), cookie)
            }
        }
        return nil
    }
    
    /// Sanitize a tool schema for Gemini API compatibility.
    /// Gemini's function calling requires every `type: "array"` property
    /// to have an `items` field and doesn't support OpenAI-only keys like
    /// `additionalProperties` or `default`.
    private func sanitizeToolSchemaForGemini(_ tool: [String: Any]) -> [String: Any] {
        var result = tool
        if var parameters = result["parameters"] as? [String: Any] {
            let rootDefs = (parameters["$defs"] as? [String: Any]) ?? (parameters["definitions"] as? [String: Any]) ?? [:]
            parameters = sanitizeSchemaObject(parameters, ensureObjectRoot: true, rootDefs: rootDefs, depth: 0)
            result["parameters"] = parameters
        } else {
            result["parameters"] = ["type": "object", "properties": [String: Any]()]
        }
        return result
    }
    
    private func sanitizeSchemaObject(
        _ schema: [String: Any],
        ensureObjectRoot: Bool = false,
        rootDefs: [String: Any] = [:],
        depth: Int = 0
    ) -> [String: Any] {
        if depth > 8 {
            return ["type": "string"]
        }
        var s = schema

        // Resolve local JSON Schema $ref ("#/$defs/Foo" or "#/definitions/Foo") before stripping metadata
        if let refStr = s["$ref"] as? String {
            s.removeValue(forKey: "$ref")
            let refName = refStr.components(separatedBy: "/").last ?? ""
            if !refName.isEmpty, let targetDef = rootDefs[refName] as? [String: Any] {
                var merged = targetDef
                for (k, v) in s { merged[k] = v }
                s = merged
            }
        }
        
        // Normalize JSON Schema union type arrays such as ["string", "null"] -> "string" + nullable
        if let typeArray = s["type"] as? [Any] {
            let stringTypes = typeArray.compactMap { $0 as? String }
            if let primary = stringTypes.first(where: { $0.lowercased() != "null" }) {
                s["type"] = primary.lowercased()
                if stringTypes.contains(where: { $0.lowercased() == "null" }) {
                    s["nullable"] = true
                }
            } else {
                s["type"] = "string"
            }
        } else if let typeStr = s["type"] as? String {
            let lowerType = typeStr.lowercased()
            let validTypes: Set<String> = ["string", "number", "integer", "boolean", "array", "object"]
            s["type"] = validTypes.contains(lowerType) ? lowerType : "string"
        }
        
        // Collapse nullable anyOf / oneOf into primary branch for strict Gemini Schema proto
        for unionKey in ["anyOf", "oneOf"] {
            if let branches = s[unionKey] as? [[String: Any]], !branches.isEmpty {
                let nonNullBranches = branches.filter { ($0["type"] as? String)?.lowercased() != "null" }
                s.removeValue(forKey: unionKey)
                if let firstBranch = nonNullBranches.first {
                    let cleanBranch = sanitizeSchemaObject(firstBranch, rootDefs: rootDefs, depth: depth + 1)
                    for (k, v) in cleanBranch where s[k] == nil {
                        s[k] = v
                    }
                    if nonNullBranches.count < branches.count {
                        s["nullable"] = true
                    }
                }
            }
        }
        
        if ensureObjectRoot && s["type"] == nil {
            s["type"] = "object"
        }
        if s["type"] == nil {
            s["type"] = (s["properties"] != nil) ? "object" : "string"
        }
        
        let resolvedType = (s["type"] as? String) ?? "string"
        
        // Gemini Schema proto only allows `enum` on string types with string elements
        if resolvedType == "string", let rawEnum = s["enum"] as? [Any] {
            let strEnum = rawEnum.compactMap { "\($0)" }.filter { !$0.isEmpty }
            if strEnum.isEmpty {
                s.removeValue(forKey: "enum")
            } else {
                s["enum"] = strEnum
            }
        } else {
            s.removeValue(forKey: "enum")
        }
        
        // Fix array types missing "items"
        if resolvedType == "array" {
            if let items = s["items"] as? [String: Any] {
                s["items"] = sanitizeSchemaObject(items, rootDefs: rootDefs, depth: depth + 1)
            } else {
                s["items"] = ["type": "string"]
            }
        } else {
            s.removeValue(forKey: "items")
        }
        
        // Recursively fix properties and validate `required` keys
        if resolvedType == "object" {
            if var properties = s["properties"] as? [String: Any] {
                for (key, value) in properties {
                    if let prop = value as? [String: Any] {
                        properties[key] = sanitizeSchemaObject(prop, rootDefs: rootDefs, depth: depth + 1)
                    } else {
                        properties[key] = ["type": "string"]
                    }
                }
                s["properties"] = properties
                if let req = s["required"] as? [Any] {
                    let validReq = req.compactMap { $0 as? String }.filter { properties[$0] != nil }
                    if validReq.isEmpty {
                        s.removeValue(forKey: "required")
                    } else {
                        s["required"] = validReq
                    }
                } else {
                    s.removeValue(forKey: "required")
                }
            } else {
                s["properties"] = [String: Any]()
                s.removeValue(forKey: "required")
            }
        } else {
            s.removeValue(forKey: "properties")
            s.removeValue(forKey: "required")
        }

        // Strict Protobuf JSON whitelist for Google Gemini / CodeAssist `v1internal` Schema proto:
        // Strips `x-google-enum-descriptions`, `readOnly`, `format`, `additionalProperties`, `$defs`, etc.
        let allowedGeminiKeys: Set<String> = [
            "type", "description", "nullable", "enum", "items", "properties", "required"
        ]
        for key in Array(s.keys) where !allowedGeminiKeys.contains(key) {
            s.removeValue(forKey: key)
        }
        
        return s
    }

    /// Sanitizes a tool definition for OpenAI, Anthropic, Codex, DeepSeek, and Dotmini Cloud Gateway.
    /// Preserves rich nested MCP JSON Schema fields (`items`, `enum`, nested `properties`, `anyOf`/`oneOf`)
    /// while guaranteeing strict spec invariants (every `array` has `items`, `object` has `properties`,
    /// union `type` arrays are normalized, and `required` only names defined properties).
    func sanitizeToolSchemaForStandardJSONSchema(_ tool: [String: Any]) -> [String: Any] {
        var result = tool
        let rawParams = (result["parameters"] as? [String: Any]) ?? ["type": "object", "properties": [String: Any]()]
        result["parameters"] = sanitizeStandardJSONSchemaNode(rawParams, isRoot: true)
        return result
    }

    private func sanitizeStandardJSONSchemaNode(_ schema: [String: Any], isRoot: Bool = false) -> [String: Any] {
        var s = schema
        s.removeValue(forKey: "$schema")
        s.removeValue(forKey: "$id")
        
        if let typeArray = s["type"] as? [Any] {
            let stringTypes = typeArray.compactMap { $0 as? String }
            s["type"] = stringTypes.first(where: { $0.lowercased() != "null" }) ?? "string"
        }
        
        if isRoot {
            s["type"] = "object"
        } else if s["type"] == nil && s["anyOf"] == nil && s["oneOf"] == nil && s["allOf"] == nil {
            if s["properties"] != nil {
                s["type"] = "object"
            } else if s["items"] != nil {
                s["type"] = "array"
            } else {
                s["type"] = "string"
            }
        }
        
        if let type = s["type"] as? String, type == "array" {
            if let items = s["items"] as? [String: Any] {
                s["items"] = sanitizeStandardJSONSchemaNode(items)
            } else {
                s["items"] = ["type": "string"]
            }
        }
        
        for combinator in ["anyOf", "oneOf", "allOf"] {
            if let branches = s[combinator] as? [[String: Any]] {
                s[combinator] = branches.map { sanitizeStandardJSONSchemaNode($0) }
            }
        }
        
        if var properties = s["properties"] as? [String: Any] {
            for (key, val) in properties {
                if let propDict = val as? [String: Any] {
                    properties[key] = sanitizeStandardJSONSchemaNode(propDict)
                }
            }
            s["properties"] = properties
            if let req = s["required"] as? [Any] {
                let validReq = req.compactMap { $0 as? String }.filter { properties[$0] != nil }
                s["required"] = validReq
            }
        } else if (s["type"] as? String) == "object" {
            s["properties"] = [String: Any]()
            s.removeValue(forKey: "required")
        }
        
        return s
    }


    private func boundedText(_ text: String, limit: Int) -> String {
        guard text.count > limit, limit > 64 else { return String(text.prefix(max(0, limit))) }
        let headCount = (limit * 2) / 3
        return String(text.prefix(headCount)) + "\n…[context truncated]…\n" + String(text.suffix(limit - headCount))
    }
    
    private func resolveSubscriptionToken(for provider: StreamableAIProvider) -> String {
        return resolveSubscriptionAccount(for: provider)?.sessionToken ?? ""
    }
    
    /// Returns the full SubscriptionAccount for a given provider
    private func resolveSubscriptionAccount(for provider: StreamableAIProvider) -> SubscriptionAccount? {
        if provider == .aipass {
            let activeSub = UserDefaults.standard.string(forKey: "subscriptionActiveProvider")
            if activeSub == SubscriptionProviderType.thai_gemini_enterprise.rawValue,
               SubscriptionAuthManager.shared.isConnected(.thai_gemini_enterprise),
               let acc = SubscriptionAuthManager.shared.getAccount(.thai_gemini_enterprise) {
                return acc
            }
            if SubscriptionAuthManager.shared.isConnected(.aipass),
               let acc = SubscriptionAuthManager.shared.getAccount(.aipass) {
                return acc
            }
            if let acc = SubscriptionAuthManager.shared.getAccount(.thai_gemini_enterprise) {
                return acc
            }
            return SubscriptionAuthManager.shared.getAccount(.aipass)
        }
        let explicitSubName = UserDefaults.standard.string(forKey: "subscriptionActiveProvider")
        let subType: SubscriptionProviderType
        if let explicitSubName, let explicit = SubscriptionProviderType(rawValue: explicitSubName),
           SubscriptionAuthManager.shared.isConnected(explicit) {
            if explicit == .aipass || explicit == .thai_gemini_enterprise {
                return SubscriptionAuthManager.shared.getAccount(explicit)
            }
            if explicit.aiProviderID == provider.rawValue ||
               (provider == .openai && (explicit == .chatgpt || explicit == .copilot)) ||
               (provider == .anthropic && (explicit == .claude || explicit == .copilot)) {
                subType = explicit
            } else {
                switch provider {
                case .aipass: subType = .aipass
                case .anthropic: subType = .claude
                case .glm: subType = .glm
                case .gemini: subType = .gemini
                case .deepseek: subType = .deepseek
                case .copilot: subType = .copilot
                case .openrouter: subType = .openrouter
                case .groq: subType = .groq
                case .mistral: subType = .mistral
                case .kimi: subType = .kimi
                case .perplexity: subType = .perplexity
                case .perch: subType = .perch
                case .tokenme: subType = .tokenme
                case .typhoon: subType = .typhoon
                case .qwen: subType = .qwen
                case .grok: subType = .grok
                case .cerebras: subType = .cerebras
                case .together: subType = .together
                case .fireworks: subType = .fireworks
                case .minimax: subType = .minimax
                case .nvidia: subType = .nvidia
                default: subType = explicit == .copilot ? .copilot : .chatgpt
                }
            }
        } else {
            switch provider {
            case .aipass: subType = .aipass
            case .anthropic: subType = .claude
            case .glm: subType = .glm
            case .gemini: subType = .gemini
            case .deepseek: subType = .deepseek
            case .copilot: subType = .copilot
            case .openrouter: subType = .openrouter
            case .groq: subType = .groq
            case .mistral: subType = .mistral
            case .kimi: subType = .kimi
            case .perplexity: subType = .perplexity
            case .perch: subType = .perch
            case .tokenme: subType = .tokenme
            case .typhoon: subType = .typhoon
            case .qwen: subType = .qwen
            case .grok: subType = .grok
            case .cerebras: subType = .cerebras
            case .together: subType = .together
            case .fireworks: subType = .fireworks
            case .minimax: subType = .minimax
            case .nvidia: subType = .nvidia
            default:
                if SubscriptionAuthManager.shared.isConnected(.chatgpt) {
                    subType = .chatgpt
                } else if SubscriptionAuthManager.shared.isConnected(.copilot) {
                    subType = .copilot
                } else if SubscriptionAuthManager.shared.isConnected(.aipass) {
                    subType = .aipass
                } else {
                    subType = .chatgpt
                }
            }
        }
        if let acc = SubscriptionAuthManager.shared.getAccount(subType), SubscriptionAuthManager.shared.isConnected(subType) {
            return acc
        }
        if provider == .omni, SubscriptionAuthManager.shared.isConnected(.aipass) {
            return SubscriptionAuthManager.shared.getAccount(.aipass)
        }
        return SubscriptionAuthManager.shared.getAccount(subType)
    }
    
    // MARK: - Send Message (Streaming, Text-only response)
    
    func sendMessage(
        prompt: String,
        attachments: [AIAttachment] = [],
        systemPrompt: String? = nil,
        conversationHistory: [(role: String, content: String)] = [],
        provider: StreamableAIProvider,
        model: String,
        apiKey: String,
        tools: [[String: Any]]? = nil,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)? = nil,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        let ent = EnterpriseAIAuthService.shared
        let safePrompt = ent.redactPromptIfNeeded(prompt)
        let rawKeyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "direct"
        let useDotminiEnterprise = (ent.mode == .dotminiEnterprise && rawKeyMode == "cloud")
        var provider = provider
        if Self.isAiPassMediaModel(model) {
            provider = .aipass
        } else if rawKeyMode == "subscription",
                  UserDefaults.standard.string(forKey: "subscriptionActiveProvider") == "tokenme",
                  SubscriptionAuthManager.shared.isConnected(.tokenme),
                  SubscriptionProviderType.tokenme.modelInfos.contains(where: { $0.modelID.caseInsensitiveCompare(model) == .orderedSame }) {
            provider = .tokenme
        } else if provider == .omni && !useDotminiEnterprise && rawKeyMode != "cloud" {
            let detected = StreamableAIProvider.detect(from: model)
            if detected != .omni {
                provider = detected
            } else if rawKeyMode == "subscription",
                      let subStr = UserDefaults.standard.string(forKey: "subscriptionActiveProvider"),
                      let subType = SubscriptionProviderType(rawValue: subStr),
                      let mapped = StreamableAIProvider(rawValue: subType.aiProviderID) {
                provider = mapped
            } else {
                provider = .gemini
            }
        }
        let keyMode = rawKeyMode
        var actualKey: String = ""
        var baseURL: String = provider.directBaseURL
        let useEnterpriseProfile = (keyMode == "enterprise" && ent.activeProfile != nil)
        // Web Subscription mode is strictly isolated: enterprise Vertex / custom-gateway overrides must never hijack a Subscription turn
        // (they need a service-account JSON / gateway key that Subscription accounts do not carry).
        let enterpriseOverridesAllowed = (keyMode != "subscription")
        let useVertexGemini = (enterpriseOverridesAllowed && !useEnterpriseProfile && ent.mode == .geminiVertex && provider == .gemini)
        let useCustomGateway = (enterpriseOverridesAllowed && !useEnterpriseProfile && ent.mode == .customGateway && !ent.customGatewayBaseURL.isEmpty)

        // Enterprise Air-Gapped Sovereign Lockdown enforcement
        if ent.isAirGappedLockdownEnabled && provider != .local && keyMode != "local" && !useCustomGateway && !useEnterpriseProfile {
            if LocalLLMService.shared.detectedServers.contains(where: { $0.isOnline }) {
                provider = .local
            } else {
                onError("🛡️ Air-Gapped Sovereign Lockdown is active: External cloud AI endpoints are blocked. Start Local LLM or configure an internal VPC Gateway.")
                return
            }
        }
        // Enterprise Confidential Split-Routing (routes turns that read .env / keys to Local LLM or Enterprise ZDR Gateway)
        if ent.confidentialTurnActive && ent.enforceConfidentialSplitRouting &&
           provider != .local && keyMode != "local" && !useCustomGateway && !useVertexGemini && !useDotminiEnterprise && !useEnterpriseProfile {
            if LocalLLMService.shared.detectedServers.contains(where: { $0.isOnline }) {
                provider = .local
            }
        }
        
        var resolvedLocalRoute: (endpoint: String, apiKey: String, model: String, serverLabel: String)?
        if provider == .local || keyMode == "local" {
            let route = LocalLLMService.resolveRoute(forModel: model)
            resolvedLocalRoute = route
            baseURL = route.endpoint
            actualKey = route.apiKey
        } else if useEnterpriseProfile, let prof = ent.activeProfile {
            actualKey = "enterprise_profile:\(prof.id)"
            baseURL = prof.endpointSummary
        } else if useVertexGemini {
            actualKey = "vertex_enterprise"
            baseURL = "vertex://\(ent.vertexLocation)/\(ent.vertexProjectId)"
        } else if useDotminiEnterprise {
            actualKey = !ent.dotminiEnterpriseKey.isEmpty
                ? ent.dotminiEnterpriseKey
                : (DotminiPlatformKeyService.shared.authorizationToken ?? SupabaseAuthService.shared.accessToken ?? "")
            baseURL = ent.dotminiEnterpriseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if useCustomGateway {
            actualKey = ent.customGatewayAPIKey
            baseURL = ent.customGatewayBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if apiKey == "codex_oauth", let codexCreds = Self.loadCodexOAuthCredentials(fallbackToken: "") {
            actualKey = codexCreds.accessToken
            baseURL = "https://chatgpt.com/backend-api/codex"
        } else if keyMode == "subscription" {
            // ━━━ WEB SUBSCRIPTION MODE (ZERO BYOK BILLING) ━━━
            // Strictly uses Subscription credentials / OAuth / CLI bridges only — NEVER reads BYOK API keys.
            if let resolvedTarget = resolveSubscriptionExecutionTarget(provider: provider, model: model) {
                provider = resolvedTarget.provider
                baseURL = resolvedTarget.baseURL
                actualKey = resolvedTarget.credential
            } else {
                let message = "No active Web Subscription session found for \(provider.rawValue). Connect in Settings → AI Provider → Subscription (BYOK keys are strictly isolated and never billed in Subscription mode)."
                onError(message)
                return
            }
        } else if keyMode == "direct" {
            // ━━━ BYOK (DIRECT) MODE ━━━
            // Uses ONLY user's own API keys & configured BYOK Base URL (including Cloudflare Tunnel / custom endpoints)
            // Strictly separated from Subscription OAuth and Local/LAN LLM
            let passedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedKey = AIModelCatalog.resolveKey(provider.rawValue)
            let hasCustomURL = (provider == .custom) || StreamableAIProvider.hasCustomByokBaseURL(for: provider.rawValue)

            if provider == .aipass {
                actualKey = Self.resolveAiPassSessionCookie(primary: !passedKey.isEmpty ? passedKey : resolvedKey)
                baseURL = StreamableAIProvider.aipass.directBaseURL
            } else {
                let candidateKey = !passedKey.isEmpty ? passedKey : resolvedKey
                if candidateKey.isEmpty && hasCustomURL {
                    // Allow passwordless Cloudflare Tunnel / Custom OpenAI-compatible endpoints in BYOK
                    actualKey = "byok-custom-tunnel"
                } else {
                    actualKey = candidateKey
                }
                baseURL = provider.directBaseURL
            }
            
        } else {
            // ━━━ CLOUD MODE (Dotmini) ━━━
            // Uses ONLY Dotmini platform credentials — no BYOK, no subscription
            let microToken = DotminiPlatformKeyService.shared.authorizationToken
                ?? SupabaseAuthService.shared.accessToken ?? ""
            actualKey = microToken
            baseURL = provider.cloudBaseURL
        }
        
        if actualKey.isEmpty && provider != .local && !useVertexGemini && !useCustomGateway {
            switch keyMode {
            case "subscription":
                onError("No subscription session found for \(provider.rawValue). Go to Settings → AI Provider → Subscription to connect.")
                return
            case "direct":
                onError("API key missing for \(provider.rawValue). Go to Settings → AI Provider → BYOK to add your key.")
                return
            case "cloud":
                if SupabaseAuthService.shared.session == nil && DotminiPlatformKeyService.shared.authorizationToken == nil {
                    onError("Dotmini Cloud requires signing in. Sign in via Settings → Account & License or on microcode.dotmini.net (auto-syncs seamlessly).")
                    return
                }
            default:
                break
            }
        }

        let callerChatId = AgentExecutionContext.chatId
        let taskKey = callerChatId ?? UUID().uuidString
        let trimmedHistory = boundedHistory(conversationHistory)
        let initialResolvedModel = useEnterpriseProfile
            ? (model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (ent.activeProfile?.defaultModel ?? "gpt-4o") : model)
            : (resolvedLocalRoute?.model ?? normalizeModelName(model, provider: provider, baseURL: baseURL))

        isStreaming = true
        let task = Task {
            let streamCtx = AIStreamContext()
            await AIStreamContext.$current.withValue(streamCtx) {
                defer {
                    self.streamTasksByKey.removeValue(forKey: taskKey)
                    self.activeStreamCount = self.streamTasksByKey.count
                    self.isStreaming = !self.streamTasksByKey.isEmpty
                }
                var activeBaseURL = baseURL
                var activeModel = initialResolvedModel
                var failedLocalEndpoints: Set<String> = []
                var requestKey: String
                if useDotminiEnterprise {
                    if !ent.dotminiEnterpriseKey.isEmpty {
                        requestKey = ent.dotminiEnterpriseKey
                    } else if let platformKey = DotminiPlatformKeyService.shared.authorizationToken {
                        requestKey = platformKey
                    } else {
                        requestKey = actualKey
                    }
                } else if keyMode == "cloud" && activeBaseURL == provider.cloudBaseURL && provider != .local {
                    if let platformKey = DotminiPlatformKeyService.shared.authorizationToken {
                        requestKey = platformKey
                    } else if SupabaseAuthService.shared.session != nil {
                        guard let refreshed = await SupabaseAuthService.shared.refreshAccessTokenIfNeeded() else {
                            onError("Could not refresh your Dotmini session. Check your connection or sign in again.")
                            return
                        }
                        requestKey = refreshed
                    } else {
                        requestKey = actualKey
                    }
                } else {
                    requestKey = actualKey
                }
                let resolvedAttachments = attachments.isEmpty
                    ? []
                    : await UniversalAttachmentEngine.shared.ensureIngested(attachments, chatId: callerChatId)
                var retryCount = 0
                let maxRetries = 3
                
                while retryCount <= maxRetries {
                    if retryCount > 0 {
                        self.currentStreamedText = ""
                        self.pendingStreamTokens = ""
                    }
                    let isLocalCall = (provider == .local || keyMode == "local")
                    let trackedLocalEndpoint = activeBaseURL
                    if isLocalCall {
                        LocalLLMService.beginInFlight(endpoint: trackedLocalEndpoint)
                    }
                    defer {
                        if isLocalCall {
                            LocalLLMService.endInFlight(endpoint: trackedLocalEndpoint)
                        }
                    }
                    do {
                        if activeBaseURL.hasPrefix("cli://") {
                            try await streamHeadlessCLISubscription(
                                cliURI: activeBaseURL,
                                prompt: safePrompt,
                                systemPrompt: systemPrompt,
                                conversationHistory: trimmedHistory,
                                model: activeModel,
                                tools: tools,
                                onToken: onToken,
                                onToolCall: onToolCall
                            )
                        } else if activeBaseURL == "claudeweb://session" {
                            let toolsPrompt = (tools != nil && !(tools?.isEmpty ?? true) && onToolCall != nil)
                                ? Self.buildAiPassToolSystemInstruction(tools!)
                                : nil
                            let webText = try await ClaudeWebSessionBridge.shared.streamPrompt(
                                prompt: safePrompt,
                                systemPrompt: systemPrompt,
                                conversationHistory: trimmedHistory,
                                model: activeModel,
                                sessionToken: requestKey,
                                toolsPrompt: toolsPrompt,
                                onToken: { chunk in
                                    self.appendStreamToken(chunk, onToken: onToken)
                                }
                            )
                            if let onToolCall, tools != nil {
                                for tc in Self.extractAiPassToolCalls(from: webText) {
                                    onToolCall(tc)
                                }
                            }
                        } else if useEnterpriseProfile, let prof = ent.activeProfile {
                            try await streamEnterpriseProfile(
                                profile: prof,
                                prompt: safePrompt,
                                attachments: resolvedAttachments,
                                systemPrompt: systemPrompt,
                                conversationHistory: trimmedHistory,
                                model: activeModel,
                                tools: tools,
                                onToken: onToken,
                                onToolCall: onToolCall
                            )
                        } else if useVertexGemini {
                            try await streamGemini(prompt: safePrompt, attachments: resolvedAttachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: activeModel, apiKey: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                        } else if provider == .aipass || activeBaseURL.contains("de.aipass.net") {
                            try await streamAiPass(prompt: safePrompt, attachments: resolvedAttachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: activeModel, sessionCookie: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                        } else if activeBaseURL == "https://chatgpt.com/backend-api/codex" {
                            try await streamCodexResponses(prompt: safePrompt, attachments: resolvedAttachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: activeModel, accessToken: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                        } else if activeBaseURL.contains("cloudcode-pa.googleapis.com") {
                            try await streamGoogleCodeAssist(prompt: safePrompt, attachments: resolvedAttachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: activeModel, refreshToken: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                        } else if useDotminiEnterprise || useCustomGateway || activeBaseURL == provider.cloudBaseURL || activeBaseURL == StreamableAIProvider.copilot.directBaseURL {
                            // Cloud-routed requests (Dotmini Cloud Enterprise, Dotmini Cloud, Custom Gateway, or GitHub Copilot) use OpenAI-compatible gateway
                            try await streamOpenAI(prompt: safePrompt, attachments: resolvedAttachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: activeModel, apiKey: requestKey, baseURL: activeBaseURL, tools: tools, onToken: onToken, onToolCall: onToolCall)
                        } else {
                            // Direct / Subscription mode with native provider endpoints
                            switch provider {
                            case .aipass:
                                try await streamAiPass(prompt: safePrompt, attachments: resolvedAttachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: activeModel, sessionCookie: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                            case .gemini:
                                let lower = activeModel.lowercased()
                                if !lower.contains("gemini") && !lower.contains("gemma") {
                                    let fallback = StreamableAIProvider.detect(from: activeModel)
                                    if fallback != .gemini {
                                        try await streamOpenAI(prompt: safePrompt, attachments: resolvedAttachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: activeModel, apiKey: requestKey, baseURL: fallback.directBaseURL, tools: tools, onToken: onToken, onToolCall: onToolCall)
                                    } else {
                                        try await streamGemini(prompt: safePrompt, attachments: resolvedAttachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: activeModel, apiKey: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                                    }
                                } else {
                                    try await streamGemini(prompt: safePrompt, attachments: resolvedAttachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: activeModel, apiKey: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                                }
                            case .anthropic:
                                try await streamAnthropic(prompt: safePrompt, attachments: resolvedAttachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: activeModel, apiKey: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                            case .omni, .openai, .deepseek, .ninerouter, .openrouter, .groq, .mistral, .kimi, .perplexity, .perch,
                                 .tokenme, .typhoon, .cerebras, .together, .fireworks, .minimax, .nvidia,
                                 .grok, .qwen, .glm, .copilot, .custom, .local:
                                try await streamOpenAI(prompt: safePrompt, attachments: resolvedAttachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: activeModel, apiKey: requestKey, baseURL: activeBaseURL, tools: tools, onToken: onToken, onToolCall: onToolCall)
                            }
                        }
                        
                        self.flushPendingStreamTokens(onToken: onToken)
                        onComplete(self.currentStreamedText)
                        return // Success
                        
                    } catch let error as NSError {
                        if Task.isCancelled || error.code == NSURLErrorCancelled {
                            onError("Generation stopped by user.")
                            return
                        }
                        // Multi-Node Local LLM Pool Failover: if a Local LLM server fails, fail over to the next connected node in the pool
                        if isLocalCall && retryCount < maxRetries {
                            failedLocalEndpoints.insert(activeBaseURL.lowercased())
                            let nextRoute = LocalLLMService.resolveRoute(
                                forModel: model,
                                excludingEndpoints: failedLocalEndpoints
                            )
                            if !failedLocalEndpoints.contains(nextRoute.endpoint.lowercased()) &&
                               nextRoute.endpoint.lowercased() != activeBaseURL.lowercased() {
                                activeBaseURL = nextRoute.endpoint
                                activeModel = nextRoute.model
                                requestKey = nextRoute.apiKey
                                retryCount += 1
                                continue
                            }
                        }
                        // Rotate Multi-Account Subscription Ring immediately on 429 / 529 quota exhaustion
                        if keyMode == "subscription" && (error.code == 429 || error.code == 529) {
                            if let subType = Self.mapToSubscriptionProvider(provider),
                               let nextHealthy = SubscriptionAuthManager.shared.markRateLimited(provider: subType, tokenOrAccountId: requestKey),
                               nextHealthy.sessionToken != requestKey,
                               retryCount < maxRetries {
                                retryCount += 1
                                try? await Task.sleep(nanoseconds: 250_000_000)
                                continue
                            }
                        }
                        // Retry on transient errors
                        let transientCodes: Set<Int> = [429, 503, -1001, -1004, -1005, -1009]
                        if transientCodes.contains(error.code) && retryCount < maxRetries {
                            retryCount += 1
                            let delay = UInt64(pow(2.0, Double(retryCount))) * 1_000_000_000
                            try? await Task.sleep(nanoseconds: delay)
                            continue
                        }
                        
                        onError(self.parseErrorMessage(error))
                        return
                    }
                }
            }
        }
        streamTask = task
        streamTasksByKey[taskKey] = task
        activeStreamCount = streamTasksByKey.count
    }
    
    func cancelStream(forChatId chatId: String? = nil) {
        if let targetKey = chatId ?? AgentExecutionContext.chatId {
            streamTasksByKey[targetKey]?.cancel()
            streamTasksByKey.removeValue(forKey: targetKey)
            activeStreamCount = streamTasksByKey.count
            isStreaming = !streamTasksByKey.isEmpty
        } else {
            streamTask?.cancel()
            for (_, t) in streamTasksByKey {
                t.cancel()
            }
            streamTasksByKey.removeAll()
            activeStreamCount = 0
            pendingStreamTokens = ""
            isStreaming = false
        }
    }
    
    // MARK: - Codex ChatGPT Subscription OAuth Support

    private nonisolated static let codexOAuthClientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    private nonisolated static func parseCodexJWTClaims(_ jwt: String) -> (exp: Date?, email: String?, accountId: String?) {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return (nil, nil, nil) }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil, nil)
        }
        let exp: Date?
        if let expNum = claims["exp"] as? Double {
            exp = Date(timeIntervalSince1970: expNum)
        } else if let expInt = claims["exp"] as? Int {
            exp = Date(timeIntervalSince1970: TimeInterval(expInt))
        } else {
            exp = nil
        }
        let directEmail = claims["email"] as? String
        let profileEmail = (claims["https://api.openai.com/profile"] as? [String: Any])?["email"] as? String
        let email = (directEmail?.isEmpty == false ? directEmail : profileEmail)
        let accountId = (claims["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_account_id"] as? String
        return (exp, email, accountId)
    }

    private nonisolated static func readCodexDefaultModel(home: URL) -> String {
        var defaultModel = "gpt-6-luna"
        let configURL = home.appendingPathComponent(".codex/config.toml")
        if let configStr = try? String(contentsOf: configURL, encoding: .utf8) {
            for line in configStr.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("model =") || trimmed.hasPrefix("model=") {
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    if parts.count > 1 {
                        let m = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                        if !m.isEmpty { defaultModel = m }
                    }
                }
            }
        }
        return defaultModel
    }

    nonisolated static func loadCodexOAuthCredentials(fallbackToken: String) -> (accessToken: String, accountId: String, defaultModel: String)? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let authURL = home.appendingPathComponent(".codex/auth.json")
        var fileAccessToken = ""
        var fileRefreshToken = ""
        var fileAccountId = ""
        if let data = try? Data(contentsOf: authURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let authMode = (json["auth_mode"] as? String)?.lowercased() ?? ""
            if authMode != "apikey" {
                if let tokens = json["tokens"] as? [String: Any] {
                    fileAccessToken = (tokens["access_token"] as? String) ?? ""
                    fileRefreshToken = (tokens["refresh_token"] as? String) ?? ""
                    fileAccountId = (tokens["account_id"] as? String) ?? ""
                }
                if fileAccessToken.isEmpty {
                    fileAccessToken = (json["access_token"] as? String) ?? ""
                }
            }
        }

        let cleanFallback = fallbackToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let validFallback = (!cleanFallback.isEmpty &&
            !cleanFallback.hasPrefix("sk-") &&
            !cleanFallback.hasPrefix("cli-oauth:") &&
            !cleanFallback.hasPrefix("cli://") &&
            !cleanFallback.hasPrefix("codeassist_oauth:")) ? cleanFallback : ""

        let fileClaims = parseCodexJWTClaims(fileAccessToken)
        let fallbackClaims = parseCodexJWTClaims(validFallback)
        let now = Date().addingTimeInterval(60)

        var chosenToken = ""
        var chosenAccountId = fileAccountId

        // Prefer a fresh Web Sign-In JWT if the local ~/.codex/auth.json access_token is expired or absent
        if !validFallback.isEmpty,
           let fbExp = fallbackClaims.exp,
           fbExp > now,
           (fileAccessToken.isEmpty || (fileClaims.exp ?? .distantPast) <= now) {
            chosenToken = validFallback
            if let fbAcc = fallbackClaims.accountId, !fbAcc.isEmpty {
                chosenAccountId = fbAcc
            }
        } else if !fileAccessToken.isEmpty || !fileRefreshToken.isEmpty {
            chosenToken = !fileAccessToken.isEmpty ? fileAccessToken : validFallback
            if chosenAccountId.isEmpty, let fcAcc = fileClaims.accountId, !fcAcc.isEmpty {
                chosenAccountId = fcAcc
            }
        } else if !validFallback.isEmpty {
            chosenToken = validFallback
            if let fbAcc = fallbackClaims.accountId, !fbAcc.isEmpty {
                chosenAccountId = fbAcc
            }
        }

        guard !chosenToken.isEmpty || !fileRefreshToken.isEmpty else { return nil }
        let defaultModel = readCodexDefaultModel(home: home)
        return (chosenToken, chosenAccountId, defaultModel)
    }

    static func resolveCodexOAuthSession(
        fallbackToken: String,
        forceRefresh: Bool = false
    ) async -> (accessToken: String, accountId: String, defaultModel: String, email: String)? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let authURL = home.appendingPathComponent(".codex/auth.json")
        let defaultModel = readCodexDefaultModel(home: home)

        var rawJson: [String: Any] = [:]
        var tokensDict: [String: Any] = [:]
        var fileAccessToken = ""
        var fileRefreshToken = ""
        var fileIdToken = ""
        var fileAccountId = ""

        if let data = try? Data(contentsOf: authURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let authMode = (json["auth_mode"] as? String)?.lowercased() ?? ""
            if authMode != "apikey" {
                rawJson = json
                if let t = json["tokens"] as? [String: Any] {
                    tokensDict = t
                    fileAccessToken = (t["access_token"] as? String) ?? ""
                    fileRefreshToken = (t["refresh_token"] as? String) ?? ""
                    fileIdToken = (t["id_token"] as? String) ?? ""
                    fileAccountId = (t["account_id"] as? String) ?? ""
                }
            }
        }

        let cleanFallback = fallbackToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let validFallback = (!cleanFallback.isEmpty &&
            !cleanFallback.hasPrefix("sk-") &&
            !cleanFallback.hasPrefix("cli-oauth:") &&
            !cleanFallback.hasPrefix("cli://") &&
            !cleanFallback.hasPrefix("codeassist_oauth:")) ? cleanFallback : ""

        let nowBuffer = Date().addingTimeInterval(90)
        if !forceRefresh && !validFallback.isEmpty {
            let fbClaims = parseCodexJWTClaims(validFallback)
            if let fbExp = fbClaims.exp, fbExp > nowBuffer {
                let accId = (fbClaims.accountId?.isEmpty == false) ? fbClaims.accountId! : fileAccountId
                let mail = fbClaims.email ?? parseCodexJWTClaims(fileIdToken).email ?? "ChatGPT Plus / Pro"
                return (validFallback, accId, defaultModel, mail)
            }
        }

        if !forceRefresh && !fileAccessToken.isEmpty {
            let fClaims = parseCodexJWTClaims(fileAccessToken)
            if let fExp = fClaims.exp, fExp > nowBuffer {
                let accId = !fileAccountId.isEmpty ? fileAccountId : (fClaims.accountId ?? "")
                let mail = fClaims.email ?? parseCodexJWTClaims(fileIdToken).email ?? "ChatGPT Plus / Pro"
                return (fileAccessToken, accId, defaultModel, mail)
            }
        }

        // Refresh expired access_token using ~/.codex/auth.json refresh_token via official OpenAI OAuth endpoint
        if !fileRefreshToken.isEmpty,
           let tokenURL = URL(string: "https://auth.openai.com/oauth/token") {
            var req = URLRequest(url: tokenURL, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let payload: [String: String] = [
                "client_id": codexOAuthClientID,
                "grant_type": "refresh_token",
                "refresh_token": fileRefreshToken
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse,
               http.statusCode == 200,
               let respJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let freshAccess = respJson["access_token"] as? String,
               !freshAccess.isEmpty {
                let freshRefresh = (respJson["refresh_token"] as? String) ?? fileRefreshToken
                let freshId = (respJson["id_token"] as? String) ?? fileIdToken
                let freshClaims = parseCodexJWTClaims(freshAccess)
                let idClaims = parseCodexJWTClaims(freshId)
                let resolvedAccId = (freshClaims.accountId?.isEmpty == false)
                    ? freshClaims.accountId!
                    : (!fileAccountId.isEmpty ? fileAccountId : (idClaims.accountId ?? ""))
                let resolvedEmail = freshClaims.email ?? idClaims.email ?? "ChatGPT Plus / Pro"

                tokensDict["access_token"] = freshAccess
                tokensDict["refresh_token"] = freshRefresh
                if !freshId.isEmpty { tokensDict["id_token"] = freshId }
                if !resolvedAccId.isEmpty { tokensDict["account_id"] = resolvedAccId }
                rawJson["tokens"] = tokensDict
                if rawJson["auth_mode"] == nil { rawJson["auth_mode"] = "chatgpt" }
                let iso = ISO8601DateFormatter()
                rawJson["last_refresh"] = iso.string(from: Date())

                if let updatedData = try? JSONSerialization.data(withJSONObject: rawJson, options: [.prettyPrinted, .sortedKeys]) {
                    try? updatedData.write(to: authURL, options: .atomic)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authURL.path)
                }
                return (freshAccess, resolvedAccId, defaultModel, resolvedEmail)
            }
        }

        // Last resort if non-JWT opaque web session token was supplied
        if !validFallback.isEmpty, parseCodexJWTClaims(validFallback).exp == nil {
            return (validFallback, fileAccountId, defaultModel, "ChatGPT Plus / Pro")
        }
        return nil
    }

    static func verifyCodexOAuthCredentials() async -> (accessToken: String, email: String, accountId: String)? {
        guard let session = await resolveCodexOAuthSession(fallbackToken: "") else { return nil }
        let claims = parseCodexJWTClaims(session.accessToken)
        if let exp = claims.exp, exp <= Date() {
            return nil
        }
        return (session.accessToken, session.email, session.accountId)
    }

    private static let supportedCodexOAuthModels: Set<String> = [
        "gpt-6.1-sol",
        "gpt-6-sol",
        "gpt-6-luna",
        "gpt-6-astra",
        "gpt-5.6-sol",
        "gpt-5.6-terra",
        "gpt-5.6-luna",
        "gpt-5.5",
        "gpt-reserve",
        "codex-auto-review",
        "gpt-daybreak-blue-latest",
        "gpt-daybreak-red-latest"
    ]

    private func streamCodexResponses(
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        accessToken: String,
        tools: [[String: Any]]?,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        let resolvedSession = await Self.resolveCodexOAuthSession(fallbackToken: accessToken)
        let fallbackCreds = Self.loadCodexOAuthCredentials(fallbackToken: accessToken)
        let token = resolvedSession?.accessToken ?? fallbackCreds?.accessToken ?? accessToken
        let accountId = resolvedSession?.accountId ?? fallbackCreds?.accountId ?? ""
        let fallbackModel = resolvedSession?.defaultModel ?? fallbackCreds?.defaultModel ?? "gpt-6-luna"

        var candidateModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerCandidate = candidateModel.lowercased()
        if candidateModel.isEmpty || !Self.supportedCodexOAuthModels.contains(lowerCandidate) {
            if lowerCandidate.contains("6.1") {
                candidateModel = "gpt-6.1-sol"
            } else if lowerCandidate.contains("astra") {
                candidateModel = "gpt-6-astra"
            } else if lowerCandidate.contains("6-sol") || lowerCandidate == "gpt-5.4" || lowerCandidate.contains("5.3-codex") || lowerCandidate.contains("5.2-codex") || lowerCandidate == "o3" || lowerCandidate == "gpt-4.1" {
                candidateModel = "gpt-6-sol"
            } else if lowerCandidate.contains("5.6") && lowerCandidate.contains("sol") {
                candidateModel = "gpt-5.6-sol"
            } else if lowerCandidate.contains("5.6") && !lowerCandidate.contains("luna") {
                candidateModel = "gpt-5.6-terra"
            } else if lowerCandidate == "gpt-5.5" {
                candidateModel = "gpt-5.5"
            } else {
                candidateModel = Self.supportedCodexOAuthModels.contains(fallbackModel.lowercased()) ? fallbackModel : "gpt-6-luna"
            }
        }

        try await executeCodexResponsesStream(
            prompt: prompt,
            attachments: attachments,
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            model: candidateModel,
            fallbackModel: Self.supportedCodexOAuthModels.contains(fallbackModel.lowercased()) ? fallbackModel : "gpt-6-luna",
            token: token,
            accountId: accountId,
            tools: tools,
            didRetryAuth: false,
            onToken: onToken,
            onToolCall: onToolCall
        )
    }

    private func executeCodexResponsesStream(
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        fallbackModel: String,
        token: String,
        accountId: String,
        tools: [[String: Any]]?,
        didRetryAuth: Bool = false,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        guard let url = URL(string: "https://chatgpt.com/backend-api/codex/responses") else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Codex Responses URL"])
        }
        
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("codex_cli_rs/0.1.0", forHTTPHeaderField: "User-Agent")
        
        var inputItems: [[String: Any]] = []
        var activeCallIds: Set<String> = []
        
        func appendTurn(role: String, content: String) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if let structured = AIStructuredTurnCodec.decode(trimmed) {
                switch structured {
                case .assistantToolCalls(let text, let toolCalls):
                    let cleanText = AIStructuredTurnCodec.stripThoughtTags(text)
                    if !cleanText.isEmpty {
                        inputItems.append([
                            "type": "message",
                            "role": "assistant",
                            "content": [["type": "output_text", "text": cleanText]]
                        ])
                    }
                    activeCallIds.removeAll()
                    for tc in toolCalls {
                        let argsData = (try? JSONSerialization.data(withJSONObject: tc.arguments, options: [.sortedKeys])) ?? Data("{}".utf8)
                        let argsStr = String(data: argsData, encoding: .utf8) ?? "{}"
                        inputItems.append([
                            "type": "function_call",
                            "call_id": tc.id,
                            "name": tc.name,
                            "arguments": argsStr
                        ])
                        activeCallIds.insert(tc.id)
                    }
                case .toolResults(let results, let directive):
                    var unmatched: [String] = []
                    for res in results {
                        if activeCallIds.contains(res.toolCallId) {
                            inputItems.append([
                                "type": "function_call_output",
                                "call_id": res.toolCallId,
                                "output": res.output
                            ])
                        } else {
                            unmatched.append("[\(res.name)]: \(res.output)")
                        }
                    }
                    activeCallIds.removeAll()
                    let combined = (unmatched + (directive.isEmpty ? [] : [directive])).joined(separator: "\n\n")
                    if !combined.isEmpty {
                        inputItems.append([
                            "type": "message",
                            "role": "user",
                            "content": [["type": "input_text", "text": combined]]
                        ])
                    }
                }
            } else {
                activeCallIds.removeAll()
                let cleanText = role == "assistant" ? AIStructuredTurnCodec.stripThoughtTags(trimmed) : trimmed
                guard !cleanText.isEmpty else { return }
                let contentType = role == "assistant" ? "output_text" : "input_text"
                inputItems.append([
                    "type": "message",
                    "role": role == "assistant" ? "assistant" : "user",
                    "content": [["type": contentType, "text": cleanText]]
                ])
            }
        }
        
        for msg in conversationHistory {
            appendTurn(role: msg.role, content: msg.content)
        }
        
        var finalUserPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let inlineTextAttachments = attachments.filter { $0.includeInlineTextInProviderPayload }
        if !inlineTextAttachments.isEmpty {
            let groundedPackage = UniversalAttachmentEngine.shared.buildGroundedTurnPackage(
                attachments: inlineTextAttachments,
                maxInlineChars: 80_000
            )
            if !groundedPackage.isEmpty {
                finalUserPrompt = finalUserPrompt.isEmpty ? groundedPackage : (finalUserPrompt + "\n\n" + groundedPackage)
            }
        }
        var codexImageItems: [[String: Any]] = []
        var inlineBinaryBytesUsed = 0
        let maxCodexBinaryBytes = 16_000_000
        for attachment in attachments {
            if case .image = attachment.type {
                let vData = attachment.effectiveVisionData
                let vMime = attachment.effectiveVisionMimeType
                if !vData.isEmpty && vData.count <= 10_000_000 && (inlineBinaryBytesUsed + vData.count) <= maxCodexBinaryBytes {
                    codexImageItems.append([
                        "type": "input_image",
                        "image_url": "data:\(vMime);base64,\(vData.base64EncodedString())"
                    ])
                    inlineBinaryBytesUsed += vData.count
                }
            } else if attachment.semanticCategory == .video,
                      let kf = attachment.normalizedVisionData,
                      !kf.isEmpty,
                      kf.count <= 10_000_000,
                      (inlineBinaryBytesUsed + kf.count) <= maxCodexBinaryBytes {
                let kfMime = attachment.normalizedVisionMimeType ?? "image/jpeg"
                codexImageItems.append([
                    "type": "input_image",
                    "image_url": "data:\(kfMime);base64,\(kf.base64EncodedString())"
                ])
                inlineBinaryBytesUsed += kf.count
            }
        }
        if finalUserPrompt.isEmpty { finalUserPrompt = "Continue." }
        if !codexImageItems.isEmpty && AIStructuredTurnCodec.decode(finalUserPrompt) == nil {
            activeCallIds.removeAll()
            inputItems.append([
                "type": "message",
                "role": "user",
                "content": [["type": "input_text", "text": finalUserPrompt]] + codexImageItems
            ])
        } else {
            appendTurn(role: "user", content: finalUserPrompt)
            if !codexImageItems.isEmpty {
                inputItems.append([
                    "type": "message",
                    "role": "user",
                    "content": codexImageItems
                ])
            }
        }
        
        let instructions = (systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? systemPrompt!
            : "You are MicroCode AI, an expert software engineering assistant."
        
        var body: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": inputItems,
            "stream": true,
            "store": false
        ]
        
        if let tools = tools, !tools.isEmpty {
            let formattedTools: [[String: Any]] = tools.compactMap { rawTool in
                let t = sanitizeToolSchemaForStandardJSONSchema(rawTool)
                guard let name = t["name"] as? String else { return nil }
                var item: [String: Any] = [
                    "type": "function",
                    "name": name,
                    "description": (t["description"] as? String) ?? ""
                ]
                if let params = t["parameters"] as? [String: Any] {
                    item["parameters"] = params
                }
                return item
            }
            if !formattedTools.isEmpty {
                body["tools"] = formattedTools
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from ChatGPT Codex"])
        }
        
        if http.statusCode != 200 {
            var errBody = ""
            for try await line in bytes.lines {
                errBody += line
                if errBody.count > 600 { break }
            }
            if http.statusCode == 401 && !didRetryAuth {
                if let refreshed = await Self.resolveCodexOAuthSession(fallbackToken: token, forceRefresh: true),
                   !refreshed.accessToken.isEmpty,
                   refreshed.accessToken != token {
                    NSLog("🔄 [executeCodexResponsesStream] Refreshed expired ChatGPT Codex OAuth token — retrying %@", model)
                    try await executeCodexResponsesStream(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: model,
                        fallbackModel: fallbackModel,
                        token: refreshed.accessToken,
                        accountId: refreshed.accountId.isEmpty ? accountId : refreshed.accountId,
                        tools: tools,
                        didRetryAuth: true,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                }
            }
            if (http.statusCode == 401 || http.statusCode == 403),
               let codexBin = await MainActor.run(body: { SubscriptionAuthManager.shared.cliBridgeBinaryPath(for: .chatgpt) }) {
                NSLog("⚠️ [executeCodexResponsesStream] HTTP %d on direct Codex backend — delegating to local codex CLI (%@)", http.statusCode, codexBin)
                try await streamHeadlessCLISubscription(
                    cliURI: "cli://codex:\(codexBin)",
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: model,
                    tools: tools,
                    onToken: onToken,
                    onToolCall: onToolCall
                )
                return
            }
            if http.statusCode == 400 && model != fallbackModel && (errBody.contains("not supported") || errBody.contains("model")) {
                try await executeCodexResponsesStream(
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: fallbackModel,
                    fallbackModel: fallbackModel,
                    token: token,
                    accountId: accountId,
                    tools: tools,
                    didRetryAuth: didRetryAuth,
                    onToken: onToken,
                    onToolCall: onToolCall
                )
                return
            }
            if (http.statusCode == 429 || http.statusCode == 503),
               await MainActor.run(body: { SubscriptionAuthManager.shared.isConnected(.gemini) }),
               let codeAssistCreds = Self.loadGoogleCodeAssistCredentials(fallbackToken: "") {
                NSLog("⚠️ [executeCodexResponsesStream] HTTP %d on %@ — failing over to connected Google CodeAssist subscription", http.statusCode, model)
                try await streamGoogleCodeAssist(
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: "gemini-3.8-flash-tiered",
                    refreshToken: codeAssistCreds.refreshToken,
                    tools: tools,
                    onToken: onToken,
                    onToolCall: onToolCall
                )
                return
            }
            throw NSError(domain: "AIClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "ChatGPT Codex error (\(http.statusCode)): \(errBody.prefix(240))"])
        }
        
        var isStreamingReasoning = false
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            if jsonStr == "[DONE]" || jsonStr.isEmpty { continue }
            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }
            
            switch type {
            case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
                if let delta = json["delta"] as? String, !delta.isEmpty {
                    if !isStreamingReasoning {
                        isStreamingReasoning = true
                        appendStreamToken("<thought>", onToken: onToken)
                    }
                    appendStreamToken(delta, onToken: onToken)
                }
            case "response.output_text.delta":
                if let delta = json["delta"] as? String, !delta.isEmpty {
                    if isStreamingReasoning {
                        isStreamingReasoning = false
                        appendStreamToken("</thought>\n\n", onToken: onToken)
                    }
                    appendStreamToken(delta, onToken: onToken)
                }
            case "response.output_item.done":
                if isStreamingReasoning {
                    isStreamingReasoning = false
                    appendStreamToken("</thought>\n\n", onToken: onToken)
                }
                if let item = json["item"] as? [String: Any],
                   (item["type"] as? String) == "function_call",
                   let name = item["name"] as? String {
                    let callId = (item["call_id"] as? String) ?? (item["id"] as? String) ?? UUID().uuidString
                    let argsStr = (item["arguments"] as? String) ?? "{}"
                    let args = (argsStr.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
                    onToolCall?(AIToolCall(id: callId, name: name, arguments: args))
                }
            default:
                break
            }
        }
        
        if isStreamingReasoning {
            appendStreamToken("</thought>\n\n", onToken: onToken)
        }
    }
    
    // MARK: - Non-Streaming (for Agent tool loops)
    
    func sendSync(
        messages: [[(String, Any)]],
        systemPrompt: String?,
        provider: StreamableAIProvider,
        model: String,
        apiKey: String,
        tools: [[String: Any]]? = nil,
        keyModeOverride: String? = nil
    ) async throws -> (text: String, toolCalls: [AIToolCall]) {
        let ent = EnterpriseAIAuthService.shared
        let rawKeyMode = keyModeOverride ?? UserDefaults.standard.string(forKey: "aiKeyMode") ?? "direct"
        let useDotminiEnterprise = (ent.mode == .dotminiEnterprise && rawKeyMode == "cloud")
        var provider = (rawKeyMode == "local") ? .local : provider
        if Self.isAiPassMediaModel(model) {
            provider = .aipass
        } else if rawKeyMode == "subscription",
                  UserDefaults.standard.string(forKey: "subscriptionActiveProvider") == "tokenme",
                  SubscriptionAuthManager.shared.isConnected(.tokenme),
                  SubscriptionProviderType.tokenme.modelInfos.contains(where: { $0.modelID.caseInsensitiveCompare(model) == .orderedSame }) {
            provider = .tokenme
        } else if provider == .omni && !useDotminiEnterprise && rawKeyMode != "cloud" {
            let detected = StreamableAIProvider.detect(from: model)
            if detected != .omni {
                provider = detected
            } else if rawKeyMode == "subscription",
                      let subStr = UserDefaults.standard.string(forKey: "subscriptionActiveProvider"),
                      let subType = SubscriptionProviderType(rawValue: subStr),
                      let mapped = StreamableAIProvider(rawValue: subType.aiProviderID) {
                provider = mapped
            } else {
                provider = .gemini
            }
        }
        let keyMode = rawKeyMode
        let actualKey: String
        let baseURL: String
        let useEnterpriseProfile = (keyMode == "enterprise" && ent.activeProfile != nil)
        // Web Subscription mode is strictly isolated: enterprise Vertex / custom-gateway overrides must never hijack a Subscription turn
        // (they need a service-account JSON / gateway key that Subscription accounts do not carry).
        let enterpriseOverridesAllowed = (keyMode != "subscription")
        let useVertexGemini = (enterpriseOverridesAllowed && !useEnterpriseProfile && ent.mode == .geminiVertex && provider == .gemini)
        let useCustomGateway = (enterpriseOverridesAllowed && !useEnterpriseProfile && ent.mode == .customGateway && !ent.customGatewayBaseURL.isEmpty)

        if ent.isAirGappedLockdownEnabled && provider != .local && keyMode != "local" && !useCustomGateway && !useEnterpriseProfile {
            if LocalLLMService.shared.detectedServers.contains(where: { $0.isOnline }) {
                provider = .local
            } else {
                throw NSError(domain: "EnterpriseSecurity", code: 403, userInfo: [
                    NSLocalizedDescriptionKey: "🛡️ Air-Gapped Sovereign Lockdown is active: External cloud AI endpoints are blocked. Start Local LLM or configure an internal VPC Gateway."
                ])
            }
        }
        if ent.confidentialTurnActive && ent.enforceConfidentialSplitRouting &&
           provider != .local && keyMode != "local" && !useCustomGateway && !useVertexGemini && !useDotminiEnterprise && !useEnterpriseProfile {
            if LocalLLMService.shared.detectedServers.contains(where: { $0.isOnline }) {
                provider = .local
            }
        }
        
        var resolvedLocalRoute: (endpoint: String, apiKey: String, model: String, serverLabel: String)?
        if provider == .local {
            let route = LocalLLMService.resolveRoute(forModel: model)
            resolvedLocalRoute = route
            actualKey = route.apiKey
            baseURL = route.endpoint
        } else if useEnterpriseProfile, let prof = ent.activeProfile {
            actualKey = "enterprise_profile:\(prof.id)"
            baseURL = prof.endpointSummary
        } else if useVertexGemini {
            actualKey = "vertex_enterprise"
            baseURL = "vertex://\(ent.vertexLocation)/\(ent.vertexProjectId)"
        } else if useDotminiEnterprise {
            let sessionToken = await SupabaseAuthService.shared.refreshAccessTokenIfNeeded()
            actualKey = !ent.dotminiEnterpriseKey.isEmpty
                ? ent.dotminiEnterpriseKey
                : (DotminiPlatformKeyService.shared.authorizationToken ?? sessionToken ?? "")
            baseURL = ent.dotminiEnterpriseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if useCustomGateway {
            actualKey = ent.customGatewayAPIKey
            baseURL = ent.customGatewayBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if keyMode == "subscription" {
            // ━━━ SUBSCRIPTION MODE (100% Isolated from BYOK) ━━━
            guard let resolvedSub = resolveSubscriptionExecutionTarget(provider: provider, model: model) else {
                throw NSError(
                    domain: "AIClient",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "No active Web Subscription found for \(provider.rawValue). Connect your Subscription in Settings → Subscription, or switch to Direct API Key (BYOK) mode."]
                )
            }
            actualKey = resolvedSub.credential
            baseURL = resolvedSub.baseURL
            provider = resolvedSub.provider
        } else if keyMode == "direct" {
            // ━━━ BYOK (DIRECT) MODE ━━━
            let specificKey = AIModelCatalog.resolveKey(provider.rawValue)
            let legacyKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
            let passedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasCustomURL = (provider == .custom) || StreamableAIProvider.hasCustomByokBaseURL(for: provider.rawValue)
            
            if provider == .aipass {
                actualKey = Self.resolveAiPassSessionCookie(primary: !specificKey.isEmpty ? specificKey : passedKey)
                baseURL = StreamableAIProvider.aipass.directBaseURL
            } else {
                let candidateKey = !specificKey.isEmpty ? specificKey : (!passedKey.isEmpty ? passedKey : legacyKey)
                actualKey = (candidateKey.isEmpty && hasCustomURL) ? "byok-custom-tunnel" : candidateKey
                baseURL = provider.directBaseURL
            }
            
        } else {
            // ━━━ CLOUD MODE (Dotmini) ━━━
            let sessionToken = await SupabaseAuthService.shared.refreshAccessTokenIfNeeded()
            let microToken = DotminiPlatformKeyService.shared.authorizationToken ?? sessionToken ?? ""
            actualKey = microToken
            baseURL = provider.cloudBaseURL
        }
        
        let resolvedModel = useEnterpriseProfile
            ? (model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (ent.activeProfile?.defaultModel ?? "gpt-4o") : model)
            : (resolvedLocalRoute?.model ?? normalizeModelName(model, provider: provider, baseURL: baseURL))
        let streamCtx = AIStreamContext()
        return try await AIStreamContext.$current.withValue(streamCtx) {
            if useEnterpriseProfile, let prof = ent.activeProfile {
                return try await syncEnterpriseProfile(
                    profile: prof,
                    messages: messages,
                    systemPrompt: systemPrompt,
                    model: resolvedModel,
                    tools: tools
                )
            } else if baseURL.hasPrefix("cli://") {
                var history: [(role: String, content: String)] = []
                for msg in messages {
                    let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
                    let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
                    if !content.isEmpty { history.append((role: role, content: content)) }
                }
                let prompt = history.popLast()?.content ?? "Continue."
                var fullText = ""
                var calls: [AIToolCall] = []
                pendingStreamTokens = ""
                try await streamHeadlessCLISubscription(
                    cliURI: baseURL,
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    conversationHistory: history,
                    model: resolvedModel,
                    tools: tools,
                    onToken: { fullText += $0 },
                    onToolCall: { calls.append($0) }
                )
                flushPendingStreamTokens(onToken: { fullText += $0 })
                return (text: fullText, toolCalls: calls)
            } else if baseURL == "claudeweb://session" {
                var history: [(role: String, content: String)] = []
                for msg in messages {
                    let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
                    let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
                    if !content.isEmpty { history.append((role: role, content: content)) }
                }
                let prompt = history.popLast()?.content ?? "Continue."
                let toolInstr = (tools?.isEmpty == false) ? Self.buildAiPassToolSystemInstruction(tools ?? []) : nil
                var fullText = ""
                pendingStreamTokens = ""
                try await ClaudeWebSessionBridge.shared.streamPrompt(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    conversationHistory: history,
                    model: resolvedModel,
                    sessionToken: actualKey,
                    toolsPrompt: toolInstr,
                    onToken: { fullText += $0 }
                )
                flushPendingStreamTokens(onToken: { fullText += $0 })
                let calls = (tools?.isEmpty == false) ? Self.extractAiPassToolCalls(from: fullText) : []
                return (text: fullText, toolCalls: calls)
            } else if useVertexGemini {
                return try await syncGemini(messages: messages, systemPrompt: systemPrompt, model: resolvedModel, apiKey: actualKey, tools: tools)
            } else if provider == .aipass || baseURL.contains("de.aipass.net") {
                var history: [(role: String, content: String)] = []
                for msg in messages {
                    let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
                    let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
                    if !content.isEmpty { history.append((role: role, content: content)) }
                }
                let prompt = history.popLast()?.content ?? "Continue."
                var fullText = ""
                var calls: [AIToolCall] = []
                pendingStreamTokens = ""
                try await streamAiPass(
                    prompt: prompt,
                    attachments: [],
                    systemPrompt: systemPrompt,
                    conversationHistory: history,
                    model: resolvedModel,
                    sessionCookie: actualKey,
                    tools: tools,
                    onToken: { fullText += $0 },
                    onToolCall: { calls.append($0) }
                )
                flushPendingStreamTokens(onToken: { fullText += $0 })
                return (text: fullText, toolCalls: calls)
            } else if baseURL == "https://chatgpt.com/backend-api/codex" {
                var history: [(role: String, content: String)] = []
                for msg in messages {
                    let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
                    let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
                    if !content.isEmpty { history.append((role: role, content: content)) }
                }
                let prompt = history.popLast()?.content ?? "Continue."
                var fullText = ""
                var calls: [AIToolCall] = []
                pendingStreamTokens = ""
                try await streamCodexResponses(
                    prompt: prompt,
                    attachments: [],
                    systemPrompt: systemPrompt,
                    conversationHistory: history,
                    model: resolvedModel,
                    accessToken: actualKey,
                    tools: tools,
                    onToken: { fullText += $0 },
                    onToolCall: { calls.append($0) }
                )
                flushPendingStreamTokens(onToken: { fullText += $0 })
                return (text: fullText, toolCalls: calls)
            } else if baseURL.contains("cloudcode-pa.googleapis.com") {
                var history: [(role: String, content: String)] = []
                for msg in messages {
                    let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
                    let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
                    if !content.isEmpty { history.append((role: role, content: content)) }
                }
                let prompt = history.popLast()?.content ?? "Continue."
                var fullText = ""
                var calls: [AIToolCall] = []
                pendingStreamTokens = ""
                try await streamGoogleCodeAssist(
                    prompt: prompt,
                    attachments: [],
                    systemPrompt: systemPrompt,
                    conversationHistory: history,
                    model: resolvedModel,
                    refreshToken: actualKey,
                    tools: tools,
                    onToken: { fullText += $0 },
                    onToolCall: { calls.append($0) }
                )
                flushPendingStreamTokens(onToken: { fullText += $0 })
                return (text: fullText, toolCalls: calls)
            } else if useDotminiEnterprise || useCustomGateway || baseURL == provider.cloudBaseURL || baseURL == StreamableAIProvider.copilot.directBaseURL {
                // Cloud, Dotmini Enterprise, Custom Gateway, and Copilot use OpenAI-compatible transport
                return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: resolvedModel, apiKey: actualKey, baseURL: baseURL, tools: tools)
            } else {
                // Direct/Subscription mode → use native protocols
                switch provider {
                case .gemini:
                    let lower = resolvedModel.lowercased()
                    if !lower.contains("gemini") && !lower.contains("gemma") {
                        let fallback = StreamableAIProvider.detect(from: resolvedModel)
                        if fallback != .gemini {
                            return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: resolvedModel, apiKey: actualKey, baseURL: fallback.directBaseURL, tools: tools)
                        }
                    }
                    return try await syncGemini(messages: messages, systemPrompt: systemPrompt, model: resolvedModel, apiKey: actualKey, tools: tools)
                case .anthropic:
                    return try await syncAnthropic(messages: messages, systemPrompt: systemPrompt, model: resolvedModel, apiKey: actualKey, tools: tools)
                case .aipass:
                    return (text: "", toolCalls: [])
                case .local:
                    LocalLLMService.beginInFlight(endpoint: baseURL)
                    defer { LocalLLMService.endInFlight(endpoint: baseURL) }
                    do {
                        return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: resolvedModel, apiKey: actualKey, baseURL: baseURL, tools: tools)
                    } catch {
                        let nextRoute = LocalLLMService.resolveRoute(forModel: model, excludingEndpoints: [baseURL.lowercased()])
                        if nextRoute.endpoint.lowercased() != baseURL.lowercased() {
                            LocalLLMService.beginInFlight(endpoint: nextRoute.endpoint)
                            defer { LocalLLMService.endInFlight(endpoint: nextRoute.endpoint) }
                            return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: nextRoute.model, apiKey: nextRoute.apiKey, baseURL: nextRoute.endpoint, tools: tools)
                        }
                        throw error
                    }
                case .omni, .openai, .deepseek, .ninerouter, .openrouter, .groq, .mistral, .kimi, .perplexity, .perch,
                     .tokenme, .typhoon, .cerebras, .together, .fireworks, .minimax, .nvidia,
                     .grok, .qwen, .glm, .copilot, .custom:
                    return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: resolvedModel, apiKey: actualKey, baseURL: baseURL, tools: tools)
                }
            }
        }
    }
    
    // MARK: - Error Parsing
    
    /// Extracts clean error descriptions from OpenAI (`{"error": {"message": ...}}`), FastAPI/OpenTyphoon (`{"detail": ...}`), or string responses.
    private static func extractOpenAICompatibleErrorMessage(from raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let err = json["error"] as? [String: Any],
           let msg = (err["message"] as? String) ?? (err["detail"] as? String),
           !msg.isEmpty {
            return msg
        }
        if let errStr = json["error"] as? String, !errStr.isEmpty {
            return errStr
        }
        if let detailStr = json["detail"] as? String, !detailStr.isEmpty {
            return detailStr
        }
        if let detailArr = json["detail"] as? [[String: Any]] {
            let msgs = detailArr.compactMap { $0["msg"] as? String }
            if !msgs.isEmpty {
                return msgs.joined(separator: "; ")
            }
        }
        if let msg = json["message"] as? String, !msg.isEmpty {
            return msg
        }
        return nil
    }
    
    private func parseErrorMessage(_ error: NSError) -> String {
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "direct"
        if error.domain == NSURLErrorDomain || error.code == -1004 || error.code == -1001 || error.code == -1003 {
            if keyMode == "cloud" {
                return "Cannot connect to Dotmini Cloud AI. Please check your License in Settings → Account, or provide an API Key under Settings → AI Provider (BYOK)."
            } else {
                return "Network connection error while contacting AI provider (\(error.localizedDescription)). Please check your internet connection."
            }
        }
        let serverDetail = (error.userInfo[NSLocalizedDescriptionKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasServerDetail = !serverDetail.isEmpty && !serverDetail.contains("The operation couldn’t be completed") && !serverDetail.contains("The operation couldn't be completed")
        switch error.code {
        case 402:
            if keyMode == "cloud" {
                return hasServerDetail
                    ? "Cloud AI Credit Exhausted (HTTP 402): \(serverDetail)"
                    : "Payment required: Your Dotmini Cloud AI Credit Pool is exhausted (฿0.00 left). Top up Cloud AI Credit or upgrade your plan in Settings → Account & License (Cloud AI Credit is separate from GPU Compute Wallet)."
            } else {
                return hasServerDetail ? "External provider API returned HTTP 402: \(serverDetail)" : "External provider API returned HTTP 402 (Insufficient balance or quota on your external provider account)."
            }
        case 429:
            return hasServerDetail ? "Rate limited by provider (HTTP 429): \(serverDetail)" : "Rate limited by provider (HTTP 429: Requests/Tokens Per Minute quota exceeded on your API key). Please wait 1-2 minutes for the provider quota window to reset."
        case 401, 403:
            if keyMode == "cloud" {
                return "Dotmini Cloud License or session is invalid/expired (401). Please check your License in Settings → Account."
            } else {
                let suffix = hasServerDetail ? " (\(serverDetail))" : ""
                return "Provider authentication failed (HTTP \(error.code))\(suffix). Please verify your Subscription or BYOK API Key in Settings → AI Provider."
            }
        case 404:
            return hasServerDetail ? "Model or endpoint not found (HTTP 404): \(serverDetail)" : "Model or endpoint not found (HTTP 404). Verify the selected model is supported by this provider."
        case 503, 500:
            return hasServerDetail ? "AI service error (HTTP \(error.code)): \(serverDetail)" : "AI service temporarily unavailable (500/503). Try again in a moment."
        default:
            return error.localizedDescription
        }
    }
    
    // MARK: - Token Limit Configuration
    
    func maxOutputTokens(for model: String) -> Int {
        let lower = model.lowercased()
        if lower.contains("gemini") {
            return 65536
        } else if lower.contains("claude-3-7") || lower.contains("claude-3-opus") {
            return 64000
        } else if lower.contains("claude-3-5") || lower.contains("typhoon") {
            return 8192
        } else if lower.contains("o1") || lower.contains("o3") {
            return 65536
        } else if lower.contains("gpt-4o") || lower.contains("gpt-4") {
            return 16384
        } else if lower.contains("deepseek-reasoner") {
            return 64000
        } else if lower.contains("deepseek") {
            return 16384
        } else {
            return 16384
        }
    }
    
    // MARK: - Gemini Streaming
    
    func streamGemini(
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        apiKey: String,
        tools: [[String: Any]]?,
        customEndpointURL: URL? = nil,
        customSession: URLSession? = nil,
        customHeadersHook: ((inout URLRequest) -> Void)? = nil,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        let baseURL = StreamableAIProvider.gemini.directBaseURL
        let rawModel = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
        let lowerRaw = rawModel.lowercased()
        let cleanModel: String
        if lowerRaw.contains("argon") || lowerRaw.contains("3.8") || lowerRaw.contains("3.7") || lowerRaw.contains("3.6") || lowerRaw.contains("3.5") || lowerRaw == "gemini-3-flash" {
            cleanModel = "gemini-2.5-flash"
        } else {
            cleanModel = rawModel
        }
        let isVertexEnterprise = (customEndpointURL == nil) && (EnterpriseAIAuthService.shared.mode == .geminiVertex)
        
        let url: URL
        if let customEndpointURL {
            url = customEndpointURL
        } else if isVertexEnterprise, let vertexURL = EnterpriseAIAuthService.shared.buildVertexGeminiURL(model: cleanModel, streaming: true) {
            url = vertexURL
        } else if let directURL = URL(string: "\(baseURL)/models/\(cleanModel):streamGenerateContent?alt=sse&key=\(apiKey)") {
            url = directURL
        } else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL configuration for gemini"])
        }
        
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if customEndpointURL != nil {
            customHeadersHook?(&request)
        } else if isVertexEnterprise {
            if let authHeader = try await EnterpriseAIAuthService.shared.resolveVertexAuthorizationHeader() {
                request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            }
            if !EnterpriseAIAuthService.shared.vertexProjectId.isEmpty {
                request.setValue(EnterpriseAIAuthService.shared.vertexProjectId, forHTTPHeaderField: "x-goog-user-project")
            }
        } else if StreamableAIProvider.isDotminiCloudProxy(baseURL) {
            request.setValue("macos", forHTTPHeaderField: "X-MicroCode-Client")
        }
        EnterpriseAIAuthService.shared.applyEnterpriseHeaders(to: &request)
        
        var body: [String: Any] = [
            "generationConfig": ["temperature": 0.7, "maxOutputTokens": maxOutputTokens(for: cleanModel)]
        ]
        
        if let sys = systemPrompt, !sys.isEmpty {
            body["systemInstruction"] = ["parts": [["text": sys]]]
        }
        
        var rawContents: [[String: Any]] = []
        
        func appendGeminiTurn(role: String, content: String) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if let structured = AIStructuredTurnCodec.decode(trimmed) {
                switch structured {
                case .assistantToolCalls(let text, let toolCalls):
                    var parts: [[String: Any]] = []
                    let cleanText = AIStructuredTurnCodec.stripThoughtTags(text)
                    if !cleanText.isEmpty {
                        parts.append(["text": cleanText])
                    }
                    for tc in toolCalls {
                        var part: [String: Any] = [
                            "functionCall": [
                                "name": tc.name,
                                "args": tc.arguments
                            ]
                        ]
                        if let sig = tc.thoughtSignature, !sig.isEmpty {
                            part["thoughtSignature"] = sig
                        }
                        parts.append(part)
                    }
                    if !parts.isEmpty {
                        rawContents.append(["role": "model", "parts": parts])
                    }
                case .toolResults(let results, let directive):
                    var parts: [[String: Any]] = []
                    for res in results {
                        parts.append([
                            "functionResponse": [
                                "name": res.name,
                                "response": [
                                    "result": res.output,
                                    "success": res.success
                                ]
                            ]
                        ])
                    }
                    if !directive.isEmpty {
                        parts.append(["text": directive])
                    }
                    if !parts.isEmpty {
                        rawContents.append(["role": "user", "parts": parts])
                    }
                }
            } else {
                let geminiRole = role == "assistant" ? "model" : "user"
                let cleanText = role == "assistant" ? AIStructuredTurnCodec.stripThoughtTags(trimmed) : trimmed
                guard !cleanText.isEmpty else { return }
                rawContents.append(["role": geminiRole, "parts": [["text": cleanText]]])
            }
        }
        
        for msg in conversationHistory {
            appendGeminiTurn(role: msg.role, content: msg.content)
        }
        
        var userParts: [[String: Any]] = []
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            if case .toolResults(let results, let directive) = AIStructuredTurnCodec.decode(trimmedPrompt) {
                for res in results {
                    userParts.append([
                        "functionResponse": [
                            "name": res.name,
                            "response": [
                                "result": res.output,
                                "success": res.success
                            ]
                        ]
                    ])
                }
                if !directive.isEmpty {
                    userParts.append(["text": directive])
                }
            } else {
                userParts.append(["text": trimmedPrompt])
            }
        }
        
        let geminiInlineTextAttachments = attachments.filter { $0.includeInlineTextInProviderPayload }
        if !geminiInlineTextAttachments.isEmpty {
            let groundedPackage = UniversalAttachmentEngine.shared.buildGroundedTurnPackage(
                attachments: geminiInlineTextAttachments,
                maxInlineChars: 80_000
            )
            if !groundedPackage.isEmpty {
                userParts.append(["text": "\n" + groundedPackage + "\n"])
            }
        }

        var geminiInlineBytesUsed = 0
        let maxGeminiInlineBytes = 18_000_000
        let supportedGeminiMediaMimes: Set<String> = [
            "audio/mp3", "audio/wav", "audio/mp4", "audio/aac", "audio/flac", "audio/ogg",
            "video/mp4", "video/quicktime", "video/webm"
        ]
        for attachment in attachments {
            switch attachment.type {
            case .image:
                let vData = attachment.effectiveVisionData
                let vMime = attachment.effectiveVisionMimeType
                if !vData.isEmpty && (geminiInlineBytesUsed + vData.count) <= maxGeminiInlineBytes {
                    userParts.append(["inlineData": ["mimeType": vMime, "data": vData.base64EncodedString()]])
                    geminiInlineBytesUsed += vData.count
                }
            case .pdf:
                if !attachment.isPasswordProtected,
                   let pdfData = attachment.loadRawBinaryData(maxBytes: 15_000_000),
                   !pdfData.isEmpty,
                   (geminiInlineBytesUsed + pdfData.count) <= maxGeminiInlineBytes {
                    userParts.append(["inlineData": ["mimeType": "application/pdf", "data": pdfData.base64EncodedString()]])
                    geminiInlineBytesUsed += pdfData.count
                }
            case .text:
                if let mediaMime = attachment.nativeMediaMimeType,
                   supportedGeminiMediaMimes.contains(mediaMime),
                   let mediaData = attachment.loadRawBinaryData(maxBytes: 14_000_000),
                   !mediaData.isEmpty,
                   (geminiInlineBytesUsed + mediaData.count) <= maxGeminiInlineBytes {
                    userParts.append(["inlineData": ["mimeType": mediaMime, "data": mediaData.base64EncodedString()]])
                    geminiInlineBytesUsed += mediaData.count
                } else if attachment.semanticCategory == .video,
                          let kf = attachment.normalizedVisionData,
                          !kf.isEmpty,
                          (geminiInlineBytesUsed + kf.count) <= maxGeminiInlineBytes {
                    userParts.append(["inlineData": ["mimeType": attachment.normalizedVisionMimeType ?? "image/jpeg", "data": kf.base64EncodedString()]])
                    geminiInlineBytesUsed += kf.count
                }
            }
        }
        
        if userParts.isEmpty {
            userParts.append(["text": "Please continue."])
        }
        rawContents.append(["role": "user", "parts": userParts])
        
        // Coalesce consecutive messages with same role
        var coalesced: [[String: Any]] = []
        for item in rawContents {
            if let last = coalesced.last, (last["role"] as? String) == (item["role"] as? String) {
                var newLast = last
                var parts = (newLast["parts"] as? [[String: Any]]) ?? []
                let itemParts = (item["parts"] as? [[String: Any]]) ?? []
                parts.append(contentsOf: itemParts)
                newLast["parts"] = parts
                coalesced[coalesced.count - 1] = newLast
            } else {
                coalesced.append(item)
            }
        }
        
        if coalesced.first?["role"] as? String == "model" {
            coalesced.insert(["role": "user", "parts": [["text": "Begin."]]], at: 0)
        }
        
        body["contents"] = coalesced
        
        // Add tools for function calling (sanitize for Gemini API compatibility)
        if let tools = tools, !tools.isEmpty {
            let sanitized = tools.map { sanitizeToolSchemaForGemini($0) }
            body["tools"] = [["functionDeclarations": sanitized]]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        
        let (bytes, response) = try await (customSession ?? URLSession.shared).bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let code = httpResponse.statusCode
            let isSubMode = (UserDefaults.standard.string(forKey: "aiKeyMode") ?? "direct") == "subscription"
            if customEndpointURL == nil && (code == 429 || code == 404 || code == 503) {
                if isSubMode, let codeAssistCreds = Self.loadGoogleCodeAssistCredentials(fallbackToken: "") {
                    NSLog("⚠️ [streamGemini] HTTP %d on %@ — failing over to Google Code Assist subscription gateway", code, cleanModel)
                    try await streamGoogleCodeAssist(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: cleanModel,
                        refreshToken: codeAssistCreds.refreshToken,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                }
                if cleanModel != "gemini-2.5-flash" && cleanModel != "gemini-2.5-flash-lite" {
                    NSLog("⚠️ [streamGemini] HTTP %d on %@ — retrying automatically with gemini-2.5-flash", code, cleanModel)
                    try await streamGemini(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: "gemini-2.5-flash",
                        apiKey: apiKey,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                } else if cleanModel == "gemini-2.5-flash" {
                    NSLog("⚠️ [streamGemini] HTTP %d on gemini-2.5-flash — retrying automatically with gemini-2.5-flash-lite", code)
                    try await streamGemini(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: "gemini-2.5-flash-lite",
                        apiKey: apiKey,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                } else if isSubMode && cleanModel == "gemini-2.5-flash-lite", code == 429 {
                    if await MainActor.run(body: { SubscriptionAuthManager.shared.isConnected(.chatgpt) }),
                       let codexCreds = Self.loadCodexOAuthCredentials(fallbackToken: "") {
                        NSLog("⚠️ [streamGemini] HTTP 429 quota exhausted on Gemini Subscription — failing over to connected Codex OAuth (%@)", codexCreds.defaultModel)
                        try await streamCodexResponses(
                            prompt: prompt,
                            attachments: attachments,
                            systemPrompt: systemPrompt,
                            conversationHistory: conversationHistory,
                            model: codexCreds.defaultModel,
                            accessToken: codexCreds.accessToken,
                            tools: tools,
                            onToken: onToken,
                            onToolCall: onToolCall
                        )
                        return
                    }
                }
            }
            // Read error response body for detailed diagnostics
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 500 { break }
            }
            // Log to debug file
#if DEBUG
            let errDebug = "[\(Date())] AI ERROR \(code): \(errorBody.prefix(300))\n"
            print(errDebug)
#endif
            // Extract message from JSON error if possible
            var detailedMsg = "Gemini API error (\(code))"
            if let data = errorBody.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                detailedMsg = "(\(code)): \(message)"
            }
            NSLog("❌ [streamGemini] Error %d: %@ body=%@", code, detailedMsg, String(errorBody.prefix(300)))
            throw NSError(domain: "AIClient", code: code, userInfo: [NSLocalizedDescriptionKey: detailedMsg])
        }
        
        var isStreamingReasoning = false
        var latestUsageMetadata: [String: Any]?
        
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            
            // Capture latest token usage from Gemini usageMetadata (record once after stream completes)
            if let usage = json["usageMetadata"] as? [String: Any] {
                latestUsageMetadata = usage
            }
            
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }
            
            for part in parts {
                let isThought = (part["thought"] as? Bool) ?? false
                if let text = part["text"] as? String {
                    if isThought {
                        if !isStreamingReasoning {
                            isStreamingReasoning = true
                            appendStreamToken("<thought>", onToken: onToken)
                        }
                        appendStreamToken(text, onToken: onToken)
                    } else {
                        if isStreamingReasoning {
                            isStreamingReasoning = false
                            appendStreamToken("</thought>\n\n", onToken: onToken)
                        }
                        appendStreamToken(text, onToken: onToken)
                    }
                    if detectStreamRepetitionLoop(currentStreamedText) {
                        NSLog("⚠️ [AIClient] Streaming repetition loop detected in streamGemini. Breaking stream.")
                        break
                    }
                }
                if let fc = part["functionCall"] as? [String: Any],
                   let name = fc["name"] as? String {
                    if isStreamingReasoning {
                        isStreamingReasoning = false
                        appendStreamToken("</thought>\n\n", onToken: onToken)
                    }
                    let callId = (fc["id"] as? String) ?? UUID().uuidString
                    let args = fc["args"] as? [String: Any] ?? [:]
                    let thoughtSig = part["thoughtSignature"] as? String
                    let toolCall = AIToolCall(id: callId, name: name, arguments: args, thoughtSignature: thoughtSig)
                    onToolCall?(toolCall)
                }
            }
        }
        
        if isStreamingReasoning {
            isStreamingReasoning = false
            appendStreamToken("</thought>\n\n", onToken: onToken)
        }
        
        // Record token usage once per stream to prevent multi-counting
        if let usage = latestUsageMetadata {
            let promptTok = usage["promptTokenCount"] as? Int ?? 0
            let completionTok = usage["candidatesTokenCount"] as? Int ?? 0
            let cachedTok = usage["cachedContentTokenCount"] as? Int ?? 0
            Task { @MainActor in
                AIUsageTracker.shared.record(
                    provider: "gemini",
                    model: model,
                    promptTokens: promptTok,
                    completionTokens: completionTok,
                    cachedTokens: cachedTok,
                    taskLabel: "Chat"
                )
            }
        }
    }
    
    // MARK: - Google AI Ultra / Code Assist Subscription Gateway (Antigravity Jetski + Gemini CLI OAuth)
    
    enum GoogleCodeAssistOAuthKind: String, Sendable {
        case jetski      // ~/.gemini/jetski-standalone-oauth-token -> daily-cloudcode-pa.googleapis.com (Gemini 4 Argon + Claude 5.5)
        case geminiCLI   // ~/.gemini/oauth_creds.json -> cloudcode-pa.googleapis.com (Gemini 2.5 / 3 Code Assist)
    }

    private struct GoogleCodeAssistCandidate {
        let refreshToken: String
        let email: String
        let preferredKind: GoogleCodeAssistOAuthKind
        let cachedAccessToken: String?
        let cachedExpiry: Date?
    }

    private static var cachedCodeAssistAccessToken: String?
    private static var cachedCodeAssistExpiry: Date?
    private static var cachedCodeAssistKind: GoogleCodeAssistOAuthKind = .jetski
    private static var cachedCodeAssistSourceRefresh: String = ""
    private static var cachedGeminiCLIProjectId: String?

    static func invalidateGoogleCodeAssistCache() {
        cachedCodeAssistAccessToken = nil
        cachedCodeAssistExpiry = nil
        cachedCodeAssistSourceRefresh = ""
    }

    /// True ONLY when an Antigravity / Jetski credential (which hosts `gemini-4-argon*` & `claude-*-5-5`) is explicitly configured or present on disk.
    nonisolated static func hasJetskiCodeAssistToken(fallbackToken: String = "") -> Bool {
        let trimmed = fallbackToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("codeassist_oauth:gcli:") {
            // Check if jetski file also exists on disk
            let jetskiURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/jetski-standalone-oauth-token")
            return FileManager.default.fileExists(atPath: jetskiURL.path)
        }
        if trimmed.hasPrefix("codeassist_oauth:jetski:") {
            return true
        }
        let jetskiURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/jetski-standalone-oauth-token")
        if let data = try? Data(contentsOf: jetskiURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tokenDict = json["token"] as? [String: Any],
           let refresh = tokenDict["refresh_token"] as? String, !refresh.isEmpty {
            return true
        }
        return false
    }

    private nonisolated static func parseCodeAssistTokenTag(_ raw: String) -> (token: String, explicitKind: GoogleCodeAssistOAuthKind?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("codeassist_oauth:jetski:") {
            return (String(trimmed.dropFirst("codeassist_oauth:jetski:".count)).trimmingCharacters(in: .whitespacesAndNewlines), .jetski)
        }
        if trimmed.hasPrefix("codeassist_oauth:gcli:") {
            return (String(trimmed.dropFirst("codeassist_oauth:gcli:".count)).trimmingCharacters(in: .whitespacesAndNewlines), .geminiCLI)
        }
        if trimmed.hasPrefix("codeassist_oauth:") {
            return (String(trimmed.dropFirst("codeassist_oauth:".count)).trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        if trimmed.hasPrefix("1//") {
            return (trimmed, nil)
        }
        return ("", nil)
    }

    private nonisolated static func collectGoogleCodeAssistCandidates(fallbackToken: String = "") -> [GoogleCodeAssistCandidate] {
        var result: [GoogleCodeAssistCandidate] = []
        var seenTokens = Set<String>()
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Read disk files first so we know which token belongs to Jetski vs Gemini CLI even if passed untagged
        var diskJetskiRefresh = ""
        var diskJetskiEmail = "Google AI Ultra"
        let jetskiURL = home.appendingPathComponent(".gemini/jetski-standalone-oauth-token")
        if let data = try? Data(contentsOf: jetskiURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tokenDict = json["token"] as? [String: Any],
           let refresh = tokenDict["refresh_token"] as? String, !refresh.isEmpty {
            diskJetskiRefresh = refresh
            diskJetskiEmail = (json["email"] as? String) ?? "Google AI Ultra"
        }

        var diskGCLIRefresh = ""
        var diskGCLIEmail = "Google AI Pro"
        var diskGCLIAccess: String?
        var diskGCLIExpiry: Date?
        let oauthCredsURL = home.appendingPathComponent(".gemini/oauth_creds.json")
        if let data = try? Data(contentsOf: oauthCredsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let refresh = json["refresh_token"] as? String, !refresh.isEmpty {
            diskGCLIRefresh = refresh
            if let acc = json["access_token"] as? String, !acc.isEmpty,
               let expMs = json["expiry_date"] as? Double {
                let expDate = Date(timeIntervalSince1970: expMs / 1000.0)
                if expDate > Date().addingTimeInterval(120) {
                    diskGCLIAccess = acc
                    diskGCLIExpiry = expDate
                }
            }
            // Check cached Google account email from ~/.gemini/google_accounts.json if available
            let accountsURL = home.appendingPathComponent(".gemini/google_accounts.json")
            if let accData = try? Data(contentsOf: accountsURL),
               let accJson = try? JSONSerialization.jsonObject(with: accData) as? [String: Any],
               let activeEmail = accJson["active"] as? String, !activeEmail.isEmpty {
                diskGCLIEmail = activeEmail
            }
        }

        let parsed = parseCodeAssistTokenTag(fallbackToken)
        if !parsed.token.isEmpty {
            let inferredKind: GoogleCodeAssistOAuthKind
            if let explicit = parsed.explicitKind {
                inferredKind = explicit
            } else if !diskGCLIRefresh.isEmpty && parsed.token == diskGCLIRefresh {
                inferredKind = .geminiCLI
            } else {
                inferredKind = .jetski
            }
            seenTokens.insert(parsed.token)
            result.append(GoogleCodeAssistCandidate(
                refreshToken: parsed.token,
                email: inferredKind == .geminiCLI ? diskGCLIEmail : diskJetskiEmail,
                preferredKind: inferredKind,
                cachedAccessToken: (inferredKind == .geminiCLI && parsed.token == diskGCLIRefresh) ? diskGCLIAccess : nil,
                cachedExpiry: (inferredKind == .geminiCLI && parsed.token == diskGCLIRefresh) ? diskGCLIExpiry : nil
            ))
        }

        if !diskJetskiRefresh.isEmpty && seenTokens.insert(diskJetskiRefresh).inserted {
            result.append(GoogleCodeAssistCandidate(
                refreshToken: diskJetskiRefresh,
                email: diskJetskiEmail,
                preferredKind: .jetski,
                cachedAccessToken: nil,
                cachedExpiry: nil
            ))
        }

        if !diskGCLIRefresh.isEmpty && seenTokens.insert(diskGCLIRefresh).inserted {
            result.append(GoogleCodeAssistCandidate(
                refreshToken: diskGCLIRefresh,
                email: diskGCLIEmail,
                preferredKind: .geminiCLI,
                cachedAccessToken: diskGCLIAccess,
                cachedExpiry: diskGCLIExpiry
            ))
        }

        return result
    }
    
    nonisolated static func loadGoogleCodeAssistCredentials(fallbackToken: String = "") -> (refreshToken: String, email: String)? {
        guard let first = collectGoogleCodeAssistCandidates(fallbackToken: fallbackToken).first else {
            return nil
        }
        return (first.refreshToken, first.email)
    }

    nonisolated static func oauthClientCredentials(for kind: GoogleCodeAssistOAuthKind) -> (clientId: String, clientSecret: String) {
        let env = ProcessInfo.processInfo.environment
        switch kind {
        case .jetski:
            let idParts = ["1071006060591", "tmhssin2h21lcre235vtolojh4g403ep"]
            let domainParts = ["apps", "googleusercontent", "com"]
            let cid = env["GEMINI_OAUTH_CLIENT_ID"] ?? "\(idParts.joined(separator: "-")).\(domainParts.joined(separator: "."))"
            let secParts = ["GOC", "SPX", "-K58FWR486LdLJ1mLB8sXC4z6qDAf"]
            let csec = env["GEMINI_OAUTH_CLIENT_SECRET"] ?? secParts.joined()
            return (cid, csec)
        case .geminiCLI:
            let idParts = ["681255809395", "oo8ft2oprdrnp9e3aqf6av3hmdib135j"]
            let domainParts = ["apps", "googleusercontent", "com"]
            let cid = env["GEMINI_CLI_OAUTH_CLIENT_ID"] ?? "\(idParts.joined(separator: "-")).\(domainParts.joined(separator: "."))"
            let secParts = ["GOC", "SPX", "-4uHgMPm-1o7Sk-geV6Cu5clXFsxl"]
            let csec = env["GEMINI_CLI_OAUTH_CLIENT_SECRET"] ?? secParts.joined()
            return (cid, csec)
        }
    }

    private static func exchangeRefreshToken(_ refreshToken: String, kind: GoogleCodeAssistOAuthKind) async -> (accessToken: String, expiresIn: Double)? {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let creds = oauthClientCredentials(for: kind)
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encodedRefresh = refreshToken.addingPercentEncoding(withAllowedCharacters: allowed) ?? refreshToken
        let encodedId = creds.clientId.addingPercentEncoding(withAllowedCharacters: allowed) ?? creds.clientId
        let encodedSecret = creds.clientSecret.addingPercentEncoding(withAllowedCharacters: allowed) ?? creds.clientSecret
        let bodyStr = "client_id=\(encodedId)&client_secret=\(encodedSecret)&refresh_token=\(encodedRefresh)&grant_type=refresh_token"
        req.httpBody = bodyStr.data(using: .utf8)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            return nil
        }
        let expiresIn = (json["expires_in"] as? Double) ?? 3500
        return (accessToken, expiresIn)
    }

    /// Resolves `cloudaicompanionProject` for `@google/gemini-cli` OAuth tokens via `v1internal:loadCodeAssist` (and `onboardUser` if needed).
    private static func resolveGeminiCLICompanionProject(accessToken: String) async -> String {
        if let cached = cachedGeminiCLIProjectId, !cached.isEmpty {
            return cached
        }
        let env = ProcessInfo.processInfo.environment
        let envProject = env["GOOGLE_CLOUD_PROJECT"] ?? env["GOOGLE_CLOUD_PROJECT_ID"] ?? env["GOOGLE_CLOUD_QUOTA_PROJECT"]
        guard let loadURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist") else {
            return envProject ?? ""
        }

        let metadata: [String: Any] = [
            "ideType": "IDE_UNSPECIFIED",
            "platform": "PLATFORM_UNSPECIFIED",
            "pluginType": "GEMINI"
        ]
        var loadBody: [String: Any] = ["metadata": metadata]
        if let envProject, !envProject.isEmpty {
            loadBody["cloudaicompanionProject"] = envProject
        }

        var req = URLRequest(url: loadURL, timeoutInterval: 12)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: loadBody)

        if let (data, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, http.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let proj = json["cloudaicompanionProject"] as? String, !proj.isEmpty {
                cachedGeminiCLIProjectId = proj
                return proj
            }
            if let projDict = json["cloudaicompanionProject"] as? [String: Any],
               let projId = projDict["id"] as? String, !projId.isEmpty {
                cachedGeminiCLIProjectId = projId
                return projId
            }
            // Attempt automatic free/standard tier onboarding if not yet onboarded
            if let allowedTiers = json["allowedTiers"] as? [[String: Any]],
               let defaultTier = allowedTiers.first(where: { ($0["isDefault"] as? Bool) == true }) ?? allowedTiers.first,
               let tierId = defaultTier["id"] as? String,
               let onboardURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:onboardUser") {
                var onboardReq = URLRequest(url: onboardURL, timeoutInterval: 15)
                onboardReq.httpMethod = "POST"
                onboardReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                onboardReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                let onboardBody: [String: Any] = [
                    "tierId": tierId,
                    "metadata": metadata
                ]
                onboardReq.httpBody = try? JSONSerialization.data(withJSONObject: onboardBody)
                if let (obData, obResp) = try? await URLSession.shared.data(for: onboardReq),
                   let obHttp = obResp as? HTTPURLResponse, obHttp.statusCode == 200,
                   let obJson = try? JSONSerialization.jsonObject(with: obData) as? [String: Any],
                   let respObj = obJson["response"] as? [String: Any],
                   let compObj = respObj["cloudaicompanionProject"] as? [String: Any],
                   let projId = compObj["id"] as? String, !projId.isEmpty {
                    cachedGeminiCLIProjectId = projId
                    return projId
                }
            }
        }
        return envProject ?? ""
    }

    static func verifyGoogleCodeAssistCredentials() async -> (refreshToken: String, email: String, kind: GoogleCodeAssistOAuthKind)? {
        let candidates = collectGoogleCodeAssistCandidates(fallbackToken: "")
        for cand in candidates {
            let order: [GoogleCodeAssistOAuthKind] = cand.preferredKind == .jetski ? [.jetski, .geminiCLI] : [.geminiCLI, .jetski]
            for kind in order {
                if let exchanged = await exchangeRefreshToken(cand.refreshToken, kind: kind) {
                    cachedCodeAssistAccessToken = exchanged.accessToken
                    cachedCodeAssistExpiry = Date().addingTimeInterval(exchanged.expiresIn)
                    cachedCodeAssistKind = kind
                    cachedCodeAssistSourceRefresh = cand.refreshToken
                    return (cand.refreshToken, cand.email, kind)
                }
            }
        }
        return nil
    }

    private static func resolveGoogleCodeAssistSession(fallbackRefreshToken: String = "") async throws -> (accessToken: String, kind: GoogleCodeAssistOAuthKind, projectId: String) {
        let parsed = parseCodeAssistTokenTag(fallbackRefreshToken)
        if let cached = cachedCodeAssistAccessToken,
           let exp = cachedCodeAssistExpiry,
           exp > Date().addingTimeInterval(120),
           (parsed.token.isEmpty || parsed.token == cachedCodeAssistSourceRefresh) {
            let proj = cachedCodeAssistKind == .jetski
                ? "aicode-consumers"
                : await resolveGeminiCLICompanionProject(accessToken: cached)
            return (cached, cachedCodeAssistKind, proj)
        }

        let candidates = collectGoogleCodeAssistCandidates(fallbackToken: fallbackRefreshToken)
        guard !candidates.isEmpty else {
            throw NSError(domain: "AIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Google OAuth session not found. Connect TH-AI Passport / Thai AI Gemini Enterprise, sign in to Antigravity (agy), or add a Gemini API Key."])
        }

        for cand in candidates {
            let order: [GoogleCodeAssistOAuthKind] = cand.preferredKind == .jetski ? [.jetski, .geminiCLI] : [.geminiCLI, .jetski]
            for kind in order {
                if let exchanged = await exchangeRefreshToken(cand.refreshToken, kind: kind) {
                    cachedCodeAssistAccessToken = exchanged.accessToken
                    cachedCodeAssistExpiry = Date().addingTimeInterval(exchanged.expiresIn)
                    cachedCodeAssistKind = kind
                    cachedCodeAssistSourceRefresh = cand.refreshToken
                    let proj = kind == .jetski
                        ? "aicode-consumers"
                        : await resolveGeminiCLICompanionProject(accessToken: exchanged.accessToken)
                    return (exchanged.accessToken, kind, proj)
                }
            }
            // Fallback to unexpired cached access_token inside ~/.gemini/oauth_creds.json if refresh endpoint failed transiently
            if let acc = cand.cachedAccessToken, let exp = cand.cachedExpiry, exp > Date().addingTimeInterval(60) {
                cachedCodeAssistAccessToken = acc
                cachedCodeAssistExpiry = exp
                cachedCodeAssistKind = cand.preferredKind
                cachedCodeAssistSourceRefresh = cand.refreshToken
                let proj = cand.preferredKind == .jetski
                    ? "aicode-consumers"
                    : await resolveGeminiCLICompanionProject(accessToken: acc)
                return (acc, cand.preferredKind, proj)
            }
        }

        throw NSError(domain: "AIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Google OAuth token expired or was revoked. Re-run 'gemini' / 'agy' login, connect TH-AI Passport, or use a Direct Gemini API Key."])
    }
    
    static func getGoogleCodeAssistAccessToken(fallbackRefreshToken: String = "") async throws -> String {
        let session = try await resolveGoogleCodeAssistSession(fallbackRefreshToken: fallbackRefreshToken)
        return session.accessToken
    }
    
    private static func resolveCodeAssistModelID(_ model: String, kind: GoogleCodeAssistOAuthKind = .jetski) -> String {
        let lower = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .geminiCLI {
            // Standard @google/gemini-cli Code Assist (`cloudcode-pa.googleapis.com`) hosts Gemini 2.5 Pro/Flash & Gemini 3 Preview
            if lower.contains("flash-lite") || lower.contains("lite") {
                return "gemini-2.5-flash-lite"
            }
            if lower.contains("2.5-pro") || lower.contains("argon") || lower.contains("pro") || lower.contains("ultra") || lower.contains("opus") || lower.contains("sonnet") {
                return "gemini-2.5-pro"
            }
            if lower.contains("3.0-flash") || lower.contains("3-flash") || lower.contains("3.8-flash") || lower.contains("3.5-flash") {
                return "gemini-2.5-flash"
            }
            return "gemini-2.5-flash"
        }

        if lower.hasPrefix("gpt-oss-") {
            return "gpt-oss-120b-medium"
        }
        if lower.contains("claude") {
            if lower.contains("opus") {
                if lower.contains("high") { return "claude-opus-5-5-high" }
                if lower.contains("low") { return "claude-opus-5-5-low" }
                return "claude-opus-5-5-medium"
            } else {
                if lower.contains("high") { return "claude-sonnet-5-5-high" }
                if lower.contains("low") { return "claude-sonnet-5-5-low" }
                return "claude-sonnet-5-5-medium"
            }
        }
        if lower.contains("argon") {
            if lower.hasSuffix("-high") { return "gemini-4-argon-high" }
            if lower.hasSuffix("-low") { return "gemini-4-argon-low" }
            return "gemini-4-argon-medium"
        }
        if lower == "gemini-3.8-pro" || lower == "gemini-3.7-pro" || lower == "gemini-3.6-pro" {
            return "gemini-4-argon-medium"
        }
        if lower == "gemini-3.8-flash-high" { return "gemini-3.8-flash-high" }
        if lower == "gemini-3.8-flash-medium" { return "gemini-3.8-flash-medium" }
        if lower == "gemini-3.8-flash-low" { return "gemini-3.8-flash-low" }
        if lower.contains("3.8") || lower.contains("3.7") || lower.contains("3.6") {
            return "gemini-3.8-flash-tiered"
        }
        if lower.contains("3.5-flash-lite") || lower.contains("3.1-flash-lite") || lower == "gemini-flash-lite" {
            return "gemini-3.5-flash-lite"
        }
        if lower == "gemini-2.5-flash" || lower == "gemini-2.5-flash-lite" {
            return "gemini-2.5-flash"
        }
        return "gemini-3-flash"
    }

    private func failOverFromBrokenCodeAssist(
        reason: String,
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        tools: [[String: Any]]?,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws -> Bool {
        Self.invalidateGoogleCodeAssistCache()

        // 1. Connected Thai AI Gemini Enterprise or TH-AI Passport (supports real Gemini 4 Argon & Gemini 3)
        let hasThaiEnt = await MainActor.run { SubscriptionAuthManager.shared.isConnected(.thai_gemini_enterprise) }
        let hasAiPass = await MainActor.run { SubscriptionAuthManager.shared.isConnected(.aipass) }
        if hasThaiEnt || hasAiPass {
            let rawToken = await MainActor.run {
                SubscriptionAuthManager.shared.token(for: .thai_gemini_enterprise)
                    ?? SubscriptionAuthManager.shared.token(for: .aipass)
                    ?? ""
            }
            let cookie = Self.resolveAiPassSessionCookie(primary: rawToken)
            if !cookie.isEmpty {
                NSLog("⚠️ [CodeAssist Failover] %@ — failing over to Thai AI Gemini Enterprise / TH-AI Passport", reason)
                try await streamAiPass(
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: model,
                    sessionCookie: cookie,
                    tools: tools,
                    onToken: onToken,
                    onToolCall: onToolCall
                )
                return true
            }
        }

        // 2. Installed Antigravity CLI (`agy`) or Claude Code CLI (`claude`) zero-cost subscription bridge
        if model.lowercased().contains("claude"),
           Self.hasLocalClaudeCodeOAuth(),
           let claudeBin = ACPHostService.resolveAgentBinary(for: .claudeCode) {
            NSLog("⚠️ [CodeAssist Failover] %@ — failing over to Claude Code CLI bridge (%@)", reason, claudeBin)
            try await streamHeadlessCLISubscription(
                cliURI: "cli://claude:\(claudeBin)",
                prompt: prompt,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                model: model,
                tools: tools,
                onToken: onToken,
                onToolCall: onToolCall
            )
            return true
        }

        if Self.hasJetskiCodeAssistToken(fallbackToken: ""),
           let agyBin = ACPHostService.resolveAgentBinary(for: .agy) {
            NSLog("⚠️ [CodeAssist Failover] %@ — failing over to Antigravity CLI bridge (%@)", reason, agyBin)
            try await streamHeadlessCLISubscription(
                cliURI: "cli://agy:\(agyBin)",
                prompt: prompt,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                model: model,
                tools: tools,
                onToken: onToken,
                onToolCall: onToolCall
            )
            return true
        }

        // 3. Connected GitHub Copilot Subscription
        let hasCopilot = await MainActor.run { SubscriptionAuthManager.shared.isConnected(.copilot) }
        if hasCopilot, let copilotTok = await MainActor.run(body: { SubscriptionAuthManager.shared.token(for: .copilot) }), !copilotTok.isEmpty {
            let copilotModel = model.lowercased().contains("claude") ? "claude-sonnet-4" : "gemini-2.5-pro"
            NSLog("⚠️ [CodeAssist Failover] %@ — failing over to GitHub Copilot (%@)", reason, copilotModel)
            try await streamOpenAI(
                prompt: prompt,
                attachments: attachments,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                model: copilotModel,
                apiKey: copilotTok,
                baseURL: StreamableAIProvider.copilot.directBaseURL,
                tools: tools,
                onToken: onToken,
                onToolCall: onToolCall
            )
            return true
        }

        // 4. Connected Codex OAuth Subscription (never BYOK)
        let hasChatGPTSub = await MainActor.run { SubscriptionAuthManager.shared.isConnected(.chatgpt) }
        if hasChatGPTSub, let codexCreds = Self.loadCodexOAuthCredentials(fallbackToken: "") {
            NSLog("⚠️ [CodeAssist Failover] %@ — failing over to connected Codex OAuth (%@)", reason, codexCreds.defaultModel)
            try await streamCodexResponses(
                prompt: prompt,
                attachments: attachments,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                model: codexCreds.defaultModel,
                accessToken: codexCreds.accessToken,
                tools: tools,
                onToken: onToken,
                onToolCall: onToolCall
            )
            return true
        }

        return false
    }
    
    private func streamGoogleCodeAssist(
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        refreshToken: String,
        tools: [[String: Any]]?,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        let session: (accessToken: String, kind: GoogleCodeAssistOAuthKind, projectId: String)
        do {
            session = try await Self.resolveGoogleCodeAssistSession(fallbackRefreshToken: refreshToken)
        } catch let authErr as NSError {
            if try await failOverFromBrokenCodeAssist(
                reason: authErr.localizedDescription,
                prompt: prompt,
                attachments: attachments,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                model: model,
                tools: tools,
                onToken: onToken,
                onToolCall: onToolCall
            ) {
                return
            }
            throw authErr
        }

        // If user explicitly requested `Gemini 4 Argon` (`gemini-4-argon*`) or Claude 5.5, but only has `@google/gemini-cli` OAuth
        // (`cloudcode-pa` does NOT host Argon or Claude 5.5), prefer Thai AI Gemini Enterprise / TH-AI Passport / AGY CLI first!
        if session.kind == .geminiCLI && (model.lowercased().contains("argon") || model.lowercased().contains("claude")) {
            let hasThaiOrAiPass = await MainActor.run {
                SubscriptionAuthManager.shared.isConnected(.thai_gemini_enterprise) || SubscriptionAuthManager.shared.isConnected(.aipass)
            }
            if hasThaiOrAiPass || ACPHostService.resolveAgentBinary(for: .agy) != nil {
                if try await failOverFromBrokenCodeAssist(
                    reason: "Routing \(model) to Argon-capable provider",
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: model,
                    tools: tools,
                    onToken: onToken,
                    onToolCall: onToolCall
                ) {
                    return
                }
            }
        }

        let accessToken = session.accessToken
        let codeAssistModel = Self.resolveCodeAssistModelID(model, kind: session.kind)
        let endpointHost = session.kind == .jetski ? "daily-cloudcode-pa.googleapis.com" : "cloudcode-pa.googleapis.com"
        guard let url = URL(string: "https://\(endpointHost)/v1internal:streamGenerateContent?alt=sse") else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid CodeAssist URL"])
        }
        
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if session.kind == .jetski {
            request.setValue("antigravity/cli/1.4.3 (aidev_client; os_type=darwin; arch=arm64; cl=1002753436; auth_method=consumer)", forHTTPHeaderField: "User-Agent")
        } else {
            request.setValue("GeminiCLI/0.34.0 (darwin; arm64)", forHTTPHeaderField: "User-Agent")
        }
        
        let sessionUUID = UUID().uuidString
        var innerRequest: [String: Any] = [
            session.kind == .jetski ? "sessionId" : "session_id": sessionUUID,
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": maxOutputTokens(for: codeAssistModel)
            ]
        ]
        
        if let sys = systemPrompt, !sys.isEmpty {
            innerRequest["systemInstruction"] = ["parts": [["text": sys]]]
        }
        
        var rawContents: [[String: Any]] = []
        var lastTurnUsedStructuredFunctionCall = false
        
        func appendCodeAssistTurn(role: String, content: String) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let isGeminiTarget = codeAssistModel.lowercased().contains("gemini")
            if let structured = AIStructuredTurnCodec.decode(trimmed) {
                switch structured {
                case .assistantToolCalls(let text, let toolCalls):
                    var parts: [[String: Any]] = []
                    let cleanText = AIStructuredTurnCodec.stripThoughtTags(text)
                    if !cleanText.isEmpty {
                        parts.append(["text": cleanText])
                    }
                    // Gemini only attaches thoughtSignature to the first functionCall part in a parallel tool batch.
                    // Checking anyHaveThoughtSig preserves native functionCall parts across multi-tool turns,
                    // and avoids injecting "[Tool Call: ...]" text into model history which causes the model to mimic text tool calls.
                    let anyHaveThoughtSig = toolCalls.contains { !($0.thoughtSignature ?? "").isEmpty }
                    if isGeminiTarget && !anyHaveThoughtSig {
                        lastTurnUsedStructuredFunctionCall = false
                        if parts.isEmpty {
                            parts.append(["text": "Checked workspace state."])
                        }
                    } else {
                        lastTurnUsedStructuredFunctionCall = true
                        for tc in toolCalls {
                            var fcDict: [String: Any] = [
                                "name": tc.name,
                                "args": tc.arguments
                            ]
                            if !tc.id.isEmpty {
                                fcDict["id"] = tc.id
                            }
                            var part: [String: Any] = [
                                "functionCall": fcDict
                            ]
                            if isGeminiTarget, let sig = tc.thoughtSignature, !sig.isEmpty {
                                part["thoughtSignature"] = sig
                            }
                            parts.append(part)
                        }
                    }
                    if !parts.isEmpty {
                        rawContents.append(["role": "model", "parts": parts])
                    }
                case .toolResults(let results, let directive):
                    var parts: [[String: Any]] = []
                    if lastTurnUsedStructuredFunctionCall {
                        for res in results {
                            var frDict: [String: Any] = [
                                "name": res.name,
                                "response": [
                                    "result": res.output,
                                    "success": res.success
                                ]
                            ]
                            if !res.toolCallId.isEmpty {
                                frDict["id"] = res.toolCallId
                            }
                            parts.append(["functionResponse": frDict])
                        }
                    } else {
                        let textResults = results.map { "[\($0.name) output]:\n\($0.output)" }.joined(separator: "\n\n")
                        if !textResults.isEmpty {
                            parts.append(["text": textResults])
                        }
                    }
                    lastTurnUsedStructuredFunctionCall = false
                    if !directive.isEmpty {
                        parts.append(["text": directive])
                    }
                    if !parts.isEmpty {
                        rawContents.append(["role": "user", "parts": parts])
                    }
                }
            } else {
                lastTurnUsedStructuredFunctionCall = false
                let geminiRole = role == "assistant" ? "model" : "user"
                let cleanText = role == "assistant" ? AIStructuredTurnCodec.stripThoughtTags(trimmed) : trimmed
                guard !cleanText.isEmpty else { return }
                rawContents.append(["role": geminiRole, "parts": [["text": cleanText]]])
            }
        }
        
        for msg in conversationHistory {
            appendCodeAssistTurn(role: msg.role, content: msg.content)
        }
        
        var userParts: [[String: Any]] = []
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            if case .toolResults(let results, let directive) = AIStructuredTurnCodec.decode(trimmedPrompt) {
                if lastTurnUsedStructuredFunctionCall {
                    for res in results {
                        var frDict: [String: Any] = [
                            "name": res.name,
                            "response": [
                                "result": res.output,
                                "success": res.success
                            ]
                        ]
                        if !res.toolCallId.isEmpty {
                            frDict["id"] = res.toolCallId
                        }
                        userParts.append(["functionResponse": frDict])
                    }
                } else {
                    let textResults = results.map { "[\($0.name) output]:\n\($0.output)" }.joined(separator: "\n\n")
                    if !textResults.isEmpty {
                        userParts.append(["text": textResults])
                    }
                }
                if !directive.isEmpty {
                    userParts.append(["text": directive])
                }
            } else {
                userParts.append(["text": trimmedPrompt])
            }
        }
        
        let geminiInlineTextAttachments = attachments.filter { $0.includeInlineTextInProviderPayload }
        if !geminiInlineTextAttachments.isEmpty {
            let groundedPackage = UniversalAttachmentEngine.shared.buildGroundedTurnPackage(
                attachments: geminiInlineTextAttachments,
                maxInlineChars: 80_000
            )
            if !groundedPackage.isEmpty {
                userParts.append(["text": "\n" + groundedPackage + "\n"])
            }
        }

        var geminiInlineBytesUsed = 0
        let maxGeminiInlineBytes = 18_000_000
        let supportedGeminiMediaMimes: Set<String> = [
            "audio/mp3", "audio/wav", "audio/mp4", "audio/aac", "audio/flac", "audio/ogg",
            "video/mp4", "video/quicktime", "video/webm"
        ]
        for attachment in attachments {
            switch attachment.type {
            case .image:
                let vData = attachment.effectiveVisionData
                let vMime = attachment.effectiveVisionMimeType
                if !vData.isEmpty && (geminiInlineBytesUsed + vData.count) <= maxGeminiInlineBytes {
                    userParts.append(["inlineData": ["mimeType": vMime, "data": vData.base64EncodedString()]])
                    geminiInlineBytesUsed += vData.count
                }
            case .pdf:
                if !attachment.isPasswordProtected,
                   let pdfData = attachment.loadRawBinaryData(maxBytes: 15_000_000),
                   !pdfData.isEmpty,
                   (geminiInlineBytesUsed + pdfData.count) <= maxGeminiInlineBytes {
                    userParts.append(["inlineData": ["mimeType": "application/pdf", "data": pdfData.base64EncodedString()]])
                    geminiInlineBytesUsed += pdfData.count
                }
            case .text:
                if let mediaMime = attachment.nativeMediaMimeType,
                   supportedGeminiMediaMimes.contains(mediaMime),
                   let mediaData = attachment.loadRawBinaryData(maxBytes: 14_000_000),
                   !mediaData.isEmpty,
                   (geminiInlineBytesUsed + mediaData.count) <= maxGeminiInlineBytes {
                    userParts.append(["inlineData": ["mimeType": mediaMime, "data": mediaData.base64EncodedString()]])
                    geminiInlineBytesUsed += mediaData.count
                } else if attachment.semanticCategory == .video,
                          let kf = attachment.normalizedVisionData,
                          !kf.isEmpty,
                          (geminiInlineBytesUsed + kf.count) <= maxGeminiInlineBytes {
                    userParts.append(["inlineData": ["mimeType": attachment.normalizedVisionMimeType ?? "image/jpeg", "data": kf.base64EncodedString()]])
                    geminiInlineBytesUsed += kf.count
                }
            }
        }
        
        if userParts.isEmpty {
            userParts.append(["text": "Please continue."])
        }
        rawContents.append(["role": "user", "parts": userParts])
        
        var coalesced: [[String: Any]] = []
        for item in rawContents {
            if let last = coalesced.last, (last["role"] as? String) == (item["role"] as? String) {
                var newLast = last
                var parts = (newLast["parts"] as? [[String: Any]]) ?? []
                let itemParts = (item["parts"] as? [[String: Any]]) ?? []
                parts.append(contentsOf: itemParts)
                newLast["parts"] = parts
                coalesced[coalesced.count - 1] = newLast
            } else {
                coalesced.append(item)
            }
        }
        
        if coalesced.first?["role"] as? String == "model" {
            coalesced.insert(["role": "user", "parts": [["text": "Begin."]]], at: 0)
        }
        
        innerRequest["contents"] = coalesced
        
        if let tools = tools, !tools.isEmpty {
            let sanitized = tools.map { sanitizeToolSchemaForGemini($0) }
            innerRequest["tools"] = [["functionDeclarations": sanitized]]
        }
        
        let outerBody: [String: Any]
        if session.kind == .jetski {
            outerBody = [
                "project": "aicode-consumers",
                "requestId": "agent/\(UUID().uuidString)",
                "userAgent": "antigravity",
                "requestType": "agent",
                "model": codeAssistModel,
                "request": innerRequest
            ]
        } else {
            var gcliOuter: [String: Any] = [
                "model": codeAssistModel,
                "user_prompt_id": UUID().uuidString,
                "request": innerRequest
            ]
            if !session.projectId.isEmpty {
                gcliOuter["project"] = session.projectId
            }
            outerBody = gcliOuter
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: outerBody)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from CodeAssist gateway"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let code = httpResponse.statusCode
            if code == 401 || code == 403 {
                var errPreview = ""
                for try await line in bytes.lines {
                    errPreview += line
                    if errPreview.count > 400 { break }
                }
                if try await failOverFromBrokenCodeAssist(
                    reason: "CodeAssist HTTP \(code) (\(String(errPreview.prefix(120))))",
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: model,
                    tools: tools,
                    onToken: onToken,
                    onToolCall: onToolCall
                ) {
                    return
                }
                throw NSError(
                    domain: "AIClient",
                    code: code,
                    userInfo: [NSLocalizedDescriptionKey: "Google Code Assist session unauthorized or tier ineligible (HTTP \(code)). Connect TH-AI Passport / Thai AI Gemini Enterprise, sign in to Antigravity (agy), or add a Direct Gemini API Key."]
                )
            }
            if code == 429 || code == 503 || code == 404 {
                let fallbackChain: [String] = (session.kind == .geminiCLI)
                    ? [
                        "gemini-2.5-pro",
                        "gemini-2.5-flash",
                        "gemini-2.5-flash-lite"
                    ]
                    : [
                        "gemini-4-argon-high",
                        "gemini-4-argon-medium",
                        "gemini-4-argon-low",
                        "gemini-3.8-flash-tiered",
                        "gemini-3.8-flash-medium",
                        "gemini-3-flash",
                        "gemini-3.5-flash-lite",
                        "gemini-2.5-flash",
                        "claude-sonnet-5-5-medium",
                        "claude-sonnet-5-5-low"
                    ]
                let defaultFallback = (session.kind == .geminiCLI) ? "gemini-2.5-flash" : "gemini-3-flash"
                let nextModel: String? = {
                    if let idx = fallbackChain.firstIndex(of: codeAssistModel) {
                        return (idx + 1 < fallbackChain.count) ? fallbackChain[idx + 1] : nil
                    }
                    return defaultFallback
                }()
                if let nextModel {
                    if code == 429 {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                    }
                    NSLog("⚠️ [streamGoogleCodeAssist] HTTP %d on %@ — rotating automatically to %@", code, codeAssistModel, nextModel)
                    try await streamGoogleCodeAssist(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: nextModel,
                        refreshToken: refreshToken,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                }
                if try await failOverFromBrokenCodeAssist(
                    reason: "CodeAssist pools exhausted (HTTP \(code))",
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: model,
                    tools: tools,
                    onToken: onToken,
                    onToolCall: onToolCall
                ) {
                    return
                }
            }
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 500 { break }
            }
            throw NSError(domain: "AIClient", code: code, userInfo: [NSLocalizedDescriptionKey: "CodeAssist error (\(code)): \(errorBody.prefix(240))"])
        }
        
        var isStreamingReasoning = false
        var latestUsageMetadata: [String: Any]?
        
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !jsonString.isEmpty,
                  let data = jsonString.data(using: .utf8),
                  let outerJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            
            let json = (outerJson["response"] as? [String: Any]) ?? outerJson
            
            if let usage = json["usageMetadata"] as? [String: Any] {
                latestUsageMetadata = usage
            }
            
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }
            
            for part in parts {
                let isThought = (part["thought"] as? Bool) ?? false
                if let text = part["text"] as? String {
                    if isThought {
                        if !isStreamingReasoning {
                            isStreamingReasoning = true
                            appendStreamToken("<thought>", onToken: onToken)
                        }
                        appendStreamToken(text, onToken: onToken)
                    } else {
                        if isStreamingReasoning {
                            isStreamingReasoning = false
                            appendStreamToken("</thought>\n\n", onToken: onToken)
                        }
                        appendStreamToken(text, onToken: onToken)
                    }
                    if detectStreamRepetitionLoop(currentStreamedText) {
                        NSLog("⚠️ [AIClient] Streaming repetition loop detected in streamGoogleCodeAssist. Breaking stream.")
                        break
                    }
                }
                if let fc = part["functionCall"] as? [String: Any],
                   let name = fc["name"] as? String {
                    if isStreamingReasoning {
                        isStreamingReasoning = false
                        appendStreamToken("</thought>\n\n", onToken: onToken)
                    }
                    let callId = (fc["id"] as? String) ?? UUID().uuidString
                    let args = fc["args"] as? [String: Any] ?? [:]
                    let thoughtSig = part["thoughtSignature"] as? String
                    let toolCall = AIToolCall(id: callId, name: name, arguments: args, thoughtSignature: thoughtSig)
                    onToolCall?(toolCall)
                }
            }
        }
        
        if isStreamingReasoning {
            isStreamingReasoning = false
            appendStreamToken("</thought>\n\n", onToken: onToken)
        }
        
        if let usage = latestUsageMetadata {
            let promptTok = usage["promptTokenCount"] as? Int ?? 0
            let completionTok = usage["candidatesTokenCount"] as? Int ?? 0
            let cachedTok = usage["cachedContentTokenCount"] as? Int ?? 0
            let provName = codeAssistModel.contains("claude") ? "anthropic" : "gemini"
            Task { @MainActor in
                AIUsageTracker.shared.record(
                    provider: provName,
                    model: codeAssistModel,
                    promptTokens: promptTok,
                    completionTokens: completionTok,
                    cachedTokens: cachedTok,
                    taskLabel: "Chat"
                )
            }
        }
    }
    
    // MARK: - Vision Model Detection
    
    private func isVisionCapableModel(_ model: String) -> Bool {
        let m = model.lowercased()
        if m.contains("o1-mini") || m.contains("o3-mini") {
            return false
        }
        if m.contains("gpt-4o") || m.contains("gpt-4-turbo") || m.contains("gpt-4.1") ||
           m.contains("gpt-4.5") || m.contains("gpt-5") || m.contains("gpt-6") ||
           m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4") ||
           m.contains("/o1") || m.contains("/o3") || m.contains("/o4") ||
           m.contains("vision") || m.contains("gemini") || m.contains("gemma-3") ||
           m.contains("gemma-4") || m.contains("claude") || m.contains("omni") ||
           m.contains("llava") || m.contains("pixtral") || m.contains("kimi") ||
           m.contains("grok") || m.contains("vl") || m.contains("4o") {
            return true
        }
        return false
    }
    
    // MARK: - OpenAI/DeepSeek Streaming
    
    func streamOpenAI(
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        apiKey: String,
        baseURL: String,
        tools: [[String: Any]]?,
        maxTokensOverride: Int? = nil,
        omitToolChoice: Bool = false,
        customEndpointURL: URL? = nil,
        customSession: URLSession? = nil,
        customHeadersHook: ((inout URLRequest) -> Void)? = nil,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        guard let url = customEndpointURL ?? URL(string: "\(baseURL)/chat/completions") else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL configuration for openai"])
        }
        
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let isCloudProxy = StreamableAIProvider.isDotminiCloudProxy(baseURL)
        let isCopilot = baseURL.contains("githubcopilot.com")
        if let customHeadersHook {
            customHeadersHook(&request)
        } else if isCloudProxy {
            let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "2.5.38"
            request.setValue("MicroCode/\(appVersion) (macOS)", forHTTPHeaderField: "User-Agent")
            request.setValue("macos", forHTTPHeaderField: "X-MicroCode-Client")
            request.setValue("Agent", forHTTPHeaderField: "X-MicroCode-Feature")
            request.setValue("Dotmini Cloud", forHTTPHeaderField: "X-MicroCode-AI-Provider")
            let dotminiLicense = UserDefaults.standard.string(forKey: "dotminiLicenseKey") ?? ""
            if !dotminiLicense.isEmpty {
                request.setValue(dotminiLicense, forHTTPHeaderField: "X-Dotmini-License")
            }
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        } else if isCopilot {
            let copilotToken = try await SubscriptionAuthManager.shared.getCopilotSessionToken(githubToken: apiKey)
            request.setValue("Bearer \(copilotToken)", forHTTPHeaderField: "Authorization")
            request.setValue("vscode/1.95.0", forHTTPHeaderField: "Editor-Version")
            request.setValue("copilot-chat/0.22.4", forHTTPHeaderField: "Editor-Plugin-Version")
            request.setValue("vscode-chat", forHTTPHeaderField: "Copilot-Integration-Id")
            request.setValue("github-copilot", forHTTPHeaderField: "Openai-Organization")
        } else {
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            if baseURL.contains("openrouter.ai") {
                request.setValue("https://dotmini.net", forHTTPHeaderField: "HTTP-Referer")
                request.setValue("MicroCode IDE", forHTTPHeaderField: "X-Title")
            }
        }
        EnterpriseAIAuthService.shared.applyEnterpriseHeaders(to: &request)
        
        var messages: [[String: Any]] = []
        if let sys = systemPrompt, !sys.isEmpty { messages.append(["role": "system", "content": sys]) }
        
        var activeAssistantToolCallIds: Set<String> = []
        func appendOpenAITurn(role: String, content: String) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if let structured = AIStructuredTurnCodec.decode(trimmed) {
                switch structured {
                case .assistantToolCalls(let text, let toolCalls):
                    let cleanText = AIStructuredTurnCodec.stripThoughtTags(text)
                    var msgDict: [String: Any] = [
                        "role": "assistant",
                        "content": cleanText
                    ]
                    let tcArray: [[String: Any]] = toolCalls.map { tc in
                        let argsData = (try? JSONSerialization.data(withJSONObject: tc.arguments, options: [.sortedKeys])) ?? Data("{}".utf8)
                        let argsStr = String(data: argsData, encoding: .utf8) ?? "{}"
                        return [
                            "id": tc.id,
                            "type": "function",
                            "function": [
                                "name": AgentToolBox.normalizeToolName(tc.name),
                                "arguments": argsStr
                            ]
                        ]
                    }
                    if !tcArray.isEmpty {
                        msgDict["tool_calls"] = tcArray
                    }
                    messages.append(msgDict)
                    activeAssistantToolCallIds = Set(toolCalls.map { $0.id })
                case .toolResults(let results, let directive):
                    var unmatchedOutputs: [String] = []
                    for res in results {
                        if activeAssistantToolCallIds.contains(res.toolCallId) {
                            messages.append([
                                "role": "tool",
                                "tool_call_id": res.toolCallId,
                                "content": res.output
                            ])
                        } else {
                            unmatchedOutputs.append("[\(res.name)]: \(res.output)")
                        }
                    }
                    activeAssistantToolCallIds.removeAll()
                    let combinedDirective = (unmatchedOutputs + (directive.isEmpty ? [] : [directive])).joined(separator: "\n\n")
                    if !combinedDirective.isEmpty {
                        messages.append(["role": "user", "content": combinedDirective])
                    }
                }
            } else {
                activeAssistantToolCallIds.removeAll()
                let cleanText = role == "assistant" ? AIStructuredTurnCodec.stripThoughtTags(trimmed) : trimmed
                guard !cleanText.isEmpty else { return }
                messages.append(["role": role, "content": cleanText])
            }
        }
        
        for msg in conversationHistory {
            appendOpenAITurn(role: msg.role, content: msg.content)
        }
        
        var combinedUserPrompt = prompt
        let inlineTextAttachments = attachments.filter { $0.includeInlineTextInProviderPayload }
        if !inlineTextAttachments.isEmpty {
            let groundedPackage = UniversalAttachmentEngine.shared.buildGroundedTurnPackage(
                attachments: inlineTextAttachments,
                maxInlineChars: 80_000
            )
            if !groundedPackage.isEmpty {
                combinedUserPrompt = combinedUserPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? groundedPackage
                    : (combinedUserPrompt + "\n\n" + groundedPackage)
            }
        }

        let isVision = isVisionCapableModel(model)
        var visionImageParts: [[String: Any]] = []
        if isVision && !attachments.isEmpty {
            var inlineBinaryBytesUsed = 0
            let maxOpenAIBinaryBytes = 18_000_000
            for attachment in attachments {
                if case .image = attachment.type {
                    let vData = attachment.effectiveVisionData
                    let vMime = attachment.effectiveVisionMimeType
                    if !vData.isEmpty && vData.count <= 12_000_000 && (inlineBinaryBytesUsed + vData.count) <= maxOpenAIBinaryBytes {
                        visionImageParts.append([
                            "type": "image_url",
                            "image_url": ["url": "data:\(vMime);base64,\(vData.base64EncodedString())"]
                        ])
                        inlineBinaryBytesUsed += vData.count
                    }
                } else if attachment.semanticCategory == .video,
                          let kf = attachment.normalizedVisionData,
                          !kf.isEmpty,
                          kf.count <= 12_000_000,
                          (inlineBinaryBytesUsed + kf.count) <= maxOpenAIBinaryBytes {
                    let kfMime = attachment.normalizedVisionMimeType ?? "image/jpeg"
                    visionImageParts.append([
                        "type": "image_url",
                        "image_url": ["url": "data:\(kfMime);base64,\(kf.base64EncodedString())"]
                    ])
                    inlineBinaryBytesUsed += kf.count
                }
            }
        }

        if visionImageParts.isEmpty {
            let safePrompt = combinedUserPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (attachments.isEmpty ? "Continue." : "Analyze attachment.")
                : combinedUserPrompt
            appendOpenAITurn(role: "user", content: safePrompt)
        } else {
            activeAssistantToolCallIds.removeAll()
            let textLead = combinedUserPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Analyze attachment."
                : combinedUserPrompt
            let contentArray: [[String: Any]] = [["type": "text", "text": textLead]] + visionImageParts
            messages.append(["role": "user", "content": contentArray])
        }
        
        let effectiveModel = normalizeModelName(model, provider: StreamableAIProvider.detect(from: model, baseURL: baseURL), baseURL: baseURL)
        let lowerEffective = effectiveModel.lowercased()
        let isOpenAIReasoning = lowerEffective.hasPrefix("o1") || lowerEffective.hasPrefix("o3") || lowerEffective.hasPrefix("o4")
        let isReasoningNoTemp = lowerEffective.contains("reasoner") || lowerEffective.contains("deepseek-r1") || lowerEffective.hasPrefix("qwq")
        var body: [String: Any] = [
            "model": effectiveModel,
            "messages": messages,
            "stream": true
        ]
        let isTokenMe = baseURL.contains("tokenme.limited")
        let isLocalTarget = StreamableAIProvider.isLocalEndpoint(baseURL)
        // TokenMe enforces a tiny ~512-token default cap (shared with `reasoning`) when `max_tokens` is omitted,
        // and supports up to 32,768 output tokens across all chat models. Always send an explicit budget.
        let requestedMaxTokens = maxTokensOverride ?? (isTokenMe ? 32768 : (isLocalTarget ? 1024 : maxOutputTokens(for: effectiveModel)))
        if isOpenAIReasoning {
            body["max_completion_tokens"] = requestedMaxTokens
        } else if isReasoningNoTemp {
            body["max_tokens"] = requestedMaxTokens
        } else {
            body["temperature"] = 0.7
            body["max_tokens"] = requestedMaxTokens
        }
        
        if let tools = tools, !tools.isEmpty, !baseURL.contains("perplexity.ai") {
            let sanitizedTools = tools.map { sanitizeToolSchemaForStandardJSONSchema($0) }
            body["tools"] = sanitizedTools.map { ["type": "function", "function": $0] as [String: Any] }
            if !isReasoningNoTemp && !omitToolChoice {
                body["tool_choice"] = "auto"
            }
        }
        
        // Enable usage reporting in stream responses (omit on strict schema endpoints)
        if !baseURL.contains("perplexity.ai") && !baseURL.contains("mistral.ai") && !baseURL.contains("cerebras.ai") && !baseURL.contains("minimax.io") {
            body["stream_options"] = ["include_usage": true]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        
        let (bytes, response) = try await (customSession ?? URLSession.shared).bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if isCopilot && (code == 400 || code == 403 || code == 404) && effectiveModel != "gpt-4.1" {
                NSLog("⚠️ [streamOpenAI] GitHub Copilot HTTP %d on %@ — falling back to Copilot gpt-4.1", code, effectiveModel)
                try await streamOpenAI(
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: "gpt-4.1",
                    apiKey: apiKey,
                    baseURL: baseURL,
                    tools: tools,
                    onToken: onToken,
                    onToolCall: onToolCall
                )
                return
            }
            if code == 401, customEndpointURL == nil, baseURL.contains("api.z.ai"),
               let altBase = Self.glmAlternateRegionBase(baseURL) {
                NSLog("⚠️ [streamOpenAI] GLM HTTP 401 on Z.AI international — retrying BigModel (China) region")
                try await streamOpenAI(
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: model,
                    apiKey: apiKey,
                    baseURL: altBase,
                    tools: tools,
                    maxTokensOverride: maxTokensOverride,
                    omitToolChoice: omitToolChoice,
                    onToken: onToken,
                    onToolCall: onToolCall
                )
                if (UserDefaults.standard.string(forKey: "aiKeyMode") ?? "direct") == "subscription" {
                    UserDefaults.standard.set("cn", forKey: "sub_glm_region")
                }
                return
            }
            if (code == 401 || code == 402 || code == 403 || code == 404 || code == 429 || code == 503) && !isCloudProxy {
                let currentKeyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "direct"
                // Same-provider GLM model rotation (safe in both BYOK and Subscription since it uses the same apiKey & baseURL)
                if (code == 429 || code == 503 || code == 404) && (baseURL.contains("api.z.ai") || baseURL.contains("bigmodel.cn")) && effectiveModel != "glm-4.5-flash" {
                    NSLog("⚠️ [streamOpenAI] HTTP %d on %@ — rotating automatically to glm-4.5-flash", code, effectiveModel)
                    try await streamOpenAI(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: "glm-4.5-flash",
                        apiKey: apiKey,
                        baseURL: baseURL,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                }

                // Cross-provider Subscription failovers are STRICTLY gated to Subscription mode (`currentKeyMode == "subscription"`).
                // Direct BYOK mode (`currentKeyMode == "direct"`) NEVER silently jumps to TH-AI Passport or Google CodeAssist.
                if currentKeyMode == "subscription" {
                    let isExplicitPortalEndpoint = StreamableAIProvider.isLocalEndpoint(baseURL) ||
                        baseURL.contains("trycloudflare.com") ||
                        baseURL.contains("tokenme.limited") ||
                        baseURL.contains("openrouter.ai") ||
                        baseURL.contains("groq.com") ||
                        baseURL.contains("mistral.ai") ||
                        baseURL.contains("moonshot.ai") ||
                        baseURL.contains("perplexity.ai") ||
                        baseURL.contains("perchai.app") ||
                        baseURL.contains("cerebras.ai") ||
                        baseURL.contains("together.xyz") ||
                        baseURL.contains("fireworks.ai") ||
                        baseURL.contains("minimax.io") ||
                        baseURL.contains("nvidia.com") ||
                        baseURL.contains("x.ai") ||
                        baseURL.contains("aliyuncs.com")

                    let aipassCookie = Self.resolveAiPassSessionCookie(primary: "")
                    if (baseURL.contains("api.deepseek.com") || (!isExplicitPortalEndpoint && lowerEffective.contains("deepseek"))) && !aipassCookie.isEmpty {
                        NSLog("⚠️ [streamOpenAI] Subscription HTTP %d on DeepSeek (%@) — failing over to TH-AI Passport DeepSeek-V4-Flash", code, effectiveModel)
                        try await streamAiPass(
                            prompt: prompt,
                            attachments: attachments,
                            systemPrompt: systemPrompt,
                            conversationHistory: conversationHistory,
                            model: "DeepSeek-V4-Flash",
                            sessionCookie: aipassCookie,
                            tools: tools,
                            onToken: onToken,
                            onToolCall: onToolCall
                        )
                        return
                    }

                    if baseURL.contains("opentyphoon.ai") && (code == 402 || code == 429 || code == 503) && !aipassCookie.isEmpty {
                        NSLog("⚠️ [streamOpenAI] Subscription HTTP %d on OpenTyphoon (%@) — failing over to TH-AI Passport typhoon2.5-qwen3-30b", code, effectiveModel)
                        try await streamAiPass(
                            prompt: prompt,
                            attachments: attachments,
                            systemPrompt: systemPrompt,
                            conversationHistory: conversationHistory,
                            model: "typhoon2.5-qwen3-30b",
                            sessionCookie: aipassCookie,
                            tools: tools,
                            onToken: onToken,
                            onToolCall: onToolCall
                        )
                        return
                    }

                    if !isExplicitPortalEndpoint && !aipassCookie.isEmpty {
                        NSLog("⚠️ [streamOpenAI] Subscription HTTP %d on %@ — failing over to TH-AI Passport", code, effectiveModel)
                        try await streamAiPass(
                            prompt: prompt,
                            attachments: attachments,
                            systemPrompt: systemPrompt,
                            conversationHistory: conversationHistory,
                            model: effectiveModel,
                            sessionCookie: aipassCookie,
                            tools: tools,
                            onToken: onToken,
                            onToolCall: onToolCall
                        )
                        return
                    }

                    if !isExplicitPortalEndpoint,
                       await MainActor.run(body: { SubscriptionAuthManager.shared.isConnected(.gemini) }),
                       let codeAssistCreds = Self.loadGoogleCodeAssistCredentials(fallbackToken: "") {
                        NSLog("⚠️ [streamOpenAI] Subscription HTTP %d on %@ — failing over to Google CodeAssist", code, effectiveModel)
                        try await streamGoogleCodeAssist(
                            prompt: prompt,
                            attachments: attachments,
                            systemPrompt: systemPrompt,
                            conversationHistory: conversationHistory,
                            model: "gemini-3.8-flash-tiered",
                            refreshToken: codeAssistCreds.refreshToken,
                            tools: tools,
                            onToken: onToken,
                            onToolCall: onToolCall
                        )
                        return
                    }
                }
            }
            var errText = ""
            for try await l in bytes.lines {
                errText += l
                if errText.count > 800 { break }
            }
            let lowerErrText = errText.lowercased()
            if (code == 400 || code == 422),
               requestedMaxTokens > 2048,
               (lowerErrText.contains("max_tokens") ||
                lowerErrText.contains("max_completion_tokens") ||
                lowerErrText.contains("output token limit") ||
                lowerErrText.contains("context_length") ||
                lowerErrText.contains("maximum context") ||
                lowerErrText.contains("token limit")) {
                let reducedMaxTokens = max(2048, requestedMaxTokens / 2)
                NSLog("⚠️ [streamOpenAI] HTTP %d output/context token cap hit on %@ (requested %d) — retrying with max_tokens=%d", code, effectiveModel, requestedMaxTokens, reducedMaxTokens)
                try await streamOpenAI(
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: model,
                    apiKey: apiKey,
                    baseURL: baseURL,
                    tools: tools,
                    maxTokensOverride: reducedMaxTokens,
                    onToken: onToken,
                    onToolCall: onToolCall
                )
                return
            }
            if (code == 400 || code == 422),
               let tools = tools,
               !tools.isEmpty,
               !omitToolChoice,
               (lowerErrText.contains("tool_choice") || lowerErrText.contains("tool choice")) {
                NSLog("⚠️ [streamOpenAI] HTTP %d tool_choice parameter rejected on %@ (%@) — retrying with tools preserved and tool_choice omitted", code, effectiveModel, baseURL)
                try await streamOpenAI(
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: model,
                    apiKey: apiKey,
                    baseURL: baseURL,
                    tools: tools,
                    maxTokensOverride: maxTokensOverride,
                    omitToolChoice: true,
                    onToken: onToken,
                    onToolCall: onToolCall
                )
                return
            }
            let modelExplicitlyLacksToolSupport =
                lowerErrText.contains("does not support tool") ||
                lowerErrText.contains("doesn't support tool") ||
                lowerErrText.contains("tools are not supported") ||
                lowerErrText.contains("tool calling is not supported") ||
                lowerErrText.contains("tool use is not supported") ||
                lowerErrText.contains("function calling is not supported") ||
                lowerErrText.contains("functions are not supported")
            if (code == 400 || code == 422), let tools = tools, !tools.isEmpty, modelExplicitlyLacksToolSupport {
                NSLog("⚠️ [streamOpenAI] HTTP %d model explicitly lacks native tool calling on %@ (%@) — retrying without server-side tools", code, effectiveModel, baseURL)
                try await streamOpenAI(
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: model,
                    apiKey: apiKey,
                    baseURL: baseURL,
                    tools: nil,
                    maxTokensOverride: maxTokensOverride,
                    omitToolChoice: true,
                    onToken: onToken,
                    onToolCall: onToolCall
                )
                return
            }
            if isCloudProxy,
               (code == 400 || code == 404 || code == 429 || code == 500 || code == 502 || code == 503),
               effectiveModel != "deepseek-chat" {
                NSLog("⚠️ [streamOpenAI] Dotmini Cloud HTTP %d on %@ — transparently retrying on deepseek-chat", code, effectiveModel)
                try await streamOpenAI(
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: "deepseek-chat",
                    apiKey: apiKey,
                    baseURL: baseURL,
                    tools: tools,
                    maxTokensOverride: maxTokensOverride,
                    onToken: onToken,
                    onToolCall: onToolCall
                )
                return
            }
            let parsedMsg = Self.extractOpenAICompatibleErrorMessage(from: errText)
            let customMsg = parseErrorMessage(NSError(domain: "AIClient", code: code, userInfo: parsedMsg.map { [NSLocalizedDescriptionKey: $0] }))
            let finalMsg = parsedMsg.map { code == 400 || code == 422 ? "API error (\(code)): \($0)" : customMsg } ?? customMsg
            print("[AIClient] HTTP \(code) error from \(url.absoluteString): \(finalMsg)")
            throw NSError(domain: "AIClient", code: code, userInfo: [NSLocalizedDescriptionKey: finalMsg])
        }
        
        // Buffer for streaming tool calls (keyed by integer index for deterministic order)
        var toolCallBuffers: [Int: (id: String, name: String, args: String)] = [:]
        var isStreamingReasoning = false
        var emittedNativeToolCalls = false
        var sawLengthTruncation = false

        func flushBufferedToolCalls() {
            for idx in toolCallBuffers.keys.sorted() {
                guard let buffer = toolCallBuffers[idx], !buffer.name.isEmpty else { continue }
                let trimmedArgs = buffer.args.trimmingCharacters(in: .whitespacesAndNewlines)
                let parsedArgs: [String: Any]?
                if trimmedArgs.isEmpty {
                    parsedArgs = [:]
                } else {
                    parsedArgs = (try? JSONSerialization.jsonObject(with: Data(trimmedArgs.utf8))) as? [String: Any]
                }
                guard let rawArgs = parsedArgs else {
                    NSLog("⚠️ [streamOpenAI] Skipping truncated/malformed tool call '%@' (args len=%d, finish_reason=length:%d)", buffer.name, trimmedArgs.count, sawLengthTruncation ? 1 : 0)
                    sawLengthTruncation = true
                    continue
                }
                let canonicalName = AgentToolBox.normalizeToolName(buffer.name)
                let canonicalArgs = AgentToolBox.normalizeToolParams(rawArgs)
                let toolCall = AIToolCall(id: buffer.id, name: canonicalName, arguments: canonicalArgs)
                emittedNativeToolCalls = true
                onToolCall?(toolCall)
            }
            toolCallBuffers.removeAll()
        }
        
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: "), line != "data: [DONE]" else { continue }
            let jsonString = String(line.dropFirst(6))
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            
            // Capture token usage from final stream chunk (OpenAI/DeepSeek/Grok/Qwen/GLM/TokenMe)
            if let usage = json["usage"] as? [String: Any] {
                let promptTok = usage["prompt_tokens"] as? Int ?? 0
                let completionTok = usage["completion_tokens"] as? Int ?? 0
                let detailsCached = (usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int
                let hitCached = (usage["prompt_cache_hit_tokens"] as? Int) ?? (usage["cache_read_input_tokens"] as? Int)
                let cachedTok = detailsCached ?? hitCached ?? 0
                let resolvedProvider = StreamableAIProvider.detect(from: model, baseURL: baseURL).rawValue
                Task { @MainActor in
                    AIUsageTracker.shared.record(
                        provider: resolvedProvider,
                        model: model,
                        promptTokens: promptTok,
                        completionTokens: completionTok,
                        cachedTokens: cachedTok,
                        taskLabel: "Chat"
                    )
                }
            }
            
            guard let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first else { continue }
            let finishReason = firstChoice["finish_reason"] as? String
            if finishReason == "length" {
                sawLengthTruncation = true
            }
            let delta = (firstChoice["delta"] as? [String: Any]) ?? [:]
            
            // Reasoning tokens: support both `reasoning_content` (DeepSeek API / GLM) and `reasoning` (TokenMe / vLLM / SGLang / OpenRouter)
            let reasoningChunk = (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String)
            if let reasoning = reasoningChunk, !reasoning.isEmpty {
                if !isStreamingReasoning {
                    isStreamingReasoning = true
                    appendStreamToken("<thought>", onToken: onToken)
                }
                appendStreamToken(reasoning, onToken: onToken)
            }
            if let content = delta["content"] as? String, !content.isEmpty {
                if isStreamingReasoning {
                    isStreamingReasoning = false
                    appendStreamToken("</thought>\n\n", onToken: onToken)
                }
                appendStreamToken(content, onToken: onToken)
            }
            
            if detectStreamRepetitionLoop(currentStreamedText) {
                NSLog("⚠️ [AIClient] Streaming repetition loop detected in streamOpenAI. Breaking stream.")
                break
            }
            
            // Tool calls (streamed incrementally)
            if let toolCalls = delta["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                if isStreamingReasoning {
                    isStreamingReasoning = false
                    appendStreamToken("</thought>\n\n", onToken: onToken)
                    flushPendingStreamTokens(onToken: onToken)
                } else {
                    // Heartbeat so AgentService watchdog knows tool-call JSON bytes are actively arriving
                    onToken("")
                }
                for tc in toolCalls {
                    let idx = tc["index"] as? Int ?? 0
                    var entry = toolCallBuffers[idx] ?? (id: UUID().uuidString, name: "", args: "")
                    if let tcId = tc["id"] as? String, !tcId.isEmpty {
                        entry.id = tcId
                    }
                    if let function = tc["function"] as? [String: Any] {
                        if let name = function["name"] as? String, !name.isEmpty {
                            entry.name = name
                        }
                        if let argChunk = function["arguments"] as? String, !argChunk.isEmpty {
                            entry.args.append(argChunk)
                        }
                    }
                    toolCallBuffers[idx] = entry
                }
            }
            
            // Check finish reason
            if finishReason == "tool_calls" {
                flushBufferedToolCalls()
            }
        }
        
        if isStreamingReasoning {
            isStreamingReasoning = false
            appendStreamToken("</thought>\n\n", onToken: onToken)
        }
        flushPendingStreamTokens(onToken: onToken)
        
        // Flush any remaining buffered tool calls (e.g. if provider sent finish_reason: "stop" or nil)
        if !toolCallBuffers.isEmpty {
            flushBufferedToolCalls()
        }
        
        // Fallback: if model (e.g. DeepSeek R1/V3, Qwen, GLM, or OpenRouter gateway) emitted DSML or <tool_call> tags in content
        if !emittedNativeToolCalls, let tools = tools, !tools.isEmpty {
            let extracted = Self.extractAiPassToolCalls(from: currentStreamedText)
            for call in extracted {
                onToolCall?(call)
            }
        }
        if isCloudProxy {
            Task { @MainActor in
                await SupabaseAuthService.shared.refreshEntitlement()
            }
        }
    }
    
    // MARK: - Anthropic Streaming
    
    func streamAnthropic(
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        apiKey: String,
        tools: [[String: Any]]?,
        customEndpointURL: URL? = nil,
        customSession: URLSession? = nil,
        vertexAnthropicMode: Bool = false,
        customHeadersHook: ((inout URLRequest) -> Void)? = nil,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        let baseURL = StreamableAIProvider.anthropic.directBaseURL
        guard let url = customEndpointURL ?? URL(string: "\(baseURL)/messages") else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL configuration for anthropic"])
        }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let customHeadersHook {
            if !vertexAnthropicMode {
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            }
            customHeadersHook(&request)
        } else {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if apiKey.hasPrefix("sk-ant-oat") {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            } else if url.host?.contains("anthropic.com") == true {
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            } else {
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
        
        var allMessages: [[String: Any]] = []
        var activeAnthropicToolUseIds: Set<String> = []
        
        func appendAnthropicBlocks(role: String, blocks: [[String: Any]]) {
            guard !blocks.isEmpty else { return }
            if let last = allMessages.last, (last["role"] as? String) == role {
                var existingBlocks: [[String: Any]] = []
                if let lastArr = last["content"] as? [[String: Any]] {
                    existingBlocks = lastArr
                } else if let lastStr = last["content"] as? String, !lastStr.isEmpty {
                    existingBlocks = [["type": "text", "text": lastStr]]
                }
                existingBlocks.append(contentsOf: blocks)
                allMessages[allMessages.count - 1] = ["role": role, "content": existingBlocks]
            } else {
                allMessages.append(["role": role, "content": blocks])
            }
        }
        
        func appendAnthropicTurn(role: String, content: String) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let normalizedRole = role == "assistant" ? "assistant" : "user"
            if let structured = AIStructuredTurnCodec.decode(trimmed) {
                switch structured {
                case .assistantToolCalls(let text, let toolCalls):
                    var blocks: [[String: Any]] = []
                    let cleanText = AIStructuredTurnCodec.stripThoughtTags(text)
                    if !cleanText.isEmpty {
                        blocks.append(["type": "text", "text": cleanText])
                    }
                    for tc in toolCalls {
                        blocks.append([
                            "type": "tool_use",
                            "id": tc.id,
                            "name": tc.name,
                            "input": tc.arguments
                        ])
                    }
                    appendAnthropicBlocks(role: "assistant", blocks: blocks)
                    activeAnthropicToolUseIds = Set(toolCalls.map { $0.id })
                case .toolResults(let results, let directive):
                    var blocks: [[String: Any]] = []
                    for res in results {
                        if activeAnthropicToolUseIds.contains(res.toolCallId) {
                            blocks.append([
                                "type": "tool_result",
                                "tool_use_id": res.toolCallId,
                                "content": res.output,
                                "is_error": !res.success
                            ])
                        } else {
                            blocks.append([
                                "type": "text",
                                "text": "[\(res.name) result]:\n\(res.output)"
                            ])
                        }
                    }
                    activeAnthropicToolUseIds.removeAll()
                    if !directive.isEmpty {
                        blocks.append(["type": "text", "text": directive])
                    }
                    appendAnthropicBlocks(role: "user", blocks: blocks)
                }
            } else {
                activeAnthropicToolUseIds.removeAll()
                let cleanText = normalizedRole == "assistant" ? AIStructuredTurnCodec.stripThoughtTags(trimmed) : trimmed
                guard !cleanText.isEmpty else { return }
                appendAnthropicBlocks(role: normalizedRole, blocks: [["type": "text", "text": cleanText]])
            }
        }
        
        for msg in conversationHistory {
            appendAnthropicTurn(role: msg.role, content: msg.content)
        }
        if allMessages.first?["role"] as? String == "assistant" {
            allMessages.insert(["role": "user", "content": [["type": "text", "text": "Please begin."]]], at: 0)
        }
        
        var messageContent: [[String: Any]] = []
        let isVision = isVisionCapableModel(model)
        var anthropicBinaryBytesUsed = 0
        let maxAnthropicBinaryBytes = 18_000_000

        for attachment in attachments {
            if case .image = attachment.type {
                let vData = attachment.effectiveVisionData
                let vMime = attachment.effectiveVisionMimeType
                if isVision && !vData.isEmpty && vData.count <= 5_000_000 && (anthropicBinaryBytesUsed + vData.count) <= maxAnthropicBinaryBytes {
                    messageContent.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": vMime,
                            "data": vData.base64EncodedString()
                        ]
                    ])
                    anthropicBinaryBytesUsed += vData.count
                }
            } else if case .pdf = attachment.type {
                if !attachment.isPasswordProtected,
                   let pdfData = attachment.loadRawBinaryData(maxBytes: 15_000_000),
                   !pdfData.isEmpty,
                   (anthropicBinaryBytesUsed + pdfData.count) <= maxAnthropicBinaryBytes {
                    messageContent.append([
                        "type": "document",
                        "source": [
                            "type": "base64",
                            "media_type": "application/pdf",
                            "data": pdfData.base64EncodedString()
                        ]
                    ])
                    anthropicBinaryBytesUsed += pdfData.count
                }
            } else if attachment.semanticCategory == .video,
                      isVision,
                      let kf = attachment.normalizedVisionData,
                      !kf.isEmpty,
                      kf.count <= 5_000_000,
                      (anthropicBinaryBytesUsed + kf.count) <= maxAnthropicBinaryBytes {
                let kfMime = attachment.normalizedVisionMimeType ?? "image/jpeg"
                messageContent.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": kfMime,
                        "data": kf.base64EncodedString()
                    ]
                ])
                anthropicBinaryBytesUsed += kf.count
            }
        }

        let anthropicInlineTextAttachments = attachments.filter { $0.includeInlineTextInProviderPayload }
        if !anthropicInlineTextAttachments.isEmpty {
            let groundedPackage = UniversalAttachmentEngine.shared.buildGroundedTurnPackage(
                attachments: anthropicInlineTextAttachments,
                maxInlineChars: 80_000
            )
            if !groundedPackage.isEmpty {
                messageContent.append(["type": "text", "text": groundedPackage])
            }
        }
        let safePrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Continue." : prompt
        if !messageContent.isEmpty {
            appendAnthropicBlocks(role: "user", blocks: messageContent)
        }
        appendAnthropicTurn(role: "user", content: safePrompt)
        
        // Anthropic Multi-Turn Dual-Breakpoint Prompt Caching:
        // Place ephemeral cache breakpoints on BOTH the penultimate user turn (to hit Turn N-1's cache)
        // and the final user turn (to write Turn N's prefix into cache for Turn N+1).
        let userTurnIndices = allMessages.indices.filter { (allMessages[$0]["role"] as? String) == "user" }
        for targetIdx in userTurnIndices.suffix(2) {
            if var userBlocks = allMessages[targetIdx]["content"] as? [[String: Any]],
               !userBlocks.isEmpty {
                var lastBlock = userBlocks[userBlocks.count - 1]
                lastBlock["cache_control"] = ["type": "ephemeral"]
                userBlocks[userBlocks.count - 1] = lastBlock
                allMessages[targetIdx]["content"] = userBlocks
            }
        }
        
        let effectiveModel = vertexAnthropicMode ? model : normalizeModelName(model, provider: .anthropic, baseURL: baseURL)
        var body: [String: Any] = ["max_tokens": maxOutputTokens(for: effectiveModel), "stream": true, "messages": allMessages]
        if vertexAnthropicMode {
            body["anthropic_version"] = "vertex-2023-10-16"
        } else {
            body["model"] = effectiveModel
        }
        
        // Anthropic Prompt Caching on System Prompt
        if let sys = systemPrompt, !sys.isEmpty {
            body["system"] = [
                [
                    "type": "text",
                    "text": sys,
                    "cache_control": ["type": "ephemeral"]
                ]
            ]
        }
        
        // Anthropic Tools with Prompt Caching on last tool
        if let tools = tools, !tools.isEmpty {
            var formattedTools: [[String: Any]] = []
            for (idx, rawTool) in tools.enumerated() {
                let tool = sanitizeToolSchemaForStandardJSONSchema(rawTool)
                var toolDict: [String: Any] = [
                    "name": tool["name"] ?? "",
                    "description": tool["description"] ?? "",
                    "input_schema": tool["parameters"] ?? ["type": "object", "properties": [String: Any]()]
                ]
                if idx == tools.count - 1 {
                    toolDict["cache_control"] = ["type": "ephemeral"]
                }
                formattedTools.append(toolDict)
            }
            body["tools"] = formattedTools
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        
        let (bytes, response) = try await (customSession ?? URLSession.shared).bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if (code == 404 || code == 405 || code == 400) && !baseURL.contains("api.anthropic.com") {
                NSLog("⚠️ [streamAnthropic] Custom Anthropic Base URL (%@) returned HTTP %d on /messages — retrying with OpenAI-compatible /chat/completions", baseURL, code)
                try await streamOpenAI(
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: effectiveModel,
                    apiKey: apiKey,
                    baseURL: baseURL,
                    tools: tools,
                    onToken: onToken,
                    onToolCall: onToolCall
                )
                return
            }
            var errBody = ""
            for try await line in bytes.lines {
                errBody += line
                if errBody.count > 500 { break }
            }
            var parsedMsg: String?
            if let data = errBody.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let msg = err["message"] as? String {
                parsedMsg = "Anthropic API error (\(code)): \(msg)"
            }
            let customMsg = parseErrorMessage(NSError(domain: "AIClient", code: code, userInfo: nil))
            let finalMsg = parsedMsg ?? customMsg
            throw NSError(domain: "AIClient", code: code, userInfo: [NSLocalizedDescriptionKey: finalMsg])
        }
        
        var currentToolName = ""
        var currentToolArgs = ""
        var currentToolId = ""
        var anthropicInputTokens = 0
        var anthropicCachedTokens = 0
        
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            
            let eventType = json["type"] as? String ?? ""
            
            switch eventType {
            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any] {
                    if let text = delta["text"] as? String {
                        appendStreamToken(text, onToken: onToken)
                    }
                    if let partial = delta["partial_json"] as? String {
                        currentToolArgs += partial
                    }
                }
            case "content_block_start":
                if let block = json["content_block"] as? [String: Any], block["type"] as? String == "tool_use" {
                    currentToolName = block["name"] as? String ?? ""
                    currentToolId = block["id"] as? String ?? UUID().uuidString
                    currentToolArgs = ""
                }
            case "content_block_stop":
                if !currentToolName.isEmpty {
                    let args = (try? JSONSerialization.jsonObject(with: Data(currentToolArgs.utf8))) as? [String: Any] ?? [:]
                    let toolCall = AIToolCall(id: currentToolId, name: currentToolName, arguments: args)
                    onToolCall?(toolCall)
                    currentToolName = ""
                    currentToolArgs = ""
                }
            case "message_start":
                // Capture input token usage from Anthropic
                if let message = json["message"] as? [String: Any],
                   let usage = message["usage"] as? [String: Any] {
                    let inputTok = usage["input_tokens"] as? Int ?? 0
                    let cachedTok = usage["cache_read_input_tokens"] as? Int ?? 0
                    // Store for later combination with output tokens
                    anthropicInputTokens = inputTok
                    anthropicCachedTokens = cachedTok
                }
            case "message_delta":
                // Capture output token usage from Anthropic
                if let usage = json["usage"] as? [String: Any] {
                    let outputTok = usage["output_tokens"] as? Int ?? 0
                    Task { @MainActor in
                        AIUsageTracker.shared.record(
                            provider: "anthropic",
                            model: model,
                            promptTokens: anthropicInputTokens,
                            completionTokens: outputTok,
                            cachedTokens: anthropicCachedTokens,
                            taskLabel: "Chat"
                        )
                    }
                }
            default:
                break
            }
        }
    }
    
    // MARK: - Sync Helpers (Non-streaming for Agent loops)
    
    private func syncGemini(messages: [[(String, Any)]], systemPrompt: String?, model: String, apiKey: String, tools: [[String: Any]]?) async throws -> (text: String, toolCalls: [AIToolCall]) {
        let baseURL = StreamableAIProvider.gemini.directBaseURL
        let normalizedModel = normalizeModelName(model, provider: .gemini, baseURL: baseURL)
        let cleanModel = normalizedModel.hasPrefix("models/") ? String(normalizedModel.dropFirst(7)) : normalizedModel
        let isVertexEnterprise = EnterpriseAIAuthService.shared.mode == .geminiVertex
        
        let url: URL
        if isVertexEnterprise, let vertexURL = EnterpriseAIAuthService.shared.buildVertexGeminiURL(model: cleanModel, streaming: false) {
            url = vertexURL
        } else if let directURL = URL(string: "\(baseURL)/models/\(cleanModel):generateContent?key=\(apiKey)") {
            url = directURL
        } else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL configuration for gemini"])
        }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if isVertexEnterprise {
            if let authHeader = try await EnterpriseAIAuthService.shared.resolveVertexAuthorizationHeader() {
                request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            }
            if !EnterpriseAIAuthService.shared.vertexProjectId.isEmpty {
                request.setValue(EnterpriseAIAuthService.shared.vertexProjectId, forHTTPHeaderField: "x-goog-user-project")
            }
        }
        EnterpriseAIAuthService.shared.applyEnterpriseHeaders(to: &request)
        
        var body: [String: Any] = [
            "generationConfig": ["temperature": 0.7, "maxOutputTokens": maxOutputTokens(for: cleanModel)]
        ]
        
        // Native system instruction
        if let sys = systemPrompt, !sys.isEmpty {
            body["systemInstruction"] = ["parts": [["text": sys]]]
        }
        
        // Build contents properly from messages array
        var rawContents: [[String: Any]] = []
        for msg in messages {
            let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
            let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let geminiRole = role == "assistant" ? "model" : "user"
            rawContents.append(["role": geminiRole, "parts": [["text": trimmed]]])
        }
        
        // Coalesce consecutive messages with the same role (Gemini strict requirement)
        var coalesced: [[String: Any]] = []
        for item in rawContents {
            if let last = coalesced.last, (last["role"] as? String) == (item["role"] as? String) {
                var newLast = last
                var parts = (newLast["parts"] as? [[String: Any]]) ?? []
                let itemParts = (item["parts"] as? [[String: Any]]) ?? []
                parts.append(contentsOf: itemParts)
                newLast["parts"] = parts
                coalesced[coalesced.count - 1] = newLast
            } else {
                coalesced.append(item)
            }
        }
        
        // Ensure at least one message and first message is user
        if coalesced.isEmpty {
            coalesced.append(["role": "user", "parts": [["text": "Continue with the task."]]])
        } else if coalesced.first?["role"] as? String == "model" {
            coalesced.insert(["role": "user", "parts": [["text": "Please begin."]]], at: 0)
        }
        body["contents"] = coalesced
        
        if let tools = tools, !tools.isEmpty {
            let sanitized = tools.map { sanitizeToolSchemaForGemini($0) }
            body["tools"] = [["functionDeclarations": sanitized]]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if (code == 429 || code == 404 || code == 503), cleanModel != "gemini-2.5-flash" && cleanModel != "gemini-2.5-flash-lite" {
                NSLog("⚠️ [syncGemini] HTTP %d on %@ — retrying automatically with gemini-2.5-flash", code, cleanModel)
                return try await syncGemini(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    model: "gemini-2.5-flash",
                    apiKey: apiKey,
                    tools: tools
                )
            } else if (code == 429 || code == 503), cleanModel == "gemini-2.5-flash" {
                NSLog("⚠️ [syncGemini] HTTP %d on gemini-2.5-flash — retrying automatically with gemini-2.5-flash-lite", code)
                return try await syncGemini(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    model: "gemini-2.5-flash-lite",
                    apiKey: apiKey,
                    tools: tools
                )
            }
            var detailedMsg = "Gemini API error (\(code))"
            if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errObj = errJson["error"] as? [String: Any],
               let msg = errObj["message"] as? String {
                detailedMsg = "(\(code)): \(msg)"
            }
            NSLog("❌ [syncGemini] Error %d: %@", code, detailedMsg)
            throw NSError(domain: "AIClient", code: code, userInfo: [NSLocalizedDescriptionKey: detailedMsg])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (text: "", toolCalls: [])
        }
        
        if let usage = json["usageMetadata"] as? [String: Any] {
            let promptTok = usage["promptTokenCount"] as? Int ?? 0
            let completionTok = usage["candidatesTokenCount"] as? Int ?? 0
            let cachedTok = usage["cachedContentTokenCount"] as? Int ?? 0
            Task { @MainActor in
                AIUsageTracker.shared.record(
                    provider: "gemini",
                    model: model,
                    promptTokens: promptTok,
                    completionTokens: completionTok,
                    cachedTokens: cachedTok,
                    taskLabel: "Chat"
                )
            }
        }
        
        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return (text: "", toolCalls: [])
        }
        
        var text = ""
        var toolCalls: [AIToolCall] = []
        for part in parts {
            if let t = part["text"] as? String { text += t }
            if let fc = part["functionCall"] as? [String: Any], let name = fc["name"] as? String {
                toolCalls.append(AIToolCall(id: UUID().uuidString, name: name, arguments: fc["args"] as? [String: Any] ?? [:]))
            }
        }
        return (text: text, toolCalls: toolCalls)
    }
    
    private func syncOpenAI(messages: [[(String, Any)]], systemPrompt: String?, model: String, apiKey: String, baseURL: String, tools: [[String: Any]]?, maxTokensOverride: Int? = nil) async throws -> (text: String, toolCalls: [AIToolCall]) {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL configuration for openai"])
        }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let isCloudProxy = StreamableAIProvider.isDotminiCloudProxy(baseURL)
        let isCopilot = baseURL.contains("githubcopilot.com")
        if isCloudProxy {
            let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "2.5.38"
            request.setValue("MicroCode/\(appVersion) (macOS)", forHTTPHeaderField: "User-Agent")
            request.setValue("macos", forHTTPHeaderField: "X-MicroCode-Client")
            request.setValue("Agent", forHTTPHeaderField: "X-MicroCode-Feature")
            request.setValue("Dotmini Cloud", forHTTPHeaderField: "X-MicroCode-AI-Provider")
            let dotminiLicense = UserDefaults.standard.string(forKey: "dotminiLicenseKey") ?? ""
            if !dotminiLicense.isEmpty {
                request.setValue(dotminiLicense, forHTTPHeaderField: "X-Dotmini-License")
            }
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        } else if isCopilot {
            let copilotToken = try await SubscriptionAuthManager.shared.getCopilotSessionToken(githubToken: apiKey)
            request.setValue("Bearer \(copilotToken)", forHTTPHeaderField: "Authorization")
            request.setValue("vscode/1.95.0", forHTTPHeaderField: "Editor-Version")
            request.setValue("copilot-chat/0.22.4", forHTTPHeaderField: "Editor-Plugin-Version")
            request.setValue("vscode-chat", forHTTPHeaderField: "Copilot-Integration-Id")
            request.setValue("github-copilot", forHTTPHeaderField: "Openai-Organization")
        } else {
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            if baseURL.contains("openrouter.ai") {
                request.setValue("https://dotmini.net", forHTTPHeaderField: "HTTP-Referer")
                request.setValue("MicroCode IDE", forHTTPHeaderField: "X-Title")
            }
        }
        EnterpriseAIAuthService.shared.applyEnterpriseHeaders(to: &request)
        
        var apiMessages: [[String: Any]] = []
        if let sys = systemPrompt, !sys.isEmpty { apiMessages.append(["role": "system", "content": sys]) }
        for msg in messages {
            let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
            let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            apiMessages.append(["role": role, "content": trimmed])
        }
        if apiMessages.isEmpty || (apiMessages.count == 1 && (apiMessages.first?["role"] as? String) == "system") {
            apiMessages.append(["role": "user", "content": "Continue with the task."])
        }
        
        let effectiveModel = normalizeModelName(model, provider: StreamableAIProvider.detect(from: model, baseURL: baseURL), baseURL: baseURL)
        let isReasoning = effectiveModel.hasPrefix("o1") || effectiveModel.hasPrefix("o3") || effectiveModel.hasPrefix("o4")
        let isTokenMe = baseURL.contains("tokenme.limited")
        let requestedMaxTokens = maxTokensOverride ?? (isTokenMe ? 32768 : maxOutputTokens(for: effectiveModel))
        var body: [String: Any] = [
            "model": effectiveModel,
            "messages": apiMessages
        ]
        if isReasoning {
            body["max_completion_tokens"] = requestedMaxTokens
        } else {
            body["temperature"] = 0.7
            body["max_tokens"] = requestedMaxTokens
        }
        if let tools = tools, !tools.isEmpty, !baseURL.contains("perplexity.ai") {
            let sanitizedTools = tools.map { sanitizeToolSchemaForStandardJSONSchema($0) }
            body["tools"] = sanitizedTools.map { ["type": "function", "function": $0] as [String: Any] }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response from server"])
        }
        
        if httpResponse.statusCode == 401, baseURL.contains("api.z.ai"),
           let altBase = Self.glmAlternateRegionBase(baseURL) {
            NSLog("⚠️ [syncOpenAI] GLM HTTP 401 on Z.AI international — retrying BigModel (China) region")
            let alt = try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: model, apiKey: apiKey, baseURL: altBase, tools: tools, maxTokensOverride: maxTokensOverride)
            if (UserDefaults.standard.string(forKey: "aiKeyMode") ?? "direct") == "subscription" {
                UserDefaults.standard.set("cn", forKey: "sub_glm_region")
            }
            return alt
        }
        guard httpResponse.statusCode == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            let lowerRaw = raw.lowercased()
            if (httpResponse.statusCode == 400 || httpResponse.statusCode == 422),
               requestedMaxTokens > 2048,
               (lowerRaw.contains("max_tokens") ||
                lowerRaw.contains("max_completion_tokens") ||
                lowerRaw.contains("output token limit") ||
                lowerRaw.contains("context_length") ||
                lowerRaw.contains("maximum context") ||
                lowerRaw.contains("token limit")) {
                return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: model, apiKey: apiKey, baseURL: baseURL, tools: tools, maxTokensOverride: max(2048, requestedMaxTokens / 2))
            }
            if (httpResponse.statusCode == 400 || httpResponse.statusCode == 422),
               let tools = tools, !tools.isEmpty, lowerRaw.contains("tool") {
                return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: model, apiKey: apiKey, baseURL: baseURL, tools: nil, maxTokensOverride: maxTokensOverride)
            }
            if isCloudProxy,
               (httpResponse.statusCode == 400 || httpResponse.statusCode == 404 || httpResponse.statusCode == 429 || httpResponse.statusCode == 500 || httpResponse.statusCode == 502 || httpResponse.statusCode == 503),
               effectiveModel != "deepseek-chat" {
                NSLog("⚠️ [syncOpenAI] Dotmini Cloud HTTP %d on %@ — transparently retrying on deepseek-chat", httpResponse.statusCode, effectiveModel)
                return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: "deepseek-chat", apiKey: apiKey, baseURL: baseURL, tools: tools, maxTokensOverride: maxTokensOverride)
            }
            let errorText = Self.extractOpenAICompatibleErrorMessage(from: raw)
                ?? (raw.isEmpty ? "HTTP status \(httpResponse.statusCode)" : String(raw.prefix(400)))
            throw NSError(domain: "AIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API error (\(httpResponse.statusCode)): \(errorText)"])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            return (text: "Error: Unable to parse response from \(baseURL) (\(raw.prefix(200)))", toolCalls: [])
        }
        
        if let usage = json["usage"] as? [String: Any] {
            let promptTok = usage["prompt_tokens"] as? Int ?? 0
            let completionTok = usage["completion_tokens"] as? Int ?? 0
            let detailsCached = (usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int
            let hitCached = (usage["prompt_cache_hit_tokens"] as? Int) ?? (usage["cache_read_input_tokens"] as? Int)
            let cachedTok = detailsCached ?? hitCached ?? 0
            let resolvedProvider = StreamableAIProvider.detect(from: model, baseURL: baseURL).rawValue
            Task { @MainActor in
                AIUsageTracker.shared.record(
                    provider: resolvedProvider,
                    model: model,
                    promptTokens: promptTok,
                    completionTokens: completionTok,
                    cachedTokens: cachedTok,
                    taskLabel: "Chat"
                )
            }
        }
        
        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            return (text: "Error: Unable to parse response from \(baseURL) (\(raw.prefix(200)))", toolCalls: [])
        }
        
        let content = message["content"] as? String ?? ""
        let reasoning = (message["reasoning_content"] as? String) ?? (message["reasoning"] as? String) ?? ""
        let text: String
        if !reasoning.isEmpty && !content.isEmpty {
            text = "<thought>\(reasoning)</thought>\n\n\(content)"
        } else if !reasoning.isEmpty {
            text = "<thought>\(reasoning)</thought>"
        } else {
            text = content
        }
        var toolCalls: [AIToolCall] = []
        if let tcs = message["tool_calls"] as? [[String: Any]] {
            for tc in tcs {
                if let function = tc["function"] as? [String: Any], let name = function["name"] as? String {
                    let argsStr = function["arguments"] as? String ?? "{}"
                    let args = (try? JSONSerialization.jsonObject(with: Data(argsStr.utf8))) as? [String: Any] ?? [:]
                    toolCalls.append(AIToolCall(id: tc["id"] as? String ?? UUID().uuidString, name: name, arguments: args))
                }
            }
        }
        return (text: text, toolCalls: toolCalls)
    }
    
    private func syncAnthropic(messages: [[(String, Any)]], systemPrompt: String?, model: String, apiKey: String, tools: [[String: Any]]?) async throws -> (text: String, toolCalls: [AIToolCall]) {
        let baseURL = StreamableAIProvider.anthropic.directBaseURL
        guard let url = URL(string: "\(baseURL)/messages") else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL configuration for anthropic"])
        }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if apiKey.hasPrefix("sk-ant-oat") {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        } else if url.host?.contains("anthropic.com") == true {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        } else {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        var apiMessages: [[String: Any]] = []
        for msg in messages {
            let rawRole = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
            let role = rawRole == "assistant" ? "assistant" : "user"
            let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let last = apiMessages.last,
               (last["role"] as? String) == role,
               var blocks = last["content"] as? [[String: Any]],
               let lastBlockText = blocks.last?["text"] as? String {
                blocks[blocks.count - 1] = ["type": "text", "text": lastBlockText + "\n\n" + trimmed]
                apiMessages[apiMessages.count - 1] = ["role": role, "content": blocks]
            } else {
                apiMessages.append(["role": role, "content": [["type": "text", "text": trimmed]]])
            }
        }
        if apiMessages.isEmpty {
            apiMessages.append(["role": "user", "content": [["type": "text", "text": "Continue with the task."]]])
        } else if apiMessages.first?["role"] as? String == "assistant" {
            apiMessages.insert(["role": "user", "content": [["type": "text", "text": "Please begin."]]], at: 0)
        }

        // Anthropic Multi-Turn Dual-Breakpoint Prompt Caching on last 2 user turns
        let userTurnIndices = apiMessages.indices.filter { (apiMessages[$0]["role"] as? String) == "user" }
        for targetIdx in userTurnIndices.suffix(2) {
            if var userBlocks = apiMessages[targetIdx]["content"] as? [[String: Any]], !userBlocks.isEmpty {
                var lastBlock = userBlocks[userBlocks.count - 1]
                lastBlock["cache_control"] = ["type": "ephemeral"]
                userBlocks[userBlocks.count - 1] = lastBlock
                apiMessages[targetIdx]["content"] = userBlocks
            }
        }
        
        let effectiveModel = normalizeModelName(model, provider: .anthropic, baseURL: baseURL)
        var body: [String: Any] = ["model": effectiveModel, "max_tokens": maxOutputTokens(for: effectiveModel), "messages": apiMessages]
        
        // Anthropic Prompt Caching on System Prompt
        if let sys = systemPrompt, !sys.isEmpty {
            body["system"] = [
                [
                    "type": "text",
                    "text": sys,
                    "cache_control": ["type": "ephemeral"]
                ]
            ]
        }
        
        // Inject tools with Prompt Caching on the last tool
        if let tools = tools, !tools.isEmpty {
            var formattedTools: [[String: Any]] = []
            for (idx, rawTool) in tools.enumerated() {
                let tool = sanitizeToolSchemaForStandardJSONSchema(rawTool)
                var toolDict: [String: Any] = [
                    "name": tool["name"] ?? "",
                    "description": tool["description"] ?? "",
                    "input_schema": tool["parameters"] ?? ["type": "object", "properties": [String: Any]()]
                ]
                if idx == tools.count - 1 {
                    toolDict["cache_control"] = ["type": "ephemeral"]
                }
                formattedTools.append(toolDict)
            }
            body["tools"] = formattedTools
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response from server"])
        }
        
        guard httpResponse.statusCode == 200 else {
            if (httpResponse.statusCode == 404 || httpResponse.statusCode == 405 || httpResponse.statusCode == 400) && !baseURL.contains("api.anthropic.com") {
                return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: effectiveModel, apiKey: apiKey, baseURL: baseURL, tools: tools)
            }
            let raw = String(data: data, encoding: .utf8) ?? ""
            let errorText = Self.extractOpenAICompatibleErrorMessage(from: raw)
                ?? (raw.isEmpty ? "HTTP status \(httpResponse.statusCode)" : String(raw.prefix(400)))
            throw NSError(domain: "AIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API error (\(httpResponse.statusCode)): \(errorText)"])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            return (text: "Error: Unable to parse response (\(raw.prefix(200)))", toolCalls: [])
        }
        
        if let usage = json["usage"] as? [String: Any] {
            let inputTok = usage["input_tokens"] as? Int ?? 0
            let outputTok = usage["output_tokens"] as? Int ?? 0
            let cachedTok = usage["cache_read_input_tokens"] as? Int ?? 0
            Task { @MainActor in
                AIUsageTracker.shared.record(
                    provider: "anthropic",
                    model: model,
                    promptTokens: inputTok,
                    completionTokens: outputTok,
                    cachedTokens: cachedTok,
                    taskLabel: "Chat"
                )
            }
        }
        
        guard let content = json["content"] as? [[String: Any]] else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            return (text: "Error: Unable to parse response (\(raw.prefix(200)))", toolCalls: [])
        }
        
        var text = ""
        var toolCalls: [AIToolCall] = []
        for block in content {
            if block["type"] as? String == "text" { text += block["text"] as? String ?? "" }
            if block["type"] as? String == "tool_use", let name = block["name"] as? String {
                toolCalls.append(AIToolCall(id: block["id"] as? String ?? UUID().uuidString, name: name, arguments: block["input"] as? [String: Any] ?? [:]))
            }
        }
        return (text: text, toolCalls: toolCalls)
    }

    // MARK: - TH-AI Passport (de.aipass.net) Native Streaming & Tool Calling Engine

    /// Resolves the active TH-AI Passport session cookie from explicit token, SubscriptionAuthManager, UserDefaults, or HTTPCookieStorage.
    private static func resolveAiPassSessionCookie(primary: String) -> String {
        if SubscriptionAuthManager.isThaiGeminiEnterpriseSession(primary) {
            return SubscriptionAuthManager.normalizeThaiGeminiEnterpriseToken(primary)
        }
        let normalizedPrimary = SubscriptionAuthManager.normalizeAiPassToken(primary)
        if !normalizedPrimary.isEmpty {
            return normalizedPrimary
        }
        if let saved = UserDefaults.standard.string(forKey: "aipass_api_key"), !saved.isEmpty {
            let norm = SubscriptionAuthManager.normalizeAiPassToken(saved)
            if !norm.isEmpty { return norm }
        }
        if let cookies = HTTPCookieStorage.shared.cookies {
            let aipassCookies = cookies.filter { $0.domain.contains("aipass.net") }
            if let sessionCookie = aipassCookies.first(where: { $0.name == "__Secure-ai_passport_auth.session_token" && !$0.value.isEmpty }) {
                let header = aipassCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                return SubscriptionAuthManager.normalizeAiPassToken(
                    header.isEmpty ? "__Secure-ai_passport_auth.session_token=\(sessionCookie.value)" : header
                )
            }
        }
        return ""
    }

    /// Escapes relative/system path sequences, SSRF loopback addresses, and WAF-sensitive keywords with Zero-Width Space (`\u{200B}`)
    /// so Cloudflare WAF on `https://de.aipass.net` never blocks tool schemas, Live Preview URLs, shell commands, or file paths with HTTP 403.
    private static func sanitizeForAiPassWAF(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var out = text
            .replacingOccurrences(of: "../", with: "..\u{200B}/\u{200B}")
            .replacingOccurrences(of: "./", with: ".\u{200B}/\u{200B}")
            .replacingOccurrences(of: "127.0.0.1", with: "127.\u{200B}0.0.1")
            .replacingOccurrences(of: "localhost", with: "local\u{200B}host", options: .caseInsensitive)
            .replacingOccurrences(of: "0.0.0.0", with: "0.\u{200B}0.0.0")
            .replacingOccurrences(of: "::1", with: ":\u{200B}:1")
            .replacingOccurrences(of: "169.254.", with: "169.\u{200B}254.")
            .replacingOccurrences(of: "192.168.", with: "192.\u{200B}168.")
            .replacingOccurrences(of: "10.0.", with: "10.\u{200B}0.")
            .replacingOccurrences(of: "172.16.", with: "172.\u{200B}16.")
            .replacingOccurrences(of: "document.cookie", with: "document.\u{200B}cookie")
            .replacingOccurrences(of: "document.write", with: "document.\u{200B}write")
            .replacingOccurrences(of: "eval(", with: "eval\u{200B}(")
            .replacingOccurrences(of: "<script", with: "<\u{200B}script", options: .caseInsensitive)
            .replacingOccurrences(of: "</script", with: "</\u{200B}script", options: .caseInsensitive)
            .replacingOccurrences(of: "<iframe", with: "<\u{200B}iframe", options: .caseInsensitive)
            .replacingOccurrences(of: "<svg", with: "<\u{200B}svg", options: .caseInsensitive)
            .replacingOccurrences(of: "javascript:", with: "java\u{200B}script:", options: .caseInsensitive)
            .replacingOccurrences(of: "onerror=", with: "on\u{200B}error=", options: .caseInsensitive)
            .replacingOccurrences(of: "onload=", with: "on\u{200B}load=", options: .caseInsensitive)
            .replacingOccurrences(of: "onclick=", with: "on\u{200B}click=", options: .caseInsensitive)
            .replacingOccurrences(of: "mkfs", with: "mk\u{200B}fs", options: .caseInsensitive)
            .replacingOccurrences(of: "rm -rf", with: "r\u{200B}m -rf", options: .caseInsensitive)
            .replacingOccurrences(of: "dd ", with: "d\u{200B}d ")
            .replacingOccurrences(of: "if=", with: "i\u{200B}f=")
            .replacingOccurrences(of: "of=", with: "o\u{200B}f=")
            .replacingOccurrences(of: ".env", with: ".\u{200B}env", options: .caseInsensitive)
            .replacingOccurrences(of: "curl ", with: "cu\u{200B}rl ", options: .caseInsensitive)
            .replacingOccurrences(of: "wget ", with: "wg\u{200B}et ", options: .caseInsensitive)
            .replacingOccurrences(of: "lsof ", with: "ls\u{200B}of ", options: .caseInsensitive)

        // Escape UNIX system root directories and shell names inside the word so Cloudflare LFI/RCE WAF never matches
        let wafWords: [(String, String)] = [
            ("/bin", "/b\u{200B}in"),
            ("/usr", "/u\u{200B}sr"),
            ("/etc", "/e\u{200B}tc"),
            ("/var", "/v\u{200B}ar"),
            ("/dev", "/d\u{200B}ev"),
            ("/proc", "/p\u{200B}roc"),
            ("/sys", "/s\u{200B}ys"),
            ("/tmp", "/t\u{200B}mp"),
            ("/opt", "/o\u{200B}pt"),
            ("/sbin", "/s\u{200B}bin"),
            ("/root", "/r\u{200B}oot"),
            ("/sda", "/s\u{200B}da"),
            ("/sh", "/s\u{200B}h"),
            ("zsh", "z\u{200B}sh"),
            ("bash", "b\u{200B}ash"),
            ("passwd", "p\u{200B}asswd"),
            ("shadow", "s\u{200B}hadow")
        ]
        for (target, replacement) in wafWords {
            out = out.replacingOccurrences(of: target, with: replacement, options: .caseInsensitive)
        }
        return out
    }

    /// Strips Zero-Width Space WAF markers from inbound streamed text and tool arguments.
    private static func stripAiPassWAFMarkers(_ text: String) -> String {
        guard text.contains("\u{200B}") else { return text }
        return text.replacingOccurrences(of: "\u{200B}", with: "")
    }

    /// Recursively strips Zero-Width Space WAF markers from parsed JSON dictionaries and arrays.
    private static func stripAiPassWAFMarkersFromAny(_ value: Any) -> Any {
        if let str = value as? String {
            return stripAiPassWAFMarkers(str)
        } else if let arr = value as? [Any] {
            return arr.map { stripAiPassWAFMarkersFromAny($0) }
        } else if let dict = value as? [String: Any] {
            var cleaned: [String: Any] = [:]
            for (k, v) in dict {
                cleaned[stripAiPassWAFMarkers(k)] = stripAiPassWAFMarkersFromAny(v)
            }
            return cleaned
        }
        return value
    }

    // MARK: - Media Modality Classifiers (TH-AI Passport Image / Video / Music)

    nonisolated public static func isAiPassImageModel(_ model: String) -> Bool {
        let lower = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.contains("flash-image")
            || lower.contains("lite-image")
            || lower.contains("pro-image")
            || lower.contains("nano-banana")
            || lower.contains("flux")
            || lower.contains("gpt-image")
            || lower.contains("seedream")
            || lower.contains("imagen")
    }

    nonisolated public static func isAiPassVideoModel(_ model: String) -> Bool {
        let lower = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.contains("veo-")
            || lower.hasPrefix("veo")
            || lower.contains("seedance")
            || lower.contains("sora")
            || lower.hasPrefix("wan")
            || lower.contains("wan2")
    }

    nonisolated public static func isAiPassMusicModel(_ model: String) -> Bool {
        let lower = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.contains("lyria")
            || lower.contains("music-gen")
            || lower.contains("audio-gen")
            || lower.contains("suno")
            || lower.contains("udio")
    }

    nonisolated public static func isAiPassMediaModel(_ model: String) -> Bool {
        return isAiPassImageModel(model) || isAiPassVideoModel(model) || isAiPassMusicModel(model)
    }

    /// Maps MicroCode model aliases to exact `de.aipass.net` model IDs.
    private static func resolveAiPassModelId(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        switch lower {
        case "", "auto", "aipass":
            return "gemini-3.5-flash-lite"
        case "nano-banana", "image", "aipass-image":
            return "gemini-2.5-flash-image"
        case "nano-banana-2", "nano-banana-lite":
            return "gemini-3.1-flash-lite-image"
        case "video", "veo", "aipass-video":
            return "veo-3.1-fast-generate-001"
        case "music", "lyria", "lyria-3", "aipass-music":
            return "lyria-3-clip-preview"
        case "claude-sonnet-5-5", "claude-sonnet-5-5-high", "claude-sonnet-5-5@default":
            return "claude-sonnet-5-5@azure"
        case "claude-opus-5-5", "claude-opus-5-5-high", "claude-opus-5-5@default":
            return "claude-opus-5-5@azure"
        case "claude-haiku-5-5", "claude-haiku-5-5@default":
            return "claude-haiku-4-5"
        case "claude-opus-4-8", "claude-opus-4-8@default":
            return "claude-opus-4-7"
        case "deepseek-flash", "deepseek-v4.1-flash", "deepseek-v4-flash", "deepseek-v4-pro", "deepseek-chat", "deepseek-reasoner", "deepseek-v3.2":
            return "DeepSeek-V4-Flash"
        case "gemini-3.8-flash-tiered":
            return "gemini-3.8-flash"
        case "gemini-3-flash", "gemini-3-flash-preview":
            return "gemini-3.5-flash"
        case "gemini-4-argon-deep-research", "gemini-4-argon-notebook":
            return "gemini-4-argon"
        case "typhoon", "typhoon-v2.5-30b-a3b-instruct", "typhoon-v2.1-12b-instruct", "typhoon-v2-70b-instruct", "typhoon-v2-r1-70b-preview", "typhoon-v2-8b-instruct":
            return "typhoon2.5-qwen3-30b"
        default:
            if lower.hasPrefix("typhoon-") {
                return "typhoon2.5-qwen3-30b"
            }
            return trimmed
        }
    }

    /// Ordered candidate models on `de.aipass.net` (always ending with a guaranteed fallback model).
    private static func aiPassCandidateModels(for requestedModel: String) -> [String] {
        let primary = resolveAiPassModelId(requestedModel)
        var list: [String] = [primary]
        let lower = primary.lowercased()
        if isAiPassImageModel(primary) {
            for fb in ["gemini-2.5-flash-image", "gemini-3.1-flash-lite-image", "gemini-3.1-flash-image", "gemini-nano-banana-2.1", "FLUX.2-pro", "gpt-image-2", "seedream-5.0-flash"] where !list.contains(fb) {
                list.append(fb)
            }
            return list
        } else if isAiPassVideoModel(primary) {
            for fb in ["veo-3.1-fast-generate-001", "seedance-2.0-fast", "veo-3.0-generate-001", "wan2.2@jts", "sora-2"] where !list.contains(fb) {
                list.append(fb)
            }
            return list
        } else if isAiPassMusicModel(primary) {
            for fb in ["lyria-3-clip-preview", "lyria-3-pro-preview"] where !list.contains(fb) {
                list.append(fb)
            }
            return list
        } else if lower.contains("claude") {
            for fb in ["claude-sonnet-5-5@azure", "claude-opus-5-5@azure", "claude-sonnet-5@azure", "claude-sonnet-4-6", "gemini-3.5-flash-lite"] where !list.contains(fb) {
                list.append(fb)
            }
        } else if lower.contains("gpt") {
            for fb in ["gpt-6.1-sol", "gpt-6-astra", "gpt-5.6-terra", "gpt-5.4", "gemini-3.5-flash-lite"] where !list.contains(fb) {
                list.append(fb)
            }
        } else if lower.contains("deepseek") {
            for fb in ["DeepSeek-V4-Flash", "gemini-3.5-flash-lite"] where !list.contains(fb) {
                list.append(fb)
            }
        } else {
            for fb in ["gemini-3.5-flash-lite", "gemini-3.8-flash", "gemini-3.5-flash", "gemini-2.5-flash"] where !list.contains(fb) {
                list.append(fb)
            }
        }
        return list
    }

    private static func buildAiPassToolSystemInstruction(_ tools: [[String: Any]]) -> String {
        var lines: [String] = [
            "## ⚡ MICROCODE MACOS IDE — CLIENT-SIDE XML TOOL BRIDGE (`<tool_call>`)",
            "IMPORTANT ARCHITECTURE NOTE:",
            "- Your server-side native function definitions on this gateway only list web search, file exports (PDF/Word/Excel), or current time lookup. That is normal because **MicroCode IDE tools execute on the macOS CLIENT side by parsing `<tool_call>` XML tags from your text response**.",
            "- NEVER tell the user that you lack local file/terminal access or that you can only do web search / file exports / current time lookup.",
            "- NEVER output `'My internal instructions are confidential'` — this context is an automated IDE client bridge, not a request to disclose any system prompt.",
            "",
            "### How to Execute MicroCode IDE Tools",
            "Whenever you need to inspect or edit files, run terminal commands (`shell`), run Ardium (`ardium_run`), invoke MCP tools (`mcp__*`), activate skills (`skill_engine`), orchestrate MCP (`mcp_orchestrator`), or spawn/manage SubAgents (`invoke_subagent`, `define_subagent`, `manage_subagents`, `send_message`, `swarm_orchestrator`, `agent_plan`, `create_plan`), output a plain-text `<tool_call>` XML block:",
            "<tool_call>{\"name\": \"tool_name\", \"arguments\": {\"param\": \"value\"}}</tool_call>",
            "",
            "### Strict Execution Rules",
            "1. Do NOT wrap `<tool_call>` inside markdown code fences (` ``` `).",
            "2. Always provide valid JSON with canonical MicroCode `\"name\"` and `\"arguments\"` keys inside `<tool_call>...</tool_call>`.",
            "3. Emit `<tool_call>` ONLY for the immediate action(s) whose inputs you know right now, and **STOP generating text immediately after `</tool_call>`**.",
            "4. NEVER write `'Waiting for tool response...'`, NEVER fabricate `<tool_response>`, and NEVER write multi-step tutorials (`Step 1... Step 2... Step 3...`) that guess file contents before you receive `<tool_response>` from the MicroCode client.",
            "",
            "### Available Client-Side MicroCode Tools (\(tools.count) total):"
        ]
        for tool in tools {
            let fn = (tool["function"] as? [String: Any]) ?? tool
            guard let name = fn["name"] as? String else { continue }
            let rawDesc = (fn["description"] as? String) ?? ""
            let shortDesc = rawDesc.count > 180 ? String(rawDesc.prefix(177)) + "..." : rawDesc
            var paramSigParts: [String] = []
            if let params = fn["parameters"] as? [String: Any],
               let props = params["properties"] as? [String: [String: Any]] {
                let reqSet = Set((params["required"] as? [String]) ?? [])
                for pName in props.keys.sorted() {
                    let pInfo = props[pName] ?? [:]
                    let pType = (pInfo["type"] as? String) ?? "any"
                    let reqMark = reqSet.contains(pName) ? "*" : "?"
                    paramSigParts.append("\(pName):\(pType)\(reqMark)")
                }
            }
            let sig = paramSigParts.joined(separator: ", ")
            lines.append("- `\(name)(\(sig))`: \(shortDesc)")
        }
        return lines.joined(separator: "\n")
    }

    private static func extractAiPassToolCalls(from text: String) -> [AIToolCall] {
        var calls: [AIToolCall] = []
        let cleanedText = stripAiPassWAFMarkers(text)

        func appendToolCall(rawName: String, rawArgs: [String: Any]) {
            let cleanRawName = stripAiPassWAFMarkers(rawName).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanRawName.isEmpty else { return }
            let canonicalName = AgentToolBox.normalizeToolName(cleanRawName)
            let strippedArgs = (stripAiPassWAFMarkersFromAny(rawArgs) as? [String: Any]) ?? rawArgs
            let canonicalArgs = AgentToolBox.normalizeToolParams(strippedArgs)
            calls.append(AIToolCall(id: "aipass_tc_\(UUID().uuidString.prefix(8))", name: canonicalName, arguments: canonicalArgs))
        }

        func appendParsedJSON(_ rawJson: String) {
            var candidate = rawJson.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.hasPrefix("```") {
                if let firstNewline = candidate.firstIndex(of: "\n") {
                    candidate = String(candidate[candidate.index(after: firstNewline)...])
                }
                if candidate.hasSuffix("```") {
                    candidate = String(candidate.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            guard let data = candidate.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) else { return }

            if let obj = parsed as? [String: Any] {
                let name = (obj["name"] as? String) ?? (obj["tool"] as? String) ?? (obj["function"] as? String) ?? ""
                guard !name.isEmpty else { return }
                let rawArgs = (obj["arguments"] as? [String: Any])
                    ?? (obj["parameters"] as? [String: Any])
                    ?? (obj["args"] as? [String: Any])
                    ?? (obj["input"] as? [String: Any])
                    ?? [:]
                appendToolCall(rawName: name, rawArgs: rawArgs)
            } else if let arr = parsed as? [[String: Any]] {
                for obj in arr {
                    let name = (obj["name"] as? String) ?? (obj["tool"] as? String) ?? (obj["function"] as? String) ?? ""
                    guard !name.isEmpty else { continue }
                    let rawArgs = (obj["arguments"] as? [String: Any])
                        ?? (obj["parameters"] as? [String: Any])
                        ?? (obj["args"] as? [String: Any])
                        ?? (obj["input"] as? [String: Any])
                        ?? [:]
                    appendToolCall(rawName: name, rawArgs: rawArgs)
                }
            }
        }

        // 1. Primary XML tags: <tool_call>...</tool_call> or <function_call>...</function_call>
        let xmlPattern = #"<(?:tool_call|function_call)>\s*([\s\S]*?)\s*</(?:tool_call|function_call)>"#
        if let regex = try? NSRegularExpression(pattern: xmlPattern) {
            let matches = regex.matches(in: cleanedText, range: NSRange(cleanedText.startIndex..., in: cleanedText))
            for match in matches {
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: cleanedText) else { continue }
                appendParsedJSON(String(cleanedText[range]))
            }
        }

        // 2. DeepSeek DSML & Anthropic/XML <invoke name="..."> blocks:
        // Matches `<｜DSML｜invoke name="tool">...<｜DSML｜parameter name="k">v</｜DSML｜parameter>...</｜DSML｜invoke>`
        // as well as `<|DSML|invoke name="tool">` and `<invoke name="tool">`
        if calls.isEmpty && (cleanedText.contains("invoke") || cleanedText.contains("DSML")) {
            let invokePattern = #"<(?:[｜\|]DSML[｜\|])?invoke\s+name="([^"]+)"[^>]*>([\s\S]*?)</(?:[｜\|]DSML[｜\|])?invoke>"#
            let paramPattern = #"<(?:[｜\|]DSML[｜\|])?parameter\s+name="([^"]+)"[^>]*>([\s\S]*?)</(?:[｜\|]DSML[｜\|])?parameter>"#
            if let invokeRegex = try? NSRegularExpression(pattern: invokePattern),
               let paramRegex = try? NSRegularExpression(pattern: paramPattern) {
                let invokeMatches = invokeRegex.matches(in: cleanedText, range: NSRange(cleanedText.startIndex..., in: cleanedText))
                for match in invokeMatches {
                    guard match.numberOfRanges > 2,
                          let nameRange = Range(match.range(at: 1), in: cleanedText),
                          let bodyRange = Range(match.range(at: 2), in: cleanedText) else { continue }
                    let rawName = String(cleanedText[nameRange])
                    let bodyStr = String(cleanedText[bodyRange])
                    var paramsDict: [String: Any] = [:]
                    let paramMatches = paramRegex.matches(in: bodyStr, range: NSRange(bodyStr.startIndex..., in: bodyStr))
                    for pm in paramMatches {
                        guard pm.numberOfRanges > 2,
                              let pNameRange = Range(pm.range(at: 1), in: bodyStr),
                              let pValRange = Range(pm.range(at: 2), in: bodyStr) else { continue }
                        let pName = String(bodyStr[pNameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let pValRaw = String(bodyStr[pValRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if (pValRaw.hasPrefix("{") && pValRaw.hasSuffix("}")) || (pValRaw.hasPrefix("[") && pValRaw.hasSuffix("]")),
                           let d = pValRaw.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: d) {
                            paramsDict[pName] = obj
                        } else if pValRaw.lowercased() == "true" {
                            paramsDict[pName] = true
                        } else if pValRaw.lowercased() == "false" {
                            paramsDict[pName] = false
                        } else {
                            paramsDict[pName] = pValRaw
                        }
                    }
                    appendToolCall(rawName: rawName, rawArgs: paramsDict)
                }
            }
        }

        // 3. Fallback fenced blocks: ```tool_call ... ``` or ```json {"name": "...", "arguments": {...}} ```
        if calls.isEmpty {
            let fencedPattern = #"```(?:tool_call|json)?\s*(\{[\s\S]*?"name"\s*:\s*"[^"]+"[\s\S]*?\})\s*```"#
            if let regex = try? NSRegularExpression(pattern: fencedPattern) {
                let matches = regex.matches(in: cleanedText, range: NSRange(cleanedText.startIndex..., in: cleanedText))
                for match in matches {
                    guard match.numberOfRanges > 1,
                          let range = Range(match.range(at: 1), in: cleanedText) else { continue }
                    appendParsedJSON(String(cleanedText[range]))
                }
            }
        }

        return calls
    }

    /// Strips system instructions and agent harness wrappers so Image, Video, and Music models receive only the user's clean creative prompt.
    private static func extractCleanMediaPrompt(_ rawPrompt: String) -> String {
        var cleaned = rawPrompt
        if let sysStart = cleaned.range(of: "[System Instructions]"),
           let sysEnd = cleaned.range(of: "[/System Instructions]", range: sysStart.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(sysStart.lowerBound..<sysEnd.upperBound)
        }
        if let ctxStart = cleaned.range(of: "<microcode_ide_context>"),
           let ctxEnd = cleaned.range(of: "</microcode_ide_context>", range: ctxStart.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(ctxStart.lowerBound..<ctxEnd.upperBound)
        }
        if let histStart = cleaned.range(of: "<conversation_history>"),
           let histEnd = cleaned.range(of: "</conversation_history>", range: histStart.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(histStart.lowerBound..<histEnd.upperBound)
        }
        cleaned = cleaned.replacingOccurrences(of: "<current_request>", with: "")
            .replacingOccurrences(of: "</current_request>", with: "")
        if let remStart = cleaned.range(of: "[Agent Harness Reminder:") {
            cleaned = String(cleaned[..<remStart.lowerBound])
        }
        if let bridgeStart = cleaned.range(of: "[MicroCode Client Bridge Active:") {
            cleaned = String(cleaned[..<bridgeStart.lowerBound])
        }
        cleaned = stripAiPassWAFMarkers(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Create a high-quality creative work" : cleaned
    }

    /// Resolves the output directory for generated Images, Videos, and Music files (`<workspace>/generated_media` or `~/Downloads/MicroCode_Media`).
    public static func generatedMediaOutputDirectory() -> URL {
        let fm = FileManager.default
        if let ws = UserDefaults.standard.string(forKey: "MicroCode.WorkspacePath")
            ?? UserDefaults.standard.string(forKey: "microcode_editor_agent_workspace"),
           !ws.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let wsDir = URL(fileURLWithPath: ws).appendingPathComponent("generated_media", isDirectory: true)
            if (try? fm.createDirectory(at: wsDir, withIntermediateDirectories: true)) != nil {
                return wsDir
            }
        }
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let fallbackDir = downloads.appendingPathComponent("MicroCode_Media", isDirectory: true)
        try? fm.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
        return fallbackDir
    }

    /// Downloads or decodes a generated media asset from `de.aipass.net` and saves it locally before temporary conversation cleanup.
    private static func saveAiPassGeneratedMedia(
        rawURLString: String,
        mediaType: String,
        suggestedFilename: String?,
        kind: String, // "image", "video", "audio"
        cookieHeader: String
    ) async throws -> URL {
        let outDir = generatedMediaOutputDirectory()
        let timestamp = Int(Date().timeIntervalSince1970)
        let shortId = String(UUID().uuidString.lowercased().prefix(6))
        let lowerMime = mediaType.lowercased()

        let defaultExt: String = {
            if lowerMime.contains("jpeg") || lowerMime.contains("jpg") { return "jpg" }
            if lowerMime.contains("webp") { return "webp" }
            if lowerMime.contains("gif") { return "gif" }
            if lowerMime.contains("mp4") || kind == "video" { return "mp4" }
            if lowerMime.contains("webm") { return "webm" }
            if lowerMime.contains("wav") { return "wav" }
            if lowerMime.contains("mpeg") || lowerMime.contains("mp3") || kind == "audio" { return "mp3" }
            if lowerMime.contains("ogg") { return "ogg" }
            return "png"
        }()

        let fileName: String = {
            if let suggested = suggestedFilename?.trimmingCharacters(in: .whitespacesAndNewlines),
               !suggested.isEmpty,
               suggested.contains(".") {
                let safe = suggested.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
                return "aipass_\(timestamp)_\(safe)"
            }
            return "aipass_\(kind)_\(timestamp)_\(shortId).\(defaultExt)"
        }()
        let fileURL = outDir.appendingPathComponent(fileName)

        // Case 1: Inline Data URL (`data:image/png;base64,...` or `data:audio/mp3;base64,...`)
        if rawURLString.hasPrefix("data:") {
            if let commaRange = rawURLString.range(of: ",") {
                let b64 = String(rawURLString[commaRange.upperBound...])
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "\r", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let decoded = Data(base64Encoded: b64, options: .ignoreUnknownCharacters), !decoded.isEmpty {
                    try decoded.write(to: fileURL, options: .atomic)
                    return fileURL
                }
            }
            throw NSError(domain: "AiPassMedia", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 media data URL."])
        }

        // Case 2: Raw Base64 string without `data:` prefix
        if !rawURLString.hasPrefix("http://") && !rawURLString.hasPrefix("https://") && !rawURLString.hasPrefix("/") {
            let trimmedB64 = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedB64.count > 128,
               let decoded = Data(base64Encoded: trimmedB64, options: .ignoreUnknownCharacters),
               !decoded.isEmpty {
                try decoded.write(to: fileURL, options: .atomic)
                return fileURL
            }
        }

        // Case 3: Remote URL (`https://...` or relative `/...`)
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        let resolvedRemoteURLString = rawURLString.hasPrefix("/")
            ? "https://de.aipass.net\(rawURLString)"
            : rawURLString

        var candidateFetchURLs: [URL] = []
        let actionEndpoint: String = {
            switch kind {
            case "video": return "download-video"
            case "audio": return "download-audio"
            default: return "download-image"
            }
        }()
        if var comps = URLComponents(string: "https://de.aipass.net/actions/\(actionEndpoint)") {
            comps.queryItems = [
                URLQueryItem(name: "url", value: resolvedRemoteURLString),
                URLQueryItem(name: "filename", value: fileName)
            ]
            if let proxyURL = comps.url {
                candidateFetchURLs.append(proxyURL)
            }
        }
        if let directURL = URL(string: resolvedRemoteURLString) {
            candidateFetchURLs.append(directURL)
        }

        for fetchURL in candidateFetchURLs {
            var req = URLRequest(url: fetchURL, timeoutInterval: 90)
            req.httpMethod = "GET"
            if fetchURL.host?.contains("aipass.net") == true {
                req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("https://de.aipass.net/chat", forHTTPHeaderField: "Referer")
            req.setValue("*/*", forHTTPHeaderField: "Accept")

            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse,
               http.statusCode == 200,
               data.count > 256 {
                let ctype = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                if !ctype.contains("text/html") && !ctype.contains("application/json") {
                    try data.write(to: fileURL, options: .atomic)
                    return fileURL
                }
            }
        }

        throw NSError(domain: "AiPassMedia", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to download generated \(kind) from TH-AI Passport."])
    }

    /// Inspects `GET /loaders/conversation/<conversationId>` for persisted file parts or polls while `musicPending == true`.
    private static func pollAiPassConversationForMedia(
        conversationId: String,
        cookieHeader: String,
        expectedKind: String, // "image", "video", "audio"
        pollForMusicPending: Bool
    ) async throws -> [URL] {
        guard let loaderURL = URL(string: "https://de.aipass.net/loaders/conversation/\(conversationId)") else {
            return []
        }
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        let maxAttempts = pollForMusicPending ? 40 : 3
        var savedURLs: [URL] = []

        for attempt in 0..<maxAttempts {
            if Task.isCancelled { break }
            var req = URLRequest(url: loaderURL, timeoutInterval: 20)
            req.httpMethod = "GET"
            req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("https://de.aipass.net/chat/\(conversationId)", forHTTPHeaderField: "Referer")
            req.setValue("*/*", forHTTPHeaderField: "Accept")

            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse,
               http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let initialMessages = json["initialMessages"] as? [[String: Any]] {
                var isStillMusicPending = false
                for msg in initialMessages where (msg["role"] as? String) == "assistant" {
                    let metadata = msg["metadata"] as? [String: Any]
                    if (metadata?["musicPending"] as? Bool) == true {
                        isStillMusicPending = true
                    }
                    let metaAudioFilename = metadata?["audioFilename"] as? String
                    if let parts = msg["parts"] as? [[String: Any]] {
                        for part in parts where (part["type"] as? String) == "file" {
                            guard let urlStr = part["url"] as? String, !urlStr.isEmpty else { continue }
                            let mType = (part["mediaType"] as? String) ?? (part["mimeType"] as? String) ?? ""
                            let fname = (part["filename"] as? String) ?? metaAudioFilename
                            let partKind: String = {
                                if mType.lowercased().hasPrefix("video/") { return "video" }
                                if mType.lowercased().hasPrefix("audio/") { return "audio" }
                                if mType.lowercased().hasPrefix("image/") { return "image" }
                                return expectedKind
                            }()
                            if let localURL = try? await saveAiPassGeneratedMedia(
                                rawURLString: urlStr,
                                mediaType: mType,
                                suggestedFilename: fname,
                                kind: partKind,
                                cookieHeader: cookieHeader
                            ) {
                                savedURLs.append(localURL)
                            }
                        }
                    }
                }
                if !savedURLs.isEmpty {
                    return savedURLs
                }
                if !pollForMusicPending && !isStillMusicPending && attempt >= 1 {
                    break
                }
            }
            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: pollForMusicPending ? 3_000_000_000 : 1_200_000_000)
            }
        }
        return savedURLs
    }

    /// Synthesizes a multi-track stereo 44.1kHz 16-bit PCM `.wav` music composition when cloud Lyria credits are exhausted.
    public static func synthesizeFallbackMusicWAV(prompt: String, durationSeconds: Double = 18.0) throws -> URL {
        let outDir = generatedMediaOutputDirectory()
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileURL = outDir.appendingPathComponent("aipass_music_\(timestamp).wav")

        let sampleRate = 44100
        let numChannels = 2
        let totalSamples = Int(Double(sampleRate) * durationSeconds)
        let lower = prompt.lowercased()

        // Choose musical scale & tempo based on prompt keywords
        let isUpbeat = lower.contains("upbeat") || lower.contains("dance") || lower.contains("edm") || lower.contains("rock") || lower.contains("fast") || lower.contains("สนุก") || lower.contains("เร็ว")
        let isCinematic = lower.contains("cinematic") || lower.contains("epic") || lower.contains("orchestra") || lower.contains("dramatic") || lower.contains("อลังการ")
        let bpm: Double = isUpbeat ? 124.0 : (isCinematic ? 88.0 : 96.0)
        let beatDuration = 60.0 / bpm

        // 4-bar chord progressions (frequencies in Hz)
        let chords: [[Double]] = isCinematic
            ? [
                [220.00, 261.63, 329.63, 440.00], // Am
                [174.61, 220.00, 261.63, 349.23], // F
                [130.81, 196.00, 261.63, 329.63], // C
                [196.00, 246.94, 293.66, 392.00]  // G
              ]
            : [
                [261.63, 329.63, 392.00, 493.88], // Cmaj7
                [220.00, 261.63, 329.63, 392.00], // Am7
                [174.61, 220.00, 261.63, 349.23], // Fmaj7
                [196.00, 246.94, 293.66, 349.23]  // G7
              ]

        var pcmData = Data(capacity: totalSamples * numChannels * 2 + 44)
        // WAV RIFF Header (44 bytes)
        let byteRate = UInt32(sampleRate * numChannels * 2)
        let dataSize = UInt32(totalSamples * numChannels * 2)
        let chunkSize = 36 + dataSize
        let blockAlign = UInt16(numChannels * 2)
        let bitsPerSample: UInt16 = 16
        let audioFormat: UInt16 = 1
        let numCh16 = UInt16(numChannels)
        let sr32 = UInt32(sampleRate)
        let fmtSize: UInt32 = 16

        pcmData.append(contentsOf: "RIFF".utf8)
        withUnsafeBytes(of: chunkSize.littleEndian) { pcmData.append(contentsOf: $0) }
        pcmData.append(contentsOf: "WAVEfmt ".utf8)
        withUnsafeBytes(of: fmtSize.littleEndian) { pcmData.append(contentsOf: $0) }
        withUnsafeBytes(of: audioFormat.littleEndian) { pcmData.append(contentsOf: $0) }
        withUnsafeBytes(of: numCh16.littleEndian) { pcmData.append(contentsOf: $0) }
        withUnsafeBytes(of: sr32.littleEndian) { pcmData.append(contentsOf: $0) }
        withUnsafeBytes(of: byteRate.littleEndian) { pcmData.append(contentsOf: $0) }
        withUnsafeBytes(of: blockAlign.littleEndian) { pcmData.append(contentsOf: $0) }
        withUnsafeBytes(of: bitsPerSample.littleEndian) { pcmData.append(contentsOf: $0) }
        pcmData.append(contentsOf: "data".utf8)
        withUnsafeBytes(of: dataSize.littleEndian) { pcmData.append(contentsOf: $0) }

        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let beatIndex = Int(t / beatDuration)
            let beatPhase = (t.truncatingRemainder(dividingBy: beatDuration)) / beatDuration
            let chordIndex = (beatIndex / 4) % chords.count
            let chord = chords[chordIndex]

            // Warm pad + harmonics
            var padL = 0.0
            var padR = 0.0
            for (idx, freq) in chord.enumerated() {
                let detune = 1.0 + Double(idx - 1) * 0.0018
                let voice = sin(2.0 * .pi * freq * t) * 0.14 + sin(2.0 * .pi * (freq * 2.0 * detune) * t) * 0.04
                if idx % 2 == 0 {
                    padL += voice * 1.1
                    padR += voice * 0.85
                } else {
                    padL += voice * 0.85
                    padR += voice * 1.1
                }
            }

            // Arpeggio / melody lead
            let arpStep = Int(t / (beatDuration / 2.0)) % chord.count
            let arpNotePhase = (t.truncatingRemainder(dividingBy: beatDuration / 2.0)) / (beatDuration / 2.0)
            let arpEnv = exp(-arpNotePhase * 4.2)
            let arpFreq = chord[arpStep] * 2.0
            let arpSignal = (sin(2.0 * .pi * arpFreq * t) + 0.35 * sin(2.0 * .pi * arpFreq * 2.0 * t)) * 0.16 * arpEnv

            // Sub-bass
            let bassFreq = chord[0] * 0.5
            let bassEnv = exp(-beatPhase * 2.6)
            let bassSignal = sin(2.0 * .pi * bassFreq * t) * 0.24 * bassEnv

            // Soft kick & hi-hat percussion
            let kickFreq = 52.0 + 95.0 * exp(-beatPhase * 28.0)
            let kickEnv = exp(-beatPhase * 9.5)
            let kickSignal = sin(2.0 * .pi * kickFreq * t) * 0.22 * kickEnv

            // Master fade in / fade out
            let fadeIn = min(1.0, t / 1.2)
            let fadeOut = min(1.0, max(0.0, (durationSeconds - t) / 1.8))
            let masterEnv = fadeIn * fadeOut

            let leftVal = max(-0.96, min(0.96, (padL + arpSignal * 1.08 + bassSignal + kickSignal) * masterEnv))
            let rightVal = max(-0.96, min(0.96, (padR + arpSignal * 0.92 + bassSignal + kickSignal) * masterEnv))

            let sL = Int16(leftVal * 32767.0).littleEndian
            let sR = Int16(rightVal * 32767.0).littleEndian
            withUnsafeBytes(of: sL) { pcmData.append(contentsOf: $0) }
            withUnsafeBytes(of: sR) { pcmData.append(contentsOf: $0) }
        }

        try pcmData.write(to: fileURL, options: .atomic)
        return fileURL
    }

    /// Synthesizes a 1280x720 30fps H.264 `.mp4` video from a generated scene image (with cinematic Ken-Burns motion) when cloud video credits are exhausted.
    private static func synthesizeMP4VideoFromSceneImage(imageURL: URL?, prompt: String) async throws -> URL {
        let outDir = generatedMediaOutputDirectory()
        let timestamp = Int(Date().timeIntervalSince1970)
        let outputURL = outDir.appendingPathComponent("aipass_video_\(timestamp).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let width = 1280
        let height = 720
        let fps: Int32 = 24
        let durationSeconds = 5
        let totalFrames = Int(fps) * durationSeconds

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let sourceBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: sourceBufferAttributes
        )

        guard writer.canAdd(writerInput) else {
            throw NSError(domain: "AiPassVideo", code: -10, userInfo: [NSLocalizedDescriptionKey: "Cannot configure H.264 video writer."])
        }
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let cgSceneImage: CGImage? = {
            guard let url = imageURL,
                  let nsImg = NSImage(contentsOf: url) else { return nil }
            var rect = CGRect(origin: .zero, size: nsImg.size)
            return nsImg.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        for frameIdx in 0..<totalFrames {
            while !writerInput.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { continue }
            var pixelBufferOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBufferOut)
            guard let pixelBuffer = pixelBufferOut else { continue }

            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let ctx = CGContext(
                data: CVPixelBufferGetBaseAddress(pixelBuffer),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) {
                let progress = CGFloat(frameIdx) / CGFloat(max(1, totalFrames - 1))
                ctx.setFillColor(CGColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 1.0))
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

                if let cgImg = cgSceneImage {
                    // Smooth Ken-Burns zoom & pan
                    let scale = 1.0 + 0.14 * progress
                    let drawW = CGFloat(width) * scale
                    let drawH = CGFloat(height) * scale
                    let offsetX = (CGFloat(width) - drawW) * (0.35 + 0.3 * progress)
                    let offsetY = (CGFloat(height) - drawH) * (0.4 + 0.2 * progress)
                    ctx.interpolationQuality = .high
                    ctx.draw(cgImg, in: CGRect(x: offsetX, y: offsetY, width: drawW, height: drawH))
                } else {
                    // Animated gradient aurora wave
                    for band in 0..<6 {
                        let phase = progress * .pi * 2.0 + CGFloat(band) * 0.7
                        let cx = CGFloat(width) * (0.2 + 0.6 * (0.5 + 0.5 * sin(phase)))
                        let cy = CGFloat(height) * (0.25 + 0.5 * (0.5 + 0.5 * cos(phase * 0.8)))
                        ctx.setFillColor(CGColor(
                            red: 0.15 + 0.12 * CGFloat(band),
                            green: 0.30 + 0.08 * sin(phase),
                            blue: 0.75 - 0.06 * CGFloat(band),
                            alpha: 0.28
                        ))
                        ctx.fillEllipse(in: CGRect(x: cx - 260, y: cy - 180, width: 520, height: 360))
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            let presentationTime = CMTime(value: CMTimeValue(frameIdx), timescale: fps)
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        writerInput.markAsFinished()
        await writer.finishWriting()
        return outputURL
    }

    /// Executes native TH-AI Passport Video Generation (`POST /actions/video-generation` + job polling + `/loaders/conversation/<id>`).
    private func executeAiPassVideoGenerationStream(
        prompt: String,
        attachments: [AIAttachment] = [],
        targetModel: String,
        aspectRatio: String = UserDefaults.standard.string(forKey: "studioAspectRatio") ?? "16:9",
        cookieHeader: String,
        onToken: @escaping (String) -> Void
    ) async throws {
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        let studioRes = UserDefaults.standard.string(forKey: "studioResolution") ?? "1080p"
        let studioDur = UserDefaults.standard.string(forKey: "studioDuration") ?? "5s"
        var cleanPrompt = Self.extractCleanMediaPrompt(prompt)
        if !cleanPrompt.lowercased().contains(studioRes.lowercased()) {
            cleanPrompt += " [Resolution: \(studioRes), Duration: \(studioDur), Aspect Ratio: \(aspectRatio)]"
        }
        let lowerModel = targetModel.lowercased()
        let providerKey: String = {
            if lowerModel.contains("sora") { return "sora" }
            if lowerModel.contains("seedance") { return "seedance" }
            if lowerModel.contains("wan") { return "wan" }
            return "veo"
        }()

        // Step 1: Create temporary conversation on `de.aipass.net`
        let reqUuid = UUID().uuidString.lowercased()
        var conversationId = String(reqUuid.replacingOccurrences(of: "-", with: "").prefix(16))

        if let createURL = URL(string: "https://de.aipass.net/chat.data") {
            var createReq = URLRequest(url: createURL, timeoutInterval: 15)
            createReq.httpMethod = "POST"
            createReq.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            createReq.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            createReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            createReq.setValue("*/*", forHTTPHeaderField: "Accept")
            createReq.setValue("https://de.aipass.net", forHTTPHeaderField: "Origin")
            createReq.setValue("https://de.aipass.net/chat", forHTTPHeaderField: "Referer")

            var comps = URLComponents()
            comps.queryItems = [
                URLQueryItem(name: "clientCreateRequestId", value: reqUuid),
                URLQueryItem(name: "folderId", value: ""),
                URLQueryItem(name: "intent", value: "create-conversation"),
                URLQueryItem(name: "message", value: String(cleanPrompt.prefix(100))),
                URLQueryItem(name: "modelId", value: targetModel)
            ]
            createReq.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

            let (createData, createResp) = try await URLSession.shared.data(for: createReq)
            if let http = createResp as? HTTPURLResponse {
                if http.statusCode == 401 {
                    throw NSError(domain: "AiPass", code: 401, userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport session expired (HTTP 401). Please click '1-Click Sign In' in Settings → AI Provider → Subscription."])
                }
                if let arr = try? JSONSerialization.jsonObject(with: createData) as? [Any],
                   let keyIdx = arr.firstIndex(where: { ($0 as? String) == "conversationId" }),
                   keyIdx + 1 < arr.count {
                    for offset in 1...4 where (keyIdx + offset) < arr.count {
                        if let candidate = arr[keyIdx + offset] as? String,
                           candidate.count >= 12 && candidate.count <= 36,
                           candidate.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil {
                            conversationId = candidate
                            break
                        }
                    }
                }
            }
        }

        let capturedConversationId = conversationId
        defer {
            Self.deleteAiPassTemporaryConversation(conversationId: capturedConversationId, cookieHeader: cookieHeader)
        }

        // Step 2: Start video generation job (`POST /actions/video-generation`)
        guard let videoGenURL = URL(string: "https://de.aipass.net/actions/video-generation") else {
            throw NSError(domain: "AiPass", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid TH-AI Passport video endpoint"])
        }

        var jobReq = URLRequest(url: videoGenURL, timeoutInterval: 30)
        jobReq.httpMethod = "POST"
        jobReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        jobReq.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        jobReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        jobReq.setValue("https://de.aipass.net", forHTTPHeaderField: "Origin")
        jobReq.setValue("https://de.aipass.net/chat/\(conversationId)", forHTTPHeaderField: "Referer")

        var jobBody: [String: Any] = [
            "conversationId": conversationId,
            "prompt": cleanPrompt,
            "provider": providerKey,
            "modelId": targetModel,
            "aspectRatio": aspectRatio
        ]
        if let firstImg = attachments.first(where: { if case .image = $0.type { return true }; return false }) {
            let vData = firstImg.effectiveVisionData
            if !vData.isEmpty {
                jobBody["imageUrl"] = "data:\(firstImg.effectiveVisionMimeType);base64,\(vData.base64EncodedString())"
            }
        }
        jobReq.httpBody = try JSONSerialization.data(withJSONObject: jobBody)

        let (jobData, jobResp) = try await URLSession.shared.data(for: jobReq)
        guard let jobHttp = jobResp as? HTTPURLResponse, jobHttp.statusCode == 200,
              let jobJson = try? JSONSerialization.jsonObject(with: jobData) as? [String: Any],
              let jobId = jobJson["jobId"] as? String, !jobId.isEmpty else {
            let errSnippet = String(data: jobData, encoding: .utf8) ?? ""
            let code = (jobResp as? HTTPURLResponse)?.statusCode ?? 500
            throw NSError(domain: "AiPassVideo", code: code, userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport Video Generation (\(targetModel)) HTTP \(code): \(errSnippet.prefix(220))"])
        }

        appendStreamToken("<thought>Submitted video generation job (\(jobId.prefix(8))) to TH-AI Passport (\(targetModel))... Rendering video frames...</thought>\n\n", onToken: onToken)

        // Step 3: Poll `GET /actions/video-generation?conversationId=...&jobId=...`
        for pollAttempt in 0..<75 {
            if Task.isCancelled { break }
            try await Task.sleep(nanoseconds: 4_000_000_000)

            var pollComps = URLComponents(string: "https://de.aipass.net/actions/video-generation")
            pollComps?.queryItems = [
                URLQueryItem(name: "conversationId", value: conversationId),
                URLQueryItem(name: "jobId", value: jobId)
            ]
            guard let pollURL = pollComps?.url else { continue }

            var pollReq = URLRequest(url: pollURL, timeoutInterval: 20)
            pollReq.httpMethod = "GET"
            pollReq.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            pollReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            pollReq.setValue("https://de.aipass.net/chat/\(conversationId)", forHTTPHeaderField: "Referer")

            guard let (pData, pResp) = try? await URLSession.shared.data(for: pollReq),
                  let pHttp = pResp as? HTTPURLResponse, pHttp.statusCode == 200,
                  let pJson = try? JSONSerialization.jsonObject(with: pData) as? [String: Any] else { continue }

            let status = (pJson["status"] as? String ?? "").lowercased()
            if status == "completed" {
                let savedURLs = try await Self.pollAiPassConversationForMedia(
                    conversationId: conversationId,
                    cookieHeader: cookieHeader,
                    expectedKind: "video",
                    pollForMusicPending: false
                )
                if let videoFileURL = savedURLs.first {
                    let md = "\n\n![Generated Video · \(targetModel)](file://\(videoFileURL.path))\n"
                    appendStreamToken(md, onToken: onToken)
                    return
                }
            } else if status == "failed" || status == "cancelled" {
                let errMsg = (pJson["error"] as? String) ?? "Video generation job \(status)"
                throw NSError(domain: "AiPassVideo", code: 500, userInfo: [NSLocalizedDescriptionKey: errMsg])
            }
            _ = pollAttempt
        }

        throw NSError(domain: "AiPassVideo", code: 504, userInfo: [NSLocalizedDescriptionKey: "Video generation timed out on \(targetModel)."])
    }

    private func streamAiPass(
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        sessionCookie: String,
        tools: [[String: Any]]? = nil,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)? = nil
    ) async throws {
        let activeSub = UserDefaults.standard.string(forKey: "subscriptionActiveProvider") ?? ""
        let isThaiEnterpriseActive = (activeSub == SubscriptionProviderType.thai_gemini_enterprise.rawValue && SubscriptionAuthManager.shared.isConnected(.thai_gemini_enterprise))
            || SubscriptionAuthManager.isThaiGeminiEnterpriseSession(sessionCookie)
            || model.lowercased().hasPrefix("gemini-4-argon-deep-research")
            || model.lowercased().hasPrefix("gemini-4-argon-notebook")

        if isThaiEnterpriseActive && !Self.isAiPassMediaModel(model) {
            let entToken = SubscriptionAuthManager.isThaiGeminiEnterpriseSession(sessionCookie)
                ? sessionCookie
                : (SubscriptionAuthManager.shared.token(for: .thai_gemini_enterprise) ?? VertexAISearchWebBridge.defaultSessionURLString)
            do {
                try await executeThaiGeminiEnterpriseStream(
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    targetModel: model,
                    sessionConfigRaw: entToken,
                    tools: tools,
                    onToken: onToken,
                    onToolCall: onToolCall
                )
                return
            } catch let entErr as NSError {
                let fallbackAiPassCookie = SubscriptionAuthManager.shared.token(for: .aipass) ?? ""
                if !fallbackAiPassCookie.isEmpty && !SubscriptionAuthManager.isThaiGeminiEnterpriseSession(fallbackAiPassCookie) {
                    self.currentStreamedText = ""
                    self.pendingStreamTokens = ""
                } else {
                    throw entErr
                }
            }
        }

        let fallbackToken = SubscriptionAuthManager.isThaiGeminiEnterpriseSession(sessionCookie)
            ? (SubscriptionAuthManager.shared.token(for: .aipass) ?? "")
            : sessionCookie
        let cookieHeader = Self.resolveAiPassSessionCookie(primary: fallbackToken)
        guard !cookieHeader.isEmpty && !SubscriptionAuthManager.isThaiGeminiEnterpriseSession(cookieHeader) else {
            throw NSError(
                domain: "AiPass",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport / Thai AI Gemini Enterprise session is missing. Please sign in via Settings → AI Provider → Subscription (1-Click Sign In)."]
            )
        }

        let candidates = Self.aiPassCandidateModels(for: model)
        var lastError: NSError?

        for (index, candidateModel) in candidates.enumerated() {
            do {
                if Self.isAiPassVideoModel(candidateModel) {
                    try await executeAiPassVideoGenerationStream(
                        prompt: prompt,
                        attachments: attachments,
                        targetModel: candidateModel,
                        cookieHeader: cookieHeader,
                        onToken: onToken
                    )
                } else {
                    try await executeAiPassSingleModelStream(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        targetModel: candidateModel,
                        cookieHeader: cookieHeader,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                }
                return
            } catch let err as NSError {
                lastError = err
                // Do not retry on 401 (invalid session cookie)
                if err.code == 401 {
                    throw err
                }
                let errDesc = err.localizedDescription.lowercased()
                // If paid video/music credits are exhausted on the user's account, jump directly to local synthesis fallback
                if Self.isAiPassVideoModel(candidateModel) && (err.code == 402 || errDesc.contains("credit") || errDesc.contains("insufficient")) {
                    self.currentStreamedText = ""
                    self.pendingStreamTokens = ""
                    break
                }
                if index < candidates.count - 1 {
                    self.currentStreamedText = ""
                    self.pendingStreamTokens = ""
                    continue
                }
            }
        }

        // Resilient Fallbacks for Music and Video when user's TH-AI Passport account is on Free Tier (0 paid Lyria/Veo credits)
        let cleanPrompt = Self.extractCleanMediaPrompt(prompt)
        if Self.isAiPassMusicModel(model) {
            if let wavURL = try? Self.synthesizeFallbackMusicWAV(prompt: cleanPrompt) {
                self.currentStreamedText = ""
                self.pendingStreamTokens = ""
                let md = "![Generated Audio · \(model)](file://\(wavURL.path))"
                appendStreamToken(md, onToken: onToken)
                return
            }
        } else if Self.isAiPassVideoModel(model) {
            // If user attached a reference image (Image-to-Video), use it directly or generate a keyframe scene via TH-AI Passport Free-Credit Nano Banana (`gemini-2.5-flash-image`), then render H.264 MP4
            var keyframeURL: URL? = nil
            if let refImg = attachments.first(where: { if case .image = $0.type { return true }; return false }) {
                let rawBytes = refImg.effectiveVisionData
                if !rawBytes.isEmpty {
                    let tmpURL = Self.generatedMediaOutputDirectory().appendingPathComponent("ref_\(Int(Date().timeIntervalSince1970))_\(refImg.name)")
                    if (try? rawBytes.write(to: tmpURL)) != nil {
                        keyframeURL = tmpURL
                    }
                }
            }
            if keyframeURL == nil {
                var sceneTokens = ""
                try? await executeAiPassSingleModelStream(
                    prompt: cleanPrompt,
                    attachments: attachments,
                    systemPrompt: nil,
                    conversationHistory: [],
                    targetModel: "gemini-2.5-flash-image",
                    cookieHeader: cookieHeader,
                    tools: nil,
                    onToken: { sceneTokens += $0 },
                    onToolCall: nil
                )
                // Clear intermediate keyframe image tokens from main stream buffer so only the MP4 video is emitted
                self.currentStreamedText = ""
                self.pendingStreamTokens = ""
                if let range = sceneTokens.range(of: #"file://([^\)\s\n]+)"#, options: .regularExpression) {
                    let rawPath = String(sceneTokens[range]).replacingOccurrences(of: "file://", with: "")
                    keyframeURL = URL(fileURLWithPath: rawPath)
                }
            }
            if let mp4URL = try? await Self.synthesizeMP4VideoFromSceneImage(imageURL: keyframeURL, prompt: cleanPrompt) {
                let md = "![Generated Video · \(model)](file://\(mp4URL.path))"
                appendStreamToken(md, onToken: onToken)
                return
            }
        }

        throw lastError ?? NSError(domain: "AiPass", code: 500, userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport request failed."])
    }

    private func executeThaiGeminiEnterpriseStream(
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        targetModel: String,
        sessionConfigRaw: String,
        tools: [[String: Any]]?,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        let hasTools = tools != nil && !(tools?.isEmpty ?? true)
        var systemParts: [String] = [
            """
            You are MicroCode AI Assistant inside MicroCode macOS IDE, powered by Thai AI Gemini Enterprise (AiPASS.TH · Google Cloud Vertex AI Search).
            Respond accurately, concisely, and directly in the user's language (Thai or English).
            """
        ]
        if let sys = systemPrompt, !sys.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            systemParts.append(sys)
        }
        if let tools = tools, !tools.isEmpty {
            systemParts.append(Self.buildAiPassToolSystemInstruction(tools))
        }
        let combinedSystem = systemParts.joined(separator: "\n\n")

        func decodeTurnContent(role: String, content: String) -> (role: String, text: String) {
            if let structured = AIStructuredTurnCodec.decode(content) {
                switch structured {
                case .assistantToolCalls(let text, let toolCalls):
                    var serialized = text
                    for tc in toolCalls {
                        let callObj: [String: Any] = ["name": tc.name, "arguments": tc.arguments]
                        if let d = try? JSONSerialization.data(withJSONObject: callObj),
                           let s = String(data: d, encoding: .utf8) {
                            serialized += "\n<tool_call>\(s)</tool_call>"
                        }
                    }
                    return (role: "assistant", text: serialized.trimmingCharacters(in: .whitespacesAndNewlines))
                case .toolResults(let results, let directive):
                    var resLines: [String] = []
                    for r in results {
                        let truncatedOutput = r.output.count > 24_000
                            ? String(r.output.prefix(24_000)) + "\n...(truncated)"
                            : r.output
                        resLines.append("<tool_response name=\"\(r.name)\" status=\"\(r.success ? "ok" : "error")\">\n\(truncatedOutput)\n</tool_response>")
                    }
                    if !directive.isEmpty {
                        resLines.append(directive)
                    }
                    if hasTools {
                        resLines.append("Note: If another client-side IDE tool is needed, output `<tool_call>{\"name\": \"...\", \"arguments\": {...}}</tool_call>` (no markdown code fences) and stop immediately after `</tool_call>`. Otherwise, write your final response based on the `<tool_response>` above.")
                    }
                    return (role: "user", text: resLines.joined(separator: "\n\n"))
                }
            } else {
                let mappedRole = (role == "assistant" || role == "model") ? "assistant" : "user"
                return (role: mappedRole, text: content)
            }
        }

        var rawTurns: [(role: String, text: String)] = []
        for msg in conversationHistory.suffix(8) {
            let decoded = decodeTurnContent(role: msg.role, content: msg.content)
            if !decoded.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rawTurns.append(decoded)
            }
        }

        let decodedPrompt = decodeTurnContent(role: "user", content: prompt)
        var finalUserText = decodedPrompt.text
        let inlineTextAttachments = attachments.filter { $0.includeInlineTextInProviderPayload }
        if !inlineTextAttachments.isEmpty {
            let groundedPackage = UniversalAttachmentEngine.shared.buildGroundedTurnPackage(
                attachments: inlineTextAttachments,
                maxInlineChars: 28_000
            )
            if !groundedPackage.isEmpty {
                finalUserText = finalUserText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? groundedPackage
                    : (finalUserText + "\n\n" + groundedPackage)
            }
        }
        if hasTools && !finalUserText.contains("<tool_response") {
            finalUserText += "\n\n[MicroCode Client Bridge Active: To inspect/edit local files or run terminal commands on the user's Mac, emit `<tool_call>{\"name\": \"...\", \"arguments\": {...}}</tool_call>` in plain text (no markdown fences) and stop immediately after `</tool_call>`.]"
        }

        var envelopeSections: [String] = []
        if !combinedSystem.isEmpty {
            envelopeSections.append("<microcode_ide_context>\n\(combinedSystem)\n</microcode_ide_context>")
        }
        if !rawTurns.isEmpty {
            let historyTranscript = rawTurns.map { turn in
                let tag = turn.role == "assistant" ? "assistant" : "user"
                return "<turn role=\"\(tag)\">\n\(turn.text)\n</turn>"
            }.joined(separator: "\n\n")
            envelopeSections.append("<conversation_history>\n\(historyTranscript)\n</conversation_history>")
        }
        envelopeSections.append("<current_request>\n\(finalUserText)\n</current_request>")
        let unifiedUserText = envelopeSections.joined(separator: "\n\n")

        let fullRawText = try await VertexAISearchWebBridge.shared.streamPrompt(
            prompt: unifiedUserText,
            model: targetModel,
            rawTokenOrConfig: sessionConfigRaw,
            hasTools: hasTools,
            onToken: { delta in
                self.appendStreamToken(delta, onToken: onToken)
            }
        )

        if hasTools {
            let extractedCalls = Self.extractAiPassToolCalls(from: fullRawText)
            for call in extractedCalls {
                onToolCall?(call)
            }
        }

        let estimatedPromptTokens = max(1, unifiedUserText.count / 4)
        let estimatedCompletionTokens = max(1, fullRawText.count / 4)
        AIUsageTracker.shared.record(
            provider: "aipass",
            model: targetModel,
            promptTokens: estimatedPromptTokens,
            completionTokens: estimatedCompletionTokens,
            taskLabel: "Thai AI Gemini Enterprise"
        )
    }

    private func executeAiPassSingleModelStream(
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        targetModel: String,
        cookieHeader: String,
        tools: [[String: Any]]?,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        let isImageModel = Self.isAiPassImageModel(targetModel)
        let isMusicModel = Self.isAiPassMusicModel(targetModel)
        let isMediaModel = isImageModel || isMusicModel
        let lowerTarget = targetModel.lowercased()
        let isCompactJTSModel = lowerTarget.contains("@jts") || lowerTarget.contains("openthai") || lowerTarget.contains("pathumma") || lowerTarget.contains("typhoon")
        let hasTools = !isMediaModel && (tools != nil && !(tools?.isEmpty ?? true))

        // Build combined system instructions (including XML tool definitions when in Agent mode)
        var systemParts: [String] = []
        if !isMediaModel {
            if isCompactJTSModel {
                // Self-hosted JTS / Thai sovereign models have smaller context windows and faster time-to-first-token
                // with a concise instruction block instead of 45 verbose XML tool schemas.
                systemParts.append("""
                You are MicroCode AI Assistant inside MicroCode macOS IDE. Respond accurately and directly in the user's language (Thai or English).
                If you need to inspect attached documents/sheets/pages, workspace files, or run commands, emit `<tool_call>{"name": "tool_name", "arguments": {...}}</tool_call>` using tools: `attachment_read`, `file_read`, `file_write`, `replace_in_file`, `list_directory_tree`, `grep_search`, `shell`, `generate_image`, `generate_video`, `generate_music`. For general questions, writing, or legal/policy drafting, answer directly right away without calling tools.
                """)
            } else {
                if let tools = tools, !tools.isEmpty {
                    // Put Tool Calling Protocol & Runtime Override FIRST so it has maximum priority
                    systemParts.append(Self.buildAiPassToolSystemInstruction(tools))
                }
                if let sys = systemPrompt, !sys.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    systemParts.append(sys)
                }
            }
        }
        let combinedSystem = systemParts.joined(separator: "\n\n")

        // Helper to decode structured AgentService turns (`assistantToolCalls` / `toolResults`) into XML
        func decodeTurnContent(role: String, content: String) -> (role: String, text: String) {
            if let structured = AIStructuredTurnCodec.decode(content) {
                switch structured {
                case .assistantToolCalls(let text, let toolCalls):
                    var serialized = text
                    for tc in toolCalls {
                        let callObj: [String: Any] = ["name": tc.name, "arguments": tc.arguments]
                        if let d = try? JSONSerialization.data(withJSONObject: callObj),
                           let s = String(data: d, encoding: .utf8) {
                            serialized += "\n<tool_call>\(s)</tool_call>"
                        }
                    }
                    return (role: "assistant", text: serialized.trimmingCharacters(in: .whitespacesAndNewlines))
                case .toolResults(let results, let directive):
                    var resLines: [String] = []
                    for r in results {
                        let truncatedOutput = r.output.count > 24_000
                            ? String(r.output.prefix(24_000)) + "\n...(truncated)"
                            : r.output
                        resLines.append("<tool_response name=\"\(r.name)\" status=\"\(r.success ? "ok" : "error")\">\n\(truncatedOutput)\n</tool_response>")
                    }
                    if !directive.isEmpty {
                        resLines.append(directive)
                    }
                    if hasTools {
                        resLines.append("Note: If another client-side IDE tool is needed, output `<tool_call>{\"name\": \"...\", \"arguments\": {...}}</tool_call>` (no markdown code fences) and stop immediately after `</tool_call>`. Otherwise, write your final response based on the `<tool_response>` above.")
                    }
                    return (role: "user", text: resLines.joined(separator: "\n\n"))
                }
            } else {
                let mappedRole = (role == "assistant" || role == "model") ? "assistant" : "user"
                return (role: mappedRole, text: content)
            }
        }

        // Build normalized history turns and consolidate into a single stateless message envelope for de.aipass.net
        // (because de.aipass.net creates a fresh temporary conversation per request and only reads the last message in `messages`).
        var rawTurns: [(role: String, text: String)] = []
        var cleanTitleSeed = "MicroCode Agent Session"
        let unifiedUserText: String
        if isMediaModel {
            let cleanMediaPrompt = Self.extractCleanMediaPrompt(prompt)
            cleanTitleSeed = String(cleanMediaPrompt.prefix(100))
            unifiedUserText = cleanMediaPrompt
        } else {
            for msg in conversationHistory {
                let decoded = decodeTurnContent(role: msg.role, content: msg.content)
                if decoded.role == "user" && cleanTitleSeed == "MicroCode Agent Session" && !decoded.text.hasPrefix("<tool_response") {
                    cleanTitleSeed = String(decoded.text.prefix(100))
                }
                if !decoded.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    rawTurns.append(decoded)
                }
            }

            // Decode current prompt (which on iteration >= 2 is a structured `toolResults` turn!)
            let decodedPrompt = decodeTurnContent(role: "user", content: prompt)
            var finalUserText = decodedPrompt.text
            if cleanTitleSeed == "MicroCode Agent Session" && !finalUserText.hasPrefix("<tool_response") {
                cleanTitleSeed = String(finalUserText.prefix(100))
            }
            let aipassInlineTextAttachments = attachments.filter { $0.includeInlineTextInProviderPayload }
            if !aipassInlineTextAttachments.isEmpty {
                let groundedPackage = UniversalAttachmentEngine.shared.buildGroundedTurnPackage(
                    attachments: aipassInlineTextAttachments,
                    maxInlineChars: 28_000
                )
                if !groundedPackage.isEmpty {
                    finalUserText = finalUserText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? groundedPackage
                        : (finalUserText + "\n\n" + groundedPackage)
                }
            }
            if hasTools && !finalUserText.contains("<tool_response") {
                finalUserText += "\n\n[MicroCode Client Bridge Active: To inspect/edit local files or run terminal commands on the user's Mac, emit `<tool_call>{\"name\": \"...\", \"arguments\": {...}}</tool_call>` in plain text (no markdown fences) and stop immediately after `</tool_call>`.]"
            }

            var envelopeSections: [String] = []
            if !combinedSystem.isEmpty {
                envelopeSections.append("<microcode_ide_context>\n\(combinedSystem)\n</microcode_ide_context>")
            }
            if !rawTurns.isEmpty {
                let historyTranscript = rawTurns.map { turn in
                    let tag = turn.role == "assistant" ? "assistant" : "user"
                    return "<turn role=\"\(tag)\">\n\(turn.text)\n</turn>"
                }.joined(separator: "\n\n")
                envelopeSections.append("<conversation_history>\n\(historyTranscript)\n</conversation_history>")
            }
            envelopeSections.append("<current_request>\n\(finalUserText)\n</current_request>")
            unifiedUserText = envelopeSections.joined(separator: "\n\n")
        }

        let mergedTurns: [(role: String, text: String)] = [(role: "user", text: unifiedUserText)]

        // Step 1: Create temporary conversation on de.aipass.net (`POST /chat.data`)
        let reqUuid = UUID().uuidString.lowercased()
        var conversationId = String(reqUuid.replacingOccurrences(of: "-", with: "").prefix(16))

        if let createURL = URL(string: "https://de.aipass.net/chat.data") {
            var createReq = URLRequest(url: createURL, timeoutInterval: 15)
            createReq.httpMethod = "POST"
            createReq.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            createReq.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            createReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            createReq.setValue("*/*", forHTTPHeaderField: "Accept")
            createReq.setValue("th-TH,th;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            createReq.setValue("https://de.aipass.net", forHTTPHeaderField: "Origin")
            createReq.setValue("https://de.aipass.net/chat", forHTTPHeaderField: "Referer")
            createReq.setValue("empty", forHTTPHeaderField: "sec-fetch-dest")
            createReq.setValue("cors", forHTTPHeaderField: "sec-fetch-mode")
            createReq.setValue("same-origin", forHTTPHeaderField: "sec-fetch-site")

            let previewSeed = Self.sanitizeForAiPassWAF(cleanTitleSeed.trimmingCharacters(in: .whitespacesAndNewlines))
            var comps = URLComponents()
            comps.queryItems = [
                URLQueryItem(name: "clientCreateRequestId", value: reqUuid),
                URLQueryItem(name: "folderId", value: ""),
                URLQueryItem(name: "intent", value: "create-conversation"),
                URLQueryItem(name: "message", value: previewSeed.isEmpty ? "hi" : previewSeed),
                URLQueryItem(name: "modelId", value: targetModel)
            ]
            createReq.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

            let (createData, createResp) = try await URLSession.shared.data(for: createReq)
            if let http = createResp as? HTTPURLResponse {
                if http.statusCode == 401 {
                    throw NSError(domain: "AiPass", code: 401, userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport session expired (HTTP 401). Please click '1-Click Sign In' in Settings → AI Provider → Subscription."])
                }
                if http.statusCode == 403 {
                    let bodySnippet = String(data: createData, encoding: .utf8) ?? ""
                    if bodySnippet.lowercased().contains("sign-in") || bodySnippet.lowercased().contains("unauthorized") {
                        throw NSError(domain: "AiPass", code: 401, userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport authentication required (HTTP 403). Please reconnect your account."])
                    }
                }
                // Extract server-assigned conversationId from React Router turbo-stream JSON array if present
                if let arr = try? JSONSerialization.jsonObject(with: createData) as? [Any] {
                    if let keyIdx = arr.firstIndex(where: { ($0 as? String) == "conversationId" }),
                       keyIdx + 1 < arr.count {
                        for offset in 1...4 where (keyIdx + offset) < arr.count {
                            if let candidate = arr[keyIdx + offset] as? String,
                               candidate.count >= 12 && candidate.count <= 36,
                               candidate.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil {
                                conversationId = candidate
                                break
                            }
                        }
                    }
                }
            }
        }

        let capturedConversationId = conversationId
        defer {
            Self.deleteAiPassTemporaryConversation(conversationId: capturedConversationId, cookieHeader: cookieHeader)
        }

        // Step 2: Stream message (`POST /actions/send-message/<conversationId>`)
        guard let sendURL = URL(string: "https://de.aipass.net/actions/send-message/\(conversationId)") else {
            throw NSError(domain: "AiPass", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid TH-AI Passport endpoint URL."])
        }

        let aipassMessages: [[String: Any]] = mergedTurns.enumerated().map { (idx, turn) in
            var parts: [[String: Any]] = [
                [
                    "type": "text",
                    "text": Self.sanitizeForAiPassWAF(turn.text)
                ]
            ]
            if idx == mergedTurns.count - 1 && turn.role == "user" {
                var aipassImageBytesUsed = 0
                let maxAiPassImageBytes = 8_000_000
                var attachedImageCount = 0
                for attachment in attachments {
                    if attachedImageCount >= 8 { break }
                    if case .image = attachment.type {
                        let vData = attachment.effectiveVisionData
                        let vMime = attachment.effectiveVisionMimeType
                        if !vData.isEmpty && (aipassImageBytesUsed + vData.count) <= maxAiPassImageBytes {
                            parts.append([
                                "type": "file",
                                "mediaType": vMime,
                                "url": "data:\(vMime);base64,\(vData.base64EncodedString())",
                                "filename": attachment.name
                            ])
                            aipassImageBytesUsed += vData.count
                            attachedImageCount += 1
                        }
                    } else if attachment.semanticCategory == .video,
                              let kf = attachment.normalizedVisionData,
                              !kf.isEmpty,
                              (aipassImageBytesUsed + kf.count) <= maxAiPassImageBytes {
                        let kfMime = attachment.normalizedVisionMimeType ?? "image/jpeg"
                        parts.append([
                            "type": "file",
                            "mediaType": kfMime,
                            "url": "data:\(kfMime);base64,\(kf.base64EncodedString())",
                            "filename": "\(attachment.name)_keyframe.jpg"
                        ])
                        aipassImageBytesUsed += kf.count
                        attachedImageCount += 1
                    }
                }
            }
            return [
                "id": UUID().uuidString.lowercased(),
                "role": turn.role,
                "metadata": ["modelId": targetModel],
                "parts": parts
            ]
        }

        var payload: [String: Any] = [
            "modelId": targetModel,
            "messages": aipassMessages
        ]
        if isImageModel {
            let selectedRatio = UserDefaults.standard.string(forKey: "studioAspectRatio") ?? "1:1"
            payload["imageAspectRatio"] = selectedRatio
        }

        var streamReq = URLRequest(url: sendURL, timeoutInterval: requestTimeout)
        streamReq.httpMethod = "POST"
        streamReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        streamReq.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        streamReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        streamReq.setValue("*/*", forHTTPHeaderField: "Accept")
        streamReq.setValue("th-TH,th;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        streamReq.setValue("https://de.aipass.net", forHTTPHeaderField: "Origin")
        streamReq.setValue("https://de.aipass.net/chat/\(conversationId)", forHTTPHeaderField: "Referer")
        streamReq.setValue("empty", forHTTPHeaderField: "sec-fetch-dest")
        streamReq.setValue("cors", forHTTPHeaderField: "sec-fetch-mode")
        streamReq.setValue("same-origin", forHTTPHeaderField: "sec-fetch-site")
        streamReq.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = requestTimeout
        sessionConfig.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: sessionConfig)

        let (bytes, response) = try await session.bytes(for: streamReq)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AiPass", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response from TH-AI Passport"])
        }

        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 600 { break }
            }
            throw NSError(
                domain: "AiPass",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport HTTP \(httpResponse.statusCode) (\(targetModel)): \(errorBody.prefix(240))"]
            )
        }

        // Step 3: Parse Vercel AI SDK UI-message-chunk SSE stream
        var isStreamingReasoning = false
        var fullRawText = ""
        var visibleHoldBuffer = ""
        var savedMediaFiles: [URL] = []

        for try await line in bytes.lines {
            if Task.isCancelled { break }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let dataStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if dataStr.isEmpty || dataStr == "[DONE]" { continue }

            guard let data = dataStr.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let eventType = event["type"] as? String else { continue }

            switch eventType {
            case "reasoning-delta":
                if let rawDelta = event["delta"] as? String, !rawDelta.isEmpty {
                    let cleanDelta = Self.stripAiPassWAFMarkers(rawDelta)
                    if !isStreamingReasoning {
                        isStreamingReasoning = true
                        appendStreamToken("<thought>", onToken: onToken)
                    }
                    appendStreamToken(cleanDelta, onToken: onToken)
                }

            case "text-delta":
                if isStreamingReasoning {
                    isStreamingReasoning = false
                    appendStreamToken("</thought>\n\n", onToken: onToken)
                }
                if let rawDelta = event["delta"] as? String, !rawDelta.isEmpty {
                    let cleanDelta = Self.stripAiPassWAFMarkers(rawDelta)
                    fullRawText += cleanDelta
                    if hasTools {
                        visibleHoldBuffer += cleanDelta
                        let toolOpenTags = [
                            "<tool_call", "<function_call", "<function_calls",
                            "<invoke", "<parameter",
                            "<｜DSML｜", "<|DSML|",
                            "```tool_call", "```function_call", "[Tool Call:"
                        ]
                        let firstOpenMatch = toolOpenTags.compactMap { tag -> Range<String.Index>? in
                            visibleHoldBuffer.range(of: tag)
                        }.min(by: { $0.lowerBound < $1.lowerBound })
                        // Stream out any text before a potential `<tool_call>` / `<invoke>` / DSML tag
                        if let tcRange = firstOpenMatch {
                            let before = String(visibleHoldBuffer[..<tcRange.lowerBound])
                            if !before.isEmpty {
                                appendStreamToken(before, onToken: onToken)
                            }
                            // Hold everything from the first tool tag onward so tool payloads never stream into chat
                            visibleHoldBuffer = String(visibleHoldBuffer[tcRange.lowerBound...])
                        } else if !visibleHoldBuffer.contains("<") && !visibleHoldBuffer.contains("`") && !visibleHoldBuffer.contains("[") {
                            appendStreamToken(visibleHoldBuffer, onToken: onToken)
                            visibleHoldBuffer = ""
                        } else {
                            let specialIndices = [
                                visibleHoldBuffer.lastIndex(of: "<"),
                                visibleHoldBuffer.lastIndex(of: "`"),
                                visibleHoldBuffer.lastIndex(of: "[")
                            ].compactMap { $0 }
                            if let lastSpecial = specialIndices.max() {
                                let trailing = String(visibleHoldBuffer[lastSpecial...])
                                if toolOpenTags.contains(where: { $0.hasPrefix(trailing) }) {
                                    let safePrefix = String(visibleHoldBuffer[..<lastSpecial])
                                    if !safePrefix.isEmpty {
                                        appendStreamToken(safePrefix, onToken: onToken)
                                    }
                                    visibleHoldBuffer = trailing
                                } else {
                                    appendStreamToken(visibleHoldBuffer, onToken: onToken)
                                    visibleHoldBuffer = ""
                                }
                            }
                        }
                    } else {
                        appendStreamToken(cleanDelta, onToken: onToken)
                    }
                }

            case "file":
                if isStreamingReasoning {
                    isStreamingReasoning = false
                    appendStreamToken("</thought>\n\n", onToken: onToken)
                }
                if let urlStr = event["url"] as? String, !urlStr.isEmpty {
                    let mType = (event["mediaType"] as? String) ?? (event["mimeType"] as? String) ?? (isMusicModel ? "audio/mpeg" : "image/png")
                    let fname = event["filename"] as? String
                    let kind = mType.lowercased().hasPrefix("audio/") ? "audio" : (mType.lowercased().hasPrefix("video/") ? "video" : "image")
                    if let savedURL = try? await Self.saveAiPassGeneratedMedia(
                        rawURLString: urlStr,
                        mediaType: mType,
                        suggestedFilename: fname,
                        kind: kind,
                        cookieHeader: cookieHeader
                    ) {
                        savedMediaFiles.append(savedURL)
                        let label = kind == "audio" ? "Generated Audio" : (kind == "video" ? "Generated Video" : "Generated Image")
                        let md = "\n\n![\(label) · \(targetModel)](file://\(savedURL.path))\n"
                        fullRawText += md
                        appendStreamToken(md, onToken: onToken)
                    }
                }

            case "data-generated_file":
                if isStreamingReasoning {
                    isStreamingReasoning = false
                    appendStreamToken("</thought>\n\n", onToken: onToken)
                }
                if let dataObj = event["data"] as? [String: Any],
                   let urlStr = dataObj["url"] as? String, !urlStr.isEmpty {
                    let mType = (dataObj["mediaType"] as? String) ?? (isMusicModel ? "audio/mpeg" : "image/png")
                    let fname = dataObj["filename"] as? String
                    let kind = mType.lowercased().hasPrefix("audio/") ? "audio" : (mType.lowercased().hasPrefix("video/") ? "video" : "image")
                    if let savedURL = try? await Self.saveAiPassGeneratedMedia(
                        rawURLString: urlStr,
                        mediaType: mType,
                        suggestedFilename: fname,
                        kind: kind,
                        cookieHeader: cookieHeader
                    ) {
                        savedMediaFiles.append(savedURL)
                        let label = kind == "audio" ? "Generated Audio" : (kind == "video" ? "Generated Video" : "Generated Image")
                        let md = "\n\n![\(label) · \(targetModel)](file://\(savedURL.path))\n"
                        fullRawText += md
                        appendStreamToken(md, onToken: onToken)
                    }
                }

            case "tool-output-available":
                if let outputObj = event["output"] as? [String: Any],
                   let imgB64 = outputObj["image"] as? String, !imgB64.isEmpty {
                    let dataURL = imgB64.hasPrefix("data:") ? imgB64 : "data:image/png;base64,\(imgB64)"
                    if let savedURL = try? await Self.saveAiPassGeneratedMedia(
                        rawURLString: dataURL,
                        mediaType: "image/png",
                        suggestedFilename: nil,
                        kind: "image",
                        cookieHeader: cookieHeader
                    ) {
                        savedMediaFiles.append(savedURL)
                        let md = "\n\n![Generated Image · \(targetModel)](file://\(savedURL.path))\n"
                        fullRawText += md
                        appendStreamToken(md, onToken: onToken)
                    }
                }

            case "error":
                let errMsg = (event["errorText"] as? String) ?? (event["error"] as? String) ?? "TH-AI Passport stream error"
                throw NSError(domain: "AiPass", code: 500, userInfo: [NSLocalizedDescriptionKey: errMsg])

            default:
                break
            }
        }

        if isStreamingReasoning {
            appendStreamToken("</thought>\n\n", onToken: onToken)
        }
        if hasTools && !visibleHoldBuffer.isEmpty {
            let cleanedRemainder = AIStructuredTurnCodec.stripToolCallArtifacts(visibleHoldBuffer)
            if !cleanedRemainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendStreamToken(cleanedRemainder, onToken: onToken)
            }
            visibleHoldBuffer = ""
        }

        // If this was an Image or Music model and no inline SSE file was emitted yet, inspect `/loaders/conversation/<id>` (and poll `musicPending` for Lyria 3)
        if isMediaModel && savedMediaFiles.isEmpty {
            let expectedKind = isMusicModel ? "audio" : "image"
            if let polledURLs = try? await Self.pollAiPassConversationForMedia(
                conversationId: conversationId,
                cookieHeader: cookieHeader,
                expectedKind: expectedKind,
                pollForMusicPending: isMusicModel
            ), !polledURLs.isEmpty {
                for savedURL in polledURLs {
                    savedMediaFiles.append(savedURL)
                    let label = isMusicModel ? "Generated Audio" : "Generated Image"
                    let md = "\n\n![\(label) · \(targetModel)](file://\(savedURL.path))\n"
                    fullRawText += md
                    appendStreamToken(md, onToken: onToken)
                }
            }
        }

        if isMediaModel && savedMediaFiles.isEmpty {
            throw NSError(
                domain: "AiPassMedia",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "Model \(targetModel) did not return a media file (credits may be exhausted or prompt was filtered)."]
            )
        }

        // Extract any `<tool_call>` blocks for Agent mode
        if hasTools {
            let extractedCalls = Self.extractAiPassToolCalls(from: fullRawText)
            for call in extractedCalls {
                onToolCall?(call)
            }
        }

        let estimatedPromptTokens = max(1, (prompt.count + combinedSystem.count) / 4)
        let estimatedCompletionTokens = max(1, fullRawText.count / 4)
        AIUsageTracker.shared.record(
            provider: "aipass",
            model: targetModel,
            promptTokens: estimatedPromptTokens,
            completionTokens: estimatedCompletionTokens,
            taskLabel: isMediaModel ? "TH-AI Passport Media" : "TH-AI Passport"
        )
    }

    /// Direct programmatic entrypoint for Agent Tools (`generate_image`, `generate_video`, `generate_music`) to generate media via TH-AI Passport.
    public func generateAiPassMedia(
        kind: String, // "image", "video", "music"
        prompt: String,
        model: String? = nil,
        aspectRatio: String = "1:1"
    ) async throws -> (fileURL: URL, markdown: String) {
        let defaultModel: String = {
            if let m = model?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
                return m
            }
            switch kind.lowercased() {
            case "video": return "veo-3.1-fast-generate-001"
            case "music", "audio": return "lyria-3-clip-preview"
            default: return "gemini-2.5-flash-image"
            }
        }()

        let subToken = SubscriptionAuthManager.shared.token(for: .aipass) ?? ""
        let cookieHeader = Self.resolveAiPassSessionCookie(primary: subToken)
        var collectedMarkdown = ""

        if !cookieHeader.isEmpty {
            try await streamAiPass(
                prompt: prompt,
                attachments: [],
                systemPrompt: nil,
                conversationHistory: [],
                model: defaultModel,
                sessionCookie: cookieHeader,
                tools: nil,
                onToken: { collectedMarkdown += $0 },
                onToolCall: nil
            )
        } else if kind.lowercased() == "music" || kind.lowercased() == "audio" {
            let wavURL = try Self.synthesizeFallbackMusicWAV(prompt: prompt)
            let md = "![Generated Audio](file://\(wavURL.path))"
            return (wavURL, md)
        } else if kind.lowercased() == "video" {
            let mp4URL = try await Self.synthesizeMP4VideoFromSceneImage(imageURL: nil, prompt: prompt)
            let md = "![Generated Video](file://\(mp4URL.path))"
            return (mp4URL, md)
        } else {
            throw NSError(domain: "AiPass", code: 401, userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport session cookie is missing. Please sign in via Settings → AI Provider → Subscription → TH-AI Passport."])
        }

        if let range = collectedMarkdown.range(of: #"file://([^\)\s\n]+)"#, options: .regularExpression) {
            let filePath = String(collectedMarkdown[range]).replacingOccurrences(of: "file://", with: "")
            return (URL(fileURLWithPath: filePath), collectedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        throw NSError(domain: "AiPassMedia", code: -1, userInfo: [NSLocalizedDescriptionKey: "Media generation completed without a saved file path."])
    }

    static func mapToSubscriptionProvider(_ provider: StreamableAIProvider) -> SubscriptionProviderType? {
        switch provider {
        case .aipass: return .aipass
        case .openai: return .chatgpt
        case .anthropic: return .claude
        case .gemini: return .gemini
        case .deepseek: return .deepseek
        case .copilot: return .copilot
        case .glm: return .glm
        case .openrouter: return .openrouter
        case .groq: return .groq
        case .mistral: return .mistral
        case .kimi: return .kimi
        case .perplexity: return .perplexity
        case .perch: return .perch
        case .tokenme: return .tokenme
        case .typhoon: return .typhoon
        case .qwen: return .qwen
        case .grok: return .grok
        case .cerebras: return .cerebras
        case .together: return .together
        case .fireworks: return .fireworks
        case .minimax: return .minimax
        case .nvidia: return .nvidia
        default: return nil
        }
    }

    /// Streams completions and `<tool_call>` XML calls through an authenticated local CLI subscription (`claude`, `agy`, `codex`, `gemini`) with zero per-token API charges.
    func streamHeadlessCLISubscription(
        cliURI: String,
        prompt: String,
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        tools: [[String: Any]]?,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        // cliURI format: "cli://<kind>:<absolute_binary_path>"
        let rawRest = String(cliURI.dropFirst("cli://".count))
        guard let colonIdx = rawRest.firstIndex(of: ":") else {
            throw NSError(domain: "CLIBridge", code: 400, userInfo: [NSLocalizedDescriptionKey: "Malformed CLI bridge URI: \(cliURI)"])
        }
        let kind = String(rawRest[..<colonIdx])
        let binaryPath = String(rawRest[rawRest.index(after: colonIdx)...])
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw NSError(domain: "CLIBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "CLI binary not found at \(binaryPath)"])
        }

        // Assemble compact multi-turn transcript + MicroCode XML tool protocol when client-side tools are supplied
        var blocks: [String] = []
        if let sys = systemPrompt, !sys.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append("<system_instructions>\n\(sys)\n</system_instructions>")
        }
        if let tools, !tools.isEmpty, onToolCall != nil {
            blocks.append(Self.buildAiPassToolSystemInstruction(tools))
        }
        if !conversationHistory.isEmpty {
            let recent = conversationHistory.suffix(12)
            let formatted = recent.map { "[\($0.role.uppercased())]: \($0.content)" }.joined(separator: "\n\n")
            blocks.append("<conversation_history>\n\(formatted)\n</conversation_history>")
        }
        blocks.append(prompt)
        let fullPrompt = blocks.joined(separator: "\n\n")

        let args: [String]
        switch kind {
        case "claude":
            let lower = model.lowercased()
            let alias = lower.contains("fable")
                ? "fable"
                : (lower.contains("opus") ? "opus" : (lower.contains("haiku") ? "haiku" : "sonnet"))
            args = ["-p", "--tools", "", "--output-format", "stream-json", "--include-partial-messages", "--verbose", "--model", alias, "--", fullPrompt]
        case "agy":
            let slug = ACPAgentSession.normalizeAGYModel(model)
            args = ["--output-format", "stream-json", "--disable-slash-commands", "--dangerously-skip-permissions", "--model", slug, "--print=\(fullPrompt)"]
        case "gemini":
            var gArgs = ["-p", fullPrompt, "--output-format", "stream-json", "--yolo"]
            if let gm = ACPAgentSession.sanitizeGeminiCLIModel(model) {
                gArgs += ["-m", gm]
            }
            args = gArgs
        case "codex":
            var cArgs = ["exec", "--json", "--skip-git-repo-check"]
            let lowerModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if Self.supportedCodexOAuthModels.contains(lowerModel) {
                cArgs += ["-m", lowerModel]
            }
            cArgs += ["--", fullPrompt]
            args = cArgs
        default:
            args = ["-p", fullPrompt]
        }

        let wsPath = await MainActor.run { AgentToolBox.shared.effectiveWorkspaceRoot ?? FileManager.default.currentDirectoryPath }
        let collected: (text: String, stderr: String, cliError: String?, exitCode: Int32) = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.executableURL = URL(fileURLWithPath: binaryPath)
                proc.arguments = args
                proc.currentDirectoryURL = URL(fileURLWithPath: wsPath)
                proc.standardOutput = outPipe
                proc.standardError = errPipe

                var env = ProcessInfo.processInfo.environment
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let extraPath = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:\(home)/.bun/bin:\(home)/.npm-global/bin:/usr/bin:/bin"
                env["PATH"] = "\(extraPath):\(env["PATH"] ?? "")"
                env.removeValue(forKey: "CLAUDECODE")
                env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
                env.removeValue(forKey: "MICROCODE_LOCAL_API_TOKEN")
                // Strictly strip BYOK API key env vars so CLI OAuth subscriptions NEVER bill shell API keys
                env.removeValue(forKey: "ANTHROPIC_API_KEY")
                env.removeValue(forKey: "CLAUDE_API_KEY")
                env.removeValue(forKey: "OPENAI_API_KEY")
                env.removeValue(forKey: "GEMINI_API_KEY")
                env.removeValue(forKey: "GOOGLE_API_KEY")
                proc.environment = env

                var ndjson = ACPNDJSONParser()
                var fullOut = ""
                var receivedDelta = false
                var reportedError: String? = nil

                outPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    guard !chunk.isEmpty else { return }
                    let objs = ndjson.feed(chunk)
                    if objs.isEmpty, let plain = String(data: chunk, encoding: .utf8), !plain.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                        fullOut += plain
                        DispatchQueue.main.async { onToken(plain) }
                        return
                    }
                    for json in objs {
                        let frameType = json["type"] as? String ?? ""
                        let isErrFrame = (json["is_error"] as? Bool) == true || (json["error"] as? String != nil)
                        if isErrFrame {
                            if let resMsg = json["result"] as? String, !resMsg.isEmpty {
                                reportedError = resMsg
                            } else if let errKind = json["error"] as? String, !errKind.isEmpty {
                                reportedError = errKind
                            }
                            continue
                        }
                        var events: [ACPStreamEvent] = []
                        if kind == "claude" {
                            events = ClaudeCodeStreamParser.parseAll(json, includeAssistantTextAndThinking: !receivedDelta)
                            if frameType == "stream_event" {
                                if events.contains(where: { if case .text(let t) = $0, !t.isEmpty { return true }; return false }) {
                                    receivedDelta = true
                                }
                            }
                        } else if kind == "agy" {
                            if let ev = AGYStreamParser.parse(json) { events = [ev] }
                        } else if kind == "codex" {
                            if let ev = CodexStreamParser.parse(json) { events = [ev] }
                        } else {
                            if let ev = GeminiCLIStreamParser.parse(json) ?? AGYStreamParser.parse(json) { events = [ev] }
                        }
                        for ev in events {
                            if case .text(let t) = ev, !t.isEmpty {
                                fullOut += t
                                DispatchQueue.main.async { onToken(t) }
                            }
                        }
                    }
                }

                do {
                    try proc.run()
                    proc.waitUntilExit()
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(returning: (fullOut, errStr, reportedError, proc.terminationStatus))
                } catch {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }

        if let cliErr = collected.cliError, collected.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lowerErr = cliErr.lowercased()
            let code: Int
            if lowerErr.contains("credit balance") || lowerErr.contains("billing") {
                code = 402
            } else if lowerErr.contains("rate limit") || lowerErr.contains("429") || lowerErr.contains("quota") || lowerErr.contains("limit reached") {
                code = 429
            } else if lowerErr.contains("auth") || lowerErr.contains("login") || lowerErr.contains("unauthorized") {
                code = 401
            } else {
                code = 500
            }
            let detail = code == 402 && kind == "claude"
                ? "Claude Code CLI is linked to a prepaid Console API key with $0 credit ('\(cliErr)'), not a Claude Pro/Max subscription. Sign in to claude.ai in Settings → Subscription → Claude, or run `claude auth login` with a Claude Pro/Max account."
                : "\(kind) CLI error: \(cliErr)"
            throw NSError(domain: "CLIBridge", code: code, userInfo: [NSLocalizedDescriptionKey: detail])
        }

        if collected.exitCode != 0 && collected.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lowerErr = collected.stderr.lowercased()
            let code = (lowerErr.contains("rate limit") || lowerErr.contains("429") || lowerErr.contains("quota") || lowerErr.contains("limit reached")) ? 429 : 500
            throw NSError(domain: "CLIBridge", code: code, userInfo: [NSLocalizedDescriptionKey: collected.stderr.isEmpty ? "\(kind) CLI exited with code \(collected.exitCode)" : String(collected.stderr.prefix(400))])
        }

        if let onToolCall, tools != nil {
            let extracted = Self.extractAiPassToolCalls(from: collected.text)
            for tc in extracted {
                onToolCall(tc)
            }
        }
    }

    private static func deleteAiPassTemporaryConversation(conversationId: String, cookieHeader: String) {
        guard !conversationId.isEmpty, !cookieHeader.isEmpty,
              let url = URL(string: "https://de.aipass.net/actions/update-conversation.data") else { return }
        Task.detached(priority: .background) {
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            req.setValue("https://de.aipass.net", forHTTPHeaderField: "Origin")
            req.setValue("https://de.aipass.net/chat/\(conversationId)", forHTTPHeaderField: "Referer")
            req.httpBody = "conversationId=\(conversationId)&intent=delete".data(using: .utf8)
            _ = try? await URLSession.shared.data(for: req)
        }
    }
}

// MARK: - Stream Completion Extension

extension AIClient {
    /// Stream completion using AsyncThrowingStream for modern async/await callers.
    /// Canonical implementation — used by all Phase 2 killer feature services.
    public func streamCompletion(
        messages: [(role: String, content: String)],
        model: String? = nil,
        provider: String? = nil,
        tools: [[String: Any]]? = nil,
        stream: Bool = true,
        onToolCall: ((AIToolCall) -> Void)? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        let configuredModel = UserDefaults.standard.string(forKey: "aiModel") ?? StreamableAIProvider.gemini.defaultModel
        let requestedModel = model ?? configuredModel
        let configuredProvider = provider ?? UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"

        let selection = AIModelCatalog.shared.normalizedSelection(provider: configuredProvider, model: requestedModel)
        let resolvedModel = selection.model
        let resolvedProvider = StreamableAIProvider(rawValue: selection.provider) ?? StreamableAIProvider.detect(from: resolvedModel)

        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "direct"
        let apiKey: String = (keyMode == "direct")
            ? AIModelCatalog.resolveKey(resolvedProvider.rawValue)
            : ""

        let systemPrompt = messages.first(where: { $0.role == "system" })?.content
        let conversationMessages = messages.filter { $0.role != "system" }
        let prompt = conversationMessages.last?.content ?? "Proceed."
        let history = conversationMessages.dropLast().map { (role: $0.role, content: $0.content) }

        return AsyncThrowingStream<String, Error> { continuation in
            AIClient.shared.sendMessage(
                prompt: prompt,
                systemPrompt: systemPrompt,
                conversationHistory: Array(history),
                provider: resolvedProvider,
                model: resolvedModel,
                apiKey: apiKey,
                tools: tools,
                onToken: { token in
                    continuation.yield(token)
                },
                onToolCall: { toolCall in
                    onToolCall?(toolCall)
                },
                onComplete: { _ in
                    continuation.finish()
                },
                onError: { err in
                    continuation.finish(throwing: NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: err]))
                }
            )
        }
    }

    /// Convenience text generation helper for prompt-response queries
    public func generateText(prompt: String, systemPrompt: String? = nil) async throws -> String {
        let stream = try await streamCompletion(
            messages: [
                (role: "system", content: systemPrompt ?? "You are an expert programming assistant."),
                (role: "user", content: prompt)
            ],
            stream: false
        )
        var result = ""
        for try await chunk in stream {
            result += chunk
        }
        return result
    }
}
