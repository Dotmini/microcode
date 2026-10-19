import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Account settings backed exclusively by the self-hosted Supabase instance.
/// Plans are server-side entitlements; there is intentionally no editable or
/// client-generated "license key" field in this view.
struct MicroCodeLicenseSettingsView: View {
    @ObservedObject private var auth = SupabaseAuthService.shared
    @ObservedObject private var platformKey = DotminiPlatformKeyService.shared
    @ObservedObject private var enterprise = EnterpriseAIAuthService.shared
    @ObservedObject private var telemetry = TelemetryService.shared
    @AppStorage("dotminiUserEmail") private var persistedEmail = ""

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var status = ""
    @State private var platformKeyInput = ""
    @State private var showServiceAccountEditor = false
    @State private var selectedTelemetryTab = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if auth.session != nil {
                    accountCard
                } else {
                    signInCard
                }
                entitlementCard
                if auth.isAdminProvider {
                    installRegistryCard
                }
                platformKeyCard
                enterpriseCard
                architectureNote
            }
            .padding(20)
        }
        .task {
            if auth.isAdminProvider {
                telemetry.loadCachedAdminDataIfAuthorized()
                await telemetry.fetchAllInstallsAndHistory()
            }
            _ = await auth.refreshAccessTokenIfNeeded()
            await auth.refreshEntitlement()
            if auth.isAdminProvider {
                await telemetry.fetchAllInstallsAndHistory()
            } else {
                telemetry.clearAdminCache()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeAccountLoggedIn"))) { _ in
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
                        if auth.isAdminProvider {
                            await telemetry.fetchAllInstallsAndHistory()
                        } else {
                            telemetry.clearAdminCache()
                        }
                        isWorking = false
                    }
                }
                .disabled(isWorking)
                Button("Sign Out", role: .destructive) {
                    auth.signOut()
                    AuthService.shared.signOut()
                    telemetry.clearAdminCache()
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
                        isWorking = false
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
                if auth.entitlement.role.lowercased() == "admin" {
                    Text("ADMIN")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                }
                Text(auth.entitlement.isLoaded
                     ? (auth.entitlement.plan.isEmpty ? "UNKNOWN" : auth.entitlement.plan.uppercased())
                     : "UNAVAILABLE")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }
            Divider()
            if auth.entitlement.isLoaded {
                HStack {
                    metric("AI tokens remaining", "\(auth.entitlement.tokensRemaining)")
                    Spacer()
                    metric("AI tokens used", "\(auth.entitlement.tokensUsed)")
                }
            } else {
                Text(auth.session == nil ? "Sign in to load your entitlement." : "Could not load your cloud entitlement. Try Refresh.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                Button("Manage plan") {
                    NSWorkspace.shared.open(URL(string: "https://microcode.dotmini.net/account")!)
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
        .cardStyle()
    }

    private var installRegistryCard: some View {
        let current = telemetry.buildCurrentInstallRecord()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Label("Installations & Download History", systemImage: "desktopcomputer.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                        Text("ADMIN PROVIDER ONLY")
                            .font(.system(size: 8.5, weight: .heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.red.opacity(0.18)))
                            .foregroundStyle(.red)
                        Text("\(telemetry.downloadLeads.count) PORTAL DL")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundStyle(.orange)
                        Text("\(telemetry.totalGitHubDownloads) GITHUB DL")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple.opacity(0.18)))
                            .foregroundStyle(.purple)
                        Text("\(telemetry.cloudUsersHistory.count) USERS")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.18)))
                            .foregroundStyle(.blue)
                        Text("\(telemetry.installedDevices.count) MAC\(telemetry.installedDevices.count == 1 ? "" : "S")")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.18)))
                            .foregroundStyle(.green)
                    }
                    Text("Visible strictly to Admin Provider accounts. Live records from microcode.dotmini.net (`microcode_downloads` & `users`), GitHub Releases (`Dotmini/microcode`), and active Mac telemetry (`microcode_installs/*`).")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    Task { await telemetry.fetchAllInstallsAndHistory() }
                } label: {
                    Label(telemetry.isFetchingInstalls ? "Syncing…" : "Sync & Refresh", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(telemetry.isFetchingInstalls)
            }

            HStack(spacing: 14) {
                metric("Portal Leads", "\(telemetry.downloadLeads.count)")
                Divider().frame(height: 28)
                metric("GitHub DMG/PKG", "\(telemetry.totalGitHubDownloads)")
                Divider().frame(height: 28)
                metric("Portal Users", "\(telemetry.cloudUsersHistory.count)")
                Divider().frame(height: 28)
                metric("This Mac Launches", "\(current.launchCount)")
                Divider().frame(height: 28)
                metric("Hardware", "\(current.device.cpu) · \(current.device.memoryGB)GB")
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.07)))

            Picker("View", selection: $selectedTelemetryTab) {
                Text("Portal Downloads (\(telemetry.downloadLeads.count))").tag(0)
                Text("Registered Users (\(telemetry.cloudUsersHistory.count))").tag(1)
                Text("Active Macs (\(telemetry.installedDevices.count))").tag(2)
            }
            .pickerStyle(.segmented)

            if selectedTelemetryTab == 0 {
                if telemetry.downloadLeads.isEmpty {
                    Text(telemetry.isFetchingInstalls ? "Syncing microcode_downloads from microcode.dotmini.net…" : "Sign in with your admin account and click Sync & Refresh to load download leads.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(telemetry.downloadLeads) { lead in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Image(systemName: lead.eventType == "macapp_active" ? "laptopcomputer.and.iphone" : "arrow.down.circle.fill")
                                        .foregroundStyle(lead.eventType == "macapp_active" ? .green : .orange)
                                    Text("#\(lead.id) \(lead.name.isEmpty ? "Anonymous" : lead.name)")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("(\(lead.email))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(lead.version) · \(lead.platform)/\(lead.arch)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.orange.opacity(0.16)))
                                }
                                HStack(spacing: 12) {
                                    Label("IP: \(lead.ipAddress)", systemImage: "network")
                                    Label(lead.sourceLabel, systemImage: "tag.fill")
                                    Spacer()
                                    Text(String(lead.downloadedAt.prefix(19)).replacingOccurrences(of: "T", with: " "))
                                }
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(.secondary)
                                Text(lead.machineInfo.isEmpty ? lead.userAgent : "\(lead.machineInfo) — \(lead.userAgent)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
                        }

                        if !telemetry.githubReleaseDownloads.isEmpty {
                            Divider().padding(.vertical, 2)
                            Text("GitHub Release Installer Downloads (Dotmini/microcode)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(telemetry.githubReleaseDownloads) { asset in
                                        HStack(spacing: 4) {
                                            Text("\(asset.assetName):")
                                                .font(.system(size: 10, design: .monospaced))
                                            Text("\(asset.downloadCount)")
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .foregroundStyle(.purple)
                                        }
                                        .fixedSize(horizontal: true, vertical: false)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Capsule().fill(Color.purple.opacity(0.12)))
                                    }
                                }
                            }
                        }
                    }
                }
            } else if selectedTelemetryTab == 1 {
                if telemetry.cloudUsersHistory.isEmpty {
                    Text(telemetry.isFetchingInstalls ? "Loading registered users from microcode.dotmini.net…" : "Sign in and click Sync & Refresh to view registered MicroCode users.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(telemetry.cloudUsersHistory) { user in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Image(systemName: user.role == "admin" ? "crown.fill" : "person.crop.circle.fill")
                                        .foregroundStyle(user.role == "admin" ? .orange : .accentColor)
                                    Text(user.fullName)
                                        .font(.system(size: 12, weight: .semibold))
                                    if !user.email.isEmpty {
                                        Text("(\(user.email))")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(user.role.uppercased())
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(user.role == "admin" ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.14)))
                                    Text(user.plan.uppercased())
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                                }
                                HStack(spacing: 12) {
                                    Label("\(user.downloadCount) Portal Download(s)", systemImage: "arrow.down.circle")
                                    Label("Version: \(user.lastVersion)", systemImage: "shippingbox")
                                    Label("Last IP: \(user.lastIP)", systemImage: "network")
                                    Spacer()
                                    if !user.lastActiveAt.isEmpty {
                                        Text("Last seen: \(String(user.lastActiveAt.prefix(19)).replacingOccurrences(of: "T", with: " "))")
                                    }
                                }
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                Text(user.latestActivity)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.primary.opacity(0.85))
                                    .lineLimit(1)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
                        }
                    }
                }
            } else {
                if telemetry.installedDevices.isEmpty {
                    Text(telemetry.isFetchingInstalls ? "Syncing installation registry with Supabase…" : "No installation records synced yet. Click Sync & Refresh.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(telemetry.installedDevices) { dev in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "laptopcomputer")
                                        .foregroundStyle(.tint)
                                    Text("\(dev.displayName) — \(dev.hostname)")
                                        .font(.system(size: 12, weight: .semibold))
                                    if dev.installID == telemetry.currentInstallID {
                                        Text("THIS MAC")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                                    }
                                    Spacer()
                                    Text("Launches: \(dev.launchCount)")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                HStack(spacing: 10) {
                                    Text("\(dev.device.hardwareModel) • \(dev.device.cpu) • \(dev.device.memoryGB)GB RAM • \(dev.device.operatingSystem)")
                                    Spacer()
                                    Text("v\(dev.appVersion)")
                                }
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                HStack(spacing: 10) {
                                    Text("User: \(dev.email.isEmpty ? "Anonymous" : dev.email)")
                                    Spacer()
                                    Text("First install: \(String(dev.firstInstalledAt.prefix(19)).replacingOccurrences(of: "T", with: " "))")
                                    Text("Last seen: \(String(dev.lastSeenAt.prefix(19)).replacingOccurrences(of: "T", with: " "))")
                                }
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                if !dev.installedAgents.isEmpty {
                                    HStack(spacing: 6) {
                                        Text("CLI Agents:")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.secondary)
                                        ForEach(dev.installedAgents, id: \.self) { agent in
                                            Text(agent)
                                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Capsule().fill(Color.secondary.opacity(0.14)))
                                        }
                                    }
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
                        }
                    }
                }
            }

            if !telemetry.lastSyncStatus.isEmpty {
                Text(telemetry.lastSyncStatus)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
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

    private var enterpriseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Label("Enterprise AI & Governance", systemImage: "building.2.crop.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        if enterprise.isEnterpriseActive {
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.2)))
                                .foregroundStyle(.green)
                        }
                        if enterprise.isMDMManaged {
                            Text("MDM MANAGED")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.2)))
                                .foregroundStyle(.blue)
                        }
                    }
                    Text("Connect directly to Google Gemini Enterprise (Vertex AI BYOC), Dotmini Cloud Enterprise (Sovereign ZDR Gateway), or a private corporate gateway.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Picker("Enterprise Mode", selection: $enterprise.mode) {
                ForEach(EnterpriseAIMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Text(enterprise.mode.subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if enterprise.mode == .dotminiEnterprise {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Organization ID (e.g. org-scb-thailand)", text: $enterprise.dotminiOrganizationId)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Dotmini Enterprise Key (sk-dotmini-ent-…)", text: $enterprise.dotminiEnterpriseKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("Enterprise Gateway URL", text: $enterprise.dotminiEnterpriseGatewayURL)
                        .textFieldStyle(.roundedBorder)
                }
            } else if enterprise.mode == .geminiVertex {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Google Cloud Project ID").font(.caption).foregroundColor(.secondary)
                            TextField("my-enterprise-gcp-project", text: $enterprise.vertexProjectId)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Vertex AI Region").font(.caption).foregroundColor(.secondary)
                            Picker("", selection: $enterprise.vertexLocation) {
                                Text("asia-southeast1 (Singapore)").tag("asia-southeast1")
                                Text("asia-northeast1 (Tokyo)").tag("asia-northeast1")
                                Text("us-central1 (Iowa)").tag("us-central1")
                                Text("europe-west4 (Netherlands)").tag("europe-west4")
                                Text("global (Global Endpoint)").tag("global")
                            }
                            .labelsHidden()
                        }
                    }

                    Picker("Vertex Authentication", selection: $enterprise.vertexAuthMode) {
                        ForEach(VertexAuthMode.allCases) { authMode in
                            Text(authMode.title).tag(authMode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if enterprise.vertexAuthMode == .serviceAccountJSON {
                        HStack(spacing: 8) {
                            Button {
                                importServiceAccountFile()
                            } label: {
                                Label(enterprise.vertexServiceAccountJSON.isEmpty ? "Import Service Account JSON…" : "Replace Service Account JSON…", systemImage: "doc.badge.key")
                            }
                            .buttonStyle(.bordered)

                            Button(showServiceAccountEditor ? "Hide JSON" : "Paste JSON") {
                                showServiceAccountEditor.toggle()
                            }
                            .buttonStyle(.bordered)

                            if !enterprise.vertexServiceAccountJSON.isEmpty {
                                Label("Service Account Loaded", systemImage: "checkmark.seal.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.green)
                            }
                        }

                        if showServiceAccountEditor {
                            TextEditor(text: $enterprise.vertexServiceAccountJSON)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(height: 90)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                        }
                    } else if enterprise.vertexAuthMode == .apiKey {
                        SecureField("Vertex AI Express / Enterprise API Key", text: $enterprise.vertexAPIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Text("Uses ~/.config/gcloud/application_default_credentials.json or `gcloud auth print-access-token` automatically.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            } else if enterprise.mode == .customGateway {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Custom Gateway Base URL (https://llm-gateway.corp.internal/v1)", text: $enterprise.customGatewayBaseURL)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Gateway Bearer API Key", text: $enterprise.customGatewayAPIKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("Organization / Cost Center ID (optional)", text: $enterprise.dotminiOrganizationId)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if enterprise.isEnterpriseActive {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Zero Data Retention (ZDR) — Never cache or log prompts on gateway", isOn: $enterprise.zeroDataRetention)
                        .font(.system(size: 12, weight: .medium))
                    Toggle("Local DLP Secret Redaction — Strip API keys, PEM keys & .env secrets before sending", isOn: $enterprise.localDLPRedaction)
                        .font(.system(size: 12, weight: .medium))
                }

                HStack {
                    Button(enterprise.isVerifying ? "Verifying…" : "Verify Enterprise Connection") {
                        Task { _ = await enterprise.verifyConnection() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(enterprise.isVerifying)

                    if !enterprise.statusMessage.isEmpty {
                        Text(enterprise.statusMessage)
                            .font(.system(size: 11))
                            .foregroundColor(enterprise.statusMessage.contains("✓") ? .green : .secondary)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func importServiceAccountFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select your Google Cloud Service Account JSON key file for Vertex AI Gemini Enterprise"
        if panel.runModal() == .OK, let url = panel.url,
           let content = try? String(contentsOf: url, encoding: .utf8) {
            enterprise.vertexServiceAccountJSON = content
            enterprise.statusMessage = "Loaded Service Account JSON (\(url.lastPathComponent))"
        }
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
            TelemetryService.shared.record(name: "account_signed_in", mode: "password")
            if auth.isAdminProvider {
                await TelemetryService.shared.fetchAllInstallsAndHistory()
            } else {
                TelemetryService.shared.clearAdminCache()
            }
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
