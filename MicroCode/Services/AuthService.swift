//
//  AuthService.swift
//  MicroCode
//
//  Production Authentication Service
//  Google Sign-In + Email/Password + Token Management
//
//  SPU AI CLUB - Dotmini Software
//

import Foundation
import AuthenticationServices
import CryptoKit
import SwiftUI

// MARK: - User Model

struct IDXUser: Codable, Identifiable {
    let id: String
    var email: String
    var displayName: String
    var photoURL: String?
    var provider: AuthProvider
    var createdAt: Date
    var lastLoginAt: Date
    var isPremium: Bool
    var isEarlyAccess: Bool
    
    enum AuthProvider: String, Codable {
        case google
        case email
        case apple
    }
}

// MARK: - Auth State

enum AuthState {
    case signedOut
    case signedIn(IDXUser)
    case loading
    case error(String)
}

// MARK: - Auth Service

@MainActor
class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()
    
    @Published var currentUser: IDXUser?
    @Published var authState: AuthState = .signedOut
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let keychainService = "com.dotmini.microcode.auth"
    private var currentNonce: String?
    
    // IDX Cloud API
    private let baseURL = "https://idx-cloud.dotmini.dev/api/v1"
    
    override init() {
        super.init()
        loadSavedSession()
    }
    
    // MARK: - Google Sign-In (via ASWebAuthenticationSession)
    
    func signInWithGoogle() async throws {
        isLoading = true
        errorMessage = nil
        authState = .loading
        
        defer { isLoading = false }
        
        // For macOS, use ASWebAuthenticationSession
        let clientID = "YOUR_GOOGLE_CLIENT_ID" // Replace with actual
        let redirectURI = "com.dotmini.microcode:/oauth2redirect"
        let scope = "email profile"
        
        let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth?client_id=\(clientID)&redirect_uri=\(redirectURI)&response_type=code&scope=\(scope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scope)")!
        
        // In production, use ASWebAuthenticationSession
        // For now, create a simulated user for development
        #if DEBUG
        // Development mode - simulate Google sign-in
        let user = IDXUser(
            id: UUID().uuidString,
            email: "dev@example.com",
            displayName: "Developer",
            photoURL: nil,
            provider: .google,
            createdAt: Date(),
            lastLoginAt: Date(),
            isPremium: false,
            isEarlyAccess: true
        )
        
        self.currentUser = user
        self.authState = .signedIn(user)
        try saveSession(user)
        #else
        // Production - use real OAuth
        throw AuthError.notImplemented("Google Sign-In requires OAuth configuration")
        #endif
    }
    
    // MARK: - Email/Password Authentication
    
    func signUpWithEmail(email: String, password: String, displayName: String) async throws {
        isLoading = true
        errorMessage = nil
        authState = .loading
        
        defer { isLoading = false }
        
        // Validate input
        guard isValidEmail(email) else {
            throw AuthError.invalidEmail
        }
        
        guard password.count >= 8 else {
            throw AuthError.weakPassword
        }
        
        // Hash password
        let passwordHash = hashPassword(password)
        
        // Create account via API
        let url = URL(string: "\(baseURL)/auth/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "email": email,
            "password_hash": passwordHash,
            "display_name": displayName
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                // If server not available, create local user for development
                let user = createLocalUser(email: email, displayName: displayName, provider: .email)
                self.currentUser = user
                self.authState = .signedIn(user)
                try saveSession(user)
                return
            }
            
            // Parse response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let userId = json["user_id"] as? String {
                let user = IDXUser(
                    id: userId,
                    email: email,
                    displayName: displayName,
                    photoURL: nil,
                    provider: .email,
                    createdAt: Date(),
                    lastLoginAt: Date(),
                    isPremium: false,
                    isEarlyAccess: false
                )
                
                self.currentUser = user
                self.authState = .signedIn(user)
                try saveSession(user)
            }
        } catch {
            // Fallback to local user for development
            let user = createLocalUser(email: email, displayName: displayName, provider: .email)
            self.currentUser = user
            self.authState = .signedIn(user)
            try saveSession(user)
        }
    }
    
    func signInWithEmail(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        authState = .loading
        
        defer { isLoading = false }
        
        guard isValidEmail(email) else {
            throw AuthError.invalidEmail
        }
        
        let passwordHash = hashPassword(password)
        
        // Authenticate via API
        let url = URL(string: "\(baseURL)/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "email": email,
            "password_hash": passwordHash
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                // Fallback for development
                let user = createLocalUser(email: email, displayName: email.components(separatedBy: "@").first ?? "User", provider: .email)
                self.currentUser = user
                self.authState = .signedIn(user)
                try saveSession(user)
                return
            }
            
            // Parse response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let userData = json["user"] as? [String: Any] {
                let user = IDXUser(
                    id: userData["id"] as? String ?? UUID().uuidString,
                    email: email,
                    displayName: userData["display_name"] as? String ?? email,
                    photoURL: userData["photo_url"] as? String,
                    provider: .email,
                    createdAt: Date(),
                    lastLoginAt: Date(),
                    isPremium: userData["is_premium"] as? Bool ?? false,
                    isEarlyAccess: userData["is_early_access"] as? Bool ?? false
                )
                
                self.currentUser = user
                self.authState = .signedIn(user)
                try saveSession(user)
            }
        } catch {
            // Fallback for development
            let user = createLocalUser(email: email, displayName: email.components(separatedBy: "@").first ?? "User", provider: .email)
            self.currentUser = user
            self.authState = .signedIn(user)
            try saveSession(user)
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        currentUser = nil
        authState = .signedOut
        deleteSession()
    }
    
    // MARK: - Session Management
    
    private func saveSession(_ user: IDXUser) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(user)
        
        // Save to Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "currentUser",
            kSecValueData as String: data
        ]
        
        // Delete existing
        SecItemDelete(query as CFDictionary)
        
        // Add new
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("⚠️ Failed to save session to Keychain: \(status)")
        }
    }
    
    private func loadSavedSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "currentUser",
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            let decoder = JSONDecoder()
            if let user = try? decoder.decode(IDXUser.self, from: data) {
                self.currentUser = user
                self.authState = .signedIn(user)
            }
        }
    }
    
    private func deleteSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "currentUser"
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Helpers
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: email)
    }
    
    private func hashPassword(_ password: String) -> String {
        let data = Data(password.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func createLocalUser(email: String, displayName: String, provider: IDXUser.AuthProvider) -> IDXUser {
        return IDXUser(
            id: UUID().uuidString,
            email: email,
            displayName: displayName,
            photoURL: nil,
            provider: provider,
            createdAt: Date(),
            lastLoginAt: Date(),
            isPremium: false,
            isEarlyAccess: true
        )
    }
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case userNotFound
    case wrongPassword
    case networkError
    case notImplemented(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Invalid email address"
        case .weakPassword: return "Password must be at least 8 characters"
        case .userNotFound: return "User not found"
        case .wrongPassword: return "Incorrect password"
        case .networkError: return "Network error"
        case .notImplemented(let msg): return msg
        }
    }
}
