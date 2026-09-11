import SwiftUI
import AuthenticationServices

/// Optional first-run onboarding. Authentication is offered as a convenience;
/// dismissing the card leaves the entire local editor available.
struct FirstLaunchWelcomeView: View {
    @EnvironmentObject private var appState: AppState

    let onComplete: () -> Void

    @State private var showingDotminiID = false
    @State private var email = ""
    @State private var password = ""
    @State private var statusMessage = ""
    @State private var isWorking = false

    var body: some View {
        ZStack {
            Color.black.opacity(appState.appTheme.isGlass ? 0.62 : 0.72)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Welcome to MicroCode")
                            .font(.system(size: 25, weight: .semibold))
                        Text("An agent-first workspace for understanding, changing, and shipping code.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        onComplete()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss Welcome Screen")
                }
                .padding(.bottom, 22)

                VStack(alignment: .leading, spacing: 10) {
                    welcomeRow("Work with the AI Agent as your primary workspace")
                    welcomeRow("Open and edit code whenever you need direct control")
                    welcomeRow("Projects and local editing work without an account")
                }
                .padding(.bottom, 24)

                Divider()
                    .padding(.bottom, 18)

                Text("SIGN IN — OPTIONAL")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)

                VStack(spacing: 9) {
                    Button(action: startGoogleSignIn) {
                        HStack(spacing: 9) {
                            Text("G")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 18)
                            Text(isWorking && !showingDotminiID ? "Opening Google…" : "Continue with Google")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                        }
                        .frame(height: 38)
                        .padding(.horizontal, 12)
                        .background(buttonBackground)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showingDotminiID.toggle()
                            statusMessage = ""
                        }
                    } label: {
                        HStack {
                            Text("Dotmini ID")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(showingDotminiID ? "Hide" : "Sign in")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 38)
                        .padding(.horizontal, 12)
                        .background(buttonBackground)
                    }
                    .buttonStyle(.plain)
                }

                if showingDotminiID {
                    VStack(spacing: 9) {
                        TextField("Email", text: $email)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 11)
                            .frame(height: 36)
                            .background(fieldBackground)

                        SecureField("Password", text: $password)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 11)
                            .frame(height: 36)
                            .background(fieldBackground)

                        Button(isWorking ? "Signing in…" : "Sign in with Dotmini ID") {
                            Task { await signInWithDotminiID() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .disabled(email.isEmpty || password.isEmpty || isWorking)
                    }
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.top, 10)
                }

                HStack {
                    Text("You can sign in later from Settings.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Continue without signing in") { onComplete() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.top, 20)
            }
            .padding(28)
            .frame(width: 500)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: appState.appTheme.elevatedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 28, y: 12)
            )
            .padding(30)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeAccountLoggedIn"))) { _ in
            onComplete()
        }
    }

    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color(nsColor: appState.appTheme.panelBackground))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.12)))
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color(nsColor: appState.appTheme.workspaceBackground))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.12)))
    }

    private func welcomeRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.9))
        }
    }

    private func startGoogleSignIn() {
        isWorking = true
        statusMessage = "Opening secure Dotmini sign-in…"
        Task { @MainActor in
            do {
                try await SupabaseAuthService.shared.startOAuth(provider: "google")
            } catch {
                isWorking = false
                statusMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func signInWithDotminiID() async {
        isWorking = true
        statusMessage = ""
        defer { isWorking = false }
        do {
            let session = try await SupabaseAuthService.shared.signIn(email: email, password: password)
            AuthService.shared.syncWithWebSession(
                email: session.email,
                token: session.accessToken,
                displayName: session.email.components(separatedBy: "@").first ?? "User"
            )
            onComplete()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
