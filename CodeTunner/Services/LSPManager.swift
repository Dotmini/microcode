//
//  LSPManager.swift
//  CodeTunner - LSP Manager
//
//  Orchestrates multiple LSP client instances for different languages.
//  Automatically starts the appropriate language server based on file type.
//
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import Foundation
import SwiftUI

/// Manages LSP clients for different languages
@MainActor
class LSPManager: ObservableObject {
    
    static let shared = LSPManager()
    
    /// Active LSP clients by server type
    @Published var activeClients: [LanguageServer: LSPClientService] = [:]
    
    /// Latest diagnostics by file URI
    @Published var fileDiagnostics: [String: [LSPDiagnostic]] = [:]
    
    /// Current root URI for workspace
    private var rootUri: String?
    
    /// Document versions for tracking changes
    private var documentVersions: [String: Int] = [:]
    
    private init() {}
    
    // MARK: - API
    
    /// Set the workspace root
    func setWorkspace(_ url: URL) {
        self.rootUri = url.absoluteString
    }
    
    /// Get or start LSP client for a language
    func clientFor(language: String) async throws -> LSPClientService? {
        guard let serverType = LanguageServer.serverFor(language: language) else {
            // No LSP server configured for this language — return nil immediately, don't hang
            return nil
        }
        
        // Return existing client if already running
        if let existing = activeClients[serverType], existing.isRunning {
            return existing
        }
        
        // FIX: Check if the server binary actually exists before trying to start
        // This prevents indefinite hangs when opening .cpp, .txt, .json etc.
        // where no language server is installed on the system
        let serverExists = serverType.searchPaths.contains { FileManager.default.isExecutableFile(atPath: $0) }
        guard serverExists else {
            // Server binary not found — don't attempt to start, return nil silently
            return nil
        }
        
        // Create and start new client
        guard let rootUri = rootUri else {
            print("⚠️ [LSPManager] No workspace set")
            return nil
        }
        
        let client = LSPClientService(serverType: serverType)
        
        do {
            try await client.start(rootUri: rootUri)
            activeClients[serverType] = client
            return client
        } catch {
            print("❌ [LSPManager] Failed to start \(serverType.rawValue): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Notify that a document was opened
    func documentOpened(uri: String, language: String, content: String) async {
        // FIX: Early exit if no server is configured or installed
        guard let serverType = LanguageServer.serverFor(language: language) else { return }
        let serverExists = serverType.searchPaths.contains { FileManager.default.isExecutableFile(atPath: $0) }
        guard serverExists else { return }
        
        documentVersions[uri] = 1
        
        guard let client = try? await clientFor(language: language) else { return }
        
        do {
            try await client.didOpen(uri: uri, languageId: language, version: 1, text: content)
        } catch {
            print("❌ [LSPManager] didOpen failed: \(error)")
        }
    }
    
    /// Notify that a document was changed
    func documentChanged(uri: String, language: String, content: String) async {
        // FIX: Skip LSP notification if no server is configured or installed for this language
        // This prevents freezes when typing in files without a matching LSP server
        guard let serverType = LanguageServer.serverFor(language: language) else { return }
        let serverExists = serverType.searchPaths.contains { FileManager.default.isExecutableFile(atPath: $0) }
        guard serverExists else { return }
        
        let version = (documentVersions[uri] ?? 0) + 1
        documentVersions[uri] = version
        
        guard let client = try? await clientFor(language: language) else { return }
        
        do {
            try await client.didChange(uri: uri, version: version, text: content)
        } catch {
            print("❌ [LSPManager] didChange failed: \(error)")
        }
    }
    
    /// Get completions at a position
    func getCompletions(uri: String, language: String, line: Int, character: Int) async -> [CompletionItem] {
        guard let client = try? await clientFor(language: language) else { return [] }
        
        do {
            return try await client.completion(uri: uri, line: line, character: character)
        } catch {
            print("❌ [LSPManager] completion failed: \(error)")
            return []
        }
    }
    
    /// Get hover info at a position
    func getHover(uri: String, language: String, line: Int, character: Int) async -> String? {
        guard let client = try? await clientFor(language: language) else { return nil }
        
        do {
            if let result = try await client.hover(uri: uri, line: line, character: character) {
                return result.contents.displayText
            }
            return nil
        } catch {
            print("❌ [LSPManager] hover failed: \(error)")
            return nil
        }
    }
    
    /// Get definition locations
    func getDefinition(uri: String, language: String, line: Int, character: Int) async -> [LSPLocation] {
        guard let client = try? await clientFor(language: language) else { return [] }
        
        do {
            return try await client.definition(uri: uri, line: line, character: character)
        } catch {
            print("❌ [LSPManager] definition failed: \(error)")
            return []
        }
    }
    
    /// Stop all LSP clients
    func stopAll() {
        for (_, client) in activeClients {
            client.stop()
        }
        activeClients.removeAll()
        documentVersions.removeAll()
    }
    
    /// Stop client for a specific language
    func stop(language: String) {
        guard let serverType = LanguageServer.serverFor(language: language) else { return }
        activeClients[serverType]?.stop()
        activeClients.removeValue(forKey: serverType)
    }
    
    // MARK: - Status
    
    /// Check if LSP is available for a language
    func isAvailable(for language: String) -> Bool {
        guard let serverType = LanguageServer.serverFor(language: language) else { return false }
        if let client = activeClients[serverType] {
            return client.isRunning
        }
        return serverType.searchPaths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }
    
    /// Get server capabilities for a language
    func capabilities(for language: String) -> ServerCapabilities? {
        guard let serverType = LanguageServer.serverFor(language: language),
              let client = activeClients[serverType] else { return nil }
        return client.serverCapabilities
    }
}

// MARK: - SwiftUI Integration

/// View modifier to enable LSP features
struct LSPEnabledModifier: ViewModifier {
    @StateObject private var lspManager = LSPManager.shared
    
    func body(content: Content) -> some View {
        content
            .environmentObject(lspManager)
    }
}

extension View {
    func lspEnabled() -> some View {
        modifier(LSPEnabledModifier())
    }
}

