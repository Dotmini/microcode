//
//  AIAutocompleteService.swift
//  CodeTunner
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
    private var debounceTimer: Timer?
    
    // Config
    private let debounceDelay: TimeInterval = 0.4
    private let maxPrefixLength = 1500
    private let maxSuffixLength = 500
    
    // Add feature flag to easily toggle AI Ghost text
    @AppStorage("enableAIGhostText") var isEnabled: Bool = true
    
    private init() {}
    
    /// Triggers an autocomplete request after a debounce delay
    func triggerAutocomplete(prefix: String, suffix: String, cursorLocation: Int, fileExtension: String) {
        guard isEnabled else { return }
        
        // Cancel previous request
        cancelRequest()
        
        // Don't autocomplete if typing extremely fast or no context
        guard !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchCompletion(prefix: prefix, suffix: suffix, cursorLocation: cursorLocation, fileExtension: fileExtension)
            }
        }
    }
    
    func cancelRequest() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        requestTask?.cancel()
        requestTask = nil
    }
    
    func clearSuggestion() {
        cancelRequest()
        currentSuggestion = nil
    }
    
    private func fetchCompletion(prefix: String, suffix: String, cursorLocation: Int, fileExtension: String) async {
        guard isEnabled else { return }
        
        // Truncate context to save tokens and latency
        let truncatedPrefix = String(prefix.suffix(maxPrefixLength))
        let truncatedSuffix = String(suffix.prefix(maxSuffixLength))
                isRequesting = true
        requestTask = Task { [weak self] in
            do {
                guard let self = self else { return }
                
                // Get active endpoint from LocalLLMService
                let endpoint = LocalLLMService.shared.activeEndpoint
                let model = LocalLLMService.shared.activeModel
                
                // Call highly optimized Rust FFI Core
                let completion = try await fetchGhostText(
                    endpoint: endpoint,
                    model: model,
                    prefix: truncatedPrefix,
                    suffix: truncatedSuffix
                )
                
                guard !Task.isCancelled else { return }
                
                // Avoid suggesting just spaces or newlines
                if completion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DispatchQueue.main.async {
                        self.isRequesting = false
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    guard !Task.isCancelled else { return }
                    self.currentSuggestion = AutocompleteSuggestion(text: completion, range: NSRange(location: cursorLocation, length: 0))
                    self.isRequesting = false
                }
                
            } catch {
                DispatchQueue.main.async {
                    self?.isRequesting = false
                }
            }
        }
    }
}
