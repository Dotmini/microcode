//
//  KeychainManager.swift
//  CodeTunner
//
//  Secure Keychain CRUD for AI Provider API Keys
//  Bridges to Rust FFI via init_llm_client() after key retrieval
//
//  Copyright © 2025 SPU AI CLUB — Dotmini Software
//

import Foundation
import Security

// MARK: - Keychain Manager

@MainActor
class KeychainManager: ObservableObject {
    static let shared = KeychainManager()
    
    private let service = "com.dotmini.microcode.api-keys"
    
    /// Known provider key identifiers
    enum ProviderKey: String, CaseIterable {
        case anthropic  = "ANTHROPIC_API_KEY"
        case gemini     = "GEMINI_API_KEY"
        case openai     = "OPENAI_API_KEY"
        case deepseek   = "DEEPSEEK_API_KEY"
        case grok       = "GROK_API_KEY"
        case codex      = "CODEX_API_KEY"
        
        var displayName: String {
            switch self {
            case .anthropic: return "Claude (Anthropic)"
            case .gemini:    return "Google Gemini"
            case .openai:    return "OpenAI / ChatGPT"
            case .deepseek:  return "DeepSeek"
            case .grok:      return "Grok (xAI)"
            case .codex:     return "Codex (OpenAI)"
            }
        }
        
        #if RUST_FFI
        /// Map to Rust FFI LlmProviderType
        var ffiProvider: LlmProviderType {
            switch self {
            case .anthropic: return .anthropic
            case .gemini:    return .gemini
            case .openai:    return .openAi
            case .deepseek:  return .deepSeek
            case .grok:      return .grok
            case .codex:     return .codex
            }
        }
        #endif
    }
    
    // MARK: - CRUD Operations
    
    /// Store an API key in Keychain
    func save(key: String, for provider: ProviderKey) -> Bool {
        guard !key.isEmpty else { return false }
        
        let data = Data(key.utf8)
        
        // Delete existing first
        delete(for: provider)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            // Bridge to Rust FFI
            initializeRustProvider(provider, key: key)
            return true
        }
        
        print("⚠️ Keychain save failed for \(provider.rawValue): \(status)")
        return false
    }
    
    /// Read an API key from Keychain
    func read(for provider: ProviderKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    /// Update an existing API key
    func update(key: String, for provider: ProviderKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        
        let update: [String: Any] = [
            kSecValueData as String: Data(key.utf8)
        ]
        
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        
        if status == errSecSuccess {
            initializeRustProvider(provider, key: key)
            return true
        }
        
        // If not found, create instead
        if status == errSecItemNotFound {
            return save(key: key, for: provider)
        }
        
        return false
    }
    
    /// Delete an API key from Keychain
    @discardableResult
    func delete(for provider: ProviderKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// Check if a key exists for a provider
    func hasKey(for provider: ProviderKey) -> Bool {
        return read(for: provider) != nil
    }
    
    /// Get all configured providers
    func configuredProviders() -> [ProviderKey] {
        return ProviderKey.allCases.filter { hasKey(for: $0) }
    }
    
    // MARK: - Rust FFI Bridge
    
    /// Call Rust init_llm_client after retrieving key from Keychain
    private func initializeRustProvider(_ provider: ProviderKey, key: String) {
        #if RUST_FFI
        do {
            let result = try initLlmClient(provider: provider.ffiProvider, token: key)
            if result.success {
                print("✅ Rust LLM client initialized: \(result.message)")
            } else {
                print("⚠️ Rust LLM init returned failure: \(result.message)")
            }
        } catch {
            print("⚠️ Rust FFI not available: \(error.localizedDescription)")
        }
        #else
        // No-op when Rust FFI is not linked (e.g. CI, previews)
        _ = (provider, key)
        #endif
    }
    
    /// Initialize all stored keys on app launch
    func initializeAllProviders() {
        for provider in ProviderKey.allCases {
            if let key = read(for: provider) {
                initializeRustProvider(provider, key: key)
            }
        }
    }
    
    /// Get models for a provider via Rust FFI
    func getModels(for provider: ProviderKey) -> [String] {
        #if RUST_FFI
        do {
            return try getProviderModels(provider: provider.ffiProvider)
        } catch {
            return []
        }
        #else
        _ = provider
        return []
        #endif
    }
}
