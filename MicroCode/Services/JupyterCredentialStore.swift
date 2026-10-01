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
    private static let cacheKey = "microcode_jupyter_token_v1"
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.dotmini.microcode.integrations",
        kSecAttrAccount as String: "jupyter.runtime-token.v1"
    ]
    static var token: String {
        get {
            if let cached = UserDefaults.standard.string(forKey: cacheKey), !cached.isEmpty {
                return cached
            }
            var lookup = query
            lookup[kSecReturnData as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            if SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
                let val = String(decoding: data, as: UTF8.self)
                UserDefaults.standard.set(val, forKey: cacheKey)
                return val
            }
            if let legacy = UserDefaults.standard.string(forKey: "hpcToken"), !legacy.isEmpty, save(legacy) {
                UserDefaults.standard.removeObject(forKey: "hpcToken")
                return legacy
            }
            return ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: cacheKey)
            if save(newValue) { UserDefaults.standard.removeObject(forKey: "hpcToken") }
        }
    }
    @discardableResult private static func save(_ value: String) -> Bool {
        if value.isEmpty {
            UserDefaults.standard.removeObject(forKey: cacheKey)
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        UserDefaults.standard.set(value, forKey: cacheKey)
        let update = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var insert = query
        insert[kSecValueData as String] = Data(value.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        var access: SecAccess?
        SecAccessCreate("MicroCode" as CFString, nil, &access)
        if let access = access {
            insert[kSecAttrAccess as String] = access
        }
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }
}
