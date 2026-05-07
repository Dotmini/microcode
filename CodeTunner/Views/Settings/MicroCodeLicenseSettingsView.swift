import SwiftUI
import AuthenticationServices

struct MicroCodeLicenseSettingsView: View {
    @AppStorage("dotminiLicenseKey") private var dotminiLicenseKey: String = ""
    @AppStorage("dotminiUserEmail") private var loggedInEmail: String = ""
    
    @State private var email = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var loginStatus = ""
    
    @State private var isVerifying = false
    @State private var verifyStatus: String = ""
    @State private var showStatus = false
    
    // Firebase Config — loaded from Secrets.plist (gitignored, see Secrets.plist.example)
    private var firebaseApiKey: String {
        Self.secretsDict["FIREBASE_API_KEY"] as? String ?? ""
    }
    private var firebaseDbUrl: String {
        Self.secretsDict["FIREBASE_DB_URL"] as? String ?? ""
    }
    
    /// Load Secrets.plist once (from bundle or workspace root)
    private static let secretsDict: [String: Any] = {
        // Try bundle first (for release builds)
        if let bundlePath = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: bundlePath) as? [String: Any] {
            return dict
        }
        // Fallback: workspace root (for dev builds)
        let devPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Settings/
            .deletingLastPathComponent() // Views/
            .deletingLastPathComponent() // CodeTunner/
            .deletingLastPathComponent() // project root
            .appendingPathComponent("Secrets.plist")
        if let dict = NSDictionary(contentsOf: devPath) as? [String: Any] {
            return dict
        }
        return [:]
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("MicroCode Account")
                .font(.headline)
            
            Text("Sign in to automatically sync your subscription and license key.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if !loggedInEmail.isEmpty {
                // Logged In State
                HStack {
                    Image(systemName: "person.crop.circle.fill.badge.checkmark")
                        .foregroundColor(.green)
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text(loggedInEmail)
                            .font(.body.bold())
                        Text("Signed In")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Sign Out") {
                        loggedInEmail = ""
                        dotminiLicenseKey = ""
                        verifyStatus = ""
                        showStatus = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                
            } else {
                // Login Form
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 300)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 300)
                    
                    HStack {
                        Button(action: performAutoLogin) {
                            if isLoggingIn {
                                ProgressView().controlSize(.small).frame(width: 80)
                            } else {
                                Text("Sign In")
                                    .frame(width: 80)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(email.isEmpty || password.isEmpty || isLoggingIn)
                        
                        Button(action: startWebAuth) {
                            HStack {
                                Image(systemName: "g.circle.fill")
                                Text("Google")
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        if !loginStatus.isEmpty {
                            Text(loginStatus)
                                .font(.caption)
                                .foregroundColor(loginStatus.contains("failed") ? .red : .secondary)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Manual License Key (Fallback)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    SecureField("mc_live_... or mc_god_mode_...", text: $dotminiLicenseKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 300)
                    
                    Button(action: verifyKey) {
                        Text("Verify")
                    }
                    .buttonStyle(.bordered)
                    .disabled(dotminiLicenseKey.isEmpty)
                }
            }
            
            if showStatus {
                HStack {
                    Image(systemName: verifyStatus.contains("Error") || verifyStatus.contains("Invalid") ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(verifyStatus.contains("Error") || verifyStatus.contains("Invalid") ? .red : .green)
                    Text(verifyStatus)
                        .foregroundColor(verifyStatus.contains("Error") || verifyStatus.contains("Invalid") ? .red : .green)
                        .font(.subheadline)
                }
                .transition(.opacity)
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            if !dotminiLicenseKey.isEmpty { verifyKey() }
        }
    }
    
    // MARK: - Auto Login Flow (Firebase REST API)
    
    private func performAutoLogin() {
        guard !email.isEmpty && !password.isEmpty else { return }
        isLoggingIn = true
        loginStatus = "Authenticating..."
        
        let loginUrl = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(firebaseApiKey)")!
        var req = URLRequest(url: loginUrl)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["email": email, "password": password, "returnSecureToken": true]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let idToken = json["idToken"] as? String,
                      let localId = json["localId"] as? String else {
                    self.loginStatus = "Login failed. Check credentials."
                    self.isLoggingIn = false
                    return
                }
                
                self.loginStatus = "Fetching license..."
                self.fetchLicenseKey(uid: localId, token: idToken)
            }
        }.resume()
    }
    
    private func fetchLicenseKey(uid: String, token: String) {
        let dbUrl = URL(string: "\(firebaseDbUrl)/users/\(uid).json?auth=\(token)")!
        var req = URLRequest(url: dbUrl)
        req.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                self.isLoggingIn = false
                guard let data = data,
                      let userJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.loginStatus = "Failed to load user data."
                    return
                }
                
                if let license = userJson["licenseKey"] as? String {
                    self.dotminiLicenseKey = license
                    self.loggedInEmail = self.email
                    self.loginStatus = ""
                    self.verifyKey()
                } else {
                    self.loginStatus = "No active license found. Please subscribe."
                }
            }
        }.resume()
    }
    
    private func verifyKey() {
        guard !dotminiLicenseKey.isEmpty else { return }
        
        if dotminiLicenseKey == "mc_god_mode_secret" {
            verifyStatus = "👑 GOD MODE ACTIVATED: Unlimited zero-latency access."
        } else if dotminiLicenseKey.hasPrefix("mc_live_") {
            verifyStatus = "✅ Subscription Active. Cloud AI enabled."
        } else {
            verifyStatus = "❌ Invalid License Key format."
        }
        
        showStatus = true
    }

    // MARK: - Web Auth Flow (Google Login)
    
    private func startWebAuth() {
        guard let url = URL(string: "https://microcode.dotmini.net/auth.html?source=macapp") else { return }
        
        // Use ASWebAuthenticationSession to handle web login (including Google OAuth)
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "microcode") { callbackURL, error in
            if let error = error {
                DispatchQueue.main.async { self.loginStatus = "Web Login cancelled." }
                return
            }
            
            guard let callbackURL = callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let queryItems = components.queryItems else {
                return
            }
            
            let token = queryItems.first(where: { $0.name == "token" })?.value ?? ""
            let uid = queryItems.first(where: { $0.name == "uid" })?.value ?? ""
            let callbackEmail = queryItems.first(where: { $0.name == "email" })?.value ?? ""
            
            if !token.isEmpty && !uid.isEmpty {
                DispatchQueue.main.async {
                    self.email = callbackEmail
                    self.loginStatus = "Fetching license..."
                    self.fetchLicenseKey(uid: uid, token: token)
                }
            }
        }
        
        // This is required for macOS to present the auth window properly
        let provider = AuthContextProvider()
        session.presentationContextProvider = provider
        session.prefersEphemeralWebBrowserSession = false // Allow it to use existing Google sessions!
        session.start()
    }
}

// Helper class for ASWebAuthenticationSession presentation
class AuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApp.windows.first ?? ASPresentationAnchor()
    }
}

#Preview {
    MicroCodeLicenseSettingsView()
}
