//
//  AIAutocompleteService.swift
//  MicroCode
//
//  Hardware-Accelerated AI Autocomplete (Ghost Text Engine)
//  Connects to LocalLLMService or Cloud GPU for FIM completions.
//
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

struct AutocompleteSuggestion: Equatable {
    let text: String
    let range: NSRange
    let id = UUID()
}

@MainActor
class AIAutocompleteService: ObservableObject {
    static let shared = AIAutocompleteService()
    
    @Published var currentSuggestion: AutocompleteSuggestion?
    @Published var isRequesting = false
    
    private var requestTask: Task<Void, Never>?
    private var suggestionCache: [Int: String] = [:]
    
    // Config
    private let debounceNanoseconds: UInt64 = 350_000_000
    private let maxPrefixLength = 1500
    private let maxSuffixLength = 500
    
    // Add feature flag to easily toggle AI Ghost text
    @AppStorage("enableAIGhostText") var isEnabled: Bool = true
    
    private init() {}
    
    /// Triggers an autocomplete request after a debounce delay using structured cancellation
    func triggerAutocomplete(prefix: String, suffix: String, cursorLocation: Int, fileExtension: String) {
        guard isEnabled else { return }
        
        // Cancel previous request immediately
        cancelRequest()
        
        // Don't autocomplete if prefix is empty
        guard !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let truncatedPrefix = String(prefix.suffix(maxPrefixLength))
        let truncatedSuffix = String(suffix.prefix(maxSuffixLength))
        
        var hasher = Hasher()
        hasher.combine(truncatedPrefix)
        hasher.combine(truncatedSuffix)
        hasher.combine(fileExtension)
        let cacheKey = hasher.finalize()
        
        if let cached = suggestionCache[cacheKey], !cached.isEmpty {
            currentSuggestion = AutocompleteSuggestion(
                text: cached,
                range: NSRange(location: cursorLocation, length: 0)
            )
            return
        }
        
        requestTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.debounceNanoseconds ?? 350_000_000)
                guard let self = self, !Task.isCancelled, self.isEnabled else { return }
                
                self.isRequesting = true
                defer { self.isRequesting = false }
                
                // Get active endpoint from LocalLLMService
                let endpoint = LocalLLMService.shared.activeEndpoint
                let model = LocalLLMService.shared.activeModel
                
                // Call highly optimized Rust FFI Core
                let rawCompletion = try await fetchGhostText(
                    endpoint: endpoint,
                    model: model,
                    prefix: truncatedPrefix,
                    suffix: truncatedSuffix
                )
                
                guard !Task.isCancelled else { return }
                
                let cleaned = Self.sanitizeCompletion(
                    rawCompletion,
                    prefix: truncatedPrefix,
                    suffix: truncatedSuffix
                )
                guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return
                }
                
                if self.suggestionCache.count > 128 {
                    self.suggestionCache.removeAll(keepingCapacity: true)
                }
                self.suggestionCache[cacheKey] = cleaned
                self.currentSuggestion = AutocompleteSuggestion(
                    text: cleaned,
                    range: NSRange(location: cursorLocation, length: 0)
                )
            } catch {
                self?.isRequesting = false
            }
        }
    }
    
    func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
        if isRequesting {
            isRequesting = false
        }
    }
    
    func clearSuggestion() {
        cancelRequest()
        if currentSuggestion != nil {
            currentSuggestion = nil
        }
    }
    
    private static func sanitizeCompletion(_ raw: String, prefix: String, suffix: String) -> String {
        var result = raw
        // Strip accidental markdown code fences
        if result.hasPrefix("```") {
            if let firstNewline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: firstNewline)...])
            } else {
                result = result.replacingOccurrences(of: "```", with: "")
            }
            if result.hasSuffix("```") {
                result = String(result.dropLast(3))
            }
        }
        // Trim duplicate suffix overlap if the model repeated the start of `suffix`
        let trimmedSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSuffix.isEmpty,
           let firstSuffixLine = trimmedSuffix.split(separator: "\n", omittingEmptySubsequences: true).first,
           firstSuffixLine.count >= 4,
           result.hasSuffix(String(firstSuffixLine)) {
            result = String(result.dropLast(firstSuffixLine.count))
        }
        return result
    }
}
