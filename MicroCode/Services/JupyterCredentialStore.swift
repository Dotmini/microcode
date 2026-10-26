//
//  JupyterCredentialStore.swift
//  MicroCode
//
//  Synchronous Keychain & Secure Local Store for Compute Kernels.
//  Maintains zero-prompt access across recompiled ad-hoc development binaries.
//  Tirawat Nantamas Founder and CEO of Dotmini Software.
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation
import Security

/// Synchronous Keychain access for compute kernels that are not UI actors.
enum JupyterCredentialStore {
    private static let sealedKey = "km_sealed_jupyter_token_v1"
    private static let legacyCacheKey = "microcode_jupyter_token_v1"

    static var token: String {
        get {
            if let sealed = UserDefaults.standard.data(forKey: sealedKey),
               let unsealed = KeychainManager.unsealSecret(sealed),
               !unsealed.isEmpty {
                return unsealed
            }
            if let cached = UserDefaults.standard.string(forKey: legacyCacheKey), !cached.isEmpty {
                UserDefaults.standard.removeObject(forKey: legacyCacheKey)
                _ = save(cached)
                return cached
            }
            if let legacy = UserDefaults.standard.string(forKey: "hpcToken"), !legacy.isEmpty, save(legacy) {
                UserDefaults.standard.removeObject(forKey: "hpcToken")
                return legacy
            }
            return ""
        }
        set {
            if save(newValue) {
                UserDefaults.standard.removeObject(forKey: "hpcToken")
                UserDefaults.standard.removeObject(forKey: legacyCacheKey)
            }
        }
    }

    @discardableResult private static func save(_ value: String) -> Bool {
        if value.isEmpty {
            UserDefaults.standard.removeObject(forKey: sealedKey)
            UserDefaults.standard.removeObject(forKey: legacyCacheKey)
            return true
        }
        guard let sealed = KeychainManager.sealSecret(value) else { return false }
        UserDefaults.standard.set(sealed, forKey: sealedKey)
        return true
    }
}
