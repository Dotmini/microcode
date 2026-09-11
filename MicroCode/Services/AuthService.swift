//
//  AuthService.swift
//  MicroCode
//
//  Presentation-facing account state. SupabaseAuthService owns every actual
//  credential, refresh, OAuth, and signup request.
//

import Foundation

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

    enum AuthProvider: String, Codable { case google, email, apple }
}

enum AuthState {
    case signedOut
    case signedIn(IDXUser)
    case loading
    case error(String)
}

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var currentUser: IDXUser?
    @Published var authState: AuthState = .signedOut
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let userDefaultsKey = "com.dotmini.microcode.auth.session"

    private init() { loadSavedSession() }

    func signInWithGoogle() async throws {
        isLoading = true
        errorMessage = nil
        authState = .loading
        defer { isLoading = false }
        do {
            try await SupabaseAuthService.shared.startOAuth(provider: "google")
            // Completion arrives through MicroCodeApp's custom URL callback.
        } catch {
            authState = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func signUpWithEmail(email: String, password: String, displayName: String) async throws {
        guard isValidEmail(email) else { throw AuthError.invalidEmail }
        guard password.count >= 8 else { throw AuthError.weakPassword }
        isLoading = true; errorMessage = nil; authState = .loading
        defer { isLoading = false }
        do {
            if let session = try await SupabaseAuthService.shared.signUp(email: email, password: password, displayName: displayName) {
                syncWithWebSession(email: session.email, token: session.accessToken, displayName: displayName)
            } else {
                let message = "Account created. Confirm your email, then sign in."
                authState = .signedOut
                errorMessage = message
            }
        } catch {
            authState = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func signInWithEmail(email: String, password: String) async throws {
        guard isValidEmail(email) else { throw AuthError.invalidEmail }
        isLoading = true; errorMessage = nil; authState = .loading
        defer { isLoading = false }
        do {
            let session = try await SupabaseAuthService.shared.signIn(email: email, password: password)
            syncWithWebSession(email: session.email, token: session.accessToken)
        } catch {
            authState = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func signOut() {
        SupabaseAuthService.shared.signOut()
        currentUser = nil
        authState = .signedOut
        errorMessage = nil
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    /// Called after either a Supabase password sign-in or the app URL OAuth
    /// callback. The JWT is never stored in this UI cache.
    func syncWithWebSession(email: String, token: String = "", displayName: String = "") {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty else { return }
        let session = SupabaseAuthService.shared.session
        let name = displayName.isEmpty ? cleanEmail.components(separatedBy: "@").first ?? "User" : displayName
        let userID = session?.userID ?? ""
        let user = IDXUser(
            id: userID.isEmpty ? cleanEmail : userID,
            email: cleanEmail,
            displayName: name,
            photoURL: nil,
            provider: .email,
            createdAt: Date(),
            lastLoginAt: Date(),
            isPremium: ["pro", "enterprise", "admin"].contains(SupabaseAuthService.shared.entitlement.plan),
            isEarlyAccess: false
        )
        currentUser = user
        authState = .signedIn(user)
        try? saveSession(user)
        _ = token // Credentials remain owned by SupabaseAuthService/Keychain.
    }

    func saveSession(_ user: IDXUser) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(user), forKey: userDefaultsKey)
    }

    private func loadSavedSession() {
        if let session = SupabaseAuthService.shared.session, !session.email.isEmpty {
            syncWithWebSession(email: session.email, token: session.accessToken)
            return
        }
        // This is UI metadata only; it grants neither an authenticated session
        // nor cloud access after the Keychain session has been removed.
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let user = try? JSONDecoder().decode(IDXUser.self, from: data) else { return }
        currentUser = user
        authState = .signedOut
    }

    private func isValidEmail(_ email: String) -> Bool {
        let expression = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", expression).evaluate(with: email)
    }
}

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
        case .notImplemented(let message): return message
        }
    }
}
