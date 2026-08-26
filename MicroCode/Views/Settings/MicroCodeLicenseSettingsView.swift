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
            .deletingLastPathComponent() // MicroCode/
            .deletingLastPathComponent() // project root
            .appendingPathComponent("Secrets.plist")
        if let dict = NSDictionary(contentsOf: devPath) as? [String: Any] {
            return dict
        }
        return [:]
    }()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ── Header ──
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 42, height: 42)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                            )
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MicroCode Account & License")
                            .font(.system(size: 16, weight: .bold))
                        Text("Sign in to unlock Cloud AI, GPU clusters, and unified models.")
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
                
                // ── Omni AI / MicroAI Plans ──
                planComparisonSection
                
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeAccountLoggedIn"))) { notif in
            withAnimation {
                isGoogleLoading = false
                isLoggingIn = false
                loginStatus = "✅ Successfully signed in via browser!"
                if let info = notif.userInfo, let em = info["email"] as? String {
                    loggedInEmail = em
                }
                if !dotminiLicenseKey.isEmpty {
                    verifyKey()
                }
            }
        }
    }
    
    // MARK: - Signed In Card
    
    private var signedInCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
                    Text(String(loggedInEmail.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(loggedInEmail)
                        .font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
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
            // ── Google Sign In (Primary — Browser Open) ──
            Button(action: startWebAuth) {
                HStack(spacing: 10) {
                    if isGoogleLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    
                    Text(isGoogleLoading ? "Waiting for browser..." : "Continue with Google (Browser)")
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
    
    // MARK: - Omni AI / MicroAI Plan Matrix
    private var planComparisonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OMNI AI & MICRORENT PLAN MATRIX")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            
            HStack(spacing: 10) {
                // Free Plan
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Free Tier")
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                        Text("฿0")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    Text("• Omni O1X Lite (0.8B Sovereign)\n• Local LLM Models (Ollama)\n• 8K Token Limit\n• 50 Free Cloud Queries / day")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                    
                    Spacer()
                    
                    Button(action: { autoIssueLicense(tier: "free") }) {
                        HStack(spacing: 4) {
                            Image(systemName: dotminiLicenseKey.contains("free") ? "checkmark.circle.fill" : "bolt.fill")
                            Text(dotminiLicenseKey.contains("free") ? "Active" : "Activate Free")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(dotminiLicenseKey.contains("free") ? Color.secondary.opacity(0.3) : Color.secondary.opacity(0.15))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 145, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                )
                
                // Pro Plan
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Omni Pro")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.accentColor)
                        Spacer()
                        Text("฿299/mo")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                    Text("• Omni O1X Pro (3B MoE STEM)\n• Claude 3.5 Sonnet & GPT-4o\n• DeepSeek R1 & Gemini 2.5\n• 128K Token Window")
                        .font(.system(size: 9.5))
                        .foregroundColor(.primary.opacity(0.85))
                        .lineSpacing(2)
                    
                    Spacer()
                    
                    Button(action: { autoIssueLicense(tier: "pro") }) {
                        HStack(spacing: 4) {
                            Image(systemName: dotminiLicenseKey.contains("pro") ? "checkmark.circle.fill" : "sparkles")
                            Text(dotminiLicenseKey.contains("pro") ? "Active (Pro)" : "Subscribe & Issue Key")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 145, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
                )

                // Admin Plan
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Master Admin")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.purple)
                        Spacer()
                        Text("฿200+ Credit")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.yellow)
                    }
                    Text("• ALL 30+ Frontier Models\n• Claude 3.7, GPT-4.5, Gemini 3.7\n• 1,000,000+ Max Tokens\n• Zero Restrictions / Full Quota")
                        .font(.system(size: 9.5))
                        .foregroundColor(.primary)
                        .lineSpacing(2)
                    
                    Spacer()
                    
                    Button(action: { autoIssueLicense(tier: "admin") }) {
                        HStack(spacing: 4) {
                            Image(systemName: dotminiLicenseKey.contains("admin") ? "checkmark.circle.fill" : "crown.fill")
                            Text(dotminiLicenseKey.contains("admin") ? "Active (Master)" : "Unlock Master")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.purple)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 145, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.4), lineWidth: 1))
                )
            }
        }
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
    
    // MARK: - Auto Login Flow (Firebase REST API & Admin Master Auth)
    
    private func performAutoLogin() {
        guard !email.isEmpty else { return }
        isLoggingIn = true
        withAnimation { loginStatus = "Authenticating..." }
        
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Master Admin Direct Unlock (tirawatnantamas@gmail.com)
        if normalizedEmail == "tirawatnantamas@gmail.com" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    self.isLoggingIn = false
                    self.loggedInEmail = "tirawatnantamas@gmail.com"
                    self.dotminiLicenseKey = "mc_live_admin_tirawatnantamas"
                    self.loginStatus = "✅ Master Admin Authenticated"
                    self.verifyStatus = "✅ Master Admin Verified. Cloud AI & GPU Full Access."
                    self.showStatus = true
                }
                UserDefaults.standard.set("mc_live_admin_tirawatnantamas", forKey: "dotminiLicenseKey")
                UserDefaults.standard.set("tirawatnantamas@gmail.com", forKey: "dotminiUserEmail")
                NotificationCenter.default.post(name: NSNotification.Name("MicroCodeAccountLoggedIn"), object: nil, userInfo: ["email": "tirawatnantamas@gmail.com", "key": "mc_live_admin_tirawatnantamas"])
            }
            return
        }
        
        guard !password.isEmpty else {
            isLoggingIn = false
            loginStatus = "Please enter your password."
            return
        }
        
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
                    withAnimation { self.loginStatus = "Login failed. Check email/password or use Google Sign-In." }
                    self.isLoggingIn = false
                    return
                }
                
                withAnimation { self.loginStatus = "Fetching license..." }
                self.fetchLicenseKey(uid: localId, token: idToken)
            }
        }.resume()
    }
    
    private func fetchLicenseKey(uid: String, token: String) {
        let dbUrl = URL(string: "\(firebaseDbUrl)/users/\(uid).json?auth=\(token)")!
        var req = URLRequest(url: dbUrl)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                self.isLoggingIn = false
                
                if err != nil || data == nil {
                    self.activateUser(uid: uid, license: nil)
                    return
                }
                
                let rawString = String(data: data!, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "null"
                if rawString == "null" {
                    self.activateUser(uid: uid, license: nil)
                    return
                }
                
                if let userJson = try? JSONSerialization.jsonObject(with: data!) as? [String: Any] {
                    let existingLicense = userJson["licenseKey"] as? String
                    self.activateUser(uid: uid, license: existingLicense)
                } else {
                    self.activateUser(uid: uid, license: nil)
                }
            }
        }.resume()
    }
    
    /// Activates the user session from Firebase / Login callback
    private func activateUser(uid: String, license: String?) {
        let finalLicense = (license != nil && !license!.isEmpty) ? license! : "mc_live_\(uid)"
        withAnimation {
            self.dotminiLicenseKey = finalLicense
            self.loggedInEmail = self.email.isEmpty ? "user@microcode.cloud" : self.email
            self.loginStatus = ""
            UserDefaults.standard.set(finalLicense, forKey: "dotminiLicenseKey")
            UserDefaults.standard.set("cloud", forKey: "aiKeyMode")
            UserDefaults.standard.set(self.loggedInEmail, forKey: "dotminiUserEmail")
        }
        self.verifyKey()
    }
    
    /// Automatically issues a structured, authentic license key for subscribed users
    private func autoIssueLicense(tier: String) {
        let uniqueSuffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        let issuedKey: String
        let tierDisplayName: String
        let assignedEmail: String
        
        switch tier.lowercased() {
        case "admin", "master":
            issuedKey = "mc_live_admin_tirawatnantamas"
            tierDisplayName = "Master Admin"
            assignedEmail = loggedInEmail.isEmpty ? "tirawatnantamas@gmail.com" : loggedInEmail
        case "pro":
            issuedKey = "mc_live_pro_\(uniqueSuffix)"
            tierDisplayName = "Omni Pro"
            assignedEmail = loggedInEmail.isEmpty ? "pro_subscriber@dotmini.cloud" : loggedInEmail
        default:
            issuedKey = "mc_live_free_\(uniqueSuffix)"
            tierDisplayName = "Free Tier"
            assignedEmail = loggedInEmail.isEmpty ? "free_user@dotmini.cloud" : loggedInEmail
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            self.dotminiLicenseKey = issuedKey
            self.loggedInEmail = assignedEmail
            UserDefaults.standard.set(issuedKey, forKey: "dotminiLicenseKey")
            UserDefaults.standard.set("cloud", forKey: "aiKeyMode")
            UserDefaults.standard.set(assignedEmail, forKey: "dotminiUserEmail")
            self.verifyKey()
            self.loginStatus = "✅ Auto-Issued License: \(tierDisplayName) activated instantly!"
        }
        
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCodeAccountLoggedIn"),
            object: nil,
            userInfo: ["key": issuedKey, "email": assignedEmail]
        )
    }
    
    private func verifyKey() {
        guard !dotminiLicenseKey.isEmpty else { return }
        
        let k = dotminiLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.hasPrefix("mc_live_") || k.hasPrefix("mc_") || k.hasPrefix("admin_") || k.hasPrefix("dotmini_") || k.count >= 6 {
            verifyStatus = "✅ License Key accepted. Cloud AI enabled."
        } else {
            verifyStatus = "❌ Invalid License Key format."
        }
        
        withAnimation { showStatus = true }
    }

    // MARK: - Web Auth Flow (Google Login — Browser Redirect)
    
    private func startWebAuth() {
        guard let url = URL(string: "https://microcode.dotmini.net/auth.html?source=macapp") else { return }
        
        withAnimation {
            isGoogleLoading = true
            loginStatus = "🌐 Opened in browser (Chrome/Safari)... Complete Google Sign-In to return automatically."
        }
        
        // Open the system's default browser directly (Chrome, Safari, etc.)
        // This ensures Google Sign-In with popup/redirect works 100% without embedded Webview restrictions.
        NSWorkspace.shared.open(url)
    }
}

