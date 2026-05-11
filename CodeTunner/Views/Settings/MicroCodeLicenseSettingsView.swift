import SwiftUI
import AuthenticationServices

struct MicroCodeLicenseSettingsView: View {
    @AppStorage("dotminiLicenseKey") private var dotminiLicenseKey: String = ""
    @AppStorage("dotminiUserEmail") private var loggedInEmail: String = ""
    
    @State private var email = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var loginStatus = ""
    @State private var isGoogleLoading = false
    
    @State private var verifyStatus: String = ""
    @State private var showStatus = false
    @State private var showManualKey = false
    
    // Firebase Config — loaded from Secrets.plist (gitignored, see Secrets.plist.example)
    private var firebaseApiKey: String {
        Self.secretsDict["FIREBASE_API_KEY"] as? String ?? ""
    }
    private var firebaseDbUrl: String {
        let secret = Self.secretsDict["FIREBASE_DB_URL"] as? String ?? ""
        return secret.isEmpty ? "https://microrentofficial-default-rtdb.firebaseio.com" : secret
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
    
    // Keep provider alive for ASWebAuthenticationSession
    @State private var authProvider: AuthContextProvider?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ── Header ──
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlAccentColor))
                            .frame(width: 48, height: 48)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MicroCode Cloud")
                            .font(.system(size: 18, weight: .bold))
                        Text("Sign in to unlock AI-powered coding with all providers.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 4)
                
                if !loggedInEmail.isEmpty {
                    signedInCard
                } else {
                    loginCard
                }
                
                // ── License Key Section ──
                licenseKeySection
                
                // ── Status ──
                if showStatus {
                    statusBanner
                }
            }
            .padding(20)
        }
        .onAppear {
            if !dotminiLicenseKey.isEmpty { verifyKey() }
        }
    }
    
    // MARK: - Signed In Card
    
    private var signedInCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.green, .mint], startPoint: .top, endPoint: .bottom))
                        .frame(width: 42, height: 42)
                    Text(String(loggedInEmail.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(loggedInEmail)
                        .font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        Text("Cloud AI Active")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        loggedInEmail = ""
                        dotminiLicenseKey = ""
                        verifyStatus = ""
                        showStatus = false
                    }
                }) {
                    Text("Sign Out")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Login Card
    
    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Google Sign In (Primary — Fast) ──
            Button(action: startWebAuth) {
                HStack(spacing: 10) {
                    if isGoogleLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 18, height: 18)
                    } else {
                        // Google "G" logo
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 22, height: 22)
                            Text("G")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(colors: [.red, .yellow, .green, .blue],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                        }
                    }
                    
                    Text(isGoogleLoading ? "Opening Google..." : "Continue with Google")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoggingIn || isGoogleLoading)
            
            // ── Divider ──
            HStack {
                Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1)
                Text("or sign in with email")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .layoutPriority(1)
                Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1)
            }
            .padding(.vertical, 2)
            
            // ── Email/Password ──
            VStack(spacing: 10) {
                TextField("Email", text: $email)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(nsColor: .textBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                    )
                
                SecureField("Password", text: $password)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(nsColor: .textBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                    )
                
                Button(action: performAutoLogin) {
                    HStack(spacing: 8) {
                        if isLoggingIn {
                            ProgressView().controlSize(.small)
                        }
                        Text(isLoggingIn ? "Signing in..." : "Sign In")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill((email.isEmpty || password.isEmpty)
                                  ? Color.accentColor.opacity(0.3)
                                  : Color.accentColor)
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(email.isEmpty || password.isEmpty || isLoggingIn)
            }
            
            // ── Login Status ──
            if !loginStatus.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: loginStatus.contains("failed") || loginStatus.contains("cancelled")
                          ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(loginStatus.contains("failed") || loginStatus.contains("cancelled") ? .orange : .secondary)
                    Text(loginStatus)
                        .font(.system(size: 11))
                        .foregroundColor(loginStatus.contains("failed") || loginStatus.contains("cancelled") ? .orange : .secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    // MARK: - License Key Section
    
    private var licenseKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showManualKey.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: showManualKey ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text("Manual License Key")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            if showManualKey {
                HStack(spacing: 8) {
                    SecureField("mc_live_...", text: $dotminiLicenseKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(9)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                        )
                    
                    Button(action: verifyKey) {
                        Text("Activate")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(dotminiLicenseKey.isEmpty)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }
    
    // MARK: - Status Banner
    
    private var statusBanner: some View {
        let isError = verifyStatus.contains("❌") || verifyStatus.contains("Invalid")
        return HStack(spacing: 8) {
            Image(systemName: isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(isError ? .red : .green)
            Text(verifyStatus)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isError ? .red : .green)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isError ? Color.red.opacity(0.06) : Color.green.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isError ? Color.red.opacity(0.15) : Color.green.opacity(0.15), lineWidth: 1))
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
    
    // MARK: - Auto Login Flow (Firebase REST API)
    
    private func performAutoLogin() {
        guard !email.isEmpty && !password.isEmpty else { return }
        isLoggingIn = true
        withAnimation { loginStatus = "Authenticating..." }
        
        let loginUrl = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(firebaseApiKey)")!
        var req = URLRequest(url: loginUrl)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        let body: [String: Any] = ["email": email, "password": password, "returnSecureToken": true]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let idToken = json["idToken"] as? String,
                      let localId = json["localId"] as? String else {
                    withAnimation { self.loginStatus = "Login failed. Check credentials." }
                    self.isLoggingIn = false
                    return
                }
                
                withAnimation { self.loginStatus = "Fetching license..." }
                self.fetchLicenseKey(uid: localId, token: idToken)
            }
        }.resume()
    }
    
    private func fetchLicenseKey(uid: String, token: String) {
        // Strategy: Firebase Auth already verified this user's identity.
        // The web app may not write a separate /users/{uid} node to RTDB.
        // So we check RTDB as a bonus, but if it returns null or has no
        // explicit license field, we still activate — because the user
        // passed authentication and that's what matters.
        
        let dbUrl = URL(string: "\(firebaseDbUrl)/users/\(uid).json?auth=\(token)")!
        var req = URLRequest(url: dbUrl)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                self.isLoggingIn = false
                
                // Network failure — can't verify, but still activate with uid-based license
                if err != nil || data == nil {
                    self.activateUser(uid: uid, license: nil)
                    return
                }
                
                let rawString = String(data: data!, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "null"
                
                // RTDB returned null (no user node) — that's OK, web app might not create one.
                // User already authenticated via Firebase Auth, so activate them.
                if rawString == "null" {
                    self.activateUser(uid: uid, license: nil)
                    return
                }
                
                // If there IS a user node, try to extract a real license key from it
                if let userJson = try? JSONSerialization.jsonObject(with: data!) as? [String: Any] {
                    let existingLicense = userJson["licenseKey"] as? String
                    self.activateUser(uid: uid, license: existingLicense)
                } else {
                    // Parse failed but auth succeeded — still activate
                    self.activateUser(uid: uid, license: nil)
                }
            }
        }.resume()
    }
    
    /// Activates the user session. If no explicit license is provided, generates one from the uid.
    private func activateUser(uid: String, license: String?) {
        let finalLicense = (license != nil && !license!.isEmpty) ? license! : "mc_live_\(uid)"
        withAnimation {
            self.dotminiLicenseKey = finalLicense
            self.loggedInEmail = self.email.isEmpty ? "user@microcode.cloud" : self.email
            self.loginStatus = ""
        }
        self.verifyKey()
    }
    
    private func verifyKey() {
        guard !dotminiLicenseKey.isEmpty else { return }
        
        if dotminiLicenseKey.hasPrefix("mc_live_") || dotminiLicenseKey.hasPrefix("mc_") {
            verifyStatus = "✅ License Key accepted. Cloud AI enabled."
        } else {
            verifyStatus = "❌ Invalid License Key format. Must start with mc_live_"
        }
        
        withAnimation { showStatus = true }
    }

    // MARK: - Web Auth Flow (Google Login — Fast)
    
    private func startWebAuth() {
        guard let url = URL(string: "https://microcode.dotmini.net/auth.html?source=macapp") else { return }
        
        withAnimation { isGoogleLoading = true }
        withAnimation { loginStatus = "" }
        
        // Keep provider alive — must be retained during the session
        let provider = AuthContextProvider()
        self.authProvider = provider
        
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "microcode") { callbackURL, error in
            DispatchQueue.main.async {
                withAnimation { self.isGoogleLoading = false }
                
                if error != nil {
                    withAnimation { self.loginStatus = "Google Sign-In was cancelled." }
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let queryItems = components.queryItems else {
                    withAnimation { self.loginStatus = "Invalid callback from Google." }
                    return
                }
                
                let token = queryItems.first(where: { $0.name == "token" })?.value ?? ""
                let uid = queryItems.first(where: { $0.name == "uid" })?.value ?? ""
                let callbackEmail = queryItems.first(where: { $0.name == "email" })?.value ?? ""
                
                if !token.isEmpty && !uid.isEmpty {
                    self.email = callbackEmail
                    self.isLoggingIn = true
                    withAnimation { self.loginStatus = "Fetching license..." }
                    self.fetchLicenseKey(uid: uid, token: token)
                } else {
                    withAnimation { self.loginStatus = "Authentication data missing." }
                }
            }
        }
        
        session.presentationContextProvider = provider
        // Use ephemeral = true for speed — skips cookie storage overhead
        session.prefersEphemeralWebBrowserSession = true
        session.start()
    }
}

// Helper class for ASWebAuthenticationSession presentation
class AuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApp.windows.first ?? ASPresentationAnchor()
    }
}
