//
//  KeychainManager.swift
//  MicroCode
//
//  Secure Keychain CRUD for AI Provider API Keys
//  Bridges to Rust FFI via init_llm_client() after key retrieval
//
//  Copyright © 2025 Dotmini Company Limited
//

import Foundation
import Security
import CryptoKit
import IOKit

// MARK: - Keychain Manager

@MainActor
class KeychainManager: ObservableObject {
    static let shared = KeychainManager()
    
    private let service = "com.dotmini.microcode.api-keys"
    private let integrationService = "com.dotmini.microcode.integrations"
    private static let missingSentinel = "__KEYCHAIN_MISSING__"
    private var memoryCache: [String: String] = [:]
    
    /// Hardware-bound AES-256-GCM key used to seal cached secrets on disk so plaintext is NEVER written to UserDefaults
    /// and macOS securityd NEVER pops up modal Keychain password dialogs across ad-hoc binary rebuilds.
    nonisolated static let hardwareSealKey: SymmetricKey = {
        let machineID = hardwareUUID() ?? "com.dotmini.microcode.sovereign.vault"
        let material = "microcode.vault.v2.\(machineID)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: digest)
    }()
    
    nonisolated private static func hardwareUUID() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }
        if let uuid = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String {
            return uuid
        }
        return nil
    }
    
    nonisolated static func sealSecret(_ plaintext: String) -> Data? {
        guard let data = plaintext.data(using: .utf8) else { return nil }
        return try? AES.GCM.seal(data, using: hardwareSealKey).combined
    }
    
    nonisolated static func unsealSecret(_ combined: Data) -> String? {
        guard let box = try? AES.GCM.SealedBox(combined: combined),
              let opened = try? AES.GCM.open(box, using: hardwareSealKey) else {
            return nil
        }
        return String(data: opened, encoding: .utf8)
    }
    
    private func encryptSecret(_ plaintext: String) -> Data? {
        Self.sealSecret(plaintext)
    }
    
    private func decryptSecret(_ combined: Data) -> String? {
        Self.unsealSecret(combined)
    }
    
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
    
    /// Store an API key in Hardware-Bound AES-256-GCM Sealed Store (zero macOS Keychain password prompts)
    func save(key: String, for provider: ProviderKey) -> Bool {
        guard !key.isEmpty else { return false }
        
        memoryCache["api:\(provider.rawValue)"] = key
        UserDefaults.standard.removeObject(forKey: "km_cached_\(provider.rawValue)")
        if let sealed = encryptSecret(key) {
            UserDefaults.standard.set(sealed, forKey: "km_sealed_\(provider.rawValue)")
        }
        
        initializeRustProvider(provider, key: key)
        return true
    }
    
    /// Read an API key from Hardware-Bound AES-256-GCM Sealed Store
    func read(for provider: ProviderKey) -> String? {
        let cacheKey = "api:\(provider.rawValue)"
        if let mem = memoryCache[cacheKey] {
            if mem == Self.missingSentinel { return nil }
            if !mem.isEmpty { return mem }
        }
        
        // Migrate legacy plaintext cache if present
        if let legacy = UserDefaults.standard.string(forKey: "km_cached_\(provider.rawValue)"), !legacy.isEmpty {
            UserDefaults.standard.removeObject(forKey: "km_cached_\(provider.rawValue)")
            if let sealed = encryptSecret(legacy) {
                UserDefaults.standard.set(sealed, forKey: "km_sealed_\(provider.rawValue)")
            }
            memoryCache[cacheKey] = legacy
            return legacy
        }
        
        if let sealed = UserDefaults.standard.data(forKey: "km_sealed_\(provider.rawValue)"),
           let str = decryptSecret(sealed), !str.isEmpty {
            memoryCache[cacheKey] = str
            return str
        }
        
        memoryCache[cacheKey] = Self.missingSentinel
        return nil
    }
    
    /// Update an existing API key
    func update(key: String, for provider: ProviderKey) -> Bool {
        return save(key: key, for: provider)
    }
    
    /// Delete an API key from Sealed Store
    @discardableResult
    func delete(for provider: ProviderKey) -> Bool {
        memoryCache["api:\(provider.rawValue)"] = Self.missingSentinel
        UserDefaults.standard.removeObject(forKey: "km_cached_\(provider.rawValue)")
        UserDefaults.standard.removeObject(forKey: "km_sealed_\(provider.rawValue)")
        return true
    }
    
    /// Check if a key exists for a provider
    func hasKey(for provider: ProviderKey) -> Bool {
        return read(for: provider) != nil
    }
    
    /// Get all configured providers
    func configuredProviders() -> [ProviderKey] {
        return ProviderKey.allCases.filter { hasKey(for: $0) }
    }

    // MARK: - Integration & SSH Secrets (Hardware-Bound AES-256-GCM Sealed Vault)

    @discardableResult
    func saveIntegrationSecret(_ value: String, account: String) -> Bool {
        guard !value.isEmpty else {
            return deleteIntegrationSecret(account: account)
        }
        memoryCache["sec:\(account)"] = value
        UserDefaults.standard.removeObject(forKey: "km_secret_\(account)")
        if let sealed = encryptSecret(value) {
            UserDefaults.standard.set(sealed, forKey: "km_sealed_sec_\(account)")
        }
        return true
    }

    func readIntegrationSecret(account: String) -> String? {
        let cacheKey = "sec:\(account)"
        if let mem = memoryCache[cacheKey] {
            if mem == Self.missingSentinel { return nil }
            if !mem.isEmpty { return mem }
        }
        // Automatically migrate legacy plaintext UserDefaults secret if found
        if let legacy = UserDefaults.standard.string(forKey: "km_secret_\(account)"), !legacy.isEmpty {
            UserDefaults.standard.removeObject(forKey: "km_secret_\(account)")
            _ = saveIntegrationSecret(legacy, account: account)
            return legacy
        }
        if let sealed = UserDefaults.standard.data(forKey: "km_sealed_sec_\(account)"),
           let decrypted = decryptSecret(sealed), !decrypted.isEmpty {
            memoryCache[cacheKey] = decrypted
            return decrypted
        }
        memoryCache[cacheKey] = Self.missingSentinel
        return nil
    }

    @discardableResult
    func deleteIntegrationSecret(account: String) -> Bool {
        memoryCache["sec:\(account)"] = Self.missingSentinel
        UserDefaults.standard.removeObject(forKey: "km_secret_\(account)")
        UserDefaults.standard.removeObject(forKey: "km_sealed_sec_\(account)")
        return true
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
