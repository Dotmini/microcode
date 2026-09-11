import SwiftUI

/// Account settings backed exclusively by the self-hosted Supabase instance.
/// Plans are server-side entitlements; there is intentionally no editable or
/// client-generated "license key" field in this view.
struct MicroCodeLicenseSettingsView: View {
    @ObservedObject private var auth = SupabaseAuthService.shared
    @ObservedObject private var platformKey = DotminiPlatformKeyService.shared
    @AppStorage("dotminiUserEmail") private var persistedEmail = ""

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var status = ""
    @State private var platformKeyInput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if auth.session != nil || !persistedEmail.isEmpty {
                    accountCard
                } else {
                    signInCard
                }
                entitlementCard
                platformKeyCard
                architectureNote
            }
            .padding(20)
        }
        .task {
            _ = await auth.refreshAccessTokenIfNeeded()
            await auth.refreshEntitlement()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeAccountLoggedIn"))) { _ in
            Task {
                _ = await auth.refreshAccessTokenIfNeeded(force: true)
                await auth.refreshEntitlement()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text("MicroCode Account")
                    .font(.system(size: 16, weight: .bold))
                Text("Self-hosted Supabase authentication and server-issued access.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(Text(String(accountEmail.prefix(1)).uppercased()).font(.system(size: 16, weight: .bold)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(accountEmail.isEmpty ? "Signed in" : accountEmail)
                        .font(.system(size: 13, weight: .semibold))
                    Label("Supabase session active", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("Refresh") {
                    Task {
                        isWorking = true
                        _ = await auth.refreshAccessTokenIfNeeded(force: true)
                        await auth.refreshEntitlement()
                        isWorking = false
                    }
                }
                .disabled(isWorking)
                Button("Sign Out", role: .destructive) {
                    auth.signOut()
                    AuthService.shared.signOut()
                    persistedEmail = ""
                    status = "Signed out from this Mac."
                }
            }
            if !status.isEmpty { statusText }
        }
        .cardStyle()
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in")
                .font(.system(size: 13, weight: .semibold))
            Button {
                isWorking = true
                status = "Opening secure browser sign-in…"
                Task { @MainActor in
                    do {
                        try await auth.startOAuth(provider: "google")
                    } catch {
                        status = error.localizedDescription
                        isWorking = false
                    }
                }
            } label: {
                Label("Continue with Google", systemImage: "globe")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)

            HStack {
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                Text("or email and password").font(.caption).foregroundColor(.secondary)
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
            }
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
            Button(isWorking ? "Signing in…" : "Sign In") {
                Task { await signInWithPassword() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || isWorking)
            if !status.isEmpty { statusText }
        }
        .cardStyle()
    }

    private var entitlementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cloud entitlement")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Read from your Supabase profile; the desktop app cannot mint or alter it.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(auth.entitlement.plan.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }
            Divider()
            HStack {
                metric("Free tokens remaining", "\(auth.entitlement.freeTokensRemaining)")
                Spacer()
                metric("Monthly tokens used", "\(auth.entitlement.monthlyTokensUsed)")
            }
            HStack {
                Button("Manage plan") {
                    NSWorkspace.shared.open(URL(string: "https://microcode.dotmini.net/account")!)
                }
                .buttonStyle(.bordered)
                Spacer()
                if auth.session == nil {
                    Text("Sign in to load your entitlement.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .cardStyle()
    }

    private var platformKeyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dotmini Platform key")
                        .font(.system(size: 13, weight: .semibold))
                    Text("One developer key for Omni models and MicroCode Cloud Runtime. Stored only in macOS Keychain.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Open Platform") {
                    NSWorkspace.shared.open(URL(string: "https://microai.dotmini.net/platform")!)
                }
                .buttonStyle(.bordered)
            }

            if platformKey.isConfigured {
                HStack {
                    Label(platformKey.maskedKey, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.green)
                    Spacer()
                    Button(platformKey.isValidating ? "Checking…" : "Verify") {
                        Task { _ = await platformKey.validate() }
                    }
                    .disabled(platformKey.isValidating)
                    Button("Remove", role: .destructive) { platformKey.remove() }
                }
            } else {
                HStack(spacing: 8) {
                    SecureField("sk-dotmini-live-… or mci-live-…", text: $platformKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Save key") {
                        if platformKey.save(platformKeyInput) { platformKeyInput = "" }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(platformKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if !platformKey.validationMessage.isEmpty {
                Text(platformKey.validationMessage)
                    .font(.system(size: 11))
                    .foregroundColor(platformKey.validationMessage.lowercased().contains("rejected") || platformKey.validationMessage.lowercased().contains("could not") ? .red : .secondary)
            }
        }
        .cardStyle()
    }

    private var architectureNote: some View {
        Label("Firebase is not used for account sign-in, tokens, licenses, or quota. Sessions are stored in macOS Keychain and refreshed with your self-hosted Supabase Auth service.", systemImage: "lock.shield")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.secondary.opacity(0.08)))
    }

    private var statusText: some View {
        Text(status)
            .font(.system(size: 11))
            .foregroundColor(status.lowercased().contains("failed") || status.lowercased().contains("not configured") ? .red : .secondary)
    }

    private var accountEmail: String { auth.currentEmail }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundColor(.secondary)
        }
    }

    private func signInWithPassword() async {
        isWorking = true
        status = ""
        defer { isWorking = false }
        do {
            let session = try await auth.signIn(email: email, password: password)
            persistedEmail = session.email
            AuthService.shared.syncWithWebSession(email: session.email, token: session.accessToken, displayName: session.email.components(separatedBy: "@").first ?? "User")
            status = "Signed in securely with Supabase."
        } catch {
            status = error.localizedDescription
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}
