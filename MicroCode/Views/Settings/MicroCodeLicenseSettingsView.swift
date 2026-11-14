import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Account & Cloud Billing settings backed by the self-hosted Supabase instance.
/// Designed strictly to macOS Human Interface Guidelines — clean surfaces, clear hierarchy, zero visual clutter.
struct MicroCodeLicenseSettingsView: View {
    @ObservedObject private var auth = SupabaseAuthService.shared
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var platformKey = DotminiPlatformKeyService.shared
    @ObservedObject private var enterprise = EnterpriseAIAuthService.shared
    @ObservedObject private var telemetry = TelemetryService.shared
    @AppStorage("dotminiUserEmail") private var persistedEmail = ""

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var status = ""
    @State private var platformKeyInput = ""
    @State private var selectedTelemetryTab = 0
    @State private var isCheckingOut = false
    @State private var checkoutStatus = ""
    @State private var checkoutVerified = false
    @State private var customTopupTHB = ""
    @State private var isCreatingAccount = false
    @State private var displayName = ""
    @State private var showAdminTelemetry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            serviceHeaderSection

            if auth.session != nil {
                accountCard
            } else {
                signInCard
            }

            entitlementCard
            platformKeyCard

            if auth.isAdminProvider {
                adminDisclosureSection
            }
        }
        .task {
            MCPServer.shared.startLocalHttpBridge(port: 18888)
            if email.isEmpty && !persistedEmail.isEmpty {
                email = persistedEmail
            }
            if auth.isAdminProvider {
                telemetry.loadCachedAdminDataIfAuthorized()
                await telemetry.fetchAllInstallsAndHistory()
            }
            _ = await auth.refreshAccessTokenIfNeeded()
            await auth.refreshEntitlement()
            if platformKey.isConfigured {
                _ = await platformKey.validate()
            }
            if auth.isAdminProvider {
                await telemetry.fetchAllInstallsAndHistory()
            } else {
                telemetry.clearAdminCache()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeAccountLoggedIn"))) { _ in
            isWorking = false
            status = ""
            Task {
                _ = await auth.refreshAccessTokenIfNeeded(force: true)
                await auth.refreshEntitlement()
                if auth.isAdminProvider {
                    await telemetry.fetchAllInstallsAndHistory()
                } else {
                    telemetry.clearAdminCache()
                }
            }
        }
    }

    // MARK: - 1. Service Header (Matches PhoneCompanionSettingsView & AI Settings)

    private var serviceHeaderSection: some View {
        let isSignedIn = auth.session != nil
        let rawPlan = auth.entitlement.plan.trimmingCharacters(in: .whitespacesAndNewlines)
        let planLabel = isSignedIn
            ? (rawPlan.isEmpty ? "FREE PLAN" : "\(rawPlan.uppercased()) PLAN")
            : "NOT SIGNED IN"

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 38, height: 38)
                AIProviderBrandIcon(provider: "microcode", size: 20)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Dotmini ID & Cloud Billing")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(isSignedIn ? Color.green.opacity(0.85) : Color.secondary.opacity(0.45))
                            .frame(width: 5.5, height: 5.5)
                        Text(planLabel)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)

                    if auth.entitlement.role.lowercased() == "admin" {
                        Text("ADMIN")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(4)
                    }
                }

                Text("Sign in with Google or your Dotmini ID to sync Cloud AI credits, monthly subscriptions, and devices across MicroCode.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(auth.authenticatedPortalURL(path: "/dashboard"))
            } label: {
                Label("Web Portal", systemImage: "arrow.up.right.square")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .cardStyle()
    }

    // MARK: - 2a. Signed-In Account Card

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Text(String((accountEmail.isEmpty ? "U" : accountEmail).prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(accountEmail.isEmpty ? "Signed in with Dotmini ID" : accountEmail)
                        .font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.green)
                        Text("Authenticated session active in macOS Keychain")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    Task {
                        isWorking = true
                        _ = await auth.refreshAccessTokenIfNeeded(force: true)
                        await auth.refreshEntitlement()
                        if auth.isAdminProvider {
                            await telemetry.fetchAllInstallsAndHistory()
                        } else {
                            telemetry.clearAdminCache()
                        }
                        isWorking = false
                    }
                } label: {
                    Label(isWorking ? "Syncing…" : "Sync", systemImage: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isWorking)

                Button("Sign Out", role: .destructive) {
                    auth.signOut()
                    AuthService.shared.signOut()
                    telemetry.clearAdminCache()
                    persistedEmail = ""
                    status = "Signed out from this Mac."
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if !status.isEmpty {
                statusText
            }
        }
        .cardStyle()
    }

    // MARK: - 2b. Clean Sign-In Card (Google OAuth + Browser Sync + Compact Email Form)

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !auth.reauthReason.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(auth.reauthReason)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.28), lineWidth: 1))
            }

            // Primary OAuth Row
            HStack(spacing: 10) {
                Button {
                    isWorking = true
                    status = "Opening Google sign-in…"
                    Task { @MainActor in
                        do {
                            try await auth.startOAuth(provider: "google")
                            isWorking = false
                        } catch {
                            status = error.localizedDescription
                            isWorking = false
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        GoogleBrandMark(size: 15)
                        Text("Continue with Google")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isWorking)

                Button {
                    status = "Opened default web browser. Completing sign-in will sync back to MicroCode automatically."
                    auth.startBrowserSignIn(provider: "google")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("Sign in via Web Browser")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Use your default browser (Safari/Chrome) if you are already signed in to microcode.dotmini.net")
            }

            HStack(spacing: 10) {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                Text(isCreatingAccount ? "or create a Dotmini ID with email" : "or sign in with email")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            }

            if isCreatingAccount {
                TextField("Display Name (optional)", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
            }

            // Compact side-by-side Email + Password + Submit row
            HStack(spacing: 8) {
                TextField("Email address", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
                    .onSubmit {
                        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty, !isWorking else { return }
                        Task { isCreatingAccount ? await createAccount() : await signInWithPassword() }
                    }

                Button(isWorking ? (isCreatingAccount ? "Creating…" : "Signing in…") : (isCreatingAccount ? "Create Account" : "Sign In")) {
                    Task { isCreatingAccount ? await createAccount() : await signInWithPassword() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || isWorking)
            }

            HStack {
                Button(isCreatingAccount ? "Already have an account? Sign in" : "Create a new account") {
                    isCreatingAccount.toggle()
                    status = ""
                }
                .buttonStyle(.link)
                .font(.system(size: 11.5))

                Spacer()

                if !isCreatingAccount {
                    Button("Forgot password?") {
                        Task { await resetPassword() }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
                    .disabled(isWorking)
                }
            }

            if !status.isEmpty {
                statusText
            }
        }
        .cardStyle()
    }

    // MARK: - 3. Cloud AI Credit & Monthly Subscription Plans

    private var entitlementCard: some View {
        let activePlan = auth.entitlement.plan.lowercased()
        let limitTHB = auth.entitlement.creditLimitTHB
        let remTHB = auth.entitlement.creditRemainingTHB
        let ratioRemaining: Double = limitTHB > 0 ? min(1.0, max(0.0, remTHB / limitTHB)) : 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cloud AI Credit & Monthly Plans")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Token-metered billing across Claude, GPT, Gemini, DeepSeek, and Omni AI. Top-up wallet credits never expire.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    Task {
                        isCheckingOut = true
                        let res = await auth.verifyLatestPayment()
                        checkoutVerified = res.verified
                        checkoutStatus = res.message
                        isCheckingOut = false
                    }
                } label: {
                    Label(isCheckingOut ? "Verifying…" : "Verify Payment", systemImage: "checkmark.seal")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isCheckingOut || auth.session == nil)
            }

            // Credit Balance Strip
            if auth.entitlement.isLoaded {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 0) {
                        metric("Available Credit", auth.entitlement.formattedAvailableCredit)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider().frame(height: 28).padding(.horizontal, 12)
                        metric("Monthly Plan Pool", auth.entitlement.formattedPlanCreditSummary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider().frame(height: 28).padding(.horizontal, 12)
                        metric("Top-Up Wallet", String(format: "฿%.2f", auth.entitlement.aiTopupBalanceTHB))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider().frame(height: 28).padding(.horizontal, 12)
                        metric("Metered Tokens", NumberFormatter.localizedString(from: NSNumber(value: auth.entitlement.totalTokensUsed), number: .decimal))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if limitTHB > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.08))
                                    Capsule()
                                        .fill(ratioRemaining > 0.2 ? Color.accentColor : Color.orange)
                                        .frame(width: max(4, geo.size.width * ratioRemaining))
                                }
                            }
                            .frame(height: 5)

                            Text(String(format: "฿%.2f used of ฿%.0f monthly plan pool · Automatically draws from Top-Up Wallet when monthly pool reaches ฿0.00.", auth.entitlement.creditUsedTHB, limitTHB))
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.03)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
            }

            // Monthly Plans 4-Column Grid
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Monthly Subscriptions")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("PromptPay QR / Credit Card via Beam Checkout")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 10) {
                    subscriptionTierTile(
                        title: "Lite",
                        price: "฿179",
                        period: "/mo",
                        quota: "฿179 AI Credit Pool",
                        planKey: "microai_lite",
                        isCurrent: activePlan == "lite" || activePlan == "microai_lite"
                    )
                    subscriptionTierTile(
                        title: "Pro",
                        price: "฿529",
                        period: "/mo",
                        quota: "฿529 AI Credit Pool",
                        planKey: "microai_pro",
                        isCurrent: activePlan == "pro" || activePlan == "microai_pro"
                    )
                    subscriptionTierTile(
                        title: "Advanced",
                        price: "฿990",
                        period: "/mo",
                        quota: "฿990 AI Credit Pool",
                        planKey: "microai_advanced",
                        isCurrent: activePlan == "advanced" || activePlan == "microai_advanced"
                    )
                    subscriptionTierTile(
                        title: "Bundle Pro",
                        price: "฿1,365",
                        period: "/mo",
                        quota: "฿1,365 Credit + IDE",
                        planKey: "bundle_pro",
                        isCurrent: activePlan == "bundle_pro" || activePlan == "bundle"
                    )
                }
            }

            // Compact Single-Row Top-Up Bar
            HStack(spacing: 8) {
                Text("Top-Up Wallet:")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)

                aiCreditTopupButton(label: "+฿100", planKey: "ai_topup_100")
                aiCreditTopupButton(label: "+฿300", planKey: "ai_topup_300")
                aiCreditTopupButton(label: "+฿500", planKey: "ai_topup_500")
                aiCreditTopupButton(label: "+฿1,000", planKey: "ai_topup_1000")

                Spacer()

                TextField("Custom ฿ (≥20)", text: $customTopupTHB)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 108)

                Button("Top Up") {
                    let amt = Double(customTopupTHB.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                    guard amt >= 20 else {
                        checkoutVerified = false
                        checkoutStatus = "กรุณาระบุยอดเติมเครดิต Cloud AI ขั้นต่ำ ฿20"
                        return
                    }
                    Task { await startAITopup(planKey: "ai_topup_custom", customAmountTHB: amt, title: "฿\(Int(amt))") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isCheckingOut || auth.session == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))

            if !checkoutStatus.isEmpty {
                Text(checkoutStatus)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(checkoutVerified ? .green : .secondary)
            }

            if !auth.paymentWatchMessage.isEmpty {
                HStack(spacing: 8) {
                    if auth.isWatchingPayment { ProgressView().controlSize(.small) }
                    Text(auth.paymentWatchMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(auth.paymentWatchVerified ? .green : .secondary)
                    if auth.paymentWatchVerified && (UserDefaults.standard.string(forKey: "aiKeyMode") ?? "") != "cloud" {
                        Button("Use Dotmini Cloud AI now") { activateDotminiCloudMode() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func aiCreditTopupButton(label: String, planKey: String) -> some View {
        Button(label) {
            Task { await startAITopup(planKey: planKey, customAmountTHB: nil, title: label) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isCheckingOut || auth.session == nil)
    }

    /// Switches chat to Dotmini Cloud with a model the gateway really serves (first live cloud model).
    private func activateDotminiCloudMode() {
        let model = AIModelCatalog.shared.dotminiCloudModels.first
        UserDefaults.standard.set("cloud", forKey: "aiKeyMode")
        if let model {
            appState.aiProvider = model.provider
            appState.aiModel = model.id
        }
        appState.saveSettings()
        checkoutVerified = true
        checkoutStatus = "สลับไปใช้ Dotmini Cloud AI แล้ว\(model.map { " (โมเดล \($0.name))" } ?? "")"
    }

    private func startAITopup(planKey: String, customAmountTHB: Double?, title: String) async {
        isCheckingOut = true
        checkoutVerified = false
        checkoutStatus = "กำลังสร้างลิงก์เติมเครดิต Cloud AI (\(title)) ผ่าน Beam Checkout…"
        do {
            let session = try await auth.createAICreditTopupCheckout(planKey: planKey, customAmountTHB: customAmountTHB)
            checkoutStatus = "เปิดหน้าชำระเงินเติมเครดิต Cloud AI (฿\(Int(session.amountTHB))) แล้ว กรุณาสแกน QR PromptPay หรือชำระผ่านบัตร แล้วกด Verify Payment"
            NSWorkspace.shared.open(session.checkoutURL)
            auth.beginPaymentWatch()
        } catch {
            checkoutStatus = error.localizedDescription
        }
        isCheckingOut = false
    }

    private func subscriptionTierTile(
        title: String,
        price: String,
        period: String,
        quota: String,
        planKey: String,
        isCurrent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if isCurrent {
                    Text("ACTIVE")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.18)))
                        .foregroundStyle(.green)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(price)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(period)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }

            Text(quota)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 2)

            Button {
                Task {
                    isCheckingOut = true
                    checkoutVerified = false
                    checkoutStatus = "กำลังสร้างลิงก์ชำระเงินจริงผ่าน Beam Checkout (\(title))…"
                    do {
                        let session = try await auth.createSubscriptionCheckout(plan: planKey)
                        checkoutStatus = "เปิดหน้าชำระเงิน Beam Checkout (฿\(Int(session.amountTHB))) แล้ว กรุณาสแกน QR PromptPay หรือชำระผ่านบัตร แล้วกด Verify Payment"
                        NSWorkspace.shared.open(session.checkoutURL)
                        auth.beginPaymentWatch()
                    } catch {
                        checkoutStatus = error.localizedDescription
                    }
                    isCheckingOut = false
                }
            } label: {
                Text(isCurrent ? "Current Plan" : "Subscribe")
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isCurrent || isCheckingOut || auth.session == nil)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.03)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isCurrent ? Color.green.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - 4. Developer Platform API Key Card

    private var platformKeyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dotmini Platform (Unified Omni AI + MicroCode)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("SHA-256 hashed developer credential shared across Omni AI, MicroCode Cloud Runtime, and API Gateway. Stored only in macOS Keychain.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    if auth.session != nil {
                        Button(platformKey.isProvisioning ? "Connecting…" : (platformKey.isConfigured ? "Rotate Key" : "1-Click Auto-Connect")) {
                            Task {
                                let ok = await platformKey.autoConnectFromSignedInAccount()
                                if ok {
                                    await AIModelCatalog.shared.refreshIfNeeded(force: true)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(platformKey.isProvisioning || platformKey.isValidating)
                    }
                    Button("Open Platform") {
                        NSWorkspace.shared.open(URL(string: DotminiPlatformKeyService.platformOrigin)!)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if platformKey.isConfigured {
                HStack(spacing: 8) {
                    Label(platformKey.maskedKey, systemImage: "checkmark.shield.fill")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.green)

                    if let thb = platformKey.availableTHB {
                        Text(String(format: "Shared Pool: ฿%.2f", thb))
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.14)))
                            .foregroundStyle(.blue)
                    }

                    if !platformKey.omniAIPlan.isEmpty || !platformKey.microCodePlan.isEmpty {
                        Text("Omni: \(platformKey.omniAIPlan.isEmpty ? "FREE" : platformKey.omniAIPlan) · MC: \(platformKey.microCodePlan.isEmpty ? "FREE" : platformKey.microCodePlan)")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                    Button(platformKey.isValidating ? "Checking…" : "Verify") {
                        Task { _ = await platformKey.validate() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(platformKey.isValidating || platformKey.isProvisioning)
                    Button("Remove", role: .destructive) { platformKey.remove() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(platformKey.isProvisioning)
                }
            } else {
                HStack(spacing: 8) {
                    SecureField("sk-dotmini-live-… or mci-live-…", text: $platformKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.regular)
                    Button("Save Key") {
                        if platformKey.save(platformKeyInput) {
                            platformKeyInput = ""
                            Task { _ = await platformKey.validate() }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(platformKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if !platformKey.validationMessage.isEmpty {
                Text(platformKey.validationMessage)
                    .font(.system(size: 11))
                    .foregroundColor(
                        platformKey.validationMessage.lowercased().contains("rejected") ||
                        platformKey.validationMessage.lowercased().contains("failed") ||
                        platformKey.validationMessage.lowercased().contains("invalid") ||
                        platformKey.validationMessage.lowercased().contains("could not") ? .red : .secondary
                    )
            }
        }
        .cardStyle()
    }

    // MARK: - 5. Admin Telemetry Disclosure Section (Admin-Only, Collapsed by Default)

    private var adminDisclosureSection: some View {
        DisclosureGroup(isExpanded: $showAdminTelemetry) {
            installRegistryContent
                .padding(.top, 10)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "desktopcomputer.and.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Admin Telemetry & Installation Registry")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("\(telemetry.downloadLeads.count) Leads · \(telemetry.cloudUsersHistory.count) Users · \(telemetry.installedDevices.count) Macs")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .cardStyle()
    }

    private var installRegistryContent: some View {
        let current = telemetry.buildCurrentInstallRecord()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 14) {
                    metric("Portal Leads", "\(telemetry.downloadLeads.count)")
                    Divider().frame(height: 24)
                    metric("GitHub DMG/PKG", "\(telemetry.totalGitHubDownloads)")
                    Divider().frame(height: 24)
                    metric("Portal Users", "\(telemetry.cloudUsersHistory.count)")
                    Divider().frame(height: 24)
                    metric("This Mac Launches", "\(current.launchCount)")
                }
                Spacer()
                Button {
                    Task { await telemetry.fetchAllInstallsAndHistory() }
                } label: {
                    Label(telemetry.isFetchingInstalls ? "Syncing…" : "Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(telemetry.isFetchingInstalls)
            }

            Picker("View", selection: $selectedTelemetryTab) {
                Text("Portal Downloads (\(telemetry.downloadLeads.count))").tag(0)
                Text("Registered Users (\(telemetry.cloudUsersHistory.count))").tag(1)
                Text("Active Macs (\(telemetry.installedDevices.count))").tag(2)
            }
            .pickerStyle(.segmented)

            if selectedTelemetryTab == 0 {
                ForEach(telemetry.downloadLeads.prefix(25)) { lead in
                    HStack {
                        Text("#\(lead.id) \(lead.name.isEmpty ? "Anonymous" : lead.name)")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("(\(lead.email))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(lead.version) · \(lead.platform)/\(lead.arch)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                }
            } else if selectedTelemetryTab == 1 {
                ForEach(telemetry.cloudUsersHistory.prefix(25)) { user in
                    HStack {
                        Text(user.fullName)
                            .font(.system(size: 11.5, weight: .semibold))
                        if !user.email.isEmpty {
                            Text("(\(user.email))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(user.plan.uppercased())
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                }
            } else {
                ForEach(telemetry.installedDevices.prefix(25)) { dev in
                    HStack {
                        Text("\(dev.displayName) — \(dev.hostname)")
                            .font(.system(size: 11.5, weight: .semibold))
                        Spacer()
                        Text("v\(dev.appVersion) · \(dev.launchCount) launches")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                }
            }
        }
    }

    // MARK: - Helpers & Actions

    private var statusText: some View {
        Text(status)
            .font(.system(size: 11))
            .foregroundColor(
                status.lowercased().contains("failed") ||
                status.lowercased().contains("not configured") ||
                status.lowercased().contains("ไม่สำเร็จ") ? .red : .secondary
            )
    }

    private var accountEmail: String { auth.currentEmail }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
        }
    }

    private func createAccount() async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanEmail.contains("@"), cleanEmail.contains(".") else { status = "กรุณากรอกอีเมลให้ถูกต้อง"; return }
        guard password.count >= 8 else { status = "รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร"; return }
        isWorking = true
        defer { isWorking = false }
        do {
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let session = try await auth.signUp(
                email: cleanEmail,
                password: password,
                displayName: name.isEmpty ? (cleanEmail.components(separatedBy: "@").first ?? "MicroCode User") : name
            )
            if session != nil {
                persistedEmail = cleanEmail
                password = ""
                status = "สร้างบัญชีสำเร็จ เข้าสู่ระบบแล้ว"
            } else {
                status = "ส่งอีเมลยืนยันไปที่ \(cleanEmail) แล้ว กรุณากดลิงก์ในอีเมล จากนั้นกลับมากด Sign In"
                isCreatingAccount = false
            }
        } catch {
            status = error.localizedDescription
        }
    }

    private func resetPassword() async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanEmail.contains("@") else { status = "กรอกอีเมลก่อน แล้วกด Forgot password?"; return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.sendPasswordReset(email: cleanEmail)
            status = "หากอีเมลนี้มีบัญชี ระบบได้ส่งลิงก์รีเซ็ตรหัสผ่านไปแล้ว"
        } catch {
            status = error.localizedDescription
        }
    }

    private func signInWithPassword() async {
        isWorking = true
        status = ""
        defer { isWorking = false }
        do {
            let session = try await auth.signIn(email: email, password: password)
            persistedEmail = session.email
            AuthService.shared.syncWithWebSession(
                email: session.email,
                token: session.accessToken,
                displayName: session.email.components(separatedBy: "@").first ?? "User"
            )
            TelemetryService.shared.record(name: "account_signed_in", mode: "password")
            if auth.isAdminProvider {
                await TelemetryService.shared.fetchAllInstallsAndHistory()
            } else {
                TelemetryService.shared.clearAdminCache()
            }
            status = "Signed in securely."
        } catch {
            status = error.localizedDescription
        }
    }
}

/// Crisp vector Google "G" mark for the native macOS sign-in button.
private struct GoogleBrandMark: View {
    var size: CGFloat = 15

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: size + 4, height: size + 4)
            Text("G")
                .font(.system(size: size * 0.78, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    AngularGradient(
                        colors: [
                            Color(red: 0.26, green: 0.52, blue: 0.96),
                            Color(red: 0.20, green: 0.66, blue: 0.33),
                            Color(red: 0.98, green: 0.74, blue: 0.02),
                            Color(red: 0.92, green: 0.26, blue: 0.21),
                            Color(red: 0.26, green: 0.52, blue: 0.96)
                        ],
                        center: .center
                    )
                )
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(14)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}
